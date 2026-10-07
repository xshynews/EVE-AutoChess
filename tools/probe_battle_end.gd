extends Node
const NODE := preload("res://scripts/data/eve_node_table.gd")
## 「敌方存活 / 战斗结束原因」实测探针
##
## ⛔⛔ 这个探针踩过一个**把结论全带偏**的坑，写在最显眼处：
##
##   第一版**没给双方设初始位置** —— `EveShip.create()` 出来的船都在原点，
##   两队在 (0,0,0) 附近**贴脸开打**，于是跑出"20 秒全歼"这种漂亮结论。
##   而实机上 `EveBattleArena.compute_deploy_z()` 会把两队拉开十几公里
##   （护卫射程 12 km、开局距离 13.8 km）—— **先要飞一段才进射程**。
##
##   ⇒ 凡是"这场仗打多久 / 打不打得完"的实测，**必须复现初始布阵**，
##     否则测的是另一个游戏。本探针现在两种都跑，直接对比。
##
## 判定来源：`scripts/core/eve_battle_simulator.gd:_check_outcome`
##   敌全灭 → 胜(0)   我全灭 → 负(1)   两边都空 → 平(-1)
##   ★ 到时限 → **一律判负(1)**（2026-10-01 起，不再按剩余总血判）

const SIM_SCRIPT := preload("res://scripts/core/eve_battle_simulator.gd")
const RUN_SCRIPT := preload("res://scripts/core/eve_run_state.gd")

const OUR_ID := "punisher"          # 惩罚者 · 艾玛护卫（新手第一档常用）
const DUMP_EVERY := 150             # 每 5 秒打一行状态

# ── `EveBattleArena` 的布阵常量（复现实机开局用，与那边保持一致）────────
const COL_STEP := 8000.0
const ROW_STEP := 6000.0
const STANDOFF_RATIO := 1.15
const ARENA_RADIUS_WORLD := 120.0
const WORLD_UNIT_IN_METERS := 1000.0


func _ready() -> void:
	print("=".repeat(78))
	print("敌方存活 / 结束原因实测（时限与敌方 comp 都取自节点表）")
	print("=".repeat(78))
	print("★ 每组跑两遍：**实机布阵**（有初始距离）vs **贴脸**（旧探针的错法）")
	# ⚠️ 全部 12 个战斗节点（事件节点没有战斗）。scale / time 与 eve_node_table 一致。
	#    我方艘数按「该节点时玩家正常应有的上场上限」给（等级上限 6 → 最多 8 艘），
	#    这里统一给 5 艘（中期典型），只看**时限够不够**。
	var rows := NODE.ROWS
	for r in rows:
		var tp := String(r.get("type", ""))
		if tp == "event":
			continue
		_case("节点%d(%s) ×5" % [int(r["index"]), tp],
				String(r.get("comp", "")), float(r.get("scale", 1.0)),
				5, float(r.get("time", 45.0)))
	get_tree().quit()


func _case(tag: String, comp: String, scale: float, own_n: int, limit: float) -> void:
	print("\n" + "-".repeat(78))
	print("[%s]  敌方 comp=%s  我方 %d 艘" % [tag, comp, own_n])
	for deployed in [true, false]:
		_run(comp, scale, own_n, limit, deployed)


