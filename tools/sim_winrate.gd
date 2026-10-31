extends Node

## 通关率 / 难度体检（无头）
##
## 目的：
##   ① 现有「守卫边境」15 节点在三种玩家策略下的通关率；
##   ② 每节点胜率曲线（看难度是在哪一段陡增）；
##   ③ 战术姿态（环绕 / 保持距离）到底对结果有没有影响；
##   ④ 羁绊数值是否真的乘进舰船。
##
## ⚠️ 这是**统计探针**，不改任何生产数值。

const RUN := preload("res://scripts/core/eve_run_state.gd")
const FACTORY := preload("res://scripts/scene/eve_fleet_factory.gd")
const SIM := preload("res://scripts/core/eve_battle_simulator.gd")
const NODE := preload("res://scripts/data/eve_node_table.gd")
const COMPS := preload("res://scripts/data/eve_enemy_comps.gd")
const DB := preload("res://scripts/core/eve_ship_database.gd")
const FT := preload("res://scripts/data/eve_campaign_tiers.gd")

## 每种策略 × 每档难度跑多少局（固定种子，可复现）
const RUNS_PER_POLICY := 16
## 姿态对照实验每种组合跑多少局
const STANCE_RUNS := 10
## 只跑四档通关率（跳过单点实验，省时间）
const SWEEP_ONLY := true

## ⚠️ 临时诊断开关（2026-10-24）：反小船考点实验。
##    true = 只跑 `_anti_swarm_experiment()`（我方=典型护卫舰海，敌方=候选编组），
##    用来回答「哪种敌方编组真的能杀掉只堆 1 费护卫舰的打法」。
##    ⚠️ 它**不改任何生产表**：候选编组在这里临时构造。
const ANTI_SWARM_PROBE := false

## ⚠️ 临时诊断开关（2026-10-24）：BOSS 关专项。
##    true = 只跑 `_boss_experiment()`：固定几种我方末段编队 × BOSS 候选编组，
##    用来定位「炼狱 BOSS 对所有人都是 0%」是壁垒太厚还是护航太强。
const BOSS_PROBE := false

## 炼狱 BOSS「钥匙是否凑齐」逐局打印（排查用，默认关闭）
const KEY_DEBUG := false

## ⚠️ 临时诊断开关（2026-10-29）：TTK 体检。
##    true = 只跑 `_ttk_experiment()`：抗性归零 + 战列舰重做之后，
##    一场战斗究竟几秒打完，用来判断「60 秒战斗窗」是不是变太长了。
##    ⛔ 它不改任何生产数值（`old_resists` 那一列只是把抗性临时回填 0.45 做对照）。
##
## ── 实测结论（2026-10-29，96 局 · 12 种子 × 8 档）────────────────
##    平均 38.8s / 中位 41.4s / 90% 分位 45.1s / 超时限 1 局
##    单机 N1 37.7 · N5 44.7 · N8 41.3 · N12 21.6（碾压局）· BOSS 37.3
##    联机 6v6 43.1 · 战列对轰 42.7 · 战列 vs 护卫 41.7
##    抗性回填 0.45 对照：N8 48.3 · 6v6 55.0（4/12 超时）· 战列对轰 50.7 · 战列vs护卫 53.8
##    ⇒ 抗性归零把 TTK 缩短约 20~30%，**但 60 秒上限仍只有 1% 的对局会顶到**。
##    ★ 2026-10-29 防御型战列 +血 15% 之后再测：合计仍是 38.7s / 90% 分位 45.1s，
##      战列对轰 42.7s、BOSS 37.1s —— 因为探针阵容里的战列全是攻击型，血量没动。
const TTK_PROBE := false

## ★ 2026-10-31：TTK 系数敏感度扫描（见 `_ttk_sweep` 顶注）。
##    true = 只跑扫描：3 个场景 × 5 组系数，回答「再加伤害还能换几秒」。
const TTK_SWEEP := false

## ⚠️ 临时诊断开关（2026-10-26）：新羁绊「电子战 / 后勤」的加成值多少胜率。
##    true = 只跑 `_trait_ab_experiment()`：把**倍率**从编队成本里剥出来单独量化 ——
##      电子战：同一支 6 船队，敌方开火间隔 ×1.00 / 1.05 / 1.10 / 1.15
##      后勤　：同一支含后勤的队，维修量/间隔 ×1.00 / ×1.30 / ×1.50（2 档）
##              以及 ×1.75·0.8 / ×2.20·0.7（4 档）
##    ⛔ 它**不改任何生产表**，只在这里临时乘倍率。
##    ⚠️ 结论已抄进 `EveTraitTable.EFFECTS` 的注释里；要复测就把下面打开。
const TRAIT_AB_PROBE := false

## ⚠️ 临时诊断开关（2026-10-31）：电子战**重做后**的 A/B。
##    true = 只跑 `_ew_ab_experiment()`。
##
##    重做内容（用户定案）：减伤从「敌方全体开火变慢」改成「电子船锁定谁就削谁」，
##    并给每艘电子船加「每 5 秒掷一次、命中 10 秒不能开火」的干扰。
##
##    对照维度：
##      · 编队：2 / 4 / 6 艘电子船（正好对应 2 / 4 / 6 档）+ 一支纯火力参考队
##      · 强度：关闭 / 旧档 / 新档 / 新档+干扰
##    ⇒ 同一支编队内部比，能单独量出「羁绊收益」；
##      纯火力参考队用来回答「满档电子队到底追不追得上常规队」。
##
##    ⛔ 它不改任何生产表，只临时写 `is_ew` / `ew_lock_reduce` / `jam_chance`。
const EW_PROBE := false

const COL_STEP := 8000.0
const ROW_STEP := 6000.0
const STANDOFF_RATIO := 1.15
const ARENA_RADIUS_WORLD := 120.0
const WORLD_UNIT_IN_METERS := 1000.0
const CELL_METERS := 6000.0
const BOARD_CELL_UNITS := 6.0
const BOARD_HALF_UNITS := 33.0

## spam   = 点点点（乱买，不刷新不升级）
## normal = 会看利息、会升级、按战力买
## hard   = 还会挑防御类型、凑羁绊
## comp   = 真人认真玩：先定一个派系，整局往一套体系上堆（最接近「会玩」）
const POLICIES := ["spam", "normal", "hard", "comp"]

var _node_wins: Dictionary = {}
var _node_plays: Dictionary = {}


func _ready() -> void:
	print("=".repeat(84))
	print("EVE 自走棋 · 难度体检（守卫边境 15 节点）")
	print("=".repeat(84))
	if TTK_PROBE:
		_ttk_experiment()
		get_tree().quit()
		return
	if TTK_SWEEP:
		print("\n" + "=".repeat(84))
		print("⑤ TTK 系数敏感度扫描（叠在生产系数 1.20 / 0.85 之上）")
		print("=".repeat(84))
		_ttk_sweep()
		get_tree().quit()
		return
	if BOSS_PROBE:
		_boss_experiment()
		get_tree().quit()
		return
	if TRAIT_AB_PROBE:
		_trait_ab_experiment()
		get_tree().quit()
		return
	if EW_PROBE:
		_ew_ab_experiment()
		get_tree().quit()
		return
	if ANTI_SWARM_PROBE:
		_anti_swarm_experiment()
		get_tree().quit()
		return
	if not SWEEP_ONLY:
		_trait_check()
		_stance_census()
		_enemy_audit()
		_stance_experiment()
		_synergy_battle_test()
	_winrate_all()
	get_tree().quit()


# ══════════════════════════════════════════════════════════════
#  ① 羁绊数值校验
# ══════════════════════════════════════════════════════════════
func _trait_check() -> void:
	print("\n" + "=".repeat(84))
	print("① 羁绊是否真的乘进舰船（同 6 艘艾玛 / 6 艘加达里对照）")
	print("=".repeat(84))
	for pair in [["艾玛", 0], ["加达里", 1]]:
		var fac := int(pair[1])
		var run: Node = RUN.new()
		run.start_run(101 + fac)
		run.field.clear()
		var picked := 0
		for d in DB.all_ships():
			if int(d["faction"]) == fac and picked < 6:
				run.field.append({"ship_key": d["ship_key"], "star": 1,
						"cell": Vector2i(7, picked)})
				picked += 1
		var fac_tool := FACTORY.new()
		var fleet: Array = fac_tool.build_own(run)
		var armor_before := 0.0
		var shield_before := 0.0
		for s in fleet:
			var base: Dictionary = DB.by_id(String(s.ship_key))
			armor_before += float(base["armor"])
			shield_before += float(base["shield"])
		var armor_after := 0.0
		var shield_after := 0.0
		for s in fleet:
			armor_after += s.max_hp[&"armor"]
			shield_after += s.max_hp[&"shield"]
		var active: Array = run.active_synergies()
		print("  %s 6 艘：装甲 %.1f → %.1f（%+.0f%%） · 护盾 %.1f → %.1f（%+.0f%%）"
				% [String(pair[0]), armor_before, armor_after,
					(armor_after / maxf(1.0, armor_before) - 1.0) * 100.0,
					shield_before, shield_after,
					(shield_after / maxf(1.0, shield_before) - 1.0) * 100.0])
		print("     生效羁绊 = %s" % str(active))


# ══════════════════════════════════════════════════════════════
#  ①a 姿态普查：52 艘船出厂时各是什么姿态
# ══════════════════════════════════════════════════════════════
func _stance_census() -> void:
	print("\n" + "=".repeat(84))
	print("①a 战术姿态普查（52 艘船按吨位 → 出厂姿态）")
	print("=".repeat(84))
	var by_class: Dictionary = {}
	var by_stance: Dictionary = {}
	var id := 9000
	var fac := FACTORY.new()
	for d in DB.all_ships():
		var s = DB.instantiate_by_id(String(d["ship_key"]), 0, id)
		id += 1
		if s == null:
			continue
		var before: int = s.stance
		fac.apply_doctrine(s)
		var cls: String = s.class_name_cn()
		if not by_class.has(cls):
			by_class[cls] = {}
		var label: String = EveDestinyMotion.stance_label(s.stance)
		by_class[cls][label] = int(by_class[cls].get(label, 0)) + 1
		by_stance[label] = int(by_stance.get(label, 0)) + 1
		if before != s.stance:
			print("     ⚠ %s 被 apply_doctrine 改写姿态" % s.ship_name)
	for cls in by_class:
		print("     %-8s %s" % [cls, str(by_class[cls])])
	print("     合计：%s" % str(by_stance))
	print("     枚举中「接近战 / 拉开风筝 / 手动」三种在整局里从不出现（无 UI 可切换）")


# ══════════════════════════════════════════════════════════════
#  ①b 敌方调度审计：每关来的是什么船、总量多少
# ══════════════════════════════════════════════════════════════
func _enemy_audit() -> void:
	print("\n" + "=".repeat(84))
	print("①b 敌方调度审计（15 节点的 comp / scale / 总量）")
	print("=".repeat(84))
	print("  节点 类型    编组                  敌舰  总EHP  总DPS  武器构成（激光/混合/射弹/导弹）")
	var id := 5000
	for i in range(1, NODE.TOTAL + 1):
		var row: Dictionary = NODE.by_index(i)
		if row.is_empty() or NODE.is_event(i):
			print("  %2d   %-6s %s" % [i, String(row.get("type", "")), "（事件节点，无战斗）"])
			continue
		var comp := String(row.get("comp", ""))
		var scale := float(row.get("scale", 1.0))
		var ehp := 0.0
		var dps := 0.0
		var weapons := [0, 0, 0, 0]
		var n := 0
		for sid in COMPS.ship_ids(comp):
			var s = DB.instantiate_by_id(String(sid), 1, id)
			id += 1
			if s == null:
				continue
			RUN.apply_enemy_scaling(s, 1, scale)
			n += 1
			ehp += s.max_hp[&"shield"] + s.max_hp[&"armor"] + s.max_hp[&"hull"]
			dps += s.weapon_damage / maxf(0.1, s.weapon_cycle)
			match String(s.weapon_id):
				"laser": weapons[0] += 1
				"hybrid": weapons[1] += 1
				"proj": weapons[2] += 1
				"missile": weapons[3] += 1
		print("  %2d   %-6s %-20s %2d  %6.0f  %5.0f   %d/%d/%d/%d（scale %.2f）"
				% [i, String(row.get("type", "")), COMPS.display_name(comp) + "*",
					n, ehp, dps, weapons[0], weapons[1], weapons[2], weapons[3], scale])


