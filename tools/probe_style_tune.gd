extends Node

## 一次性出图探针（非无头）：2026-10-13「样式微调」面板验证。
##   ① 面板本身长什么样（滑杆 / 数值 / 保存 / 恢复默认 / 关闭）
##   ② **真实链路**：拉滑杆 ⇒ 牌桌立刻跟着变（不是直接改变量）
##   ③ 保存 ⇒ user://ddz_style_tune.cfg 真的写进去了（回读校验）
## 跑法："$GODOT_BIN" --path . --quit-after 8000 res://tools/probe_style_tune.tscn
## 产物：user://style_tune_open.png / style_tune_card16.png

const DECK := preload("res://scenes/doudizhu.tscn")
const TUNE := preload("res://scripts/card/ddz/ddz_style_tune.gd")
const SEED := 20261007


func _ready() -> void:
	# ★ 安卓真实分辨率（2340×1080，比基准区 1920 宽）—— 工具就是为这个场景做的
	_backup_cfg()
	var vp := SubViewport.new()
	vp.size = Vector2i(2340, 1080)
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var t: Variant = DECK.instantiate()
	vp.add_child(t)
	await get_tree().process_frame

	t.call("_new_game", SEED)
	t.call("_do_bid", 0, true)
	for _i in 6:
		t.call("_ai_step")
	for _i in 3:
		await get_tree().process_frame

	# ── ① 打开面板（走顶栏按钮那条真实路径）──
	t.call("_on_button", "style")
	for _i in 3:
		await get_tree().process_frame
	var panel: Variant = t.get("_tune")
	print("[probe] 面板可见=%s 在台上=%s" % [str(panel.visible), str(panel != null)])
	await _shoot(vp, "style_tune_open.png")

	# ── ② 拉「牌大小」到 1.45 + 试着拉「整体缩放」（会被本机上限挡住）──
	var ctrls: Dictionary = panel.get("_ctrls")
	(ctrls["card_scale"] as Dictionary)["slider"].value = 1.45
	(ctrls["zoom"] as Dictionary)["slider"].value = 1.25
	await get_tree().process_frame
	print("[probe] zoom=%.2f（本机上限 %.2f）card=%.2f"
			% [float(t.get("zoom")), float(t.call("zoom_cap")), float(t.get("card_scale"))])
	# ★ 画与点同源（缩放后）：把「样式」按钮中心的**屏幕坐标**反向换算回去能命中
	var o: Vector2 = t.call("_ui_origin")
	var z := float(t.get("zoom"))
	var design := Vector2(1920.0 - 424.0 + 44.0, 22.0)
	var screen_pt := o + design * z
	print("[probe] 反算命中=「%s」（期望 style）· origin=%s zoom=%.2f"
			% [String(t.call("_hit_button", (screen_pt - o) / z)), str(o), z])
	t.call("_on_button", "style")         # 关面板看牌桌
	for _i in 3:
		await get_tree().process_frame
	await _shoot(vp, "style_tune_zoom.png")

	# ── ③ 保存 + 回读（写盘不报错 ≠ 写进去了）──
	t.call("_on_button", "style")
	panel.call("_on_save")
	var back := TUNE.load_style()
	print("[probe] 保存回读 zoom=%.2f card=%.2f table=%.2f win=%.2f font=%.2f"
			% [float(back.get("zoom", -1.0)), float(back.get("card_scale", -1.0)),
			   float(back.get("table_scale", -1.0)), float(back.get("win_scale", -1.0)),
			   float(back.get("font_scale", -1.0))])
	# ⚠️⚠️ **绝不能删玩家的存档**：探针开场先备份原 cfg（或记下"原本没有"），
	#    结尾原样写回。之前的版本直接 `clear_style()` —— 会把手调好的数值抹掉。
	_restore_cfg()
	get_tree().quit()


const STYLE_CFG := "user://ddz_style_tune.cfg"
const CFG_BAK := "user://ddz_style_tune.cfg.probe_bak"


func _backup_cfg() -> void:
	if FileAccess.file_exists(STYLE_CFG):
		DirAccess.copy_absolute(STYLE_CFG, CFG_BAK)


func _restore_cfg() -> void:
	if FileAccess.file_exists(CFG_BAK):
		DirAccess.copy_absolute(CFG_BAK, STYLE_CFG)
		DirAccess.remove_absolute(CFG_BAK)
	elif FileAccess.file_exists(STYLE_CFG):
		# 开场没有 ⇒ 把探针写出来的删掉（不留痕）
		DirAccess.remove_absolute(STYLE_CFG)


func _shoot(vp: SubViewport, file: String) -> void:
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	var path := "user://" + file
	img.save_png(path)
	print("[probe] %s" % ProjectSettings.globalize_path(path))
