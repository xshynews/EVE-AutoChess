extends "res://scripts/ui/eve_window.gd"

## EVE 自走棋 —— 事件四选一面板（阶段 C）
##
## 节点 4 / 10 / 14 共用同一套选项（真源 `scripts/data/eve_event_table.gd`）。
## 这是全局**唯一**的「打断式决策面板」：平时 HUD 全是只读信息窗，
## 只有它需要玩家点一下才能继续。所以它有两条不同于其他窗口的规矩：
##
##   ① **不给自己留退路** —— 没有关闭按钮、点窗口外不消失。
##      与云顶的海克斯一致：给你四条路，你必须选一条。
##   ② **面板只负责显示与回调**，数值一律回 `EveRunState.apply_event()` 落地。
##      UI 里出现第二份数值口径，是这类面板最容易烂掉的地方。
##
## 视觉：沿用 EveWindow 的一套（直角 / 1px 边 / 26px 标题栏），
## 只有卡片带分类色 —— 分类色是**内容**，不是新的一套皮肤。
##
## 变更清单（2026-09-20 实装）：
##   - show_options(options, line, meta) / 4 张卡
##   - 三态：常态 / 悬停（分类色描边 + 提亮）/ 已获取（压暗 + 「已获取」）
##   - 悬停与点击都在卡片自身上（PanelContainer 的 gui_input + mouse_entered/exited）

signal option_chosen(id: StringName)
## 选船模式：玩家点了第 index 张卡（对应 `show_ship_pick` 传进来的数组下标）
signal ship_picked(index: int)

## 卡片宽高由 HBox 均分，这里只定一个最小宽 —— 防止窗口被拖窄后 4 张卡挤成条
const CARD_MIN_W := 150.0

var _cards: Array[Dictionary] = []
var _cards_row: HBoxContainer
var _intro: Label
var _footer: Label
var _options: Array = []
var _hover: int = -1
## true = 这一屏是「选 1 艘船」而不是「四选一」。只是**换个回调出口**，
## 卡片与窗口皮肤完全复用 —— 不新造第二套面板。
var _pick_mode := false


func _ready() -> void:
	window_title = "事件"
	density = Density.NORMAL
	super._ready()
	_build_contents()


func _build_contents() -> void:
	_intro = Label.new()
	_intro.add_theme_color_override("font_color", C_TEXT_DIM)
	FONT.fs(_intro, 11)
	_intro.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	_intro.custom_minimum_size = Vector2(0, 0)
	_intro.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_intro.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(_intro)

	_cards_row = HBoxContainer.new()
	_cards_row.add_theme_constant_override("separation", 10)
	_cards_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(_cards_row)

	_footer = Label.new()
	_footer.add_theme_color_override("font_color", C_TEXT_FAINT)
	FONT.fs(_footer, 9)
	_footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(_footer)


# ------------------------------------------------------------------ 对外

## 打开面板。options 元素 = EveEventTable 的条目（带 taken 标记）。
func show_options(p_options: Array, line: String = "", meta: String = "") -> void:
	_options = p_options
	_hover = -1
	_intro.text = line
	set_status(meta)
	_footer.text = "选择即生效 · 三次事件共用这一套选项，已获取的不能再选"
	while _cards_row.get_child_count() < options_count():
		var i := _cards_row.get_child_count()
		var w := _build_card()
		var root: PanelContainer = w["root"]
		root.gui_input.connect(_on_card_input.bind(i))
		root.mouse_entered.connect(_on_card_hover.bind(i, true))
		root.mouse_exited.connect(_on_card_hover.bind(i, false))
		_cards_row.add_child(root)
		_cards.append(w)
	for i in _cards.size():
		var opt = p_options[i] if i < p_options.size() else null
		_fill_card(_cards[i], opt)


## 打开「选 1 艘船」模式。
##
## ⚠️ 面板**不认识"船"这个概念** —— `options` 是调用方拼好的伪选项
##    （name / tag / icon / desc 四个字段就够），面板只管画卡与回传下标。
##    这样"船从哪来"这件事只有一份真相源（`EveRunState`），面板不用管。
func show_ship_pick(options: Array, line: String = "", meta: String = "") -> void:
	_pick_mode = true
	show_options(options, line, meta)
	_footer.text = "选中的那艘船本局永久生效 —— 只能选一次"


func options_count() -> int:
	return _options.size()


func close_panel() -> void:
	# 面板不复用（一局只有三次），收起就是隐藏；下次 show_options 重新填。
	visible = false
	_pick_mode = false


# ------------------------------------------------------------------ 卡片构建

