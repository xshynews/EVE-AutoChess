extends Node
## 渲染设置窗（不开 headless），让用户能看见 DEBUG 加币按钮长啥样。
##
## 跑法：
##   "C:/godot/Godot_v4.7.1-stable_win64_console.exe" \
##     --path "F:/evezzq/eve自走棋918" --quit-after 5000 \
##     res://tools/probe_settings_shot.tscn
## 产物：user://settings_with_debug.png  （在 C:/Users/.../AppData/.../EVE自走棋918/）

const SETTINGS_SCRIPT := preload("res://scripts/ui/panels/eve_settings.gd")

var _vp: SubViewport = null
var _cam: Camera2D = null
var _root: Control = null


func _ready() -> void:
	# 1. SubViewport 装一个"伪屏幕"
	#
	# ⚠️ 360×560 是**改后**设置窗的尺寸（320 宽 + 左右各 20 留白）；
	#    窗高由它自己按内容反推（`_fit_height`），这里给足即可。
	_vp = SubViewport.new()
	_vp.size = Vector2i(360, 560)
	_vp.transparent_bg = false
	# own_world_2d 是只读、不需要显式设（默认 true 即可让 Control 用独立 2D 空间）
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp)

	# 2. 一个深色底（避免透明黑难看）
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.09, 0.11, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.position = Vector2.ZERO
	bg.size = _vp.size
	_vp.add_child(bg)

	# 3. 实例化设置窗
	#
	# ⚠️ 只给 x/y/宽 —— 高度由窗自己 `_fit_height()` 反推，
	#    这里写死高度会掩盖「内容变多之后窗底出现空洞」这类问题。
	_root = SETTINGS_SCRIPT.new()
	_root.visible = true
	_root.set_window_rect(20, 16, 320, 520)
	_vp.add_child(_root)
	# ⚠️ 模拟主控打开窗时的回写（show_settings 的 state）——
	#    不喂的话滑杆全是构建默认 1.0，截图会「看起来全是 100%」，
	#    与实机默认（sfx 0.60 / amb 0.39 / music 0.32）对不上。
	await get_tree().process_frame
	_root.set_state({
		"background": "caldari_c07", "mood": 0,
		"fog": false, "rings": true, "board": true,
		"paused": false, "muted": false,
		"volumes": {"master": 1.0, "sfx": 0.60, "amb": 0.39, "music": 0.32},
	})
	await get_tree().process_frame
	await get_tree().process_frame

	# 4. 拿图像
	await RenderingServer.frame_post_draw
	var tex := _vp.get_texture()
	if tex == null:
		print("[SHOT] 拿不到 viewport 纹理")
		get_tree().quit(1)
		return
	var img: Image = tex.get_image()
	if img == null:
		print("[SHOT] 拿不到 image")
		get_tree().quit(1)
		return
	img.save_png("user://settings_with_debug.png")
	print("[SHOT] saved user://settings_with_debug.png  size=%s" % str(img.get_size()))
	get_tree().quit(0)
