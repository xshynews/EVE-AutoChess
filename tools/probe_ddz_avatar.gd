extends Node
## 斗地主头像出图探针（**非无头**）。
##
## 目的：`set_avatar()` 在座位面板里到底画成什么样，headless 断不出来。
## 这里给三个座位贴红/绿/蓝三张带「深色圆」的头像，人眼一眼就能看出：
##   ① 三张脸是不是都画上了（而不是只有自己那张）；
##   ② 有没有被拉伸/裁切（圆应当还是圆）。
##
## 跑法（⛔ 必须非 headless）：
##   "$GODOT_BIN" --path . --quit-after 6000 res://tools/probe_ddz_avatar.tscn
##
## 产物：user://ddz_avatar.png

const DECK := preload("res://scenes/doudizhu.tscn")
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

	t.call("_new_game", SEED)
	# 三个座位各贴一张纯色头像（红/绿/蓝），验证「有贴图 ⇒ 画立绘」
	t.call("set_avatar", 0, _tex(Color(0.85, 0.22, 0.22)))
	t.call("set_avatar", 1, _tex(Color(0.22, 0.80, 0.35)))
	t.call("set_avatar", 2, _tex(Color(0.30, 0.45, 0.95)))
	t.call("queue_redraw")
	await _shoot(vp, "ddz_avatar.png")
	print("[probe] 头像已贴：座位0=红 · 座位1=绿 · 座位2=蓝")
	get_tree().quit()


## 造一张 96×96 的纯色头像，中间压一个深色圆（圆没变椭圆 ⇒ 没被拉伸）。
func _tex(col: Color) -> ImageTexture:
	var img := Image.create(96, 96, false, Image.FORMAT_RGBA8)
	img.fill(col)
	for y in 96:
		for x in 96:
			if Vector2(x - 48, y - 44).length() < 22.0:
				img.set_pixel(x, y, col.darkened(0.35))
	return ImageTexture.create_from_image(img)


func _shoot(vp: SubViewport, file: String) -> void:
	for i in 3:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	var path := "user://" + file
	img.save_png(path)
	print("[probe] %s" % ProjectSettings.globalize_path(path))
