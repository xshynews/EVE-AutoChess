extends Node

## 敌方编组全表体检（无头）—— 「每回合来什么船、什么数值」
##
## ══════════════════════════════════════════════════════════════════
##  它回答什么
## ══════════════════════════════════════════════════════════════════
##  用户 2026-10-27：「重做每回合敌人的编组…把每回合会出现的船和他们的数据、
##  加成以及加成之后的数值全部报告给我，如果难度选择影响数值的话，就分难度档呈报」。
##
##  所以本探针**不重算任何公式**，而是逐难度 × 逐节点调用**生产链**：
##      EveShipDatabase.instantiate_by_id → EveRunState.apply_enemy_scaling
##      → EveFleetFactory.apply_doctrine → EveRunState.apply_fleet_traits(若该档开)
##      → cycle_scale(电子战) → incoming_mult(炼狱壁垒)
##  这样报出来的数**就是**玩家真的会遇到的数。⛔ 别在探针里手抄倍率 ——
##  一旦生产链改了（比如以后羁绊又多一条），手抄的表立刻变假。
##
## ⚠️ 探针**只读**：不改船表 / 编组表 / 节点表 / 难度表，也不写存档。
##
## ── 输出 ─────────────────────────────────────────────────────────
##   ① 难度档总览（scale / ai_level / 羁绊 / 阵型 / 壁垒 / 逐节点战败代价）
##   ② 逐难度 × 逐节点：编组名 · 敌方羁绊 · 每艘船的基础值 → 最终值 + 倍率
##   ③ 全 15 关的「总 EHP / 总 DPS / 总维修」汇总，用来看难度爬升形状
##
##  报告写到 `user://enemy_comps_report.md`（Markdown，可直接给设计侧看）。

const RUN := preload("res://scripts/core/eve_run_state.gd")
const SIM := preload("res://scripts/core/eve_battle_simulator.gd")
const NODE := preload("res://scripts/data/eve_node_table.gd")
const COMPS := preload("res://scripts/data/eve_enemy_comps.gd")
const DB := preload("res://scripts/core/eve_ship_database.gd")
const FT := preload("res://scripts/data/eve_campaign_tiers.gd")
const FACTORY := preload("res://scripts/scene/eve_fleet_factory.gd")
## ★ 2026-10-27：程序化编组配方（普通/困难/炼狱共用）。
const PLANS := preload("res://scripts/data/eve_enemy_plans.gd")

## 展示配方形状用的样本种子（与真实对局无关，仅为了让报告可复现）。
## ⚠️ 给**三个**不同种子：配方只写死了「舰种 + 艘数」，具体抽到哪几条船
##    每次开局都不一样 —— 单一样本会让人误以为这是一张固定名单。
const PLAN_SAMPLE_SEEDS: Array[int] = [4242, 20261027, 777]

## 报告路径（user:// 落盘，避免 tools/ 里出现产物）
const OUT := "user://enemy_comps_report.md"
## 机器可读配方规格（JSON）—— 给其他 AI / 工具直接读，不用解析 Markdown
const SPEC_OUT := "user://enemy_comps_spec.json"

var _lines: PackedStringArray = PackedStringArray()


func _ready() -> void:
	_lines.append("# 敌方编组全表（逐难度 × 逐节点）")
	_lines.append("")
	_lines.append("> 本表由 `tools/probe_enemy_comps.gd` 调**生产装配链**生成，"
			+ "报出来的敌方数值就是实战会遇到的值。")
	_lines.append("> 基础值 = 权威船表原值（星级 1、无任何加成）；"
			+ "最终值 = 走完 敌方倍率 → 敌方羁绊 → 炼狱壁垒 之后的值。")
	_lines.append(">")
	_lines.append("> ⚠️ **不含玩家电子战干扰**：探针没有玩家舰队，`enemy_cycle_pct()` 恒为 0。"
			+ "实战里玩家凑到电子战会把敌舰开火间隔 ×1.05 / ×1.10 / ×1.15"
			+ "（三档），本表看不出这一层。")
	_lines.append("")

	_difficulty_overview()
	for d in FT.difficulties():
		_dump_difficulty(String(d["id"]))
	_totals_curve()
	_anomalies()

	var f := FileAccess.open(OUT, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(_lines))
		f.close()
	print("\n".join(_lines))
	print("\n[报告] %s" % ProjectSettings.globalize_path(OUT))
	_write_spec()
	get_tree().quit()


