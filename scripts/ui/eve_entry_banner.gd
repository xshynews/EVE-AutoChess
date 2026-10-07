extends Control


## ★ 字号缩放（2026-10-07）：⛔ 别直接调 `add_theme_font_size_override`，
## 一律走 `FONT.fs(node, 设计字号)` —— 它同时记住设计字号（供改滑块时就地重算）。
## ⚠️ 子类（`extends eve_window.gd` 的那 9 个）靠**继承**拿到这个常量，
##    它们自己再写一个会撞名（基类已有同名成员 ⇒ 子类编译失败，本工程踩过）。
const FONT := preload("res://scripts/ui/eve_font.gd")
## EVE 自走棋 —— 节点进场词横幅（阶段 C 收尾）
##
## ══════════════════════════════════════════════════════════════════
##  它是什么
## ══════════════════════════════════════════════════════════════════
##  每个**战斗类**节点进入准备阶段时，居中浮出一段字幕：
##
##        ────────────◆────────────          ① 规则线（自绘）
##              节点 05 / 15 · 遭遇战          ② 节点号 + 类型标签
##        旗舰信号 —— 精锐先锋，装甲厚得不像海盗。   ③ 进场词（主角）
##
##  停留几秒后整体淡出。**本文件不存任何文案** —— ③ 来自
##  `EveNodeTable.ROWS[].line`（唯一真源），② 来自 `EveNodeTable.label_of()`。
##
## ── 为什么它可以做得醒目，而「功能区必须小」这条依然成立 ──────────
##  工程口径把屏幕元素分两类：
##    · **常驻功能区**（六窗 + 轨道）—— 必须小，视觉重点是战场；
##      这条由 `EveHudRoot` 的 RECT_* 与「UI 面积占屏比 ≈19.5%」守着。
##    · **打断式 / 瞬时元素**（事件四选一、伤害数字、本横幅）—— 允许压屏，
##      因为一局只闪几次。事件面板 1000×296 就是按这条口径放的。
##  进场词属第二类：每个节点一次、共 4.2 秒、`mouse_filter = IGNORE`
##  不接任何输入。它**不占常驻 UI 面积** —— 开局占屏比一个像素都没变。
##
## ── 为什么 ③ 用 Label 而不是像伤害数字那样 `_draw()` ────────────
##  伤害数字用 `_draw()` 是因为量太大（峰值几十条/秒，逐个建 Label 会掉帧）。
##  本横幅一辈子只有三个 Label，量不成问题。
##  而**中文**必须走 Label 的字体解析链：本工程没有自定义主题字体、
##  也没有 .ttf 资源，简中靠系统字体回退渲染 ——
##  `_draw()` 手动取 `ThemeDB.fallback_font` 会绕开这条链，风险是整行豆腐块。
##
## ⚠️ 可读性靠 Label 的 `font_outline_color`（不加背景板、不压暗天空盒）——
##    亮星云上没描边的浅色字会**整条消失**，这是伤害数字层已经踩过的教训。
##
## ── 为什么事件节点（4 / 10 / 14）不弹它 ──────────────────────────
##  事件节点的进场词已经由事件面板的引导语展示（`show_event(opts, line, meta)`）。
##  同一句话同一时刻出现在横幅和面板上会互相打脸。

## 淡入 / 停留 / 淡出（秒）。LIFE = 总寿命，主控与验收都读它。
const FADE_IN := 0.30
## 停留时长。2026-10-01 用户要求「回合名称的显示时间再长一点，
## 大约 3S 以上到 5S 之间」⇒ 总在屏 = FADE_IN + HOLD + FADE_OUT = **4.8s**。
## ⚠️ 改 HOLD 就会改总时长，别只看这一个数。
const HOLD := 3.80
const FADE_OUT := 0.70
const LIFE := FADE_IN + HOLD + FADE_OUT

## 淡入期间的上浮距离（像素）：静止出现会显得「贴上去」，上浮才有入场感
const RISE := 10.0

## 横幅顶边默认 y。选 196 的理由：
##   顶条在 6..46，事件面板顶边在 300，商店在 898 ⇒ 196..286 是**空窗带**，
##   三个常驻件一个都碰不到，也压不到屏幕中段（那里是舰船与战场中心的所在）。
const BASE_Y := 196.0
## 容器高度（不是视觉高度，是排版用）：规则线 9 + 间距 5 + 标签 ~15
## + 间距 5 + 正文 ~29 ≈ 63。给 90 留富余，且 196+90=286 仍不碰事件面板。
const BOX_H := 90.0

