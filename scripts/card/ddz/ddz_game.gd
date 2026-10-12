extends RefCounted
## 斗地主 · 对局状态机（**纯逻辑，无 UI / 无时间**）。
##
## ★ 用法：`g.start(seed)` → 循环 `bid/play/pass` → `g.phase == OVER`。
##   驱动层（UI 或自动对战脚本）只负责「谁该动」，规则全在这里。
##
## ⚠️ 洗牌用**显式 seed**，⛔ 不用全局 `randi()` —— 两个客户端要能发出同一副牌。
##    （2026-10-06 定的硬约束，将来接 P2P 时只需同步 seed + 动作序列。）

const R := preload("res://scripts/card/ddz/ddz_rules.gd")
const P := preload("res://scripts/card/ddz/ddz_plays.gd")

enum Phase { BID, PLAY, OVER }
## BID 阶段的两步：先「叫地主」（随机起点按序），有人叫了才进「抢地主」。
enum BidStage { CALL, GRAB }

const SEATS := 3
const HAND_SIZE := 17
const BOTTOM_SIZE := 3
## ★ 流局重发的防爆上限：连续这么多次「三家都不叫」后，强制让起点座位当地主。
##   （三家全不叫的概率本来就极低，这个兜底只为「绝不死循环」。）
const MAX_REDEALS := 5

var hands: Array = [[], [], []]        ## 三家手牌（牌 id 数组）
var bottom: Array = []                 ## 底牌（叫完地主才翻开并归地主）
var phase := Phase.BID
var landlord := -1                     ## 地主座位（-1 = 未定）
var turn := 0                          ## 当前该谁动
var last_play: Dictionary = {}         ## {"seat": int, "cards": Array, "info": Dictionary}
var pass_streak := 0                   ## 连续过牌数；满 2 ⇒ 重新开轮
## ══ 抢地主（BID 阶段）══ 规则（用户 2026-10-12 定稿）：
##   ① 随机起点按序「叫地主」，**全不叫 = 流局重新发牌**；
##   ② 有人叫后进「抢」：问询队列 = 叫者的下家→再下家（**剔除叫阶段弃权者**），
##      走完后若有人抢过，再把**叫者**排到队尾问一次（= 反抢）；
##      ⛔ 一圈制：每人最多一次表态，不是循环抢；
##   ③ **最后抢的人当地主**；没人抢 = 叫者当地主；
##   ④ 每抢一次基础倍数 ×2（base_score = 2^grabs）。
var bid_stage := BidStage.CALL
var claimant := -1                     ## 当前叫/抢到的人（-1 = 还没有人）
var grabs := 0                         ## 抢的次数
var bid_pass := [false, false, false]  ## 叫阶段「不叫」= 弃权 ⇒ 抢阶段没资格
var bid_asked := [false, false, false] ## 叫阶段是否已被问过（走轮用）
var ask_queue: Array = []              ## 抢阶段的问询队列（座位号）
var ask_idx := 0
var _opener := -1                      ## 最初的叫者
var _opener_asked := false             ## 叫者的反抢问过没有
var bid_starter := -1                  ## 本局叫地主的起点座位（随机派生）
var redeals := 0                       ## 流局重发次数
var winner := -1
var base_score := 1                    ## 倍数基数（抢地主制：2^抢的次数）
var log_lines: Array[String] = []      ## 人读的对局记录（验证/调试用）
## ★ 已打出的牌（三家合计）—— **公开信息**，`ddz_eval` 的记牌器靠它算「外面还剩什么」。
## ⚠️ 底牌不算「打出」（它归地主手里）；叫完地主后底牌是公开的，但仍在某人手上。
var played: Array = []
## ★ 2026-10-06 倍数记账（娱乐币结算用）—— 依据参考图：**结算 = 底分 × 倍数**。
##   倍数 = 2^(炸弹+王炸个数) × (春天 ? 2 : 1)
##   ⚠️ 只统计**打出去的**炸弹（手里捏着不算）—— 否则玩家会为了倍数不敢留炸。
var bombs := 0
var spring := false
var farmer_plays := 0                  ## 两个农民累计出牌次数（判春天用）


