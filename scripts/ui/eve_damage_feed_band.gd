extends Control
## ★ 字号缩放：自绘文字的字号也要过它（`FONT.s(设计字号)`）。
const FONT := preload("res://scripts/ui/eve_font.gd")

## EVE 自走棋 —— **战斗播报条**（屏幕中央靠上，3 行滚动）
##
## ══════════════════════════════════════════════════════════════════
##  它和 `eve_damage_feed.gd`（船身上飘的数字）的分工
## ══════════════════════════════════════════════════════════════════
##   · `eve_damage_feed`：**世界空间**的即时反馈 —— 谁挨了一下、掉多少。
##     它回答的是「刚才那一下打在哪艘船上」，随战场位置变化。
##   · 本文件：**战报** —— 「谁对谁打了多少、破没破盾」。它不指向位置，
##     而是按时间排队，让人在战斗最乱的时候也能读到最近三条结论。
##
##  用户原话（2026-10-30）：「同步攻防信息 —— 谁把谁打掉了多少血、谁破盾了，
##  全部同步到画面中央靠上，显示 7 秒（含 0.5 秒淡入、1 秒淡出），最多 3 行，
##  最新的在最下行，信息滚动出现」。
##
## ── 三条硬约束（改之前先读）───────────────────────────────────────
##  ① **最新在下、旧的上滚**：视线固定在下行，人不用追着看。
##     新条目出现时整列**平滑上移一格**（0.18s），不是瞬间跳 —— 跳会让
##     "刚才那条"和"这条"分不清哪条是新的。
##  ② **7 秒生命周期 = 0.5 淡入 + 5.5 保持 + 1.0 淡出**。
##     保持段必须完全不透明：战斗中最常发生的是"三条都在淡出"，
##     那是读不出来的，等于没有。
##  ③ **每条自己算寿命**：不断有新消息时，最上面那条照样到点消失，
##     下面自动补位 —— 不能做成"整批刷新"，否则密集交火时永远读不到结论。
##
## ⚠️ 铺满全屏 + `MOUSE_FILTER_IGNORE`：它绝不能吃掉鼠标事件。
## ⚠️ 上限硬性 3 条（用户指定，手机端同款）—— 战斗最密集时每秒几十条，
##    不设上限会把屏幕上方糊成一片。

## 单条寿命（秒）
const LIFE := 7.0
const FADE_IN := 0.5
const FADE_OUT := 1.0
## 同屏最多几条（用户定案：手机端缩到 3）
const MAX_ROWS := 3
## 行高（设计像素，会过 FONT 缩放）
const ROW_H := 34.0
## 上滚补位动画时长（秒）
const SLIDE := 0.18
## 整块停靠在屏幕高度的百分之几处（中央靠上）
const TOP_FRAC := 0.19

## 我方造成 / 我方承受（用户指定：亮蓝 / 红）
const C_MINE := Color(0.31, 0.76, 0.97)
const C_TAKEN := Color(1.0, 0.42, 0.35)
const C_TEXT := Color(0.84, 0.90, 0.94)
const C_DIM := Color(0.55, 0.66, 0.72)
const C_HOT := Color(0.88, 0.66, 0.29)     ## 破层 / 穿透
const C_KILL := Color(1.0, 0.56, 0.42)     ## 击毁

## 正在播的条目（**最新在前**，下标 0 = 最下行）
## 元素 = {amount:int, mine:bool, kind:StringName, name:String,
##         t:float, row:float(动画中), row_target:float}
##
## ⚠️⚠️ `row` 是**屏幕 y 方向的偏移行数**：`row = 0` 是最下行，往上为**负**。
##   即 `row_target == -float(index)` —— 下标越大（越旧）越靠上。
##   ⛔ 2026-10-30 首版写反了（旧条目 +1 ⇒ 越旧越往下），玩家一眼看出
##   "游戏里是从上往下"，和演示动画相反。改的时候别再把符号弄丢。
var _items: Array[Dictionary] = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)


## 当前条目数（验收/探针用）
func active_count() -> int:
	return _items.size()


func clear() -> void:
	_items.clear()
	set_process(false)
	queue_redraw()


## 播报一条。
##
## `p_kind` 取值：`&"hit"` 命中 / `&"pierce"` 穿透 / `&"shield"` 破盾 /
##              `&"armor"` 破甲 / `&"kill"` 击毁。
## `p_mine` = true 表示**我方造成**（亮蓝），false = 我方承受（红）。
func push(p_amount: int, p_mine: bool, p_kind: StringName, p_name: String) -> void:
	if p_name.strip_edges() == "":
		return
	# 旧条目整体**上移**一格（row 往负方向走），给新条目让出最下行
	for it in _items:
		it["row_target"] = float(it["row_target"]) - 1.0
	_items.insert(0, {
		"amount": maxi(0, p_amount),
		"mine": p_mine,
		"kind": StringName(p_kind),
		"name": p_name,
		"t": 0.0,
		# 新条目从**最下行正下方一整行**滑进来：起点 +1 行，目标 0 行。
		# ⚠️ 必须正好 1 行（不是 0.55 之类）—— 旧条目同时在往 -1 走，
		#    两边同一时长、同一距离，行间距才恒定 1 行，滚动时不会挤在一起。
		"row": 1.0,
		"row_target": 0.0,
	})
	while _items.size() > MAX_ROWS:
		_items.pop_back()
	set_process(true)
	queue_redraw()


