extends Node
## 探针：**小吨位打大吨位**到底有多快（2026-10-31 玩家反馈）。
##
## 玩家原话：「护卫打战巡和战列的伤害也高。2 个小护卫能 6 秒干掉满血战列。不好」
##
## 本探针只回答一件事：不同「艘数 × 星级」下，护卫杀战列要几秒。
## 场景里没有羁绊、没有关卡缩放、没有事件 —— 纯吨位对轰，把变量压到最少。
##
## ⚠️ 判据是 `sim.elapsed`（打完那一刻），不是「血条空」，两者一致。
## ⚠️ 星级走 `EveFleetFactory.apply_star`（= 游戏里同名函数），别在这里手抄 1.8。
const DB := preload("res://scripts/core/eve_ship_database.gd")
const SIM := preload("res://scripts/core/eve_battle_simulator.gd")
const FACTORY := preload("res://scripts/scene/eve_fleet_factory.gd")

var _id := 1


func _ready() -> void:
	# 先把「纸面数据」打出来：DPS 与三层血量，方便手算校验
	print("=".repeat(78))
	print("纸面：每发伤害 / 间隔 / DPS / 三层血量")
	print("=".repeat(78))
	for key in ["rifter", "punisher", "tristan", "hurricane", "dominix", "abaddon"]:
		var s = _make(key, 1, 0)
		print("  %-10s cost=%d 每发 %.1f × %.2fs ⇒ DPS %.1f · 血 盾%.0f/甲%.0f/结%.0f = %.0f"
				% [key, s.cost, s.weapon_damage, s.weapon_cycle,
					s.weapon_damage / s.weapon_cycle,
					s.max_hp[&"shield"], s.max_hp[&"armor"], s.max_hp[&"hull"],
					s.total_max_hp()])

	# 关键对照：护卫 vs 战列（1 费 vs 5 费）
	#
	# ⚠️ 两组间距必须都测：
	#   45,000 = 生产侧 `_deploy_z` 的典型接敌距离（要飞一段）
	#   12,000 = 贴脸（已经接敌完毕）。玩家看到的「6 秒干掉战列」只可能在贴脸下发生
	#            —— 远距离那 20 多秒全花在接敌上，会把真实 TTK 完全盖住。
	var cases: Array = [
		["1 护卫(1★) vs 1 战列(1★)", ["rifter"], [1], ["dominix"], [1]],
		["2 护卫(1★) vs 1 战列(1★)", ["rifter", "rifter"], [1, 1], ["dominix"], [1]],
		["2 护卫(2★) vs 1 战列(1★)", ["rifter", "rifter"], [2, 2], ["dominix"], [1]],
		["2 护卫(3★) vs 1 战列(1★)", ["rifter", "rifter"], [3, 3], ["dominix"], [1]],
		["2 护卫(3★) vs 1 战列(3★)", ["rifter", "rifter"], [3, 3], ["dominix"], [3]],
		["1 护卫(3★) vs 1 战列(1★)", ["rifter"], [3], ["dominix"], [1]],
		["2 护卫(3★) vs 1 战巡(1★)", ["rifter", "rifter"], [3, 3], ["hurricane"], [1]],
		["2 护卫(3★) vs 1 战列(1★) 艾玛", ["punisher", "punisher"], [3, 3], ["abaddon"], [1]],
		["1 战列(1★) vs 1 护卫(1★)（反向）", ["dominix"], [1], ["rifter"], [1]],
		["1 战列(1★) vs 2 护卫(1★)（反向）", ["dominix"], [1], ["rifter", "rifter"], [1, 1]],
	]
	for gap_d in [45_000.0, 12_000.0]:
		print("\n" + "=".repeat(78))
		print("对决 · 初始间距 %.0f m%s" % [gap_d, "（贴脸，已接敌）" if gap_d < 20000.0 else "（典型接敌距离）"])
		print("=".repeat(78))
		for c in cases:
			var times: Array[float] = []
			var detail := ""
			var win_seed := -1
			for seed_v in [7001, 7002, 7003]:
				var r := _duel(c[1], c[2], c[3], c[4], seed_v, gap_d)
				times.append(float(r["time"]))
				detail = String(r["detail"])
				if win_seed < 0:
					win_seed = int(r["winner"])
			times.sort()
			var win_txt := "攻方胜" if win_seed == 0 else "守方胜"
			print("  %-30s %-6s 中位 %5.1fs  三局 %s"
					% [String(c[0]), win_txt, times[1],
						", ".join(PackedStringArray(times.map(func(x): return "%.1f" % x)))])
			print("      %s" % detail)
	get_tree().quit()


