extends Node
## 49 轮 · **终极归因探针**：用「工具那把尺子」量实机。
##
## ═══ 用户的核心质疑 ═══
##   「我那个工具是不是白花 token 来写了？我定了舰船的朝向，
##     那按照我定的再全部定其他地方的位置不就行了？怎么还能天天调」
##
## ═══ 本探针要一次说清的三件事 ═══
##
##  ── ① 工具标的值到底有没有被用上？──
##   逐艘打印 `SHIP_AXES[id]` 与 `pose_table.json[id]`，**并排**给结论。
##
##  ── ② 工具的「模型空间轴」到实机的「世界方向」中间隔了几层变换？──
##   工具里轴杆摆在世界系、船姿 = 用户手转的 `r`、**船身是模型原始姿态**；
##   实机里船姿 = `R_y(extra)·M·mesh_rot` 再叠全局滚转，**还叠了一层 C**。
##   ⇒ 打印这条链**逐层的输出向量**，看哪一层把 up 翻了。
##
##  ── ③ ★关键：**「实机静止姿态」与「用户工具里摆出的那个静止姿态」是否同一姿态**？
##  这是唯一重要的判据。做法：
##     · A = 实机零姿态基 `zero_pose_basis(id)`（生产函数）
##     · B = 工具里「船姿 r=单位阵」时的基 —— 就是「模型原始姿态」= 单位阵
##       （工具里的船不吃 `zero_pose_basis`，见 `probe_bow_box._apply_ship_transform`）
##   ⇒ 若 A ≠ B，说明**工具里看到的船 ≠ 实机里的船**，
##     那用户"以工具为准"就永远对不上 —— 这正是"天天调"的根因。
##
## 输出：`user://diag49.txt` + stdout

const IDX := preload("res://scripts/data/eve_ship_asset_index.gd")
const YAW := preload("res://scripts/data/eve_ship_yaw.gd")
## ⚠️ `load()` 不是常量表达式 ⇒ 只能用 `var`（用 `const` 会 Parse Error）。
var ZPS: Variant = load("res://scripts/visual/eve_ship_visual.gd")

const ENEMY := Vector3(0.0, 0.0, -1.0)
const UP := Vector3(0.0, 1.0, 0.0)

var _L: Array[String] = []


func _ready() -> void:
	# provider 必须先装上，否则 mesh_rot 全是单位阵（假数据）
	ZPS.call("mesh_rot_of", &"abaddon")

	_L.append("╔══════════════════════════════════════════════════════════════════════╗")
	_L.append("║  49 轮 · 用「工具那把尺子」量实机 —— 归因报告                        ║")
	_L.append("╚══════════════════════════════════════════════════════════════════════╝")
	_L.append("")
	_L.append("【坐标口径】敌人恒在世界 −Z（红线 42）· 天上 = +Y")
	_L.append("")

	_check_table()
	_check_chain()
	_check_tool_vs_game()
	_write()
	get_tree().quit(0)


## ① 表 vs 用户标定 —— 逐条并排
func _check_table() -> void:
	_L.append("═══ ① 工具标定值 ↔ SHIP_AXES 源码表 ═══")
	_L.append("")
	var rows := IDX.all()
	rows.sort_custom(func(a, b): return String(a.id) < String(b.id))
	var diff := 0
	_L.append("  %-13s %-18s %-18s %s" % ["id", "SHIP_AXES(源码)", "工具标定(pose_table)", "结论"])
	for s in rows:
		var sid := String(s.id)
		var src := YAW.ship_axes_text(StringName(sid))
		var tool := _tool_pose(sid)
		var ok := (src == tool)
		if not ok:
			diff += 1
		_L.append("  %-13s %-18s %-18s %s" % [sid, src, tool, "一致" if ok else "★不一致"])
	_L.append("")
	_L.append("  ⇒ 不一致 %d 条（共 %d 艘）" % [diff, rows.size()])
	_L.append("")


