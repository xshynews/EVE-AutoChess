extends Node

## Real ENet probe. Two processes:
##   godot --headless res://tools/probe_enet.tscn -- --host --port 27099
##   godot --headless res://tools/probe_enet.tscn -- --join --port 27099

const NET := preload("res://scripts/net/eve_versus_net.gd")
const TR := preload("res://scripts/net/eve_ddz_transport.gd")

var net = null
var tr = null
var is_host := false
var ticks := 0

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	is_host = args.has("--host")
	var port := 27099
	for i in args.size():
		if args[i] == "--port" and i + 1 < args.size():
			port = int(args[i + 1])
	net = NET.new()
	tr = TR.new()
	add_child(tr)
	tr.set_process(false)   ## 探针自己 poll，避免双重 poll 吃包
	net.attach_transport(tr)
	if is_host:
		net.host_setup(["host", "", ""], 1)
		var ok: bool = tr.host_start(port)
		print("[HOST] start ok=" + str(ok) + " port=" + str(port))
		if not ok:
			print("[HOST] " + tr.last_error)
			get_tree().quit(1)
			return
		print("[HOST] waiting")
	else:
		net.client_setup(0, "client")
		var ok2: bool = tr.join("127.0.0.1", port, Time.get_ticks_msec())
		tr.peer.peer_connected.connect(func(id): print("[RAW] peer_connected " + str(id)))
		tr.peer.peer_disconnected.connect(func(id): print("[RAW] peer_disconnected " + str(id)))
		print("[CLIENT] join ok=" + str(ok2))
		if not ok2:
			print("[CLIENT] " + tr.last_error)
			get_tree().quit(1)
			return
		# ENet 握手要几帧，连接建立前发包会被静默丢弃
		# => 必须等 connected_ok 再发 HELLO
		tr.connected_ok.connect(func():
			print("[CLIENT] connected_ok, sending HELLO")
			net.client_join("A")
			print("[CLIENT] HELLO sent"))

func _process(_d: float) -> void:
	ticks += 1
	var polled = null
	if tr != null:
		polled = tr.peer
	if polled != null:
		polled.poll()   ## void，不要接返回值
		if ticks % 30 == 0:
			print("[DBG] t=" + str(ticks) + " status=" + str(polled.get_connection_status()) + " avail=" + str(polled.get_available_packet_count()))
	for msg in net.drain():
		var d: Dictionary = msg["d"]
		var from := int(msg["from"])
		if is_host:
			var r: Dictionary = net.apply_remote(from, d)
			print("[HOST] recv kind=" + str(int(d.get("kind",-1))) + " ok=" + str(bool(r.get("ok",false))))
			if bool(r.get("ok", false)) and int(d.get("kind",-1)) == NET.Kind.HELLO:
				net.host_broadcast_net(NET.Kind.WELCOME, {"seats": net.seats.duplicate(true)})
				print("[HOST] WELCOME sent")
		else:
			print("[CLIENT] recv kind=" + str(int(d.get("kind",-1))))
			if int(d.get("kind",-1)) == NET.Kind.WELCOME:
				net.seats = d["seats"]
				net.client_ready_net()
				print("[CLIENT] READY sent")
	if is_host and ticks == 120:
		var rc := 0
		for s2 in net.seats:
			if bool(s2["ready"]):
				rc += 1
		print("[HOST] ready " + str(rc) + "/" + str(net.seats.size()))
		net.host_broadcast_net(NET.Kind.ROUND, {"round": 1, "kind": 1, "time": 90.0})
		print("[HOST] ROUND broadcast")
	if ticks > 200:
		print("=== done ===")
		get_tree().quit(0)