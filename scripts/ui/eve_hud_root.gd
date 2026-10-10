extends Control
class_name EveHudRoot

## ★ 字号缩放（2026-10-07）：⛔ 别直接调 `add_theme_font_size_override`，
## 一律走 `FONT.fs(node, 设计字号)` —— 它同时记住设计字号（供改滑块时就地重算）。
## ⚠️ 子类（`extends eve_window.gd` 的那 9 个）靠**继承**拿到这个常量，
##    它们自己再写一个会撞名（基类已有同名成员 ⇒ 子类编译失败，本工程踩过）。
const FONT := preload("res://scripts/ui/eve_font.gd")
## ★ 2026-10-11（i18n）：文案取词（见 `eve_text.gd` 顶注）。
const T := preload("res://scripts/core/eve_text.gd")
## ★ 非 16:9 分辨率下的**内容居中偏移**（`origin()`）+ 设计空间唯一真相源。
## ⚠️ 桌面端原本「布局是死坐标、与视口无关」；有了分辨率档之后这句话不再成立 ——
##    1920×1200 这类档会让设计空间比基准大，内容必须整体居中（见 EveLayout 顶注）。
const LAYOUT := preload("res://scripts/ui/eve_layout.gd")

## EVE 自走棋 —— HUD 根节点（V3 布局稿实装版）
##
## ══════════════════════════════════════════════════════════════════
##  默认位（1920 × 1080）—— 与设计稿 v3.html 的坐标一一对应
## ══════════════════════════════════════════════════════════════════
##    顶条 · 舰队指挥      620,   6,  680,  40   裸条，无标题栏
##    左上 · 舰队构成        8,  56,  172, 268
##    左下 · 装备栏位        8, 336,  172, 116
##    右上 · 舰船档案     1740,  56,  172, 128   默认收起；点选后 320 高
##    右下 · 战斗日志     1740, 384,  172, 200
##    底中 · 商店          389, 908, 1142, 158
##    备战席格带（非窗口）  360, 760, 1200, 140
##
##  UI 面积 ≈ 19.5%（云顶之弈实测 18.7%，上一版 51.2%）
##  中央纯空旷区 = 1560 × 792 全留给星空与场景（以后放建筑 / 矿石）
##
## ── 三条不可回退的约定（都来自用户逐条下达的规格）────────────────
##   ① 所有信息功能栏都是【可拖动 / 可缩放的独立窗口】（EVE 式）。
##      标题栏即拖动手柄，右下角三角即缩放柄，窗口之间留缝露出天空。
##   ② 天空盒必须看得见（满屏、原图直出亮度）；棋盘格子默认不显示。
##   ③ 备战席【不是窗口】，但也**不再是裸刻度线**（2026-09-22 改版）：
##      它是一排 8 个看得见的方格，紧贴棋盘近端、整体微微上浮（悬空分层）。
##      **格子里画的是 2D 立绘**（2026-09-23 改版，见下），不是 3D 模型。
##
## ⚠️ 2026-09-23 备战席改版（用户口径：「把备战席的船也改为 2D 立绘卡牌吧，
##    现在这样特别别扭，尤其是放上去的模型朝向还不一样」）：
##      船的呈现方式：EveBenchStage（3D 模型层）→ **EveBenchRail 内画官方立绘**
##      · 立绘 = res://assets/ships/<id>.png，与商店卡片同一套、同一主键
##      · 3D 层停用（EveBenchStage 文件保留，回退方法见该文件与
##        EveBattleArena._ready() 里的注释）
##      · 顺带把 HIT_ABOVE 48 → 10（立绘不再伸到格子外）
##
##      这一改解决的：① 压暗（HUD 格底曾把 3D 船蒙黑）、② 清晰度。
##      ⚠️ **它没有解决朝向** —— 官方 render 图的机位固定、但 52 艘船的
##         模型自身朝向各不相同，所以立绘本身就有「正视 / 侧视」两种构图
##         （实测：横构图 bbox 约 439×294，竖构图约 336×439）。
##         要看全貌跑 tools/probe_ship_art.tscn。
##
## ⚠️ 2026-09-22 备战席改版（用户口径：「把备战席和棋盘放到一个位置，
##    做得明显大一点，做得不一样一点」）：
##      旧：RECT_BENCH(389, 838, 1142,  52) —— 一条两端渐隐的裸轨道线
##      新：RECT_BENCH(360, 760, 1200, 140) —— 8 个方格 + 顶部金色层高线
##    纵向排布（1080 高，底部留 14px 边距）：
##      棋盘区 55..760（3D）→ 格带 760..900 → 缝隙 8 → 商店 908..1066
##    ⚠️ 商店同时从 168px 压到 158px（卡面 56→50、按钮 26→24），否则格带吃不下。
##      商店内容的最小高度需求约 128~135px，158 仍有富余。
##
##    ⚠️ 宽度取 1200（而不是"铺满整屏 1920"）是**美学判断**，不是省事：
##      棋盘在布阵取景下投影宽 1055px（单格 96px，见
##      EveBattleArena.BOARD_VIEW_ZOOM）。格带铺满 1920 会比棋盘宽 865px，
##      读起来是「棋盘坐在一条过长的台上」；1200 只宽 145px，
##      两者看起来才像同一块地上的两层。单格 150px 也比旧版的 142.8px 略大。
##      ⚠️ 做到「格带单格 = 棋盘单格」是不可能的：那需要格带宽 768px
##      （8 × 96），反而比旧版窄一半 —— 因为棋盘横向被纵向高度（710px）锁死了。
##
## 变更清单（实装版）：
##   - 六窗 + 一条轨道，全部按 V3 坐标落位
##   - demo_content：一键填演示数据（装备 / 商店卡 / 日志 / 羁绊），
##     让首次启动就能看到完整形态；接真实玩法时置 false
##   - 商店的「拿起备战舰船 → 整块化作出售区」链路已打通（set_selling）

# ── V3 默认位（改这里就等于改默认布局）────────────────────────────
#
# ⚠️ 2026-09-20 阶段 A：顶条从 620,6,680,40 加宽到 560,6,800,40。
#    加宽的唯一原因是**信标上了顶条**（交接文档 §11 P0：
#    它是一局的生命线，必须在场，否则「失败」没有载体），
#    顺带给计时段加了阶段名（准备 / 交战 / 结算）。
#    中心仍是 960（560 + 800/2），左右各让出 60px，仍不足屏宽一半。
#    后面再往顶条塞东西之前，先算一次「UI 面积占屏比」（当前 19.x%）。
const RECT_TOP := Rect2(560, 6, 800, 40)
const RECT_SYN := Rect2(8, 56, 172, 268)
const RECT_EQ := Rect2(8, 336, 172, 116)
const RECT_INFO := Rect2(1740, 56, 172, 128)
const RECT_LOG := Rect2(1740, 384, 172, 200)
const RECT_SHOP := Rect2(389, 908, 1142, 158)
const RECT_BENCH := Rect2(360, 760, 1200, 140)

# ── 阶段 C 新增的两块（2026-09-20）──────────────────────────────────
#
# ⚠️ RECT_AUG 接在左列已有的两窗下面（8, 336..452 → 8, 460）：
#    左列在 V3 稿里 452..838 是空的，所以它是**唯一**既在左列、
#    又不挤压现有窗口的位置，而且补上了左列「有头无尾」的观感。
#    它默认**隐藏**（没拿到增益时不占屏），所以开局占屏比与 V3 的 19.3% 一致。
#
# ⚠️ RECT_EVENT 是全局唯一的**打断式决策面板**：4 张卡横排居中压在战场上。
#    它不算「功能区」——功能区是常驻的，它一局只出现三次、每次点一下就消失。
#    y 取 292（而不是正中 540-186=354）是为了把底部备战席 / 商店那一带留干净，
#    让「面板浮在海盗船与星空之上」这层关系一眼看得懂。
const RECT_AUG := Rect2(8, 460, 172, 140)
## 高度 296 是**按内容反推**的：标题栏 26 + 上内距 6 + 引导语 16 + 间距 6
## + 卡片 215 + 间距 6 + 脚注 13 + 下内距 8 ≈ 296。
## ⚠️ 别再随手调大 —— `EveWindow` 修好 `_content_margin` 的扩张之后，
##    卡片会**吃掉所有富余高度**，窗高给多 100px 就是卡片里多 100px 空洞。
const RECT_EVENT := Rect2(460, 300, 1000, 296)

