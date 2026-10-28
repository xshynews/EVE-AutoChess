extends Node

## Verify: does attaching the peer to SceneTree.multiplayer activate it?
const TR := preload("res://scripts/net/eve_ddz_transport.gd")

var tr = null
var is_host := false
var ticks := 0
var sent := false

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	is_host = args.has("--host")
	var port := 27095
	for i in args.size():
		if args[i] == "--port" and i + 1 < args.size():
			port = int(args[i + 1])
	tr = TR.new()
	add_child(tr)
	if is_host:
		var ok: bool = tr.host_start(port)
		print("[H] server ok=" + str(ok))
		# 关键：把 peer 挂到树的 multiplayer 上
		get_tree().multiplayer.multiplayer_peer = tr.peer
		print("[H] peer attached to tree.multiplayer, status=" + str(get_tree().multiplayer.multiplayer_peer.get_connection_status()))
		tr.packet.connect(func(pid, d): print("[H] PACKET from " + str(pid) + ": " + str(d)))
		tr.peer_joined.connect(func(pid): print("[H] JOIN " + str(pid)))
	else:
		var ok2: bool = tr.join("127.0.0.1", port, Time.get_ticks_msec())
		print("[C] client ok=" + str(ok2))
		get_tree().multiplayer.multiplayer_peer = tr.peer
		print("[C] peer attached, status=" + str(get_tree().multiplayer.multiplayer_peer.get_connection_status()))
		tr.connected_ok.connect(func(): print("[C] CONNECTED my_id=" + str(tr.my_id)))
		tr.packet.connect(func(pid, d): print("[C] PACKET from " + str(pid) + ": " + str(d)))
		tr.peer_joined.connect(func(pid): print("[C] JOIN " + str(pid)))

func _process(_d: float) -> void:
	ticks += 1
	if ticks % 40 == 0:
		var st = get_tree().multiplayer.multiplayer_peer.get_connection_status() if get_tree().multiplayer.multiplayer_peer != null else -1
		print("[DBG] t=" + str(ticks) + " status=" + str(st))
	if not is_host and not sent and ticks > 25:
		tr.send_to(1, {"kind": 0, "hello": "hi"})
		sent = true
		print("[C] sent")
	if ticks > 100:
		print("=== done ===")
		get_tree().quit(0)