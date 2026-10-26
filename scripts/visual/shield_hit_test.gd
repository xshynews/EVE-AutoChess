extends Node3D
## 护盾受击测试场景（程序化搭建，不依赖外部资源）
##
## 尺度可调：ship_half_length 默认 180，和 Blender 里启示号的半长一致，
## 用来验证「参数按船体尺寸等比缩放」这套换算。
##
## 操作：空格/1 单发；2/3/4 追加不同位置的命中。

const SHIELD_SHADER := preload("res://scripts/visual/fx_shield_wave.gdshader")
const FIRE_SHADER := preload("res://scripts/visual/fx_flipbook_fire.gdshader")
const MAX_HITS := 4

@export var atlas: Texture2D
@export var ship_half_length := 180.0
@export var burst_lifetime := 1.6
@export var auto_demo := true

var shield_mat: ShaderMaterial
var shield_axes := Vector3.ONE
var bursts: Array = []

var centers := PackedVector3Array()
var radii := PackedFloat32Array()
var amps := PackedFloat32Array()
var age := PackedFloat32Array()

func _ready() -> void:
	if atlas == null:
		var p := "res://assets/vfx/fire_large_01.png"
		if ResourceLoader.exists(p):
			atlas = load(p)
	for i in range(MAX_HITS):
		centers.append(Vector3.ZERO)
		radii.append(0.0)
		amps.append(0.0)
		age.append(999.0)
	_build_env()
	_build_ship()
	_build_shield()
	if auto_demo:
		_auto_demo()

func _build_env() -> void:
	var L := ship_half_length
	var cam := Camera3D.new()
	cam.position = Vector3(L * 0.9, L * 1.1, L * 2.6)
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

func _build_shield() -> void:
	# 与 Blender 蛋形护盾同一套比例：长 1.02L / 横向 0.51L / 高 0.15L
	shield_axes = Vector3(ship_half_length * 1.02, ship_half_length * 0.51, ship_half_length * 0.15)
	var mi := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 64
	sphere.rings = 32
	mi.mesh = sphere
	mi.scale = shield_axes
	mi.name = "ShieldShell"
	shield_mat = ShaderMaterial.new()
	shield_mat.shader = SHIELD_SHADER
	shield_mat.set_shader_parameter("ring_width", ship_half_length * 0.092)
	shield_mat.set_shader_parameter("core_radius", ship_half_length * 0.37)
	mi.material_override = shield_mat
	add_child(mi)
	_push_params()

func _push_params() -> void:
	shield_mat.set_shader_parameter("impact_center", centers)
	shield_mat.set_shader_parameter("impact_radius", radii)
	shield_mat.set_shader_parameter("impact_amp", amps)
	shield_mat.set_shader_parameter("impact_count", MAX_HITS)

## 方向（单位向量）→ 椭球壳上的点
func _surface_point(dir: Vector3) -> Vector3:
	var d := Vector3(dir.x / shield_axes.x, dir.y / shield_axes.y, dir.z / shield_axes.z).normalized()
	return Vector3(d.x * shield_axes.x, d.y * shield_axes.y, d.z * shield_axes.z)

func _hit(pos: Vector3, normal: Vector3) -> void:
	var slot := 0
	var oldest := -1.0
	for i in range(MAX_HITS):
		if amps[i] <= 0.01:
			slot = i
			break
		if age[i] > oldest:
			oldest = age[i]
			slot = i
	centers[slot] = pos
	radii[slot] = 0.0
	amps[slot] = 1.1
	age[slot] = 0.0
	_push_params()

	if atlas == null:
		return
	var base := ship_half_length * 0.09
	for k in range(3):
		var mi := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(1.0, 1.0)
		mi.mesh = q
		var mat := ShaderMaterial.new()
		mat.shader = FIRE_SHADER
		mat.set_shader_parameter("atlas", atlas)
		mat.set_shader_parameter("frame", 0)
		mat.set_shader_parameter("brightness", 3.0)
		mi.material_override = mat
		mi.position = pos
		var up := normal.normalized()
		var right := up.cross(Vector3.UP)
		if right.length() < 0.01:
			right = up.cross(Vector3.RIGHT)
		right = right.normalized()
		var fwd := right.cross(up).normalized()
		var basis := Basis(right, up, fwd)
		mi.basis = basis.rotated(up, deg_to_rad(60.0 * k))
		mi.scale = Vector3(0.01, 0.01, 0.01)
		add_child(mi)
		bursts.append({"node": mi, "t": 0.0, "mat": mat, "base": base})

func _auto_demo() -> void:
	var dirs := [
		[0.4, Vector3(-0.62, 0.55, 0.42)],
		[1.1, Vector3(-0.05, 0.95, 0.30)],
		[1.8, Vector3(0.55, 0.62, 0.38)],
		[2.5, Vector3(0.22, -0.80, 0.45)],
	]
	for s in dirs:
		var t := Timer.new()
		t.one_shot = true
		t.wait_time = s[0]
		add_child(t)
		var dir: Vector3 = (s[1] as Vector3).normalized()
		var pt := _surface_point(dir)
		t.timeout.connect(func(): _hit(pt, dir))
		t.start()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var dirs := {
			KEY_SPACE: Vector3(-0.62, 0.55, 0.42),
			KEY_1: Vector3(-0.62, 0.55, 0.42),
			KEY_2: Vector3(-0.05, 0.95, 0.30),
			KEY_3: Vector3(0.55, 0.62, 0.38),
			KEY_4: Vector3(0.22, -0.80, 0.45),
		}
		if dirs.has(event.keycode):
			var d: Vector3 = (dirs[event.keycode] as Vector3).normalized()
			_hit(_surface_point(d), d)

func _process(delta: float) -> void:
	var rmax := ship_half_length * 0.7
	for i in range(MAX_HITS):
		if amps[i] <= 0.0:
			continue
		age[i] += delta
		radii[i] = rmax * (1.0 - exp(-age[i] * 2.2))
		amps[i] = 1.1 * clamp(1.0 - age[i] / 1.4, 0.0, 1.0)
	_push_params()

	for b in bursts:
		b.t += delta
		var k: float = b.t / burst_lifetime
		var s: float = b.base * clamp(k * 2.2, 0.02, 1.0)
		b.node.scale = Vector3(s, s, s)
		b.mat.set_shader_parameter("frame", int(clamp(k, 0.0, 0.999) * 63.0))
		b.mat.set_shader_parameter("brightness", 3.0 * (1.0 - k))
		b.node.visible = k < 1.0
	bursts = bursts.filter(func(b): return b.t < burst_lifetime)