# ══════════════════════════════════════════════════════════════
#  ② 姿态对照（环绕 / 保持距离 / 全部贴近）
# ══════════════════════════════════════════════════════════════
func _stance_experiment() -> void:
	print("\n" + "=".repeat(84))
	print("② 战术姿态对照：同一支舰队、同一批种子，只改 stance")
	print("=".repeat(84))
	print("  （每格 = 胜场/总场 · 平均耗时；我方固定 6 艘：3 护卫 + 2 巡洋 + 1 战巡）")
	var own_keys := ["punisher", "condor", "rifter", "omen", "caracal", "drake"]
	for node_idx in [1, 8, 15]:
		var row: Dictionary = NODE.by_index(node_idx)
		if row.is_empty():
			continue
		print("\n  ── 节点 %d（%s · %s · scale %.2f · 时限 %.0fs）──"
				% [node_idx, String(row.get("type", "")),
					String(row.get("comp", "")), float(row.get("scale", 1.0)),
					float(row.get("time", 45.0))])
		for mode in ["default", "keep", "orbit"]:
			var wins := 0
			var total_time := 0.0
			var own_dmg := 0.0
			var enemy_dmg := 0.0
			for k in STANCE_RUNS:
				var r := _stance_case(node_idx, own_keys, mode, 7000 + node_idx * 100 + k)
				wins += 1 if int(r["winner"]) == 0 else 0
				total_time += float(r["time"])
				own_dmg += float(r["own_damage"])
				enemy_dmg += float(r["enemy_damage"])
			print("     %-8s  胜 %2d/%d · 平均 %.1fs · 我伤 %.0f / 敌伤 %.0f"
					% [mode, wins, STANCE_RUNS, total_time / float(STANCE_RUNS),
						own_dmg / float(STANCE_RUNS), enemy_dmg / float(STANCE_RUNS)])


func _stance_case(node_idx: int, own_keys: Array, mode: String, seed_v: int) -> Dictionary:
	var row: Dictionary = NODE.by_index(node_idx)
	var fac := FACTORY.new()
	var own: Array = []
	var id := 1
	for key in own_keys:
		var s = DB.instantiate_by_id(String(key), 0, id)
		id += 1
		if s == null:
			continue
		fac.apply_doctrine(s)
		_set_stance(s, mode)
		own.append(s)
	var enemy: Array = []
	for sid in COMPS.ship_ids(String(row.get("comp", ""))):
		var e = DB.instantiate_by_id(String(sid), 1, id)
		id += 1
		if e == null:
			continue
		RUN.apply_enemy_scaling(e, 1, float(row.get("scale", 1.0)))
		fac.apply_doctrine(e)
		_set_stance(e, mode)
		enemy.append(e)
	var dz := _deploy_z(own, enemy)
	_place_own(own, dz[0], own_keys.size())
	_place_enemy(enemy, dz[1])
	var sim = SIM.new()
	sim.setup(_typed(own), _typed(enemy))
	sim.set_seed(seed_v)
	var limit := float(row.get("time", 45.0))
	sim.set_time_limit(limit)
	_run_sim(sim, limit)
	var own_dmg := 0.0
	var enemy_dmg := 0.0
	for s in own:
		own_dmg += s.damage_dealt
	for s in enemy:
		enemy_dmg += s.damage_dealt
	return {"winner": sim.winner_team, "time": sim.elapsed,
			"own_damage": own_dmg, "enemy_damage": enemy_dmg}


## 当前上阵里激光炮舰船数（诊断用：看"是不是还在死堆激光"）
func _laser_count(run) -> int:
	var n := 0
	for e in run.field_entries():
		var d: Dictionary = DB.by_id(String(e.get("ship_key", "")))
		if StringName(d.get("weapon_id", &"")) == &"laser":
			n += 1
	return n


## 炼狱里"我要往哪条破甲线上堆"（探针的真人建模）。
##
## 真人不会在第一天就宣布"我玩导弹"，而是**看商店给了什么**：
##   · 手里（上阵 + 备战席）哪条破甲线最多，就继续往那条线堆；
##   · 一条都没有时，按"打装甲墙的效率"排：导弹 > 射弹炮 > 混合炮 > 激光。
##
## ⚠️ 这只影响探针策略。生产规则是 `EveRunState.armor_break_power()`：
##    任意一条线凑够等效 6 艘就算开钥匙，**不要求是某一条**。
func _key_line_weapon(run) -> StringName:
	var lines: Array[StringName] = [&"missile", &"proj", &"hybrid", &"laser"]
	var counts: Dictionary = {}
	for line in lines:
		counts[line] = 0
	var tally := func(entries: Array) -> void:
		for e in entries:
			var d: Dictionary = DB.by_id(String(e.get("ship_key", "")))
			var wid := StringName(d.get("weapon_id", &""))
			if counts.has(wid):
				counts[wid] = int(counts[wid]) + 1
	tally.call(run.field_entries())
	tally.call(run.bench)
	var best: StringName = lines[0]
	for line in lines:
		if int(counts[line]) > int(counts[best]):
			best = line
	return best


## 无类型 Array → 战斗模拟器要求的 Array[EveShip]
func _typed(arr: Array) -> Array[EveShip]:
	var out: Array[EveShip] = []
	for s in arr:
		out.append(s)
	return out


## Stance 枚举顺序 = APPROACH(0) / KEEP(1) / ORBIT(2) / KITE(3) / MANUAL(4)
func _set_stance(s, mode: String) -> void:
	match mode:
		"keep":
			s.stance = 1
		"orbit":
			s.stance = 2
		_:
			pass


# ══════════════════════════════════════════════════════════════
#  ②c 新羁绊「电子战 / 后勤」的倍率价值（2026-10-26）
# ══════════════════════════════════════════════════════════════
##
## 为什么单独做这个实验：
##   羁绊在实战里同时带着**编队成本**（多带 2 艘后勤＝少 2 艘火力船），
##   直接比「开/关羁绊」会把倍率价值和成本混在一起，看不出数值本身值多少。
##   所以这里**固定编队**，只改倍率：
##     电子战 = 把敌方 `weapon_cycle` 乘 m（m = 1.00 / 1.05 / 1.10 / 1.15）
##     后勤   = 把后勤船 `logistics_repair` 乘 a、`logistics_cycle` 乘 c
##   这样每一行的差就是「这个倍率本身」的价值。
func _trait_ab_experiment() -> void:
	print("\n" + "=".repeat(84))
	print("②c 新羁绊倍率体检（固定编队，只改倍率；40 个固定种子 × 3 个节点）")
	print("=".repeat(84))
	var seeds := 40
	var nodes := [8, 13, 15]

	# ── 电子战：敌方开火间隔 ×m ──────────────────────────────
	print("\n【电子战】我方固定 6 艘（惩罚者/秃鹫/分裂者/启示/狞獾/幼龙）")
	var combat := ["punisher", "condor", "rifter", "omen", "caracal", "drake"]
	for m in [1.0, 1.05, 1.10, 1.15]:
		var wins := 0
		var plays := 0
		var taken := 0.0
		var dealt := 0.0
		var alive := 0.0
		for ni in nodes:
			for k in seeds:
				var r := _trait_ab_case(int(ni), combat, m, Vector2.ZERO, 8100 + int(ni) * 100 + k)
				plays += 1
				wins += 1 if int(r["winner"]) == 0 else 0
				taken += float(r["enemy_damage"])
				dealt += float(r["own_damage"])
				alive += float(r["alive"])
		print("   敌方间隔 ×%.2f（惩罚 %+.0f%%）  胜 %2d/%d · 存活 %.1f/6 · 我挨伤 %.0f · 我输出 %.0f"
				% [m, (1.0 / m - 1.0) * 100.0, wins, plays, alive / float(plays),
					taken / float(plays), dealt / float(plays)])

	# ── 后勤：维修量 ×a / 间隔 ×c（同一个编队内对照）────────────
	# ⚠️ 除了胜率，还记「平均剩余存活舰数」——维修的直接收益体现在 EHP 上，
	#    胜率被时限/斩杀线盖住了，看不出差别（实测 30% 时胜率一模一样）。
	print("\n【后勤】")
	for pair in [
			# [说明, 编队, [基准, 现推荐, 加码候选]]
			["4 火力 + 2 后勤（2 档）", ["punisher", "condor", "rifter", "omen",
					"navitas", "exequror"],
				[Vector2(1.0, 1.0), Vector2(1.30, 1.0), Vector2(1.50, 1.0)]],
			["2 火力 + 4 后勤（4 档）", ["punisher", "condor",
					"navitas", "exequror", "bantam", "scythe"],
				[Vector2(1.0, 1.0), Vector2(1.75, 0.8), Vector2(2.20, 0.7)]],
		]:
		var keys: Array = pair[1]
		print("   %s" % String(pair[0]))
		for mult in pair[2]:
			var v: Vector2 = mult
			var wins := 0
			var plays := 0
			var taken := 0.0
			var dealt := 0.0
			var alive := 0.0
			for ni in nodes:
				for k in seeds:
					var r := _trait_ab_case(int(ni), keys, 1.0, v, 8200 + int(ni) * 100 + k)
					plays += 1
					wins += 1 if int(r["winner"]) == 0 else 0
					taken += float(r["enemy_damage"])
					dealt += float(r["own_damage"])
					alive += float(r["alive"])
			print("     维修 ×%.2f / 间隔 ×%.2f  胜 %2d/%d · 存活 %.1f/%d · 我挨伤 %.0f · 我输出 %.0f"
					% [v.x, v.y, wins, plays, alive / float(plays), keys.size(),
						taken / float(plays), dealt / float(plays)])


## ★★ 2026-10-31（用户定案）电子战重做的 A/B。
##
## 为什么探针里**另存一份档位数值**：这一轮比的是「旧档 vs 新档」，
## 而旧档已经从 `eve_trait_table.gd` 删掉了 —— 不抄一份就没法做对照。
## ⚠️ 生产代码读的是 trait table，**不读这里**，两边不同步不影响游戏；
##    但下次再调档时，先改 trait table，再回来同步这两个表（否则对照会失真）。
##
## ★ 2026-10-31 第二轮：`EW_NEW` 跟着生产表提到 30/30/40，
##   第一轮的 20/20/40 留成 `EW_R20` 做对照 —— 用户拍板「按建议落地」时，
##   要有数字能回答「提到 30% 到底换回了几个百分点」。
##   ⚠️ `EW_NEW` **必须**与 `eve_trait_table.gd` 的 ew 档位逐字一致。
const EW_NEW := {
	0: {"reduce": 0.0, "cycle": 0.0},
	2: {"reduce": 0.30, "cycle": 0.0},
	4: {"reduce": 0.30, "cycle": 0.10},
	6: {"reduce": 0.40, "cycle": 0.20},
}
## 第一轮（2026-10-31 上午）的 20/20/40，留作对照。
const EW_R20 := {
	0: {"reduce": 0.0, "cycle": 0.0},
	2: {"reduce": 0.20, "cycle": 0.0},
	4: {"reduce": 0.20, "cycle": 0.10},
	6: {"reduce": 0.40, "cycle": 0.20},
}
const EW_OLD := {
	0: {"reduce": 0.0, "cycle": 0.0},
	2: {"reduce": 0.0, "cycle": 0.05},
	4: {"reduce": 0.0, "cycle": 0.10},
	6: {"reduce": 0.0, "cycle": 0.15},
}

