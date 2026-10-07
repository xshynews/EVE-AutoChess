extends Node

## ★★ 53 轮（第十二版）· **批量翻转 up 方向**（48 艘 `up:+Y` → `up:-Y`）
##
## ══════════════════════════════════════════════════════════════════
##  它解决什么
## ══════════════════════════════════════════════════════════════════
##  48 轮的 ±Z 表把全库 48 艘的 `up` 都标成 `+Y`，但**用户的眼睛**对 `+Y` 那端
##  的语义理解与标定者相反（用户眼里"朝上 = 甲板有装甲的那面"，几何体 +Y 那端
##  在 EVE 模型里**实际上是**腹面）。⇒ 全库 48 艘都需要 `up:+Y` → `up:-Y`。
##
##  ⚠️ 旋转 180° 相当于绕 `bow` 轴翻 = bow 不变、up 翻号、side 翻号。
##  ⇒ `AXIS_REMAP` 的 M 矩阵需要**整体重算**（红线 48b：两张表必须同步改）。
##
## ══════════════════════════════════════════════════════════════════
##  实现要点
## ══════════════════════════════════════════════════════════════════
##  · 不动 bow（用户眼里的"船头"判读对了一半 ⇒ bow 不翻）
##  · up 翻号（_Y）；side 由 `bow × up` 自动翻（红线 50c：派生不填）
##  · `AXIS_REMAP` 通过 `probe_setaxis53` 已有的反解路径
##    （`_make_align(mesh_rot·bow, mesh_rot·up)` ⇒ 枚举 48 spec）来
##    重算 M ⇒ 不会出现"两张表一改一忘"
##  · 4 艘离群（algos/catalyst/myrmidon/tristan）**保持原样**，
##    它们本来就 up:±Z/±X，不参与批量翻转
##
##  用法：
##      Godot_v4.7.1-stable_win64_console.exe --headless \
##          --path "<工程>" --quit-after 30000 \
##          res://tools/probe_flip_up.tscn

const YAW := preload("res://scripts/data/eve_ship_yaw.gd")
const SHIP_SCRIPT := preload("res://scripts/visual/eve_ship_visual.gd")

var _lines: PackedStringArray = []


func _ready() -> void:
	# 读 pose_table.json（用户重标过的版本；如果不存在就退回到源码 SHIP_AXES）
	var pt: Dictionary = _load_pose_table()
	if pt.is_empty():
		print("⚠ pose_table.json 不存在或为空 —— 退回到源码 SHIP_AXES")
	print("══════════════════════════════════════════════════════════════")
	print("  53 轮 · 批量翻转 up（48 艘 +Y → −Y · 4 艘离群不动）")
	print("══════════════════════════════════════════════════════════════")

	var flips: Array[String] = []
	var n_skip := 0
	var n_no_res := 0
	for sid in _sorted_keys(pt):
		var v: Dictionary = pt[sid]
		var b: Vector3 = _vec(String(v.get("bow", "")))
		var u: Vector3 = _vec(String(v.get("up", "")))
		if b == Vector3.ZERO or u == Vector3.ZERO:
			n_skip += 1
			continue
		if u != Vector3(0, 1, 0):
			# 不是 +Y：跳过（离群或已翻过）
			n_skip += 1
			continue
		var mesh_rot: Basis = SHIP_SCRIPT.mesh_rot_of(StringName(sid)).orthonormalized()
		var b_in_mesh: Vector3 = mesh_rot * b
		var u_in_mesh: Vector3 = mesh_rot * u
		# 翻号：up 由 +Y → -Y
		var hits := _search(StringName(sid), b, Vector3(0, -1, 0), b.cross(Vector3(0, -1, 0)))
		if hits.size() != 1:
			n_no_res += 1
			print("  ✗ %-12s 无唯一解（hits=%d）" % [sid, hits.size()])
			continue
		flips.append(sid)
		var new_spec: String = hits[0]
		print("  ↻ %-12s bow=%-3s up:%-3s→up:-Y  AXIS_REMAP=%s" % [
				sid, String(v["bow"]), String(v["up"]), new_spec])
		_p('      &"%s": "bow:%s up:-Y",' % [sid, String(v["bow"])])
		_p('      &"%s": "%s",' % [sid, new_spec])

	_p("")
	_p("──────────────────────────────────────────────────────────")
	_p("  共翻转 %d 艘 · 跳过 %d 艘 · 无解 %d 艘" % [flips.size(), n_skip, n_no_res])
	_p("──────────────────────────────────────────────────────────")
	_p("")
	_p("── SHIP_AXES 新块（贴回源码）──")
	for sid in flips:
		var v: Dictionary = pt[sid]
		_p('    &"%s": "bow:%s up:-Y",' % [sid, String(v["bow"])])
	_p("")
	_p("── AXIS_REMAP 新块（贴回源码）──")
	for sid in flips:
		var v: Dictionary = pt[sid]
		var b: Vector3 = _vec(String(v["bow"]))
		var u: Vector3 = Vector3(0, -1, 0)
		var hits := _search(StringName(sid), b, u, b.cross(u))
		if hits.size() == 1:
			_p('    &"%s": "%s",' % [sid, hits[0]])

	get_tree().quit()


