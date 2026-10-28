class_name EveVersusNet
extends RefCounted

## 联机对战协议层（本地回环版）。
##
## ── 为什么先做回环、不接 ENet ──────────────────────────────
##   斗地主那套（ddz_net.gd）是**主机权威**：主机持有唯一棋局，
##   客户端发命令、收快照。联机对战不是这个形状 —— 每人持有自己的
##   EveRunState，战斗各打各的，主机只需要同步：
##       谁准备好了 / 回合到几 / 谁多少血 / 谁掉了
##   所以协议层要重写，但**传输层可以原样复用** ddz_transport 的 ENet。
##   两步走：先用内存回环把协议跑通（好调试、无网络干扰），
##   再把回环换成 ENet。⛔ 不要两边一起调。
##
## ── 与斗地主的三个本质差异 ────────────────────────────────
##   ① 权威对象：ddz 是「一副棋局」，versus 是「N 份各自的 run」；
##   ② 同步内容：ddz 发全量快照，versus 只发回合/血量/配对；
##   ③ 玩家操作：ddz 是出牌命令，versus 只是「我准备好了」。

enum Role { HOST, CLIENT }

## 消息类型（与 ddz_net 的 Kind 同风格：小整数，省字节）
## ⚠️ 2026-10-27：HELLO 必须是 0。
##    原来 HELLO 不写值 ⇒ 从 0 开始，但 READY=1 与 WELCOME=1 撞车，
##    客户端发 READY 被房主当成 WELCOME ⇒ "未知消息 1"。
##    ⛔ 枚举值一旦上过线就不能改序，只能显式写死。
enum Kind {
	HELLO = 0,   ## 入房：客户端报上名字
	WELCOME = 1, ## 房主回：座位表
	READY = 2,   ## 我准备好了（准备阶段结束前发）
	UNREADY = 3, ## 我又想改编制（取消准备）
	ROUND = 4,   ## 房主广播：回合开始（含回合号/类型/时限/配对）
	HP = 5,      ## 房主广播：所有人血量
	RESULT = 6,  ## 房主广播：本回合各家胜负
	BYE = 7,     ## 掉线通知
	FLEET = 8,   ## 上报本回合编制（客户端 → 房主 / 广播）
	SYNC = 9,    ## 房主权威回合状态（血量 / 回合号 / 配对）
}

const MAX_SEATS := 8

var role := Role.HOST
var my_seat := 0
var seats: Array = []          ## [{name, peer, online, ai, ready}]
var round_no := 0
var round_kind := 0
var round_time := 90.0
var pairings: Array = []
var hp: Array = []
var results: Array = []

## 回环总线：`[{from: int, d: Dictionary}]`，`tick()` 时逐条投递。
## 真实网络里这就是 ENet 的 packet 回调，形状故意做成一样。
##
## ⚠️⚠️ 为什么是 **static**：回环版里每个客户端是独立的 EveVersusNet
##    实例，各自持有 `_bus`。客户端往自己总线塞的消息，房主的 tick()
##    根本看不到 —— 实测「入座握手全失败、READY 处理 0 条」。
##    进程内回环必须共享一根总线；换成真 ENet 时把这个 static 去掉即可
##    （ENet 的 packet 回调天然跨实例）。
static var _bus: Array = []
var _inbox: Array = []


# ---------------------------------------------------------------- 房主侧

func host_setup(names: Array = [], host_peer: int = 1) -> void:
	role = Role.HOST
	my_seat = 0
	seats = []
	for i in mini(names.size(), MAX_SEATS):
		seats.append({
			"name": String(names[i]),
			"peer": host_peer if i == 0 else -1,
			"online": i == 0,
			"ai": false,
			"ready": false,
		})


func bind_peer(seat: int, peer: int) -> bool:
	if seat < 0 or seat >= seats.size():
		return false
	if seats[seat]["online"]:
		return false
	seats[seat]["peer"] = peer
	seats[seat]["online"] = true
	seats[seat]["ready"] = false
	return true


