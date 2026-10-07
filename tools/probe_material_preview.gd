extends Node

## 探针 —— 材质「还原」在受控光照下的对照渲染
##
## ═══════════════════════════════════════════════════════════════════════
## 为什么不能只靠实机截图
## ═══════════════════════════════════════════════════════════════════════
## 实机（battle_scene）里舰船是**近黑剪影**：
##   环境光 = 常量色 × 0.28、太阳 0.55、补光 0.18；
##   而星云是**几何球幕**（自定义着色器），不是 Sky 资源 ⇒
##   它既不是环境光来源、也不是反射来源，金属**没有东西可反**。
## 于是改前改后都是黑的，看不出材质差别 —— 实测舰船像素均亮
## 0.102 → 0.087，差异被压到噪声量级。那是**光照的问题**，不是材质的问题。
##
## 所以这里另起一个受控台架：把真星云（c07 全景图）挂成 Sky，
## 让它同时当环境光与反射来源，金属就能"被光擦亮"。
##
## ═══════════════════════════════════════════════════════════════════════
## 渲染三张（同一机位、同一光照）
## ═══════════════════════════════════════════════════════════════════════
##   ① 空场景（只有星云）        → 当背景基准，用来精确抠出舰船像素
##   ② 原始 glb 材质（退化）      → metallic = spec 原值
##   ③ ramp 还原材质              → metallic = 0 / 0.80 / 0.95
## ②与③**同一位置**渲染，所以可以逐像素比；①给出舰船掩膜。
##
## 用法（**必须开窗口**）：
##   godot_console.exe --path <工程> --quit-after 400 res://tools/probe_material_preview.tscn

const SHIP := &"punisher"
const SKY_TEX := "res://assets/backgrounds/caldari-c07-nebula-4096.png"
const DIR := "user://mat_preview"

var _cam: Camera3D = null
var _holder: Node3D = null


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	_build_env()
	_build_camera()
	_holder = Node3D.new()
	add_child(_holder)

	await _shot(null, "sky")                 # ① 只有星云
	await _shot(false, "raw")                # ② 原始材质
	await _shot(true, "upgraded")            # ③ 还原材质
	print("[材质预览] 三张已存 ", ProjectSettings.globalize_path(DIR))
	get_tree().quit(0)


func _build_env() -> void:
	var sky_mat := PanoramaSkyMaterial.new()
	var tex: Texture2D = load(SKY_TEX)
	if tex == null:
		push_error("[材质预览] 载不到星云 %s" % SKY_TEX)
	sky_mat.panorama = tex
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_256

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	# ⚠️ 关键：让**天空**同时当环境光与反射来源。
	#    实机那份 Environment 用的是常量环境光 + 几何球幕，
	#    金属因此没有可反的东西 —— 这正是实机里看不出材质差别的原因。
	env.ambient_light_source = Environment.AMBIENT_SOURCE_BG
	env.ambient_light_energy = 1.0
	env.reflected_light_source = Environment.REFLECTION_SOURCE_BG
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.glow_enabled = false
	env.ssao_enabled = false
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	# 主光：给一点方向性，让金属有明确的高光可看
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(0.95, 0.96, 1.0)
	sun.light_energy = 1.1
	sun.rotation_degrees = Vector3(-38, 34, 0)
	sun.shadow_enabled = false
	add_child(sun)


func _build_camera() -> void:
	_cam = Camera3D.new()
	_cam.fov = 42.0
	_cam.position = Vector3(2.1, 2.4, 4.6)
	# ⚠️ 必须先 add_child 再 look_at —— Node3D.look_at 在树外会报
	#    「Node not inside tree. Use look_at_from_position() instead.」
	#    而且**不会抛错中断**，只是相机不动（图还是照存，但构图全错）。
	add_child(_cam)
	_cam.look_at(Vector3.ZERO)
	_cam.make_current()


func _shot(upgrade, tag: String) -> void:
	if _holder.get_child_count() > 0:
		_holder.get_child(0).free()
	if upgrade != null:
		var m := EveShipModel.instantiate(SHIP, bool(upgrade))
		if m == null:
			push_error("[材质预览] 拿不到模型")
			return
		var span := EveShipModel.max_dim_m(SHIP)
		m.scale = Vector3.ONE * (3.0 / span)      # 归一化到 3 世界单位
		# glb 长轴 +X；转成 3/4 视角看侧面（与 eve_ship_visual 的 -PI/2 同源）
		m.rotate_y(-PI / 2.0 + deg_to_rad(38.0))
		m.name = "Ship_%s" % tag
		_holder.add_child(m)
		print("  %-9s 已还原材质=%s  max_dim=%.1f m  缩放=%.4f" % [
				tag, str(EveShipMaterial.is_upgraded(m)), span, 3.0 / span])
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img == null:
		push_error("[材质预览] 拿不到 viewport 图像（headless？）")
		return
	img.save_png("%s/%s.png" % [DIR, tag])
	print("  已存 %s.png  %s" % [tag, img.get_size()])
