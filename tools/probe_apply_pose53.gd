extends Node

## ★★ 53 轮（第五版）· **把标定台结果（`pose_table.json`）应用回源码**
##
## ══════════════════════════════════════════════════════════════════
##  它解决什么
## ══════════════════════════════════════════════════════════════════
##  `probe_bow_box` 落表写在 `user://bow_calib/pose_table.json`
##  （**按设计不直接改源码**，见该文件注释）⇒ 用户标完 52 艘之后，
##  源码 `eve_ship_yaw.gd` 的 `SHIP_AXES` / `AXIS_REMAP` **还是旧的**。
##  本探针负责把标定值**反解**成两张表并落盘。
##
## ══════════════════════════════════════════════════════════════════
##  为什么用「枚举 48 spec」而不是直接反解
## ══════════════════════════════════════════════════════════════════
##  直接反解（`_make_align`）在**斜轴船**上会失败（53 轮实测 myrmidon 差 180°、
##  algos/catalyst 差 90°）—— 因为 spec 只能表达 48 种置换矩阵，
##  而斜轴 `mesh_rot` 需要的抵消矩阵不是置换矩阵。
##
##  ⇒ 改为**枚举全部 48 个 spec**，判据**三条同时成立**（红线 48b）：
##        `M · mesh_rot · bow  = −Z`（舰艏朝敌）
##        `M · mesh_rot · up   = +Y`（船背朝天）
##        `M · mesh_rot · side = +X`（右舷朝屏幕右）
##  ★ 第三条必须有：否则每艘会命中 2 个解（左右镜像都是解）。
##  ⇒ **唯一命中**才采纳；0 个 / ≥2 个都报出来人工处理。
##
##  用法：
##      Godot_v4.7.1-stable_win64_console.exe --headless \
##          --path "<工程>" --quit-after 9000 \
##          res://tools/probe_apply_pose53.tscn -- --out "<路径>"

const YAW := preload("res://scripts/data/eve_ship_yaw.gd")
const SHIP_SCRIPT := preload("res://scripts/visual/eve_ship_visual.gd")

const POSE_PATH := "user://bow_calib/pose_table.json"
## ⚠️ 53 轮实测：headless 下 `FileAccess.open("C:/...", WRITE)` 会让进程直接崩
##   （退出码 2、无任何错误输出）⇒ 兜底写 `user://`。
const FALLBACK_OUT := "user://apply_pose53.txt"

var _lines: PackedStringArray = []
var _out := ""


