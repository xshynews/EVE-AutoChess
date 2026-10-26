extends Node

## 主界面出图探针（非无头）—— 三个状态各出一张。
##
## 为什么用 SubViewport 而不是截图整个窗口：
##   真窗尺寸会被屏幕分辨率改写，量不出 1920x1080 的定稿效果。
##   SubViewport 锁死 1920x1080，与设计稿同口径。
##
## 跑法：
##   "$GODOT_BIN" \
##     --path . --quit-after 6000 \
##     res://tools/probe_main_menu.tscn
## 产物：user://main_menu_*.png
##
## ★ 2026-10-25：加 `-- --measure` 走**手机档量窗**（MuMu「难度长条出界」排查用），
##   见 `_measure_mobile_menus()`。

## ⚠️ 必须实例化**真场景**：曾经这里写 MENU_SCRIPT.new()，那是个没设锚点的裸 Control
##    （尺寸 0x0）⇒ 锚满父节点的底图 TextureRect 等于没画，整张图全黑。
const MENU_SCENE := preload("res://scenes/main_menu.tscn")
const FONT := preload("res://scripts/ui/eve_font.gd")

# ⚠️ `mode` 写的是**模式 id**，⛔ 不是下标 —— 用下标的话，
#    模式列表一增删（2026-10-06 加了「棋牌室」）这里就会静默拍错界面。
const SHOTS := [
	{"file": "main_menu_1_campaign.png", "mode": "campaign", "tier": 0},
	{"file": "main_menu_2_tier2.png", "mode": "campaign", "tier": 1},
	{"file": "main_menu_3_endless.png", "mode": "endless", "tier": 0},
	{"file": "main_menu_4_cardroom.png", "mode": "cardroom", "tier": 0},
	# ★ 2026-10-10 右上角「设置」窗打开态（PROFILE_MENU 档案）。
	{"file": "main_menu_5_settings.png", "mode": "campaign", "tier": 0, "settings": true},
]


func _ready() -> void:
	if "--measure" in OS.get_cmdline_user_args():
		await _measure_mobile_menus()
		get_tree().quit()
		return
	if "--measure-desktop" in OS.get_cmdline_user_args():
		await _measure_desktop_menu()
		get_tree().quit()
		return
	for shot in SHOTS:
		var vp := SubViewport.new()
		vp.size = Vector2i(1920, 1080)
		vp.transparent_bg = false
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(vp)

		# ⚠️ 类型写成 Variant：Control 类型的变量上写 `menu._foo()` 会解析失败
		var menu: Variant = MENU_SCENE.instantiate()
		vp.add_child(menu)
		await get_tree().process_frame

		# 切到目标状态（菜单自己的私有方法，探针直接调）
		# 按 id 找下标（列表会增删，⛔ 不写死位置）
		var mi := 0
		for k in menu._modes.size():
			if String(menu._modes[k]["id"]) == String(shot["mode"]):
				mi = k
				break
		menu._on_mode_pressed(mi)
		if int(shot["tier"]) != 0:
			menu._pick["campaign"] = int(shot["tier"])
			menu._refresh_strips()
		# ★ 2026-10-10 右上角「设置」窗（打开态出图）
		if bool(shot.get("settings", false)):
			menu._toggle_settings()
		await get_tree().process_frame
		await get_tree().process_frame
		await RenderingServer.frame_post_draw

		var img := vp.get_texture().get_image()
		var path := "user://" + String(shot["file"])
		img.save_png(path)
		print("[probe] %s  %dx%d" % [path, img.get_width(), img.get_height()])
		vp.queue_free()
		await get_tree().process_frame

	get_tree().quit()


