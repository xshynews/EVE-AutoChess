extends Control
## ★ 字号缩放（2026-10-07）：自绘文字的字号也要过它（`FONT.s(设计字号)`）。
const FONT := preload("res://scripts/ui/eve_font.gd")

## EVE 自走棋 —— 伤害数字层（阶段 D）
##
## ══════════════════════════════════════════════════════════════════
##  它是什么，以及为什么不做成 3D 飘字
## ══════════════════════════════════════════════════════════════════
##  战斗反馈分两层，刻意分家（与 `eve_battle_fx.gd` 的分工）：
##    · **世界空间**（`EveBattleFx`）：曳光、命中爆点、击毁爆炸 ——
##      这些东西「发生在某个位置」，随相机远近缩放是对的。
##    · **屏幕空间**（本文件）：伤害**数字** ——
##      数字是给人读的，必须恒定字号。挂在世界空间里的 Label3D 会随相机
##      推近而糊满屏、拉远而变成一排小点，两头都读不出来。
##
##  ── 为什么数字要「往上飘 + 淡出」而不是原地闪 ─────────────────────
##  集火时同一艘船一秒能挨五六下。原地闪的话数字会叠成一坨黑块。
##  往上飘让「后来的数字压在先来的上面」，再叠一个随机横向抖动，
##  同一时刻的多个数字就读得出来 —— 这也是云顶/暗黑的通行做法。
##
## ── 为什么数量上限是硬的 ──────────────────────────────────────────
##    6v6、30Hz 开火，峰值每秒几十条。无上限的话每帧在 add/remove 上百个
##    Label，无头验收会明显变慢（实测过），实机上直接掉帧。
##    超过上限时**丢最老的**：刚打出的那一下永远是玩家最该看到的。
##
## ⚠️ 这一层铺满全屏且 `mouse_filter = IGNORE` —— 它绝不能吃掉鼠标事件，
##    否则商店/棋盘的点击会被一层看不见的东西挡住（症状是「哪儿都点不动」）。

## 单条飘字的存活时间（秒）
const LIFE := 0.85
## 存活上限（超过就丢最老的）
const MAX_POPUPS := 48
## 同屏同位置的横向散开半径（像素）
const JITTER_X := 26.0
## 一个数字最多占多少像素宽 —— 超过就压缩，防止 BOSS 暴击的 5 位数糊出屏幕
const MAX_TEXT_W := 92.0

## 正在飘的：元素 = {
##   "pos": Vector2（起始屏幕坐标）, "t": float, "life": float,
##   "text": String, "color": Color, "size": int, "dx": float, "crit": bool }
var _popups: Array[Dictionary] = []


func _ready() -> void:
	# ⚠️ 三件缺一不可（缺了就是「看不见 / 点不动」这类静默事故）：
	#    ① 铺满视口 —— 否则 size 为 0，draw 什么都不画；
	#    ② IGNORE —— 飘字层绝不能抢鼠标；
	#    ③ 不在 _process 里 queue_redraw 之外做任何事 —— 它有 48 条上限。
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## 当前活跃飘字数（验收断言用）
func active_count() -> int:
	return _popups.size()


## 清空（重开一局 / 进准备阶段时调）
func clear() -> void:
	_popups.clear()
	queue_redraw()


## 冒一个伤害数字。
##
## 参数：
##   screen_pos  世界坐标换算出来的**屏幕**位置（由主控调 arena.world_to_screen）
##   damage      实际伤害值；<= 0 且 hit 为真时也算有效（护盾吃完的零头）
##   quality     EveCombatCore.HitQuality 档位
##   hit         false = 未命中（显示 miss 而不是 0）
func pop(screen_pos: Vector2, damage: float, quality: int, hit: bool) -> void:
	var text := ""
	var color := Color(0.70, 0.82, 0.86)
	var size := 13
	var crit := false

	if not hit:
		text = "miss"
		color = Color(0.48, 0.55, 0.58)
		size = 11
	elif damage < 1.0:
		# 打中了但这一层已经被吃干（护盾见底时常见）—— 报小数字而不是 0
		text = "%d" % int(round(maxf(1.0, damage)))
		color = Color(0.52, 0.62, 0.68)
	else:
		text = "%d" % int(round(damage))
		# 配色跟打击特效同一套口径（见 EveBattleFx.QUALITY_COLORS）
		match clampi(quality, 0, 6):
			1: color = Color(0.62, 0.70, 0.72)
			2: color = Color(0.70, 0.82, 0.86)
			3: color = Color(0.55, 0.78, 0.82)
			4: color = Color(0.35, 0.70, 0.90)
			5:
				color = Color(0.85, 0.68, 0.28)
				size = 16
			6:
				color = Color(0.95, 0.45, 0.30)
				size = 18
				crit = true
		# 致命一击（击毁前那一下）用金色描边挑出来
		if quality >= 5:
			crit = true

	while _popups.size() >= MAX_POPUPS:
		_popups.pop_front()

	_popups.append({
		"pos": screen_pos,
		"t": 0.0,
		"life": LIFE,
		"text": text,
		"color": color,
		"size": size,
		"dx": randf_range(-JITTER_X, JITTER_X),
		"crit": crit,
	})
	queue_redraw()


func _process(delta: float) -> void:
	if _popups.is_empty():
		return
	var alive: Array[Dictionary] = []
	for p in _popups:
		p["t"] = float(p["t"]) + delta
		if float(p["t"]) < float(p["life"]):
			alive.append(p)
	_popups = alive
	queue_redraw()


func _draw() -> void:
	if _popups.is_empty():
		return
	var font := ThemeDB.fallback_font
	for p in _popups:
		var k: float = clampf(float(p["t"]) / float(p["life"]), 0.0, 1.0)
		# 上升：先快后慢（起手一冲，然后缓下来）—— 匀速上升看起来像吊线木偶
		var rise := (1.0 - pow(1.0 - k, 2.0)) * 34.0
		# 淡出只占寿命的后半段：前半段必须全不透明，否则小数字看不清
		var alpha := 1.0 if k < 0.5 else (1.0 - (k - 0.5) / 0.5)
		var col: Color = p["color"]
		col.a = alpha
		var at := (p["pos"] as Vector2) + Vector2(float(p["dx"]) * k, -rise)
		# ★ 字号缩放：在这里收口 ⇒ 下面的测量、描边、收缩到 MAX_TEXT_W 全都跟着变
		var fs: int = FONT.s(int(p["size"]))
		var txt: String = p["text"]
		var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		if w > MAX_TEXT_W:
			fs = maxi(9, int(float(fs) * MAX_TEXT_W / w))
			w = font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var origin := at - Vector2(w * 0.5, 0.0)
		# 描边：亮星云背景下没有描边的数字会整条消失（不是变淡，是彻底看不见）
		var outline := Color(0.02, 0.03, 0.04, alpha * 0.92)
		for o in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]:
			font.draw_string(get_canvas_item(), origin + o, txt,
					HORIZONTAL_ALIGNMENT_LEFT, -1, fs, outline)
		font.draw_string(get_canvas_item(), origin, txt,
				HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
		if bool(p["crit"]):
			# 重击：底部补一道短横线，和普通数字拉开「这一下很疼」的区分度
			var y := at.y + 3.0
			draw_line(Vector2(origin.x, y), Vector2(origin.x + w, y),
					Color(col.r, col.g, col.b, alpha * 0.55), 1.0)
