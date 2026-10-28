extends Node
## Minimal transport clone for bisecting the ENet failure.
## Contains ONLY: peer + host_start + join + poll. No signals, no _ready, no wire fns.

var peer: ENetMultiplayerPeer = null
var is_server := false
var my_id := 1
var last_error := ""

func host_start(port: int) -> bool:
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_server(port, 4)
	if err != OK:
		last_error = "port busy"
		peer = null
		return false
	is_server = true
	my_id = 1
	return true

func join(ip: String, port: int) -> bool:
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, port)
	if err != OK:
		last_error = "cannot connect"
		peer = null
		return false
	is_server = false
	return true

func poll() -> void:
	if peer == null or not is_instance_valid(peer):
		return
	peer.poll()
