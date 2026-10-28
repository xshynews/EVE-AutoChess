extends Node

## 战斗日志「敌我标注」出图探针 —— ⛔ 必须非 headless。
##
## 用法：
##     "$GODOT_BIN" --path . res://tools/probe_log_side.tscn -- --out "F:/evezzq/preview/log_side"
##
## 只出图不验逻辑（逻辑在 `verify_run._t_log_side()` 里钉）。
## 这里要回答的是「172px 窄栏里，我 / 敌 两个标记是否读得出来、是否挤压正文」。

const SCENE_PATH := "res://scenes/battle_scene.tscn"

var _battle: Node = null
var _frame := 0
var _out := "user://log_side"


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		print("✗ 必须非 headless 才能截图")
		get_tree().quit(1)
		return
	for i in OS.get_cmdline_user_args().size():
		var args: Array = OS.get_cmdline_user_args()
		if String(args[i]) == "--out" and i + 1 < args.size():
			_out = String(args[i + 1])
	_battle = (load(SCENE_PATH) as PackedScene).instantiate()
	add_child(_battle)


func _process(_dt: float) -> void:
	_frame += 1
	if _frame == 40:
		_battle.call("begin_prep")
		return
	if _frame == 80:
		var hud: Node = _battle.get("hud")
		# 四条对照：我方破层 / 敌方摧毁 / 我方后勤 / 不分阵营的系统行
		hud.call("append_log", {"time": 12.4, "category": &"break",
				"text": "茶隼级 的装甲被击穿", "team": 0})
		hud.call("append_log", {"time": 13.1, "category": &"damage",
				"text": "因卡萨斯级 已被摧毁", "team": 1})
		hud.call("append_log", {"time": 13.6, "category": &"repair",
				"text": "矮脚鸡级 → 茶隼级 护盾 +21", "team": 0})
		hud.call("append_log", {"time": 14.0, "category": &"system",
				"text": "战斗开始：8 v 8"})
		return
	if _frame < 92:
		return
	var hud2: Node = _battle.get("hud")
	var logw: Control = hud2.get("log_window")
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(_out + "_full.png")
	if logw != null:
		# ⚠️ 图像是**窗口像素**，`global_position` 是**画布坐标**（设计 1920×1080）。
		#    项目是 `stretch/mode=canvas_items` ⇒ 两者差一个缩放比，不换算就裁偏。
		var k := Vector2(img.get_size()) / get_viewport().get_visible_rect().size
		var r := Rect2i(Vector2i(Vector2(logw.global_position) * k),
				Vector2i(Vector2(logw.size) * k))
		var crop := img.get_region(r)
		# 放大 3 倍便于肉眼确认字距与颜色（最近邻，不糊）
		crop.resize(crop.get_width() * 3, crop.get_height() * 3, Image.INTERPOLATE_NEAREST)
		err = max(err, crop.save_png(_out + "_crop.png"))
	print("SHOT %s err=%d log=%s" % [ProjectSettings.globalize_path(_out),
			err, str(logw.size) if logw != null else "null"])
	get_tree().quit(0 if err == OK else 1)
