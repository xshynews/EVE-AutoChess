extends "res://scripts/ui/eve_window.gd"

## EVE 自走棋 —— 舰队指挥顶条（裸条，无标题栏）
##
## V3 稿尺寸 680 × 40，位于顶部中央。按云顶之弈的阶段条做法：
## 无边框浮条，不是「窗口」—— 但它仍然可以拖走（拖动挂在整个内容区上）。
##
## 内容分五段（从左到右，各段之间 1px 竖分隔线）：
##   ① 阶段    节点 6 + 阶段标签（普通战 / 精英战 / 首领战）
##   ② 信标    ⛨ 100 —— **一局的生命线**，P0 常驻（交接文档 §11 P0）
##   ③ 计时    阶段名 + 环形进度 + 剩余时间
##   ④ 进度    15 枚方块 = 本局节点进度；Boss 节点描边为橙
##   ⑤ 操作    若全漏代价 / ✦ 开战 / ≡ 设置
##
## ⚠️ 2026-09-20（阶段 A）新增：
##   - 信标段 —— 在此之前 HUD 只有「若全漏代价」没有「信标本身」，
##     而信标是「失败」的唯一载体：不补这一条，玩家永远不知道自己离输还有多远。
##   - 计时段加了阶段名 —— 同一个环在准备阶段是布阵倒计时、
##     在战斗阶段是战斗时限，两者含义不同，必须写出来。
##   - `timer_expired` 信号 —— 倒计时到 0 不再自己绕回来，
##     由主控决定「开打」还是「结束」。
##
## ⚠️ 图标一律用几何字符（✦ ≡），不用 ⚔ 🔒 这类 —— 后者在 Windows 会
##    落到 Segoe UI Emoji 渲染成彩色 emoji，与工程规范冲突（已踩过）。
##
## 变更清单（实装版）：
##   - 五段式布局 + 15 节点进度方块 + 信标
##   - 环形倒计时（自绘，无贴图）
##   - start_battle_requested / settings_requested / timer_expired 三个信号

signal start_battle_requested()
signal settings_requested()
## 倒计时归零（准备阶段到点 / 战斗时限到点）
signal timer_expired()

const NODE_TOTAL := 15
## 首领节点（1-based 的第 9 / 12 / 15 个 = 下标 8 / 11 / 14）
## ⚠️ 与 EveNodeTable.BOSS_INDEXES 同一个口径，改一处必须改两处
##    （自检 tools/verify_run.tscn 会断言两者一致）
## ★ 2026-10-11（i18n）：文案取词（见 `eve_text.gd` 顶注）。
const T := preload("res://scripts/core/eve_text.gd")

const BOSS_NODES: Array[int] = [8, 11, 14]

var node_index: int = 1
var stage_label: String = T.t("BAR_STAGE_DEFAULT", "遭遇战")
var time_left: float = 24.0
var time_total: float = 60.0
## 战败会掉多少信标（预览）。⛔ 原字段名 `leak_damage` 随漏网机制一起删了。
var loss_cost: int = 0
var beacon: int = 100
var beacon_max: int = 100
## 0 = 准备 / 1 = 战斗 / 2 = 结算
var phase: int = 0

var _stage_phase: Label
var _stage_tag: Label
var _beacon_value: Label
var _beacon_icon: EveIcon
var _ring: Control
var _phase_label: Label
var _time_label: Label
var _dots: Array[Control] = []
var _loss_label: Label
var _start_btn: Button
var _expired_emitted := false


func _ready() -> void:
	window_title = T.t("BAR_TITLE", "舰队指挥")
	density = Density.BARE
	show_header = false          # 裸条：没有标题栏
	show_status_text = false
	resizable = false            # 顶条不给缩放（它的宽度就是屏宽的一部分）
	draggable = true
	super._ready()
	_build_contents()
	refresh()


