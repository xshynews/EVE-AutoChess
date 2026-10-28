extends Node

## 联机 · **UDP 中转客户端**（本机转发器）—— 让手机也能当房主的关键一块。
##
## ══════════════════════════════════════════════════════════════════
##  它解决什么
## ══════════════════════════════════════════════════════════════════
##  手机不能建 TUN（没有 VpnService 就走不了 EasyTier 房主），于是改成：
##  **两端都主动连一台公网 UDP 中继**，中继按 8 位房间码把两端的包互转。
##  本文件在这一端做「本地 ENet ⇄ 中继」的搬运工，ENet 本身一行不改。
##
##      房主：ENet 服务端 127.0.0.1:27016  ←→  本转发器(绑定 27015)  ←→  中继
##      加入：ENet 客户端 → 127.0.0.1:27015（本转发器）→ 中继 → 房主
##
##  ⚠️ 为什么房主要绑 27016：本转发器要占用 27015 才能**接住**加入方的
##    ENet 包，房主的 ENet 服务端就必须错开一个端口，否则两个 socket 抢同一端口。
##  ⚠️ 为什么加入方不需要固定目标：ENet 客户端是「发向 27015」，所以转发器
##    从收到的包里就学到了它自己的源地址，回包按这个地址发回去即可。
##
## ── 协议（11 字节头 + 原样负载）──────────────────────────────
##      [0..1]  "EV"（0x45 0x56）
##      [2..9]  房间码 8 个 ASCII 字符（已 normalize，大写、去分隔符）
##      [10]    本端身份：0 = 房主 / 1 = 加入方
##      [11..]  ENet 原始数据报（原样转发，不解析）
##
##  ⚠️ 中继只做「UDP 数据报转发」：不认识 ENet、不重排、不重传 ——
##    可靠性仍由 ENet 自己保证，所以这条链路上不存在「第二份协议」。

const MAGIC_0 := 0x45   ## 'E'
const MAGIC_1 := 0x56   ## 'V'
const HEADER := 11
const ROOM_LEN := 8

const SIDE_HOST := 0
const SIDE_GUEST := 1

## 注册心跳间隔（毫秒）。
##
## ⚠️⚠️ 这个不能省：中继只知道「谁给它发过包」，而**房主的 ENet 服务端从不主动发包**
##   （它只回包）⇒ 没有心跳的话，加入方发来的包在中继那里找不到房主的地址，
##   直接被丢弃、永远连不上。心跳用**空负载**，两端收到空负载都当注册包丢掉。
const REG_EVERY_MS := 1500

## 中继服务器地址（IP 或域名，`configure()` 时解析一次）
var relay_host := ""
var relay_port := 0
## 8 位房间码（大写字母数字）
var room := ""
## 本端身份：SIDE_HOST / SIDE_GUEST
var side := SIDE_HOST

## 本转发器占用的本地端口（加入方的 ENet 连这里；房主从这里发向 27016）
var local_port := 0

## 房主：固定把中继来的包送到这个本地地址（ENet 服务端）
var fixed_local_ip := ""
var fixed_local_port := 0

## 已解析的中继 IP（空 = 还没解析 / 解析失败）
var _relay_ip := ""
## 下次允许重试解析的时刻（毫秒）。
## ⚠️ `IP.resolve_hostname` 是**同步**的 —— 手机在弱网下解析失败可能卡几百毫秒，
##   而心跳是每 1.5 秒一次 ⇒ 不加退避就会每 1.5 秒卡一次。失败后 10 秒再试。
var _resolve_next_ms := 0
## 加入方：上一次从本地 ENet 收到的来源（回包目标）
var _peer_ip := ""
var _peer_port := 0

var _sock: PacketPeerUDP = null
## 是否已经发过第一次注册（⛔ 不能用 `_last_reg_ms == 0` 判断：
## 引擎启动后的前 1.5 秒里 `Time.get_ticks_msec()` 还没到心跳间隔，会漏掉首次注册）
var _reg_sent := false
var _last_reg_ms := 0
## 统计（验收 / 日志用）
var packets_up := 0     ## 本地 → 中继
var packets_down := 0   ## 中继 → 本地


## 配好房间参数（**在 `start()` 之前调**）。`p_side` 见 `SIDE_*`。
func configure(p_relay_host: String, p_relay_port: int, p_room: String, p_side: int) -> void:
	relay_host = p_relay_host.strip_edges()
	relay_port = p_relay_port
	room = p_room.strip_edges().to_upper()
	side = p_side & 1
	_relay_ip = ""
	_resolve_next_ms = 0


## 房主用：中继来的包固定送给本机的 ENet 服务端（`127.0.0.1:27016`）。
func set_fixed_local(ip: String, port: int) -> void:
	fixed_local_ip = ip
	fixed_local_port = port


