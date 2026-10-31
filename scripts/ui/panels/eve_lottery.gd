extends "res://scripts/ui/eve_window.gd"

## EVE 自走棋 —— 舰船抽奖窗口（炼狱专属 · 事件「黑市情报」）
##
## ★★ 2026-10-31（用户定案）：
##   「抽船事件单独做一个抽奖窗口 …… 下面会有一个许愿，让你在可能的舰船中选，
##     一星和二星舰船分开，选一个，如果真抽到了自己许愿的那个船，
##     就奖励舰船星币（二星舰船按一星舰船计价）」
##
## ── 这个窗口只做三件事 ─────────────────────────────────────────
##   ① 把**两个候选池**（一星 cost≥3 / 二星巡洋）摊开给玩家看；
##   ② 收集**两个愿望**（每池只能许一个，再点一次取消）；
##   ③ 把结果画出来（抽到谁 / 有没有命中 / 返了几个星币）。
##
##   ⛔ 数值一概不在这里算：抽取、落席、返币全在 `EveRunState.lottery_draw()`。
##     面板里出现第二份"命中判定"或"该退多少钱"，是最容易烂掉的那类分叉
##     （与 `eve_event.gd` 同一条规矩：面板只显示与回调）。
##
## ── 为什么两个池要分开摆 ───────────────────────────────────────
##   许愿栏是「一星选一个、二星选一个」。若两池合并成一列，
##   玩家会分不清自己许的是哪个池的船，二星那 12 艘也会被 32 艘一星淹没。

## 玩家点了「抽取」—— 两个愿望原样交给场景（空 = 没许愿）
signal draw_requested(wish1: StringName, wish2: StringName)
## 抽完点「完成」—— 场景据此推进节点
signal finished()

const CARD_W := 106.0
const CARD_H := 46.0
const POOL_COLS := 4

var _pool1: Array = []
var _pool2: Array = []
var _wish1: StringName = &""
var _wish2: StringName = &""
## ship_key → 卡片控件字典（高亮时按池分别取用）
var _cards1: Dictionary = {}
var _cards2: Dictionary = {}

var _intro: Label
var _pools_box: HBoxContainer
var _wish_label: Label
var _draw_btn: Button
var _result_box: VBoxContainer
var _grid1: GridContainer
var _grid2: GridContainer
var _drawn := false


func _ready() -> void:
	window_title = "舰船抽奖"
	density = Density.NORMAL
	super._ready()
	_build_contents()


# ------------------------------------------------------------------ 构建

func _build_contents() -> void:
	_intro = Label.new()
	_intro.text = ""
	_intro.add_theme_color_override("font_color", C_TEXT_DIM)
	FONT.fs(_intro, 11)
	_intro.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	_intro.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_intro.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(_intro)

	# 两池横排（各占一半）
	_pools_box = HBoxContainer.new()
	_pools_box.add_theme_constant_override("separation", 12)
	_pools_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(_pools_box)
	_pools_box.add_child(_build_pool_column("★1 · 3 费以上", C_ACCENT))
	_pools_box.add_child(_build_pool_column("★2 · 二星巡洋", C_GOLD))

	_wish_label = Label.new()
	_wish_label.add_theme_color_override("font_color", C_TEXT)
	FONT.fs(_wish_label, 11)
	_wish_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(_wish_label)

	# 结果区（抽完顶掉池子，同一块地方给答案）
	#
	# ⚠️ 它排在按钮**之前**是刻意的：VBox 的最后一个子节点才是"贴底"的那个。
	#    这里让结果区吃满剩余高度、按钮永远在最底 —— 抽取前 / 抽完后
	#    按钮位置不跳，玩家的手指（或鼠标）不用重新找它。
	_result_box = VBoxContainer.new()
	_result_box.add_theme_constant_override("separation", 10)
	_result_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_result_box.visible = false
	content.add_child(_result_box)

	_draw_btn = Button.new()
	_draw_btn.text = "抽 取"
	_draw_btn.custom_minimum_size = Vector2(0, 34)
	FONT.fs(_draw_btn, 13)
	_draw_btn.pressed.connect(_on_draw_pressed)
	content.add_child(_draw_btn)


## 一列 = 标题 + 可竖滚的网格。
##
## ⚠️ 池子必须能滚：一星池 32 艘、4 列 ⇒ 8 行，窗口绝对放不下。
##    用 `ScrollContainer` 而不是缩小卡片：卡太小名字就截断了，
##    而"看得清是哪艘船"正是许愿的前提。
func _build_pool_column(title: String, col: Color) -> Control:
	var col_box := VBoxContainer.new()
	col_box.add_theme_constant_override("separation", 5)
	col_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col_box.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var head := Label.new()
	head.text = title
	head.add_theme_color_override("font_color", col)
	FONT.fs(head, 11)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col_box.add_child(head)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	col_box.add_child(scroll)
	# ★ 2026-10-31：与全工程同口径，滚动条加宽到 10（默认 8 抓不住）
	widen_scrollbar(scroll)

	var grid := GridContainer.new()
	grid.columns = POOL_COLS
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid)
	if title.begins_with("★1"):
		_grid1 = grid
	else:
		_grid2 = grid
	return col_box