# ── 阶段 D 新增的两块（2026-09-20）──────────────────────────────────
#
# 结算页：居中、比事件面板窄（它是「读一屏数字」，不是「四选一」）。
# 宽 420 / 高 356 是按内容反推的（规则 11）：
#   标题栏 26 + 内距 6 + 结论 30 + 副标题 14 + 分隔 1 + 间距 7
#   + 信标行 30 + 分隔 1 + 战果 3×18 + 分隔 1 + 收益 2×18 + 分隔 1 + 按钮 28 + 下内距 8 ≈ 356
# ⚠️ 别再随手调大 —— EveWindow 的 _content_margin 修好 EXPAND 之后，
#    富余高度会被内容吃掉，给多 100px 就是窗里的空洞（本工程的既有教训）。
const RECT_RESULT := Rect2(750, 330, 420, 356)

# 设置窗：靠左中，不压战场中心（玩家开着它多半还想看画面变化）。
#
# ⚠️ 宽度 320（原 248）是 2026-09-28 加音量滑杆 + 暂停按钮之后必须的：
#    一行「标签 + 滑杆 + 百分比」最少要 ~300px，248 会把滑杆压成一条缝。
# ⚠️ 高度**只是初值** —— 设置窗自己会在 _ready 里按内容反推（`_fit_height`），
#    这里写 480 是为了让「布局还没跑完的那一帧」不至于塌成一团。
const RECT_SETTINGS := Rect2(196, 250, 320, 480)

# 备战席格数（与 EveBenchRail.SLOTS 对齐）
const BENCH_SLOTS := 8

var command_bar: EveWindow            ## 顶条
var synergy_window: EveWindow         ## 左上：舰队构成
var equipment_window: EveWindow       ## 左下：装备栏位
var augments_window: EveWindow        ## 左中：事件增益（阶段 C；无增益时隐藏）
var dossier_window: EveWindow         ## 右上：舰船档案
var log_window: EveWindow             ## 右下：战斗日志
var shop_window: EveWindow            ## 底中：商店
var event_window: EveWindow           ## 居中：事件四选一（阶段 C；平时隐藏）
## 居中：节点结算页（阶段 D；平时隐藏）
var result_window: EveWindow = null

## 设置窗（阶段 D；平时隐藏，点顶条 ≡ 打开）
var settings_window: EveWindow = null
## 全屏暂停遮罩（阶段 D+；平时隐藏）。见 `set_paused()` 的口径说明。
var pause_veil: Control = null
var bench_rail: EveBenchRail          ## 备战席轨道（非窗口）
## 伤害数字层（阶段 D）—— 屏幕空间的飘字，压在所有窗口之上、幽灵之下。
var damage_feed: Control = null
## 节点进场词横幅（阶段 C 收尾）—— 同样压在所有窗口之上、飘字之下。
var entry_banner: Control = null

## 首次启动是否填演示数据。
##
## ⚠️ 2026-09-20（阶段 A）默认改为 **false**：真实数据已经接上了
##    （EveRunState 喂商店 / 经济 / 备战席 / 羁绊 / 日志），
##    再默认打开演示数据就等于「开局先骗玩家一次」。
##    想看 V3 稿的满配形态时，把 run 的 demo_content 打开即可 ——
##    它仍然遵守「只填还没有真实数据的窗口」这条规则。
@export var demo_content: bool = false

## 按钮皮肤（沿用 EveButtonTheme 的可替换机制）
@export_enum("default", "accent", "plain", "hud", "hud_main", "hud_warn")
var button_skin: String = "hud"

signal start_battle_requested()
signal settings_requested()
signal shop_buy_requested(offer_index: int)
signal shop_refresh_requested()
signal shop_levelup_requested()
signal shop_lock_toggled(on: bool)
signal salvage_requested()
## 顶条倒计时归零（准备阶段到点 / 战斗时限到点）
signal stage_timer_expired()
## 事件四选一：玩家点了某一条（id = EveEventTable 的主键）
signal event_option_chosen(id: StringName)
## 事件「选 1 艘船」：玩家点了第 index 艘（对应 `show_ship_pick` 传进来的数组）
signal event_ship_picked(index: int)

# ── 阶段 D 新增 ──
## 结算页：继续下一节点 / 结束本局
signal result_next_requested()
signal result_end_requested()
## ★ 打捞区（2026-10-04 改版：按钮在结算页**下方**，逐艘直接点「打捞」）。
##   · 点某一艘的「打捞」按钮（参数 = 残骸下标）
##   · 零选二次确认通过（「确定放弃本回合全部残骸」）
signal salvage_pick_one(idx: int)
signal salvage_pick_zero()
signal salvage_section_closed()      ## 点「关闭」收起打捞区
## 设置窗
signal settings_closed()
signal settings_background_changed(id: String)
signal settings_mood_changed(mode: int)
signal settings_fog_toggled(on: bool)
signal settings_board_toggled(on: bool)
signal settings_camera_reset()
signal settings_restart()
## 设置窗「放弃本局 · 回主界面」→ 主控切回主菜单
signal settings_back_to_menu()
## 设置窗的暂停 / 继续。`on = true` = 请求暂停（主控才是真相源）。
signal settings_pause_toggled(on: bool)
## 音量滑杆。`kind` = &"master" / &"sfx" / &"amb" / &"music"
signal settings_volume_changed(kind: StringName, v: float)
## 静音开关
signal settings_mute_toggled(on: bool)
## 暂停遮罩上的「继续」按钮 —— 暂停期间设置窗可以被关掉，
## 那时鼠标唯一能点的东西就是它（否则玩家只能靠空格脱身）。
signal pause_resume_requested()
## ⚠️ DEBUG-ONLY: 调试期加币信号，发布时删除
signal settings_add_coins(amount: int)

## 全刷请求 —— 调试按钮 / 自动化脚本（探针 / 录制回放）调 `hud.refresh()` 触发，
## 主控接住后调自己的 `_refresh_run_ui()`。解耦 hud 与主控类型。
signal refresh_requested()

# 以下两个为兼容旧调用方保留：新布局里姿态与圆环开关没有落位（V3 稿没有这两块），
# 设置页会接管它们。信号先留着，免得旧代码连不上。
signal stance_changed(ship: EveShip, stance: int)
signal range_rings_toggled(enabled: bool)

const COMMAND_BAR_SCRIPT := preload("res://scripts/ui/panels/eve_command_bar.gd")
const SYNERGY_SCRIPT := preload("res://scripts/ui/panels/eve_fleet_synergy.gd")
const EQUIPMENT_SCRIPT := preload("res://scripts/ui/panels/eve_equipment.gd")
const DOSSIER_SCRIPT := preload("res://scripts/ui/panels/eve_ship_dossier.gd")
const LOG_SCRIPT := preload("res://scripts/ui/panels/eve_combat_log.gd")
const SHOP_SCRIPT := preload("res://scripts/ui/panels/eve_shop.gd")
const BENCH_SCRIPT := preload("res://scripts/ui/panels/eve_bench.gd")
const AUGMENTS_SCRIPT := preload("res://scripts/ui/panels/eve_augments.gd")
const EVENT_SCRIPT := preload("res://scripts/ui/panels/eve_event.gd")
const DAMAGE_FEED_SCRIPT := preload("res://scripts/ui/eve_damage_feed.gd")
## 节点进场词横幅（阶段 C 收尾）—— 瞬时元素，见 eve_entry_banner.gd 的口径说明
const ENTRY_BANNER_SCRIPT := preload("res://scripts/ui/eve_entry_banner.gd")
const SETTINGS_SCRIPT := preload("res://scripts/ui/panels/eve_settings.gd")
const RESULT_SCRIPT := preload("res://scripts/ui/panels/eve_result.gd")
## ★ 平台 UI 缩放档（2026-10-07）。⛔ 用 preload 常量而不是裸写 class_name
##   —— 新 class_name 要等 .godot 重扫才注册得上（红线 22）。
const UI_SCALE_SCRIPT := preload("res://scripts/ui/eve_ui_scale.gd")

var _selected_ship: EveShip = null
var _fleet: Array = []
var _demo_used := false
var _drag_ghost: _DragGhost = null


