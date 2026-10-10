extends Node

## EVE 自走棋 —— 战斗场景主控（阶段 A：一局状态机已接通）
##
## ══════════════════════════════════════════════════════════════════
##  它在整局里的位置
## ══════════════════════════════════════════════════════════════════
##
##     EveRunState（数字与规则）  ←──  本文件负责「把数字变成船和窗口」
##              │                      和「把玩家的点击变回数字」
##              └──→ HUD（把数字变成字）
##
## 一局的四个阶段（曾经这里只有一个「打完 4 秒自动重开」）：
##
##     PREP     准备：布阵 + 商店 + 买船 + 加速等级 + 倒计时
##     BATTLE   战斗：锁定操作（只有相机可动）
##     RESOLVE  结算：漏船扣信标 / 发经验发钱 / 推进节点
##     ENDING   结局：通关 / 撤离
##
## ── 这一版删掉了什么，为什么 ──────────────────────────────────
##   `auto_restart_delay = 4.0` 的**自动重开**被删掉了。
##   自走棋的节奏是「我准备好了才开打」；自动重开把玩家从决策者降级成观众。
##   这一行不改，后面加多少经济系统都救不回来（路线文档 §2 阶段 A）。
##
##   `own_size / enemy_size` 两个导出参数也删了 —— 舰队不再随机抽，
##   而是「玩家买的船」和「节点表指定的编组」。
##
## 变更清单（阶段 A）：
##   - begin_prep / start_battle / resolve_battle 三段拆分（所有后续的插槽）
##   - 五条线全部接上：买 / 刷新 / 加速等级 / 锁定 / 开战
##   - 备战席（数据 + 3D 舰船层）· 上场（阶段 A 自动部署）
##   - 顶条：信标常驻 + 阶段名 + 开战按钮文案随阶段变
##   - 战斗时限改由节点表给（45 / 55 / 70 秒）

const ARENA_SCRIPT := preload("res://scripts/scene/eve_battle_arena.gd")
const HUD_SCRIPT := preload("res://scripts/ui/eve_hud_root.gd")
const RUN_STATE_SCRIPT := preload("res://scripts/core/eve_run_state.gd")
const AUDIO_SCRIPT := preload("res://scripts/core/eve_audio.gd")
## 设置持久化（同样用 preload 而非全局类名，理由见 eve_settings.gd 的 STORE 注释）
const SETTINGS_STORE := preload("res://scripts/core/eve_settings_store.gd")
## 平台 UI 缩放档（唯一真相源；桌面端 resolve() 恒返回 1.0）
const UI_SCALE_SCRIPT := preload("res://scripts/ui/eve_ui_scale.gd")
## ★ 字号缩放（2026-10-07）：只动字、不动版面（见 eve_font.gd）
const FONT := preload("res://scripts/ui/eve_font.gd")
## ★ 窗口分辨率档（2026-10-07）：桌面端才有；无头 / 移动端内部直接返回。
const RESOLUTION := preload("res://scripts/ui/eve_resolution.gd")

## 准备阶段时长（秒）。
##
## ⚠️ 交接文档只规定了【战斗时限】（§5.2：遭遇 45 / 精英 55 / BOSS 70），
##    **没有**规定准备阶段多长。这里的 30 秒是本工程侧的取值（云顶同量级）。
##    它不是一个随便的数字：准备倒计时是「买 / 存 / 刷新 / 升级 四选一」
##    这个互斥决策的压力来源 —— 钱只有一个，没有倒计时就没有取舍。
##    要调就调这一个数。
const PREP_SECONDS := 30.0

## 结算展示时长（秒）。
##
## ⚠️ **阶段 D 起这条路径已经退居二线**：正常情况下结算由
##    `EveResult` 结算页停住，等玩家点「继续 · 下一节点」。
##    这个常量只剩一个用途 —— 无头验收 / 调试脚本如果显式设了
##    `_resolve_timer`，仍按定时器收尾（保证旧脚本不用全改）。
##    正常玩法下 `_resolve_timer` 恒为 -1.0，这一行永远不会触发。
const RESOLVE_SECONDS := 3.5

## 结算弹窗的延迟（秒）—— 打完最后一艘船之后，等这么久才弹结算页。
##
## ══════════════════════════════════════════════════════════════════
##  为什么需要这个延迟（2026-10-01 用户要求）
## ══════════════════════════════════════════════════════════════════
##  用户原话：「每回合的结算弹窗需要在舰船被击毁后的一秒后弹出」。
##
##  没有它的话：最后一艘敌舰被击毁的**同一帧**，结算页就盖了上来 ——
##  玩家看不到那条开火线、也看不到击毁爆炸（爆炸寿命 0.75 秒），
##  「我把最后一艘打爆了」这个最有成就感的瞬间被一个弹窗吃掉了。
##
##  ⚠️ 取值 1.0 是用户指定的，别顺手改成 0.5「因为更快」——
##     击毁爆炸的寿命就是 0.75 秒，1.0 才刚好让它完整播完。
##
##  ⚠️ 计时用**真实 delta**（`_process` 里减），不是 `sim.elapsed`：
##     战斗此刻已经结束，`sim.step()` 不再被调用，`elapsed` 冻住了。
##     用 elapsed 计时的话计时器永远归零 ⇒ 结算页永远不弹。（这是本工程
##     反复踩过的那类「停摆变量当计时源」的坑。）
const RESULT_POPUP_DELAY := 1.0

## 全局时间倍率（调试用：2.0 = 战斗快进一倍）
@export var time_scale: float = 1.0

## 准备倒计时归零是否自动开战。
##
## 默认开（云顶口径：准备阶段结束就开打）。
## 想让「准备阶段无限长、只等玩家点开战」时置 false ——
## 调试布阵 / 录素材时用得上。
@export var auto_start_on_timeout: bool = true

var arena: EveBattleArena
var hud: EveHudRoot
var run: EveRunState
var sim: EveBattleSimulator = null
## 音频层（阶段 D 子项 ④）。三条总线 + 节流 + 可断言计数器。
var audio: EveAudio

## 上一次播过的倒计时秒数 —— 只在「秒数变了」时才响滴答。
##
## ⚠️ 不记这个的话，准备阶段 30 秒会按帧触发 tick（60fps × 30s = 1800 次）。
##    节流窗口能压住音量，但压不住「本该一秒一响」这个语义。
var _last_tick_second := -1
## ⚠️ 开战读秒（3/2/1）**没有**自己的状态变量 —— 它就挂在准备阶段倒计时的
##    最后 3 秒上（见 `_tick_countdown_sfx`）。
##    早期版本想在 `start_battle()` 里同帧连播 3/2/1：三声挤在一帧里根本听不出
##    读秒，是假实现；而真要「战前等 3 秒」又属于玩法改动。挂在准备倒计时上
##    既真读秒、又不改战斗时序。别把 `play_countdown` 挪回 start_battle。

## ⛔ 2026-10-01 删除：原来有个 `_leaked`（打完后还活着的敌舰）当「漏网」判据，
##    结算时按「漏了几艘」扣信标。整套机制已删 —— 现在信标只按「输没输」扣。
##    仍然需要「打完后敌方还剩几艘」这个数，但只在结算函数里当局部变量用。

## 暂停态（2026-09-28 起是【全局】暂停：PVE 准备 / 战斗都要能停）。
##
## ⚠️ 唯一写入口 = `set_paused()`。直接 `_paused = x` 会漏掉
##    遮罩显隐与设置窗按钮回写 —— 出现「场上停了、按钮还写着暂停」，
##    且不报错。`restart_run()` 是唯一的例外（硬重置，见那里的注释）。
var _paused := false
var _next_ship_id := 1
var _own_ships: Array[EveShip] = []
## 与 _own_ships 一一对应的 run.field_entries() 下标。
##
## ⚠️ 为什么不直接「_own_ships 的下标 == field 下标」：
##    _build_own_fleet 里遇到造不出来的船会 `continue` 跳过，那一跳之后两个数组就错位了。
##    拖放要用它把「屏幕上点是哪艘船」翻译成「上前名单的第几项」，
##    错一位的后果是「拖 A 船，B 船飞过去」——玩家会以为整个交互坏了。
var _own_field_index: Array[int] = []
var _enemy_ships: Array[EveShip] = []
## 敌方视觉是否已经生成（2026-10-01 起敌方改成"点开战才出现"，见 begin_prep）
var _enemy_visuals_spawned := false
## 事件「选 1 艘」进行中的那条 id（&"" = 不在选船态）
var _pending_event: StringName = &""
var _resolve_timer := -1.0
## 结算页弹出倒计时（秒）。> 0 = 正在等「击毁爆炸播完」；<= 0 = 已弹出。
##
## ⚠️ 与 `_resolve_timer` **不是一回事**，别合并：
##    `_resolve_timer` 是「结算页**收起**」的计时器（老逻辑，正常玩法恒为 -1）；
##    这个是「结算页**弹出**」的延迟。两个方向相反的计时器。
##    `_result_popup_timer > 0` 同时也是「结算数据已经算好、但页还没弹」的判据 ——
##    验收要断言的正是这个中间态。
var _result_popup_timer := -1.0
## 延迟弹出期间攒下的结算数据（到点由 `_popup_result()` 消费）。
## ⚠️ 必须**先算好存下来**而不是到点再算：`resolve_battle()` 会就地改
##    `run.beacon`，隔 1 秒再调一次会**再扣一遍血**。
var _pending_result: Dictionary = {}
## `_build_result_payload()` 最近一次的产物（`_pending_result` 的同一份引用）。
## 单独留一个名字是为了让「组装」与「消费」在代码里分得开。
var _result_payload: Dictionary = {}
## 上一次重建舰队时的「上场名单 + 棋盘格」指纹。
## 买到新船 / 三连合成 / 拖放调位都会变 —— 变了就得把舰队重新造一遍，
## 否则玩家花了钱或挪了位，战场上却不出现对应的变化。
var _last_field_sig := ""
## 只有名单（不含格号）的指纹 —— 决定要不要打那一行「上场 n／m 艘」日志
var _last_roster_sig := ""
## 上一次打过的「生效羁绊」组合 —— 只在变化时打日志
var _last_synergy_sig := ""
## 正在重建舰队（begin_prep 期间）—— 这期间不要再被 changed 信号触发一次重建
var _busy := false

## 拖动状态。空字典 = 没在拖。
##
## ⚠️ 刻意用【一份字典】而不是一堆 _drag_xxx 变量：
##    拖动是「要么全有要么全无」的状态。拆成 source / index / ship_key / screen
##    四个独立变量之后，取消路径上漏清一个就会留下「拿到一半」的中间态 ——
##    这是拖放交互最经典的 bug 来源（表现为下一次点击莫名其妙地开始拖东西）。
##    键：source(&"bench"/&"field") / index / ship_key / star / cost / name /
##        color / screen
var _drag: Dictionary = {}


func _ready() -> void:
	randomize()
	# ★ 字号缩放必须在**建 UI 之前**装好 —— HUD 的每一处字号都在建立时就算定，
	#   晚了第一帧会闪一下旧字号（`reapply()` 能补救，但没必要让它闪）。
	FONT.load_from_settings()
	# ★ 窗口分辨率（2026-10-07）：读盘并应用。
	#   ⚠️ 在**建 UI 之前** —— 窗口尺寸一变，设计空间就变了（非 16:9 的档会产生
	#      居中偏移），HUD 首次铺窗口时要拿到新值。桌面端才有；无头/移动端内部返回。
	RESOLUTION.apply_from_settings(get_window())

	# 3D 竞技场
	arena = ARENA_SCRIPT.new()
	arena.name = "Arena"
	add_child(arena)

	# 音频层（阶段 D 子项 ④）。放在 Arena 之后、HUD 之前 ——
	# 顺序无关紧要，但集中在一处便于看出「场景里的几层是谁」。
	audio = AUDIO_SCRIPT.new()
	audio.name = "Audio"
	add_child(audio)

	# HUD（CanvasLayer 保证浮在 3D 之上）
	var layer := CanvasLayer.new()
	layer.name = "HudLayer"
	add_child(layer)
	hud = HUD_SCRIPT.new()
	hud.name = "Hud"
	layer.add_child(hud)
	# 真实数据已经接上，演示内容一律关掉（HUD 侧默认已是 false，这里再钉一次）
	hud.demo_content = false

	# ⚠️ 2026-09-23：原先这里要把 HUD 的 RECT_BENCH 交给 arena.bench_stage，
	#    让 3D 舰船踩在轨道线上。备战席改画 2D 立绘后，这件事归 EveBenchRail
	#    自己管（立绘就在它的 _draw() 里），**不再需要跨「2D HUD → 3D 场景」
	#    递坐标** —— 那一步正是当年多个「两份坐标漂移」事故的来源。
	#    留此注释是为了说明「这里曾经有一行 configure」而不是被误删。

	# ── HUD 信号 ──
	hud.stance_changed.connect(_on_stance_changed)
	hud.range_rings_toggled.connect(_on_range_rings_toggled)
	hud.start_battle_requested.connect(_on_start_battle_requested)
	hud.settings_requested.connect(_on_settings_requested)
	hud.shop_buy_requested.connect(_on_shop_buy)
	hud.shop_refresh_requested.connect(_on_shop_refresh)
	hud.shop_levelup_requested.connect(_on_shop_levelup)
	hud.shop_lock_toggled.connect(func(on: bool): run.set_shop_locked(on))
	hud.salvage_requested.connect(_on_salvage)
	# ★ 打捞区两段接线（2026-10-04 改版：逐艘点，无浮层）
	hud.salvage_pick_one.connect(_on_salvage_pick_one)
	hud.salvage_pick_zero.connect(_on_salvage_pick_zero)
	hud.salvage_section_closed.connect(_on_salvage_section_closed)
	hud.stage_timer_expired.connect(_on_stage_timer_expired)
	# 事件四选一（阶段 C）：面板点选 → 这里落地。
	# ⚠️ 少了这一行，面板会**看起来完全正常**（4 张卡、悬停、点击高亮都对），
	#    但点下去什么都不发生 —— 因为信号发出来没人接。verify_run 的
	#    `_step_event_choose` 就是为这类「静默断线」设的（实测捕获过一次）。
	hud.event_option_chosen.connect(_on_event_chosen)
	hud.event_ship_picked.connect(_on_event_ship_picked)

	# ── 阶段 D：结算页 / 设置窗 ──
	# ⚠️ 与上面 event_option_chosen 同款风险 —— 少一行就是「按钮看着能点、
	#    点下去什么都不发生」。verify_run 的 `_step_d_*` 会走控件自身通道验它。
	hud.result_next_requested.connect(_on_result_next)
	hud.result_end_requested.connect(_on_result_end)
	hud.settings_background_changed.connect(_on_settings_background)
	hud.settings_mood_changed.connect(_on_settings_mood)
	hud.settings_fog_toggled.connect(_on_settings_fog)
	hud.settings_board_toggled.connect(_on_settings_board)
	hud.settings_camera_reset.connect(_on_settings_camera_reset)
	hud.settings_restart.connect(_on_settings_restart)
	hud.settings_back_to_menu.connect(_on_settings_back_to_menu)
	# ── 阶段 D+（2026-09-28）：暂停 / 音量 ──
	#
	# ⚠️ 与上面同款风险 —— 少一行就是「按钮看着能点、点下去什么都不发生」。
	#    暂停尤其危险：按下去没反应的话，玩家会以为游戏卡死了。
	hud.settings_pause_toggled.connect(_on_settings_pause)
	hud.settings_volume_changed.connect(_on_settings_volume)
	hud.settings_mute_toggled.connect(_on_settings_mute)
	# 暂停遮罩上的「继续」按钮（设置窗被关掉时的唯一鼠标出口）
	hud.pause_resume_requested.connect(func(): set_paused(false))
	# ⚠️ DEBUG-ONLY: 加币信号（与 settings_window.add_coins_requested 对应）
	hud.settings_add_coins.connect(_on_settings_add_coins)
	# 全刷请求（hud.refresh() 触发）
	hud.refresh_requested.connect(_refresh_run_ui)

	# ── 读盘：把上一次的设置应用到这一局 ──
	#
	# ⚠️ 必须在**信号连好之后**做：设置窗是 hud 的子节点，它的 _ready 比这里早，
	#    在它自己 _ready 里 emit 的话没人接得到（connect 还没执行）⇒ 静默失效。
	_apply_saved_settings()

	# ── 一局状态机 ──
	run = RUN_STATE_SCRIPT.new()
	run.name = "RunState"
	add_child(run)
	run.log_event.connect(_on_run_log)
	run.offers_changed.connect(_on_offers_changed)
	run.changed.connect(_refresh_run_ui)
	run.phase_changed.connect(_on_phase_changed)
	run.run_ended.connect(_on_run_ended)

	# 等一帧让 HUD 完成布局
	await get_tree().process_frame

	hud.clear_log()
	run.start_run()
	begin_prep()


