extends Node

## 主界面出图探针（非无头）—— 三个状态各出一张。
##
## 为什么用 SubViewport 而不是截图整个窗口：
##   真窗尺寸会被屏幕分辨率改写，量不出 1920x1080 的定稿效果。
##   SubViewport 锁死 1920x1080，与设计稿同口径。
##
## 跑法：
##   "C:/godot/Godot_v4.7.1-stable_win64_console.exe" \
##     --path "F:/evezzq/eve自走棋918" --quit-after 6000 \
##     res://tools/probe_main_menu.tscn
## 产物：user://main_menu_*.png

## ⚠️ 必须实例化**真场景**：曾经这里写 MENU_SCRIPT.new()，那是个没设锚点的裸 Control
##    （尺寸 0x0）⇒ 锚满父节点的底图 TextureRect 等于没画，整张图全黑。
const MENU_SCENE := preload("res://scenes/main_menu.tscn")

# ⚠️ `mode` 写的是**模式 id**，⛔ 不是下标 —— 用下标的话，
#    模式列表一增删（2026-10-06 加了「棋牌室」）这里就会静默拍错界面。
const SHOTS := [
	{"file": "main_menu_1_campaign.png", "mode": "campaign", "tier": 0},
	{"file": "main_menu_2_tier2.png", "mode": "campaign", "tier": 1},
	{"file": "main_menu_3_endless.png", "mode": "endless", "tier": 0},
	{"file": "main_menu_4_cardroom.png", "mode": "cardroom", "tier": 0},
]


func _ready() -> void:
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
