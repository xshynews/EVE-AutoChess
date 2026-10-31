extends "res://scripts/ui/eve_window.gd"

## EVE 自走棋 —— 节点结算页（阶段 D）
##
## ══════════════════════════════════════════════════════════════════
##  它取代了什么
## ══════════════════════════════════════════════════════════════════
##  在它出现之前，战斗结束后走的是 `EveBattleScene.RESOLVE_SECONDS = 3.5`
##  的**定时器自动推进** —— 打完等 3.5 秒，画面自己跳到下一节点。
##  那个常量的注释里写着「阶段 D 的结算页会取代它」，这就是它。
##
##  ── 为什么自动推进必须去掉（不只是「加个好看的页」）──────────────
##  自走棋的节奏是「我准备好了才开打」。自动推进把这个权力从玩家手里拿走了：
##  结算那 3.5 秒里发生的事情（漏了几艘、信标掉了多少、拿到什么残骸）
##  如果玩家没看见就翻页了，那么「我这一局打成什么样」这件事就没被传达。
##  这和阶段 A 删掉 `auto_restart_delay` 是同一个理由（那次是把玩家从
##  决策者降级成观众，这次是把玩家从读者降级成观众）。
##
##  ── 两个按钮：为什么是这两个 ─────────────────────────────────────
##    「继续 · 下一节点」= 推进节点（Resolve 阶段唯一的正常出路）
##    「结束本局」      = 放弃这一局，回准备阶段重开
##  第二个按钮**不是**「退出游戏」—— 一个自走棋原型里把进程退掉没有意义。
##  它的语义是「这局我不打了」，落地为 `restart_run()`（重开一局）。
##
##  ── 布局：一眼看出「发生了什么」的优先级 ─────────────────────────
##    ① 结论    拦截成功 / 被突破（最大字号，配色绿 / 红）
##    ② 信标    变化前后 + 差额（一局的生命线，掉了多少是玩家最关心的）
##    ③ 战果    击毁 / 我方存活
##    ④ 收益    经验 + 残骸（有没有东西可打捞）
##    ⑤ 操作    两个按钮
##
## ⚠️ 三个数字必须与 `EveRunState.resolve_battle()` 的**返回值**同源 ——
##    不要在场景侧自己再算一遍（判据写两份必然分叉，这是本工程的既有铁律）。

signal next_requested()      ## 继续 · 下一节点
signal end_requested()       ## 结束本局（重开）
## ★ 打捞区（2026-10-04 改版：按钮在结算页**下方**，逐艘直接点「打捞」）
signal salvage_pick_requested(idx: int)  ## 点某一艘的「打捞」按钮，参数 = 残骸下标
signal salvage_pick_zero()               ## 零选二次确认通过（「确定放弃」）
signal salvage_section_closed()         ## 点「✕」收起打捞区（**不下单**）
var _title: Label
var _subtitle: Label
var _beacon_before: Label
var _beacon_after: Label
var _beacon_delta: Label
var _kill_row: HBoxContainer
var _alive_row: HBoxContainer
var _xp_row: HBoxContainer
var _loot_row: HBoxContainer
## 联机对战模式：结算页**只留打捞**，推进完全交给回合倒计时。
var _versus_mode := false
## 联机名次表（单机时不可见）
var _rank_box: VBoxContainer
var _rank_rows: VBoxContainer
var _next_btn: Button
var _end_btn: Button
## ★ 打捞区（2026-10-04 改版）。挂在结算页 content 末尾，默认隐藏。
var _salvage_section: VBoxContainer
var _salvage_title: Label
var _salvage_hint: Label
var _salvage_warn: Label
var _salvage_list: GridContainer
var _salvage_scroll: ScrollContainer
## 防重入标记（见 `_on_result_resized`）：拖动缩放时列数与窗高互相触发。
var _fitting_salvage := false
var _salvage_queue: Label
var _salvage_coin: Label
var _salvage_close_btn: Button
## ★ 2026-10-13：确认框从 Godot 内置 `ConfirmationDialog` 换成自绘的
##    `EveConfirmDialog` —— 内置那个是**原生 OS 窗口**（系统标题栏/字体/配色），
##    与 EVE 窗口语言完全两个物种（用户原话「给我丑哭了」）。
##    ⚠️ 它挂在**本窗的父节点**（HUD 根）上，⛔ 不能 add_child 到本窗：
##       EveWindow 根是 PanelContainer，会把每个子节点拉成整窗矩形。
var _salvage_ask: EveConfirmDialog

## 结果数据（最近一次 show_result 的入参，验收脚本可读）
var _data: Dictionary = {}


