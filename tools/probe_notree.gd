extends Node

## probe_min WITHOUT add_child(tr): the transport node stays out of the tree.
const TR := preload("res://tools/tr_min.gd")

var is_host := false
var tr = null
var ticks := 0

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	is_host = args.has("--host")
	var port := 35700
	for i in args.size():
		if args[i] == "--port" and i + 1 < args.size():
			port = int(args[i + 1])
	tr = TR.new()
	# NOTE: no add_child here
	if is_host:
		var ok: bool = tr.host_start(port)
		print("[H] host_start ok=" + str(ok))
		tr.peer.peer_connected.connect(func(id): print("[H] JOIN " + str(id)))
	else:
		var ok2: bool = tr.join("127.0.0.1", port)
		print("[C] join ok=" + str(ok2))
		tr.peer.peer_connected.connect(func(id): print("[C] CONNECTED " + str(id)))

func _process(_d: float) -> void:
	ticks += 1
	if tr.peer != null:
		tr.peer.poll()
	if ticks % 30 == 0:
		var st := "-"
		if tr.peer != null:
			st = str(tr.peer.get_connection_status())
		print("[DBG] t=" + str(ticks) + " status=" + st)
	if ticks > 120:
		print("=== done ===")
		get_tree().quit(0)