func _ready() -> void:
	var ua := OS.get_cmdline_user_args()
	for t in ua:
		if t.begins_with("--out="):
			_out = t.substr(6)

	if not FileAccess.file_exists(POSE_PATH):
		print("✗ 找不到 %s" % POSE_PATH)
		get_tree().quit()
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(POSE_PATH))
	if not (parsed is Dictionary):
		print("✗ pose_table.json 解析失败")
		get_tree().quit()
		return
	var pose: Dictionary = parsed

	_p("══════════════════════════════════════════════════════════════")
	_p("  53h · pose_table.json → SHIP_AXES / AXIS_REMAP（枚举 48 spec）")
	_p("══════════════════════════════════════════════════════════════")
	_p("  判据三条同时成立：bow→−Z · up→+Y · side→+X（side 那条防左右镜像双解）")
	_p("")

	var ok_lines: Array[String] = []
	var remap_lines: Array[String] = []
	var n_ok := 0
	var n_multi := 0
	var n_none := 0

	for sid in _sorted_keys(pose):
		var v: Dictionary = pose[sid]
		var bow_s := String(v.get("bow", ""))
		var up_s := String(v.get("up", ""))
		var b := _vec(bow_s)
		var u := _vec(up_s)
		if b == Vector3.ZERO or u == Vector3.ZERO:
			_p("  ⚠ %-12s bow/up 取值非法：%s / %s" % [sid, bow_s, up_s])
			n_none += 1
			continue
		if absf(b.dot(u)) > 0.01:
			_p("  ⚠ %-12s bow 与 up 不正交：%s / %s" % [sid, bow_s, up_s])
			n_none += 1
			continue

		var mesh_rot: Basis = SHIP_SCRIPT.mesh_rot_of(StringName(sid)).orthonormalized()
		var side := b.cross(u)
		var hits := _search(mesh_rot, b, u, side)
		if hits.size() == 1:
			n_ok += 1
			ok_lines.append('\t&"%s": "bow:%s up:%s",' % [sid, bow_s, up_s])
			remap_lines.append('\t&"%s": "%s",' % [sid, hits[0]])
			_p("  ✔ %-12s bow=%-3s up=%-3s  →  AXIS_REMAP = %s" % [sid, bow_s, up_s, hits[0]])
		elif hits.is_empty():
			n_none += 1
			_p("  ✗ %-12s bow=%-3s up=%-3s  →  **无解**（斜轴？需人工）" % [sid, bow_s, up_s])
		else:
			n_multi += 1
			_p("  ✗ %-12s bow=%-3s up=%-3s  →  **%d 个解**：%s" % [
					sid, bow_s, up_s, hits.size(), ", ".join(hits)])

	_p("")
	_p("──────────────────────────────────────────────────────────")
	_p("  合计 %d 艘：唯一解 %d · 多解 %d · 无解 %d" % [pose.size(), n_ok, n_multi, n_none])
	_p("──────────────────────────────────────────────────────────")
	_p("")
	_p("── 请替换 SHIP_AXES 块 ──")
	for l in ok_lines:
		_p(l)
	_p("")
	_p("── 请替换 AXIS_REMAP 块 ──")
	for l in remap_lines:
		_p(l)

	if _out != "":
		var f := FileAccess.open(_out, FileAccess.WRITE)
		if f != null:
			f.store_string("\n".join(_lines))
			f.close()
			print("")
			print("[probe_apply_pose53] 已写：%s" % ProjectSettings.globalize_path(_out))
		else:
			# ⚠️ 53 轮实测：headless 下直接写工程外绝对路径会崩（退出码 2，无报错）。
			#    ⇒ 兜底写 `user://`，再让外部脚本拷贝。
			var fb := FileAccess.open(FALLBACK_OUT, FileAccess.WRITE)
			if fb != null:
				fb.store_string("\n".join(_lines))
				fb.close()
				print("")
				print("⚠ 写 %s 失败 ⇒ 已兜底写到 %s" % [_out, FALLBACK_OUT])
				print("[probe_apply_pose53] 绝对路径：%s"
						% ProjectSettings.globalize_path(FALLBACK_OUT))
			else:
				print("✗ 两个路径都写失败")
	get_tree().quit()


## 枚举 48 个 spec，返回全部满足三条判据的
func _search(mesh_rot: Basis, b: Vector3, u: Vector3, side: Vector3) -> Array[String]:
	var ax: Array[Vector3] = [
		Vector3(1, 0, 0), Vector3(-1, 0, 0),
		Vector3(0, 1, 0), Vector3(0, -1, 0),
		Vector3(0, 0, 1), Vector3(0, 0, -1),
	]
	var out: Array[String] = []
	for r0 in ax:
		for r1 in ax:
			if absf(r0.dot(r1)) > 0.5:
				continue
			for r2 in ax:
				if absf(r0.dot(r2)) > 0.5 or absf(r1.dot(r2)) > 0.5:
					continue
				var spec := "%s,%s,%s" % [_tok(r0), _tok(r1), _tok(r2)]
				var m := YAW.parse_axis_remap(spec)
				var zp := m * mesh_rot
				if (zp * b).normalized().dot(Vector3(0, 0, -1)) < 0.999:
					continue
				if (zp * u).normalized().dot(Vector3(0, 1, 0)) < 0.999:
					continue
				if (zp * side).normalized().dot(Vector3(1, 0, 0)) < 0.999:
					continue
				out.append(spec)
	return out


func _sorted_keys(d: Dictionary) -> Array:
	var k: Array = []
	for key in d.keys():
		k.append(String(key))
	k.sort()
	return k


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
