extends RefCounted
## 联机：内置 EasyTier 内核的进程管理（启动、停止、就绪判定、失败原因）。
##
## 整体方案见 `docs/联机方案.md`。
##
## 参数用命令行传递，不用 TOML 配置文件：命令行参数都实机跑通过，TOML 字段名没有验证过，
## 猜错的表现是内核静默退出，排查成本很高。网络密钥例外，通过环境变量 `ET_NETWORK_SECRET`
## 传递（见 `build_env()`），避免出现在进程列表的命令行里。
##
## 所有节点都使用 `--no-tun`：不创建虚拟网卡，不需要管理员权限，也不需要 wintun 驱动。
## - 加入者：`--port-forward` 把本机 127.0.0.1:27015 转发到房主的虚拟 IP。
## - 房主：no-TUN 节点仍可经虚拟 IP 被访问，内核把收到的流量交给本机端口。
##   游戏服务器必须监听 127.0.0.1（或 0.0.0.0），不能绑定虚拟 IP（无 TUN 时该地址不存在，
##   绑定会报 WSAEADDRNOTAVAIL）。实测记录见 `docs/联机方案.md`。
##
## 只结束自己启动的那个 PID（`OS.kill(pid)`），不要按进程名批量结束。

const RC := preload("res://scripts/net/eve_room_code.gd")

enum Role { HOST, CLIENT }
enum State { IDLE, STARTING, UP, FAILED, STOPPED }

## 内核版本（与 `tools/pipeline/_fetch_easytier.py` 和许可声明必须同号）
const VERSION := "2.6.4"
const CORE := "easytier-core.exe"
## `Packet.dll` 是内核的加载期依赖：缺了它内核约 100 ms 就静默退出，报错只打在内核自己的
## 标准输出上（`create_process` 读不到）。no-TUN 模式只需要内核与它，不需要 wintun.dll。
const PACKET_DLL := "Packet.dll"
## 传递网络密钥的环境变量（内核 `--network-secret` 对应的 env，见 `easytier-core --help`）。
const ENV_SECRET := "ET_NETWORK_SECRET"
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
## `seat_no` —— ★ **只有房主用它定位虚拟 IP**；加入者用 DHCP，`seat_no` 仅用于派生
##   端口与实例名（所以同一台机器上跑多个加入者时，传不同的 slot 就能错开端口）。
static func build_args(code_text: String, seat_no: int, is_host: bool,
		relays: Array, display_name: String) -> Array[String]:
	var a: Array[String] = []
	var vip := RC.virtual_ip(code_text, seat_no)
	var lp := RC.listen_port(code_text, seat_no)
	var rp := RC.rpc_port(code_text, seat_no)
	if is_host:
		# ★★ 房主的 IP **必须带 `/24` 前缀**：加入者的 DHCP 靠它确定自己落在哪个网段。
		#    实测：房主 `-i 10.201.7.1/24` ⇒ 加入者 DHCP 拿到 `10.201.7.2`（同网段）；
		#    不带前缀时 DHCP 会给到默认的 `10.126.126.x` ⇒ **两边不在一个子网，通不了**。
		a.append("-i")
		a.append(vip + "/24")
	else:
		# ★★ 加入者用 **DHCP 自动取址**，⛔ 不要自己指定 IP：
		#    加入者在收到房主分配座位之前**并不知道自己是几号位**，
		#    若写死 `-i 10.x.y.2`，第二个加入者会撞同一个 IP（实测会冲突）。
		#    交给 DHCP 就不会撞，也顺手省掉「猜座位」这一步。
		a.append("-d")
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
	# 网络密钥不放在命令行里，由 build_env() 经环境变量传递。
	for uri in relays:
		a.append("-p")
		a.append(String(uri))
	# 所有节点都不建虚拟网卡（见文件头说明）。
	a.append("--no-tun")
	if not is_host:
		# 加入者把本机 27015 转发到房主的虚拟 IP，所以游戏里所有人都连 127.0.0.1:27015。
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


## 启动内核时需要设置的环境变量。目前只有网络密钥：放在命令行里会出现在进程列表中，
## 同一台机器上的其他程序都能看到。
static func build_env(code_text: String) -> Dictionary:
	return {ENV_SECRET: RC.network_secret(code_text)}


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


## 缺哪些文件。缺文件时不要启动，否则现象是内核静默退出、原因未知。
## 房主与加入者都是 no-TUN，依赖相同；`is_host` 参数保留以兼容现有调用。
static func missing_files(_is_host: bool = false) -> Array[String]:
	var out: Array[String] = []
	var exe := core_path()
	if exe == "":
		out.append(CORE)
		return out
	var dir := exe.get_base_dir()
	for n in [CORE, PACKET_DLL]:
		if not FileAccess.file_exists(dir.path_join(n)):
			out.append(n)
	return out


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
	# 子进程在创建时继承当前环境变量，所以只在 create_process 前后短暂设置，随即清除。
	var env := build_env(code_text)
	for k in env:
		OS.set_environment(String(k), String(env[k]))
	pid = OS.create_process(exe, args, false)
	for k in env:
		OS.unset_environment(String(k))
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
