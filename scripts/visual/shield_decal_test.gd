extends Node3D
## 启示号真实网格 + 曲面护盾贴花（对齐 Blender v3）。
##
## 关键点：
##   护盾壳本身完全不渲染。受击时生成一块真实贴合椭球面的贴花网格，
##   每个顶点都投影到壳面上，UV 显式给出，因此曲率大的位置也不会被拉伸。
##   动画只改图集帧号与亮度，不改网格尺寸（缩放会把贴花拉离曲面）。

const DECAL_SHADER := preload("res://scripts/visual/fx_shield_decal.gdshader")
const ATLAS_SIZE := 8
const PATCH_SEGMENTS := 28          # 每个方向的网格段数
const PATCH_RADIUS_U := 0.28        # 单位球空间半宽
const PATCH_RADIUS_V := 0.23

@export var atlas: Texture2D
@export var hit_duration := 1.15
@export var auto_demo := true

var ship_root: Node3D
var camera: Camera3D
var ship_center := Vector3.ZERO
var shell_axes := Vector3.ONE
var hits: Array = []

func _ready() -> void:
	if atlas == null:
		atlas = load("res://assets/vfx/advent_shield_impact_atlas.png")
	_build_ship()
	_build_environment()
	_build_camera()
	if auto_demo:
		var d := Vector3(0.10, 0.62, -0.78).normalized()
		_hit(d)
	if OS.get_cmdline_user_args().has("--sweep"):
		# 同一半径、不同曲率位置的对照：验证贴花尺寸不随壳面弯曲变化
		# 三个方位都朝镜头一侧，只是沿船长方向位置不同 → 壳面曲率不同
		_hit(Vector3(-0.62, 0.48, -0.62).normalized())   # 船尾侧，曲率大
		_hit(Vector3(0.62, 0.48, -0.62).normalized())    # 船首侧，曲率大
		_hit(Vector3(0.0, 0.62, -0.78).normalized())     # 船中，曲率小
		_frame_camera_wide()
	if OS.get_cmdline_user_args().has("--shot"):
		var out := "F:/evezzq/refs/godot_curved_decal.png"
		if OS.get_cmdline_user_args().has("--sweep"):
			out = "F:/evezzq/refs/godot_curvature_sweep.png"
		if OS.get_cmdline_user_args().has("--debug"):
			out = "F:/evezzq/refs/godot_curved_debug.png"
		_save_shot(0.50, out)

func _build_ship() -> void:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_file("res://assets/vfx/revelation_hull.glb", state)
	if err != OK:
		push_error("GLB import failed: %s" % err)
		return
	ship_root = doc.generate_scene(state)
	ship_root.name = "RevelationHull"
	add_child(ship_root)

	var bounds := _combined_bounds(ship_root)
	ship_center = bounds.get_center()
	var half := bounds.size * 0.5
	# 船体尺寸约 X=326(长) Y=39(高) Z=164(宽)。护盾略外扩，薄轴多扩一些。
	shell_axes = Vector3(
		half.x * 1.10,
		max(half.y * 1.55, half.z * 0.22),
		half.z * 1.13
	)
	print("HULL BOUNDS ", bounds, " AXES ", shell_axes)
	_tame_hull_materials()

## GLB 的船体材质来自 Blender 的烘焙贴图，直接放进 Godot 容易整船过曝。
## 这里只做「可读性」处理：关自发光、压反照率，几何与贴图都保留。
func _tame_hull_materials() -> void:
	for mi in _mesh_nodes(ship_root):
		for s in range(mi.mesh.get_surface_count()):
			var src := mi.get_active_material(s)
			if src == null:
				continue
			if src is BaseMaterial3D:
				var m: BaseMaterial3D = src.duplicate()
				m.emission_enabled = false
				m.albedo_color = Color(
					m.albedo_color.r * 0.35,
					m.albedo_color.g * 0.35,
					m.albedo_color.b * 0.35, 1.0)
				m.metallic = 0.25
				m.roughness = 0.55
				mi.set_surface_override_material(s, m)
			print("HULL MAT ", src.get_class(), " ", src.resource_name)

func _mesh_nodes(root: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if root is MeshInstance3D:
		out.append(root)
	for c in root.get_children():
		out.append_array(_mesh_nodes(c))
	return out

func _combined_bounds(root: Node) -> AABB:
	var result := AABB()
	var have := false
	for mi in _mesh_nodes(root):
		var a: AABB = mi.global_transform * mi.get_aabb()
		if not have:
			result = a
			have = true
		else:
			result = result.merge(a)
	return result

func _build_environment() -> void:
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-30.0, -35.0, 0.0)
	light.light_energy = 1.4
	add_child(light)

	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.004, 0.006, 0.012)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.05, 0.07, 0.12)
	env.ambient_light_energy = 0.35
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.55
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_bloom = 0.05
	we.environment = env
	add_child(we)

func _build_camera() -> void:
	camera = Camera3D.new()
	camera.near = 0.5
	camera.far = 8000.0
	camera.fov = 40.0
	add_child(camera)
	_frame_camera()

