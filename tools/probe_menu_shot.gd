extends SceneTree

## ★ 主菜单**真实渲染截图**（不开游戏也能看）—— 非 headless 才能拿到视口纹理。
##
## 用法（⛔ 别加 `--headless`）：
##     Godot_v4.7.2-stable_win64_console.exe --path "F:\evezzq\eve自走棋918" \
##         --quit-after 600 --script res://tools/probe_menu_shot.gd
##
## 产物：C:/godot/_export/menu_shot.png（写工程外，⛔ 别污染工程目录）
##
## 存在的理由：i18n 迁移期出过「数据源对、渲染路径错」的 bug（副标题裸 %d），
## 只测 `_build_mode_table()` 的返回值测不出来 ⇒ 得看真实界面。
##
## ⚠️ SceneTree 脚本探针的两个坑：① `_initialize()` 里 add_child 时 root 还没进树
##    ⇒ `_ready` 要等几帧才跑；② 必须在 `_process()` 里等帧，不能在 `_initialize()` 里截图。

const SHOT := "C:/godot/_export/menu_shot.png"

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
	if _frames < 8:                 # 让 `_ready` 建完 UI + 字体/布局稳定
		return false
	var img := root.get_viewport().get_texture().get_image()
	var err := img.save_png(SHOT)
	print("SHOT %s err=%d size=%s" % [SHOT, err, img.get_size()])
	quit(0 if err == OK else 1)
	return true
