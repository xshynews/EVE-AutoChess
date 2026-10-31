extends Node

## EVE 自走棋 —— AI 操作桥（2026-10-26）
##
## 一个**本地 TCP 服务**（127.0.0.1:9081），协议是「一行一个 JSON」：
##
##     请求  {"id": 1, "cmd": "state"}
##     响应  {"id": 1, "ok": true, "data": {...}}
##     错误  {"id": 1, "ok": false, "error": "..."}
##
## ⚠️ 为什么是 TCP 而不是「轮询 user:// 下的命令文件」：
##    文件轮询有至少一帧的延迟且要处理半写状态；TCP 一行一条、天然原子，
##    而且 Godot 的 TCPServer 在无头 / 实机 / 编辑器里行为一致。
##
## ⚠️ 只绑 **127.0.0.1**：这个口子是「给本机 AI 用的」，不是联网服务。
##    端口选 9081 是为了避开 Godot MCP 的 9080。
##
## 命令清单与语义见 `eve_ai_api.gd`。

const API := preload("res://scripts/core/eve_ai_api.gd")

const PORT := 9081
## 单帧最多处理几条命令。AI 一次性刷一屏指令时不让它把主线程占满。
const MAX_CMD_PER_FRAME := 8
## 单行最大字节数。超长的行直接断开 —— 那是客户端写错了，不是游戏该忍的。
const MAX_LINE_BYTES := 1 << 20

var _api: Object
var _server := TCPServer.new()
## 每个连接：{"peer": StreamPeerTCP, "buf": PackedByteArray, "dead": bool}
var _conns: Array[Dictionary] = []
var _listening := false


func _ready() -> void:
	_api = API.new()
	var enabled := _bridge_enabled()
	# 一行状态落盘（`user://ai_bridge_state.txt`）。
	# 导出的 Windows 包是 GUI 子系统，**没有 stdout**，出问题时唯一的现场证据就是它。
	_log_state("enabled=%s editor=%s env=%s argv=%s" % [
		enabled, OS.has_feature("editor"), OS.get_environment("EVE_AI_BRIDGE"),
		str(OS.get_cmdline_args())])
	if not enabled:
		return
	var err := _server.listen(PORT, "127.0.0.1")
	if err != OK:
		_log_state("listen_failed=%d" % err)
		push_warning("[AI桥] 监听 127.0.0.1:%d 失败（错误 %d）—— AI 操作不可用" % [PORT, err])
		return
	_listening = true
	_log_state("listen_ok=%d" % PORT)
	print("[AI桥] 已监听 127.0.0.1:%d · JSON 行协议 · 命令见 scripts/core/eve_ai_api.gd" % PORT)


func _log_state(line: String) -> void:
	var f := FileAccess.open("user://ai_bridge_state.txt", FileAccess.WRITE)
	if f == null:
		return
	f.store_line(line)
	f.close()


## 是否开监听口。
##
## ★ 2026-10-29（用户：「导出的PC版本，说被电脑的防火墙拦截」）：
##   **发布包里默认不开**。Windows 只要看到程序建了 TCP 监听口（哪怕只绑
##   127.0.0.1）就会弹「防火墙已拦截」授权框，而普通玩家根本用不上这个桥，
##   等于每次开游戏都被安全软件拦一次。
##
##   · 编辑器里跑（`--path .` 直接 run）：照旧自动开，开发流程不受影响；
##   · 导出版本：必须显式传 `--ai-bridge`（`exe --ai-bridge`），
##     或 `exe -- --ai-bridge`（Godot 会把 `--` 之后的参数留在
##     `OS.get_cmdline_user_args()` 里）。
##
## ⛔ 别改成「检测端口被占用就退让」之类的迂回 —— 问题不是端口冲突，
##    是发布包**不该**持有一个对外可见的监听口。
##
## ⚠️ 命令行开关实测在**导出的 Windows GUI 包**里读不到
##    （`OS.get_cmdline_args()` 拿不到 `--ai-bridge`，包本身没问题，
##    默认启动确实不监听 —— 见 2026-10-29 现场排查）。
##    所以发布包请优先用环境变量 `EVE_AI_BRIDGE=1` 打开；命令行两条保留兼容。
func _bridge_enabled() -> bool:
	if OS.has_feature("editor"):
		return true
	var env := OS.get_environment("EVE_AI_BRIDGE").strip_edges().to_lower()
	if env == "1" or env == "true" or env == "yes":
		return true
	var argv := OS.get_cmdline_args()
	if "--ai-bridge" in argv:
		return true
	return "--ai-bridge" in OS.get_cmdline_user_args()