func _load_pose_table() -> Dictionary:
	var p := "user://bow_calib/pose_table.json"
	if not FileAccess.file_exists(p):
		return {}
	var s: String = FileAccess.get_file_as_string(p)
	var v: Variant = JSON.parse_string(s)
	if not (v is Dictionary):
		return {}
	return v


func _sorted_keys(d: Dictionary) -> Array:
	var k: Array = []
	for key in d.keys():
		k.append(String(key))
	k.sort()
	return k


func _search(sid: StringName, b: Vector3, u: Vector3, side: Vector3) -> Array[String]:
	var ax: Array[Vector3] = [
		Vector3(1, 0, 0), Vector3(-1, 0, 0),
		Vector3(0, 1, 0), Vector3(0, -1, 0),
		Vector3(0, 0, 1), Vector3(0, 0, -1),
	]
	var mesh_rot: Basis = SHIP_SCRIPT.mesh_rot_of(sid).orthonormalized()
	var b_in_mesh: Vector3 = mesh_rot * b
	var u_in_mesh: Vector3 = mesh_rot * u
	var s_in_mesh: Vector3 = mesh_rot * side
	var out: Array[String] = []
	for r0 in ax:
		for r1 in ax:
			if absf(r0.dot(r1)) > 0.5:
				continue
			for r2 in ax:
				if absf(r0.dot(r2)) > 0.5 or absf(r1.dot(r2)) > 0.5:
					continue
				var spec := "%s,%s,%s" % [_tok(r0), _tok(r1), _tok(r2)]
				var m: Basis = YAW.parse_axis_remap(spec)
				var zp: Basis = m * mesh_rot
				if (zp * b).normalized().dot(Vector3(0, 0, -1)) < 0.999:
					continue
				if (zp * u).normalized().dot(Vector3(0, 1, 0)) < 0.999:
					continue
				if (zp * side).normalized().dot(Vector3(1, 0, 0)) < 0.999:
					continue
				out.append(spec)
	return out


func _tok(v: Vector3) -> String:
	var n := ["X", "Y", "Z"]
	for i in 3:
		if absf(v[i]) > 0.5:
			return ("+" if v[i] > 0.0 else "-") + n[i]
	return "+X"


func _vec(t: String) -> Vector3:
	match t.to_upper():
		"+X": return Vector3(1, 0, 0)
		"-X": return Vector3(-1, 0, 0)
		"+Y": return Vector3(0, 1, 0)
		"-Y": return Vector3(0, -1, 0)
		"+Z": return Vector3(0, 0, 1)
		"-Z": return Vector3(0, 0, -1)
	return Vector3.ZERO


func _p(s: String) -> void:
	print(s)
	_lines.append(s)