func unbind_peer(peer: int) -> void:
	for s in seats:
		if int(s["peer"]) == peer:
			s["online"] = false
			s["ready"] = false
			s["peer"] = -1


func seat_of_peer(peer: int) -> int:
	for i in seats.size():
		if int(seats[i]["peer"]) == peer and bool(seats[i]["online"]):
			return i
	return -1


## 网络命令入口（客户端发来的都要过这里）。
func apply_remote(peer: int, d: Dictionary) -> Dictionary:
	var kind := int(d.get("kind", -1))
	if kind == Kind.HELLO:
		var seat := _first_free_seat()
		if seat < 0:
			return _deny("房间已满")
		if not bind_peer(seat, peer):
			return _deny("入座失败")
		seats[seat]["name"] = String(d.get("name", "玩家 %d" % seat))
		return {"ok": true, "reason": "", "result": {"seat": seat, "seats": seats.duplicate(true)}}
	var seat2 := seat_of_peer(peer)
	if seat2 < 0:
		return _deny("该连接没有入座")
	match kind:
		Kind.READY:
			seats[seat2]["ready"] = true
			return {"ok": true, "reason": "", "result": {}}
		Kind.UNREADY:
			seats[seat2]["ready"] = false
			return {"ok": true, "reason": "", "result": {}}
	return _deny("未知消息 %d" % kind)


func host_broadcast(kind: int, extra: Dictionary = {}) -> void:
	var d := extra.duplicate()
	d["kind"] = kind
	# ★ 2026-10-27：挂上传输层时走网络，否则走回环总线。
	#   ⚠️ 原来这里恒走 _bus ⇒ 真联机时房主的广播只有本进程看得见。
	if transport != null:
		transport.broadcast(d)
		return
	for s in seats:
		if int(s["peer"]) >= 0 and bool(s["online"]):
			_bus.append({"to": int(s["peer"]), "d": d.duplicate()})


func host_send(peer: int, kind: int, extra: Dictionary = {}) -> void:
	var d := extra.duplicate()
	d["kind"] = kind
	# ★ 2026-10-27：同上。原来恒走 _bus ⇒ WELCOME 永远发不到客户端
	#   （实测客户端只收到广播的 ROUND，收不到点发的 WELCOME）。
	_send(peer, d)


# ---------------------------------------------------------------- 客户端侧

func client_setup(seat: int, my_name: String = "") -> void:
	role = Role.CLIENT
	my_seat = seat


## ⚠️ `from` 必填：房主的 apply_remote 靠它定位座位。
func client_hello(my_peer: int, my_name: String) -> void:
	_bus.append({"to": 1, "from": my_peer, "d": {"kind": Kind.HELLO, "name": my_name}})


## `my_peer` 是这条连接在传输层的 id（ENet 里由 MULTIPLAYER_PEER_ID 给）。
## ⚠️ 必须带上：房主的 `apply_remote` 靠它定位座位，不带就永远
##    匹配不到（实测 READY 全部落空）。
func client_ready(my_peer: int) -> void:
	_bus.append({"to": 1, "from": my_peer, "d": {"kind": Kind.READY}})


# ---------------------------------------------------------------- 回环驱动

## 投递一条消息。回环版直接同步调用；真实网络里这是 ENet 回调。
##
## ⚠️ `from` 是**发件人**，`to` 是收件人。原实现把 `to` 传进来当
##    `from` 写，房主收到客户端消息时 `from` 变成 1（房主自己），
##    `seat_of_peer(1)` 返回座位 0 ⇒ 所有客户端的命令都落到房主头上。
func deliver(from_peer: int, d: Dictionary) -> void:
	_inbox.append({"from": from_peer, "d": d})


