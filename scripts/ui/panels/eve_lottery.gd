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
## ── 星级怎么区分（矩阵里混排）────────────────────────────────────
##   原来是一栏一张平铺网格，星级只能靠卡面分辨。现在**★2 单独成一段**
##   压在池子最下面（用户 2026-11-01 的要求），段头是金色分隔线；
##   段内仍按同样的「费用行 × 定位列」排，所以位置一眼可预期。
##   ★1 用青色边（C_ACCENT）、★2 用金色边（C_GOLD），名字前面还有 `★n`。
##   ⚠️ 别再靠"名字后加个 2"之类的隐晦手段 —— 二星船名和一星一模一样，
##      玩家一眼扫过去分不出来，就会许错愿。

## 玩家点了「抽取」—— 愿望原样交给场景（空 = 没许愿）
signal draw_requested(wish_key: StringName, wish_star: int)
## 抽完点「完成」—— 场景据此推进节点
signal finished()

const CARD_W := 100.0
const CARD_H := 44.0

## ══════════════════════════════════════════════════════════════════
##  「同级一行 · 同定位一列」的矩阵排版
## ══════════════════════════════════════════════════════════════════
##  ★ 2026-11-01（用户）：「抽船那个事件，在选船的时候，因为太多，不太好选，
##    建议做做分类，同级的一行，同定位的一列，二星的在下面」。
##
##  行 = 费用档（3 费巡洋 / 4 费战巡 / 5 费战列）；★2 单独成一段放最下面；
##  列 = 定位（攻击型 / 防御型 / 后勤）。
##
##  ⚠️ 定位用 **`role_id`（attack/defense/logi）** 分组，⛔ 不认中文名
##     —— 与全工程同一条红线（见 `EveCombatIds` 顶注）。
##     ⛔ 别改用图鉴那套五档（含电子战 / 加强型）：那五档是**互斥**口径
##     （电子战船从「攻击型 / 防御型」里扣掉），拿来做列会得到 5 列，
##     而 5 列 × 两行卡 ≈ 1090px，塞不进 970px 的内容区 —— 只能退化成
##     每列 1 张卡宽、竖向堆 4 层，整池高度翻倍。三列是这个窗口装得下
##     且信息量最大的分法。电子战/后勤标签仍在卡面上单独标（正交信息）。
##
##  ⚠️ 列宽**固定**、不随内容长短伸缩：格内卡片按 `POOL_CELL_ROWS` 行折行，
##     于是每个费用档正好两行卡、行高一致。列宽取「该列最挤那档」所需宽度
##     （目前是 5 费防御型 8 艘 ⇒ 4 个子列），空出来的格子留白 ——
##     宁可留白也不能让列宽逐行变化，那样「同定位一列」当场就散了。
const POOL_CELL_ROWS := 2
const POOL_GAP := 6
## 三个定位列之间的间距（比格内间距大，用来把「列」切出来）
const POOL_BAND_GAP := 14
## 左侧费用栏宽度：竖排「3 费 / 巡洋」两行
const POOL_GUTTER := 42.0
## 费用档 → 吨位简称（与图鉴顶部「吨位」筛选 chip 同一套说法）
const COST_SHORT := {3: "巡洋", 4: "战巡", 5: "战列"}
## 列的固定顺序（与图鉴「定位」一行的先后一致）
const ROLE_ORDER := [&"attack", &"defense", &"logi"]
## 列标题色：攻击橙 / 防御蓝 / 后勤绿 —— 全是 `EveWindow` 既有语义色，
## 不新造颜色（它们本来就是「火力 / 护盾 / 修复」的通用语义）。
const ROLE_COLORS := {
	&"attack": Color(0.88, 0.52, 0.30),
	&"defense": Color(0.35, 0.70, 0.90),
	&"logi": Color(0.52, 0.76, 0.55),
}

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
## 池子顶部的说明行（文字按真实数量重写，⛔ 不再写死「44 艘」）
var _pool_head: Label
## 矩阵本体（列标题 + 每个费用档一行 + ★2 段）—— 每次开窗重建
var _pool_box: VBoxContainer
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


