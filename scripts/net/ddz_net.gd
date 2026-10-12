extends RefCounted
## 斗地主 · 联机会话层（**房主权威**）。纯逻辑：⛔ 不碰 UI、⛔ 不碰任何网络 API。
##
## 配套设计：`F:\EVE自走棋\牌面\牌面\联机方案-内置EasyTier-工程设计-2026-10-12.md`
##
## 四条硬约束（2026-10-12）：
##  ① **真相只在房主**：局面由房主的 `ddz_game` 独家持有；客户端**只有**一份裁剪过的
##     `view` 字典，⛔ 不建本地对局（建了就等于拿到整副牌）。
##  ② ★★ **手牌隔离**：下发给某座位的负载里**只含他自己的手牌**。
##  ③ ★★ **种子绝不外发**：谁拿到 seed 谁就能重算整副牌 ⇒ 等于看穿所有人手牌。
##     seed 只留房主侧（复盘 / 断线托管 / 审计）。⚠️ 注意 `ddz_game` 的
##     `log_lines[0]` 是「发牌（seed=N）」—— 所以本层**另建公开日志 `events`**，
##     ⛔ 绝不转发 `_game.log_lines`。
##  ④ 负载**全 JSON 安全**（只含 int/bool/String/Array/Dictionary）⇒ 可直接
##     `JSON.stringify()` / `var_to_bytes()` 丢给任意传输层。
##
## ⚠️ 为什么是「按座位裁剪的快照」而不是「增量」：一副牌的状态极小（≤54 个 int），
##    每次全量下发比维护增量更省事、且**不可能失步**（增量丢一包就永久歪）。
##
## ⚠️ `ddz_game.gd` **本层完全不动** —— 它已经是命令式 API（`bid/play/pass_turn`
##    + 查询），再包一层 `apply_command` 只是把「命令 → 方法」的翻译集中到一处，
##    本地玩家与远端玩家因此走**同一条路径**。

const G := preload("res://scripts/card/ddz/ddz_game.gd")
const AI := preload("res://scripts/card/ddz/ddz_ai.gd")
const P := preload("res://scripts/card/ddz/ddz_plays.gd")

enum Role { HOST, CLIENT }

## 命令种类。网络层只需把 `{"seat": int, "kind": Kind, ...}` 原样搬过来。
enum Kind { BID, PLAY, PASS, PING }

const SEATS := 3
## 心跳间隔与托管阈值（毫秒）。⚠️ 由驱动层把「当前毫秒」传进来，本层不读时钟
## —— 无头验收才好控制（⛔ 不用 `Time.get_ticks_msec()` 埋在逻辑里）。
const HEARTBEAT_MS := 10000
const TAKEOVER_MS := 20000
## 客户端保留的公开日志行数
const LOG_TAIL := 12
## 单次 `tick()` 最多自动推进多少步（防托管三连时死循环）
const MAX_AUTO_STEPS := 64

var role := Role.HOST
var my_seat := 0
## 座位表：[{"name":String, "peer":int, "online":bool, "ai":bool, "last_seen_ms":int}]
var seats: Array = []
var started := false
## 客户端侧的唯一真源（裁剪过的快照）；房主侧不用它
var view: Dictionary = {}
## ★ 公开日志（本层自建）。⛔ 不转发 `_game.log_lines`（首行含 seed）。
var events: Array[String] = []

## ⚠️ 动态类型：`preload(...).new()` 推不出类型，用 `:=` 会报错。
var _game = null


# ══════════════════════════════════════════════════════════════ 房主侧

## 房主开房：登记三个座位的名字。`names[i]` 缺省用「座位 i」。
func host_setup(names: Array = []) -> void:
	role = Role.HOST
	my_seat = 0
	seats = []
	for i in SEATS:
		seats.append({
			"name": String(names[i]) if i < names.size() else "座位%d" % i,
			"peer": i,
			"online": true,
			"ai": false,
			"last_seen_ms": 0,
		})
	_game = null
	started = false
	events = []
	view = {}


