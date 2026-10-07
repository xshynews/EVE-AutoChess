extends Node

## 实测「glb 导入 Godot 后，根节点自带变换是否还在」——
## 这是「离线渲染图」与「实机画面」是否同一艘船的分水岭。
##
## ══════════════════════════════════════════════════════════════════
##  为什么要问这个
## ══════════════════════════════════════════════════════════════════
##  离线渲染器 `gather()` 的顶点提取里有一行：
##
##      world = parent @ local_mat(n)      # 把节点自带变换乘进顶点
##
##  而 `eve_ship_visual.gd` 是**整体覆盖**：
##
##      model.basis = Basis.from_euler(Vector3(0, yaw, 0)) * M
##
##  ⇒ 若 Godot 导入后根节点仍带旋转，则
##      实机 = R_y(yaw)·M·v
##      离线 = R_y(yaw)·M·R_root·v
##    两者差一个 R_root ⇒ **所有在离线图上标定出来的表，用到实机都是错的。**
##
##  若 Godot 导入时已把 R_root 烘进 mesh（根节点 rotation = 0），则两者一致。
##
## ⚠️ 判据是**根节点 rotation 是否为 0** + **meshAABB 是否等于 python 侧
##    只取原始 POSITION 的 AABB**（后者才是「顶点没被额外转过」的铁证）。
##
## 用法：
##   Godot_v4.7.1-stable_win64_console.exe --headless --path <工程> \
##       --quit-after 3000 res://tools/probe_model_xform.tscn

const IDS: Array[StringName] = [
	&"catalyst", &"myrmidon", &"raven", &"abaddon", &"dominix",
	&"rifter", &"kestrel", &"tristan", &"executioner", &"incursus",
	&"harbinger", &"omen", &"thorax", &"vexor", &"scythe",
]


func _ready() -> void:
	print("[XF] ===== ① glb 导入后根节点自带变换（游戏覆盖**前**）=====")
	for sid in IDS:
		var m := EveShipModel.instantiate(sid, false)
		if m == null:
			print("[XF] %-12s NO MODEL" % sid)
			continue
		var a := _aabb_rel(m)
		print("[XF] %-12s pos=(%8.2f,%8.2f,%8.2f) rotDeg=(%7.2f,%7.2f,%7.2f) sc=(%.3f,%.3f,%.3f)"
			% [sid, m.position.x, m.position.y, m.position.z,
				m.rotation_degrees.x, m.rotation_degrees.y, m.rotation_degrees.z,
				m.scale.x, m.scale.y, m.scale.z])
		print("[XF] %-12s meshAABB min=(%8.2f,%8.2f,%8.2f) size=(%8.2f,%8.2f,%8.2f)"
			% [(" " + sid), a.position.x, a.position.y, a.position.z,
				a.size.x, a.size.y, a.size.z])
		m.free()

	print("[XF] ===== ② 覆盖 basis（= 游戏算式 R_y(yaw)·M）之后 =====")
	for sid in IDS:
		var m := EveShipModel.instantiate(sid, false)
		if m == null:
			continue
		var yaw: float = -PI / 2.0 + EveShipYawTable.extra_yaw(sid)
		var mb := EveShipYawTable.axis_remap(sid)
		m.basis = Basis.from_euler(Vector3(0, yaw, 0)) * mb
		m.scale = Vector3.ONE
		var a := _aabb_rel(m)
		print("[XF] %-12s yaw=%+8.2f  pos=(%8.2f,%8.2f,%8.2f) | AABB min=(%8.2f,%8.2f,%8.2f) size=(%8.2f,%8.2f,%8.2f)"
			% [sid, rad_to_deg(yaw), m.position.x, m.position.y, m.position.z,
				a.position.x, a.position.y, a.position.z,
				a.size.x, a.size.y, a.size.z])
		m.free()

	print("[XF] ==== DONE ====")
	get_tree().quit()


## root 子树里所有 MeshInstance3D 的 AABB（以 root **自身**为原点，含 root 变换）。
func _aabb_rel(root: Node) -> AABB:
	var out := AABB()
	var has := false
	var stack: Array = [[root, Transform3D.IDENTITY]]
	while not stack.is_empty():
		var pr: Array = stack.pop_back()
		var n: Node = pr[0]
		var t: Transform3D = pr[1]
		var lt: Transform3D = t
		if n is Node3D:
			lt = t * (n as Node3D).transform
		if n is MeshInstance3D:
			var bb: AABB = (n as MeshInstance3D).mesh.get_aabb()
			for i in 8:
				var wp: Vector3 = lt * bb.get_endpoint(i)
				if has:
					out = out.expand(wp)
				else:
					out = AABB(wp, Vector3.ZERO)
					has = true
		for c in n.get_children():
			stack.append([c, lt])
	return out
