extends "res://scripts/ui/eve_window.gd"

## EVE 自走棋 —— 舰船抽奖窗口（炼狱专属 · 事件「黑市情报」）
##
## ★★ 2026-10-31（用户定案，两次来回）：
##   第一版需求：「抽船事件单独做一个抽奖窗口 …… 下面会有一个许愿，
##     让你在可能的舰船中选，一星和二星舰船分开，选一个，
##     如果真抽到了自己许愿的那个船，就奖励舰船星币（二星舰船按一星舰船计价）」
##   纠正：「一星二星**全部进一个池子**……二星不是单独的池子，玩家**只能选一艘**」
##
## ── 这个窗口只做三件事 ─────────────────────────────────────────
##   ① 把**一个合并池**（一星 32 + 二星 12 = 44 张）摊开给玩家看；
##   ② 收集**一个愿望**（再点一次取消；点另一张就换）；
##   ③ 把结果画出来（抽到谁 / 有没有命中 / 返了几个星币）。
##
##   ⛔ 数值一概不在这里算：抽取、落席、返币全在 `EveRunState.lottery_draw()`。
##     面板里出现第二份"命中判定"或"该退多少钱"，是最容易烂掉的那类分叉
##     （与 `eve_event.gd` 同一条规矩：面板只显示与回调）。
##
## ── 为什么卡片键是 `ship_key#star` 而不是 `ship_key` ──────────────
##   合并池里**必然有 12 对同名条目**：一星池是「cost ≥ 3 全量」，本来就含
##   cost == 3 的那 12 艘巡洋；二星池又是同样这 12 艘的 ★2 版本。
##   若拿 `ship_key` 当键，后写的一张卡会把前一张覆盖掉 ⇒ 池子里少 12 张，
##   而且点同名另一张会高亮错卡。所以键必须带星级。
##
## ── 星级怎么区分（一栏里混排）────────────────────────────────────
##   原来是两栏两张表，星级靠"在哪一栏"表达。合并成一栏之后只能靠卡面：
##   ★1 用青色边（C_ACCENT）、★2 用金色边（C_GOLD），副标题里也写清 `★n`。
##   ⚠️ 别再靠"名字后加个 2"之类的隐晦手段 —— 二星船名和一星一模一样，
##      玩家一眼扫过去分不出来，就会许错愿。

## 玩家点了「抽取」—— 愿望原样交给场景（空 = 没许愿）
signal draw_requested(wish_key: StringName, wish_star: int)
## 抽完点「完成」—— 场景据此推进节点
signal finished()

const CARD_W := 106.0
const CARD_H := 46.0
## 一栏 8 列：窗口 1000 宽，8×106 + 7×6 ≈ 890，刚好，再宽就得横向滚
const POOL_COLS := 8

## 显示名取词（与商店卡 / 羁绊窗同一口径）。
const TERMS := preload("res://scripts/core/eve_terms.gd")

var _pool: Array = []
## 许愿：船 + 星级（两者一起才唯一 —— 同名 ★1/★2 是两个不同奖品）
var _wish_key: StringName = &""
var _wish_star := 0
## `ship_key#star` → 卡片控件字典
var _cards: Dictionary = {}

var _intro: Label
var _pools_box: VBoxContainer
var _wish_label: Label
var _draw_btn: Button
var _result_box: VBoxContainer
var _grid: GridContainer
var _drawn := false


func _ready() -> void:
	window_title = "舰船抽奖"
	density = Density.NORMAL
	super._ready()
	# ★ 窗底**全实底**（alpha=1.0）：
	#   其它窗口内容基本填满，0.84 的 HUD 透底质感没问题；
	#   但抽奖窗抽完后只剩两张结果卡，大片空白区会把**背后的事件文本**
	#   透出来 —— 实测 0.97 仍能认出"前方发现残骸信号…"（3% 透底在暗底上
	#   足够刺眼），0.84 就更别提了。模态打断窗没有"要看穿"的理由，
	#   只覆盖本窗，不动 EveWindow 全局基线。
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.043, 0.058, 0.068, 1.0)
	sb.border_color = EveWindow.C_BORDER
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(0)
	add_theme_stylebox_override("panel", sb)
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

	# 单池（占满宽度，可竖滚）
	_pools_box = VBoxContainer.new()
	_pools_box.add_theme_constant_override("separation", 5)
	_pools_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(_pools_box)
	_pools_box.add_child(_build_pool())

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