# ══════════════════════════════════════════════════════════════════
#  阶段一：准备
# ══════════════════════════════════════════════════════════════════

## 进入准备阶段：清场 → 造双方舰队 → 摆位 → 刷 HUD → 起倒计时
##
## ⚠️ 这里【不建模拟器】。准备阶段不该有战斗推进 ——
##    舰队只是站在那里，等玩家说「开打」。
func begin_prep() -> void:
	# 事件节点（4 / 10 / 14）：没有战斗，进来就开面板。
	#
	# ⚠️ 放在函数**最前面**分派，而不是在后面加一个 if：
	#    事件节点没有敌方编组，一旦先跑了建队那一段，
	#    compute_deploy_z(我方, []) 就要拿到一支空舰队去算接敌距离。
	#    分派在最前面 = 那一段永远不会被事件节点走到。
	if run.phase != EveRunState.Phase.ENDING and EveNodeTable.is_event(run.node_index):
		_enter_event_node()
		return

	_busy = true
	run.set_phase(EveRunState.Phase.PREP)
	hud.set_phase(0)
	hud.set_selling(false)
	hud.set_bench_drag(-1)
	_resolve_timer = -1.0
	# 阶段 D：进准备阶段 = 上一场彻底翻篇。结算页收起、残留的爆炸/飘字清掉。
	# ⚠️ 不清的话，上一场最后一秒的爆炸会飘在下一轮的布阵台上（残留 0.75 秒）。
	hud.hide_result()
	hud.clear_damage()
	arena.fx_clear()

	arena.clear_ships()
	_own_ships = _build_own_fleet()
	_enemy_ships = _build_enemy_fleet()

	# 部署带按双方实际射程自动计算 —— 保证开局接敌距离落在武器射程附近。
	# 这是战斗能收敛的前提（详见 EveBattleArena.compute_deploy_z 的说明）。
	var dz := arena.compute_deploy_z(_own_ships, _enemy_ships)
	arena.deploy_own_z = float(dz[0])
	arena.deploy_enemy_z = float(dz[1])
	# 棋盘对齐到本节点的接敌线（细节与「棋盘不是等比地图」这个事实见
	# EveBattleArena.align_board_to_line 的说明）
	arena.align_board_to_line(arena.deploy_own_z)

	# ⚠️ 只重新取景，**不调 reset_camera()** —— 保留玩家上一局转过的视角。
	#    每回合把镜头掰回默认角度的话，玩家刚调好的观察角度就白调了。
	#
	# ⚠️⚠️ 但**视距必须还原**（2026-09-20 阶段 D 回归的修复）：
	#    `reset_camera()` 管的是**角度**（那个确实该保留），
	#    而开战镜头改的是**视距**（zoom ×1.55 推近）—— 它不属于"玩家的观察角度"，
	#    是系统临时加的。不还原的话，下一轮布阵时棋盘格投影会整体下移，
	#    格 (8,5) 正好落进商店窗的出售区矩形里 ⇒ 玩家的船被"拖到格子上"却**卖掉了**。
	#    详见 EveBattleArena.reset_battle_zoom() 的说明。
	arena.reset_battle_zoom()
	arena.frame_battlefield()

	_place_fleet(_own_ships, 0)
	_place_fleet(_enemy_ships, 1)
	for ship in _own_ships:
		arena.spawn_ship_visual(ship)
	# ★ 2026-10-01：**敌方视觉不在这里生成**。
	#
	#   用户原话：「我知道云顶之弈打怪回合那些怪会优先出现在战场上，
	#             但这个我还是想像 PVP 回合一点，所以想把流程改为
	#             在玩家点击开战之后才出现。」
	#
	#   ⚠️ 只推迟 **`spawn_ship_visual`** 这一步。数据层照旧：
	#      `_build_enemy_fleet()` 正常建队、`_place_fleet(_enemy_ships, 1)`
	#      也照旧写 `ship.body.position` —— 因为 `compute_deploy_z()` 要靠
	#      敌方射程算接敌距离，这条不变量不能断。
	#      （`arena.snap_ships/_sync_ships` 对没有视觉的船是 null 跳过，安全。）
	_enemy_visuals_spawned = false
	# ★ 53 轮：布阵阶段**必须显式同步一次姿态**（红线 54 配套）。
	#
	# ⚠️ 为什么以前是漏的、以及漏了为什么"看着还行"：
	#   `_process` 的 `PREP` 分支**只走倒计时**（`hud.tick_stage` + `_tick_countdown_sfx`），
	#   **不调 `arena.sync_ships()`** —— 那句话在 `BATTLE` 分支里。
	#   而 `spawn_ship_visual()` → `setup()` 只会：① 由 `_build_hull_model` 定 `model.basis`
	#   ② 把**节点** `position` 设成 `body.position / 1000`。
	#   节点的**旋转（`quaternion`）在 `setup` 里从头到尾没被写过** ⇒ 停在
	#   `Quaternion.IDENTITY`（`_facing_quat` 的初值）。
	#   ⇒ 布阵阶段玩家看到的朝向 = **Identity 姿态**，与 `SHIP_AXES` 毫无关系！
	#     它"看着像朝前"纯属偶然（Identity 恰好接近某些船的正确姿态），
	#     而不同船的正确姿态各不相同 ⇒ **布阵画面里船头乱指**。
	#
	# ⚠️ 敌方那次同步（下方 `sync_ships(_enemy_ships)`）是 47 轮为"部署带变了要重摆位置"
	#    加的，只覆盖敌方；我方**从来没有**在布阵阶段同步过。
	#
	# ⇒ 修法：摆完 + 生成完，**对全舰队同步一次**（我方 + 敌方）。
	#    `delta` 传 `1.0/60.0`（一个标准帧）：布阵态下 `aim_dir` 已由
	#    `_place_fleet` 写死为朝敌，`slerp` 权重 `FACING_LERP=0.12` 会让姿态
	#    **只走到 12%** —— 这是唯一需要在调用点显式处理的事。
	#    见下方 `_snap_fleet_facing()` 的做法与理由。
	_snap_fleet_facing()
	_last_field_sig = _field_signature()
	_last_roster_sig = _roster_signature()

	# HUD
	_refresh_run_ui()
	hud.set_stage(run.node_index, run.stage_label(), PREP_SECONDS)
	# 阶段 C 收尾：节点进场字幕（4.2 秒后自己淡出，见 eve_entry_banner.gd）。
	#
	# ⚠️ 只有战斗类节点弹 —— 事件节点（4/10/14）的进场词已经是事件面板的引导语
	#    （`_enter_event_node` 传给 show_event 的 line 参数），
	#    同一句话同一时刻出现两处会互相打脸。
	hud.show_entry(run.node_index, run.node_type(), run.entry_line())
	hud.set_loss_cost(run.loss_preview())
	hud.set_fleet(_own_ships)
	hud.set_start_button("✦ 开战", true)
	_log_synergies()

	hud.append_log({
		"time": 0.0, "category": &"system",
		"text": "节点 %d／%d · %s · 敌方「%s」%d 艘 · 时限 %ds" % [
			run.node_index, EveNodeTable.TOTAL, run.stage_label(),
			run.enemy_comp_name(), run.enemy_comp_size(), int(run.battle_seconds()),
		],
	})
	hud.append_log({
		"time": 0.1, "category": &"hint",
		"text": run.current_node().get("line", ""),
	})
	if _own_ships.size() > 0:
		hud.show_ship(_own_ships[0])
	_busy = false


## 上场名单指纹（船 id + 星级 + 棋盘格）。
##
## ⚠️ 一定要带格号：阶段 B 之后「把一艘船挪到另一格」不改变名单，
##    但舰队必须重建（船要出现在新格子里）。只比 id:star 的话，
##    拖放会「编制变了、船没动」，玩家立刻发现。
func _field_signature() -> String:
	var parts := PackedStringArray()
	for e in run.field_entries():
		var c = e.get("cell", Vector2i(-1, -1))
		var cs := "auto"
		if c is Vector2i and c.x >= 0:
			cs = "%d.%d" % [c.x, c.y]
		parts.append("%s:%d@%s" % [String(e.get("ship_key", "")), int(e.get("star", 1)), cs])
	return ",".join(parts)


## 只有名单（不含格号）的指纹 —— 用来决定「要不要打那一行上场日志」。
## 拖一次就打一次「上场 5／5 艘」是纯噪音。
func _roster_signature() -> String:
	var parts := PackedStringArray()
	for e in run.field_entries():
		parts.append("%s:%d" % [String(e.get("ship_key", "")), int(e.get("star", 1))])
	return ",".join(parts)


## 准备阶段买到新船 / 三连合成 / 拖放调位 → 我方舰队重建。
##
## ⚠️ 这条链必须存在，否则「买船」只是一个让星币变少的按钮 ——
##    买到的东西不出现在战场上，玩家五分钟内就会发现这是个假系统。
##    重建范围刻意只到「我方 + 重新摆位」：
##    敌方不重建（他们的数值与玩家的购买无关），只跟着新的部署带挪个位置。
func _respawn_own_fleet() -> void:
	for s in _own_ships:
		arena.remove_ship_visual(s.id)

	_own_ships = _build_own_fleet()
	_last_field_sig = _field_signature()

	var dz := arena.compute_deploy_z(_own_ships, _enemy_ships)
	arena.deploy_own_z = float(dz[0])
	arena.deploy_enemy_z = float(dz[1])
	arena.align_board_to_line(arena.deploy_own_z)
	_place_fleet(_own_ships, 0)
	_place_fleet(_enemy_ships, 1)
	for ship in _own_ships:
		arena.spawn_ship_visual(ship)
	# 敌方的位置也变了（部署带跟着玩家舰队的射程中位数走），
	# 让它们的可视节点从 body 重新同步一次
	arena.sync_ships(_enemy_ships)
	# ★ 53 轮：我方新生成的节点**必须补一次瞬时姿态**（红线 54）。
	#   `spawn_ship_visual` → `setup()` 不设 rotation ⇒ 新买的船会是 Identity 姿态
	#   （= 朝向乱）。布阵期 `_process` 不跑 `sync_ships` ⇒ 不补就一直是错的。
	#   ⚠️ 这里覆盖全舰队（不只新船）：反正只是赋值，且能纠正任何残留。
	_snap_fleet_facing()

	hud.set_fleet(_own_ships)
	hud.set_loss_cost(run.loss_preview())
	_log_synergies()
	if _roster_signature() != _last_roster_sig:
		_last_roster_sig = _roster_signature()
		hud.append_log({
			"time": 0.0, "category": &"deploy",
			"text": "上场 %d／%d 艘：%s" % [
				_own_ships.size(), run.field_limit(),
				", ".join(_names_of(_own_ships)),
			],
		})
	if _own_ships.size() > 0:
		hud.show_ship(_own_ships[0])


static func _names_of(fleet: Array[EveShip]) -> PackedStringArray:
	var out := PackedStringArray()
	for s in fleet:
		out.append(s.ship_name)
	return out


## 玩家舰队 = 上场名单
##
## ⚠️ 每次准备阶段都**重新造实例**，所以上一节点打残的血量不会带过来 ——
##    这是自走棋的基本盘（每回合开打前全员满血）。
##
## 数值叠加顺序（与敌方的那条链对齐）：
##      base → star(×1.8^Δ) → **羁绊**
## ⚠️ 羁绊必须在星级【之后】：羁绊里的固定值加成（甲抗「结构 +150」）
##    不该被星级放大 —— 星级放大的是船本身的底子，羁绊是外挂的团队加成。
##    反过来（先羁绊后星级）会让 3★ 的「结构 +150」变成 +486，那是另一个游戏。
func _build_own_fleet() -> Array[EveShip]:
	var out: Array[EveShip] = []
	var idx_map: Array[int] = []
	var entries := run.field_entries()
	for i in entries.size():
		var e: Dictionary = entries[i]
		var key := String(e.get("ship_key", ""))
		var star := int(e.get("star", 1))
		var ship := EveShipDatabase.instantiate_by_id(key, 0, _next_ship_id)
		if ship == null:
			continue
		_next_ship_id += 1
		ship.star = star
		if star > 1:
			var m := pow(EveRunState.STAR_MULT, float(star - 1))
			ship.warhead_scale(m)
			ship.armor_scale(m)
		_apply_doctrine(ship)
		out.append(ship)
		idx_map.append(i)
	# 与 out 同步下标的映射（拖放要用，见 _own_field_index 的说明）
	_own_field_index = idx_map
	# 羁绊：从【真实上场名单】统计，只加在带该羁绊的船上
	run.apply_synergies_to(out)
	# 事件增益：**全队**（面板文案写的就是「全队」），所以放在最后、
	# 且不受羁绊的「只加带该羁绊的船」那条约束。
	run.apply_events_to(out)
	# 逐艘的**永久**增益（武器调校 / 结构加固）—— 走 idx_map，不能用 out[i]↔field[i]
	run.apply_field_buffs_to(out, idx_map)
	return out


