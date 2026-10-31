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
## ── 星级怎么区分（混排在一屏里）──────────────────────────────────
##   原来是一栏一张平铺网格，星级只能靠卡面分辨。现在**★2 单独成一段**
##   压在池子最下面（用户 2026-11-01 的要求），段头是金色分隔线；
##   段内沿同一条排版规则往下排，所以位置一眼可预期。
##   ★1 用青色边（C_ACCENT）、★2 用金色边（C_GOLD），名字前面还有 `★n`。
##   ⚠️ 别再靠"名字后加个 2"之类的隐晦手段 —— 二星船名和一星一模一样，
##      玩家一眼扫过去分不出来，就会许错愿。

## 玩家点了「抽取」—— 愿望原样交给场景（空 = 没许愿）
signal draw_requested(wish_key: StringName, wish_star: int)
## 抽完点「完成」—— 场景据此推进节点
signal finished()

const CARD_W := 106.0
const CARD_H := 44.0

## ══════════════════════════════════════════════════════════════════
##  「同级一行 · 一块两行 · 同族一列」的池子排版
## ══════════════════════════════════════════════════════════════════
##  ★★ 2026-11-01（用户转来玩家画的排布示意图，定案）：
##     「这个表是玩家建议的排序方式，好好阅读，好好理解一下，按玩家给的方式排出来」。
##
##  图上那几条规矩（照做，别再自己加戏）：
##    ① **同级一行**：3 费 / 4 费 / 5 费 各占一条横带，★2 单独一段压在最下面；
##    ② **一块两行**：卡片不再铺成一条长龙，而是折成「2 行」的小块；
##    ③ **同族一列**：块内按势力排，同一族的船落进同一列；
##       盾抗族（加达里 / 米玛塔尔）在前、甲抗族（盖伦特 / 艾玛）在后 ——
##       于是每块的「列」天然就是防御类型（见 `FACTION_ORDER` 的注释）。
##
##  ★1 段比图上多一条，但图里 3 费那三块就是这个意思：
##    **按标签拆组** —— 常规 / 电子战 / 后勤 各成一块。特殊船单独挑出来，
##    想找"能打电子战的那几条"不用在 12 张里挨个扫。
##    ⚠️ ★2 段**不拆**标签：12 艘巡洋每族正好 3 条（常规 / 电子战 / 后勤各一），
##       一族一行反而更好比价 —— 图的下半段正是这么排的。
##
##  ⚠️ 一块 = `BLOCK_ROWS` 行 × 最多 `BLOCK_MAX_COLS` 列；超了就 **均分**
##     （8 张 → 4+4，12 张 → 6+6）。⛔ 别让最后一块只剩一两张：
##     同一档两块宽窄不一，整张表当场就散了（图里 4 费 / 5 费 都是均分的）。

## 一块固定 2 行；最多 3 列（= 6 张）。改这两个数等于改整张表的骨架。
const BLOCK_ROWS := 2
const BLOCK_MAX_COLS := 3
const BLOCK_MAX := BLOCK_ROWS * BLOCK_MAX_COLS
## 块内卡片间距
const POOL_GAP := 6
## 费用栏与矩阵之间
const BLOCK_GAP := 18
## 费用带之间（3 费 ↔ 4 费 ↔ 5 费 ↔ ★2 段）
const SECTION_GAP := 12
## 左侧费用栏宽度：竖排「3 费 / 巡洋」两行
const POOL_GUTTER := 42.0
## 费用档 → 吨位简称（与图鉴顶部「吨位」筛选 chip 同一套说法）
const COST_SHORT := {3: "巡洋", 4: "战巡", 5: "战列"}

