extends Node

## Bare ENet but with max_clients = 3 (same as the transport layer).
var is_host := false
var p = null
var ticks := 0

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	is_host = args.has("--host")
	var port := 28333
	for i in args.size():
		if args[i] == "--port" and i + 1 < args.size():
			port = int(args[i + 1])
	if is_host:
		p = ENetMultiplayerPeer.new()
		var e = p.create_server(port, 3)
		print("[H] create_server(3) err=" + str(e))
		p.peer_connected.connect(func(id): print("[H] JOIN " + str(id)))
	else:
		p = ENetMultiplayerPeer.new()
		var e2 = p.create_client("127.0.0.1", port)
		print("[C] create_client err=" + str(e2))
		p.peer_connected.connect(func(id): print("[C] CONNECTED " + str(id)))

func _process(_d: float) -> void:
	ticks += 1
	if p != null:
		p.poll()
	if ticks > 100:
		print("=== done ===")
		get_tree().quit(0)