extends Node

## A/B: bare ENet peer vs project transport, identical tick loop.
##   --mode A : bare
##   --mode B : transport
const TR := preload("res://scripts/net/eve_ddz_transport.gd")

var mode := "A"
var is_host := false
var ticks := 0
var bare = null
var tr = null

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	is_host = args.has("--host")
	for i in args.size():
		if args[i] == "--mode" and i + 1 < args.size():
			mode = String(args[i + 1])
	var port := 31111
	for i in args.size():
		if args[i] == "--port" and i + 1 < args.size():
			port = int(args[i + 1])
	print("[INIT] mode=" + mode + " host=" + str(is_host) + " port=" + str(port))
	if mode == "A":
		bare = ENetMultiplayerPeer.new()
		if is_host:
			var e: int = bare.create_server(port, 4)
			print("[A] server err=" + str(e))
			bare.peer_connected.connect(func(id): print("[A] JOIN " + str(id)))
		else:
			var e2: int = bare.create_client("127.0.0.1", port)
			print("[A] client err=" + str(e2))
			bare.peer_connected.connect(func(id): print("[A] CONNECTED " + str(id)))
	else:
		tr = TR.new()
		add_child(tr)
		tr.set_process(false)
		if is_host:
			var ok: bool = tr.host_start(port)
			print("[B] host_start ok=" + str(ok))
			tr.peer_joined.connect(func(pid): print("[B] JOIN " + str(pid)))
		else:
			var ok2: bool = tr.join("127.0.0.1", port, Time.get_ticks_msec())
			print("[B] join ok=" + str(ok2))
			tr.connected_ok.connect(func(): print("[B] CONNECTED id=" + str(tr.my_id)))

func _process(_d: float) -> void:
	ticks += 1
	var polled = null
	if mode == "A":
		polled = bare
	else:
		polled = tr.peer if tr != null else null
	if polled != null:
		var e3 = polled.poll()
		if ticks % 30 == 0:
			print("[DBG] t=" + str(ticks) + " poll=" + str(e3) + " status=" + str(polled.get_connection_status()) + " avail=" + str(polled.get_available_packet_count()))
	if ticks > 120:
		print("=== done ===")
		get_tree().quit(0)