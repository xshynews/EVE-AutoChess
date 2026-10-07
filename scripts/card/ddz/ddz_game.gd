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

const SEATS := 3
const HAND_SIZE := 17
const BOTTOM_SIZE := 3

var hands: Array = [[], [], []]        ## 三家手牌（牌 id 数组）
var bottom: Array = []                 ## 底牌（叫完地主才翻开并归地主）
var phase := Phase.BID
var landlord := -1                     ## 地主座位（-1 = 未定）
var turn := 0                          ## 当前该谁动
var last_play: Dictionary = {}         ## {"seat": int, "cards": Array, "info": Dictionary}
var pass_streak := 0                   ## 连续过牌数；满 2 ⇒ 重新开轮
var bid_best := -1                     ## 当前最高叫分
var bid_seat := -1
var winner := -1
var base_score := 1                    ## 叫分（倍数基数）
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


## 开一局：洗牌 + 发牌 + 定座位 0 先叫。
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
	turn = 0
	last_play = {}
	pass_streak = 0
	bid_best = -1
	bid_seat = -1
	winner = -1
	base_score = 1
	played = []
	bombs = 0
	spring = false
	farmer_plays = 0
	log_lines = []
	log_lines.append("发牌（seed=%d）" % seed_value)


## 叫分（0 = 不叫，1~3 = 叫几分）。返回 {"ok": bool, "reason": String}。
func bid(seat: int, score: int) -> Dictionary:
	if phase != Phase.BID:
		return _deny("不在叫分阶段")
	if seat != turn:
		return _deny("还没轮到你")
	if score != 0 and score <= bid_best:
		return _deny("叫分必须高于当前最高分")
	if score > 0:
		bid_best = score
		bid_seat = seat
		base_score = score
		log_lines.append("座位 %d 叫 %d 分" % [seat, score])
	else:
		log_lines.append("座位 %d 不叫" % seat)
	# 3 分直接定；或者转完一圈有人叫过就定
	if bid_best == 3 or (seat == SEATS - 1 and bid_seat >= 0):
		_landlord_decided()
		return {"ok": true, "reason": "", "done": true}
	if seat == SEATS - 1:
		# 三家都不叫 ⇒ 座位 0 兜底当地主（不重发，避免驱动层陷入死循环）
		bid_seat = 0
		base_score = 1
		log_lines.append("三家不叫 ⇒ 座位 0 兜底当地主")
		_landlord_decided()
		return {"ok": true, "reason": "", "done": true}
	turn = (seat + 1) % SEATS
	return {"ok": true, "reason": "", "done": false}


func _landlord_decided() -> void:
	landlord = bid_seat
	(hands[landlord] as Array).append_array(bottom)
	(hands[landlord] as Array).sort()
	phase = Phase.PLAY
	turn = landlord
	last_play = {}
	pass_streak = 0
	# 出牌阶段才开始数炸弹；底牌的 3 张不算"打过"
	bombs = 0
	farmer_plays = 0
	spring = false
	log_lines.append("地主 = 座位 %d，底牌 %s" % [landlord,
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
