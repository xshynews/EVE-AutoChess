class_name EveAiBrain
extends RefCounted

## AI 玩家的决策器。
##
## ⚠️ 关键设计：brain **只做决策，不做输入**。
##    人类玩家用鼠标操作，AI 玩家直接改 `run` 状态 —— 两者终点一致。
##    鼠标层（ai_mouse_bot）是「演示给人看」用的，不是游戏逻辑的一部分。
##    所以 brain 可以跑得很快，不必等动画，人类玩家的节奏完全不受影响。

const FACTION := ["艾玛", "加达里", "盖伦特", "米玛塔尔"]
const WEAPON := ["激光炮", "混合炮", "射弹炮", "导弹"]
const DEFENSE := ["甲抗", "盾抗"]
## ⚠️ 这份表必须和 `EveTraitTable.GROUPS` 的 `tiers` 一致 ——
##    AI 靠它判断「还差几艘到下一档」。两边漂移不会报错，
##    只会让 AI 在错误的艘数上收手或继续买（表现为"AI 莫名其妙不补船"）。
##    ★ 2026-10-31：武器/防御 3,6 → 2,4,6（同 `EveTraitTable`，见那里的设计说明）。
##    ⚠️ AI **不追** 后勤/电子战（那两条没进本表）—— 这是既有行为，不是遗漏：
##       改了会让 AI 的买船策略整体变强，属于平衡改动，得单独评估。
const TIERS := { "faction": [2, 4], "weapon": [2, 4, 6], "defense": [2, 4, 6] }

var difficulty := "normal"


func _init(p_difficulty := "normal") -> void:
	difficulty = p_difficulty


static func _first_in(traits: Array, pool: Array) -> String:
	for t in traits:
		if pool.has(t):
			return String(t)
	return ""


## 统计一名玩家舰队的三组羁绊计数
static func count_traits(ships: Array) -> Dictionary:
	var out := { "faction": {}, "weapon": {}, "defense": {} }
	for g in ["faction", "weapon", "defense"]:
		var pool: Array = FACTION if g == "faction" else (WEAPON if g == "weapon" else DEFENSE)
		for m in pool:
			out[g][m] = 0
	for s in ships:
		var tr: Array = s.get("traits", [])
		var f := _first_in(tr, FACTION)
		if f != "":
			out["faction"][f] = int(out["faction"][f]) + 1
		var w := _first_in(tr, WEAPON)
		if w != "":
			out["weapon"][w] = int(out["weapon"][w]) + 1
		var d := _first_in(tr, DEFENSE)
		if d != "":
			out["defense"][d] = int(out["defense"][d]) + 1
	return out


## 还差几艘到下一档
static func next_tier(group: String, n: int) -> int:
	for v in TIERS.get(group, []):
		if n < v:
			return v - n
	return 0


## 主体系：已积累最多的那一组；没有积累时按默认武器组起步
static func pick_main(counts: Dictionary) -> Dictionary:
	var best := { "g": "weapon", "name": "", "n": 0 }
	for g in ["faction", "weapon", "defense"]:
		for m in (counts[g] as Dictionary).keys():
			var n: int = counts[g][m]
			if n > int(best["n"]):
				best = { "g": g, "name": String(m), "n": n }
	if String(best["name"]) == "":
		best["name"] = "混合炮"
	return best


## 准备阶段的完整决策：买 -> 布阵 -> (刷新的慎重判断)。
## `run` 是这名 AI 玩家的 EveRunState。
func take_prep_turn(run) -> void:
	var owned: Array = run.all_owned()
	var counts := count_traits(owned)
	var main := pick_main(counts)
	var need := next_tier(String(main["g"]), int(main["n"]))

	# ① 买：只买能推进主体系的（正常玩家的「不乱选」）
	var room = 8 - int(run.bench.size())
	var bought := 0
	for offer in run.offers:
		if bought >= room:
			break
		if not (offer is Dictionary):
			continue
		var od: Dictionary = offer
		if not od.has("ship_key"):
			continue
		var tags: Array = od.get("traits", [])
		var cost: int = od.get("cost", 1)
		if run.coin < cost:
			continue
		var is_main := tags.has(main["name"])
		var advances := is_main and need > 0
		# 不推进体系又不会掉出利息台阶 ⇒ 不花
		if not advances and run.coin - cost >= 10:
			continue
		if run.buy(run.offers.find(od)).ok:
			bought += 1
			if is_main:
				need -= 1

	# ② 布阵：尽量填满上场位
	var limit = int(run.field_limit())
	while run.field.size() < limit and run.bench.size() > 0:
		var r = run.deploy_from_bench(int(run.bench.size()) - 1, 7, int(run.field.size()))
		if not (r is Dictionary) or not bool(r.get("ok", false)):
			break

	# ③ 经验：体系推进完了、钱又多才买
	if bought == 0 and run.coin >= 20 and run.level < 6:
		run.levelup()

	return