const RULE_W := 420.0
const RULE_H := 9.0
## 正文与标签字号。「放大」是这条交付的核心 ——
## 战斗日志窗里那行只有 **9px**（`eve_combat_log.gd` 的 font_size），
## 而且 172px 窗宽盛不下整句，会被截成「前方发现两艘散兵级…」。
## 这里是 22px 且整屏居中、不截断 —— 量级差别一眼可见。
## 验收断言直接读 `line_font_size()`。
const LINE_FONT := 22
const TAG_FONT := 11

## 节点类型 → 标签配色。纯表现层，与 `EveNodeTable.TYPE_LABELS` 的语义对齐：
##   遭遇战=常规青 / 精英战=装甲金（心跳节点）/ 首领战=结构红（危险）/ 事件=护盾蓝
const TYPE_COLORS := {
	&"battle": Color(0.55, 0.78, 0.82),
	&"elite": Color(0.85, 0.68, 0.28),
	&"boss": Color(0.82, 0.32, 0.28),
	&"event": Color(0.50, 0.83, 0.94),
}

var _showing := false
var _t := 0.0

var _box: VBoxContainer
var _rule: Control
var _tag_node: Label
var _tag_type: Label
var _line: Label


func _ready() -> void:
	# ⚠️ 三件缺一不可（缺了就是「看不见 / 点不动」这类静默事故）：
	#    ① 铺满视口 —— 否则 size 为 0，子容器没有可排版的宽度；
	#    ② IGNORE —— 字幕绝不能抢鼠标（否则商店/棋盘的点击被一层看不见的东西挡住）；
	#    ③ 默认不自 process —— 空闲时它是零成本。
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	visible = false
	set_process(false)


func _build() -> void:
	_box = VBoxContainer.new()
	_box.name = "Banner"
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_box.offset_top = BASE_Y
	_box.offset_bottom = BASE_Y + BOX_H
	_box.add_theme_constant_override("separation", 5)
	_box.alignment = BoxContainer.ALIGNMENT_BEGIN
	add_child(_box)

	_rule = _Rule.new()
	_rule.name = "Rule"
	_rule.custom_minimum_size = Vector2(RULE_W, RULE_H)
	_rule.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.add_child(_rule)

	var tag := HBoxContainer.new()
	tag.add_theme_constant_override("separation", 6)
	tag.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.add_child(tag)

	_tag_node = Label.new()
	FONT.fs(_tag_node, TAG_FONT)
	_tag_node.add_theme_color_override("font_color", EveWindow.C_ACCENT)
	tag.add_child(_tag_node)

	var dot := Label.new()
	dot.text = "·"
	FONT.fs(dot, TAG_FONT)
	dot.add_theme_color_override("font_color", EveWindow.C_TEXT_FAINT)
	tag.add_child(dot)

	_tag_type = Label.new()
	FONT.fs(_tag_type, TAG_FONT)
	tag.add_child(_tag_type)

	_line = Label.new()
	_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	FONT.fs(_line, LINE_FONT)
	# 比常驻正文（C_TEXT = 0.70,0.82,0.85）更亮一档 —— 它是这一幕的主角
	_line.add_theme_color_override("font_color", Color(0.92, 0.96, 0.97))
	_line.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.04, 0.94))
	_line.add_theme_constant_override("outline_size", 4)
	_box.add_child(_line)


# ------------------------------------------------------------------ 对外接口

## 弹一段进场字幕。
##
## 参数：index = 节点号（1-based）· type_key = EveNodeTable 的 type 键 ·
##       line = 该节点的进场词。**不传文案以外的任何东西** —— 配色由 type_key 决定。
func show_entry(index: int, type_key: StringName, line: String) -> void:
	if _box == null:
		return
	_tag_node.text = "节点 %02d / %d" % [maxi(1, index), EveNodeTable.TOTAL]
	_tag_type.text = EveNodeTable.label_of(type_key)
	var col: Color = TYPE_COLORS.get(type_key, EveWindow.C_ACCENT)
	_tag_type.add_theme_color_override("font_color", col)
	_rule.set("accent", col)
	_rule.queue_redraw()
	_line.text = line
	_t = 0.0
	_showing = true
	visible = true
	set_process(true)
	_apply(0.0)


