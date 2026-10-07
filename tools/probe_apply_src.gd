extends Node

## ★ 53 轮（第二十版）· **从源码读 SHIP_AXES + 枚举反解 AXIS_REMAP**
##
## 与 `probe_apply_pose53` 的区别：本探针**不读 `pose_table.json`**，
## 直接从 `eve_ship_yaw.gd` 源码的 `const SHIP_AXES := { ... }` 块取值。

const YAW := preload("res://scripts/data/eve_ship_yaw.gd")
const SHIP_SCRIPT := preload("res://scripts/visual/eve_ship_visual.gd")
const SRC_PATH := "res://scripts/data/eve_ship_yaw.gd"

var _lines: PackedStringArray = []
var _new_remap: Dictionary = {}


func _ready() -> void:
	var src := FileAccess.get_file_as_string(SRC_PATH)
	var cur := _parse_block(src, "SHIP_AXES")
	if cur.is_empty():
		print("✗ 解析源码 SHIP_AXES 失败")
		get_tree().quit()
		return

	print("══════════════════════════════════════════════════════════════")
	print("  53 轮 · 从源码 SHIP_AXES 反解 AXIS_REMAP")
	print("══════════════════════════════════════════════════════════════")
	print("  源共 %d 艘" % cur.size())

	var n := 0
	var n_no := 0
	var _na: Dictionary = {}
	for sid in cur.keys():
		var v: String = cur[sid]
		var m := RegEx.create_from_string("^bow:([+-][XYZ]) up:([+-][XYZ])$").search(v)
		if m == null:
			n_no += 1
			continue
		var bow_sign: String = m.get_string(1)
		var up_sign: String = m.get_string(2)
		var b := _vec(bow_sign)
		var u := _vec(up_sign)
		var hits := _search(StringName(sid), b, u)
		if hits.size() != 1:
			n_no += 1
			print("  ✗ %-12s 无唯一解（hits=%d）" % [sid, hits.size()])
			continue
		_new_remap[sid] = hits[0]
		print("  ✔ %-12s bow=%-3s up=%-3s  AXIS_REMAP=%s" % [
				sid, bow_sign, up_sign, hits[0]])
		n += 1

	print("")
	print("  反解 %d 艘 · 无解 %d 艘" % [n, n_no])
	_emit("AXIS_REMAP", _new_remap)

	var f := FileAccess.open("user://apply_src.txt", FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(_lines))
		f.close()
	get_tree().quit()


func _parse_block(src: String, cn: String) -> Dictionary:
	var i := src.find("const %s := {" % cn)
	if i < 0:
		return {}
	var j := src.find("\n}", i)
	var blk := src.substr(i, j - i)
	var out: Dictionary = {}
	for m in RegEx.create_from_string('&"(\\w+)":\\s*"([^"]+)"').search_all(blk):
		out[m.get_string(1)] = m.get_string(2)
	return out


func _vec(sign: String) -> Vector3:
	match sign:
		"+X": return Vector3(1, 0, 0)
		"-X": return Vector3(-1, 0, 0)
		"+Y": return Vector3(0, 1, 0)
		"-Y": return Vector3(0, -1, 0)
		"+Z": return Vector3(0, 0, 1)
		"-Z": return Vector3(0, 0, -1)
	return Vector3.ZERO


func _search(sid: StringName, b: Vector3, u: Vector3) -> Array[String]:
	var ax: Array[Vector3] = [
		Vector3(1, 0, 0), Vector3(-1, 0, 0),
		Vector3(0, 1, 0), Vector3(0, -1, 0),
		Vector3(0, 0, 1), Vector3(0, 0, -1),
	]
	var mesh_rot: Basis = SHIP_SCRIPT.mesh_rot_of(sid).orthonormalized()
	var side: Vector3 = b.cross(u)
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


func _emit(label: String, tab: Dictionary) -> void:
	_p("── %s 新块（共 %d 艘）──" % [label, tab.size()])
	for sid in tab.keys():
		_p('    &"%s": "%s",' % [sid, tab[sid]])


func _p(s: String) -> void:
	print(s)
	_lines.append(s)
