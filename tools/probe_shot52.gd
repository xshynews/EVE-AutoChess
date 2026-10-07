extends Node3D
## ══════════════════════════════════════════════════════════════════════
##  52 轮 · **工具 ↔ 实机 并排对照（重做版）**
## ══════════════════════════════════════════════════════════════════════
##
## ── 51 轮那版为什么废掉（用户：「标出来的 8 艘，全部和工具里不一样」）───
##   两个硬伤，**都在我的出图上，不在船身上**：
##    ① **两边尺度不同**：工具侧归一化到 1.0，实机侧走
##       `2.6/span × _visual_scale(0.7~1.35) × 1.20` ≈ 2.2~4.2
##       ⇒ 同一机位下实机侧大 2~4 倍，**看起来就不是同一艘船**。
##    ② **相机正对船头**：实机侧 aim = (0,0,−1)（朝敌），而相机恰好在 +Z 朝 −Z 看
##       ⇒ 看到的是**正面**，长轴缩成一点，**根本判不出朝向**。
##
## ── 本版修法 ─────────────────────────────────────────────────────
##   · **两边统一到同一个世界长度** `UNIT = 2.6`（= HULL_REF_LENGTH）
##       · 工具侧：`sc = UNIT / long_len`（原来硬编码 1.0/long_len）
##       · 实机侧：**关掉 `_apply_scale()` 的放大**（board_mode=false 时
##         hull_root.scale = _visual_scale × VISUAL_EXAGGERATION，我除回去）
##   · **相机从「侧上方」看**，四个视角都给：
##       侧视（相机在 +X，屏幕左 = −Z 敌向）
##       俯视（相机在 +Y，屏幕上 = −Z 敌向）
##       前视（相机在 +Z）
##       后视（相机在 −Z）
##   · 每张图内：**左 = 工具里，右 = 实机里**，同机位同尺度。
##
## 跑法（非 headless）：
##   ... res://tools/probe_shot52.tscn -- --ids=abaddon,kestrel
## 输出：`user://shot52/<id>_<view>.png`

const YAW := preload("res://scripts/data/eve_ship_yaw.gd")
const VISUAL := preload("res://scripts/visual/eve_ship_visual.gd")
const MODEL := preload("res://scripts/visual/eve_ship_model.gd")
const SHIP := preload("res://scripts/core/eve_ship.gd")
const MOTION := preload("res://scripts/core/eve_destiny_motion.gd")
const ASSET := preload("res://scripts/data/eve_ship_asset_index.gd")

## 两边统一的世界长度（= 生产的 HULL_REF_LENGTH）
const UNIT := 2.6
const GAP := 1.35          ## 两船中心半距（总距 2×GAP）

## 四个视角：name → [相机方向(单位), up]
const VIEWS := {
	"SIDE":  [Vector3(1, 0.25, 0.55), Vector3(0, 1, 0)],
	"TOP":   [Vector3(0, 1, 0.15), Vector3(0, 0, -1)],
	"FRONT": [Vector3(0, 0.30, 1), Vector3(0, 1, 0)],
}

var _ids: PackedStringArray = PackedStringArray()

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute("user://shot52")
	_ids = _parse_ids()
	print("[52·并排] 共 %d 艘：%s" % [_ids.size(), ", ".join(_ids)])
	_env()
	await _run()
	get_tree().quit(0)


func _parse_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--ids="):
			for s in a.substr(6).split(",", false):
				out.append(s.strip_edges())
	if out.is_empty():
		out.append("abaddon")
	return out


func _env() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = Sky.new()
	env.sky.sky_material = ProceduralSkyMaterial.new()
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 1.0
	we.environment = env
	add_child(we)
	# 世界锚：红 = −Z（敌向）· 蓝 = +Y（天）
	_ball(Vector3(0, 0, -1) * 3.4, Color(1, 0.18, 0.18), "-Z 敌")
	_ball(Vector3(0, 1, 0) * 3.4, Color(0.30, 0.60, 1), "+Y 天")


func _ball(pos: Vector3, col: Color, txt: String) -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.075
	sm.height = 0.15
	mi.mesh = sm
	mi.position = pos
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = 2.5
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = m
	add_child(mi)
	var lb := Label3D.new()
	lb.text = txt
	lb.position = pos
	lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lb.no_depth_test = true
	lb.font_size = 40
	lb.pixel_size = 0.0018
	lb.modulate = col
	add_child(lb)