## 唯一的那一栏 = 图例 + 可竖滚的网格。
##
## ⚠️ 池子必须能滚：44 张 / 8 列 = 6 行，窗口还塞得下，但**别指望它永远塞得下**
##    （以后往池子里加船就会溢出）。用 `ScrollContainer` 而不是缩小卡片：
##    卡太小名字就截断了，而"看得清是哪艘船"正是许愿的前提。
func _build_pool() -> Control:
	var col_box := VBoxContainer.new()
	col_box.add_theme_constant_override("separation", 5)
	col_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col_box.size_flags_vertical = Control.SIZE_EXPAND_FILL

	# 星级图例 —— 合并成一栏后，这是玩家唯一的分辨依据
	var head := Label.new()
	head.text = "候选池 · 共 44 艘　　■ 青色 = ★1　■ 金色 = ★2（二星巡洋）"
	head.add_theme_color_override("font_color", C_TEXT_DIM)
	FONT.fs(head, 10)
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

	_grid = GridContainer.new()
	_grid.columns = POOL_COLS
	_grid.add_theme_constant_override("h_separation", 6)
	_grid.add_theme_constant_override("v_separation", 6)
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_grid)
	return col_box


# ------------------------------------------------------------------ 对外

## 打开窗口。`pool` = `EveRunState.lottery_pool()` 的原样产物（合并池）。
func show_lottery(pool: Array, line: String = "", meta: String = "") -> void:
	_pool = pool
	_wish_key = &""
	_wish_star = 0
	_drawn = false
	_intro.text = line
	set_status(meta)
	_pools_box.visible = true
	_result_box.visible = false
	_draw_btn.text = "抽 取"
	_draw_btn.disabled = false
	_fill_grid(pool)
	_refresh_wish_label()


## 抽完了：把结果画出来。`results` = 若干次 `lottery_draw()` 的返回，可含 `{ok:false}`。
func show_result(results: Array) -> void:
	_drawn = true
	_pools_box.visible = false
	_result_box.visible = true
	_draw_btn.text = "完 成"
	_draw_btn.disabled = false
	# 顶部那句「点卡片许愿」在抽完之后就是错的，换成结果说明
	_intro.text = "抽奖完成 —— 船已进备战席（满了会折成星币），拖到棋盘即可上场"
	# 许愿行同理：抽完之后「再点一次取消」已经不可能发生了
	_wish_label.text = "许愿回顾：%s" % _wish_text()
	for c in _result_box.get_children():
		c.queue_free()
	var head := Label.new()
	head.text = "抽取结果（%d 艘）" % results.size()
	head.add_theme_color_override("font_color", C_ACCENT)
	FONT.fs(head, 12)
	_result_box.add_child(head)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_result_box.add_child(row)
	for r in results:
		row.add_child(_build_result_card(r))


## 当前愿望（自检 / 断言用）。空 key = 未许愿。
func current_wish() -> Dictionary:
	return {"key": _wish_key, "star": _wish_star}


func is_drawn() -> bool:
	return _drawn


## 池子里有多少张卡（自检用：合并池必须等于 44，别被同名覆盖吃掉 12 张）
func card_count() -> int:
	return _cards.size()


# ------------------------------------------------------------------ 池与卡

## 卡片/许愿的唯一键：`ship_key#star`（同名 ★1/★2 必须能分开）
static func _card_id(key: StringName, star: int) -> String:
	return "%s#%d" % [String(key), star]


