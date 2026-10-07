extends "res://scripts/ui/eve_window.gd"

## EVE 自走棋 —— 装备栏位
##
## V3 稿尺寸 172 × 116，左下。2 行 × 4 列 = 8 格（用户定死：只能攒 8 个）。
##
## 空槽画虚线框（表示「可以放」），有装备画实线框 + 描边图标。
## 每格 35px 高，图标 18px —— 尺寸来自 V3 稿的 .eq / .eq svg。
##
## 变更清单（实装版）：
##   - 8 槽自绘（虚线空态 / 实线满态）
##   - set_slots() 接装备数组；put()/take() 单格操作
##   - 满仓时标题栏右侧显示「8 / 8」并转橙

const SLOT_COUNT := 8
const SLOT_H := 35.0

var capacity: int = SLOT_COUNT
var _slots: Array[Control] = []
var _icons: Array[EveIcon] = []
var _items: Array = []


func _ready() -> void:
	window_title = "装备栏位"
	density = Density.COMPACT
	super._ready()
	_build_contents()
	set_slots([])


func _build_contents() -> void:
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(grid)

	for i in SLOT_COUNT:
		var pair := EveSlot.make_with_icon(SLOT_H)
		var slot: EveSlot = pair["root"]
		slot.custom_minimum_size = Vector2(0, SLOT_H)
		slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(slot)

		_slots.append(slot)
		_icons.append(pair["icon"])


## 整批设置。items 里每项 = {"icon": StringName, "color": Color}，null / {} 表示空槽
func set_slots(items: Array) -> void:
	_items = items.duplicate()
	for i in SLOT_COUNT:
		var it = items[i] if i < items.size() else null
		_set_slot(i, it)
	_refresh_status()


func _set_slot(i: int, item) -> void:
	var slot: EveSlot = _slots[i]
	var ic: EveIcon = _icons[i]
	if item == null or (item is Dictionary and (item as Dictionary).is_empty()):
		slot.filled = false
		ic.visible = false
		return
	var d: Dictionary = item
	slot.filled = true
	ic.icon = d.get("icon", &"plus")
	ic.color = d.get("color", C_TEXT)
	ic.visible = true


## 放入一格（返回是否成功）
func put(index: int, item: Dictionary) -> bool:
	if index < 0 or index >= SLOT_COUNT:
		return false
	if index >= _items.size():
		_items.resize(index + 1)
	_items[index] = item
	_set_slot(index, item)
	_refresh_status()
	return true


## 取走一格（返回被取走的装备，空槽返回 {}）
func take(index: int) -> Dictionary:
	if index < 0 or index >= _items.size():
		return {}
	var it = _items[index]
	_items[index] = null
	_set_slot(index, null)
	_refresh_status()
	return it if it is Dictionary else {}


func used() -> int:
	var n := 0
	for it in _items:
		if it != null and (not (it is Dictionary) or not (it as Dictionary).is_empty()):
			n += 1
	return n


func _refresh_status() -> void:
	var n := used()
	set_status("%d / %d" % [n, capacity])
	if _status_label:
		_status_label.add_theme_color_override("font_color",
				C_WARN if n >= capacity else C_TEXT_DIM)
