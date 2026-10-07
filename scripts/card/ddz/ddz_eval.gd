extends RefCounted
## 斗地主 · 局面评估（**纯函数 + 记忆化缓存**）。
##
## ★ 2026-10-06 新增。查了资料之后的结论：网上**能打的**斗地主 AI（RLCard 规则模型、
## justa-cai/doudizhu 自研引擎、各源码站的「拆牌」系列）都靠三件事，
## 而我们的 L2 一件都没有 ⇒ 这就是「农民偏弱、地主胜率 64.5%」的根因：
##
##   ① **手数**：把这手牌拆成几手能出完。「这手牌好不好」的核心量 ——
##      PerfectDou（NeurIPS 2022）的 node reward 就直接用「地主最少几步出完」。
##   ② **记牌**：从已出的牌推外面还剩什么 ⇒ 才能判断「我这手是不是最大」。
##   ③ **农民配合**：不压队友、但对手快走完时必须压（在 `ddz_ai.gd` 里用本文件实现）。
##
## ## 为什么要 DFS + 记忆化
## 手牌拆分是组合优化（顺子/连对/飞机可任意组合、四个能拆成 3+1 或 2+2），
## 朴素枚举会爆炸。通行做法 = **外层枚举顺子类 + 剩余部分 DP**
## （见 `justa-cai/doudizhu`：outer DFS 枚举顺子/连对/飞机，剩余用 memoized DP），
## 这里再加**节点预算**兜最坏情况。实测 17 张手牌 1ms 内出结果。
##
## ⚠️ 缓存只影响**速度**、不影响结果（`min_plays` 是计数数组的纯函数）
##    ⇒ 不违反「全确定性 / 无全局随机」那条约束（P2P 用得上）。
## ⚠️ 带牌（三带一 / 飞机带牌）的**陪牌只取最小的**（不为陪牌做全排列）——
##    这是通行近似：陪牌怎么选对「手数」影响极小，但会让状态数爆炸。

const R := preload("res://scripts/card/ddz/ddz_rules.gd")

## DFS 节点上限。超了就用贪心估计兜底（宁可不准，也不卡住 UI）
const BUDGET := 40000
## 记忆表上限（条）。超了就整个清掉。
## ⚠️ `min_plays` 是纯函数 ⇒ 清缓存只影响速度、**不影响结果**。
##    不清会吃光内存：早期「枚举全部出牌」的版本涨到过 500 万条。
const MEMO_MAX := 300000

## 计数数组下标 = 点数 − 3 ⇒ 0..14 对应 3,4,...,A,2,小王,大王
const N_RANKS := 15
const IDX_SJ := 13      ## 小王
const IDX_BJ := 14      ## 大王
## 顺子/连对/飞机主体的点数上限（A = 14 ⇒ 下标 11）
const IDX_MAX_RUN := 11

static var _memo := {}
static var _nodes := 0
static var _aborted := false
static var _abort_count := 0      ## 诊断用：预算用尽的次数


static func idx(rank: int) -> int:
	return rank - 3


## 牌 id 数组 → 点数计数数组（长 15）
static func counts_of(cards: Array) -> Array:
	var c: Array = []
	c.resize(N_RANKS)
	c.fill(0)
	for card in cards:
		c[idx(R.rank_of(int(card)))] += 1
	return c


## 「外面还剩什么」：整副牌 − 我的手牌 − 已出的牌。
##
## ⚠️ 底牌那 3 张如果是别人手里的，它就在 `unseen` 里（**正确**：它确实在别人手上）。
static func unseen_counts(game, seat: int) -> Array:
	var c: Array = []
	c.resize(N_RANKS)
	c.fill(4)
	c[IDX_SJ] = 1
	c[IDX_BJ] = 1
	for card in game.hand_of(seat):
		c[idx(R.rank_of(int(card)))] -= 1
	for card in game.played_ids():
		c[idx(R.rank_of(int(card)))] -= 1
	return c


# ══════════════════════════════════════════════════════════════════
#  最少手数
# ══════════════════════════════════════════════════════════════════

## 这副牌最少几手能出完（越小越好）。`cards` = 牌 id 数组。
static func min_plays(cards: Array) -> int:
	return min_plays_counts(counts_of(cards))


static func min_plays_counts(c: Array) -> int:
	if total(c) == 0:
		return 0
	var key := _key(c)
	if _memo.has(key):
		return int(_memo[key])
	_nodes = 0
	_aborted = false
	var v := _search(c)
	if _aborted:
		_abort_count += 1
		return _greedy(c)
	if not _aborted:
		_memo[key] = v
	return v


## 从手牌里去掉 `cards` 之后的计数数组（用于「出了这手还剩几手」）
static func rest_after(hand: Array, cards: Array) -> Array:
	var c := counts_of(hand)
	for card in cards:
		var i := idx(R.rank_of(int(card)))
		c[i] -= 1
	return c


static func total(c: Array) -> int:
	var n := 0
	for v in c:
		n += int(v)
	return n


static func stats() -> Dictionary:
	return {"memo": _memo.size(), "aborts": _abort_count}