func _fill_grid(pool: Array) -> void:
	for c in _grid.get_children():
		c.queue_free()
	_cards.clear()
	for d in pool:
		var ship: Dictionary = d
		var key := StringName(ship.get("ship_key", &""))
		var star := clampi(int(ship.get("star", 1)), 1, 2)
		var w := _build_card(ship, star)
		var root: PanelContainer = w["root"]
		root.gui_input.connect(_on_card_input.bind(key, star))
		_grid.add_child(root)
		_cards[_card_id(key, star)] = w


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

	# 一星二星同名，名字必须带星级前缀 —— 只靠边框色，扫视时容易看错
	var nm := Label.new()
	nm.text = "★%d %s" % [star, String(ship.get("name", "—"))]
	nm.add_theme_color_override("font_color", Color(0.875, 0.949, 0.965))
	FONT.fs(nm, 10)
	# ⚠️ clip_text：不带它时 Label 的最小宽度 = 文本宽度 ⇒ 卡片会被长名字撑开，
	#    网格列宽参差不齐（商店卡 / 事件卡都踩过同一个坑）。
	nm.clip_text = true
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(nm)

	# ★ 2026-10-31（用户：「巨鸟等船的卡牌上没有电子战羁绊标签，这不行，加上」）：
	#   副标题行改成「N 费 · 派系」+（电子战船才有的）紫色「电子战」。
	#   ⚠️ 宽度账（卡 106 − 左右内边距 12 = 94px 可用）：
	#        「3 费 · 米玛塔尔」≈ 4 字 36 + 前缀 15 = 51px
	#        「·电子战」     ≈ 36px            ⇒ 合计 ~87px，放得下；
	#      派系名再长也不会把标签挤没 —— `sub` 吃 EXPAND_FILL 且 clip_text，
	#      被压缩的只会是派系名，标签用 SHRINK_END 保完整。
	#   ⛔ 别用「EW」这种缩写：玩家不认识，而卡片宽度只差 12px。
	var sub_row := HBoxContainer.new()
	sub_row.add_theme_constant_override("separation", 2)
	sub_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(sub_row)

	var sub := Label.new()
	sub.text = "%d 费 · %s" % [int(ship.get("cost", 0)), String(ship.get("faction_cn", ""))]
	sub.add_theme_color_override("font_color", C_TEXT_DIM)
	FONT.fs(sub, 9)
	sub.clip_text = true
	sub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sub_row.add_child(sub)

	# 判据唯一真源 = `EveTraitTable.EW_SHIP_KEYS`（走公开入口 `is_ew_ship`）。
	if EveTraitTable.is_ew_ship(ship):
		var ew := Label.new()
		ew.text = "·" + TERMS.trait_member(&"ew", "电子战")
		ew.add_theme_color_override("font_color", EveTraitTable.EW_COLOR)
		FONT.fs(ew, 9)
		ew.size_flags_horizontal = Control.SIZE_SHRINK_END
		ew.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sub_row.add_child(ew)

	# ★ 2026-10-31：后勤标签（与电子战完全对称，判据走公开入口）。
	#   ⚠️ 卡宽 106px，两个标签同时出现会挤掉派系名 —— 这是**有意的取舍**：
	#      派系名上面那张卡在羁绊窗/档案里都查得到，而「这条船属于哪条羁绊」
	#      在抽奖池里是选牌的唯一依据。`sub` 已 EXPAND_FILL + clip_text，
	#      被压缩的只会是派系名，标签保完整（SHRINK_END）。
	if EveTraitTable.is_logi_ship(ship):
		var lg := Label.new()
		lg.text = "·" + TERMS.trait_member(&"logi", "后勤")
		lg.add_theme_color_override("font_color", EveTraitTable.LOGI_COLOR)
		FONT.fs(lg, 9)
		lg.size_flags_horizontal = Control.SIZE_SHRINK_END
		lg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sub_row.add_child(lg)

	return {"root": card, "name": nm, "sub": sub, "star": star}


## 卡片皮肤。
##
## ⚠️ 选中态必须**一眼看得出来**：第一版只把边框从 1px 加到 2px、alpha 0.34→1.0，
##    截图里几乎分辨不出（深底 + 细边，缩图后完全糊掉）。
##    现在三件事一起做：金边 2px + 偏金的底 + 名字转金色。
##
## ⚠️ 未选中时，★2 也要比 ★1 显眼（金边 vs 青边）—— 否则合并池里
##    12 张二星卡被 32 张一星淹没，玩家根本不知道池子里有二星。
func _card_style(star: int, wished: bool) -> StyleBoxFlat:
	var col := C_GOLD if (star >= 2 or wished) else C_ACCENT
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.15, 0.125, 0.05, 0.96) if wished else Color(0.035, 0.047, 0.055, 0.72)
	sb.border_color = Color(col.r, col.g, col.b, 1.0 if wished else (0.55 if star >= 2 else 0.34))
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


func _on_card_input(event: InputEvent, key: StringName, star: int) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if _drawn:
		return
	# 再点一次同一张 = 取消许愿（否则玩家选错了就只能硬着头皮抽）
	# 点另一张 = 直接换过去（只能许一艘，不是"每张各记一个"）
	if _wish_key == key and _wish_star == star:
		_wish_key = &""
		_wish_star = 0
	else:
		_wish_key = key
		_wish_star = star
	_apply_wish_visuals()
	_refresh_wish_label()


func _apply_wish_visuals() -> void:
	for id in _cards.keys():
		var w: Dictionary = _cards[id]
		var star := int(w.get("star", 1))
		var on := _wish_key != &"" and String(id) == _card_id(_wish_key, _wish_star)
		(w["root"] as PanelContainer).add_theme_stylebox_override("panel",
				_card_style(star, on))
		(w["name"] as Label).add_theme_color_override("font_color",
				C_GOLD if on else Color(0.875, 0.949, 0.965))


func _refresh_wish_label() -> void:
	_wish_label.text = "许愿：%s　（点卡片许愿 · 只能选一艘 · 再点一次取消）" % _wish_text()


func _wish_text() -> String:
	if _wish_key == &"":
		return "未许愿"
	var w: Dictionary = _cards.get(_card_id(_wish_key, _wish_star), {})
	var nm := String(_wish_key) if w.is_empty() else (w["name"] as Label).text
	return nm


# ------------------------------------------------------------------ 按钮

func _on_draw_pressed() -> void:
	if _drawn:
		finished.emit()
		return
	_draw_btn.disabled = true
	draw_requested.emit(_wish_key, _wish_star)


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