## 把本节点生效的羁绊写进日志（只在档位组合变化时打，免得变成噪音）
func _log_synergies() -> void:
	if run == null:
		return
	var act := run.active_synergies()
	var parts := PackedStringArray()
	for a in act:
		parts.append("%s=%d" % [String(a["member"]), int(a["n"])])
	var sig := ",".join(parts)
	if sig == _last_synergy_sig:
		return
	_last_synergy_sig = sig
	for a in act:
		var line := "羁绊生效：%s %d／%d —— %s" % [
				String(a["member"]), int(a["n"]),
				EveTraitTable.max_tier(a["group"]), String(a["text"])]
		var pending: PackedStringArray = a.get("pending", PackedStringArray())
		if not pending.is_empty():
			# ⚠️ 未实装的特殊机制必须写出来。让玩家以为「凑齐就有效果」比不生效更糟。
			line += "（特殊机制未实装：%s）" % ", ".join(pending)
		hud.append_log({"time": 0.0, "category": &"economy", "text": line})


## 敌方舰队 = 节点表指定的编组（EveEnemyComps）
##
## 数值叠加顺序严格按交接文档 §6.4 的冻结口径：base → star → power_scale。
func _build_enemy_fleet() -> Array[EveShip]:
	var out: Array[EveShip] = []
	for d in run.enemy_roster():
		var ship := EveShipDatabase.instantiate_by_id(
				String(d.get("ship_key", "")), 1, _next_ship_id)
		if ship == null:
			continue
		_next_ship_id += 1
		EveRunState.apply_enemy_scaling(ship, 1, run.enemy_scale())
		_apply_doctrine(ship)
		out.append(ship)
	return out


## 战术二次校正
##
## apply_stats 已按吨位给了默认姿态与交战距离。
## 这里只处理一个例外：射程极远的船如果也去贴身，它的射程优势就白给了。
## 所以远程船强制拉开，其余保持吨位默认。
func _apply_doctrine(ship: EveShip) -> void:
	if ship.optimal_range >= 20000.0 and ship.stance == EveCombatCore.Stance.ORBIT:
		# 巡洋级射程 + 环绕 = 自废武功（自己转向慢，绕起来打不中别人）
		ship.stance = EveCombatCore.Stance.KEEP
	# 交战距离兜底：不能小于 2km（不然会撞在一起）
	ship.desired_range = maxf(2000.0, ship.desired_range)


## ★ 53 轮：布阵阶段的**瞬时姿态快照**（红线 54）。
##
## ── 为什么必须存在 ────────────────────────────────────────────────
##  ① **布阵阶段没有每帧姿态同步**：`_process` 的 `PREP` 分支只走倒计时
##     （`hud.tick_stage` + `_tick_countdown_sfx`），`arena.sync_ships()` 在
##     `BATTLE` 分支里 ⇒ 布阵期视觉节点**一次都不会被同步姿态**。
##  ② `spawn_ship_visual()` → `setup()` **只设 position，不设 rotation**
##     ⇒ 节点 `quaternion` 停在 `Quaternion.IDENTITY`。
##  ③ 于是布阵画面里的朝向 = **Identity 姿态**，与 `SHIP_AXES` 无关
##     —— 这正是「摆到战斗区时朝向乱」的真根因。
##
## ── 为什么是 `snap_ships` 而不是 `sync_ships` ─────────────────────
##  `sync_ships` 走 `slerp(want, FACING_LERP=0.12)`，**单次只走 12%**。
##  布阵期只同步一次 ⇒ 12% ≈ 看着没转。必须用瞬时版
##  （`EveShipVisual.snap_facing()`，姿态算式与 `sync_from_body` 同源，只是不做插值）。
##
## ⚠️ 与下方敌方那次 `sync_ships(_enemy_ships)` 的关系：
##    那次是 47 轮为「部署带变了要重摆**位置**」加的，**只覆盖敌方**、
##    且走平滑版（位置是直接赋值、不受 slerp 影响 ⇒ 位置正确；姿态则只走 12%）。
##    现在由本函数统一接管**姿态**；敌方那次保留（它管位置，职责不重叠）。
func _snap_fleet_facing() -> void:
	arena.snap_ships(_own_ships)
	arena.snap_ships(_enemy_ships)


## 摆放舰队（己方 z 正、敌方 z 负）
##
## ⚠️ 位置有【两个来源】，优先级明确：
##    ① 玩家摆过的船（entry 里有 cell）→ 棋盘格 → 世界坐标（arena.board_cell_to_meters）。
##       这是阶段 B 的拖放部署；玩家说什么就是什么。
##    ② 其余（敌方全部、我方的空位）→ arena.default_formation() 的通用阵列。
##    本文件不自己算 x/z：站位算法只有 arena 一份真相源（路线文档 §3①）。
##
## ★★ 53 轮：**布阵阶段一律显式朝敌方**（用户裁决，红线 54）★★
##
## ── 用户原话（53 轮）─────────────────────────────────────────────
##   「在初始状态下，肯定是一律朝着正前方啊，但我怕的是又是把**朝着玩家操作
##     方向**当做是朝前，这就相当尴尬了。」
##   「'正前方' 是相机看向的方向……敌人是离我越来越近的，我是朝着 −Z 看。」
##   「初始状态，就是我把舰船摆到战斗区的时候的状态。」
##
## ── 定案口径（无歧义版）─────────────────────────────────────────
##   · 「正前方」= **世界 −Z**（= 我方相机看出去的方向 = 敌人阵地）。
##     理由：棋盘局部轴与世界轴同向（`eve_board.row_z0()` 的 row 0 在 −Z），
##     相机 `yaw≈0` 时 `cos(0)=1` ⇒ 相机架在 **+Z 侧**朝 −Z 看 ⇒ 画面上方 = −Z。
##     ⚠️ 判据是「**绝对世界方向**」，与玩家操作 / 拖放 / 镜头转动**完全无关**
##     —— 这正是用户担心的那个坑，这里用"写死常量"从源头堵掉。
##   · 「初始状态」= **布阵 / 准备阶段**（船刚被摆到战斗区、还没开打）。
##   · 开打之后：`aim_dir` 改由 `_refresh_targets()` 每 tick 写「朝锁定目标」，
##     **不再**由本函数决定（本函数的结果会被第一 tick 覆盖）。
##
## ── 为什么必须写 `aim_dir` 而**不是**像以前那样只写 `velocity` ──────
##   ⚠️⚠️ 旧写法（53 轮前）：
##       `ship.body.velocity = facing_dir * max_speed * 0.15`   # 注释写"初始朝向"
##   **这是"意图与实现错位"的典型**：
##     · `velocity` 是**速度**，不是朝向；布阵阶段 `aim_dir == 0`
##       ⇒ `sync_from_body` 走**兜底分支** `f = v̂`
##       ⇒ 朝向**碰巧**对（因为 velocity 恰好指敌方），但这是**巧合不是契约**；
##     · 更糟的是 `velocity` 会被**战斗积分衰减**（`integrate_body` 的阻尼项）：
##       一旦衰减到 `MOVE_EPS` 以下，`f` 变零向量 ⇒ `_has_align` 整段跳过
##       ⇒ 该船的旋转**永远停在 `setup` 时的初始姿态**（不报错，只是"这船不转身"）。
##   ⇒ 正确做法 = **显式写 `aim_dir`**（走"有目标"那条确定分支），
##     与开打后的语义**同构**：`aim_dir` 就是「舰艏该朝哪」的唯一通道。
##     这样布阵态与战斗态**只有一处差异**（谁写 `aim_dir`），姿态链完全复用。
##
##   ⚠️ `velocity` 那行**保留**（原语义不变）：它是船的初始动量，
##     0.15 倍是"开战瞬间有个起步感"的观感调参，与朝向无关。
##     **别把朝向的职责塞回 velocity**（那就是旧写法的病根）。
func _place_fleet(fleet: Array[EveShip], team: int) -> void:
	var positions := arena.default_formation(fleet.size(), team)
	# ⚠️ 这里必须显式标 Array，不能写 `var entries := ...`：
	#    `:=` 会按第一个分支把类型推断成 Array[Dictionary]，
	#    而 team == 1 时表达式给的是裸 []（Array）→ 运行时报
	#    「Trying to assign an array of type Array to Array[Dictionary]」，
	#    而且只在对局里跑起来才炸，静态检查看不出来。
	var entries: Array = run.field_entries() if team == 0 else []
	# 己方朝 −Z（敌方阵地），敌方朝 +Z（我方阵地）——绝对世界方向，与操作无关。
	var facing_dir := Vector3(0, 0, -1.0 if team == 0 else 1.0)
	for i in fleet.size():
		var ship := fleet[i]
		var pos: Vector3 = positions[i] if i < positions.size() else Vector3.ZERO
		if team == 0 and i < entries.size():
			var c = entries[i].get("cell", Vector2i(-1, -1))
			if c is Vector2i and c.x >= 0:
				pos = arena.board_cell_to_meters(c.x, c.y)
		ship.body.position = pos
		ship.body.previous_position = pos
		# ★ 53 轮：**朝向走 `aim_dir`**（唯一通道，与战斗态同构）。
		#   拍平到水平面（XZ）—— 与 `_refresh_targets()` 的写入口径**完全一致**
		#   （红线 46：`aim_dir` 必须是水平单位向量），布阵态与战斗态因此无缝衔接。
		ship.body.aim_dir = Vector3(facing_dir.x, 0.0, facing_dir.z).normalized()
		# 初始动量（观感：开战瞬间有个起步感）—— 与朝向无关，别混用。
		ship.body.velocity = facing_dir * ship.body.max_speed * 0.15


# ══════════════════════════════════════════════════════════════════
#  阶段二：战斗
# ══════════════════════════════════════════════════════════════════

## 准备结束 → 锁定操作 → 开打
func start_battle() -> void:
	if run.phase != EveRunState.Phase.PREP:
		return
	if _own_ships.is_empty():
		# ⚠️ 2026-09-20 起「买船」不再自动上场，所以空手上阵成了一种
		#    玩家真会踩到的状态（云顶里也是）。挡下来，并说清楚下一步做什么 ——
		#    只说「没有船」而不说「去哪儿拿船」，玩家会以为按钮坏了。
		var hint := "场上一艘船都没有 —— 从备战席拖一艘到棋盘上"
		if run.bench.is_empty():
			hint = "一艘船都没有 —— 先在商店买一艘，再从备战席拖到棋盘上"
		hud.append_log({"time": 0.0, "category": &"hint", "text": hint})
		return

	run.set_phase(EveRunState.Phase.BATTLE)
	hud.set_phase(1)
	hud.set_start_button("交战中", false)
	# 阶段 D④：开战读秒在准备阶段倒计时的**最后 3 秒**由 `_tick_countdown_sfx`
	# 播（3 / 2 / 1）。这里**不**同帧假播 —— 三声挤一帧听不出读秒。
	# ⚠️ 若玩家自己点「开战」，就不会听到这 3 声（倒计时还没走到 3），
	#    这是刻意的：读秒是「自动开战」的预告，不是强制前摇。

	# ── 阶段 D①：开战镜头 ──
	# 推近 + 平滑偏到一个更有动感的方位（细节与取值依据见 arena.begin_battle_shot）。
	# ⚠️ 在【建模拟器之前】调：这一下不能等第一帧，否则玩家会看到
	#    「先打了两下、镜头才推过去」。
	# ★ 敌方视觉在**开战这一刻**才生成（准备阶段战场上看不到敌舰）
	if not _enemy_visuals_spawned:
		for ship in _enemy_ships:
			arena.spawn_ship_visual(ship)
		# ⚠️ 生成后必须补一次瞬时姿态：`setup()` 不写 rotation ⇒ 不补的话
		#    敌舰会以 Identity 姿态出场（船头乱指，红线 54）。
		#    此时 `ships_board_mode` 已是 false（它只在拖拽期间为真）⇒ 尺寸正确。
		arena.snap_ships(_enemy_ships)
		_enemy_visuals_spawned = true

	arena.begin_battle_shot()
	hud.clear_damage()
	# 阶段 C 收尾：点了「开战」就是玩家不想再读那行进场词了 —— 立刻收掉，
	# 别让它继续挂在交战画面上（它自己的 4.2 秒寿命还在跑）。
	hud.hide_entry()

	var limit := run.battle_seconds()
	sim = EveBattleSimulator.new()
	sim.setup(_own_ships, _enemy_ships)
	# ⚠️ 时限必须在 setup 之后设 —— setup 会把它重置回默认 180s
	sim.set_time_limit(limit)
	sim.unit_destroyed.connect(_on_unit_destroyed)
	sim.battle_finished.connect(_on_battle_finished)
	# ── 阶段 D②③：命中反馈 + 伤害数字 ──
	# ⚠️ 这一行同样是「少了它一切照跑、只是什么都看不见」的类型。
	#    verify_run 的 `_step_d_hit` 直接数 arena.battle_fx.active_count()
	#    与 hud.damage_feed.active_count()，就是为了捕获这种静默断线。
	sim.shot_fired.connect(_on_shot_fired)

	# 顶条的倒计时切成「战斗时限」
	hud.set_stage(run.node_index, "%s · 交战" % run.stage_label(), limit)

	_logged_count = 0
	_sd_announced = false
	_timeout_forfeit = false
	_sync_log()
	hud.append_log({"time": 0.0, "category": &"system",
			# ⚠️ 2026-10-01 第二次改：超时**不再判负**，战斗打到一方全灭为止，
			#    收敛由「火力渐增」保证（伤害在时限后继续放大）。
			# ⛔ 这里原来写着「时限内未清场即判负」—— 2026-10-01 第二次改：
			#    超时**不再判负**，战斗打到一方全灭为止（收敛靠火力渐增）。
			#    继续那么写会让玩家盯着倒计时、以为到 0 就输。
			"text": "开战：我方 %d 艘 vs 敌方 %d 艘 · 打到一方全灭为止（%ds 后火力渐增）"
			% [_own_ships.size(), _enemy_ships.size(), int(limit)]})


# ══════════════════════════════════════════════════════════════════
#  阶段三：结算
# ══════════════════════════════════════════════════════════════════

