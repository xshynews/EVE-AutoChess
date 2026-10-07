extends Node
## 单点诊断：为什么「实机布阵 45 秒零伤害」？
##
## `_fire_once()` 里 **只有命中才写日志**（`if not hit: return`），
## 所以"日志不涨"有两种可能：① 一炮没开 ② 开了但全 MISS。
## 靠 `shot_fired` 信号（**每次开火都发**，含 MISS）把两者分开。
##
## 命中率公式（`EveCombatCore.turret_chance_to_hit`）：
##   range_factor    = 0.5^((d − optimal)/falloff)²      d ≤ optimal 时为 1
##   tracking_factor = 0.5^(angular / tracking)²         （sig_res = target_sig 时）
##   chance = range_factor × tracking_factor
## ⇒ **角速度 angular = 横向相对速度 / 距离**，是这个尺度下的胜负手。
const SIM_SCRIPT := preload("res://scripts/core/eve_battle_simulator.gd")
const RUN_SCRIPT := preload("res://scripts/core/eve_run_state.gd")

const HALF_M := 6900.0        # compute_deploy_z 在护卫档给出的半距


func _ready() -> void:
	_run(true)
	_run(false)
	get_tree().quit()


func _run(deployed: bool) -> void:
	var a: Array[EveShip] = []
	for i in 3:
		a.append(EveShipDatabase.instantiate_by_id("punisher", 0, 100 + i))
	var b: Array[EveShip] = []
	for id in EveEnemyComps.ship_ids("pirate_scout"):
		var e: EveShip = EveShipDatabase.instantiate_by_id(String(id), 1, 200 + b.size())
		if e == null:
			continue
		RUN_SCRIPT.apply_enemy_scaling(e, 1, 1.0)
		b.append(e)

	if deployed:
		for i in a.size():
			a[i].body.position = Vector3((float(i % 4) - 1.5) * 8000.0, 0.0, HALF_M)
		for i in b.size():
			b[i].body.position = Vector3((float(i % 4) - 1.5) * 8000.0, 0.0, -HALF_M)

	print("\n" + "=".repeat(72))
	print(deployed and "【实机布阵】开局相距 %.0f m" % (HALF_M * 2) or "【贴脸】不设初始位置")
	var s0: EveShip = a[0]
	print("  惩罚者级：射程 %.0f  falloff %.0f  追踪 %.3f  信号 %.0f  循环 %.2fs  极速 %.0f m/s"
			% [s0.optimal_range, s0.falloff, s0.tracking,
			   s0.signature_resolution, s0.weapon_cycle, s0.body.max_speed])

	var sim: Variant = SIM_SCRIPT.new()
	sim.setup(a, b)
	sim.set_time_limit(45.0)

	var n_shots := [0]
	var n_hits := [0]
	sim.shot_fired.connect(func(_at, _tg, h, _q, _d):
		n_shots[0] += 1
		if h:
			n_hits[0] += 1)

	var t := 0.0
	for k in 1350:
		sim.step(1.0 / 30.0)
		t += 1.0 / 30.0
		if (k + 1) % 150 == 0:
			var hit_pct := 100.0 * float(n_hits[0]) / maxf(1.0, float(n_shots[0]))
			print("  t=%4.1fs 最近 %5.0f m  炮 %3d 中 %3d（%4.1f%%）  存活 我 %d/%d 敌 %d/%d"
					% [t, _closest(a, b), n_shots[0], n_hits[0], hit_pct,
					   _alive(a), a.size(), _alive(b), b.size()])
	var hit_pct2 := 100.0 * float(n_hits[0]) / maxf(1.0, float(n_shots[0]))
	print("  [结果] winner=%d  存活 我 %d/%d 敌 %d/%d  总炮 %d  总中 %d  命中率 %.1f%%"
			% [int(sim.get("winner_team")), _alive(a), a.size(),
			   _alive(b), b.size(), n_shots[0], n_hits[0], hit_pct2])


func _alive(pool: Array[EveShip]) -> int:
	var n := 0
	for s in pool:
		if s.alive:
			n += 1
	return n


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
