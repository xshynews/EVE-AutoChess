extends Node3D
class_name EveBoard

## EVE 自走棋 —— 11 × 11 棋盘
##
## ══════════════════════════════════════════════════════════════════
##  用户定稿的分区（v2 指令原文）
## ══════════════════════════════════════════════════════════════════
##    上 4 行  = 敌方出现区
##    中 3 行  = 隔离区（橙虚线，不可放置）
##    下 4 行  = 我方部署区
##
##  「格子只在拖动舰船时显形」—— 默认 completamente 隐藏，
##  这是用户明确要求的第一条视觉规则（视觉重点必须是棋盘本身，
##  但格子本身在非交互时不该抢戏）。
##
## ── 为什么画在 3D 世界空间而不是 HUD 上 ──────────────────────────
##    V3 设计稿里棋盘是用 2D 投影画死的（固定机位下的闭式解）。
##    实装到 Godot 后相机是自由轨道相机（玩家可绕圈），
##    2D 贴图式的棋盘一转视角就穿帮。所以棋盘必须是世界空间里的真几何体。
##    代价是格子的屏幕投影会随视角变化 —— 这正是「真 3D」应有的行为。
##
## ── 尺度 ────────────────────────────────────────────────────────
##    格边长取 EveShipDatabase.CELL_METERS（6000 m）—— 与射程/移速的换算
##    同源，保证「表里说射程 2 格」和「场上隔 2 格」是同一个距离。
##    11 格 = 66 世界单位，落在 arena_radius（120）以内。
##
## 变更清单（实装版）：
##   - 三区色底（三角面）+ 网格线 + 边界线（PRIMITIVE_LINES）
##   - 隔离区上下边界画成橙虚线
##   - 落点高亮格（半透明面 + 亮边）
##   - configure_unit_scale() 接竞技场的世界单位换算

const COLS := 11
const ROWS := 11
const ENEMY_ROWS := 4
const ISOLATION_ROWS := 3

signal cell_picked(row: int, col: int)

## 一格的世界边长（由 configure 决定）
var cell := 6.0
var half := 33.0

var _mesh: MeshInstance3D
var _highlight: MeshInstance3D
var _hl_row := -1
var _hl_col := -1


func _ready() -> void:
	visible = false          # ⚠️ 默认不显示（用户定稿）
	_build_static()
	_build_highlight()


## 由竞技场调用：把「米」的口径带进来
func configure(cell_meters: float, meters_per_unit: float) -> void:
	cell = cell_meters / maxf(1.0, meters_per_unit)
	half = 5.5 * cell
	if is_inside_tree():
		_build_static()
		_build_highlight()


# ------------------------------------------------------------------ 坐标

## 行 r 的 z 区间。r=0 是最远（敌方侧，z 最负），r=10 是最近（我方侧）
func row_z0(r: int) -> float:
	return -half + float(r) * cell


func row_z1(r: int) -> float:
	return row_z0(r) + cell


func col_x0(c: int) -> float:
	return -half + float(c) * cell


func col_x1(c: int) -> float:
	return col_x0(c) + cell


## 格中心（世界坐标，y=0 平面）
func cell_center(row: int, col: int) -> Vector3:
	return Vector3(col_x0(col) + cell * 0.5, 0.0, row_z0(row) + cell * 0.5)


func zone_of_row(r: int) -> int:
	if r < ENEMY_ROWS:
		return 0          # 敌方出现区
	if r < ENEMY_ROWS + ISOLATION_ROWS:
		return 1          # 隔离区
	return 2              # 我方部署区


## 该格能不能放船（隔离区不能）
func is_placeable(row: int, col: int) -> bool:
	if row < 0 or row >= ROWS or col < 0 or col >= COLS:
		return false
	return zone_of_row(row) != 1


## 我方部署区的第一行（= 敌方区 + 隔离区之后）
static func own_zone_row0() -> int:
	return ENEMY_ROWS + ISOLATION_ROWS