# ══════════════════════════════════════════════════════════════
#  ① 难度档总览
# ══════════════════════════════════════════════════════════════
func _difficulty_overview() -> void:
	_lines.append("## ① 难度档改了什么")
	_lines.append("")
	_lines.append("| 档位 | 敌方倍率 scale | AI 等级 | 敌方吃羁绊 | 敌方按阵型站位 | 编组来源 | 机制壁垒 | 开局星币 | 基础收入 | 利息上限 |")
	_lines.append("|---|---|---|---|---|---|---|---|---|---|")
	for d in FT.difficulties():
		_lines.append("| **%s** | ×%.2f | %d | %s | %s | %s | %s | %d | %d | %d |" % [
			String(d["name"]), float(d["scale"]), int(d["ai_level"]),
			"吃" if bool(d["enemy_traits"]) else "否",
			"是" if bool(d["enemy_formation"]) else "否",
			"程序化配方" if bool(d.get("random_comps", false)) else "节点表静态编组",
			String(d.get("key_mechanic", "")) if String(d.get("key_mechanic", "")) != "" else "—",
			int(d["start_gold"]), int(d["base_income"]), int(d["interest_max"]),
		])
	_lines.append("")
	_lines.append("⚠️ **四档的玩家经济完全一致**（星币 / 收入 / 利息），"
			+ "难度只动敌方与战败代价 —— 这是设计红线。")
	_lines.append("")
	_lines.append("⚠️ 只有**简单档**读节点表的静态编组（`random_comps = false`，"
			+ "用户要求「简单就现在的不变」）；普通 / 困难 / 炼狱三档共用"
			+ "`EveEnemyPlans` 的同一套配方，**同一局同一关摇出的船完全相同**，"
			+ "差别只在倍率与羁绊。")
	_lines.append("")
	_lines.append("### 逐节点战败代价（信标 −N，开局 100）")
	_lines.append("")
	_lines.append("| 档位 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 | 13 | 14 | 15 | 合计不可避免 |")
	_lines.append("|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|")
	for d in FT.difficulties():
		var c: Array = d["loss_curve"]
		var cells := PackedStringArray()
		var sum := 0
		for v in c:
			cells.append(str(int(v)))
			sum += int(v)
		_lines.append("| %s | %s | **%d** |" % [String(d["name"]), " | ".join(cells), sum])
	_lines.append("")
	_lines.append("> 「合计」= 15 关全输的战败代价总和。"
			+ "它 < 100 表示「全输也死不了」，> 100 表示「输够一定次数就出局」。")
	_lines.append("")

	_lines.append("### 各档的编组来源（2026-10-27 改）")
	_lines.append("")
	_lines.append("| 档位 | 编组来源 |")
	_lines.append("|---|---|")
	for d in FT.difficulties():
		if bool(d.get("random_comps", false)):
			_lines.append("| %s | **程序化配方**（`EveEnemyPlans` 逐节点抽船，"
					% String(d["name"]) + "种子 = 本局种子 + 节点号，不含难度）|")
		else:
			_lines.append("| %s | 节点表静态编组（`comp` 字段，与改版前一致） |"
					% String(d["name"]))
	_lines.append("")
	_lines.append("> ⛔ 旧版「困难 / 炼狱各挂一张按节点号替换的静态编组表」"
			+ "（`comp_overrides`）**已整条废止**。现在普通 / 困难 / 炼狱共用同一套配方，"
			+ "同一局同一关摇出的船完全相同，差别只在倍率与羁绊。")
	_lines.append("")
	_lines.append("#### ★ 逐节点可能性普查（换个种子就换一批船 —— 下面是「能摇出多少种」）")
	_lines.append("")
	_lines.append("> 配方只固定**舰种与艘数**，具体抽到哪几条船每局都在变"
			+ "（有放回抽签 `EveEnemyPlans._pick_n`）。下表把每个节点的"
			+ "**可能性总数**算了出来 —— N1 正好是 **16 种**（4 艘普通护卫 × 2 个位、允许重复）。")
	_lines.append("")
	_possibility_census()
	_lines.append("#### 同三个种子下的实际产出（只是样本，不是名单）")
	_lines.append("")
	_lines.append("| 节点 | 编组名 | 阵型 | 种子 %d | 种子 %d | 种子 %d |" % [
			PLAN_SAMPLE_SEEDS[0], PLAN_SAMPLE_SEEDS[1], PLAN_SAMPLE_SEEDS[2]])
	_lines.append("|---|---|---|---|---|---|")
	for i in range(1, NODE.TOTAL + 1):
		if not PLANS.has_plan(i):
			continue
		_lines.append("| N%d | %s | `%s` | %s | %s | %s |" % [
			i, PLANS.name_of(i), PLANS.formation_of(i),
			_plan_desc(i, PLAN_SAMPLE_SEEDS[0]),
			_plan_desc(i, PLAN_SAMPLE_SEEDS[1]),
			_plan_desc(i, PLAN_SAMPLE_SEEDS[2])])
	_lines.append("")
	_pool_catalog()
	_recipe_section()
	_randomness_selfproof()


## 把某节点的配方在给定种子下摇出来的船，拼成一句人话，用于展示配方形状。
## ⚠️ 这只是**一个样本**；真实对局里种子 = 本局种子 + 节点号，逐局不同。
func _plan_desc(node_index: int, p_seed: int) -> String:
	var plan: Dictionary = PLANS.build(node_index, p_seed)
	if plan.is_empty():
		return "—"
	var parts := PackedStringArray()
	for sid in plan["ships"]:
		var d: Dictionary = DB.by_id(String(sid))
		if d.is_empty():
			parts.append("%s（⚠️不在船表）" % String(sid))
			continue
		parts.append("%s（%d费）" % [String(d["name"]), int(d["cost"])])
	return "、".join(parts)


