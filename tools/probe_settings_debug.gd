extends Node
## 验证 settings 窗 DEBUG 块儿按钮齐全 + 发送 signal 正常
##
## 跑法：
##   "C:/godot/Godot_v4.7.1-stable_win64_console.exe" --headless \
##     --path "F:/evezzq/eve自走棋918" --quit-after 5000 \
##     res://tools/probe_settings_debug.tscn

const SETTINGS_SCRIPT := preload("res://scripts/ui/panels/eve_settings.gd")

var _lines: Array[String] = []


func _ready() -> void:
	var w: EveWindow = SETTINGS_SCRIPT.new()
	add_child(w)
	# 等 _ready 跑完
	await get_tree().process_frame

	# 1. 列出所有 Button
	var btns: Array[Button] = []
	_collect_buttons(w, btns)
	_lines.append("═══ 设置窗按钮清单 ═══")
	_lines.append("  总计 %d 个按钮：" % btns.size())
	for b in btns:
		_lines.append("    • \"%s\"" % b.text)

	# 2. 找 DEBUG 块
	var found_debug := false
	var debug_btns: Array[Button] = []
	for b in btns:
		if "+100 星币" in b.text or "+300 星币" in b.text or "+999 星币" in b.text:
			debug_btns.append(b)
	if debug_btns.size() == 3:
		found_debug = true
		_lines.append("")
		_lines.append("  ✅ DEBUG 块：3 个加币按钮齐全（+100 / +300 / +999）")
	else:
		_lines.append("")
		_lines.append("  ❌ DEBUG 块缺失（只找到 %d 个）" % debug_btns.size())

	# 3. 验 signal：模拟点击 +300
	_lines.append("")
	_lines.append("═══ signal add_coins_requested 行为 ═══")
	w.add_coins_requested.connect(func(amt: int):
		_lines.append("  ✅ 收到 add_coins_requested(%d)" % amt))
	for b in debug_btns:
		if "+300" in b.text:
			b.emit_signal("pressed")
			break

	# 4. 列出所有 signal（确认 add_coins_requested 已注册）
	_lines.append("")
	_lines.append("═══ 窗体所有 signal ═══")
	for s in w.get_signal_list():
		_lines.append("    • %s" % String(s["name"]))

	# 输出
	for s in _lines:
		print(s)
	var f := FileAccess.open("user://settings_debug_report.txt", FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(_lines))
		f.close()
	get_tree().quit(0)


func _collect_buttons(n: Node, out: Array[Button]) -> void:
	if n is Button:
		out.append(n)
	for c in n.get_children():
		_collect_buttons(c, out)