## 这一行是不是我方部署区
##
## ⚠️ 与 is_placeable() 的区别：is_placeable 排除的是「隔离区」，
##    而玩家只许放在【自己的 4 行】里 —— 敌方的出现区同样不许放。
##    拖放落点的判定用这个，别用 is_placeable（否则玩家能把船丢进敌区）。
func is_mine_zone(row: int) -> bool:
	return row >= own_zone_row0() and row < ROWS


## 世界坐标 → 格（越界返回 Vector2i(-1, -1)）
func world_to_cell(p: Vector3) -> Vector2i:
	var c := int(floor((p.x + half) / cell))
	var r := int(floor((p.z + half) / cell))
	if r < 0 or r >= ROWS or c < 0 or c >= COLS:
		return Vector2i(-1, -1)
	return Vector2i(r, c)


# ------------------------------------------------------------------ 构建

const ZONE_FILL := [
	Color(0.82, 0.32, 0.28, 0.17),    # 敌方：红
	Color(0.88, 0.52, 0.30, 0.13),    # 隔离：橙
	Color(0.55, 0.78, 0.82, 0.16),    # 我方：青
]
## 网格线：底衬一条近黑，上面再压一条浅青 —— 在亮星云上才读得出来。
##
## ⚠️ 三层高度必须错开，否则透明面与线会在同一平面上打架（z-fighting）：
##      面     y = 0
##      底衬线 y = 0.010
##      主线   y = 0.020
##    0.01 世界单位 = 10 米，在当前相机距离（~150 单位）下深度精度绰绰有余。
const Y_FILL := 0.0
const Y_DARK := 0.010
const Y_LINE := 0.020
const LINE_DARK := Color(0.008, 0.024, 0.039, 0.72)
const LINE_LIGHT := Color(0.745, 0.933, 0.973, 0.46)
const LINE_EDGE := Color(0.745, 0.933, 0.973, 0.80)
const LINE_MINE := Color(0.745, 0.933, 0.973, 0.95)
const LINE_ENEMY := Color(1.0, 0.588, 0.541, 0.95)
const LINE_ISO := Color(1.0, 0.718, 0.471, 1.0)


func _build_static() -> void:
	if _mesh == null:
		_mesh = MeshInstance3D.new()
		_mesh.name = "BoardMesh"
		add_child(_mesh)
	_mesh.mesh = _make_mesh()


func _make_mesh() -> ArrayMesh:
	var am := ArrayMesh.new()

	# ── surface 0：三个区的半透明底色 ──
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for r in ROWS:
		var zz0 := row_z0(r)
		var zz1 := row_z1(r)
		var fc: Color = ZONE_FILL[zone_of_row(r)]
		_add_quad(st, Vector3(-half, Y_FILL, zz0), Vector3(half, Y_FILL, zz0),
				Vector3(half, Y_FILL, zz1), Vector3(-half, Y_FILL, zz1), fc)
	st.commit(am)

	# ── surface 1：网格线（每条线两遍：近黑底衬 + 浅青主线）──
	var sl := SurfaceTool.new()
	sl.begin(Mesh.PRIMITIVE_LINES)

	# 纵向 12 条（沿 z）
	for i in COLS + 1:
		var x := -half + float(i) * cell
		var edge := (i == 0) or (i == COLS)
		_line(sl, Vector3(x, Y_DARK, -half), Vector3(x, Y_DARK, half), LINE_DARK)
		_line(sl, Vector3(x, Y_LINE, -half), Vector3(x, Y_LINE, half),
				LINE_EDGE if edge else LINE_LIGHT)

	# 横向 12 条（沿 x）
	for j in ROWS + 1:
		var z := -half + float(j) * cell
		if j == 0:
			_line(sl, Vector3(-half, Y_DARK, z), Vector3(half, Y_DARK, z), LINE_DARK)
			_line(sl, Vector3(-half, Y_LINE, z), Vector3(half, Y_LINE, z), LINE_ENEMY)
		elif j == ROWS:
			_line(sl, Vector3(-half, Y_DARK, z), Vector3(half, Y_DARK, z), LINE_DARK)
			_line(sl, Vector3(-half, Y_LINE, z), Vector3(half, Y_LINE, z), LINE_MINE)
		elif j == ENEMY_ROWS or j == ENEMY_ROWS + ISOLATION_ROWS:
			# 隔离区上下界 —— 橙虚线（用户：中 3 行不可放置，要看得出来）
			_line(sl, Vector3(-half, Y_DARK, z), Vector3(half, Y_DARK, z), LINE_DARK)
			_dashed(sl, Vector3(-half, Y_LINE, z), Vector3(half, Y_LINE, z),
					LINE_ISO, 2.0, 1.3)
		else:
			_line(sl, Vector3(-half, Y_DARK, z), Vector3(half, Y_DARK, z), LINE_DARK)
			_line(sl, Vector3(-half, Y_LINE, z), Vector3(half, Y_LINE, z), LINE_LIGHT)

	# 外框（四面都描一遍，压在所有线之上）
	for seg in [
		[Vector3(-half, 0, -half), Vector3(half, 0, -half)],
		[Vector3(-half, 0, half), Vector3(half, 0, half)],
		[Vector3(-half, 0, -half), Vector3(-half, 0, half)],
		[Vector3(half, 0, -half), Vector3(half, 0, half)],
	]:
		var a: Vector3 = seg[0]
		var b: Vector3 = seg[1]
		a.y = Y_DARK
		b.y = Y_DARK
		_line(sl, a, b, LINE_DARK)
		a.y = Y_LINE + 0.008
		b.y = Y_LINE + 0.008
		_line(sl, a, b, LINE_MINE)

	sl.commit(am)

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	am.surface_set_material(0, mat)
	am.surface_set_material(1, mat)
	return am