func _ready() -> void:
	# ⚠️ 必须铺满整个视口。裸 Control 若不设锚点，size 就是 0×0，
	#    所有子窗口会塌缩到原点（实测现象：整个 HUD 只剩一个 40px 小方块）。
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS
	_build_layout()
	# ★ 设计空间变了（设备旋转 / 换分辨率 / 切缩放档）⇒ 紧凑档要重铺一遍。
	#   桌面端 `_on_resized()` 会立刻返回 —— 它的布局是设计稿的绝对坐标，
	#   跟视口无关（这也是「Windows 端逐像素不变」的一部分）。
	resized.connect(_on_resized)
	if demo_content:
		_apply_demo_content()


func _build_layout() -> void:
	# ① 备战席轨道（先加，让它落在最底层：窗口永远压在它上面）
	bench_rail = BENCH_SCRIPT.new()
	bench_rail.name = "BenchRail"
	bench_rail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bench_rail)
	bench_rail.set_anchors_preset(Control.PRESET_TOP_LEFT)
	# 位置/尺寸由 `_apply_rects()` 统一铺（档位表决定）

	# ② 顶条
	command_bar = COMMAND_BAR_SCRIPT.new()
	command_bar.name = "CommandBar"
	add_child(command_bar)
	command_bar.start_battle_requested.connect(func(): start_battle_requested.emit())
	command_bar.settings_requested.connect(func(): settings_requested.emit())
	command_bar.timer_expired.connect(func(): stage_timer_expired.emit())

	# ③ 左上：舰队构成
	synergy_window = SYNERGY_SCRIPT.new()
	synergy_window.name = "FleetSynergy"
	add_child(synergy_window)
	synergy_window.set_status(T.t("HUD_TRAITS", "羁绊"))

	# ④ 左下：装备栏位
	equipment_window = EQUIPMENT_SCRIPT.new()
	equipment_window.name = "Equipment"
	add_child(equipment_window)

	# ④b 左中：事件增益（阶段 C）—— 默认隐藏，拿到第一条增益才现身
	augments_window = AUGMENTS_SCRIPT.new()
	augments_window.name = "Augments"
	add_child(augments_window)
	augments_window.visible = false

	# ⑤ 右上：舰船档案（默认收起）
	dossier_window = DOSSIER_SCRIPT.new()
	dossier_window.name = "ShipDossier"
	add_child(dossier_window)

	# ⑥ 右下：战斗日志
	log_window = LOG_SCRIPT.new()
	log_window.name = "CombatLog"
	add_child(log_window)

	# ⑦ 底中：商店
	shop_window = SHOP_SCRIPT.new()
	shop_window.name = "Shop"
	add_child(shop_window)

	shop_window.buy_requested.connect(func(i: int): shop_buy_requested.emit(i))
	shop_window.refresh_requested.connect(func(): shop_refresh_requested.emit())
	shop_window.levelup_requested.connect(func(): shop_levelup_requested.emit())
	shop_window.lock_toggled.connect(func(on: bool): shop_lock_toggled.emit(on))
	shop_window.salvage_requested.connect(func(): salvage_requested.emit())

	# ⑧ 居中：事件四选一（阶段 C）
	#
	# ⚠️ 顺序要紧：它要压在商店 / 备战席之上（事件节点玩家仍可以整理舰队，
	#    但点面板时不能被商店的卡片抢走点击），同时又要被拖动幽灵压住。
	#    所以位置是「商店之后、幽灵之前」。
	event_window = EVENT_SCRIPT.new()
	event_window.name = "EventChoice"
	add_child(event_window)
	event_window.visible = false
	event_window.option_chosen.connect(func(id: StringName): event_option_chosen.emit(id))
	event_window.ship_picked.connect(func(i: int): event_ship_picked.emit(i))

	# ⑨ 居中：结算页（阶段 D）—— 默认隐藏，战斗结束时上台。
	#
	# ⚠️ 它必须**压过事件面板**（两者都是居中大窗，理论上不会同时出现，
	#    但「不可能同时出现」这种假设不值得靠顺序之外的东西保证）。
	result_window = RESULT_SCRIPT.new()
	result_window.name = "Result"
	add_child(result_window)
	result_window.visible = false
	result_window.next_requested.connect(func(): result_next_requested.emit())
	result_window.end_requested.connect(func(): result_end_requested.emit())
	# ★ 打捞区接两条信号（2026-10-04 改版：逐艘点，没有浮层了）
	result_window.salvage_pick_requested.connect(
			func(i: int): salvage_pick_one.emit(i))
	result_window.salvage_pick_zero.connect(func(): salvage_pick_zero.emit())
	result_window.salvage_section_closed.connect(
			func(): salvage_section_closed.emit())

	# ⑩ 设置窗（阶段 D）—— 默认隐藏，点顶条 ≡ 打开。
	settings_window = SETTINGS_SCRIPT.new()
	settings_window.name = "Settings"
	add_child(settings_window)
	settings_window.visible = false
	settings_window.background_changed.connect(func(id: String): settings_background_changed.emit(id))
	settings_window.mood_changed.connect(func(m: int): settings_mood_changed.emit(m))
	settings_window.fog_toggled.connect(func(on: bool): settings_fog_toggled.emit(on))
	settings_window.range_rings_toggled.connect(func(on: bool): range_rings_toggled.emit(on))
	settings_window.board_toggled.connect(func(on: bool): settings_board_toggled.emit(on))
	settings_window.camera_reset_requested.connect(func(): settings_camera_reset.emit())
	settings_window.run_restart_requested.connect(func(): settings_restart.emit())
	settings_window.back_to_menu_requested.connect(func(): settings_back_to_menu.emit())
	settings_window.pause_toggled.connect(func(on: bool): settings_pause_toggled.emit(on))
	settings_window.volume_changed.connect(func(kind: StringName, v: float):
			settings_volume_changed.emit(kind, v))
	settings_window.mute_toggled.connect(func(on: bool): settings_mute_toggled.emit(on))
	# ★ 2026-10-10：设置窗标题栏的 ✕ 按下也会发 `closed` ⇒ 这里统一收口成
	#   「隐藏 + 转发」。hide_settings() 是唯一入口（三场景共用）。
	settings_window.closed.connect(func():
			hide_settings()
			settings_closed.emit())
	# ★ 缩放档：HUD 自己消化（见 `_on_ui_scale_picked` 的说明）
	settings_window.ui_scale_changed.connect(_on_ui_scale_picked)
	# ★ 字号变了 ⇒ 底部两条要按新字高重新上抬（字体本身由设置窗 reapply）
	settings_window.font_scale_changed.connect(_on_font_scale_changed)
	# ★ 分辨率变了 ⇒ 重铺（非 16:9 的档会改居中偏移，见 `on_resolution_changed`）。
	#   ⚠️ 窗口尺寸由**设置窗自己**改（`EveResolution.apply_index`），这里只负责重铺；
	#      不看那个信号也行（`resized` 会来），但**两条路重复重铺一次**比
	#      「刚好漏掉"清拖动记录"那一步」安全 —— 后者表现为窗停在半路上，极难查。
	settings_window.resolution_changed.connect(func(_i: int): on_resolution_changed())
	# ⚠️ DEBUG-ONLY: 加币信号转发（与 settings_window.add_coins_requested 同源）
	# 发布时**整组删除**（按钮 / signal / connect 三处一致删）。
	settings_window.add_coins_requested.connect(func(amt: int): settings_add_coins.emit(amt))

	# ⑪ 伤害数字层（阶段 D）—— 屏幕空间飘字。
	#
	# ⚠️ 位置很讲究：**在窗口之后、拖动幽灵之前**。
	#    在窗口之前的话，飘字会被商店窗盖住（而战斗时玩家就盯着战场中央，
	#    那里恰好是商店窗上方）；在幽灵之后的话，拖动时飘字会盖住手上的卡。
	damage_feed = DAMAGE_FEED_SCRIPT.new()
	damage_feed.name = "DamageFeed"
	add_child(damage_feed)

	# ⑫ 节点进场词横幅（阶段 C 收尾）
	#
	# ⚠️ 加在飘字**之前**：两者极少同时出现（横幅在准备阶段入口、飘字在交战），
	#    万一撞上，让伤害数字压在上面 —— 战斗中的读数永远优先于氛围字幕。
	entry_banner = ENTRY_BANNER_SCRIPT.new()
	entry_banner.name = "EntryBanner"
	add_child(entry_banner)

	# ⑫b 暂停遮罩（阶段 D+）—— 默认隐藏。
	#
	# ⚠️ 位置必须在【所有窗口之后】，否则它遮不住商店 / 备战席 ——
	#    那就成了「暂停了还能买船」。同时必须在【拖动幽灵之前】：
	#    幽灵是手上的东西，任何遮罩都不该盖住它（虽然暂停时不会在拖）。
	pause_veil = _build_pause_veil()
	add_child(pause_veil)

	# ⑬ 拖动幽灵（阶段 B）—— 最后加 + 常驻最前，保证它压在所有窗口之上
	_drag_ghost = _DragGhost.new()
	_drag_ghost.name = "DragGhost"
	_drag_ghost.visible = false
	add_child(_drag_ghost)

	# ★ 全部窗建完 ⇒ 按当前档位统一铺一遍矩形。
	#   ⚠️ 必须在**最后**：窗建到一半时 `_win_of()` 还会拿到 null。
	#   ⚠️⚠️ 走 `refresh_layout()` 而**不是** `_apply_rects()` ——
	#      后者只铺、不算档位表。少了「先算表」这一步，
	#      `_r()` 全部回落 `RECT_TOP` ⇒ **十扇窗叠在顶条上**（实测踩过），
	#      而且 `_rect_tbl` 为空会让「档位没变就早退」那道守卫失效。
	refresh_layout()


