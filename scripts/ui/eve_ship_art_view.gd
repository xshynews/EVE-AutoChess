extends Control
class_name EveShipArtView

## EVE 自走棋 —— 舰船立绘视图（**全工程唯一**的画立绘控件）
##
## ══════════════════════════════════════════════════════════════════
##  [WHY] 为什么有这个文件（2026-10-28）
## ══════════════════════════════════════════════════════════════════
##  舰船图鉴第一版用了 `scripts/visual/ship_portrait_art.gd` —— 那是
##  2026-09 没有任何美术资源时画的**程序化几何侧影**（几个梯形色块）。
##  52 艘船画出来几乎是同一个形状，用户原话：「用莫名其妙的图标是咋回事」。
##
##  而商店卡（`eve_shop.gd` 的内部类 `_CardArt`）早就在用**真立绘**了 ——
##  `EveShipArt` → `assets/ships/<id>.png`（官方 1024px 渲染图抠像）。
##  同一个游戏里两套画法，就是"图鉴像另一个游戏"的根因。
##
##  ⇒ 把 `_CardArt` 的实现提出来提到这里，**商店 / 图鉴 / 详情大图共用一份**。
##    ⛔ 别再在任何地方另写一遍「画舰船」：加新场合就用这个控件。
##
##  [SRC] 立绘来源：`EveShipArt.portrait(ship_key)`，文件名 = 舰船 id。
##  [PITFALL] 立绘是 512×512 方画布 + 四周透明留白。**必须**走
##    `EveShipArt.draw_ship()`（内部先按 `used_rect` 裁留白再等比 contain），
##    直接 draw_texture_rect 整张方图会让细长船缩成"远处的蚊子"。

## 要画的舰船 id（= EveShipTable 的 id 列）
var ship_key: StringName = &"":
	set(v):
		if ship_key == v:
			return
		ship_key = v
		_tex = EveShipArt.portrait(v)
		queue_redraw()

## 压暗（买不起 / 未选中）。云顶口径：降亮度，而不是盖一层灰罩。
##
## ★ 用 setter 而不是让调用方手动 queue_redraw：商店里有 `art.dimmed = x`
##   这种直接赋值的写法，裸变量会导致"改了不重绘"。
var dimmed: bool = false:
	set(v):
		if dimmed == v:
			return
		dimmed = v
		queue_redraw()

## 派系色（只在**没有立绘**时画兜底剪影用）
var accent: Color = Color(0.55, 0.78, 0.82):
	set(v):
		accent = v
		queue_redraw()

## 四边内缩（px）。0 = 船体撑满整个控件（商店卡那种紧排用）；
## 图鉴卡格与格之间没有间隙，撑满会让两条船尖顶到一起 ⇒ 给 4~6px 呼吸。
var inset: float = 0.0:
	set(v):
		inset = v
		queue_redraw()

var _tex: Texture2D = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func set_ship_key(k: StringName) -> void:
	ship_key = k


## 有没有真立绘（验收 / 探针用）
func has_art() -> bool:
	return _tex != null


func _draw() -> void:
	if size.x <= 2.0 or size.y <= 2.0:
		return
	var pad := maxf(inset, 0.0)
	var box := Rect2(Vector2(pad, pad), size - Vector2(pad, pad) * 2.0)
	if box.size.x <= 2.0 or box.size.y <= 2.0:
		box = Rect2(Vector2.ZERO, size)
	if _tex != null:
		var tint := Color(0.62, 0.66, 0.70) if dimmed else Color.WHITE
		EveShipArt.draw_ship(self, box, ship_key, tint)
		return
	_draw_placeholder()


## 无立绘兜底：淡色机库剪影（不是抽象图标，只是一条能看出"这里该有艘船"的线框）
func _draw_placeholder() -> void:
	var cx := size.x * 0.5
	var s := minf(size.x, size.y) * 0.42
	if s <= 3.0:
		return
	var col := Color(accent.r, accent.g, accent.b, 0.30)
	var y := size.y * 0.5
	var w := s * 1.6
	draw_line(Vector2(cx - w * 0.5, y + s * 0.42), Vector2(cx + w * 0.5, y + s * 0.42), col, 1.4)
	draw_line(Vector2(cx - w * 0.35, y + s * 0.42), Vector2(cx - w * 0.35, y - s * 0.10), col, 1.4)
	draw_line(Vector2(cx - w * 0.35, y - s * 0.10), Vector2(cx, y - s * 0.45), col, 1.4)
	draw_line(Vector2(cx, y - s * 0.45), Vector2(cx + w * 0.35, y - s * 0.10), col, 1.4)
	draw_line(Vector2(cx + w * 0.35, y - s * 0.10), Vector2(cx + w * 0.35, y + s * 0.42), col, 1.4)
