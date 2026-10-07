extends Node

## HUD 窗体检探针 —— 量【内容盒 vs 窗口】的实际尺寸
##
## ══════════════════════════════════════════════════════════════════
##  为什么需要它
## ══════════════════════════════════════════════════════════════════
##  `EveWindow` 是 `PanelContainer`，内部结构是
##      PanelContainer
##        └ VBoxContainer root
##            ├ (可选的 26px 标题栏)
##            └ MarginContainer _content_margin
##                └ VBoxContainer content        ← 子类往这里塞内容
##
##  各功能窗都在内层写了 `size_flags_vertical = SIZE_EXPAND_FILL`，
##  **但如果 `_content_margin` 自己没有 EXPAND 标志，那句就是空转的** ——
##  BoxContainer 只把富余空间分给带 EXPAND 的孩子，一个都没有时，
##  富余空间堆在末尾 ⇒ 窗口底部出现一条永远填不满的死白。
##
##  这个探针把每个窗的「死白高度」直接量出来（还有负数 = 内容溢出窗口）。
##
## ── 跑法 ─────────────────────────────────────────────────────────
##   "C:/godot/Godot_v4.7.1-stable_win64_console.exe" \
##     --path "F:/evezzq/eve自走棋918" --quit-after 900 res://tools/probe_hud_layout.tscn
##
##  报告落在 user://hud_layout_report.txt（UTF-8，别经 PowerShell 管道读）。
##  ⚠️ 只看 stdout 的话中文会乱码，所以一律写文件。

const SCENE_PATH := "res://scenes/battle_scene.tscn"
const OUT := "user://hud_layout_report.txt"

var _battle: Node = null
var _frame := 0
var _lines := PackedStringArray()


func _ready() -> void:
	_lines.append("═══ HUD 窗体检：内容盒 vs 窗口 ═══")
	_lines.append("")
	_lines.append("死白 = 窗口底 − 内容盒底（>0 就是填不满的空档；<0 = 内容溢出窗口）")
	_lines.append("")
	var packed: PackedScene = load(SCENE_PATH)
	_battle = packed.instantiate()
	add_child(_battle)


func _process(_dt: float) -> void:
	_frame += 1
	# 等 HUD 完成布局与第一轮数据填充
	if _frame == 40:
		_battle.call("begin_prep")
		return
	if _frame < 90:
		return
	_report()
	get_tree().quit(0)


func _report() -> void:
	var hud: Node = _battle.get("hud")
	var names := [
		["command_bar", "顶条"],
		["synergy_window", "舰队构成"],
		["equipment_window", "装备栏位"],
		["augments_window", "事件增益"],
		["dossier_window", "舰船档案"],
		["log_window", "战斗日志"],
		["shop_window", "商店"],
		["event_window", "事件面板"],
	]
	var worst := 0.0
	var worst_name := ""
	for pair in names:
		var key := String(pair[0])
		var cn := String(pair[1])
		var win = hud.get(key)
		if win == null:
			_lines.append("  %-8s %s  —— 不存在" % [key, cn])
			continue
		if not bool(win.get("visible")):
			_lines.append("  %-8s %s  —— 隐藏（不参与体检）" % [key, cn])
			continue
		var content: Control = win.get("content")
		var win_pos: Vector2 = win.global_position
		var win_sz: Vector2 = win.size
		var c_pos: Vector2 = content.global_position
		var c_sz: Vector2 = content.size
		# 内容盒底相对窗口顶的距离
		var c_bottom := (c_pos.y - win_pos.y) + c_sz.y
		var dead := win_sz.y - c_bottom
		_lines.append("  %-8s %-6s 窗口 %.0f×%.0f @ (%.0f,%.0f) · 内容盒 %.0f×%.0f · 死白 %+.1f px"
				% [key, cn, win_sz.x, win_sz.y, win_pos.x, win_pos.y,
					c_sz.x, c_sz.y, dead])
		if dead > worst:
			worst = dead
			worst_name = "%s/%s" % [key, cn]
	_lines.append("")
	if worst > 4.0:
		_lines.append("★ 最大死白 = %.1f px（%s）—— 它（以及所有 >4px 的）都应被填满" % [worst, worst_name])
	else:
		_lines.append("★ 最大死白 = %.1f px —— 各窗内容都填满了窗口" % worst)

	var f := FileAccess.open(OUT, FileAccess.WRITE)
	if f == null:
		push_error("写不了 %s" % OUT)
		return
	f.store_string("\n".join(_lines))
	f.close()
	print("[HUD 体检] 报告 → %s" % ProjectSettings.globalize_path(OUT))
	for ln in _lines:
		print(ln)