func _process(delta: float) -> void:
	if _items.is_empty():
		set_process(false)
		return
	var alive: Array[Dictionary] = []
	for it in _items:
		it["t"] = float(it["t"]) + delta
		if float(it["t"]) >= LIFE:
			continue
		# 行位补间（向上滚一格）
		# ⚠️ 用**定速**推进，不能用 `lerpf(cur, tgt, delta/SLIDE)` ——
		#    那是指数收敛（每帧只吃掉当前差距的 9%），实测要 1.2s 才停，
		#    SLIDE=0.18 形同虚设，滚动看着发黏。定速才让 0.18 是真的。
		var cur := float(it["row"])
		var tgt := float(it["row_target"])
		var gap := tgt - cur
		var step := delta / SLIDE
		if absf(gap) <= step:
			it["row"] = tgt
		else:
			it["row"] = cur + signf(gap) * step
		alive.append(it)
	_items = alive
	if _items.is_empty():
		set_process(false)
	queue_redraw()


func _draw() -> void:
	if _items.is_empty():
		return
	var font := ThemeDB.fallback_font
	var vp := size
	if vp.y <= 1.0:
		return
	var row_h := FONT.s(int(ROW_H))
	# `base_y` = **最下行**的基线。因为 row 往上为负，块是从 base_y 往上长的。
	# 再往下挪半块（(MAX_ROWS-1)/2 行），让「满 3 行」时整块中心正好落在 TOP_FRAC。
	var base_y := vp.y * TOP_FRAC + row_h * float(MAX_ROWS - 1) * 0.5
	var h := vp.x * 0.5
	for it in _items:
		var t := float(it["t"])
		var alpha := 1.0
		if t < FADE_IN:
			alpha = t / FADE_IN
		elif t > LIFE - FADE_OUT:
			alpha = clampf((LIFE - t) / FADE_OUT, 0.0, 1.0)
		if alpha <= 0.01:
			continue
		var y := base_y + float(it["row"]) * row_h
		_draw_line(font, h, y, it, alpha)


## 画一行：`[数字] [标记] → 对/来自 [船名] · [后缀]`，整行水平居中。
##
## ⚠️ 不能拼成一个字符串再画：数字与船名要不同字号、不同颜色，
##    拼起来就只剩一种颜色 —— 那正是「一眼看不出谁打谁」的老问题。
func _draw_line(font: Font, cx: float, y: float, it: Dictionary, alpha: float) -> void:
	var mine := bool(it["mine"])
	var kind := StringName(it["kind"])
	var col := C_MINE if mine else C_TAKEN
	var fs_num := FONT.s(17)
	var fs_txt := FONT.s(13)
	var amount := int(it["amount"])

	# 后缀（破层/击毁用琥珀，普通命中用灰）
	var suffix := "· 命中"
	var suffix_col := C_DIM
	match kind:
		&"pierce":
			suffix = "· 穿透"
			suffix_col = C_HOT
		&"shield":
			suffix = "· 破盾"
			suffix_col = C_HOT
		&"armor":
			suffix = "· 破甲"
			suffix_col = C_HOT
		&"kill":
			suffix = "· 击毁"
			suffix_col = C_KILL

	var num_txt := "%d" % amount
	var mark := "»" if kind == &"hit" or kind == &"pierce" else "×"
	var pre := "对 " if mine else "来自 "
	var name_txt := String(it["name"])

	# 分段测量（含固定间隙），再整体居中
	var gap := float(FONT.s(7))
	var segs: Array = [
		{"t": num_txt, "fs": fs_num, "c": col},
		{"t": mark, "fs": fs_txt, "c": col},
		{"t": "→", "fs": fs_txt, "c": C_DIM.darkened(0.15)},
		{"t": pre, "fs": fs_txt, "c": C_DIM},
		{"t": name_txt, "fs": fs_txt, "c": C_TEXT},
		{"t": suffix, "fs": fs_txt, "c": suffix_col},
	]
	var total := 0.0
	for s in segs:
		total += font.get_string_size(String(s["t"]), HORIZONTAL_ALIGNMENT_LEFT, -1,
				int(s["fs"])).x + gap
	total -= gap
	var x := cx - total * 0.5
	for s in segs:
		var fs := int(s["fs"])
		var txt := String(s["t"])
		var base := Color(s["c"] as Color)
		base.a = alpha
		var outline := Color(0.02, 0.03, 0.04, alpha * 0.9)
		# 描边：亮星云背景下没有描边的字会整条消失（不是变淡，是看不见）
		for o in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]:
			font.draw_string(get_canvas_item(), Vector2(x, y) + o, txt,
					HORIZONTAL_ALIGNMENT_LEFT, -1, fs, outline)
		font.draw_string(get_canvas_item(), Vector2(x, y), txt,
				HORIZONTAL_ALIGNMENT_LEFT, -1, fs, base)
		x += font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + gap
