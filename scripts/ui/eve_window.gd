extends PanelContainer
class_name EveWindow

## ★ 字号缩放（2026-10-07）：⛔ 别直接调 `add_theme_font_size_override`，
## 一律走 `FONT.fs(node, 设计字号)` —— 它同时记住设计字号（供改滑块时就地重算）。
## ⚠️ 子类（`extends eve_window.gd` 的那 9 个）靠**继承**拿到这个常量，
##    它们自己再写一个会撞名（基类已有同名成员 ⇒ 子类编译失败，本工程踩过）。
const FONT := preload("res://scripts/ui/eve_font.gd")

## EVE 自走棋 —— 漂浮窗口基类
##
## 所有功能分区都是这个：半透明深灰面板 + 1px 细边框 + 直角 + 小号标题栏。
## 不发光、不描金、不圆角 —— 对应 EVE 游戏内 HUD 的克制风格。
##
## 视觉语言（修改前先看这里，别自己另起一套）：
##   面板底     rgba(14,18,21,.84)      裸条 / 实底  rgba(12,16,18,.94)
##   边框       1px rgba(107,140,153,.42)
##   标题栏     高 26px，底 rgba(26,36,43,.88)，底边 1px 分隔线
##   标题文字   12px #B3D1D9
##   标题左角标 2×12px 竖线 rgba(115,158,173,.55)
##
## ── 三条交互行为（V3 布局稿定稿，实装于 2026-09-20）──────────────
##   ① 拖标题栏 = 移动窗口（拖离锚点后转为绝对定位）
##   ② 拖右下角三角 = 缩放窗口（EVE 同款位置）
##   ③ 点任意位置 = 把窗口提到最前（多窗重叠时不必先找标题栏）
##   拖拽与缩放结束后都会 clamp 回视口内 —— 保证标题栏永远够得着。
##
## 变更清单（2026-09-20 实装版）：
##   - 新增 show_header（false = 无标题栏的「裸条」，顶条用）
##   - 新增 set_window_rect()（按 V3 稿的绝对像素位摆放）
##   - 新增右下角缩放把手 + 尺寸下限
##   - 新增点击置顶 + 视口 clamp
##   - 便捷构建器补 key_width 参数（V3 稿的键宽是 26/42/58 三档）

const C_PANEL := Color(0.055, 0.070, 0.082, 0.84)
const C_PANEL_SOLID := Color(0.048, 0.062, 0.072, 0.94)
const C_BORDER := Color(0.42, 0.55, 0.60, 0.42)
const C_TITLE_BG := Color(0.10, 0.14, 0.17, 0.88)
const C_TEXT := Color(0.70, 0.82, 0.85)
const C_TEXT_DIM := Color(0.44, 0.55, 0.59)

# --- 全站配色（所有窗口子类共用；定义在这里是为了让子类不必跨继承链取常量）---
const C_ACCENT := Color(0.55, 0.78, 0.82)                # 强调（青）
const C_SHIELD := Color(0.35, 0.70, 0.90)                # 护盾（蓝）
const C_ARMOR := Color(0.85, 0.68, 0.28)                 # 装甲（金）
const C_HULL := Color(0.82, 0.32, 0.28)                  # 结构（红）
const C_WARN := Color(0.88, 0.52, 0.30)                  # 警告（橙）
const C_OK := Color(0.52, 0.76, 0.55)                    # 正常（绿）
const C_CAP := Color(0.50, 0.62, 0.86)                   # 电容（蓝紫）

# --- 次级文字（V3 稿新增的两档灰，用于标题栏右侧小字 / 注释行）---
const C_TEXT_FAINT := Color(0.35, 0.43, 0.47)            # #5A6E78
const C_GOLD := Color(0.91, 0.76, 0.35)                  # 星币 / 星级

# --- 羁绊分组色（V3 稿「舰队构成」窗）---
const C_FACTION_AMARR := Color(0.96, 0.78, 0.26)
const C_FACTION_CALDARI := Color(0.23, 0.76, 0.88)
const C_FACTION_GALLENTE := Color(0.27, 0.77, 0.49)
const C_FACTION_MINMATAR := Color(0.94, 0.27, 0.27)
const C_WEAPON := Color(0.50, 0.83, 0.94)
const C_DEFENSE := Color(1.00, 0.64, 0.24)

enum Density { NORMAL, COMPACT, BARE }

## 标题栏高度（所有窗口共用，缩放把手的 clamp 也要用它）
const HEADER_H := 26.0
## 缩放把手边长
const GRIP := 14.0          ## 右下缩放把手边长（11 → 14：11 太小，安卓手指点不到）

