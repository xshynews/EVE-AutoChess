extends RefCounted

## ★ 2026-10-11（i18n）：文案取词（见 `eve_text.gd` 顶注）。
## ⚠️ 本文件仍是**纯逻辑**（无 UI / 无时间 / 无随机）—— 取词只是把显示名过一遍
##    `T.t()`，不引入任何状态。⛔ 别在这里读存档 / 读文件。
const T := preload("res://scripts/core/eve_text.gd")

## 斗地主 · 规则内核（**纯函数，无 UI / 无全局状态 / 无随机**）。
##
## ★ 2026-10-06 立项。设计约束（P2P 路线要求的，即使现在只做单机也照办）：
##   ① 纯逻辑：输入 → 输出，不碰场景树、不读文件、不写全局
##   ② 无随机：洗牌在 `ddz_game.gd` 用**显式 seed**，本文件只做判定
##   ③ 无时间：不出现 delta / 墙钟
##   ⇒ 将来加联机只需同步「动作 + 种子」，本文件一行不用改。
##
## ## 牌 id 约定（0~53）
## ##   0~51  = 52 张普通牌：`rank = 3 + id / 4`，`suit = id % 4`
## ##   52    = 小王（rank 16）
## ##   53    = 大王（rank 17）
## ## 点数用 **rank 3~17**：3..10 就是面值，J=11 / Q=12 / K=13 / A=14 / 2=15，
## ## 小王=16 / 大王=17。⛔ 别用「A 当 1」那套 —— 顺子里 A 只能接在 K 后面。

enum Type {
	INVALID = 0,
	SINGLE,           ## 单张
	PAIR,             ## 对子
	TRIPLE,           ## 三张
	TRIPLE_ONE,       ## 三带一
	TRIPLE_TWO,       ## 三带二
	STRAIGHT,         ## 顺子（≥5 张连续单牌，3~A）
	STRAIGHT_PAIR,    ## 连对（≥3 对连续）
	PLANE,            ## 飞机（≥2 组连续三张，不带牌）
	PLANE_ONE,        ## 飞机带单
	PLANE_TWO,        ## 飞机带对
	FOUR_TWO_SINGLE,  ## 四带二（单）
	FOUR_TWO_PAIR,    ## 四带二（对）
	BOMB,             ## 炸弹（四张同点）
	ROCKET,           ## 王炸
}

## 顺子/连对/飞机主体的最大点数：A（14）。
## ⚠️ 2（15）和王（16/17）**不许**进顺子 —— 这是斗地主的硬规则，
##    写漏了就会出现「QKA2」这种非法顺子被放行。
const MAX_RUN_RANK := 14
const MIN_STRAIGHT := 5        ## 顺子最少 5 张
const MIN_STRAIGHT_PAIR := 3   ## 连对最少 3 对
const MIN_PLANE := 2           ## 飞机最少 2 组

## 牌型 id —— ⛔ 与 `Type` 枚举**顺序严格对齐**（改枚举必须同步改这里）。
## 用途只有一个：拼 i18n 的 key（`CARD_TYPE_SINGLE` …），⛔ 别拿中文当 key。
const TYPE_IDS: Array[String] = [
	"INVALID", "SINGLE", "PAIR", "TRIPLE", "TRIPLE_ONE", "TRIPLE_TWO",
	"STRAIGHT", "STRAIGHT_PAIR", "PLANE", "PLANE_ONE", "PLANE_TWO",
	"FOUR_TWO_SINGLE", "FOUR_TWO_PAIR", "BOMB", "ROCKET",
]


# ══════════════════════════════════════════════════════════════════
#  牌 id ↔ 点数
# ══════════════════════════════════════════════════════════════════

static func rank_of(id: int) -> int:
	if id == 52:
		return 16
	if id == 53:
		return 17
	return 3 + (id / 4)


static func suit_of(id: int) -> int:
	if id >= 52:
		return 4          ## 王没有花色，用 4 表示
	return id % 4


## 牌面文字（画牌与日志共用，**唯一的**展示口径）
static func label_of(id: int) -> String:
	match rank_of(id):
		16: return "小王"
		17: return "大王"
		11: return "J"
		12: return "Q"
		13: return "K"
		14: return "A"
		15: return "2"
		_: return str(rank_of(id))


