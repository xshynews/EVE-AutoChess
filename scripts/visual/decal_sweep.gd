extends Node3D
## 贴花参数扫描：同一壳上并排铺 5 组 (decal_radius, frame) 组合，
## 一次渲染就能对比出最佳配比。

const DECAL_SHADER := preload("res://scripts/visual/fx_shield_decal.gdshader")

@export var ship_half_length := 180.0
var atlas: Texture2D

func _ready() -> void:
	atlas = load("res://assets/vfx/advent_shield_impact_atlas.png")
	_build_env()
	_build_ship()
	var cases := [
		[0.30, 0.20], [0.40, 0.30], [0.50, 0.40], [0.62, 0.50], [0.75, 0.60],
	]
	for i in range(cases.size()):
		var t: float = cases[i][0]
		var fk: float = cases[i][1]
		_add_decal(i, t, fk)
	_save_shot(2.0, "F:/evezzq/refs/godot_sweep.png")

func _build_env() -> void:
	var L := ship_half_length
	var cam := Camera3D.new()
	cam.position = Vector3(L * 0.55, L * 0.55, L * 1.5)
	cam.near = 1.0
	cam.far = 20000.0
	add_child(cam)
	cam.look_at(Vector3.ZERO, Vector3.UP)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, 40, 0)
	light.light_energy = 1.4
	add_child(light)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.008, 0.010, 0.018)
	env.glow_enabled = true
	env.glow_intensity = 1.2
	env.glow_bloom = 0.3
	we.environment = env
	add_child(we)

func _build_ship() -> void:
	var L := ship_half_length
	var ship := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = L * 0.16
	cap.height = L * 1.75
	cap.radial_segments = 32
	ship.mesh = cap
	ship.rotation_degrees = Vector3(0, 0, 90)
	ship.scale = Vector3(1.0, 1.0, 0.45)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.36, 0.35, 0.31)
	mat.metallic = 0.55
	mat.roughness = 0.6
	ship.material_override = mat
	add_child(ship)

func _add_decal(idx: int, radius_factor: float, frame_factor: float) -> void:
	var axes := Vector3(ship_half_length * 1.02, ship_half_length * 0.51, ship_half_length * 0.15)
	# 沿船长方向分布 5 个点
	var u: float = lerp(-0.55, 0.55, float(idx) / 4.0)
	var dir := Vector3(u, 0.78, 0.55).normalized()
	var n := Vector3(dir.x / axes.x, dir.y / axes.y, dir.z / axes.z).normalized()
	var p := Vector3(n.x * axes.x, n.y * axes.y, n.z * axes.z)

	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 64
	sphere.rings = 32
	var mi := MeshInstance3D.new()
	mi.mesh = sphere
	mi.scale = axes
	mi.name = "Sweep_%d" % idx
	var mat := ShaderMaterial.new()
	mat.shader = DECAL_SHADER
	mat.set_shader_parameter("atlas", atlas)
	mat.set_shader_parameter("frame", int(frame_factor * 63.0))
	mat.set_shader_parameter("intensity", 2.2)
	mat.set_shader_parameter("decal_radius", ship_half_length * radius_factor)
	mat.set_shader_parameter("hit_center", p)
	var t1 := Vector3(1, 0, 0) - n * Vector3(1, 0, 0).dot(n)
	if t1.length() < 0.01:
		t1 = Vector3(0, 1, 0) - n * n.y
	t1 = t1.normalized()
	var t2 := n.cross(t1).normalized()
	mat.set_shader_parameter("hit_tangent_u", t1)
	mat.set_shader_parameter("hit_tangent_v", t2)
	mat.set_shader_parameter("hit_normal", n)
	mi.material_override = mat
	add_child(mi)

func _save_shot(delay: float, path: String) -> void:
	var t := Timer.new()
	t.one_shot = true
	t.wait_time = delay
	add_child(t)
	t.timeout.connect(func():
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png(path)
		print("[SHOT] ", path)
	)
	t.start()
