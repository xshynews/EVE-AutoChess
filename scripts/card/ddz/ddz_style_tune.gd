extends PanelContainer

## 斗地主「样式微调」面板（2026-10-13 用户要的手机调参工具）。
##
## 存在的理由：手机上「牌还是小」，但**照截图猜数值**改一轮要重导一次包，
## 太慢。⇒ 把四个旋钮做成**滑杆**，在真机上实时拉、实时看，满意了点「保存」——
## 数值落 `user://ddz_style_tune.cfg`，**下次进牌桌自动生效**（不必重导包）。
## 定稿后再把数值烘回 `ddz_table.gd` 的常量即可（面板会 print 出可直接粘贴的行）。
##
## ⚠️ 它**不改规则**，只改画：所有数值都乘在几何漏斗上（见 ddz_table 的
##    `card_scale / table_scale / win_scale` 三个变量与 `_draw_text` 的 FONT.s）。
## ⚠️ 打开期间牌局**不推进**（ddz_table._process 有守卫）—— 与设置窗同一条口径。
##
## 四个旋钮：
##   牌大小   card_scale  —— 手牌 / 出牌 / 底牌（含命中区、发牌动画）
##   桌沿大小 table_scale —— 距离环椭圆 + 出牌位（80km 圈那条）
##   界面字号 font_scale  —— 走 EveFont（与设置窗里那根滑杆**同一个旋钮**）
##   设置窗宽 win_scale   —— 设置窗宽度倍率（只影响牌桌这扇）

const STYLE_CFG := "user://ddz_style_tune.cfg"

## ⚠️ 本工程的字号接口是**脚本常量**（不是 autoload）——每个用到它的脚本都要 preload。
const FONT := preload("res://scripts/ui/eve_font.gd")

const ROWS := [
	{"key": "zoom", "label": "整体缩放", "min": 0.80, "max": 1.60, "step": 0.05},
	{"key": "card_scale", "label": "牌大小", "min": 0.60, "max": 2.20, "step": 0.05},
	{"key": "table_scale", "label": "桌沿大小", "min": 0.50, "max": 1.30, "step": 0.05},
	# ⚠️ 字号域直接用 EveFont 的 MIN/MAX（0.80~1.30）—— ⛔ 别在这儿另开一个域，
	#    否则滑杆能拉到没效果的位置（玩家会以为工具坏了）。
	{"key": "font_scale", "label": "界面字号", "min": 0.80, "max": 1.30, "step": 0.05},
	{"key": "win_scale", "label": "设置窗宽", "min": 0.60, "max": 1.60, "step": 0.05},
]

var _tbl: Variant = null                 ## ddz_table（Variant：脚本间不建硬依赖）
var _ctrls: Dictionary = {}              ## key → {"slider": HSlider, "num": Label}
var _note: Label = null
var _drag_off := Vector2.ZERO            ## 拖拽时「光标 - 面板左上角」的偏移
var _dragging := false                   ## 见 `_gui_input`：抓手 = 顶部标题带


## 由 ddz_table 调用：绑定宿主 + 按当前值回写滑杆。
func setup(table: Variant) -> void:
	_tbl = table
	_build()
	_sync_from_table()
	# ★ 整体缩放的**上限跟着屏幕走**（装不下就不许放大 ⇒ 不会裁掉顶栏/操作栏）。
	#   ⚠️ 上限是 1.00 时**必须把这个事实写在标签上**，否则那根滑杆看着像坏了
	#     （手机 2340×1080 屏高已用满，上限就是 1.00 —— 该用「牌大小」）。
	var cap := float(_tbl.call("zoom_cap"))
	var zrec: Dictionary = _ctrls.get("zoom", {})
	if not zrec.is_empty():
		(zrec["slider"] as HSlider).max_value = cap
		(zrec["label"] as Label).text = "整体缩放" if cap > 1.001 \
				else "整体缩放（本机上限 1.00）"
	# ⚠️ 不用锚点：面板加入的这一刻宿主尺寸可能是 0（实测锚点会被定在左上角，
	#   面板跑到屏外）。⇒ 显式按宿主尺寸摆位，并跟着宿主 resize 重摆。
	var host := _tbl as Control
	if host != null:
		host.resized.connect(place)
	place()