# ⚠️ 名字**不能叫 `STORE`** —— `eve_settings.gd`（本类的子类）里已经有 `const STORE`，
#    基类同名成员会让它直接编译失败（实测：The member "STORE" already exists in parent
#    class EveWindow）⇒ 连带 HUD / 战斗场景 / verify_run / verify_camera 全挂。
#    ⇒ **给基类加成员之前，先 grep 一遍所有子类有没有同名的。**
const LAYOUT_STORE := preload("res://scripts/ui/eve_window_store.gd")
## ★ 2026-10-10 i18n：HUD 文案取词入口（见 eve_text.gd 顶注）。
## ⚠️⛔ **这里必须叫 `TEXT` 而不是 `T`** —— 子类 `eve_settings.gd` 自己也声明了
##    `const T`，成员同名会让**基类**直接编译失败：
##    `Parse Error: The member "T" already exists in parent class EveWindow`
##    （实测踩过，连带 HUD / 战斗场景 / 三套 verify 全挂）。
##    这正是本工程那条红线：「给基类加成员前先 grep 一遍所有子类」。
const TEXT := preload("res://scripts/core/eve_text.gd")
## 拖拽/缩放后至少留在视口内的像素（保证还够得着）
const MIN_VISIBLE := 60.0

@export var window_title: String = "窗口":
	set(v):
		window_title = v
		if _title_label:
			_title_label.text = v

@export var density: int = Density.NORMAL
@export var draggable: bool = true
@export var resizable: bool = true

## false = 不建标题栏（顶条这种「裸条」用）。
## ⚠️ 裸条仍然可以拖动 —— 此时【整条都是拖动手柄】（事件挂在窗口自己身上）。
##    这一点必须由 _build() 里的分支保证，别以为注释写了就自动成立：
##    曾经拖动只挂在 _header_panel 上，而裸条不建标题栏 ⇒ 顶条根本拖不动。
@export var show_header: bool = true

## 标题栏右侧的小字（如「Lv.3 · 14/68」）。设了才建那个 Label。
@export var show_status_text: bool = true

## ★ 2026-10-07 「像 EVE 一样能收起来」：收起后只剩标题栏（roll-up）。
##   ⚠️ 自带收起逻辑的窗（如舰船档案）要设 false，否则两套收起会打架。
@export var collapsible: bool = true

## 标题栏 ✕ 被按下。是否真的关闭由**持有者**决定（见 `closable`）。
signal close_requested

## ★ 2026-10-10：标题栏右上角建一枚 ✕（在折叠按钮**右边**）。
##
## ⚠️ 默认 false —— 只有「需要玩家显式关掉」的窗（设置窗）才开。其余窗是常驻面板，
##    给它们一个 ✕ 只会得到「看着能点、点了没反应」的假按钮（红线 9）。
##
## ⚠️ 本窗**不负责隐藏自己** —— 按下只发 `close_requested`，由持有它的场景决定
##    去处（设置窗 → `EveHudRoot.hide_settings()`；三场景可共用同一枚按钮）。
@export var closable: bool = false
## 记住玩家拖到的位置 / 拉成的尺寸 / 收起态（写 `user://window_layout.cfg`）。
@export var persist_layout: bool = true
## 布局存档键。留空 ⇒ 用 `window_title`（各窗标题互不相同，见下面注释）。
@export var layout_key: String = ""
## ★ 2026-10-07：高度由控件自己接管、且**可能高过设计稿**的窗（设置窗）设 true。
##
## 为什么需要它：HUD 每次刷新都用 `set_window_rect()` 把窗摆回**设计稿坐标**，
## 而那个 y 是配着设计稿高度算的（设置窗 RECT 高 480、y 250 ⇒ 居中）。
## 实际高度由内容反推（加完「显示 · 分辨率」实测 **866**）⇒ 250 + 866 = 1116
## 顶出 1080 屏外。⇒ 打开这个开关之后，摆位时会把 y **上移**，保证整扇窗在屏内。
##
## ⚠️ 默认 false：`_clamp_into_viewport()` 的语义是"标题栏别丢"（给玩家拖动用的），
##    允许窗身出屏；本开关要的是"整扇可见"，两者不是一回事，⛔ 别混用。
@export var fit_in_viewport: bool = false
## 「整扇窗」离屏幕边缘至少留多少像素
const FIT_MARGIN := 8.0

