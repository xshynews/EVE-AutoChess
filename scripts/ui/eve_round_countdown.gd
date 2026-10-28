extends Control
## 联机对战 · 准备阶段最后 10 秒的**屏幕中央倒计时**。
##
## ★ 2026-10-28 用户定案：
##   「倒计时还剩 10 秒的时候，屏幕中间出现一个放大的倒计时，从 10 倒数到 0，
##    到 0 秒后对战开始」。
## ★ 云顶之弈的做法（调研结论）：备战 30 秒、到点自动开战、顶条计时器；
##   它**没有**中央大字，靠颜色/读秒制造紧迫感。这里是刻意偏离 ——
##   手机小屏 + 联机「同时开战」需要比顶条更醒目的共同裁判。
##
## ⛔ 本组件**不持有时间**：唯一真相源是顶条 `command_bar.time_left`
##   （`set_stage` 给总时长，`tick` 每帧递减）。自己再存一份就会漂移，
##   而且暂停时会出现「数字还在走」的假暂停。
##
## ⚠️ 只在**联机**（`versus != null`）启用：单机仍保留手动开战键，
##   中央大字会干扰布阵视线。

const FONT := preload("res://scripts/ui/eve_font.gd")
const T := preload("res://scripts/core/eve_text.gd")
## 平台判据走工程唯一真源（⛔ 别在这里写 `OS.has_feature`）
const UI_SCALE := preload("res://scripts/ui/eve_ui_scale.gd")

## 从第几秒开始放大显示
const BIG_FROM := 10.0
## 圆心相对屏幕中心的**上移量**（设计像素）。
##
## ★ 2026-10-28 用户实测反馈：「位置有点偏下了，向上移动个 200 多 300px 都可以」。
##   1080 设计高下圆心 540 → 300：正落在进场横幅（下沿 286）与棋盘上沿之间的空窗带，
##   眼睛不用往下瞟就能读到；再往上会顶到横幅，再往下又回到「挡棋盘」的老问题。
## ⚠️ 上移后依然**不遮操作**：本层 `mouse_filter = IGNORE`，且 10 秒时进场横幅
##   已自然淡出（`eve_entry_banner.gd` 的 LIFE ≈ 6s，开局就播）。
const CENTER_LIFT := 240.0
## 环半径（设计像素；数字 168px 能完整装在环内）
const RING_R := 130.0
const RING_W := 9.0
## 颜色分档：10–6 青 / 5–4 金 / 3–1 红
const BAND_GOLD := 5.0
const BAND_RED := 3.0
## 归零后「开战」闪字停留时长
const FLASH_SEC := 0.45

const C_ACCENT := Color(0.55, 0.78, 0.82)
const C_GOLD := Color(0.91, 0.76, 0.35)
const C_RED := Color(0.86, 0.36, 0.30)
const C_TRACK := Color(0.24, 0.33, 0.38, 0.55)
## 半透明底片：数字压在明亮战场上时仍然读得清（不挡操作，鼠标穿透）
const C_SCRIM := Color(0.03, 0.045, 0.055, 0.62)

## 顶条（`eve_command_bar.gd`）—— 只读它的 `time_left` / `phase`
var _bar: EveWindow = null
var _active := false
var _sec := 0.0
var _digits := 0
var _band := -1
## 环是否要画（闪字期间主数字已隐藏，但闪字仍要显示）
var _show_ring := false
var _flash_t := 0.0
var _tween: Tween = null

