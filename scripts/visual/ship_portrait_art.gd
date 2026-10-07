extends Control
class_name ShipPortraitArt
## ★ 字号缩放（2026-10-07）：自绘文字的字号也要过它（`FONT.s(设计字号)`）。
const FONT := preload("res://scripts/ui/eve_font.gd")

## EVE 自走棋 —— 舰船立绘（程序化占位）
##
## 用 _draw() 画出一个「工业几何」的舰船侧影 + 全息网格底纹。
## 这不是最终立绘 —— 后续替换为 EVE 官方渲染图（Image CDN 或自制渲染）。
## 保留它的价值：在没有任何美术资源时，玩家仍能从形状区分吨位与派系。
##
## 变更清单（初版）：
##   - 网格底纹（全息感）
##   - 按吨位缩放的舰体侧影
##   - 派系配色填充 + 边缘高光线

var ship: EveShip = null

## 派系配色（与概念图一致）
const F_COLORS := {
	EveShip.Faction.AMARR: Color(0.72, 0.58, 0.30),
	EveShip.Faction.CALDARI: Color(0.38, 0.47, 0.56),
	EveShip.Faction.GALLENTE: Color(0.44, 0.50, 0.34),
	EveShip.Faction.MINMATAR: Color(0.53, 0.35, 0.26),
}


func set_ship(p_ship: EveShip) -> void:
	ship = p_ship
	queue_redraw()


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	# 底：近黑
	draw_rect(rect, Color(0.022, 0.030, 0.038), true)
	_draw_grid(rect)

	if ship == null:
		_draw_hint(rect)
		return

	var base: Color = F_COLORS.get(ship.faction, Color(0.5, 0.5, 0.5))
	var scale_factor := _scale_for_ship_art()
	_draw_ship_side(rect, base, scale_factor)


## 全息网格底纹
func _draw_grid(rect: Rect2) -> void:
	var grid_color := Color(0.30, 0.44, 0.50, 0.13)
	var step := 14.0
	var x := rect.position.x
	while x <= rect.end.x:
		draw_line(Vector2(x, rect.position.y), Vector2(x, rect.end.y), grid_color, 1.0)
		x += step
	var y := rect.position.y
	while y <= rect.end.y:
		draw_line(Vector2(rect.position.x, y), Vector2(rect.end.x, y), grid_color, 1.0)
		y += step

	# 中心十字准星
	var center := rect.get_center()
	var cross := Color(0.42, 0.60, 0.66, 0.22)
	draw_line(Vector2(center.x, rect.position.y), Vector2(center.x, rect.end.y), cross, 1.0)
	draw_line(Vector2(rect.position.x, center.y), Vector2(rect.end.x, center.y), cross, 1.0)


func _draw_hint(rect: Rect2) -> void:
	var f := ThemeDB.fallback_font
	var text := "未选中舰船"
	var text_size := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT.s(11))
	draw_string(f, rect.get_center() - text_size * 0.5 + Vector2(0, 4),
		text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT.s(11), Color(0.35, 0.44, 0.48))


## 立绘倍率（**与 3D 同一套 10 级刻度**，但锚点是本管线自己的画布尺度）
##
## ⚠️ 2026-09-28：旧的 `_scale_for_class()` 只有 3 档（0.62/0.80/1.0/`_`=0.8）
##    ⇒ **战巡与战列共用 `_` 的 0.8**，比巡洋(1.0) 还小 —— 与 3D 那边同一个病。
##
## ── 红线 27（只许一处）的落法 ──────────────────────────────────
##    「等级刻度」与「档内位置 u」**不在本文件里重算**，一律取
##    `EveShipVisual.tier_level()` / `EveShipVisual.tier_slot_u()`
##    —— 那两个是唯一真相源；本文件只放**本管线自己的锚点**（画布尺度不同）。
##
## ── 为什么上限仍是 1.0（安全）──────────────────────────────────
##    `_draw_ship_side` 里 `unit = min(w,h)*0.42*scale_factor`，舰艏最远到
##    `unit*1.85`；原来**巡洋就是 1.0**（12 艘在用）⇒ 本表把上限仍定在 1.0，
##    **不会比改动前更容易裁切**。
func _scale_for_ship_art() -> float:
	var lv := EveShipVisual.tier_level(ship.ship_class)
	if lv <= 0:
		# 禁隐式默认（红线）：未登记的吨位必须点名，别悄悄退回一个数
		push_warning("ShipPortraitArt: 吨位档 %d 未登记立绘倍率 ⇒ 退回 0.80" % ship.ship_class)
		return 0.80
	var anchor := 0.62 + (1.0 - 0.62) * float(lv - 1) / 9.0
	var u := EveShipVisual.tier_slot_u(ship.ship_key, ship.ship_class)
	return anchor * (1.0 + EveShipVisual.CLASS_SCALE_SPREAD * (2.0 * u - 1.0))