## ★ 火力渐增的开始提示（时限的 60% 处触发一次）。
##
## ⚠️⚠️ 2026-10-04 修的真 bug：原来这里直接调
##    `hud.set_stage(..., 0.0)` 把顶条倒计时**当场归零** ——
##    而火力渐增在**时限的 60%** 就开始（SUDDEN_DEATH_FRACTION=0.60）：
##    遭遇战 45s → 27s 触发，顶条还剩 18s；精英战 55s → 33s，还剩 22s。
##    ⇒ 用户实机看到「明明战斗还剩 20 多秒，结果一下就归零了」。
##
##    正确行为：火力渐增只是**伤害放大机制**的开始，跟倒计时**没有任何关系**
##    —— 只发一条日志，倒计时让它自然走完。
##    （判据 `damage_multiplier() > 1.0` 与「倒计时归零」根本不是同一件事，
##      2026-10-01 写这行时把两者混为一谈了。）
##
## ⚠️ 抽成独立方法不为好看：verify_run 要直接调它，断言「调完之后
##    顶条的 time_left 一个字都没变」—— 内联在 _process 里就测不到了。
func _check_sudden_death() -> void:
	if _sd_announced or sim == null:
		return
	if sim.damage_multiplier() > 1.0:
		_sd_announced = true
		hud.append_log({"time": sim.elapsed, "category": &"system",
				"text": "火力渐增 —— 伤害开始放大，直到一方被击毁或时限归零"})


## 结算原因 —— **纯函数**（三个事实进、一个字符串出）。
##
## ⚠️ 抽出来不是为了好看：四条分支里有两条（「未部署」「我方全灭」）在真实
##    对局里很难稳定复现（一条要等准备倒计时走完、一条要正好被打光），
##    抽成纯函数，自检才能四条一起钉住（`verify_run._step_d_result`）。
##
## ⛔ 2026-10-01：这个数原来叫 `leaked`（漏网），现在只表示「敌方还剩几艘」——
##    **它不再参与任何扣血计算**，只用来区分「这场为什么结束」。
##
## 判定顺序**不能换**：
##   ① `own_empty`        —— 只有「准备超时判负」这条路会为真（不经过模拟器）
##   ② `enemy_alive > 0`  —— 还有敌舰活着 ⇒ 我方被打光，或极罕见的僵持收场
##   ③ 剩下（=0）         —— 敌舰全死，含"平局"（双方同归于尽时也是 0）
##
## ⛔ 2026-10-01（第二次改）：这里原来返回「时限耗尽」。战斗已改为
##    **打到一方全灭为止**（超时不再判负），所以正常情况下
##    **只有「敌方全灭 / 我方全灭 / 未部署」三种**会出现。
static func battle_end_reason(own_empty: bool, enemy_alive: int, own_alive: int,
		timed_out: bool = false) -> String:
	if own_empty:
		return "未部署"
	# ★ 2026-10-04：时限归零判负恢复（用户口径），把「时限耗尽」分支加回来 ——
	#    玩家必须能从结算页一眼看出「我是超时输的」，而不是笼统的「拦截失败」。
	#    ⚠️ 顺序在 own_empty 之后：未部署判负是另一条路（PREP 归零），
	#       它不该被「时限耗尽」盖掉。
	if timed_out:
		return "时限耗尽"
	if enemy_alive > 0:
		return "我方全灭" if own_alive == 0 else "僵持收场"
	return "敌方全灭"


func _on_battle_finished(winner_team: int) -> void:
	# 「击毁」= 打完之后不活着的船 ⇒ 出残骸（打捞）。
	# 「敌方存活」只用来判断**这场为什么结束**，⛔ 不再参与扣血
	#    （2026-10-01 删掉「漏网」机制：信标只按「输没输」扣）。
	#
	# ⚠️ 2026-10-01：顺手把**结算那一刻**的原始属性证据抄下来。
	#    理由见 `EveRunState.derive_wreck_tier()` 上方那段：
	#    残骸要在结算后 1 秒才画出来，而这 1 秒里舰队会被重建 ⇒
	#    事后再去读 `EveShip` 上的字段一定读不到。**只有此刻是准的。**
	#    三个数都是「已放大后的读数 ÷ 放大倍率」的反解，不是拍脑袋。
	#
	# ★★ 2026-10-01 用户口径：**敌我双方都捞**。
	#    原实现只把 `_enemy_ships` 的阵亡者塞进来 —— 玩家原话：
	#    「打捞要么只打捞我方的，要么打捞敌我双方的，断然没有只打捞敌方的道理」。
	#    ⇒ 现在两边一起收，`_set_wreck_from()` 仍按**费用最高**挑一艘
	#      （所以「打一场硬仗我方死了一艘大战列」和「零损失全歼」会有不同产出）。
	#    ⚠️ 顺带修掉一个隐藏的不公：只捞敌方时，**输掉的战斗反而必出残骸**
	#      （敌方活着的少 → 我方阵容被打崩），而赢家全歼时也有残骸、
	#      但**输了却全灭**（我方全死、敌方全活）时反倒没有 —— 逻辑是反的。
	var destroyed: Array = []
	var sources: Array = []
	var enemy_alive := 0
	var m_scale := run.enemy_scale()
	var _collect := func(s: EveShip) -> void:
		destroyed.append(s)
		var sb: Dictionary = s._extra
		var atk0 := float(sb.get("attack", s.attack))
		var def0 := float(sb.get("armor_struct", 1.0))
		sources.append({
			"star": int(s.star),
			"atk_base": atk0,
			"def_base": def0,
			"shot": maxf(0.0, float(s.attack)),
			"m": m_scale,
		})
	for s in _enemy_ships:
		if s.alive:
			enemy_alive += 1
		else:
			_collect.call(s)
	# ★ 我方阵亡者也要进打捞池（同一个 `_collect`，证据口径完全一致）。
	for s in _own_ships:
		if not s.alive:
			_collect.call(s)

	# ── 结束原因 ──
	# 见 `battle_end_reason()` 的说明。这里只负责把事实喂进去；
	# `timed_out` = 归零判负那条路（`_forfeit_timeout`）置的位。
	var end_reason := battle_end_reason(_own_ships.is_empty(),
			enemy_alive, _alive_count(0), _timeout_forfeit)

	# ⚠️ 结算前的信标读数必须**先记下来** —— resolve_battle 会就地改 run.beacon，
	#    返回值里的 beacon 是结算后的值，光凭它算不出「掉了多少」。
	var beacon_before := run.beacon
	var res := run.resolve_battle(winner_team, destroyed, sources, m_scale)

	# ── 阶段 D：开战镜头收回 ──
	# 推近是为了看交战，结算就该把构图还回来（不然结算页浮在一个贴脸的特写上）。
	arena.end_battle_shot()
	# 阶段 D④：结算音。`resolve_battle` 已经算完，这里只是报告结果。
	audio.play_resolve()

	hud.set_phase(2)
	hud.set_stage(run.node_index, "结算", 0.0)
	hud.set_start_button("结算中…", false)

	var text := "平局"
	if winner_team == 0:
		text = "拦截成功"
	elif winner_team == 1:
		# ⛔ 这里原来写「被突破」，2026-10-01 改成「拦截失败」——
		#    「突破」这个词是跟着已删除的漏网机制来的，玩家看不懂。
		#    原因那一栏（`end_reason`）另说，会明确写「我方全灭 / 时限耗尽」。
		text = "拦截失败"
	hud.append_log({
		# ⚠️ `sim` 可能为 null（未布阵判负那条路径根本没有模拟器）——
		#    直接读 sim.elapsed 会崩，而且崩在结算里最难查。
		"time": 0.0 if sim == null else sim.elapsed,
		"category": &"economy" if winner_team == 0 else &"damage",
		"text": "%s（%s）· 我方存活 %d／%d · 信标 −%d（剩 %d）" % [
			text, end_reason, _alive_count(0), _own_ships.size(),
			int(res.get("damage", 0)), run.beacon,
		],
	})

	# ── 阶段 D⑤：结算页取代 RESOLVE_SECONDS 的定时自动推进 ──
	# 玩家点「继续 · 下一节点」或「结束本局」之前，这一页一直停着。
	# 见 EveResult 顶部的说明（自动推进 = 把玩家从读者降级成观众）。
	#
	# ★ 2026-10-01：弹窗**不在这一帧弹** —— 延迟 `RESULT_POPUP_DELAY` 秒，
	#   让最后那一下开火线与击毁爆炸播完（用户要求「击毁后一秒弹出」）。
	#   ⚠️ 数据必须在**这里**算好：`resolve_battle()` 已经跑过了，隔一秒再跑
	#      会二次扣血。所以整包存进 `_pending_result`，到点原样交给 HUD。
	_build_result_payload(res, bool(res.get("won", false)), beacon_before,
			destroyed.size(), end_reason)
	_pending_result = _result_payload
	_result_popup_timer = RESULT_POPUP_DELAY
	_resolve_timer = -1.0
	# ⚠️ 我方全灭 / 未部署时**没有**击毁爆炸可看（爆的是自己船，而且
	#    结算页正要盖上来）—— 这时候没必要让玩家干等一秒，立刻弹。
	#    ⛔ 这条**不是**「胜利立刻弹」：胜利时 `_alive_count(0) > 0`，
	#       一定走满延迟 —— 那正是要看的爆炸。
	if _alive_count(0) == 0 or _own_ships.is_empty():
		_popup_result()


## 组装结算页的入参（唯一真相源）。
##
## ⚠️ 抽出来是因为「立刻弹出」与「延迟一秒弹出」两条路都要拿到**同一份**数据。
##    两处各拼一遍字典的话，改一个字段必然漏改另一处 ——
##    而漏改的表现是「某个数在结算页上不对」，不报错。
##
## `won` 从 `res` 里再取一次而不是由调用方传：调用方传的是 `res.get("won")`，
## 两个参数同源，多传一个只会给将来「传错值」留口子。
func _build_result_payload(res: Dictionary, won: bool, beacon_before: int,
		destroyed: int, end_reason: String) -> Dictionary:
	_result_payload = {
		"won": won,
		"damage": int(res.get("damage", 0)),
		"beacon": run.beacon,
		"beacon_before": beacon_before,
		"beacon_max": run.beacon_max(),
		"destroyed": destroyed,
		"alive": _alive_count(0),
		"total": _own_ships.size(),
		"xp": EveRunState.NODE_XP_REWARD,
		"wreck": not run.wrecks.is_empty(),
		"wreck_count": run.wrecks.size(),
		"wreck_name": String((run.wrecks[0] as Dictionary).get("name", "")) \
				if not run.wrecks.is_empty() else "",
		"node": run.node_index,
		"stage": run.stage_label(),
		"ending": _ending_code(),
		"reason": end_reason,
	}
	return _result_payload


## 结局代号（"cleared" / "evacuated" / ""）—— 结算页据此换按钮。
func _ending_code() -> String:
	if run.phase != EveRunState.Phase.ENDING:
		return ""
	return "cleared" if run.ending == EveRunState.Ending.CLEARED else "evacuated"


## 延迟到点 / 特例提前触发：把攒下的结算数据交给结算页。
##
## ⚠️ 幂等：重复调用第二次会被 `_pending_result` 已清空这件事挡住 ——
##    `_process` 的倒计时与「我方全灭立刻弹」两条路都可能调到它。
func _popup_result() -> void:
	if _pending_result.is_empty():
		return
	hud.show_result(_pending_result)
	# ★ 打捞区单独推一次（2026-10-04 改版）。
	#    ⚠️ 为什么不能靠 `show_result()` 自己取：`res` 是**结算 payload**
	#    （{won, beacon, wreck_count, …}），**没有** `state` / `items` ——
	#    拿它当 `salvage_info()` 用，打捞区会永远显示「空」。
	#    ⇒ 两个数据源形状不同，必须由主控显式各推一次。
	_refresh_salvage_area()
	_pending_result = {}
	_result_popup_timer = -1.0


# ── 阶段 D：结算页的两个出口 ──

## 「继续 · 下一节点」→ 推进节点（走的是与旧定时器同一个出口 `_end_resolve`）。
func _on_result_next() -> void:
	if run == null:
		return
	# 结局已经发生（信标归零 / 通关）：这一页上的按钮已经换成「再来一局」，
	# 但玩家也可能在这一刻按 ESC / 快捷键，统一在这里兜住。
	if run.phase == EveRunState.Phase.ENDING:
		hud.hide_result()
		restart_run()
		return
	if run.phase != EveRunState.Phase.RESOLVE:
		return
	# ⚠️ 还有残骸没打捞就点「继续」⇒ 先问一句（参考图 1 那条红字的护栏）。
	#    玩家确认放弃才推进；没有残骸时**静默推进**，不给玩家添堵。
	if not run.wrecks.is_empty():
		_maybe_confirm_leftover_wrecks()
		return
	hud.hide_result()
	_end_resolve()


## 「结束本局」→ 放弃这一局、重开。
##
## ⚠️ 不是「退出进程」：一个自走棋原型里把窗口关掉没有意义，
##    玩家的意图是「这局不打了」，所以落地为 restart_run()。
func _on_result_end() -> void:
	if hud:
		hud.hide_result()
	if run != null and run.phase == EveRunState.Phase.ENDING:
		# 已经结算过结局了，只需要把页面收掉 + 刷一次按钮
		hud.set_start_button("↻ 再来一局", true)
		return
	hud.append_log({"time": 0.0, "category": &"hint", "text": "已结束本局 —— 重新开始"})
	restart_run()


## 结算结束 → 推进节点（或收束到结局）
##
## ⚠️ 阶段 D 之后，本函数的调用方从「定时器到点」变成了「玩家点继续」。
##    `_resolve_timer` 因此不再被设值（保留字段是为了兼容 verify_run 的
##    `debug_skip_resolve` 与旧的无头调用方，见那里的注释）。
func _end_resolve() -> void:
	_resolve_timer = -1.0
	# 阶段 D④：节点推进音。放在 advance() 之前 —— 它代表「这一节点结束了」，
	# 而不是「下一节点开始了」。
	audio.play_node_advance()
	run.advance()
	if run.phase == EveRunState.Phase.ENDING:
		hud.set_phase(2)
		hud.set_stage(run.node_index, "本局结束", 0.0)
		hud.set_start_button("↻ 再来一局", true)
		return
	# 事件节点不用在这里特判 —— begin_prep() 第一个分支就会转给 _enter_event_node()
	begin_prep()


# ══════════════════════════════════════════════════════════════════
#  阶段 C：事件节点（4 / 10 / 14）四选一
# ══════════════════════════════════════════════════════════════════

