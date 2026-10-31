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

## 逐发打印战列的目标（查「命中但 0 伤害」时置 true）。
const DEBUG_BATTLESHIP := false

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
	for gap_d in [13_800.0, 24_000.0, 34_500.0]:
		print("\n" + "=".repeat(78))
		print("对决 · 两军全距 %.0f m%s" % [gap_d, "（贴脸，已接敌）" if gap_d < 20000.0 else "（生产量级）"])
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

	# ── 混编队（B 方案「分层站位」的验收场景）────────────────────────
	#
	# 为什么要单独测这一组：上面全是纯吨位对轰，**看不出「混编」的问题**。
	# 玩家抱怨的「战列打不中还手」恰恰出现在混编队里 ——
	# 因为 `_fleet_station_distance()` 取全队**最短射程**，
	# 编队里只要有 1 艘护卫（6 km），旗舰就被拖到 4 km，战列跟着贴脸。
	print("\n" + "=".repeat(78))
	print("混编队 · 2 战列 + 2 战巡 + 2 护卫 vs 镜像（看战列有没有输出）")
	print("=".repeat(78))
	for gap_d in [13_800.0, 24_000.0, 34_500.0]:
		for seed_v in [7101, 7102]:
			var r := _mixed(gap_d, seed_v)
			print("  间距 %5.0fm · seed %d → %s" % [gap_d, seed_v, String(r["detail"])])
	get_tree().quit()


## 混编镜像对轰。摆位：护卫在前排（靠敌），战列在后排。
func _mixed(gap_d: float, seed_v: int) -> Dictionary:
	var own: Array = []
	var foe: Array = []
	# 顺序有意义：前排 = 护卫，后排 = 战列
	var comp: Array = [["rifter", 1], ["rifter", 1], ["hurricane", 1],
			["hurricane", 1], ["dominix", 1], ["dominix", 1]]
	for i in comp.size():
		own.append(_make(String(comp[i][0]), int(comp[i][1]), 0))
		foe.append(_make(String(comp[i][0]), int(comp[i][1]), 1))
	_put_ranks(own, gap_d * 0.5, -1.0)    # team0 在 +z（与生产 deploy_own_z 同向）
	_put_ranks(foe, -gap_d * 0.5, 1.0)
	var sim = SIM.new()
	sim.setup(_typed(own), _typed(foe))
	sim.set_seed(seed_v)
	sim.set_ai_level(1)
	sim.set_time_limit(60.0)
	# ★ 逐船开火统计 —— 「战列输出 0」必须分清三种病因：
	#   ① 一枪没开（没目标 / 卡射程 / 在飞）  ② 开了但全空（命中率问题）
	#   ③ 开了也中但伤害为 0（结算问题）
	var shots := {}
	var hits := {}
	sim.shot_fired.connect(func(a, t, hit, _q, dmg):
		if int(a.team) != 0:
			return
		var k := int(a.ship_class)
		# ★ 战列「命中但 0 伤害」必须看到它打的是谁 —— 只有 5 发，全打出来
		#   （查完就关：把 DEBUG_BATTLESHIP 置 false）
		if DEBUG_BATTLESHIP and k == EveShip.Class.BATTLESHIP:
			print("      [战列] 目标=%s(hp %.0f) 命中=%s 伤害=%.1f 目标alive=%s" % [
					["护", "驱", "巡", "战巡", "战列"][int(t.ship_class)],
					t.total_hp(), str(hit), dmg, str(t.alive)])
		shots[k] = int(shots.get(k, 0)) + 1
		if hit:
			hits[k] = int(hits.get(k, 0)) + 1)
	var guard := 0
	# ★ 时间采样：B 方案（分层站位）**在数值上可以毫无差别**（实测 TTK / 输出逐字相同），
	#   它改变的是「前 30 秒各吨位停在哪」—— 这是纯空间/观感差异，
	#   只有按时间点采样才看得见，末态一采样就全丢了。
	var marks: Array = [6.0, 12.0, 18.0, 24.0, 30.0]
	var samples := {}
	while not sim.finished and sim.elapsed < 90.0 and guard < 3000:
		sim.run_seconds(0.1)
		guard += 1
		for m in marks:
			if not samples.has(m) and sim.elapsed >= float(m):
				samples[m] = _dist_profile(own, foe)
	var by_class := {}
	for s in own:
		# ⚠️ 必须统计**含阵亡**的船：只算活船会让「全灭的兵种」显示输出 0，
		#    看起来像「战列一枪没打」，实际是它打到死为止（2026-10-31 踩过）。
		var cls := int(s.ship_class)
		by_class[cls] = float(by_class.get(cls, 0.0)) + float(s.damage_dealt)
	var detail := "%.1fs · 攻方剩 %d 艘 · winner=%d" % [sim.elapsed, _alive(own), sim.winner_team]
	# ★ 末态几何 —— 45km 开局测出「双方 0 输出」时必须靠它区分两种病因：
	#   ① 压根没接到敌（还在飞）  ② 接到了但谁都不在射程内（站位/夹持问题）
	var gap := 0.0
	var nearest := INF
	for a in own:
		if not a.alive:
			continue
		for b in foe:
			if not b.alive:
				continue
			nearest = minf(nearest, a.body.position.distance_to(b.body.position))
	detail += " · 最近间距 %.1fkm" % (nearest / 1000.0 if nearest < INF else -1.0)
	var cls_rng := ""
	for a in own:
		if a.alive:
			cls_rng += "%s(射程%.0fkm,z%.0fkm) " % [
					["护", "驱", "巡", "战巡", "战列"][int(a.ship_class)],
					(a.optimal_range + a.falloff) / 1000.0, a.body.position.z / 1000.0]
	detail += " · " + cls_rng
	detail += " · 战列输出 %.0f / 战巡 %.0f / 护卫 %.0f" % [
			float(by_class.get(EveShip.Class.BATTLESHIP, 0.0)),
			float(by_class.get(EveShip.Class.BATTLE_CRUISER, 0.0)),
			float(by_class.get(EveShip.Class.FRIGATE, 0.0))]
	detail += " · 开火/命中 护%d/%d 战巡%d/%d 战列%d/%d" % [
			int(hits.get(EveShip.Class.FRIGATE, 0)), int(shots.get(EveShip.Class.FRIGATE, 0)),
			int(hits.get(EveShip.Class.BATTLE_CRUISER, 0)), int(shots.get(EveShip.Class.BATTLE_CRUISER, 0)),
			int(hits.get(EveShip.Class.BATTLESHIP, 0)), int(shots.get(EveShip.Class.BATTLESHIP, 0))]
	detail += " · 存活 %s" % ",".join(PackedStringArray(own.map(
			func(s): return "%.0f" % s.total_hp() if s.alive else "亡")))
	# 站位剖面：每个时间点上「各吨位距最近敌人多远」
	for m in [6.0, 12.0, 18.0, 24.0, 30.0]:
		if samples.has(m):
			detail += "\n      t=%2.0fs  %s" % [m, String(samples[m])]
	return {"detail": detail}


