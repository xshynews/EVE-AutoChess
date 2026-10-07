extends Node
## 48 轮 · **验证标定工具的双重反解 bug**（不改任何生产代码，纯离线复算）。
##
## ═══ 契约（从源码逐字读出）═══
##  工具里船的显示姿态：`_holder.transform.basis = r · zero_pose_basis(sid)`
##      （`_apply_ship_transform`：`Transform3D(r * norm.basis, ...)`）
##      其中 `r = _ship_rotation()` = 用户转船的增量，`norm.basis` = 正常姿态。
##  轴杆的世界方向：`_axis_dirs[i]`（用户摆到"看着是舰艏"的位置）
##
##  落表（`_on_confirm_pressed`）：
##      `_axis_dir_in_model(0) = (r·zp)⁻¹ · _axis_dirs[0]`      ← 已回到模型空间 ✔
##      `bw_raw = _axis_dir_to_model(那个, sid) = zp⁻¹ · 上面`  ← **再除一次 zp** ✗
##
## ═══ 本探针要证的事 ═══
##  设用户把轴杆摆到**真·模型空间舰艏轴**的世界像上（即"看着对"）：
##      `_axis_dirs[0] := (r·zp) · bow_true`
##  则落表结果应为 `bow_true`。实际会得到 `zp⁻¹ · bow_true`。
##  逐艘打印两者，看差多少。
const YAW := preload("res://scripts/data/eve_ship_yaw.gd")
const IDS := ["abaddon", "catalyst", "kestrel", "slasher", "tristan",
		"myrmidon", "algos", "omen", "burst", "dominix"]


func _ready() -> void:
	print("═══ 48 轮 · 标定工具反解链验证 ═══")
	print("")
	print("  %-12s | zp⁻¹·bow 在模型空间的轴（=落表实际存的） | 真值 | 一致?" % "ship")
	var bad := 0
	for id in IDS:
		var sid := StringName(id)
		var zp: Basis = EveShipVisual.zero_pose_basis(sid)
		var bow_true: Vector3 = YAW.bow_axis(sid)          # 当前表里的值
		var stored: Vector3 = (zp.inverse() * bow_true).normalized()
		var same: bool = stored.distance_to(bow_true) < 0.05
		if not same:
			bad += 1
		print("  %-12s | %s | %s | %s"
				% [id, _v(stored), _v(bow_true), ("✔" if same else "✗ 差 %.2f" % stored.distance_to(bow_true))])
	print("")
	print("  ── 若用户【看着对】地摆杆，工具的落表结果与真值不符：%d / %d ──" % [bad, IDS.size()])
	print("")
	print("  ── 附：zp 的构成（应 = R_y(extra)·M·mesh_rot）──")
	for id in IDS.slice(0, 3):
		var sid := StringName(id)
		var m: Basis = YAW.axis_remap(sid)
		var mr: Basis = EveShipVisual.mesh_rot_of(sid)
		var extra: float = YAW.extra_yaw(sid)
		var ry := Basis.from_euler(Vector3(0, extra, 0))
		var rebuilt: Basis = ry * m * mr
		print("  %-12s zp == R_y·M·mesh_rot ? %s   (extra=%.1f°)" 
				% [id, ("✔" if rebuilt.is_equal_approx(EveShipVisual.zero_pose_basis(sid)) else "✗"), rad_to_deg(extra)])
	get_tree().quit(0)


func _v(v: Vector3) -> String:
	return "(%+.2f,%+.2f,%+.2f)" % [v.x, v.y, v.z]
