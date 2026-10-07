extends Node

## 探针 —— 量出缩放把手的真实矩形，并实测鼠标事件的【真实路由】
##
## 为什么需要这个：
##   用户报告「鼠标移到商店上，指针变成一个拉大拉小的缩放指针」。
##   根因是 EveWindow 继承 PanelContainer，而 Container 会把【每个】子节点 fit 成
##   整块矩形，于是 11×11 的缩放手把被拉成整窗大小。
##
## ⚠️ 这个 bug 有两条「验收陷阱」，两条都踩过：
##   ① 截图拍不到 —— 光标形状只在悬停时生效，静帧里没有光标。
##      → 必须量矩形。
##   ② headless 收不到 GUI 输入 —— 实测 gui_get_hovered_control() 恒为 null，
##      Input.parse_input_event / Viewport.push_input 四种写法全不生效。
##      → 这个探针【必须非 headless 跑】，否则输入那几项会假 FAIL。
##
## 跑法（注意：不加 --headless）：
##   "C:/godot/Godot_v4.7.1-stable_win64_console.exe" --path "F:/evezzq/eve自走棋918" \
##     --quit-after 400 res://tools/probe_grip.tscn

const SHOP_SCRIPT := preload("res://scripts/ui/panels/eve_shop.gd")
const SYN_SCRIPT := preload("res://scripts/ui/panels/eve_fleet_synergy.gd")
const BAR_SCRIPT := preload("res://scripts/ui/panels/eve_command_bar.gd")
const GRIP := 11.0

var _fail := 0
var _root: Control
var _headless := false


func _ready() -> void:
	_headless = DisplayServer.get_name() == "headless"

	# 与真实 HUD 同构：窗口挂在【铺满视口的 Control】下面，不是裸 Node
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_root)

	print("=".repeat(78))
	print("[缩放把手探针]  运行环境 = %s" % ("headless（输入项会跳过）" if _headless else "有显示"))
	print("=".repeat(78))

	var cases := [
		["商店", SHOP_SCRIPT, 389.0, 898.0, 1142.0, 168.0],
		["羁绊", SYN_SCRIPT, 8.0, 56.0, 172.0, 268.0],
		# 顶条是「裸条」：show_header=false / resizable=false。
		# 它没有把手，但【必须能拖动】—— 这条单独回归，见 _check 里的裸条分支。
		["顶条(裸条)", BAR_SCRIPT, 620.0, 6.0, 680.0, 40.0],
	]
	for c in cases:
		await _check(c[0], c[1], c[2], c[3], c[4], c[5])

	print("\n结果：%s" % ("全部通过" if _fail == 0 else "%d 项 FAIL" % _fail))
	get_tree().quit(0 if _fail == 0 else 1)