## 每个战斗节点「用户给的条件」原话（照抄，用于并排对账 —— 别改写，改了就没法对账）
const NODE_CONDITION := {
	1: "随机出现两艘普通型护卫",
	2: "随机出现两艘护卫（30% 的几率出现一艘电子战或者后勤护卫）",
	3: "随机一艘防御型驱逐 + 其余两艘护卫按 N2 走",
	5: "新增一艘攻击型驱逐，其余按 N3 走（共 4 艘船）",
	6: "一艘普通巡洋 + 一艘驱逐 + 两艘后勤或电子战护卫（共 4 艘船）",
	7: "一艘巡洋（30% 概率出现一艘电子战或后勤巡洋）+ 两艘驱逐 + 两艘后勤或电子战护卫（2026-10-27 定案）",
	8: "一艘刺客级 + 一艘电子战或后勤巡洋 + 两艘驱逐 + 两艘后勤或电子战护卫（都从米玛塔尔舰船随机，2026-10-27 定案）",
	9: "从加达里/艾玛随机一艘战巡 + 一艘普通巡洋 + 两艘后勤或电子战巡洋 + 两艘后勤或电子战护卫（阵型保持距离，2026-10-27 定案）",
	11: "加达里导弹狼群：1 战巡 + 2 巡洋（3 种巡洋全随机）+ 2 驱逐 + 3 电子战或后勤护卫",
	12: "四艘巡洋（一族一艘，含电子战/后勤）+ 两艘随机驱逐 + 两艘电子战或后勤护卫",
	13: "盖伦特专场：2 战巡 + 2 电子战或后勤巡洋 + 2 驱逐 + 3 电子战或后勤护卫",
	15: "一艘战列（加强型中随机）+ 两艘攻击型战巡 + 4 电子战或后勤巡洋 + 4 电子战或后勤护卫",
}

## 概率条件实测名单（用户写死「30%」的那几个节点）
##
## ⚠️ 判据必须能**唯一**归因到那个 30%：
##    N2 / N3 / N5 的护卫里只有 `_escort_frigates` 会引入电子战/后勤 ⇒ 出现即触发；
##    N7 同理只看**第 1 艘巡洋**（第 4 艘护卫本来就必定是支援，不能拿来判）。
##    ⛔ N6 也带 2 艘支援护卫，但那是「两艘后勤或者电子战护卫」的**硬性**要求，
##       与 30% 无关 ⇒ 不在本表里。
const CHANCE_CONDITIONAL := {
	2: "frigate",
	3: "frigate",
	5: "frigate",
	7: "cruiser",
}

## 普查抽样局数 / 「已穷尽」复验局数 / 小空间全枚举阈值
const CENSUS_RUNS := 6000
const CENSUS_SMALL := 600
const CENSUS_CONFIRM_RUNS := 30000
const CENSUS_LIST_MAX := 40


## 逐节点**可能性总数**（按用户条件做乘法）—— 这是对账表。
##
## ⚠️ 约定：每个「随机一艘」= 乘该池的大小；「允许重复」⇒ 同一位反复出现也算
##    不同种（如 N13 的 3 艘护卫来自 2 艘池 ⇒ 2³ = 8）。
##    抽样（`CENSUS_RUNS`）数出来的值必须与它一致；不一致就说明**配方代码与
##    用户给的条件出现了偏差** —— 这正是本表存在的意义。
const POSSIBILITIES := {
	1: {"expr": "4²（普通护卫 4 选 2，有放回）", "n": 16},
	2: {"expr": "4² + 2 × 4 × 8（70% 双普通 / 30% 一支援，换哪个位 ×2）", "n": 80},
	3: {"expr": "4 × 80（防御驱逐 × N2）", "n": 320},
	5: {"expr": "4 × 4 × 80（防御驱逐 × 攻击驱逐 × N2）", "n": 1280},
	6: {"expr": "4 × 8 × 8²（普通巡洋 × 驱逐 × 2 支援护卫）", "n": 2048},
	7: {"expr": "(4 + 8) × 8 × 8 × 8²（巡洋 12 种 × 2 驱逐 × 2 支援护卫）", "n": 49152},
	8: {"expr": "1 × 2 × 2² × 8²（刺客级固定 × 米玛塔尔支援巡洋 × 2 驱逐 × 2 支援护卫）",
			"n": 512},
	9: {"expr": "4 × 2 × 4² × 8²（加达里+艾玛：战巡 × 普通巡洋 × 2 支援巡洋 × 2 支援护卫）",
			"n": 8192},
	11: {"expr": "2 × 3² × 2² × 2³（加达里：战巡 × 2 巡洋 × 2 驱逐 × 3 护卫）", "n": 576},
	12: {"expr": "3⁴ × 8² × 8²（一族一艘巡洋 × 2 驱逐 × 2 支援护卫）", "n": 331776},
	13: {"expr": "2² × 2² × 2² × 2³（盖伦特：2 战巡 × 2 支援巡洋 × 2 驱逐 × 3 护卫）",
			"n": 512},
	15: {"expr": "4 × 1² × 4⁴ × 4⁴（战列 × 2 攻击战巡 × 4 支援巡洋 × 4 支援护卫）",
			"n": 262144},
}


