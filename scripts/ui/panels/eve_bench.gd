extends Control
class_name EveBenchRail
## ★ 字号缩放（2026-10-07）：自绘文字的字号也要过它（`FONT.s(设计字号)`）。
const FONT := preload("res://scripts/ui/eve_font.gd")

## EVE 自走棋 —— 备战席格带
##
## ⚠️ 这不是窗口 —— 它没有面板底、没有标题栏、没有边框。
##
## ══════════════════════════════════════════════════════════════════
## 2026-09-23 改版（用户口径）：
##   「把备战席的船也改为 2D 立绘卡牌吧，现在这样特别别扭，
##     尤其是放上去的模型朝向还不一样」
## ══════════════════════════════════════════════════════════════════
##   格子里画的**不再是 3D 模型，而是官方立绘图**：
##     res://assets/ships/<id>.png ← EveShipArt（与商店卡片同一主键、同一套图）
##
##   这一改同时解决了三件事 —— 这是它比「修 3D 朝向」更划算的原因：
##
##     ① **朝向**：官方渲染图出自同一个接口（images.evetech.net 的 render），
##        是**统一机位**批量渲染的，所以「朝向一致」是资源自带的性质。
##        而 3D 模型来自 gamemodels3d，每艘船的**建模朝向各不相同**，
##        在 EveBenchStage 那套「相机对齐」基向量下就会有的横躺、有的竖着。
##        ⇒ 走 2D 就不需要逐船标定 52 个 yaw 角。
##
##     ② **压暗**：3D 船画在 HUD **之下**，所以格底每加一分不透明度，
##        就是给站在格子里的船蒙一层黑（上一版实测踩过：格底 0.40 时
##        船暗到几乎读不出来，症状表现为「点购买后像是船没上备战席」）。
##        2D 立绘与格底在**同一个 _draw()** 里，先画底、后画船 ——
##        顺序天然正确，这个坑从结构上被消掉了。
##
##     ③ **清晰度**：立绘是已经抠像 + 面积归一化过的 512×512 透明底图，
##        比「按包围盒缩放的 3D 模型」更容易一眼认出是哪艘船。
##
##   3D 层（EveBenchStage）随之停用 —— 停用原因与回退方法见该文件头注释。
##
## ── 星级怎么表达 ────────────────────────────────────────────────
##   边线配色（1★ 青灰 / 2★ 金 / 3★ 亮金）+ 格底一行星号。
##   两个都做是**刻意**的：边线色在快速扫视时最快，星号在细看时最准。
##   ⚠️ 边框只表达星级，**不掺派系色** —— 派系信息由立绘本身承担。
##
## ── 为什么格子框【固定显示】而不区分「有船 / 空格」────────────────
##   因为「哪一格有船」的唯一真相源是 `EveRunState.bench`。
##   本控件只是它的**显示投影**（见 set_fleet 的注释），
##   从不自己维护占用表 —— 否则撤回（填回中间空位）时两份状态必然分叉。
##
## ── 顶部那条金线是什么 ──────────────────────────────────────────
##   它是「悬空分层」的视觉载体：格带整体是一层**浮在棋盘外侧的平台**，
##   金线 = 平台的近端边缘高光。用户明确要「高差明显」。
##
## 变更清单：
##   2026-09-22  RECT_BENCH 1142×52 → 1200×140；裸线 + 刻度 → 8 个方格 + 金线
##               hover / dragging / selling 三态保留；格区几何收敛到 cell_area()
##   2026-09-23  格子内改画 2D 立绘 + 星级；新增 set_fleet()；
##               HIT_ABOVE 48 → 10（2D 立绘不再往格子外伸，命中区无需上扩）
##   2026-09-23  格内左上角加「吨位几何标识」（EveTierIcon 预烘贴图，2:1 无 mip）；
##               set_fleet() 同步缓存 fleet_cost（避免 _draw 每帧查表）
##   2026-09-23  吨位符号按用户口径重建（3/4/5 由「拱形实心」改为描边房子 + 分叉）；
##               TIER_SIZE 语义 15(高度) → 12(宽度)，见常量注释

const SLOTS := 8