## 绑定本地端口并开始转发。返回是否成功。
##
## ⚠️ 只绑 127.0.0.1：这是「本机 ENet ⇄ 中继」的私线，不需要对局域网暴露。
func start(p_local_port: int) -> bool:
	local_port = p_local_port
	if _sock == null:
		_sock = PacketPeerUDP.new()
	var err := _sock.bind(local_port, "127.0.0.1")
	if err != OK:
		push_warning("[relay] 绑定 127.0.0.1:%d 失败（%d）" % [local_port, err])
		_sock = null
		return false
	_resolve_relay()
	print("[relay] 转发器就绪 · 本地 %d · 中继 %s:%d · 房间 %s · 身份 %s" % [
			local_port, _relay_ip, relay_port, room,
			"房主" if side == SIDE_HOST else "加入"])
	return true


func stop() -> void:
	if _sock != null:
		_sock.close()
		_sock = null


func is_running() -> bool:
	return _sock != null


## 每帧调：双向搬运。
func poll() -> void:
	if _sock == null:
		return
	var now := Time.get_ticks_msec()
	# ── 注册心跳（空负载）：房主不主动发包，必须先让中继记住它 ──
	if not _reg_sent or now - _last_reg_ms >= REG_EVERY_MS:
		_reg_sent = true
		_last_reg_ms = now
		if _relay_ip == "":
			_resolve_relay()
		if _relay_ip != "":
			_sock.set_dest_address(_relay_ip, relay_port)
			_sock.put_packet(encode(room, side, PackedByteArray()))
	while _sock.get_available_packet_count() > 0:
		var pkt := _sock.get_packet()
		var from_ip := _sock.get_packet_ip()
		var from_port := _sock.get_packet_port()
		if from_ip == _relay_ip and from_port == relay_port:
			# ── 中继 → 本地 ──
			var body := decode(pkt, room)
			# 空负载 = 对端的注册心跳（或垃圾包）⇒ 不往本地 ENet 送
			if body.is_empty():
				continue
			var dst_ip := fixed_local_ip
			var dst_port := fixed_local_port
			if dst_ip == "":
				dst_ip = _peer_ip
				dst_port = _peer_port
			if dst_ip == "":
				continue
			_sock.set_dest_address(dst_ip, dst_port)
			_sock.put_packet(body)
			packets_down += 1
		else:
			# ── 本地 ENet → 中继 ──（加入方顺手记住回包地址）
			_peer_ip = from_ip
			_peer_port = from_port
			if _relay_ip == "":
				_resolve_relay()
				if _relay_ip == "":
					continue
			_sock.set_dest_address(_relay_ip, relay_port)
			_sock.put_packet(encode(room, side, pkt))
			packets_up += 1


# ────────────────────────────────────────────── 纯函数（自检直接断言）

## 组包：`EV + 8 位房间 + 身份 + 原负载`。
static func encode(p_room: String, p_side: int, payload: PackedByteArray) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(HEADER + payload.size())
	out[0] = MAGIC_0
	out[1] = MAGIC_1
	var rb := p_room.strip_edges().to_upper().to_ascii_buffer()
	for i in ROOM_LEN:
		out[2 + i] = rb[i] if i < rb.size() else 0x30
	out[10] = p_side & 1
	if not payload.is_empty():
		for i in payload.size():
			out[HEADER + i] = payload[i]
	return out


## 解包：魔数/长度/房间不符 ⇒ 返回空数组（调用方当垃圾包丢弃）。
static func decode(pkt: PackedByteArray, p_room: String) -> PackedByteArray:
	if pkt.size() < HEADER:
		return PackedByteArray()
	if pkt[0] != MAGIC_0 or pkt[1] != MAGIC_1:
		return PackedByteArray()
	var got := pkt.slice(2, 2 + ROOM_LEN).get_string_from_ascii()
	if got != p_room.strip_edges().to_upper():
		return PackedByteArray()
	return pkt.slice(HEADER)


# ────────────────────────────────────────────── 内部

func _resolve_relay() -> void:
	if relay_host == "" or relay_port <= 0:
		_relay_ip = ""
		return
	var now := Time.get_ticks_msec()
	if _relay_ip == "" and now < _resolve_next_ms:
		return
	# IP 直填（含 IPv4/IPv6）直接可用；域名走同步解析（失败后退避 10 秒）
	if relay_host.is_valid_ip_address():
		_relay_ip = relay_host
		return
	var ip := IP.resolve_hostname(relay_host, IP.TYPE_ANY)
	_relay_ip = ip if ip != "" else ""
	if _relay_ip == "":
		_resolve_next_ms = now + 10000
		push_warning("[relay] 中继域名解析失败（10 秒后重试）：%s" % relay_host)