## ★ 逐节点可能性普查。
##
## 用户 2026-10-27：「N1 的种子数不够…普通护卫每族还剩一艘，而且我允许重复，
## 所以一共有 16 种可能」+「其余的全部按我给到的条件重新计算种子」——
## 所以这里**按每个节点的条件把可能性总数算出来**（`POSSIBILITIES` 算式），
## 再用连续种子抽样**独立复验**；小空间（≤ `CENSUS_LIST_MAX`）逐条列出全部可能。
func _possibility_census() -> void:
	_lines.append("| 节点 | 艘数 | 可能性总数（算式） | 抽样复验 | 用户条件（原话） |")
	_lines.append("|---|---|---|---|---|")
	var small_spaces: Dictionary = {}
	for i in range(1, NODE.TOTAL + 1):
		if not PLANS.has_plan(i):
			continue
		var spec: Dictionary = POSSIBILITIES.get(i, {})
		var exact := int(spec.get("n", -1))
		var seen := {}
		for sd in range(1, CENSUS_RUNS + 1):
			seen[_plan_key(i, sd)] = true
		var n := seen.size()
		var verdict := ""
		if n <= CENSUS_SMALL:
			var seen2 := {}
			for sd in range(1, CENSUS_CONFIRM_RUNS + 1):
				seen2[_plan_key(i, sd)] = true
			n = seen2.size()
			small_spaces[i] = seen2
			verdict = "✅ 穷尽 %d" % n
			if exact > 0:
				verdict += "，与算式%s" % ("一致" if n == exact
						else "❌ 不符（算式 %d）" % exact)
		else:
			verdict = "下界 ≥%d（未穷尽）" % n
		_lines.append("| N%d | %d | %s = **%d** | %s | %s |" % [
			i, PLANS.ship_ids(i, 1).size(), String(spec.get("expr", "?")), exact,
			verdict, String(NODE_CONDITION.get(i, ""))])
	_lines.append("")
	_lines.append("> 「可能性总数」按用户条件做乘法 —— 每个「随机一艘」乘池子大小，"
			+ "「允许重复」⇒ 同一位反复出现算不同种。N1 = 4 × 4 = **16**，与你算的一致。")
	_lines.append("")
	_lines.append("> 「抽样复验」是用连续种子（1…%d）独立跑配方数出来的；" % CENSUS_RUNS
			+ "两者一致 ⇒ 配方代码**确实**按你给的条件在抽。"
			+ "标「下界」的几个是池太大、抽样数不完（不是写死）。")
	_lines.append("")

	# ── 小空间：逐条列出全部可能（N1 的 16 种会全部列出来）
	for i in small_spaces.keys():
		var keys: Array = small_spaces[i].keys()
		if keys.size() > CENSUS_LIST_MAX:
			continue
		keys.sort()
		_lines.append("##### N%d —— 全部 %d 种可能" % [int(i), keys.size()])
		_lines.append("")
		for k in keys:
			_lines.append("- %s" % _plan_key_desc(String(k)))
		_lines.append("")

	_chance_rates()


## 概率条件实测：用户写死 30% 的那几个节点，跑一遍看实际触发率
func _chance_rates() -> void:
	_lines.append("#### 概率条件实测（用户写死的 30%）")
	_lines.append("")
	_lines.append("| 节点 | 条件 | 抽样局数 | 实测触发率 | 与 30% 的偏差 |")
	_lines.append("|---|---|---|---|---|")
	var keys: Array = CHANCE_CONDITIONAL.keys()
	keys.sort()
	for i in keys:
		var kind := String(CHANCE_CONDITIONAL[i])
		var hits := 0
		for sd in range(1, CENSUS_CONFIRM_RUNS + 1):
			if _chance_triggered(int(i), kind, PLANS.ship_ids(int(i), sd)):
				hits += 1
		var rate := float(hits) / float(CENSUS_CONFIRM_RUNS)
		_lines.append("| N%d | %s | %d | **%.2f%%** | %+.2f pp |" % [
			int(i), "出现电子战/后勤巡洋" if kind == "cruiser" else "出现电子战/后勤护卫",
			CENSUS_CONFIRM_RUNS, rate * 100.0, (rate - 0.30) * 100.0])
	_lines.append("")


## 这批船里有没有「由那个 30% 引入」的支援舰
func _chance_triggered(node_index: int, kind: String, ids: PackedStringArray) -> bool:
	if kind == "cruiser":
		# N7 的巡洋在**第 1 个位**（`_cruiser_with_chance`），最后一个位必定是支援护卫
		return ids.size() > 0 and PLANS.SUPPORT_CRUISER.has(String(ids[0]))
	for sid in ids:
		if PLANS.SUPPORT_FRIGATE.has(String(sid)):
			return true
	return false


## 一副编组的「指纹」（按位置有序，用 | 连接船 id —— 船 id 不含 |）
func _plan_key(node_index: int, p_seed: int) -> String:
	return "|".join(PLANS.ship_ids(node_index, p_seed))


## 指纹 → 中文名串
func _plan_key_desc(key: String) -> String:
	var parts := PackedStringArray()
	for sid in key.split("|"):
		var d: Dictionary = DB.by_id(String(sid))
		parts.append(String(d.get("name", sid)))
	return "、".join(parts)


## ★ 池子清单 —— 「还能抽到谁」。
##
## ⚠️ 这一节是**给其他 AI / 工具的关键补充**：上面那些表只显示了「抽到过谁」，
##    换个种子就不一样；只有池子清单是**固定不变**的，它才是配方的真身。
func _pool_catalog() -> void:
	_lines.append("#### ★ 池子清单（配方的真身 —— 「还能抽到谁」）")
	_lines.append("")
	_lines.append("> 上面各表显示的是**抽签结果**，逐局在变。**这张表才是固定的**："
			+ "每个池的成员就是配方的全部兵源。要把这套随机交给别的 AI / 工具，"
			+ "**必须连它一起给** —— 否则对方只知道抽到过谁，不知道还能抽到谁。")
	_lines.append("")
	_lines.append("| 池名 | 成员（`id` · 中文名 · 势力）|")
	_lines.append("|---|---|")
	var pl: Dictionary = PLANS.pools()
	var names: Array = pl.keys()
	names.sort()
	for nm in names:
		var parts := PackedStringArray()
		for sid in pl[nm]:
			var d: Dictionary = DB.by_id(String(sid))
			parts.append("`%s` · %s · %s" % [String(sid), String(d.get("name", "⚠️?")),
					String(d.get("faction_cn", "?"))])
		_lines.append("| `%s` | %s |" % [String(nm), "；".join(parts)])
	_lines.append("")
	_lines.append("> N15 还会用到三个**派生池**（按随机到的战列动态选），"
			+ "成员就是上表里的对应项：`%s`。" % "、".join(
					PackedStringArray(PLANS.DERIVED_POOLS)))
	_lines.append("")