# ------------------------------------------------------------------ 平台档位（2026-10-07）

## 是不是「紧凑档」。
## ⚠️ 桌面端**恒 false** ⇒ `_rect_tbl` 逐项等于 `RECT_*` ⇒ 布局与从前逐像素一致。
var _compact := false
## 当前生效的缩放倍数（1.0 = 设计稿原尺寸）
var _ui_scale := 1.0
## 键 → 实际矩形。`_build_layout()` / `refresh_layout()` 都读它。
## ⛔ 唯一真相源：别在别处直接引用 `RECT_*` 去摆窗 ——
##    那样紧凑档会**静默漏掉那一扇**（窗还在 1080 的坐标上，掉出屏幕）。
var _rect_tbl: Dictionary = {}
## 上次铺矩形时的设计空间（用来判断「视口真的变了」，避免白刷）
var _last_design := Vector2.ZERO
## 上次铺矩形时用的**居中偏移**（非 16:9 分辨率档下不为零，见 `_apply_rects`）。
## ⚠️ 它让 `_on_resized()` 能在**桌面端**判断出「换分辨率档了、要重铺」——
##    没有它，从 1920×1080 切到 1920×1200 时内容会偏在半路上。
var _origin_applied := Vector2.ZERO

## 紧凑档默认收起的侧列。
##
## ⚠️ 是**收起**不是隐藏：点标题栏就能展开，功能一个不少（红线 9：不许摆
##    「看着在、点不了」的东西）。手机屏的纵向是稀缺资源，侧列默认让位给战场。
##
## ⛔ **不许把 `info`（舰船档案）写进来** —— 它自己实现了 128↔320 的收起/展开，
##    在 `_ready()` 里把 `collapsible` 置成了 false（两套收起会互相打架）。
##    写进来是个**静默的空操作**：看着像收了，其实什么都没发生。
##    （它只有 172×128，本来也不占地方。）
const COMPACT_COLLAPSED := ["syn", "eq", "aug", "log"]

## 紧凑档的边距常量（口径与设计稿一致：底部留 14、两条之间留 8）。
const COMPACT_PAD := 12.0
const COMPACT_BOTTOM := 14.0
const COMPACT_GAP := 8.0
## 字号放大时「商店」会长高多少（**实测标定**）。
##
## ⚠️⚠️ 为什么必须有这个数：商店的**矩形**是设计稿写死的 158 高，但它里面的
##    行会被字撑开 ⇒ 实测 1.00 档 **161**、1.30 档 **173**。
##    而它是**贴底**摆的（y 908 + 高）⇒ 高出来的部分直接往屏幕外长：
##    实测 1.30 档底边 **1081 > 1080**，最后一行被切掉。
##    ⇒ 按这个斜率把底部两条整体**上抬**同样的量，底边就钉住不动。
##    代价是战场少一条 —— 这是「只放大字」必然要付的（界面缩放那种整齐放大不会）。
##
## ⚠️ 改字号上限、或改商店内部排版之后，**必须重新量一次**这个斜率
##    （量法：跑 `tools/_probe_font.tscn`，看两次打印的商店 `size.y` 之差）。
const SHOP_FONT_GROW := 40.0

## 底部两条**必须让出**的侧列宽度（左列 8..180，再留 8px 缝）。
## ⚠️ 少了它，窄屏（1.35 档下的 16:9 手机：设计宽只有 1422）上
##    备战席会横着压到装备栏上。
const COMPACT_SIDE := 188.0


## 当前设计空间（= 视口 ÷ 拉伸倍数）。
##
## ⚠️ **实现已收口到 `EveLayout.design_space()`**（唯一真相源）——
##    主菜单 / 牌桌 / 战场三处都要按同一口径算，抄第二份必然漂移。
func _design_space() -> Vector2:
	return LAYOUT.design_space(get_window())


## 紧凑档（移动端）布局 —— **纯函数**：设计空间进、矩形出。
##
## ⚠️ 提成 static 是为了**能单独自检**（verify_ui_scale 直接喂真实手机尺寸，
##    不需要真的跑在安卓上）。这也是本工程「抽单一来源函数」那条惯例。
##
## 与设计稿（`RECT_*`）的区别只有三处，但每一处都是必需的：
##   ① 顶条 / 底部两条**水平居中** —— 手机屏比 16:9 宽，设计稿按 1920 靠左会飘；
##   ② 商店 / 备战席**贴底** —— 设计高不再是 1080，绝对 y 会让它们掉出屏幕；
##   ③ 底部两条**让出侧列宽度** —— 否则窄屏上会横向压到装备栏。
## 侧列（舰队构成 / 装备 / 增益 / 档案 / 日志）**保持设计稿的纵坐标**：
## 它们是收起态的细条（见 `COMPACT_COLLAPSED`），而保持设计稿间距能保证
## 「展开之后彼此仍然不重叠」。
static func compact_rects(d: Vector2) -> Dictionary:
	var w := maxf(640.0, d.x)
	var h := maxf(480.0, d.y)
	# ① 顶条：居中
	var top_w := minf(RECT_TOP.size.x, w - 2.0 * COMPACT_PAD)
	var top := Rect2((w - top_w) * 0.5, RECT_TOP.position.y, top_w, RECT_TOP.size.y)
	# ② 底部两条：先让出侧列宽度，再居中；商店贴底、备战席骑在它头上
	var avail := maxf(320.0, w - 2.0 * COMPACT_SIDE)
	var shop_w := minf(RECT_SHOP.size.x, avail)
	var shop := Rect2((w - shop_w) * 0.5, h - RECT_SHOP.size.y - COMPACT_BOTTOM,
			shop_w, RECT_SHOP.size.y)
	var bench_w := minf(RECT_BENCH.size.x, avail)
	var bench := Rect2((w - bench_w) * 0.5,
			shop.position.y - COMPACT_GAP - RECT_BENCH.size.y,
			bench_w, RECT_BENCH.size.y)
	# ③ 居中的大窗（事件 / 结算 / 设置）：在「顶条以下、备战席以上」这段里居中
	var mid := (RECT_TOP.position.y + RECT_TOP.size.y + bench.position.y) * 0.5
	var ev_w := minf(RECT_EVENT.size.x, w - 2.0 * COMPACT_PAD)
	var res_w := minf(RECT_RESULT.size.x, w - 2.0 * COMPACT_PAD)
	return {
		"top": top,
		"syn": Rect2(RECT_SYN.position, RECT_SYN.size),
		"eq": Rect2(RECT_EQ.position, RECT_EQ.size),
		"aug": Rect2(RECT_AUG.position, RECT_AUG.size),
		"info": Rect2(w - 8.0 - RECT_INFO.size.x, RECT_INFO.position.y,
				RECT_INFO.size.x, RECT_INFO.size.y),
		"log": Rect2(w - 8.0 - RECT_LOG.size.x, RECT_LOG.position.y,
				RECT_LOG.size.x, RECT_LOG.size.y),
		"shop": shop,
		"bench": bench,
		"event": Rect2((w - ev_w) * 0.5, mid - RECT_EVENT.size.y * 0.5,
				ev_w, RECT_EVENT.size.y),
		"result": Rect2((w - res_w) * 0.5, mid - RECT_RESULT.size.y * 0.5,
				res_w, RECT_RESULT.size.y),
		"settings": Rect2((w - RECT_SETTINGS.size.x) * 0.5,
				mid - RECT_SETTINGS.size.y * 0.5,
				RECT_SETTINGS.size.x, RECT_SETTINGS.size.y),
	}


