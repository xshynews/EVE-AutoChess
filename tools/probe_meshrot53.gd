extends Node

## ★ 53 轮 · `mesh_rot` **双读源**差异普查
##
## ══════════════════════════════════════════════════════════════════
##  为什么必须查这一条
## ══════════════════════════════════════════════════════════════════
##  `zero_pose_basis()` 与 `_capture_bow_axes()` 都用 `mesh_rot_of()`，
##  而 `_build_hull_model()` 里真正写进 `model.basis` 的是
##  `_bake_mesh_rotation()` 的返回值。两者是**两条独立的读法**：
##
##    ① `mesh_rot_of(id)`      —— 实例化 glb，取 `_first_mesh()`（**第一个**
##                                MeshInstance3D，递归找），只读它一个节点的旋转
##    ② `_bake_mesh_rotation()` —— 遍历 `model.get_children()`（**一层**），
##                                把所有**非单位旋转**的子节点 basis **累乘**起来
##
##  glb 结构是「根 Node3D → 子 MeshInstance3D」时两者相等（只有一层、只有一个
##  非单位旋转的子节点）。**但只要 glb 是多层 / 多个带旋转的子节点，二者就分叉。**
##
##  ⚠️ 而且在 release 构建里，`_build_hull_model` 那条 `assert(... or
##     mesh_rot.is_equal_approx(Basis.IDENTITY))` 会被**整个剥离** ⇒
##     不一致**静默通过**，表现为「逐艘各异的乱」（正是 47 轮描述的病象）。
##
## ══════════════════════════════════════════════════════════════════
##  这个探针报什么
## ══════════════════════════════════════════════════════════════════
##  对 52 艘逐艘报：两个 mesh_rot 是否一致、差多少度、差在哪个轴。
##  再做**端到端判别**——分别用两个 mesh_rot 走 `zero_pose_basis`
##  的口径算 `M·mesh_rot·bow`，看是否都指向 −Z（朝敌）。
##
##  用法：
##      Godot_v4.7.1-stable_win64_console.exe --headless \
##          --path "<工程>" --quit-after 900 \
##          res://tools/probe_meshrot53.tscn

const OUT_DIR := "user://meshrot53"

## 用到的两个静态表函数
var _yaw: Variant = null

var _rows: Array = []
var _bad := 0


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	_yaw = load("res://scripts/data/eve_ship_yaw.gd")

	print("══════════════════════════════════════════════════════════════")
	print("  53 轮 · mesh_rot 双读源差异普查")
	print("══════════════════════════════════════════════════════════════")

	var ids: Array = _yaw.all_ship_ids()
	print("全库 %d 艘" % ids.size())
	print("")
	print("%-14s %-10s %-9s %-22s %-22s" % [
			"ship_id", "一致?", "差角°", "mesh_rot_of", "_bake_mesh_rotation"])
	print("──────────────────────────────────────────────────────────────")

	for sid in ids:
		_survey(sid)

	print("──────────────────────────────────────────────────────────────")
	print("不一致 %d / %d 艘" % [_bad, ids.size()])
	print("")

	_end_to_end()
	_write_report()
	get_tree().quit()


## 单艘普查：两种读法 + 差角
func _survey(sid: StringName) -> void:
	var a: Basis = EveShipVisual.mesh_rot_of(sid)
	var b: Basis = _bake_mesh_rotation_dry(sid)

	var same := a.is_equal_approx(b)
	if not same:
		_bad += 1

	# 角度差：用四元数夹角（Basis → Quaternion 是纯旋转，两侧都已正交归一化）
	var dq := Quaternion(a).angle_to(Quaternion(b))
	var ddeg := rad_to_deg(dq)

	print("%-14s %-10s %-9.2f %-22s %-22s" % [
			String(sid),
			"✓" if same else "✗ 分叉",
			ddeg,
			_axis_label(a),
			_axis_label(b)])

	_rows.append({
		"id": String(sid),
		"same": same,
		"deg": ddeg,
		"a": a,
		"b": b,
	})


## 复刻 `_bake_mesh_rotation()` 的**读法**（不修改场景树，只算）。
##
## ⚠️ 红线 40：这里必须与生产实现**逐字同源**。生产是实例化后遍历
##    `model.get_children()`（一层），累乘所有非单位旋转的子节点 basis。
##    本函数照做，只是**不写回**子节点（探针不改场景）。
func _bake_mesh_rotation_dry(sid: StringName) -> Basis:
	var inst := EveShipModel.instantiate(sid, false)
	if inst == null:
		return Basis.IDENTITY
	var acc := Basis.IDENTITY
	var lifted := 0
	for c in inst.get_children():
		var n3 := c as Node3D
		if n3 == null:
			continue
		var bb := n3.transform.basis.orthonormalized()
		if bb.is_equal_approx(Basis.IDENTITY):
			continue
		acc = acc * bb
		lifted += 1
	inst.free()
	if lifted == 0:
		return Basis.IDENTITY
	return acc.orthonormalized()