func _build_card() -> Dictionary:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size = Vector2(CARD_MIN_W, 0)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.add_theme_stylebox_override("panel", _card_style(C_TEXT, 0.72, false))

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(col)

	# 分类色顶条 3px（与商店卡同一个语汇：顶条 = 分类）
	var top := ColorRect.new()
	top.custom_minimum_size = Vector2(0, 3)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(top)

	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 9)
	pad.add_theme_constant_override("margin_right", 9)
	pad.add_theme_constant_override("margin_top", 8)
	pad.add_theme_constant_override("margin_bottom", 8)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(pad)

	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 5)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_child(body)

	# 图标（居中）
	var ic_center := CenterContainer.new()
	ic_center.custom_minimum_size = Vector2(0, 46)
	ic_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(ic_center)
	var ic := EveIcon.make(&"diamond", 30.0, C_ACCENT, 1.6)
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ic_center.add_child(ic)

	var nm := Label.new()
	nm.text = "—"
	nm.add_theme_color_override("font_color", Color(0.875, 0.949, 0.965))
	FONT.fs(nm, 13)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# ⚠️ clip_text：不带它时 Label 的最小宽度 = 文本宽度，4 张卡按各自名字分空间
	#    → 卡片宽度参差不齐（商店卡踩过同一个坑，见 eve_shop.gd 的注释）。
	nm.clip_text = true
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(nm)

	var tag := Label.new()
	tag.text = "—"
	FONT.fs(tag, 9)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.clip_text = true
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(tag)

	body.add_child(make_divider())

	var desc := Label.new()
	desc.text = "—"
	desc.add_theme_color_override("font_color", C_TEXT)
	FONT.fs(desc, 11)
	desc.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(desc)

	# 撑开，把操作提示推到底部
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(spacer)

	var foot := Label.new()
	foot.text = "点击选择"
	foot.add_theme_color_override("font_color", C_TEXT_FAINT)
	FONT.fs(foot, 10)
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(foot)

	return {"root": card, "top": top, "icon": ic, "name": nm,
			"tag": tag, "desc": desc, "foot": foot}


func _fill_card(w: Dictionary, opt) -> void:
	var card: PanelContainer = w["root"]
	if opt == null or (opt is Dictionary and (opt as Dictionary).is_empty()):
		card.visible = false
		return
	card.visible = true
	var o: Dictionary = opt
	var tag: StringName = StringName(o.get("tag", &""))
	var col := EveEventTable.tag_color(tag)
	var taken := bool(o.get("taken", false))

	(w["top"] as ColorRect).color = Color(col.r, col.g, col.b, 0.85)
	(w["name"] as Label).text = String(o.get("name", "—"))
	(w["tag"] as Label).text = "%s · 永久" % String(tag)
	(w["tag"] as Label).add_theme_color_override("font_color", col)
	(w["desc"] as Label).text = String(o.get("desc", ""))
	var ic: EveIcon = w["icon"]
	ic.icon = StringName(o.get("icon", &"diamond"))
	ic.color = Color(col.r, col.g, col.b, 1.0)
	ic.queue_redraw()

	if taken:
		card.modulate = Color(1, 1, 1, 0.38)
		(w["foot"] as Label).text = "已获取"
		(w["foot"] as Label).add_theme_color_override("font_color", C_TEXT_FAINT)
		card.mouse_default_cursor_shape = Control.CURSOR_ARROW
	else:
		card.modulate = Color.WHITE
		(w["foot"] as Label).text = "点击选择"
		(w["foot"] as Label).add_theme_color_override("font_color", C_TEXT_DIM)
		card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.add_theme_stylebox_override("panel", _card_style(col, 0.72, false))


## 卡片背景。hover 时提亮 + 换分类色描边 —— 只动颜色，不动尺寸（否则鼠标一过卡片就跳）。
func _card_style(col: Color, bg_alpha: float, hover: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.035, 0.047, 0.055, bg_alpha + (0.10 if hover else 0.0))
	sb.border_color = Color(col.r, col.g, col.b, 0.85 if hover else 0.40)
	sb.set_border_width_all(1 if not hover else 2)
	sb.set_corner_radius_all(0)
	sb.content_margin_left = 0
	sb.content_margin_right = 0
	sb.content_margin_top = 0
	sb.content_margin_bottom = 0
	return sb


# ------------------------------------------------------------------ 交互

func _on_card_hover(index: int, entered: bool) -> void:
	if index < 0 or index >= _cards.size():
		return
	var opt = _options[index] if index < _options.size() else null
	if opt == null or bool((opt as Dictionary).get("taken", false)):
		return
	_hover = index if entered else -1
	var col := EveEventTable.tag_color(StringName((opt as Dictionary).get("tag", &"")))
	var w := _cards[index]
	(w["root"] as PanelContainer).add_theme_stylebox_override("panel",
			_card_style(col, 0.72, entered))
	var foot: Label = w["foot"]
	foot.add_theme_color_override("font_color", C_ACCENT if entered else C_TEXT_DIM)


func _on_card_input(event: InputEvent, index: int) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if index < 0 or index >= _options.size():
		return
	var o: Dictionary = _options[index]
	if bool(o.get("taken", false)):
		return
	if _pick_mode:
		ship_picked.emit(index)
		return
	option_chosen.emit(StringName(o.get("id", &"")))
