extends Node3D
## ══════════════════════════════════════════════════════════════════════
## ⛔⛔ **53 轮标注：本探针的判据/出图已作废**，仅留档参考 ——
##    原因见「接手手册-2026-09-24 / 03_3D模型朝向标定.md」§16.5（对照图两硬伤）。
##    **不要**拿它的输出当下结论。
##  51 轮 · **工具船身是否被表污染** —— 出图坐实（用户 51 轮裁决）
## ══════════════════════════════════════════════════════════════════════
##
## ── 要回答的问题 ─────────────────────────────────────────────────
##   用户在工具里看到的船，到底是不是**模型的原样**？
##   `probe_bow_box._load_current()` 写的是：
##       `_ship_norm = Transform3D(zero_pose_basis(id) * scale, ...)`
##   而 `zero_pose_basis(id) = R_z(180°) · R_y(extra) · M · mesh_rot`。
##
##   ⇒ 若 M（`AXIS_REMAP`）本身就是「为了让舰艏朝敌」而定的姿态修正，
##     那么把它烘进**标定用**的船身上，就等于**拿答案去当题目**：
##        · 用户看到的是**已经被摆成"朝敌"的船**（若 M 正确）
##        · 用户把红球对到"看起来的舰艏" ⇒ 落表的其实是 `M` 已经摆过的那根轴
##        · 一旦 M 有偏差，用户在工具里**永远看不出来**（船跟着 M 一起转）
##     ⇒ 标定必须建立**与 M 无关**的参照，否则是闭环自证。
##
## ── 本探针做什么 ─────────────────────────────────────────────────
##   同一艘船，出**三种摆法**并排：
##     A. `M`（原样几何摆法，**工具当前**）= zero_pose_basis(id)
##     B. `raw`（**模型原样**，不叠任何表）= 单位阵
##     C. `noM`（只剥 `M`，保留 `mesh_rot`）= R_z(180°)·R_y(extra)·mesh_rot
##   ⚠️ C 是关键对照：它把「工程为了修朝向加的 M」剥掉，
##      剩下「glb 自带的几何事实」⇒ 这才是**船的真实几何姿态**。
##      用户在工具里应该看到的是 **C（或 B）**，而不是 A。
##
## 跑法（非 headless）：
##   ... res://tools/probe_cmp51b.tscn -- --ids=abaddon,algos,catalyst,kestrel
## 输出：`user://cmp51b/<id>_ABC.png`（一屏三船）

const YAW := preload("res://scripts/data/eve_ship_yaw.gd")
const VISUAL := preload("res://scripts/visual/eve_ship_visual.gd")
const MODEL := preload("res://scripts/visual/eve_ship_model.gd")
const ASSET := preload("res://scripts/data/eve_ship_asset_index.gd")

const CAM_DIST := 5.2
const VIEWS := {
	"主视图": [Vector3(0, 0, 1), Vector3(0, 1, 0)],
	"俯视图": [Vector3(0, 1, 0), Vector3(0, 0, -1)],
	"左视图": [Vector3(-1, 0, 0), Vector3(0, 1, 0)],
}

var _ids: PackedStringArray = PackedStringArray()

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute("user://cmp51b")
	_ids = _parse_ids()
	print("[51b] 共 %d 艘：%s" % [_ids.size(), ", ".join(_ids)])
	_env_setup()
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


func _env_setup() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = Sky.new()
	env.sky.sky_material = ProceduralSkyMaterial.new()
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 1.0
	we.environment = env
	add_child(we)
	_world_ball(Vector3(0, 0, -1) * (CAM_DIST * 1.3), Color(1, 0.15, 0.15), "TO_ENEMY(-Z)")
	_world_ball(Vector3(0, 1, 0) * (CAM_DIST * 1.3), Color(0.25, 0.55, 1), "UP(+Y)")


func _world_ball(pos: Vector3, col: Color, txt: String) -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.10
	sm.height = 0.20
	mi.mesh = sm
	mi.position = pos
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = 2.0
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = m
	add_child(mi)
	var lb := Label3D.new()
	lb.text = txt
	lb.position = pos
	lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lb.no_depth_test = true
	lb.font_size = 40
	lb.pixel_size = 0.002
	lb.modulate = col
	add_child(lb)


func _run() -> void:
	var cam := Camera3D.new()
	cam.fov = 45.0
	add_child(cam)
	cam.current = true

	for id in _ids:
		var sid := StringName(id)
		var holder := Node3D.new()
		add_child(holder)
		# A / B / C 三船横排，间距 3.2
		_make(holder, sid, "A_M", _basis_A(sid), Vector3(-3.2, 0, 0))
		_make(holder, sid, "B_RAW", Basis.IDENTITY, Vector3(0, 0, 0))
		_make(holder, sid, "C_noM", _basis_C(sid), Vector3(3.2, 0, 0))
		await _wait(6)

		for vn in VIEWS.keys():
			var d: Vector3 = VIEWS[vn][0]
			var up: Vector3 = VIEWS[vn][1]
			cam.global_position = d.normalized() * (CAM_DIST * 2.6)
			cam.look_at(Vector3.ZERO, up)
			await _wait(2)
			var img := get_viewport().get_texture().get_image()
			img.save_png("user://cmp51b/%s_%s.png" % [String(sid), vn])
			print("   · %s / %s" % [String(sid), vn])
		for c in holder.get_children():
			c.queue_free()
		holder.queue_free()
		await _wait(2)
	cam.queue_free()
	print("[51b] 完毕 → user://cmp51b")


## A：工具当前摆法 = `zero_pose_basis(id)`（**含 M**）
func _basis_A(id: StringName) -> Basis:
	return VISUAL.zero_pose_basis(id).orthonormalized()


## C：剥掉 `M`，保留 `mesh_rot`（+ 全局滚转与 yaw，其余同 A）
func _basis_C(id: StringName) -> Basis:
	var mr: Basis = VISUAL.mesh_rot_of(id)
	var yaw := YAW.extra_yaw(id)
	var out := Basis.from_euler(Vector3(0, yaw, 0)) * mr
	# 全局滚转（与生产同源）
	if VISUAL.GLOBAL_ROLL_180:
		out = Basis.from_euler(VISUAL.GLOBAL_ROLL_AXIS * PI) * out
	return out.orthonormalized()


func _make(holder: Node3D, id: StringName, tag: String, basis: Basis, off: Vector3) -> void:
	var model := MODEL.instantiate(id)
	if model == null:
		return
	var aabb := _aabb_of(model)
	if aabb.size.length() < 1e-4:
		model.queue_free()
		return
	var long_len := maxf(aabb.size.x, maxf(aabb.size.y, maxf(aabb.size.z, 1e-4)))
	var sc := 1.0 / long_len
	holder.add_child(model)
	model.basis = basis * Basis.IDENTITY.scaled(Vector3.ONE * sc)
	model.position = off - (sc * aabb.get_center())
	model.name = "%s_%s" % [tag, String(id)]
	var lb := Label3D.new()
	lb.text = tag
	lb.position = off + Vector3(0, 1.1, 0)
	lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lb.no_depth_test = true
	lb.font_size = 40
	lb.pixel_size = 0.002
	holder.add_child(lb)


func _aabb_of(n: Node) -> AABB:
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
