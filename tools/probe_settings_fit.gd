extends Node

## 量「设置窗底部到底空了多少」—— 真 HUD 路径下的复现。
##
## ⚠️ 为什么不能直接信 `probe_settings_shot`：那个探针把窗**单独**塞进 SubViewport，
##    而实机走的是 `EveHudRoot` 的 `add_child → set_window_rect → show_settings` 这条链。
##    两者在「布局第一帧时窗口宽度是否已定」上不同 —— 而带 autowrap 的 Label 的
##    最小高度**恰好取决于当时拿到的宽度**（宽度越窄 ⇒ 折行越多 ⇒ 最小高度越大）。
##
## 跑法：
##   "C:/godot/Godot_v4.7.1-stable_win64_console.exe" --headless \
##     --path "F:/evezzq/eve自走棋918" --quit-after 3000 res://tools/probe_settings_fit.tscn

const HUD_SCRIPT := preload("res://scripts/ui/eve_hud_root.gd")

var _vp: SubViewport = null


func _ready() -> void:
	_vp = SubViewport.new()
	_vp.size = Vector2i(1920, 1080)
	_vp.transparent_bg = false
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp)

	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.09, 0.11, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.size = _vp.size
	_vp.add_child(bg)

	var hud = HUD_SCRIPT.new()
	_vp.add_child(hud)
	await get_tree().process_frame
	await get_tree().process_frame
	hud.show_settings({
		"background": "caldari_c07", "mood": 0,
		"fog": false, "rings": true, "board": true,
		"paused": false, "muted": false,
		"volumes": {"master": 1.0, "sfx": 0.60, "amb": 0.39, "music": 0.32},
	})
	await get_tree().process_frame
	await get_tree().process_frame

	var sw = hud.get("settings_window")
	_report(sw, "收起态")

	# 出一张「真 HUD 环境」的图：单独塞进 SubViewport 的截图象不了
	# 「窗在 1080p 屏幕上占多大」这件事 —— 而这次的病恰好只在真 HUD 路径下出现。
	await RenderingServer.frame_post_draw
	var img := _vp.get_texture().get_image()
	if img != null:
		img.save_png("user://settings_hud.png")
		print("[FIT] 已存 user://settings_hud.png  size=%s" % str(img.get_size()))

	# DEBUG 展开：折叠条是新增的，展开后窗高必须跟着长、且同样不留空白
	var dbg_btn = sw.get("_dbg_btn")
	if dbg_btn != null:
		dbg_btn.emit_signal("pressed")
		await get_tree().process_frame
		await get_tree().process_frame
		_report(sw, "DEBUG 展开")
		dbg_btn.emit_signal("pressed")
		await get_tree().process_frame
		await get_tree().process_frame
		_report(sw, "再收起")

	get_tree().quit(0)


func _report(sw, tag: String) -> void:
	var content = sw.get("content")
	var margin = sw.get("_content_margin")
	var last_bottom := 0.0
	for c in content.get_children():
		if not bool(c.get("visible")):
			continue
		last_bottom = maxf(last_bottom, float(c.get("position").y + c.get("size").y))
	var abs_last := float(margin.position.y + content.position.y + last_bottom)
	print("[FIT·%s] 窗高 %.1f · content min %.1f · 最后控件底 %.1f ⇒ 空白 %.1f"
			% [tag, float(sw.size.y), float(content.get_combined_minimum_size().y),
			abs_last, float(sw.size.y) - abs_last])
