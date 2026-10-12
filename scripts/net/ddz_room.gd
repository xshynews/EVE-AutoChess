extends Node
## 联机 · 房间协调器 —— **UI 只跟这个类打交道**。
##
## 它把四样东西串起来：
##   `ddz_net`（会话层：房主权威 + 裁剪快照）
##   `eve_ddz_transport`（传输层：ENet）
##   `eve_tunnel`（连通层：内置 EasyTier 内核）
##   `eve_room_code`（房间码 → 网络名/密钥/网段/端口）
##
## 配套设计：`F:\EVE自走棋\牌面\牌面\联机方案-内置EasyTier-工程设计-2026-10-12.md`
##
## ★ 三条产品规则（都来自实测/用户决定）：
##   ① **全员连同一个地址** `127.0.0.1:27015`：房主是本地直连，加入者由内核转发。
##      ⇒ 游戏侧没有「联机逻辑」和「单机逻辑」两套。
##   ② **房主确认加入**：8 位房间码 + 房主点「允许」（`needs_approval`）。默认开。
##   ③ **降级**：内核起不来 / 玩家拒绝权限 ⇒ `skip_tunnel = true` 走局域网直连，
##      或者用 `peer_ip` 指定一个已知 IP。⛔ 任何情况下都**不能静默失败**。

signal state_changed()
signal join_requested(peer_id: int, player_name: String)
signal failed(reason: String)
signal log_line(text: String)

const N := preload("res://scripts/net/ddz_net.gd")
const RC := preload("res://scripts/net/eve_room_code.gd")
const RELAY := preload("res://scripts/net/eve_relay_list.gd")
const TUN := preload("res://scripts/net/eve_tunnel.gd")
const TP := preload("res://scripts/net/eve_ddz_transport.gd")

enum State { IDLE, TUNNEL, LISTENING, CONNECTING, PLAYING, FAILED }
enum Msg { HELLO, ACCEPT, REJECT, SNAP, CMD, PING }

## 房主是否要手动确认每个加入者（2026-10-12 用户定：要）
var needs_approval := true
## 跳过内核，直接用 ENet 连（局域网模式 / 无头验收）
var skip_tunnel := false
## 目标 IP。默认 127.0.0.1（内核转发口）；局域网降级时可填房主的局域网 IP
var peer_ip := "127.0.0.1"
## 玩家自定义会合节点（设置面板里填；空 = 只用内置）
var custom_relays: Array = []

var code := ""
var is_host := false
var display_name := ""
var state := State.IDLE
var last_error := ""

var net = null
var _tp: Node = null
var _tun = null
## 房主侧：peer_id → {"name":String, "seat":int}
var players := {}
var seat_of_peer := {}
var peer_of_seat := {}
var _pending := {}          ## peer_id → 名字（等房主确认）
var _last_snap := {}        ## seat → 上次下发的负载（避免无变化时反复发）
var _last_ping_ms := -99999 ## ⚠️ 心跳限流：⛔ 别每帧发（60 包/秒纯属浪费）
const PING_INTERVAL_MS := 1000


func _ready() -> void:
	set_process(true)


func _process(_d: float) -> void:
	tick(Time.get_ticks_msec())


## 每帧推进（也由无头验收手动调；本类不读时钟，now_ms 外部传入）。
func tick(now_ms: int) -> void:
	if _tun != null and state == State.TUNNEL:
		if _tun.poll(now_ms) == TUN.State.FAILED:
			_fail(_tun.last_error)
			return
		if _tun.is_up():
			if is_host:
				_start_net_host()
			else:
				_start_net_client(now_ms)
	if _tp != null:
		if not is_host:
			_tp.check_timeout(now_ms)
		if is_host and state == State.PLAYING and net != null:
			var r: Dictionary = net.tick(now_ms)
			if not (r["takeover"] as Array).is_empty() or not (r["auto"] as Array).is_empty():
				for line in r["events"]:
					log_line.emit(String(line))
				_push_all()
		if not is_host and state == State.PLAYING \
				and now_ms - _last_ping_ms >= PING_INTERVAL_MS:
			_last_ping_ms = now_ms
			_send_ping(now_ms)


