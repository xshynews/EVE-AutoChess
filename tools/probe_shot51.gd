extends Node3D
## ══════════════════════════════════════════════════════════════════════
## ⛔⛔ **53 轮标注：本探针的判据/出图已作废**，仅留档参考 ——
##    原因见「接手手册-2026-09-24 / 03_3D模型朝向标定.md」§16.5（对照图两硬伤）。
##    **不要**拿它的输出当下结论。
##  51 轮 · **工具 ↔ 实机 并排出图**（你亲眼看，一眼判）
## ══════════════════════════════════════════════════════════════════════
##
## 左边 = 工具里的船（`zero_pose_basis(id)`，你在标定工具里看到的就是它）
## 右边 = 实机里的船（走生产 `setup()` + `sync_from_body(aim=(0,0,-1))`）
##
## ⚠️ 两边**都是生产代码摆的**，零复刻（红线 40）。
## 相机在同一机位，同时框住两艘 ⇒ 一眼看它们是否同一个姿态。
##
## 跑法（非 headless）：
##   ... res://tools/probe_shot51.tscn [-- --ids=a,b]
## 输出：`user://shot51/<id>_CMP.png`（另有 _L/_R 单独图）

const YAW := preload("res://scripts/data/eve_ship_yaw.gd")
const VISUAL := preload("res://scripts/visual/eve_ship_visual.gd")
const MODEL := preload("res://scripts/visual/eve_ship_model.gd")
const SHIP := preload("res://scripts/core/eve_ship.gd")
const MOTION := preload("res://scripts/core/eve_destiny_motion.gd")
const ASSET := preload("res://scripts/data/eve_ship_asset_index.gd")

const SPAN := 2.6
const GAP := 1.9          ## 两船中心距（世界单位）

var _ids: PackedStringArray = PackedStringArray()

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute("user://shot51")
	_ids = _parse_ids()
	print("[51·并排] 共 %d 艘" % _ids.size())
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


func _run() -> void:
	# 固定机位：从「我方背后」朝 −Z 看（= 实机战斗的相机语义）
	#   屏幕上方 = 敌人方向（红线 42）
	var cam := Camera3D.new()
	cam.fov = 40.0
	add_child(cam)
	cam.position = Vector3(0, 1.7, 7.6)
	cam.look_at_from_position(Vector3(0, 1.7, 7.6), Vector3(0, 0, 0), Vector3.UP)
	cam.current = true

	for id in _ids:
		var sid := StringName(id)
		var root := Node3D.new()
		add_child(root)

		# ── 左：工具视角 ──
		var l := Node3D.new()
		l.position = Vector3(-GAP, 0, 0)
		root.add_child(l)
		_build_tool(l, sid)

		# ── 右：实机视角（生产 setup + sync_from_body）──
		var r := Node3D.new()
		r.position = Vector3(GAP, 0, 0)
		root.add_child(r)
		await _build_real(r, sid)

		_add_label(root, Vector3(-GAP, 1.15, 0), "工具里")
		_add_label(root, Vector3(GAP, 1.15, 0), "实机里")
		_add_label(root, Vector3(0, 1.75, 0), "↑ 屏幕上方 = 敌人方向 (−Z)")

		await _wait(8)
		var img := get_viewport().get_texture().get_image()
		img.save_png("user://shot51/%s_CMP.png" % String(sid))
		print("   · %s" % String(sid))
		root.queue_free()
		await _wait(3)
	cam.queue_free()


## 工具视角：与 `probe_bow_box._load_current` 同式（holder.basis = zp · scale）
func _build_tool(parent: Node3D, sid: StringName) -> void:
	var model := MODEL.instantiate(sid)
	if model == null:
		return
	var aabb := _aabb(model)
	var long_len := maxf(aabb.size.x, maxf(aabb.size.y, maxf(aabb.size.z, 1e-4)))
	var sc := 1.0 / long_len
	parent.add_child(model)
	model.basis = VISUAL.zero_pose_basis(sid) * Basis.IDENTITY.scaled(Vector3.ONE * sc)
	model.position = -(sc * aabb.get_center())


## 实机视角：生产 setup() + sync_from_body(aim = −Z)
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


func _add_label(parent: Node3D, pos: Vector3, txt: String) -> void:
	var lb := Label3D.new()
	lb.text = txt
	lb.position = pos
	lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lb.no_depth_test = true
	lb.font_size = 44
	lb.pixel_size = 0.0016
	lb.modulate = Color(1, 0.92, 0.55)
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
