extends Node3D

## 舰船**原始姿态**多方位取景探针（不套任何 yaw 修正）
##
## ══════════════════════════════════════════════════════════════════
##  为什么要它（与 probe_ship_axis 的分工）
## ══════════════════════════════════════════════════════════════════
##  `probe_ship_axis` 拍的是「工程算式生效后」的姿态 —— 用来验证实装。
##  本探针拍的是 **glb 的原始姿态**（不旋转）—— 用来跟**用户从 EVE 客户端
##  截来的图**做轮廓配准：只要找到「哪一个方位角拍出来和用户那张一样」，
##  就能把用户图里的特征（发动机尾焰在哪端）**翻译回模型坐标**。
##
##  这是「朝向只能人眼判」这条结论下唯一剩下的**客观**路径：
##    用户图给的是**语义**（哪端是舰艉），本探针给的是**坐标系**（哪端是 +X/+Z）。
##
## ── 跑法（非 headless：要读 SubViewport 纹理）──────────────────
##   "C:/godot/Godot_v4.7.1-stable_win64_console.exe" \
##     --path "F:/evezzq/eve自走棋918" --quit-after 4000 \
##     res://tools/probe_ship_raw_views.tscn -- --ids=catalyst,kestrel
##
##   可选：--azs=0,45,90,...   --els=0,35   --size=480   --dir=raw_views

const INDEX := preload("res://scripts/data/eve_ship_asset_index.gd")

const OUT_DIR := "user://raw_views"
const CAM_DIST := 8.0
const CAM_SIZE := 1.28          # 归一化后最长边 = 1.0，留 28% 余量

var _ids: PackedStringArray = PackedStringArray()
var _azs: Array = []
var _els: Array = []
var _size := 480
var _dir := OUT_DIR

var _vp: SubViewport = null
var _cam: Camera3D = null
var _holder: Node3D = null


func _ready() -> void:
	var ids := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--ids="):
			ids = a.substr(6)
		elif a.begins_with("--azs="):
			_azs = _floats(a.substr(6))
		elif a.begins_with("--els="):
			_els = _floats(a.substr(6))
		elif a.begins_with("--size="):
			_size = maxi(96, int(a.substr(7)))
		elif a.begins_with("--dir="):
			_dir = "user://" + a.substr(6)
	if _azs.is_empty():
		var i := 0
		while i < 360:
			_azs.append(float(i))
			i += 22
	if _els.is_empty():
		_els = [0.0, 35.0]
	_ids = ids.split(",") if not ids.is_empty() else PackedStringArray()
	_build()
	await _run()


func _floats(s: String) -> Array:
	var out: Array = []
	for t in s.split(","):
		out.append(float(t))
	return out


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

	_holder = Node3D.new()
	_vp.add_child(_holder)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_dir))
	var n := 0
	for id in _ids:
		var sid := StringName(String(id).strip_edges())
		if not await _prep(sid):
			continue
		for el in _els:
			for az in _azs:
				if await _shoot(sid, float(az), float(el)):
					n += 1
	print("[RAWV] 出图 %d 张 -> %s" % [n, ProjectSettings.globalize_path(_dir)])
	print("[RAWV] 原始姿态（未套 MODEL_YAW_FIX / 未套 yaw 表）")
	print("[RAWV] ==== DONE ====")
	get_tree().quit(0)


func _prep(id: StringName) -> bool:
	for c in _holder.get_children():
		_holder.remove_child(c)
		c.queue_free()
	_holder.transform = Transform3D()
	var model := EveShipModel.instantiate(id, false)
	if model == null:
		push_warning("[RAWV] %s 无 3D 模型" % String(id))
		return false
	_holder.add_child(model)
	var aabb := _aabb_of(model, Transform3D())
	if aabb.size.length() < 0.0001:
		return false
	var long_len := maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z))
	var k := 1.0 / maxf(long_len, 0.0001)
	var basis := Basis.IDENTITY.scaled(Vector3.ONE * k)
	_holder.transform = Transform3D(basis, -(basis * aabb.get_center()))
	print("[RAWV] %-12s 原始尺寸 %s  最长边 %.1f m" % [
		String(id), str(aabb.size.snappedf(0.1)), long_len])
	return true


func _shoot(id: StringName, az_deg: float, el_deg: float) -> bool:
	var az := deg_to_rad(az_deg)
	var el := deg_to_rad(el_deg)
	var dir := Vector3(cos(el) * cos(az), sin(el), cos(el) * sin(az)).normalized()
	_cam.position = dir * CAM_DIST
	_cam.look_at(Vector3.ZERO, Vector3.UP)
	await RenderingServer.frame_post_draw
	var tex := _vp.get_texture()
	if tex == null:
		return false
	var img := tex.get_image()
	if img == null:
		return false
	img.save_png("%s/%s_az%03d_el%+03d.png" % [_dir, String(id), int(az_deg), int(el_deg)])
	return true


func _aabb_of(root: Node, pre: Transform3D) -> AABB:
	var parts: Array[AABB] = []
	_collect(root, pre, parts)
	if parts.is_empty():
		return AABB()
	var a := parts[0]
	for i in range(1, parts.size()):
		a = a.merge(parts[i])
	return a


func _collect(n: Node, xf: Transform3D, out: Array[AABB]) -> void:
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
		_collect(c, here, out)
