extends RefCounted
## 斗地主 · AI 决策（**纯函数：给定局面返回一手牌**）。
##
## ## 三档的来历（2026-10-06 查资料后重写）
##   L1 贪心 —— 能压就压最小的。**只够跑通**。
##   L2 不拆炸弹 + 农民不压队友 + 主动出小牌。← 上一版。**实测偏弱**：
##      200 局地主胜率 64.5%（真实约 45~55%），也就是两个农民加起来打不过地主。
##   L3 = 本版：**手数评估 + 记牌 + 农民配合 + 残局规则**。
##
## ## L3 每条改动的依据 + 实测（同牌身份互换对打 L2，样本 200 副）
## | 改动 | 依据 | 实测 |
## |---|---|---|
## | **手数**（这手牌几手能出完）决定出牌 | PerfectDou(NeurIPS 2022) 的 node reward 就是「地主最少几步出完」 | 整体 64% |
## | **记牌器**（已出的牌 → 外面还剩什么） | 源码实战文：「有没有这个逻辑，AI 强度完全是两个档次」 | 含在上面 |
## | **别拆结构**（拆对子/三张/炸弹出单张要扣分） | 同上：拆错一次就可能输掉整局 | 含在上面 |
## | **农民对队友「便宜才跟」** | ⚠️ **实测推翻了资料里「一律让牌」**：让牌 ⇒ 每轮只出 1 手，地主每轮都能动。改成便宜就跟后 **农民胜率 36% → 51%** | 整体 62.8% |
## | **地主下家要顶牌**（用大牌封堵） | 源码实战文的「顶牌」条 | 含在上面 |
## | **对手剩 1 张时不出单张** | justa-cai：对手剩一张时避免领出单牌 | 含在上面 |
## | **喂队友**（队友剩 1 张时领小单张） | 资料里的农民配合条 | 含在上面 |
##
## ⚠️ `choose()` 是唯一入口（L3）。`choose_l2()` 是**故意保留的对照组** ——
##    强度是相对的，得有个基准能 A/B 对打（见 `verify_ddz` 的 `_t_ab()`）。
## ⚠️ `bid_score()` 两边**共用不改**：A/B 只比「出牌」，叫分不一样会污染结论。

const R := preload("res://scripts/card/ddz/ddz_rules.gd")
const E := preload("res://scripts/card/ddz/ddz_eval.gd")

## 对手手牌少到这个数，就进入「拼命模式」（允许动炸弹、优先压制）
const ENDGAME_HAND := 2
## 主动出牌时最多评估多少个候选（性能上限）。
## ⚠️ `min_plays` 有全局记忆化 ⇒ 第一副最慢、之后基本命中缓存；这个上限是兜底。
const LEAD_EVAL_MAX := 48


# ══════════════════════════════════════════════════════════════════
#  L3：唯一入口
# ══════════════════════════════════════════════════════════════════

## 返回 `{"cards": [...]}` 或 `{"pass": true}`。
static func choose(game, seat: int) -> Dictionary:
	var hand: Array = game.hand_of(seat)
	if hand.is_empty():
		return {"pass": true}
	# ⚠️ 显式标注类型：`game` 是动态类型，`:=` 推不出来。
	var following: bool = not game.last_play.is_empty() \
			and int(game.last_play["seat"]) != seat
	if following:
		return follow(game, seat)
	return lead(game, seat)


## 主动出牌（我是本轮第一个出的）。
static func lead(game, seat: int) -> Dictionary:
	var hand: Array = game.hand_of(seat)
	var cands: Array = game.legal_now(seat)
	if cands.is_empty():
		return {"cards": [int(hand[0])]}

	# 能一把走完 ⇒ 立刻走
	for c in cands:
		if (c as Array).size() == hand.size():
			return {"cards": c}

	var unseen: Array = E.unseen_counts(game, seat)
	var short := _shortlist(cands)
	var best_score := -1000000000
	var best: Array = short[0]
	for c in short:
		var s := score_lead(c, hand, unseen, game, seat)
		if s > best_score:
			best_score = s
			best = c
	return {"cards": best}