var content: VBoxContainer          ## 子类往这里塞内容
var header: HBoxContainer
var _title_label: Label
var _status_label: Label
var _header_panel: PanelContainer
var _content_margin: MarginContainer
## 铺满整窗的透明层，只为给缩放把手当父节点（见 _build_grip）
## ⚠️ 名字不能叫 _overlay —— EveShop 自己已经有一个 _overlay（出售遮罩），
##    同名会报 `The member "_overlay" already exists in parent class EveWindow`。
var _grip_layer: Control
var _grip: Control
var _dragging: bool = false
var _drag_offset: Vector2 = Vector2.ZERO
var _resizing: bool = false
var _resize_start: Vector2 = Vector2.ZERO
## 收起态（只剩标题栏）
var _collapsed := false
## 设计稿给的矩形（`set_window_rect` 记下来）。⚠️ HUD 会**反复**调它，
## 所以这里只记录、不当场生效 —— 生效由 `_effective_rect()` 决定。
var _base_rect := Rect2()
## 玩家拖/缩后的矩形（有它就用它，压过设计稿）
var _user_rect := Rect2()
## 高度是否由**控件自己**管（档案窗收起/展开 128↔320、结算窗按内容反推窗高）。
## ⚠️ 一旦为 true，`set_window_rect()` **只更新位置与宽度、不动高度** ——
##    否则 HUD 每次刷新都会把控件自己算好的高度按设计稿改回去。
##    （实测：档案窗 set_window_height(320) 后被刷新改回 128；
##      结算窗的确定性窗高同理 —— 同一处根因。）
var _height_owned := false
var _collapse_btn: Control = null
var _collapse_hot := false
var _close_btn: Control = null
var _close_hot := false
var _grip_hot := false
var _resize_from: Vector2 = Vector2.ZERO


func _ready() -> void:
	_build()
	_load_layout()        # ★ 玩家上次把窗口摆哪儿了（EVE 的窗口布局是记着的）


func _build() -> void:
	set_anchors_preset(Control.PRESET_TOP_LEFT)

	# 面板外观
	var sb := StyleBoxFlat.new()
	sb.bg_color = C_PANEL_SOLID if density == Density.BARE else C_PANEL
	sb.border_color = C_BORDER
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(0)
	sb.content_margin_left = 0
	sb.content_margin_right = 0
	sb.content_margin_top = 0
	sb.content_margin_bottom = 0
	add_theme_stylebox_override("panel", sb)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 0)
	add_child(root)

	if show_header:
		_build_header(root)

	# 内容区
	_content_margin = MarginContainer.new()
	var pad_h := 8 if density == Density.COMPACT else 10
	var pad_v := 6 if density == Density.COMPACT else 8
	if not show_header:
		pad_h = 10
		pad_v = 0
	_content_margin.add_theme_constant_override("margin_left", pad_h)
	_content_margin.add_theme_constant_override("margin_right", pad_h)
	_content_margin.add_theme_constant_override("margin_top", pad_v)
	_content_margin.add_theme_constant_override("margin_bottom", pad_v if not show_header else 8)
	# ⚠️ 这一行**必需**，少了它内容区永远只有最小高度：
	#    BoxContainer 只把富余空间分给带 EXPAND 的孩子；`_content_margin` 若没有
	#    EXPAND，`root` 里就只有标题栏拿到高度、富余空间整条堆在末尾
	#    ⇒ **窗口底部出现一条填不满的死白**，而且下面 `content` 那句
	#    `size_flags_vertical = EXPAND_FILL`（以及各功能窗内层的所有同类设定）
	#    会**全部空转**（不报错、不警告，只看代码完全看不出来）。
	#    实测（tools/probe_hud_layout.tscn）：修前 8 个窗全有死白，
	#    战斗日志 47px、顶条 14px、舰队构成 12px、档案 10px。
	_content_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_content_margin)

	content = VBoxContainer.new()
	content.add_theme_constant_override("separation", 6)
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content_margin.add_child(content)

	if resizable:
		_build_grip()

	# 拖动手柄：有标题栏就挂标题栏，没标题栏（裸条）就把【整条】当手柄。
	# ⚠️ 这个 else 分支不能省 —— 顶条 show_header=false，少了它就完全拖不动。
	if draggable:
		if _header_panel != null:
			_header_panel.gui_input.connect(_on_header_input)
		else:
			gui_input.connect(_on_header_input)

	# 点任意处置顶 —— 多窗重叠时不用先去点标题栏
	mouse_filter = Control.MOUSE_FILTER_STOP
	gui_input.connect(_on_window_input)


