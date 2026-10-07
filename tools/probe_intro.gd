extends Node

## 开场剧情出图探针（**非无头**）
##
## 跑法：
##   "C:/godot/Godot_v4.7.1-stable_win64_console.exe" \
##     --path "F:/evezzq/eve自走棋918" --quit-after 900 \
##     res://tools/probe_intro.tscn
##
## 产物在 `user://`（= %APPDATA%\Godot\app_userdata\EVE自走棋918\）
##
## ⚠️ 每个状态用一个**新的 SubViewport** —— 复用同一个会把上一个状态的控件叠在里面。
## ⚠️ 必须等 `RenderingServer.frame_post_draw` 才拿得到画好的那一帧。

const INTRO_SCENE := preload("res://scenes/intro_scene.tscn")
const SCRIPT := preload("res://scripts/data/eve_intro_script.gd")

const SHOTS := [
	[1.20,  "intro_1_片头（应整屏无UI）"],
	[3.60,  "intro_2_第2句·玩家"],
	[10.60, "intro_3_第6句·斥候"],
	[22.20, "intro_4_展开前（收起态）"],
	[24.10, "intro_5_展开中"],
	[25.80, "intro_6_展开完成+任务提示"],
]


func _ready() -> void:
	print("=".repeat(60))
	print("开场出图探针（1920×1080 锁死）")
	print("=".repeat(60))
	for shot in SHOTS:
		await _one(float(shot[0]), String(shot[1]))
	print("完成。产物在 user:// 下")
	get_tree().quit()


func _one(t: float, file: String) -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(1920, 1080)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.transparent_bg = false
	add_child(vp)

	var intro: Variant = INTRO_SCENE.instantiate()
	vp.add_child(intro)
	intro.process_mode = Node.PROCESS_MODE_DISABLED
	await get_tree().process_frame
	await get_tree().process_frame

	intro.seek(t)
	# 让 Tween / SubViewport 有机会真正渲染出来
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw

	var img := vp.get_texture().get_image()
	img.save_png("user://%s.png" % file)
	print("  [%.2fs] → %s.png  %s" % [t, file, str(img.get_size())])
	vp.queue_free()
	await get_tree().process_frame
