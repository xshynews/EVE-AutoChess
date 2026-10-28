extends Node

const NET := preload("res://scripts/net/eve_versus_net.gd")

func _ready() -> void:
	print("=== versus net handshake (loopback) ===")
	print("Kind.HELLO=%d WELCOME=%d READY=%d ROUND=%d" % [NET.Kind.HELLO, NET.Kind.WELCOME, NET.Kind.READY, NET.Kind.ROUND])
	var host = NET.new()
	host.host_setup(["host", "empty", "empty"], 1)
	var c1 = NET.new(); c1.client_setup(1, "A")
	var c2 = NET.new(); c2.client_setup(2, "B")
	print("host room: " + str(host.seats.size()) + " seats")

	# 1) hello
	c1.client_hello(11, "A")
	c2.client_hello(12, "B")
	host.tick()
	for msg in host.drain():
		var r = host.apply_remote(int(msg["from"]), msg["d"])
		if bool(r.get("ok", false)):
			print("  " + String(msg["d"].get("name","?")) + " -> seat " + str(int(r["result"]["seat"])))
			host.host_send(int(msg["from"]), NET.Kind.WELCOME, {"seats": host.seats.duplicate(true)})

	# 2) welcome
	host.tick()
	for c in [c1, c2]:
		for msg in c.drain():
			if int(msg["d"]["kind"]) == NET.Kind.WELCOME:
				c.seats = msg["d"]["seats"]
				print("  client sees seats: " + (c.seats || []).map(func(s): return String(s["name"])).join(", "))

	# 3) ready
	c1.client_ready(11)
	c2.client_ready(12)
	host.tick()
	var n := 0
	for msg in host.drain():
		var r = host.apply_remote(int(msg["from"]), msg["d"])
		if bool(r.get("ok", false)):
			n += 1
		else:
			print("  READY denied: " + String(r.get("reason","")))
	var rc := 0
	for s in host.seats:
		if bool(s["ready"]):
			rc += 1
	print("  READY handled " + str(n) + ", ready " + str(rc) + "/" + str(host.seats.size()))

	# 4) round broadcast
	host.host_broadcast(NET.Kind.ROUND, {"round": 5, "kind": 1, "time": 90.0, "pairings": [[0,1],[2,-1]]})
	host.tick()
	for c in [c1, c2]:
		for msg in c.drain():
			if int(msg["d"]["kind"]) == NET.Kind.ROUND:
				c.round_no = int(msg["d"]["round"])
				c.pairings = msg["d"]["pairings"]
				print("  client got ROUND #" + str(c.round_no))

	# 5) hp broadcast
	host.host_broadcast(NET.Kind.HP, {"hp": [88, 42, 12]})
	host.tick()
	for c in [c1, c2]:
		for msg in c.drain():
			if int(msg["d"]["kind"]) == NET.Kind.HP:
				c.hp = msg["d"]["hp"]
				print("  client got HP " + str(c.hp))

	# 6) disconnect
	host.unbind_peer(12)
	var on := 0
	for s in host.seats:
		if bool(s["online"]):
			on += 1
	print("  after disconnect: " + str(on) + "/" + str(host.seats.size()) + " online")

	print("=== all passed ===")
	get_tree().quit(0)
