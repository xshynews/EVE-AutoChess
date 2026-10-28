extends Node

## Test: does SceneTree drive the peer when assigned to node.multiplayer_peer?
const TR := preload("res://scripts/net/eve_ddz_transport.gd")

var tr = null
var is_host := false
var ticks := 0
var sent := false

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	is_host = args.has("--host")
	var port := 27092
	for i in args.size():
		if args[i] == "--port" and i + 1 < args.size():
			port = int(args[i + 1])
	tr = TR.new()
	add_child(tr)
	if is_host:
		var ok: bool = tr.host_start(port)
		print("[H] server ok=" + str(ok) + " port=" + str(port))
		tr.packet.connect(func(pid, d): print("[H] PACKET " + str(pid) + " " + str(d)))
		tr.peer_joined.connect(func(pid): print("[H] JOIN " + str(pid)))
	else:
		var ok2: bool = tr.join("127.0.0.1", port, Time.get_ticks_msec())
		print("[C] client ok=" + str(ok2) + " port=" + str(port))
		tr.packet.connect(func(pid, d): print("[C] PACKET " + str(pid) + " " + str(d)))
		tr.peer_joined.connect(func(pid): print("[C] JOIN " + str(pid)))
		tr.connected_ok.connect(func(): print("[C] CONNECTED id=" + str(tr.my_id)))

func _process(_d: float) -> void:
	ticks += 1
	tr.poll()   # 手动驱动：tr 可能在 _ready 时还没进树
	if ticks == 45:
		print("[DBG] t=45 conn_status=" + str(tr.peer.get_connection_status()) if tr.peer != null else "peer=null")
	if not is_host and not sent and ticks > 60:
		tr.send_to(1, {"kind": 0, "hello": "hi"})
		sent = true
		print("[C] sent")
	if is_host and ticks == 90:
		tr.broadcast({"kind": 4})
		print("[H] broadcast")
	if ticks > 140:
		print("=== done ===")
		get_tree().quit(0)