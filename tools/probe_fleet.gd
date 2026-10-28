extends Node

## 1) build_from_entries 能不能按外部名单造船
## 2) FLEET(kind=8) 能不能在真 TCP 上往返
const TR := preload("res://scripts/net/eve_versus_transport.gd")
const NET := preload("res://scripts/net/eve_versus_net.gd")
const FACTORY := preload("res://scripts/scene/eve_fleet_factory.gd")

var is_host := false
var tr = null
var net = null
var t0 := 0
const LIFE_MS := 22000

func _ready() -> void:
	t0 = Time.get_ticks_msec()
	_check_builder()
	var args := OS.get_cmdline_user_args()
	is_host = args.has("--host")
	var port := 37100
	for i in args.size():
		if args[i] == "--port" and i + 1 < args.size():
			port = int(args[i + 1])
	net = NET.new()
	tr = TR.new()
	add_child(tr)
	tr.set_process(false)
	net.attach_transport(tr)
	if is_host:
		net.host_setup(["h","","",""], 1)
		var ok: bool = tr.host_start(port)
		print("[H] host ok=" + str(ok))
	else:
		net.client_setup(0, "c")
		var ok2: bool = tr.join("127.0.0.1", port, Time.get_ticks_msec())
		print("[C] join ok=" + str(ok2))


func _check_builder() -> void:
	var f = FACTORY.new()
	var entries: Array = [
		{"ship_key": "rifter", "star": 2},
		{"ship_key": "kestrel", "star": 1},
		{"ship_key": "stabber", "star": 3},
	]
	var ships: Array = f.build_from_entries(entries, 1)
	print("[BUILD] n=" + str(ships.size()))
	for s in ships:
		print("[BUILD]   " + String(s.ship_name) + " star=" + str(s.star) + " team=" + str(s.team))


func _process(_d: float) -> void:
	tr.poll()
	for msg in net.drain():
		var d: Dictionary = msg["d"]
		var kind := int(d.get("kind", -1))
		if kind == 8:
			print("[FLEET] got seat=%d round=%d n=%d first=%s" % [
				int(d.get("seat", -1)), int(d.get("round", 0)),
				(d.get("entries", []) as Array).size(),
				String(((d.get("entries", []) as Array)[0] as Dictionary).get("ship_key", "?"))])
	if not is_host and tr.my_id != 1 and not _sent:
		_sent = true
		# 注意：房主也要收广播 —— transport.broadcast 在客户端是发给 SERVER_ID。
		tr.send_to(1, {"kind": 8, "seat": 1, "round": 5, "entries": [
			{"ship_key": "rifter", "star": 2}, {"ship_key": "stabber", "star": 2}]})
		print("[C] FLEET sent")
	if Time.get_ticks_msec() - t0 > LIFE_MS:
		print("=== done ===")
		get_tree().quit(0)

var _sent := false