## ★ 逐节点配方（形式化、机器可读）—— 与「抽签结果」严格分开
func _recipe_section() -> void:
	_lines.append("#### ★ 逐节点配方（形式化 —— 这才是「规则」，上面的都是「样本」）")
	_lines.append("")
	_lines.append("> 读法：`有放回抽 P × n` = 从池 `P` 里**独立抽 n 次**（允许抽到同一艘）。"
			+ "步的先后 = 编组里的位置先后。**每一条都是规则，不是某一局的名单。**")
	_lines.append("")
	_lines.append("| 节点 | 配方步骤（按位置顺序） | 可能性总数 |")
	_lines.append("|---|---|---|")
	var keys: Array = PLANS.RECIPE_STEPS.keys()
	keys.sort()
	for i in keys:
		var steps := PackedStringArray()
		for step in PLANS.RECIPE_STEPS[i]:
			steps.append(_step_text(step))
		var spec: Dictionary = POSSIBILITIES.get(int(i), {})
		_lines.append("| N%d | %s | **%d** |" % [
			int(i), "；".join(steps), int(spec.get("n", -1))])
	_lines.append("")
	_lines.append("> 全部抽签**有放回**（用户 2026-10-27：「没有特别规定，就是允许重复」）。"
			+ "「可能性总数」按**位置有序**计（两艘互换算两种）。")
	_lines.append("")


## 把一个配方步写成人话
func _step_text(step: Dictionary) -> String:
	match String(step.get("kind", "")):
		"draw":
			return "有放回抽 `%s` × %d" % [String(step["pool"]), int(step["n"])]
		"fixed":
			var d: Dictionary = DB.by_id(String(step["ship"]))
			return "固定 `%s`（%s）" % [String(step["ship"]),
					String(d.get("name", "⚠️不在船表"))]
		"chance_draw":
			return "以 %.0f%% 抽 `%s` × 1，否则抽 `%s` × 1" % [
					float(step["p"]) * 100.0, String(step["pool"]),
					String(step["else_pool"])]
		"chance_replace":
			return "以 %.0f%% 把第 %d 步里的**随机 1 艘**换成 `%s` × 1" % [
					float(step["p"]) * 100.0, int(step["of"]) + 1, String(step["pool"])]
	return "⚠️ 未知步"


## 把机器可读规格落成 JSON（给其他 AI / 工具直接读，不用解析 Markdown）
func _write_spec() -> void:
	var spec: Dictionary = PLANS.spec()
	spec["generated_by"] = "tools/probe_enemy_comps.gd"
	spec["note"] = "本文件是配方的**规则**（池子 + 步骤），不含任何一局的抽签结果。"
	var counts: Dictionary = {}
	for i in POSSIBILITIES.keys():
		counts[str(int(i))] = int(POSSIBILITIES[i]["n"])
	spec["possibility_counts"] = counts
	var f := FileAccess.open(SPEC_OUT, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(spec, "  "))
	f.close()
	print("[规格] %s" % ProjectSettings.globalize_path(SPEC_OUT))


## ★ 随机性自证：**走真实生产路径**（`EveRunState.start_run(种子)` → `enemy_roster()`），
##   而不是直接调 `EveEnemyPlans` —— 用户要的证据是「游戏里每局敌人不一样」，
##   只有这条路能证明。取 5 个不同的「本局种子」，在同一个难度、同一个节点上跑，
##   把结果并排列出来。
##
## ⚠️ 它同时证明了另一条设计约束：**同一种子下普通与困难必须是同一批船**
##    （用户原话「困难难度的舰船随机与上面的相同」）。
func _randomness_selfproof() -> void:
	_lines.append("#### ★ 随机性自证（走真实路径：`start_run(种子)` → `enemy_roster()`）")
	_lines.append("")
	_lines.append("> 同一个难度「普通」、同一个节点 N12，只换**本局种子**。"
			+ "注意每行的船都在变 —— 这就是它在游戏里的样子。")
	_lines.append("")
	var seeds: Array[int] = [11, 222, 3333, 44444, 555555]
	_lines.append("| 本局种子 | N12 的 8 艘 |")
	_lines.append("|---|---|")
	for sd in seeds:
		_lines.append("| %d | %s |" % [sd, _roster_desc("normal", 12, sd)])
	_lines.append("")
	_lines.append("> 再验证「普通与困难同种子同船」这条硬约束（用户指定）：")
	_lines.append("")
	_lines.append("| 本局种子 | 普通 | 困难 | 一致？ |")
	_lines.append("|---|---|---|---|")
	for sd in seeds:
		var n := _roster_desc("normal", 12, sd)
		var h := _roster_desc("hard", 12, sd)
		_lines.append("| %d | %s | %s | %s |" % [
			sd, n, h, "✅ 是" if n == h else "❌ **否**"])
	_lines.append("")