func _run() -> void:
	var cam := Camera3D.new()
	cam.fov = 42.0
	add_child(cam)

	for id in _ids:
		var sid := StringName(id)
		var root := Node3D.new()
		add_child(root)

		# 左 = 工具里（与 probe_bow_box._load_current 同式，但**统一到 UNIT**）
		var l := Node3D.new()
		l.position = Vector3(-GAP, 0, 0)
		root.add_child(l)
		_build_tool(l, sid)

		# 右 = 实机里（生产 setup + sync_from_body，**尺度除回基准**）
		var r := Node3D.new()
		r.position = Vector3(GAP, 0, 0)
		root.add_child(r)
		await _build_real(r, sid)

		_lbl(root, Vector3(-GAP, UNIT * 0.82, 0), "工具里")
		_lbl(root, Vector3(GAP, UNIT * 0.82, 0), "实机里")

		await _wait(8)
		for vn in VIEWS.keys():
			var d: Vector3 = VIEWS[vn][0]
			var up: Vector3 = VIEWS[vn][1]
			var dist := 5.4
			cam.global_position = d.normalized() * dist
			cam.look_at_from_position(d.normalized() * dist, Vector3(0, 0, 0), up)
			await _wait(3)
			var img := get_viewport().get_texture().get_image()
			img.save_png("user://shot52/%s_%s.png" % [String(sid), vn])
		print("   · %s" % String(sid))
		root.queue_free()
		await _wait(3)
	cam.queue_free()
	print("[52·并排] 完毕 → user://shot52")


## 工具侧：同一式子，但把归一化改成与实机同尺度（UNIT / long_len）
func _build_tool(parent: Node3D, sid: StringName) -> void:
	var model := MODEL.instantiate(sid)
	if model == null:
		return
	var aabb := _aabb(model)
	var long_len := maxf(aabb.size.x, maxf(aabb.size.y, maxf(aabb.size.z, 1e-4)))
	var sc := UNIT / long_len          # ★ 51 轮那版这里写的是 1.0/long_len
	parent.add_child(model)
	model.basis = VISUAL.zero_pose_basis(sid) * Basis.IDENTITY.scaled(Vector3.ONE * sc)
	model.position = -(sc * aabb.get_center())


## 实机侧：生产 setup() + sync_from_body(aim=−Z)，并把放大除回去
func _build_real(parent: Node3D, sid: StringName) -> void:
	var ship: Variant = SHIP.new()
	ship.ship_key = sid
	ship.team = 0
	ship.body = MOTION.Body.new()
	var vis: Variant = VISUAL.new()
	parent.add_child(vis)
	vis.call("setup", ship)
	ship.body.aim_dir = Vector3(0, 0, -1)
	ship.body.velocity = Vector3.ZERO
	for _i in 70:
		vis.call("sync_from_body", ship.body, true, 1.0 / 60.0)
		await get_tree().process_frame
	# ★ 关掉 _apply_scale() 的放大：hull_root.scale 被设成
	#   _visual_scale × VISUAL_EXAGGERATION(=1.20)，这里除回去 ⇒ 只剩 HULL_REF_LENGTH 基准
	var hr: Node3D = vis.get("hull_root")
	if hr != null:
		hr.scale = Vector3.ONE


func _lbl(parent: Node3D, pos: Vector3, txt: String) -> void:
	var lb := Label3D.new()
	lb.text = txt
	lb.position = pos
	lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lb.no_depth_test = true
	lb.font_size = 44
	lb.pixel_size = 0.0016
	lb.modulate = Color(1, 0.93, 0.55)
	parent.add_child(lb)


func _aabb(n: Node) -> AABB:
	var out := AABB()
	var first := true
	for m in _meshes(n):
		var mi: MeshInstance3D = m
		var a: AABB = mi.get_aabb()
		if first:
			out = a
			first = false
		else:
			out = out.merge(a)
	if first:
		return AABB(Vector3.ZERO, Vector3.ZERO)
	return out


func _meshes(n: Node) -> Array:
	var out: Array = []
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(_meshes(c))
	return out


func _wait(n: int) -> void:
	for _i in n:
		await get_tree().process_frame
