extends Node

## 无头验证脚本 —— 不依赖任何输入，跑一局完整战斗并打印台账
##
## 用法：
##   godot_console.exe --headless --path <工程> --quit-after 3000 ^
##       res://tools/verify_battle.tscn -- --own=5 --enemy=6
##
## 目的：
##   1. 验证舰船数值表、运动学、战斗数学能串起来
##   2. 打印关键指标（距离/角速度/存活数），确认战斗收敛
##   3. 断言不会永久挂起

var _sim: EveBattleSimulator
var _tick := 0
var _last_report := 0
var _finished := false
var _shot_count := 0
var _hit_count := 0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var own := 5
	var enemy := 6
	for a in args:
		if a.begins_with("--own="):
			own = int(a.substr(6))
		elif a.begins_with("--enemy="):
			enemy = int(a.substr(8))

	print("=".repeat(72))
	print("[1] 舰船数据库自检")
	print("=".repeat(72))

	var all := EveShipDatabase.all_ships()
	print("舰船总数: %d" % all.size())
	var by_faction: Dictionary = {}
	var by_class: Dictionary = {}
	for d in all:
		by_faction[d["faction"]] = by_faction.get(d["faction"], 0) + 1
		by_class[d["class"]] = by_class.get(d["class"], 0) + 1
	# ⚠️ 别在这里硬编码中文名数组。
	#    曾经写死成 3 档 ["护卫","驱逐","巡洋"]，船表扩到 5 档（战列巡洋/战列）后
	#    直接 index 越界 —— 而且报错发生在 _ready() 里，会把后面的 _sim 初始化整段吃掉，
	#    症状是 _process 每帧刷 "Nonexistent function 'step' in base 'Nil'"，
	#    看起来像战斗逻辑崩了，其实是第 48 行越界。改用权威表当唯一来源。
	for f in by_faction:
		print("  派系 %s : %d 型" % [EveShip.FACTION_NAMES.get(f, "?"), by_faction[f]])
	for c in by_class:
		print("  吨位 %s : %d 型" % [EveShip.CLASS_NAMES.get(c, "?"), by_class[c]])

	var pk: EveShip = EveShipDatabase.instantiate(0, 0, 1001)
	print("\n[抽查] %s (%s %s %d费)" % [
		pk.ship_name, pk.faction_name(), pk.class_name_cn(), pk.cost])
	print("  血量  护盾 %.0f / 装甲 %.0f / 结构 %.0f  = %.0f" % [
		pk.max_hp[&"shield"], pk.max_hp[&"armor"], pk.max_hp[&"hull"], pk.total_max_hp()])
	print("  武器  %s  伤害 %.1f / 循环 %.2fs  → 理论 DPS %.1f" % [
		pk._extra.get("weapon_type", "?"), pk.weapon_damage, pk.weapon_cycle,
		pk.weapon_damage / pk.weapon_cycle])
	print("  射程  %.0f + %.0f m   追踪 %.3f   信号分辨率 %.0f" % [
		pk.optimal_range, pk.falloff, pk.tracking, pk.signature_resolution])
	print("  抗性  护盾 %s" % _arr(pk.resists[&"shield"]))
	print("        装甲 %s" % _arr(pk.resists[&"armor"]))
	print("  电容  %.0f  回充 %.1f/s  耗电 %.1f" % [pk.cap_max, pk.cap_regen, pk.cap_use])
	print("  机动  速度 %.0f m/s  质量 %.0f kg  灵活度 %.1f" % [
		pk.body.max_speed, pk.body.mass, pk.body.agility])
	print("  锁定时间 %.2f s" % pk.lock_total)
	print("  羁绊  %s" % str(pk.traits))

	print("\n" + "=".repeat(72))
	print("[2] 战斗推演  own=%d  enemy=%d" % [own, enemy])
	print("=".repeat(72))

	_sim = EveBattleSimulator.new()
	_sim.unit_destroyed.connect(_on_destroyed)
	_sim.battle_finished.connect(_on_finished)
	_sim.shot_fired.connect(_on_shot)

	var own_fleet := _gen(own, 0, 100)
	var enemy_fleet := _gen(enemy, 1, 500)
	_place(own_fleet, enemy_fleet, 0)
	_place(enemy_fleet, own_fleet, 1)
	_sim.setup(own_fleet, enemy_fleet)


func _process(_dt: float) -> void:
	if _finished:
		return
	# 每帧推进 4 个 tick → 300 帧 ≈ 40 秒战斗时间
	for i in 4:
		if _finished:
			return
		_sim.step(EveBattleSimulator.FIXED_STEP)
		_tick += 1
		if _tick - _last_report >= int(EveBattleSimulator.TICK_RATE) * 5:
			_last_report = _tick
			_report()
	if _tick >= EveBattleSimulator.MAX_TICKS:
		print("\n[警告] 到达最大 tick(%d) 仍未结束 —— 战斗未收敛！" % EveBattleSimulator.MAX_TICKS)
		_report()
		_finish_report(-2)


