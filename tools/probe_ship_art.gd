extends Control

## 52 艘船立绘检查台 + 朝向标定台（非 headless）
##
## ══════════════════════════════════════════════════════════════════
##  为什么需要它
## ══════════════════════════════════════════════════════════════════
##  备战席改画 2D 立绘（EveBenchRail）之后必须回答两件事，而它们
##  在单张备战席截图里看不出来（只有 1~8 艘船、且都在小格子里）：
##
##    ① 官方渲染图的**构图 / 朝向是否统一**？
##       —— 若不统一，2D 方案就只是把「3D 模型朝向不一致」换成了
##          「2D 立绘朝向不一致」，问题没解决、只是换了个地方。
##
##    ② **哪些船需要镜像**（水平翻转）才能统一？
##       —— 这是可标定的：立绘翻转是纯 2D 显示操作，
##          改一个表就生效，不需要重渲任何资源。
##
##  输出：8×7 网格平铺 52 艘船，每格 = 立绘 + 序号 + id + 自动判定的朝向。
##
##  用法：
##    ① 非 headless 跑本场景，出图 user://ship_art_sheet.png
##    ② 肉眼看哪些格子的**船头朝向与多数不一致**（编号在每格左下）
##    ③ 把编号报给 AI → 写进 ship_art_orient.gd 的覆盖表
##
## ⚠️ 自动判定只是**初值**，不是结论。它的规则是「截面积小的一端 = 船头」，
##    对少数船型（船尾比船头窄、或船头带长刺）会判错。
##    所以最终以**人眼**为准 —— 这张图存在的意义就是让人眼做最终裁决。
##
## ── 跑法（⚠️ 不要加 --headless，headless 下截图不上报）────────────
##   "C:/godot/Godot_v4.7.1-stable_win64_console.exe" \
##     --path "F:/evezzq/eve自走棋918" --quit-after 240 \
##     res://tools/probe_ship_art.tscn

const INDEX_SCRIPT := preload("res://scripts/data/eve_ship_asset_index.gd")
const OUT_SHOT := "user://ship_art_sheet.png"

const COLS := 8
const ROWS := 7
const CELL := Vector2(240.0, 154.0)
const ART_H := 122.0
const TOP := 6.0

## 逐像素太慢（52 张 × 512² = 1300 万次）—— 采样步长。
const SAMPLE := 2

var _shot_done := false
var _frame := 0
## id -> 自动判定的朝向：1 = 头朝右/下，-1 = 头朝左/上，0 = 判不出
var _head: Dictionary = {}
## id -> bbox（Rect2i）
var _box: Dictionary = {}


func _ready() -> void:
	custom_minimum_size = Vector2(1920, 1080)
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_analyze()


## 逐艘算 bbox 与「船头朝哪」。
##
## 规则：把 alpha 掩膜沿**长轴**分成两半，**截面积小的一半是船头**。
## 依据：船头收敛、船尾宽 —— 这条对侧视图与俯视图都成立。
##
## 返回值：1 = 朝右/下，-1 = 朝左/上，0 = 判不出（两半面积相等 / 贴图取不到）。
func _analyze() -> void:
	for r in INDEX_SCRIPT.ROWS:
		var id := StringName(r[0])
		var tex := EveShipArt.portrait(id)
		if tex == null:
			_head[id] = 0
			_box[id] = Rect2i()
			continue
		var img := tex.get_image()
		if img == null or img.is_empty():
			_head[id] = 0
			_box[id] = Rect2i()
			continue
		var ur := img.get_used_rect()
		_box[id] = ur
		_head[id] = _guess_head(img, ur)


func _guess_head(img: Image, bbox: Rect2i) -> int:
	if bbox.size.x <= 2 or bbox.size.y <= 2:
		return 0
	var vertical := bbox.size.y > bbox.size.x
	var n := bbox.size.y if vertical else bbox.size.x
	var half := int(n / 2)
	var a := 0
	var b := 0
	var i := 0
	while i < n:
		var area := 0
		var j := 0
		var m := bbox.size.x if vertical else bbox.size.y
		while j < m:
			var x := bbox.position.x + (j if not vertical else i)
			var y := bbox.position.y + (i if not vertical else j)
			if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
				if img.get_pixel(x, y).a > 0.25:
					area += 1
			j += SAMPLE
		if i < half:
			a += area
		else:
			b += area
		i += SAMPLE
	if a == b:
		return 0
	return -1 if a < b else 1