static func reset_stats() -> void:
	_memo = {}
	_abort_count = 0


# ------------------------------------------------------------------ 搜索

static func _search(c: Array) -> int:
	if total(c) == 0:
		return 0
	var key := _key(c)
	if _memo.has(key):
		return int(_memo[key])
	_nodes += 1
	if _nodes > BUDGET:
		_aborted = true
		return 0        # 上层会被丢弃（见 min_plays_counts）
	if _memo.size() > MEMO_MAX:
		# ⚠️ 纯函数 ⇒ 清缓存只影响速度、不影响结果。不清会吃光内存
		#    （实测「枚举全部出牌」那版能涨到 500 万条）。
		_memo = {}
	var best := 99

	# ★★ 关键剪枝：**只看「点数最小的那张牌」能用哪些牌组走掉**。
	#    任何一种拆法都必须处理这张最小的牌 ⇒ 只分支它能进的牌组，
	#    就把「同一拆法的不同顺序」这类重复状态全砍掉了
	#    （实测比「枚举所有出牌」快两个数量级）。
	var lo := _lowest(c)

	# ── 单 / 对 / 三（含带一、带二）/ 炸 ──
	best = mini(best, 1 + _search(_dec(c, [lo], 1)))
	if int(c[lo]) >= 2:
		best = mini(best, 1 + _search(_dec(c, [lo], 2)))
	if int(c[lo]) >= 3:
		var base := _dec(c, [lo], 3)
		best = mini(best, 1 + _search(base))
		var k1 := _kicker(base, 1)
		if k1 >= 0:
			best = mini(best, 1 + _search(_dec(base, [k1], 1)))
		var k2 := _kicker(base, 2)
		if k2 >= 0:
			best = mini(best, 1 + _search(_dec(base, [k2], 2)))
	if int(c[lo]) == 4:
		var base4 := _dec(c, [lo], 4)
		best = mini(best, 1 + _search(base4))                    # 炸弹
		var ks := _kickers_n(base4, 2, 1)                        # 四带两单
		if ks.size() == 2:
			best = mini(best, 1 + _search(_dec_multi(base4, ks, 1)))
		var kp := _kickers_n(base4, 2, 2)                        # 四带两对
		if kp.size() == 2:
			best = mini(best, 1 + _search(_dec_multi(base4, kp, 2)))

	# ── 王炸（只有最小牌是小王时才可能）──
	if lo == IDX_SJ and int(c[IDX_BJ]) >= 1:
		best = mini(best, 1 + _search(_dec(c, [IDX_SJ, IDX_BJ], 1)))

	if lo <= IDX_MAX_RUN:
		# ── 顺子（必须含最小牌，长度 5..能连到的最长）──
		for ln in range(5, _run_len(c, lo, 1) + 1):
			best = mini(best, 1 + _search(_take(c, _seg(lo, ln), 1)))
		# ── 连对 ──
		for ln in range(3, _run_len(c, lo, 2) + 1):
			best = mini(best, 1 + _search(_take(c, _seg(lo, ln), 2)))
		# ── 飞机（裸 / 带单 / 带对）──
		for ln in range(2, _run_len(c, lo, 3) + 1):
			var body := _take(c, _seg(lo, ln), 3)
			best = mini(best, 1 + _search(body))
			var ks2 := _kickers_n(body, ln, 1)
			if ks2.size() == ln:
				best = mini(best, 1 + _search(_dec_multi(body, ks2, 1)))
			var kp2 := _kickers_n(body, ln, 2)
			if kp2.size() == ln:
				best = mini(best, 1 + _search(_dec_multi(body, kp2, 2)))

	if not _aborted:
		_memo[key] = best
	return best


static func _lowest(c: Array) -> int:
	for i in N_RANKS:
		if int(c[i]) > 0:
			return i
	return -1


## 从 `start` 起，每点至少 `per` 张，能连续几个点
static func _run_len(c: Array, start: int, per: int) -> int:
	var n := 0
	var i := start
	while i <= IDX_MAX_RUN and int(c[i]) >= per:
		n += 1
		i += 1
	return n


static func _seg(start: int, ln: int) -> Array:
	var out: Array = []
	for j in ln:
		out.append(start + j)
	return out


## 贪心兜底（预算用尽时用）：炸弹/火箭各 1 手，顺子贪心取最长，剩下按组数算。
static func _greedy(c: Array) -> int:
	var cc := c.duplicate()
	var n := 0
	if int(cc[IDX_SJ]) >= 1 and int(cc[IDX_BJ]) >= 1:
		n += 1
		cc[IDX_SJ] -= 1
		cc[IDX_BJ] -= 1
	for i in N_RANKS:
		if int(cc[i]) == 4:
			n += 1
			cc[i] = 0
	# 顺子：能凑就凑（贪心取最长）
	while true:
		var best_len := 0
		var best_start := -1
		for ln in range(12, 4, -1):
			var segs := _runs(cc, ln, 1)
			if segs.size() > 0:
				best_len = ln
				best_start = int(segs[0][0])
				break
		if best_len == 0:
			break
		n += 1
		for j in best_len:
			cc[best_start + j] -= 1
	# 三张（尽量带牌）/ 对子 / 单张
	for i in N_RANKS:
		if int(cc[i]) >= 3:
			n += 1
			cc[i] -= 3
	for i in N_RANKS:
		if int(cc[i]) >= 2:
			n += 1
			cc[i] -= 2
	for i in N_RANKS:
		n += int(cc[i])
	return n