## `star` 走真实链路（`apply_star`），与游戏内一致。
func _make(key: String, star: int, team: int):
	var s = DB.instantiate_by_id(key, team, _id)
	_id += 1
	FACTORY.apply_doctrine(s)
	FACTORY.apply_star(s, star)
	return s


func _duel(a_keys: Array, a_stars: Array, b_keys: Array, b_stars: Array, seed_v: int, gap_d: float) -> Dictionary:
	var own: Array = []
	var foe: Array = []
	for i in a_keys.size():
		own.append(_make(String(a_keys[i]), int(a_stars[i]), 0))
	for i in b_keys.size():
		foe.append(_make(String(b_keys[i]), int(b_stars[i]), 1))
	# 摆位：双方沿 z 轴隔开，间距 = 双方射程中位数 × 1.15（与生产侧 `_deploy_z` 同口径）
	var d := gap_d
	_put(own, -d, -1.0)
	_put(foe, d, 1.0)
	var sim = SIM.new()
	sim.setup(_typed(own), _typed(foe))
	sim.set_seed(seed_v)
	sim.set_ai_level(1)
	sim.set_time_limit(60.0)
	var tally := {"own_shots": 0, "own_hits": 0, "foe_shots": 0, "foe_hits": 0}
	sim.shot_fired.connect(func(a, _t, hit, _q, _d):
		if int(a.team) == 0:
			tally["own_shots"] += 1
			if hit:
				tally["own_hits"] += 1
		else:
			tally["foe_shots"] += 1
			if hit:
				tally["foe_hits"] += 1)
	var guard := 0
	while not sim.finished and sim.elapsed < 90.0 and guard < 3000:
		sim.run_seconds(0.1)
		guard += 1
	# 诊断：谁还剩多少血 —— 光看「胜方」标签分不清「打死了」和「没打完」
	var detail := "攻方剩 %d 艘" % _alive(own)
	if not own.is_empty() and own[0].alive:
		detail += "(" + ",".join(PackedStringArray(own.map(
				func(s): return "%.0f" % s.total_hp()))) + ")"
	detail += " · 守方剩 %d 艘" % _alive(foe)
	if not foe.is_empty() and foe[0].alive:
		detail += "(" + ",".join(PackedStringArray(foe.map(
				func(s): return "%.0f" % s.total_hp()))) + ")"
	detail += " · 攻方总输出 %.0f / 守方总输出 %.0f" % [_sum_dealt(own), _sum_dealt(foe)]
	detail += " · 开火 攻 %d/%d 中 · 守 %d/%d 中" % [
			tally["own_hits"], tally["own_shots"], tally["foe_hits"], tally["foe_shots"]]
	detail += " · winner=%d" % sim.winner_team
	return {"winner": sim.winner_team, "time": sim.elapsed, "detail": detail}


func _sum_dealt(fleet: Array) -> float:
	var n := 0.0
	for s in fleet:
		n += float(s.damage_dealt)
	return n


func _alive(fleet: Array) -> int:
	var n := 0
	for s in fleet:
		if s.alive:
			n += 1
	return n


func _typed(arr: Array) -> Array[EveShip]:
	var out: Array[EveShip] = []
	for s in arr:
		out.append(s)
	return out


func _put(fleet: Array, z: float, aim_z: float) -> void:
	for i in fleet.size():
		var s = fleet[i]
		var x := (float(i) - float(fleet.size() - 1) * 0.5) * 8000.0
		var p := Vector3(x, 0.0, z)
		s.body.position = p
		s.body.previous_position = p
		s.body.aim_dir = Vector3(0, 0, aim_z)
		s.body.velocity = Vector3(0, 0, aim_z) * s.body.max_speed * 0.15
