extends RefCounted
## 斗地主联机会话层（房主权威）。
##
## 纯逻辑：不依赖 UI，也不调用任何网络 API。网络层负责收发字节，本层负责裁决与裁剪。
##
## 安全约束：
## 1. 局面只存在于房主的 `ddz_game` 中。客户端只持有裁剪后的 `view`，不建本地对局。
## 2. 下发给某个座位的快照只含该座位自己的手牌。
## 3. 发牌种子不下发：拿到种子就能重算整副牌。`ddz_game.log_lines` 首行含种子，
##    所以本层另建公开日志 `events`，不转发 `log_lines`。
## 4. 网络来的命令一律走 `apply_remote()`：座位号由连接（peer）查得，
##    命令里自带的 `seat` 字段会被忽略，防止冒充他人。
## 5. 所有外部输入先过 `_validate()`，类型或取值不对直接拒绝，不让脚本报错。
##
## 采用按座位裁剪的全量快照而不是增量：一副牌的状态很小，全量下发更简单，且丢包不会失步。

const G := preload("res://scripts/card/ddz/ddz_game.gd")
const AI := preload("res://scripts/card/ddz/ddz_ai.gd")
const P := preload("res://scripts/card/ddz/ddz_plays.gd")

enum Role { HOST, CLIENT }

## 命令种类。命令格式：`{"seat": int, "kind": Kind, "score": int, "cards": Array, "now_ms": int}`。
enum Kind { BID, PLAY, PASS, PING }

const SEATS := 3
## 未绑定连接的座位的 peer 值。
const NO_PEER := -1
## 心跳间隔与托管阈值（毫秒）。当前时间由驱动层传入，本层不读时钟，便于无头验收。
const HEARTBEAT_MS := 10000
const TAKEOVER_MS := 20000
## 客户端保留的公开日志行数。
const LOG_TAIL := 12
## 单次 `tick()` 最多自动推进的步数，防止多个托管座位连续出牌时死循环。
const MAX_AUTO_STEPS := 64
## 一副牌的牌 id 范围为 0 ~ DECK_SIZE-1。
const DECK_SIZE := 54
## 单手最多出牌张数（与 `ddz_rules.classify` 的上限一致）。
const MAX_PLAY_CARDS := 20
## 单条网络消息的字节上限。快照不到 2 KB，超过上限的数据直接丢弃。
const MAX_WIRE_BYTES := 64 * 1024

var role := Role.HOST
var my_seat := 0
## 座位表：`[{"name": String, "peer": int, "online": bool, "ai": bool, "last_seen_ms": int}]`。
var seats: Array = []
var started := false
## 客户端侧唯一的数据来源（裁剪后的快照）。房主侧不使用。
var view: Dictionary = {}
## 公开日志。不含发牌种子。
var events: Array[String] = []
## 这一轮谁按了「不要」（公开信息，界面要画标记）。
## ⚠️ 会话层自己维护，⛔ 别指望 `ddz_game` 有 —— 它只记 `pass_streak`。
var passed: Array = [false, false, false]

## 权威对局对象。`preload(...).new()` 推断不出类型，所以这里用动态类型。
var _game = null


# ---------------------------------------------------------------- 房主侧

## 开房并登记三个座位。`names[i]` 缺省为「座位 i」。
## `host_peer` 是房主自己的连接 id（Godot 多人 API 中服务端恒为 1），绑定到座位 0。
func host_setup(names: Array = [], host_peer: int = 1) -> void:
	role = Role.HOST
	my_seat = 0
	seats = []
	for i in SEATS:
		seats.append({
			"name": String(names[i]) if i < names.size() else "座位%d" % i,
			"peer": host_peer if i == 0 else NO_PEER,
			"online": true,
			"ai": false,
			"last_seen_ms": 0,
		})
	_game = null
	started = false
	events = []
	view = {}