func _ew_ab_experiment() -> void:
	print("\n" + "=".repeat(92))
	print("③ 电子战重做 A/B —— 同一编队内比强度，另设纯火力队做天花板参考")
	print("=".repeat(92))
	print("口径：40 种子 × 3 节点（N8/N13/N15）= 120 局/格；敌方编组与缩放沿用节点表")
	var seeds := 40
	var nodes := [8, 13, 15]
	# ⚠️ 6 艘上限，总费用尽量对齐（电子船便宜，这是它的定位，不强行拉平）
	var comps := [
		{"name": "2 电子 · 2 档", "n": 2, "cost": 10,
			"keys": ["condor", "tristan", "punisher", "rifter", "caracal", "thorax"]},
		{"name": "4 电子 · 4 档", "n": 4, "cost": 10,
			"keys": ["condor", "tristan", "slasher", "executioner", "caracal", "thorax"]},
		{"name": "6 电子 · 6 档", "n": 6, "cost": 10,
			"keys": ["condor", "tristan", "slasher", "executioner", "moa", "vexor"]},
		{"name": "纯火力 · 参考", "n": 0, "cost": 12,
			"keys": ["punisher", "rifter", "kestrel", "caracal", "thorax", "rupture"]},
	]
	var variants := [
		{"id": "off", "desc": "关闭（基线）"},
		{"id": "old", "desc": "旧档：全体间隔 +5/10/15%"},
		{"id": "r20", "desc": "新档·第一轮"},
		{"id": "new", "desc": "新档·本轮（生产值）"},
		{"id": "jam", "desc": "新档·本轮 + 单船干扰"},
	]
	for comp in comps:
		var n := int(comp["n"])
		var tier_old: Dictionary = EW_OLD[n]
		var tier_new: Dictionary = EW_NEW[n]
		var tier_r20: Dictionary = EW_R20[n]
		print("\n【%s】%d 费 · %s" % [String(comp["name"]), int(comp["cost"]),
				", ".join(PackedStringArray(comp["keys"]))])
		var base_wins := -1
		for v in variants:
			var vid := String(v["id"])
			var reduce := 0.0
			var cycle := 0.0
			var jam := false
			match vid:
				"old":
					reduce = float(tier_old["reduce"])
					cycle = float(tier_old["cycle"])
				"r20":
					reduce = float(tier_r20["reduce"])
					cycle = float(tier_r20["cycle"])
				"new":
					reduce = float(tier_new["reduce"])
					cycle = float(tier_new["cycle"])
				"jam":
					reduce = float(tier_new["reduce"])
					cycle = float(tier_new["cycle"])
					jam = true
			var wins := 0
			var plays := 0
			var taken := 0.0
			var dealt := 0.0
			var alive := 0.0
			var secs := 0.0
			for ni in nodes:
				for k in seeds:
					var r := _ew_case(int(ni), comp["keys"], reduce, cycle, jam,
							3100 + int(ni) * 100 + k)
					plays += 1
					wins += 1 if int(r["winner"]) == 0 else 0
					taken += float(r["enemy_damage"])
					dealt += float(r["own_damage"])
					alive += float(r["alive"])
					secs += float(r["time"])
			if base_wins < 0:
				base_wins = wins
			var delta := wins - base_wins if vid != "off" else 0
			print("   %-22s [减伤%2.0f%% 间隔+%2.0f%%] 胜 %2d/%d (%+.0f%%) · 存活 %.1f/6 · 我挨伤 %.0f · 我输出 %.0f · 平均 %.1fs"
					% [String(v["desc"]), reduce * 100.0, cycle * 100.0,
						wins, plays, float(delta) * 100.0 / float(maxi(1, plays)),
						alive / float(plays), taken / float(plays), dealt / float(plays),
						secs / float(plays)])


## 一格 = 同一编队 × 同一强度 × 一个种子。
## ⚠️ 电子战字段**直接写**在 `EveShip` 上，不走工厂 ——
##    工厂的入口要一个真实的 `EveRunState`（要凑羁绊、要上场名单），
##    探针里只想控制「减伤 / 间隔 / 干扰」这三个旋钮。
func _ew_case(node_idx: int, keys: Array, reduce: float, enemy_cycle: float,
		jam: bool, seed_v: int) -> Dictionary:
	var row: Dictionary = NODE.by_index(node_idx)
	var fac := FACTORY.new()
	var own: Array = []
	var id := 1
	for key in keys:
		var s = DB.instantiate_by_id(String(key), 0, id)
		id += 1
		if s == null:
			continue
		fac.apply_doctrine(s)
		if EveTraitTable.EW_SHIP_KEYS.has(String(key)):
			s.is_ew = true
			s.ew_lock_reduce = reduce
			if jam:
				s.jam_chance = EveShip.jam_chance_for_class(s.ship_class)
			s.jam_timer = EveShip.JAM_CYCLE
		own.append(s)
	var enemy: Array = []
	for sid in COMPS.ship_ids(String(row.get("comp", ""))):
		var e = DB.instantiate_by_id(String(sid), 1, id)
		id += 1
		if e == null:
			continue
		RUN.apply_enemy_scaling(e, 1, float(row.get("scale", 1.0)))
		fac.apply_doctrine(e)
		if enemy_cycle > 0.0:
			e.cycle_scale(1.0 + enemy_cycle)
		enemy.append(e)
	var dz := _deploy_z(own, enemy)
	_place_own(own, dz[0], own.size())
	_place_enemy(enemy, dz[1])
	var sim = SIM.new()
	sim.setup(_typed(own), _typed(enemy))
	sim.set_seed(seed_v)
	var limit := float(row.get("time", 45.0))
	sim.set_time_limit(limit)
	_run_sim(sim, limit)
	var own_dmg := 0.0
	var enemy_dmg := 0.0
	var alive := 0
	for s in own:
		own_dmg += s.damage_dealt
		if s.alive:
			alive += 1
	for s in enemy:
		enemy_dmg += s.damage_dealt
	return {"winner": sim.winner_team, "time": sim.elapsed, "alive": alive,
			"own_damage": own_dmg, "enemy_damage": enemy_dmg}


func _trait_ab_case(node_idx: int, keys: Array, enemy_cycle: float,
		logi_mult: Vector2, seed_v: int) -> Dictionary:
	var row: Dictionary = NODE.by_index(node_idx)
	var fac := FACTORY.new()
	var own: Array = []
	var id := 1
	for key in keys:
		var s = DB.instantiate_by_id(String(key), 0, id)
		id += 1
		if s == null:
			continue
		fac.apply_doctrine(s)
		# 后勤倍率只乘「本来就是后勤」的船（与 `EveShip.repair_scale` 同口径）
		if logi_mult != Vector2.ZERO and s.logistics_repair > 0.0:
			s.repair_scale(logi_mult.x, logi_mult.y)
		own.append(s)
	var enemy: Array = []
	for sid in COMPS.ship_ids(String(row.get("comp", ""))):
		var e = DB.instantiate_by_id(String(sid), 1, id)
		id += 1
		if e == null:
			continue
		RUN.apply_enemy_scaling(e, 1, float(row.get("scale", 1.0)))
		fac.apply_doctrine(e)
		if not is_equal_approx(enemy_cycle, 1.0):
			e.cycle_scale(enemy_cycle)
		enemy.append(e)
	var dz := _deploy_z(own, enemy)
	_place_own(own, dz[0], own.size())
	_place_enemy(enemy, dz[1])
	var sim = SIM.new()
	sim.setup(_typed(own), _typed(enemy))
	sim.set_seed(seed_v)
	var limit := float(row.get("time", 45.0))
	sim.set_time_limit(limit)
	_run_sim(sim, limit)
	var own_dmg := 0.0
	var enemy_dmg := 0.0
	var alive := 0
	for s in own:
		own_dmg += s.damage_dealt
		if s.alive:
			alive += 1
	for s in enemy:
		enemy_dmg += s.damage_dealt
	return {"winner": sim.winner_team, "time": sim.elapsed, "alive": alive,
			"own_damage": own_dmg, "enemy_damage": enemy_dmg}


# ══════════════════════════════════════════════════════════════
#  ②b 羁绊对战斗结果的真实影响（同一批船，开/关羁绊）
# ══════════════════════════════════════════════════════════════
func _synergy_battle_test() -> void:
	print("\n" + "=".repeat(84))
	print("②b 羁绊对战局的影响（6 艘艾玛，开 / 关羁绊，同种子）")
	print("=".repeat(84))
	var amarr: Array[String] = []
	for d in DB.all_ships():
		if int(d["faction"]) == 0 and amarr.size() < 6:
			amarr.append(String(d["ship_key"]))
	for node_idx in [5, 13, 15]:
		var row: Dictionary = NODE.by_index(node_idx)
		print("\n  ── 节点 %d（%s · 时限 %.0fs）──"
				% [node_idx, String(row.get("comp", "")), float(row.get("time", 45.0))])
		for with_traits in [true, false]:
			var wins := 0
			var own_dmg := 0.0
			for k in 6:
				var r := _synergy_case(node_idx, amarr, with_traits, 3300 + node_idx * 40 + k)
				wins += 1 if int(r["winner"]) == 0 else 0
				own_dmg += float(r["own_damage"])
			print("     羁绊 %-2s  胜 %d/6 · 我伤 %.0f"
					% ["开" if with_traits else "关", wins, own_dmg / 6.0])


func _synergy_case(node_idx: int, keys: Array, with_traits: bool, seed_v: int) -> Dictionary:
	var row: Dictionary = NODE.by_index(node_idx)
	var fac := FACTORY.new()
	var own: Array = []
	var id := 1
	if with_traits:
		# 走真实链路：先在 run 里布阵，再由 EveFleetFactory 乘羁绊
		var run: Node = RUN.new()
		run.start_run(seed_v)
		run.field.clear()
		for k in keys:
			run.field.append({"ship_key": StringName(k), "star": 1,
					"cell": Vector2i(7, own.size())})
		own = fac.build_own(run)
	else:
		for k in keys:
			var s = DB.instantiate_by_id(String(k), 0, id)
			id += 1
			if s == null:
				continue
			fac.apply_doctrine(s)
			own.append(s)
	var enemy: Array = []
	for sid in COMPS.ship_ids(String(row.get("comp", ""))):
		var e = DB.instantiate_by_id(String(sid), 1, id)
		id += 1
		if e == null:
			continue
		RUN.apply_enemy_scaling(e, 1, float(row.get("scale", 1.0)))
		fac.apply_doctrine(e)
		enemy.append(e)
	var dz := _deploy_z(own, enemy)
	_place_own(own, dz[0], own.size())
	_place_enemy(enemy, dz[1])
	var sim = SIM.new()
	sim.setup(_typed(own), _typed(enemy))
	sim.set_seed(seed_v)
	var limit := float(row.get("time", 45.0))
	sim.set_time_limit(limit)
	_run_sim(sim, limit)
	var own_dmg := 0.0
	for s in own:
		own_dmg += s.damage_dealt
	return {"winner": sim.winner_team, "own_damage": own_dmg}


# ══════════════════════════════════════════════════════════════
#  ②b 反常排查：为什么「普通档 spam 通关率 > normal」
# ══════════════════════════════════════════════════════════════
##
## 病象：普通档 spam 94% / normal 69%，而 normal 的 EHP 反而高 54%。
## 本诊断把「每一场战斗的双方构成 + 结果」原样打出来，用来判断根因在哪一层：
##   ① 探针策略建模（例如 normal 买了一堆不开火的「后勤」船）
##   ② 战斗模拟器（同一支更强舰队反而打不过）
## ⚠️ 只打日志，不改任何数值。
func _anomaly_probe() -> void:
	print("\n" + "=".repeat(84))
	print("②b 反常排查：困难档 spam vs comp（逐节点构成 + 结果）")
	print("=".repeat(84))
	for policy in ["spam", "comp"]:
		print("\n" + "─".repeat(84))
		print("【困难 · %s】2 局固定种子" % policy)
		print("─".repeat(84))
		var cleared := 0
		for k in 2:
			var r := _play_run(policy, "hard", 424242 + k * 7919, true)
			if bool(r["cleared"]):
				cleared += 1
		print("      ⇒ %s 通关 %d/2" % [policy, cleared])