## 牌型名字（**唯一的展示口径**）。
##
## ⚠️ 牌桌（要给玩家看「已选：顺子」）和状态机（日志要写「出 34567（顺子）」）
##    都从这里取 —— ⛔ 别在各自文件里再抄一份表：两处口径一分叉，
##    玩家看到的和日志写的就会不一样（这类 bug 不报错、只能靠对拍发现）。
static func type_name(t: int) -> String:
	var names := ["非法", "单", "对", "三张", "三带一", "三带二", "顺子", "连对",
			"飞机", "飞机带单", "飞机带对", "四带二", "四带两对", "炸弹", "王炸"]
	var cn: String = names[t] if t >= 0 and t < names.size() else "?"
	# ★ i18n：按**枚举 id** 拼 key（⛔ 别拿中文当 key）。中文版逐字不变。
	var id := TYPE_IDS[t] if t >= 0 and t < TYPE_IDS.size() else "UNKNOWN"
	return T.t("CARD_TYPE_%s" % id, cn)


## 一副完整的 54 张（顺序固定；洗牌由 `ddz_game` 用 seed 负责）
static func full_deck() -> Array:
	var out: Array = []
	for i in 54:
		out.append(i)
	return out


# ══════════════════════════════════════════════════════════════════
#  牌型判定
# ══════════════════════════════════════════════════════════════════

## 判定一组牌的牌型。
##
## 返回 `{}` = 非法；否则 `{"type": Type, "rank": 主点数, "len": 主体长度}`。
## `len` 对顺子是张数、对连对是**对数**、对飞机是**组数** ——
## 比较时「同型且同 len」才可比，所以它是必需字段。
static func classify(cards: Array) -> Dictionary:
	var n := cards.size()
	if n <= 0 or n > 20:
		return {}
	var rs: Array[int] = []
	for c in cards:
		rs.append(rank_of(int(c)))
	rs.sort()

	var cnt := {}
	for r in rs:
		cnt[r] = int(cnt.get(r, 0)) + 1
	var uniq: Array[int] = []
	for r in cnt:
		uniq.append(r)
	uniq.sort()
	var kinds := uniq.size()

	# ── ① 王炸 ──
	if n == 2 and rs[0] == 16 and rs[1] == 17:
		return _t(Type.ROCKET, 17, 1)

	# ── ② 同点数：单 / 对 / 三 / 炸 ──
	if kinds == 1:
		var r: int = rs[0]
		match n:
			1: return _t(Type.SINGLE, r, 1)
			2: return _t(Type.PAIR, r, 1)
			3: return _t(Type.TRIPLE, r, 1)
			4: return _t(Type.BOMB, r, 1)
		return {}

	# ── ③ 三带一 / 三带二 ──
	if n == 4 and kinds == 2:
		var t1 := _rank_of_count(cnt, 3)
		if t1 > 0:
			return _t(Type.TRIPLE_ONE, t1, 1)
	if n == 5 and kinds == 2:
		var t2 := _rank_of_count(cnt, 3)
		if t2 > 0 and _rank_of_count(cnt, 2) > 0:
			return _t(Type.TRIPLE_TWO, t2, 1)

	# ── ④ 顺子：≥5 张、全不重复、连续、封顶 A ──
	if n >= MIN_STRAIGHT and kinds == n and _is_run(uniq) \
			and uniq[uniq.size() - 1] <= MAX_RUN_RANK:
		return _t(Type.STRAIGHT, uniq[uniq.size() - 1], n)

	# ── ⑤ 连对：≥3 对、每点恰好 2 张、连续、封顶 A ──
	if n >= MIN_STRAIGHT_PAIR * 2 and n % 2 == 0 and kinds == n / 2 \
			and _all_count_is(cnt, 2) and _is_run(uniq) \
			and uniq[uniq.size() - 1] <= MAX_RUN_RANK:
		return _t(Type.STRAIGHT_PAIR, uniq[uniq.size() - 1], kinds)

	# ── ⑥ 飞机（主体 = k 组连续三张，封顶 A）──
	for k in range(MIN_PLANE, 7):
		var body := _plane_top_rank(cnt, k)
		if body <= 0:
			continue
		if n == k * 3:
			return _t(Type.PLANE, body, k)
		if n == k * 4:
			return _t(Type.PLANE_ONE, body, k)
		if n == k * 5 and _rest_are_pairs(cnt, k):
			return _t(Type.PLANE_TWO, body, k)

	# ── ⑦ 四带二（单 / 对）──
	if n == 6:
		var f := _rank_of_count(cnt, 4)
		if f > 0:
			return _t(Type.FOUR_TWO_SINGLE, f, 1)
	if n == 8:
		var f2 := _rank_of_count(cnt, 4)
		if f2 > 0 and _pairs_in_rest(cnt, f2, 2):
			return _t(Type.FOUR_TWO_PAIR, f2, 1)

	return {}