## 把一个连接绑定到座位。房主确认玩家加入后调用；玩家重连换了 peer id 时再调一次即可。
## 同一个 peer 不能同时占两个座位。
func bind_peer(seat: int, peer: int) -> bool:
	if not _seat_ok(seat) or peer == NO_PEER:
		return false
	var other := seat_of_peer(peer)
	if other >= 0 and other != seat:
		return false
	seats[seat]["peer"] = peer
	return true


## 解除连接绑定（玩家离开房间时调用）。
func unbind_peer(peer: int) -> void:
	var seat := seat_of_peer(peer)
	if seat >= 0:
		seats[seat]["peer"] = NO_PEER


## 连接对应的座位；未入座返回 -1。
func seat_of_peer(peer: int) -> int:
	if peer == NO_PEER:
		return -1
	for i in seats.size():
		if int(seats[i]["peer"]) == peer:
			return i
	return -1


## 开局。`seed_value` 只交给 `_game`，不会出现在任何下发负载里。
func host_start(seed_value: int, now_ms: int = 0) -> Dictionary:
	if role != Role.HOST:
		return _deny("只有房主能开局")
	if _game != null and started:
		return _deny("已经开局了")
	_game = G.new()
	_game.start(seed_value)
	started = true
	for i in SEATS:
		seats[i]["last_seen_ms"] = now_ms
	events = []
	passed = [false, false, false]
	_push_log("发牌完成。牌局由房主裁定（发牌种子不下发）。")
	return {"ok": true, "reason": ""}


## 网络命令入口。座位号由 `peer` 决定，忽略 `cmd` 里的 `seat` 字段。
## 返回 `{"ok": bool, "reason": String, "result": Dictionary}`。
func apply_remote(peer: int, cmd) -> Dictionary:
	if typeof(cmd) != TYPE_DICTIONARY:
		return _deny("命令格式错误")
	var seat := seat_of_peer(peer)
	if seat < 0:
		return _deny("该连接没有入座")
	var c: Dictionary = (cmd as Dictionary).duplicate()
	c["seat"] = seat
	return apply_command(c)


## 受信任的命令入口：房主自己的界面与托管逻辑使用，座位号取自 `cmd["seat"]`。
## 网络来的命令不要直接调用它，改用 `apply_remote()`。
func apply_command(cmd: Dictionary) -> Dictionary:
	if role != Role.HOST:
		return _deny("客户端不裁决（房主权威）")
	if _game == null or not started:
		return _deny("尚未开局")
	var bad := _validate(cmd)
	if bad != "":
		return _deny(bad)
	var seat := int(cmd["seat"])
	var kind := int(cmd["kind"])
	if kind == Kind.PING:
		touch(seat, int(cmd.get("now_ms", 0)))
		return {"ok": true, "reason": "", "result": {}}
	if bool(seats[seat]["ai"]):
		# 托管中的座位不接受真人命令，防止掉线玩家与 AI 同时出牌。
		# 玩家重连时先调 `reclaim(seat)`。托管自己出牌走 `_dispatch()`，不经过这里。
		return _deny("该座位已交给托管")
	return _dispatch(seat, kind, cmd)


## 按座位裁剪的快照。下发给客户端的只有这一份数据。
func snapshot_for(seat: int) -> Dictionary:
	if role != Role.HOST or _game == null or not started:
		return {}
	if not _seat_ok(seat):
		return {}
	var counts := [0, 0, 0]
	for i in SEATS:
		counts[i] = (_game.hands[i] as Array).size()
	var lp: Dictionary = {}
	if not _game.last_play.is_empty():
		lp = {
			"seat": int(_game.last_play["seat"]),
			"cards": (_game.last_play["cards"] as Array).duplicate(),
			"info": (_game.last_play["info"] as Dictionary).duplicate(),
		}
	return {
		"seat": seat,
		"phase": int(_game.phase),
		"turn": int(_game.turn),
		"landlord": int(_game.landlord),
		"base_score": int(_game.base_score),
		"pass_streak": int(_game.pass_streak),
		"bombs": int(_game.bombs),
		"spring": bool(_game.spring),
		"winner": int(_game.winner),
		"multiplier": int(_game.multiplier()),
		"counts": counts,
		"passed": passed.duplicate(),
		"your_hand": (_game.hands[seat] as Array).duplicate(),
		"last_play": lp,
		"played": _game.played.duplicate(),
		# 定地主之前底牌不公开。
		"bottom": (_game.bottom.duplicate() if _game.landlord >= 0 else []),
		"log": events.slice(maxi(0, events.size() - LOG_TAIL)),
		"seats": _seat_public(),
	}


