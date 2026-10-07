extends Node

## 斗地主牌桌出图探针（**非无头**）。
##
## 存在的理由：上下家是**画面左右**这种东西，验收脚本只能钉住常量
## （`SEAT_DIR`），钉不住"看起来对不对" —— 工程里那条
## 「机器验过 ≠ 实机对」在这里同样成立。⇒ 出一张图，人眼扫一下。
##
## 跑法（⛔ 必须非 headless，否则拿不到图像）：
##   "C:/godot/Godot_v4.7.2-stable_win64_console.exe" \
##     --path "F:/evezzq/eve自走棋918" --quit-after 6000 \
##     res://tools/probe_ddz_seats.tscn
##
## 产物：user://ddz_seats_bid.png / user://ddz_seats_play.png

const DECK := preload("res://scenes/doudizhu.tscn")

## 固定种子 ⇒ 每次出的图**同一副牌**（好对照、好回归）
const SEED := 20261007


func _ready() -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(1920, 1080)
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)

	# ⚠️ 写 Variant：Control 类型的变量上写 `t._foo()` 会解析失败
	var t: Variant = DECK.instantiate()
	vp.add_child(t)
	await get_tree().process_frame

	# ── ① 叫分阶段（不播发牌动画 ⇒ 直接可打）──
	t.call("_new_game", SEED)
	await _shoot(vp, "ddz_seats_bid.png")
	_dump(t)

	# ── ② 出牌阶段：自己叫 3 分当地主 ⇒ 三家都出牌区可见 ──
	t.call("_do_bid", 0, 3)
	await _shoot(vp, "ddz_seats_play.png")

	get_tree().quit()


func _shoot(vp: SubViewport, file: String) -> void:
	for i in 3:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	var path := "user://" + file
	img.save_png(path)
	print("[probe] %s" % ProjectSettings.globalize_path(path))


## 把三家的「名字 + 方位 + 画面坐标」打出来 —— 出图之外的第二重证据。
func _dump(t: Variant) -> void:
	print("[probe] SEAT_DIR = %s（期望 [下, 右, 左]）" % str(t.SEAT_DIR))
	for s in 3:
		var p: Vector2 = t.call("_seat_pt", s)
		print("[probe] 座位 %d = %s · 方位坐标 (%.0f, %.0f)"
				% [s, String(t.call("_seat_name", s)), p.x, p.y])
