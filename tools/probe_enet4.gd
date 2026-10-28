extends Node

## Single-variable bisect: probe_bare body + add_child, no preloads, no transport.
## If THIS connects, the transport class is at fault.
var is_host := false
var p = null
var dummy = null
var ticks := 0

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	is_host = args.has("--host")
	var port := 34300
	for i in args.size():
		if args[i] == "--port" and i + 1 < args.size():
			port = int(args[i + 1])
	dummy = Node.new()
	add_child(dummy)
	dummy.set_process(false)
	p = ENetMultiplayerPeer.new()
	if is_host:
		var e = p.create_server(port, 4)
		print("[H] server err=" + str(e))
		p.peer_connected.connect(func(id): print("[H] JOIN " + str(id)))
	else:
		var e2 = p.create_client("127.0.0.1", port)
		print("[C] client err=" + str(e2))
		p.peer_connected.connect(func(id): print("[C] CONNECTED " + str(id)))

func _process(_d: float) -> void:
	ticks += 1
	var e3 = p.poll()
	if ticks % 30 == 0:
		print("[DBG] t=" + str(ticks) + " poll=" + str(e3) + " status=" + str(p.get_connection_status()))
	if ticks > 120:
		print("=== done ===")
		get_tree().quit(0)