func _report() -> void:
	var alive_a := 0
	var alive_b := 0
	var total_ang := 0.0
	var total_dist := 0.0
	var pairs := 0
	var total_hp_a := 0.0
	var total_hp_b := 0.0
	for s in _sim.ships:
		if not s.alive:
			continue
		if s.team == 0:
			alive_a += 1
			total_hp_a += s.total_hp()
		else:
			alive_b += 1
			total_hp_b += s.total_hp()
		if s.target_id > 0:
			var t: EveShip = _sim._ship_by_id.get(s.target_id)
			if t and t.alive:
				var m := EveCombatCore.relative_motion(
					s.body.position, s.body.velocity, t.body.position, t.body.velocity)
				total_ang += m["angular"]
				total_dist += m["distance"]
				pairs += 1
	var avg_ang := total_ang / maxf(1.0, float(pairs))
	var avg_dist := total_dist / maxf(1.0, float(pairs))
	print("t=%5.1fs | A:%d(%6.0f) B:%d(%6.0f) | 交战对:%2d | 均距 %6.0fm 均角速 %.5f" % [
		_sim.elapsed, alive_a, total_hp_a, alive_b, total_hp_b, pairs, avg_dist, avg_ang])


func _gen(count: int, team: int, base_id: int) -> Array[EveShip]:
	var out: Array[EveShip] = []
	var n := EveShipDatabase.all_ships().size()
	for i in count:
		out.append(EveShipDatabase.instantiate(i % n, team, base_id + i))
	return out


## 战场单位约定（全工程统一，务必遵守）
##
##   body.position / body.velocity / optimal_range / falloff / radius
##   —— 全部以【米】为单位，和 EVE 原始数据一致。
##   只有【渲染层】(EveBattleArena 的 Node3D 位置) 才做 米→世界单位 的缩放，
##   缩放系数是 EveBattleArena.world_unit_in_meters = 1000。
##
##   所以仿真里部署 40 km = 写 40000.0，不要写 40.0。
func _place(fleet: Array[EveShip], other: Array[EveShip], team: int) -> void:
	# 与实战一致：按双方射程【中位数】算部署间距（避免被单艘远程船拉爆）
	var ranges: Array[float] = []
	for s in fleet + other:
		if s != null:
			ranges.append(s.optimal_range)
	if ranges.is_empty():
		ranges.append(20_000.0)
	ranges.sort()
	var mid := ranges.size() / 2
	var median := ranges[mid] if ranges.size() % 2 == 1 \
			else (ranges[mid - 1] + ranges[mid]) * 0.5
	var basis := clampf(median, 12_000.0, ranges[ranges.size() - 1])
	# ⚠️ 必须与 EveBattleArena.deploy_standoff_ratio 保持一致，
	#    否则「无头验证跑得通」但「实机打不完」——两边参数不同就没有验证意义。
	var standoff_m := basis * 1.15
	var z := standoff_m * 0.5 if team == 0 else -standoff_m * 0.5
	# 4 列阵型（与 arena.default_formation 同构），列距 8km
	var n := fleet.size()
	var col_step := 8_000.0
	for i in n:
		var col := i % 4
		var row := i / 4
		var x := (float(col) - 1.5) * col_step
		var zz := z + (float(row) * 6_000.0) * (-1.0 if team == 0 else 1.0)
		fleet[i].body.position = Vector3(x, 0.0, zz)
		fleet[i].body.previous_position = fleet[i].body.position
		fleet[i].body.velocity = Vector3.ZERO


func _on_destroyed(ship: EveShip) -> void:
	print("      >>> 击毁 %s (队%d)  t=%.1fs" % [ship.ship_name, ship.team, _sim.elapsed])


func _on_shot(_a: EveShip, _t: EveShip, hit: bool, _q: int, _d: float) -> void:
	_shot_count += 1
	if hit:
		_hit_count += 1


func _on_finished(winner: int) -> void:
	_finish_report(winner)


func _finish_report(winner: int) -> void:
	if _finished:
		return
	_finished = true
	print("\n" + "=".repeat(72))
	match winner:
		-2: print("[结果] 未收敛（超时保护触发）")
		-1: print("[结果] 平局")
		0:  print("[结果] 己方(队0) 获胜")
		1:  print("[结果] 敌方(队1) 获胜")
	print("[用时] %.1fs   ticks=%d" % [_sim.elapsed, _tick])
	print("[开火] %d 次，命中 %d 次，命中率 %.1f%%" % [
		_shot_count, _hit_count,
		100.0 * float(_hit_count) / maxf(1.0, float(_shot_count))])
	var st := _sim.statistics()
	print("[总输出] %.0f 伤害" % float(st["total_damage"]))
	print("[日志] %d 条" % int(st["log_count"]))
	print("=".repeat(72))
	get_tree().quit(0)


func _arr(a: PackedFloat32Array) -> String:
	var parts: PackedStringArray = []
	for v in a:
		parts.append("%d%%" % int(round(v * 100.0)))
	return "[%s]  电磁/热能/动能/爆炸" % " ".join(parts)
