extends Node3D
## Step 5 · Godot 对齐测试
## 参数与 Blender 的 multi_hit.blend 一一对应，用于 A7 截图对比。

const DECAL_SHADER := preload("res://scripts/visual/fx_shield_decal.gdshader")

@export var ship_half_length := 180.0
var atlas: Texture2D
var axes := Vector3.ZERO

func _ready() -> void:
	atlas = load("res://assets/vfx/advent_shield_impact_atlas.png")
	axes = Vector3(ship_half_length * 1.015, ship_half_length * 0.509, ship_half_length * 0.146)
	_build_env()
	_build_ship()
	_build_hits()
	_save_shot(2.2, "F:/evezzq/refs/godot_aligned.png")

func _build_env() -> void:
	var L := ship_half_length
	var cam := Camera3D.new()
	cam.position = Vector3(0, -L * 2.8, L * 1.15)
	cam.near = 1.0
	cam.far = 20000.0
	add_child(cam)
	cam.look_at(Vector3(0, L * 0.30, L * 0.10), Vector3.UP)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, 150, 0)
	light.light_energy = 1.2
	add_child(light)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.004, 0.005, 0.010)
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
	mat.albedo_color = Color(0.30, 0.29, 0.26)
	mat.metallic = 0.5
	mat.roughness = 0.65
	ship.material_override = mat
	add_child(ship)

func _surf(theta_deg: float, phi_deg: float) -> Vector3:
	var th := deg_to_rad(theta_deg)
	var ph := deg_to_rad(phi_deg)
	return Vector3(axes.x * cos(th) * cos(ph),
	               axes.y * sin(th) * cos(ph),
	               axes.z * sin(ph))

func _build_hits() -> void:
	# 与 Blender 完全相同的四个参数
	var params := [[62.0, 32.0], [80.0, 38.0], [100.0, 35.0], [118.0, 30.0]]
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 96
	sphere.rings = 48

	for i in range(params.size()):
		var p := _surf(params[i][0], params[i][1])
		var n := Vector3(p.x / (axes.x * axes.x), p.y / (axes.y * axes.y), p.z / (axes.z * axes.z)).normalized()
		var mi := MeshInstance3D.new()
		mi.mesh = sphere
		mi.scale = axes
		var mat := ShaderMaterial.new()
		mat.shader = DECAL_SHADER
		mat.set_shader_parameter("atlas", atlas)
		mat.set_shader_parameter("shell_axes", axes)
		mat.set_shader_parameter("hit_center", p)
		mat.set_shader_parameter("hit_normal", n)
		# 基在单位空间：u 沿船长(x)，v 沿垂直(z)
		mat.set_shader_parameter("hit_tangent_u", Vector3(1, 0, 0))
		mat.set_shader_parameter("hit_tangent_v", Vector3(0, 0, 1))
		mat.set_shader_parameter("decal_radius", 0.95)
		mat.set_shader_parameter("aspect", 1.45)
		mat.set_shader_parameter("intensity", 6.0)
		mat.set_shader_parameter("frame", 34)
		mi.material_override = mat
		add_child(mi)

func _save_shot(delay: float, path: String) -> void:
	var t := Timer.new()
	t.one_shot = true
	t.wait_time = delay
	add_child(t)
	t.timeout.connect(func():
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(path)
		print("[SHOT] ", path)
	)
	t.start()
