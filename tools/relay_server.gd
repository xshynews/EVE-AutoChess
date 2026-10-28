extends Node

## 联机 · **UDP 中转服务器（GDScript 版，本地测试 / 临时开服）**
##
## 跑法（无头）：
##     godot --headless --path . res://tools/relay_server.tscn -- 27100
## 或者直接 `godot --path . res://tools/relay_server.tscn` 看窗口（不建议）。
##
## ⚠️ 正式部署到 VPS 用 `tools/relay/eve_relay_server.js`（Node，单文件、更好运维）。
##    两边协议完全一致：[EV][8 字节房间][1 字节身份][ENet 原始负载]。
##
## 只做三件事：按房间码把包互转、记录两端地址、清理长期不活跃的房间。
## ⛔ 不解析 ENet、不重排、不重传、不存任何游戏数据。

const MAGIC_0 := 0x45
const MAGIC_1 := 0x56
const HEADER := 11
## 房间多久没包就丢掉（毫秒）
const ROOM_TTL_MS := 60000

@export var port := 27100

var _sock: PacketPeerUDP = null
## 房间码 → {"eps": [端0, 端1], "last": 毫秒}；端 = {"ip":String,"port":int}
var _rooms: Dictionary = {}
var _last_clean_ms := 0
## 统计（排查用）
var rooms_served := 0
var packets_relayed := 0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty() and String(args[0]).is_valid_int():
		port = int(args[0])
	_sock = PacketPeerUDP.new()
	var err := _sock.bind(port, "*")
	if err != OK:
		push_error("[relay-server] 绑定 UDP %d 失败（%d）" % [port, err])
		_sock = null
		return
	print("[relay-server] 已监听 UDP %d" % port)


func _process(_dt: float) -> void:
	if _sock == null:
		return
	while _sock.get_available_packet_count() > 0:
		var pkt := _sock.get_packet()
		var from_ip := _sock.get_packet_ip()
		var from_port := _sock.get_packet_port()
		if pkt.size() < HEADER or pkt[0] != MAGIC_0 or pkt[1] != MAGIC_1:
			continue
		var room := pkt.slice(2, 2 + 8).get_string_from_ascii()
		var side := pkt[10] & 1
		var e: Dictionary = _rooms.get(room, {})
		if e.is_empty():
			e = {"eps": [null, null], "last": 0}
			rooms_served += 1
		var eps: Array = e["eps"]
		eps[side] = {"ip": from_ip, "port": from_port}
		e["eps"] = eps
		e["last"] = Time.get_ticks_msec()
		_rooms[room] = e
		var other: Variant = eps[side ^ 1]
		if other == null:
			continue
		# 原样转发（头部保留发送方身份，接收方只关心负载）
		_sock.set_dest_address(String(other["ip"]), int(other["port"]))
		_sock.put_packet(pkt)
		packets_relayed += 1
	var now := Time.get_ticks_msec()
	if now - _last_clean_ms >= 15000:
		_last_clean_ms = now
		_cleanup(now)


func _cleanup(now: int) -> void:
	for code in _rooms.keys():
		var e: Dictionary = _rooms[code]
		if now - int(e.get("last", 0)) >= ROOM_TTL_MS:
			_rooms.erase(code)
