extends RefCounted
## 联机 · 内置 EasyTier 内核的**进程管理**（起 / 停 / 就绪判定 / 降级）。
##
## 配套设计：作者本地文档《联机方案-内置EasyTier-工程设计-2026-10-12》（未入库）。
##
## ★★ 为什么用**命令行参数**而不是 TOML 配置文件（2026-10-12 定）：
##    `-i / -l / -r / -m / -p / --network-name / --network-secret / --no-tun /
##     --port-forward / --file-log-dir` **全部在本机实机跑通过**；
##    而 TOML 里 `no_tun`、`port_forwards` 这些**字段名是从文档推断的、没验过**
##     —— 猜错的表现是「内核静默起不来」，排查成本极高。
##     ⇒ 先用确定能跑的形态；将来真要配置文件，必须对着内核实测字段名再换。
##
## ★ 权限策略（非对称）：
##    · 房主 = `no_tun = false`（**要建虚拟网卡**）⇒ 需要管理员权限一次；
##    · 加入者 = `--no-tun` + `--port-forward` ⇒ **不需要任何权限、不装驱动**。
##    依据：实测「无 TUN 模式无法 bind 虚拟 IP ⇒ 只有『被连接』的一方需要虚拟网卡」。
##
## ⛔ 铁律：只杀**自己启动的那个 PID**（`OS.kill(pid)`），绝不做按进程名批量杀。

const RC := preload("res://scripts/net/eve_room_code.gd")

enum Role { HOST, CLIENT }
enum State { IDLE, STARTING, UP, FAILED, STOPPED }

## 内核版本（与 `tools/pipeline/_fetch_easytier.py` 和许可声明必须同号）
const VERSION := "2.6.4"
const CORE := "easytier-core.exe"
## ★ `Packet.dll`（WinDivert 的用户态库）是**加载期硬依赖**：缺了它内核
##   **约 100 ms 就静默退出**，而报错只打在它自己的 stdout 上（`create_process`
##   读不到）⇒ 现象是「内核起不来、原因未知」。这个坑实测踩过一次，补依赖时别忘了它。
const PACKET_DLL := "Packet.dll"
## 只有房主（TUN 模式，要建虚拟网卡）才需要。
const WINTUN := "wintun.dll"
## 就绪判定超时（毫秒）：起不来的话 UI 得给玩家一个说法，别无限转圈
const READY_TIMEOUT_MS := 20000

var state := State.IDLE
var last_error := ""
var pid := -1
var role := Role.HOST
var code := ""
var seat := 0

var _probe: StreamPeerTCP = null
var _started_ms := 0


# ══════════════════════════════════════════════════════════════ 参数生成

## 生成内核命令行参数（**纯函数**，可无头验收）。
##
## `relays` = 会合节点 uri 列表（全员必须同一份，见 `eve_relay_list.gd`）。
static func build_args(code_text: String, seat_no: int, is_host: bool,
		relays: Array, display_name: String) -> Array[String]:
	var a: Array[String] = []
	var vip := RC.virtual_ip(code_text, seat_no)
	var lp := RC.listen_port(code_text, seat_no)
	var rp := RC.rpc_port(code_text, seat_no)
	a.append("-i")
	a.append(vip)
	# 监听端口由房间码 + 座位派生 ⇒ 同机跑「房主 + 加入者」也不会撞端口
	a.append("-l")
	a.append("tcp://0.0.0.0:%d" % lp)
	a.append("-l")
	a.append("udp://0.0.0.0:%d" % lp)
	# 管理 RPC 只监听本机：我们靠「能不能连上它」判断内核就绪
	a.append("-r")
	a.append("127.0.0.1:%d" % rp)
	# 实例名必须同机唯一（否则内核会认为是同一个实例）
	a.append("-m")
	a.append("eve-%s" % ("host" if is_host else "guest%d" % seat_no))
	a.append("--network-name")
	a.append(RC.network_name(code_text))
	a.append("--network-secret")
	a.append(RC.network_secret(code_text))
	for uri in relays:
		a.append("-p")
		a.append(String(uri))
	if not is_host:
		a.append("--no-tun")
		# ★ 加入者的关键一步：把本地 27015 映射到房主的虚拟 IP
		#   ⇒ 游戏侧**所有人**都只连 127.0.0.1:27015，一行代码不用分叉
		a.append("--port-forward")
		a.append("udp://127.0.0.1:%d/%s:%d" % [
				RC.DEFAULT_PORT, RC.host_virtual_ip(code_text), RC.DEFAULT_PORT])
	a.append("--console-log-level")
	a.append("warn")
	a.append("--file-log-level")
	a.append("info")
	a.append("--file-log-dir")
	a.append(log_dir())
	return a


## 内核日志目录（给玩家报障用）。
static func log_dir() -> String:
	return ProjectSettings.globalize_path("user://logs/easytier")


# ══════════════════════════════════════════════════════════════ 二进制定位

## 内核可执行文件路径。找不到返回 ""。
##
## 查找顺序（先找到先用）：
##   ① `user://easytier/<版本>/` —— 从导出包里解出来的（正式包走这条）
##   ② 与游戏 exe 同级的 `easytier/` —— 安装器直接摆好的形态
##   ③ `res://addons/easytier/bin/` —— 编辑器 / 开发期（内核不入库，靠 fetch 脚本放）
static func core_path() -> String:
	for dir in [user_dir(), exe_dir(), res_dir()]:
		if dir == "":
			continue
		# ⚠️ 显式标注：循环变量是 Variant，`:=` 推不出类型（实测踩过 Parse Error）
		var p: String = dir.path_join(CORE)
		if FileAccess.file_exists(p):
			return p
	return ""


