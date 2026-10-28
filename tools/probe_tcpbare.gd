extends Node
## Bare TCP loopback test. Lifespan is WALL CLOCK, not ticks:
## headless runs _process unthrottled, so tick-based exits fire in <1 s
## and the peer process starts AFTER we already quit (ECONNREFUSED).
var is_host := false
var srv: TCPServer = null
var cli: StreamPeerTCP = null
var ticks := 0
var t0 := 0
const LIFE_MS := 40000

func _ready() -> void:
	t0 = Time.get_ticks_msec()
	var args := OS.get_cmdline_user_args()
	is_host = args.has("--host")
	var port := 36400
	for i in args.size():
		if args[i] == "--port" and i + 1 < args.size():
			port = int(args[i + 1])
	if is_host:
		srv = TCPServer.new()
		var e := srv.listen(port)
		print("[H] listen err=" + str(e) + " port=" + str(port))
	else:
		cli = StreamPeerTCP.new()
		var e2 := cli.connect_to_host("127.0.0.1", port)
		print("[C] connect err=" + str(e2))

func _process(_d: float) -> void:
	ticks += 1
	if is_host:
		if srv != null and srv.is_connection_available():
			var c := srv.take_connection()
			print("[H] ACCEPTED")
			c.put_data("hi".to_utf8_buffer())
	else:
		if cli != null:
			cli.poll()
			var st := cli.get_status()
			if st == StreamPeerTCP.STATUS_CONNECTED:
				if not _said:
					_said = true
					print("[C] CONNECTED")
				if cli.get_available_bytes() > 0:
					print("[C] GOT " + str(cli.get_partial_data(64)[1].get_string_from_utf8()))
	if Time.get_ticks_msec() - t0 > LIFE_MS:
		print("=== done ===")
		get_tree().quit(0)

var _said := false