func _check(label: String, script: GDScript, x: float, y: float,
		w: float, h: float) -> void:
	var win: Variant = script.new()
	_root.add_child(win)
	win.call("set_window_rect", x, y, w, h)
	# 等两帧 —— Container 的重排发生在帧末，立刻读会读到旧值
	await get_tree().process_frame
	await get_tree().process_frame

	var wpos: Vector2 = win.get("position")
	var wsize: Vector2 = win.get("size")
	var resizable: bool = win.get("resizable")
	var grip: Variant = win.get("_grip")
	print("\n── %s   窗口 size=%s  resizable=%s" % [label, wsize, resizable])

	if not resizable:
		# 不可缩放的窗口（顶条）：不该有把手，但【必须能拖动】
		_ok("不可缩放 ⇒ 无缩放把手", grip == null)
		if _headless:
			print("     （headless 无法注入 GUI 输入，跳过拖动测试）")
			win.queue_free()
			return
		await _check_bare_drag(win, wpos, wsize)
		win.queue_free()
		return

	if grip == null:
		_ok("存在缩放把手", false)
		return

	var gpos: Vector2 = grip.get("position")
	var gsize: Vector2 = grip.get("size")
	print("     grip pos=%s size=%s   占窗口面积 %.2f%%"
			% [gpos, gsize, gsize.x * gsize.y / maxf(1.0, wsize.x * wsize.y) * 100.0])
	_ok("尺寸 11×11", absf(gsize.x - GRIP) < 1.5 and absf(gsize.y - GRIP) < 1.5)
	_ok("贴住右下角",
			absf(gpos.x - (wsize.x - GRIP)) < 1.5
			and absf(gpos.y - (wsize.y - GRIP)) < 1.5)

	var header_pt := wpos + Vector2(wsize.x * 0.5, 13.0)
	var grect: Rect2 = grip.call("get_global_rect")
	_ok("把手不含标题栏中心（拖得动窗口）", not grect.has_point(header_pt))
	# 顺带确认把手的鼠标穿透范围：不应盖住窗口中部（点得到按钮）
	_ok("把手不含窗口中心（点得到按钮）",
			not grect.has_point(wpos + wsize * 0.5))

	if _headless:
		print("     （headless 无法注入 GUI 输入，跳过真实路由测试）")
		win.queue_free()
		return

	# ① 标题栏按下 → 应当进入「拖动」，不是「缩放」
	await _click(win, header_pt)
	var dragging: bool = win.get("_dragging")
	var resizing: bool = win.get("_resizing")
	print("     标题栏按下 → _dragging=%s  _resizing=%s" % [dragging, resizing])
	_ok("标题栏按下走拖动分支", dragging and not resizing)
	_reset(win)

	# ② 右下角按下 → 应当进入「缩放」
	var corner := wpos + wsize - Vector2(GRIP * 0.5, GRIP * 0.5)
	await _click(win, corner)
	var dragging2: bool = win.get("_dragging")
	var resizing2: bool = win.get("_resizing")
	print("     右下角按下 → _dragging=%s  _resizing=%s" % [dragging2, resizing2])
	_ok("右下角按下走缩放分支", resizing2 and not dragging2)
	_reset(win)

	# ③ 窗口中部按下 → 两个分支都不该走（事件属于内容区）
	var mid := wpos + wsize * 0.5
	await _click(win, mid)
	var dragging3: bool = win.get("_dragging")
	var resizing3: bool = win.get("_resizing")
	print("     窗口中部按下 → _dragging=%s  _resizing=%s" % [dragging3, resizing3])
	_ok("中部按下不被把手劫持", not dragging3 and not resizing3)
	_reset(win)

	win.queue_free()


## 裸条（无标题栏）专项：整条都该是拖动手柄。
##
## ⚠️ 不能只试一个点 —— 条上散布着按钮 / 自绘仪表（RingGauge），
##    它们会先吃掉事件。只要【有任何一个非按钮位置】能起拖，就算合格，
##    所以这里扫几个不同位置，命中其一即通过。
func _check_bare_drag(win: Variant, wpos: Vector2, wsize: Vector2) -> void:
	var fracs := [0.05, 0.25, 0.5, 0.75, 0.95]
	var hits := 0
	var probe_log := PackedStringArray()
	for f in fracs:
		var pt := wpos + Vector2(wsize.x * f, wsize.y * 0.5)
		await _click(win, pt)
		if win.get("_dragging"):
			hits += 1
			probe_log.append("%.2f✓" % f)
		else:
			probe_log.append("%.2f✗" % f)
		_reset(win)
	print("     裸条拖动试探 [%s] 命中 %d/%d"
			% [" ".join(probe_log), hits, fracs.size()])
	_ok("裸条可以拖动（至少一处起拖）", hits > 0)
	# 起拖点应该【不止一处】—— 整条都是手柄，只有一处能拖说明手柄太窄
	_ok("裸条拖动热点足够宽（≥3 处）", hits >= 3)


## 先送 motion（把 viewport 的 last_mouse_pos 立起来），再按下、再松开
func _click(win: Variant, at: Vector2) -> void:
	var m := InputEventMouseMotion.new()
	m.position = at
	m.global_position = at
	get_viewport().push_input(m)
	await get_tree().process_frame

	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = at
	down.global_position = at
	get_viewport().push_input(down)
	await get_tree().process_frame


func _reset(win: Variant) -> void:
	win.set("_dragging", false)
	win.set("_resizing", false)


func _ok(what: String, passed: bool) -> void:
	if not passed:
		_fail += 1
	print("     %s %s" % ["OK  " if passed else "FAIL", what])
