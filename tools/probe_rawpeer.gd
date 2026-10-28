extends Node

## Take the transport's own ENetMultiplayerPeer and poll it directly from the probe.
const TR := preload("res://scripts/net/eve_ddz_transport.gd")

var is_host := false
var tr = null
var ticks := 0

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	is_host = args.has("--host")
	var port := 27069
	for i in args.size():
		if args[i] == "--port" and i + 1 < args.size():
			port = int(args[i + 1])
	if is_host:
		tr = TR.new()
		add_child(tr)
		tr.set_process(false)
		var ok: bool = tr.host_start(port)
		print("[H] host_start ok=" + str(ok))
	else:
		tr = TR.new()
		add_child(tr)
		tr.set_process(false)
		var ok2: bool = tr.join("127.0.0.1", port, Time.get_ticks_msec())
		print("[C] join ok=" + str(ok2))
		print("[C] peer null? " + str(tr.peer == null))
		tr.peer.peer_connected.connect(func(id): print("[C] RAW peer_connected " + str(id)))
		tr.peer.peer_disconnected.connect(func(id): print("[C] RAW peer_disconnected " + str(id)))

func _process(_d: float) -> void:
	ticks += 1
	if tr.peer != null:
		tr.peer.poll()   ## 直接 poll 裸 peer，绕过传输层的 poll()
	if ticks % 25 == 0:
		var st = "-1" if tr.peer == null else str(tr.peer.get_connection_status())
		print("[DBG] t=" + str(ticks) + " status=" + st)
	if ticks > 90:
		print("=== done ===")
		get_tree().quit(0)