func _add_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		col: Color) -> void:
	for v in [a, b, c, a, c, d]:
		st.set_color(col)
		st.add_vertex(v)


func _line(st: SurfaceTool, a: Vector3, b: Vector3, col: Color) -> void:
	st.set_color(col)
	st.add_vertex(a)
	st.set_color(col)
	st.add_vertex(b)


func _dashed(st: SurfaceTool, a: Vector3, b: Vector3, col: Color,
		dash: float, gap: float) -> void:
	var total := a.distance_to(b)
	var dir := (b - a).normalized()
	var t := 0.0
	while t < total:
		var t2 := minf(t + dash, total)
		st.set_color(col)
		st.add_vertex(a + dir * t)
		st.set_color(col)
		st.add_vertex(a + dir * t2)
		t = t2 + gap


# ------------------------------------------------------------------ 落点高亮

func _build_highlight() -> void:
	if _highlight == null:
		_highlight = MeshInstance3D.new()
		_highlight.name = "BoardHighlight"
		_highlight.visible = false
		add_child(_highlight)
	_highlight.mesh = _make_highlight_mesh()


func _make_highlight_mesh() -> ArrayMesh:
	var am := ArrayMesh.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_quad(st, Vector3(-cell * 0.5, 0, -cell * 0.5),
			Vector3(cell * 0.5, 0, -cell * 0.5),
			Vector3(cell * 0.5, 0, cell * 0.5),
			Vector3(-cell * 0.5, 0, cell * 0.5),
			Color(0.745, 0.933, 0.973, 0.34))
	st.commit(am)

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	am.surface_set_material(0, mat)
	return am


## 高亮某一格（row/col 传 -1 取消）
func highlight(row: int, col: int) -> void:
	if row < 0 or col < 0 or row >= ROWS or col >= COLS:
		clear_highlight()
		return
	if _hl_row == row and _hl_col == col and _highlight.visible:
		return
	_hl_row = row
	_hl_col = col
	_highlight.position = cell_center(row, col)
	_highlight.visible = true


func clear_highlight() -> void:
	_hl_row = -1
	_hl_col = -1
	if _highlight:
		_highlight.visible = false


## 显隐。⚠️ 这是外部唯一需要的入口（用户：格子只在拖动时显形）
func set_board_visible(on: bool) -> void:
	visible = on
	if not on:
		clear_highlight()