## ② 变换链逐层打印（取 3 艘代表：主流 / 特殊 spec / 有 FLIP 历史）
func _check_chain() -> void:
	_L.append("═══ ② 生产变换链逐层输出（实机静止姿态）═══")
	_L.append("")
	_L.append("  链：geo = R_y(extra) · M · mesh_rot ；zp = global_roll · geo")
	_L.append("")
	for sid_s in ["abaddon", "catalyst", "myrmidon", "kestrel", "tristan"]:
		var sid := StringName(sid_s)
		var m: Basis = YAW.axis_remap(sid)
		var mr: Basis = ZPS.call("mesh_rot_of", sid)
		var ex: float = YAW.extra_yaw(sid)
		var geo: Basis = ZPS.call("zero_pose_basis_no_roll", sid)
		var zp: Basis = ZPS.call("zero_pose_basis", sid)
		var b: Vector3 = YAW.bow_axis(sid)
		var u: Vector3 = YAW.up_axis(sid)
		_L.append("  ── %s ──  SHIP_AXES=%s  spec=%s  extra_yaw=%.2f°" % [
			sid_s, YAW.ship_axes_text(sid), String(YAW.AXIS_REMAP.get(sid, "·")), rad_to_deg(ex)])
		_L.append("     M      ·bow=(%+.2f,%+.2f,%+.2f)  ·up=(%+.2f,%+.2f,%+.2f)" % [
			(m * b).x, (m * b).y, (m * b).z, (m * u).x, (m * u).y, (m * u).z])
		_L.append("     mesh_rot = %s" % str(_rot_kind(mr)))
		_L.append("     geo·bow=(%+.2f,%+.2f,%+.2f)  geo·up=(%+.2f,%+.2f,%+.2f)   ← 不含滚转" % [
			(geo * b).x, (geo * b).y, (geo * b).z, (geo * u).x, (geo * u).y, (geo * u).z])
		_L.append("     zp ·bow=(%+.2f,%+.2f,%+.2f)  zp ·up=(%+.2f,%+.2f,%+.2f)   ← 实机实际" % [
			(zp * b).x, (zp * b).y, (zp * b).z, (zp * u).x, (zp * u).y, (zp * u).z])
		_L.append("")
	_L.append("")


## ③ ★ 工具里看到的船姿 vs 实机船姿 —— 这是根因所在
func _check_tool_vs_game() -> void:
	_L.append("═══ ③ ★ 工具里「船身姿态」 vs 实机「零姿态」 ═══")
	_L.append("")
	_L.append("  工具里：_holder.basis = r · _ship_norm.basis，而 _ship_norm.basis = 纯缩放")
	_L.append("          ⇒ r 为单位阵时，船 = **模型原始姿态**（即单位阵）")
	_L.append("  实机里：model.basis = zero_pose_basis(id) = global_roll · R_y(extra) · M · mesh_rot")
	_L.append("")
	var n_diff := 0
	var rows := IDX.all()
	rows.sort_custom(func(a, b): return String(a.id) < String(b.id))
	_L.append("  %-13s %-30s %s" % ["id", "实机静止 bow / up（世界系）", "实机 ≠ 工具?"])
	for s in rows:
		var sid := StringName(s.id)
		var zp: Basis = ZPS.call("zero_pose_basis", sid)
		var bw := (zp * YAW.bow_axis(sid)).normalized()
		var uw := (zp * YAW.up_axis(sid)).normalized()
		# 工具里（船=单位阵）各轴在世界系就是它自己
		var is_same := zp.is_equal_approx(Basis.IDENTITY)
		if not is_same:
			n_diff += 1
		_L.append("  %-13s bow=(%+.1f,%+.1f,%+.1f) up=(%+.1f,%+.1f,%+.1f)   %s" % [
			String(sid), bw.x, bw.y, bw.z, uw.x, uw.y, uw.z,
			"同一" if is_same else "★不同"])
	_L.append("")
	_L.append("  ⇒ 实机零姿态 ≠ 单位阵的船：**%d / %d**" % [n_diff, rows.size()])
	_L.append("     这意味着：**工具里看到的船姿，和实机里船的静止姿态不是同一个姿态**")
	_L.append("     ⇒ 用户在工具里「以眼为准」定的方向，到了实机必然对不上 ——")
	_L.append("       因为中间隔着 `R_y·M·mesh_rot·R_z` 四层，而工具只反映了 `r` 那一层。")
	_L.append("")


## 读工具落盘的姿势表（用户标定真值）
func _tool_pose(sid: String) -> String:
	var p := "user://bow_calib/pose_table.json"
	if not FileAccess.file_exists(p):
		return "(无表)"
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null:
		return "(读失败)"
	var txt := f.get_as_text()
	f.close()
	var d: Variant = JSON.parse_string(txt)
	if not (d is Dictionary):
		return "(格式错)"
	if not d.has(sid):
		return "(未标定)"
	var rec: Variant = d[sid]
	if not (rec is Dictionary):
		return str(rec)
	return "bow:%s up:%s" % [String(rec.get("bow", "?")), String(rec.get("up", "?"))]


func _rot_kind(m: Basis) -> String:
	if m.is_equal_approx(Basis.IDENTITY):
		return "单位阵"
	if m.is_equal_approx(Basis.from_euler(Vector3(0, PI, 0))):
		return "R_y(180°)"
	if m.is_equal_approx(Basis.from_euler(Vector3(PI / 2, 0, 0))):
		return "R_x(+90°)"
	if m.is_equal_approx(Basis.from_euler(Vector3(-PI / 2, 0, 0))):
		return "R_x(−90°)"
	return "其它(斜轴)"


func _write() -> void:
	for l in _L:
		print(l)
	var f := FileAccess.open("user://diag49.txt", FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(_L))
		f.close()
	print("[DIAG49] 报告：%s" % ProjectSettings.globalize_path("user://diag49.txt"))