## 命中区在格带上方多留的高度（设计像素）。
##
## ⚠️ 2026-09-23：48 → 10。
##    旧值 48 是给「3D 船身向上伸出控件顶部」留的（玩家会去点船而不是点框）。
##    改 2D 立绘后船体**完全落在格子内**，那 48px 反而变成隐患：
##    备战席顶 760，命中区一直伸到 712 —— 而棋盘近端就在 762，
##    于是「点棋盘最下一行」会被判成「点备战席空格」，表现是点了没反应且不报错。
##    收到 10 只保留一点手抖容差。
const HIT_ABOVE := 10.0

## 格子左右各留的缝（设计像素）—— 保证 8 个格子是 8 个独立的框
const CELL_GAP := 4.0
## 格顶距控件顶部（金线所在处）的距离
const CELL_TOP := 10.0
## 格底距控件底部的距离
const CELL_BOTTOM := 6.0

## 立绘区在格子内的内缩（设计像素）
##
## ⚠️ BOTTOM 比 TOP 大：底部要留出画星级那一行（基线在 end.y - 7）。
const ART_PAD_X := 3.0
const ART_PAD_TOP := 4.0
const ART_PAD_BOTTOM := 18.0

## 立绘横向放大系数（相对格子可用宽度）。
##
## 1.0 = 立绘恰好铺满格宽、相邻格之间留 CELL_GAP。**不要轻易调过 1.05**：
## 相邻格的船翼会互相压线（3D 版曾经就是这样，读作「两艘船黏在一起」）。
const ART_FILL := 1.0

## 层高线（悬空分层的载体）
const LAYER_GOLD := Color(0.851, 0.678, 0.278)
## 格框 / 格底（空格状态）
const CELL_LINE := Color(0.784, 0.941, 0.980)
const CELL_FILL := Color(0.043, 0.063, 0.078)

## 星级配色。索引 = star - 1。
const STAR_LINE := [
	Color(0.784, 0.941, 0.980),   # ★1 青灰（与空格框同色系，但更实）
	Color(0.851, 0.678, 0.278),   # ★2 金
	Color(1.000, 0.827, 0.353),   # ★3 亮金
]

## ── 吨位标识（几何符号，格内左上角）────────────────────────────
##
## 5 个符号的规则（用户 2026-09-23 口述 + 13 图鉴页实测复核）：
##   护卫 = 三角（底边即底线）/ 驱逐 = 三角 + 一横 /
##   巡洋 = 屋顶三角 + 长方形（房子的形状）/ 战巡 = 巡洋 + 一横 /
##   战列 = 巡洋的下面改成三角（底部 Λ 凹口 ⇒ 读作箭镞）
## 五个符号**共用同一个屋顶**（顶点与屋檐同位），只在下半部分逐级生长。
##
## ⚠️ 走预烘贴图而不是 _draw 现画 —— 完整理由见 EveTierIcon 的头注释，
##    **那边是唯一真相源**（一句话：msaa_2d 没开，2D 侧没有 antialiased 参数）。
## ⚠️ TIER_SIZE 是【符号外框宽】，**不是高度** ——
##    5 个吨位的宽度是常量、高度随吨位长（0.50 ~ 1.21 倍宽）。
##    按宽度对齐才能让五个符号的屋顶同位（官方图鉴同口径）。
const TIER_SIZE := 12.0
## 符号左 / 上边距（相对格子左上角）
const TIER_INSET := 5.0
## 符号配色。⚠️ 比格线更透一档：它是压在立绘上的**信息**，不是结构线。
const TIER_COLOR := Color(0.784, 0.941, 0.980, 0.72)

## 格区（相对本控件的局部矩形）—— 格带几何的**唯一真相源**。
static func cell_area(rail_size: Vector2) -> Rect2:
	var h := maxf(8.0, rail_size.y - CELL_TOP - CELL_BOTTOM)
	return Rect2(0.0, CELL_TOP, rail_size.x, h)

## 当前被拿起的格子下标（-1 = 没有）
var dragging_index: int = -1
## 鼠标悬停的格子（-1 = 没有）—— 只做「这里可以拿」的提示
var hover_index: int = -1
## 整个格带变橙色出售区
var selling: bool = false

