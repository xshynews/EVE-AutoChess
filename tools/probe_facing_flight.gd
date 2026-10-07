extends Node
## 第二十一轮验证：sync_from_body 改后 bow 在战斗中是否朝速度方向
##
## 跑法：
##   "C:/godot/Godot_v4.7.1-stable_win64_console.exe" --path "F:/evezzq/eve自走棋918" \
##     --quit-after 8000 res://tools/probe_facing_flight.tscn

const YAW := preload("res://scripts/data/eve_ship_yaw.gd")

# 4 艘代表
const CASES := [
	{"id": "abaddon",  "name": "地狱天使级",  "v_init": Vector3(0, 0, -300)},
	{"id": "catalyst", "name": "促进级",     "v_init": Vector3(0, 0, -300)},
	{"id": "myrmidon", "name": "蚁熊级",     "v_init": Vector3(0, 0, -300)},
	{"id": "kestrel",  "name": "茶隼级",     "v_init": Vector3(0, 0, -300)},
	{"id": "abaddon",  "name": "地狱天使级（右飞）", "v_init": Vector3(300, 0, 0)},
]

var _lines: Array[String] = []


func _ready() -> void:
	for c in CASES:
		var id := StringName(c["id"])
		var v_init: Vector3 = c["v_init"]
		var v_n := v_init.normalized()
		var speed_angle := atan2(v_init.x, v_init.z)

		# 1. setup: model.basis = R_y(MODEL_YAW_FIX) · M
		var M := YAW.axis_remap(id)
		var yaw := -PI / 2.0 + YAW.extra_yaw(id)
		var model_basis := Basis.from_euler(Vector3(0, yaw, 0)) * M
		# 未打时 bow
		var bow_setup := model_basis * Vector3(1, 0, 0)
		# 跑过 N 帧后 lerp_angle 收敛到 target = speed_angle + PI
		var facing_target := speed_angle + PI
		# lerp_angle 0.12 跑 100 帧 ≈ 1 - 0.88^100 ≈ 1（已收敛）
		var facing_after := _lerp_to(facing_target, 0.12, 100)
		var bow_after := Basis.from_euler(Vector3(0, facing_after, 0)) * bow_setup

		_lines.append("═══ %s (%s)" % [c["name"], String(id)])
		_lines.append("  v_init = (%.0f, %.0f, %.0f)  speed_angle = %.1f°  target_facing = %.1f°" % [
			v_init.x, v_init.y, v_init.z,
			rad_to_deg(speed_angle), rad_to_deg(facing_target)])
		_lines.append("  setup 后 bow (rotation.y=0) = (%.3f, %.3f, %.3f) %s" % [
			bow_setup.x, bow_setup.y, bow_setup.z,
			_where(bow_setup)])
		_lines.append("  100 帧后 bow (rotation.y=%.1f°) = (%.3f, %.3f, %.3f) %s" % [
			rad_to_deg(facing_after), bow_after.x, bow_after.y, bow_after.z, _where(bow_after)])
		_lines.append("  bow · v_normalized = %.3f  (1.0 = 完美对齐)" % bow_after.dot(v_n))
		_lines.append("")

	for s in _lines:
		print(s)
	get_tree().quit(0)


func _lerp_to(target: float, t: float, n: int) -> float:
	# 从 0 平滑到 target（模拟 lerp_angle 0.12 跑 N 帧）
	var cur := 0.0
	for _i in n:
		cur = _lerp_angle(cur, target, t)
	return cur


func _lerp_angle(a: float, b: float, t: float) -> float:
	var d := fposmod(b - a + PI, TAU) - PI
	return a + d * t


func _where(bow: Vector3) -> String:
	if bow.y < -0.5:
		return "(朝下 — myrmidon 特例)"
	if absf(bow.y) > 0.5:
		return "(垂直)"
	if bow.z < -0.9:
		return "(朝敌 −Z)"
	if bow.z > 0.9:
		return "(朝我方 +Z)"
	return "(侧向)"
