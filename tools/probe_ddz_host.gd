extends Node
## 「驻留真房主」探针 —— 在这台电脑上开一个**真的带 EasyTier 隧道**的房间，
## 让真机（安卓）用房间码加入。
##
## 为什么需要它：本机验收（`verify_*`）全是**单进程**的，永远覆盖不到
## 「两台设备跨网络真的连上」这件事。这台真房主 + 真机加入，是唯一能把
## 内核执行 / 隧道组网 / ENet 握手 / 房间协议 全链路串起来跑一次的验法。
##
## 用法：
##     godot --headless --path <工程> --quit-after 200000 \
##           res://tools/probe_ddz_host.tscn -- [房间码种子]
##
## 行为：建房 → 打印房间码（同一 seed 恒定复现）→ **自动放行**加入请求
##       → 除房主外进来 1 人即自动开局（空位由 AI 托管）→ 每 3 秒打印状态。
## ⛔ 它是探针，不进验收套件。

const ROOM := preload("res://scripts/net/ddz_room.gd")
const RC := preload("res://scripts/net/eve_room_code.gd")

## 房间码种子：非 0 ⇒ 房间码**可复现**（同一个种子永远生成同一个码，便于让我先知道码）。
## 可用 `-- <整数>` 覆盖（换种子 = 换一个全新虚拟网，排除旧网络残留）。
const DEFAULT_SEED := 20261012
const NAME := "电脑房主"
## 自炸保险：到这个秒数自己退出（`--quit-after` 只是兜底，别依赖它）
const MAX_SECONDS := 900.0
## 除房主外进来几个人就自动开局（空位由 AI 接管 ⇒ 1 人就够）
const AUTO_START_AFTER := 1
## ★ 探针的房主是 **headless**（没人点牌）⇒ 开局后把座位 0 交给电脑托管。
##   ⛔ 不这么做，整局会卡在「房主不出牌」上，真机玩家什么都做不了 —— 会白跑一趟测试。
const HOST_SEAT_AI := true

var _room = null
var _t := 0.0
var _next_report := 0.0
var _started := false
var _seed := DEFAULT_SEED


func _ready() -> void:
	print("═══ 驻留真房主探针 ═══")
	var args := OS.get_cmdline_user_args()
	if not args.is_empty() and args[0].is_valid_int():
		_seed = int(args[0])
	_room = ROOM.new()
	add_child(_room)
	_room.skip_tunnel = false
	_room.join_requested.connect(_on_join_requested)
	_room.log_line.connect(func(s: String): print("  [房主] %s" % s))
	_room.failed.connect(func(r: String): print("  ✗ 房主失败：%s" % r))
	_room.state_changed.connect(func(): print("  · 状态 → %d" % _room.state))
	if not _room.create_room(NAME, Time.get_ticks_msec(), _seed):
		print("✗ 建房失败：%s" % _room.last_error)
		get_tree().quit(1)
		return
	print("★★ 房间码 = %s（8 位，让真机用这个码加入）" % _room.code)
	print("   隧道内核 pid=%s" % str(_room._tun.pid if _room._tun != null else "无"))
	# ★ 诊断用：这几个值让「隧道层」可以被独立观测（`easytier-cli -p 127.0.0.1:<rpc> peer`），
	#   ⛔ 别只靠游戏层的一句话判断「连没连上」。
	print("   诊断：RPC 端口 = %d · 房主虚拟 IP = %s · 网段 = %s" % [
			RC.rpc_port(_room.code, 0), RC.host_virtual_ip(_room.code),
			RC.subnet_for(_room.code)])


func _on_join_requested(peer_id: int, player_name: String) -> void:
	print("★ 收到加入请求：peer=%d 名字=%s ⇒ 自动放行" % [peer_id, player_name])
	_room.approve(peer_id)


func _process(delta: float) -> void:
	_t += delta
	if _t >= MAX_SECONDS:
		print("── 到时收工（%d 秒）" % int(_t))
		get_tree().quit(0)
		return
	_maybe_autostart()
	if _t >= _next_report:
		_next_report = _t + 3.0
		print("  t=%ds 状态=%d 座位=%s" % [int(_t), _room.state, _seat_brief()])
		if _room.state == ROOM.State.FAILED:
			print("  ✗ 失败原因：%s" % _room.last_error)


func _maybe_autostart() -> void:
	if _started or _room.net == null or _room.state != ROOM.State.LISTENING:
		return
	var humans := 0
	for i in _room.net.SEATS:
		if int(_room.net.seats[i]["peer"]) != _room.net.NO_PEER:
			humans += 1
	if humans > AUTO_START_AFTER:
		_started = true
		var seed_value := int(Time.get_unix_time_from_system() * 1000.0) & 0x7FFFFFFF
		print("★ 人到了（%d 人）⇒ 自动开局" % humans)
		if not _room.start_game(seed_value):
			print("  ✗ 开局失败")
			_started = false
			return
		# ★ 见 HOST_SEAT_AI 的注释：房主座位交给电脑，否则这一局会卡死在第 0 座。
		#   （`ddz_net.tick()` 的自动出牌只看 `seats[turn]["ai"]`，所以直接置位即生效。）
		if HOST_SEAT_AI:
			_room.net.seats[0]["ai"] = true
			_room.net.seats[0]["online"] = false
			print("   · 房主座位（0）已交给电脑托管")


## 座位简报：`0:真人 1:AI 2:空`
func _seat_brief() -> String:
	if _room.net == null:
		return "(未建网)"
	var parts: Array[String] = []
	for i in _room.net.SEATS:
		var s: Dictionary = _room.net.seats[i]
		if int(s["peer"]) != _room.net.NO_PEER:
			parts.append("%d:真人" % i)
		elif bool(s.get("ai", false)):
			parts.append("%d:AI" % i)
		else:
			parts.append("%d:空" % i)
	return " ".join(parts)