func _build_header(root: VBoxContainer) -> void:
	header = HBoxContainer.new()
	header.custom_minimum_size = Vector2(0, HEADER_H)
	var header_sb := StyleBoxFlat.new()
	header_sb.bg_color = C_TITLE_BG
	header_sb.border_color = C_BORDER
	header_sb.border_width_bottom = 1
	header_sb.content_margin_left = 7
	header_sb.content_margin_right = 7

	_header_panel = PanelContainer.new()
	_header_panel.add_theme_stylebox_override("panel", header_sb)
	_header_panel.add_child(header)
	_header_panel.mouse_filter = Control.MOUSE_FILTER_STOP

	# 标题栏左侧有一道细竖线 —— EVE 式的角标感
	var tick := ColorRect.new()
	tick.color = Color(0.45, 0.62, 0.68, 0.55)
	tick.custom_minimum_size = Vector2(2, 12)
	tick.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tick.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(tick)

	_title_label = Label.new()
	_title_label.text = window_title
	_title_label.add_theme_color_override("font_color", C_TEXT)
	FONT.fs(_title_label, 12)
	_title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(_title_label)

	if show_status_text:
		_status_label = Label.new()
		_status_label.add_theme_color_override("font_color", C_TEXT_DIM)
		FONT.fs(_status_label, 11)
		_status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		header.add_child(_status_label)

	# ★ 收起按钮放在标题栏**最右端**（EVE 也在标题栏右侧放窗口控制）
	if collapsible:
		_build_collapse_btn(header)
	# ★✕ 关闭按钮再往右一格 —— 与收起按钮同排、居最右（用户 2026-10-10 要求）。
	#   顺序不能反：HBoxContainer 按 add_child 先后从左到右排，
	#   所以「先收起、后关闭」才是「关闭在收起右边」。
	if closable:
		_build_close_btn(header)

	root.add_child(_header_panel)

	# 注意：拖动事件【不在这里】接 —— 裸条不建标题栏，
	# 若把拖动写在这个函数里，裸条就永远拖不动。统一由 _build() 分派。


## 右下角缩放把手 —— 一枚直角三角（EVE 同款位置与手感）
##
## ⚠️⚠️ 把手【不能直接 add_child 到 self】—— 这个坑踩过，症状极具迷惑性：
##
##     EveWindow 继承 PanelContainer，而 PanelContainer 是 Container，
##     它会在 NOTIFICATION_SORT_CHILDREN 里把【每一个】子节点都 fit 成自己的整块矩形。
##     所以锚点/offset 全部被无声覆盖，把手实测被拉成 1142×168（≠ 11×11）。
##     两个后果：
##       ① 鼠标悬停在窗口【任何位置】都变成「拉大拉小」光标
##          （用户 2026-09-20 报告的就是这个）；
##       ② 把手 mouse_filter = STOP，它把窗口内容的鼠标事件全吃掉了
##          —— 点商店按钮、拖标题栏全部失灵，而且因为它满窗，
##            拖任意位置都会走进 _on_grip_input 的缩放分支。
##     正解：垫一层普通 Control 当「覆盖层」。容器只会拉满这一层（这正是想要的），
##     而 Control 不是 Container，不会再管它自己的子节点，把手的锚点就生效了。
##     注：覆盖层设 IGNORE 不影响把手收事件 —— Godot 的命中测试是先递归子节点，
##         再把父节点自身算进去，IGNORE 只让【该节点自己】不参与。
func _build_grip() -> void:
	if _grip_layer == null:
		_grip_layer = Control.new()
		_grip_layer.name = "GripLayer"
		_grip_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_grip_layer)

	_grip = Control.new()
	_grip.name = "ResizeGrip"
	_grip.mouse_default_cursor_shape = Control.CURSOR_FDIAGSIZE
	_grip.mouse_filter = Control.MOUSE_FILTER_STOP
	_grip.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_grip.offset_left = -GRIP
	_grip.offset_top = -GRIP
	_grip.offset_right = 0
	_grip.offset_bottom = 0
	_grip.draw.connect(_draw_grip)
	_grip.gui_input.connect(_on_grip_input)
	_grip.mouse_entered.connect(func() -> void:
		_grip_hot = true
		if _grip != null:
			_grip.queue_redraw())
	_grip.mouse_exited.connect(func() -> void:
		_grip_hot = false
		if _grip != null:
			_grip.queue_redraw())
	_grip_layer.add_child(_grip)