## ══════════════════════════════════════════════════════════════════
##  ★★ 2026-11-01（用户：「能对齐的地方都给我对齐」）—— 全表一条列网格
## ══════════════════════════════════════════════════════════════════
## 上一版是「HBox 里塞若干个 GridContainer，块缝用 spacer 凑」，
## 探针实测（`tools/probe_lot_layout.gd` dump 出来的 x 坐标）：
##     3 费 块起点 531 / 789 / 1047　（组缝 40）
##     4 费 块起点 531 / 767　　　　　（块缝 18）
##     5 费 块起点 531 / 879　　　　　（3 列块，缝 18）
##   ⇒ 同一个"第 2 块"，三个费用带落在三个不同的 x 上，
##     竖列一跳一跳，整张表看着就是散的。
##
## 现在：**一行 = 一个 GridContainer**，分组的空隙不用像素凑，
## 直接**空掉一整列**（宽度正好一张卡）。于是：
##   ① 所有卡片（和占位格）都落在同一条网格 `左起 + k×(CARD_W+POOL_GAP)`；
##   ② 块缝只剩下"空一列"这一种，⛔ 不再有 40 / 18 两种不同的缝；
##   ③ 3 费 8 列（2+空+2+空+2）= 890px，仍在 910px 可用宽里，不溢出。
##
## ⚠️ 网格化的代价：块缝 = 一整张卡（112px），比原来的 40 大得多。
##    这是**为了对齐付的账** —— 想让 2 列块和 3 列块的竖边都对齐，
##    缝就只能按整列走，没有中间值。⛔ 别把块缝改回几十像素，
##    一旦不是整列，竖列立刻又错开。
## ⚠️ 因此 `TAG_GAP` 已删除：分组的强弱现在只由"空一列"表达。
const COL_STEP := 112.0   # = CARD_W(106) + POOL_GAP(6)，仅作文档口径，代码走布局

## 势力顺序：**盾抗族先、甲抗族后**。
##
## ⚠️ 这不是随手排的：加达里 / 米玛塔尔 全族盾抗，盖伦特 / 艾玛 全族甲抗
##    （见 `EveShipTable` 的 `defense` 列，52 艘无一例外）。
##    按这个顺序落进 2 列的块里 ⇒「同一列 = 同一种防御」自动成立，
##    玩家扫一眼就知道"右边这列全是甲抗"。
## ⛔ 别改成拼音序 / 中文序（那正好是 加→盖→米→艾，盾甲会混列）；
##    ⛔ 也别按 `role` 排 —— 定位是另一条正交信息，卡面上没有它。
const FACTION_ORDER := ["加达里", "米玛塔尔", "盖伦特", "艾玛"]

## 标签三档：块的先后顺序（★1 段），也是族内的列序（★2 段）。
const TAG_PLAIN := 0
const TAG_EW := 1
const TAG_LOGI := 2
const TAG_ORDER := [TAG_PLAIN, TAG_EW, TAG_LOGI]

## ══════════════════════════════════════════════════════════════════
##  ★★ 2026-11-01（用户：「战列这里不对，该按照攻击 防御 加强来分，再辅以种族」）
## ══════════════════════════════════════════════════════════════════
## 战列那一行原来和别的档一样按"势力成行"排（一族一行），玩家看不出攻击/防御的差别。
## 改成**先按定位拆块、块内再按防御 + 种族**。
##
## 数据实测（12 艘战列，`EveShipDatabase.role_tag()` 五档互斥口径）：
##   攻击型 4（乌鸦 / 万王宝座 / 狂暴 / 灾难）
##   防御型 4（毒蝎 / 多米尼克斯 / 台风 / 末日沙场）
##   加强型 4（鹏鲲 / 亥伯龙神 / 死亡漩涡 / 地狱天使 —— 即 `REINFORCED_BATTLESHIP`）
##   ⇒ **4+4+4 = 三块**，与 3 费那三块同宽同构，8 列网格自动对齐。
##
## ⚠️ 判据走 `EveShipDatabase.role_tag()`，⛔ **不要读表里的 `role` 列**：
##    那一列只有攻击/防御/后勤三种，把"加强型"读没了（加强型在表里标的是"防御型"）。
## ⚠️ 只对 **cost ≥ 5** 生效：3 费按定位分会碎成 4 块（攻击 3 / 防御 1 / 电子战 4 / 后勤 4），
##    块宽参差，那才是真的乱。3 费维持"电子战 / 后勤 单独成块"的老口径 ——
##    那一档玩家的痛点是"想找特殊船"，不是"想看攻防"。
const ROLE_SPLIT_MIN_COST := 5
const ROLE_SPLIT_ORDER: Array[StringName] = [
	&"attack", &"defense", &"command", &"logistics", &"ew",
]
## 块内按防御排：盾抗在前、甲抗在后（与 `FACTION_ORDER` 同一个理由 ——
## 这两族的防御类型是全族统一的，按它排 ⇒ 2 行块的"上排盾、下排甲"自然成立）。
const DEFENSE_ORDER := ["盾抗", "甲抗"]

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
	_pool_box.add_theme_constant_override("separation", SECTION_GAP)
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