## 房主自己的视图，等价于 `snapshot_for(my_seat)`。
func host_self_snapshot() -> Dictionary:
	return snapshot_for(my_seat)


## 权威对局对象，供房主侧复盘、托管与自检使用。
## 不要把它或它的 `hands` 序列化下发，那等于公开整副牌。
func authoritative_game():
	return _game


## 心跳。
func touch(seat: int, now_ms: int) -> void:
	if not _seat_ok(seat):
		return
	seats[seat]["last_seen_ms"] = now_ms
	seats[seat]["online"] = true


## 网络层收到断线事件时调用。
func mark_offline(seat: int) -> void:
	if not _seat_ok(seat):
		return
	seats[seat]["online"] = false
	_push_log("%s 掉线。" % String(seats[seat]["name"]))


## 玩家回来了：解除托管，下一次轮到他时由本人出牌。
func reclaim(seat: int, now_ms: int = 0) -> void:
	if not _seat_ok(seat):
		return
	seats[seat]["online"] = true
	seats[seat]["last_seen_ms"] = now_ms
	if bool(seats[seat]["ai"]):
		seats[seat]["ai"] = false
		_push_log("%s 回到牌桌，解除托管。" % String(seats[seat]["name"]))


## 推进托管：心跳超时的座位交给 AI；轮到托管座位时自动出牌。
## 返回 `{"takeover": [seat...], "auto": [seat...], "events": [String...]}`。
func tick(now_ms: int) -> Dictionary:
	var took: Array = []
	var auto: Array = []
	if not started or _game == null:
		return {"takeover": took, "auto": auto, "events": []}
	for i in SEATS:
		if bool(seats[i]["online"]) or bool(seats[i]["ai"]):
			continue
		if now_ms - int(seats[i]["last_seen_ms"]) >= TAKEOVER_MS:
			seats[i]["ai"] = true
			took.append(i)
			_push_log("%s 掉线超时，由电脑托管。" % String(seats[i]["name"]))
	var steps := 0
	while not _game.is_over() and steps < MAX_AUTO_STEPS:
		var t := int(_game.turn)
		if not bool(seats[t]["ai"]):
			break
		var sig := _progress_sig()
		steps += 1
		auto.append(t)
		_auto_one_command(t)
		if _progress_sig() == sig and not _game.is_over():
			break
	return {"takeover": took, "auto": auto, "events": events.duplicate()}


# ---------------------------------------------------------------- 客户端侧

## 客户端入座。客户端只知道自己的座位号，不知道种子。
func client_setup(seat: int, my_name: String = "") -> void:
	role = Role.CLIENT
	my_seat = seat
	started = true
	view = {}
	events = []
	if my_name != "":
		seats = [{"name": my_name, "peer": NO_PEER, "online": true, "ai": false,
				"last_seen_ms": 0}]


## 用房主下发的快照覆盖本地视图。这是客户端唯一的数据来源。
func client_apply_snapshot(snap: Dictionary) -> void:
	view = snap.duplicate(true)
	if view.has("log"):
		events = []
		for line in view["log"]:
			events.append(String(line))


## 本地计算当前可出的牌。只用于界面提示，裁决始终在房主。
func client_legal_now() -> Array:
	if view.is_empty():
		return []
	var hand: Array = view.get("your_hand", [])
	var target: Dictionary = {}
	var lp: Dictionary = view.get("last_play", {})
	if not lp.is_empty() and int(lp.get("seat", -1)) != my_seat:
		target = lp.get("info", {})
	return P.candidates_for(hand, target)


