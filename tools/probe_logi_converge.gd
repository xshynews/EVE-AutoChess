extends Node

## EVE 自走棋 —— 后勤修理对「战斗收敛性」的影响探针（2026-10-01）
##
## 背景：加后勤修理之后 verify_run 卡住了（>4 分钟没跑完）。
## 必须先**证伪**猜测再改代码 —— 所以本探针做对拍：
##   A 组：修理关掉（logistics_repair = 0）
##   B 组：修理打开（表里的值）
## 同一编队、同一种子、同一时限，看 A/B 的收场时间与结果。
##
## ⚠️ 不跑渲染、不跑 UI，直接推 sim.step()。
const FIXED := 1.0 / 60.0

var _lines: Array[String] = []


func _ready() -> void:
	_lines.append("后勤修理 vs 战斗收敛性 —— 同一编队对拍")
	_lines.append("")
	# 用户实机最可能撞上的组合：我方 4 艘混编（含 1 艘后勤），敌方 pirate_scout。
	# 编队照节点 1 的真实配置来。
	_run_case("A 组：后勤修理【关】", 0.0)
	_run_case("B 组：后勤修理【开】（护卫 12/次，2 秒周期）", 12.0)
	_run_case("C 组：后勤修理【开·加倍】（24/次）", 24.0)
	_run_case("D 组：后勤修理【开·四倍】（48/次）", 48.0)

	var f := FileAccess.open("user://probe_logi_converge.txt", FileAccess.WRITE)
	for l in _lines:
		print(l)
		f.store_line(l)
	f.close()
	get_tree().quit()


func _run_case(title: String, repair: float) -> void:
	_lines.append("──────────────────────────────────────────────")
	_lines.append(title)
	# 我方：攻击型 ×2 + 防御型 ×1 + 后勤 ×1（护卫档）
	var own: Array[EveShip] = []
	var keys := ["condor", "incursus", "kestrel", "bantam"]
	for i in keys.size():
		var s := EveShipDatabase.instantiate_by_id(keys[i], 0, 1000 + i)
		if s == null:
			_lines.append("  ✗ 建船失败：" + keys[i])
			return
		if keys[i] == "bantam":
			s.logistics_repair = repair
			if repair <= 0.0:
				s.logistics_layer = &""
		own.append(s)
	# 敌方：节点 1 的真实编组
	var foe: Array[EveShip] = []
	var ids := EveEnemyComps.ship_ids("pirate_scout")
	for i in ids.size():
		var s := EveShipDatabase.instantiate_by_id(String(ids[i]), 1, 2000 + i)
		if s == null:
			continue
		foe.append(s)

	var sim := EveBattleSimulator.new()
	sim.setup(own, foe)
	sim.set_time_limit(45.0)

	var t := 0.0
	var finished_at := -1.0
	var winner := -99
	while t < 180.0:
		sim.step(FIXED)
		t += FIXED
		if sim.finished:
			finished_at = t
			winner = sim.winner_team
			break
	if finished_at < 0.0:
		_lines.append("  ✗ **180 秒内未收敛** —— 这就是病")
	else:
		_lines.append("  收场：%.1f 秒 · 胜方 team=%d（0=我 / 1=敌 / -1=平）"
				% [finished_at, winner])
	# 统计修理贡献
	var healed := 0.0
	var shots := 0.0
	for s in own:
		healed += s.repaired_total
		shots += s.damage_dealt
	_lines.append("  后勤累计修入 %.0f 点 · 我方累计输出 %.0f 点 · 占比 %.1f%%"
			% [healed, shots, (0.0 if shots <= 0.0 else healed / shots * 100.0)])
	_lines.append("")
