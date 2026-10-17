extends Node

## 一次性出图探针（非无头）：2026-10-13 三条改动的实机验证。
##   ① 终局：赢家最后一轮出的牌保持展示（AI 赢家不再被「已出完」顶掉）
##   ② 牌桌设置窗（手机档栏目态 = 半屏宽 + 常驻底栏返回）
##   ③ 主菜单设置窗（同上）
## 跑法："$GODOT_BIN" --path . --quit-after 6000 res://tools/probe_ddz_review.tscn
## 产物：user://ddz_final.png / ddz_settings_mobile.png / menu_settings_mobile.png

const DECK := preload("res://scenes/doudizhu.tscn")
const MENU := preload("res://scenes/main_menu.tscn")
const SEED := 20261007


func _ready() -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(1920, 1080)
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var t: Variant = DECK.instantiate()
	vp.add_child(t)
	await get_tree().process_frame

	# ── ① 打到终局（全 AI 推进；挑一个 AI 赢的 seed，直接验证修复点）──
	var seed_v := SEED
	for _try in 8:
		t.call("_new_game", seed_v)
		t.call("_do_bid", 0, true)
		var g: Variant = t.get("game")
		var guard := 0
		while not bool(g.is_over()) and guard < 400:
			t.call("_ai_step")
			guard += 1
		print("[probe] seed=%d winner=%d over=%s" % [seed_v, int(g.winner), str(g.is_over())])
		if int(g.winner) != 0:
			break
		seed_v += 1
	for _i in 3:
		await get_tree().process_frame
	await _shoot(vp, "ddz_final.png")

	# ── ② 牌桌设置窗（强制栏目态 ⇒ 半屏宽矩形 + 底栏返回）──
	t.call("_toggle_settings")
	var sw: Variant = t.get("_settings")
	sw.call("set_tabbed", true)
	t.call("_place_settings")
	for _i in 3:
		await get_tree().process_frame
	await _shoot(vp, "ddz_settings_mobile.png")
	t.call("_toggle_settings")

	# ── ③ 主菜单设置窗（同款）──
	var m: Variant = MENU.instantiate()
	vp.add_child(m)
	await get_tree().process_frame
	m.call("_toggle_settings")
	var ms: Variant = m.get("_settings")
	ms.call("set_tabbed", true)
	m.call("_place_settings")
	for _i in 3:
		await get_tree().process_frame
	await _shoot(vp, "menu_settings_mobile.png")
	get_tree().quit()


func _shoot(vp: SubViewport, file: String) -> void:
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	var path := "user://" + file
	img.save_png(path)
	print("[probe] %s" % ProjectSettings.globalize_path(path))