# ══════════════════════════════════════════════════════════ 房主

## 开房：生成房间码 → 起内核（TUN）→ 起 ENet 服务器 → 等玩家。
func create_room(name: String, now_ms: int, seed_for_code: int = 0) -> bool:
	is_host = true
	display_name = name
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_for_code if seed_for_code != 0 else int(Time.get_unix_time_from_system() * 1000.0)
	code = RC.generate(rng)
	players = {}
	seat_of_peer = {}
	peer_of_seat = {}
	_pending = {}
	_last_snap = {}
	net = N.new()
	net.host_setup([name, "座位1", "座位2"])
	net.my_seat = 0
	_start_transport()
	if skip_tunnel:
		_start_net_host()
		return true
	_tun = TUN.new()
	state = State.TUNNEL
	state_changed.emit()
	log_line.emit("正在启动联机内核…")
	if not _tun.start(code, 0, true, RELAY.peers_with(custom_relays), name, now_ms):
		_fail(_tun.last_error)
		return false
	return true


## 房主确认某个玩家的加入请求。
func approve(peer_id: int) -> void:
	if not _pending.has(peer_id):
		return
	var nm := String(_pending[peer_id])
	_pending.erase(peer_id)
	_assign(peer_id, nm)


## 房主拒绝。
func decline(peer_id: int) -> void:
	if not _pending.has(peer_id):
		return
	_pending.erase(peer_id)
	_tp.send_to(peer_id, {"t": Msg.REJECT, "reason": "房主没有放行"})
	log_line.emit("已拒绝 %d 的加入请求" % peer_id)


## 开局（房主调）。★ seed 只在房主侧，不下发。
func start_game(seed_value: int) -> bool:
	if not is_host or net == null:
		return false
	# 人没到齐也能开（空座位由托管接手），但要给房主一句实话
	var humans := 1 + peer_of_seat.size()
	if humans < N.SEATS:
		log_line.emit("还有 %d 个座位空着，将由电脑托管" % (N.SEATS - humans))
	var r: Dictionary = net.host_start(seed_value, Time.get_ticks_msec())
	if not bool(r["ok"]):
		return false
	state = State.PLAYING
	_push_all()
	state_changed.emit()
	return true


## 出命令 —— **房主和加入者共用这一个入口**（UI 不用分情况）。
##   房主本地（座位 0）：直接裁决并广播；
##   加入者：打包发给房主，等房主回快照（⛔ 客户端本地不产生任何权威状态）。
## 返回房主的裁决结果（加入者拿不到，返回空字典 —— 它只能等快照）。
func send_command(kind: int, payload: Dictionary = {}) -> Dictionary:
	if is_host:
		var cmd := {"seat": 0, "kind": kind}
		cmd.merge(payload, true)
		return _host_apply(cmd)
	if net == null or state != State.PLAYING:
		return {}
	var c: Dictionary = net.client_make_command(kind, payload)
	_tp.send_to(TP.SERVER_ID, {"t": Msg.CMD, "d": c})
	return {}


func _start_net_host() -> void:
	if not _tp.host_start(RC.DEFAULT_PORT):
		_fail(_tp.last_error)
		return
	state = State.LISTENING
	log_line.emit("房间已创建，等待玩家加入")
	state_changed.emit()


func _assign(peer_id: int, nm: String) -> void:
	var seat := _free_seat()
	if seat < 0:
		_tp.send_to(peer_id, {"t": Msg.REJECT, "reason": "房间满了"})
		return
	players[peer_id] = {"name": nm, "seat": seat}
	seat_of_peer[peer_id] = seat
	peer_of_seat[seat] = peer_id
	net.seats[seat]["name"] = nm
	net.seats[seat]["online"] = true
	net.reclaim(seat, Time.get_ticks_msec())
	_tp.send_to(peer_id, {"t": Msg.ACCEPT, "seat": seat,
			"needs_approval": needs_approval})
	_push_seat(seat)
	log_line.emit("%s 加入了（座位 %d）" % [nm, seat])
	state_changed.emit()


