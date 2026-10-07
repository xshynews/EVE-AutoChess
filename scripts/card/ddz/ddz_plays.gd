extends RefCounted
## 斗地主 · 候选出牌生成（纯逻辑）。
##
## ⚠️ 为什么单独一个文件：**枚举手牌的所有子集是 2^17，不可行**。
##    这里只生成「形状有限的候选」：
##      · 跟牌 ⇒ 只找**同型、同长度**且点数更大的组合，外加炸弹 / 王炸
##      · 主动出牌 ⇒ 每种点数只取最少张数的组合（1 张 / 2 张 / 3 张 / 4 张）
##    这是 AI 能算得动的前提，也是所有斗地主实现的通行做法。

const R := preload("res://scripts/card/ddz/ddz_rules.gd")


## 手牌按点数分组：`{rank: [card_id, ...]}`（每组已排序）
static func group_by_rank(hand: Array) -> Dictionary:
	var g := {}
	for c in hand:
		var r := R.rank_of(int(c))
		if not g.has(r):
			g[r] = []
		g[r].append(int(c))
	for r in g:
		(g[r] as Array).sort()
	return g


## 能压过 `target` 的全部候选。`target` 为空 ⇒ 返回「所有可主动出的牌型」。
##
## 返回 `Array`，元素是**牌 id 数组**。
static func candidates_for(hand: Array, target: Dictionary) -> Array:
	var out: Array = []
	var g := group_by_rank(hand)
	var ranks: Array[int] = []
	for r in g:
		ranks.append(int(r))
	ranks.sort()

	if target.is_empty():
		_all_shapes(g, ranks, out)
		return _dedup(out)

	var tt := int(target["type"])
	var tlen := int(target["len"])
	var trank := int(target["rank"])

	# ── 炸弹 / 王炸永远可以压（除了压更大的炸弹/王炸）──
	if tt != R.Type.ROCKET:
		if tt != R.Type.BOMB:
			for r in ranks:
				if (g[r] as Array).size() == 4:
					out.append((g[r] as Array).slice(0, 4))
		else:
			for r in ranks:
				if (g[r] as Array).size() == 4 and r > trank:
					out.append((g[r] as Array).slice(0, 4))
		if g.has(16) and g.has(17):
			out.append([(g[16] as Array)[0], (g[17] as Array)[0]])

	# ── 同型同长，比点数 ──
	match tt:
		R.Type.SINGLE:
			for r in ranks:
				if r > trank:
					out.append([(g[r] as Array)[0]])
		R.Type.PAIR:
			for r in ranks:
				if r > trank and (g[r] as Array).size() >= 2:
					out.append((g[r] as Array).slice(0, 2))
		R.Type.TRIPLE:
			for r in ranks:
				if r > trank and (g[r] as Array).size() >= 3:
					out.append((g[r] as Array).slice(0, 3))
		R.Type.TRIPLE_ONE, R.Type.TRIPLE_TWO:
			var need2 := 2 if tt == R.Type.TRIPLE_TWO else 1
			for r in ranks:
				if r <= trank or (g[r] as Array).size() < 3:
					continue
				for kick in _kickers(g, r, need2, 1):
					out.append((g[r] as Array).slice(0, 3) + kick)
		R.Type.STRAIGHT:
			for seg in _runs(ranks, tlen):
				if seg[seg.size() - 1] > trank:
					out.append(_take(g, seg, 1))
		R.Type.STRAIGHT_PAIR:
			var pr := _pair_ranks(g, ranks)
			for seg in _runs(pr, tlen):
				if seg[seg.size() - 1] > trank:
					out.append(_take(g, seg, 2))
		R.Type.PLANE, R.Type.PLANE_ONE, R.Type.PLANE_TWO:
			var triple_r := _triple_ranks(g, ranks)
			for seg in _runs(triple_r, tlen):
				if seg[seg.size() - 1] <= trank:
					continue
				var body := _take(g, seg, 3)
				if tt == R.Type.PLANE:
					out.append(body)
				else:
					var need3 := 2 if tt == R.Type.PLANE_TWO else 1
					for kick in _kickers(g, -1, need3, tlen, seg):
						out.append(body + kick)
		R.Type.FOUR_TWO_SINGLE, R.Type.FOUR_TWO_PAIR:
			var need4 := 2 if tt == R.Type.FOUR_TWO_PAIR else 1
			for r in ranks:
				if r > trank and (g[r] as Array).size() == 4:
					for kick in _kickers(g, r, need4, 2):
						out.append((g[r] as Array).slice(0, 4) + kick)
	return _dedup(out)