## 用某难度跑真实开局，返回某节点的敌舰中文名列表（逗号连接）
func _roster_desc(diff_id: String, node: int, p_seed: int) -> String:
	var r: EveRunState = RUN.new()
	r.set_difficulty(diff_id)
	r.start_run(p_seed)
	r.node_index = node
	var names := PackedStringArray()
	for e in r.enemy_roster():
		var d: Dictionary = DB.by_id(String(e.get("ship_key", "")))
		names.append(String(d.get("name", e.get("ship_key", "?"))))
	r.free()
	return "、".join(names) if names.size() > 0 else "（空）"


# ══════════════════════════════════════════════════════════════
#  ② 逐难度 × 逐节点详表
# ══════════════════════════════════════════════════════════════
func _dump_difficulty(diff_id: String) -> void:
	var d: Dictionary = FT.difficulty(diff_id)
	_lines.append("---")
	_lines.append("")
	_lines.append("## ②「%s」逐节点明细" % String(d["name"]))
	_lines.append("")

	for i in range(1, NODE.TOTAL + 1):
		var row: Dictionary = NODE.by_index(i)
		if row.is_empty():
			continue
		var ntype := StringName(row["type"])
		if ntype == &"event":
			_lines.append("### N%d · 事件节点（无战斗）" % i)
			_lines.append("")
			continue

		var run: EveRunState = RUN.new()
		run.set_difficulty(diff_id)
		run.start_run(4242)
		run.node_index = i
		# ⚠️ 事件节点的增益会污染敌方？不会 —— 敌方链不读事件。
		#    但 `enemy_scale()` 要 `current_node()` 正确，所以 node_index 必须先设。

		var comp_id := run.enemy_comp_id()
		var scale := run.enemy_scale()
		var base_scale := float(row.get("scale", 1.0))
		var roster := run.enemy_roster()

		# ★ 关键：**一次性**造出「最终舰队」（走完整生产链：倍率 → 敌方羁绊
		#   → 电子战干扰 → 炼狱壁垒），再与「裸实例」（基础值）按下标配对。
		#   ⛔ 不要按船单独重算 —— 羁绊是**编队级**的，单船算不出来。
		var fleet := _enemy_fleet(run)
		var base_list: Array = []
		for e in roster:
			base_list.append(DB.instantiate_by_id(String(e.get("ship_key", "")), 1, 0))
		var mismatch := fleet.size() != roster.size()
		var barrier := run.boss_barrier_mult()

		_lines.append("### N%d · %s · %s · %d 艘" % [
			i, NODE.label_of(ntype), COMPS.display_name(comp_id), roster.size()])
		_lines.append("")
		_lines.append("- 节点基础倍率 **×%.2f** × 难度倍率 **×%.2f** = 实际 **×%.3f**" % [
			base_scale, float(d["scale"]), scale])
		_lines.append("- 战斗时限 **%.0fs** · 阵型 `%s` · 进场词：「%s」" % [
			float(row.get("time", 0.0)), String(COMPS.by_id(comp_id).get("formation", "")),
			String(row.get("line", ""))])
		if mismatch:
			_lines.append("- ⚠️ 舰队实例数 %d ≠ 名单数 %d（有 id 在船表里不存在）"
					% [fleet.size(), roster.size()])
		# 敌方羁绊 —— 必须报**真正乘进敌舰的那几条**，否则会给出错误结论。
		#
		# ⚠️ 两个坑（都踩过，别再退回去）：
		#   ① `enemy_traits = false` 的档（简单/普通）**一条都不生效**。上一版
		#      无论档位都按 `_fleet_synergies` 打印，于是简单 N5 报「吃羁绊：
		#      艾玛 +20% 装甲」，可右边倍率表全是 ×1.00 —— 自相矛盾，且误导。
		#   ② 电子战(ew)是全表**唯一一条玩家侧羁绊**（削「玩家对面的敌方」
		#      开火间隔）：玩家凑出来才生效。敌方编组自己凑到 ew 时，
		#      `apply_fleet_traits → _apply_synergy` 根本不处理 `enemy_cycle_pct`
		#      ⇒ 对敌方是**彻头彻尾的 no-op**。⛔ 不能报成「敌方吃到电子战」。
		var eats := bool(d["enemy_traits"])
		var traits := EveRunState._fleet_synergies(fleet)
		var live := PackedStringArray()    # 真乘进敌舰的
		var off := PackedStringArray()     # 编组能满足，但本档不吃 ⇒ 不生效
		var ew_off := PackedStringArray()  # 电子战：敌方自己凑到无效果
		for t in traits:
			var grp := StringName(t["group"])
			var desc := "%s/%s %d 艘 → %s" % [String(grp), String(t["member"]),
					int(t["count"]), String(t["text"])]
			if grp == &"ew":
				ew_off.append(desc)
			elif eats:
				live.append(desc)
			else:
				off.append(desc)
		if live.is_empty():
			if eats:
				_lines.append("- 敌方羁绊（**实际生效**）：**无** —— 本档虽然吃羁绊，"
						+ "但这副编组各派系/武器/防御都不到阈值")
			else:
				_lines.append("- 敌方羁绊（**实际生效**）：**无** —— "
						+ "本档 `enemy_traits = false`，敌人一律白板")
		else:
			_lines.append("- 敌方羁绊（**实际生效**）：%s" % "；".join(live))
		if not off.is_empty():
			_lines.append("- ↳ 编组本身能满足、但**本档 `enemy_traits = false` 故不生效**：%s"
					% "；".join(off))
		if not ew_off.is_empty():
			_lines.append("- ↳ 编组含电子战船：%s —— ⚠️ 电子战是**玩家侧**羁绊"
					% "；".join(ew_off)
					+ "（削玩家所面对的敌方开火间隔）；**敌方自己凑到不产生任何效果**")
		if barrier < 1.0:
			_lines.append("- ★ **炼狱壁垒**：玩家没凑齐「%s」⇒ 敌方受击 ×%.2f "
					% [run.key_mechanic(), barrier]
					+ "⇒ 有效 EHP **×%.0f**" % (1.0 / barrier))
		_lines.append("")

		_lines.append("| # | 舰船 | 吨位 | 势力 | 武器 | 防御 | 定位 | 护盾 | 装甲 | 结构 | 攻击 | 开火间隔 | 移速 | 修量/间隔 |")
		_lines.append("|---|---|---|---|---|---|---|---|---|---|---|---|---|---|")
		for k in fleet.size():
			var s: EveShip = fleet[k]
			_lines.append("| %d | %s | %d | %s | %s | %s | %s | %.0f | %.0f | %.0f | %.0f | %.2fs | %.1f | %s |" % [
				k + 1, s.ship_name, s.cost, s.faction_name(), String(s.weapon_type),
				String(s.defense_type), String(s.role),
				float(s.max_hp[&"shield"]), float(s.max_hp[&"armor"]),
				float(s.max_hp[&"hull"]), s.weapon_damage, s.weapon_cycle,
				s.body.max_speed if s.body != null else 0.0,
				("%.1f / %.1fs" % [s.logistics_repair, s.logistics_cycle])
						if s.logistics_repair > 0.0 else "—",
			])
		_lines.append("")
		_lines.append("> 上表已是**最终值**（含敌方倍率 + 敌方羁绊 + 炼狱壁垒；"
				+ "⚠️ **不含**玩家电子战干扰，探针无玩家舰队）。"
				+ "逐艘倍率 = 最终 ÷ 基础（星级 1 · 无任何加成的裸值）：")
		_lines.append("")
		_lines.append("| # | 舰船 | 护盾 × | 装甲 × | 结构 × | 攻击 × | 开火间隔 × | 综合 EHP × |")
		_lines.append("|---|---|---|---|---|---|---|---|")
		for k in fleet.size():
			var s: EveShip = fleet[k]
			var b = base_list[k] if k < base_list.size() else null
			if b == null:
				continue
			var b_ehp: float = float(b.max_hp[&"shield"]) + float(b.max_hp[&"armor"]) \
					+ float(b.max_hp[&"hull"])
			var f_ehp: float = float(s.max_hp[&"shield"]) + float(s.max_hp[&"armor"]) \
					+ float(s.max_hp[&"hull"])
			_lines.append("| %d | %s | ×%.2f | ×%.2f | ×%.2f | ×%.2f | ×%.2f | **×%.2f** |" % [
				k + 1, s.ship_name,
				float(s.max_hp[&"shield"]) / maxf(1.0, float(b.max_hp[&"shield"])),
				float(s.max_hp[&"armor"]) / maxf(1.0, float(b.max_hp[&"armor"])),
				float(s.max_hp[&"hull"]) / maxf(1.0, float(b.max_hp[&"hull"])),
				s.weapon_damage / maxf(0.01, b.weapon_damage),
				s.weapon_cycle / maxf(0.01, b.weapon_cycle),
				f_ehp / maxf(1.0, b_ehp),
			])
		_lines.append("")

		# 该关总量
		var tot := _totals_of(fleet)
		_lines.append("**该关合计**：总 EHP **%.0f**（盾 %.0f / 甲 %.0f / 结构 %.0f） · "
				% [tot["ehp"], tot["shield"], tot["armor"], tot["hull"]]
				+ "总 DPS **%.1f** · 总维修 **%.1f/s** · 每艘平均 EHP %.0f"
				% [tot["dps"], tot["repair"], tot["ehp"] / maxf(1.0, float(fleet.size()))])
		if barrier < 1.0:
			_lines.append("")
			_lines.append("★ 计入壁垒后，玩家要打穿的**有效 EHP = %.0f**（原 %.0f × %.0f）。"
					% [tot["ehp"] / barrier, tot["ehp"], 1.0 / barrier])
		_lines.append("")
		run.free()


