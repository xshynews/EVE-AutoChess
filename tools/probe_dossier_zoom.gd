extends Node

## 舰船档案窗「缩放按钮」出图探针 —— ⛔ 必须非 headless。
##
## 用法：
##     "$GODOT_BIN" --path . res://tools/probe_dossier_zoom.tscn -- --out "F:/evezzq/preview/dossier"
##
## 产出 `--out` 前缀 + `_normal.png` / `_zoomed.png` / `_zoomed_other.png` 三张图。
##
## ⚠️ 为什么要出图：自检只能证明「宽高数字变了、换船后尺寸没退回去」，
##    证明不了标题栏那枚按钮**画出来像不像**一个缩放图标（自绘图形最容易画歪）。
##
## ⚠️⚠️ 2026-10-28 二次改：**必须用真实鼠标事件**点，不能直接 `call("toggle_zoom")`。
##    直接调方法会绕开 GUI picking —— 而玩家报的正是「图标在，点了没反应」。
##    同时保留一段**对照实验**：用同一套注入手法去点折叠按钮（既有功能），
##    如果连折叠都没反应，就说明是注入在本场景不生效，不能反推"缩放按钮坏了"。

const SCENE_PATH := "res://scenes/battle_scene.tscn"
const SHIP_DB := preload("res://scripts/core/eve_ship_database.gd")

var _battle: Node = null
var _frame := 0
var _out := "user://dossier"
var _hud: Control = null
var _dos: Control = null
var _xf_printed := false


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		print("✗ 必须非 headless 才能截图")
		get_tree().quit(1)
		return
	var args: Array = OS.get_cmdline_user_args() + OS.get_cmdline_args()
	for i in args.size():
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
		_hud = _battle.get("hud")
		if _hud != null:
			_hud.call("show_ship", SHIP_DB.instantiate_by_id("caracal", 0, 9901))
		_dos = _hud.get("dossier_window") if _hud != null else null
		return
	if _frame == 96:
		_shot("_normal")
		return
	if _frame == 106:
		# ── 对照实验：点折叠按钮（EveWindow 既有功能）──
		var cb: Control = _dos.get("_collapse_btn") if _dos != null else null
		if cb == null:
			print("CTRL 没有 _collapse_btn，跳过对照")
			return
		var before := _dos.size
		_click(cb)
		print("CTRL 点折叠按钮 %s ⇒ size %s → %s（变了=注入有效）" % [
				str(cb.get_global_rect()), str(before), str(_dos.size)])
		return
	if _frame == 112:
		# 恢复折动态，别影响后面的截图
		var cb2: Control = _dos.get("_collapse_btn") if _dos != null else null
		if cb2 != null:
			_click(cb2)
		print("CTRL 恢复后 size=%s zoom_btn_visible=%s" % [
				str(_dos.size), str(_dos.get("_zoom_btn").visible)])
		return
	if _frame == 124:
		# ── 正题：真实鼠标点缩放按钮 ──
		var zb: Control = _dos.get("_zoom_btn") if _dos != null else null
		if zb == null:
			print("CLICK FAIL: 找不到 _zoom_btn")
			return
		print("CLICK btn %s visible=%s filter=%d" % [
				str(zb.get_global_rect()), str(zb.visible), int(zb.mouse_filter)])
		_click(zb)
		print("CLICK 点完(push_input) size=%s zoomed=%s" % [
				str(_dos.size), str(_dos.call("is_zoomed"))])
		# ★ 判别注入坐标是否偏：本机记录过 `Input.warp_mouse` 与视口有 (+60,0) 的差
		#   （见 ai_mouse_bot 的 calibrate_mouse）。若 `push_input` 吃的是另一种坐标，
		#   点击就会整体偏移 ⇒ 打到旁边的 HBox 上，表现成"按钮点了没反应"。
		#   这里把三个候选点各试一次，只为了**证明注入本身是否可靠**。
		if not bool(_dos.call("is_zoomed")):
			for dx in [-60.0, 60.0, 0.0]:
				if _click_at(zb, dx):
					print("CLICK 偏移 %+.0f 有效 ⇒ 注入坐标口径不同（按钮本身是好的）" % dx)
					break
		return
	if _frame == 140:
		_shot("_zoomed")
		return
	if _frame == 150:
		# 放大态下换一艘船：尺寸必须保持不变（用户硬要求）
		if _hud != null:
			_hud.call("show_ship", SHIP_DB.instantiate_by_id("abaddon", 0, 9902))
		return
	if _frame == 170:
		print("KEEP size=%s zoomed=%s（放大后换船，尺寸应还是放大值）" % [
				str(_dos.size), str(_dos.call("is_zoomed"))])
		_shot("_zoomed_other")
		get_tree().quit(0)
		return


## 在控件中心发一套真实鼠标事件（motion → press → release）。
func _click(c: Control) -> void:
	_click_at(c, 0.0, false)


## 同上，但点击位置横向偏移 `dx`（用来判别注入坐标口径）。
## 返回 true = 这一次点击真的改变了放大态。
func _click_at(c: Control, dx: float, revert: bool = true) -> bool:
	var before := bool(_dos.call("is_zoomed")) if _dos != null else false
	# ★★ 2026-10-28 关键：`get_global_rect()` 是**画布坐标（设计空间 1920×1080）**，
	#    而 `push_input()` 吃的是**窗口像素**。项目开了 `content_scale_mode`，
	#    两者差一个 `get_final_transform()`（2048/1920 ≈ 1.0667）。
	#    ⚠️ 不做这一步转换，点击会整体偏移 6%：落在按钮左边 ~19px 就是标题栏
	#      HBox 自己 —— 表现就是「按钮点不动」，害我一度以为控件 picking 坏了。
	var xf := get_viewport().get_final_transform()
	var p := xf * c.get_global_rect().get_center() + Vector2(dx, 0.0)
	if not _xf_printed:
		_xf_printed = true
		print("XF final=%s → 点击点 %s" % [str(xf), str(p)])
	var mv := InputEventMouseMotion.new()
	mv.position = p
	mv.global_position = p
	get_viewport().push_input(mv)
	for down in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = down
		ev.position = p
		ev.global_position = p
		get_viewport().push_input(ev)
	if _dos == null:
		return false
	var after := bool(_dos.call("is_zoomed"))
	if after != before:
		# 试错命中后要复位，免得干扰后续判定（正式点击传 revert=false）
		if revert:
			_dos.call("toggle_zoom")
		return true
	return false


func _shot(tag: String) -> void:
	var img := get_viewport().get_texture().get_image()
	var path := "%s%s.png" % [_out, tag]
	var err := img.save_png(path)
	print("SHOT %s err=%d size=%s | dossier=%.0fx%.0f zoomed=%s" % [
			ProjectSettings.globalize_path(path), err, img.get_size(),
			_dos.size.x if _dos != null else 0.0, _dos.size.y if _dos != null else 0.0,
			str(_dos.call("is_zoomed")) if _dos != null else "?"])