## 跟牌（要压过上一手，或过）。
static func follow(game, seat: int) -> Dictionary:
	var hand: Array = game.hand_of(seat)
	var cands: Array = game.legal_now(seat)
	if cands.is_empty():
		return {"pass": true}

	# 能一把走完 ⇒ 立刻走（农民也不让了，这是赢棋）
	for c in cands:
		if (c as Array).size() == hand.size():
			return {"cards": c}

	var target_seat: int = int(game.last_play["seat"])
	var i_am_farmer: bool = seat != game.landlord
	var target_is_farmer: bool = target_seat != game.landlord
	var opp_min: int = _min_opponent_cards(game, seat)
	var unseen: Array = E.unseen_counts(game, seat)

	# ── 农民对队友：**便宜就跟一手** ──
	#
	# ★★ 这里是**实测推翻资料**的地方：
	#   资料（justa-cai/doudizhu）说「farmer 不盖队友的牌」，我第一版照做 ⇒
	#   A/B 同牌对打只有 57.5%；而反向注入「一律无脑跟一手」反而涨到 72.5%。
	#   原因：两家农民互相让牌 ⇒ **每轮只出 1 手牌**，而地主每轮都能动；
	#   跟一手（且**不花大牌**）能让农民一轮出 2 手，走牌速度直接翻倍。
	#   ⇒ 结论：**让牌要分情况**。判据 = 「这一手便宜吗」：不是炸弹/王炸 ·
	#     不用 2 和王 · 不拆对子/三张/炸弹。
	#   ⛔ 别改回「一律 pass」：那是把节奏白白送给地主。
	if i_am_farmer and target_is_farmer:
		var cheap: Array = []
		for c in cands:
			if _is_cheap_cover(c, hand):
				cheap.append(c)
		if not cheap.is_empty():
			cheap.sort_custom(func(a, b): return _cost(a) < _cost(b))
			return {"cards": cheap[0]}
		# 手上没有便宜牌可跟 ⇒ 只有两种情况值得花大牌：
		#   ① 压这一手之后我只剩 1 手（接管牌权就能走完）；
		#   ② 对手（地主）只剩 1~2 张、而我这张「没人能压」——抢回牌权，
		#      别让队友那张被他吃掉后地主直接走。
		for c in cands:
			if E.min_plays_counts(E.rest_after(hand, c)) <= 1:
				return {"cards": c}
		for c in cands:
			if opp_min <= 2 and E.is_top(c, unseen):
				return {"cards": c}
		return {"pass": true}

	# ── 炸弹门槛 ──
	var pool: Array = []
	for c in cands:
		var t := int(R.classify(c)["type"])
		var is_bomb: bool = t == R.Type.BOMB or t == R.Type.ROCKET
		if is_bomb and opp_min > ENDGAME_HAND:
			# 只在「炸完就走完」时才允许平时动炸弹
			if E.min_plays_counts(E.rest_after(hand, c)) > 0:
				continue
		pool.append(c)
	if pool.is_empty():
		return {"pass": true}

	var best_score := -1000000000
	var best: Array = pool[0]
	for c in pool:
		var s := score_follow(c, hand, unseen, game, seat, opp_min)
		if s > best_score:
			best_score = s
			best = c
	return {"cards": best}


# ══════════════════════════════════════════════════════════════════
#  打分（分开成纯函数，便于验收直接断言「为什么不选那手」）
# ══════════════════════════════════════════════════════════════════

## 主动出牌的打分。**主要项是手数**，其余是修正。
static func score_lead(cards: Array, hand: Array, unseen: Array, game, seat: int) -> int:
	var rest: Array = E.rest_after(hand, cards)
	if E.total(rest) == 0:
		return 1000000                      # 一次走完 = 直接赢
	var plays := E.min_plays_counts(rest)
	var s := -10 * plays                    # ★ 出完这手之后还要几手 —— 主导项
	s -= _break_penalty(cards, hand)
	var top := E.is_top(cards, unseen)
	var opp_min: int = _min_opponent_cards(game, seat)
	if top and plays == 1:
		s += 25                             # 这手没人能压、下一手就走完 ⇒ 非常大
	elif top and opp_min > ENDGAME_HAND:
		s -= 8                              # 平时花掉一张「没人能压」的牌 = 白丢一次牌权
	var t := int(R.classify(cards).get("type", 0))
	if opp_min == 1 and t == R.Type.SINGLE:
		# 对手只剩 1 张 ⇒ ⛔ 出单张等于把牌权递给他（他一张就能走）
		s -= 20
	# ★ 队友只剩 1 张 ⇒ **喂单张**（越小越好）：他接过去一张就走完。
	#   资料里的「配合」条：农民要有意识给对方创造走完的机会。
	if _teammate_cards(game, seat) == 1 and t == R.Type.SINGLE:
		s += 20 - mini(int(R.classify(cards).get("rank", 3)), 17)
	if opp_min <= ENDGAME_HAND and (t == R.Type.BOMB or t == R.Type.ROCKET):
		s += 15                             # 对手将赢，压制优先
	return s


