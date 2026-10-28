extends Node

## 中转链路自检：协议编解码 + 服务器转发 + 两端转发器（房主/加入）。
##
## 用法：godot --headless --path . --quit-after 6000 res://tools/verify_udp_relay.tscn
##
## ⚠️ 用**高位端口**（27190+），避免撞到真实对局的 27015/27016。
## ⚠️ 全部在单进程内跑：服务器、两个转发器、两个假 ENet 端点。

const RELAY := preload("res://scripts/net/eve_udp_relay.gd")
const SERVER_SCENE := "res://tools/relay_server.tscn"

const RP := 27190        ## 中继服务器端口
const H_FWD := 27191     ## 房主转发器（占 27015 的角色）
const H_ENET := 27192    ## 房主的假 ENet 服务端（占 27016 的角色）
const G_FWD := 27193     ## 加入方转发器
const G_ENET := 27194    ## 加入方的假 ENet 客户端

var _pass := 0
var _fail := 0


func _ok(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("  [FAIL] %s" % msg)


func _ready() -> void:
	print("═══ UDP 中转链路自检 ═══")
	# ① 协议
	var pkt := RELAY.encode("abcd2345", RELAY.SIDE_HOST, "hi".to_utf8_buffer())
	_ok(pkt.size() == 13, "encode：11 字节头 + 2 字节负载（实际 %d）" % pkt.size())
	_ok(pkt[0] == RELAY.MAGIC_0 and pkt[1] == RELAY.MAGIC_1, "encode：魔数 EV")
	_ok(pkt.slice(2, 10).get_string_from_ascii() == "ABCD2345", "encode：房间码自动大写")
	_ok(RELAY.decode(pkt, "ABCD2345").get_string_from_utf8() == "hi", "decode：同房间可解")
	_ok(RELAY.decode(pkt, "ZZZZ9999").is_empty(), "decode：异房间直接丢")
	_ok(RELAY.decode("x".to_utf8_buffer(), "ABCD2345").is_empty(), "decode：短包直接丢")

	# ② 服务器 + 两个转发器 + 两个假 ENet
	var srv = (load(SERVER_SCENE) as PackedScene).instantiate()
	srv.set("port", RP)
	add_child(srv)
	await get_tree().process_frame

	var h = RELAY.new()
	h.name = "HostRelay"
	add_child(h)
	h.configure("127.0.0.1", RP, "ABCD2345", RELAY.SIDE_HOST)
	h.set_fixed_local("127.0.0.1", H_ENET)
	_ok(h.start(H_FWD), "房主转发器绑定 127.0.0.1:%d" % H_FWD)

	var g = RELAY.new()
	g.name = "GuestRelay"
	add_child(g)
	g.configure("127.0.0.1", RP, "ABCD2345", RELAY.SIDE_GUEST)
	_ok(g.start(G_FWD), "加入转发器绑定 127.0.0.1:%d" % G_FWD)

	var he := PacketPeerUDP.new()
	_ok(he.bind(H_ENET, "127.0.0.1") == OK, "假 ENet 服务端绑定")
	var ge := PacketPeerUDP.new()
	_ok(ge.bind(G_ENET, "127.0.0.1") == OK, "假 ENet 客户端绑定")

	# 加入方 → 房主（先让双方各自发一次心跳，中继才记住两端地址）
	await _pump(h, g, 90)
	ge.set_dest_address("127.0.0.1", G_FWD)
	ge.put_packet("PING".to_utf8_buffer())
	await _pump(h, g, 60)
	var got_h := _drain(he)
	_ok(got_h.has("PING"), "加入 → 房主：经中继到达（收到 %s）" % str(got_h))

	# 房主 → 加入方（回包）
	he.set_dest_address("127.0.0.1", H_FWD)
	he.put_packet("PONG".to_utf8_buffer())
	await _pump(h, g, 60)
	var got_g := _drain(ge)
	_ok(got_g.has("PONG"), "房主 → 加入：经中继到达（收到 %s）" % str(got_g))
	_ok(int(h.packets_up) > 0 and int(h.packets_down) > 0, "房主转发器双向都有计数")
	_ok(int(g.packets_up) > 0 and int(g.packets_down) > 0, "加入转发器双向都有计数")

	# ③ 异房间不串线
	var og := PacketPeerUDP.new()
	og.bind(27196, "127.0.0.1")
	og.set_dest_address("127.0.0.1", RP)
	og.put_packet(RELAY.encode("ZZZZ9999", RELAY.SIDE_GUEST, "X".to_utf8_buffer()))
	await _pump(h, g, 30)
	_ok(not _drain(he).has("X"), "别的房间的包不会串进本房间")

	print("═══ RESULT passed=%d failed=%d ═══" % [_pass, _fail])
	if _fail > 0:
		print("⚠️ 有失败项")
	get_tree().quit(1 if _fail > 0 else 0)


func _pump(a, b, frames: int) -> void:
	for i in frames:
		a.poll()
		b.poll()
		await get_tree().process_frame


func _drain(peer: PacketPeerUDP) -> PackedStringArray:
	var out := PackedStringArray()
	while peer.get_available_packet_count() > 0:
		out.append(peer.get_packet().get_string_from_utf8())
	return out
