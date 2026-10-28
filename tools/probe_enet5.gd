extends Node

## Bisect step 2: probe_enet4 but the peer comes from the transport class.
## No eve_versus_net at all. If this FAILS, the transport is the culprit.
const TR := preload("res://scripts/net/eve_ddz_transport.gd")

var is_host := false
var tr = null
var ticks := 0

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	is_host = args.has("--host")
	var port := 34400
	for i in args.size():
		if args[i] == "--port" and i + 1 < args.size():
			port = int(args[i + 1])
	tr = TR.new()
	add_child(tr)
	tr.set_process(false)
	print("[INIT] MAX_CLIENTS=" + str(TR.MAX_CLIENTS))
	if is_host:
		var ok: bool = tr.host_start(port)
		print("[H] host_start ok=" + str(ok) + " port=" + str(port))
		tr.peer_joined.connect(func(pid): print("[H] JOIN " + str(pid)))
	else:
		var ok2: bool = tr.join("127.0.0.1", port, Time.get_ticks_msec())
		print("[C] join ok=" + str(ok2))
		tr.connected_ok.connect(func(): print("[C] CONNECTED id=" + str(tr.my_id)))

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