func _build_contents() -> void:
	content.add_theme_constant_override("separation", 0)

	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 0)
	bar.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(bar)

	# ── ① 阶段 ──
	var stage := HBoxContainer.new()
	stage.add_theme_constant_override("separation", 6)
	stage.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_child(stage)

	_stage_phase = Label.new()
	_stage_phase.text = T.t("BAR_NODE", "节点 %d") % node_index
	_stage_phase.add_theme_color_override("font_color", Color(0.918, 0.969, 0.980))
	FONT.fs(_stage_phase, 14)
	_stage_phase.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	stage.add_child(_stage_phase)

	_stage_tag = Label.new()
	_stage_tag.text = stage_label
	_stage_tag.add_theme_color_override("font_color", C_TEXT_DIM)
	FONT.fs(_stage_tag, 9)
	_stage_tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_stage_tag.add_theme_stylebox_override("normal", _tag_box())
	stage.add_child(_stage_tag)

	bar.add_child(_vline())

	# ── ② 信标（一局的生命线，P0 常驻）──
	var beacon_box := HBoxContainer.new()
	beacon_box.add_theme_constant_override("separation", 5)
	beacon_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_child(beacon_box)

	_beacon_icon = EveIcon.make(&"beacon", 15, C_HULL, 1.4)
	beacon_box.add_child(_beacon_icon)

	_beacon_value = Label.new()
	_beacon_value.text = "100"
	_beacon_value.add_theme_color_override("font_color", C_HULL)
	FONT.fs(_beacon_value, 15)
	_beacon_value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	beacon_box.add_child(_beacon_value)

	var beacon_unit := Label.new()
	beacon_unit.text = T.t("BAR_BEACON", "信标")
	beacon_unit.add_theme_color_override("font_color", C_TEXT_DIM)
	FONT.fs(beacon_unit, 9)
	beacon_unit.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	beacon_box.add_child(beacon_unit)

	bar.add_child(_vline())

	# ── ③ 计时 ──
	var timer := HBoxContainer.new()
	timer.add_theme_constant_override("separation", 6)
	timer.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_child(timer)

	# ⚠️ 同一个环在准备阶段是「布阵倒计时」、在战斗阶段是「战斗时限」，
	#    含义不同 —— 所以必须把阶段名写出来，不能只留一个转圈的表。
	_phase_label = Label.new()
	_phase_label.text = T.t("BAR_PHASE_PREP", "准备")
	_phase_label.add_theme_color_override("font_color", C_ACCENT)
	FONT.fs(_phase_label, 10)
	_phase_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	timer.add_child(_phase_label)

	_ring = _RingGauge.new()
	_ring.custom_minimum_size = Vector2(24, 24)
	timer.add_child(_ring)

	_time_label = Label.new()
	_time_label.text = "00:24"
	_time_label.add_theme_color_override("font_color", Color(0.918, 0.969, 0.980))
	FONT.fs(_time_label, 14)
	_time_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	timer.add_child(_time_label)

	bar.add_child(_vline())

	# ── ④ 节点进度 ──
	var dots := HBoxContainer.new()
	dots.add_theme_constant_override("separation", 3)
	dots.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_child(dots)

	for i in NODE_TOTAL:
		var d := PanelContainer.new()
		d.custom_minimum_size = Vector2(8, 8)
		d.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		d.mouse_filter = Control.MOUSE_FILTER_IGNORE
		d.add_theme_stylebox_override("panel", _dot_box(false, false))
		dots.add_child(d)
		_dots.append(d)

	bar.add_child(_vline())

	# ── ⑤ 操作 ──
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(spacer)

	_loss_label = Label.new()
	# ⚠️ 这是**预览**（"这一场输了会掉多少"），不是已经发生的事。
	#    ⛔ 原来写「若全漏 −N」——「漏」字是漏网机制的残留，玩家看不懂，
	#       2026-10-01 改成「战败 −N」。
	_loss_label.text = T.t("BAR_LOSS", "战败 −%d") % 0
	_loss_label.add_theme_color_override("font_color", C_WARN)
	FONT.fs(_loss_label, 10)
	_loss_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_loss_label.add_theme_stylebox_override("normal", _leak_box())
	_loss_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(_loss_label)

	var pad1 := Control.new()
	pad1.custom_minimum_size = Vector2(10, 0)
	pad1.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(pad1)

	var start_btn := Button.new()
	start_btn.text = T.t("BAR_START", "✦ 开战")
	start_btn.custom_minimum_size = Vector2(0, 26)
	start_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	EveButtonTheme.apply(start_btn, "hud_main")
	start_btn.pressed.connect(func(): start_battle_requested.emit())
	bar.add_child(start_btn)
	_start_btn = start_btn

	var pad2 := Control.new()
	pad2.custom_minimum_size = Vector2(8, 0)
	pad2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(pad2)

	var set_btn := Button.new()
	set_btn.text = "≡"
	set_btn.tooltip_text = T.t("BAR_SETTINGS_TIP",
			"设置（待接入：天空盒切换 / 显示模式）")
	set_btn.custom_minimum_size = Vector2(26, 26)
	set_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	EveButtonTheme.apply(set_btn, "hud")
	set_btn.pressed.connect(func(): settings_requested.emit())
	bar.add_child(set_btn)


