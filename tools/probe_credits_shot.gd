extends SceneTree

## ★ 主菜单「版权声明」真实渲染截图 —— 改版权文案后目视确认框内不被裁。
##
## 用法（⛔ 别加 `--headless`）：
##     Godot_v4.7.2-stable_win64_console.exe --path "F:\evezzq\eve自走棋918" \
##         --quit-after 600 --script res://tools/probe_credits_shot.gd
##
## 产物：C:/godot/_export/credits_shot.png（写工程外，⛔ 别污染工程目录）
##
## 和 `probe_menu_shot.gd` 同一套路（场景树探针要等帧），只是多一步切模式。
## ⚠️ 版权框是**定高**面板（`CREDITS_H`）⇒ 文案变长只能靠目视确认没有溢出/裁切。

## 截图写到 user://（各平台都可写），运行后在输出里打印实际路径。
const SHOT := "user://credits_shot.png"

var _menu: Variant = null
var _frames := 0


func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		print("✗ 必须非 headless 才能截图")
		quit(1)
		return
	_menu = load("res://scenes/main_menu.tscn").instantiate()
	root.add_child(_menu)


func _process(_d: float) -> bool:
	_frames += 1
	if _frames == 8:
		# 切到「版权声明」模式（按 id 找下标，⛔ 别写死序号）
		var modes: Array = _menu.get("_modes")
		for i in modes.size():
			if String((modes[i] as Dictionary)["id"]) == "credits":
				_menu.call("_on_mode_pressed", i)
				print("已切到版权声明（index %d）" % i)
		return false
	if _frames < 24:                # 等重排 + 字体稳定
		return false
	var img := root.get_viewport().get_texture().get_image()
	var err := img.save_png(SHOT)
	print("SHOT %s err=%d size=%s" % [ProjectSettings.globalize_path(SHOT), err, img.get_size()])
	quit(0 if err == OK else 1)
	return true
