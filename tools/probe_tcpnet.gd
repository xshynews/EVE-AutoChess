extends Node
## Full versus handshake over TCP.  --host / --join --port N
## Lifespan is WALL CLOCK (headless _process is unthrottled).
const NET := preload("res://scripts/net/eve_versus_net.gd")
const TR := preload("res://scripts/net/eve_versus_transport.gd")

var is_host := false
var net = null
var tr = null
var hello_sent := false
var round_sent := false
var t0 := 0
const LIFE_MS := 45000

func _ready() -> void:
	t0 = Time.get_ticks_msec()
	var args := OS.get_cmdline_user_args()
	is_host = args.has("--host")
	var port := 36100
	for i in args.size():
		if args[i] == "--port" and i + 1 < args.size():
			port = int(args[i + 1])
	net = NET.new()
	tr = TR.new()
	add_child(tr)
	tr.set_process(false)
	net.attach_transport(tr)
	if is_host:
		net.host_setup(["房主", "", ""], 1)
		var ok: bool = tr.host_start(port)
		print("[H] server ok=" + str(ok) + " port=" + str(port))
	else:
		net.client_setup(0, "客A")
		var ok2: bool = tr.join("127.0.0.1", port, Time.get_ticks_msec())
		print("[C] join ok=" + str(ok2))

func _process(_d: float) -> void:
	tr.poll()
	for msg in net.drain():
		var d: Dictionary = msg["d"]
		var from := int(msg["from"])
		var kind := int(d.get("kind", -1))
		if is_host:
			var r: Dictionary = net.apply_remote(from, d)
			print("[H] recv kind=" + str(kind) + " from=" + str(from) + " ok=" + str(bool(r.get("ok", false))))
			if bool(r.get("ok", false)) and kind == NET.Kind.HELLO:
				net.host_send(from, NET.Kind.WELCOME, {"seats": net.seats.duplicate(true)})
				print("[H] WELCOME sent")
		else:
			print("[C] recv kind=" + str(kind))
			if kind == NET.Kind.WELCOME:
				net.seats = d["seats"]
				net.client_ready_net()
				print("[C] READY sent")
			elif kind == NET.Kind.ROUND:
				print("[C] ROUND #" + str(int(d.get("round", -1))) + " kind=" + str(int(d.get("kind", -1))))
	if not is_host and not hello_sent and tr.my_id != 1:
		hello_sent = true
		net.client_join("客A")
		print("[C] HELLO sent")
	if is_host and not round_sent and Time.get_ticks_msec() - t0 > 8000:
		round_sent = true
		var rc := 0
		for s in net.seats:
			if bool(s["ready"]):
				rc += 1
		print("[H] ready " + str(rc) + "/" + str(net.seats.size()) + "  online=" + str(_online()))
		net.host_broadcast_net(NET.Kind.ROUND, {"round": 1, "kind": 1, "time": 90.0})
		print("[H] ROUND broadcast")
	if Time.get_ticks_msec() - t0 > LIFE_MS:
		print("=== done ===")
		get_tree().quit(0)

func _online() -> int:
	var n := 0
	for s in net.seats:
		if bool(s["online"]):
			n += 1
	return n