## 备战席名单（每格一个 Dictionary；空槽 = `{}`）。
##
## ⚠️ 这是 `EveRunState.bench` 的**显示投影**，不是第二份状态 ——
##    本类只读它、从不写它，也不从它推导「哪格占用」之类的派生量。
##    真相源永远在 EveRunState（拖放/撤回/合成都在那边改）。
var fleet: Array = []

## 每格的吨位档（1~5；0 = 空槽 / 查不到）。
##
## ⚠️ 在 set_fleet() 里算一次缓存，**不在 _draw() 里查表** ——
##    _draw 每帧跑，8 次 EveShipDatabase.by_id 纯属浪费。
## ⚠️ 别改成「按 index 去 EveRunState 现问」：那是第二份状态来源，
##    与 fleet 一旦分叉就会出现「船是 A 的、吨位标识是 B 的」且不报错。
var fleet_cost: Array[int] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 吨位贴图 24px 缩到 12px 显示（**2:1，双线性的精确盒平均**）。
	# ⚠️ 关 mip 链：2:1 已经是最优采样，套上 mip 反而先平均一遍再采样。
	#    实测（tools/probe_tier_icon）12px 显示下最细的独立横线保留率：
	#    48px+mip 56% → 24px+LINEAR ~95%。改 TIER_SIZE 前先读 EveTierIcon 头注释。
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR


## 喂一份备战席名单。entries 元素 = {"ship_key": StringName, "star": int}
##
## 由 EveHudRoot.set_bench_fleet() 转发，最终来源是 `run.bench_entries()`。
func set_fleet(entries: Array) -> void:
	fleet = entries
	fleet_cost.clear()
	for i in SLOTS:
		var e := _entry_at(i)
		if e.is_empty():
			fleet_cost.append(0)
		else:
			# 吨位档 = 费用档（EveShipTable 的口径：cost 1~5 就是吨位档）
			var d := EveShipDatabase.by_id(String(e.get("ship_key", "")))
			fleet_cost.append(int(d.get("cost", 0)))
	queue_redraw()


## 取第 i 格的名单项；越界或空槽返回 `{}`
func _entry_at(i: int) -> Dictionary:
	if i < 0 or i >= fleet.size():
		return {}
	var e = fleet[i]
	if e is Dictionary and not (e as Dictionary).is_empty():
		return e as Dictionary
	return {}


func slot_center_x(index: int) -> float:
	return (float(index) + 0.5) * (size.x / float(SLOTS))


## 本控件内的坐标 → 槽位下标（越界返回 -1）
##
## ⚠️ 命中判定放在这里而不是让上层去算，是为了让「格带几何」只有一份真相源：
##    格宽 = size.x / SLOTS 这件事只有本文件知道。
##    上层（battle_scene）只需要问「这个屏幕点是不是落在某一格上」。
func slot_at(local: Vector2) -> int:
	if size.x <= 4.0 or size.y <= 2.0:
		return -1
	if local.x < 0.0 or local.x >= size.x:
		return -1
	if local.y < -HIT_ABOVE or local.y > size.y + 4.0:
		return -1
	var i := int(local.x / (size.x / float(SLOTS)))
	return clampi(i, 0, SLOTS - 1)


func set_hover(index: int) -> void:
	if hover_index == index:
		return
	hover_index = index
	queue_redraw()