## 进入事件节点：清空战场 → 面板上台 → 等玩家点。
##
## 为什么**不建任何舰队**（明明可以先摆好我方舰队再让玩家挑）：
##   事件节点没有敌方编组，硬凑一支「我方面对一个空战场」的阵型，
##   只会让玩家以为这里也要开打。清场 + 面板全屏中心，语义最干净：
##   「这一格不是战斗，是一个决定」。挑完立刻进下一节点的正常准备阶段。
##
## 倒计时传 0.0：顶条 tick() 见到 time_left <= 0 就原地返回，
## 不会再广播 timer_expired —— 决策点**没有时限**（与云顶海克斯一致）。
func _enter_event_node() -> void:
	_busy = true
	run.set_phase(EveRunState.Phase.PREP)
	hud.set_phase(0)
	hud.set_selling(false)
	hud.set_bench_drag(-1)
	_resolve_timer = -1.0

	arena.clear_ships()
	_own_ships.clear()
	_enemy_ships.clear()
	_last_field_sig = ""
	_last_roster_sig = ""

	_refresh_run_ui()
	hud.set_stage(run.node_index, "%s · 选择增益" % run.stage_label(), 0.0)
	hud.set_loss_cost(0)
	hud.set_start_button("选择增益", false)

	hud.append_log({
		"time": 0.0, "category": &"system",
		"text": "节点 %d／%d · %s · %s" % [
			run.node_index, EveNodeTable.TOTAL, run.stage_label(),
			run.entry_line(),
		],
	})
	hud.append_log({
		"time": 0.0, "category": &"hint",
		"text": "四条增益里选一条 —— 节点 %s 共用这一套，已获取的不能再选" % _event_idx_text(),
	})
	hud.show_event(run.event_options(),
			run.entry_line(),
			"节点 %d · %d 选 1" % [run.node_index, EveEventTable.count()])
	_busy = false


func _event_idx_text() -> String:
	var parts := PackedStringArray()
	for i in EveNodeTable.event_indexes():
		parts.append(str(i))
	return " / ".join(parts)


## 面板回传：玩家选了某一条。
##
## ⚠️ 校验一律走 `run.apply_event()` 的返回值（空 = 无效 / 已获取），
##    这里不再自己判一遍「是不是选过了」—— 两份判据一定会漂移。
## 事件「选 1 艘」的候选（上场优先、备战席兜底）与缓存。
##
## ⚠️ 卡片里塞的是**条目本体**（引用），选完直接改它 ——
##    不记"第几格"：那样上下场一换位就指错人。
var _ship_pick_cache: Array = []


func _ship_pick_cards() -> Array:
	var src: Array = []
	src.append_array(run.field_entries())
	src.append_array(run.bench_entries())
	var out: Array = []
	for e in src:
		var d := EveShipDatabase.by_id(String(e.get("ship_key", "")))
		if d.is_empty():
			continue
		var st := int(e.get("star", 1))
		out.append({
			"id": StringName("pick_%d" % out.size()),
			"name": String(d.get("name", "?")),
			"tag": &"舰队",
			"icon": &"armor_plate",
			"desc": "★%d · 吨位 %d\nATK %d · 结构 %d" % [
				st, int(d.get("cost", 1)), int(d.get("attack", 0)), int(d.get("armor", 0))],
			"entry": e,
		})
	return out


func _on_event_chosen(id: StringName) -> void:
	if run == null or run.phase != EveRunState.Phase.PREP:
		return
	if not hud.event_is_open():
		return
	# ★ 需要选船的（武器调校 / 结构加固）：先收起四选一，让玩家点一艘船。
	#   ⛔ 不在这里直接 `apply_event` —— 没有目标的话它会返回 {}，
	#      面板那边看起来就像"点了没反应"。
	var opt0 := EveEventTable.by_id(id)
	if bool(opt0.get("pick_ship", false)):
		_ship_pick_cache = _ship_pick_cards()
		if _ship_pick_cache.is_empty():
			# 连备战席都是空的 ⇒ 这条根本没法落地，让玩家换一条
			hud.append_log({"time": 0.0, "category": &"hint",
					"text": "一艘船都没有 ——「%s」要指定一艘船，先换一条"
							% String(opt0.get("name", id))})
			return
		_pending_event = id
		hud.hide_event()
		hud.show_ship_pick(_ship_pick_cache, "选 1 艘船 —— 本局永久生效",
				"节点 %d · %s" % [run.node_index, String(opt0.get("name", id))])
		return
	_apply_event_and_advance(id, {})


func _on_event_ship_picked(index: int) -> void:
	if run == null or run.phase != EveRunState.Phase.PREP or _pending_event == &"":
		return
	if index < 0 or index >= _ship_pick_cache.size():
		return
	var entry: Dictionary = _ship_pick_cache[index].get("entry", {})
	var id := _pending_event
	_pending_event = &""
	hud.hide_ship_pick()
	_apply_event_and_advance(id, entry)


## 落地 + 推进。选船路径与四选一路径**共用这一段** —— 推进逻辑只有一份。
func _apply_event_and_advance(id: StringName, target: Dictionary) -> void:
	var opt := run.apply_event(id, target)
	if opt.is_empty():
		hud.append_log({"time": 0.0, "category": &"hint",
				"text": "这条增益没生效（已获取过，或没选到船）—— 换一条"})
		# 退回四选一：选船那条路径已经把面板收起来了，得把它放回来
		if not hud.event_is_open():
			hud.show_event(run.event_options(), run.entry_line(),
					"节点 %d · %d 选 1" % [run.node_index, EveEventTable.count()])
		return
	hud.hide_event()

	# 事件节点不占一个回合：选完直接推进到下一节点，走它的正常准备阶段。
	run.advance()
	if run.phase == EveRunState.Phase.ENDING:
		hud.set_phase(2)
		hud.set_stage(run.node_index, "本局结束", 0.0)
		hud.set_start_button("↻ 再来一局", true)
		return
	begin_prep()


# ══════════════════════════════════════════════════════════════════
#  主循环
# ══════════════════════════════════════════════════════════════════

func _process(delta: float) -> void:
	if run == null:
		return
	# ⚠️ 暂停 = **整个推进停摆**，不只是战斗 sim：
	#    准备阶段的倒计时（`hud.tick_stage`）也必须停 ——
	#    否则「暂停了 30 秒，回来发现准备时间没了、自动开战了」，
	#    那是最让人恼火的一种假暂停。视觉同步（`arena.sync_ships`）同理：
	#    它在暂停期间照常跑的话，舰艏会继续转向、镜头插值继续走，
	#    画面看着在动而数字不动，玩家会以为暂停坏了。
	if _paused:
		return

	match run.phase:
		EveRunState.Phase.PREP:
			# 准备阶段：不推战斗，只走倒计时
			hud.tick_stage(delta)
			_tick_countdown_sfx()

		EveRunState.Phase.BATTLE:
			if not _paused and sim != null and not sim.finished:
				sim.step(delta * time_scale)
				_sync_log()
				_check_sudden_death()
			if sim != null:
				arena.sync_ships(sim.ships, delta)
			hud.tick_stage(delta)
			_tick_countdown_sfx()

		EveRunState.Phase.RESOLVE:
			# ⚠️ 阶段 D 起，RESOLVE 阶段**不再自动推进** —— 结算页停在那里
			#    等玩家点「继续 · 下一节点」。`_resolve_timer` 只剩一条路会用：
			#    无头验收 / 调试路径显式设了它（那种情况下仍按定时器收尾，
			#    免得旧的测试脚本全部要改）。
			#
			# ★ 2026-10-01：结算页**弹出**也有一个计时器（方向相反的另一个）。
			#   期间让 `arena.sync_ships` 与特效继续跑 —— 这一秒的看点就是
			#   最后那一下开火线与击毁爆炸（用户要求「击毁后一秒弹出」）。
			#   ⚠️ `sim.step()` **不在这里**：战斗已结束，`finished` 后
			#      `sim.step` 是空转；不调它反而让 `elapsed` 冻在结束时刻，
			#      结算页上那一行日志的时间戳才是对的。
			if _result_popup_timer > 0.0:
				_result_popup_timer -= delta
				if _result_popup_timer <= 0.0:
					_popup_result()
			if sim != null:
				arena.sync_ships(sim.ships, delta)
			if _resolve_timer > 0.0:
				_resolve_timer -= delta
				if _resolve_timer <= 0.0:
					hud.hide_result()
					_end_resolve()

		_:
			pass


func _alive_count(team: int) -> int:
	var pool: Array[EveShip] = _own_ships if team == 0 else _enemy_ships
	var n := 0
	for s in pool:
		if s.alive:
			n += 1
	return n


## 当前场上所有的船（准备阶段没有模拟器，所以要从两份名单拼）
func _all_ships() -> Array[EveShip]:
	var out: Array[EveShip] = []
	out.append_array(_own_ships)
	out.append_array(_enemy_ships)
	return out


# ══════════════════════════════════════════════════════════════════
#  日志桥接
# ══════════════════════════════════════════════════════════════════

var _logged_count := 0
## 火力渐增是否已经播报过（只播一次）
var _sd_announced := false
## ★ 本场战斗是否以「时限归零判负」收场（2026-10-04 恢复归零判负）。
##    置位后由 `_on_battle_finished` 传给 `battle_end_reason`，
##    让结算页显示「时限耗尽」而不是笼统的「我方全灭」。
##    ⚠️ `start_battle()` 里复位 —— 不复位的话上一场的标志会污染下一场
##      （「明明打赢了却显示时限耗尽」，极难排查的那种幽灵 bug）。
var _timeout_forfeit := false

func _sync_log() -> void:
	if sim == null:
		return
	if _logged_count >= sim.log_entries.size():
		return
	for i in range(_logged_count, sim.log_entries.size()):
		hud.append_log(sim.log_entries[i])
	_logged_count = sim.log_entries.size()


func _on_run_log(text: String, category: StringName) -> void:
	hud.append_log({
		"time": sim.elapsed if sim != null else 0.0,
		"category": category,
		"text": text,
	})


# ══════════════════════════════════════════════════════════════════
#  状态机 → HUD
# ══════════════════════════════════════════════════════════════════

## 经济 / 等级 / 信标 / 上场上限 / 备战席 → HUD
func _refresh_run_ui() -> void:
	if run == null:
		return
	# ⚠️ 满级后经验没有去处（超频走星币），所以这里把「超频进度」当经验条显示。
	#    读数会是 "Lv.6 · 1 / 2" —— 语义是「超频档 1／2」，不是「等级经验 1/2」。
	var xp_now := run.xp_in_level()
	var xp_need := run.xp_need()
	if run.level >= EveRunState.MAX_LEVEL:
		xp_now = run.overtier
		xp_need = EveRunState.MAX_TIER - EveRunState.MAX_LEVEL
	hud.set_economy(run.coin, run.level, xp_now, xp_need,
			EveRunState.REFRESH_COST, EveRunState.BUY_XP_COST)
	hud.set_bench(run.bench_used(), EveRunState.BENCH_SLOTS)
	# ⚠️ 上限要用 run.beacon_max()：事件「信标增幅器」会把上限抬高 20。
	#    写死 START_BEACON 的话，顶条的信标色带（>60% 绿 / >30% 橙）就会按错的分母算，
	#    玩家看到的是「满血却是橙字」。
	hud.set_beacon(run.beacon, run.beacon_max())
	hud.set_shop_locked(run.shop_locked)
	# ★ 商店买卖闸门也在这里兜一次：`_on_phase_changed` 只在**变化时**触发，
	#   而开局第一个 PREP 是「本来就是 PREP」⇒ 那条路不会响。
	#   幂等（值没变直接 return），放这儿零成本。
	hud.set_shop_buy_enabled(run.phase == EveRunState.Phase.PREP)
	hud.set_augments(run.picked_event_info())
	# 打捞框：`salvage_info()` 是唯一输入源，三态（无 / 可下单 / 修复中）都在里面判，
	# 场景这一侧不重复判一遍「有没有残骸」—— 判据写两份必然分叉。
	hud.set_salvage(run.salvage_info())
	# 备战席立绘（2D，画在 EveBenchRail 的格子里）。
	# ⚠️ 2026-09-23：入口从 arena.bench_stage.update_fleet 换成这里 ——
	#    3D 备战层已停用（原因与回退方法见 EveBenchStage 头注释）。
	#    对比一下旧写法：那条路径要经过「3D 场景 → 反投影 → 每帧重算 transform」，
	#    而现在只是一次「把名单交给 HUD 重绘」，链路短了一整层。
	hud.set_bench_fleet(run.bench_entries())

	# 上场名单变了 → 重建我方舰队（只在准备阶段做；战斗中重建会把正在打的船换掉）
	# ⚠️ 拖动期间也不重建：万一有哪条路径在拖动中 emit 了 changed，
	#    重建会把正被拖着的那艘船换掉，幽灵和真船对不上号。
	if not _busy and _drag.is_empty() and run.phase == EveRunState.Phase.PREP:
		if _field_signature() != _last_field_sig:
			_respawn_own_fleet()


func _on_offers_changed() -> void:
	hud.set_shop_offers(run.offers)


func _on_phase_changed(phase: int) -> void:
	# 阶段名由 begin_prep / start_battle / 结算各自设置（它们更清楚上下文），
	# 这里只兜一件事：战斗结束的那一帧把「开战」按钮收回来。
	if phase == EveRunState.Phase.BATTLE:
		hud.set_start_button("交战中", false)

	# ★ 2026-10-05：**商店买卖的阶段闸门**。
	#    商店面板是常驻的，非准备阶段卡片照样亮着 —— 点下去只会被
	#    `buy()` 以「只有准备阶段能买船」拒绝，而卡片本身毫无变化，
	#    玩家会当成「点了没反应 / 买了没到手」。
	#    ⇒ 非准备阶段把整排卡压暗并停发请求。
	hud.set_shop_buy_enabled(phase == EveRunState.Phase.PREP)

	# ── 阶段 D④：阶段环境音 + BGM 切换 ──
	#
	# ⚠️ 这是**唯一的**阶段音入口。begin_prep / start_battle / resolve 各自
	#    还会设 HUD 文案，但声音只在这里发一次 —— 否则「开战」会响两遍
	#    （一次来自这里、一次来自 start_battle 自己的提示音）。
	audio.play_phase(phase)
	# ★ 2026-10-10：守卫边境的 BGM 改成**按节点分段**，不再按准备/交战分曲。
	#
	# ⚠️ 为什么要这么改：准备→交战→结算**每个节点都要走一遍**，按阶段切曲
	#    意味着每回合都交叉淡入淡出两次（1.2s × 2），一场 15 节点淡 30 次 ——
	#    听感是「音乐一直在找方向」。分段后整局只在第 11 个节点换一次曲。
	match phase:
		EveRunState.Phase.PREP, EveRunState.Phase.BATTLE, EveRunState.Phase.RESOLVE:
			audio.play_music(_round_music())
		_:
			audio.play_music("")


## 守卫边境的 BGM 分段节点（前 10 个节点一段，第 11 起是终局段）。
##
## ⚠️ 写死成常量而不是由 `EveNodeTable.TOTAL` 算：分段点是**设计值**
##    （用户 2026-10-10 定），改它要连音源一起换，不是「节点数变了就跟着变」。
const MUSIC_ROUND_SPLIT := 10


