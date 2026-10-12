extends Node
## 联机 · 传输层（ENet + 自定义消息）。
##
## 配套设计：`F:\EVE自走棋\牌面\牌面\联机方案-内置EasyTier-工程设计-2026-10-12.md`
##
## ★ 为什么**不用 RPC**：
##   ① 本项目的会话层（`ddz_net.gd`）是 `RefCounted` 不是 `Node`，而 `@rpc` 只能挂在 Node 上；
##   ② 房主权威要的是「**按座位发不同的内容**」（每个客户端只能拿到自己的手牌），
##      用 `put_packet` + `set_target_peer` 比 RPC 广播 + 过滤更直白、也更难写错。
##
## ★ 为什么**自己持一个 `ENetMultiplayerPeer` 而不共用树里那个 `multiplayer`**：
##   ① 同一进程里要能同时存在「服务端 + 客户端」（无头端到端验收就这么跑）；
##   ② 不污染全局 multiplayer，避免和别的系统抢通道。
##
## ⛔ 只传**已经裁剪过**的负载（见 `ddz_net.snapshot_for`）。本层不做任何过滤
##    —— 过滤逻辑放在会话层是刻意的：那里有权威局面，能算出「哪些牌别人不该看到」。

## 服务端 id 恒为 1（ENet 约定）
const SERVER_ID := 1
const MAX_CLIENTS := 3
## 连接超时（毫秒），由驱动层传 now_ms 进来
const CONNECT_TIMEOUT_MS := 15000
## 负载编解码复用会话层那两个静态函数（`var_to_bytes`，保证 int 不变 float）
const PROTO := preload("res://scripts/net/ddz_net.gd")

signal peer_joined(peer_id: int)
signal peer_left(peer_id: int)
signal connected_ok()
signal connect_failed()
signal packet(peer_id: int, d: Dictionary)

var peer: ENetMultiplayerPeer = null
var is_server := false
var my_id := SERVER_ID
var last_error := ""

var _connect_started_ms := 0
var _ever_connected := false


func _ready() -> void:
	# ⚠️ 每帧必须 poll，否则 ENet 不收包（本类不共用树里的 multiplayer，没人替我们 poll）
	set_process(true)


func _process(_d: float) -> void:
	poll()


func poll() -> void:
	# ⚠️ 双重守卫：`peer` 可能已被 `stop()` 置空，也可能对象已释放
	#   （节点 queue_free 与 _process 之间有一帧的窗口）⇒ 都要挡住，否则打 ERROR 日志。
	if peer == null or not is_instance_valid(peer):
		return
	peer.poll()
	# ⛔ while 条件里**也要再判一次**：`packet.emit()` 是同步跑信号处理的，
	#   处理过程里可能把连接关掉（例如收到「房主离开」⇒ 房间 `close()` ⇒ `stop()`）
	#   ⇒ 回到循环顶部时 `peer` 已经是 null 了。实测在套件里报过
	#   `Cannot call method 'get_available_packet_count' on a null value`。
	while peer != null and is_instance_valid(peer) \
			and peer.get_available_packet_count() > 0:
		# ⛔⛔ 顺序**必须**是「先问发送者、再取包」！
		#    Godot 4 的 `get_packet_peer()` 看的是 `incoming_packets` 队列的**队首**，
		#    而 `get_packet()` 会把包弹出去 ⇒ 先 `get_packet` 再问，队列已空，
		#    它会**静默返回 1**（正好是服务端自己的 id）⇒ 表现是「房主以为消息来自自己」，
		#    于是所有回包都发给 id=1，报 `Invalid target peer: 1`，玩家端一直停在「连接中」。
		#    实测排了大半个小时，别再改回去。
		var from := peer.get_packet_peer()
		var data := peer.get_packet()
		var d: Dictionary = PROTO.from_wire(data)
		if not d.is_empty():
			packet.emit(from, d)


## 开服务器。端口 = 「所有人统一连 127.0.0.1:27015」里的那个 27015。
func host_start(port: int) -> bool:
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_CLIENTS)
	if err != OK:
		# ★ 实测最常见的成因：**同一个机器上已经开着另一个游戏实例**（哪怕是忘了关的旧窗口），
		#   它把 UDP 27015 占住了。光说「被占用」玩家不知道怎么办 ⇒ 直接给出可照做的动作。
		last_error = "本地端口 %d 被占用：请先关掉另一个正在联机/残留的游戏窗口，再重新创建房间（%d）" % [port, err]
		peer = null
		return false
	is_server = true
	my_id = SERVER_ID
	_ever_connected = true
	peer.peer_connected.connect(func(id: int): peer_joined.emit(id))
	peer.peer_disconnected.connect(func(id: int): peer_left.emit(id))
	return true


## 连服务器。★ 地址固定 `127.0.0.1` —— 加入者的内核已经把本地 27015 转发到房主的虚拟 IP，
## 所以游戏侧**所有人**（含房主自己）都连同一个地址，不需要分支。
##
## ⚠️ Godot 4 的 `ENetMultiplayerPeer` **只有** `peer_connected/peer_disconnected`
##    两个信号（`connection_failed` 是 Godot 3 的东西，接了会直接报错崩掉）。
##    ⇒ 客户端连上服务端 = 收到 `peer_connected(1)`；连不上**没有信号**，
##      只能靠 `check_timeout()` 计时判超时。
func join(ip: String, port: int, now_ms: int) -> bool:
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, port)
	if err != OK:
		last_error = "无法发起连接（%d）" % err
		peer = null
		return false
	is_server = false
	_connect_started_ms = now_ms
	_ever_connected = false
	peer.peer_connected.connect(func(id: int):
		if id == SERVER_ID:
			_ever_connected = true
			my_id = peer.get_unique_id()
			connected_ok.emit()
		else:
			peer_joined.emit(id))
	peer.peer_disconnected.connect(func(id: int): peer_left.emit(id))
	return true


## 连接是否超时（由驱动层每帧调；`now_ms` 外部传入）。
func check_timeout(now_ms: int) -> bool:
	if peer == null or is_server or _ever_connected:
		return false
	if now_ms - _connect_started_ms >= CONNECT_TIMEOUT_MS:
		last_error = "连接房主超时"
		connect_failed.emit()
		return true
	return false


## 发一份负载给指定对端。
## ⚠️ `set_target_peer(SERVER_ID)` = 发给服务端；`0` = 广播给所有人（服务端用）。
func send_to(target_peer_id: int, d: Dictionary) -> void:
	if peer == null or not is_instance_valid(peer):
		return
	peer.set_target_peer(target_peer_id)
	peer.put_packet(PROTO.to_wire(d))


func broadcast(d: Dictionary) -> void:
	send_to(0, d)


func stop() -> void:
	if peer != null:
		peer.close()
		peer = null
	_ever_connected = false
	set_process(false)


func is_active() -> bool:
	return peer != null