func _draw() -> void:
	if size.x <= 4.0 or size.y <= 2.0:
		return

	if selling:
		_draw_selling()
		return

	_draw_layer_line()

	var area := cell_area(size)
	var cw := size.x / float(SLOTS)
	var top := area.position.y
	var h := area.size.y

	for i in SLOTS:
		var x := float(i) * cw
		var cell := Rect2(Vector2(x + CELL_GAP * 0.5, top),
				Vector2(cw - CELL_GAP, h))
		var entry := _entry_at(i)
		var has_ship := not entry.is_empty()
		var star := clampi(int(entry.get("star", 1)), 1, 3)
		var hovered := (i == hover_index and dragging_index < 0)
		_draw_cell(cell, hovered, has_ship, star)
		# 立绘：玩家正拿起的那一格**不画** —— 那艘船此刻在鼠标上，
		# 格子里再画一艘会变成「两艘」（3D 版靠 set_hidden_index 做同一件事）。
		if has_ship and i != dragging_index:
			_draw_ship_art(cell, StringName(entry.get("ship_key", "")))
			# 吨位标识画在立绘**之后** —— 它压在船体上而不是垫在底下，
			# 与「船名压在船图上」是同一个口径（见项目规范规则 20）。
			_draw_tier(cell, _cost_at(i))

	# 源格标记（玩家正拿起的那一格）
	if dragging_index >= 0 and dragging_index < SLOTS:
		var cx := slot_center_x(dragging_index)
		var cell_bottom := top + h
		draw_line(Vector2(cx, top + 6.0), Vector2(cx, cell_bottom - 8.0),
				Color(1.0, 0.588, 0.463, 0.95), 1.5)
		var font2 := ThemeDB.fallback_font
		draw_string(font2, Vector2(cx - 13.0, top + 22.0), "已拿起",
				HORIZONTAL_ALIGNMENT_LEFT, -1, FONT.s(9), Color(0.878, 0.522, 0.302))


## 一个格子：底 + 框 + 星级
##
## ⚠️ 格底**故意不压太深**（0.20 空 / 0.40 有船）。
##    2D 立绘与它同属一次 _draw、且**后画**，所以不会被压暗；
##    压深一点反而能衬托立绘（浅色船体在深底上更清楚）。
##    但也不能太深 —— 星际背景是亮的，整块太黑会像贴了补丁。
func _draw_cell(cell: Rect2, hovered: bool, has_ship: bool, star: int) -> void:
	var fill_a := 0.46 if hovered else (0.40 if has_ship else 0.20)
	draw_rect(cell, Color(CELL_FILL.r, CELL_FILL.g, CELL_FILL.b, fill_a), true)

	# 内侧极淡的一层，只为了让格子在亮星云上有点「厚度」
	var inner := cell.grow(-3.0)
	if inner.size.x > 4.0 and inner.size.y > 4.0:
		draw_rect(inner, Color(0.024, 0.035, 0.045, 0.12), true)

	# 边框：空格 = 青灰；有船 = 星级色
	var line_a := 0.86 if hovered else 0.58
	var col := Color(CELL_LINE.r, CELL_LINE.g, CELL_LINE.b, line_a)
	if has_ship:
		var sc: Color = STAR_LINE[clampi(star - 1, 0, STAR_LINE.size() - 1)]
		col = Color(sc.r, sc.g, sc.b, 0.90)
	draw_rect(cell, col, false, 1.0)

	# 顶边高光：平台近端边缘受光，是「悬空分层」读得出来的关键一笔
	draw_line(Vector2(cell.position.x + 1.0, cell.position.y),
			Vector2(cell.end.x - 1.0, cell.position.y),
			Color(col.r, col.g, col.b, 1.0), 1.0)

	if hovered:
		draw_rect(cell.grow(-1.0), Color(0.784, 0.941, 0.980, 0.16), true)

	# 星级一行（格子底部居中）。
	# ⚠️ ★1 也要画：不画的话玩家会以为「这格没星 / 是空格」。
	if has_ship:
		var sc2: Color = STAR_LINE[clampi(star - 1, 0, STAR_LINE.size() - 1)]
		var font := ThemeDB.fallback_font
		var fs := FONT.s(9)
		var txt := "★".repeat(clampi(star, 1, 3))
		var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(font,
				Vector2(cell.position.x + (cell.size.x - w) * 0.5, cell.end.y - 6.0),
				txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
				Color(sc2.r, sc2.g, sc2.b, 0.95))


## 把立绘铺进格子里
##
## ⚠️ 必须用 `EveShipArt.draw_ship`（按 alpha 包围盒 contain），
##    **不要**直接把整张 512×512 方图 contain 进去 ——
##    立绘管线产出的是方画布、船只占其中一条，直接 contain 方图
##    会让船只占格宽的三分之一（商店卡片踩过这个坑，见 EveShipArt.used_rect）。
func _draw_ship_art(cell: Rect2, ship_key: StringName) -> void:
	if String(ship_key).is_empty():
		return
	var avail := Vector2(cell.size.x - ART_PAD_X * 2.0,
			cell.size.y - ART_PAD_TOP - ART_PAD_BOTTOM)
	if avail.x <= 4.0 or avail.y <= 4.0:
		return
	# ART_FILL > 1 时以格中心为基准向外扩（左右对称溢出）
	var w := avail.x * ART_FILL
	var art := Rect2(
			cell.position + Vector2((cell.size.x - w) * 0.5, ART_PAD_TOP),
			Vector2(w, avail.y))
	EveShipArt.draw_ship(self, art, ship_key, Color.WHITE)


