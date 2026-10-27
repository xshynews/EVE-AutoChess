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
##   "$GODOT_BIN" \
##     --path . --quit-after 900 res://tools/probe_hud_layout.tscn
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
	# 选船面板塞 8 艘（>6 张就必然超出 1000 窗宽）—— 量横向滚动是否接管
	if _frame == 80:
		var ev = _battle.get("hud").get("event_window")
		if ev != null:
			var opts := []
			for i in 8:
				opts.append({"name": "测试舰 %d" % (i + 1), "tag": "测试",
						"icon": &"diamond", "desc": "占位"})
			ev.call("show_ship_pick", opts)
			ev.show()          # ⚠️ `show_options()` 只填内容，不负责显形（HUD 才负责）
			ev.call("_apply_rect", ev.call("_effective_rect"))
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
	# ── 新增「后勤」组之后：两扇窗还装得下吗（2026-10-26）─────────────
	_lines.append("")
	_lines.append("── 新增羁绊组后的内容高度（内容最小高 > 可用高 = 底部被裁）──")
	for pair in [["synergy_window", "舰队构成"], ["dossier_window", "舰船档案"]]:
		var wn = _battle.get("hud").get(String(pair[0]))
		if wn == null:
			_lines.append("  %s 不存在" % pair[0])
			continue
		if String(pair[0]) == "dossier_window":
			wn.show()
			wn.call("_set_expanded", true)
		var c: Control = wn.get("content")
		var need: float = c.get_combined_minimum_size().y
		# ⚠️ 不能拿 `c.size.y` 当「可用高」—— 内容超框时它会被子控件的最小高撑大，
		#    于是「need ≤ 可用」永远成立（这正是上一版漏报 36px 的原因）。
		#    真正要问的是「内容最小高 + 上外框 + 下内距 ≤ 窗高」。
		var chrome_top: float = c.global_position.y - wn.global_position.y
		var need_total: float = need + chrome_top + 8.0
		_lines.append("  %s %s：窗 %.0f 高 · 内容最小 %.0f + 外框 %.0f = %.0f → %s"
				% [pair[0], pair[1], wn.size.y, need, chrome_top + 8.0, need_total,
						"OK" if need_total <= wn.size.y + 0.5
						else "★ 裁掉 %.0f px" % (need_total - wn.size.y)])

	if worst > 4.0:
		_lines.append("★ 最大死白 = %.1f px（%s）—— 它（以及所有 >4px 的）都应被填满" % [worst, worst_name])
	else:
		_lines.append("★ 最大死白 = %.1f px —— 各窗内容都填满了窗口" % worst)

	# ── 商店卡：定位小标 N/C/T —— ★ 2026-10-27 已删除 ────────────────
	#   用户：「去掉 CTN 的标志，以后再定，毕竟现在也丑」。
	#   ⇒ 这里从「打印每张卡角标的位置」改成「断言角标确实不存在」，
	#     免得以后有人悄悄加回来而没人发现。
	_lines.append("")
	_lines.append("── 商店卡定位小标（2026-10-27 已按用户要求删除，应全部为空）──")
	var shop = hud.get("shop_window")
	if shop == null:
		_lines.append("  shop_window 不存在")
	else:
		var widgets: Array = shop.get("_card_widgets")
		var stray := 0
		for i in widgets.size():
			var w: Dictionary = widgets[i]
			if w.has("badge"):
				stray += 1
				_lines.append("  ⛔ 卡%d 仍有 `badge` 键 —— 与「已删除」不符" % i)
		_lines.append("  ✓ 共 %d 张卡，均无角标（残留 %d 个）" % [widgets.size(), stray])

	# ── 事件·选船：8 张卡时横向滚动是否接管（2026-10-25）─────────────
	_lines.append("")
	_lines.append("── 事件·选船（8 艘）：卡片行 + 横向滚动条 ──")
	var ev2 = hud.get("event_window")
	if ev2 == null:
		_lines.append("  event_window 不存在")
	else:
		var sc = ev2.get("_scroll")
		var row = ev2.get("_cards_row")
		if sc == null or row == null:
			_lines.append("  ⛔ _scroll / _cards_row 为 null（滚动没接上）")
		else:
			var bar: HScrollBar = sc.get_h_scroll_bar()
			_lines.append("  窗 %.0f 宽 · 滚动视口 %.0f 宽 · 卡片行 %.0f 宽（内容最小宽 %.0f）"
					% [ev2.size.x, sc.size.x, row.size.x, row.get_combined_minimum_size().x])
			_lines.append("  横向滚动条 visible=%s max=%.0f page=%.0f  ← 期望 visible=true 且 max>0"
					% [str(bar.visible), bar.max_value, bar.page])

	var f := FileAccess.open(OUT, FileAccess.WRITE)
	if f == null:
		push_error("写不了 %s" % OUT)
		return
	f.store_string("\n".join(_lines))
	f.close()
	print("[HUD 体检] 报告 → %s" % ProjectSettings.globalize_path(OUT))
	for ln in _lines:
		print(ln)