## 竖分隔线（自带左右 12px / 上下 11px 留白，免得线顶满 40px 显硬）
func _vline() -> Control:
	var v := ColorRect.new()
	v.color = Color(0.42, 0.55, 0.60, 0.28)
	v.custom_minimum_size = Vector2(1, 0)
	v.size_flags_vertical = Control.SIZE_FILL
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 用 MarginContainer 包一层给上下留白，免得竖线顶满 40px 显得很硬
	var wrap := MarginContainer.new()
	wrap.add_theme_constant_override("margin_left", 12)
	wrap.add_theme_constant_override("margin_right", 12)
	wrap.add_theme_constant_override("margin_top", 11)
	wrap.add_theme_constant_override("margin_bottom", 11)
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(v)
	return wrap


func _tag_box() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.42, 0.55, 0.60, 0.18)
	sb.border_color = Color(0.42, 0.55, 0.60, 0.40)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(0)
	sb.content_margin_left = 5
	sb.content_margin_right = 5
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	return sb


func _leak_box() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.282, 0.188, 0.102, 0.45)
	sb.border_color = Color(0.878, 0.522, 0.302, 0.50)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(0)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	return sb


func _dot_box(done: bool, boss: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(0)
	sb.set_border_width_all(1)
	if done:
		sb.bg_color = Color(0.52, 0.76, 0.55, 0.55)
		sb.border_color = Color(0.52, 0.76, 0.55, 0.75)
	elif boss:
		sb.bg_color = Color(0.55, 0.78, 0.82, 0.12)
		sb.border_color = Color(0.878, 0.522, 0.302, 0.80)
	else:
		sb.bg_color = Color(0.55, 0.78, 0.82, 0.12)
		sb.border_color = Color(0.55, 0.78, 0.82, 0.42)
	return sb


# ------------------------------------------------------------------ 刷新

const PHASE_NAMES: Array[String] = ["准备", "交战", "结算"]
## 与 `PHASE_NAMES` **一一对应**的 key（⛔ 顺序不许错）。
const PHASE_KEYS: Array[String] = [
	"BAR_PHASE_PREP", "BAR_PHASE_BATTLE", "BAR_PHASE_RESOLVE",
]


## 把当前状态刷进 UI。战斗主控每帧或状态变化时调一次。
func refresh() -> void:
	_stage_phase.text = T.t("BAR_NODE", "节点 %d") % node_index
	_stage_tag.text = stage_label
	_loss_label.text = T.t("BAR_LOSS", "战败 −%d") % loss_cost
	_refresh_beacon()

	var ph := clampi(phase, 0, PHASE_NAMES.size() - 1)
	_phase_label.text = T.t(PHASE_KEYS[ph], PHASE_NAMES[ph])
	_phase_label.add_theme_color_override("font_color",
			[C_ACCENT, C_WARN, C_OK][ph])

	_time_label.text = "%02d:%02d" % [int(time_left) / 60, int(time_left) % 60]
	_ring.set("progress", clampf(
			1.0 - time_left / maxf(0.001, time_total), 0.0, 1.0))
	_ring.queue_redraw()

	for i in _dots.size():
		var done := i < node_index - 1
		var cur := i == node_index - 1
		var boss := BOSS_NODES.has(i)
		var box := _dot_box(done or cur, boss)
		if cur:
			box.bg_color = C_ACCENT
			box.border_color = Color(0.875, 0.949, 0.965)
		_dots[i].add_theme_stylebox_override("panel", box)


## 信标读数与配色。
## 三段色带对齐工程语义色：>60% 正常绿 / >30% 警告橙 / 其余结构红。
func _refresh_beacon() -> void:
	if _beacon_value == null:
		return
	_beacon_value.text = str(beacon)
	var ratio := float(beacon) / maxf(1.0, float(beacon_max))
	var col := C_OK
	if ratio <= 0.30:
		col = C_HULL
	elif ratio <= 0.60:
		col = C_WARN
	_beacon_value.add_theme_color_override("font_color", col)
	if _beacon_icon != null:
		_beacon_icon.set_color(col)


func set_stage(index: int, label: String, total_time: float) -> void:
	node_index = clampi(index, 1, NODE_TOTAL)
	stage_label = label
	time_total = total_time
	time_left = total_time
	_expired_emitted = false
	refresh()


## 切换阶段（0 准备 / 1 战斗 / 2 结算）
func set_phase(p: int) -> void:
	phase = clampi(p, 0, PHASE_NAMES.size() - 1)
	refresh()


## 信标结构值 + 上限（上限只在紧急维修 / 事件回复时才有意义，默认 100）
func set_beacon(value: int, max_value: int = -1) -> void:
	beacon = maxi(0, value)
	if max_value > 0:
		beacon_max = max_value
	refresh()


## 开战按钮的文案随阶段变 —— 同一个按钮在准备阶段是「开战」、
## 结算阶段是「下一节点」、结局是「再来一局」。
## 不写清楚的话，玩家在结算阶段会以为点了没用（其实那是推进节点）。
func set_start_button(text: String, enabled: bool = true) -> void:
	if _start_btn == null:
		return
	_start_btn.text = text
	_start_btn.disabled = not enabled
	_start_btn.modulate = Color(1, 1, 1, 1.0 if enabled else 0.45)


## 推进倒计时。归零后**停在 0 并广播一次** `timer_expired`，
## 由主控决定下一步（准备阶段到点 = 开打；战斗时限到点 = 由模拟器收尾）。
##
## ⚠️ 旧实现到 0 就自己绕回起点（"让环一直转着"）—— 那是回合制没接上时的占位。
##    现在真接上了，再自己绕回去就等于「倒计时可以无限循环」，玩家没有压力。
func tick(delta: float) -> void:
	if time_left <= 0.0:
		return
	time_left = maxf(0.0, time_left - delta)
	refresh()
	if time_left <= 0.0 and not _expired_emitted:
		_expired_emitted = true
		timer_expired.emit()


# ------------------------------------------------------------------ 自绘环形倒计时

class _RingGauge extends Control:
	var progress: float = 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5 - 2.2
		if r <= 1.0:
			return
		draw_arc(c, r, 0.0, TAU, 40, Color(0.42, 0.55, 0.60, 0.32), 2.4, true)
		if progress <= 0.001:
			return
		var start := -PI * 0.5
		draw_arc(c, r, start, start + TAU * progress, 40,
				Color(0.549, 0.780, 0.820), 2.4, true)