## 造一支敌方舰队（走生产链）
func _enemy_fleet(run: EveRunState) -> Array[EveShip]:
	var f := FACTORY.new()
	return f.build_enemy(run)


## 一支**已装配好**的舰队的汇总（含羁绊 / 电子战 / 壁垒之后的值）
func _totals_of(fleet: Array[EveShip]) -> Dictionary:
	var out := {"ehp": 0.0, "shield": 0.0, "armor": 0.0, "hull": 0.0,
			"dps": 0.0, "repair": 0.0}
	for s in fleet:
		out["shield"] += float(s.max_hp[&"shield"])
		out["armor"] += float(s.max_hp[&"armor"])
		out["hull"] += float(s.max_hp[&"hull"])
		out["dps"] += s.weapon_damage / maxf(0.05, s.weapon_cycle)
		out["repair"] += s.logistics_repair / maxf(0.05, s.logistics_cycle)
	out["ehp"] = out["shield"] + out["armor"] + out["hull"]
	# ⚠️ `EveShip` 是 RefCounted，⛔ 不要 free（free 会报错并中断函数）。
	return out


# ══════════════════════════════════════════════════════════════
#  ③ 难度爬升曲线（只看总量，15 关连起来看形状）
# ══════════════════════════════════════════════════════════════
func _totals_curve() -> void:
	_lines.append("---")
	_lines.append("")
	_lines.append("## ③ 难度爬升形状（每关敌方总量）")
	_lines.append("")
	_lines.append("⚠️ 只看**敌方总量**，不含玩家侧。用来判断「难度是台阶还是断崖」。")
	_lines.append("")
	_lines.append("| 节点 | 简单 EHP/DPS | 普通 EHP/DPS | 困难 EHP/DPS | 炼狱 EHP/DPS | 简单 艘 | 普通 艘 | 困难 艘 | 炼狱 艘 |")
	_lines.append("|---|---|---|---|---|---|---|---|---|")
	for i in range(1, NODE.TOTAL + 1):
		var row: Dictionary = NODE.by_index(i)
		if StringName(row.get("type", &"")) == &"event":
			_lines.append("| N%d | 事件 | 事件 | 事件 | 事件 | — | — | — | — |" % i)
			continue
		var cells := PackedStringArray()
		var counts := PackedStringArray()
		for d in FT.difficulties():
			var run: EveRunState = RUN.new()
			run.set_difficulty(String(d["id"]))
			run.start_run(4242)
			run.node_index = i
			var t := _totals_of(_enemy_fleet(run))
			cells.append("%.0f / %.1f" % [t["ehp"], t["dps"]])
			counts.append(str(run.enemy_roster().size()))
			run.free()
		_lines.append("| N%d | %s | %s | %s | %s | %s | %s | %s | %s |" % [
			i, cells[0], cells[1], cells[2], cells[3],
			counts[0], counts[1], counts[2], counts[3]])
	_lines.append("")
	_lines.append("> 「艘」= 该关敌方舰船数；「EHP/DPS」= 三层血总和 / 每秒总伤害。")
	_lines.append("")