func _process(_delta: float) -> void:
	_frame += 1
	if _frame == 12 and not _shot_done:
		_shot_done = true
		_shot()


func _draw() -> void:
	var font := ThemeDB.fallback_font
	for idx in INDEX_SCRIPT.ROWS.size():
		var r = INDEX_SCRIPT.ROWS[idx]
		var id := StringName(r[0])
		var col := idx % COLS
		var row := idx / COLS
		var cell := Rect2(Vector2(col * CELL.x, row * CELL.y), CELL)

		# 格底（深色，衬托立绘）
		draw_rect(cell, Color(0.031, 0.043, 0.055, 0.90), true)
		draw_rect(cell, Color(0.30, 0.38, 0.43, 0.55), false, 1.0)

		# 立绘（与 EveBenchRail 同一取用方式：按 alpha 包围盒 contain）
		var art := Rect2(cell.position + Vector2(4.0, TOP),
				Vector2(CELL.x - 8.0, ART_H))
		EveShipArt.draw_ship(self, art, id, Color.WHITE)

		# 序号（该船在表里的下标，报给 AI 就报这个）
		var hd: int = int(_head.get(id, 0))
		var hd_txt := "→" if hd > 0 else ("←" if hd < 0 else "?")
		var hd_col := Color(0.45, 0.85, 0.95) if hd != 0 else Color(0.9, 0.5, 0.3)
		var bx: Rect2i = _box.get(id, Rect2i())
		var ratio := 0.0
		if bx.size.y > 0:
			ratio = float(bx.size.x) / float(bx.size.y)
		draw_string(font, Vector2(cell.position.x + 6.0, cell.end.y - 18.0),
				"%d" % idx, HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
				Color(1.0, 0.85, 0.4))
		draw_string(font, Vector2(cell.position.x + 24.0, cell.end.y - 18.0),
				"%s %s" % [hd_txt, String(id)], HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
				Color(0.83, 0.90, 0.93))
		draw_string(font, Vector2(cell.position.x + 6.0, cell.end.y - 5.0),
				"bbox %d×%d  %s" % [
					bx.size.x, bx.size.y,
					("竖" if ratio < 1.0 else "横")],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 9,
				Color(0.55, 0.62, 0.68))

	# 抬头说明
	draw_rect(Rect2(Vector2(0, 0), Vector2(1920, 42)), Color(0.02, 0.03, 0.04, 0.92), true)
	draw_string(font, Vector2(12.0, 27.0),
			"52 艘船立绘检查台 · 箭头=自动判定的船头朝向 · 报「序号」即可标定镜像",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.86, 0.93, 0.96))


func _shot() -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(OUT_SHOT)
	print("[ART] 图 -> %s" % ProjectSettings.globalize_path(OUT_SHOT))

	# 同时把自动判定的结果打成文本，方便直接写进表里
	var left_n := 0
	var right_n := 0
	var unk_n := 0
	var lines: PackedStringArray = []
	for idx in INDEX_SCRIPT.ROWS.size():
		var id := StringName(INDEX_SCRIPT.ROWS[idx][0])
		var hd: int = int(_head.get(id, 0))
		var bx: Rect2i = _box.get(id, Rect2i())
		var shape := "竖" if (bx.size.y > bx.size.x) else "横"
		lines.append("%2d %-14s %s %s  bbox %d×%d" % [
			idx, String(id), ("→右" if hd > 0 else ("←左" if hd < 0 else " ? ")),
			shape, bx.size.x, bx.size.y])
		if hd > 0:
			right_n += 1
		elif hd < 0:
			left_n += 1
		else:
			unk_n += 1
	print("[ART] ==== 自动判定汇总 ====")
	print("[ART] 头朝右 %d · 头朝左 %d · 判不出 %d" % [right_n, left_n, unk_n])
	for l in lines:
		print("[ART] " + l)
	print("[ART] ==== DONE ====")