func client_is_my_turn() -> bool:
	return not view.is_empty() and int(view.get("turn", -1)) == my_seat


## 构造一条发给房主的命令。房主会用连接身份覆盖其中的 `seat`。
func client_make_command(kind: int, payload: Dictionary = {}) -> Dictionary:
	var cmd := {"seat": my_seat, "kind": kind}
	cmd.merge(payload, true)
	return cmd


# ---------------------------------------------------------------- 传输辅助

## 负载转字节。用 `var_to_bytes` 而不是 JSON：JSON 会把整数变成浮点数。
## `bytes_to_var` 不会反序列化对象，可以安全处理不可信数据。
static func to_wire(d: Dictionary) -> PackedByteArray:
	return var_to_bytes(d)


## 字节转负载。空数据、截断数据、超长数据或非字典一律返回空字典。
static func from_wire(b: PackedByteArray) -> Dictionary:
	if b.size() < 4 or b.size() > MAX_WIRE_BYTES:
		return {}
	var v = bytes_to_var(b)
	return v if v is Dictionary else {}


## 泄漏检查用：递归收集负载中出现的全部整数。
## 用结构化遍历而不是字符串匹配，避免 "37" 误中 "137"。
static func collect_ints(d, out: Array = []) -> Array:
	match typeof(d):
		TYPE_INT:
			out.append(int(d))
		TYPE_FLOAT:
			out.append(int(d))
		TYPE_ARRAY:
			for x in d:
				collect_ints(x, out)
		TYPE_DICTIONARY:
			for k in d:
				collect_ints(d[k], out)
	return out


## 泄漏检查用：递归收集字典的全部键名，用于发现多出来的字段（例如 seed）。
static func collect_keys(d, out: Array = []) -> Array:
	match typeof(d):
		TYPE_DICTIONARY:
			for k in d:
				out.append(String(k))
				collect_keys(d[k], out)
		TYPE_ARRAY:
			for x in d:
				collect_keys(x, out)
	return out


# ---------------------------------------------------------------- 内部

## 校验命令的类型与取值。合法返回空字符串，否则返回拒绝原因。
## 规则层（`ddz_game`）还会校验回合、叫分范围、牌型与手牌归属，这里只挡格式问题。
func _validate(cmd: Dictionary) -> String:
	if typeof(cmd.get("seat")) != TYPE_INT or not _seat_ok(int(cmd["seat"])):
		return "座位越界"
	if typeof(cmd.get("kind")) != TYPE_INT or not Kind.values().has(int(cmd["kind"])):
		return "未知命令"
	match int(cmd["kind"]):
		Kind.BID:
			if typeof(cmd.get("score")) != TYPE_INT:
				return "叫分格式错误"
		Kind.PLAY:
			return _validate_cards(cmd.get("cards"))
		Kind.PING:
			if cmd.has("now_ms") and typeof(cmd["now_ms"]) != TYPE_INT:
				return "心跳格式错误"
	return ""


func _validate_cards(cards) -> String:
	if typeof(cards) != TYPE_ARRAY:
		return "出牌格式错误"
	var arr: Array = cards
	if arr.is_empty():
		return "没选牌"
	if arr.size() > MAX_PLAY_CARDS:
		return "出牌张数过多"
	var seen := {}
	for c in arr:
		if typeof(c) != TYPE_INT or int(c) < 0 or int(c) >= DECK_SIZE:
			return "牌 id 不合法"
		if seen.has(c):
			return "重复的牌"
		seen[c] = true
	return ""


## 内部派发，不检查「座位是否托管」。只供房主侧代码（托管）使用，不要接网络命令。
func _dispatch(seat: int, kind: int, cmd: Dictionary) -> Dictionary:
	match kind:
		Kind.BID:
			return _apply_bid(seat, int(cmd.get("score", 0)))
		Kind.PLAY:
			return _apply_play(seat, cmd.get("cards", []))
		Kind.PASS:
			return _apply_pass(seat)
	return _deny("未知命令 kind=%d" % kind)


