extends Node3D

## 舰船朝向「轴标同框」取证探针 —— 把船与 ±Z 球放进同一张图
##
## ══════════════════════════════════════════════════════════════════
##  它要终结的争论
## ══════════════════════════════════════════════════════════════════
##  朝向标定出过两次「看起来完全正常、结论整体反掉」的事故：
##    ① 判定图把「前方」箭头画在右边，而那个机位下世界 +Z 在屏幕【左侧】
##    ② 于是所有「靠箭头判」的名单都有 180° 的整组风险
##
##  本探针把「船的姿态」和「世界 +Z 在哪」**放进同一张图**，
##  不再需要任何中间推理 —— 看一眼就知道船头朝红球还是蓝球。
##
## ── 设计（关键：球不受 holder 的旋转影响）────────────────────────
##  船的归一化把「船中心 → 世界原点、长轴(在 +Z)长度 → 1.0」，
##  所以船两端恒在 z = ±0.5。于是：
##      **红球放在世界 (0, 0.48, +0.62)、蓝球放在 (0, 0.48, −0.62)**
##  球直接挂在 SubViewport 下，**不进 holder** ⇒ 不会被船的 yaw 转走。
##  一根细杆把两球连起来，明确「这是一根世界 Z 轴」。
##
## ── 跑法（非 headless）──────────────────────────────────────────
##   "C:/godot/Godot_v4.7.1-stable_win64_console.exe" \
##     --path "F:/evezzq/eve自走棋918" --quit-after 4000 \
##     res://tools/probe_ship_axis.tscn -- --ids=algos,abaddon
##
##   可选：--ids=a,b,c（默认 6 艘代表）· --size=300 · --extra（同时出 +180° 版）

const INDEX := preload("res://scripts/data/eve_ship_asset_index.gd")

const SIZE := 300
const OUT_DIR := "user://axis_check"
const CAM_DIR := Vector3(1.0, 0.78, 0.22)
const CAM_SIZE := 1.55
const MODEL_YAW_FIX := -PI / 2.0
const PCA_STEP := 11

## 默认取证样本：**空 = 全部 52 艘**（逐格带球标，自己的基准自己带）
const DEFAULT_IDS := ""

var _ids: PackedStringArray = PackedStringArray()
var _size := SIZE
var _extra := false

var _vp: SubViewport = null
var _cam: Camera3D = null
var _holder: Node3D = null
var _axis_root: Node3D = null


func _ready() -> void:
	var ids_arg := DEFAULT_IDS
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--ids="):
			ids_arg = a.substr(6)
		elif a.begins_with("--size="):
			_size = maxi(96, int(a.substr(7)))
		elif a == "--extra":
			_extra = true
	if ids_arg.is_empty() or ids_arg == "all":
		_ids = PackedStringArray()
		for r in INDEX.ROWS:
			_ids.append(String(r[0]))
		_ids.sort()
	else:
		_ids = ids_arg.split(",")
	_build()
	await _run()


func _build() -> void:
	_vp = SubViewport.new()
	_vp.size = Vector2i(_size, _size)
	_vp.transparent_bg = true
	_vp.own_world_3d = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp)

	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0, 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.58, 0.63, 0.70)
	env.ambient_light_energy = 1.35
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	we.environment = env
	_vp.add_child(we)

	var key := DirectionalLight3D.new()
	key.light_energy = 1.8
	key.rotation_degrees = Vector3(-36, -126, 0)
	_vp.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.light_energy = 0.7
	rim.rotation_degrees = Vector3(-14, 58, 0)
	_vp.add_child(rim)

	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.size = CAM_SIZE
	_cam.near = 0.01
	_cam.far = 40.0
	_vp.add_child(_cam)
	_cam.position = CAM_DIR.normalized() * 8.0
	_cam.look_at(Vector3.ZERO, Vector3.UP)

	_holder = Node3D.new()
	_vp.add_child(_holder)

	_axis_root = Node3D.new()
	_vp.add_child(_axis_root)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var n_ok := 0
	for id in _ids:
		var sid := StringName(id)
		if await _shot(sid, false, "asis"):
			n_ok += 1
		if _extra:
			if await _shot(sid, true, "plus180"):
				n_ok += 1
	print("[AXISV] 出图 %d 张 -> %s" % [n_ok, ProjectSettings.globalize_path(OUT_DIR)])
	print("[AXISV] 红球 = 世界 +Z（游戏里的【前方】）；蓝球 = 世界 −Z（后方）")
	print("[AXISV] ==== DONE ====")
	get_tree().quit(0)