# ------------------------------------------------------------------ 对外

## 打开窗口。两个池 = `EveRunState.lottery_pool(1)` / `lottery_pool(2)` 的原样产物。
func show_lottery(pool1: Array, pool2: Array, line: String = "", meta: String = "") -> void:
	_pool1 = pool1
	_pool2 = pool2
	_wish1 = &""
	_wish2 = &""
	_drawn = false
	_intro.text = line
	set_status(meta)
	_pools_box.visible = true
	_result_box.visible = false
	_draw_btn.text = "抽 取"
	_draw_btn.disabled = false
	_fill_grid(_grid1, _cards1, 1, pool1)
	_fill_grid(_grid2, _cards2, 2, pool2)
	_refresh_wish_label()


## 抽完了：把结果画出来。`results` = 两次 `lottery_draw()` 的返回，可含 `{ok:false}`。
func show_result(results: Array) -> void:
	_drawn = true
	_pools_box.visible = false
	_result_box.visible = true
	_draw_btn.text = "完 成"
	_draw_btn.disabled = false
	# 顶部那句「点卡片许愿」在抽完之后就是错的，换成结果说明
	_intro.text = "抽奖完成 —— 船已进备战席（满了会折成星币），拖到棋盘即可上场"
	# 许愿行同理：抽完之后「再点一次取消」已经不可能发生了
	_wish_label.text = "许愿回顾：一星 → %s　·　二星 → %s" % [
			"未许愿" if _wish1 == &"" else _card_name(_cards1, _wish1),
			"未许愿" if _wish2 == &"" else _card_name(_cards2, _wish2)]
	for c in _result_box.get_children():
		c.queue_free()
	var head := Label.new()
	head.text = "抽取结果"
	head.add_theme_color_override("font_color", C_ACCENT)
	FONT.fs(head, 12)
	_result_box.add_child(head)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_result_box.add_child(row)
	for r in results:
		row.add_child(_build_result_card(r))


## 当前两个愿望（自检 / 断言用）。[0] = 一星池，[1] = 二星池；空 = 未许愿。
func current_wishes() -> Array[StringName]:
	return [_wish1, _wish2]


func is_drawn() -> bool:
	return _drawn


# ------------------------------------------------------------------ 池与卡

func _fill_grid(grid: GridContainer, cache: Dictionary, star: int, pool: Array) -> void:
	for c in grid.get_children():
		c.queue_free()
	cache.clear()
	for d in pool:
		var ship: Dictionary = d
		var key := StringName(ship.get("ship_key", &""))
		var w := _build_card(ship, star)
		var root: PanelContainer = w["root"]
		root.gui_input.connect(_on_card_input.bind(star, key))
		grid.add_child(root)
		cache[key] = w


func _build_card(ship: Dictionary, star: int) -> Dictionary:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(CARD_W, CARD_H)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.add_theme_stylebox_override("panel", _card_style(star, false))

	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 7)
	pad.add_theme_constant_override("margin_right", 5)
	pad.add_theme_constant_override("margin_top", 4)
	pad.add_theme_constant_override("margin_bottom", 4)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(pad)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 1)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_child(col)

	var nm := Label.new()
	nm.text = String(ship.get("name", "—"))
	nm.add_theme_color_override("font_color", Color(0.875, 0.949, 0.965))
	FONT.fs(nm, 10)
	# ⚠️ clip_text：不带它时 Label 的最小宽度 = 文本宽度 ⇒ 卡片会被长名字撑开，
	#    网格列宽参差不齐（商店卡 / 事件卡都踩过同一个坑）。
	nm.clip_text = true
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(nm)

	var sub := Label.new()
	sub.text = "%d 费 · %s" % [int(ship.get("cost", 0)), String(ship.get("faction_cn", ""))]
	sub.add_theme_color_override("font_color", C_TEXT_DIM)
	FONT.fs(sub, 9)
	sub.clip_text = true
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(sub)

	return {"root": card, "name": nm, "sub": sub}


## 卡片皮肤。
##
## ⚠️ 选中态必须**一眼看得出来**：第一版只把边框从 1px 加到 2px、alpha 0.34→1.0，
##    截图里几乎分辨不出（深底 + 细边，缩图后完全糊掉）。
##    现在三件事一起做：金边 2px + 偏金的底 + 名字转金色。
func _card_style(star: int, wished: bool) -> StyleBoxFlat:
	var col := C_GOLD if (star >= 2 or wished) else C_ACCENT
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.15, 0.125, 0.05, 0.96) if wished else Color(0.035, 0.047, 0.055, 0.72)
	sb.border_color = Color(col.r, col.g, col.b, 1.0 if wished else 0.34)
	sb.set_border_width_all(2 if wished else 1)
	sb.set_corner_radius_all(0)
	return sb