## 按当前档位算出矩形表。
## ⚠️ 桌面分支就是那 11 个 `RECT_*` **原封不动** —— 这是「Windows 端不变」的落点，
##    也正因为它逐项相等，桌面的布局才不需要任何回归验证。
func _refresh_rect_tbl() -> void:
	_last_design = _design_space()
	if _compact:
		_rect_tbl = compact_rects(_last_design)
	else:
		_rect_tbl = {
			"top": RECT_TOP, "syn": RECT_SYN, "eq": RECT_EQ, "aug": RECT_AUG,
			"info": RECT_INFO, "log": RECT_LOG, "shop": RECT_SHOP,
			"bench": RECT_BENCH, "event": RECT_EVENT, "result": RECT_RESULT,
			"settings": RECT_SETTINGS,
		}
	# ★ 字号放大 ⇒ 底部两条整体上抬（两个档位都要，见 `SHOP_FONT_GROW`）。
	#   ⚠️ 放在两个分支**之外**：紧凑档同样是贴底摆的，同样会被字撑出去。
	var g := _bottom_grow()
	if g > 0.01:
		for key in ["shop", "bench"]:
			var r: Rect2 = _rect_tbl[key]
			_rect_tbl[key] = Rect2(r.position.x, r.position.y - g, r.size.x, r.size.y)


## 字号带来的底部抬升量（设计字号档 = 0：⛔ 不能让默认档有一像素漂移）。
func _bottom_grow() -> float:
	return maxf(0.0, (FONT.scale - 1.0) * SHOP_FONT_GROW)


## 取当前档位的矩形（表还没算出来时回落设计稿）。
func _r(key: String) -> Rect2:
	var v = _rect_tbl.get(key)
	return RECT_TOP if v == null else v


## 键 → 窗对象。
func _win_of(key: String) -> EveWindow:
	match key:
		"top": return command_bar
		"syn": return synergy_window
		"eq": return equipment_window
		"aug": return augments_window
		"info": return dossier_window
		"log": return log_window
		"shop": return shop_window
		"event": return event_window
		"result": return result_window
		"settings": return settings_window
	return null


## 把当前档位的矩形铺到所有窗 + 备战席轨道。
##
## ★ 2026-10-07：**加居中偏移** `o` —— 非 16:9 的分辨率档（1920×1200 之类）下
##   设计空间比 1920×1080 大，按死坐标摆的内容会贴在左上、边缘露出空白。
##   ⚠️ 紧凑档**不加**：`compact_rects()` 自己就是按设计空间居中排的，
##      再叠一层就是重复偏移。
##   ⚠️ 偏移记进 `_origin_applied`，`_on_resized()` 靠它判断「桌面端要不要重铺」。
func _apply_rects() -> void:
	if command_bar == null:
		return                       # 还没建（`_ready` 之前）
	if _rect_tbl.is_empty():
		# 防御：正常路径（`_build_layout` / `refresh_layout`）都会先算表。
		# ⛔ 但少了这一道，空表会让每扇窗都摆到 `RECT_TOP`（叠成一堆），
		#    而且**不报任何错** —— 值得一行兜底。
		_refresh_rect_tbl()
	var o := Vector2.ZERO if _compact else LAYOUT.origin(get_window())
	_origin_applied = o
	for key in ["top", "syn", "eq", "aug", "info", "log",
			"shop", "event", "result", "settings"]:
		var w: EveWindow = _win_of(key)
		if w == null:
			continue
		var r := _r(key)
		w.set_window_rect(r.position.x + o.x, r.position.y + o.y, r.size.x, r.size.y)
	if bench_rail != null:
		var b := _r("bench")
		bench_rail.position = b.position + o
		bench_rail.size = b.size
		bench_rail.custom_minimum_size = b.size


## 应用 UI 缩放档。
##
## ⚠️ **只有一个入口**（开局由主控调、玩家改设置由设置窗信号调）——
##    分散成两处必然出现「窗里写着 135%、实际是 125%」。
##
## ⚠️ 档位**真的变了**才会重铺：桌面端主控也会调一次（传 1.0），
##    那时 `_ui_scale` 已经是 1.0 ⇒ 直接返回 ⇒ **一个字节都不动**
##    （否则每次开局都会把玩家的窗口布局重置掉）。
func apply_ui_profile(scale: float) -> void:
	var s := maxf(1.0, scale)
	var compact := UI_SCALE_SCRIPT.is_compact(s)
	var changed := (not is_equal_approx(s, _ui_scale)) or compact != _compact
	_ui_scale = s
	_compact = compact
	var win := get_window()
	if win != null and not is_equal_approx(win.content_scale_factor, s):
		win.content_scale_factor = s
	if not changed and not _rect_tbl.is_empty():
		return
	# 档位变了 ⇒ 先让每扇窗忘掉旧档位下摆的位置。
	# ⚠️ 必须做：设计空间都不一样了，旧坐标留着只会错位
	#（玩家拖动记录是绝对像素，`_effective_rect()` 会优先用它）。
	for key in ["top", "syn", "eq", "aug", "info", "log",
			"shop", "event", "result", "settings"]:
		var w: EveWindow = _win_of(key)
		if w != null:
			w.reset_layout()
	refresh_layout()
	if _compact:
		for key in COMPACT_COLLAPSED:
			var w2: EveWindow = _win_of(key)
			if w2 != null:
				w2.set_collapsed(true)


## 按当前档位重铺一遍（切档位 / 设备旋转 / 设计空间变化）。
func refresh_layout() -> void:
	if command_bar == null:
		return
	_refresh_rect_tbl()
	_apply_rects()


## ★ 玩家换了**窗口分辨率**（设置窗的「显示」分区）⇒ 重铺。
##
## ⚠️ 两件事都要做，少一件都是静默错位：
##   ① **清掉玩家的拖动记录**（`_user_rect` 是绝对像素，基准原点变了之后
##      它指向的位置就不再是玩家想要的那个地方）—— 与 `apply_ui_profile`
##      切档位时的处理同源；顺带也清掉「已收起」的记忆，避免新旧坐标混着用。
##   ② 重铺：偏移 `o` 由 `_apply_rects()` 按**新的**设计空间算。
func on_resolution_changed() -> void:
	for key in ["top", "syn", "eq", "aug", "info", "log",
			"shop", "event", "result", "settings"]:
		var w: EveWindow = _win_of(key)
		if w != null:
			w.reset_layout()
	refresh_layout()


## 设计空间变了 ⇒ 重铺。
##
## ⚠️ 桌面端**原本立刻返回**（布局是设计稿的绝对坐标、与视口无关）。
##    2026-10-07 加了分辨率档之后这条不再完全成立：**非 16:9 的档**会让设计空间
##    比基准大 ⇒ 居中偏移 `o` 变了 ⇒ 必须重铺，否则内容还停在旧偏移上。
##    ⇒ 桌面端只在「偏移真的变了」时重铺。**这一条是本函数的全部要点**：
##      少了它，从 1920×1080 切到 1920×1200 时 HUD 会偏在半路上。
func _on_resized() -> void:
	var o := Vector2.ZERO if _compact else LAYOUT.origin(get_window())
	if o != _origin_applied:
		refresh_layout()
		return
	if not _compact:
		return
	if _design_space().is_equal_approx(_last_design):
		return
	refresh_layout()


## 玩家在设置窗里换了缩放档。
##
## ⚠️ 这个信号**不往主控转发** —— 缩放是 HUD 自己的事：
##    3D 战场跑在原生分辨率上（`canvas_items` 只缩放 2D 画布），
##    所以它不需要任何「跟着改相机」的动作。转发出去只会让两层都以为该管。
func _on_ui_scale_picked(v: float) -> void:
	apply_ui_profile(UI_SCALE_SCRIPT.resolve(v))


## 玩家改了字号。
##
## ⚠️ 分两件事，⛔ 别混在一处：
##    · 「字体本身」由**设置窗**就地 `FONT.reapply()`（它离玩家最近，要即时）；
##    · 「版面」由 HUD 重铺 —— 字号会撑高商店，底部两条得跟着上抬（见 `SHOP_FONT_GROW`）。
func _on_font_scale_changed(_v: float) -> void:
	refresh_layout()



# ------------------------------------------------------------------ 对外接口