## 空座位：1..2（0 是房主自己）
func _free_seat() -> int:
	for s in range(1, N.SEATS):
		if not peer_of_seat.has(s):
			return s
	return -1


func _host_apply(cmd: Dictionary) -> Dictionary:
	var res: Dictionary = net.apply_command(cmd)
	if bool(res["ok"]):
		_push_all()
		state_changed.emit()
	return res


## 把「按座位裁剪」的快照发给对应的玩家。**变化了才发**（省流量、也少一次出错机会）。
func _push_all() -> void:
	for s in peer_of_seat.keys():
		_push_seat(int(s))


func _push_seat(seat: int) -> void:
	if not peer_of_seat.has(seat) or _tp == null:
		return
	var snap: Dictionary = net.snapshot_for(seat)
	if snap.is_empty():
		return
	var sig := str(snap["turn"]) + "|" + str(snap["phase"]) + "|" + str(snap["landlord"]) \
			+ "|" + str(snap["base_score"]) + "|" + str(snap["pass_streak"]) \
			+ "|" + str(snap["counts"]) + "|" + str(snap["played"]) \
			+ "|" + str(snap["bottom"]) + "|" + str(snap["winner"]) \
			+ "|" + str(snap["your_hand"])
	# ⚠️ 签名必须覆盖**全部会变的局面字段**。早先只算了 turn/phase/counts ⇒
	#    「三家叫完分定地主、而 turn 恰好还是同一个人」时签名不变 ⇒ **该发的没发**，
	#    客户端永远停在叫分界面。这类漏发极难查，所以宁可多算几个字段。
	if String(_last_snap.get(seat, "")) == sig:
		return
	_last_snap[seat] = sig
	_tp.send_to(int(peer_of_seat[seat]), {"t": Msg.SNAP, "d": snap})


# ══════════════════════════════════════════════════════════ 加入者

## 加入房间。
func join_room(room_code: String, name: String, now_ms: int) -> bool:
	is_host = false
	display_name = name
	code = RC.normalize(room_code)
	if not RC.is_valid(code):
		_fail("房间码不对（应是 8 位）")
		return false
	net = N.new()
	_start_transport()
	if skip_tunnel:
		_start_net_client(now_ms)
		return true
	_tun = TUN.new()
	state = State.TUNNEL
	state_changed.emit()
	log_line.emit("正在启动联机内核…")
	# ★ 加入者的隧道「座位」只用来派生端口/实例名（虚拟 IP 由 DHCP 自动取，见 eve_tunnel）。
	#   随机取一个 slot ⇒ 同一台机器上跑多个加入者也不会撞端口。
	var slot := RandomNumberGenerator.new()
	slot.seed = int(Time.get_unix_time_from_system() * 1000.0) ^ int(name.hash())
	if not _tun.start(code, slot.randi_range(1, 63), false,
			RELAY.peers_with(custom_relays), name, now_ms):
		_fail(_tun.last_error)
		return false
	return true


func _start_net_client(now_ms: int) -> void:
	if not _tp.join(peer_ip, RC.DEFAULT_PORT, now_ms):
		_fail(_tp.last_error)
		return
	state = State.CONNECTING
	log_line.emit("正在连接房主…")
	state_changed.emit()


func _send_hello() -> void:
	_tp.send_to(TP.SERVER_ID, {"t": Msg.HELLO, "name": display_name,
			"ver": TUN.VERSION})


func _send_ping(now_ms: int) -> void:
	_tp.send_to(TP.SERVER_ID, {"t": Msg.PING, "now_ms": now_ms})


# ══════════════════════════════════════════════════════════ 传输接线

func _start_transport() -> void:
	_tp = TP.new()
	_tp.name = "DdzTransport"
	add_child(_tp)
	_tp.peer_joined.connect(_on_peer_joined)
	_tp.peer_left.connect(_on_peer_left)
	_tp.connected_ok.connect(_on_connected)
	_tp.connect_failed.connect(func(): _fail(_tp.last_error))
	_tp.packet.connect(_on_packet)


func _on_peer_joined(peer_id: int) -> void:
	if is_host:
		log_line.emit("有玩家接入（等待身份）…")
	else:
		pass


