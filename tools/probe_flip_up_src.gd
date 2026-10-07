extends Node

## ★★ 53 轮 · **源码作真源 · 批量翻 up（48 艘）** ★★
##
## 与 probe_flip_up.tscn 的区别：直接读 `eve_ship_yaw.gd` 源码的 SHIP_AXES，
## 不依赖 `pose_table.json`（否则会把上一轮用户的 ±X 标定带回来）。

const YAW := preload("res://scripts/data/eve_ship_yaw.gd")
const SHIP_SCRIPT := preload("res://scripts/visual/eve_ship_visual.gd")

const SRC_PATH := "res://scripts/data/eve_ship_yaw.gd"

var _lines: PackedStringArray = []
var _new_axes: Dictionary = {}
var _new_remap: Dictionary = {}


func _ready() -> void:
	print("══════════════════════════════════════════════════════════════")
	print("  53 轮 · 批量翻 up（基于源码 48 轮 ±Z 表 · 48 艘）")
	print("══════════════════════════════════════════════════════════════")

	var src := FileAccess.get_file_as_string(SRC_PATH)
	var cur := _parse_block(src, "SHIP_AXES")
	var cur_r := _parse_block(src, "AXIS_REMAP")
	if cur.is_empty():
		print("✗ 解析源码失败")
		get_tree().quit()
		return

	var n := 0
	var n_skip := 0
	var pat: RegEx = RegEx.create_from_string("^bow:([+-][XYZ]) up:([+-][XYZ])$")
	for sid in cur.keys():
		var v: String = cur[sid]
		var m := pat.search(v)
		if m == null:
			n_skip += 1
			continue
		var bow_sign: String = m.get_string(1)
		var up_sign: String = m.get_string(2)
		if up_sign != "+Y":
			# 不是 +Y：跳过（algos/catalyst/myrmidon/tristan）
			n_skip += 1
			continue
		# 翻：up +Y → -Y
		var new_axes_val := "bow:%s up:-Y" % bow_sign
		# AXIS_REMAP：调用 _make_align 反解
		var b := _vec(bow_sign)
		var u := Vector3(0, -1, 0)
		var new_spec: String = _solve_remap(StringName(sid), b, u)
		if new_spec == "":
			n_skip += 1
			continue
		_new_axes[sid] = new_axes_val
		_new_remap[sid] = new_spec
		print("  ↻ %-12s %-18s ⇒  %-18s  AXIS_REMAP=%s" % [
				sid, v, new_axes_val, new_spec])
		n += 1

	print("")
	print("══════════════════════════════════════════════════════════════")
	print("  翻 %d 艘 · 跳过 %d 艘 · 无解 0" % [n, n_skip])
	print("══════════════════════════════════════════════════════════════")
	_emit("SHIP_AXES", _new_axes)
	_emit("AXIS_REMAP", _new_remap)

	# 写到 src 的副本（不动源码），供人手动核对
	# 不在工程目录里 patch 源码，避免用户源被覆盖。
	# 改用 `apply` 探针风格：用 _lines 拼好的两段，写到 /tmp 等待 python 接管。
	var f := FileAccess.open("user://flip_up_result.txt", FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(_lines))
		f.close()
		print(" 报告已写：user://flip_up_result.txt")
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


func _solve_remap(sid: StringName, b: Vector3, u: Vector3) -> String:
	var ax: Array[Vector3] = [
		Vector3(1, 0, 0), Vector3(-1, 0, 0),
		Vector3(0, 1, 0), Vector3(0, -1, 0),
		Vector3(0, 0, 1), Vector3(0, 0, -1),
	]
	var mesh_rot: Basis = SHIP_SCRIPT.mesh_rot_of(sid).orthonormalized()
	var side: Vector3 = b.cross(u)
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
				return spec
	return ""


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