## 选中一艘船 → 刷新右上档案窗（同时把它所在舰队喂给羁绊统计）
func show_ship(ship: EveShip) -> void:
	_selected_ship = ship
	if dossier_window and dossier_window.has_method("set_ship"):
		dossier_window.set_ship(ship)


func get_selected_ship() -> EveShip:
	return _selected_ship


## 喂当前场上/备战席的舰队 —— 羁绊窗与档案窗的 n/m 都从这一份算
func set_fleet(ships: Array, fleet_is_demo: bool = false) -> void:
	_fleet = ships
	if fleet_is_demo:
		return
	if synergy_window and synergy_window.has_method("set_fleet"):
		synergy_window.set_fleet(ships)
	if dossier_window and dossier_window.has_method("set_fleet"):
		dossier_window.set_fleet(ships)


func append_log(entry) -> void:
	if log_window and log_window.has_method("append_entry"):
		log_window.append_entry(entry)


func clear_log() -> void:
	if log_window and log_window.has_method("clear_log"):
		log_window.clear_log()


## 商店报价（元素 = EveShipDatabase 出来的 Dictionary）
func set_shop_offers(offers: Array) -> void:
	if shop_window and shop_window.has_method("set_offers"):
		shop_window.set_offers(offers)


## ★ 阶段闸门：只有准备阶段能买卖（2026-10-05）。
##
## ⚠️ 商店面板是**常驻**的（不随阶段显隐），少了这道闸门就会出现
##    「结算/战斗阶段卡片亮着，点了被 run 拒、卡片毫无变化」——
##    玩家理解成「点了没反应、东西也没到手」。
func set_shop_buy_enabled(on: bool) -> void:
	if shop_window and shop_window.has_method("set_buy_enabled"):
		shop_window.set_buy_enabled(on)


## 打捞框。入参 = `EveRunState.salvage_info()` 的输出（**唯一输入源**）：
##   {"state": "wreck", "name": …, "star": …, "cost": …, "price": …}  可下单
##   {"state": "repairing", "name": …, "star": …}                     已下单等到账
##   {}                                                              空
func set_salvage(info: Dictionary) -> void:
	if shop_window:
		shop_window.set_salvage(info)


## 已获取的事件增益（元素 = EveRunState.picked_event_info() 的输出）。
## 空数组 = 整窗隐藏（开局与 V3 稿逐像素一致）。
func set_augments(list: Array) -> void:
	if augments_window and augments_window.has_method("set_augments"):
		augments_window.set_augments(list)


## 打开事件四选一面板。
##
## meta 走标题栏右侧（如「节点 4 · 4 选 1」），line 是节点的进场词。
func show_event(options: Array, line: String = "", meta: String = "") -> void:
	if event_window == null:
		return
	event_window.show_options(options, line, meta)
	event_window.visible = true
	event_window.move_to_front()


## 打开事件「选 1 艘船」面板（与四选一共用同一个窗口，只是换成选船模式）
func show_ship_pick(options: Array, line: String = "", meta: String = "") -> void:
	if event_window == null:
		return
	event_window.show_ship_pick(options, line, meta)
	event_window.visible = true
	event_window.move_to_front()


func hide_ship_pick() -> void:
	if event_window:
		event_window.visible = false
		event_window.close_panel()


func hide_event() -> void:
	if event_window:
		event_window.visible = false


func event_is_open() -> bool:
	return event_window != null and event_window.visible


# ------------------------------------------------------------------ 结算页（阶段 D）

## 打开结算页。res 的形状见 EveResult.show_result 的说明。
func show_result(res: Dictionary) -> void:
	if result_window == null:
		return
	result_window.show_result(res)
	result_window.visible = true
	result_window.move_to_front()


## 收起结算页。**顺手把打捞浮层也收掉**（2026-10-04）。
##
func hide_result() -> void:
	if result_window:
		result_window.visible = false


func result_is_open() -> bool:
	return result_window != null and result_window.visible


# ------------------------------------------------------------------ 设置窗（阶段 D）

## 打开设置窗。
##
## ⚠️ 打开时必须**回写当前真实状态**（state 参数）——
##    否则窗里显示的是上次的旧值，玩家看到一个和实际不符的开关，
##    点一下反而把状态改成了他不想要的那个。
## ⚠️ state 是**一整份**字典而不是拆开的参数列：设置项每加一项就要改一次
##    签名的话，迟早会漏改一处调用点（而漏改的表现是「窗里少同步了一项」，
##    不报错）。现在主控把真实状态整包递进来，窗自己按 key 取。
func show_settings(state: Dictionary) -> void:
	if settings_window == null:
		return
	settings_window.set_state(state)
	settings_window.visible = true
	settings_window.move_to_front()


func hide_settings() -> void:
	if settings_window:
		settings_window.visible = false


func settings_is_open() -> bool:
	return settings_window != null and settings_window.visible


## 设置窗里的「棋盘」开关状态由场景侧回写（KEY_B 也能改它，两条路要一致）
func sync_settings_toggle(key: String, on: bool) -> void:
	if settings_window and settings_window.has_method("_set_toggle"):
		settings_window.call("_set_toggle", key, on)


## 暂停 / 解除暂停 —— 遮罩的**唯一**入口。
##
## ══ 为什么必须有一层全屏遮罩 ══════════════════════════════════════
##  「暂停之后禁止操作」这句话在 Godot 里有三种实现，只有一种是对的：
##    ① 在每个 handler 里加 `if paused: return` —— 漏一个就是「暂停了还能买船」，
##       而且漏掉一个**不报错**（本工程红线：散落的守卫必然腐烂）；
##    ② `get_tree().paused = true` —— 会把整个场景树停掉，
##       连设置窗自己的按钮都点不动（玩家直接卡死在暂停里）；
##    ③ **全屏遮罩吃掉鼠标** —— 一处生效，天然覆盖所有控件与 3D 输入，
##       且「谁还能被点到」变成**排列顺序**这个显式的、看得见的事实。
##  这里选 ③，键盘侧的守卫留给主控（遮罩管不到键盘）。
##
## ⚠️ 遮罩**不能**盖住设置窗 —— 否则玩家点完暂停、顺手关掉设置窗，
##    就再也没有鼠标能点的东西了（只能按空格）。所以每次上遮罩都把
##    设置窗提到最前；遮罩自己也带一个「继续对局」按钮作为兜底。
func set_paused(on: bool) -> void:
	if pause_veil == null:
		if not on:
			return
		pause_veil = _build_pause_veil()
		add_child(pause_veil)
	pause_veil.visible = on
	if on:
		if settings_window != null:
			# 设置窗开着才需要提到最前；关着的话遮罩上的按钮负责恢复
			if settings_window.visible:
				settings_window.move_to_front()
		if _drag_ghost != null:
			_drag_ghost.move_to_front()


## 主控改了暂停态（键盘空格 / 结算 / 重开）之后回写设置窗的按钮文字。
func sync_settings_pause(on: bool) -> void:
	if settings_window != null and settings_window.has_method("set_paused"):
		settings_window.call("set_paused", on)


## 暂停遮罩：半透明压暗 + 居中大字 + 一个「继续」按钮。
func _build_pause_veil() -> Control:
	var veil := Control.new()
	veil.name = "PauseVeil"
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_STOP
	veil.visible = false

	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.04, 0.45)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	veil.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	veil.add_child(center)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(box)

	var big := Label.new()
	big.text = T.t("HUD_PAUSED", "‖ 已暂停")
	FONT.fs(big, 34)
	big.add_theme_color_override("font_color", Color(0.55, 0.78, 0.82))
	big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	big.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(big)

	var small := Label.new()
	small.text = T.t("HUD_PAUSED_SUB", "对局已冻结 · 操作已锁定")
	FONT.fs(small, 13)
	small.add_theme_color_override("font_color", Color(0.44, 0.55, 0.59))
	small.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	small.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(small)

	var resume := Button.new()
	resume.text = T.t("HUD_RESUME", "▶ 继续对局")
	resume.custom_minimum_size = Vector2(180, 34)
	EveButtonTheme.apply(resume, "hud_main")
	FONT.fs(resume, 14)
	resume.pressed.connect(func(): pause_resume_requested.emit())
	box.add_child(resume)

	return veil


# ------------------------------------------------------------------ 伤害数字（阶段 D）

