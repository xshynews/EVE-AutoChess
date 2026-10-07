extends Node

## 逐船诊断 —— 打印每一艘船的目标、期望距离、实际距离、姿态
## 用来定位"舰队整体漂移"到底是哪一类船在拖

var _sim: EveBattleSimulator
var _tick := 0
var _done := false
var _report_at := [10.0, 30.0, 60.0, 90.0]
var _ri := 0


func _ready() -> void:
	_sim = EveBattleSimulator.new()
	# ⚠️ 别在注释里写死船名（比如以前的「惩罚者级 护卫 9km」）。
	#    船表从 12 艘换成 52 艘权威表之后，索引 0/1/2 早就不是惩罚者/刽子手/灾难了，
	#    写死的注释只会误导下一个读代码的人。改成运行期打印实际拿到什么。
	var own: Array[EveShip] = [
		EveShipDatabase.instantiate(0, 0, 101),
		EveShipDatabase.instantiate(1, 0, 102),
		EveShipDatabase.instantiate(2, 0, 103),
	]
	var foe: Array[EveShip] = [
		EveShipDatabase.instantiate(3, 1, 201),
		EveShipDatabase.instantiate(2, 1, 202),
	]
	print("[诊断] 我方 = %s" % _fleet_str(own))
	print("[诊断] 敌方 = %s" % _fleet_str(foe))
	for i in own.size():
		own[i].body.position = Vector3(-40.0 + i * 40.0, 0.0, 45000.0)
	for i in foe.size():
		foe[i].body.position = Vector3(-30.0 + i * 40.0, 0.0, -45000.0)
	_sim.setup(own, foe)


func _process(_dt: float) -> void:
	if _done:
		return
	for i in 4:
		_sim.step(EveBattleSimulator.FIXED_STEP)
		_tick += 1
		if _ri < _report_at.size() and _sim.elapsed >= _report_at[_ri]:
			_ri += 1
			_snapshot()
		if _ri >= _report_at.size():
			_done = true
			get_tree().quit(0)
			return


func _snapshot() -> void:
	print("\n" + "=".repeat(88))
	print("t = %.0f s" % _sim.elapsed)
	print("=".repeat(88))
	print("%s %s %6s %8s %8s %8s %9s %9s %8s" % [
		_pad("舰船", 12), _pad("队", 4), "吨位", "射程", "期望", "距离", "径向", "横向", "角速度"])
	print("-".repeat(88))
	for s in _sim.ships:
		if not s.alive:
			continue
		var t: EveShip = _sim._ship_by_id.get(s.target_id)
		if t == null:
			print("%s %s 无目标" % [_pad(s.ship_name, 12), _pad(str(s.team), 4)])
			continue
		var m := EveCombatCore.relative_motion(
			s.body.position, s.body.velocity, t.body.position, t.body.velocity)
		print("%s %s %6d %8.0f %8.0f %8.0f %9.0f %9.0f %8.4f" % [
			_pad(s.ship_name, 12), _pad(str(s.team), 4), s.ship_class,
			s.optimal_range, s.engagement_range(t.optimal_range),
			m["distance"], m["radial"], m["transversal"], m["angular"]])
		print("             └ 目标=%s 姿态=%s 锁定=%s 速度=%6.0f" % [
			_pad(t.ship_name, 12), _pad(EveDestinyMotion.stance_label(s.stance), 8),
			_pad(str(s.locked), 5), s.body.velocity.length()])


func _fleet_str(fleet: Array[EveShip]) -> String:
	var parts: PackedStringArray = []
	for s in fleet:
		if s == null:
			parts.append("<null>")
			continue
		parts.append("%s(%s %s)" % [s.ship_name, s.faction_name(), s.class_name_cn()])
	return ", ".join(parts)


## 按【显示宽度】补空格。
##
## ⚠️ Godot 的 "%-12s" 是按【字符数】算的，而中文一个字在终端占两格 ——
##    用它排中文列会歪。52 艘权威表里船名长短不一（小鹰级 / 亥伯龙神级 / 多米尼克斯级），
##    歪得更明显，所以这里自己按东亚全角宽度算。
func _pad(text: String, width: int) -> String:
	var w := 0
	for i in text.length():
		w += 2 if _is_wide(text.unicode_at(i)) else 1
	var fill := width - w
	return text + " ".repeat(fill) if fill > 0 else text


func _is_wide(cp: int) -> bool:
	# CJK 统一表意 / 假名 / 谚文 / 全角标点 —— 覆盖本工程用得到的全部中文
	return (cp >= 0x1100 and cp <= 0x115F) \
			or (cp >= 0x2E80 and cp <= 0xA4CF) \
			or (cp >= 0xAC00 and cp <= 0xD7A3) \
			or (cp >= 0xF900 and cp <= 0xFAFF) \
			or (cp >= 0xFE30 and cp <= 0xFE6F) \
			or (cp >= 0xFF00 and cp <= 0xFF60) \
			or (cp >= 0xFFE0 and cp <= 0xFFE6)