## 池子 → `{star: {cost: [ship...]}}`。只分桶、不改序。
##
## ⚠️ 这里**不做排序**（排序全交给 `_sort_ships()`）；保持入参原序，
##    是为了让每个桶的并集必然 == 池子本身 —— 分桶丢卡是这类重排最常见的错。
static func _bucket_stars(pool: Array) -> Dictionary:
	var stars := {}
	for d in pool:
		var ship: Dictionary = d
		var star := clampi(int(ship.get("star", 1)), 1, 3)
		var cost := int(ship.get("cost", 0))
		if not stars.has(star):
			stars[star] = {}
		var by_cost: Dictionary = stars[star]
		if not by_cost.has(cost):
			by_cost[cost] = []
		(by_cost[cost] as Array).append(ship)
	return stars


## 一条船属于哪一档标签。
##
## ⚠️ 判据**只认羁绊表的公开入口**（`is_ew_ship` / `is_logi_ship`），
##    ⛔ 不在这里另抄一份船名表 —— 电子战名单是会变的（`EW_SHIP_KEYS` 是唯一真源）。
static func _tag_of(ship: Dictionary) -> int:
	if EveTraitTable.is_ew_ship(ship):
		return TAG_EW
	if EveTraitTable.is_logi_ship(ship):
		return TAG_LOGI
	return TAG_PLAIN


## 组内排序：势力（盾抗族 → 甲抗族）为主键，标签（常规 → 电子战 → 后勤）为次键。
##
## ⚠️ 用「按桶取」而不是 `sort_custom`：Godot 的数组排序**不稳定**，
##    同族同标签的两条船顺序会随机翻 —— 同一张表每次打开都不一样，
##    玩家会以为卡在跳。
static func _sort_ships(ships: Array) -> Array:
	var out: Array = []
	for fac in FACTION_ORDER:
		for tag in TAG_ORDER:
			for d in ships:
				var s: Dictionary = d
				if String(s.get("faction_cn", "")) != fac:
					continue
				if _tag_of(s) != tag:
					continue
				out.append(s)
	# 兜底：势力没登记的新船（以后扩表）按原序补在末尾，⛔ 绝不丢卡
	for d in ships:
		if not out.has(d):
			out.append(d)
	return out


## 块内排序：防御（盾抗 → 甲抗）为主键，势力为次键。
##
## 为什么主键是防御而不是势力：块折成 2 行之后，"行"才是第一眼看到的东西。
## 按防御排 ⇒ 4 张一块时**上排全盾抗、下排全甲抗**，一眼就知道哪两条怕什么。
## 若按势力排，上排会是"加达里+米玛塔尔"（都是盾抗），效果相同；
## 但一旦出现同族两张且跨防御的情况（战列加强型就有），按势力排会把
## 盾抗和甲抗混进同一行 —— 那种块整个看板都会读不出来。
static func _sort_by_defense(ships: Array) -> Array:
	var out: Array = []
	for def in DEFENSE_ORDER:
		for fac in FACTION_ORDER:
			for d in ships:
				var s: Dictionary = d
				if String(s.get("defense_type", "")) != def:
					continue
				if String(s.get("faction_cn", "")) != fac:
					continue
				out.append(s)
	# 兜底：没登记防御/势力的新船按原序补在末尾，⛔ 绝不丢卡
	for d in ships:
		if not out.has(d):
			out.append(d)
	return out