## 开一局：洗牌 + 发牌 + **随机起点**叫地主。
func start(seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	# ★ 显式 seed —— 同一 seed 必然发到同一副牌（P2P 的同步基础）
	rng.seed = seed_value
	var deck: Array = R.full_deck()
	for i in range(deck.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = deck[i]
		deck[i] = deck[j]
		deck[j] = t
	hands = [[], [], []]
	for s in SEATS:
		hands[s] = deck.slice(s * HAND_SIZE, s * HAND_SIZE + HAND_SIZE)
		bottom = deck.slice(SEATS * HAND_SIZE, SEATS * HAND_SIZE + BOTTOM_SIZE)
	for s in SEATS:
		(hands[s] as Array).sort()
	phase = Phase.BID
	landlord = -1
	# ★★ 叫地主的起点**随机**（2026-10-12 用户定稿）：但必须从**发牌 rng** 派生 ——
	#    同一 seed 连「谁先叫」都可复现（⛔ 绝不碰全局 randf/randi，那会破坏确定性）。
	turn = rng.randi_range(0, SEATS - 1)
	bid_starter = int(turn)
	last_play = {}
	pass_streak = 0
	bid_stage = BidStage.CALL
	claimant = -1
	grabs = 0
	bid_pass = [false, false, false]
	bid_asked = [false, false, false]
	ask_queue = []
	ask_idx = 0
	_opener = -1
	_opener_asked = false
	redeals = 0
	winner = -1
	base_score = 1
	played = []
	bombs = 0
	spring = false
	farmer_plays = 0
	log_lines = []
	log_lines.append("发牌（seed=%d）" % seed_value)
	log_lines.append("叫地主起点 = 座位 %d" % int(turn))


## 叫/抢地主。`grab` = true 表示「叫地主 / 抢地主」，false = 「不叫 / 不抢」。
##
## 返回 `{"ok", "reason", "done"(本阶段是否收口), "redeal"(需要流局重发)}`。
## ⛔ 轮次强校验保留（`seat != turn` 拒绝）—— 联机时命令来自客户端，不能信。
func bid(seat: int, grab: bool) -> Dictionary:
	if phase != Phase.BID:
		return _deny("不在叫/抢地主阶段")
	if seat != turn:
		return _deny("还没轮到你")
	if bid_stage == BidStage.CALL:
		return _bid_call(seat, grab)
	return _bid_grab(seat, grab)


## ── 第一步：叫地主（随机起点按序，每人一次；全不叫 = 流局）──
func _bid_call(seat: int, want: bool) -> Dictionary:
	bid_asked[seat] = true
	if want:
		claimant = seat
		_opener = seat
		log_lines.append("座位 %d 叫地主" % seat)
		_enter_grab()
		return _advance_grab()
	bid_pass[seat] = true
	log_lines.append("座位 %d 不叫" % seat)
	var nxt := _next_call_seat((seat + 1) % SEATS)
	if nxt < 0:
		# ⛔ 防爆兜底（实际到不了）：连续 MAX_REDEALS 次流局后不再重发，
		#   让本局**起点座位**直接当地主（底分 1）—— 规则让位于「绝不死循环」。
		if redeals >= MAX_REDEALS:
			claimant = bid_starter
			grabs = 0
			log_lines.append("连续 %d 次流局 ⇒ 兜底：座位 %d 当地主" % [redeals, bid_starter])
			_decide_landlord()
			return {"ok": true, "reason": "", "done": true, "redeal": false}
		# ★ 标准：三家都不叫 = 流局重新发牌（2026-10-12 用户定稿；旧版是座位 0 兜底）
		redeals += 1
		log_lines.append("三家都不叫 ⇒ 流局，重新发牌（第 %d 次）" % redeals)
		return {"ok": true, "reason": "", "done": true, "redeal": true}
	turn = nxt
	return {"ok": true, "reason": "", "done": false, "redeal": false}


## 叫阶段还没被问过的下一个座位（-1 = 全问过了）。
func _next_call_seat(from: int) -> int:
	for k in SEATS:
		var s := (from + k) % SEATS
		if not bool(bid_asked[s]):
			return s
	return -1


## ── 第二步：抢地主。建问询队列：叫者的下家→再下家，**剔除叫阶段弃权者**。──
func _enter_grab() -> void:
	bid_stage = BidStage.GRAB
	ask_queue = []
	for k in range(1, SEATS):
		var s := (_opener + k) % SEATS
		# ★「不叫」等于放弃：叫阶段弃权的人**没有抢的资格**（用户定稿的关键细节）
		if not bool(bid_pass[s]):
			ask_queue.append(s)
	ask_idx = 0
	_opener_asked = false


func _bid_grab(seat: int, want: bool) -> Dictionary:
	if want:
		claimant = seat
		grabs += 1
		log_lines.append("座位 %d 抢地主（第 %d 抢）" % [seat, grabs])
	else:
		log_lines.append("座位 %d 不抢" % seat)
	ask_idx += 1
	return _advance_grab()


## 推进抢阶段。★ 反抢是**懒追加**的：只有真有人抢过，才把叫者排到队尾问一次
##   （没人抢时多问叫者一次毫无意义 —— 他已经是地主了）。
func _advance_grab() -> Dictionary:
	if ask_idx < ask_queue.size():
		turn = int(ask_queue[ask_idx])
		return {"ok": true, "reason": "", "done": false, "redeal": false}
	if grabs > 0 and not _opener_asked:
		_opener_asked = true
		ask_queue.append(_opener)
		turn = _opener
		return {"ok": true, "reason": "", "done": false, "redeal": false}
	_decide_landlord()
	return {"ok": true, "reason": "", "done": true, "redeal": false}


func _decide_landlord() -> void:
	landlord = claimant
	(hands[landlord] as Array).append_array(bottom)
	(hands[landlord] as Array).sort()
	phase = Phase.PLAY
	turn = landlord
	last_play = {}
	pass_streak = 0
	# ★ 抢地主制的基础分：**每抢一次 ×2**（没人抢 = 1）。结算公式（底分 × 倍数）不变。
	base_score = 1 << grabs
	# 出牌阶段才开始数炸弹；底牌的 3 张不算"打过"
	bombs = 0
	farmer_plays = 0
	spring = false
	log_lines.append("地主 = 座位 %d（抢 %d 次，底分 %d），底牌 %s" % [landlord,
			grabs, base_score,
			", ".join(bottom.map(func(c): return R.label_of(int(c))))])


## 出牌。`cards` = 牌 id 数组。
func play(seat: int, cards: Array) -> Dictionary:
	if phase != Phase.PLAY:
		return _deny("不在出牌阶段")
	if seat != turn:
		return _deny("还没轮到你")
	if cards.is_empty():
		return _deny("没选牌")
	var info := R.classify(cards)
	if info.is_empty():
		return _deny("不是合法牌型")
	if not _owns(seat, cards):
		return _deny("手里没有这些牌")
	if not last_play.is_empty():
		if not R.beats(info, last_play["info"]):
			return _deny("压不过上一手")
	_remove(seat, cards)
	played.append_array(cards)
	# ★ 倍数记账：炸弹/王炸翻倍；农民出过牌就不算春天
	var t_now := int(info.get("type", 0))
	if t_now == 13 or t_now == 14:
		bombs += 1
	if seat != landlord:
		farmer_plays += 1
	last_play = {"seat": seat, "cards": cards.duplicate(), "info": info}
	pass_streak = 0
	log_lines.append("座位 %d 出 %s（%s）" % [seat, _cards_text(cards), _type_text(info)])
	if (hands[seat] as Array).is_empty():
		winner = seat
		phase = Phase.OVER
		# 春天：地主赢，且两个农民**一张牌都没出过**（他们的手牌还是 17 张）
		spring = (seat == landlord) and farmer_plays == 0
		log_lines.append("座位 %d 走完了 —— %s 胜" % [seat, "地主" if seat == landlord else "农民"])
		return {"ok": true, "reason": "", "over": true}
	turn = (seat + 1) % SEATS
	return {"ok": true, "reason": "", "over": false}


## 过牌。新一轮的第一手不能过。
##
## ⚠️ 函数名是 `pass_turn` 而不是 `pass` —— `pass` 是 GDScript **保留字**，
##    拿它当函数名直接解析失败（`Expected function name after "func"`）。
func pass_turn(seat: int) -> Dictionary:
	if phase != Phase.PLAY:
		return _deny("不在出牌阶段")
	if seat != turn:
		return _deny("还没轮到你")
	if last_play.is_empty():
		return _deny("新一轮不能过牌（必须先出）")
	pass_streak += 1
	log_lines.append("座位 %d 过" % seat)
	if pass_streak >= SEATS - 1:
		# 其余两家都过 ⇒ 回到出牌者，重新开轮（他可以随意出）
		turn = int(last_play["seat"])
		last_play = {}
		pass_streak = 0
		log_lines.append("—— 重新开轮，座位 %d 出牌" % turn)
		return {"ok": true, "reason": "", "over": false}
	turn = (seat + 1) % SEATS
	return {"ok": true, "reason": "", "over": false}


# ------------------------------------------------------------------ 查询

func hand_of(seat: int) -> Array:
	return hands[seat]


## 已打出的牌（三家合计，公开信息）。给记牌器用。
func played_ids() -> Array:
	return played


## 当前该座位可以出的全部候选（跟牌时只给「压得过」的）。
func legal_now(seat: int) -> Array:
	var target := {}
	if not last_play.is_empty() and int(last_play["seat"]) != seat:
		target = last_play["info"]
	return P.candidates_for(hands[seat], target)


func is_over() -> bool:
	return phase == Phase.OVER


## 本局倍数。★ 结算公式 = 底分 × 倍数 × 单位（见 `ddz_table` 的 `_settle()`）。
func multiplier() -> int:
	return int(pow(2.0, float(bombs))) * (2 if spring else 1)


func landlord_won() -> bool:
	return winner >= 0 and winner == landlord


func _owns(seat: int, cards: Array) -> bool:
	var h: Array = (hands[seat] as Array).duplicate()
	for c in cards:
		var idx := h.find(int(c))
		if idx < 0:
			return false
		h.remove_at(idx)
	return true


func _remove(seat: int, cards: Array) -> void:
	var h: Array = hands[seat]
	for c in cards:
		var idx := h.find(int(c))
		if idx >= 0:
			h.remove_at(idx)


func _deny(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}


func _cards_text(cards: Array) -> String:
	var parts: Array[String] = []
	for c in cards:
		parts.append(R.label_of(int(c)))
	return " ".join(parts)


func _type_text(info: Dictionary) -> String:
	# ⚠️ 走 `R.type_name()`，⛔ 本文件不再自带一份名字表 ——
	#    牌桌也要显示牌型，两份表迟早会分叉（日志写「顺子」、界面写「非法」）。
	return R.type_name(int(info.get("type", 0)))
