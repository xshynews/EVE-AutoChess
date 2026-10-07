extends Node
## 48 轮 · **验证修法**：`_capture_bow_axes` 的 geo 只该含 `R_y(extra)·mesh_rot`（**不含 M**）。
##
## 理由：C 的契约是「把**零姿态**（还没被 M 摆过）的三轴送到 −Z/+Y/+X」，
## 而运行时是 `target = looking_at(f)·C`，之后 model 节点自己再乘 `zero_pose_basis`
## （内含 M）⇒ M 只该在 model 那一层出现一次。
## 旧写法传 `zero_pose_basis`（已含 M）⇒ **M 被应用两次** ⇒ bow 净效果翻 180°
## ⇒ 实机症状「每艘船的舰艏指向很乱」+「全部肚皮朝天」（同一个病根的两个面）。
##
## 本探针**不改任何生产代码**，只在离线复算两种口径的完整链条。
const YAW := preload("res://scripts/data/eve_ship_yaw.gd")
const IDS := ["abaddon", "catalyst", "kestrel", "slasher", "inquisitor",
		"myrmidon", "tristan", "algos", "omen", "burst", "dominix", "raven"]


func _ready() -> void:
	print("═══ 48 轮 · 修法验证（geo 去掉 M 之后，两条链是否同时达标）═══")
	print("")
	print("  %-12s | [旧] 链·bow  链·up·天 | [新] 链·bow  链·up·天 | 判" % "ship")
	var ok_n := 0
	for id in IDS:
		var sid := StringName(id)
		var mr: Basis = EveShipVisual.mesh_rot_of(sid)
		var m: Basis = YAW.axis_remap(sid)
		var bow: Vector3 = YAW.bow_axis(sid)
		var up: Vector3 = YAW.up_axis(sid)
		var extra: float = YAW.extra_yaw(sid)
		var ry := Basis.from_euler(Vector3(0, extra, 0))
		var zp: Basis = EveShipVisual.zero_pose_basis(sid)
		var f := Vector3(0, 0, -1)
		var look := Basis.looking_at(f, Vector3.UP)
		# ── 旧口径：geo = zp（含 M）──
		var c_old: Basis = _make_align(zp * bow, zp * up)
		var t_old: Basis = look * c_old
		var bow_old: Vector3 = (t_old * bow).normalized()
		var up_old: Vector3 = (t_old * up).normalized()
		# ── 新口径：geo = R_y(extra)·mesh_rot（不含 M）──
		var geo_new: Basis = ry * mr
		var c_new: Basis = _make_align(geo_new * bow, geo_new * up)
		var t_new: Basis = look * c_new
		var bow_new: Vector3 = (t_new * bow).normalized()
		var up_new: Vector3 = (t_new * up).normalized()
		# ── 最终：节点 quaternion(=t) 之后再叠 model.basis(=zp) ──
		var final_bow_old: Vector3 = (t_old * zp * bow).normalized()
		var final_up_old: Vector3 = (t_old * zp * up).normalized()
		var final_bow_new: Vector3 = (t_new * zp * bow).normalized()
		var final_up_new: Vector3 = (t_new * zp * up).normalized()
		var pass_new: bool = final_bow_new.dot(f) > 0.999 and final_up_new.dot(Vector3.UP) > 0.999
		if pass_new:
			ok_n += 1
		print("  %-12s | %s %+.3f | %s %+.3f | %s"
				% [id,
				   _v(final_bow_old), final_up_old.dot(Vector3.UP),
				   _v(final_bow_new), final_up_new.dot(Vector3.UP),
				   ("✔" if pass_new else "✗")])
	print("")
	print("  ── [新] 口径端到端达标 %d / %d ──" % [ok_n, IDS.size()])


func _make_align(bow0: Vector3, up0: Vector3) -> Basis:
	var b := bow0.normalized()
	var u := up0 - b * b.dot(up0)
	if u.length_squared() < 1e-8:
		u = Vector3.UP - b * b.dot(Vector3.UP)
		if u.length_squared() < 1e-8:
			u = Vector3(0.0, 0.0, 1.0) - b * b.dot(Vector3(0.0, 0.0, 1.0))
	u = u.normalized()
	var l := b.cross(u).normalized()
	var p := Basis(b, u, l)
	var q := Basis(Vector3(0.0, 0.0, -1.0), Vector3(0.0, 1.0, 0.0), Vector3(1.0, 0.0, 0.0))
	return q * p.transposed()


func _v(v: Vector3) -> String:
	return "(%+.2f,%+.2f,%+.2f)" % [v.x, v.y, v.z]