## 一场战斗的双方构成 + 结果（只被 `_anomaly_probe` 用）
func _line_report(policy: String, run, own: Array, enemy: Array, sim,
		tally: Dictionary = {}) -> void:
	var own_ehp := 0.0
	var own_dps := 0.0
	var own_logi := 0
	for s in own:
		own_ehp += s.max_hp[&"shield"] + s.max_hp[&"armor"] + s.max_hp[&"hull"]
		own_dps += s.weapon_damage / maxf(0.1, s.weapon_cycle)
		if s.is_logistics_unit():
			own_logi += 1
	var foe_ehp := 0.0
	var foe_dps := 0.0
	var foe_logi := 0
	for s in enemy:
		foe_ehp += s.max_hp[&"shield"] + s.max_hp[&"armor"] + s.max_hp[&"hull"]
		foe_dps += s.weapon_damage / maxf(0.1, s.weapon_cycle)
		if s.is_logistics_unit():
			foe_logi += 1
	var own_alive := 0
	var foe_alive := 0
	var own_dmg := 0.0
	var foe_dmg := 0.0
	for s in own:
		if s.alive:
			own_alive += 1
		own_dmg += s.damage_dealt
	for s in enemy:
		if s.alive:
			foe_alive += 1
		foe_dmg += s.damage_dealt
	print("      [%s] N%d 我 %d艘(EHP %.0f DPS %.0f 后勤 %d) vs 敌 %d艘(EHP %.0f DPS %.0f 后勤 %d) · 币%d 备战%d"
			% [policy, run.node_index, own.size(), own_ehp, own_dps, own_logi,
				enemy.size(), foe_ehp, foe_dps, foe_logi, run.coin, run.bench.size()])
	print("              → %s %.1fs · 存活 我 %d/%d 敌 %d/%d · 伤害 我 %.0f / 敌 %.0f"
			% ["胜" if sim.winner_team == 0 else "负", sim.elapsed,
				own_alive, own.size(), foe_alive, enemy.size(), own_dmg, foe_dmg])
	# ★ 命中率（按阵营）—— 追踪/信号半径机制的"体温计"。
	#   大炮打小船时 angular 高 ⇒ 命中率崩掉；这一列是诊断的核心证据。
	if not tally.is_empty():
		var own_hit: Array = tally.get(0, [0, 0])
		var foe_hit: Array = tally.get(1, [0, 0])
		print("              命中率：我方 %d/%d（%.0f%%） · 敌方 %d/%d（%.0f%%）"
				% [int(own_hit[0]), int(own_hit[1]),
					100.0 * float(own_hit[0]) / maxf(1.0, float(own_hit[1])),
					int(foe_hit[0]), int(foe_hit[1]),
					100.0 * float(foe_hit[0]) / maxf(1.0, float(foe_hit[1]))])
	# 双方编成（星号 = 星级，c = 费用）—— 看「乱点」到底买出了什么
	var names := PackedStringArray()
	for s in own:
		var d: Dictionary = DB.by_id(String(s.ship_key))
		names.append("%s%d★c%d" % [String(s.ship_key).substr(0, 4), s.star,
				int(d.get("cost", 1))])
	print("              我方：%s" % " ".join(names))
	names = PackedStringArray()
	for s in enemy:
		names.append("%s%d★" % [String(s.ship_key).substr(0, 4), s.star])
	print("              敌方：%s" % " ".join(names))


# ══════════════════════════════════════════════════════════════
#  ②c 反小船考点实验（2026-10-24）
# ══════════════════════════════════════════════════════════════
##
## 病根（证据见「②b」的命中率列）：只堆 1 费护卫舰就能赢，因为
## 护卫舰信号半径 36 + 环绕姿态 ⇒ 敌方大船（炮塔）的
## `tracking_factor = 0.5^((angular × sig_res)/(tracking × sig))²` 直接崩到 5~30%。
## 而**导弹 `WEAPON_TRACKING = 999`**（必中），只受爆炸半径限制 ⇒
## 只有「小号导弹船」能真的打中它们 —— 现实中也就是轻导弹/火箭打护卫舰。
##
## ⚠️ 关于 EHP 的算术（决定了本实验的候选集）：
##   典型的点点点舰队 ≈ 7 艘 × ~300 EHP ≈ 2100 EHP，而
##   敌方一个编组只有 4~6 艘 ⇒ 光看"血量+火力"它赢不了。**必须靠命中率**。
##   所以候选集只围绕「加达里导弹船 + 小船数量」这一个轴展开。
##
## 本函数回答一个具体问题：**哪种敌方编组能让「护卫舰海」真的输**？
##   · 目标：我方胜率压到 30% 以下（那样 15 个节点里能输掉 5~7 场）
##   · 若全部候选都压不下去 ⇒ 结论是"编组这一层不够"，必须动战斗机制。
func _anti_swarm_experiment() -> void:
	print("\n" + "=".repeat(84))
	print("②c 反小船考点实验（我方 3 种水平 × 敌方候选编组）")
	print("=".repeat(84))
	# 我方三支舰队 = 探针实测到的真实末段编成（见「②b」我方清单）
	var own_sets: Array = [
		["乱点 7 艘（1 费混编）",
			["punisher", "navitas", "condor", "kestrel", "rifter", "tristan", "catalyst"],
			[1, 2, 2, 1, 1, 1, 1]],
		["会玩 8 艘（2~3 费混编）",
			["punisher", "kestrel", "condor", "vexor", "moa", "stabber",
				"corax", "catalyst"],
			[1, 1, 2, 1, 1, 1, 2, 2]],
		["重甲 8 艘（3~4 费 · 对照组）",
			["maller", "omen", "ferox", "moa", "drake", "caracal",
				"vexor", "thorax"],
			[1, 1, 1, 1, 1, 1, 1, 1]],
	]
	# ⚠️ 本轮测「混合编组」：纯狼群的水位太陡（10 艘 100% → 11 艘 13%），
	#   所以把几艘重船混进去，用「导弹数量」当连续旋钮。
	var waves: Array = [
		["4 导弹 + 2 巡洋", ["kestrel", "condor", "cormorant", "corax", "moa", "caracal"]],
		["6 导弹 + 2 巡洋", ["kestrel", "condor", "cormorant", "corax", "kestrel",
			"condor", "moa", "caracal"]],
		["8 导弹 + 2 巡洋", ["kestrel", "condor", "cormorant", "corax", "kestrel",
			"condor", "cormorant", "corax", "moa", "caracal"]],
		["8 导弹 + 2 巡洋 + 后勤", ["kestrel", "condor", "cormorant", "corax", "kestrel",
			"condor", "cormorant", "corax", "moa", "caracal", "osprey"]],
		["10 导弹 + 2 巡洋", ["kestrel", "condor", "cormorant", "corax", "kestrel",
			"condor", "cormorant", "corax", "kestrel", "condor", "moa", "caracal"]],
		["6 导弹 + 2 战巡锚点", ["kestrel", "condor", "cormorant", "corax", "kestrel",
			"condor", "ferox", "drake"]],
		["8 导弹 + 4 巡洋", ["kestrel", "condor", "cormorant", "corax", "kestrel",
			"condor", "cormorant", "corax", "moa", "caracal", "ferox", "drake"]],
		["6 导弹 + 3 巡洋", ["kestrel", "condor", "cormorant", "corax", "kestrel",
			"condor", "moa", "caracal", "ferox"]],
	]
	const SEEDS := 10
	var tiers: Array = [
		["普通口径（×1.05 · 无羁绊）", 1.05, false],
		["困难口径（×1.15 · 吃羁绊）", 1.15, true],
	]
	for t in tiers:
		var scale := float(t[1])
		var traits_on := bool(t[2])
		var head := "     "
		for w in waves:
			head += "%-16s" % String(w[0])
		print("\n  %s · 每格 = 我方（玩家）胜率" % String(t[0]))
		print(head)
		print("    " + "─".repeat(16 * waves.size()))
		for os in own_sets:
			var line := "%-22s" % String(os[0])
			for w in waves:
				var wins := 0
				for k in SEEDS:
					var r := _anti_swarm_case(os[1], os[2], w[1], scale, traits_on,
							8100 + k * 977)
					wins += 1 if int(r["winner"]) == 0 else 0
				line += "%-16s" % ("%d%%" % int(round(100.0 * float(wins) / float(SEEDS))))
			print(line)


## 一场「护卫舰海 vs 候选编组」。★ 我方走**真实链路**（build_own）——
## 羁绊 / 星级 / 后勤修理全都生效，否则实验结论不成立。
func _anti_swarm_case(own_keys: Array, own_stars: Array, foe_keys: Array,
		scale: float, foe_traits: bool, seed_v: int) -> Dictionary:
	var run: Node = RUN.new()
	run.set_difficulty("normal")
	run.start_run(seed_v)
	run.field.clear()
	for i in own_keys.size():
		run.field.append({"ship_key": StringName(own_keys[i]),
				"star": int(own_stars[i]) if i < own_stars.size() else 1,
				"cell": Vector2i(7, i)})
	var fac := FACTORY.new()
	var own: Array = fac.build_own(run)
	var enemy: Array = []
	var id := 1000
	for key in foe_keys:
		var e = DB.instantiate_by_id(String(key), 1, id)
		id += 1
		if e == null:
			continue
		RUN.apply_enemy_scaling(e, 1, scale)
		fac.apply_doctrine(e)
		enemy.append(e)
	if foe_traits:
		RUN.apply_fleet_traits(enemy)
	var dz := _deploy_z(own, enemy)
	_place_own(own, dz[0], own.size())
	_place_enemy(enemy, dz[1])
	var sim = SIM.new()
	sim.setup(_typed(own), _typed(enemy))
	sim.set_seed(seed_v)
	sim.set_ai_level(1)
	sim.set_time_limit(45.0)
	var tally: Array = [0, 0]
	sim.shot_fired.connect(func(a, _t, hit, _q, _d):
		if int(a.team) == 1:
			tally[1] = int(tally[1]) + 1
			if hit:
				tally[0] = int(tally[0]) + 1)
	_run_sim(sim, 45.0)
	var own_dmg := 0.0
	var foe_dmg := 0.0
	for s in own:
		own_dmg += s.damage_dealt
	for s in enemy:
		foe_dmg += s.damage_dealt
	return {"winner": sim.winner_team, "time": sim.elapsed,
			"own_damage": own_dmg, "foe_damage": foe_dmg,
			"foe_hits": int(tally[0]), "foe_shots": int(tally[1])}