## 跟牌的打分。
static func score_follow(cards: Array, hand: Array, unseen: Array,
		game, seat: int, opp_min: int) -> int:
	var rest: Array = E.rest_after(hand, cards)
	if E.total(rest) == 0:
		return 1000000
	var info := R.classify(cards)
	var rank := int(info.get("rank", 0))
	var s := -10 * E.min_plays_counts(rest)
	s -= _break_penalty(cards, hand)
	var top := E.is_top(cards, unseen)
	var i_am_farmer: bool = seat != game.landlord
	var target_seat: int = int(game.last_play["seat"])
	var target_is_landlord: bool = target_seat == game.landlord

	if opp_min <= ENDGAME_HAND:
		# ★ 拼命模式：对手将赢 ⇒ 优先「压得住且压完还能保持牌权」
		s += mini(rank, 17) * 3
		if top:
			s += 20
	elif i_am_farmer and target_is_landlord:
		# ★ 地主下家要**顶牌**：用较大的牌封堵，别拿小牌放他随意走
		#   （资料原话：作为地主下家时，AI 会出较大的牌顶住地主）
		s += mini(rank, 14) * 2             # 到 A 封顶
		if rank >= 15:
			s -= 12                         # 平时别拿 2 / 王 去顶
	else:
		# 我是地主（或对手是队友，已在上面分流）⇒ 省牌：越小越省
		s -= mini(rank, 17) * 2
		if top:
			s -= 6
	return s


## 「便宜的一手」= 跟队友的牌时**不心疼**的牌：
## 不是炸弹/王炸 · 不用 2 和王（留着控场）· 不拆对子/三张/炸弹。
static func _is_cheap_cover(cards: Array, hand: Array) -> bool:
	var info := R.classify(cards)
	if info.is_empty():
		return false
	var t := int(info["type"])
	if t == R.Type.BOMB or t == R.Type.ROCKET:
		return false
	if int(info["rank"]) >= 15:
		return false
	return _break_penalty(cards, hand) == 0


## 拆结构惩罚：出单张却拆了对子/三张/炸弹，或拆王炸。
## 资料原话：拆错一次（比如拆掉一个顺子）就可能输掉整局。
static func _break_penalty(cards: Array, hand: Array) -> int:
	var info := R.classify(cards)
	if info.is_empty():
		return 0
	var cnt := E.counts_of(hand)
	var t := int(info["type"])
	var p := 0
	if t == R.Type.SINGLE:
		var i := E.idx(int(info["rank"]))
		match int(cnt[i]):
			4: p += 14
			3: p += 9
			2: p += 6
		if i == E.IDX_SJ and int(cnt[E.IDX_BJ]) >= 1:
			p += 8                          # 拆王炸
		elif i == E.IDX_BJ and int(cnt[E.IDX_SJ]) >= 1:
			p += 8
	elif t == R.Type.PAIR and int(cnt[E.idx(int(info["rank"]))]) >= 3:
		p += 5
	return p


## 候选裁剪：只做**性能兜底**（顺序按「长牌型优先 + 小牌优先」），不改变主要逻辑。
static func _shortlist(cands: Array) -> Array:
	if cands.size() <= LEAD_EVAL_MAX:
		return cands
	var a := cands.duplicate()
	a.sort_custom(func(x, y): return _proxy(x) < _proxy(y))
	return a.slice(0, LEAD_EVAL_MAX)


static func _proxy(cards: Array) -> int:
	var info := R.classify(cards)
	if info.is_empty():
		return 99999
	# 张数越多越优先（长顺子/连对先被考虑），同张数下点数越小越优先
	return int(info["rank"]) * 4 - (cards as Array).size() * 10


# ══════════════════════════════════════════════════════════════════
#  叫分（**L2/L3 共用**：A/B 只比出牌，叫分不一样会污染结论）
# ══════════════════════════════════════════════════════════════════

