extends Node

## 出图 + 量数：① 战场设置窗（含分辨率块）是否整扇在屏内
##              ② 牌桌设置窗（lounge 档案）长什么样
##              ③ 4:3（1920×1200）下牌桌内容是否居中、背景是否铺满
##              ④ 4:3 下主菜单内容是否居中、底图是否还铺得满
##
## ⛔ 必须**非无头**：分辨率块只在桌面端构建，无头下根本不建（见 `EveResolution.is_enabled`）。
##
## 跑法：
##   "C:/godot/Godot_v4.7.2-stable_win64_console.exe" \
##     --path "F:/evezzq/eve自走棋918" --quit-after 8000 res://tools/probe_display_layout.tscn
## 产物：user://shot_settings_battle.png · shot_lounge_settings.png
##       · shot_table_43.png · shot_menu_43.png

const HUD_SCRIPT := preload("res://scripts/ui/eve_hud_root.gd")
const DDZ := preload("res://scenes/doudizhu.tscn")
const MENU := preload("res://scenes/main_menu.tscn")


func _ready() -> void:
	# ★ 顺带量一下窗口标题 —— 它由 `application/config/name` 决定，
	#   而那一项 2026-10-07 从「EVE自走棋918」改成了「EVE 自走棋」（红线：918）。
	#   ⛔ 这里只读不写：标题必须来自项目设置，别用 `title = ...` 盖掉（那就验不出来了）。
	print("[disp] 窗口标题 = 「%s」（期望「EVE 自走棋」）" % get_window().title)
	await _battle_settings()
	await _lounge_settings()
	await _table_43()
	await _menu_43()
	get_tree().quit()


func _battle_settings() -> void:
	var vp := _mk_vp(1920, 1080)
	var hud: Variant = HUD_SCRIPT.new()
	vp.add_child(hud)
	await _frames(3)
	hud.show_settings({
		"background": "caldari_c07", "mood": 0,
		"fog": false, "rings": true, "board": true,
		"paused": false, "muted": false,
		"volumes": {"master": 1.0, "sfx": 0.60, "amb": 0.39, "music": 0.32},
		"ui_scale": 0.0, "font_scale": 1.10,
	})
	await _frames(6)
	var sw: Variant = hud.get("settings_window")
	print("[disp] 战场设置窗  pos=%s  size=%s  底边=%.0f / 屏高 1080"
			% [str(sw.position), str(sw.size), sw.position.y + sw.size.y])
	print("[disp]   分辨率按钮=%d 个" % sw.get("_res_btns").size())
	await _shoot(vp, "shot_settings_battle.png")
	vp.queue_free()
	await _frames(2)


func _lounge_settings() -> void:
	var vp := _mk_vp(1920, 1080)
	var t: Variant = DDZ.instantiate()
	vp.add_child(t)
	await _frames(4)
	t.call("_new_game", 20261007)
	t.call("_toggle_settings")
	await _frames(6)
	var sw: Variant = t.get("_settings")
	print("[disp] 牌桌设置窗  pos=%s  size=%s  底边=%.0f"
			% [str(sw.position), str(sw.size), sw.position.y + sw.size.y])
	await _shoot(vp, "shot_lounge_settings.png")
	vp.queue_free()
	await _frames(2)


func _table_43() -> void:
	var vp := _mk_vp(1920, 1200)
	var t: Variant = DDZ.instantiate()
	vp.add_child(t)
	await _frames(4)
	t.call("_new_game", 20261007)
	t.call("_do_bid", 0, 3)
	await _frames(4)
	print("[disp] 4:3 牌桌  size=%s  偏移=%s" % [str(t.size), str(t.call("_ui_origin"))])
	await _shoot(vp, "shot_table_43.png")
	vp.queue_free()
	await _frames(2)


func _menu_43() -> void:
	var vp := _mk_vp(1920, 1200)
	var m: Variant = MENU.instantiate()
	vp.add_child(m)
	await _frames(6)
	print("[disp] 4:3 主菜单  size=%s  内容层 pos=%s size=%s"
			% [str(m.size), str(m.get("_content").position), str(m.get("_content").size)])
	await _shoot(vp, "shot_menu_43.png")
	vp.queue_free()
	await _frames(2)


func _mk_vp(w: int, h: int) -> SubViewport:
	var vp := SubViewport.new()
	vp.size = Vector2i(w, h)
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	return vp


func _shoot(vp: SubViewport, file: String) -> void:
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	img.save_png("user://" + file)
	print("[disp] → %s" % ProjectSettings.globalize_path("user://" + file))


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
