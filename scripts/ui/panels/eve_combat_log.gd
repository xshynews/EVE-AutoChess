extends "res://scripts/ui/eve_window.gd"

## EVE 自走棋 —— 战斗日志窗（右列下）
##
## V3 稿尺寸 172 × 200，位于舰船档案正下方。
##
## ── 与上一版的差别（窄栏重做）────────────────────────────────────
##   旧版是 320 宽 + 5 个分类过滤按钮 + 每行「时间戳 / 色块 / 自动换行文本」。
##   塞进 172 宽之后：
##     ① 过滤按钮行整行删掉 —— 5 个按钮在 154px 里每个只剩 30px，读不出来。
##        过滤能力改由「分类色块 + 分类文字前缀」承担，这个宽度只够做这个。
##     ② 文本不再自动换行，超出用省略号。窄栏里换行会把一条日志撑成三行，
##        200px 高只装得下 6 条，还不如不换。
##
## 变更清单（实装版）：
##   - 窄栏紧凑行（时间戳 30px + 分类色块 + 单行省略文本）
##   - 分类前缀用中文小字（结算 / 拾取 / 装备 / 打捞 / 提示 / 射击 / 破层）
##   - 自动滚动到底 + 上限裁剪

const MAX_LINES := 120

const CAT_COLORS := {
	&"fire": Color(0.62, 0.80, 0.86),
	&"damage": Color(0.88, 0.45, 0.35),
	&"break": Color(0.90, 0.68, 0.30),
	&"system": Color(0.48, 0.58, 0.62),
	&"economy": Color(0.60, 0.76, 0.48),
	# 阶段 B 新增两类：布阵与出售都是「编制」类操作，用同一个偏青的色
	&"deploy": Color(0.55, 0.78, 0.82),
	&"sell": Color(0.88, 0.62, 0.35),
	# 2026-10-01 后勤舰给友军修血。用**医疗绿**，与「损伤红」「破层橙」拉开：
	# 玩家扫日志时要能一眼分清「我掉了多少」与「我补回了多少」。
	&"repair": Color(0.52, 0.86, 0.68),
}

## 分类 → 行首小字。没有对应分类就不显示前缀。
const CAT_LABELS := {
	&"economy": "结算",
	&"loot": "拾取",
	&"equip": "装备",
	&"salvage": "打捞",
	&"hint": "提示",
	&"buy": "购买",
	&"deploy": "部署",
	&"sell": "出售",
	&"system": "系统",
	&"damage": "损伤",
	&"break": "破层",
	&"fire": "射击",
	&"repair": "后勤",
}

## ★ 2026-10-11（i18n）：文案取词（见 `eve_text.gd` 顶注）。
const T := preload("res://scripts/core/eve_text.gd")

var _scroll: ScrollContainer
var _list: VBoxContainer
var _entries: Array = []
var _built := false


func _ready() -> void:
	window_title = T.t("LOG_TITLE", "战斗日志")
	density = Density.COMPACT
	show_status_text = false
	super._ready()
	_build_contents()
	_built = true


func _build_contents() -> void:
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.custom_minimum_size = Vector2(0, 120)
	content.add_child(_scroll)

	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 1)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_list)


## 写入一条日志。entry 需要 .time / .category / .text 三个字段
func append_entry(entry) -> void:
	_entries.append(entry)
	if _entries.size() > 400:
		_entries = _entries.slice(_entries.size() - 300)
	_append_line(entry)
	_trim()
	_scroll_to_bottom()


func append_text(text: String, category: StringName = &"system",
		time: float = 0.0) -> void:
	var e := {
		"time": time, "category": category, "text": text,
	}
	append_entry(e)


func _append_line(entry) -> void:
	var cat: StringName = _cat_of(entry)
	var time_v := _time_of(entry)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var t := Label.new()
	t.text = "%04.1f" % time_v
	t.add_theme_color_override("font_color", Color(0.34, 0.43, 0.47))
	FONT.fs(t, 9)
	t.custom_minimum_size = Vector2(30, 0)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(t)

	var chip := ColorRect.new()
	chip.color = CAT_COLORS.get(cat, Color(0.4, 0.5, 0.5))
	chip.custom_minimum_size = Vector2(3, 11)
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(chip)

	var text := Label.new()
	# ⚠️ 必须显式标注 String —— Dictionary.get() 返回 Variant，
	#    用 := 推断会被判为「从 Variant 推断类型」而报错（工程把它当 error）。
	var prefix: String = T.t("LOG_CAT_%s" % String(cat).to_upper(),
			String(CAT_LABELS.get(cat, "")))
	text.text = ("%s " % prefix if prefix != "" else "") + _text_of(entry)
	text.add_theme_color_override("font_color", _text_color_for(cat))
	FONT.fs(text, 9)
	text.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if prefix != "":
		text.tooltip_text = String(_text_of(entry))
	row.add_child(text)

	_list.add_child(row)


static func _cat_of(entry) -> StringName:
	if entry is Dictionary:
		return StringName(entry.get("category", &"system"))
	var v = entry.get("category")
	return StringName(v) if v != null else &"system"


static func _time_of(entry) -> float:
	if entry is Dictionary:
		return float(entry.get("time", 0.0))
	var v = entry.get("time")
	return float(v) if v != null else 0.0


static func _text_of(entry) -> String:
	if entry is Dictionary:
		return String(entry.get("text", ""))
	var v = entry.get("text")
	return String(v) if v != null else ""


func _text_color_for(cat: StringName) -> Color:
	match cat:
		&"damage": return Color(0.80, 0.56, 0.50)
		&"break": return Color(0.82, 0.68, 0.44)
		&"system": return Color(0.55, 0.64, 0.68)
		&"economy": return Color(0.62, 0.78, 0.52)
		_: return Color(0.66, 0.78, 0.82)


func _trim() -> void:
	while _list.get_child_count() > MAX_LINES:
		var first := _list.get_child(0)
		_list.remove_child(first)
		first.queue_free()


func _scroll_to_bottom() -> void:
	if _scroll == null:
		return
	await get_tree().process_frame
	if is_instance_valid(_scroll):
		_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)


func clear_log() -> void:
	_entries.clear()
	if _list:
		for c in _list.get_children():
			c.queue_free()