## a 能否压过 b（两副牌型字典，空 = 不能出）。
##
## 规则：王炸 > 炸弹 > 一切；同型且同长度比点数。
static func beats(a: Dictionary, b: Dictionary) -> bool:
	if a.is_empty() or b.is_empty():
		return false
	var ta := int(a["type"])
	var tb := int(b["type"])
	if ta == Type.ROCKET:
		return true
	if tb == Type.ROCKET:
		return false
	if ta == Type.BOMB and tb != Type.BOMB:
		return true
	if tb == Type.BOMB and ta != Type.BOMB:
		return false
	if ta != tb or int(a["len"]) != int(b["len"]):
		return false
	return int(a["rank"]) > int(b["rank"])


# ══════════════════════════════════════════════════════════════════
#  内部工具
# ══════════════════════════════════════════════════════════════════

static func _t(type: int, rank: int, len: int) -> Dictionary:
	return {"type": type, "rank": rank, "len": len}


## 恰好 `want` 张的那个点数（多个时取最大）；没有返回 0。
static func _rank_of_count(cnt: Dictionary, want: int) -> int:
	var best := 0
	for r in cnt:
		if int(cnt[r]) == want and int(r) > best:
			best = int(r)
	return best


static func _all_count_is(cnt: Dictionary, want: int) -> bool:
	for r in cnt:
		if int(cnt[r]) != want:
			return false
	return true


## 一组点数是否**严格连续**（已排序、无重复）
static func _is_run(sorted_uniq: Array) -> bool:
	for i in range(1, sorted_uniq.size()):
		if int(sorted_uniq[i]) != int(sorted_uniq[i - 1]) + 1:
			return false
	return true


## 找 k 个**连续**且每个都 ≥3 张的点数段，返回该段的最高点数（0 = 没有）。
##
## ⚠️ 从高往低找：飞机带牌时比较用的是主体最高点，取低段会让大小判反。
static func _plane_top_rank(cnt: Dictionary, k: int) -> int:
	var cands: Array[int] = []
	for r in cnt:
		if int(cnt[r]) >= 3 and int(r) <= MAX_RUN_RANK:
			cands.append(int(r))
	cands.sort()
	for i in range(cands.size() - k, -1, -1):
		var ok := true
		for j in range(k):
			if cands[i + j] != cands[i] + j:
				ok = false
				break
		if ok:
			return cands[i + k - 1]
	return 0


## 去掉主体（每种点数剥 3 张）之后，剩下的牌是否**全是**对子
static func _rest_are_pairs(cnt: Dictionary, k: int) -> bool:
	# 主体由调用方保证存在；这里只验「剩余部分能否凑成若干对」
	var rest := {}
	for r in cnt:
		rest[r] = int(cnt[r])
	# 剥掉 k 组三张：挑点数最高的那些 ≥3 的
	var triples: Array[int] = []
	for r in rest:
		if int(rest[r]) >= 3 and int(r) <= MAX_RUN_RANK:
			triples.append(int(r))
	triples.sort()
	if triples.size() < k:
		return false
	for i in range(k):
		var r: int = triples[triples.size() - 1 - i]
		rest[r] = int(rest[r]) - 3
	for r in rest:
		if int(rest[r]) != 0 and int(rest[r]) % 2 != 0:
			return false
	return true


## 去掉点数 `four` 的四张后，剩余能否凑成 `need` 个对子
static func _pairs_in_rest(cnt: Dictionary, four: int, need: int) -> bool:
	var pairs := 0
	for r in cnt:
		if int(r) == four:
			continue
		if int(cnt[r]) % 2 != 0:
			return false
		pairs += int(cnt[r]) / 2
	return pairs == need
