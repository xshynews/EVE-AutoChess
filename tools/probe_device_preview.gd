extends Node
## 安卓线 · 设备精确预览探针（**非无头**）。
##
## 目的：让「桌面出图」尽量接近「真机」。做法不是把窗口拉大，而是：
##   物理分辨率 ÷ content_scale_factor = 真机逻辑视口
## 然后用一个**正好这么大**的 SubViewport 渲染场景 —— 场景代码读到的
## `get_viewport_rect()` 与真机一致，版式才会一致。
##
## 跑法（⛔ 必须非 headless）：
##   "$GODOT_BIN" --path . --quit-after 8000 res://tools/probe_device_preview.tscn \
##     -- --w=2340 --h=1080 --factor=1.35 --safe-top=0 --safe-bottom=0 \
##        --scene=ddz --out=device_preview.png
##
## 参数（都可省）：
##   --w/--h       物理像素，默认 2340×1080（vivo V2353DA 的横屏）
##   --factor      content_scale_factor，默认 1.0（战场是 1.35，牌桌/主菜单是 1.0）
##   --safe-top/bottom/left/right   安全区内缩（**物理像素**，会按 factor 换算）
##   --scene       ddz | menu，默认 ddz
##   --out         user:// 下的文件名，默认 device_preview.png
##
## 产物：`user://<out>`；控制台会打印实际用的逻辑视口尺寸。

const DECK := preload("res://scenes/doudizhu.tscn")
const MENU := preload("res://scenes/main_menu.tscn")

var _w := 2340
var _h := 1080
var _factor := 1.0
var _scene := "ddz"
var _out := "device_preview.png"
var _safe := {"top": 0, "bottom": 0, "left": 0, "right": 0}


func _ready() -> void:
	_parse_args()
	var logical := Vector2i(
			maxi(1, int(round(float(_w) / _factor))),
			maxi(1, int(round(float(_h) / _factor))))
	print("[preview] 物理 %dx%d ÷ factor %.2f ⇒ 逻辑视口 %dx%d"
			% [_w, _h, _factor, logical.x, logical.y])

	var vp := SubViewport.new()
	vp.size = logical
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)

	var packed: PackedScene = DECK if _scene == "ddz" else MENU
	var inst: Node = packed.instantiate()
	vp.add_child(inst)
	for i in 4:
		await get_tree().process_frame

	# 安全区红线（把物理像素内缩换算到逻辑坐标）。
	var inset := Rect2(
			float(_safe["left"]) / _factor,
			float(_safe["top"]) / _factor,
			float(logical.x) - float(_safe["left"] + _safe["right"]) / _factor,
			float(logical.y) - float(_safe["top"] + _safe["bottom"]) / _factor)
	var overlay := SafeOverlay.new()
	overlay.safe = inset
	overlay.info = "logical %dx%d  factor %.2f  safe %s" % [
			logical.x, logical.y, _factor, str(_safe)]
	overlay.size = Vector2(logical)
	vp.add_child(overlay)
	for i in 3:
		await get_tree().process_frame

	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	var path := "user://" + _out
	img.save_png(path)
	print("[preview] %s" % ProjectSettings.globalize_path(path))
	get_tree().quit()


func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--w="):
			_w = int(a.substr(4))
		elif a.begins_with("--h="):
			_h = int(a.substr(4))
		elif a.begins_with("--factor="):
			_factor = maxf(0.1, float(a.substr(9)))
		elif a.begins_with("--safe-top="):
			_safe["top"] = int(a.substr(11))
		elif a.begins_with("--safe-bottom="):
			_safe["bottom"] = int(a.substr(14))
		elif a.begins_with("--safe-left="):
			_safe["left"] = int(a.substr(12))
		elif a.begins_with("--safe-right="):
			_safe["right"] = int(a.substr(13))
		elif a.begins_with("--scene="):
			_scene = a.substr(8)
		elif a.begins_with("--out="):
			_out = a.substr(6)


## 画安全区红线 + 一行指标（不参与任何布局，纯叠加）。
class SafeOverlay extends Control:
	var safe := Rect2()
	var info := ""

	func _draw() -> void:
		draw_rect(safe, Color(1.0, 0.28, 0.12, 0.95), false, 4.0)
		var f := ThemeDB.fallback_font
		draw_string(f, Vector2(24, 52), info, HORIZONTAL_ALIGNMENT_LEFT, -1,
				28, Color(1, 1, 1, 0.95))