## 房主开局。★ `seed_value` 只进 `_game`，**不进任何下发负载**。
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
	_push_log("发牌完成。牌局由房主裁定（发牌种子不下发）。")
	return {"ok": true, "reason": ""}


## 统一命令入口 —— 本地玩家与远端玩家都走这里。
##
## `cmd` = `{"seat": int, "kind": Kind, "score": int, "cards": Array, "now_ms": int}`
## 返回 `{"ok": bool, "reason": String, "result": Dictionary}`
func apply_command(cmd: Dictionary) -> Dictionary:
	if role != Role.HOST:
		return _deny("客户端不裁决（房主权威）")
	if _game == null or not started:
		return _deny("尚未开局")
	var seat := int(cmd.get("seat", -1))
	if seat < 0 or seat >= SEATS:
		return _deny("座位越界")
	var kind := int(cmd.get("kind", -1))
	if kind == Kind.PING:
		touch(seat, int(cmd.get("now_ms", 0)))
		return {"ok": true, "reason": "", "result": {}}
	if bool(seats[seat]["ai"]):
		# 托管中的座位不接受**真人**命令（防掉线玩家与 AI 抢着出牌）。
		# ⚠️ 托管自己出牌走 `_dispatch()`（内部通道），⛔ 不能再走这道闸 ——
		#    否则 AI 会把自己的命令挡掉（实测踩过：turn 永远停在托管座位）。
		# 玩家重连时先 `reclaim(seat)`。
		return _deny("该座位已交给托管")
	return _dispatch(seat, kind, cmd)


## 内部派发：**没有**「托管座位不许操作」那道闸。
## ⛔ 只给房主自己的代码用（`tick` 里的托管）；⛔ 别拿它接网络来的命令。
func _dispatch(seat: int, kind: int, cmd: Dictionary) -> Dictionary:
	match kind:
		Kind.BID:
			return _apply_bid(seat, int(cmd.get("score", 0)))
		Kind.PLAY:
			return _apply_play(seat, cmd.get("cards", []))
		Kind.PASS:
			return _apply_pass(seat)
	return _deny("未知命令 kind=%d" % kind)


## ★ 按座位裁剪的快照 —— **下发给客户端的就是这一份**，别的东西一律不下发。
func snapshot_for(seat: int) -> Dictionary:
	if role != Role.HOST or _game == null or not started:
		return {}
	if seat < 0 or seat >= SEATS:
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
		# ★★ 只有他自己的手牌
		"your_hand": (_game.hands[seat] as Array).duplicate(),
		"last_play": lp,
		"played": _game.played.duplicate(),
		# 亮底前是空数组（⛔ 别提前泄露底牌）
		"bottom": (_game.bottom.duplicate() if _game.landlord >= 0 else []),
		"log": events.slice(maxi(0, events.size() - LOG_TAIL)),
		"seats": _seat_public(),
	}


## 房主给自己看的那份（等价于 `snapshot_for(my_seat)`，语义更清楚）。
func host_self_snapshot() -> Dictionary:
	return snapshot_for(my_seat)


## 权威对局对象（房主侧：复盘 / 断线托管 / 自检用）。
##
## ⛔⛔ **绝不把它、或它的 `hands`，序列化下发给任何人** —— 那等于把整副牌送出去。
##     自检（`verify_ddz_net`）靠它算出「哪些牌是别人不该看到的」来做泄漏断言。
func authoritative_game():
	return _game


## 心跳。`now_ms` 由驱动层给（本层不读时钟）。
func touch(seat: int, now_ms: int) -> void:
	if seat < 0 or seat >= SEATS:
		return
	seats[seat]["last_seen_ms"] = now_ms
	seats[seat]["online"] = true


## 掉线（网络层收到断线事件时调）。
func mark_offline(seat: int) -> void:
	if seat < 0 or seat >= SEATS:
		return
	seats[seat]["online"] = false
	_push_log("%s 掉线。" % String(seats[seat]["name"]))