## 结果卡皮肤：比候选卡亮一档（它是"答案"，要压过底下的池子）。
func _result_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.055, 0.075, 0.088, 0.96)
	sb.border_color = Color(C_ACCENT.r, C_ACCENT.g, C_ACCENT.b, 0.55)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(0)
	return sb


func _on_card_input(event: InputEvent, star: int, key: StringName) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if _drawn:
		return
	# 再点一次同一张 = 取消许愿（否则玩家选错了就只能硬着头皮抽）
	if star >= 2:
		_wish2 = &"" if _wish2 == key else key
	else:
		_wish1 = &"" if _wish1 == key else key
	_apply_wish_visuals()
	_refresh_wish_label()


func _apply_wish_visuals() -> void:
	for key in _cards1.keys():
		var w: Dictionary = _cards1[key]
		var on := StringName(key) == _wish1
		(w["root"] as PanelContainer).add_theme_stylebox_override("panel",
				_card_style(1, on))
		(w["name"] as Label).add_theme_color_override("font_color",
				C_GOLD if on else Color(0.875, 0.949, 0.965))
	for key in _cards2.keys():
		var w: Dictionary = _cards2[key]
		var on := StringName(key) == _wish2
		(w["root"] as PanelContainer).add_theme_stylebox_override("panel",
				_card_style(2, on))
		(w["name"] as Label).add_theme_color_override("font_color",
				C_GOLD if on else Color(0.875, 0.949, 0.965))


func _refresh_wish_label() -> void:
	var a := "未许愿" if _wish1 == &"" else _card_name(_cards1, _wish1)
	var b := "未许愿" if _wish2 == &"" else _card_name(_cards2, _wish2)
	_wish_label.text = "许愿：一星 → %s　·　二星 → %s　（点卡片许愿，再点一次取消）" % [a, b]


func _card_name(cache: Dictionary, key: StringName) -> String:
	var w: Dictionary = cache.get(key, {})
	if w.is_empty():
		return String(key)
	return (w["name"] as Label).text




# ------------------------------------------------------------------ 按钮

func _on_draw_pressed() -> void:
	if _drawn:
		finished.emit()
		return
	_draw_btn.disabled = true
	draw_requested.emit(_wish1, _wish2)


# ------------------------------------------------------------------ 结果卡

func _build_result_card(r) -> Control:
	var card := PanelContainer.new()
	# ⚠️ 纵向**不要** EXPAND_FILL：结果只有四行字，撑满 400px 高就是一块黑砖
	#    （第一版就是这样，截图里结果卡像两个空面板）。
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	card.custom_minimum_size = Vector2(0, 108)
	card.add_theme_stylebox_override("panel", _result_style())

	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 12)
	pad.add_theme_constant_override("margin_right", 12)
	pad.add_theme_constant_override("margin_top", 10)
	pad.add_theme_constant_override("margin_bottom", 10)
	card.add_child(pad)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	pad.add_child(col)

	var res: Dictionary = r if r is Dictionary else {}
	var ok := bool(res.get("ok", false))
	var head := Label.new()
	head.add_theme_color_override("font_color", C_TEXT_DIM)
	FONT.fs(head, 10)
	col.add_child(head)

	if not ok:
		head.text = "抽取失败（候选池为空，请上报）"
		return card
	head.text = "★%d 抽到" % int(res.get("star", 1))

	var nm := Label.new()
	nm.text = String(res.get("name", "?"))
	nm.add_theme_color_override("font_color", Color(0.90, 0.96, 0.98))
	FONT.fs(nm, 18)
	col.add_child(nm)

	var info := Label.new()
	var placed := String(res.get("placed", "bench"))
	if placed == "bench":
		info.text = "%d 费 · 已进备战席" % int(res.get("cost", 0))
	else:
		info.text = "%d 费 · 备战席已满，折成 %d ◆" % [int(res.get("cost", 0)), int(res.get("cost", 0))]
	info.add_theme_color_override("font_color", C_TEXT_DIM)
	FONT.fs(info, 10)
	col.add_child(info)

	if bool(res.get("hit", false)):
		var hit := Label.new()
		hit.text = "许愿命中！+%d ◆" % int(res.get("reward", 0))
		hit.add_theme_color_override("font_color", C_GOLD)
		FONT.fs(hit, 12)
		col.add_child(hit)
	else:
		var miss := Label.new()
		miss.text = "未命中许愿"
		miss.add_theme_color_override("font_color", C_TEXT_FAINT)
		FONT.fs(miss, 10)
		col.add_child(miss)

	return card