## 跑一场完整战斗。`deployed == true` ⇒ 按实机算法摆开双方。
func _run(comp: String, scale: float, own_n: int, limit: float, deployed: bool) -> void:
	var a: Array[EveShip] = []
	for i in own_n:
		var s: EveShip = EveShipDatabase.instantiate_by_id(OUR_ID, 0, 3000 + i)
		if s == null:
			print("  !! 取不到船: %s" % OUR_ID)
			return
		a.append(s)

	var b: Array[EveShip] = []
	for id in _comp_ship_ids(comp):
		var e: EveShip = EveShipDatabase.instantiate_by_id(String(id), 1, 4000 + b.size())
		if e == null:
			continue
		RUN_SCRIPT.apply_enemy_scaling(e, 1, scale)
		b.append(e)

	if deployed:
		var dz := _deploy_z(a, b)
		_place(a, 0, float(dz[0]))
		_place(b, 1, float(dz[1]))

	var tag := "实机布阵" if deployed else "贴脸（旧探针的错法）"
	print("   ── %s ──  射程 %.0f / 交战距离 %.0f / 速度 %.0f m/s · 开局最近距离 %.0f m"
			% [tag, a[0].optimal_range, a[0].desired_range,
			   a[0].body.max_speed, _closest(a, b)])

	var sim: Variant = SIM_SCRIPT.new()
	sim.setup(a, b)
	sim.set_time_limit(limit)

	var t := 0.0
	var guard := 0
	var ever_fought := false
	while not bool(sim.finished) and guard < 40000:
		sim.step(1.0 / 30.0)
		t += 1.0 / 30.0
		guard += 1
		if _closest(a, b) <= a[0].optimal_range:
			ever_fought = true
		if guard % DUMP_EVERY == 0:
			print("        t=%5.1fs 我 %d/%d 敌 %d/%d  最近 %5.0f  我z %6.0f 敌z %6.0f  锁定 %d  日志 %d"
					% [t, _alive(a), a.size(), _alive(b), b.size(),
					   _closest(a, b), _avg_z(a), _avg_z(b),
					   _locked(a), sim.log_entries.size()])

	var winner := int(sim.get("winner_team"))
	# ⚠️ winner ∈ {−1 平局, 0 我方胜, 1 我方负} ⇒ winner+1 ∈ {0,1,2}
	#    （这里曾经把数组写成 ["我方胜","我方负","平局"]，于是"敌方全灭"
	#     被印成"我方负"、"我方全灭"被印成"平局" —— 判据对、**显示错**。）
	var wname: String = String(["平局", "我方胜", "我方负"][winner + 1])
	var leaked := _alive(b)
	var why := "敌方全灭" if leaked == 0 else ("我方全灭" if _alive(a) == 0 else "超时判负")
	print("        ⇒ t=%.1fs（%.0f%% 时限）· %s · %s · 结束存活 我 %d/%d 敌 %d/%d · 曾经进过射程=%s"
			% [t, t / limit * 100.0, wname, why,
			   _alive(a), a.size(), leaked, b.size(), "是" if ever_fought else "**否**"])


# ── 复现 `EveBattleArena` 的布阵（本次探针修正的核心）──────────────────

## `EveBattleArena.compute_deploy_z()` 的等价实现
func _deploy_z(own: Array[EveShip], enemy: Array[EveShip]) -> Array:
	var allships: Array[EveShip] = []
	allships.append_array(own)
	allships.append_array(enemy)
	var ranges: Array[float] = []
	for s in allships:
		ranges.append(float(s.optimal_range))
	if ranges.is_empty():
		return [6900.0, -6900.0]
	ranges.sort()
	var mid := ranges.size() / 2
	var median := ranges[mid] if ranges.size() % 2 == 1 \
			else (ranges[mid - 1] + ranges[mid]) * 0.5
	var longest := ranges[ranges.size() - 1]
	var basis := minf(maxf(median, 12_000.0), longest)
	var half_m := basis * STANDOFF_RATIO * 0.5
	half_m = clampf(half_m, 6_000.0,
			ARENA_RADIUS_WORLD * WORLD_UNIT_IN_METERS * 0.6)
	return [half_m, -half_m]


## `EveBattleArena.default_formation()` 的等价实现
func _place(fleet: Array[EveShip], team: int, z_center: float) -> void:
	var sign_z := -1.0 if team == 0 else 1.0
	for i in fleet.size():
		var row := i / 4
		var col := i % 4
		var p := Vector3((float(col) - 1.5) * COL_STEP, 0.0,
				z_center + sign_z * float(row) * ROW_STEP)
		fleet[i].body.position = p
		fleet[i].body.previous_position = p


# ── 工具 ──────────────────────────────────────────────────────────────

func _comp_ship_ids(comp: String) -> Array:
	return EveEnemyComps.ship_ids(comp)


## 我方平均 z —— 看"到底有没有接近"（敌方在 −z 侧）
func _avg_z(pool: Array[EveShip]) -> float:
	var acc := 0.0
	var n := 0
	for s in pool:
		if s.alive:
			acc += s.body.position.z
			n += 1
	return 0.0 if n == 0 else acc / float(n)


## 已锁定的船数 —— 开火的前提
func _locked(pool: Array[EveShip]) -> int:
	var n := 0
	for s in pool:
		if s.alive and s.locked:
			n += 1
	return n


func _alive(pool: Array[EveShip]) -> int:
	var n := 0
	for s in pool:
		if s.alive:
			n += 1
	return n


## 两队之间最近的船距（米）—— 用来判断"到底有没有接敌"
func _closest(a: Array[EveShip], b: Array[EveShip]) -> float:
	var best := INF
	for x in a:
		if not x.alive:
			continue
		for y in b:
			if not y.alive:
				continue
			var d := x.body.position.distance_to(y.body.position)
			if d < best:
				best = d
	return 0.0 if best == INF else best