## 叫分（0 = 不叫，1~3）。按手里的「大牌」给个粗档 —— 够用即可。
##
## ⚠️ 返回值必须**高于**当前最高叫分，否则 `game.bid()` 会拒（这是规则）。
static func bid_score(game, seat: int) -> int:
	var pts: int = 0
	for c in game.hand_of(seat):
		match R.rank_of(int(c)):
			17: pts += 3          # 大王
			16: pts += 2          # 小王
			15: pts += 1          # 2
			14: pts += 1          # A
	# ★ 顺带用「手数」补一档：牌散但有炸也是好牌（不该只看大牌张数）
	if E.min_plays(game.hand_of(seat)) <= 7:
		pts += 2
	var want: int = 0
	if pts >= 6:
		want = 3
	elif pts >= 4:
		want = 2
	elif pts >= 2:
		want = 1
	if want <= int(game.bid_best):
		return 0
	return want


# ══════════════════════════════════════════════════════════════════
#  L2（**对照组**，别再改进它 —— 它是「新 AI 到底强了多少」的尺子）
# ══════════════════════════════════════════════════════════════════

static func choose_l2(game, seat: int) -> Dictionary:
	var hand: Array = game.hand_of(seat)
	if hand.is_empty():
		return {"pass": true}
	var following: bool = not game.last_play.is_empty() \
			and int(game.last_play["seat"]) != seat
	if not following:
		return _lead_l2(game, seat, hand)

	var cands: Array = game.legal_now(seat)
	if cands.is_empty():
		return {"pass": true}
	for c in cands:
		if (c as Array).size() == hand.size():
			return {"cards": c}

	var target_seat: int = int(game.last_play["seat"])
	var i_am_farmer: bool = seat != game.landlord
	var target_is_farmer: bool = target_seat != game.landlord
	if i_am_farmer and target_is_farmer:
		return {"pass": true}

	var danger: bool = _min_opponent_cards(game, seat) <= ENDGAME_HAND
	var pool: Array = []
	for c in cands:
		var t := int(R.classify(c)["type"])
		var is_bomb := t == R.Type.BOMB or t == R.Type.ROCKET
		if is_bomb and not danger:
			continue
		pool.append(c)
	if pool.is_empty():
		return {"pass": true} if not danger else {"cards": cands[0]}
	pool.sort_custom(func(a, b): return _cost(a) < _cost(b))
	return {"cards": pool[0]}


static func _lead_l2(game, seat: int, hand: Array) -> Dictionary:
	var cands: Array = game.legal_now(seat)
	if cands.is_empty():
		return {"cards": [int(hand[0])]}
	for c in cands:
		if (c as Array).size() == hand.size():
			return {"cards": c}
	var pool: Array = []
	for c in cands:
		var t := int(R.classify(c)["type"])
		if t != R.Type.BOMB and t != R.Type.ROCKET:
			pool.append(c)
	if pool.is_empty():
		pool = cands
	pool.sort_custom(func(a, b): return _cost(a) < _cost(b))
	for c in pool:
		var t := int(R.classify(c)["type"])
		if t == R.Type.SINGLE or t == R.Type.PAIR:
			return {"cards": c}
	return {"cards": pool[0]}


## 出牌「代价」：点数为主、张数为辅（L2 用）。
static func _cost(cards: Array) -> int:
	var info := R.classify(cards)
	if info.is_empty():
		return 9999
	var t := int(info["type"])
	if t == R.Type.ROCKET:
		return 9000
	if t == R.Type.BOMB:
		return 8000 + int(info["rank"])
	return int(info["rank"]) * 10 + (cards as Array).size()


# ══════════════════════════════════════════════════════════════════

## 别的座位里最少的手牌数（判断「是不是该拼了」）
static func _min_opponent_cards(game, seat: int) -> int:
	var best: int = 99
	for s in 3:
		if s == seat:
			continue
		best = mini(best, (game.hand_of(s) as Array).size())
	return best


## 队友（另一个农民）的手牌数。我是地主 ⇒ 99（没有队友）。
static func _teammate_cards(game, seat: int) -> int:
	if seat == int(game.landlord):
		return 99
	for s in 3:
		if s != seat and s != int(game.landlord):
			return (game.hand_of(s) as Array).size()
	return 99