## 玩家回来了：解除托管（下一个轮到他时由他本人出牌）。
func reclaim(seat: int, now_ms: int = 0) -> void:
	if seat < 0 or seat >= SEATS:
		return
	seats[seat]["online"] = true
	seats[seat]["last_seen_ms"] = now_ms
	if bool(seats[seat]["ai"]):
		seats[seat]["ai"] = false
		_push_log("%s 回到牌桌，解除托管。" % String(seats[seat]["name"]))


## 推进「托管」：心跳超时 ⇒ 交给 AI；托管座位轮到自己就自动出牌。
##
## 返回 `{"takeover": [seat...], "auto": [seat...], "events": [str...]}`
func tick(now_ms: int) -> Dictionary:
	var took: Array = []
	var auto: Array = []
	if not started or _game == null:
		return {"takeover": took, "auto": auto, "events": []}
	for i in SEATS:
		if bool(seats[i]["online"]):
			continue
		if bool(seats[i]["ai"]):
			continue
		if now_ms - int(seats[i]["last_seen_ms"]) >= TAKEOVER_MS:
			seats[i]["ai"] = true
			took.append(i)
			_push_log("%s 掉线超时 ⇒ 由电脑托管。" % String(seats[i]["name"]))
	# 托管座位轮到就自动打（一局里可能连着几个托管座位）
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
			# 一步都推不动 ⇒ 立刻停，别空转到上限
			# （⚠️ 不能用「turn 有没有变」当信号：叫 3 分定地主时 turn 可能不变）
			break
	return {"takeover": took, "auto": auto, "events": events.duplicate()}


## 「局面往前走了没有」的信号。用 phase/turn/已出牌数/过牌计数组合 ——
## 单看 turn 会漏掉「叫分定地主后 turn 不变」这种情况。
func _progress_sig() -> int:
	if _game == null:
		return 0
	return int(_game.phase) * 100000 + int(_game.turn) * 1000 \
			+ (_game.played as Array).size() * 10 + int(_game.pass_streak)


# ══════════════════════════════════════════════════════════════ 客户端侧

## 客户端入座。⚠️ 只有座位号，**没有** seed。
func client_setup(seat: int, my_name: String = "") -> void:
	role = Role.CLIENT
	my_seat = seat
	started = true
	view = {}
	events = []
	if my_name != "":
		seats = [{"name": my_name, "peer": seat, "online": true, "ai": false,
				"last_seen_ms": 0}]


## 收到房主下发的快照 ⇒ 覆盖本地视图。
## ★★ 这是客户端**唯一**的数据来源；⛔ 不要在这里偷偷建本地 `ddz_game`。
func client_apply_snapshot(snap: Dictionary) -> void:
	view = snap.duplicate(true)
	if view.has("log"):
		events = []
		for line in view["log"]:
			events.append(String(line))


## 客户端本地算「我现在能出哪些牌」—— **只为 UI 置灰/提示**，⛔ 不是裁决依据
## （裁决永远在房主；客户端算错最多是按钮灰错，不会改变局面）。
func client_legal_now() -> Array:
	if view.is_empty():
		return []
	var hand: Array = view.get("your_hand", [])
	var target: Dictionary = {}
	var lp: Dictionary = view.get("last_play", {})
	if not lp.is_empty() and int(lp.get("seat", -1)) != my_seat:
		target = lp.get("info", {})
	return P.candidates_for(hand, target)


## 现在轮到我了吗。
func client_is_my_turn() -> bool:
	return not view.is_empty() and int(view.get("turn", -1)) == my_seat


## 客户端构造一条命令（交给网络层发给房主）。
func client_make_command(kind: int, payload: Dictionary = {}) -> Dictionary:
	var cmd := {"seat": my_seat, "kind": kind}
	cmd.merge(payload, true)
	return cmd


# ══════════════════════════════════════════════════════════════ 传输辅助

## 负载 → 字节（`var_to_bytes` 保留 int/bool 类型；⛔ 别用 JSON —— JSON 会把
## 所有数字变 float，`your_hand` 里的牌 id 回来就成 5.0 了）。
static func to_wire(d: Dictionary) -> PackedByteArray:
	return var_to_bytes(d)