# ══════════════════════════════════════════════════════════════════
#  ★ 高度账（2026-10-04 二改：压短 + 修「窗高失控」）
# ══════════════════════════════════════════════════════════════════
#
## 打捞区的一行（= 一个「打捞」按钮的高度 + 行间距）。
##
## ★★ 2026-10-31（用户：「战损多的时候后面的船打捞不到」）：**20 → 22**。
##   20 是按钮本身的高度，漏了 `v_separation`（2）⇒ 算式永远比内容矮一截。
##   实测（`probe_result_ui -- --many`，420 宽单列）：12 行内容高 262 ⇒ 21.83/行。
##   症状正是用户看到的那样：列表最后一行**只露出半个按钮**，剩下一半被窗底裁掉。
##   ⚠️ 改这里必须重跑那个探针核对 `内容高 / 行数`。
const SALVAGE_ROW_H := 22.0
## 打捞列表区的最大高度（默认窗宽下的基准）：超过就滚动（N 艘再多也不撑破窗）。
## ⚠️ 窗**被玩家拖大**之后这个上限会跟着放（见 `_salvage_list_h_now`）——
##    写死的上限就是「拖大了也只显示 6 艘」那个问题的来源。
const SALVAGE_LIST_MAX_H := 176.0
## 打捞区一列的最小宽度（设计像素）。
## 一行 = 船名 + 星级 + 「打捞」按钮，实测再窄就只剩省略号。
const SALVAGE_MIN_COL_W := 230.0
## 最多几列 —— 再宽也只是留白，不会更易读。
const SALVAGE_MAX_COLS := 4
## 打捞区的固定部分（标题行 + 警告行 + 队列行占位 + 段间距）。
##
## ⚠️⚠️ 这个数是**实测标定**的，不是算出来的 —— 改打捞区排版后**必须重量一次**
##    并同步这里，否则窗高会算歪（症状 = 底部多一条空白 或 内容被切掉）。
##    标定方法：跑 `tools/_m_res.tscn`（量窗高探针），
##    固定部分 = 有残骸窗高 − 无残骸窗高 − 行数 × 20。
const SALVAGE_FIXED_H := 47.0
## 结算页顶部固定部分（标题 + 副标题 + 信标 + 战果 + 收益 + 操作 + 分隔 + 段间距），
## **含 content 容器的 separation**，所以它是「content 的最小高度」整数值。
##
## ⚠️⚠️ 同样是**实测标定**的：跑量窗高探针，无残骸时的 content 高度就是它
##    （外壳 41 另算）。改结算页顶部结构后必须重量。
const RESULT_HEAD_H := 203.0
## `EveWindow` 的窗口外壳（标题栏 + 上下内边距 + 边框）。
##
## ⚠️⚠️ **这是实测值，不是猜的**：一个 content minimum 为 315 的结算页，
##    实际窗口高 356 ⇒ 外壳 = 41。
##    ⛔ 原来这里写的是 `+96`，凭空多留 55px 白底 —— 那正是用户说的
##      「结算页面做得太长了」的直接原因之一。
##    若日后改了 `EveWindow` 的 density 或标题栏，这个数要跟着改；
##    症状 = 底部一条空白（多了）或内容被切（少了）。
const RESULT_CHROME_H := 41.0

## ★ 2026-10-10 i18n：玩家可见文案一律从这里取（见 eve_text.gd 顶注）。
const T := preload("res://scripts/core/eve_text.gd")
## ★ 2026-10-21（UI 比例基线 · 阶段 0-3）：字号走全站刻度（桌面端自动回落原值）。
const METRICS := preload("res://scripts/ui/eve_ui_metrics.gd")
const LAYOUT := preload("res://scripts/ui/eve_layout.gd")


## 当前设计空间（桌面端与手机端同一口径；不在树里时回落 1920×1080）。
func _dspace() -> Vector2:
	if not is_inside_tree():
		return Vector2(1920.0, 1080.0)
	return LAYOUT.design_space(get_window())


## 标题/副标题放大后，顶部固定高度要**补多少**。
##
## ⚠️⚠️ 结算页的窗高是**确定性算式**（`_fit_salvage_height`），⛔ 不读容器实时最小尺寸。
##   所以字号一变，就必须同步补高度 —— 否则症状是「底部被切」或「多一条白底」。
## ⚠️ 只算**放大**（缩小时不补，避免负数把窗压塌）。行高按 1.3×字号估算。
func _title_grow() -> float:
	var d := _dspace()
	var dt := METRICS.t1(d, 22) - 22
	var ds := METRICS.t3(d, 10) - 10
	return maxf(0.0, 1.3 * float(dt + ds))



func _ready() -> void:
	window_title = T.t("RESULT_TITLE", "节点结算")
	density = Density.COMPACT
	super._ready()
	_build_contents()
	# ★ 打捞区在 `_build_contents` **之后**建 —— 它要挂在 content 的末尾
	#    （用户要求「按钮在后面」），而 content 是在 _build_contents 里填的。
	_build_salvage_section()
	# ★ 2026-10-30：玩家拖动放大/缩小结算窗 ⇒ 打捞列表要跟着重排列数与可见行数。
	resized.connect(_on_result_resized)