## 一档定位 → 4 个字的卡面短标签（`·攻击` / `·防御` / `·加强` / `·电子` / `·后勤`）。
##
## ⚠️ 卡面只有 94px 可用宽，`ROLE_LABELS` 是"攻击型 / 防御型 / 加强型"三字，
##    加个点就是 4 字 = 36px，会把派系名挤到截断（`sub` 是 EXPAND_FILL + clip）。
##    ⇒ 这里用**两字**（·攻击 / ·防御 /·加强），语义不丢，省 9px。
##    ⛔ 别把三个字直接塞进卡面。
static func _role_short(tag: StringName) -> String:
	match tag:
		&"attack": return "攻击"
		&"defense": return "防御"
		&"command": return "加强"
		&"logistics": return "后勤"
		&"ew": return "电子"
		_: return ""


## 一条费用带 → 若干「组」，每组内部已排好序、可以直接切块。
##
## 三种口径，按优先级：
##  ① ★2 段：整带一组（一族正好 3 条巡洋，一族一行最好比价）；
##  ② ★1 且 cost ≥ `ROLE_SPLIT_MIN_COST`（战列）：按**定位**拆（攻击/防御/加强），
##     块内按防御+种族排 —— 见 `ROLE_SPLIT_ORDER` 的顶注；
##  ③ 其余 ★1：拆成 常规 / 电子战 / 后勤 三组（空组不产出）。
static func _section_groups(ships: Array, star: int) -> Array:
	var out: Array = []
	if star >= 2:
		out.append(_sort_ships(ships))
		return out
	if ships.is_empty():
		return out
	var cost := int((ships[0] as Dictionary).get("cost", 0))
	if cost >= ROLE_SPLIT_MIN_COST:
		for tag in ROLE_SPLIT_ORDER:
			var bucket: Array = []
			for d in ships:
				if EveShipDatabase.role_tag(String((d as Dictionary).get("ship_key", ""))) == tag:
					bucket.append(d)
			if not bucket.is_empty():
				out.append(_sort_by_defense(bucket))
		return out
	for tag in TAG_ORDER:
		var bucket: Array = []
		for d in ships:
			if _tag_of(d) == tag:
				bucket.append(d)
		if not bucket.is_empty():
			out.append(_sort_ships(bucket))
	return out


## 一组 → 若干块。每块 `BLOCK_ROWS` 行、最多 `BLOCK_MAX_COLS` 列，超了均分。
##
## 例：4 张 → [4]（2 列）｜8 张 → [4, 4]（各 2 列）｜12 张 → [6, 6]（各 3 列）。
static func _chunk(ships: Array) -> Array:
	var n := ships.size()
	if n <= 0:
		return []
	var blocks := int(ceil(float(n) / float(BLOCK_MAX)))
	var per := int(ceil(float(n) / float(blocks)))
	var out: Array = []
	var i := 0
	while i < n:
		out.append(ships.slice(i, mini(i + per, n)))
		i += per
	return out


func _fill_grid(pool: Array) -> void:
	for c in _pool_box.get_children():
		c.queue_free()
	_cards.clear()

	_pool_head.text = "候选池 · 共 %d 艘　｜　同级一行 · 一块两行 · 战列按攻击/防御/加强分块 · 其余按电子战/后勤分块 · 全表同一列网格　｜　青边 ★1 · 金边 ★2" \
			% pool.size()

	var stars := _bucket_stars(pool)
	var star_keys := stars.keys()
	star_keys.sort()
	for sk in star_keys:
		var star := int(sk)
		# ★2 起单独成段、压在最下面（用户原话「二星的在下面」），
		# 未来若出现 ★3 也照这个规矩往下接，⛔ 不静默丢卡
		if star >= 2:
			_pool_box.add_child(_section_divider(
					"★2 二星巡洋 · 许愿命中返星币" if star == 2 else "★%d" % star))
		var by_cost: Dictionary = stars[sk]
		for cost in _sorted_costs(by_cost):
			_pool_box.add_child(_build_cost_row(star, int(cost), by_cost[cost]))


## 费用键升序（3 费 → 5 费）。Dictionary 的 key 顺序不保证，必须显式排。
static func _sorted_costs(by_cost: Dictionary) -> Array:
	var ks := by_cost.keys()
	ks.sort()
	return ks