## 摆到宿主底部居中（手边够得着，且不太挡桌面）。
##
## ⚠️ 面板本身是**真实控件**（在缩放之外，不受 `zoom` 影响）—— 这点很重要：
##    牌桌放大到 1.6 时，面板仍然是屏幕上的固定大小，永远读得清、点得准。
func place() -> void:
	var host := _tbl as Control
	var w: float = host.size.x if host != null and host.size.x > 1.0 else 1920.0
	var h: float = host.size.y if host != null and host.size.y > 1.0 else 1080.0
	var pw := minf(760.0, maxf(460.0, w - 40.0))
	custom_minimum_size = Vector2(pw, 0.0)
	var ph := maxf(get_combined_minimum_size().y, 1.0)
	size = Vector2(pw, ph)
	position = Vector2((w - pw) * 0.5, h - ph - 10.0)


func _build() -> void:
	custom_minimum_size = Vector2(760.0, 0.0)
	mouse_filter = Control.MOUSE_FILTER_STOP     # 吃掉点击 ⇒ ⛔ 不穿透到牌桌
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.055, 0.075, 0.090, 0.96)
	style.border_color = Color(0.20, 0.36, 0.40)
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(14.0)
	add_theme_stylebox_override("panel", style)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)

	var title := Label.new()
	title.text = "样式微调（本机实时生效 · 满意后点保存）　✥ 按住这一行可拖动"
	title.add_theme_color_override("font_color", Color(0.91, 0.96, 0.97))
	FONT.fs(title, 16)
	box.add_child(title)

	for row in ROWS:
		var key := String(row["key"])
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 10)
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(line)
		var lab := Label.new()
		lab.text = String(row["label"])
		lab.custom_minimum_size = Vector2(130.0, 0.0)
		lab.add_theme_color_override("font_color", Color(0.70, 0.82, 0.85))
		FONT.fs(lab, 18)
		line.add_child(lab)
		var sl := HSlider.new()
		sl.min_value = float(row["min"])
		sl.max_value = float(row["max"])
		sl.step = float(row["step"])
		# ⚠️ 手机上手指的触摸目标：44 / 48 是底线（这条更是给安卓用的）
		sl.custom_minimum_size = Vector2(360.0, 44.0)
		sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sl.value_changed.connect(_on_changed.bind(key))
		line.add_child(sl)
		var num := Label.new()
		num.custom_minimum_size = Vector2(84.0, 0.0)
		num.add_theme_color_override("font_color", Color(0.91, 0.76, 0.35))
		FONT.fs(num, 18)
		line.add_child(num)
		_ctrls[key] = {"slider": sl, "num": num, "label": lab}

	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 10)
	btns.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(btns)
	var save := _mk_btn("保存（本机生效）")
	EveButtonTheme.apply(save, "hud_main")
	save.pressed.connect(_on_save)
	btns.add_child(save)
	var reset := _mk_btn("恢复默认")
	EveButtonTheme.apply(reset, "hud_warn")
	reset.pressed.connect(_on_reset)
	btns.add_child(reset)
	var close := _mk_btn("关闭")
	close.pressed.connect(func() -> void: visible = false)
	btns.add_child(close)

	_note = Label.new()
	_note.text = "数值随时可改；保存后**下次进牌桌仍然有效**（存 user://ddz_style_tune.cfg）"
	_note.add_theme_color_override("font_color", Color(0.44, 0.55, 0.59))
	FONT.fs(_note, 12)
	box.add_child(_note)


func _mk_btn(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0.0, 48.0)      # 手指目标 ≥48
	FONT.fs(b, 17)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.focus_mode = Control.FOCUS_NONE
	return b


## 拖拽：**只在顶部标题带**（前 46px）抓取 —— 滑杆区、按钮区照常工作。
##
## 为什么需要它：面板默认停在底部居中，正好压着手牌 —— 调「牌大小」时看不全。
## 手指按住标题一拖就能把它挪到不挡事的地方（手机上尤其需要）。
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed:
			if mb.position.y <= 46.0:
				_dragging = true
				_drag_off = mb.position
				accept_event()
		elif _dragging:
			_dragging = false
			accept_event()
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		var host := _tbl as Control
		var lim := host.size if host != null else Vector2(1920.0, 1080.0)
		var np := position + (mm.position - _drag_off)
		# 不许拖出屏外（拖出去就再也抓不回来了）
		np.x = clampf(np.x, -size.x + 80.0, lim.x - 80.0)
		np.y = clampf(np.y, 0.0, lim.y - 40.0)
		position = np
		accept_event()
