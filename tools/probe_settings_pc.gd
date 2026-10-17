extends Node

## 一次性出图探针（非无头）：2026-10-13「设置更新同步到 PC 端」的实机验证。
##   PC（桌面档）战场 / 牌桌两处设置窗 = 与手机同一套栏目窗
##   （半屏宽 960 + 定高 560 + 底栏常驻返回），矩形照 HUD `_refresh_rect_tbl`
##   的口径用 `settings_rect()` 摆。
## 跑法："$GODOT_BIN" --path . --quit-after 6000 res://tools/probe_settings_pc.tscn
## 产物：user://pc_settings_battle.png / pc_settings_lounge.png

const SETTINGS_SCRIPT := preload("res://scripts/ui/panels/eve_settings.gd")
const HUD_SCRIPT := preload("res://scripts/ui/eve_hud_root.gd")


func _ready() -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(1920, 1080)
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)

	for conf in [[SETTINGS_SCRIPT.PROFILE_BATTLE, "pc_settings_battle.png"],
			[SETTINGS_SCRIPT.PROFILE_LOUNGE, "pc_settings_lounge.png"]]:
		var sw: EveWindow = SETTINGS_SCRIPT.new()
		sw.profile = String(conf[0])
		sw.layout_key = "probe_%s" % String(conf[0])
		vp.add_child(sw)
		await get_tree().process_frame
		# 与 HUD 桌面档同一套矩形（settings_rect 是唯一真源）
		var r: Rect2 = HUD_SCRIPT.settings_rect(Vector2(1920, 1080))
		sw.set_window_rect(r.position.x, r.position.y, r.size.x, r.size.y)
		sw.set_state({"muted": false, "volumes": {}})
		sw.visible = true
		for _i in 3:
			await get_tree().process_frame
		await _shoot(vp, String(conf[1]))
		sw.visible = false
	get_tree().quit()


func _shoot(vp: SubViewport, file: String) -> void:
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	var path := "user://" + file
	img.save_png(path)
	print("[probe] %s" % ProjectSettings.globalize_path(path))