## 三角形用 _draw 画 —— 比叠三个 ColorRect 省节点，且缩放时不会错位
func _draw_grip() -> void:
	if _grip == null:
		return
	var s := Vector2(GRIP, GRIP)
	# ★ 2026-10-07：原来 alpha 0.44 / 11px —— 在深色底上几乎看不见，
	#   而「找不到把手」等于「缩不了」。现在加大 + hover 提亮 + 内侧加一道亮线。
	var a := 0.72 if _grip_hot else 0.46
	var col := Color(0.58, 0.82, 0.86, a)
	_grip.draw_colored_polygon(PackedVector2Array([
		Vector2(0, s.y), Vector2(s.x, s.y), Vector2(s.x, 0)
	]), col)
	_grip.draw_line(Vector2(s.x * 0.30, s.y), Vector2(s.x, s.y * 0.30),
			Color(0.90, 0.97, 0.98, minf(1.0, a + 0.22)), 1.0)


## 收起按钮：用 EVE 的 chevron 语言 —— 展开时朝下（点了收起），收起时朝右（点了展开）。
##
## ⚠️ 自绘而不是用 Button：这个工程的按钮皮肤是 `EveButtonTheme`（带边框/文字），
##    塞一个 18×18 的文字按钮会得到一个难看的方框。图标按钮一律自绘。
func _draw_collapse_btn() -> void:
	if _collapse_btn == null:
		return
	var c := _collapse_btn.size * 0.5
	var col := Color(0.82, 0.93, 0.96, 0.95) if _collapse_hot \
			else Color(0.58, 0.72, 0.76, 0.80)
	var r := 4.0
	if _collapsed:
		for k in 2:                       # 朝右：>>
			var x := c.x - 4.0 + float(k) * 5.0
			_collapse_btn.draw_polyline(PackedVector2Array([
				Vector2(x, c.y - r), Vector2(x + r * 0.9, c.y), Vector2(x, c.y + r)
			]), col, 1.6)
	else:
		for k in 2:                       # 朝下：vv
			var y := c.y - 4.0 + float(k) * 5.0
			_collapse_btn.draw_polyline(PackedVector2Array([
				Vector2(c.x - r, y), Vector2(c.x, y + r * 0.9), Vector2(c.x + r, y)
			]), col, 1.6)


func _build_collapse_btn(header_row: HBoxContainer) -> void:
	_collapse_btn = Control.new()
	_collapse_btn.name = "CollapseBtn"
	_collapse_btn.custom_minimum_size = Vector2(22, 18)
	_collapse_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_collapse_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_collapse_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	_collapse_btn.tooltip_text = TEXT.t(&"WINDOW_COLLAPSE_TIP", "收起 / 展开（也可以双击标题栏）")
	_collapse_btn.draw.connect(_draw_collapse_btn)
	_collapse_btn.gui_input.connect(_on_collapse_input)
	_collapse_btn.mouse_entered.connect(func() -> void:
		_collapse_hot = true
		if _collapse_btn != null:
			_collapse_btn.queue_redraw())
	_collapse_btn.mouse_exited.connect(func() -> void:
		_collapse_hot = false
		if _collapse_btn != null:
			_collapse_btn.queue_redraw())
	header_row.add_child(_collapse_btn)


func _on_collapse_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		toggle_collapse()
		accept_event()          # ⛔ 必须消费掉：否则标题栏会同时开始拖窗


## 关闭按钮：与收起按钮同款自绘（⛔ 别用文字 Button —— 那个皮肤带边框，
## 塞进标题栏会得到一个难看的方框，见 `_draw_collapse_btn` 的说明）。
## 图形就是一个 ✕（红线 3：HUD 图标只许几何字符 / 自绘线条）。
func _draw_close_btn() -> void:
	if _close_btn == null:
		return
	var c := _close_btn.size * 0.5
	# 常态偏冷灰（融进标题栏），悬停转暖红 —— 关闭是**破坏性**动作，颜色给出预兆。
	var col := Color(1.00, 0.70, 0.66, 0.98) if _close_hot \
			else Color(0.62, 0.71, 0.75, 0.82)
	var r := 3.6
	_close_btn.draw_line(c + Vector2(-r, -r), c + Vector2(r, r), col, 1.6)
	_close_btn.draw_line(c + Vector2(r, -r), c + Vector2(-r, r), col, 1.6)