## 唯一的那一栏 = 说明行 + 可竖滚的矩阵。
##
## ⚠️ 池子必须能滚：矩阵现在是「4 个费用档 × 2 行卡」，窗口还塞得下，
##    但**别指望它永远塞得下**（以后往池子里加船、或加一档星级就会溢出）。
##    用 `ScrollContainer` 而不是缩小卡片：卡太小名字就截断了，
##    而"看得清是哪艘船"正是许愿的前提。
func _build_pool() -> Control:
	var col_box := VBoxContainer.new()
	col_box.add_theme_constant_override("separation", 5)
	col_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col_box.size_flags_vertical = Control.SIZE_EXPAND_FILL

	# 说明行 —— 文字在 `_fill_grid` 里按真实数量重写
	# （旧版把「共 44 艘」写死在字符串里，池子一动就和实际对不上）
	_pool_head = Label.new()
	_pool_head.add_theme_color_override("font_color", C_TEXT_DIM)
	FONT.fs(_pool_head, 10)
	_pool_head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col_box.add_child(_pool_head)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	col_box.add_child(scroll)
	# ★ 2026-10-31：与全工程同口径，滚动条加宽到 10（默认 8 抓不住）
	widen_scrollbar(scroll)

	_pool_box = VBoxContainer.new()
	_pool_box.add_theme_constant_override("separation", POOL_GAP)
	_pool_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_pool_box)
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


# ------------------------------------------------------------------ 矩阵排版

## 池子 → 三层分组：`{star: {cost: {role_id: [ship...]}}}`
##
## ⚠️ 只分组、不改序：同一格内的卡片保持池子原序（权威表按族排，
##    所以同一族的船会挨在一起 —— 这是玩家本来就熟悉的顺序）。
## ⚠️ 池子里出现没登记的 `role_id` 时**归到第一列**，⛔ 绝不丢卡：
##    少一张卡 = 玩家许不到那个愿望，而且界面上完全看不出来少了什么。
func _group_pool(pool: Array) -> Dictionary:
	var stars := {}
	for d in pool:
		var ship: Dictionary = d
		var star := clampi(int(ship.get("star", 1)), 1, 3)
		var cost := int(ship.get("cost", 0))
		var rid := StringName(ship.get("role_id", &""))
		if rid == &"":
			# 老存档 / 未来新增定位没登记 ⇒ 退回按中文查一次，再兜底到第一列
			rid = EveCombatIds.role_id_of(String(ship.get("role", "")))
		if rid == &"":
			rid = StringName(ROLE_ORDER[0])
		if not stars.has(star):
			stars[star] = {}
		var by_cost: Dictionary = stars[star]
		if not by_cost.has(cost):
			by_cost[cost] = {}
		var by_role: Dictionary = by_cost[cost]
		if not by_role.has(rid):
			by_role[rid] = []
		(by_role[rid] as Array).append(ship)
	return stars


## 每列要几个子列 = 「该列最挤那档的艘数 / `POOL_CELL_ROWS`」向上取整。
##
## ★ 这保证**任何**费用档都正好 `POOL_CELL_ROWS` 行卡 ⇒ 所有行等高，
##   网格看起来是规整的表格（这是「好选」的关键，不是装饰）。
func _role_sub_cols(stars: Dictionary) -> Dictionary:
	var max_n := {}
	for star in stars:
		for cost in (stars[star] as Dictionary):
			for rid in (stars[star][cost] as Dictionary):
				var n: int = ((stars[star][cost][rid]) as Array).size()
				max_n[rid] = maxi(int(max_n.get(rid, 0)), n)
	var out := {}
	for rid in ROLE_ORDER:
		var n: int = int(max_n.get(rid, 0))
		out[rid] = maxi(1, int(ceil(float(n) / float(POOL_CELL_ROWS))))
	return out


## 一个定位格子的宽度（子列数 × 卡宽 + 格内间距）
static func _cell_width(sub_cols: int) -> float:
	return float(sub_cols) * CARD_W + float(maxi(0, sub_cols - 1)) * float(POOL_GAP)


func _fill_grid(pool: Array) -> void:
	for c in _pool_box.get_children():
		c.queue_free()
	_cards.clear()

	var stars := _group_pool(pool)
	var sub_cols := _role_sub_cols(stars)
	var cell_w := {}
	for rid in ROLE_ORDER:
		cell_w[rid] = _cell_width(int(sub_cols.get(rid, 1)))

	_pool_head.text = "候选池 · 共 %d 艘　｜　行 = 费用档　列 = 定位　｜　青边 ★1 · 金边 ★2（二星巡洋）" \
			% pool.size()

	# ① 列标题（三个定位）—— 与下面的行用同一套列宽，所以能对齐
	_pool_box.add_child(_build_col_header(cell_w))

	# ② ★1：每个费用档一行
	var s1: Dictionary = stars.get(1, {})
	for cost in _sorted_costs(s1):
		_pool_box.add_child(_build_cost_row(cost, s1[cost], sub_cols, cell_w))

	# ③ ★2：单独一段放最下面（用户原话「二星的在下面」）
	var s2: Dictionary = stars.get(2, {})
	if not s2.is_empty():
		_pool_box.add_child(_section_divider("★2 二星巡洋 · 许愿命中返星币"))
		for cost in _sorted_costs(s2):
			_pool_box.add_child(_build_cost_row(cost, s2[cost], sub_cols, cell_w))

	# ④ 未来若出现 ★3（或更高）：接着往下排，⛔ 不静默丢卡
	for star in stars.keys():
		if int(star) <= 2:
			continue
		_pool_box.add_child(_section_divider("★%d" % int(star)))
		var sx: Dictionary = stars[star]
		for cost in _sorted_costs(sx):
			_pool_box.add_child(_build_cost_row(cost, sx[cost], sub_cols, cell_w))


