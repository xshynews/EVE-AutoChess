extends Node
## ⚠️⚠️ **已作废（2026-09-26 第二十二轮，红线 46）—— 留档，别再按它的结论改代码**
##
## 本探针的结论「最佳 δ = +π / rotation.y 方案可行」**只在单 yaw 自由度下成立**，
## 且对舰艏轴不在水平面的船（myrmidon / tristan）**数学上无解**（它自己打印的
## `dot=0.000` 就是死锁的证据，当年被误读成了"例外可接受"）。
##
## 现行实现 = `sync_from_body` 的**完整旋转对齐**（`Basis.looking_at(v̂,UP)·C` + slerp），
## 验收换 `tools/probe_bow_align.gd`（52 艘 × 4 航向，bow·v̂ 必须严格 = 1）。
##
## ── 以下为原文 ────────────────────────────────────────────────────
## 第二十一轮开局：验算 "rotation.y 偏移量" 让 bow 朝速度方向
##
## 跑法：
##   "C:/godot/Godot_v4.7.1-stable_win64_console.exe" --headless \
##     --path "F:/evezzq/eve自走棋918" --quit-after 5000 \
##     res://tools/probe_facing_offset.tscn

const YAW := preload("res://scripts/data/eve_ship_yaw.gd")
const MODEL_YAW_FIX := -PI / 2.0


func _ready() -> void:
	# 1. 枚举几个代表性 spec，列出 ship.rotation.y = atan2(v.x,v.z) + δ 时的 bow
	# 2. δ = 让 bow 朝速度方向的常量偏移
	var cases := [
		{"id": "abaddon",   "spec": "-X,+Y,-Z",  "note": "28 艘主类"},
		{"id": "catalyst",  "spec": "-X,+Z,+Y",  "note": "2 艘"},
		{"id": "myrmidon",  "spec": "-Y,-X,-Z",  "note": "长轴在 Y（特例）"},
		{"id": "tristan",   "spec": "+Y,-X,+Z",  "note": "长轴在 Y（特例）"},
		{"id": "kestrel",   "spec": "-X,+Y,-Z",  "note": "改后同 abaddon"},
	]
	for c in cases:
		var spec: String = c["spec"]
		var M := _spec_to_basis(spec)
		# setup 时 model.basis = R_y(-π/2)·M
		var M_setup := Basis.from_euler(Vector3(0.0, MODEL_YAW_FIX, 0.0)) * M
		var bow_no_yaw := M_setup * Vector3(1.0, 0.0, 0.0)  # 未打时 bow（ship.rotation.y = 0）
		print("")
		print("═══ %s (%s) — %s" % [c["id"], spec, c["note"]])
		print("  setup 后 bow_world (rotation.y=0) = (%.3f, %.3f, %.3f) %s" % [
			bow_no_yaw.x, bow_no_yaw.y, bow_no_yaw.z,
			("(朝我方)" if bow_no_yaw.z > 0.1 else ("(朝敌)" if bow_no_yaw.z < -0.1 else "(垂直/侧向)"))])

		# 速度朝敌人方向 (0, 0, -1)：speed_angle = atan2(0, -1) = π
		var speed_angle := PI
		var v_n := Vector3(sin(speed_angle), 0, cos(speed_angle))
		# 假设 ship.rotation.y = speed_angle + δ
		# bow = R_y(speed_angle + δ) · M_setup · (1, 0, 0)
		# 用数值方法：找 δ 让 bow · v_normalized = 1
		var best_delta := 0.0
		var best_dot := -2.0
		for i in 360:
			var delta := deg_to_rad(float(i) - 180.0)
			var bow := Basis.from_euler(Vector3(0.0, speed_angle + delta, 0.0)) * M_setup * Vector3(1.0, 0.0, 0.0)
			var d := bow.dot(v_n)
			if d > best_dot:
				best_dot = d
				best_delta = delta
		print("  速度朝敌 (speed_angle=π) ⇒ 最佳 δ = %.1f° (dot=%.3f)" % [
			rad_to_deg(best_delta), best_dot])

		# 速度朝我方 (0, 0, +1)：speed_angle = 0
		speed_angle = 0.0
		v_n = Vector3(0.0, 0.0, 1.0)
		best_delta = 0.0
		best_dot = -2.0
		for i in 360:
			var delta := deg_to_rad(float(i) - 180.0)
			var bow := Basis.from_euler(Vector3(0.0, speed_angle + delta, 0.0)) * M_setup * Vector3(1.0, 0.0, 0.0)
			var d := bow.dot(v_n)
			if d > best_dot:
				best_dot = d
				best_delta = delta
		print("  速度朝我方 (speed_angle=0) ⇒ 最佳 δ = %.1f° (dot=%.3f)" % [
			rad_to_deg(best_delta), best_dot])

		# 速度朝右 (1, 0, 0)：speed_angle = π/2
		speed_angle = PI / 2.0
		v_n = Vector3(1.0, 0.0, 0.0)
		best_delta = 0.0
		best_dot = -2.0
		for i in 360:
			var delta := deg_to_rad(float(i) - 180.0)
			var bow := Basis.from_euler(Vector3(0.0, speed_angle + delta, 0.0)) * M_setup * Vector3(1.0, 0.0, 0.0)
			var d := bow.dot(v_n)
			if d > best_dot:
				best_dot = d
				best_delta = delta
		print("  速度朝右 (speed_angle=π/2) ⇒ 最佳 δ = %.1f° (dot=%.3f)" % [
			rad_to_deg(best_delta), best_dot])

	get_tree().quit(0)


func _spec_to_basis(spec: String) -> Basis:
	var parts := spec.split(",")
	var rows: Array[Vector3] = []
	for p in parts:
		var s := String(p).strip_edges()
		var sign := 1.0 if s[0] == "+" else -1.0
		var v := Vector3.ZERO
		match s[1].to_upper():
			"X": v.x = sign
			"Y": v.y = sign
			"Z": v.z = sign
		rows.append(v)
	return Basis(
		Vector3(rows[0].x, rows[1].x, rows[2].x),
		Vector3(rows[0].y, rows[1].y, rows[2].y),
		Vector3(rows[0].z, rows[1].z, rows[2].z))