## 冒一个伤害飘字（屏幕坐标）。
##
## ⚠️ 屏幕坐标由**场景侧**算好传进来（`arena.world_to_screen`），
##    HUD 不认识 3D 世界，不该在这里反向依赖相机。
func pop_damage(screen_pos: Vector2, damage: float, quality: int, hit: bool) -> void:
	if damage_feed and damage_feed.has_method("pop"):
		damage_feed.call("pop", screen_pos, damage, quality, hit)


func clear_damage() -> void:
	if damage_feed and damage_feed.has_method("clear"):
		damage_feed.call("clear")


# ------------------------------------------------------------------ 节点进场词横幅（阶段 C 收尾）

## 弹一段节点进场字幕。
##
## 参数：index = 节点号（1-based）· type_key = `EveNodeTable` 的 type 键 ·
##       line = 该节点的进场词。
##
## ⚠️ 只收 `type_key` 不收现成的中文标签 —— 类型文案的唯一真源是
##    `EveNodeTable.TYPE_LABELS`，在这里再传一个字符串进来就等于开了第二份。
func show_entry(index: int, type_key: StringName, line: String) -> void:
	if entry_banner and entry_banner.has_method("show_entry"):
		entry_banner.call("show_entry", index, type_key, line)


## 收掉横幅（开战 / 重开一局）。
func hide_entry() -> void:
	if entry_banner and entry_banner.has_method("clear"):
		entry_banner.call("clear")


## 横幅当前是否在显示（验收断言用）
func entry_banner_active() -> int:
	if entry_banner and entry_banner.has_method("active_count"):
		return int(entry_banner.call("active_count"))
	return 0


## 拿起 / 放下备战席舰船 —— 整块化作出售区
func set_selling(on: bool) -> void:
	if shop_window:
		shop_window.set_selling(on)
	if bench_rail:
		bench_rail.set_selling(on)


## 备战席拿起的是第几格（-1 = 没拿起）—— 轨道上显示出「已拿起」标记
func set_bench_drag(index: int) -> void:
	if bench_rail:
		bench_rail.set_dragging(index)


func set_economy(coin: int, level: int, xp: int, xp_need: int,
		refresh_cost: int, levelup_cost: int) -> void:
	if shop_window:
		shop_window.set_economy(coin, level, xp, xp_need, refresh_cost, levelup_cost)


## 顶层"全刷"入口 —— 通过 `refresh_requested` signal 通知主控刷。
##
## ⚠️ 存在原因：调试按钮 / 自动化脚本（探针 / 录制回放）调 `hud.refresh()`
##    时不应该需要知道具体刷哪些子模块。把"全刷"封一个稳定接口名，调用方
##    写 `hud.refresh()` 就行；后续加新字段（信标 / 备战席 / 羁绊）也只需要
##    在主控 `_refresh_run_ui()` 里挂一句，不会让所有调用方跟着改。
##
## 实现走 signal 而非直接引用主控 —— hud 不需要知道主控的类型，
## 任何容器（主控 / 录制回放 / 自动化）接上 signal 都能响应。
##
## 性能上不是"每帧调"的接口（每帧调会刷一整组 set_* + 羁绊 list + 立绘），
## 调试按钮 / 一次性脚本触发 OK，**别放进 _process**。
func refresh() -> void:
	refresh_requested.emit()


func set_bench(used: int, cap: int) -> void:
	if shop_window:
		shop_window.set_bench(used, cap)


func set_equipment(items: Array) -> void:
	if equipment_window and equipment_window.has_method("set_slots"):
		equipment_window.set_slots(items)


func set_stage(index: int, label: String, total_time: float) -> void:
	if command_bar and command_bar.has_method("set_stage"):
		command_bar.set_stage(index, label, total_time)


func tick_stage(delta: float) -> void:
	if command_bar and command_bar.has_method("tick"):
		command_bar.tick(delta)


## 当前阶段剩余秒数（向上取整）—— 倒计时滴答音要用。
##
## ⚠️ 为什么不让音频层自己去持有倒计时：
##    倒计时的**唯一真相源**是 `command_bar.time_left`（阶段总时长由
##    `set_stage` 给，`tick` 每帧递减）。音频层再存一份就会漂移 ——
##    和「别造第二份真相源」是同一条规则。
##    这里只做一个「读出来」的口子，不新增状态。
func stage_seconds_left() -> int:
	if command_bar == null:
		return -1
	return int(ceil(maxf(0.0, command_bar.time_left)))


## 顶条上的「战败 −N」预览。
## ⛔ 2026-10-01 改名：原来叫 `set_leak`，跟着已删除的漏网机制来的。
func set_loss_cost(damage: int) -> void:
	if command_bar:
		command_bar.loss_cost = damage
		command_bar.refresh()


## 信标结构值 —— 一局的生命线（交接文档 §11 P0，必须常驻可见）
func set_beacon(value: int, max_value: int = -1) -> void:
	if command_bar and command_bar.has_method("set_beacon"):
		command_bar.set_beacon(value, max_value)


## 顶条上的阶段：0 准备 / 1 战斗 / 2 结算
func set_phase(p: int) -> void:
	if command_bar and command_bar.has_method("set_phase"):
		command_bar.set_phase(p)


## 开战按钮的文案 + 可用性（随阶段变：开战 / 交战中 / 下一节点 / 再来一局）
func set_start_button(text: String, enabled: bool = true) -> void:
	if command_bar and command_bar.has_method("set_start_button"):
		command_bar.set_start_button(text, enabled)


## 同步商店的「锁定加速列表」按钮状态（锁定真正的语义在 EveRunState）
func set_shop_locked(on: bool) -> void:
	if shop_window and shop_window.has_method("set_locked"):
		shop_window.set_locked(on)


## 商店卡片是否买得起 —— 买不起的卡压暗，别让玩家点了才知道
func set_shop_affordable(coin: int) -> void:
	if shop_window and shop_window.has_method("set_affordable"):
		shop_window.set_affordable(coin)


# ------------------------------------------------------------------ 拖放（阶段 B5）

## 备战席格带的【可点击区域】。
##
## ⚠️ 比画出来的格带高 EveBenchRail.HIT_ABOVE。
##    ⚠️ 2026-09-23 改 2D 立绘后该值 48 → 10：立绘完全落在格子内，
##    不再需要为「3D 船身伸到控件外」留热区。留着 48 反而是隐患 ——
##    备战席顶 760、命中区一直伸到 712，而棋盘近端就在 762，
##    于是「点棋盘最下一行」会被判成「点备战席空格」（不报错、点了没反应）。
func bench_hit_rect() -> Rect2:
	if bench_rail == null:
		return Rect2(RECT_BENCH)
	var p := bench_rail.position
	var s := bench_rail.size
	if s.x <= 4.0:
		s = RECT_BENCH.size
		p = RECT_BENCH.position
	return Rect2(Vector2(p.x, p.y - EveBenchRail.HIT_ABOVE),
			Vector2(s.x, s.y + EveBenchRail.HIT_ABOVE + 4.0))


## 屏幕点落在备战席第几格（-1 = 没落在轨道上）
func bench_slot_at(screen_pos: Vector2) -> int:
	if bench_rail == null:
		return -1
	var r := bench_hit_rect()
	if not r.has_point(screen_pos):
		return -1
	return bench_rail.slot_at(screen_pos - bench_rail.position)


func set_bench_hover(index: int) -> void:
	if bench_rail:
		bench_rail.set_hover(index)


## 喂备战席名单（格子里画 2D 立绘用）。entries 元素 = {"ship_key", "star"}
##
## ⚠️ 转发而不是让 battle_scene 直接摸 bench_rail：
##    HUD 的对外接口一律走本类（bench_hit_rect / bench_slot_at / set_bench_drag
##    都是这样），多一层转发换来的是「谁能改 HUD 内部状态」这件事只有一个答案。
func set_bench_fleet(entries: Array) -> void:
	if bench_rail:
		bench_rail.set_fleet(entries)


## 出售区矩形 = 商店窗的实时矩形（含标题栏）。
##
## ⚠️ 必须读实时矩形，不能读 RECT_SHOP 常量 —— 商店是【可拖动/可缩放的窗口】，
##    玩家把它挪走之后，常量指向的位置就成了一张空桌子。
func sell_zone_rect() -> Rect2:
	if shop_window == null:
		return Rect2(RECT_SHOP)
	return Rect2(shop_window.position, shop_window.size)


## 设置拖动幽灵。info：{} = 隐藏；
## 否则 {name, star, cost, color, hint, hint_ok, screen}
func set_drag_ghost(info: Dictionary) -> void:
	if _drag_ghost == null:
		return
	_drag_ghost.apply(info)