## 把总线上的消息全部投递，然后清空。返回收到的条数。
##
## `to == 1` 的消息进房主 inbox，其余进对应收件人的 inbox。
## 回环版里「对应收件人」就是同一进程里的另一个实例，
## 所以这里按 `to` 分派：`to == 1` 自己收，否则记到共享的收件箱里。
func tick() -> int:
	var pending := _bus.duplicate()
	_bus = []          ## static 数组不能 .clear()，要整体重新赋值
	for msg in pending:
		var to := int(msg.get("to", 1))
		var from := int(msg.get("from", to))
		if to == 1:
			_inbox.append({"from": from, "d": msg["d"]})
	return pending.size()


func drain() -> Array:
	var out := _inbox.duplicate()
	_inbox.clear()
	return out


func _first_free_seat() -> int:
	for i in seats.size():
		if not bool(seats[i]["online"]):
			return i
	return -1


func _deny(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "result": {}}


# ══════════════════════════════════════════════════════════════════
#  ENet 适配（2026-10-27）
# ══════════════════════════════════════════════════════════════════
#  协议层不变，只是把 `_bus` 换成真传输层。形状故意保持一致：
#    回环：`{"to": peer, "from": peer, "d": {...}}`
#    ENet：`packet` 信号给 `(peer_id, d)`，`send_to(peer_id, d)` 发出
#  所以两层之间只差一个 adapt 函数。
#
#  ⚠️ 传输层直接复用斗地主那套 `eve_ddz_transport.gd` —— 它是通用
#    ENet 包装（host_start / join / send_to / broadcast / packet 信号），
#    与游戏规则无关，一行都不用改。

## 附着的传输层（`eve_ddz_transport.gd` 实例）。null = 回环模式。
var transport = null


## 挂上真传输层。`tr` 需提供：
##   `host_start(port) -> bool`、`join(ip, port, now_ms) -> bool`、
##   `send_to(peer_id, d)`、`broadcast(d)`、`stop()`、
##   以及 `packet(peer_id, d)` / `peer_joined(peer_id)` / `peer_left(peer_id)` 信号。
func attach_transport(tr) -> void:
	transport = tr
	if tr == null:
		return
	tr.packet.connect(_on_transport_packet)
	tr.peer_joined.connect(_on_transport_joined)
	tr.peer_left.connect(_on_transport_left)


func _on_transport_packet(peer_id: int, d: Dictionary) -> void:
	_inbox.append({"from": peer_id, "d": d})


func _on_transport_joined(peer_id: int) -> void:
	## 客户端连上服务端时 Godot 也会报 peer_connected(1)，忽略自己。
	if role == Role.HOST and peer_id != 1:
		pass


func _on_transport_left(peer_id: int) -> void:
	if role == Role.HOST:
		unbind_peer(peer_id)
		_emit_bye(peer_id)


func _emit_bye(peer_id: int) -> void:
	if transport == null:
		return
	transport.broadcast({"kind": Kind.BYE, "peer": peer_id})


## 发一条消息（自动选路：有传输层走网络，否则进回环总线）。
func _send(to_peer: int, d: Dictionary) -> void:
	if transport != null:
		if to_peer <= 0:
			transport.broadcast(d)
		else:
			transport.send_to(to_peer, d)
		return
	_bus.append({"to": to_peer, "from": my_peer_id(), "d": d})


## 房主广播。`to_peer <= 0` 表示广播。
func host_broadcast_net(kind: int, extra: Dictionary = {}) -> void:
	var d := extra.duplicate()
	d["kind"] = kind
	if transport != null:
		transport.broadcast(d)
		return
	host_broadcast(kind, extra)


## 当前连接在传输层的 id。房主恒为 1（Godot 多人 API 约定）。
func my_peer_id() -> int:
	if transport != null and transport.get("my_id") != null:
		return int(transport.my_id)
	return 1


## 客户端入房（网络版）。
func client_join(my_name: String) -> void:
	_send(1, {"kind": Kind.HELLO, "name": my_name})


## 客户端报准备（网络版）。
func client_ready_net() -> void:
	_send(1, {"kind": Kind.READY})