## 一条费用带 = 左侧「3 费 / 巡洋」+ 一个**整行网格**（块只是网格里被空列隔开的列段）。
##
## ⚠️ 这里必须**逐行**往 GridContainer 里塞（它是行优先填充的）：
##    先塞满第 1 行的所有列（含分组空列），再塞第 2 行。
##    ⛔ 别按"块"依次塞 —— 那样第 2 块会接着第 1 块往右排，
##       "一块两行"立刻退化成"一条长龙"，而且是那种图上看着像掉了一行的错法。
func _build_cost_row(star: int, cost: int, ships: Array) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", BLOCK_GAP)
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

	# 先把这一带拍平成"块列表"（顺序就是最终从左到右的顺序）
	var blocks: Array = []
	for group in _section_groups(ships, star):
		for chunk in _chunk(group):
			blocks.append(chunk)

	# 总列数 = Σ 各块列数 + 每组之间的一列空位
	var total_cols := 0
	for b in blocks:
		total_cols += _block_cols(b)
	total_cols += maxi(0, blocks.size() - 1)

	var grid := GridContainer.new()
	# ⚠️ `columns` 必须显式给：默认 1 列会竖成一条线（老版踩过）
	grid.columns = maxi(1, total_cols)
	grid.add_theme_constant_override("h_separation", POOL_GAP)
	grid.add_theme_constant_override("v_separation", POOL_GAP)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	grid.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(grid)

	for r in BLOCK_ROWS:
		for bi in blocks.size():
			var chunk: Array = blocks[bi]
			if bi > 0:
				# 分组沟 = **空一整列**（宽度 = 一张卡），不是随手填的几十像素
				grid.add_child(_blank_cell())
			var cols := _block_cols(chunk)
			for c in cols:
				var idx := r * cols + c
				if idx < chunk.size():
					grid.add_child(_card_cell(chunk[idx]))
				else:
					grid.add_child(_blank_cell())
	return row


## 一块占几列：`ceil(张数 / 2)`。4 张 → 2 列；5 张 → 3 列（末行空一格）；6 张 → 3 列。
static func _block_cols(chunk: Array) -> int:
	return maxi(1, int(ceil(float(chunk.size()) / float(BLOCK_ROWS))))


## 空占位：撑住列宽（= 一张卡），让后面的卡不会因为缺格而往前挤。
##
## ⚠️ 必须显式给 `custom_minimum_size`：宽度为 0 的空 Control 会把这一列的
##    宽度交给别的单元格，整条网格立刻塌成不齐 —— 而它自己肉眼完全看不见。
func _blank_cell() -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(CARD_W, CARD_H)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


## 一张卡 = 建卡 + 接信号 + 登记进 `_cards`（许愿找卡全靠这张表）。
func _card_cell(d) -> Control:
	var ship: Dictionary = d
	var key := StringName(ship.get("ship_key", &""))
	var star := clampi(int(ship.get("star", 1)), 1, 3)
	var w := _build_card(ship, star)
	var root: PanelContainer = w["root"]
	root.gui_input.connect(_on_card_input.bind(key, star))
	_cards[_card_id(key, star)] = w
	return root


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

	# ★★ 2026-11-01（用户：「战列这里不对，该按照攻击 防御 加强来分」）：
	#   战列那一档的**分块依据就是定位**（见 `ROLE_SPLIT_ORDER` 顶注），
	#   卡面不标的话，玩家只看到"三块，不知道按什么分的"。
	#
	# ⚠️ 只在 cost ≥ `ROLE_SPLIT_MIN_COST` 时加：
	#    3 费的卡面上已经挂着 电子战/后勤 标签，再塞一个定位标签必然挤掉派系名
	#    （那两项在抽奖池里是选牌的唯一依据，不能截）。
	# ⚠️ 用两字短标签（`_role_short`），⛔ 别塞 `ROLE_LABELS` 的三字全称。
	if int(ship.get("cost", 0)) >= ROLE_SPLIT_MIN_COST:
		var rtag := EveShipDatabase.role_tag(String(ship.get("ship_key", "")))
		var short := _role_short(rtag)
		if short != "":
			var rl := Label.new()
			rl.text = "·" + short
			rl.add_theme_color_override("font_color", EveShipDatabase.role_color(rtag))
			FONT.fs(rl, 9)
			rl.size_flags_horizontal = Control.SIZE_SHRINK_END
			rl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			sub_row.add_child(rl)

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