# ══════════════════════════════════════════════════════════════
#  ②d BOSS 关专项（2026-10-24）
# ══════════════════════════════════════════════════════════════
##
## 为什么单独量 BOSS：通关判定只有一个闸门 = **打得过 BOSS**。
## 中段输几场只扣信标，只要 BOSS 过得去，整局就算通关 ⇒ 整档通关率
## 基本等于「BOSS 单场胜率 × 血量够不够」。
## 所以 BOSS 一旦对所有人都 0%（炼狱就是这么死的），整档必然全 0%，
## 而原因可能是两件完全不同的事：
##   ① BOSS 的**壁垒**（`incoming_mult`，需要 6 激光破解）太厚；
##   ② 护航的**必中导弹**太多，把我方 DPS 提前磨光。
## 本函数把两者拆开量。
func _boss_experiment() -> void:
	print("\n" + "=".repeat(84))
	print("②d BOSS 关专项：我方 4 种末段编队 × BOSS 候选构成")
	print("=".repeat(84))
	# 我方末段编队（按探针实测的三种水平 + 一种"为破壁垒凑的 6 激光"）
	var own_sets: Array = [
		["乱点 7 艘（1 费混编）",
			["punisher", "navitas", "condor", "kestrel", "rifter", "tristan", "catalyst"],
			[1, 2, 2, 1, 1, 1, 1]],
		["会玩 7 艘（2~3 费混编）",
			["vexor", "moa", "stabber", "caracal", "catalyst", "thorax", "omen"],
			[1, 1, 1, 1, 2, 1, 1]],
		["重甲 7 艘（3~4 费）",
			["maller", "omen", "ferox", "moa", "drake", "caracal", "vexor"],
			[1, 1, 1, 1, 1, 1, 1]],
		["6 激光（为破壁垒凑的体系）",
			["maller", "omen", "punisher", "tormentor", "executioner", "augoror", "maller"],
			[1, 1, 1, 1, 1, 1, 2]],
	]
	# BOSS 候选：壁垒开/关 × 护航数量
	var foes: Array = [
		["纯壁垒 6（无护航）", ["abaddon", "prophecy", "maller", "omen", "dragoon", "coercer"]],
		["壁垒 6 + 2 导弹", ["abaddon", "prophecy", "maller", "omen", "dragoon", "coercer",
			"kestrel", "condor"]],
		["壁垒 6 + 3 导弹", ["abaddon", "prophecy", "maller", "omen", "dragoon", "coercer",
			"kestrel", "condor", "cormorant"]],
		["海盗王 6（无护航）", ["abaddon", "myrmidon", "drake", "caracal", "scythe", "thorax"]],
		["海盗王 6 + 2 导弹", ["abaddon", "myrmidon", "drake", "caracal", "scythe", "thorax",
			"kestrel", "condor"]],
		["海盗王 6 + 3 导弹", ["abaddon", "myrmidon", "drake", "caracal", "scythe", "thorax",
			"kestrel", "condor", "cormorant"]],
		["海盗王 6 + 4 导弹", ["abaddon", "myrmidon", "drake", "caracal", "scythe", "thorax",
			"kestrel", "condor", "cormorant", "corax"]],
		["海盗王 6 + 6 导弹", ["abaddon", "myrmidon", "drake", "caracal", "scythe", "thorax",
			"kestrel", "condor", "cormorant", "corax", "kestrel", "condor"]],
	]
	const SEEDS := 8
	var tiers: Array = [
		["普通口径（×1.05 · 无羁绊 · 无壁垒）", 1.05, false, false],
		["困难口径（×1.15 · 吃羁绊 · 无壁垒）", 1.15, true, false],
		["炼狱口径 ×1.25（吃羁绊 · 壁垒）", 1.25, true, true],
		["炼狱口径 ×1.15（吃羁绊 · 壁垒）", 1.15, true, true],
		["炼狱口径 ×1.10（吃羁绊 · 壁垒）", 1.10, true, true],
	]
	for t in tiers:
		var head := "     "
		for f in foes:
			head += "%-22s" % String(f[0])
		print("\n  %s · 每格 = 我方胜率" % String(t[0]))
		print(head)
		print("    " + "─".repeat(22 * foes.size()))
		for os in own_sets:
			var line := "%-26s" % String(os[0])
			for f in foes:
				var wins := 0
				for k in SEEDS:
					var r := _boss_case(os[1], os[2], f[1], float(t[1]),
							bool(t[2]), bool(t[3]), 3300 + k * 613)
					wins += 1 if int(r["winner"]) == 0 else 0
				line += "%-22s" % ("%d%%" % int(round(100.0 * float(wins) / float(SEEDS))))
			print(line)
	print("\n  ⚠️ 「壁垒 0.1」= 没凑够 6 激光时，敌方只受 10% 伤害（见 EveRunState）。")


func _boss_case(own_keys: Array, own_stars: Array, foe_keys: Array, scale: float,
		foe_traits: bool, wall: bool, seed_v: int) -> Dictionary:
	var run: Node = RUN.new()
	run.set_difficulty("inferno" if wall else "hard")
	run.start_run(seed_v)
	run.field.clear()
	for i in own_keys.size():
		run.field.append({"ship_key": StringName(own_keys[i]),
				"star": int(own_stars[i]) if i < own_stars.size() else 1,
				"cell": Vector2i(7, i)})
	var fac := FACTORY.new()
	var own: Array = fac.build_own(run)
	# ⚠️ 与生产同口径：**钥匙开出来了就不该挨壁垒**。
	#    判据走 `armor_break_power()`（破甲体系整类，不是只数激光）。
	var pierced: bool = run.armor_break_power() >= RUN.ARMOR_BREAK_NEED
	var enemy: Array = []
	var id := 1000
	for key in foe_keys:
		var e = DB.instantiate_by_id(String(key), 1, id)
		id += 1
		if e == null:
			continue
		RUN.apply_enemy_scaling(e, 1, scale)
		fac.apply_doctrine(e)
		if wall and not pierced:
			e.incoming_mult = 0.1
		enemy.append(e)
	if foe_traits:
		RUN.apply_fleet_traits(enemy)
	var dz := _deploy_z(own, enemy)
	_place_own(own, dz[0], own.size())
	_place_enemy(enemy, dz[1])
	var sim = SIM.new()
	sim.setup(_typed(own), _typed(enemy))
	sim.set_seed(seed_v)
	sim.set_ai_level(0 if not foe_traits else 2)
	sim.set_time_limit(90.0)
	_run_sim(sim, 90.0)
	return {"winner": sim.winner_team}


# ══════════════════════════════════════════════════════════════
#  ④ TTK 体检（2026-10-29）
# ══════════════════════════════════════════════════════════════
##
## 回答的问题：抗性全归 0 + 战列舰重做之后，**一场战斗实际打多久**？
## 60 秒战斗窗是不是变成了「20 秒打完、40 秒干等」？
##
## 口径：
##   · 我方走 `build_own`（真实编制链，吃星级倍率），敌方走节点表编组 + `apply_enemy_scaling`。
##   · 每格 12 个固定种子；打印 平均 / 中位 / 区间，以及
##     「时限内结束」「火力渐增(时限 60%)之前就结束」两档占比。
##   · `old_resists` 那一列把双方抗性临时回填 0.45（改前的量级），只作对照。
func _ttk_experiment() -> void:
	print("\n" + "=".repeat(84))
	print("④ TTK 体检：一场战斗几秒打完（抗性归零 + 战列舰重做之后）")
	print("=".repeat(84))
	print("  每格 12 局固定种子；「渐增前」= 在时限 %.0f%% 处（伤害开始放大）之前就打完"
			% (SIM.SUDDEN_DEATH_FRACTION * 100.0))
	var seeds := 12
	var cruisers := ["omen", "caracal", "drake", "punisher", "rifter", "condor"]
	var cases: Array = [
		{"name": "单机 N1  开局 3 护卫 1★", "node": 1, "limit": 60.0,
			"own": ["punisher", "condor", "rifter"], "stars": [1, 1, 1]},
		{"name": "单机 N5  首个精英 · 5 艘 1★", "node": 5, "limit": 60.0,
			"own": ["punisher", "rifter", "omen", "caracal", "condor"],
			"stars": [1, 1, 1, 1, 1]},
		{"name": "单机 N8  中期 · 6 艘 2★", "node": 8, "limit": 60.0,
			"own": cruisers, "stars": [2, 2, 2, 2, 2, 2], "contrast": true},
		{"name": "单机 N12 后期 · 7 艘含 1 战列 2★", "node": 12, "limit": 60.0,
			"own": ["raven"] + cruisers, "stars": [2, 2, 2, 2, 2, 2, 2],
			"contrast": true},
		{"name": "单机 N15 BOSS · 双战列 2★", "node": 15, "limit": 70.0,
			"own": ["raven", "megathron", "omen", "caracal", "drake", "rifter"],
			"stars": [2, 2, 2, 2, 2, 2]},
		{"name": "联机 6v6 巡洋队 2★ 镜像", "limit": 60.0,
			"own": cruisers, "stars": [2, 2, 2, 2, 2, 2],
			"foe": cruisers, "foe_star": 2, "mirror": true, "contrast": true},
		{"name": "联机 3 战列 2★ 对轰（各带 3 巡洋）", "limit": 60.0,
			"own": ["raven", "megathron", "apocalypse", "omen", "caracal", "drake"],
			"stars": [2, 2, 2, 2, 2, 2],
			"foe": ["raven", "megathron", "apocalypse", "omen", "caracal", "drake"],
			"foe_star": 2, "mirror": true, "contrast": true},
		{"name": "联机 3 战列 2★ vs 6 护卫 2★", "limit": 60.0,
			"own": ["raven", "megathron", "apocalypse", "omen", "caracal", "drake"],
			"stars": [2, 2, 2, 2, 2, 2],
			"foe": ["punisher", "condor", "rifter", "omen", "caracal", "drake"],
			"foe_star": 2, "mirror": true, "contrast": true},
	]
	var all_times: Array[float] = []
	var all_over := 0
	for spec in cases:
		var p := _ttk_report(spec, seeds, false)
		all_times.append_array(p["times"])
		all_over += int(p["over"])
		if bool(spec.get("contrast", false)):
			print("      └ 对照：抗性回填 0.45 时 —— %s" % _ttk_line(_ttk_report(spec, seeds, true)))
		print("")
	var over_pct := 100.0 * float(all_over) / maxf(1.0, float(all_times.size()))
	all_times.sort()
	print("─".repeat(84))
	print("合计 %d 局：平均 %.1fs · 中位 %.1fs · 90%% 分位 %.1fs · 超过时限 %d 局（%.0f%%）"
			% [all_times.size(), _mean(all_times), _median(all_times),
				_pct(all_times, 0.9), all_over, over_pct])
	print("说明：时限内结束 ⇒ 战斗不拖时间；超过时限的那几局是火力渐增在收尾，不是站桩。")


## 跑一档 TTK 并打印一行摘要，返回原始耗时（供合计用）。
func _ttk_report(spec: Dictionary, seeds: int, old_resists: bool) -> Dictionary:
	var times: Array[float] = []
	var mults := 0.0
	var own_wins := 0
	var foe_wins := 0
	var over := 0
	var before_sd := 0
	var limit := float(spec.get("limit", 60.0))
	for k in seeds:
		var r := _ttk_case(spec, 4100 + k * 977, old_resists)
		var t := float(r["elapsed"])
		times.append(t)
		mults += float(r["mult"])
		if int(r["winner"]) == 0:
			own_wins += 1
		elif int(r["winner"]) == 1:
			foe_wins += 1
		if t > limit:
			over += 1
		if t <= limit * SIM.SUDDEN_DEATH_FRACTION:
			before_sd += 1
	var sorted := times.duplicate()
	sorted.sort()
	var payload := {"times": times, "mults": mults, "over": over,
			"before_sd": before_sd, "own_wins": own_wins, "foe_wins": foe_wins,
			"n": seeds, "limit": limit}
	if not old_resists:
		print("\n【%s】时限 %.0fs" % [String(spec["name"]), limit])
		print("   %s" % _ttk_line(payload))
	return payload