## 按**当前节点**选 BGM 逻辑名（逻辑名 = 文件名去掉末尾 `_NN`，见 `EveAudio._scan_dir`）：
##    节点 1~10   → `"border"`        （`border_01.ogg`，80s 无缝循环）
##    节点 11~15  → `"border_final"`  （`border_final_01.ogg`，96s 无缝循环）
##
## ⚠️ 判据用 `run.node_index`（唯一真相源）而不是自己数阶段：
##    `EveRunState.advance()` 先 `node_index += 1` 再发 `phase_changed`，
##    所以这里读到的**已经是新节点**，第 11 节点那一帧就换曲。
func _round_music() -> String:
	return "border" if run.node_index <= MUSIC_ROUND_SPLIT else "border_final"


func _on_run_ended(cleared: bool) -> void:
	hud.set_start_button("↻ 再来一局", true)
	hud.append_log({
		"time": 0.0, "category": &"economy" if cleared else &"damage",
		"text": "═══ 本局结束：%s · 节点 %d／%d · 信标 %d ═══" % [
			"通关" if cleared else "撤离", run.node_index,
			EveNodeTable.TOTAL, run.beacon,
		],
	})


# ══════════════════════════════════════════════════════════════════
#  玩家操作
# ══════════════════════════════════════════════════════════════════

func _on_start_battle_requested() -> void:
	match run.phase:
		EveRunState.Phase.PREP:
			start_battle()
		EveRunState.Phase.RESOLVE:
			_end_resolve()
		EveRunState.Phase.ENDING:
			restart_run()
		_:
			pass   # 战斗中点了没用


## 倒计时滴答音（阶段 D④）。
##
## ⚠️ 触发条件是「秒数**变了**」而不是「每帧」：
##    60fps 下每帧调一次 tick 音会变成一片噪音，而且和视觉上「数字在跳」
##    对不上。这里用 `_last_tick_second` 做去重，一秒一响。
##
## ⚠️ 只在最后 10 秒响。整段 30 秒的倒计时从头滴到尾会很烦 ——
##    急促的滴答是「要来不及了」的信号，从头响就等于没有信号。
##
## ⚠️ 准备阶段的最后 3 秒换成 `play_countdown`（3 / 2 / 1）：
##    滴答和读秒是**两件事** —— 滴答是「还在等」，读秒是「马上开打」，
##    音色必须分开，否则玩家分不出 5 秒和 2 秒的区别。
func _tick_countdown_sfx() -> void:
	var sec := hud.stage_seconds_left()
	if sec <= 0:
		return
	if sec == _last_tick_second:
		return
	_last_tick_second = sec
	if run.phase == EveRunState.Phase.PREP and sec <= 3:
		audio.play_countdown(sec)
	elif sec <= 10:
		audio.play_tick(sec)


func _on_stage_timer_expired() -> void:
	# ★★ 战斗时限归零 ⇒ **判负**（2026-10-04 用户口径恢复）。
	#
	#   用户原话：「在我们的设计里面，归零是该直接判负并扣除信标HP的，
	#   惩罚很严重的。」
	#
	#   ⚠️ 口径史（别再改回去时找不到出处）：
	#   · 2026-10-01 曾按用户「自走棋就该打到被击毁」改成**超时不判负**，
	#     彼时火力渐增（60%→∞）负责保证战斗收敛；
	#   · 2026-10-04 用户明确「归零判负并扣信标 HP」—— **以后者为准**。
	#   ⇒ 火力渐增的职责随之变回「帮玩家**在时限内**清场」（60%→100% 渐增到
	#     5 倍），时限归零那一刻战斗直接结束，不存在「超时继续加伤」的阶段。
	#
	#   ⚠️ 走 `_on_battle_finished(1)`（敌方胜）—— 与战败**同一条结算路径**：
	#      扣信标 / 连败 / 打捞 / 经验全走既有逻辑，⛔ 不另造第二份真相源。
	#      （同 `_forfeit_no_deploy` 的做法与理由。）
	if run.phase == EveRunState.Phase.BATTLE:
		_forfeit_timeout()
		return
	if run.phase != EveRunState.Phase.PREP:
		return
	# ★ 2026-10-01：准备时间到、**一条船都没上** ⇒ 直接判本节点负。
	#
	#   原行为是「什么都不做，停在那里」，用户原话：
	#   「倒计时完之后还没有拖船上棋盘，现在的状态是会暂停，没有任何动作，
	#     这不行，得改成直接判负，就是这一回合判我输。」
	#
	#   ⚠️ 顺手堵掉一条白嫖规则：原来"不布阵"既不用打、也不掉血 ——
	#      等于可以靠不操作无限拖延。
	if run.field.is_empty():
		print("[对局] 准备时间到 · 场上 0 艘 ⇒ 判负（节点 %d）" % run.node_index)
		_forfeit_no_deploy()
		return
	if not auto_start_on_timeout:
		hud.append_log({"time": 0.0, "category": &"hint",
				"text": "准备时间到（自动开战已关闭，布好阵后点「开战」）"})
		return
	hud.append_log({"time": 0.0, "category": &"system", "text": "准备时间结束 —— 自动开战"})
	start_battle()


## 未布阵判负 —— **走和正常战败完全同一条结算路径**。
##
## ⛔ 不另造一条「直接扣血 / 直接推进」的分支：那会变成第二份真相源 ——
##    扣血公式、连胜连败、残骸、经验……每加一条规则都要记得改两处。
##    这里只是喂给 `_on_battle_finished(1)`：敌舰一艘没死，
##    它自己会走「未部署」这条结束原因，后面的扣血与推进全走既有逻辑。
func _forfeit_no_deploy() -> void:
	hud.append_log({"time": 0.0, "category": &"damage",
			"text": "准备时间结束 —— 未部署任何舰船，本节点判负"})
	_on_battle_finished(1)


## ★ 战斗时限归零判负（2026-10-04 恢复，见 `_on_stage_timer_expired` 的口径史）。
##
## ⚠️ 三个必须：
##   ① `sim.finished = true` 停掉模拟器 —— 不停的话 `_process` 的 BATTLE 分支
##      还会继续 `sim.step()`，结算页都弹出来了战斗还在打（幽灵战斗）。
##   ② `_timeout_forfeit = true` —— 让结算页显示「时限耗尽」而不是「我方全灭」
##      （此刻我方往往还有活船，不标记的话 reason 会算成「僵持收场」，看不懂）。
##   ③ 走 `_on_battle_finished(1)` —— 扣信标走的是既有战败公式，
##      ⛔ 不在这里手写「直接扣 N 点」（第二份真相源）。
func _forfeit_timeout() -> void:
	if sim != null:
		sim.finished = true
	_timeout_forfeit = true
	hud.append_log({"time": 0.0, "category": &"damage",
			"text": "战斗时限归零 —— 未能在时限内清场，本节点判负"})
	_on_battle_finished(1)


func _on_shop_buy(index: int) -> void:
	var r := run.buy(index)
	if not bool(r.get("ok", false)):
		hud.append_log({"time": 0.0, "category": &"hint",
				"text": String(r.get("reason", "买不了"))})


func _on_shop_refresh() -> void:
	var r := run.refresh()
	if not bool(r.get("ok", false)):
		hud.append_log({"time": 0.0, "category": &"hint",
				"text": String(r.get("reason", "刷新失败"))})


func _on_shop_levelup() -> void:
	var r := run.levelup()
	if not bool(r.get("ok", false)):
		hud.append_log({"time": 0.0, "category": &"hint",
				"text": String(r.get("reason", "加速失败"))})


## ★★ 打捞区（2026-10-04 改版：按钮在结算页**下方**，逐艘直接点「打捞」）
##
## 版式依据（用户 2026-10-04 原话）：「我想把打捞做成这样在**后面的按钮**的，
## 现在在前面点选有点反直觉了」+ 两张参考图。
## ⇒ 不再是「顶部一个按钮 → 弹浮层 → 勾选 → 确认」两段式，
##   改成结算页下方直接展开列表，**每艘右侧一个「打捞」按钮，点哪艘算哪艘**。
##
## ⚠️ 另一条护栏（参考图 1 的红字）：「本回合不决定，这 N 艘残骸永久作废」
##    ⇒ 玩家点「继续 · 下一节点」时若还有残骸没处理，弹二次确认。

## 点某一艘的「打捞」按钮。
##
## ⚠️ 结算页可能在这一刻已被关掉（玩家先点了「继续」）——
##    那时 `phase` 已经不是 RESOLVE，`salvage_order()` 会自己拒绝，
##    这里只负责把拒绝理由报给玩家，不做任何状态假设。
func _on_salvage_pick_one(idx: int) -> void:
	if run == null:
		return
	var r := run.salvage_order([idx])
	if not bool(r.get("ok", false)):
		hud.append_log({"time": 0.0, "category": &"hint",
				"text": String(r.get("reason", "打捞失败"))})
		_refresh_salvage_area()
		return
	hud.append_log({"time": 0.0, "category": &"salvage",
			"text": "打捞 %s −%d ◆ · 下一节点到账（占 1 个货位）"
			% [", ".join(r.get("names", [])), int(r.get("paid", 0))]})
	_refresh_salvage_area()


## 点「关闭」→ **只收起打捞区**（不下单、不推进）。
##
## ⚠️ 残骸**仍在  里**，玩家可以在结算页继续点「继续 · 下一节点」
##    重新打开它（下次  会再推一次）。
func _on_salvage_section_closed() -> void:
	pass


## 确认「放弃剩余残骸」→ 关掉结算页、推进到下一节点。
##
## ⚠️ 这里**必须真的推进**，不能只刷新 UI：确认框是「放弃打捞并继续」的
##    唯一出口，不接上推进玩家就被卡在结算页（点「继续」只会再弹一次框）。
func _on_salvage_pick_zero() -> void:
	if run == null or run.phase != EveRunState.Phase.RESOLVE:
		return
	hud.hide_result()
	_end_resolve()


## ★ 把 `run.salvage_info()` 推给结算页的打捞区（**唯一输入源**）。
##
## ⚠️ 顺带做一件容易被漏掉的事：**如果玩家还有残骸没处理就点「继续」，
##    必须拦一下**（用户参考图 1 的红字警告就是这个意思）。
##    这里只在「真的有残骸」时弹框 —— 没有残骸时静默推进，不给玩家添堵。
func _maybe_confirm_leftover_wrecks() -> void:
	if run == null:
		return
	var info := run.salvage_info()
	if String(info.get("state", "")) != "list" or run.wrecks.is_empty():
		return
	var res_win = hud.get("result_window")
	if res_win == null:
		return
	var ask: ConfirmationDialog = res_win.get("_salvage_ask")
	if ask == null:
		return
	ask.dialog_text = "本回合还有 %d 艘残骸没有打捞。\n确定要放弃吗？" % run.wrecks.size()
	ask.popup_centered(Vector2i(400, 176))


## 重画打捞区（下单 / 取消后都要调）。
func _refresh_salvage_area() -> void:
	if hud == null or run == null:
		return
	var res_win = hud.get("result_window")
	if res_win == null:
		return
	# ⚠️ 结局页（ENDING）不给打捞区：局已经结束了，残骸没有意义。
	var ended := run.phase == EveRunState.Phase.ENDING
	res_win.refresh_salvage(run.salvage_info(), ended)
## ⚠️ 旧入口：商店面板那个小打捞框（`EveShop` 的 `_slv_box`）。
##    2026-10-04 起打捞搬到结算页，这里**只保留日志报错**，
##    不再下单 —— 免得两条路径都能扣钱、状态机却只认一条。
##    ⛔ 别删这个函数：`hud.salvage_requested` 仍连着它，删了会运行时报错。
func _on_salvage() -> void:
	if run == null:
		return
	var info := run.salvage_info()
	if String(info.get("state", "")) == "list":
		hud.append_log({"time": 0.0, "category": &"hint",
				"text": "打捞在**战斗结算页下方** —— 打完那页的「⚓ 打捞 残骸」区逐艘点"})
	else:
		hud.append_log({"time": 0.0, "category": &"hint",
				"text": "本回合没有可打捞的残骸"})


func restart_run() -> void:
	arena.clear_ships()
	# 阶段 D：重开一局要把特效与两个新面板都收干净
	arena.fx_clear()
	# 阶段 D④：音频也要收干净 —— 不清的话上一局的爆炸音会飘进新一局的布阵台，
	# 而且 `_last_tick_second` 会跨局残留（新一局第一次滴答被误判为「没变」）。
	audio.stop_all()
	audio.reset_stats()
	_last_tick_second = -1
	arena.end_battle_shot()
	hud.hide_result()
	hud.hide_settings()
	hud.clear_damage()
	hud.hide_entry()
	_next_ship_id = 1
	sim = null
	# 重开 = 硬重置：直接把暂停态清掉并撤遮罩。
	#
	# ⚠️ 不走 `set_paused(false)` —— 它在「本来就没暂停」时会 early return，
	#    而重开必须**无条件**保证遮罩是收起的（否则新一局开局就蒙着一层灰）。
	_paused = false
	hud.set_paused(false)
	hud.sync_settings_pause(false)
	_resolve_timer = -1.0
	# ★ 2026-10-01：延迟弹窗的状态也要清 —— 不清的话「上一局结束时正好处在
	#   延迟中 → 玩家点了结束本局 → 1 秒后新一局的布阵台上弹出一张旧结算页」。
	_result_popup_timer = -1.0
	_pending_result = {}
	_result_payload = {}
	_last_field_sig = ""
	hud.clear_log()
	hud.set_selling(false)
	run.start_run()
	begin_prep()


# ══════════════════════════════════════════════════════════════════
#  阶段 D：设置窗
# ══════════════════════════════════════════════════════════════════
#
# ⚠️ 这里所有 handler 的共同约定：**改的是 arena 的真实状态**，
#    改完不回头去刷设置窗的按钮 —— 窗里的按钮就是玩家刚点的那个，
#    它自己已经切好皮肤了。回刷会引入「谁是真相源」的歧义。
#    唯一的例外见 _sync_settings_ui()（键盘改的，窗不知道）。

