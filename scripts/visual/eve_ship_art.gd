extends RefCounted
class_name EveShipArt

## EVE 自走棋 —— 舰船立绘资源（官方渲染图，透明底）
##
## 数据来源（外部离线管线，不在工程内跑）：
##   images.evetech.net/types/<typeID>/render?size=1024   ← 官方 1024px 渲染图
##   → isnet-general-use 语义分割抠像 + 最大连通域清理
##   → 面积归一化（前景占画布 22%）+ 512×512 居中画布
##   脚本：C:\godot\_export\fetch_official.py / off_cut_all.py / cut_models.py
##
## ⚠️ 文件名 = EveShipTable 的 id 列（condor / punisher / apocalypse …），
##    与本文件的 [member DIR] 拼起来就是资源路径。**不要按中文名找文件。**
##
## ⚠️ 图片是 512×512 的 1:1 画布，船体已等比居中、四周留白。
##    所以绘制时可以直接 contain 进任意矩形，不会再出现「舰艏被裁掉」
##    （那个坑在旧的程序化立绘上踩过一次，见 ship_portrait_art.gd 的注释）。

## 资源目录。约定：`res://assets/ships/<id>.png`
const DIR := "res://assets/ships/"
const EXT := ".png"

## 立绘缓存。Key = ship_key，Value = Texture2D 或 null（未命中也要缓存，
## 避免每帧对同一个不存在的路径反复做 ResourceLoader.exists 的磁盘探测）。
static var _cache: Dictionary = {}

## 有效像素包围盒缓存（见 [method used_rect]）
static var _bbox: Dictionary = {}


## 取一艘船的立绘。没有资源时返回 null（调用方负责画占位）。
static func portrait(ship_key: StringName) -> Texture2D:
	var k := String(ship_key)
	if k.is_empty():
		return null
	if _cache.has(k):
		return _cache[k]
	var path := DIR + k + EXT
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	_cache[k] = tex
	return tex


## 是否已有立绘
static func has_portrait(ship_key: StringName) -> bool:
	return portrait(ship_key) != null


## 立绘里【真正画了船】的那块矩形（纹理坐标），即去掉透明留白后的包围盒。
##
## ⚠️ 为什么必须有这一步：
##   管线产出的是 **512×512 方画布**（面积归一化要求），船被居中放进方形里，
##   四周是透明留白。而 HUD 里的立绘槽普遍是【扁的】（卡面约 200×55、
##   档案约 168×38）。直接把整张方图 contain 进去，会被槽位**高度**卡住，
##   船只占槽宽的三分之一 —— 看起来像「远处的蚊子」。
##   裁掉留白后缩放系数由「船的实际包围盒」决定，同样的槽位能大出 1.5~3 倍。
##
## 各船 bbox 长宽比差异很大（长尾鲛 1005×356 很扁，惩罚者 1014×911 近方），
## 所以这一步对扁船的收益最大。
static func used_rect(ship_key: StringName) -> Rect2:
	var k := String(ship_key)
	if _bbox.has(k):
		return _bbox[k]
	var tex := portrait(ship_key)
	var r := Rect2()
	if tex != null:
		var img := tex.get_image()
		if img != null and not img.is_empty():
			var ur := img.get_used_rect()
			if ur.size.x > 0 and ur.size.y > 0:
				r = Rect2(ur)
	if r.size.x <= 0.0:
		# 取不到像素（纹理被压缩/无 alpha）→ 退回整张图，行为与不做裁剪一致
		if tex != null:
			r = Rect2(Vector2.ZERO, Vector2(tex.get_width(), tex.get_height()))
	_bbox[k] = r
	return r


## 把立绘「裁掉透明留白后」等比 contain 画进 rect 的中心。
##
## 与 [method draw_portrait] 的区别只有一点：缩放基准是船的包围盒而不是整张
## 方画布。**HUD 里一律用这个**，[method draw_portrait] 只留给需要完整方画布的场合。
static func draw_ship(ci: CanvasItem, rect: Rect2, ship_key: StringName,
		tint: Color = Color.WHITE) -> void:
	var tex := portrait(ship_key)
	if tex == null:
		return
	draw_portrait(ci, rect, tex, tint, used_rect(ship_key))


## 把（[param src] 指定的）一块贴图等比 contain 画进 rect 的中心。
## src 传 Rect2() 表示用整张贴图。
##
## 与 TextureRect 的 STRETCH_KEEP_ASPECT_CENTERED 等价，但用于 _draw() 场合。
## tint 用于在未选中时压暗（云顶口径：非选中卡面降亮度而不是加灰罩）。
static func draw_portrait(ci: CanvasItem, rect: Rect2, tex: Texture2D,
		tint: Color = Color.WHITE, src: Rect2 = Rect2()) -> void:
	if tex == null or rect.size.x <= 2.0 or rect.size.y <= 2.0:
		return
	if src.size.x <= 0.0 or src.size.y <= 0.0:
		src = Rect2(Vector2.ZERO, Vector2(tex.get_width(), tex.get_height()))
	if src.size.x <= 0.0 or src.size.y <= 0.0:
		return
	var s := minf(rect.size.x / src.size.x, rect.size.y / src.size.y)
	var d := src.size * s
	var o := rect.position + (rect.size - d) * 0.5
	ci.draw_texture_rect_region(tex, Rect2(o, d), src, tint)
