extends Node

## Compare bare ENet vs project transport in the SAME process.
const TR := preload("res://scripts/net/eve_ddz_transport.gd")

var is_host := false
var ticks := 0
var bare = null
var tr = null

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	is_host = args.has("--host")
	var port := 27086
	for i in args.size():
		if args[i] == "--port" and i + 1 < args.size():
			port = int(args[i + 1])
	tr = TR.new()
	add_child(tr)
	if is_host:
		# 裸服务端
		bare = ENetMultiplayerPeer.new()
		var e: int = bare.create_server(port, 4)
		print("[H] bare create_server err=" + str(e))
		bare.peer_connected.connect(func(id): print("[H] bare JOIN " + str(id)))
		# 传输层服务端（另一个端口）
		var ok: bool = tr.host_start(port + 1)
		print("[H] tr host_start ok=" + str(ok) + " port=" + str(port + 1))
		tr.peer_joined.connect(func(pid): print("[H] tr JOIN " + str(pid)))
	else:
		# 客户端：先连裸服务端
		bare = ENetMultiplayerPeer.new()
		var e2: int = bare.create_client("127.0.0.1", port)
		print("[C] bare create_client err=" + str(e2))
		bare.peer_connected.connect(func(id): print("[C] bare CONNECTED " + str(id)))
		# 再连传输层服务端
		var ok2: bool = tr.join("127.0.0.1", port + 1, Time.get_ticks_msec())
		print("[C] tr join ok=" + str(ok2))

func _process(_d: float) -> void:
	ticks += 1
	if bare != null:
		bare.poll()
	if ticks % 30 == 0:
		var bs = "null" if bare == null else str(bare.get_connection_status())
		print("[DBG] t=" + str(ticks) + " bare=" + bs)
	if ticks > 120:
		print("=== done ===")
		get_tree().quit(0)