static func from_wire(b: PackedByteArray) -> Dictionary:
	# ⚠️ 空字节 / 半截数据不能让引擎抛 `decode_variant` 错误（实测会打 ERROR 日志）。
	if b.size() < 4:
		return {}
	var v = bytes_to_var(b)
	return v if v is Dictionary else {}


## 给泄漏检查用：把负载**递归**摊平成「出现过的全部整数」。
## ⚠️ 刻意不做字符串子串匹配（`"37"` 会撞上 `"137"`）—— 结构化遍历才是准的。
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


## 给泄漏检查用：摊平字典的**键名**（抓「偷偷塞了 seed 字段」这类问题）。
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


# ══════════════════════════════════════════════════════════════ 内部

func _apply_bid(seat: int, score: int) -> Dictionary:
	var res: Dictionary = _game.bid(seat, score)
	if not bool(res.get("ok", false)):
		return _deny(String(res.get("reason", "叫分被拒")))
	_push_log("%s %s" % [_who(seat),
			("叫 %d 分" % score) if score > 0 else "不叫"])
	if bool(res.get("done", false)):
		_push_log("地主 = %s" % _who(int(_game.landlord)))
	return {"ok": true, "reason": "", "result": res}


func _apply_play(seat: int, cards: Array) -> Dictionary:
	var res: Dictionary = _game.play(seat, cards)
	if not bool(res.get("ok", false)):
		return _deny(String(res.get("reason", "出牌被拒")))
	_push_log("%s 出牌" % _who(seat))
	if bool(res.get("over", false)):
		_push_log("对局结束，%s 获胜。" % _who(int(_game.winner)))
	return {"ok": true, "reason": "", "result": res}


func _apply_pass(seat: int) -> Dictionary:
	var res: Dictionary = _game.pass_turn(seat)
	if not bool(res.get("ok", false)):
		return _deny(String(res.get("reason", "过牌被拒")))
	_push_log("%s 过牌" % _who(seat))
	return {"ok": true, "reason": "", "result": res}


## 托管座位自动走一步（叫分 / 出牌 / 过牌）。
##
## ⚠️ 走 `_dispatch()`（内部通道），⛔ 不走 `apply_command()` —— 后者会以
##    「该座位已交给托管」为由把 AI 自己的命令拒掉。
func _auto_one_command(seat: int) -> void:
	if int(_game.phase) == int(G.Phase.BID):
		_dispatch(seat, Kind.BID, {"score": AI.bid_score(_game, seat)})
		return
	var mv: Dictionary = AI.choose(_game, seat)
	if not bool(mv.get("pass", false)):
		var r: Dictionary = _dispatch(seat, Kind.PLAY, {"cards": mv.get("cards", [])})
		if bool(r.get("ok", false)):
			return
	# 压不过 / AI 给的牌被判非法 ⇒ 过牌
	var rp: Dictionary = _dispatch(seat, Kind.PASS, {})
	if bool(rp.get("ok", false)):
		return
	# 新一轮不能过 ⇒ 兜底出最小一张（⛔ 别把牌局卡死在托管座位上）
	var hand: Array = _game.hand_of(seat)
	if not hand.is_empty():
		_dispatch(seat, Kind.PLAY, {"cards": [int(hand[0])]})


## 日志里的称呼。托管中的座位显式标出，免得玩家以为对面在正常操作。
func _who(seat: int) -> String:
	var n := String(seats[seat]["name"])
	if seat >= 0 and seat < SEATS and bool(seats[seat]["ai"]):
		return n + "（托管）"
	return n


func _seat_public() -> Array:
	var out: Array = []
	for i in SEATS:
		out.append({
			"name": String(seats[i]["name"]),
			"online": bool(seats[i]["online"]),
			"ai": bool(seats[i]["ai"]),
		})
	return out


func _push_log(line: String) -> void:
	events.append(line)


func _deny(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "result": {}}