## 「局面是否前进」的签名。只看 turn 不够：叫 3 分定地主时 turn 可能不变。
func _progress_sig() -> int:
	if _game == null:
		return 0
	return int(_game.phase) * 100000 + int(_game.turn) * 1000 \
			+ (_game.played as Array).size() * 10 + int(_game.pass_streak)


func _apply_bid(seat: int, score: int) -> Dictionary:
	var res: Dictionary = _game.bid(seat, score)
	if not bool(res.get("ok", false)):
		return _deny(String(res.get("reason", "叫分被拒")))
	_push_log("%s %s" % [_who(seat),
			("叫 %d 分" % score) if score > 0 else "不叫"])
	if bool(res.get("done", false)):
		passed = [false, false, false]
		_push_log("地主 = %s" % _who(int(_game.landlord)))
	return {"ok": true, "reason": "", "result": res}


func _apply_play(seat: int, cards: Array) -> Dictionary:
	var res: Dictionary = _game.play(seat, cards)
	if not bool(res.get("ok", false)):
		return _deny(String(res.get("reason", "出牌被拒")))
	passed[seat] = false          # 出了牌 ⇒ 这一家的「不要」标记清掉
	_push_log("%s 出牌" % _who(seat))
	if bool(res.get("over", false)):
		_push_log("对局结束，%s 获胜。" % _who(int(_game.winner)))
	return {"ok": true, "reason": "", "result": res}


func _apply_pass(seat: int) -> Dictionary:
	# ⚠️ 先记下过牌前的手数：`pass_turn()` 在「其余两家都过」时会把 streak 归零并重开一轮。
	var streak_before := int(_game.pass_streak)
	var res: Dictionary = _game.pass_turn(seat)
	if not bool(res.get("ok", false)):
		return _deny(String(res.get("reason", "过牌被拒")))
	passed[seat] = true
	if streak_before >= SEATS - 2 and int(_game.pass_streak) == 0:
		# 重新开轮 ⇒ 三家的「不要」标记一起清掉
		passed = [false, false, false]
	_push_log("%s 过牌" % _who(seat))
	return {"ok": true, "reason": "", "result": res}


## 托管座位自动走一步（叫分 / 出牌 / 过牌）。
## 走 `_dispatch()` 而不是 `apply_command()`，否则会被「该座位已交给托管」拒掉。
func _auto_one_command(seat: int) -> void:
	if int(_game.phase) == int(G.Phase.BID):
		_dispatch(seat, Kind.BID, {"score": AI.bid_score(_game, seat)})
		return
	var mv: Dictionary = AI.choose(_game, seat)
	if not bool(mv.get("pass", false)):
		var r: Dictionary = _dispatch(seat, Kind.PLAY, {"cards": mv.get("cards", [])})
		if bool(r.get("ok", false)):
			return
	# 压不过，或 AI 给的牌被判非法：过牌。
	var rp: Dictionary = _dispatch(seat, Kind.PASS, {})
	if bool(rp.get("ok", false)):
		return
	# 新一轮不能过牌：出最小的一张，避免牌局卡在托管座位上。
	var hand: Array = _game.hand_of(seat)
	if not hand.is_empty():
		_dispatch(seat, Kind.PLAY, {"cards": [int(hand[0])]})


## 日志中的称呼。托管中的座位会标注出来。
func _who(seat: int) -> String:
	if not _seat_ok(seat):
		return "座位%d" % seat
	var n := String(seats[seat]["name"])
	return n + "（托管）" if bool(seats[seat]["ai"]) else n


func _seat_public() -> Array:
	var out: Array = []
	for i in SEATS:
		out.append({
			"name": String(seats[i]["name"]),
			"online": bool(seats[i]["online"]),
			"ai": bool(seats[i]["ai"]),
		})
	return out


func _seat_ok(seat: int) -> bool:
	return seat >= 0 and seat < SEATS and seat < seats.size()


func _push_log(line: String) -> void:
	events.append(line)


func _deny(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "result": {}}