func _build_close_btn(header_row: HBoxContainer) -> void:
	_close_btn = Control.new()
	_close_btn.name = "CloseBtn"
	_close_btn.custom_minimum_size = Vector2(20, 18)
	_close_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_close_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_close_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	_close_btn.tooltip_text = TEXT.t(&"WINDOW_CLOSE", "关闭")
	_close_btn.draw.connect(_draw_close_btn)
	_close_btn.gui_input.connect(_on_close_input)
	_close_btn.mouse_entered.connect(func() -> void:
		_close_hot = true
		if _close_btn != null:
			_close_btn.queue_redraw())
	_close_btn.mouse_exited.connect(func() -> void:
		_close_hot = false
		if _close_btn != null:
			_close_btn.queue_redraw())
	header_row.add_child(_close_btn)


func _on_close_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		close_requested.emit()
		accept_event()          # ⛔ 同上：别让标题栏同时开始拖窗


# ------------------------------------------------------------------ 交互

func _on_window_input(event: InputEvent) -> void:
	# 点一下就把自己提到最前。用 pressed 而不是 released ——
	# 与「点标题栏开始拖」同一个时机，手感才一致。
	if event is InputEventMouseButton and event.pressed:
		move_to_front()


func _on_header_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		# ★ EVE 习惯：双击标题栏 = 收起 / 展开
		if event.double_click and collapsible:
			_dragging = false
			toggle_collapse()
			return
		_dragging = event.pressed
		if _dragging:
			move_to_front()
			_drag_offset = get_global_mouse_position() - global_position
		else:
			# 松手 = 拖动结束 ⇒ 记下玩家摆的位置并写盘（⛔ 不在拖动过程中写）
			_note_user_rect()
			_save_layout()
	elif event is InputEventMouseMotion and _dragging:
		# 拖动时脱离锚点，改为绝对定位
		set_anchors_preset(Control.PRESET_TOP_LEFT)
		global_position = get_global_mouse_position() - _drag_offset
		_clamp_into_viewport()


func _on_grip_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_resizing = event.pressed
		if _resizing:
			move_to_front()
			_resize_start = get_global_mouse_position()
			_resize_from = size
	elif event is InputEventMouseMotion and _resizing:
		var want := _resize_from + (get_global_mouse_position() - _resize_start)
		var min_h := HEADER_H if _collapsed else custom_minimum_size.y
		size = Vector2(maxf(custom_minimum_size.x, want.x), maxf(min_h, want.y))
		_clamp_into_viewport()
	if event is InputEventMouseButton and not event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT and _resizing:
		_resizing = false
		_note_user_rect()
		_save_layout()


## 把窗口拉回视口内。
##
## ⚠️ 不能只在拖动时 clamp：缩放时窗口右/下边会被拖出屏幕，
##    而缩放把手就在那个角上 —— 让它跑出屏幕等于把把手弄丢了，
##    玩家再也缩不回来。所以两个操作都要 clamp。
func _clamp_into_viewport() -> void:
	var parent := get_parent_control()
	if parent == null:
		return
	var limit := parent.size
	if limit.x <= 0.0 or limit.y <= 0.0:
		return
	position.x = clampf(position.x, MIN_VISIBLE - size.x, limit.x - MIN_VISIBLE)
	position.y = clampf(position.y, 0.0, maxf(0.0, limit.y - HEADER_H))


func set_status(text: String) -> void:
	if _status_label:
		_status_label.text = text


## 按 V3 稿的绝对像素位摆放窗口
##
## V3 稿给的是 (x, y, w, h) 四元组，实装直接照抄，不做锚点换算 ——
## 因为「窗口可以被玩家拖走」这件事本身就让锚点失去意义。
## ⚠️⚠️ 本函数**会被 HUD 反复调用**（每次界面刷新都来一遍，见 `eve_hud_root.gd` 的
##     十处 `set_window_rect`）。所以它**只记录设计稿矩形**，不当场生效 ——
##     实际生效的由 `_effective_rect()` 决定（玩家拖过用玩家的 / 收起只留标题栏）。
##     ⛔ 别改回"无条件套用参数"：那样「玩家收起的窗、HUD 一刷新又弹开」，
##        而且拖动/缩放的结果会被下一次刷新无声抹掉。
func set_window_rect(x: float, y: float, w: float, h: float) -> void:
	# ★ 高度已被控件自己接管 ⇒ 只更新位置与宽度（见 `_height_owned` 注释）
	var use_h := _base_rect.size.y if _height_owned and _base_rect.size.y > 1.0 else h
	# ★ 高度接管 + `fit_in_viewport` ⇒ 把过高的窗上移进屏（见字段注释）
	if _height_owned and fit_in_viewport:
		y = _fit_y_in_viewport(y, use_h)
	_base_rect = Rect2(x, y, w, use_h)
	_apply_rect(_effective_rect())


