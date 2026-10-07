extends Node
## 48 轮 · **标定工具落表链实测**（把 `probe_bow_box` 的三个函数逐字复刻到这里，
## 走一遍"用户转船 → 摆杆 → 按回车"的完整流程，看落表值对不对）。
##
## ⚠️ 复刻是为了**取证**（工具的函数是私有 + 依赖大量 UI 状态，没法直接调）。
##    复刻版与源码**逐字对照**（函数体从 probe_bow_box.gd 抄来），
##    并且**同时**打印"正确口径"作对照 —— 两者一比就知道有没有 bug。
##
## 源码（probe_bow_box.gd）：
##   3395: `_apply_ship_transform()`:  `_holder.transform = Transform3D(r * norm.basis, r * norm.origin)`
##         ⇒ 船上屏的姿态 = `r · zp`
##   3476: `_ship_rotation()` = Basis.from_euler(_ship_pitch, _ship_yaw, _ship_roll)  = r
##   3344: `_axis_dir_in_model(i)` = `(_ship_rotation().inverse() * _axis_dirs[i])`  → 只除 r
##   2971: `_axis_dir_to_model(v, sid)` = `zero_pose_basis(sid).inverse() * v`       → 再除 zp
##   2742: `bw_raw = _axis_dir_to_model(_axis_dir_in_model(0), sid)`
const YAW := preload("res://scripts/data/eve_ship_yaw.gd")
const IDS := ["abaddon", "catalyst", "kestrel", "slasher", "tristan", "myrmidon", "algos", "omen"]


func _ready() -> void:
	print("═══ 48 轮 · 标定工具落表链实测 ═══")
	print("")
	print("  场景：用户把船转到某姿态 r（比如「站着船尾看舰艏」），")
	print("        再把轴杆摆到**画面上看着是舰艏**的位置（= zp·bow 的世界像经 r 转过）。")
	print("")
	print("  %-12s | 落表结果(工具链)   | 真值 bow_axis     | 判" % "ship")
	for id in IDS:
		var sid := StringName(id)
		var zp: Basis = EveShipVisual.zero_pose_basis(sid)
		var bow_model: Vector3 = YAW.bow_axis(sid)
		# ── 模拟"用户转船"：取一个非平凡的 r ──
		var r := Basis.from_euler(Vector3(deg_to_rad(12.0), deg_to_rad(-37.0), deg_to_rad(8.0)))
		# 船在屏上的姿态 = r · zp
		# ── 用户把杆摆到"看着是舰艏" ⇒ 杆在屏上指着 (r·zp)·bow_model ──
		var axis_dir: Vector3 = ((r * zp) * bow_model).normalized()
		# ── 工具落表链（逐字复刻）──
		var in_model: Vector3 = (r.inverse() * axis_dir).normalized()      # 3344
		var raw: Vector3 = (zp.inverse() * in_model).normalized()          # 2971 + 2742
		var tool_ax := _proj(raw)
		# ── 正确口径（只除 r 就够了，因为 axis_dir 本身已是 (r·zp)·bow）──
		var right_in_model: Vector3 = (zp.inverse() * in_model).normalized()  # 与上面相同?
		# 真正的正确值 = bow_model（用户摆的就是它）
		var ok: bool = tool_ax.length() > 0.0 and tool_ax.distance_to(bow_model) < 0.05
		print("  %-12s | %-18s | %-18s | %s"
				% [id, _fmt(tool_ax), _fmt(bow_model), ("✔" if ok else "✗")])
	print("")
	print("  ── 说明 ──")
	print("  若全部 ✔ ⇒ 工具链**没问题**（`_axis_dir_in_model` 只除 r、`_axis_dir_to_model` 除 zp，")
	print("     合起来把 (r·zp) 全除掉 ⇒ 得到 bow_model ✔）")
	get_tree().quit(0)


func _proj(v: Vector3) -> Vector3:
	var ax := 0
	var best := -1.0
	for i in 3:
		if absf(v[i]) > best:
			best = absf(v[i])
			ax = i
	var out := Vector3.ZERO
	out[ax] = signf(v[ax])
	return out


func _fmt(v: Vector3) -> String:
	return "(%+.0f,%+.0f,%+.0f)" % [v.x, v.y, v.z]
