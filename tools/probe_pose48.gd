extends Node3D
## 48 轮 · **实机姿态 4 机位对照图**（⚠️ 非 headless：headless 下拿不到 SubViewport 纹理）。
##
## ═══ 它要回答的问题 ═══
##  用户实机报「船全部肚皮朝天」。但代码层已经逐层验证**全部正确**：
##    · `SHIP_AXES` 与用户 17:05~17:10 的标定 52/52 一致
##    · `AXIS_REMAP` 自洽：`M·mesh_rot·up = +Y` 15/15
##    · `zero_pose_basis·up = +Y` 10/10
##    · 端到端（含 model 节点层）`链·up·天 = +1.000` 12/12
##  ⇒ 只剩一种可能：**「up」的语义在代码里与用户眼中不是同一件事**。
##    本探针就是要把它**画出来**给用户看。
##
## ═══ 机位设计（关键：必须有一张能一眼看出正反）═══
##  · `top`   俯视（+Y 往下看）：能看出**翼展平面**与机身，但看不出正反
##  · `front` 正前（从 +X 看）：能看出**机身中轴**与上下厚度分布
##  · `side`  正侧（从 +Z 看）：同上，正交
##  · `offi`  官方观感机位（斜上）
##  ⇒ **能不能判「背朝天」要看 `front` / `side`**（上下两半的厚度差）。
##
## ═══ 坐标口径（红线 42）═══
##  游戏里：敌人恒在世界 **−Z**；相机在我方背后朝 −Z 看 ⇒ 画面上方 = 敌人方向。
##  所以本探针的「正前」机位 = 从 **+Z 朝 −Z 看**（模拟玩家视角）。
##
## ── 跑法（⚠️ 不要加 --headless）──
##   "C:/godot/Godot_v4.7.1-stable_win64_console.exe" \
##     --path "F:/evezzq/eve自走棋918" --quit-after 1200 \
##     res://tools/probe_pose48.tscn -- --ids=abaddon,kestrel
const INDEX := preload("res://scripts/data/eve_ship_asset_index.gd")

const SIZE := 300
const OUT_DIR := "user://pose48"
const CAM_SIZE := 1.45
const PCA_STEP := 7

## 舱位（船被 NORMALIZE 到长轴 = 1.0 世界单位）
const VIEWS := {
	"top": Vector3(0.0, 1.0, 0.0),
	"front": Vector3(0.0, 0.0, 1.0),      # 玩家视角：从 +Z 看向 −Z（敌人方向）
	"side": Vector3(1.0, 0.0, 0.0),
	"offi": Vector3(0.48, 0.37, 0.80),
}

var _size := SIZE
var _out_dir := OUT_DIR
var _ids: PackedStringArray = PackedStringArray()
var _vp: SubViewport = null
var _cam: Camera3D = null
var _holder: Node3D = null


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--size="):
			_size = maxi(64, int(a.substr(7)))
		elif a.begins_with("--dir="):
			_out_dir = "user://" + a.substr(6)
		elif a.begins_with("--ids="):
			_ids = a.substr(6).split(",")
	_build_world()
	await _run()


func _build_world() -> void:
	_vp = SubViewport.new()
	_vp.size = Vector2i(_size, _size)
	_vp.transparent_bg = false
	_vp.own_world_3d = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp)

	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.06, 0.08, 0.12)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.60, 0.70)
	env.ambient_light_energy = 1.3
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	we.environment = env
	_vp.add_child(we)

	var key := DirectionalLight3D.new()
	key.light_energy = 1.9
	key.rotation_degrees = Vector3(-38, -122, 0)
	_vp.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.light_energy = 0.7
	rim.rotation_degrees = Vector3(-18, 64, 0)
	_vp.add_child(rim)

	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.size = CAM_SIZE
	_cam.near = 0.01
	_cam.far = 60.0
	_vp.add_child(_cam)          # look_at 需要节点已在树里

	_holder = Node3D.new()
	_vp.add_child(_holder)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out_dir))
	var rows: Array = []
	for r in INDEX.ROWS:
		if _ids.size() > 0 and not _ids.has(String(r[0])):
			continue
		rows.append(r)
	rows.sort_custom(func(a, b): return String(a[0]) < String(b[0]))
	print("[POSE48] 条数=%d  out=%s" % [rows.size(), _out_dir])
	var ok := 0
	for r in rows:
		var id := StringName(r[0])
		if await _shoot(id):
			ok += 1
	print("[POSE48] 完成 %d / %d" % [ok, rows.size()])
	print("[POSE48] 目录：%s" % ProjectSettings.globalize_path(_out_dir))
	get_tree().quit(0)


func _shoot(id: StringName) -> bool:
	# ── 建船（**用生产代码摆姿态**，见 eve_ship_visual.zero_pose_basis）──
	var holder := Node3D.new()
	_holder.add_child(holder)
	var model := EveShipModel.instantiate(id)
	if model == null:
		print("[POSE48] %s 载入失败" % id)
		holder.queue_free()
		return false
	holder.add_child(model)
	var span := EveShipModel.max_dim_m(id)
	if span <= 0.001:
		holder.queue_free()
		return false
	var s := 1.0 / span                     # 长轴归一化到 1.0
	# ⚠️ 顺序：先 basis 后 scale（反了缩放被静默清成 1）
	model.basis = EveShipVisual.zero_pose_basis(id)
	model.scale = Vector3.ONE * s

	await get_tree().process_frame
	await get_tree().process_frame

	for vname in VIEWS:
		var dirv: Vector3 = VIEWS[vname]
		# top 机位：up 不能用 +Y（与视线平行 ⇒ look_at 退化）
		var upv := Vector3.UP
		if absf(dirv.normalized().dot(Vector3.UP)) > 0.99:
			upv = Vector3(0.0, 0.0, -1.0)    # 俯视时用「敌人方向」当画面上方
		_cam.position = dirv.normalized() * 10.0
		_cam.look_at(Vector3.ZERO, upv)
		await get_tree().process_frame
		await get_tree().process_frame
		var img: Image = _vp.get_texture().get_image()
		img.save_png("%s/%s_%s.png" % [_out_dir, String(id), vname])
	holder.queue_free()
	await get_tree().process_frame
	return true
