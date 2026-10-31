extends "res://scripts/ui/eve_window.gd"

## EVE 自走棋 —— 事件增益（阶段 C）
##
## 一条只读小窗：把玩家在事件节点（4 / 10 / 14）拿到的增益列出来。
##
## ⚠️ 两条设计取舍，都写在这里免得日后被"优化"掉：
##   ① **没拿到任何增益时整窗隐藏**。开局 HUD 与 V3 稿逐像素一致（19.3% 占屏），
##      增益窗在第一个事件节点之后才出现 —— 它出现的那一刻本身就是反馈。
##      代价：玩家第一次见到它是"凭空多了一扇窗"，所以标题栏右侧带了 n/m。
##   ② **只读，不可操作**。它不是装备栏（可拖进拖出），没有交互就没有误操作。
##
## 行高 26（名称 11px + 效果 9px 两行）—— 172 宽的栏里，名称与效果并排会挤，
## 所以效果另起一行左对齐（与「舰队构成」的双行条目同一套排版）。

const ROW_H := 26.0

## 一屏最多显示几行。
##
## ★ 2026-10-30（玩家反馈）：「事件变多了，左下角的事件栏位没变多，
##   多于 3 个不显示但依旧生效」。
##   根因不是这里 —— 行的数量本来就跟着 `event_indexes().size()` 走，
##   真凶是**手机布局把窗高写死 158（=3 行）**，第 4 行起被裁掉了。
##   现在行数改成「按实际拿到的增益动态补行」，高度由 `content_need_h()`
##   回给 HUD 参与左列分配；超过本上限时只显示前 MAX_ROWS 条并在标题栏写明总数
##   （⛔ 不做内部滚动：172 宽的窄栏里滚动条会吃掉 8px，条目文本直接读不全）。
const MAX_ROWS := 6

var _rows: Array[Dictionary] = []
var _empty: Label
var _list_box: VBoxContainer
var _max_picks: int = 0


func _ready() -> void:
	window_title = "事件增益"
	density = Density.COMPACT
	super._ready()
	_build_contents()
	set_augments([])


func _build_contents() -> void:
	_max_picks = EveNodeTable.event_indexes().size()

	_empty = Label.new()
	_empty.text = "事件节点 %s 各可选一条增益" % _idx_text()
	_empty.add_theme_color_override("font_color", C_TEXT_FAINT)
	FONT.fs(_empty, 9)
	_empty.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	_empty.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(_empty)

	_list_box = VBoxContainer.new()
	_list_box.add_theme_constant_override("separation", 2)
	_list_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(_list_box)

	for i in mini(_max_picks, MAX_ROWS):
		var row := _build_row()
		_rows.append(row)
		(row["root"] as Control).visible = false
		_list_box.add_child(row["root"])


## 按需要把行补齐（`set_augments` 里调用）。上限 `MAX_ROWS`。
func _ensure_rows(n: int) -> void:
	n = clampi(n, 1, MAX_ROWS)
	while _rows.size() < n:
		var row := _build_row()
		_rows.append(row)
		(row["root"] as Control).visible = false
		_list_box.add_child(row["root"])


## 当前内容需要的高度（HUD 左列分配用；0 = 整窗隐藏、不占位）。
##
## ⚠️ 口径 = 标题栏 40 + 每行 ROW_H + 行间距 2。
##    这个数**必须由窗口自己回给布局**，写死在 `MOBILE_AUG_H` 里就会重演
##    「第 4 条被裁掉」的老问题。
func content_need_h() -> float:
	var n := 0
	for r in _rows:
		if (r["root"] as Control).visible:
			n += 1
	if n <= 0:
		return 0.0
	return 40.0 + float(n) * ROW_H + float(n - 1) * 2.0


func _idx_text() -> String:
	var parts := PackedStringArray()
	for i in EveNodeTable.event_indexes():
		parts.append(str(i))
	return " / ".join(parts)


func _build_row() -> Dictionary:
	var root := HBoxContainer.new()
	root.add_theme_constant_override("separation", 6)
	root.custom_minimum_size = Vector2(0, ROW_H)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var ic := EveIcon.make(&"diamond", 13.0, C_ACCENT, 1.3)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(ic)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(col)

	var nm := Label.new()
	nm.text = "—"
	nm.add_theme_color_override("font_color", C_TEXT)
	FONT.fs(nm, 11)
	nm.clip_text = true
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(nm)

	var ef := Label.new()
	ef.text = "—"
	FONT.fs(ef, 9)
	ef.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	ef.clip_text = true
	ef.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(ef)

	return {"root": root, "icon": ic, "name": nm, "effect": ef}


## 设置已获取的增益。元素 = EveRunState.picked_event_info() 的输出。
func set_augments(list: Array) -> void:
	visible = not list.is_empty()
	if not visible:
		set_status("")
		return
	# ★ 2026-10-30：行数跟着实际拿到的增益长，不再固定 3 行（见 MAX_ROWS 的说明）。
	_ensure_rows(list.size())
	for i in maxi(_rows.size(), list.size()):
		# ⚠️ 增益条数可能超过 MAX_ROWS（行只建到上限）⇒ 先挡住越界，
		#    超出部分由标题栏的 n/m 交代，不留「数组越界」这种崩法。
		if i >= _rows.size():
			break
		var w := _rows[i]
		var root: Control = w["root"]
		if i >= list.size():
			root.visible = false
			continue
		var d: Dictionary = list[i]
		root.visible = true
		var col := d.get("color", C_ACCENT) as Color
		var ic: EveIcon = w["icon"]
		ic.icon = StringName(d.get("icon", &"diamond"))
		ic.color = col
		ic.queue_redraw()
		(w["name"] as Label).text = String(d.get("name", "—"))
		var ef: Label = w["effect"]
		ef.text = String(d.get("effect", ""))
		ef.add_theme_color_override("font_color", Color(col.r, col.g, col.b, 0.78))
	set_status("%d / %d" % [list.size(), _max_picks])
