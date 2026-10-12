extends SceneTree

## ★ 主菜单**真实渲染截图**（不开游戏也能看）—— 非 headless 才能拿到视口纹理。
##
## 用法（⛔ 别加 `--headless`）：
##     "$GODOT_BIN" --path . \
##         --quit-after 600 --script res://tools/probe_menu_shot.gd
##
## 产物：user://menu_shot.png（写在工程外，运行后输出里会打印实际路径）
##
## ★ 2026-10-12：加 `-- --collapsed` 可截「自走棋收起」态（两层侧栏的折叠视觉）。
##
## 存在的理由：i18n 迁移期出过「数据源对、渲染路径错」的 bug（副标题裸 %d），
## 只测 `_build_mode_table()` 的返回值测不出来 ⇒ 得看真实界面。
##
## ⚠️ SceneTree 脚本探针的两个坑：① `_initialize()` 里 add_child 时 root 还没进树
##    ⇒ `_ready` 要等几帧才跑；② 必须在 `_process()` 里等帧，不能在 `_initialize()` 里截图。

## 截图写到 user://（各平台都可写），运行后在输出里打印实际路径。
const SHOT := "user://menu_shot.png"

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
	if _frames == 4:
		# ⚠️ `--script` 起动时 `--` 之后的参数在 get_cmdline_user_args()，
		#    但个别起动方式会落到 get_cmdline_args() ⇒ 两处都扫，免得静默失效。
		var args: Array = OS.get_cmdline_user_args() + OS.get_cmdline_args()
		if args.has("collapsed"):
			# 「自走棋」父项点一下 = 收起子项（⛔ 按 id 找，别写死下标）
			var i: int = _menu.call("_index_of_id", "autochess")
			if i >= 0:
				_menu.call("_on_mode_pressed", i)
				print("已收起「自走棋」子项（index %d）" % i)
		return false
	if _frames < 8:                 # 让 `_ready` 建完 UI + 字体/布局稳定
		return false
	var img := root.get_viewport().get_texture().get_image()
	var err := img.save_png(SHOT)
	print("SHOT %s err=%d size=%s" % [ProjectSettings.globalize_path(SHOT), err, img.get_size()])
	quit(0 if err == OK else 1)
	return true