func _build_contents() -> void:
	content.add_theme_constant_override("separation", 7)

	# ── ① 结论 ──
	_title = Label.new()
	_title.text = T.t("RESULT_WIN", "拦截成功")
	FONT.fs(_title, METRICS.t1(_dspace(), 22))
	_title.add_theme_color_override("font_color", C_OK)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(_title)

	_subtitle = Label.new()
	_subtitle.text = T.t("RESULT_SUB", "节点 1 / 15 · 遭遇战")
	FONT.fs(_subtitle, METRICS.t3(_dspace(), 10))
	_subtitle.add_theme_color_override("font_color", C_TEXT_DIM)
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(_subtitle)

	content.add_child(make_divider())

	# ── ② 信标（本页的视觉重点）──
	var beacon_box := HBoxContainer.new()
	beacon_box.add_theme_constant_override("separation", 6)
	beacon_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	beacon_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(beacon_box)

	var ic := EveIcon.make(&"beacon", 18.0, C_ACCENT, 1.6)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	beacon_box.add_child(ic)

	var flow := HBoxContainer.new()
	flow.add_theme_constant_override("separation", 6)
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	flow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	flow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	beacon_box.add_child(flow)

	_beacon_before = _num_label(18, C_TEXT_DIM)
	flow.add_child(_beacon_before)

	var arrow := Label.new()
	arrow.text = "→"
	FONT.fs(arrow, 16)
	arrow.add_theme_color_override("font_color", C_TEXT_FAINT)
	arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flow.add_child(arrow)

	_beacon_after = _num_label(22, C_HULL)
	flow.add_child(_beacon_after)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flow.add_child(spacer)

	_beacon_delta = _num_label(15, C_WARN)
	_beacon_delta.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	flow.add_child(_beacon_delta)

	content.add_child(make_divider())
	# ── ②b 联机名次表（单机不可见）──
	_rank_box = VBoxContainer.new()
	_rank_box.add_theme_constant_override("separation", 4)
	_rank_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rank_box.visible = false
	content.add_child(_rank_box)

	_rank_rows = VBoxContainer.new()
	_rank_rows.add_theme_constant_override("separation", 3)
	_rank_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rank_box.add_child(_rank_rows)

	# ── ③ 战果（★ 二改：两行**并成一行**，省下 23px）──
	# ⛔ 2026-10-01：这里原来还有一行「漏网 N 艘」—— 整行删掉了。
	#    「漏网」是内部算法（已废的「阶段基础 + Σ舰船费用」），
	#    玩家既不需要知道，也无从解释（"我全活为什么还漏网"）。
	#    代价只看「信标 −N」，战绩只留「击毁 / 我方存活」。
	#
	# ⚠️ 并排的写法：两个 `make_stat_row` 塞进一个外层 HBox，各自 EXPAND 占一半。
	#    `_stat()` 仍然用 `get_child(1)` 改值，⛔ 所以**行对象本身不能换**
	#    （换成别的容器会让 `_stat()` 静默改错控件）。
	_kill_row = make_stat_row(T.t("RESULT_KILL", "击毁"),
			T.t("RESULT_SHIPS_0", "0 艘"), C_OK, 40.0)
	_alive_row = make_stat_row(T.t("RESULT_ALIVE", "我方存活"), "0 / 0", C_TEXT, 48.0)
	content.add_child(_pair_hbox(_kill_row, _alive_row))

	content.add_child(make_divider())

	# ── ④ 收益（★ 二改：同样并成一行）──
	_xp_row = make_stat_row(T.t("RESULT_XP", "经验"), "+2", C_CAP, 40.0)
	_loot_row = make_stat_row(T.t("RESULT_WRECK", "残骸"),
			T.t("RESULT_NONE", "无"), C_ARMOR, 48.0)
	content.add_child(_pair_hbox(_xp_row, _loot_row))

	content.add_child(make_divider())

	# ── ⑤ 操作 ──
	var acts := HBoxContainer.new()
	acts.add_theme_constant_override("separation", 6)
	acts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(acts)

	_end_btn = Button.new()
	_end_btn.text = T.t("RESULT_END", "结束本局")
	_end_btn.custom_minimum_size = Vector2(0, 28)
	_end_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_end_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	EveButtonTheme.apply(_end_btn, "hud")
	_end_btn.pressed.connect(func(): end_requested.emit())
	acts.add_child(_end_btn)

	_next_btn = Button.new()
	_next_btn.text = T.t("RESULT_NEXT", "继续 · 下一节点")
	_next_btn.custom_minimum_size = Vector2(0, 28)
	# 主按钮占更大份量（这是 90% 的情况想点的那一个）
	_next_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_next_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	EveButtonTheme.apply(_next_btn, "hud_main")
	_next_btn.pressed.connect(func(): next_requested.emit())
	acts.add_child(_next_btn)
	# 左右权重 3:5 —— 「继续」更宽，视觉上就是默认动作
	_end_btn.size_flags_stretch_ratio = 3.0
	_next_btn.size_flags_stretch_ratio = 5.0


# ══════════════════════════════════════════════════════════════════
#  ★ 打捞区（2026-10-04 改版：按钮在**后**，逐艘点）
# ══════════════════════════════════════════════════════════════════
#
## 用户反馈（2026-10-04 原话）：「我想把打捞做成这样在**后面的按钮**的，
## 现在在前面点选有点反直觉了」，并给了两张参考图。
##
## ## 版式为什么是这样（对照参考图）
## ##   ① 打捞入口放在**「结束本局 / 继续」之后**（页面下方），
## ##      不是像上一版那样顶在收益行下面、还弹一层浮层。
## ##   ② 列表**直接展开在结算页里**，每艘右侧一个「打捞」按钮 ——
## ##      玩家点哪艘就是哪艘，**不用先勾选、再点确认**（两段式反直觉）。
## ##   ③ 打捞完（或本回合没残骸）时，同一位置显示
## ##      「修复队列（下回合到账）」+「持有 N 星币」—— 收支一目了然。
##
## ⚠️ 只参考**按钮与排版形态**，配色/字体沿用本工程 `EveWindow` 的
##    那一套（用户明确交代：不参考整体设计风格）。