## 费用键升序（3 费 → 5 费）。Dictionary 的 key 顺序不保证，必须显式排。
static func _sorted_costs(by_cost: Dictionary) -> Array:
	var ks := by_cost.keys()
	ks.sort()
	return ks


## 列标题行：左侧空出费用栏，三个定位各占一格宽度并居中。
func _build_col_header(cell_w: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", POOL_BAND_GAP)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var gutter := Control.new()
	gutter.custom_minimum_size = Vector2(POOL_GUTTER, 0)
	gutter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(gutter)
	for rid in ROLE_ORDER:
		var l := Label.new()
		l.text = String(EveCombatIds.ROLE_LABEL.get(rid, String(rid)))
		var col: Color = ROLE_COLORS.get(rid, C_TEXT_DIM)
		l.add_theme_color_override("font_color", col)
		FONT.fs(l, 10)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.custom_minimum_size = Vector2(float(cell_w.get(rid, CARD_W)), 0)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(l)
	return row


## 一个费用档 = 左边「3 费 / 巡洋」+ 三个定位格（格内卡片折行）
func _build_cost_row(cost: int, by_role: Dictionary,
		sub_cols: Dictionary, cell_w: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", POOL_BAND_GAP)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var tag := Label.new()
	tag.text = "%d 费\n%s" % [cost, String(COST_SHORT.get(cost, ""))]
	tag.add_theme_color_override("font_color", C_TEXT_DIM)
	FONT.fs(tag, 10)
	tag.custom_minimum_size = Vector2(POOL_GUTTER, 0)
	tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(tag)

	for rid in ROLE_ORDER:
		var ships: Array = by_role.get(rid, [])
		var cell: Control
		if ships.is_empty():
			# 空列（4 费 / 5 费没有后勤船）也要占住列宽，否则后面的列会往左缩，
			# 整张表就歪了。留一个极淡的「—」说明"这档本来就没有"，
			# ⛔ 别只留白：玩家会以为是没渲染出来。
			cell = _empty_cell(float(cell_w.get(rid, CARD_W)))
		else:
			cell = _build_role_cell(ships, int(sub_cols.get(rid, 1)))
			cell.custom_minimum_size = Vector2(float(cell_w.get(rid, CARD_W)), 0)
		row.add_child(cell)
	return row


## 空定位格：一个居中、极淡的破折号（占满该列宽度）
func _empty_cell(w: float) -> Control:
	var l := Label.new()
	l.text = "—"
	l.add_theme_color_override("font_color", C_TEXT_FAINT)
	FONT.fs(l, 10)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.custom_minimum_size = Vector2(w, CARD_H)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## 一个定位格：`sub_cols` 列、最多 `POOL_CELL_ROWS` 行的卡片网格
func _build_role_cell(ships: Array, sub_cols: int) -> Control:
	var cell := GridContainer.new()
	cell.columns = maxi(1, sub_cols)
	cell.add_theme_constant_override("h_separation", POOL_GAP)
	cell.add_theme_constant_override("v_separation", POOL_GAP)
	cell.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for d in ships:
		var ship: Dictionary = d
		var key := StringName(ship.get("ship_key", &""))
		var star := clampi(int(ship.get("star", 1)), 1, 3)
		var w := _build_card(ship, star)
		var root: PanelContainer = w["root"]
		root.gui_input.connect(_on_card_input.bind(key, star))
		cell.add_child(root)
		_cards[_card_id(key, star)] = w
	return cell


## 分段标题（★2 那一段）：两条细线夹一行金字，与鸣谢面板的段头同版式。
func _section_divider(text: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := EveWindow.make_divider()
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	var t := Label.new()
	t.text = text
	t.add_theme_color_override("font_color", C_GOLD)
	FONT.fs(t, 10)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(t)
	var r := EveWindow.make_divider()
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(r)
	return row


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