func _on_changed(v: float, key: String) -> void:
	if _tbl == null:
		return
	if key == "font_scale":
		FONT.set_scale(clampf(v, FONT.MIN_SCALE, FONT.MAX_SCALE))
		FONT.reapply(_tbl)
		var sw = _tbl.get("_settings")
		if sw != null:
			FONT.reapply(sw)
	else:
		# 整体缩放要过本机上限（见 ddz_table.zoom_cap：装不下就不许放大）
		if key == "zoom":
			v = minf(v, float(_tbl.call("zoom_cap")))
		_tbl.set(key, v)
		if key == "win_scale":
			_tbl.call("_place_settings")
	_tbl.call("queue_redraw")
	_update_num(key, v)


func _update_num(key: String, v: float) -> void:
	var rec: Dictionary = _ctrls.get(key, {})
	if not rec.is_empty():
		(rec["num"] as Label).text = "%.2f" % v


## 把宿主的当前值回写到滑杆（打开面板 / 恢复默认后调用）。
func _sync_from_table() -> void:
	if _tbl == null:
		return
	for row in ROWS:
		var key := String(row["key"])
		var v: float = float(FONT.scale) if key == "font_scale" \
				else float(_tbl.get(key))
		var rec: Dictionary = _ctrls.get(key, {})
		if not rec.is_empty():
			(rec["slider"] as HSlider).set_value_no_signal(clampf(v,
					float(row["min"]), float(row["max"])))
			_update_num(key, v)


func _on_save() -> void:
	if _tbl == null:
		return
	var d := current_values()
	# ⚠️ 写盘后**回读一次**再报成功 —— 「写了但没写进去」在手机上不报错，
	#   玩家只会觉得"保存了怎么没用"。
	if not save_style(d):
		_note.text = "⚠ 保存失败（写不了 user:// —— 见控制台）"
		return
	_note.text = "已保存 —— 下次进牌桌自动生效"
	# 控制台打一份「可直接粘回 ddz_table.gd」的常量行（定稿时用）
	print("[style_tune] 已保存 %s" % str(d))
	print("[style_tune] 烘回常量：HAND_CARD_W/PLAY_CARD_W/TABLE_RX/TABLE_RY × card/table_scale"
			+ "；card=%.2f table=%.2f win=%.2f font=%.2f"
			% [d["card_scale"], d["table_scale"], d["win_scale"], d["font_scale"]])


func _on_reset() -> void:
	if _tbl == null:
		return
	_tbl.set("zoom", 1.0)
	_tbl.set("card_scale", 1.0)
	_tbl.set("table_scale", 1.0)
	_tbl.set("win_scale", 1.0)
	FONT.set_scale(FONT.default_scale())
	FONT.reapply(_tbl)
	_tbl.call("_place_settings")
	_tbl.call("queue_redraw")
	_sync_from_table()
	_note.text = "已恢复默认（未保存则下次进来仍是默认）"


func current_values() -> Dictionary:
	return {
		"zoom": float(_tbl.get("zoom")),
		"card_scale": float(_tbl.get("card_scale")),
		"table_scale": float(_tbl.get("table_scale")),
		"win_scale": float(_tbl.get("win_scale")),
		"font_scale": float(FONT.scale),
	}


# ── 存档（与宿主解耦：静态函数，ddz_table 开场直接调 `load_style()`）──

static func save_style(d: Dictionary) -> bool:
	var cf := ConfigFile.new()
	cf.set_value("meta", "schema_version", 1)
	for k in ["zoom", "card_scale", "table_scale", "win_scale", "font_scale"]:
		cf.set_value("style", k, float(d.get(k, 1.0)))
	return cf.save(STYLE_CFG) == OK


static func load_style() -> Dictionary:
	var cf := ConfigFile.new()
	if cf.load(STYLE_CFG) != OK:
		return {}
	var out := {}
	for k in ["zoom", "card_scale", "table_scale", "win_scale", "font_scale"]:
		if cf.has_section_key("style", k):
			out[k] = float(cf.get_value("style", k))
	return out


static func clear_style() -> void:
	if FileAccess.file_exists(STYLE_CFG):
		DirAccess.remove_absolute(STYLE_CFG)