## 各吨位「距最近敌人」的距离（km），按吨位聚合取中位。
func _dist_profile(own: Array, foe: Array) -> String:
	var by := {}
	for a in own:
		if not a.alive:
			continue
		var best := INF
		for b in foe:
			if b.alive:
				best = minf(best, a.body.position.distance_to(b.body.position))
		if best == INF:
			continue
		var k := int(a.ship_class)
		if not by.has(k):
			by[k] = [] as Array[float]
		(by[k] as Array[float]).append(best / 1000.0)
	var names := ["护", "驱", "巡", "战巡", "战列"]
	var parts: PackedStringArray = []
	for k in [EveShip.Class.FRIGATE, EveShip.Class.CRUISER,
			EveShip.Class.BATTLE_CRUISER, EveShip.Class.BATTLESHIP]:
		if not by.has(k):
			continue
		var arr: Array[float] = by[k]
		arr.sort()
		parts.append("%s%.1f" % [names[int(k)], arr[arr.size() / 2]])
	return " ".join(parts) + " km"


## 按排布位：前排（靠敌）= 护卫/驱逐，后排（远离敌）= 大型舰。
## ⚠️ 后排 z 要沿 `aim_z` 方向**再退** 6 km：aim_z = ±1 是本队的朝向符号，
##    乘上去就自动对齐「离敌人更远」，不用写 if。
func _put_ranks(fleet: Array, z: float, aim_z: float) -> void:
	var small: Array = []
	var large: Array = []
	for s in fleet:
		if int(s.ship_class) <= EveShip.Class.DESTROYER:
			small.append(s)
		else:
			large.append(s)
	_put(small, z, aim_z)
	# 后排 = 更远离敌人。`aim_z` 是**朝向敌人**的符号（team0 = −1）
	# ⇒ 后退方向是 −aim_z ⇒ `z − aim_z × 6km`（写成 `z + aim_z × 6km` 会推到敌阵里）
	_put(large, z - aim_z * 6000.0, aim_z)


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
	# 摆位：双方沿 z 轴隔开，`gap_d` = **两军全距**（不是半距）。
	#
	# ⚠️⚠️ 2026-10-31 两处修正，都影响结论可信度：
	#   ① 方向：原来 own 摆在 **−z** 半场，与生产**正好相反**（生产 `deploy_own_z > 0`）。
	#      `_fleet_station()` 对 team0 有硬夹持 `station.z = max(station.z, 0)`
	#      ⇒ 摆在 −45km 的 team0 必须飞越中线 ⇒ 双方对穿、各跑到对方后方。
	#   ② 口径：原来把 gap 当成**半距**（各摆 ±gap = 全距 2×gap）。
	#      生产是 `compute_deploy_z()` = 1.15 × 射程中位数 **全距**，
	#      实测混编 34.5km / 纯护卫 13.8km / 纯战列 39.1km。
	#      传 45km 等于在模拟 90km —— 比生产远 2.6 倍，会得出「打不起来」的假象。
	var d := gap_d * 0.5
	_put(own, d, -1.0)   # team0：+z 半场，朝 −z（朝敌人）
	_put(foe, -d, 1.0)   # team1：−z 半场，朝 +z
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