func _on_peer_left(peer_id: int) -> void:
	if not is_host:
		# 房主没了 ⇒ 牌局结束（不静默：给玩家一句话）
		if state == State.PLAYING:
			_fail("房主已离开，牌局结束")
		return
	var seat := int(seat_of_peer.get(peer_id, -1))
	if seat < 0:
		# 可能还在等确认阶段就断了
		_pending.erase(peer_id)
		return
	seat_of_peer.erase(peer_id)
	peer_of_seat.erase(seat)
	players.erase(peer_id)
	net.mark_offline(seat)
	log_line.emit("座位 %d 掉线，稍后由电脑托管" % seat)
	for line in net.events.slice(maxi(0, net.events.size() - 1)):
		log_line.emit(String(line))
	state_changed.emit()


func _on_connected() -> void:
	if not is_host:
		_send_hello()
		log_line.emit("已连上房主，等待放行…")


func _on_packet(from_peer: int, d: Dictionary) -> void:
	var t := int(d.get("t", -1))
	if is_host:
		_host_handle(from_peer, t, d)
	else:
		_client_handle(t, d)


func _host_handle(from_peer: int, t: int, d: Dictionary) -> void:
	match t:
		Msg.HELLO:
			var nm := String(d.get("name", "玩家"))
			if String(d.get("ver", TUN.VERSION)) != TUN.VERSION:
				_tp.send_to(from_peer, {"t": Msg.REJECT, "reason": "游戏版本不一致"})
				return
			if _free_seat() < 0:
				_tp.send_to(from_peer, {"t": Msg.REJECT, "reason": "房间满了"})
				return
			if needs_approval:
				_pending[from_peer] = nm
				join_requested.emit(from_peer, nm)
				log_line.emit("%s 请求加入，等待房主确认" % nm)
			else:
				_assign(from_peer, nm)
		Msg.CMD:
			var seat := int(seat_of_peer.get(from_peer, -1))
			if seat < 0:
				return
			var cmd: Dictionary = (d.get("d", {}) as Dictionary).duplicate(true)
			cmd["seat"] = seat          # ★ 用「连接身份」覆盖座位，⛔ 不许客户端自称是谁
			var res := _host_apply(cmd)
			if not bool(res["ok"]):
				# 被拒也要回一句，免得客户端按钮灰错后一脸茫然
				_tp.send_to(from_peer, {"t": Msg.REJECT, "reason": String(res["reason"])})
		Msg.PING:
			net.touch(int(seat_of_peer.get(from_peer, -1)), int(d.get("now_ms", 0)))


func _client_handle(t: int, d: Dictionary) -> void:
	match t:
		Msg.ACCEPT:
			var seat := int(d.get("seat", -1))
			if seat < 0:
				return
			net.client_setup(seat, display_name)
			state = State.PLAYING
			log_line.emit("已加入房间（座位 %d）" % seat)
			state_changed.emit()
		Msg.REJECT:
			if state == State.PLAYING:
				log_line.emit("操作被拒：%s" % String(d.get("reason", "")))
			else:
				_fail(String(d.get("reason", "无法加入房间")))
		Msg.SNAP:
			net.client_apply_snapshot(d.get("d", {}))
			state_changed.emit()


# ══════════════════════════════════════════════════════════ 收尾

func _fail(reason: String) -> void:
	if state == State.FAILED:
		return
	last_error = reason
	state = State.FAILED
	log_line.emit(reason)
	close()
	state_changed.emit()
	failed.emit(reason)


## 退出房间 / 关房：⛔ 一定要把内核停掉，绝不留残余进程。
func close() -> void:
	if _tp != null:
		_tp.stop()
		_tp.queue_free()
		_tp = null
	if _tun != null:
		_tun.stop()
		_tun = null
	if state != State.FAILED:
		state = State.IDLE
		state_changed.emit()


## 当前玩家该看的视图（房主看自己的裁剪快照，加入者看下发的）。
func view() -> Dictionary:
	if net == null:
		return {}
	return net.host_self_snapshot() if is_host else net.view


func my_seat() -> int:
	if net == null:
		return -1
	return int(net.my_seat)