## 拖动中「指针真的进了出售区」的高亮（出售区 = 商店窗实时矩形）。
##
## ⚠️ 与 set_selling() 的区别，别混用：
##    set_selling()     = 整块变橙（商店窗 **+** 备战席轨道），是「出售模式」的总开关，
##                        只在进入/退出准备阶段时用。
##    set_sell_hot()    = 只点亮商店窗，跟随指针进出，语义是「松手就卖在这里」。
##
##    为什么不把备战席轨道也点亮：轨道是「撤回 / 换位」的落点。
##    两个区域都亮橙的话，玩家想撤回的船会被卖在自己脚下 —— 这是不可逆的损失。
func set_sell_hot(on: bool) -> void:
	if shop_window:
		shop_window.set_selling(on)


# ------------------------------------------------------------------ 演示数据

## 一键填演示内容。
##
## ⚠️ 只填「还没有真实数据」的部分 —— 每个窗口填之前都先看它是不是空的，
##    这样一旦 battle_scene 开始喂真数据，演示内容自然退场，不用手改开关。
func _apply_demo_content() -> void:
	if _demo_used:
		return
	_demo_used = true

	# 装备栏位（沿用 V3 稿的 6 件）
	set_equipment([
		{"icon": &"armor_plate", "color": Color(0.85, 0.68, 0.28)},
		{"icon": &"shield", "color": Color(0.35, 0.70, 0.90)},
		{"icon": &"chevrons", "color": Color(0.88, 0.52, 0.30)},
		{"icon": &"capacitor", "color": Color(0.50, 0.62, 0.86)},
		{"icon": &"targeting", "color": Color(0.55, 0.78, 0.82)},
		{"icon": &"railgun", "color": Color(0.52, 0.76, 0.55)},
	])

	# 商店：从权威表里按 1/1/1/2/3 费各取一艘（就是 V3 稿那 5 张卡的位置）
	var offers: Array = []
	var want := [["punisher", 0], ["kestrel", 0], ["rifter", 0],
			["coercer", 0], ["omen", 0]]
	for w in want:
		var d := EveShipDatabase.by_id(String(w[0]))
		if not d.is_empty():
			offers.append(d)
	set_shop_offers(offers)

	set_economy(47, 3, 14, 68, 2, 4)
	set_bench(2, BENCH_SLOTS)
	# 演示备战席立绘（2 艘，与上面的「2 / 8」对上）。
	# ⚠️ 只填「还没被真数据覆盖」的部分 —— battle_scene 一旦喂真数据，
	#    它会用 set_bench_fleet 覆盖掉这里（与其余窗口同一条约定）。
	set_bench_fleet([
		{"ship_key": &"executioner", "star": 1},
		{"ship_key": &"cormorant", "star": 2},
	])
	set_stage(6, "精英战", 60.0)

	# 舰队构成：拿演示商店那几艘当「当前舰队」，好让羁绊条有数
	_demo_fleet()

	append_log({"time": 6.0, "category": &"economy", "text": "胜利 星币 +5 连胜 +1"})
	append_log({"time": 6.1, "category": &"loot", "text": "刽子手级★1 → 备战席"})
	append_log({"time": 6.2, "category": &"salvage", "text": "下单 断崖级★1 −2 ◆"})
	append_log({"time": 6.3, "category": &"hint", "text": "距窗口关闭 00:24"})
	append_log({"time": 5.4, "category": &"buy", "text": "茶隼级 −1 ◆ → 备战席"})
	_set_demo_salvage()


func _demo_fleet() -> void:
	var ships: Array = []
	for key in ["punisher", "kestrel", "rifter", "executioner", "coercer",
			"cormorant", "omen"]:
		var s := EveShipDatabase.instantiate_by_id(key, 0, 0)
		if s != null:
			ships.append(s)
	set_fleet(ships)
	# 顺带把档案窗展开给一艘船看效果
	if ships.size() > 0:
		show_ship(ships[0])


func _set_demo_salvage() -> void:
	# ⚠️ 必须按 salvage_info() 的形状填。旧版只给 name/star，三态化之后
	#    那样填会被判成 "empty"（框里一片空白），而且**不报错**。
	set_salvage({"state": "wreck", "name": "断崖级", "star": 1, "cost": 4, "price": 2})


# ------------------------------------------------------------------ 自绘件

## 拖动幽灵（阶段 B5）
##
## 跟手的小标签，回答玩家此刻最关心的两个问题：
##    「我手上拿的是哪艘」→ 名称 + ★n + ◆c
##    「松手会发生什么」  → 底部一行提示（放到第几行 / 出售返还多少 / 为什么不行）
##
## ⚠️ 为什么不在鼠标下放第二艘 3D 船：
##    投影进世界的第二艘船会随相机改变大小，而落格提示是屏幕空间的东西，
##    两种尺寸语言混在一起，玩家反而读不出「我到底要放到哪一格」。
##    云顶用的也是「手上挂一张卡」，不是把棋子贴在世界里。
class _DragGhost extends Control:
	## ⚠️ 内嵌类**看不到**文件级的 `FONT` ⇒ 自己 preload 一份（别写 `EveHudRoot.FONT`：
	##    那要等 class_name 注册，多一层「记得跑 --import」的隐性前提）。
	const FONT := preload("res://scripts/ui/eve_font.gd")
	const GHOST_SIZE := Vector2(178.0, 44.0)
	const OFFSET := Vector2(18.0, 16.0)

	var ship_name: String = ""
	var star: int = 1
	var cost: int = 1
	var accent: Color = Color(0.55, 0.78, 0.82)
	var hint: String = ""
	var hint_ok: bool = true

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = GHOST_SIZE
		size = GHOST_SIZE

	## info = {} 或 active=false → 隐藏；否则按字段重绘
	func apply(info: Dictionary) -> void:
		if info.is_empty() or not bool(info.get("active", false)):
			visible = false
			return
		ship_name = String(info.get("name", "—"))
		star = int(info.get("star", 1))
		cost = int(info.get("cost", 1))
		accent = info.get("color", accent)
		hint = String(info.get("hint", ""))
		hint_ok = bool(info.get("hint_ok", true))
		visible = true
		move_to_front()
		_follow(info.get("screen", Vector2.ZERO))
		queue_redraw()

	## 跟手，但整体夹在视口内（贴着屏幕右/下边缘时自动翻到鼠标另一侧）
	func _follow(sp: Vector2) -> void:
		var vp := get_viewport()
		var vs := vp.get_visible_rect().size if vp != null else Vector2(1920, 1080)
		var p := sp + OFFSET
		if p.x + GHOST_SIZE.x > vs.x - 4.0:
			p.x = sp.x - OFFSET.x - GHOST_SIZE.x
		if p.y + GHOST_SIZE.y > vs.y - 4.0:
			p.y = sp.y - OFFSET.y - GHOST_SIZE.y
		position = Vector2(maxf(4.0, p.x), maxf(4.0, p.y))

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, GHOST_SIZE)
		draw_rect(r, Color(0.055, 0.071, 0.082, 0.92), true)
		draw_rect(r, Color(0.42, 0.55, 0.60, 0.55), false, 1.0)
		draw_rect(Rect2(Vector2.ZERO, Vector2(3.0, GHOST_SIZE.y)), accent, true)

		var font := ThemeDB.fallback_font
		var tf := FONT.s(12)
		var tf_small := FONT.s(10)
		draw_string(font, Vector2(11.0, 18.0), "%s ★%d" % [ship_name, star],
				HORIZONTAL_ALIGNMENT_LEFT, GHOST_SIZE.x - 70.0, tf,
				Color(0.918, 0.969, 0.980))
		var cost_text := "◆ %d" % cost
		var cw := font.get_string_size(cost_text, HORIZONTAL_ALIGNMENT_LEFT, -1, tf).x
		draw_string(font, Vector2(GHOST_SIZE.x - 11.0 - cw, 18.0), cost_text,
				HORIZONTAL_ALIGNMENT_LEFT, -1, tf, Color(0.851, 0.678, 0.278))
		draw_string(font, Vector2(11.0, 36.0), hint,
				HORIZONTAL_ALIGNMENT_LEFT, GHOST_SIZE.x - 22.0, tf_small,
				Color(0.522, 0.761, 0.851) if hint_ok else Color(0.878, 0.522, 0.302))
