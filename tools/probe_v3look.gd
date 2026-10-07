extends Node

## 布阵视觉实验（一次性）—— 回答两个问题，全部用实拍数据说话
##
## ══════════════════════════════════════════════════════════════════
##  ① 取景该放大几倍？（用户：「船现在还是小……就拉大两倍棋盘」）
##     扫 arena.board_view_zoom = 1.0 / 1.4 / 2.0，同机位同 yaw 同船。
## ══════════════════════════════════════════════════════════════════
##  ② 船为什么暗、怎么调亮？
##     现状：Environment.background_mode = BG_COLOR（可见背景是纯色），
##     ⇒ reflected_light_source 默认取「背景」= 一块近黑纯色
##     ⇒ **金属件没有任何东西可反射**，只能靠两盏平行光的直接照明。
##     再加上 ambient 只有 0.28（颜色又很暗），背光面几乎全黑。
##     本探针逐一试：提环境光 / 提主光 / 加相机头灯 / 让天空盒参与 IBL。
##
## 跑法：
##   "C:/godot/Godot_v4.7.1-stable_win64_console.exe" \
##     --path "F:/evezzq/eve自走棋918" --quit-after 1200 res://tools/probe_v3look.tscn
##
## 产物（user://）：
##   v3_zoom_100.png / v3_zoom_140.png / v3_zoom_200.png
##   v3_lt_<方案>.png          每个亮度方案一张
##   v3_no_ships.png           无船参照帧（给差分用；背景是 unshaded，不受灯光影响）
##   v3_look_report.txt

const SCENE_PATH := "res://scenes/battle_scene.tscn"
const BG_TEX := "res://assets/backgrounds/caldari-c07-nebula-4096.png"

## 取景放大档
const ZOOM_CASES := [1.0, 1.4, 2.0]

## 亮度方案（顺序 = 报告里的顺序）
const LIGHT_CASES := [
	{"id": "base", "note": "现状：ambient 0.28 / sun 0.55 / fill 0.18"},
	{"id": "amb", "note": "环境光 0.28→0.60 且颜色提亮 (0.34,0.42,0.50)"},
	{"id": "amb_hi", "note": "环境光 0.28→0.95 且颜色 (0.40,0.50,0.60)（看上限在哪）"},
	{"id": "sun", "note": "主光 0.55→1.10（其余不动）"},
	{"id": "head", "note": "加相机头灯：跟随相机的平行光 0.55"},
	{"id": "sky", "note": "天空盒参与 IBL：ambient 源=SKY、反射源=SKY、能量 0.6"},
	{"id": "mix", "note": "环境光 0.55 + 主光 0.95 + 头灯 0.40"},
	{"id": "sky_mix", "note": "天空盒 IBL 0.5 + 主光 0.95 + 头灯 0.40"},
]

var _battle: Node = null
var _arena: Variant = null
var _cam: Camera3D = null
var _env: Environment = null
var _sun: DirectionalLight3D = null
var _fill: DirectionalLight3D = null
var _head: DirectionalLight3D = null
var _ships_layer: Node3D = null
var _lines: Array[String] = []


func _ready() -> void:
	var packed: PackedScene = load(SCENE_PATH)
	_battle = packed.instantiate()
	add_child(_battle)
	for _i in 45:
		await get_tree().process_frame

	_arena = _battle.get("arena")
	_cam = _arena.get("camera")
	_ships_layer = _arena.get("ships_layer")

	var we: WorldEnvironment = _arena.get_node_or_null("WorldEnvironment")
	_env = we.environment if we != null else null
	for c in _arena.get_children():
		if c is DirectionalLight3D:
			if _sun == null:
				_sun = c
			else:
				_fill = c

	# 相机头灯（默认熄灭）—— 挂在相机下，方向 = 相机朝向
	_head = DirectionalLight3D.new()
	_head.name = "ProbeHeadLight"
	_head.light_color = Color(0.86, 0.90, 0.96)
	_head.light_energy = 0.0
	_head.shadow_enabled = false
	_cam.add_child(_head)

	_put_ships_on_board()
	for _i in 24:
		await get_tree().process_frame

	# 布阵取景 + 正对机位（两次实验都锁死这两个变量）
	_arena.board.set_board_visible(true)
	_arena.frame_own_zone()
	_arena.orion_cam.set("yaw", 0.0)
	_arena.orion_cam.call("apply_to_camera")
	for _i in 10:
		await get_tree().process_frame

	await _run_zoom_cases()
	await _run_light_cases()

	var f := FileAccess.open("user://v3_look_report.txt", FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(_lines))
		f.close()
	get_tree().quit(0)


## 往棋盘上放 4 艘船（跨 4 列，便于比较「船 / 格」的比例）
func _put_ships_on_board() -> void:
	var st = _battle.get("run")
	st.coin = 400
	st.level = 6                      # 上场上限 8，够放 4 艘
	for i in 6:
		st.buy(i % 5)
	for i in 4:
		if st.bench.size() > 0:
			st.deploy_from_bench(0, 8, 2 + i)
	_lines.append("上场 %d 艘 · 备战席 %d 艘" % [st.field.size(), st.bench.size()])


# ------------------------------------------------------------------ ① 取景档

