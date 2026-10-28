extends Node

## Transport layer, but with its own _process disabled so only the probe polls.
const TR := preload("res://scripts/net/eve_ddz_transport.gd")

var is_host := false
var tr = null
var ticks := 0

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	is_host = args.has("--host")
	var port := 27074
	for i in args.size():
		if args[i] == "--port" and i + 1 < args.size():
			port = int(args[i + 1])
	tr = TR.new()
	add_child(tr)
	tr.set_process(false)   ## 禁用它自己的 poll，只由本探针驱动
	if is_host:
		var ok: bool = tr.host_start(port)
		print("[H] ok=" + str(ok))
		tr.peer_joined.connect(func(pid): print("[H] JOIN " + str(pid)))
	else:
		var ok2: bool = tr.join("127.0.0.1", port, Time.get_ticks_msec())
		print("[C] ok=" + str(ok2))
		tr.connected_ok.connect(func(): print("[C] CONNECTED id=" + str(tr.my_id)))
		tr.peer_joined.connect(func(pid): print("[C] JOIN " + str(pid)))

func _process(_d: float) -> void:
	ticks += 1
	tr.poll()
	if ticks == 60:
		print("[DBG] t=60 status=" + str(tr.peer.get_connection_status()) if tr.peer != null else "null")
	if ticks > 100:
		print("=== done ===")
		get_tree().quit(0)