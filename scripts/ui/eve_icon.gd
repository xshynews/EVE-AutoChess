extends Control
class_name EveIcon

## EVE 自走棋 —— 几何描边图标（自绘，无贴图）
##
## ⚠️ 为什么不用 emoji / 图标字体：
##    Windows 上 ⚔ ⬆ 🔒 ✂ ⚙ 这类字符会落到 Segoe UI Emoji，
##    渲染成彩色 emoji —— 和 EVE 的克制灰青风格完全冲突。
##    工程规范因此只允许几何字符（▲ ▼ ◆ ● ✦ ★ ↻ ≡），
##    需要更具体的图形就自绘。这个文件就是自绘那一半。
##
## 画法约定：所有图标在 24×24 的逻辑坐标系里描述（与设计稿的 SVG viewBox 同源），
## 实际尺寸由控件 size 决定，等比缩放且居中对齐。
##
## 用法：
##   var ic := EveIcon.new()
##   ic.icon = &"shield"
##   ic.color = EveWindow.C_SHIELD
##   ic.custom_minimum_size = Vector2(18, 18)

@export var icon: StringName = &"": set = set_icon
@export var color: Color = Color(0.70, 0.82, 0.85): set = set_color
@export var line_width: float = 1.5: set = set_line_width


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_icon(v: StringName) -> void:
	icon = v
	queue_redraw()


func set_color(v: Color) -> void:
	color = v
	queue_redraw()


func set_line_width(v: float) -> void:
	line_width = v
	queue_redraw()


func _draw() -> void:
	if icon == &"":
		return
	var s := minf(size.x, size.y) / 24.0
	if s <= 0.0:
		return
	# ⚠️ 这里不用 lambda 做坐标换算。
	#    GDScript 把「赋给局部变量的 lambda」用 P(...) 直接调用会报
	#    "Function P() not found in base self"（它被当成 self 的方法去查了），
	#    必须写 P.call(...)。图标是高频绘制路径，整份代码都走 .call() 太别扭，
	#    所以改成把换算参数缓存到成员上、用普通方法画。
	_o = Vector2((size.x - 24.0 * s) * 0.5, (size.y - 24.0 * s) * 0.5)
	_s = s
	_lw = maxf(1.0, line_width * s)

	match icon:
		# ── 装备栏位 8 格（与设计稿 V3 的 8 枚图标一一对应）──
		&"armor_plate", &"lines":
			_poly([[5, 7], [19, 7]])
			_poly([[5, 12], [19, 12]])
			_poly([[5, 17], [19, 17]])
		&"shield":
			_poly([[12, 3], [19, 6.2], [19, 11.8], [12, 21], [5, 11.8], [5, 6.2]], true)
		&"chevrons":
			_poly([[6, 5.5], [11.5, 12], [6, 18.5]])
			_poly([[13, 5.5], [18.5, 12], [13, 18.5]])
		&"capacitor":
			draw_rect(Rect2(_pt(4, 8), Vector2(13, 9) * _s), color, false, _lw)
			_poly([[17, 10.5], [20, 10.5]])
			_poly([[17, 14.5], [20, 14.5]])
			_poly([[20, 10.5], [20, 14.5]])
		&"targeting":
			draw_arc(_pt(12, 12), 2.6 * _s, 0.0, TAU, 24, color, _lw, true)
			_poly([[10, 10], [5.5, 5.5]])
			_poly([[14, 10], [18.5, 5.5]])
			_poly([[10, 14], [5.5, 18.5]])
			_poly([[14, 14], [18.5, 18.5]])
		&"railgun":
			draw_rect(Rect2(_pt(3.5, 10), Vector2(12, 4) * _s), color, false, _lw)
			_poly([[15.5, 8.5], [15.5, 15.5]])
			_poly([[19, 10.5], [19, 13.5]])
		&"diamond":
			_poly([[12, 3.5], [18.5, 12], [12, 20.5], [5.5, 12]], true)
		&"plus":
			_poly([[12, 4.5], [12, 19.5]])
			_poly([[4.5, 12], [19.5, 12]])

		# ── 其他（档案窗空态、日志分类等）──
		&"hangar":
			_poly([[4, 17], [20, 17]])
			_poly([[6, 17], [6, 9.5], [12, 5.5], [18, 9.5], [18, 17]])
			_poly([[10, 17], [10, 12.5], [14, 12.5], [14, 17]])
		&"clock":
			draw_arc(_pt(12, 12), 9.5 * _s, 0.0, TAU, 32, color, _lw, true)
			_poly([[12, 12], [12, 5.5]])
			_poly([[12, 12], [17, 14]])
		&"chevron_down":
			_poly([[6, 9.5], [12, 15.5], [18, 9.5]])
		&"chevron_up":
			_poly([[6, 14.5], [12, 8.5], [18, 14.5]])
		&"coin":
			draw_arc(_pt(12, 12), 8.0 * _s, 0.0, TAU, 28, color, _lw, true)
			_poly([[12, 8], [12, 16]])
		&"beacon":
			# 信标塔：三角塔身 + 底座 + 塔顶两道信号弧
			# 用途 = 顶条的「信标结构值」（一局的生命线，交接文档 §11 P0）
			_poly([[9.5, 19.5], [12.0, 9.5], [14.5, 19.5]], true)
			_poly([[8.0, 19.5], [16.0, 19.5]])
			draw_arc(_pt(12, 9.5), 3.0 * _s, PI, TAU, 16, color, _lw, true)
			draw_arc(_pt(12, 9.5), 5.2 * _s, PI, TAU, 20, color, _lw * 0.8, true)
		&"star":
			# 五星（沿用 ▲ 的几何语言：只画外轮廓，不填）
			_poly([[12, 3.5], [14.4, 9.6], [20.8, 10.1], [15.9, 14.3],
					[17.5, 20.6], [12, 17.2], [6.5, 20.6], [8.1, 14.3],
					[3.2, 10.1], [9.6, 9.6]], true)
		_:
			# 未登记的名字画个方框，方便一眼看出「这里少了个图标」
			draw_rect(Rect2(_pt(5, 5), Vector2(14, 14) * _s), color, false, _lw)


# ── 绘制辅助（24×24 逻辑坐标 → 像素）─────────────────────────────
var _o := Vector2.ZERO
var _s := 1.0
var _lw := 1.0


func _pt(x: float, y: float) -> Vector2:
	return _o + Vector2(x, y) * _s


func _poly(pts: Array, closed: bool = false) -> void:
	var arr := PackedVector2Array()
	for pt in pts:
		arr.append(_pt(pt[0], pt[1]))
	if closed and arr.size() > 0:
		arr.append(arr[0])
	draw_polyline(arr, color, _lw, true)


## 便捷构造：一行建好一枚图标控件
static func make(name: StringName, px: float, col: Color,
		width: float = 1.5) -> EveIcon:
	var ic := EveIcon.new()
	ic.icon = name
	ic.color = col
	ic.line_width = width
	ic.custom_minimum_size = Vector2(px, px)
	ic.size = Vector2(px, px)
	return ic