## 打开设置窗（顶条 ≡）。必须先把**当前真实状态**回写进窗里。
func _on_settings_requested() -> void:
	if hud.settings_is_open():
		# 再点一次 = 收起。这比强制玩家去找关闭按钮友好。
		hud.hide_settings()
		return
	# ⚠️ 打开时必须回写**全部**真实状态（含音量与暂停态）——
	#    否则玩家看到的开关与实际不符，点一下反而改成了他不想要的那个。
	var vols := audio.volumes()
	hud.show_settings({
		"background": arena.current_background_id(),
		"mood": int(arena.render_mood),
		"fog": bool(arena.enable_space_fog),
		"rings": arena.range_layer != null and arena.range_layer.visible,
		"board": arena.board != null and arena.board.visible,
		"paused": _paused,
		# ⚠️ 现读存档而不是缓存字段：玩家在窗里改完就写盘了，
		#    缓存一份必然会和盘上漂移（表现 = 重开窗高亮跑位）。
		"ui_scale": float(SETTINGS_STORE.load_all().get("ui_scale", 0.0)),
		# ⚠️ 分辨率传**解析后的档位下标**（不是存档里的 key）——
		#    存档空串是「自动」，窗里要亮的是"实际生效的那一档"。
		"resolution_index": RESOLUTION.current_index(),
		# ⚠️ 字号传**当前生效值**（`FONT.scale`）而不是存档原值：存档里 0.0
		#    是「没设过」，真正生效的是平台出厂默认（桌面 1.10 / 移动 1.20）
		#    —— 传原值会让滑杆停在 0 位上（显示成 0%，玩家一看就懵）。
		"font_scale": FONT.scale,
		"muted": bool(vols.get("muted", false)),
		"volumes": vols,
	})


func _on_settings_background(id: String) -> void:
	if arena.set_background(id):
		hud.append_log({"time": 0.0, "category": &"system",
				"text": "天空盒 → %s" % id})
	else:
		# ⚠️ set_background 对不存在的 id 返回 false。静默失败的话，
		#    玩家点了一个坏条目，画面不动、也没有任何解释。
		hud.append_log({"time": 0.0, "category": &"hint",
				"text": "天空盒 %s 加载失败（资源缺失）" % id})


func _on_settings_mood(mode: int) -> void:
	arena.render_mood = mode
	arena._build_environment()
	hud.append_log({"time": 0.0, "category": &"system",
			"text": "显示模式 → %s" % ("通透" if mode == 0 else "氛围")})


func _on_settings_fog(on: bool) -> void:
	arena.enable_space_fog = on
	arena._build_environment()
	hud.append_log({"time": 0.0, "category": &"system",
			"text": "空间雾 %s" % ("开" if on else "关")})


func _on_settings_board(on: bool) -> void:
	# ⚠️ 走 set_board_visible 而不是 toggle_board() ——
	#    设置窗给的是**目标状态**，toggle 给的是「翻一下」。
	#    两者在「窗里显示开、实际是关」这种不同步状态下的结果相反。
	arena.set_board_visible(on)
	_board_auto = false
	hud.append_log({"time": 0.0, "category": &"system",
			"text": "棋盘 %s" % ("显示（11×11）" if on else "隐藏")})


func _on_settings_camera_reset() -> void:
	arena.reset_camera()


## 设置窗「放弃本局 · 回主界面」→ 切回主菜单。
## ⚠️ 直接 change_scene：这一局的状态（信标/星币/关卡进度）**不保留**，
##    所以设置窗里那个按钮写的是"放弃本局"。等有了存档再改成"离开"。
func _on_settings_back_to_menu() -> void:
	print("[主控] 放弃本局 → 返回主界面")
	set_paused(false)
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func _on_settings_restart() -> void:
	hud.append_log({"time": 0.0, "category": &"system", "text": "重开一局"})
	restart_run()


## 暂停 / 继续的**唯一入口**。
##
## ══ 三条路都走这里 ════════════════════════════════════════════════
##    设置窗的暂停按钮 · 键盘空格 · 暂停遮罩上的「继续」按钮。
##  三条路各写一遍 `_paused = x` 的后果是必然的：漏一个回写就出现
##  「场上停着、按钮写着暂停」或者「遮罩还在、游戏已经在跑」——
##  这类不一致**不报错**，只在玩家手里发作。
##
## ⚠️ 暂停是【全局】的：准备阶段也要能停（PVE 也要），
##    所以它不是「战斗 sim 的一个开关」，而是整个 `_process` 的闸门。
func set_paused(on: bool) -> void:
	if _paused == on:
		return
	_paused = on
	hud.set_paused(on)
	# ⚠️ 回写设置窗的按钮：键盘空格改的状态，窗自己不知道
	hud.sync_settings_pause(on)
	hud.append_log({"time": sim.elapsed if sim != null else 0.0,
			"category": &"system",
			"text": "已暂停 · 操作已锁定（空格 / 设置窗「继续对局」恢复）"
					if on else "继续"})


func _on_settings_pause(on: bool) -> void:
	set_paused(on)


func _on_settings_volume(kind: StringName, v: float) -> void:
	audio.set_volume(kind, v)


func _on_settings_mute(on: bool) -> void:
	audio.set_muted(on)


## 把 `user://settings.cfg` 里的偏好应用到这一局（音量 / 静音 / 天空盒 / 显示模式）。
##
## ⚠️ 只应用「玩家偏好」—— 雾 / 射程环 / 棋盘是**场上状态**，
##    读出来覆盖的话会出现「上局收尾时棋盘是关的 ⇒ 新一局开局也是关的」。
##    （它们因此也不进持久化表，见 EveSettingsStore 的说明。）
func _apply_saved_settings() -> void:
	var s := SETTINGS_STORE.load_all()
	audio.set_volume(&"master", float(s.get("master", 1.0)))
	audio.set_volume(&"sfx", float(s.get("sfx", 0.60)))
	audio.set_volume(&"amb", float(s.get("amb", 0.39)))
	audio.set_volume(&"music", float(s.get("music", 0.32)))
	audio.set_muted(bool(s.get("muted", false)))
	# ★ 平台缩放档（2026-10-07）：移动端放大 + 紧凑档；桌面端 resolve() 恒 1.0
	#   ⇒ `apply_ui_profile()` 会因为「档位没变」直接返回，一个字节都不动。
	#   ⚠️ 必须在 `_build_layout()` 之后此刻调（HUD 的 _ready 已经跑完），
	#      同一帧内完成 ⇒ 不会闪一帧错位的布局。
	hud.apply_ui_profile(UI_SCALE_SCRIPT.resolve(float(s.get("ui_scale", 0.0))))
	var bid := String(s.get("background", ""))
	if not bid.is_empty():
		arena.set_background(bid)
	arena.render_mood = int(s.get("mood", 0))
	arena._build_environment()


## ⚠️ DEBUG-ONLY: 设置窗里"加币"按钮的处理器，发布时删除。
## 走 `run.coin += amt` + 调 `_refresh_run_ui()` 走标准刷路径（经济栏 / HUD / 商店可买性一并更新）。
## 不绕过 run_state 的 `_deny()` / `log_event` —— 调试按钮也得**走规则**，方便抓退路。
func _on_settings_add_coins(amt: int) -> void:
	if run == null or amt <= 0:
		return
	run.coin += amt
	hud.append_log({"time": 0.0, "category": &"economy",
			"text": "[DEBUG] 星币 +%d（当前 %d）" % [amt, run.coin]})
	_refresh_run_ui()


## 键盘改了会影响设置窗显示的状态时，回写窗里的按钮。
##
## ⚠️ 不这么做的话会出现「窗里写 [关]、实际棋盘是开的」——
##    玩家下一次点它，会把棋盘从「显示」切成「隐藏」，
##    而他以为自己在打开它。键盘与窗口是同一份状态的两条入口，必须同步。
func _sync_settings_ui() -> void:
	if not hud.settings_is_open():
		return
	hud.sync_settings_toggle("board",
			arena.board != null and arena.board.visible)
	hud.sync_settings_toggle("rings",
			arena.range_layer != null and arena.range_layer.visible)


func _on_stance_changed(ship: EveShip, stance: int) -> void:
	var visual := arena.get_ship_visual(ship.id)
	if visual and visual.has_method("refresh_stance"):
		visual.refresh_stance()
	hud.append_log({
		"time": sim.elapsed if sim != null else 0.0, "category": &"system",
		"text": "%s 切换姿态：%s" % [ship.ship_name, EveDestinyMotion.stance_label(stance)],
	})


func _on_unit_destroyed(ship: EveShip) -> void:
	# 选中船被摧毁时保留信息（显示为已损毁状态）—— 这里不改选中，
	# 因为战斗结束后玩家多半还想回看那艘船的数据。
	#
	# ── 阶段 D②：击毁反馈 ──
	# 爆炸挂在那艘船【当时的位置】上。ship.body.position 是米。
	arena.fx_boom(ship.body.position)
	# 阶段 D④：击毁爆炸音。放在视觉之后 —— 先看见再听见，
	# 顺序反了会觉得「声音提前了」（虽然间隔只有一帧）。
	# ⚠️ 一样要先喂模拟器时间，否则快进时被节流吞掉。
	if sim != null:
		audio.set_clock(float(sim.elapsed))
	audio.play_boom()
	hud.append_log({
		"time": sim.elapsed if sim != null else 0.0, "category": &"damage",
		"text": "%s 结构崩溃 · 爆炸解体" % ship.ship_name,
	})
	# ⚠️ 视觉节点此刻起不可见（sync_from_body 见到 alive=false 会隐藏它）。
	#    Label3D 不带 no_depth_test 的话会跟着一起消失，这里不做额外处理 ——
	#    船没了就是没了，留一个浮空的名字反而像 bug。


## 开火：画曳光 + 冒伤害数字（阶段 D②③）
##
## ⚠️ 这个回调在 **sim.step() 的一次调用里可能被触发上百次**
##    （固定步长的 tick 循环）。所以它里面【绝不能】做重活 ——
##    一切只是 add_child 一个 quad / 往数组里压一条记录。
##    verify_run 的 `debug_fast_forward_battle` 一次快进 90 秒，
##    就是靠这条约束才不会卡死。
func _on_shot_fired(attacker: EveShip, target: EveShip, hit: bool,
		quality: int, damage: float) -> void:
	if attacker == null or target == null:
		return
	arena.fx_tracer(attacker.body.position, target.body.position, hit, quality)
	# 阶段 D④：开火 + 命中音。
	#
	# ⚠️ 这两行的调用频率极高（一次 sim.step 里可能上百次），
	#    但 `play_fire` / `play_hit` 内部**第一件事就是查节流表**，
	#    被吞掉时只加一个计数器就返回 —— 不做任何采样加载或节点操作。
	#    所以这里的成本是「一次字典查表」，不会拖慢快进。
	#
	# ⚠️ 先把**模拟器时间**喂给音频层（见 EveAudio.set_clock）：
	#    节流必须按战斗时间来，否则快进 / 倍速时一整场只响一两声。
	if sim != null:
		audio.set_clock(float(sim.elapsed))
	audio.play_fire(quality)
	if not hit:
		# 未命中也有信息量（「打空了」），但不画爆点、不冒数字 ——
		# 一次齐射里 60% 是未命中，全冒出来会糊满整个屏幕。
		# 声音侧同理：未命中只响开火音，**不**响命中音 ——
		# ⚠️ 早期版本这里误调了 `play_hit(quality)`：品质 0 会去查 "miss" 音源，
		#    查不到就退回通用 "hit"，于是「打空了」反而播出一声命中 ——
		#    而且不报错。
		return
	audio.play_hit(quality)
	arena.fx_hit(target.body.position, quality)
	var sp := arena.world_to_screen(target.body.position + Vector3(0, 4, 0))
	hud.pop_damage(sp, damage, quality, true)


func _on_range_rings_toggled(enabled: bool) -> void:
	arena.range_layer.visible = enabled
	_sync_settings_ui()


# ══════════════════════════════════════════════════════════════════
#  验收 / 调试入口
# ══════════════════════════════════════════════════════════════════

## 把当前战斗一次性快进若干秒。
##
## ⚠️ 它会在一次调用里跑完几百个 tick（sim.step 内部是固定步长循环），
##    所以只在无头验收脚本里用，不要接到 UI 上。
func debug_fast_forward_battle(seconds: float) -> void:
	if sim == null or sim.finished:
		return
	sim.step(seconds)
	_sync_log()
	# ⚠️ 快进时把 `seconds` 当 delta 传：一次调用跑完了 `seconds` 秒的模拟，
	#    限速闸门就应按「这段时间的总可转角」放行，否则快进后舰艏会滞后于
	#    已经跑完的几百帧（验收脚本拿到的是"半路姿态"）。这是**有意的**。
	arena.sync_ships(sim.ships, seconds)


## 跳过结算等待（验收脚本用）。
##
## ⚠️ 阶段 D 之后 RESOLVE 阶段不再有定时器 —— 结算页会一直停着。
##    所以这个入口改为「等价于点一次结算页的继续按钮」，
##    而不是去等一个不存在的超时。旧脚本调用它得到的语义完全不变。
##
## ★ 2026-10-01：结算页现在有 1 秒的**延迟弹出**。如果在这一秒里调它，
##    `hud.hide_result()` 会作用在一张还没弹出来的页上（无害），但
##    `_pending_result` 会残留 ⇒ 下一回合的开场弹出一张旧结算页。
##    所以这里先 `_popup_result()` 把它消费掉，再走原路径收起并推进 ——
##    对调用方而言「跳过结算」的语义一字未变。
func debug_skip_resolve() -> void:
	if run != null and run.phase == EveRunState.Phase.RESOLVE:
		_popup_result()
		hud.hide_result()
		_end_resolve()


## 把结算弹窗的延迟一次性走完（验收脚本用）。
##
## ⚠️ 存在的理由：`_process` 里那一秒是靠**真实帧**累加的，而无头验收
##    在 `_step_battle_done` 里是一次性快进 90 秒（**一帧内**跑完），
##    中间根本没有帧过去 ⇒ 不主动催一下的话，那一秒要等到下一个
##    `_step_*` 的若干帧之后才走完，断言会读到「结算页还没弹」。
##    给验收一个显式入口，比让每个脚本各自 await 一堆帧稳得多。
func debug_flush_result_popup() -> void:
	_popup_result()


# ══════════════════════════════════════════════════════════════════
#  输入
# ══════════════════════════════════════════════════════════════════
#
# ⚠️ 左键现在有三种含义，必须由同一个地方仲裁
#
#   ① 「在我方舰船 / 备战席上按下并拖动」= 拖放布阵（阶段 B5）
#   ② 「在空白处按下并拖动」            = 轨道相机转视角
#   ③ 「单击」                          = 选中最近舰船
#
#   仲裁顺序：先试 ①（拿得起来吗），拿不起来才交给 ② / ③。
#   顺序不能反 —— 反了就会出现「想拖船，结果转了视角」。
#
# ⚠️ 为什么「拖动期间」的事件收在 _input() 而不是 _unhandled_input()：
#   松手时指针很可能停在【商店窗】上（那里就是出售区）。窗口是 MOUSE_FILTER_STOP，
#   事件会被 GUI 吃掉，根本到不了 _unhandled_input ——
#   症状是「把船拖到商店上松手，什么都没发生，船还留在原地」。
#   _input() 在所有 GUI 之前拿到事件，拖动期间用它才稳。
var _cam_dragged := false

