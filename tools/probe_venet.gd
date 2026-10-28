extends Node

## 验证：ENet(UDP) 传输层 + versus 协议层，双进程握手 + 编制往返。
const TR := preload("res://scripts/net/eve_ddz_transport.gd")
const NET := preload("res://scripts/net/eve_versus_net.gd")

var is_host := false
var tr = null
var net = null
var t0 := 0
var hello_sent := false
var _fleet_sent := false
const LIFE_MS := 26000

func _ready() -> void:
	t0 = Time.get_ticks_msec()
	var args := OS.get_cmdline_user_args()
	is_host = args.has("--host")
	var port := 27500
	for i in args.size():
		if args[i] == "--port" and i + 1 < args.size():
			port = int(args[i + 1])
	net = NET.new()
	tr = TR.new()
	add_child(tr)
	tr.set_process(false)
	net.attach_transport(tr)
	if is_host:
		net.host_setup(["h", "e", "e", "e"], 1)
		var ok: bool = tr.host_start(port)
		print("[H] host ok=" + str(ok))
	else:
		net.client_setup(0, "c")
		var ok2: bool = tr.join("127.0.0.1", port, Time.get_ticks_msec())
		print("[C] join ok=" + str(ok2))


func _process(_d: float) -> void:
	tr.poll()
	tr.check_timeout(Time.get_ticks_msec())
	for msg in net.drain():
		var d: Dictionary = msg["d"]
		var from := int(msg["from"])
		var kind := int(d.get("kind", -1))
		if is_host:
			var r: Dictionary = net.apply_remote(from, d)
			if bool(r.get("ok", false)) and kind == NET.Kind.HELLO:
				net.host_send(from, NET.Kind.WELCOME, {"seats": net.seats.duplicate(true)})
				print("[H] 收到 HELLO from=" + str(from) + " → WELCOME 已发")
			elif kind == 8:
				print("[H] 收到编制 seat=" + str(int(d.get("seat", -1))) + " n=" + str((d.get("entries", []) as Array).size()))
		else:
			if kind == NET.Kind.WELCOME:
				print("[C] 收到 WELCOME")
				net.client_ready_net()
				print("[C] READY 已发")
	if not is_host and not hello_sent and tr.my_id != 1:
		hello_sent = true
		net.client_join("c")
		print("[C] HELLO 已发 my_id=" + str(tr.my_id))
	if not is_host and hello_sent and not _fleet_sent and Time.get_ticks_msec() - t0 > 6000:
		_fleet_sent = true
		tr.send_to(1, {"kind": 8, "seat": 2, "round": 1, "entries": [{"ship_key": "rifter", "star": 2}]})
		print("[C] 编制已发")
	if Time.get_ticks_msec() - t0 > LIFE_MS:
		print("=== done ===")
		get_tree().quit(0)