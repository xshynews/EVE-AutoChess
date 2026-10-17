extends Button

## 试听台单元格（候选按钮 / 确定投放格双形态，仅服务 probe_ddz_sfx_listen）。
## 候选形态：点击=试听（play_requested）；按住拖动=带走 drag 数据。
## 确定形态：接受 drag 投放（picked）；右键清除（cleared）；有点击即重听。

signal play_requested(path: String)
signal picked(event: String, path: String)
signal cleared(event: String)

var _event := ""
var _path := ""
var _slot := false


func setup_candidate(p_path: String, p_label: String) -> void:
	_slot = false
	_path = p_path
	text = p_label
	tooltip_text = p_path
	add_theme_font_size_override("font_size", 13)
	focus_mode = Control.FOCUS_NONE


func setup_slot(p_event: String) -> void:
	_slot = true
	_event = p_event
	text = "（拖入音效）"
	add_theme_font_size_override("font_size", 13)
	custom_minimum_size = Vector2(230.0, 30.0)
	focus_mode = Control.FOCUS_NONE


func fill_slot(p_path: String, p_label: String) -> void:
	_path = p_path
	text = "✔ " + p_label
	tooltip_text = p_path


func _get_drag_data(_pos: Vector2) -> Variant:
	if _slot or _path.is_empty():
		return null
	var prev := Label.new()
	prev.text = "🔊 " + text
	set_drag_preview(prev)
	return {"kind": "ddz_sfx", "path": _path, "label": text}


func _can_drop_data(_pos: Vector2, data: Variant) -> bool:
	return _slot and data is Dictionary and data.get("kind", "") == "ddz_sfx"


func _drop_data(_pos: Vector2, data: Variant) -> void:
	fill_slot(data["path"], data["label"])
	picked.emit(_event, _path)
	play_requested.emit(_path)


func _pressed() -> void:
	if not _path.is_empty():
		play_requested.emit(_path)


func _gui_input(event: InputEvent) -> void:
	if _slot and event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_RIGHT:
		_path = ""
		text = "（拖入音效）"
		tooltip_text = ""
		cleared.emit(_event)
		accept_event()