## 端到端：两个 mesh_rot 分别代入 `zero_pose_basis` 口径，看舰艏是否都朝敌。
##
## 口径（红线 42 / 47）：零姿态 = `R_y(yaw) · M · mesh_rot`，
##   敌人恒在世界 **−Z** ⇒ 要求 `(R_y(yaw)·M·mesh_rot)·bow` 的水平分量 ≈ −Z。
##
## ⚠️ 这里**不自己复刻 `zero_pose_basis`**：直接调生产静态函数拿 A 口径，
##    再用同一个 `M` / `yaw` 手工换掉 mesh_rot 那一层算 B 口径。
##    （`zero_pose_basis` 内部就是 `R_y·M·mesh_rot` 再叠全局滚转；
##      全局滚转是 `R_z(180°)` 左乘，**不影响**下面的判别口径一致性，
##      因为两个口径都会经过同一层滚转 ⇒ 相对差异只来自 mesh_rot。）
func _end_to_end() -> void:
	print("══════════════════════════════════════════════════════════════")
	print("  端到端判别：舰艏是否朝敌（−Z）")
	print("══════════════════════════════════════════════════════════════")
	print("%-14s %-24s %-24s" % ["ship_id", "A: mesh_rot_of", "B: bake(累乘)"])
	print("──────────────────────────────────────────────────────────────")

	var ids: Array = _yaw.all_ship_ids()
	var a_ok := 0
	var b_ok := 0
	var a_bad_list: Array = []
	var b_bad_list: Array = []

	for sid in ids:
		var m: Basis = EveShipYawTable.axis_remap(sid)
		var yaw: float = EveShipYawTable.extra_yaw(sid)
		var bow: Vector3 = EveShipYawTable.bow_axis(sid)

		var ra: Basis = EveShipVisual.mesh_rot_of(sid)
		var rb: Basis = _bake_mesh_rotation_dry(sid)

		var dir_a := _zero_dir(yaw, m, ra, bow)
		var dir_b := _zero_dir(yaw, m, rb, bow)

		var ok_a := _is_forward(dir_a)
		var ok_b := _is_forward(dir_b)
		if ok_a:
			a_ok += 1
		else:
			a_bad_list.append(String(sid))
		if ok_b:
			b_ok += 1
		else:
			b_bad_list.append(String(sid))

		print("%-14s %-24s %-24s" % [
				String(sid),
				("%s  %s" % ["✓" if ok_a else "✗", _fmt(dir_a)]),
				("%s  %s" % ["✓" if ok_b else "✗", _fmt(dir_b)])])

	print("──────────────────────────────────────────────────────────────")
	print("A 口径（mesh_rot_of）  朝敌 %d / %d" % [a_ok, ids.size()])
	print("B 口径（bake 累乘）    朝敌 %d / %d" % [b_ok, ids.size()])
	if not a_bad_list.is_empty():
		print("  A 不朝敌：%s" % ", ".join(a_bad_list))
	if not b_bad_list.is_empty():
		print("  B 不朝敌：%s" % ", ".join(b_bad_list))


## `(R_y(yaw)·M·mesh_rot)·bow` —— 与 `zero_pose_basis_no_roll` 同口径。
##
## ⚠️ 不调 `zero_pose_basis()` 的原因：那个函数固定读 `mesh_rot_of()`，
##    测不了 B 口径。这里显式写同一式子，**逐字对齐**
##    `zero_pose_basis_no_roll()` 的实现（第 539~542 行）：
##        `Basis.from_euler(Vector3(0, yaw, 0)) * m * mesh_rot`
func _zero_dir(yaw: float, m: Basis, mesh_rot: Basis, bow: Vector3) -> Vector3:
	var zp := Basis.from_euler(Vector3(0.0, yaw, 0.0)) * m * mesh_rot
	return (zp * bow).normalized()


## 水平分量是否指向 −Z（朝敌，红线 42）。
##
## 判据取 20° 容差：标定本身有残差，且部分船（burst/myrmidon）官方停泊姿态
## 是竖着/横着的 ⇒ 舰艏轴未必在水平面。这里**只看水平分量的符号方向**，
## 若水平分量退化（|xy| 极小）则跳过（报 −1 表示"无法判"）。
func _is_forward(d: Vector3) -> bool:
	var h := Vector3(d.x, 0.0, d.z)
	if h.length() < 0.05:
		return false   # 水平分量退化 ⇒ 舰艏近乎垂直，本判据不适用
	h = h.normalized()
	return h.dot(Vector3(0.0, 0.0, -1.0)) > 0.94   # 20°


func _axis_label(b: Basis) -> String:
	if b.is_equal_approx(Basis.IDENTITY):
		return "I"
	# 用欧拉角粗描述（只为人类读，不参与任何判定）
	var e := b.get_euler()
	return "(%.0f,%.0f,%.0f)" % [rad_to_deg(e.x), rad_to_deg(e.y), rad_to_deg(e.z)]


func _fmt(v: Vector3) -> String:
	return "(%.2f,%.2f,%.2f)" % [v.x, v.y, v.z]


func _write_report() -> void:
	var lines := PackedStringArray()
	lines.append("53 轮 · mesh_rot 双读源普查")
	lines.append("不一致 %d / %d" % [_bad, _rows.size()])
	for r in _rows:
		lines.append("%s  一致=%s  差=%.2f°" % [r["id"], r["same"], r["deg"]])
	var f := FileAccess.open(OUT_DIR + "/report.txt", FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(lines))
		f.close()