# ══════════════════════════════════════════════════════════════
#  ④ 自动扫出的线索（供重设计定位，不是结论）
# ══════════════════════════════════════════════════════════════
func _anomalies() -> void:
	_lines.append("---")
	_lines.append("")
	_lines.append("## ④ 自动扫出的线索（供重设计定位，**不是结论**）")
	_lines.append("")
	_lines.append("### a. 相邻战斗节点的总 EHP 跳变 ≥ ×1.80")
	_lines.append("")
	_lines.append("| 档位 | 跳变 |")
	_lines.append("|---|---|")
	# 同一趟里顺手挑出「结构性虚胖」最严重的一艘（每档一艘）
	var worst := {}
	for d in FT.difficulties():
		var prev := -1.0
		var prev_i := 0
		for i in range(1, NODE.TOTAL + 1):
			var row: Dictionary = NODE.by_index(i)
			if StringName(row.get("type", &"")) == &"event":
				continue
			var run: EveRunState = RUN.new()
			run.set_difficulty(String(d["id"]))
			run.start_run(4242)
			run.node_index = i
			var fleet := _enemy_fleet(run)
			var roster := run.enemy_roster()
			var ehp: float = float(_totals_of(fleet)["ehp"])
			if prev > 0.0 and ehp / prev >= 1.80:
				_lines.append("| %s | N%d %.0f → N%d %.0f（**×%.2f**） |"
						% [String(d["name"]), prev_i, prev, i, ehp, ehp / prev])
			for k in fleet.size():
				if k >= roster.size():
					break
				var b := DB.instantiate_by_id(String(roster[k].get("ship_key", "")), 1, 0)
				var s: EveShip = fleet[k]
				var b_ehp: float = float(b.max_hp[&"shield"]) + float(b.max_hp[&"armor"]) \
						+ float(b.max_hp[&"hull"])
				var f_ehp: float = float(s.max_hp[&"shield"]) + float(s.max_hp[&"armor"]) \
						+ float(s.max_hp[&"hull"])
				var m := f_ehp / maxf(1.0, b_ehp)
				var key := String(d["id"])
				if not worst.has(key) or m > float(worst[key]["m"]):
					worst[key] = {"m": m, "node": i, "ship": s.ship_name, "cost": s.cost}
			prev = ehp
			prev_i = i
	_lines.append("")
	_lines.append("### b. 每档「结构性虚胖」最严重的一艘（综合 EHP 倍率最大）")
	_lines.append("")
	_lines.append("> 根因多为**结构 `+N` 固定加成**（flat）：底子越小，被放大的倍数越夸张。")
	_lines.append("")
	_lines.append("| 档位 | 节点 | 舰船 | 吨位 | 综合 EHP × |")
	_lines.append("|---|---|---|---|---|")
	for d in FT.difficulties():
		var key := String(d["id"])
		if not worst.has(key):
			continue
		var w: Dictionary = worst[key]
		_lines.append("| %s | N%d | %s | %d | **×%.2f** |" % [String(d["name"]),
				int(w["node"]), String(w["ship"]), int(w["cost"]), float(w["m"])])
	_lines.append("")
	_lines.append("### c. 炼狱 BOSS 的有效 EHP（壁垒 ×10）")
	_lines.append("")
	var run2: EveRunState = RUN.new()
	run2.set_difficulty("inferno")
	run2.start_run(4242)
	run2.node_index = 15
	var t2 := _totals_of(_enemy_fleet(run2))
	var bar := run2.boss_barrier_mult()
	run2.free()
	_lines.append("- 炼狱 N15：原 EHP **%.0f**，计入壁垒（受击 ×%.2f）后玩家需打穿 "
			% [float(t2["ehp"]), bar]
			+ "**%.0f**（= ×%.0f）。" % [float(t2["ehp"]) / bar, 1.0 / bar])
	_lines.append("")