func _frame_camera() -> void:
	# 掠射角：视线几乎与壳面相切，曲率最容易读出来。
	var d := Vector3(0.10, 0.62, -0.78).normalized()
	var hit := _surface_point(d)
	# 机位要偏向命中点法线，否则曲面片侧对镜头会被压成一条线（71° 掠射几乎不可见）。
	var n := _hit_normal(d)
	var skew := Vector3(0.85, 0.0, 0.0)
	var view := (n * 0.80 + skew * 0.55).normalized()
	camera.position = hit + view * 165.0
	# 让船体也进画面，便于判断贴花在壳面而不是凭空出现
	var aim := hit.lerp(ship_center, 0.16)
	camera.look_at(aim, Vector3.UP)

## 全景：三条不同曲率位置同时显示，用于比较贴花实际占位是否一致。
func _frame_camera_wide() -> void:
	var view := Vector3(0.55, 0.42, -1.0).normalized()
	camera.position = ship_center + view * 520.0
	camera.look_at(ship_center, Vector3.UP)
	camera.fov = 42.0

func _hit_normal(unit_dir: Vector3) -> Vector3:
	return Vector3(
		unit_dir.x / shell_axes.x,
		unit_dir.y / shell_axes.y,
		unit_dir.z / shell_axes.z
	).normalized()

func _surface_point(unit_dir: Vector3) -> Vector3:
	return ship_center + Vector3(
		unit_dir.x * shell_axes.x,
		unit_dir.y * shell_axes.y,
		unit_dir.z * shell_axes.z
	)

## 生成贴合椭球面的贴花片。
func _build_patch(unit_dir: Vector3) -> ArrayMesh:
	var n := unit_dir.normalized()
	# 单位球空间里的切向基
	var tu := Vector3.RIGHT - n * Vector3.RIGHT.dot(n)
	if tu.length() < 0.01:
		tu = Vector3.FORWARD - n * Vector3.FORWARD.dot(n)
	tu = tu.normalized()
	var tv := n.cross(tu).normalized()

	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()

	var seg := PATCH_SEGMENTS
	for j in range(seg + 1):
		var v := -PATCH_RADIUS_V + 2.0 * PATCH_RADIUS_V * float(j) / float(seg)
		for i in range(seg + 1):
			var u := -PATCH_RADIUS_U + 2.0 * PATCH_RADIUS_U * float(i) / float(seg)
			# 关键：先把点投到单位球面，再按椭球轴缩放 → 顶点严格在壳面上
			var q := (n + tu * u + tv * v).normalized()
			verts.append(Vector3(q.x * shell_axes.x, q.y * shell_axes.y, q.z * shell_axes.z))
			var nrm := Vector3(q.x / shell_axes.x, q.y / shell_axes.y, q.z / shell_axes.z).normalized()
			normals.append(nrm)
			uvs.append(Vector2(float(i) / float(seg), float(j) / float(seg)))

	for j in range(seg):
		for i in range(seg):
			var a := j * (seg + 1) + i
			var b := a + 1
			var c := a + (seg + 1) + 1
			var dd := a + (seg + 1)
			idx.append(a); idx.append(b); idx.append(c)
			idx.append(a); idx.append(c); idx.append(dd)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func _hit(unit_dir: Vector3) -> void:
	var mesh := _build_patch(unit_dir)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = ship_center      # 顶点是相对船心的壳面坐标
	mi.name = "CurvedImpact"
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var mat := ShaderMaterial.new()
	mat.shader = DECAL_SHADER
	mat.set_shader_parameter("atlas", atlas)
	mat.set_shader_parameter("atlas_size", ATLAS_SIZE)
	mat.set_shader_parameter("frame", 0)
	mat.set_shader_parameter("intensity", 8.0)
	if OS.get_cmdline_user_args().has("--debug"):
		mat.set_shader_parameter("debug_solid", true)
	mi.set_surface_override_material(0, mat)
	add_child(mi)
	hits.append({"node": mi, "mat": mat, "t": 0.0})
	print("HIT patch verts=", mesh.get_surface_count(), " dir=", unit_dir)

func _process(delta: float) -> void:
	for h in hits:
		h.t += delta
		var k: float = h.t / hit_duration
		if k >= 1.0:
			h.node.visible = false
			continue
		h.node.visible = true
		h.mat.set_shader_parameter("frame", int(clamp(k, 0.0, 0.999) * float(ATLAS_SIZE * ATLAS_SIZE - 1)))
		# 亮度包络：前 12% 冲高，之后衰减
		var env := 1.0
		if k < 0.12:
			env = lerp(1.25, 1.0, k / 0.12)
		else:
			env = pow(1.0 - (k - 0.12) / 0.88, 1.6)
		h.mat.set_shader_parameter("intensity", 8.0 * clamp(env, 0.0, 1.4))

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
		_hit(Vector3(0.10, 0.62, -0.78).normalized())

func _save_shot(delay: float, path: String) -> void:
	var timer := Timer.new()
	timer.one_shot = true
	timer.wait_time = delay
	add_child(timer)
	timer.timeout.connect(func():
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png(path)
		print("[SHOT] ", path, " ", img.get_width(), "x", img.get_height())
		get_tree().quit()
	)
	timer.start()