## 把 y 收进「整扇窗可见」的范围（高度超出可用高度时贴顶）。
##
## ⚠️ 提出来是因为它有两个调用点：HUD 刷新时的 `set_window_rect()`，
##    以及窗口自己按内容反推高度时的 `_fit_height()`（设置窗）。
##    ⛔ 抄两份必然漂移 —— 一处修了另一处没修，表现是"某个入口进来看不见底部"。
func _fit_y_in_viewport(y: float, h: float) -> float:
	var vh := get_viewport_rect().size.y
	if vh <= 1.0 or y + h <= vh - FIT_MARGIN:
		return y
	return maxf(FIT_MARGIN, vh - FIT_MARGIN - h)


## 只改高（档案窗「收起 / 展开」用）
##
## ⚠️ 必须同步 `_base_rect` —— 否则 HUD 下次刷新调 `set_window_rect` 时，
##    会按设计稿把这里刚设的高度改回去（档案窗的展开被无声顶掉）。
func set_window_height(h: float) -> void:
	_height_owned = true          # ★ 从此高度归控件自己管，见字段注释
	var x := _base_rect.position.x if _base_rect.size.x > 1.0 else position.x
	var y := _base_rect.position.y if _base_rect.size.y > 1.0 else position.y
	var w := _base_rect.size.x if _base_rect.size.x > 1.0 else size.x
	_base_rect = Rect2(x, y, w, h)
	_apply_rect(_base_rect)


# ------------------------------------------------------------------ 收起 / 布局记忆

## 收起 / 展开（EVE 的 roll-up：收起后只剩标题栏）
func toggle_collapse() -> void:
	if not collapsible or _content_margin == null:
		return
	_collapsed = not _collapsed
	_refresh_collapsed()
	_save_layout()
	# ⚠️ 收起会让窗口变成一条 ⇒ 刷新完要再 clamp 一次，别让它挂在屏幕外
	_clamp_into_viewport()


func is_collapsed() -> bool:
	return _collapsed


## 直接设定收起态（幂等）。
##
## ⚠️ 存在的理由：紧凑档（移动端放大）需要**开局就把侧列收起来**，
##    而 `toggle_collapse()` 的语义是「玩家点了一下」—— 它不幂等，
##    也不能拿布尔去调（那样「已经是收起态」会被再翻一次，变成展开）。
## ⛔ 别用它代替 `toggle_collapse()`：玩家点击那条路必须保留「翻转」语义。
func set_collapsed(on: bool) -> void:
	if _collapsed == on:
		return
	toggle_collapse()


## 把「收起态」刷到界面上（visible / 把手 / 高度）
func _refresh_collapsed() -> void:
	if _content_margin != null:
		_content_margin.visible = not _collapsed
	if _grip != null:
		_grip.visible = resizable and not _collapsed
	if _collapse_btn != null:
		_collapse_btn.queue_redraw()
	var r := _effective_rect()
	if r.size.x > 1.0 and r.size.y > 1.0:
		_apply_rect(r)


## 实际生效的矩形：玩家拖/缩过 ⇒ 用玩家的；否则用设计稿的。
func _effective_rect() -> Rect2:
	if _user_rect.size.x > 1.0 and _user_rect.size.y > 1.0:
		return _user_rect
	if _base_rect.size.x > 1.0 and _base_rect.size.y > 1.0:
		return _base_rect
	return Rect2(position, size)


func _apply_rect(r: Rect2) -> void:
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	position = r.position
	var h := r.size.y
	if _collapsed:
		h = HEADER_H
	custom_minimum_size = Vector2(r.size.x, h)
	size = Vector2(r.size.x, h)


## 记下「玩家把窗口摆成了什么样」。
##
## ⚠️ 收起状态下 `size.y` 只有标题栏高 —— ⛔ 别把它当成"玩家要的高度"存下来，
##    否则展开后回不到原来的高度。要取**展开态**的高度。
func _note_user_rect() -> void:
	var prev := _effective_rect()
	var h := size.y
	if _collapsed:
		h = prev.size.y if prev.size.y > HEADER_H + 1.0 else 240.0
	_user_rect = Rect2(position, Vector2(size.x, h))


func _layout_key() -> String:
	return layout_key if layout_key != "" else window_title