## ★ 2026-10-25（MuMu 实机「难度长条出界」量窗）：
##   在**手机档**下把主菜单摆进不同设计空间，量「卡片条右/下边界 vs 屏」。
##   假设：列数按 4 算时单卡宽 < 卡片内容最小宽，PanelContainer 自己涨宽 ⇒ 冲出屏。
## ⚠️ 设计空间 = 逻辑视口 ÷ 1.35（`EveUiScale.MOBILE`），下面喂的就是设计空间。
func _measure_mobile_menus() -> void:
	const UI_SCALE := preload("res://scripts/ui/eve_ui_scale.gd")
	var old := UI_SCALE.force_mobile
	UI_SCALE.force_mobile = true
	for d in [Vector2i(1920, 1080), Vector2i(1784, 800), Vector2i(1422, 800),
			Vector2i(1226, 711), Vector2i(948, 533), Vector2i(759, 337)]:
		var vp := SubViewport.new()
		vp.size = d
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(vp)
		var menu: Variant = MENU_SCENE.instantiate()
		vp.add_child(menu)
		await get_tree().process_frame
		await get_tree().process_frame
		var grid: Dictionary = menu._layout_of("campaign")
		var row: Control = menu._strip_row
		var cards: Array = menu._cards_of(menu._mode_idx)
		var minx := 0.0
		var miny := 0.0
		var widths: Array = []
		for c in row.get_children():
			minx = maxf(minx, (c as Control).get_combined_minimum_size().x)
			miny = maxf(miny, (c as Control).get_combined_minimum_size().y)
			widths.append(round((c as Control).size.x))
		var right: float = row.position.x + row.size.x
		var bottom: float = row.position.y + row.size.y
		print("[measure] 设计空间 %s ⇒ cols=%d w=%.0f h=%.0f · 卡片最小 %s"
				% [str(d), int(grid["cols"]), float(grid["w"]), float(grid["h"]),
					str(Vector2(minx, miny))])
		print("[measure]   条 pos=%s size=%s ⇒ 右 %.1f/%.1f %s · 底 %.1f/%.1f %s"
				% [str(row.position), str(row.size), right, float(d.x),
					"出界" if right > float(d.x) + 0.5 else "在内",
					bottom, float(d.y),
					"出界" if bottom > float(d.y) + 0.5 else "在内"])
		print("[measure]   卡片 %d 张 · 实际宽 %s · 字号档 %.2f"
				% [cards.size(), str(widths), float(FONT.scale)])
		var img2 := vp.get_texture().get_image()
		if img2 != null:
			img2.save_png("user://menu_m_%dx%d.png" % [d.x, d.y])
		if row.get_child_count() > 0:
			var p: Control = row.get_child(0)
			var host: Control = p.get_child(0)
			var mn: Control = host.get_child(0)
			var col: Control = mn.get_child(0)
			var btn: Control = null
			for i in col.get_child_count():
				var c2: Control = col.get_child(i)
				if c2 is HBoxContainer and c2.get_child_count() > 0 \
						and c2.get_child(0) is Button:
					btn = c2.get_child(0)
			print("[measure]   卡内内容最小 %s · 可用 %s ⇒ %s · 按钮底 %.0f/%0.f"
					% [str(col.get_combined_minimum_size().y), str(host.size.y),
						"放得下" if col.get_combined_minimum_size().y <= host.size.y + 0.5
							else "★ 被裁",
						btn.position.y + btn.size.y if btn != null else -1.0,
						host.size.y])
		vp.queue_free()
		await get_tree().process_frame
	UI_SCALE.force_mobile = old


## 桌面档量窗（回归护栏）：1920×1080 下 4 张难度卡必须排成一行、
## 卡片宽度 ≥ 内容最小宽（否则新的「内容宿主裁剪」会把文字截掉）。
func _measure_desktop_menu() -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(1920, 1080)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var menu: Variant = MENU_SCENE.instantiate()
	vp.add_child(menu)
	await get_tree().process_frame
	await get_tree().process_frame
	var grid: Dictionary = menu._layout_of("campaign")
	var row: Control = menu._strip_row
	var minx := 0.0
	var widths: Array = []
	for c in row.get_children():
		var p := c as Control
		var host: Control = p.get_child(0)
		var col: Control = host.get_child(0).get_child(0)
		minx = maxf(minx, col.get_combined_minimum_size().x)
		widths.append(round(p.size.x))
	print("[desktop] 1920×1080 ⇒ cols=%d w=%.0f h=%.0f · 内容最小宽 %.0f"
			% [int(grid["cols"]), float(grid["w"]), float(grid["h"]), minx])
	print("[desktop]   条 pos=%s size=%s ⇒ 右 %.1f/1920" % [str(row.position),
			str(row.size), row.position.x + row.size.x])
	print("[desktop]   卡片实际宽 %s ⇒ %s" % [str(widths),
			"★ 内容被裁" if minx > float(grid["w"]) + 0.5 else "内容放得下"])
	print("[desktop]   字号档 %.2f · 卡片最小 %s"
			% [float(FONT.scale), str(Vector2(minx, 0.0))])
	vp.queue_free()
	await get_tree().process_frame
