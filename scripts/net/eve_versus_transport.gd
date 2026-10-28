extends Node
## 联机对战 · 传输层（TCP + 长度前缀帧）。
##
## ── 为什么不用 ENet（2026-10-27 实测结论）────────────────────
##   ENet 在本机 headless 双进程下**不可靠**：同一份代码，`ENetMultiplayerPeer`
##   建在场景根脚本里能连通，建在辅助脚本的方法里就永远停在 CONNECTING
##   （服务端收不到 JOIN）。交叉测试确认是**服务端**侧问题，
##   最小化到 `peer.create_server(port, 4)` 一行仍然复现。机制未查明。
##
##   而且——自走棋**本来就不需要 ENet**：
##     · 回合制，消息量小且必须可靠有序；
##     · 不需要丢包/乱序容忍，不需要延迟补偿；
##     · 需要的是「简单、可调试、别给我惊喜」。
##   ⇒ 换成 TCP。项目里的 `eve_ai_bridge.gd` 就是 TCP，一直很稳。
##
## ── 帧格式 ────────────────────────────────────────────────
##   4 字节大端长度 + `var_to_bytes(dict)`。
##   ⛔ 不用 JSON：JSON 会把 int 变成 float，回合号/座位号会悄悄带上 `.0`。

signal peer_joined(peer_id: int)
signal peer_left(peer_id: int)
signal connected_ok()
signal connect_failed()
signal packet(peer_id: int, d: Dictionary)

const SERVER_ID := 1
const MAX_MSG := 64 * 1024
const CONNECT_TIMEOUT_MS := 15000

var is_server := false
var my_id := SERVER_ID
var last_error := ""

var _srv: TCPServer = null
var _cli: StreamPeerTCP = null
var _next_id := 2
var _peers := {}          ## id -> StreamPeerTCP
var _bufs := {}           ## id -> PackedByteArray
var _started_ms := 0
var _ever := false


## 开服务器。返回是否成功（端口占用会失败并写 last_error）。
func host_start(port: int) -> bool:
	_srv = TCPServer.new()
	var err := _srv.listen(port)
	if err != OK:
		last_error = "端口 %d 占用（%d）—— 关掉残留的游戏窗口再试" % [port, err]
		_srv = null
		return false
	is_server = true
	my_id = SERVER_ID
	_ever = true
	return true


## 连服务器。
func join(ip: String, port: int, now_ms: int) -> bool:
	_cli = StreamPeerTCP.new()
	var err := _cli.connect_to_host(ip, port)
	if err != OK:
		last_error = "无法连接 %s:%d（%d）" % [ip, port, err]
		_cli = null
		return false
	is_server = false
	_started_ms = now_ms
	_ever = false
	return true


## 客户端连上没？（超时用真实毫秒）
func check_timeout(now_ms: int) -> bool:
	if is_server or _ever or _cli == null:
		return false
	if now_ms - _started_ms < CONNECT_TIMEOUT_MS:
		return false
	last_error = "连接房主超时"
	connect_failed.emit()
	return true


func is_active() -> bool:
	return _srv != null or _cli != null


## 每帧驱动。不依赖本节点的 _process —— 由上层显式调，
## 这样「同一个进程里既当服务端又当客户端」也不会互相踩。
func poll() -> void:
	if is_server:
		_poll_server()
	elif _cli != null:
		_poll_client()


func _poll_server() -> void:
	if _srv == null:
		return
	while _srv.is_connection_available():
		var c := _srv.take_connection()
		if c == null:
			break
		var id := _next_id
		_next_id += 1
		_peers[id] = c
		_bufs[id] = PackedByteArray()
		peer_joined.emit(id)
	for id in _peers.keys():
		_pump(int(id))


func _poll_client() -> void:
	_cli.poll()
	var st := _cli.get_status()
	if st == StreamPeerTCP.STATUS_CONNECTED:
		if not _ever:
			_ever = true
			# ⚠️ 必须离开 SERVER_ID：上层用 `my_id != 1` 判断「我已经连上了」。
			#   原来这里不赋值 ⇒ 客户端 my_id 恒为 1 ⇒ 上层永远以为还没连上，
			#   HELLO 一个字节都发不出去（实测卡在这一行）。
			my_id = 2
			connected_ok.emit()
		_pump(SERVER_ID)
	elif st == StreamPeerTCP.STATUS_ERROR:
		if _ever:
			peer_left.emit(SERVER_ID)
		last_error = "连接断开"
		_cli = null
		if not _ever:
			connect_failed.emit()


## 读一个对端的所有完整帧。
func _pump(pid: int) -> void:
	var conn: StreamPeerTCP = null
	if is_server:
		conn = _peers.get(pid, null)
	else:
		conn = _cli
	if conn == null:
		return
	var avail := conn.get_available_bytes()
	if avail <= 0:
		return
	var got = conn.get_partial_data(avail)
	if int(got[0]) != OK:
		return
	var buf: PackedByteArray = _bufs.get(pid, PackedByteArray())
	buf.append_array(got[1])
	while true:
		if buf.size() < 4:
			break
		var n := buf.decode_u32(0)
		if n == 0 or n > MAX_MSG:
			last_error = "帧长度非法 %d" % n
			buf = PackedByteArray()
			break
		if buf.size() < 4 + n:
			break
		var payload := buf.slice(4, 4 + n)
		buf = buf.slice(4 + n)
		var v = bytes_to_var(payload)
		if v is Dictionary:
			packet.emit(pid, v)
	_bufs[pid] = buf


## 发一份负载给指定对端（0 = 广播，仅服务端有意义）。
func send_to(target: int, d: Dictionary) -> void:
	var payload := var_to_bytes(d)
	if payload.size() > MAX_MSG:
		last_error = "负载过大 %d" % payload.size()
		return
	var frame := PackedByteArray()
	frame.resize(4)
	frame.encode_u32(0, payload.size())
	frame.append_array(payload)
	if is_server:
		for id in _peers.keys():
			if target != 0 and int(id) != target:
				continue
			var c: StreamPeerTCP = _peers[id]
			if c != null:
				c.put_data(frame)
	elif _cli != null and (target == 0 or target == SERVER_ID):
		_cli.put_data(frame)


func broadcast(d: Dictionary) -> void:
	send_to(0, d)


func stop() -> void:
	for id in _peers.keys():
		var c: StreamPeerTCP = _peers[id]
		if c != null:
			c.disconnect_from_host()
	_peers.clear()
	_bufs.clear()
	if _srv != null:
		_srv.stop()
		_srv = null
	if _cli != null:
		_cli.disconnect_from_host()
		_cli = null
	is_server = false
	_ever = false
