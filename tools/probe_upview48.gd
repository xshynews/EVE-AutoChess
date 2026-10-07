extends Node3D
## 48 轮 · **实机视角对照图**（⚠️ 非 headless）。
##
## ═══ 要回答的问题 ═══
##  引擎世界量说：`up · (0,1,0) = +1.000`（船背朝天）。
##  用户实机说：**肚皮朝天**。
##  两者矛盾 ⇒ 只可能是「`SHIP_AXES` 的 up 标反了」——
##  表里的 `up:+Y` 其实是船**腹**，而工具用同一张表摆轴杆 ⇒ 怎么看都自洽。
##
## ═══ 本探针的做法 ═══
##  用**游戏生产代码**摆船（`zero_pose_basis`），机位放在**我方阵营后上方**
##  （复刻用户实机视角：相机在 +Z 侧朝 −Z 看，画面上方 = 敌人方向）。
##  同时在场景里放一个**明确的天上标记**（世界 +Y 处一颗亮球 + 一条竖线），
##  这样图里能直接看出「船的哪一面朝着天上标记」。
##
## ── 跑法（⚠️ 不要加 --headless）──
##   "C:/godot/Godot_v4.7.1-stable_win64_console.exe" \
##     --path "F:/evezzq/eve自走棋918" --quit-after 900 \
##     res://tools/probe_upview48.tscn -- --ids=abaddon,kestrel --dir=upview48
const INDEX := preload("res://scripts/data/eve_ship_asset_index.gd")

const SIZE := 420
const OUT_DIR := "user://upview48"

var _size := SIZE
var _out_dir := OUT_DIR
var _ids: PackedStringArray = PackedStringArray()
var _vp: SubViewport = null
var _cam: Camera3D = null
var _stage: Node3D = null


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--size="):
			_size = maxi(64, int(a.substr(7)))
		elif a.begins_with("--dir="):
			_out_dir = "user://" + a.substr(6)
		elif a.begins_with("--ids="):
			_ids = a.substr(6).split(",")
	_build()
	await _run()


func _build() -> void:
	_vp = SubViewport.new()
	_vp.size = Vector2i(_size, _size)
	_vp.own_world_3d = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp)

	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.07, 0.11)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.66, 0.74)
	env.ambient_light_energy = 1.5
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	we.environment = env
	_vp.add_child(we)

	var key := DirectionalLight3D.new()
	key.light_energy = 2.0
	key.rotation_degrees = Vector3(-42, -118, 0)
	_vp.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.light_energy = 0.8
	fill.rotation_degrees = Vector3(-20, 70, 0)
	_vp.add_child(fill)

	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.size = 2.1
	_cam.near = 0.01
	_cam.far = 80.0
	_vp.add_child(_cam)

	_stage = Node3D.new()
	_vp.add_child(_stage)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out_dir))
	var rows: Array = []
	for r in INDEX.ROWS:
		if _ids.size() > 0 and not _ids.has(String(r[0])):
			continue
		rows.append(r)
	rows.sort_custom(func(a, b): return String(a[0]) < String(b[0]))
	print("[UPVIEW48] 条数=%d → %s" % [rows.size(), _out_dir])
	for r in rows:
		await _shoot(StringName(r[0]))
	print("[UPVIEW48] 目录：%s" % ProjectSettings.globalize_path(_out_dir))
	get_tree().quit(0)


func _shoot(id: StringName) -> void:
	var root := Node3D.new()
	_stage.add_child(root)

	# ── 船：生产代码摆姿态 ──
	var model := EveShipModel.instantiate(id)
	if model == null:
		print("[UPVIEW48] %s 载入失败" % id); root.queue_free(); return
	root.add_child(model)
	var span := EveShipModel.max_dim_m(id)
	if span <= 0.001:
		root.queue_free(); return
	model.basis = EveShipVisual.zero_pose_basis(id)   # ⚠️ 先 basis
	model.scale = Vector3.ONE * (1.0 / span)          # 再 scale

	# ── 天上标记：世界 +Y 处一颗亮球 + 竖线（红线 42 语境：敌人恒在 −Z）──
	var up_mark := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.06
	sph.height = 0.12
	up_mark.mesh = sph
	var m_up := StandardMaterial3D.new()
	m_up.albedo_color = Color(0.2, 1.0, 0.35)
	m_up.emission_enabled = true
	m_up.emission = Color(0.2, 1.0, 0.35)
	m_up.emission_energy_multiplier = 3.0
	up_mark.material_override = m_up
	up_mark.position = Vector3(0.62, 0.62, 0.0)     # 世界 +Y 侧
	root.add_child(up_mark)

	# ── 敌人方向标记：世界 −Z 处一颗红球 ──
	var enemy_mark := MeshInstance3D.new()
	enemy_mark.mesh = sph.duplicate()
	var m_en := StandardMaterial3D.new()
	m_en.albedo_color = Color(1.0, 0.25, 0.25)
	m_en.emission_enabled = true
	m_en.emission = Color(1.0, 0.25, 0.25)
	m_en.emission_energy_multiplier = 3.0
	enemy_mark.material_override = m_en
	enemy_mark.position = Vector3(0.0, 0.0, -0.75)   # 世界 −Z = 敌人
	root.add_child(enemy_mark)

	await get_tree().process_frame
	await get_tree().process_frame

	# 机位：我方后上方（相机在 +Z 侧、略高，朝 −Z 看）= 复刻实机视角
	_cam.position = Vector3(0.0, 0.85, 2.3)
	_cam.look_at(Vector3(0.0, 0.0, 0.0), Vector3.UP)
	await get_tree().process_frame
	await get_tree().process_frame
	_vp.get_texture().get_image().save_png("%s/%s_view.png" % [_out_dir, String(id)])

	# 机位 2：正侧（从 +X 看）—— 上下厚度差最清楚
	_cam.position = Vector3(2.6, 0.0, 0.0)
	_cam.look_at(Vector3(0.0, 0.0, 0.0), Vector3.UP)
	await get_tree().process_frame
	await get_tree().process_frame
	_vp.get_texture().get_image().save_png("%s/%s_side.png" % [_out_dir, String(id)])

	root.queue_free()
	await get_tree().process_frame