## 主动出牌：每种形状取「最小可用」的一组（同一个点数不重复造等价组合）
static func _all_shapes(g: Dictionary, ranks: Array[int], out: Array) -> void:
	for r in ranks:
		var c: Array = g[r]
		out.append([c[0]])
		if c.size() >= 2:
			out.append(c.slice(0, 2))
		if c.size() >= 3:
			out.append(c.slice(0, 3))
			var k1 := _kickers(g, r, 1, 1)
			if k1.size() > 0:
				out.append(c.slice(0, 3) + k1[0])
			var k2 := _kickers(g, r, 2, 1)
			if k2.size() > 0:
				out.append(c.slice(0, 3) + k2[0])
		if c.size() == 4:
			out.append(c.slice(0, 4))
	# 顺子（长度 5..12）
	for ln in range(R.MIN_STRAIGHT, 13):
		for seg in _runs(ranks, ln):
			out.append(_take(g, seg, 1))
	# 连对（3..10 对）
	var pr := _pair_ranks(g, ranks)
	for ln in range(R.MIN_STRAIGHT_PAIR, 11):
		for seg in _runs(pr, ln):
			out.append(_take(g, seg, 2))
	# 飞机（2..6 组）
	var tr := _triple_ranks(g, ranks)
	for ln in range(R.MIN_PLANE, 7):
		for seg in _runs(tr, ln):
			out.append(_take(g, seg, 3))
	if g.has(16) and g.has(17):
		out.append([(g[16] as Array)[0], (g[17] as Array)[0]])


# ------------------------------------------------------------------ 内部工具

## 从 `g` 里取 `seg` 这些点数、每个取 `each` 张
static func _take(g: Dictionary, seg: Array, each: int) -> Array:
	var out: Array = []
	for r in seg:
		out.append_array((g[int(r)] as Array).slice(0, each))
	return out


## 点数集合里长度为 `ln` 的**连续段**（含所有起点）
static func _runs(sorted_ranks: Array, ln: int) -> Array:
	var out: Array = []
	var arr: Array[int] = []
	for r in sorted_ranks:
		if int(r) <= R.MAX_RUN_RANK:
			arr.append(int(r))
	arr.sort()
	for i in range(0, arr.size() - ln + 1):
		var ok := true
		for j in range(ln):
			if arr[i + j] != arr[i] + j:
				ok = false
				break
		if ok:
			var seg: Array = []
			for j in range(ln):
				seg.append(arr[i + j])
			out.append(seg)
	return out


static func _pair_ranks(g: Dictionary, ranks: Array[int]) -> Array:
	var out: Array[int] = []
	for r in ranks:
		if (g[r] as Array).size() >= 2:
			out.append(r)
	return out


static func _triple_ranks(g: Dictionary, ranks: Array[int]) -> Array:
	var out: Array[int] = []
	for r in ranks:
		if (g[r] as Array).size() >= 3:
			out.append(r)
	return out


## 带牌候选：给主体挑 `count` 组陪牌。
##
## `per` = 每组几张（1 = 三带一 / 2 = 三带二或飞机带对）；
## `groups` = 需要几组（三带一是 1 组，飞机带牌是 k 组）。
## `exclude_ranks` = 不能用来当陪牌的点数（主体自己 / 已定的四张）。
##
## ⚠️ 只返回**有限个**组合（每个点数取最少张数），不是全排列 ——
##    全排列在手牌多时是组合爆炸，而 AI 只需要「有个能打的」。
static func _kickers(g: Dictionary, main_rank: int, per: int, groups: int,
		exclude_ranks: Array = []) -> Array:
	var pool: Array[int] = []
	var rs: Array[int] = []
	for r in g:
		rs.append(int(r))
	rs.sort()
	for r in rs:
		if r == main_rank or exclude_ranks.has(r):
			continue
		if (g[r] as Array).size() >= per:
			pool.append(r)
	var out: Array = []
	if pool.size() < groups:
		return out
	var one: Array = []
	for i in groups:
		one.append_array((g[pool[i]] as Array).slice(0, per))
	out.append(one)
	return out


## 去重（按排序后的 id 串）
static func _dedup(list: Array) -> Array:
	var seen := {}
	var out: Array = []
	for item in list:
		var a: Array = (item as Array).duplicate()
		a.sort()
		var k := str(a)
		if seen.has(k):
			continue
		seen[k] = true
		out.append(a)
	return out