## 本次拖动点亮的棋盘是不是「自动的」（松手要还原）。
##
## ⚠️ 玩家用 KEY_B 手动开的棋盘不该被一次拖放顺手关掉 —— 他开棋盘是在核对格子。
##    所以只还原「因为这次拖动才亮起来」的棋盘。
var _board_auto := false

func _input(event: InputEvent) -> void:
	# 只在「正在拖船」时抢事件；其余一概不碰（让相机与 GUI 各司其职）
	if _drag.is_empty():
		return
	if event is InputEventMouseMotion:
		_update_drag((event as InputEventMouseMotion).position)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			_end_drag(mb.position)
			get_viewport().set_input_as_handled()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
			_cancel_drag("已取消")
			get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_ESCAPE:
		_cancel_drag("已取消")
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	# 左键先给相机仲裁
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_cam_dragged = false
				# ① 先试拿船（备战席 / 我方场上）。拿起来了 → 本次左键归拖放
				if _try_begin_drag(mb.position):
					return
				# ② 没拿起来 → 老行为：相机（它会开始记录拖拽距离）
				arena.handle_camera_input(event)
				return
			else:
				# 松开：先让相机收尾，再据「是否真拖过」决定要不要选船
				var cam_consumed := arena.handle_camera_input(event)
				if not cam_consumed:
					_try_select_at(mb.position)
				return

		# 滚轮 / 其他键：直接给相机（不影响选中）
		if arena.handle_camera_input(event):
			return

	elif event is InputEventMouseMotion:
		# 没在拖船、但棋盘可见时（KEY_B 手动开）：鼠标扫到哪格就高亮哪格
		if arena.board != null and arena.board.visible:
			var cell: Vector2i = arena.screen_to_cell(event.position)
			if cell.x >= 0:
				arena.board.highlight(cell.x, cell.y)
			else:
				arena.board.clear_highlight()
		if arena.handle_camera_input(event):
			return

	if event is InputEventKey and event.pressed and not event.echo:
		# ⚠️ 暂停期间**只放行空格**（唯一的解锁键）。
		#    R / C / B 一律吞掉 —— 遮罩管得住鼠标、管不住键盘，
		#    这条守卫就是键盘侧的那一半。放行它们等于开了个
		#    「暂停中偷偷重开一局 / 转镜头」的后门。
		if _paused and event.keycode != KEY_SPACE:
			return
		match event.keycode:
			KEY_SPACE:
				set_paused(not _paused)
			KEY_R:
				hud.append_log({"time": 0.0, "category": &"system", "text": "重开一局"})
				restart_run()
			KEY_C:
				# 手动复位机位（双击左键也可，见 arena.handle_camera_input）
				arena.reset_camera()
				hud.append_log({"time": sim.elapsed if sim != null else 0.0,
						"category": &"system", "text": "相机已复位"})
			KEY_B:
				# 棋盘开关（检查格子用）。真实玩法里由「拖起舰船」自动触发，
				# 这个手动入口保留 —— 它就是「棋盘现在归玩家管」的那条路径。
				var board_on := arena.toggle_board()
				_board_auto = false
				# 阶段 D：设置窗开着的话把它那个「棋盘 [开/关]」按钮同步过来，
				# 否则窗里显示的和实际相反（下一次点击就会反着操作）。
				_sync_settings_ui()
				hud.append_log({"time": sim.elapsed if sim != null else 0.0,
						"category": &"system",
						"text": "棋盘 %s" % ("显示（11×11）" if board_on else "隐藏")})


## 点击选中最近的舰船（屏幕距离 60px 内）
func _try_select_at(screen_pos: Vector2) -> void:
	var best: EveShip = null
	var best_dist := PICK_RADIUS
	for ship in _all_ships():
		if not ship.alive:
			continue
		var sp := arena.world_to_screen(ship.body.position + Vector3(0, 4, 0))
		var d := sp.distance_to(screen_pos)
		if d < best_dist:
			best_dist = d
			best = ship
	if best != null:
		hud.show_ship(best)


# ══════════════════════════════════════════════════════════════════
#  拖放布阵（阶段 B5）
# ══════════════════════════════════════════════════════════════════
#
# 一次拖动的完整生命周期 —— 四个函数，别把逻辑散到别处去：
#
#     _try_begin_drag   按下：这一下是想拿船，还是想转视角？
#     _update_drag      移动：幽灵跟手 · 棋盘显形 · 落点高亮 · 写一句「松手会怎样」
#     _end_drag         松手：按落点分派到 部署 / 换位 / 撤回 / 出售
#     _cancel_drag      取消：ESC / 右键，等于落点「哪儿都不是」
#     _finish_drag      收尾：拖动期间的所有临时状态在这里一次清干净（唯一出口）
#
# ⚠️ 状态只有一份（_drag 字典），见它的声明 —— 就是为了让取消路径不可能漏清。

## 屏幕上「点中一艘舰船」的判定半径（像素）
const PICK_RADIUS := 60.0

## 按下左键时试着拿起一艘船。拿起来了 → true（本次左键从此归拖放）
func _try_begin_drag(pos: Vector2) -> bool:
	if run == null or run.phase != EveRunState.Phase.PREP:
		return false          # 战斗中锁操作，是阶段 A 就定下的规矩

	# ① 备战席：轨道几何只有 HUD 知道（格宽 = size.x / 8），所以问它落在第几格
	var bi := hud.bench_slot_at(pos)
	var bench := run.bench_entries()
	if bi >= 0 and bi < bench.size():
		_drag = _make_drag(bench[bi], &"bench", bi)
		_drag["screen"] = pos
		_begin_drag_visual()
		return true

	# ② 我方场上舰船：屏幕距离最近的一艘
	var si := _own_ship_at(pos)
	if si >= 0 and si < _own_field_index.size():
		var fi: int = _own_field_index[si]
		var entries := run.field_entries()
		if fi >= 0 and fi < entries.size():
			_drag = _make_drag(entries[fi], &"field", fi)
			_drag["screen"] = pos
			_begin_drag_visual()
			return true

	return false


## 屏幕点选了我方第几艘（_own_ships 的下标；-1 = 没点中）
func _own_ship_at(pos: Vector2) -> int:
	var best := -1
	var best_d := PICK_RADIUS
	for i in _own_ships.size():
		var ship := _own_ships[i]
		if not ship.alive:
			continue
		var sp := arena.world_to_screen(ship.body.position + Vector3(0, 4, 0))
		var d := sp.distance_to(pos)
		if d < best_d:
			best_d = d
			best = i
	return best


## 组装拖动状态。各字段的含义见 _drag 的声明处。
func _make_drag(e: Dictionary, source: StringName, index: int) -> Dictionary:
	var key := String(e.get("ship_key", ""))
	var d := EveShipDatabase.by_id(key)
	var star := maxi(1, int(e.get("star", 1)))
	var cost := int(d.get("cost", 1))
	return {
		"source": source,
		"index": index,
		"ship_key": key,
		"star": star,
		"cost": cost,
		"name": String(d.get("name", key)),
		"color": EveShip.FACTION_COLORS.get(int(d.get("faction", 0)), Color.GRAY),
		# 出售返还 = cost × 3^(star-1)（与 RunState.sell_value 同口径）
		"refund": cost * int(pow(3.0, float(star - 1))),
		"screen": Vector2.ZERO,
		"hint": "",
		"hint_ok": false,
	}


## 拿起之后的第一帧：幽灵现身 · 棋盘显形 · 备战席标记 + 那艘 3D 船先藏起来
func _begin_drag_visual() -> void:
	# 棋盘显形 + 布阵取景。
	# ⚠️ 走 arena.show_board_for_deploy()，**不走** arena.set_board_visible ——
	#    后者是把取景硬设到目标位；拖动途中画面「啪」地一跳，玩家立刻失去手感。
	#    show_board_for_deploy 只把「棋盘可见」立起来，
	#    取景（推近到 BOARD_VIEW_ZOOM 倍）由 arena._process 每帧收敛过去。
	if arena.board != null:
		if not arena.board.visible:
			_board_auto = true
		arena.show_board_for_deploy()
	# ── 布阵尺寸（2026-09-20 用户要求）──────────────────────────────
	# 舰船切到布阵态（放大 BOARD_EXAGGERATION 倍，实测原尺寸只有 0.39 格宽，
	# 连拖拽命中半径都点不中）。幂等，连续拖拽重复调用无害。
	arena.set_ships_board_mode(true)
	# 从备战席拿的：格带上标出「这格被拿起了」，并让那一格**不画立绘**。
	# （EveBenchRail._draw 按 dragging_index 跳过该格，否则会和幽灵重叠成两艘；
	#  3D 版当年靠 bench_stage.set_hidden_index 做同一件事，已随 3D 层停用。）
	if StringName(_drag["source"]) == &"bench":
		hud.set_bench_drag(int(_drag["index"]))
	_update_drag(_drag["screen"])


## 拖动中：幽灵跟手 · 落点高亮 · 把「松手会怎样」写进幽灵的第二行
func _update_drag(pos: Vector2) -> void:
	if _drag.is_empty():
		return
	_drag["screen"] = pos

	var source := StringName(_drag["source"])
	var index := int(_drag["index"])
	var over_sell := hud.sell_zone_rect().has_point(pos)
	var bi := hud.bench_slot_at(pos)
	var cell: Vector2i = arena.screen_to_cell(pos)
	var on_mine := cell.x >= 0 and arena.board != null and arena.board.is_mine_zone(cell.x)

	var hint := ""
	var ok := false
	if over_sell:
		hint = "出售 · 返还 ◆%d" % int(_drag["refund"])
		ok = true
	elif on_mine:
		var pv := run.preview_place(cell.x, cell.y, source, index)
		ok = bool(pv.get("ok", false))
		if ok:
			if source == &"bench":
				hint = "部署到 第 %d 行第 %d 列" % [cell.x + 1, cell.y + 1]
			else:
				hint = "移动到这里"
		else:
			hint = String(pv.get("reason", "不能放在这里"))
	elif bi >= 0:
		if source == &"field":
			if run.can_recall():
				hint = "撤回备战席"
				ok = true
			else:
				hint = "备战席已满（%d／%d）" % [run.bench_used(), EveRunState.BENCH_SLOTS]
		else:
			hint = "放回备战席"
			ok = true
	else:
		hint = "拖到下方部署区 · 或拖到商店出售"

	_drag["hint"] = hint
	_drag["hint_ok"] = ok

	# 棋盘高亮：只高亮「真的落得下」的格子。
	# ⚠️ 无效格也给高亮的话，玩家会以为能放 —— 高亮本身就是一句承诺。
	if arena.board != null:
		if on_mine and ok:
			arena.board.highlight(cell.x, cell.y)
		else:
			arena.board.clear_highlight()

	# 出售区跟随高亮（只在指针真的进了商店窗时亮）
	hud.set_sell_hot(over_sell)
	# 备战席：悬停格提示「松手就落这一格」
	hud.set_bench_hover(-1 if over_sell else bi)
	hud.set_drag_ghost(_ghost_payload())


## 幽灵要显示的内容（与 HUD 侧 _DragGhost.apply 的字段约定一致）
func _ghost_payload() -> Dictionary:
	return {
		"active": true,
		"name": String(_drag.get("name", "—")),
		"star": int(_drag.get("star", 1)),
		"cost": int(_drag.get("cost", 1)),
		"color": _drag.get("color", Color.GRAY),
		"hint": String(_drag.get("hint", "")),
		"hint_ok": bool(_drag.get("hint_ok", false)),
		"screen": _drag.get("screen", Vector2.ZERO),
	}


## 松手：按落点分派动作。整个拖放**唯一的生效点**。
##
## 落点优先级：出售区 → 棋盘格 → 备战席轨道 → 什么都不做（静默放回）。
func _end_drag(pos: Vector2) -> void:
	if _drag.is_empty():
		return
	var source := StringName(_drag["source"])
	var index := int(_drag["index"])

	# ⚠️ 顺序不能反：**先清拖动状态，再执行落点动作**。
	#    因为动作会 emit changed，而 _refresh_run_ui 在「拖动中」是跳过舰队重建的。
	#    先动作后清理的话：船确实上前了（数据对了），但战场上不会出现它 ——
	#    要等下一次 changed 才补上，玩家看到的现象是「松手没反应」。
	_finish_drag()

	var res: Dictionary = {"ok": false, "reason": ""}
	if hud.sell_zone_rect().has_point(pos):
		# 出售。日志（含返还金额）由 RunState 自己发，这里不重复写一行
		if source == &"bench":
			res = run.sell_from_bench(index)
		else:
			res = run.sell_from_field(index)
	else:
		var cell: Vector2i = arena.screen_to_cell(pos)
		var on_mine := cell.x >= 0 and arena.board != null and arena.board.is_mine_zone(cell.x)
		if on_mine:
			if source == &"bench":
				res = run.deploy_from_bench(index, cell.x, cell.y)
			else:
				res = run.move_field(index, cell.x, cell.y)
		elif source == &"field" and hud.bench_slot_at(pos) >= 0:
			res = run.recall_to_bench(index)
		# else：备战席里的船放回备战席 / 丢在空白处 → 静默放回，不打日志

	# 被拒时把原因告诉玩家（这是唯一一处「为什么没生效」的出口）
	if not bool(res.get("ok", false)):
		var why := String(res.get("reason", ""))
		if why != "":
			hud.append_log({"time": 0.0, "category": &"hint", "text": why})

	# 兜底再刷一次：RunState 的 changed 已经刷过一遍，这次是给
	# 「动作被拒但界面仍需回正」（例如高亮、备战席 hover）收尾。
	_refresh_run_ui()
	_log_synergies()


## 取消：ESC / 右键。落点当成「哪儿都不是」，一个字节的数据都不改。
func _cancel_drag(msg: String = "") -> void:
	if _drag.is_empty():
		return
	if msg != "":
		hud.append_log({"time": 0.0, "category": &"hint", "text": msg})
	_finish_drag()


## 收尾：拖动期间的所有临时状态，全在这里一次清干净。
##
## ⚠️ 以后每加一个「拖动时才会出现的副作用」，它的清理就写在这里 ——
##    只有这一个出口。这就是把 _drag 做成单份字典的收益。
func _finish_drag() -> void:
	_drag = {}
	hud.set_drag_ghost({})
	hud.set_bench_drag(-1)
	hud.set_bench_hover(-1)
	hud.set_sell_hot(false)
	if arena.board != null:
		arena.board.clear_highlight()
		if _board_auto and arena.board.visible:
			# 走 hide_board()（不是 board.set_board_visible）——
			# 取景交回 _process 的舰队跟随，那条路径同样是平滑的，不会跳。
			arena.hide_board()
	_board_auto = false
	# 舰船退出布阵态，回到战斗尺寸（与 _begin_drag_visual 的进入成对）
	arena.set_ships_board_mode(false)