## 立即收掉（开战 / 重开一局）。不等它自然淡完 ——
## 玩家按了「开战」就是他不想再读这行字了。
func clear() -> void:
	_showing = false
	_t = 0.0
	visible = false
	set_process(false)


## 推进寿命。
##
## ⚠️ 单独开一个公开 `tick` 而不把逻辑写在 `_process` 里，是为了让验收脚本
##    能按需推进（无头下靠帧数推 4.2 秒太慢，也不稳）。`_process` 只是它的转发。
func tick(delta: float) -> void:
	if not _showing:
		return
	_t += delta
	if _t >= LIFE:
		clear()
		return
	_apply(_t)


func _process(delta: float) -> void:
	tick(delta)


func _apply(t: float) -> void:
	var a := 1.0
	if t < FADE_IN:
		a = t / FADE_IN
	elif t > FADE_IN + HOLD:
		a = maxf(0.0, 1.0 - (t - FADE_IN - HOLD) / FADE_OUT)
	modulate.a = a
	# 上浮：先快后慢（起手一冲再缓下来）。匀速上浮看起来像吊线木偶。
	var e := 1.0 - pow(1.0 - clampf(t / FADE_IN, 0.0, 1.0), 2.0)
	var dy := -RISE * e
	_box.offset_top = BASE_Y + dy
	_box.offset_bottom = BASE_Y + BOX_H + dy


# ------------------------------------------------------------------ 验收用读数

## 1 = 正在显示，0 = 已收（与 `EveBattleFx.active_count()` 同一套口径）
func active_count() -> int:
	return 1 if _showing else 0


func is_showing() -> bool:
	return _showing


## 当前正文（断言「显示的是本节点的进场词」）
func current_text() -> String:
	return _line.text if _line != null else ""


func current_type_text() -> String:
	return _tag_type.text if _tag_type != null else ""


func current_node_text() -> String:
	return _tag_node.text if _tag_node != null else ""


## 正文实际字号 —— 「放大」是这条交付的核心，验收直接量它，不靠肉眼判断
func line_font_size() -> int:
	return _line.get_theme_font_size("font_size") if _line != null else 0


## 已显示时长（秒），用于断言「寿命到了会自己收」
func elapsed() -> float:
	return _t


## 总寿命（秒）—— 验收按它推 tick，别在测试里重复写 4.2 这个数
func life_seconds() -> float:
	return LIFE


# ------------------------------------------------------------------ 自绘规则线

## 两端渐隐 + 中央加亮段 + 中央菱形。
##
## 中央菱形是**自绘多边形**而不是 `◆` 字符：字符要走字体回退，
## 本工程没有自带字体，几何字符在某些 Windows 环境下会落到 emoji 字体
## 被渲染成彩色方块（`⚔ ⬆ 🔒` 已经踩过这个坑），自绘没有这个风险。
class _Rule extends Control:
	var accent := Color(0.55, 0.78, 0.82)

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var w := size.x
		if w <= 16.0:
			return
		var y := size.y * 0.5
		var cx := w * 0.5
		var half := 46.0
		draw_line(Vector2(cx - half, y), Vector2(cx + half, y),
				Color(accent.r, accent.g, accent.b, 0.72), 1.6)

		var tail := cx - half
		if tail > 1.0:
			var steps := 24
			var seg := tail / float(steps)
			for i in steps:
				var k := float(i) / float(steps)
				var a := 0.26 * (1.0 - k) * (1.0 - k)
				var x0 := float(i) * seg
				var col := Color(accent.r, accent.g, accent.b, a)
				draw_line(Vector2(x0, y), Vector2(x0 + seg + 0.5, y), col, 1.0)
				draw_line(Vector2(w - x0 - seg - 0.5, y), Vector2(w - x0, y), col, 1.0)

		var r := 3.2
		var pts := PackedVector2Array([
			Vector2(cx, y - r), Vector2(cx + r, y),
			Vector2(cx, y + r), Vector2(cx - r, y),
		])
		draw_colored_polygon(pts, Color(accent.r, accent.g, accent.b, 0.92))
		draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]),
				Color(0.918, 0.969, 0.980, 0.85), 1.0)
