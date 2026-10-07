extends Node

## ★★ 53 轮（第四版）· **「改一艘船的朝向」反解器**
##
## ══════════════════════════════════════════════════════════════════
##  它解决什么
## ══════════════════════════════════════════════════════════════════
##  用户在实机（或总览图）上目视判定某艘船「舰艏应该是模型 +Y、船背是 +Z」
##  ⇒ 需要把它落成 `eve_ship_yaw.gd` 里的**两行**：
##        SHIP_AXES[id]  = "bow:+Y up:+Z"
##        AXIS_REMAP[id] = "..."          ← **必须同步重算**（红线 47b/48b）
##
##  ⚠️ 两张表是同一个不变量的两种表达，`validate()` 第 ⑧ 条会交叉校验。
##     只改一张 ⇒ `verify_run` 立刻飘红。所以**必须一起算**。
##
## ══════════════════════════════════════════════════════════════════
##  为什么不能手推 AXIS_REMAP
## ══════════════════════════════════════════════════════════════════
##  红线 40 / 48b：`AXIS_REMAP` 的 spec 是**行语义**（第 j 个 token = M 第 j 行），
##  手推错一次就是整艘倒飞且**不报错**（23 轮 kestrel 实测翻过车）。
##  ⇒ 本探针**只调生产函数**：`EveShipVisual._make_align(bow, up)` 给出把
##     bow→−Z、up→+Y 的矩阵，再按行语义转成 spec token。零手推。
##
##  用法：
##      Godot_v4.7.1-stable_win64_console.exe --headless \
##          --path "<工程>" --quit-after 900 \
##          res://tools/probe_setaxis53.tscn -- --id=tristan --bow=+Y --up=+Z
##
##  输出（可直接粘进源码的两行）：
##      SHIP_AXES  &"tristan": "bow:+Y up:+Z",
##      AXIS_REMAP &"tristan": "-Y,+Z,-X",
##
##  不传 `--bow/--up` 时：只打印该船**当前**的两行值（查表用）。

const YAW := preload("res://scripts/data/eve_ship_yaw.gd")
const SHIP_SCRIPT := preload("res://scripts/visual/eve_ship_visual.gd")

var _id := ""
var _bow := ""
var _up := ""


func _ready() -> void:
	var ua := OS.get_cmdline_user_args()
	for t in ua:
		if t.begins_with("--id="):
			_id = t.substr(5)
		elif t.begins_with("--bow="):
			_bow = t.substr(6)
		elif t.begins_with("--up="):
			_up = t.substr(5)

	if _id == "":
		print("用法：-- --id=<ship_id> [--bow=+X|+Y|+Z|-X|-Y|-Z] [--up=...]")
		get_tree().quit()
		return

	var sid := StringName(_id)
	print("══════════════════════════════════════════════════════════════")
	print("  53g · 朝向反解器 · 船 = %s" % _id)
	print("══════════════════════════════════════════════════════════════")

	# ── 当前值 ──
	var cb := YAW.bow_axis(sid)
	var cu := YAW.up_axis(sid)
	print("  现值：SHIP_AXES  bow=%s up=%s  side(bow×up)=%s" % [
			_tok(cb), _tok(cu), _tok(YAW.side_axis(sid))])
	print("        AXIS_REMAP = %s" % _current_remap_str(sid))
	print("")
	print("  ★ 左右约定：`side = bow × up` = 船自身的**右舷**")
	print("    （`_make_align` 把它送到世界 +X = 屏幕右侧；"
			+ "见 `EveShipYawTable.side_axis()` 注释：「纯派生，不许人工填」）")
	print("")

	if _bow == "" or _up == "":
		print("  （未给 --bow/--up ⇒ 只打印现值，不反解）")
		get_tree().quit()
		return

	# ── 反解 ──
	var b := _vec(_bow)
	var u := _vec(_up)
	if b == Vector3.ZERO or u == Vector3.ZERO:
		print("  ✗ --bow/--up 只能是 +X/-X/+Y/-Y/+Z/-Z")
		get_tree().quit()
		return
	if absf(b.dot(u)) > 0.01:
		print("  ✗ bow 与 up 必须正交（你给的 %s 与 %s 不正交）" % [_bow, _up])
		get_tree().quit()
		return

	# ★ 生产函数：把 (bow→−Z, up→+Y) 的矩阵（红线 40：零复刻）
	#
	# ⚠️⚠️ **53 轮踩坑**：传给 `_make_align` 的必须是**网格空间**的轴，
	#    **不是**模型根空间 —— 因为 `M` 的作用对象是 `mesh_rot` 之后的东西：
	#        `zero_pose = R_y(yaw) · M · mesh_rot`
	#        要求 `zero_pose · bow_local = −Z`
	#      ⇒ `M · (mesh_rot · bow_local) = −Z`
	#      ⇒ **`M = _make_align(mesh_rot·bow, mesh_rot·up)`**
	#    第一版我直接传 `bow_local`（漏了 `mesh_rot`）⇒ 反解出的 spec 自检
	#    报「舰艏 (0,−1,0) 朝敌 +0.000」（船侧躺），与现值也对不上。
	var mesh_rot: Basis = SHIP_SCRIPT.mesh_rot_of(sid).orthonormalized()

	# ⚠️ 斜轴船告警：`AXIS_REMAP` 的 spec 只能表达 **48 种置换矩阵**，
	#    而 `mesh_rot` 是斜轴（如 myrmidon/tristan 的 120°）时，`M` 需要的
	#    抵消矩阵**不是置换矩阵** ⇒ 反解必然丢失信息（实测 myrmidon 差 180°）。
	#    ⇒ 这类船**不许用本反解器**改，要走 `pose_table` 标定台或单独处理。
	if not _is_permutation_like(mesh_rot):
		print("  ⚠⚠ **斜轴船**：`mesh_rot` 不是置换矩阵（含非 ±1/0 分量）")
		print("     ⇒ spec 格式表达不了它 ⇒ 本反解器的结果**不可信**，别落表。")
		print("     实测：myrmidon / algos / catalyst 反解自检差 180°/90°。")
		print("     ⇒ 改这类船请走标定台（probe_bow_box）或单独推。")
		print("")

	var c: Basis = SHIP_SCRIPT._make_align(mesh_rot * b, mesh_rot * u)
	var spec := _spec_from_basis(c)

	print("  目标：bow=%s up=%s" % [_bow, _up])
	print("")
	print("  ── 请把这两行写进 scripts/data/eve_ship_yaw.gd ──")
	print("")
	print('      SHIP_AXES  &"%s": "%s",' % [_id, "bow:%s up:%s" % [_bow, _up]])
	print('      AXIS_REMAP &"%s": "%s",' % [_id, spec])
	print("")
	print("  ── 自检（用新 spec 反算的世界方向）──")
	var m := _basis_from_spec(spec)
	var zp: Basis = Basis.from_euler(Vector3(0, YAW.extra_yaw(sid), 0)) * m * mesh_rot
	var bw := (zp * b).normalized()
	var uw := (zp * u).normalized()
	print("      舰艏(世界) = %s   · 朝敌(−Z) = %+.3f" % [_v(bw), bw.dot(Vector3(0, 0, -1))])
	print("      船背(世界) = %s   · 朝天(+Y) = %+.3f" % [_v(uw), uw.dot(Vector3(0, 1, 0))])
	if bw.dot(Vector3(0, 0, -1)) > 0.999 and uw.dot(Vector3(0, 1, 0)) > 0.999:
		print("      ✅ 合格")
	else:
		print("      ⚠ 不合格 —— 别落表，先查")

	get_tree().quit()