func _save_layout() -> void:
	if not persist_layout:
		return
	var r := _effective_rect()
	if r.size.x <= 1.0 or r.size.y <= 1.0:
		return
	LAYOUT_STORE.save_window(_layout_key(), {
		"x": position.x, "y": position.y,
		"w": r.size.x, "h": r.size.y,
		"collapsed": _collapsed,
	})


func _load_layout() -> void:
	if not persist_layout:
		return
	var d := LAYOUT_STORE.load_window(_layout_key())
	if d.is_empty():
		return
	var w := float(d.get("w", 0.0))
	var h := float(d.get("h", 0.0))
	if w > 1.0 and h > 1.0:
		_user_rect = Rect2(float(d.get("x", position.x)),
				float(d.get("y", position.y)), w, h)
	_collapsed = bool(d.get("collapsed", false))
	_refresh_collapsed()


## 忘掉这扇窗的布局（恢复设计稿位置）
func reset_layout() -> void:
	_user_rect = Rect2()
	_collapsed = false
	_height_owned = false         # 交还高度控制权，回到设计稿
	LAYOUT_STORE.save_window(_layout_key(), {})
	_refresh_collapsed()
	if _base_rect.size.x > 1.0:
		_apply_rect(_base_rect)


# ------------------------------------------------------------------ 便捷构建器

## 分隔线
static func make_divider() -> ColorRect:
	var line := ColorRect.new()
	line.color = Color(0.42, 0.55, 0.60, 0.28)
	line.custom_minimum_size = Vector2(0, 1)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return line


## 小标题（分组用）
static func make_section(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", Color(0.52, 0.66, 0.70))
	FONT.fs(l, 11)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## 极小号分组标签（「势力 FACTION」这种全大写分组头）
static func make_group_header(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", Color(0.43, 0.53, 0.58))
	FONT.fs(l, 9)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## 键值行（左侧标签 + 右侧数值）
static func make_stat_row(key: String, value: String, value_color: Color = C_TEXT,
		key_width: float = 58.0) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var k := Label.new()
	k.text = key
	k.add_theme_color_override("font_color", C_TEXT_DIM)
	FONT.fs(k, 11)
	k.custom_minimum_size = Vector2(key_width, 0)
	k.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(k)

	var v := Label.new()
	v.text = value
	v.add_theme_color_override("font_color", value_color)
	FONT.fs(v, 11)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(v)

	return row


## 数据条（血条 / 属性条）
##
## 返回 {"row": HBoxContainer, "bar": ProgressBar, "num": Label}
## num 是右侧数值，bar 由调用方每帧刷新。
static func make_bar_row(key: String, color: Color, max_value: float,
		key_width: float = 42.0, num_width: float = 52.0) -> Dictionary:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var k := Label.new()
	k.text = key
	k.add_theme_color_override("font_color", C_TEXT_DIM)
	FONT.fs(k, 11)
	k.custom_minimum_size = Vector2(key_width, 0)
	k.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(k)

	var bar := ProgressBar.new()
	bar.max_value = maxf(1.0, max_value)
	bar.value = max_value
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 8)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.10, 0.13, 0.15, 0.9)
	bg.set_corner_radius_all(0)
	bg.set_border_width_all(0)
	bar.add_theme_stylebox_override("background", bg)

	var fg := StyleBoxFlat.new()
	fg.bg_color = color
	fg.set_corner_radius_all(0)
	bar.add_theme_stylebox_override("fill", fg)
	row.add_child(bar)

	var num := Label.new()
	num.text = "%d" % int(max_value)
	num.add_theme_color_override("font_color", C_TEXT)
	FONT.fs(num, 11)
	num.custom_minimum_size = Vector2(num_width, 0)
	num.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	num.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(num)

	return {"row": row, "bar": bar, "num": num}


## 自绘进度细条（羁绊的 th 条 —— 比 ProgressBar 更容易对齐 6px 高度）
##
## 返回 {"root": Control, "set_value": Callable(pct: float)}
static func make_thin_bar(fill_color: Color, height: float = 6.0) -> Dictionary:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(0, height)
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var track := ColorRect.new()
	track.color = Color(0.10, 0.13, 0.15, 0.92)
	track.set_anchors_preset(Control.PRESET_FULL_RECT)
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(track)

	var fill := ColorRect.new()
	fill.color = fill_color
	fill.anchor_bottom = 1.0
	fill.offset_right = 0.0
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(fill)

	var setter := func(pct: float) -> void:
		if is_instance_valid(fill):
			fill.offset_right = holder.size.x * clampf(pct, 0.0, 1.0)
	return {"root": holder, "set_value": setter}