func _shot(id: StringName, extra_flip: bool, tag: String) -> bool:
	for c in _holder.get_children():
		_holder.remove_child(c)
		c.queue_free()
	_holder.transform = Transform3D()

	var model := EveShipModel.instantiate(id, false)
	if model == null:
		push_warning("[AXISV] %s 无 3D 模型" % String(id))
		return false
	_holder.add_child(model)

	var theta := _xz_principal_angle(model)
	var yaw := MODEL_YAW_FIX + EveShipYawTable.extra_yaw(id) + (PI if extra_flip else 0.0)
	# ⚠️ 2026-09-26 修：**必须一并乘上 `AXIS_REMAP` 的 M**，否则对 7 艘重映射船
	#    （myrmidon / catalyst / kestrel / tristan / condor / raven / slasher）
	#    渲出来的是「完全没修过」的姿态 —— 船在图上躺着/侧着，而表其实已经生效。
	#    这是**取证假阴性**：不报错、图也"看着正常"，但结论与工程真实朝向无关。
	#    口径与 `eve_ship_visual._build_hull_model()` 逐字一致：
	#        最终朝向 = R_y(MODEL_YAW_FIX + extra_yaw) ∘ M
	#    ⚠️ 乘了 M 之后，某些船的**长轴不再沿世界 Z**（myrmidon 就是竖着的），
	#       而下面的 ±Z 球标是按「船两端恒在 z=±0.5」摆的 ⇒ 球会跑到船体侧面。
	#       球标的语义没变（**它标的是世界 +Z**），但那句「球串在船首尾轴上」的
	#       假设对重映射船**不成立**，看图时别把球的位置当成船的端点。
	var rot := Basis.from_euler(Vector3(0.0, yaw, 0.0)) * EveShipYawTable.axis_remap(id)
	var aabb := _aabb_of(model, Transform3D(rot, Vector3.ZERO))
	if aabb.size.length() < 0.0001:
		return false
	var long_len := maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z))
	long_len = maxf(long_len, 0.0001)
	var basis := rot.scaled(Vector3.ONE * (1.0 / long_len))
	var origin := -(basis * aabb.get_center())
	_holder.transform = Transform3D(basis, origin)

	_rebuild_axis()

	await RenderingServer.frame_post_draw
	var tex := _vp.get_texture()
	if tex == null:
		return false
	var img := tex.get_image()
	if img == null:
		return false
	img.save_png("%s/%s_%s.png" % [OUT_DIR, String(id), tag])
	print("[AXISV] %-12s %-7s theta=%+6.1f°  yaw=%+7.1f°" % [
		String(id), tag, rad_to_deg(theta), rad_to_deg(yaw)])
	return true


## 重建 ±Z 轴标：红球在 +Z、蓝球在 −Z，中间一根细杆
##
## ⚠️ 挂在 _vp 下（不是 _holder 下）—— holder 的 basis 含船的 yaw，
##    挂进去会把「世界 Z 轴」跟着船转掉，标定立刻失去意义。
func _rebuild_axis() -> void:
	for c in _axis_root.get_children():
		_axis_root.remove_child(c)
		c.queue_free()
	var y := 0.50
	_axis_root.add_child(_ball(Vector3(0.0, y, 0.66), Color(0.95, 0.16, 0.16), 0.078))
	_axis_root.add_child(_ball(Vector3(0.0, y, -0.66), Color(0.16, 0.38, 0.98), 0.078))
	var rod := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.028, 0.028, 1.20)
	rod.mesh = bm
	rod.position = Vector3(0.0, y, 0.0)
	rod.material_override = _mat(Color(0.78, 0.80, 0.84))
	_axis_root.add_child(rod)


func _ball(pos: Vector3, c: Color, r: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	mi.mesh = sm
	mi.position = pos
	mi.material_override = _mat(c)
	return mi


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = 0.1
	m.roughness = 0.5
	return m


func _xz_principal_angle(root: Node) -> float:
	var pts: PackedVector2Array = []
	_collect_xz(root, Transform3D(), pts)
	if pts.size() < 4:
		return 0.0
	var n := float(pts.size())
	var mean := Vector2.ZERO
	for p in pts:
		mean += p
	mean /= n
	var cxx := 0.0
	var czz := 0.0
	var cxz := 0.0
	for p in pts:
		var d := p - mean
		cxx += d.x * d.x
		czz += d.y * d.y
		cxz += d.x * d.y
	return 0.5 * atan2(2.0 * cxz, cxx - czz)


func _collect_xz(n: Node, xf: Transform3D, out: PackedVector2Array) -> void:
	var here := xf
	if n is Node3D:
		here = xf * (n as Node3D).transform
	if n is MeshInstance3D:
		var mesh: Mesh = (n as MeshInstance3D).mesh
		if mesh != null:
			for si in mesh.get_surface_count():
				var arrays := mesh.surface_get_arrays(si)
				if arrays.size() <= Mesh.ARRAY_VERTEX:
					continue
				var vs: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var i := 0
				while i < vs.size():
					var p := here * vs[i]
					out.append(Vector2(p.x, p.z))
					i += PCA_STEP
	for c in n.get_children():
		_collect_xz(c, here, out)


func _aabb_of(root: Node, pre: Transform3D) -> AABB:
	var parts: Array[AABB] = []
	_collect_aabb(root, pre, parts)
	if parts.is_empty():
		return AABB()
	var a := parts[0]
	for i in range(1, parts.size()):
		a = a.merge(parts[i])
	return a


func _collect_aabb(n: Node, xf: Transform3D, out: Array[AABB]) -> void:
	var here := xf
	if n is Node3D:
		here = xf * (n as Node3D).transform
	if n is MeshInstance3D:
		var a := (n as MeshInstance3D).get_aabb()
		var mn := Vector3(1e9, 1e9, 1e9)
		var mx := Vector3(-1e9, -1e9, -1e9)
		for i in 8:
			var p := here * a.get_endpoint(i)
			mn = mn.min(p)
			mx = mx.max(p)
		out.append(AABB(mn, mx - mn))
	for c in n.get_children():
		_collect_aabb(c, here, out)
