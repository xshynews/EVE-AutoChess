extends Node

## Bisect step 4: probe_enet4 (works) + the transport's PROTO preload chain.
## If adding this preload breaks the handshake, ddz_net is the culprit.
const PROTO := preload("res://scripts/net/ddz_net.gd")

var is_host := false
var p = null
var ticks := 0

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	is_host = args.has("--host")
	var port := 34600
	for i in args.size():
		if args[i] == "--port" and i + 1 < args.size():
			port = int(args[i + 1])
	print("[INIT] PROTO loaded = " + str(PROTO != null))
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
	p.poll()
	if ticks % 30 == 0:
		print("[DBG] t=" + str(ticks) + " status=" + str(p.get_connection_status()))
	if ticks > 120:
		print("=== done ===")
		get_tree().quit(0)