var _num: Label
var _cap: Label
var _flash: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_num = _mk_label(168, C_ACCENT, HORIZONTAL_ALIGNMENT_CENTER)
	_cap = _mk_label(20, Color(0.70, 0.82, 0.85), HORIZONTAL_ALIGNMENT_CENTER)
	_flash = _mk_label(96, C_GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	_flash.text = T.t("HUD_COUNTDOWN_GO", "开战")
	_flash.visible = false
	visible = true
	_show_ring = false
	_layout()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout()


## 绑定顶条（HUD 建完顶条后立刻调）。
func bind(bar: EveWindow) -> void:
	_bar = bar


## 联机对战时打开；单机保持关闭。
func set_active(on: bool) -> void:
	_active = on
	if not on:
		_show_ring = false
		_num.visible = false
		_cap.visible = false
		queue_redraw()


## 归零瞬间的金色「开战」闪字（由主控在真正开打时调，避免被相位切换吞掉）。
func flash() -> void:
	_flash.visible = true
	_flash.modulate.a = 0.0
	_flash.pivot_offset = _flash.size * 0.5
	_flash.scale = Vector2(1.22, 1.22)
	var tw := create_tween()
	tw.tween_property(_flash, "modulate:a", 1.0, 0.10)
	tw.parallel().tween_property(_flash, "scale", Vector2.ONE, 0.16)
	_flash_t = FLASH_SEC


# ────────────────────────────────────────────── 纯函数（自检直接断言）

## 显示的数字：0 = 不显示；否则 10..1。
static func digits_for(sec: float) -> int:
	if sec <= 0.0:
		return 0
	return mini(10, int(ceil(sec)))


## 颜色档：0 青 / 1 金 / 2 红。
static func band_for(sec: float) -> int:
	if sec > BAND_GOLD:
		return 0
	if sec > BAND_RED:
		return 1
	return 2


# ────────────────────────────────────────────── 每帧（只读顶条）

func _process(delta: float) -> void:
	# ⚠️ 锚点铺满在「父级还没定尺寸」时会是 0×0（实测：HUD 1920×1080、本层 0×0，
	#    数字画到屏幕左上角外面 ⇒ 看起来像没生效）。每帧跟一次父级尺寸，自愈。
	var host := get_parent() as Control
	if host != null and size != host.size:
		size = host.size
		_layout()
	if _flash_t > 0.0:
		_flash_t = maxf(0.0, _flash_t - delta)
		if _flash_t <= 0.0:
			_flash.visible = false
	if not _active or _bar == null:
		return
	var sec := float(_bar.time_left)
	var phase := int(_bar.phase)
	var show := phase == 0 and sec > 0.0 and sec <= BIG_FROM
	if not show:
		if _show_ring:
			_show_ring = false
			_num.visible = false
			_cap.visible = false
			queue_redraw()
		return
	var d := digits_for(sec)
	if d != _digits:
		_digits = d
		_num.text = str(d)
		if band_for(sec) == 2:
			_cap.text = T.t("HUD_COUNTDOWN_LAST", "最后读秒")
		else:
			_cap.text = T.t("HUD_COUNTDOWN_PREP", "准备时间")
		_pop()
	var b := band_for(sec)
	if b != _band:
		_band = b
		var c := _band_color()
		_num.add_theme_color_override("font_color", c)
		_cap.add_theme_color_override("font_color", c if b == 2 else Color(0.70, 0.82, 0.85))
	_sec = sec
	if not _show_ring:
		_show_ring = true
		_num.visible = true
		_cap.visible = not UI_SCALE.is_mobile()
	queue_redraw()


func _draw() -> void:
	if not _show_ring:
		return
	var c := _center()
	draw_circle(c, RING_R - RING_W * 1.5, C_SCRIM)
	draw_arc(c, RING_R, -PI * 0.5, PI * 1.5, 64, C_TRACK, RING_W, true)
	var frac := clampf(_sec / BIG_FROM, 0.0, 1.0)
	if frac > 0.0:
		draw_arc(c, RING_R, -PI * 0.5, -PI * 0.5 + TAU * frac, 96,
				_band_color(), RING_W + 1.0, true)


# ────────────────────────────────────────────── 内部

func _band_color() -> Color:
	match _band:
		1:
			return C_GOLD
		2:
			return C_RED
		_:
			return C_ACCENT


func _mk_label(font_size: int, color: Color, align: int) -> Label:
	var l := Label.new()
	FONT.fs(l, font_size)
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.visible = false
	add_child(l)
	return l


## 视觉圆心：屏幕中心上移 `CENTER_LIFT`。
##
## ⚠️ `_draw()` 与 `_layout()` 必须**共用这一个入口**：两边各写一份 `size * 0.5`
##    的话，改偏移时只会改到一半 —— 表现为「环挪了、数字没挪」。
## ⚠️ 下限 180：窗口/视口很矮时圆心不能跑到屏幕外（否则整块读秒看不见）。
func _center() -> Vector2:
	var c := size * 0.5
	c.y = maxf(180.0, c.y - CENTER_LIFT)
	return c


func _layout() -> void:
	# ⚠️ RESIZED 可能在 `_ready` 之前来（节点刚挂上父级时），此时子标签还没建
	if _num == null or _cap == null or _flash == null:
		return
	var c := _center()
	_num.size = Vector2(560.0, 260.0)
	_num.position = c - _num.size * 0.5
	_num.pivot_offset = _num.size * 0.5
	_cap.size = Vector2(560.0, 36.0)
	_cap.position = c + Vector2(-280.0, RING_R + 18.0)
	_flash.size = Vector2(560.0, 150.0)
	_flash.position = c - _flash.size * 0.5
	# ⚠️ 手机：说明文字正好压在棋盘顶边上（实测 2026-10-28 截图），
	#   而手机屏小、棋盘占满下半屏 ⇒ 只留数字与环，说明行不画。
	_cap.visible = _show_ring and not UI_SCALE.is_mobile()
	queue_redraw()


func _pop() -> void:
	_num.scale = Vector2(1.16, 1.16)
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_num, "scale", Vector2.ONE, 0.14) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
