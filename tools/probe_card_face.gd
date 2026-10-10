extends Node

## 斗地主「贴图牌面」出图探针（**非无头**）。
##
## 存在的理由：`CARD_FACES` 白名单命中的牌整张画贴图，贴图的圆角 /
## 比例 / 与金框的压叠关系只能人眼看 —— 出一张图扫一下。
##
## 跑法（⛔ 必须非 headless，否则拿不到图像）：
##   "C:/godot/Godot_v4.7.2-stable_win64_console.exe" \
##     --path "F:/evezzq/eve自走棋918" --quit-after 6000 \
##     res://tools/probe_card_face.tscn
##
## 产物：user://ddz_card_face.png

const DECK := preload("res://scenes/doudizhu.tscn")

## 方块2（id%4: 2=方块；rank=3+id/4=15 ⇒ id 48~51 是四张 2）
const FACE_ID := 50
## 与 ddz_table.CARD_FACES 对齐的白名单键（这里只做**画面证据**，
## 断言口径 = 贴图真的被画出来 + 手里确有这张牌）
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

	# 固定种子开局（不播发牌动画 ⇒ 直接可画）
	t.call("_new_game", SEED)

	# 强制让玩家手里有方块2：没有就拿第一张换掉，再排序（画面稳定可对照）
	var game: Variant = t.get("game")
	var hand: Array = game.hand_of(0)
	if not hand.has(FACE_ID):
		hand[0] = FACE_ID
		(hand as Array).sort()
	t.call("queue_redraw")

	print("[probe] 手牌含方块2(id=%d) = %s" % [FACE_ID, str((hand as Array).has(FACE_ID))])

	await _shoot(vp, "ddz_card_face.png")
	get_tree().quit()


func _shoot(vp: SubViewport, file: String) -> void:
	for i in 3:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	var path := "user://" + file
	img.save_png(path)
	print("[probe] %s" % ProjectSettings.globalize_path(path))
