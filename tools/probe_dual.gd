extends Node

## Run bare ENet on port P and the transport on port P+1 in the same two processes.
const TR := preload("res://scripts/net/eve_ddz_transport.gd")

var is_host := false
var ticks := 0
var bare = null
var tr = null

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	is_host = args.has("--host")
	var base := 27060
	for i in args.size():
		if args[i] == "--port" and i + 1 < args.size():
			base = int(args[i + 1])
	tr = TR.new()
	add_child(tr)
	tr.set_process(false)
	if is_host:
		bare = ENetMultiplayerPeer.new()
		var e: int = bare.create_server(base, 4)
		print("[H] bare server err=" + str(e) + " port=" + str(base))
		bare.peer_connected.connect(func(id): print("[H] bare JOIN " + str(id)))
		var ok: bool = tr.host_start(base + 1)
		print("[H] tr server ok=" + str(ok) + " port=" + str(base + 1))
		tr.peer_joined.connect(func(pid): print("[H] tr JOIN " + str(pid)))
	else:
		bare = ENetMultiplayerPeer.new()
		var e2: int = bare.create_client("127.0.0.1", base)
		print("[C] bare client err=" + str(e2))
		bare.peer_connected.connect(func(id): print("[C] bare CONNECTED " + str(id)))
		var ok2: bool = tr.join("127.0.0.1", base + 1, Time.get_ticks_msec())
		print("[C] tr join ok=" + str(ok2))
		tr.connected_ok.connect(func(): print("[C] tr CONNECTED id=" + str(tr.my_id)))

func _process(_d: float) -> void:
	ticks += 1
	if bare != null:
		bare.poll()
	if tr.peer != null:
		tr.peer.poll()
	if ticks > 110:
		print("=== done ===")
		get_tree().quit(0)