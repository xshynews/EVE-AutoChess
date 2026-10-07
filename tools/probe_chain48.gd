extends Node
## 48 轮 · **运行时姿态链仲裁**：把 setup 那一层的每个中间量都打出来。
##
## 目标：定位「肚皮朝天」到底是哪一步引入的 180°。
## 判据（全部用引擎算的量，逐层验证）：
##   ① `mesh_rot_of(id)` —— glb 内层旋转
##   ② `zero_pose_basis(id)` = R_y(extra)·M·mesh_rot  —— 生产函数
##   ③ `zero_pose_basis · up_model` —— 应 = +Y
##   ④ `_make_align` 的 C —— 从 setup 实际拿的值复算
##   ⑤ `C · up_model` —— 运行时真正用的对齐
##   ⑥ `looking_at(-Z, UP) · C · up_model` —— 完整链条（f = 朝敌 = −Z）
const YAW := preload("res://scripts/data/eve_ship_yaw.gd")
const IDS := ["abaddon", "catalyst", "kestrel", "slasher", "myrmidon", "tristan"]


func _ready() -> void:
	print("═══ 48 轮 · 运行时姿态链逐层解剖 ═══")
	print("")
	for id in IDS:
		var sid := StringName(id)
		var mr: Basis = EveShipVisual.mesh_rot_of(sid)
		var zp: Basis = EveShipVisual.zero_pose_basis(sid)
		var bow: Vector3 = YAW.bow_axis(sid)
		var up: Vector3 = YAW.up_axis(sid)
		print("── %s ──" % id)
		print("   M (AXIS_REMAP)  = %s  det %+.2f" % [_b(YAW.axis_remap(sid)), YAW.axis_remap(sid).determinant()])
		print("   mesh_rot        = %s  det %+.2f" % [_b(mr), mr.determinant()])
		print("   zero_pose       = %s  det %+.2f" % [_b(zp), zp.determinant()])
		print("   M-meshrot       = %s  det %+.2f"
				% [_b(YAW.axis_remap(sid) * mr), (YAW.axis_remap(sid) * mr).determinant()])
		print("   bow_model %s -> zp·bow %s" % [_v(bow), _v((zp * bow).normalized())])
		print("   up_model  %s -> zp·up  %s  (dot 天 %+.3f)"
				% [_v(up), _v((zp * up).normalized()), (zp * up).normalized().dot(Vector3.UP)])
		# ── C 的两种算法（setup 传 zp 进去）──
		var c_setup: Basis = _make_align(zp * bow, zp * up)
		print("   C(setup 口径, geo=zp)  = %s" % _b(c_setup))
		print("        C·bow_model = %s   C·up_model = %s"
				% [_v((c_setup * bow).normalized()), _v((c_setup * up).normalized())])
		# ── 完整链条：f = 朝敌 = −Z ──
		var f := Vector3(0, 0, -1)
		var t := Basis.looking_at(f, Vector3.UP) * c_setup
		print("   [链] looking_at(−Z)·C·bow = %s    (应 = −Z 朝敌)"
				% _v((t * bow).normalized()))
		print("   [链] looking_at(−Z)·C·up  = %s    (应 = +Y 背朝天)  dot 天 %+.3f"
				% [_v((t * up).normalized()), (t * up).normalized().dot(Vector3.UP)])
		print("")


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


func _b(m: Basis) -> String:
	return "[%s | %s | %s]" % [_v(m.x), _v(m.y), _v(m.z)]


func _v(v: Vector3) -> String:
	return "(%+.2f,%+.2f,%+.2f)" % [v.x, v.y, v.z]
