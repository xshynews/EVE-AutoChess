extends Control
class_name EveSlot

## EVE 自走棋 —— 通用槽位（装备格 / 空位）
##
## 空槽画虚线框（语义：可以放），满槽画实线框（语义：这里面有东西）。
## 装备栏位（左下 8 格）与舰船档案（装备 2 格）共用这一个类 ——
## 两处的槽位必须长得一样，抽出来是为了避免哪天改一处忘一处。
##
## ⚠️ Godot 的 StyleBoxFlat 不支持虚线边框，所以整体自绘。

const FONT := preload("res://scripts/ui/eve_font.gd")

const DASH := 4.0
const GAP := 3.0
## 序号标签只在格子被拉得足够高时才显示（手机档 8 格 2×4 ⇒ 格高 ~130；
## 桌面档 35 高的格子塞一行字会压到图标 ⇒ 自动隐藏，PC 观感不变）。
const TAG_SHOW_H := 56.0

## 槽里有没有东西
var filled: bool = false: set = set_filled
## 满槽时的强调色（用于图标描边，可由调用方设）
var accent: Color = Color(0.70, 0.82, 0.85)
## 槽位序号（装备栏 Ⅰ~Ⅷ）—— 空槽时让「8 个固定位」可被指认。
## ⚠️ 只在格子够高时可见（见 `TAG_SHOW_H`）；⛔ 别用它存业务数据。
var tag: String = "": set = set_tag

var _tag_lb: Label = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_filled(v: bool) -> void:
	filled = v
	queue_redraw()


func set_tag(v: String) -> void:
	tag = v
	_ensure_tag_lb()
	_refresh_tag_visible()


func _ensure_tag_lb() -> void:
	if _tag_lb != null or tag == "":
		return
	_tag_lb = Label.new()
	_tag_lb.name = "Tag"
	_tag_lb.add_theme_color_override("font_color", Color(0.35, 0.43, 0.47))
	FONT.fs(_tag_lb, 9)
	_tag_lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tag_lb.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_tag_lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tag_lb.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_tag_lb.offset_top = 3.0
	add_child(_tag_lb)


func _refresh_tag_visible() -> void:
	if _tag_lb == null:
		return
	_tag_lb.text = tag
	_tag_lb.visible = tag != "" and size.y >= TAG_SHOW_H


func _notification(what: int) -> void:
	# 格子被拉高（手机档）⇒ 序号亮出来；收回（桌面档）⇒ 收回去
	if what == NOTIFICATION_RESIZED:
		_refresh_tag_visible()


func _draw() -> void:
	var full := Rect2(Vector2.ZERO, size)
	var inner := Rect2(Vector2(0.5, 0.5), size - Vector2(1.0, 1.0))
	if filled:
		draw_rect(full, Color(0.035, 0.047, 0.055, 0.72))
		draw_rect(inner, Color(0.42, 0.55, 0.60, 0.42), false, 1.0)
	else:
		draw_rect(full, Color(0.035, 0.047, 0.055, 0.40))
		_dashed_rect(inner, Color(0.42, 0.55, 0.60, 0.22))


func _dashed_rect(r: Rect2, col: Color) -> void:
	var seg := DASH + GAP
	var x := r.position.x
	while x < r.end.x:
		var x2 := minf(x + DASH, r.end.x)
		draw_line(Vector2(x, r.position.y), Vector2(x2, r.position.y), col, 1.0)
		draw_line(Vector2(x, r.end.y), Vector2(x2, r.end.y), col, 1.0)
		x += seg
	var y := r.position.y
	while y < r.end.y:
		var y2 := minf(y + DASH, r.end.y)
		draw_line(Vector2(r.position.x, y), Vector2(r.position.x, y2), col, 1.0)
		draw_line(Vector2(r.end.x, y), Vector2(r.end.x, y2), col, 1.0)
		y += seg


## 建好一格（含图标子节点），返回 {"root": EveSlot, "icon": EveIcon}
static func make_with_icon(px: float) -> Dictionary:
	var slot := EveSlot.new()
	slot.custom_minimum_size = Vector2(px, px)
	slot.size = Vector2(px, px)

	var icon := EveIcon.new()
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.visible = false
	slot.add_child(icon)

	return {"root": slot, "icon": icon}


## 往一格塞装备（item = {"icon": StringName, "color": Color}；传 null 清空）
static func fill(slot_icon: Dictionary, item) -> void:
	var slot: EveSlot = slot_icon["root"]
	var icon: EveIcon = slot_icon["icon"]
	if item == null or (item is Dictionary and (item as Dictionary).is_empty()):
		slot.filled = false
		icon.visible = false
		return
	var d: Dictionary = item
	slot.filled = true
	icon.icon = d.get("icon", &"plus")
	icon.color = d.get("color", slot.accent)
	icon.visible = true