## 格内左上角的吨位几何符号
##
## 位置口径：贴格子左上角内侧 TIER_INSET px。
## ⚠️ 用**格子自身**定位而不是再走一遍 `cell_area()` —— 符号属于「格子」这一层
##    装饰，格子矩形由 _draw() 现算（已含 CELL_GAP 的半缝）。
##    再走一次 cell_area 会引入第二套换算，格带尺寸一变就有两处要改。
func _draw_tier(cell: Rect2, cost: int) -> void:
	if cost <= 0:
		return
	EveTierIcon.draw(self, cell.position + Vector2(TIER_INSET, TIER_INSET),
			TIER_SIZE, cost, TIER_COLOR)


## 第 i 格的吨位档；越界 / 空槽返回 0
func _cost_at(i: int) -> int:
	if i < 0 or i >= fleet_cost.size():
		return 0
	return fleet_cost[i]


## 顶部金色层高线 —— 「格带是浮在棋盘外侧的一层平台」的唯一视觉声明
##
## ⚠️ 两端做小幅渐隐（3%）而不是硬切：格带比棋盘还宽，
##    硬切的两个端点会在星空上留下两根突兀的「针」。
func _draw_layer_line() -> void:
	var y := 0.5
	var segs := 40
	var sw := size.x / float(segs)
	for i in segs:
		var f := float(i) / float(segs - 1)
		var a := 1.0
		if f < 0.03:
			a = f / 0.03
		elif f > 0.97:
			a = (1.0 - f) / 0.03
		draw_line(Vector2(i * sw, y), Vector2((i + 1) * sw, y),
				Color(LAYER_GOLD.r, LAYER_GOLD.g, LAYER_GOLD.b, 0.92 * a), 1.5)
	# 金线下方压一条暗线 —— 让它在亮星云上也读得出来（沿用旧版轨道线的做法）
	draw_line(Vector2(0.0, y + 1.5), Vector2(size.x, y + 1.5),
			Color(0.0, 0.0, 0.0, 0.55), 1.0)


func _draw_selling() -> void:
	draw_rect(Rect2(Vector2(0, 0), size),
			Color(0.376, 0.204, 0.063, 0.52), true)
	draw_dashed_band(Rect2(Vector2(0.5, 0.5), size - Vector2(1.0, 1.0)),
			Color(1.0, 0.690, 0.431, 0.90), 12.0, 8.0, 2.0)
	var font := ThemeDB.fallback_font
	var text := "拖到此处出售 · 返还 ◆"
	var fs := 15
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(font, Vector2((size.x - w) * 0.5, size.y * 0.5 + 5.0),
			text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1.0, 0.863, 0.733))


## 虚线框（出售态用的）
func draw_dashed_band(r: Rect2, col: Color, dash: float, gap: float, width: float) -> void:
	var seg := dash + gap
	var x := r.position.x
	while x < r.end.x:
		var x2 := minf(x + dash, r.end.x)
		draw_line(Vector2(x, r.position.y), Vector2(x2, r.position.y), col, width)
		draw_line(Vector2(x, r.end.y), Vector2(x2, r.end.y), col, width)
		x += seg
	var y := r.position.y
	while y < r.end.y:
		var y2 := minf(y + dash, r.end.y)
		draw_line(Vector2(r.position.x, y), Vector2(r.position.x, y2), col, width)
		draw_line(Vector2(r.end.x, y), Vector2(r.end.x, y2), col, width)
		y += seg


func set_dragging(index: int) -> void:
	dragging_index = index
	queue_redraw()


func set_selling(on: bool) -> void:
	selling = on
	queue_redraw()
