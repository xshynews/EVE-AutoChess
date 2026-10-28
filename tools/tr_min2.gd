extends Node
## Minimal host/join, no error handling at all.
var peer: ENetMultiplayerPeer = null

func host_start(port: int) -> bool:
	peer = ENetMultiplayerPeer.new()
	peer.create_server(port, 4)
	return true

func join(ip: String, port: int) -> bool:
	peer = ENetMultiplayerPeer.new()
	peer.create_client(ip, port)
	return true
