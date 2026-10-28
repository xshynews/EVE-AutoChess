extends Node

## Real-ENet versus handshake via the transport layer.
## Poll style MUST be a bare unconditional call: `tr.peer.poll()`.
## A `for k in N:` loop around it reproducibly breaks the ENet handshake
## in Godot headless (verified 2026-10-27). Do not "optimise" this.
const NET := preload("res://scripts/net/eve_versus_net.gd")
const TR := preload("res://scripts/net/eve_ddz_transport.gd")

var is_host := false
var net = null
var tr = null
var ticks := 0
var hello_sent := false

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	is_host = args.has("--host")
	var port := 33666
	for i in args.size():
		if args[i] == "--port" and i + 1 < args.size():
			port = int(args[i + 1])
	net = NET.new()
	if is_host:
		net.host_setup(["host", "", ""], 1)
	else:
		net.client_setup(0, "A")
	tr = TR.new()
	add_child(tr)
	tr.set_process(false)
	net.attach_transport(tr)
	if is_host:
		var ok: bool = tr.host_start(port)
		print("[H] server ok=" + str(ok) + " port=" + str(port))
		tr.peer_joined.connect(func(pid): print("[H] JOIN " + str(pid)))
	else:
		var ok2: bool = tr.join("127.0.0.1", port, Time.get_ticks_msec())
		print("[C] join ok=" + str(ok2))
		tr.connected_ok.connect(func(): print("[C] CONNECTED id=" + str(tr.my_id)))

func _process(_d: float) -> void:
	ticks += 1
	tr.peer.poll()
	if not is_host and not hello_sent and tr.my_id != 1:
		net.client_join("A")
		hello_sent = true
		print("[C] HELLO sent")
	if ticks % 30 == 0:
		var st := "-"
		if tr.peer != null:
			st = str(tr.peer.get_connection_status())
		print("[DBG] t=" + str(ticks) + " status=" + st)
	for msg in net.drain():
		var d: Dictionary = msg["d"]
		var from := int(msg["from"])
		if is_host:
			var r: Dictionary = net.apply_remote(from, d)
			print("[H] recv kind=" + str(int(d.get("kind",-1))) + " ok=" + str(bool(r.get("ok",false))))
			if bool(r.get("ok", false)) and int(d.get("kind",-1)) == NET.Kind.HELLO:
				net.host_broadcast_net(NET.Kind.WELCOME, {"seats": net.seats.duplicate(true)})
				print("[H] WELCOME sent")
		else:
			print("[C] recv kind=" + str(int(d.get("kind",-1))))
			if int(d.get("kind",-1)) == NET.Kind.WELCOME:
				net.seats = d["seats"]
				net.client_ready_net()
				print("[C] READY sent")
	if is_host and ticks == 120:
		var rc := 0
		for s2 in net.seats:
			if bool(s2["ready"]):
				rc += 1
		print("[H] ready " + str(rc) + "/" + str(net.seats.size()))
		net.host_broadcast_net(NET.Kind.ROUND, {"round": 1, "kind": 1, "time": 90.0})
		print("[H] ROUND broadcast")
	if ticks > 200:
		print("=== done ===")
		get_tree().quit(0)