## 缺哪些文件（缺了就别启动 —— 否则现象是「静默退出、原因未知」）。
static func missing_files(is_host: bool) -> Array[String]:
	var out: Array[String] = []
	var exe := core_path()
	if exe == "":
		out.append(CORE)
		return out
	var dir := exe.get_base_dir()
	var need: Array[String] = [CORE, PACKET_DLL]
	if is_host:
		need.append(WINTUN)          # 房主要建虚拟网卡
	for n in need:
		if not FileAccess.file_exists(dir.path_join(n)):
			out.append(n)
	return out


## 房主侧还需要 `wintun.dll`（TUN 模式要它）；加入者不需要。
static func has_wintun() -> bool:
	var exe := core_path()
	if exe == "":
		return false
	return FileAccess.file_exists(exe.get_base_dir().path_join(WINTUN))


static func available() -> bool:
	return core_path() != ""


static func user_dir() -> String:
	return ProjectSettings.globalize_path("user://easytier/%s" % VERSION)


static func exe_dir() -> String:
	return OS.get_executable_path().get_base_dir().path_join("easytier")


static func res_dir() -> String:
	return ProjectSettings.globalize_path("res://addons/easytier/bin")


# ══════════════════════════════════════════════════════════════ 生命周期

## 启动内核。成功（进程起来了）返回 true —— ⚠️ 此时**还没就绪**，要接着 `poll()`。
func start(code_text: String, seat_no: int, is_host: bool,
		relays: Array, display_name: String, now_ms: int) -> bool:
	if state == State.STARTING or state == State.UP:
		return true
	code = code_text
	seat = seat_no
	role = Role.HOST if is_host else Role.CLIENT
	var exe := core_path()
	if exe == "":
		state = State.FAILED
		last_error = "没找到内置的联机内核（请重新安装完整包）"
		return false
	# ★ 先把「缺文件」判掉：否则现象是内核静默退出、原因未知（见 PACKET_DLL 的注释）
	var miss := missing_files(is_host)
	if not miss.is_empty():
		state = State.FAILED
		last_error = "缺少内核文件：%s（请重新安装完整包）" % ", ".join(miss)
		return false
	DirAccess.make_dir_recursive_absolute(log_dir())
	var args := build_args(code_text, seat_no, is_host, relays, display_name)
	# ⛔⛔ **不要**自己给参数加引号！`OS.create_process` 已经会替含空格的参数加引号，
	#   再加一层变成 `""C:/…EVE 自走棋…""` ⇒ 内核认不出这个参数 ⇒ **约 190 ms 静默退出**。
	#   （实测踩过：一度以为是内部日志目录带空格的问题。）
	pid = OS.create_process(exe, args, false)
	if pid <= 0:
		state = State.FAILED
		last_error = "内核启动失败（可能被安全软件拦截）"
		pid = -1
		return false
	state = State.STARTING
	last_error = ""
	_started_ms = now_ms
	_probe = null
	return true


## 轮询就绪状态。由 UI/驱动层每帧调（本类不读时钟，`now_ms` 外部传入）。
## 返回当前 `State`；`FAILED` 时看 `last_error` 拿人话原因。
func poll(now_ms: int) -> State:
	if state != State.STARTING:
		return state
	if not OS.is_process_running(pid):
		state = State.FAILED
		last_error = _exit_reason()
		return state
	if now_ms - _started_ms >= READY_TIMEOUT_MS:
		state = State.FAILED
		last_error = "联机内核启动超时"
		stop()
		return state
	# 就绪判据：管理 RPC 端口能连上（不需要额外二进制，也不依赖日志格式）
	if _probe == null:
		_probe = StreamPeerTCP.new()
		_probe.connect_to_host("127.0.0.1", RC.rpc_port(code, seat))
	_probe.poll()
	var st := _probe.get_status()
	if st == StreamPeerTCP.STATUS_CONNECTED:
		state = State.UP
		_probe.disconnect_from_host()
		_probe = null
	elif st == StreamPeerTCP.STATUS_ERROR:
		_probe = null
	return state


## 停内核。⛔ 只杀自己那个 PID。
func stop() -> void:
	if pid > 0:
		if OS.is_process_running(pid):
			OS.kill(pid)
		pid = -1
	if _probe != null:
		_probe.disconnect_from_host()
		_probe = null
	if state == State.STARTING or state == State.UP:
		state = State.STOPPED


func is_up() -> bool:
	return state == State.UP


## 从内核日志尾部找一句人话原因（给 UI 显示，便于玩家/我们定位）。
func _exit_reason() -> String:
	var tail := read_log_tail(4)
	if tail.is_empty():
		return "联机内核启动后立刻退出（原因未知，可能被安全软件拦截）"
	var t := tail.to_lower()
	if t.find("wintun") >= 0 or t.find("adapter") >= 0:
		return "创建虚拟网卡失败（需要允许管理员权限）"
	if t.find("administrator") >= 0 or t.find("permission") >= 0:
		return "权限不足（需要允许管理员权限）"
	if t.find("addr") >= 0 and t.find("use") >= 0:
		return "端口被占用（可能有其它联机工具在运行）"
	return "联机内核启动失败：" + tail.split("\n")[-1].substr(0, 120)


## 读内核日志尾部若干行（找不到就返回空串，别抛错）。
static func read_log_tail(lines: int) -> String:
	var d := DirAccess.open(log_dir())
	if d == null:
		return ""
	var newest := ""
	var newest_time := 0
	for f in d.get_files():
		var p := log_dir().path_join(f)
		var t := FileAccess.get_modified_time(p)
		if t > newest_time:
			newest_time = t
			newest = p
	if newest == "":
		return ""
	var txt := FileAccess.get_file_as_string(newest)
	var all := txt.split("\n")
	var from := maxi(0, all.size() - lines)
	return "\n".join(Array(all).slice(from))
