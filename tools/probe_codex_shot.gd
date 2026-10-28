extends Node

## 舰船图鉴**真实渲染截图**探针（不开游戏也能看）—— ⛔ 必须非 headless。
##
## 用法：
##     "$GODOT_BIN" --path . res://tools/probe_codex_shot.tscn -- --out "F:/evezzq/preview/codex_after.png"
##
## [WHY] 2026-10-28 重做立绘（程序化侧影 → 真立绘）需要 A/B 对照图。
##   `verify_codex` 只能证明"卡片数/筛选/详情数据对"，证明不了"画出来是艘船"。
##
## ⚠️ 用 .tscn 而不是 `--script`：SceneTree 脚本模式不注册 class_name 全局类，
##    `EveShipArtView` / `EveShipArt` 会全部报 Identifier not declared
##    （同 docs/多人对战架构 第六节记录的坑）。
##
## ⚠️ 截完图必须等两三帧：`_open_codex()` 里刚 add_child 的卡片还没完成
##    布局，立刻抓图会得到空白网格。

const MENU := "res://scenes/main_menu.tscn"

var _menu: Node = null


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		print("✗ 必须非 headless 才能截图")
		get_tree().quit(1)
		return
	_menu = (load(MENU) as PackedScene).instantiate()
	add_child(_menu)
	await get_tree().process_frame
	await get_tree().process_frame

	_menu.call("_open_codex")
	# 可选：`--role ew` 直接筛某一档定位（攻击 attack / 防御 defense /
	# 后勤 logistics / 电子战 ew / 加强型 command），用来单独出那一档的图。
	var codex = _menu.get("_codex")
	var args0: Array = OS.get_cmdline_user_args() + OS.get_cmdline_args()
	for i in args0.size():
		if String(args0[i]) == "--role" and i + 1 < args0.size() and codex != null:
			codex.call("set_filter", -1, -1, StringName(String(args0[i + 1])))
		# 派系：0 艾玛 / 1 加达里 / 2 盖伦特 / 3 米玛塔尔（= EveShip.Faction 枚举）
		if String(args0[i]) == "--fac" and i + 1 < args0.size() and codex != null:
			codex.call("set_filter", int(String(args0[i + 1])), -1)
	# 等布局 + 立绘上传（EveShipArt 首次会 load 52 张 png）
	for i in 6:
		await get_tree().process_frame
	await get_tree().process_frame

	var out := "user://codex_shot.png"
	var args: Array = OS.get_cmdline_user_args() + OS.get_cmdline_args()
	for i in args.size():
		if String(args[i]) == "--out" and i + 1 < args.size():
			out = String(args[i + 1])
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(out)
	print("SHOT %s err=%d size=%s" % [ProjectSettings.globalize_path(out), err, img.get_size()])
	get_tree().quit(0 if err == OK else 1)