func _process(_delta: float) -> void:
	if not _listening:
		return
	_accept()
	_poll_conns()


func _accept() -> void:
	while _server.is_connection_available():
		var peer := _server.take_connection()
		if peer == null:
			continue
		peer.set_no_delay(true)
		_conns.append({"peer": peer, "buf": PackedByteArray(), "dead": false})
		print("[AI桥] 新连接（当前 %d 个）" % _conns.size())


## 收 + 派发。派发可能是协程（screenshot / wait），所以用 await 但不阻塞其它连接。
func _poll_conns() -> void:
	var budget := MAX_CMD_PER_FRAME
	for i in range(_conns.size() - 1, -1, -1):
		var c: Dictionary = _conns[i]
		var peer: StreamPeerTCP = c["peer"]
		peer.poll()
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			_conns.remove_at(i)
			continue
		# 收字节
		var avail := peer.get_available_bytes()
		if avail > 0:
			var ret: Array = peer.get_data(avail)
			if int(ret[0]) == OK:
				var buf: PackedByteArray = c["buf"]
				buf.append_array(ret[1])
				if buf.size() > MAX_LINE_BYTES:
					# 客户端不换行硬灌 —— 判为异常连接
					_conns.remove_at(i)
					peer.disconnect_from_host()
					continue
				c["buf"] = buf
		# 切行
		while budget > 0:
			var line := _next_line(c)
			if line.is_empty():
				break
			budget -= 1
			var req: Variant = JSON.parse_string(line)
			if not (req is Dictionary):
				_reply(peer, {"ok": false, "error": "bad json line"})
				continue
			await _dispatch(req, peer)


## 从连接缓冲里取出一行（不含 \n）。没有完整行时返回空串。
func _next_line(c: Dictionary) -> String:
	var buf: PackedByteArray = c["buf"]
	var idx := -1
	for i in buf.size():
		if buf[i] == 10:
			idx = i
			break
	if idx < 0:
		return ""
	var line := buf.slice(0, idx).get_string_from_utf8()
	c["buf"] = buf.slice(idx + 1)
	return line.strip_edges()


func _dispatch(req: Dictionary, peer: StreamPeerTCP) -> void:
	var id: int = int(req.get("id", 0))
	var cmd := String(req.get("cmd", ""))
	# ⚠️ 必须用 Variant 接：`var args: Dictionary = 1554` 会**当场抛类型错误**，
	#    协程就此中断、响应永远发不回去（客户端只能等到超时）。
	#    实测病象：客户端没认出来的命令走 default 分支把原始参数塞进 args，
	#    桥这边一连接炸一次，日志里刷「Trying to assign value of type float」。
	var raw: Variant = req.get("args", {})
	var args: Dictionary = raw if (raw is Dictionary) else {}
	var res: Dictionary = await _api.execute(cmd, args)
	var out := {"id": id}
	out["ok"] = bool(res.get("ok", false))
	if res.has("data"):
		out["data"] = res["data"]
	if res.has("error"):
		out["error"] = res["error"]
	_reply(peer, out)


func _reply(peer: StreamPeerTCP, payload: Dictionary) -> void:
	if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		return
	var text := JSON.stringify(payload) + "\n"
	peer.put_data(text.to_utf8_buffer())


## 战斗场景快照转发（场景自己造、桥负责转，见 eve_ai_api.build_battle_snapshot）。
func battle_snapshot(sc: Node) -> Dictionary:
	if _api != null and sc != null:
		return _api.build_battle_snapshot(sc)
	return {}


## 连接数 / 是否在听（验收与自检用）。
func debug_status() -> Dictionary:
	return {"listening": _listening, "port": PORT, "connections": _conns.size()}