## 造出整个打捞区（挂在结算页 content 的**末尾**）。
##
## ★★ 2026-10-04 二改：**压短**（用户反馈「结算页面做得太长了」）。
##
## ## 从哪省下来的（对照改前）
## ##   ① 标题 + 机制说明**并成一行**（原来各占一行）        —— 省 ~14
## ##   ② 「关闭」从**独占一行**挪到标题行右端的小「✕」      —— 省 ~28
## ##   ③ 警告行与「持有 N 星币」**并成一行**                —— 省 ~18
## ##   ④ 行高 22 → 18、行间 3 → 2                          —— 每艘省 5
## ##   ⑤ 全部 `autowrap` 去掉 —— 见下方红字说明
##
## ⚠️⚠️ **`autowrap_mode` 是这里的高度炸弹，不许加回来**：
##    带 autowrap 的 Label 放进 VBoxContainer 时，容器给它的最小宽度可以小到
##    一个字宽 ⇒ 文字折成一列竖排 ⇒ `get_combined_minimum_size().y` 爆炸
##    （实测同一个 Label 在布局前后能从 14 变成 958）。
##    本区的文案都是**短句**，直接让它单行显示；真要折行就自己断句写两行，
##    ⛔ 不交给 autowrap 判。
func _build_salvage_section() -> void:
	_salvage_section = VBoxContainer.new()
	_salvage_section.name = "SalvageSection"
	_salvage_section.add_theme_constant_override("separation", 3)
	# ⚠️ 默认**隐藏**：没有残骸时不占地方（结算页本来就该短）。
	_salvage_section.visible = false
	content.add_child(_salvage_section)

	# ── ① 标题行：⚓ 打捞 残骸 ｜ 下单即付款·下节点到账 ｜ ✕ ──
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 5)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_salvage_section.add_child(head)

	var icon := Label.new()
	icon.text = "⚓"
	FONT.fs(icon, 12)
	icon.add_theme_color_override("font_color", C_ARMOR)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(icon)

	_salvage_title = Label.new()
	_salvage_title.text = T.t("RESULT_SALVAGE_TITLE", "打捞 残骸")
	FONT.fs(_salvage_title, 12)
	_salvage_title.add_theme_color_override("font_color", C_ARMOR)
	_salvage_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_salvage_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(_salvage_title)

	# 机制说明：挤在标题右边（EXPAND 吃掉中间空白），字号压到 8
	_salvage_hint = Label.new()
	_salvage_hint.text = T.t("RESULT_SALVAGE_HINT", "下单即付款 · 下节点到账占位")
	FONT.fs(_salvage_hint, 8)
	_salvage_hint.add_theme_color_override("font_color", C_TEXT_FAINT)
	_salvage_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_salvage_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_salvage_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(_salvage_hint)

	# 「关闭」= 收起打捞区（**不下单**）。
	#  ★ 二改：从独占一行 24px 的按钮，压成标题行右端一个 16×16 的「✕」。
	#  ⚠️ 语义仍是 `salvage_section_closed`，⛔ 别复用 `salvage_pick_requested`
	#     （那是「打捞这一艘的下标」信号）—— 发错会让上层把 idx=0 当第 0 艘
	#     ⇒ **凭空扣钱**。
	_salvage_close_btn = Button.new()
	_salvage_close_btn.text = "✕"
	_salvage_close_btn.custom_minimum_size = Vector2(18, 16)
	_salvage_close_btn.focus_mode = Control.FOCUS_NONE
	_salvage_close_btn.tooltip_text = T.t("RESULT_SALVAGE_CLOSE_TIP",
				"收起打捞区（残骸仍保留）")
	EveButtonTheme.apply(_salvage_close_btn, "hud")
	_salvage_close_btn.pressed.connect(func(): salvage_section_closed.emit())
	_salvage_close_btn.visible = false
	head.add_child(_salvage_close_btn)

	# ── ② 警告行（左）＋ 持有星币（右）**共用一行** ──
	var ar := HBoxContainer.new()
	ar.add_theme_constant_override("separation", 6)
	ar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_salvage_section.add_child(ar)

	_salvage_warn = Label.new()
	FONT.fs(_salvage_warn, 9)
	_salvage_warn.add_theme_color_override("font_color", C_HULL)
	_salvage_warn.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_salvage_warn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_salvage_warn.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ar.add_child(_salvage_warn)

	_salvage_coin = Label.new()
	FONT.fs(_salvage_coin, 10)
	_salvage_coin.add_theme_color_override("font_color", C_CAP)
	_salvage_coin.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_salvage_coin.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_salvage_coin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ar.add_child(_salvage_coin)

	# ── ③ 列表（可滚动；N 艘再多也不撑破窗）──
	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.custom_minimum_size = Vector2(0, 0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_salvage_section.add_child(scroll)
	_salvage_scroll = scroll
	# ★ 2026-10-31（用户：「拉不动」）：默认 8px 滚动条压不住 ⇒ 统一走基类的加宽
	widen_scrollbar(scroll)

	# ★ 2026-10-30（玩家反馈）：「结算栏拖动放大的同时，打捞选项也要展示更多」。
	#   列表从**单列 VBox** 换成**网格**：窗一宽就自动分 2/3/4 列，
	#   窗一高就多显示几行（列数与行数都由 `_apply_salvage_grid` 现算）。
	_salvage_list = GridContainer.new()
	_salvage_list.name = "List"
	_salvage_list.columns = 1
	_salvage_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_salvage_list.add_theme_constant_override("h_separation", 10)
	_salvage_list.add_theme_constant_override("v_separation", 2)
	scroll.add_child(_salvage_list)

	# ── ④ 修复队列行（无残骸时才有内容；有残骸时它是空串）──
	_salvage_queue = Label.new()
	FONT.fs(_salvage_queue, 9)
	_salvage_queue.add_theme_color_override("font_color", C_OK)
	_salvage_queue.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_salvage_queue.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_salvage_section.add_child(_salvage_queue)

	# ── 零选二次确认（图 1 那种「本回合不决定 → 永久作废」的护栏）──
	# ★★ 2026-10-13 换装：内置 ConfirmationDialog → EveConfirmDialog（见上面成员注释）
	_salvage_ask = EveConfirmDialog.new()
	_salvage_ask.name = "SalvageAsk"
	_salvage_ask.setup(T.t("RESULT_SALVAGE_ASK_TITLE", "放弃打捞"), "",
			T.t("RESULT_SALVAGE_ASK_OK", "确定放弃"),
			T.t("RESULT_SALVAGE_ASK_CANCEL", "回去再选"))
	_salvage_ask.confirmed.connect(_emit_zero_pick_confirmed)
	# ⚠️ 挂在父节点（HUD 根）上，本窗自己是个 PanelContainer（会把子节点拉变形）。
	#    「本窗不可见 ⇒ 确认框一起收」由 `_notification` 保证，不会漏在外面吃点击。
	var ask_host := get_parent()
	if ask_host != null:
		ask_host.add_child(_salvage_ask)
	else:
		add_child(_salvage_ask)


## 「继续」时还有残骸 ⇒ 弹二次确认（EVE 窗口语言版）。
##
## 主控（`eve_battle_scene._maybe_confirm_leftover_wrecks`）只报个数，
## 文案与弹框都在这里 —— ⛔ 别再回退成去戳内置 ConfirmationDialog。
## 「放弃打捞」确认框是否开着（AI 操作面用）。
func salvage_ask_open() -> bool:
	return _salvage_ask != null and _salvage_ask.is_open()


## 确认 / 取消「放弃打捞」。
## ⚠️ 必须走 EveConfirmDialog 的 confirm()/cancel()（它们自带 close_dialog），
##    不要在这里直接 emit 信号。
func confirm_salvage_ask() -> void:
	if _salvage_ask != null:
		_salvage_ask.confirm()


func cancel_salvage_ask() -> void:
	if _salvage_ask != null:
		_salvage_ask.cancel()


func ask_abandon_salvage(count: int) -> void:
	if _salvage_ask == null:
		return
	# ⚠️ 这句文案 2026-10-13 从主控搬来。i18n 冻结期不迁 key，保持原样。
	_salvage_ask.message = "本回合还有 %d 艘残骸没有打捞。\n确定要放弃吗？" % count
	_salvage_ask.open_dialog()


## 结算页被收起（`hud.hide_result()` / 推进节点 / 重开）⇒ 确认框必须一起收。
##
## ⚠️ 为什么需要它：确认框挂在 **HUD 根**（不是本窗的子节点），
##    本窗 `visible = false` 不会连带它 —— 不主动收的话，一枚全屏 scrim
##    会留在战场上继续吃点击（玩家点哪都没反应，且**不报错**）。
##    确认/取消两条路都会自己 `close_dialog()`，这里兜的是其余所有收起路径。
func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and not visible:
		if _salvage_ask != null and _salvage_ask.visible:
			_salvage_ask.close_dialog()


## 一艘残骸的一行：`节点 N · 舰名 ★S` … `N ◆` … [打捞]
func _add_salvage_row(it: Dictionary) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# 左：舰名 + 星级（阵营用颜色区分，不用文字标签 —— 少一列更清爽）
	var name_lb := Label.new()
	var team := int(it.get("team", 0))
	name_lb.text = T.t("RESULT_SALVAGE_ROW", "节点 %d · %s ★%d") % [int(it.get("node", 1)),
			String(it.get("name", "?")), int(it.get("star", 1))]
	FONT.fs(name_lb, 10)
	name_lb.add_theme_color_override("font_color", C_OK if team == 0 else C_TEXT)
	name_lb.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_lb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(name_lb)

	# 中：单价
	var price_lb := Label.new()
	price_lb.text = "%d ◆" % int(it.get("price", 0))
	FONT.fs(price_lb, 10)
	# 敌方更贵 ⇒ 橙色，让「捞谁」的取舍在视觉上就成立
	price_lb.add_theme_color_override("font_color",
			C_WARN if team != 0 else C_CAP)
	price_lb.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	price_lb.custom_minimum_size = Vector2(44, 0)
	price_lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	price_lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(price_lb)

	# 右：打捞按钮（★ 核心：逐艘直接点，不用先勾后确认）
	var btn := Button.new()
	btn.text = T.t("RESULT_SALVAGE_BTN", "打捞")
	# ★ 二改：按钮高 22 → 18（压短；仍是标准「打捞」按钮的形态）
	btn.custom_minimum_size = Vector2(50, 18)
	btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	EveButtonTheme.apply(btn, "hud")
	btn.pressed.connect(_emit_salvage_one.bind(int(it.get("idx", -1))))
	row.add_child(btn)

	_salvage_list.add_child(row)


## 逐艘「打捞」按钮的出口：把下标抛给上层去下单。
func _emit_salvage_one(idx: int) -> void:
	salvage_pick_requested.emit(idx)


## 零选二次确认的最终出口（由 ConfirmationDialog 的 confirmed 触发）。
func _emit_zero_pick_confirmed() -> void:
	salvage_pick_zero.emit()


## ★ 刷新打捞区（每次下单后、以及每次 `show_result()` 都要调）。
##
## `res` = `EveRunState.salvage_info()` 的输出（**唯一输入源**，UI 不自己算）。
## `ended` = 本局是否已结束（结局页不显示打捞）。
##
## ## 两种形态（对照参考图）
## ##   ① **有残骸** ⇒ 逐艘列表，每行一个「打捞」按钮 + 顶部红字警告
## ##      「本回合不决定，这 N 艘残骸永久作废」。
## ##   ② **无残骸但有在途** ⇒ 「暂无残骸 —— 一艘船被击毁后会出现在这里」
## ##      +「修复队列（下回合到账）：…」+「持有 N 星币」（参考图 2）。
## ##   ③ 两者都空 ⇒ 整个区块隐藏（不让空白占地方）。
func refresh_salvage(res: Dictionary, ended: bool = false) -> void:
	_clear_salvage_rows()
	var items: Array = res.get("items", []) if String(res.get("state", "")) == "list" \
			else [] as Array
	var queue: Array = res.get("queue", []) if String(res.get("state", "")) == "list" \
			else _queue_from_repairing(res)
	var coin := int(res.get("coin", 0))

	# 结局页 / 全空 ⇒ 不显示打捞区。
	# ⚠️ **仍然要调 `_fit_salvage_height()`** —— 否则窗高停在 `RECT_RESULT`
	#    那个固定值（356），明明没内容却留一大块空白。这正是「太长」的一半。
	if ended or (items.is_empty() and queue.is_empty()):
		_salvage_section.visible = false
		_fit_salvage_height()
		return
	_salvage_section.visible = true

	# ── ① 列表形态 ──
	if not items.is_empty():
		_salvage_warn.text = T.t("RESULT_SALVAGE_WARN", "⚠ 不决定就作废（%d 艘）") \
				% items.size()
		_salvage_warn.visible = true
		_salvage_list.visible = true
		for it in items:
			_add_salvage_row(it as Dictionary)
		# 列数 / 高度由**当前窗宽窗高**现算（拖动放大 → 立刻多显示几艘）
		_apply_salvage_grid()
	else:
		_salvage_warn.visible = false
		_salvage_list.visible = false
		if _salvage_scroll != null:
			_salvage_scroll.custom_minimum_size = Vector2(0, 0)
		# 「暂无残骸」占位（参考图 2 的那句）
		var none_lb := Label.new()
		none_lb.text = T.t("RESULT_SALVAGE_EMPTY", "暂无残骸 —— 舰船被击毁后会出现在这里")
		FONT.fs(none_lb, 9)
		none_lb.add_theme_color_override("font_color", C_TEXT_FAINT)
		none_lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		none_lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_salvage_list.add_child(none_lb)
		_salvage_list.visible = true
	# 「收起」按钮**任何时候都在**（参考图 2）—— 它是关掉打捞区的唯一出口，
	# ⛔ 别写成「打完才显示」：还有残骸时玩家也想先收起、看完战果再决定。
	_salvage_close_btn.visible = true

	# ── ② 队列行（有残骸时它是空串，自然不占高）──
	if queue.is_empty():
		_salvage_queue.text = ""
		_salvage_queue.visible = false
	else:
		var names: Array[String] = []
		for q in queue:
			names.append("%s ★%d" % [String((q as Dictionary).get("name", "?")),
					int((q as Dictionary).get("star", 1))])
		_salvage_queue.text = T.t("RESULT_SALVAGE_QUEUE", "修复队列（下回合到账）：%s") \
				% ", ".join(names)
		_salvage_queue.visible = true
	_salvage_coin.text = T.t("RESULT_COIN", "持有 %d 星币") % coin
	_fit_salvage_height()


## 「repairing」态下从 `salvage_info()` 取在途队列（图 2 的「修复队列」）。
func _queue_from_repairing(res: Dictionary) -> Array:
	if String(res.get("state", "")) != "repairing":
		return []
	return [res] as Array


## 清掉列表里的所有行。
##
## ⚠️ 必须 `remove_child()` + `queue_free()` **两步**：`queue_free()` 要到帧末
##    才真删，同一帧内重画会看到新旧两批（实测 3 旧 + 3 新 = 6 行）。
func _clear_salvage_rows() -> void:
	for c in _salvage_list.get_children():
		_salvage_list.remove_child(c)
		c.queue_free()


## 按内容**反推**窗高。
##
## ⚠️ 本工程铁律：窗高由内容算，⛔ 不手写 —— 手写会留一条死白底边（踩过 2 次）。
## ══════════════════════════════════════════════════════════════════
##  ★ 2026-10-30：打捞列表**网格化**（玩家：拖动放大要显示更多船）
## ══════════════════════════════════════════════════════════════════
##
## 列数 = 可用宽 / 单列最小宽（1~4），行数 = ceil(条数 / 列数)。
## 高度上限 = max(基准 120, 窗高 − 280) —— 窗拖得越高，能同时看到的行越多。
## ⚠️ 三处必须**同源**：`refresh_salvage` 的排版、`_fit_salvage_height` 的窗高、
##    拖动放大时的重排，全都只调这几个函数，⛔ 别在别处再写一遍行高。

## 当前该分几列（按滚动区实际宽度；还没排版时用窗宽兜底）。
func _salvage_cols_now() -> int:
	var avail := 0.0
	if _salvage_scroll != null:
		avail = _salvage_scroll.size.x
	if avail <= 8.0:
		avail = maxf(200.0, size.x - 60.0)
	return clampi(int(floor(avail / SALVAGE_MIN_COL_W)), 1, SALVAGE_MAX_COLS)


## 打捞列表当前应占的高度（0 = 没显示 / 没内容）。
##
## ★★ 2026-10-31（用户：「战损多的时候 后面的船打捞不到」）：
##   旧算法 `cap = max(120, size.y - 360)` 有个**先有鸡后有蛋**的死结 ——
##   窗口高由列表高决定，列表高又被**当前**窗高限制 ⇒ 卡死在 120（5 行半）。
##   战损 12 艘时永远只显示 5 行半，且第 6 行被裁一半（`SALVAGE_ROW_H` 少算 2px）。
##
##   现在 cap 改成**按设计空间**给：屏幕还有多高就允许多高，窗自然长上去；
##   玩家手动拖高那一份仍然认（`size.y - 360`）。
##
##   ⚠️ 结果必须**向下取整到整行**：给半行 = 按钮被裁一半，比不给更糟。
func _salvage_list_h_now() -> float:
	if _salvage_list == null or not _salvage_list.visible:
		return 0.0
	var n := _salvage_list.get_child_count()
	if n <= 0:
		return 0.0
	var cols := maxi(1, _salvage_list.columns)
	var rows := int(ceil(float(n) / float(cols)))
	# 上限 = 「屏幕还愿意给的高度」与「玩家拖出来的那份」取大
	var room := _dspace().y * 0.55 - RESULT_HEAD_H - SALVAGE_FIXED_H
	var cap := maxf(SALVAGE_LIST_MAX_H, room)
	cap = maxf(cap, size.y - 360.0)
	var want := float(rows) * SALVAGE_ROW_H
	# ⚠️ 至少给一整行，否则空列表上方会塌掉
	return maxf(SALVAGE_ROW_H, floorf(minf(want, cap) / SALVAGE_ROW_H) * SALVAGE_ROW_H)


## 重算列数并同步滚动区高度。排版 / 缩放 / 拖动三条路径共用。
func _apply_salvage_grid() -> void:
	if _salvage_list == null:
		return
	var cols := _salvage_cols_now()
	if _salvage_list.columns != cols:
		_salvage_list.columns = cols
	if _salvage_scroll != null:
		_salvage_scroll.custom_minimum_size = Vector2(0, _salvage_list_h_now())


## 窗口被拖动缩放：重排列数 + 重算窗高。
##
## ⚠️ 不这样做的话，玩家放大窗口只会得到一块更大的空白 —— 列表仍按放大前的
##    列数排（`custom_minimum_size` 是排版那一刻写死的）。
func _on_result_resized() -> void:
	if _salvage_section == null or not _salvage_section.visible:
		return
	# ⚠️ 防重入：`_apply_salvage_grid()` 会改滚动区最小尺寸 ⇒ 触发重排 ⇒
	#    可能再发一次 `resized`；`_fit_salvage_height()` 自己也会改窗高。
	#    没有这道闸，一次拖动会变成反复互相触发。
	if _fitting_salvage:
		return
	_fitting_salvage = true
	_apply_salvage_grid()
	_fit_salvage_height()
	_fitting_salvage = false


func _fit_salvage_height() -> void:
	# ⚠️⚠️ 这里**必须用确定性算式**，⛔ 绝不能读 `get_combined_minimum_size()`。
	#
	#    实测踩过：同一个 `_salvage_section`，在「刚填完行、还没走布局」那一刻
	#    返回 958，两帧后收敛到 181 —— 而 `refresh_salvage()` 恰好落在前者。
	#    后果是**窗高被设成 1054**（几乎顶满 1080 屏幕），
	#    这正是用户报的「结算页面做得太长了」。
	#    ⇒ 高度必须由**已知的行数与常量**算，不看容器的实时最小尺寸。
	var h := RESULT_HEAD_H + _title_grow()
	if _salvage_section.visible:
		h += SALVAGE_FIXED_H
		if _salvage_list.visible:
			# ★ 2026-10-30：改成「按列数折成行数」再乘行高（网格化之后，
			#   一艘一行的旧算法会把窗高算成 2 倍，底部留一条大白）。
			h += _salvage_list_h_now()
		if _salvage_queue.visible:
			h += 14.0          # 队列行
	# ★★ 2026-10-25（真机「打捞列表看不见」）：上面这个算式里的常量是按
	#   **桌面字号 110%** 标定的；移动端字号档是 **120%**，同一段内容实际比它高
	#   （实测 4 艘：算式 367 vs 实际 367+? ⇒ content 367 > 宿主 339，底部 28px
	#   连同打捞列表一起被 `_content_host.clip_contents` 裁掉）。
	#   ⇒ 取「算式」与「内容真实最小高」的**较大值**：算式保证不会因为刚填完行、
	#     布局还没跑而读到失控值（那是 `get_combined_minimum_size` 曾经的坑，
	#     根因是 autowrap，已拆除）；真实最小高负责兜住字号档 / 平台差异。
	#   ⛔ 别只留实时最小高 —— 别的平台/字号下它仍可能在未排版的那一帧偏小。
	h = maxf(h, content.get_combined_minimum_size().y)
	set_window_height(h + RESULT_CHROME_H)


## 把两行 `make_stat_row` 并排放进一个 HBox（各占一半）。
##
## ★ 2026-10-04 二改：结算页原来「战果」「收益」各占两行，压短后各并成一行。
## ⚠️ 行对象**原样搬进外层 HBox**（不重新 `make_stat_row`）——
##    `_stat()` 靠 `row.get_child(1)` 改值，换了容器就会静默改错控件。
func _pair_hbox(a: Control, b: Control) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(a)
	box.add_child(b)
	return box


func _num_label(fs: int, col: Color) -> Label:
	var l := Label.new()
	FONT.fs(l, fs)
	l.add_theme_color_override("font_color", col)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


# ------------------------------------------------------------------ 对外

## 显示一次结算。
##
## res 必须是 `EveRunState.resolve_battle()` 的**原始返回值**（唯一真相源），
## 外加场景侧补充的几个字段：
##   res = {"damage": int, "beacon": int, "won": bool, "wreck": bool,
##          "beacon_before": int, "leaked": int, "destroyed": int,
##          "alive": int, "total": int, "xp": int, "node": int,
##          "stage": String, "wreck_name": String, "ending": String}
##
## ⚠️ `beacon_before` 必须由主控传：`resolve_battle()` 已经就地改过 `beacon`，
##    返回值里的 `beacon` 是**结算后**的值，光凭它算不出差额。
## 联机名次结算。
##
## rows = [{name, hp, is_ai, alive}]，已按名次排好。
## 单机那套信标/残骸/打捞区全部隐藏 —— 多人局里它们没有意义。
func show_versus_ranking(rows: Array, round_label: String) -> void:
	visible = true
	_title.text = T.t("VERSUS_OVER", "联机对战结束")
	_title.add_theme_color_override("font_color", C_ACCENT)
	_subtitle.text = "第 %s 回合收束 · 最后存活者胜" % round_label
	# 隐藏单机内容
	var stats := _title.get_parent()
	if stats != null:
		for ch in stats.get_children():
			if ch == _title or ch == _subtitle or ch == _rank_box:
				continue
			if ch is Control:
				(ch as Control).visible = false
	# 名次表
	for ch in _rank_rows.get_children():
		ch.queue_free()
	_rank_box.visible = true
	for i in rows.size():
		var r = rows[i]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var no := Label.new()
		no.text = "%d." % (i + 1)
		no.custom_minimum_size = Vector2(26, 0)
		FONT.fs(no, 13)
		var alive := bool(r.get("alive", false))
		no.add_theme_color_override("font_color", C_ACCENT if alive else C_TEXT_FAINT)
		row.add_child(no)
		var nm := Label.new()
		var tg := "[AI] " if bool(r.get("is_ai", false)) else ""
		nm.text = tg + String(r.get("name", "?"))
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		FONT.fs(nm, 13)
		nm.add_theme_color_override("font_color", C_TEXT if alive else C_TEXT_FAINT)
		row.add_child(nm)
		var hp := Label.new()
		hp.text = ("存活 %d" if alive else "淘汰 %d") % int(r.get("hp", 0))
		hp.custom_minimum_size = Vector2(78, 0)
		hp.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		FONT.fs(hp, 13)
		hp.add_theme_color_override("font_color", C_OK if alive else C_HULL)
		row.add_child(hp)
		_rank_rows.add_child(row)
	# 按钮：联机只有「再来一局」
	_next_btn.text = T.t("VERSUS_AGAIN", "再来一局")
	_next_btn.disabled = false
	if _end_btn != null:
		_end_btn.visible = false


func show_result(res: Dictionary) -> void:
	_data = res.duplicate(true)
	var won := bool(res.get("won", false))

	_title.text = T.t("RESULT_WIN", "拦截成功") if won \
			else T.t("RESULT_LOSE", "拦截失败")
	_title.add_theme_color_override("font_color", C_OK if won else C_HULL)

	# 结束原因（敌方全灭 / 我方全灭 / 时限耗尽 / 未部署）——
	# ★ 玩家看结算时唯一能回答「为什么会漏网」的一行。
	var reason := String(res.get("reason", ""))
	_subtitle.text = T.t("RESULT_SUB_FMT", "节点 %d / 15 · %s%s") % [
		int(res.get("node", 1)),
		res.get("stage", T.t("RESULT_STAGE_SKIRMISH", "遭遇战")),
		"" if reason.is_empty() else " · " + reason]

	_beacon_before.text = str(int(res.get("beacon_before", 0)))
	var after := int(res.get("beacon", 0))
	_beacon_after.text = str(after)
	var dmg := int(res.get("damage", 0))
	_beacon_delta.text = "−%d" % dmg if dmg > 0 else "±0"
	_beacon_delta.add_theme_color_override("font_color",
			C_WARN if dmg > 0 else C_TEXT_FAINT)
	# 信标读数直接复用顶条的色带口径（>60% 绿 / >30% 橙 / 其余红），
	# 保证「顶条上那个数」和「结算页上那个数」颜色一致。
	var ratio := float(after) / maxf(1.0, float(res.get("beacon_max", 100)))
	_beacon_after.add_theme_color_override("font_color",
			C_OK if ratio > 0.60 else (C_WARN if ratio > 0.30 else C_HULL))

	_stat(_kill_row, T.t("RESULT_SHIPS_N", "%d 艘") % int(res.get("destroyed", 0)))
	_stat(_alive_row, "%d / %d" % [int(res.get("alive", 0)), int(res.get("total", 0))])
	_stat(_xp_row, "+%d" % int(res.get("xp", 0)))
	if bool(res.get("wreck", false)):
		# ★ 2026-10-04 多选：收益行只报**数量**，逐艘的选择在页面下方的打捞区。
		_stat(_loot_row, T.t("RESULT_WRECK_N", "%d 艘待打捞") % int(res.get("wreck_count", 1)))
		_loot_row.get_child(1).add_theme_color_override("font_color", C_ARMOR)
	else:
		_stat(_loot_row, T.t("RESULT_NONE", "无"))
		_loot_row.get_child(1).add_theme_color_override("font_color", C_TEXT_FAINT)
	# ⚠️ 结局页（ENDING）不给打捞区：那时局已经结束了，
	#    摆个按钮在那儿点了也没用（打捞要在战斗结算页做，而结局页不是）。
	#    ⛔ 这里**不能**顺手调 `refresh_salvage(res)`：入参 `res` 是**结算 payload**，
	#    形状是 {won, beacon, wreck_count, …}，**没有** `state` / `items` ——
	#    拿它当 `salvage_info()` 用会让打捞区永远显示「空」。
	#    打捞数据必须由主控另推（`_refresh_salvage_area()`，入参是真正的 info）。

	# 结局已经发生（信标归零 / 打完节点 15）时，「继续下一节点」是错的按钮：
	# 那时候点下去只会什么都不发生（RunState.advance 在 ENDING 阶段直接 return）。
	# 所以换成「再来一局」，并且**去掉**「结束本局」——两个按钮做同一件事很蠢。
	var ending := String(res.get("ending", ""))
	if ending != "":
		# ★ 2026-10-31（用户定案）：通关标题从「遥望边境已肃清」改成
		#   「守卫成功，增援已到」—— 原句是**叙事描述**，玩家读完不知道自己赢了；
		#   新句先说结果（守卫成功）再说后续（增援已到），既有结论又留了钩子。
		_title.text = T.t("RESULT_ENDING_CLEARED", "守卫成功，增援已到") if ending == "cleared" \
			else T.t("RESULT_ENDING_BEACON", "信标归零 · 撤离")
		_title.add_theme_color_override("font_color",
				C_OK if ending == "cleared" else C_HULL)
		_next_btn.text = T.t("RESULT_AGAIN", "↻ 再来一局")
		_end_btn.visible = false

	# ★★ 2026-10-27 联机对战：结算页**只有打捞**，没有任何推进按钮。
	#    推进由回合倒计时决定 —— 「打完时倒计时也结束了，就没时间选打捞了」，
	#    这是设计上的心理博弈，不是遗漏。
	#    ⛔ 单机 ⛔ 不要动，只在 versus 里生效。
	if _versus_mode:
		_next_btn.visible = false
		if _end_btn != null:
			_end_btn.visible = false
		_subtitle.text = T.t("RESULT_VERSUS_WAIT",
				"联机对战 · 倒计时结束自动进入下一回合（只可打捞）")


## 联机对战开关：结算页只留打捞，推进交给回合倒计时。
## ⚠️ 只在 versus 模式调；单机一律保持 false。
func set_versus_mode(on: bool) -> void:
	_versus_mode = on


## 改右侧数值标签（make_stat_row 的第 2 个子节点）
func _stat(row: HBoxContainer, text: String) -> void:
	if row.get_child_count() >= 2:
		(row.get_child(1) as Label).text = text


## 最近一次的结算数据（验收脚本读它）
func result_data() -> Dictionary:
	return _data
