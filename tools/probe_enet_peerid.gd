extends Node
## 探针：Godot 4 ENet 的 peer id 语义 —— **两个反直觉点**，踩过所以留档。
##
## ① 服务端给客户端分配的 id 是**随机 32 位整数**（如 2084365138），**不是** 2/3/4；
##    服务端自己的 id 恒为 1。客户端连上表现为收到 `peer_connected(1)`。
## ② ⛔⛔ `get_packet_peer()` 必须在 `get_packet()` **之前**调用：
##    它看的是 `incoming_packets` 队列**队首**，而 `get_packet()` 会把包弹走 ⇒
##    先取包再问，队列已空 ⇒ **静默返回 1**（正好等于服务端 id）⇒
##    表现是「房主以为消息来自自己」，回包全发给 id=1，报 `Invalid target peer: 1`。
##
## 跑法：`godot --headless --path <工程> --quit-after 600 res://tools/probe_enet_peerid.tscn`
var srv: ENetMultiplayerPeer
var cli: ENetMultiplayerPeer
var cli_ready := false
var srv_cid := 0

func _ready() -> void:
	srv = ENetMultiplayerPeer.new()
	srv.create_server(27999, 4)
	srv.peer_connected.connect(func(id):
		srv_cid = id
		print("  [服务端] peer_connected id=", id))
	cli = ENetMultiplayerPeer.new()
	cli.create_client("127.0.0.1", 27999)
	cli.peer_connected.connect(func(id):
		print("  [客户端] peer_connected id=", id, " self unique_id=", cli.get_unique_id())
		if id == 1:
			cli_ready = true)
	# 等连上
	for i in 300:
		await get_tree().process_frame
		srv.poll(); cli.poll()
		if cli_ready:
			break
	print("  连上了吗 =", cli_ready)
	# 客户端 → 服务端（目标写 1）
	cli.set_target_peer(1)
	print("  客户端 put_packet err=", cli.put_packet("hi".to_utf8_buffer()))
	for i in 60:
		await get_tree().process_frame
		srv.poll(); cli.poll()
		while srv.get_available_packet_count() > 0:
			var f := srv.get_packet_peer()      # ★ 先问发送者
			var d := srv.get_packet()           # ★ 再取包
			print("  [服务端] 收到 '", d.get_string_from_utf8(), "' → 发送者 =", f)
	# 服务端 → 客户端：目标 id 用 peer_connected 给的那个（随机 32 位，不是 2/3/4）
	srv.set_target_peer(srv_cid)
	print("  服务端 put_packet err=", srv.put_packet("yo".to_utf8_buffer()))
	for i in 60:
		await get_tree().process_frame
		srv.poll(); cli.poll()
		while cli.get_available_packet_count() > 0:
			var f := cli.get_packet_peer()
			var d := cli.get_packet()
			print("  [客户端] 收到 '", d.get_string_from_utf8(), "' → 发送者 =", f)
	get_tree().quit(0)