## 舰船侧影：长楔形舰体 + 背脊结构 + 引擎
##
## ⚠️ 尺度约束：所有横向坐标最远到 unit * 1.92（引擎光尾），
##    纵向最远到 unit * 0.80（舰桥顶）。
##    所以 unit 必须满足 unit * 1.92 <= 半宽 且 unit * 0.80 <= 半高，
##    否则舰艏/引擎会被窗口边框裁掉（实测过：立绘只剩中间一段）。
func _draw_ship_side(rect: Rect2, base: Color, scale_factor: float) -> void:
	var center := rect.get_center()
	# 0.42 而非 0.38：给「引擎光尾」留出余量，避免右侧被裁
	var unit := minf(rect.size.x * 0.42, rect.size.y * 0.42) * scale_factor
	var fill := base.darkened(0.30)
	var edge := base.lightened(0.30)
	var dark := base.darkened(0.55)

	# 主舰体（长楔形：向左收窄为舰艏，向右为舰艉）
	var hull_pts := PackedVector2Array([
		center + Vector2(-unit * 1.85, 0.0),          # 舰艏尖
		center + Vector2(-unit * 0.55, -unit * 0.34),
		center + Vector2(unit * 1.30, -unit * 0.40),
		center + Vector2(unit * 1.55, -unit * 0.12),
		center + Vector2(unit * 1.55, unit * 0.12),
		center + Vector2(unit * 1.30, unit * 0.40),
		center + Vector2(-unit * 0.55, unit * 0.34),
	])
	draw_colored_polygon(hull_pts, fill)
	_draw_outline(hull_pts, edge, 1.0)

	# 背脊结构块（粗野主义几何）
	var spine_pts := PackedVector2Array([
		center + Vector2(-unit * 0.30, -unit * 0.34),
		center + Vector2(unit * 0.55, -unit * 0.38),
		center + Vector2(unit * 0.55, -unit * 0.62),
		center + Vector2(-unit * 0.30, -unit * 0.56),
	])
	draw_colored_polygon(spine_pts, dark)
	_draw_outline(spine_pts, edge, 1.0)

	# 舰桥
	var bridge_pts := PackedVector2Array([
		center + Vector2(-unit * 0.05, -unit * 0.56),
		center + Vector2(unit * 0.42, -unit * 0.58),
		center + Vector2(unit * 0.42, -unit * 0.80),
		center + Vector2(-unit * 0.05, -unit * 0.74),
	])
	draw_colored_polygon(bridge_pts, base.darkened(0.15))
	_draw_outline(bridge_pts, edge, 1.0)

	# 装甲板分隔线
	var seam := Color(edge.r, edge.g, edge.b, 0.28)
	draw_line(center + Vector2(-unit * 0.10, -unit * 0.32),
		center + Vector2(-unit * 0.10, unit * 0.32), seam, 1.0)
	draw_line(center + Vector2(unit * 0.60, -unit * 0.38),
		center + Vector2(unit * 0.60, unit * 0.38), seam, 1.0)

	# 引擎喷口（尾部两道青白色的光）
	var glow := Color(0.50, 0.75, 0.95, 0.85)
	draw_line(center + Vector2(unit * 1.58, -unit * 0.22),
		center + Vector2(unit * 1.92, -unit * 0.18), glow, 2.0)
	draw_line(center + Vector2(unit * 1.58, unit * 0.22),
		center + Vector2(unit * 1.92, unit * 0.18), glow, 2.0)


func _draw_outline(pts: PackedVector2Array, color: Color, width: float) -> void:
	var closed := pts.duplicate()
	closed.append(pts[0])
	for i in closed.size() - 1:
		draw_line(closed[i], closed[i + 1], color, width)