## `Basis` → spec token。
##
## ⚠️⚠️ **53 轮踩坑记录**（这个坑值一条红线）：
##   `Basis.x / .y / .z` 是**列**（基向量），**不是行** —— Godot 文档写的是
##   "The basis's X axis (column 0)"。我第一版按"行"去读，反解出的 spec
##   自检直接报「舰艏 (0,-1,0) 朝敌 +0.000」——**差一个转置，船就侧躺**。
##   （`tools/probe_kestrel53.gd` 里那句「`x`/`y`/`z` 就是三行」的注释是**错的**，
##    已按此修正。）
##   ⇒ 取第 j 行用 **`c[j]`**（Godot `Basis` 的 `operator[]` 返回行）。
func _spec_from_basis(c: Basis) -> String:
	return ",".join(PackedStringArray([_tok(c[0]), _tok(c[1]), _tok(c[2])]))


## `mesh_rot` 是否"近似置换矩阵"（每个分量的绝对值接近 0 或 1）。
## 斜轴船（120° 之类）会有 0.5 / 0.707 这类分量 ⇒ 判 false。
func _is_permutation_like(m: Basis) -> bool:
	for r in 3:
		for c in 3:
			var a := absf(m[r][c])
			if a > 0.02 and a < 0.98:
				return false
	return true


## 把一行（±1/0 分量）写成 `+X` / `-Y` 形式
func _tok(row: Vector3) -> String:
	var ax := ["X", "Y", "Z"]
	var best := 0
	var bv := 0.0
	for i in 3:
		if absf(row[i]) > bv:
			bv = absf(row[i])
			best = i
	return ("+" if row[best] > 0.0 else "-") + ax[best]


func _vec(t: String) -> Vector3:
	match t.to_upper():
		"+X": return Vector3(1, 0, 0)
		"-X": return Vector3(-1, 0, 0)
		"+Y": return Vector3(0, 1, 0)
		"-Y": return Vector3(0, -1, 0)
		"+Z": return Vector3(0, 0, 1)
		"-Z": return Vector3(0, 0, -1)
	return Vector3.ZERO


## ⚠️ spec → Basis **必须调生产函数** `EveShipYawTable.parse_axis_remap()`
##   （红线 40 / 47 轮：自己复刻一份解析，行列语义写反就会"工具写的 spec
##    装回游戏是错的"，而且不报错，只是船倒着飞）。
func _basis_from_spec(spec: String) -> Basis:
	return YAW.parse_axis_remap(spec)


## 从源码文本读该船当前的 AXIS_REMAP 字符串
func _current_remap_str(sid: StringName) -> String:
	var src := FileAccess.get_file_as_string("res://scripts/data/eve_ship_yaw.gd")
	var i := src.find("const AXIS_REMAP := {")
	if i < 0:
		return "?"
	var j := src.find("\n}", i)
	var blk := src.substr(i, j - i)
	for ln in blk.split("\n"):
		var s := ln.strip_edges()
		if s.begins_with("&\"%s\":" % String(sid)):
			var p := s.find("\"", s.find(":"))
			var q := s.find("\"", p + 1)
			if p >= 0 and q > p:
				return s.substr(p + 1, q - p - 1)
	return "（未登记）"


func _v(v: Vector3) -> String:
	return "(%.2f,%+.2f,%+.2f)" % [v.x, v.y, v.z]