## ★ 2026-10-31（用户定案后追加）：TTK 系数**敏感度扫描**。
##
## 为什么需要它：把生产系数改成（伤害 ×1.20 / 血量 ×0.85）之后实测，
## 单机场景 37.7s → 17.1s（−55%），但**联机对轰只从 43.1s → 39.8s（−8%）**。
## 差这么多说明「伤害 ÷ 血量」不是唯一瓶颈：
##   · 单机是「我方碾压敌方」，伤害一涨就快速收割；
##   · 联机镜像对轰双方同时受益，而且时间大量花在**打不中**
##     （命中率 = 角速度驱动，见 `EveCombatCore.turret_chance_to_hit`），
##     堆伤害的边际收益会衰减。
## ⇒ 这个扫描量的是「再加一倍伤害，到底能换回几秒」，用来决定该往哪加码。
func _ttk_sweep() -> void:
	var combos := [
		["现状（生产 1.20 / 0.85）", 1.0, 1.0],
		["伤害再 ×1.15", 1.15, 1.0],
		["伤害再 ×1.35", 1.35, 1.0],
		["伤害再 ×1.35 + 血再 ×0.90", 1.35, 0.90],
		["伤害再 ×1.60", 1.60, 1.0],
	]
	var seeds := 8
	var specs := [
		{"name": "联机 6v6 巡洋镜像", "limit": 60.0,
			"own": ["omen", "caracal", "drake", "punisher", "rifter", "condor"],
			"stars": [2, 2, 2, 2, 2, 2],
			"foe": ["omen", "caracal", "drake", "punisher", "rifter", "condor"],
			"foe_star": 2, "mirror": true},
		{"name": "联机 3 战列对轰", "limit": 60.0,
			"own": ["raven", "megathron", "apocalypse", "omen", "caracal", "drake"],
			"stars": [2, 2, 2, 2, 2, 2],
			"foe": ["raven", "megathron", "apocalypse", "omen", "caracal", "drake"],
			"foe_star": 2, "mirror": true},
		{"name": "单机 N8 中期", "node": 8, "limit": 60.0,
			"own": ["omen", "caracal", "drake", "punisher", "rifter", "condor"],
			"stars": [2, 2, 2, 2, 2, 2]},
	]
	for spec in specs:
		print("\n【%s】%d 局/格" % [String(spec["name"]), seeds])
		for c in combos:
			var t := 0.0
			for k in seeds:
				var r := _ttk_case(spec, 4200 + k * 977, false,
						float(c[1]), float(c[2]))
				t += float(r["elapsed"])
			print("   %-32s 平均 %.1fs" % [String(c[0]), t / float(seeds)])


func _ttk_line(p: Dictionary) -> String:
	var times: Array = p["times"]
	var sorted := times.duplicate()
	sorted.sort()
	var n := maxf(1.0, float(p.get("n", times.size())))
	return "平均 %.1fs · 中位 %.1fs · %.1f~%.1fs · 时限内 %d/%d · 渐增前 %d/%d · 收尾倍率 平均 ×%.2f · 我胜 %d / 敌胜 %d" % [
		_mean(sorted), _median(sorted), float(sorted[0]),
		float(sorted[sorted.size() - 1]), int(p["n"]) - int(p["over"]), int(p["n"]),
		int(p["before_sd"]), int(p["n"]), float(p["mults"]) / n,
		int(p["own_wins"]), int(p["foe_wins"])]


func _mean(arr: Array) -> float:
	if arr.is_empty():
		return 0.0
	var s := 0.0
	for v in arr:
		s += float(v)
	return s / float(arr.size())


func _median(arr: Array) -> float:
	if arr.is_empty():
		return 0.0
	var a := arr.duplicate()
	a.sort()
	var mid := a.size() / 2
	if a.size() % 2 == 1:
		return float(a[mid])
	return (float(a[mid - 1]) + float(a[mid])) * 0.5


func _pct(arr: Array, q: float) -> float:
	if arr.is_empty():
		return 0.0
	var a := arr.duplicate()
	a.sort()
	var i := int(roundf(clampf(q, 0.0, 1.0) * float(a.size() - 1)))
	return float(a[i])


## 单局：我方 = 真实编制链，敌方 = 节点表编组（或显式给出）。
## `old_resists` = 把双方三层抗性临时回填 0.45，只用于「改前」对照。
func _ttk_case(spec: Dictionary, seed_v: int, old_resists: bool,
		dmg_extra: float = 1.0, hp_extra: float = 1.0) -> Dictionary:
	var run: Node = RUN.new()
	run.set_difficulty("simple")
	run.start_run(seed_v)
	run.field.clear()
	var keys: Array = spec["own"]
	var stars: Array = spec["stars"]
	for i in keys.size():
		run.field.append({"ship_key": StringName(keys[i]),
				"star": int(stars[i]) if i < stars.size() else 1,
				"cell": Vector2i(7, i)})
	var fac := FACTORY.new()
	var own: Array = fac.build_own(run)
	var foe_keys: Array = []
	var scale := 1.0
	if spec.has("node"):
		var row: Dictionary = NODE.by_index(int(spec["node"]))
		foe_keys = COMPS.ship_ids(String(row.get("comp", "")))
		scale = float(row.get("scale", 1.0))
	else:
		foe_keys = spec["foe"]
	var foe_star := int(spec.get("foe_star", 1))
	var enemy: Array = []
	var id := 900
	for key in foe_keys:
		var e = DB.instantiate_by_id(String(key), 1, id)
		id += 1
		if e == null:
			continue
		RUN.apply_enemy_scaling(e, foe_star, scale)
		fac.apply_doctrine(e)
		enemy.append(e)
	if old_resists:
		for s in own + enemy:
			for layer in [&"shield", &"armor", &"hull"]:
				s.resists[layer] = PackedFloat32Array([0.45, 0.45, 0.45, 0.45])
	# ★ 2026-10-31：系数扫描用的**额外**缩放（叠在生产系数之上）。
	#   ⚠️ 只给探针用，⛔ 别把这套搬进生产代码 —— 生产只有一个旋钮
	#      （`EveShipDatabase.TTK_DAMAGE_MULT / TTK_HP_MULT`）。
	if not is_equal_approx(dmg_extra, 1.0) or not is_equal_approx(hp_extra, 1.0):
		for s in own + enemy:
			if not is_equal_approx(dmg_extra, 1.0):
				s.warhead_scale(dmg_extra)
			if not is_equal_approx(hp_extra, 1.0):
				s.layer_hp_adjust({&"shield": hp_extra, &"armor": hp_extra,
						&"hull": hp_extra}, {})
	var dz := _deploy_z(own, enemy)
	_place_own(own, dz[0], own.size())
	# `mirror` = 敌方按我方站位**镜像**摆（联机对局两边都是玩家编制，
	# 不镜像的话「我方前排 + 敌方默认 4 列网格」会造出与数值无关的先手优势）。
	if bool(spec.get("mirror", false)) and own.size() > 0:
		for i in mini(enemy.size(), own.size()):
			var p: Vector3 = own[i].body.position
			enemy[i].body.position = Vector3(p.x, 0.0, -p.z)
			enemy[i].body.previous_position = enemy[i].body.position
			enemy[i].body.aim_dir = Vector3(0, 0, 1)
			enemy[i].body.velocity = Vector3(0, 0, 1) * enemy[i].body.max_speed * 0.15
	else:
		_place_enemy(enemy, dz[1])
	var sim = SIM.new()
	sim.setup(_typed(own), _typed(enemy))
	sim.set_seed(seed_v)
	var limit := float(spec.get("limit", 60.0))
	sim.set_time_limit(limit)
	_run_sim(sim, limit)
	return {"elapsed": sim.elapsed, "winner": sim.winner_team,
			"mult": sim.damage_multiplier()}


# ══════════════════════════════════════════════════════════════
#  ③ 整局通关率
# ══════════════════════════════════════════════════════════════
func _winrate_all() -> void:
	print("\n" + "=".repeat(84))
	print("③ 四档难度通关率（每格 %d 局 · 固定种子）" % RUNS_PER_POLICY)
	print("=".repeat(84))
	for diff in FT.difficulties():
		var did := String(diff["id"])
		print("\n" + "─".repeat(84))
		print("【%s】%s" % [String(diff["name"]), String(diff["desc"])])
		print("   参数：收入 %d + 利息 %d · 敌方强度 ×%.2f · AI %d%s"
				% [int(diff["base_income"]), int(diff["interest_max"]),
					float(diff.get("scale", 1.0)), int(diff["ai_level"]),
					"" if String(diff.get("key_mechanic", "")).is_empty()
					else " · 钥匙 " + String(diff["key_mechanic"])])
		# ★ 末段失误代价（2026-10-24 新增）：这一列是**这一档难度的核心**——
		#   云顶的难度不来自敌人面板，来自「同一个失误后期贵一个量级」。
		#   开局/精英/BOSS 三个点足以看出曲线陡不陡。
		var curve: Array = diff.get("loss_curve", [])
		if not curve.is_empty():
			print("   失误代价（信标 100）：开局 N1 −%d · 首个精英 N5 −%d · 末段 N13 −%d · BOSS N15 −%d"
					% [int(curve[0]), int(curve[4]), int(curve[12]), int(curve[14])])
			print("     整条曲线 N1..15 = %s" % str(curve))
		print("─".repeat(84))
		for policy in POLICIES:
			_node_wins.clear()
			_node_plays.clear()
			var cleared := 0
			var evacuated := 0
			var beacon_total := 0
			var coin_total := 0
			var level_total := 0
			var evac_node: Array[int] = []
			var field_total := 0
			var ehp_total := 0.0
			for k in RUNS_PER_POLICY:
				var r := _play_run(policy, did, 424242 + k * 7919)
				if bool(r["cleared"]):
					cleared += 1
				else:
					evacuated += 1
					evac_node.append(int(r["node"]))
				beacon_total += int(r["beacon"])
				coin_total += int(r["coin"])
				level_total += int(r["level"])
				field_total += int(r["field"])
				ehp_total += float(r["ehp"])
			print("  %-7s 通关 %2d/%d（%3.0f%%） · 信标 %4.1f · 星币 %4.1f · Lv%.1f · 上阵 %.1f 艘 / EHP %.0f"
					% [policy, cleared, RUNS_PER_POLICY,
						100.0 * float(cleared) / float(RUNS_PER_POLICY),
						float(beacon_total) / float(RUNS_PER_POLICY),
						float(coin_total) / float(RUNS_PER_POLICY),
						float(level_total) / float(RUNS_PER_POLICY),
						float(field_total) / float(RUNS_PER_POLICY),
						ehp_total / float(RUNS_PER_POLICY)])
			if not evac_node.is_empty():
				print("          撤离节点：%s" % str(evac_node))
			_print_node_rates()


func _print_node_rates() -> void:
	print("   节点胜率：")
	var line := "     "
	for i in range(1, NODE.TOTAL + 1):
		var p := int(_node_plays.get(i, 0))
		if p == 0:
			continue
		var w := int(_node_wins.get(i, 0))
		line += " N%d=%d%%" % [i, int(roundf(100.0 * float(w) / float(p)))]
		if i % 5 == 0:
			print(line)
			line = "     "
	if line.strip_edges() != "":
		print(line)


