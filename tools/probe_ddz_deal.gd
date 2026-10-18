extends Node

## 斗地主**发牌动画**连拍探针（**非无头**）。
##
## 存在的理由：发牌的「段落感」是**纯视觉**的东西 ——
## 验收脚本能钉住"第 k 段末手牌正好 n 张"，但钉不住"看着有没有一顿一顿的感觉"。
## 用户 2026-10-18：「我并没有感受到那种段落感」⇒ 出一张**接触印相**（把等间隔的
## 若干帧裁出手牌区、竖着拼成一张图），人眼扫一眼就知道哪一帧在发牌、哪一帧在停顿。
##
## 跑法（⛔ 必须非 headless，否则拿不到图像）：
##   "$GODOT_BIN" --path . --quit-after 6000 res://tools/probe_ddz_deal.tscn
##
## 产物：user://ddz_deal_sheet.png（约 17 行 × 每 0.2s 一行）
##       + stdout 里的「采样时刻 / 进度 / 画出来的张数」逐行对照表

const DECK := preload("res://scenes/doudizhu.tscn")
const SEED := 20261018

## 采样间隔（秒）。⛔ 别改太小：行数太多拼出来的图太长，反而看不清。
const STEP := 0.2
## 裁出来的手牌区（设计空间坐标，1920×1080 基准）。含上方那行「你的手牌 · N 张」。
const CROP := Rect2i(300, 756, 1320, 204)


func _ready() -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(1920, 1080)
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)

	# ⚠️ 写 Variant：Control 类型的变量上写 `t._foo()` 会解析失败（同 probe_ddz_seats）
	var t: Variant = DECK.instantiate()
	vp.add_child(t)
	await get_tree().process_frame

	# ★ 走 `_start_game`：它才是"真的发牌"那条路（有动画 + 有发牌音）
	t.call("_start_game", SEED)

	var deal_sec := float(t.DEAL_SEC)
	var total := deal_sec + 0.4
	var crops: Array[Image] = []
	var rows: Array[String] = []
	var now := 0.0
	while now <= total:
		# 推一小步动画，再等两帧让 `_draw()` 落笔
		t.call("_process", STEP)
		now += STEP
		for i in 2:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var full := vp.get_texture().get_image()
		crops.append(full.get_region(CROP))
		rows.append("%5.2fs  进度 %5.2f/17  画出来 %2d 张" % [now,
				float(t.call("_deal_progress")), _visible(t)])

	# ── 竖着拼成一张接触印相 ──
	var sheet := Image.create(CROP.size.x, CROP.size.y * crops.size(), false, Image.FORMAT_RGBA8)
	for i in crops.size():
		sheet.blit_rect(crops[i], Rect2i(Vector2i.ZERO, CROP.size), Vector2i(0, CROP.size.y * i))
	var path := "user://ddz_deal_sheet.png"
	sheet.save_png(path)
	print("[probe] %s（%d 帧，每帧间隔 %.2fs，从上到下 = 时间顺序）"
			% [ProjectSettings.globalize_path(path), crops.size(), STEP])
	print("[probe] DEAL_SEC=%.4f  段长=%.3f  停顿=%.2f  段数=%d  收尾=%.2f"
			% [deal_sec, float(t.DEAL_SEG_SOUND), float(t.DEAL_SEG_GAP),
				int(t.DEAL_BURSTS), float(t.DEAL_TAIL)])
	print("[probe] ── 逐行对照（行号 = 图上从上往下的第几行）──")
	for i in rows.size():
		print("[probe] 行 %2d  %s" % [i, rows[i]])

	get_tree().quit()


## 当前**画出来**的手牌张数（走 `_hand_card_visible()` —— 与 `_draw()` 同源）。
func _visible(t: Variant) -> int:
	var n := 0
	for i in int(t.DEAL_FACE):
		if bool(t.call("_hand_card_visible", i)):
			n += 1
	return n