func _run_zoom_cases() -> void:
	_lines.append("")
	_lines.append("═══ ① 取景放大档（同机位同一批船）═══")
	for z in ZOOM_CASES:
		_arena.board_view_zoom = float(z)
		_arena.frame_own_zone()
		_arena.orion_cam.set("yaw", 0.0)
		_arena.orion_cam.call("apply_to_camera")
		for _i in 6:
			await get_tree().process_frame
		_report_zoom(float(z))
		await _shot("v3_zoom_%d" % int(round(float(z) * 100.0)))
	# 复位到默认档
	_arena.board_view_zoom = _arena.get("board_view_zoom")


func _report_zoom(z: float) -> void:
	var b: Variant = _arena.board
	var h: float = float(b.half)
	# 一格在屏幕上的宽 / 高
	var c0 := _proj(b, Vector3(0.0, 0.0, 0.0))
	var c1 := _proj(b, Vector3(float(b.cell), 0.0, 0.0))
	var c2 := _proj(b, Vector3(0.0, 0.0, float(b.cell)))
	# 棋盘四角 → 是否还在画幅内
	var nl := _proj(b, Vector3(-h, 0.0, h))
	var nr := _proj(b, Vector3(h, 0.0, h))
	var fl := _proj(b, Vector3(-h, 0.0, -h))
	var fr := _proj(b, Vector3(h, 0.0, -h))
	var w := float(get_viewport().get_visible_rect().size.x)
	var hh := float(get_viewport().get_visible_rect().size.y)
	var in_frame := 0
	for p in [nl, nr, fl, fr]:
		if p.x >= 0.0 and p.x <= w and p.y >= 0.0 and p.y <= hh:
			in_frame += 1
	_lines.append("zoom %.2f  相机距离 %.1f  一格 %.1f x %.1f px  (宽高比 %.2f)"
			% [z, float(_arena.orion_cam.call("get_distance")),
			(c1 - c0).length(), (c2 - c0).length(),
			(c1 - c0).length() / maxf(1.0, (c2 - c0).length())])
	_lines.append("           棋盘四角在画幅内 %d/4 · 近端横边 x=%.0f..%.0f（画幅 0..%.0f）"
			% [in_frame, nl.x, nr.x, w])


# ------------------------------------------------------------------ ② 亮度方案

func _run_light_cases() -> void:
	_lines.append("")
	_lines.append("═══ ② 亮度方案（zoom 固定 2.0 · 机位固定）═══")
	# 无船参照帧：背景是 unshaded，不受任何灯光影响 → 一份就够
	_ships_layer.visible = false
	for _i in 4:
		await get_tree().process_frame
	await _shot("v3_no_ships")
	_ships_layer.visible = true
	for _i in 4:
		await get_tree().process_frame

	for c in LIGHT_CASES:
		_apply_light(String(c["id"]))
		for _i in 5:
			await get_tree().process_frame
		_lines.append("  %-9s %s" % [String(c["id"]), String(c["note"])])
		await _shot("v3_lt_%s" % String(c["id"]))


## 每个方案都【先从基线复位】再改 —— 否则会互相污染（尤其是 sky / head）
func _apply_light(id: String) -> void:
	if _env != null:
		_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		_env.ambient_light_color = Color(0.22, 0.28, 0.33)
		_env.ambient_light_energy = 0.28
		_env.set("reflected_light_source", 0)     # 0 = 取背景（= 近黑纯色）
		_env.sky = null
	if _sun != null:
		_sun.light_energy = 0.55
	if _head != null:
		_head.light_energy = 0.0

	match id:
		"base":
			pass
		"amb":
			_env.ambient_light_color = Color(0.34, 0.42, 0.50)
			_env.ambient_light_energy = 0.60
		"amb_hi":
			_env.ambient_light_color = Color(0.40, 0.50, 0.60)
			_env.ambient_light_energy = 0.95
		"sun":
			_sun.light_energy = 1.10
		"head":
			_head.light_energy = 0.55
		"sky":
			_setup_sky_ibl(0.60)
		"mix":
			_env.ambient_light_color = Color(0.32, 0.40, 0.48)
			_env.ambient_light_energy = 0.55
			_sun.light_energy = 0.95
			_head.light_energy = 0.40
		"sky_mix":
			_setup_sky_ibl(0.50)
			_sun.light_energy = 0.95
			_head.light_energy = 0.40


## 让天空盒参与 IBL：反射与环境光都取自全景图，而【可见背景仍由
## EveBackground 的球幕负责】（background_mode 保持 BG_COLOR，球幕照常画）。
##
## 这才是这艘船「暗」的正解：现在 reflected_light_source 取的是
## 一块近黑纯色背景 —— 金属件没东西可反射，只能靠直接光。
func _setup_sky_ibl(energy: float) -> void:
	if _env == null:
		return
	var tex: Texture2D = load(BG_TEX)
	if tex == null:
		_lines.append("    ⚠️ 背景贴图缺失，IBL 方案跳过")
		return
	var pm := PanoramaSkyMaterial.new()
	pm.panorama = tex
	pm.energy_multiplier = 0.86
	var sky := Sky.new()
	sky.sky_material = pm
	_env.sky = sky
	_env.set("reflected_light_source", 2)          # 2 = 取天空（SKY）
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	_env.ambient_light_sky_contribution = 1.0
	_env.ambient_light_energy = energy


# ------------------------------------------------------------------ 工具

func _proj(board: Variant, local: Vector3) -> Vector2:
	var w: Vector3 = board.to_global(local) if board.is_inside_tree() else local
	return _cam.unproject_position(w)


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img == null:
		_lines.append("    ⚠️ 截图失败 %s" % name)
		return
	img.save_png("user://%s.png" % name)