func _play_run(policy: String, diff_id: String, seed_v: int,
		verbose: bool = false) -> Dictionary:
	var run: Node = RUN.new()
	run.set_difficulty(diff_id)
	run.start_run(seed_v)
	var fac := FACTORY.new()
	var guard := 0
	var last_field: int = 0
	var last_ehp := 0.0
	while run.ending == 0 and guard < 40:
		guard += 1
		_prep(run, policy)
		var own: Array = fac.build_own(run)
		var enemy: Array = fac.build_enemy(run)
		var winner := 1
		var destroyed: Array = []
		# 按阵营统计开火/命中（只在诊断模式下挂，正式统计不挂）
		var tally: Dictionary = {}
		last_field = run.field.size()
		last_ehp = 0.0
		for s in own:
			last_ehp += s.max_hp[&"shield"] + s.max_hp[&"armor"] + s.max_hp[&"hull"]
		# ⚠️ 炼狱 BOSS 的钥匙体检（临时）：确认"到底有没有凑够 6 激光"。
		#   没有这行就没法区分「BOSS 太硬」和「玩家根本没开出钥匙」——
		#   那两件事的修法完全相反。默认关闭（会刷 60+ 行）。
		if KEY_DEBUG and run.key_mechanic() != "" and run.node_index == 15:
			print("      [钥匙] %-7s 满足=%s 破甲强度=%.1f/%.0f（激光 %d）上阵=%d"
					% [policy, str(run.key_mechanic_satisfied()),
						run.armor_break_power(), RUN.ARMOR_BREAK_NEED,
						_laser_count(run), run.field.size()])
		# 事件节点没有战斗：直接算「通过」，且不计入节点胜率
		if NODE.is_event(run.node_index) or enemy.is_empty():
			winner = 0
		elif not own.is_empty():
			var dz := _deploy_z(own, enemy)
			_place_own(own, dz[0], own.size())
			_place_enemy(enemy, dz[1], _enemy_formation(run))
			var sim = SIM.new()
			sim.setup(_typed(own), _typed(enemy))
			sim.set_seed(run.battle_seed())
			sim.set_ai_level(int(run.difficulty_row().get("ai_level", 0)))
			var limit: float = run.battle_seconds()
			sim.set_time_limit(limit)
			if verbose:
				sim.shot_fired.connect(func(a, _t, hit, _q, _d):
					var k := int(a.team)
					var rec: Array = tally.get(k, [0, 0])
					if hit:
						rec[0] = int(rec[0]) + 1
					rec[1] = int(rec[1]) + 1
					tally[k] = rec)
			_run_sim(sim, limit)
			winner = sim.winner_team
			if verbose:
				_line_report(policy, run, own, enemy, sim, tally)
			for e in enemy:
				if not e.alive:
					destroyed.append(e)
		if not NODE.is_event(run.node_index):
			_node_plays[run.node_index] = int(_node_plays.get(run.node_index, 0)) + 1
			if winner == 0:
				_node_wins[run.node_index] = int(_node_wins.get(run.node_index, 0)) + 1
		run.resolve_battle(winner, destroyed, [], run.enemy_scale())
		run.advance()
	return {
		# Ending 枚举：NONE=0 / CLEARED=1 / EVACUATED=2
		"cleared": int(run.ending) == 1,
		"node": run.node_index,
		"beacon": run.beacon,
		"coin": run.coin,
		"level": run.level,
		"field": last_field,
		"ehp": last_ehp,
	}


func _run_sim(sim, limit: float) -> void:
	var hard := limit * 3.0
	var guard := 0
	while not sim.finished and sim.elapsed < hard and guard < 2000:
		sim.run_seconds(0.5)
		guard += 1


# ══════════════════════════════════════════════════════════════
#  玩家策略
# ══════════════════════════════════════════════════════════════
func _prep(run, policy: String) -> void:
	match policy:
		"spam":
			_buy_spam(run)
		"normal":
			_level_up(run, 6, 4)
			_buy_normal(run)
		"hard":
			_level_up(run, 4, 2)
			_buy_hard(run)
			_maybe_refresh(run)
		"comp":
			_level_up(run, 4, 3)
			_buy_comp(run)
			_maybe_refresh(run)
	_deploy(run, policy)
	# 备战席满了：普通/困难会卖掉最弱的，点点点不管
	if policy != "spam":
		_sell_overflow(run, policy)


func _buy_spam(run) -> void:
	# 点点点：从第一个槽开始，买得起就买，不刷新、不升级
	var guard := 0
	while guard < 12:
		guard += 1
		var bought := false
		for i in run.offers.size():
			var d = run.offers[i]
			if not (d is Dictionary) or (d as Dictionary).is_empty():
				continue
			if run.bench.size() >= RUN.BENCH_SLOTS:
				break
			var r: Dictionary = run.buy(i)
			if bool(r.get("ok", false)):
				bought = true
				break
		if not bought:
			break


## 普通：按战力挑（会算裸战力 + 凑对），保留利息档，不刷新
func _buy_normal(run) -> void:
	var reserve := _interest_reserve(run)
	_buy_merges(run, reserve)
	var scored: Array = []
	for i in run.offers.size():
		var d = run.offers[i]
		if not (d is Dictionary) or (d as Dictionary).is_empty():
			continue
		scored.append([i, _ship_score(d, &"", run)])
	scored.sort_custom(func(a, b): return float(a[1]) > float(b[1]))
	for pair in scored:
		if run.bench.size() >= RUN.BENCH_SLOTS:
			break
		var i := int(pair[0])
		var d: Dictionary = run.offers[i]
		if run.coin - int(d.get("cost", 1)) < reserve:
			continue
		run.buy(i)

## 困难：看敌方武器构成挑防御类型 + 凑羁绊 + 优先合成 + 攒钱吃利息
func _buy_hard(run) -> void:
	var want_def := _preferred_defense(run)
	var reserve := _interest_reserve(run)
	_buy_merges(run, reserve)
	var scored: Array = []
	for i in run.offers.size():
		var d = run.offers[i]
		if not (d is Dictionary) or (d as Dictionary).is_empty():
			continue
		scored.append([i, _ship_score(d, want_def, run)])
	scored.sort_custom(func(a, b): return float(a[1]) > float(b[1]))
	for pair in scored:
		if run.bench.size() >= RUN.BENCH_SLOTS:
			break
		var i := int(pair[0])
		var d: Dictionary = run.offers[i]
		var cost := int(d.get("cost", 1))
		if run.coin - cost < reserve:
			continue
		run.buy(i)


## 认真玩：先按敌方武器定一个派系（护盾/装甲），整局只堆这一套
func _buy_comp(run) -> void:
	var fac := _target_faction(run)
	var forcing_key: bool = String(run.key_mechanic()) == "armor_pierce"
	var reserve := _interest_reserve(run)
	_buy_merges(run, reserve)
	var scored: Array = []
	for i in run.offers.size():
		var d = run.offers[i]
		if not (d is Dictionary) or (d as Dictionary).is_empty():
			continue
		var s := _ship_score(d, _preferred_defense(run), run)
		if int(d.get("faction", -1)) == fac:
			s *= 1.8
		# ★ 炼狱的"搏一把"建模范式：整局往**破甲体系**上凑。
		#
		# ★★ 2026-10-24（用户定案后重写）：钥匙**不再只认激光**。
		#   真玩家的做法是「看商店给了哪条破甲线，就往那条线上堆」——
		#   导弹 / 射弹炮 / 混合炮 / 激光羁绊都算数（见 EveRunState.ARMOR_BREAK_WEIGHT）。
		#   所以探针也不许再死盯激光，否则测出来的仍是"只有激光能过"。
		#
		# ⚠️ 上一版的坑（留着提醒）：原来这里**无条件**跳过所有非激光船 ⇒
		#   前几关商店里没有激光炮，玩家从节点 1 起就什么也不买，
		#   实测炼狱 comp 的 N1 胜率只有 6%。那不是"炼狱很难"，
		#   是**探针把认真玩的人建模成不买船**。
		if forcing_key:
			var wid := StringName(d.get("weapon_id", &""))
			s *= 3.0 if wid == _key_line_weapon(run) else 1.0
			# 上阵已够 5 艘（不会被打空）之后，只补当前那条破甲线
			if run.node_index >= 7 and run.field.size() >= 5 \
					and run.armor_break_power() < RUN.ARMOR_BREAK_NEED:
				if wid != _key_line_weapon(run):
					continue
		scored.append([i, s])
	scored.sort_custom(func(a, b): return float(a[1]) > float(b[1]))
	for pair in scored:
		if run.bench.size() >= RUN.BENCH_SLOTS:
			break
		var i := int(pair[0])
		var d: Dictionary = run.offers[i]
		if run.coin - int(d.get("cost", 1)) < reserve:
			continue
		run.buy(i)


## 破甲线 → 该线的代表性派系（用于"整局往一条派系上堆"的建模）。
##
## 口径 = 现实里谁用这种兵器：激光=艾玛、导弹=加达里、射弹=米玛塔尔、
## 混合=盖伦特（`EveShipTable.FACTION_INDEX`：艾玛0 / 加达里1 / 盖伦特2 / 米玛塔尔3）。
## ⚠️ 混合炮在加达里船上也有，但**盖伦特才是纯混合炮派系**，所以按后者。
func _faction_of_weapon(wid: StringName) -> int:
	match wid:
		&"laser":
			return 0
		&"missile":
			return 1
		&"hybrid":
			return 2
		&"proj":
			return 3
		_:
			return 0


## 敌方主力伤害 → 该堆哪个派系（**真·克制推算**，不是按武器名硬映射）：
##   ① 我方武器打到敌方的效率（敌方三层血量按实际占比加权）
##   ② 敌方武器打到我方的效率（越低越好）
##   分数 = ① / ②，取最高的派系。
func _target_faction(run) -> int:
	# ★ 炼狱有机制钥匙：整局往**那条破甲线所在的派系**堆（"搏一把"的人不改主意）。
	#   ⚠️ 2026-10-24 起钥匙不只认激光，所以这里也不能再写死"艾玛(0)"——
	#   否则探针会在选了导弹线之后还硬买艾玛船，测出来的仍是"只有激光能过"。
	if run.key_mechanic() == "armor_pierce":
		return _faction_of_weapon(_key_line_weapon(run))
	var enemy: Array = []
	for sid in COMPS.ship_ids(run.enemy_comp_id()):
		var d: Dictionary = DB.by_id(String(sid))
		if not d.is_empty():
			enemy.append(d)
	if enemy.is_empty():
		return 0
	var best := 0
	var best_score := -INF
	for fac in 4:
		var sample: Dictionary = _faction_sample(fac)
		if sample.is_empty():
			continue
		var my_profile: PackedFloat32Array = sample["weapon_profile"]
		var offense := 0.0
		var wsum := 0.0
		for e in enemy:
			var w := float(e["shield"]) + float(e["armor"]) + float(e["hull"])
			offense += w * _layered_df(my_profile, e)
			wsum += w
		offense /= maxf(1.0, wsum)
		var taken := 0.0
		for e in enemy:
			taken += _layered_df(e["weapon_profile"], sample)
		taken /= maxf(1.0, float(enemy.size()))
		var score := offense / maxf(0.05, taken)
		if score > best_score:
			best_score = score
			best = fac
	return best


## 同派系所有船的武器 / 防御都相同 ⇒ 取一艘做样本即可（结果缓存）
var _fac_samples: Dictionary = {}

func _faction_sample(fac: int) -> Dictionary:
	if _fac_samples.has(fac):
		return _fac_samples[fac]
	for d in DB.all_ships():
		if int(d["faction"]) == fac:
			_fac_samples[fac] = d
			return d
	return {}


## 武器构成对某一层的穿透比例（与 EveCombatCore.damage_factor 同口径）
func _df(profile: PackedFloat32Array, resists: PackedFloat32Array) -> float:
	var f := 0.0
	for i in 4:
		var r := clampf(float(resists[i]) if i < resists.size() else 0.0, 0.0, 0.999)
		f += float(profile[i]) * (1.0 - r)
	return f


## 按三层血量占比加权后的「这一炮打进这艘船的比例」
func _layered_df(profile: PackedFloat32Array, e: Dictionary) -> float:
	var sh := float(e.get("shield", 0.0))
	var ar := float(e.get("armor", 0.0))
	var hu := float(e.get("hull", 0.0))
	var total := maxf(1.0, sh + ar + hu)
	return (sh * _df(profile, e["shield_resists"])
			+ ar * _df(profile, e["armor_resists"])
			+ hu * _df(profile, e["hull_resists"])) / total