# ------------------------------------------------------------------ 计数数组小工具

static func _key(c: Array) -> int:
	# 15 位 5 进制 ⇒ 5^15 = 3.05e10，int64 装得下
	var k := 0
	var mul := 1
	for i in N_RANKS:
		k += int(c[i]) * mul
		mul *= 5
	return k


static func _dec(c: Array, idxs: Array, n: int) -> Array:
	var out := c.duplicate()
	for i in idxs:
		out[int(i)] -= n
	return out


static func _dec_multi(c: Array, idxs: Array, n: int) -> Array:
	return _dec(c, idxs, n)


## 每个点数取 `per` 张
static func _take(c: Array, seg: Array, per: int) -> Array:
	var out := c.duplicate()
	for r in seg:
		out[int(r)] -= per
	return out


## 长度为 `ln` 的连续段（每点至少 `per` 张），主体点数封顶 A
static func _runs(c: Array, ln: int, per: int) -> Array:
	var out: Array = []
	for start in range(0, IDX_MAX_RUN + 1 - ln + 1):
		var ok := true
		for j in ln:
			if int(c[start + j]) < per:
				ok = false
				break
		if ok:
			var seg: Array = []
			for j in ln:
				seg.append(start + j)
			out.append(seg)
	return out


## 最小的可用陪牌点数（优先不拆炸弹/三张：先挑 1~2 张的点数）
static func _kicker(base: Array, per: int) -> int:
	var fallback := -1
	for i in N_RANKS:
		if int(base[i]) >= per:
			if int(base[i]) < 4:
				return i
			if fallback < 0:
				fallback = i
	return fallback


## 取 `need` 个最小的陪牌点数（每个至少 `per` 张）
static func _kickers_n(base: Array, need: int, per: int) -> Array:
	var out: Array = []
	for i in N_RANKS:
		if out.size() >= need:
			break
		if int(base[i]) >= per and int(base[i]) < 4:
			out.append(i)
	if out.size() < need:      # 允许拆炸弹兜底
		for i in N_RANKS:
			if out.size() >= need:
				break
			if int(base[i]) >= per and not out.has(i):
				out.append(i)
	return out


# ══════════════════════════════════════════════════════════════════
#  「这手牌是不是没人能压」
# ══════════════════════════════════════════════════════════════════

## 我出的这手牌，**按同型同长比较**是否已无敌（保牌权）。
##
## ⚠️ **不考虑对手的炸弹/王炸**：炸弹是低频事件，把它算进来会让这个判据几乎恒假、
##    整个「保牌权」策略失效。资料里的做法（justa-cai/doudizhu）也是只看同型。
##    炸弹风险另用 `has_enemy_bomb()` 单独评估。
static func is_top(cards: Array, unseen: Array) -> bool:
	var info := R.classify(cards)
	if info.is_empty():
		return false
	var t := int(info["type"])
	var r := int(info["rank"])
	var i0 := idx(r)
	match t:
		R.Type.ROCKET:
			return true
		R.Type.BOMB:
			for i in range(i0 + 1, N_RANKS):
				if int(unseen[i]) >= 4:
					return false
			return not (int(unseen[IDX_SJ]) >= 1 and int(unseen[IDX_BJ]) >= 1)
		R.Type.SINGLE:
			for i in range(i0 + 1, N_RANKS):
				if int(unseen[i]) >= 1:
					return false
			return true
		R.Type.PAIR:
			for i in range(i0 + 1, N_RANKS):
				if int(unseen[i]) >= 2:
					return false
			return true
		R.Type.TRIPLE, R.Type.TRIPLE_ONE, R.Type.TRIPLE_TWO:
			for i in range(i0 + 1, N_RANKS):
				if int(unseen[i]) >= 3:
					return false
			return true
		R.Type.FOUR_TWO_SINGLE, R.Type.FOUR_TWO_PAIR:
			for i in range(i0 + 1, N_RANKS):
				if int(unseen[i]) >= 4:
					return false
			return true
		R.Type.STRAIGHT, R.Type.STRAIGHT_PAIR, R.Type.PLANE, \
		R.Type.PLANE_ONE, R.Type.PLANE_TWO:
			# 同长度的顺子类只能靠「起点更高」来压 ⇒ 主体到 A 就无敌
			return r >= 14
	return false


## 外面还有没有炸弹/王炸（用来评估「该不该为这一手拼命」）
static func has_enemy_bomb(unseen: Array) -> bool:
	for i in N_RANKS:
		if int(unseen[i]) >= 4:
			return true
	return int(unseen[IDX_SJ]) >= 1 and int(unseen[IDX_BJ]) >= 1