## 利息档：会玩的人**不会为了吃利息把船饿死**。
##
## ⛔ 2026-10-24 修的一个探针建模 bug（它把整套难度测量带偏了）：
##    旧版 `return int(run.coin / 10) * 10` ⇒ 保留「当前档位的全部钱」，
##    于是
##      ① 星币恰好是 10 的整数倍时，`coin - cost < reserve` 恒成立
##         ⇒ 那一整个节点**一艘船都买不到**（`_buy_merges` 同样买不到）；
##      ② 由于收入 ≥ 5，钱只会在 10 的倍数附近来回，几乎每两关就冻一次；
##      ③ 后果：普通/困难/认真三个"会玩"策略的星币一路涨到 27~30 却
##         买不出船 —— 实测节点 13 只剩 **4 艘、EHP 656**（同种子下
##         spam 是 7 艘 2136）。于是「乱点通关率 94% > 会玩 69%」，
##         而那不是游戏难度问题，是**探针把会玩的人建模成不买船**。
##
## ✅ 现在的口径：
##     · 只保留「上一档」的钱（利息不至于掉档），手里永远留得住 10 枚；
##     · 利息已封顶时**一分不留** —— 超过上限的存款没有任何收益，
##       真人也一定花掉（这是"会玩"的题中之义）。
func _interest_reserve(run) -> int:
	var cap := int(run.difficulty_row().get("interest_max", 5))
	if run.interest() >= cap:
		return 0
	return maxi(0, int(run.coin / 10) * 10 - 10)


func _preferred_defense(run) -> StringName:
	var enemy: Array = []
	for sid in COMPS.ship_ids(run.enemy_comp_id()):
		var d: Dictionary = DB.by_id(String(sid))
		if not d.is_empty():
			enemy.append(d)
	if enemy.is_empty():
		return &""
	var armor_taken := 0.0
	var shield_taken := 0.0
	var armor_sample := _faction_sample(0)    # 艾玛 = 甲抗
	var shield_sample := _faction_sample(1)   # 加达里 = 盾抗
	for e in enemy:
		armor_taken += _layered_df(e["weapon_profile"], armor_sample)
		shield_taken += _layered_df(e["weapon_profile"], shield_sample)
	if is_equal_approx(armor_taken, shield_taken):
		return &""
	return &"armor" if armor_taken < shield_taken else &"shield"


func _ship_score(d: Dictionary, want_def: StringName, run = null) -> float:
	var cost := float(d.get("cost", 1))
	var atk := float(d.get("attack", 0.0))
	var hp := float(d.get("shield", 0.0)) + float(d.get("armor_struct", 0.0))
	var score := cost * 40.0 + atk * 0.8 + hp * 0.18
	if want_def != &"" and StringName(d.get("defense_id", &"")) == want_def:
		score *= 1.35
	if bool(d.get("is_logistics", false)):
		score *= 0.9
	if run != null:
		# 羁绊向：跟场上已有船同势力 / 同武器 / 同防御的加分
		var fac := int(d.get("faction", -1))
		var wp := StringName(d.get("weapon_id", &""))
		var df := StringName(d.get("defense_id", &""))
		var fac_n := 0
		var wp_n := 0
		var df_n := 0
		for e in run.field + run.bench:
			var o: Dictionary = DB.by_id(String(e.get("ship_key", "")))
			if o.is_empty():
				continue
			if int(o.get("faction", -1)) == fac:
				fac_n += 1
			if StringName(o.get("weapon_id", &"")) == wp:
				wp_n += 1
			if StringName(o.get("defense_id", &"")) == df:
				df_n += 1
		# 差 1 艘就开档的位置最值钱
		score *= 1.0 + _tier_bonus(fac_n) + _tier_bonus(wp_n) + _tier_bonus(df_n)
		# 已经持有同名的加成 —— 三连合成才是自走棋最大的战力跃迁
		var dup := 0
		for e in run.field + run.bench:
			if StringName(e.get("ship_key", &"")) == StringName(d.get("ship_key", &"")):
				dup += 1
		score += float(dup) * 150.0
	return score


## 羁绊阈值附近加权：差 1~2 艘开档时最划算
func _tier_bonus(n: int) -> float:
	if n == 1 or n == 2:
		return 0.10
	if n == 3 or n == 4 or n == 5:
		return 0.06
	return 0.0


func _buy_merges(run, reserve: int) -> void:
	for i in run.offers.size():
		var d = run.offers[i]
		if not (d is Dictionary) or (d as Dictionary).is_empty():
			continue
		var key := StringName(d.get("ship_key", &""))
		var star := int(d.get("star", 1))
		var have := 0
		for e in run.bench:
			if StringName(e.get("ship_key", &"")) == key \
					and int(e.get("star", 1)) == star:
				have += 1
		for e in run.field:
			if StringName(e.get("ship_key", &"")) == key \
					and int(e.get("star", 1)) == star:
				have += 1
		if have >= 2 and int(d.get("cost", 1)) <= run.coin - reserve \
				and run.bench.size() < RUN.BENCH_SLOTS:
			run.buy(i)


func _offers_sorted_by_cost(run, desc: bool) -> Array:
	var arr: Array = []
	for i in run.offers.size():
		var d = run.offers[i]
		if not (d is Dictionary) or (d as Dictionary).is_empty():
			continue
		arr.append([i, int(d.get("cost", 1))])
	arr.sort_custom(func(a, b):
		return int(a[1]) > int(b[1]) if desc else int(a[1]) < int(b[1]))
	var out: Array = []
	for p in arr:
		out.append(int(p[0]))
	return out


func _level_up(run, reserve: int, max_extra: int) -> void:
	var target := _desired_level(int(run.node_index))
	var tries := 0
	while run.level < target and tries < max_extra:
		tries += 1
		if run.coin < RUN.BUY_XP_COST + reserve:
			break
		if not bool(run.levelup().get("ok", false)):
			break


func _desired_level(node_index: int) -> int:
	if node_index <= 2:
		return 2
	if node_index <= 5:
		return 3
	if node_index <= 8:
		return 4
	if node_index <= 11:
		return 5
	return 6


func _maybe_refresh(run) -> void:
	if run.coin < 16:
		return
	var want_def := _preferred_defense(run)
	var want_fac := _target_faction(run)
	var has_good := false
	for d in run.offers:
		if not (d is Dictionary) or (d as Dictionary).is_empty():
			continue
		if int(d.get("faction", -1)) == want_fac and EveRunState.offer_tier(d as Dictionary) >= 2:
			has_good = true
		if want_def != &"" and StringName(d.get("defense_id", &"")) == want_def \
				and EveRunState.offer_tier(d as Dictionary) >= 3:
			has_good = true
	for d in run.offers:
		if not (d is Dictionary) or (d as Dictionary).is_empty():
			continue
		var key := StringName(d.get("ship_key", &""))
		for e in run.bench + run.field:
			if StringName(e.get("ship_key", &"")) == key:
				has_good = true
	if has_good:
		return
	run.refresh()


func _deploy(run, policy: String) -> void:
	var cells := _own_cells()
	var limit: int = run.field_limit()
	if policy == "spam":
		while run.field.size() < limit and run.bench.size() > 0:
			var c: Vector2i = cells[run.field.size()]
			if not bool(run.deploy_from_bench(0, c.x, c.y).get("ok", false)):
				break
		return
	# 普通/困难：每次都从当前备战席里挑最强的一艘上场
	# ⚠️ 不能先算好索引数组 —— `deploy_from_bench` 会 remove_at，后面的下标全错位
	while run.field.size() < limit and run.bench.size() > 0:
		var best := 0
		var best_power := -1.0
		for i in run.bench.size():
			var p: float = _entry_power(run.bench[i])
			if p > best_power:
				best_power = p
				best = i
		var c: Vector2i = cells[run.field.size()]
		var r: Dictionary = run.deploy_from_bench(best, c.x, c.y)
		if not bool(r.get("ok", false)):
			break


func _entry_power(e: Dictionary) -> float:
	var d: Dictionary = DB.by_id(String(e.get("ship_key", "")))
	if d.is_empty():
		return 0.0
	var star := int(e.get("star", 1))
	var m := pow(RUN.STAR_MULT, float(star - 1))
	return _ship_score(d, &"") * m


func _sell_overflow(run, policy: String) -> void:
	if run.bench.size() < RUN.BENCH_SLOTS:
		return
	# 只卖 1★ 且不成对的
	var best := -1
	var best_power := INF
	for i in run.bench.size():
		var e: Dictionary = run.bench[i]
		if int(e.get("star", 1)) > 1:
			continue
		var key := StringName(e.get("ship_key", &""))
		var dup := 0
		for o in run.bench:
			if StringName(o.get("ship_key", &"")) == key:
				dup += 1
		for o in run.field:
			if StringName(o.get("ship_key", &"")) == key:
				dup += 1
		if dup > 1:
			continue
		var p := _entry_power(e)
		if p < best_power:
			best_power = p
			best = i
	if best >= 0:
		run.sell_from_bench(best)


## 敌方站位模板：只有开了 `enemy_formation` 的难度才消费（与场景同口径）
func _enemy_formation(run) -> String:
	if not bool(run.difficulty_row().get("enemy_formation", false)):
		return ""
	return String(COMPS.by_id(run.enemy_comp_id()).get("formation", ""))


func _own_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	# 前 8 格放第 7 行（接敌第一排），之后第 8 行
	for col in range(3, 9):
		out.append(Vector2i(7, col))
	for col in range(3, 9):
		out.append(Vector2i(8, col))
	for col in range(0, 11):
		out.append(Vector2i(9, col))
	for col in range(0, 11):
		out.append(Vector2i(10, col))
	return out


# ══════════════════════════════════════════════════════════════
#  布阵（与 EveBattleArena / EveBattleScene 同口径）
# ══════════════════════════════════════════════════════════════
func _deploy_z(own: Array, enemy: Array) -> Array:
	var ranges: Array[float] = []
	for s in own + enemy:
		ranges.append(float(s.optimal_range))
	if ranges.is_empty():
		return [45000.0, -45000.0]
	ranges.sort()
	var mid := ranges.size() / 2
	var median := ranges[mid] if ranges.size() % 2 == 1 \
			else (ranges[mid - 1] + ranges[mid]) * 0.5
	var longest := ranges[ranges.size() - 1]
	var basis := minf(maxf(median, 12_000.0), longest)
	var half_m := clampf(basis * STANDOFF_RATIO * 0.5, 6_000.0,
			ARENA_RADIUS_WORLD * WORLD_UNIT_IN_METERS * 0.6)
	return [half_m, -half_m]


func _place_own(fleet: Array, dz: float, count: int) -> void:
	# 棋盘偏移 = deploy_own_z/1000 − row8 中心局部 z（−33 + 8×6 + 3 = 18）
	var board_z_units := dz / WORLD_UNIT_IN_METERS - 18.0
	var cells := _own_cells()
	for i in fleet.size():
		var c: Vector2i = cells[i] if i < cells.size() else Vector2i(9, 0)
		var x := ((float(c.y) * BOARD_CELL_UNITS) - BOARD_HALF_UNITS + 3.0) * 1000.0
		var z := ((float(c.x) * BOARD_CELL_UNITS) - BOARD_HALF_UNITS + 3.0
				+ board_z_units) * 1000.0
		fleet[i].body.position = Vector3(x, 0.0, z)
		fleet[i].body.previous_position = Vector3(x, 0.0, z)
		fleet[i].body.aim_dir = Vector3(0, 0, -1)
		fleet[i].body.velocity = Vector3(0, 0, -1) * fleet[i].body.max_speed * 0.15


func _place_enemy(fleet: Array, dz: float, formation: String = "") -> void:
	var positions: Array[Vector3] = []
	if formation != "":
		positions = COMPS.formation_positions(formation, fleet.size(), dz, 1.0)
	for i in fleet.size():
		var p: Vector3
		if positions.size() > i:
			p = positions[i]
		else:
			var row := i / 4
			var col := i % 4
			p = Vector3((float(col) - 1.5) * COL_STEP, 0.0,
					dz + float(row) * ROW_STEP)
		fleet[i].body.position = p
		fleet[i].body.previous_position = p
		fleet[i].body.aim_dir = Vector3(0, 0, 1)
		fleet[i].body.velocity = Vector3(0, 0, 1) * fleet[i].body.max_speed * 0.15
