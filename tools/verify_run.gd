extends Node

## 一局闭环验收（阶段 A + B）
##
## ══════════════════════════════════════════════════════════════════
##  它验的是什么
## ══════════════════════════════════════════════════════════════════
##  「这一局能不能玩」不是一个可以靠读代码回答的问题，所以这里分两段：
##
##   第一段 · 纯数值（不碰 3D）
##     概率表 / 等级曲线 / 经济 / 信标 / 结局判定 —— 全部照交接文档的
##     权威口径断言。这一段才是「数值有没有接错」的判据。
##     阶段 B 追加：羁绊表阈值（对 CSV）/ 三连合成 / 上场上限 / 羁绊乘数 /
##     拖放编制 API（部署·换位·撤回·出售·战斗期锁定）。
##
##   第二段 · 场景联动
##     真实实例化 battle_scene，然后像玩家一样操作：
##     买船 → 钱变少 → 开战 → 快进战斗 → 结算扣信标 → 推进节点
##     → **拖一艘船到棋盘上指定的格**（B5，走 屏幕↔格 换算 + 编制写入）。
##     每步都断言「状态机的数字」与「HUD 上的字 / 3D 的位置」一致。
##
## ── 跑法（⚠️ 第二段要看像素，所以【不要加 --headless】）──────────
##   "C:/godot/Godot_v4.7.1-stable_win64_console.exe" \
##     --path "F:/evezzq/eve自走棋918" --quit-after 900 res://tools/verify_run.tscn
##
## 产物：user://run_prep_1.png / run_prep_bought.png / run_battle_1.png /
##       run_resolve_1.png / run_node2_prep.png /
##       run_drag.png（拖动中） / run_deployed.png（落格后）
##
## ⚠️ 拖动那两步之间会保持「拿着船」的状态约 1 秒（为了截拖动中的图）。
##    这期间不要用鼠标点窗口 —— 真实点击会提前结束拖动，让落格断言落空。
##
## 退出码：0 = 全过；1 = 有断言失败（失败项会逐条打进 stdout）

const SCENE_PATH := "res://scenes/battle_scene.tscn"
## 顶条的 BOSS 方块下标在命令条里（那个脚本没有 class_name，只能 preload 取常量）
const COMMAND_BAR_SCRIPT := preload("res://scripts/ui/panels/eve_command_bar.gd")
const BATTLE_SCRIPT := preload("res://scripts/eve_battle_scene.gd")
## 阶段 D：开战镜头的常量在 arena 脚本里，用它读（而不是从实例上 get）——
## 常量属于**脚本**，从实例 get 靠的是 Godot 的实现细节，脚本 preload 才是正规口径。
const ARENA_SCRIPT := preload("res://scripts/scene/eve_battle_arena.gd")
const ORBIT_CAM_SCRIPT := preload("res://scripts/scene/eve_orbit_camera.gd")
const SETTINGS_SCRIPT := preload("res://scripts/ui/panels/eve_settings.gd")
## 浮窗布局存档（`user://window_layout.cfg`）—— 验收要能**隔离**玩家存下来的窗布局。
const WINDOW_STORE := preload("res://scripts/ui/eve_window_store.gd")
## 打击特效层：开火线的几何验收要读它的 `METERS_PER_UNIT`（米↔世界单位）
const BfxScript := preload("res://scripts/visual/eve_battle_fx.gd")

## 47 轮锚点用：**生产算式**的静态入口（`EveShipVisual.zero_pose_basis`）。
##
## ⚠️ 用 `load()` 拿到的是 `GDScript` 资源，**静态函数要经 `.call(name, ...args)`**：
##     `gds.call("zero_pose_basis", id)` —— 直接 `gds.zero_pose_basis(id)` 会被
##     解释成"调一个名叫 id 的函数"（实测报 `Nonexistent function 'bantam'`）。
##     也不用全局类名 `EveShipVisual.`：它依赖 `--import` 生成的 class_cache。
var _ZP_SCRIPT: Variant = load("res://scripts/visual/eve_ship_visual.gd")

const OUT_PREP := "user://run_prep_1.png"
const OUT_BOUGHT := "user://run_prep_bought.png"
const OUT_PREP_FULL := "user://run_prep_full.png"
const OUT_RESOLVE := "user://run_resolve_1.png"
const OUT_NODE2 := "user://run_node2_prep.png"
const OUT_DRAG := "user://run_drag.png"
const OUT_DEPLOYED := "user://run_deployed.png"
const OUT_EVENT := "user://run_event_pick.png"
const OUT_EVENT_DONE := "user://run_event_done.png"
const OUT_SALVAGE := "user://run_salvage_wreck.png"
const OUT_SALVAGE_ORDER := "user://run_salvage_order.png"
const OUT_SALVAGE_ARRIVE := "user://run_salvage_arrive.png"
## 阶段 D
const OUT_SETTINGS := "user://run_settings.png"

## 拖动测试要落的那一格（我方部署区 = 第 7~10 行，取中间那行第 6 列）
const DRAG_ROW := 8
const DRAG_COL := 5

var _battle: Node = null
var _frame := 0
var _stage := 0
var _fail := 0
var _pass := 0

## 节点 1 敌方舰队的数值快照 —— 用来验「节点 2 是同一张脸 + scale 1.25」
var _node1_enemy_comp := ""
var _node1_enemy_shield := 0.0
var _node1_enemy_attack := 0.0
var _node1_loss := 0
## 下单打捞的那艘船（跨步骤断言「到账的就是它」）
var _salvage_key: StringName = &""
## 阶段 D①：开战**之前**的相机偏航角 —— 跨步骤与开战后的值对账（验「真的转了」）
var _cam_yaw_before := 0.0
## 阶段 D④：音频计数器快照（跨步骤对账）。
##
## ⚠️ 音频在无头环境里**不会真的响**（没有音频设备），所以只能验「调用链通了 +
##    音源真的找到了」。`missing` 那条尤其重要：它捕获的是
##    「逻辑名写错 / 资产没拷进来 → 静默跳过 → 玩家听不到但一切正常」。
var _audio_at_battle_start: Dictionary = {}
## 阶段 C 收尾：进场字幕的总寿命（步骤 1 读出，步骤 7 验「开战即收」时对账）
var _entry_banner_life := 0.0

## 已执行过的步骤名集合 —— 守卫「步骤被静默跳过」这类缺陷。
##
## ⚠️ 为什么需要它：`_shot_and()` 曾在 await 处让出控制权，
##    导致被它包裹的 `_step_*` **整个不执行**：
##    既不报错、也不打 print，而它前后两步的断言照常输出 ——
##    只看结果像"某个函数内部提前 return 了"，实际是调度错位。
##    有了这张表，任何一步漏跑都会在结尾被点名（见 `_finish()`）。
const REQUIRED_STEPS := [
	"_step_start", "_step_buy", "_step_deploy_first", "_step_economy",
	"_step_levelup", "_step_start_battle", "_step_d_hit", "_step_battle_done",
	"_step_d_result", "_step_d_settings", "_step_next_node", "_step_b_drag",
	"_step_b_drop", "_step_b_place", "_step_event_open", "_step_event_choose",
	"_step_salvage_wreck", "_step_salvage_order", "_step_salvage_arrive",
	"_step_salvage_buy",
]
var _ran_steps := {}

## 步骤名 → 方法引用。`_shot_and` 走的是裸方法引用（不是 `_call` 包装），
## 拿不到函数名，只能靠这张表反查（见 `_step_label`）。
var STEP_CALLABLES := {}


func _ready() -> void:
	# 步骤名 ↔ 方法引用 反查表（`_shot_and` 记名用，见 `_step_label`）
	STEP_CALLABLES = {
		"_step_start": _step_start, "_step_buy": _step_buy,
		"_step_deploy_first": _step_deploy_first, "_step_economy": _step_economy,
		"_step_levelup": _step_levelup, "_step_start_battle": _step_start_battle,
		"_step_d_hit": _step_d_hit, "_step_battle_done": _step_battle_done,
		"_step_d_result": _step_d_result, "_step_d_settings": _step_d_settings,
		"_step_next_node": _step_next_node, "_step_b_drag": _step_b_drag,
		"_step_b_drop": _step_b_drop, "_step_b_place": _step_b_place,
		"_step_event_open": _step_event_open, "_step_event_choose": _step_event_choose,
		"_step_salvage_wreck": _step_salvage_wreck,
		"_step_salvage_order": _step_salvage_order,
		"_step_salvage_arrive": _step_salvage_arrive,
		"_step_salvage_buy": _step_salvage_buy, "_finish": _finish,
	}
	print("═══ 第一段：纯数值口径 ═══")
	await _unit_tests()

	print("")
	print("═══ 第二段：场景联动 ═══")
	# ⚠️ 先把视口钳到【设计分辨率 1920×1080】（2026-09-20 挖出的环境坑）
	#
	#   project.godot 是 `stretch/mode=canvas_items` + `aspect=expand`：
	#   真实窗口下 2D 层会按窗口比例扩展，而**无头模式没有真实窗口**，
	#   视口退化成 1920×1920（正方形）。于是：
	#     · HUD 的 RECT_* 是【按 1080 高设计的绝对像素】→ 商店窗跑去了非预期位置；
	#     · 相机取景走 CAMERA_ASPECT=1.7778 的写死常量 → 格子投影按 16:9 算。
	#   两者错配 ⇒ 格 (8,5) 的投影 (1098,1044) 恰好落进商店窗 (y 898~1067)，
	#   拖放被判定成「拖到出售区」→ 提示没行号 / 商店亮橙 / 上场数少 1。
	#   **这不是产品 bug，是无头视口口径不对**：实机 1920×1080 下两者一致。
	#   ⇒ 显式钳尺寸，让无头跑的验收与实机同口径（否则这条断言会永久假红）。
	var win := get_window()
	if win != null:
		win.size = Vector2i(1920, 1080)
	# 守卫：钳完之后必须是 16:9。**这条不能省** ——
	# 它一旦失效（引擎改了 headless 行为 / 有人删了上面两行），
	# 下面所有「屏幕坐标 ↔ 格号」的断言会一起变成假红，
	# 而症状是「提示没写行号 / 商店亮橙 / 上场数少 1」三条，
	# 看起来全像玩法 bug，没人会想到是视口尺寸。
	# 把根因钉在这一条上，下次挂了先看这里。
	var vp_now := get_viewport().get_visible_rect().size
	var vp_ratio := vp_now.x / maxf(1.0, vp_now.y)
	# ⚠️ 用容差而不是 is_equal_approx：1.7778 是**手抄的近似值**
	#    （真值 16/9 = 1.77778...），is_equal_approx 的精度带不住这个差值。
	_expect(absf(vp_ratio - float(ARENA_SCRIPT.CAMERA_ASPECT)) < 0.001,
			"无头视口已钳到设计比例 %.4f（实际 %s · 比例 %.4f）"
			% [float(ARENA_SCRIPT.CAMERA_ASPECT), str(vp_now), vp_ratio])
	var packed: PackedScene = load(SCENE_PATH)
	_battle = packed.instantiate()
	add_child(_battle)


func _process(_dt: float) -> void:
	_frame += 1
	# 每 30 帧一个里程碑
	if _frame % 30 != 0:
		return
	_stage += 1
	_dispatch(_stage)


## 把 match 抽出来，唯一目的是**在派发前记名**（见 REQUIRED_STEPS）。
## ⚠️ 记名必须发生在调用之前：若某个 `_step_*` 跑到一半报错中断，
##    它仍应算"跑过"（有它自己的报错为证），漏跑的才是真问题。
func _dispatch(stage: int) -> void:
	match stage:
		1: _call("_step_start", _step_start)
		2: _shot_and(OUT_PREP, _step_buy)
		3: _shot(OUT_BOUGHT, "买完 5 张 —— 全在备战席轨道上（买入不自动上场）")
		4: _call("_step_deploy_first", _step_deploy_first)
		5: _call("_step_economy", _step_economy)
		6: _call("_step_levelup", _step_levelup)
		7: _shot_and(OUT_PREP_FULL, _step_start_battle)
		# ── 阶段 D②③：先跑几秒战斗，验命中反馈与伤害数字真的在冒 ──
		8: _call("_step_d_hit", _step_d_hit)
		9: _call("_step_battle_done", _step_battle_done)
		10: _shot(OUT_RESOLVE, "结算（信标扣血 · 结算页上台等玩家点）")
		11: _call("_step_d_result", _step_d_result)
		12: _call("_step_d_settings", _step_d_settings)
		13: _shot(OUT_SETTINGS, "设置窗：天空盒 / 显示模式 / 三个开关 / 操作")
		14: _call("_step_next_node", _step_next_node)
		15: _shot(OUT_NODE2, "节点 2 准备阶段（同一张脸 · scale 1.25）")
		16: _call("_step_b_drag", _step_b_drag)
		17: _shot(OUT_DRAG, "拖动中：棋盘自动显形 · 落格高亮 · 幽灵跟手")
		18: _call("_step_b_drop", _step_b_drop)
		19: _shot(OUT_DEPLOYED, "拖放落格：编制记下格号 · 舰船站到那一格")
		20: _call("_step_b_place", _step_b_place)
		21: _call("_step_event_open", _step_event_open)
		22: _shot_and(OUT_EVENT, _step_event_choose)
		23: _shot(OUT_EVENT_DONE, "选完：面板收起 · 事件增益窗显形 · 已推进到节点 5")
		24: _call("_step_salvage_wreck", _step_salvage_wreck)
		25: _shot_and(OUT_SALVAGE, _step_salvage_order)
		26: _shot_and(OUT_SALVAGE_ORDER, _step_salvage_arrive)
		27: _shot_and(OUT_SALVAGE_ARRIVE, _step_salvage_buy)
		28: _call("_step_timer_forfeit", _step_timer_forfeit)
		29: _call("_finish", _finish)


func _call(step_name: String, fn: Callable) -> void:
	_ran_steps[step_name] = true
	fn.call()


# ══════════════════════════════════════════════════════════════════
#  第一段：纯数值
# ══════════════════════════════════════════════════════════════════

func _unit_tests() -> void:
	_t_ship_names()      # 舰船**显示名**（id 与中文名的一致性）
	_t_node_table()
	_t_odds_table()
	_t_economy()
	_t_levels()
	_t_beacon_and_loss()
	_t_endings()
	# ── 阶段 B ──
	_t_trait_table()     # B0 羁绊表阈值与效果（CSV 直录）
	_t_merge()           # B1 三连合成（连锁 + 位置继承）
	_t_field_cap()       # B2 上场上限是硬的
	_t_synergy()         # B3 羁绊真算进数值
	_t_drag_api()        # B5 部署 / 换位 / 撤回 / 出售
	# ── 阶段 C ──
	_t_event_table()     # C1 事件选项表自检（3 个事件节点共用一套）
	_t_event_apply()     # C2 事件效果落地（星币 / 经验 / 信标 / 每节点 / 漏怪减免）
	_t_salvage()         # C3 打捞（残骸来源 / 下单 / 延迟到账占货位 / 刷新刷不掉 / 买走解锁）
	_t_salvage_tier()    # C4 ★ 残骸星级反解 + 打捞框「数字残留」修复（2026-10-01）
	await _t_salvage_scope()   # C5 ★★ 打捞范围 = 敌我双方（2026-10-01 用户定案）
	# ── 阶段 D ──
	_t_ship_yaw()        # D1 舰船朝向修正表（用户逐艘目视标定的落盘）
	_t_logistics()       # E1 ★ 后勤舰（攻击压制 + 真修友军 + 修层按防御类型，2026-10-01）


## 节点表与敌方编组
## ══════════════════════════════════════════════════════════════════
##  ★ 舰船**显示名**自检（2026-10-06 新增）
## ══════════════════════════════════════════════════════════════════
##
## 起因：`executioner` 的中文名被写成「磨难级」（正确 =「刽子手级」），
## 玩家在游戏里一直看到错名 —— 而模型、数值、朝向全都正常，所以没人发现。
##
## ## 为什么这条错只能靠 id / 英文名判
## ##   模型与资产都绑在 id 上（红线 1：关联靠 id 不靠名字），
## ##   中文名是**纯标签** ⇒ 它写错不会引发任何报错、也不会影响任何功能。
## ##   ⇒ 判据只能是「中文名 vs 英文名/id 是否对得上」+「有没有撞名」。
func _t_ship_names() -> void:
	var ex := EveShipDatabase.by_id("executioner")
	_expect(not ex.is_empty(), "executioner 在舰船表里")
	# ① 用户裁决（2026-10-06）：这艘船的中文名是「刽子手级」
	_expect(String(ex.get("name", "")) == "刽子手级",
			"★★ executioner 的中文名 =「刽子手级」（实际「%s」）"
			% String(ex.get("name", "")))
	# ② 英文名/id 必须**原封不动** —— 改标签时最容易顺手改到 id，
	#    那会连带打断资产索引 / 朝向表 / 存档（红线 1）。
	_expect(String(ex.get("en", "")) == "Executioner",
			"★★ executioner 的英文名仍是 Executioner（实际「%s」）"
			% String(ex.get("en", "")))
	_expect(StringName(ex.get("ship_key", &"")) == &"executioner",
			"★★ ship_key 仍是 executioner（实际「%s」）"
			% String(ex.get("ship_key", &"")))
	# ③ 反向：**全库不许再有任何一艘叫「磨难级」**（错名清干净）
	var bad: Array[String] = []
	for s in EveShipDatabase.all_ships():
		if String(s.get("name", "")).contains("磨难"):
			bad.append("%s(%s)" % [String(s.get("ship_key", "")), String(s.get("name", ""))])
	_expect(bad.is_empty(), "★★ 全库没有一艘还叫「磨难级」（残留：%s）" % str(bad))
	# ④ 中文名**唯一** —— 改名的头号事故就是撞名（商店里两艘同名分不清）
	var seen := {}
	var dup: Array[String] = []
	for s in EveShipDatabase.all_ships():
		var nm := String(s.get("name", ""))
		if seen.has(nm):
			dup.append(nm)
		seen[nm] = true
	_expect(dup.is_empty(), "★ 全库 %d 艘的中文名互不重复（重复：%s）"
			% [EveShipDatabase.all_ships().size(), str(dup)])
	print("[舰船名] executioner =「%s」· 全库 %d 艘 · 无「磨难级」残留 · 无重名"
			% [String(ex.get("name", "")), EveShipDatabase.all_ships().size()])


func _t_node_table() -> void:
	_expect(EveNodeTable.count() == 15, "节点表 15 行（实际 %d）" % EveNodeTable.count())
	_expect(EveNodeTable.by_index(1)["comp"] == "pirate_scout",
			"节点 1 = pirate_scout")
	_expect(EveNodeTable.by_index(2)["comp"] == "pirate_scout"
			and is_equal_approx(float(EveNodeTable.by_index(2)["scale"]), 1.25),
			"节点 2 = 同一张脸 + scale 1.25（全表最聪明的一手）")
	_expect(EveEnemyComps.validate().is_empty(),
			"敌人编组表自检：%s" % str(EveEnemyComps.validate()))
	# 顶条的 BOSS 描边下标必须与节点表一致（两处口径不能漂移）
	var boss_ok := true
	for i in EveNodeTable.BOSS_INDEXES:
		if not COMMAND_BAR_SCRIPT.BOSS_NODES.has(i - 1):
			boss_ok = false
	_expect(boss_ok, "顶条 BOSS 方块下标与 EveNodeTable.BOSS_INDEXES 一致")


## 商店概率表：8 档、每行和为 100、低费只降不升 / 5 费只升不降
func _t_odds_table() -> void:
	var keys: Array = EveRunState.SHOP_ODDS.keys()
	keys.sort()
	_expect(keys.size() == 8, "概率表 8 档（实际 %d）" % keys.size())
	var sum_ok := true
	for k in keys:
		var row: Array = EveRunState.SHOP_ODDS[k]
		var s := 0
		for v in row:
			s += int(v)
		if s != 100:
			sum_ok = false
			print("       第 %d 档求和 = %d" % [k, s])
	_expect(sum_ok, "每档概率之和 = 100")

	var low_mono := true
	var high_mono := true
	var expect_mono := true
	var prev_expect := 0.0
	for i in range(1, keys.size()):
		var a: Array = EveRunState.SHOP_ODDS[keys[i - 1]]
		var b: Array = EveRunState.SHOP_ODDS[keys[i]]
		# ⚠️ 只有 1 费是严格单调不增的：2 费在 Lv5→Lv6 是 20 → 25（权威表如此，
		#    不是错），所以「低费只降不升」这条不变量的正确范围是【1 费】。
		if int(b[0]) > int(a[0]):
			low_mono = false
		if int(b[4]) < int(a[4]):
			high_mono = false
		# 真正的整表不变量是「期望费用严格递增」（交接文档 §8.3 原话）
		var ec := 0.0
		for j in b.size():
			ec += float(j + 1) * float(b[j]) / 100.0
		if ec <= prev_expect:
			expect_mono = false
		prev_expect = ec
	_expect(low_mono, "1 费概率随档位只降不升")
	_expect(high_mono, "5 费概率随档位只升不降")
	_expect(expect_mono, "期望费用随档位严格递增")

	# 抽取入口：Lv1 只可能出 cost1
	var st := _new_run(20260920)
	var only_cost1 := true
	for i in 200:
		st.roll_shop()
		for o in st.offers:
			if int(o.get("cost", 0)) != 1:
				only_cost1 = false
	_expect(only_cost1, "Lv1 抽 1000 张全为 1 费（概率表 100/0/0/0/0）")

	# Lv6 抽 2000 张必须出现 5 费
	st.level = 6
	var seen := {}
	for i in 400:
		st.roll_shop()
		for o in st.offers:
			seen[int(o.get("cost", 0))] = true
	_expect(seen.has(5), "Lv6 抽 2000 张出现 5 费（实际到过 %s）" % str(seen.keys()))
	st.queue_free()


## 经济：买 / 刷新 / 加速等级 / 利息 / 收入
func _t_economy() -> void:
	var st := _new_run(7)
	_expect(st.coin == 5, "开局星币 5（实际 %d）" % st.coin)
	_expect(st.beacon == 100, "开局信标 100（实际 %d）" % st.beacon)

	# ⚠️ 2026-09-20 流程改版（云顶口径）：买入【只进备战席】，不自动上场。
	#    开局 5 星币 → 连买 5 张 1 费 → 备战席 5 艘、场上 0 艘。
	for i in 5:
		st.buy(i % 5)
	_expect(st.coin == 0, "买 5 张 1 费后星币归零（实际 %d）" % st.coin)
	_expect(st.field.is_empty() and st.bench.size() == 5,
			"买入只进备战席、不自动上场（上场 %d / 备战 %d）"
			% [st.field.size(), st.bench.size()])

	# 备战席 → 棋盘（玩家手动拖）—— 这是场上唯一的进场入口
	var dep := st.deploy_from_bench(0, 8, 5)
	_expect(bool(dep.get("ok", false)),
			"备战席拖 1 艘上场（%s）" % String(dep.get("reason", "")))
	_expect(st.field.size() == 1 and st.bench.size() == 4,
			"编制变成 上场 1 / 备战 4（实际 %d / %d）"
			% [st.field.size(), st.bench.size()])

	var r := st.buy(0)
	_expect(not bool(r.get("ok", true)),
			"没钱时买船被拒（原因：%s）" % String(r.get("reason", "")))
	r = st.refresh()
	_expect(not bool(r.get("ok", true)),
			"没钱时刷新被拒（原因：%s）" % String(r.get("reason", "")))
	r = st.levelup()
	_expect(not bool(r.get("ok", true)),
			"没钱时加速等级被拒（原因：%s）" % String(r.get("reason", "")))

	# 给钱 → 刷新扣 2
	st.coin = 20
	st.refresh()
	_expect(st.coin == 18, "刷新扣 2（20 → %d）" % st.coin)

	# 利息档：9 → 0 档；10 → 1 档；59 → 5 档（封顶）
	st.coin = 9
	_expect(st.interest() == 0, "9 星币利息 0（实际 %d）" % st.interest())
	st.coin = 10
	_expect(st.interest() == 1, "10 星币利息 1（实际 %d）" % st.interest())
	st.coin = 59
	_expect(st.interest() == 5, "59 星币利息 5（实际 %d）" % st.interest())
	st.coin = 999
	_expect(st.interest() == 5, "999 星币利息封顶 5（实际 %d）" % st.interest())
	_expect(st.income() == 10, "收入 = 基础 5 + 利息 5（实际 %d）" % st.income())
	st.queue_free()


## 等级曲线（交接文档 §8.2 的累计阈值）+ 上场上限 + 每节点自动 +2
func _t_levels() -> void:
	var st := _new_run(11)
	_expect(st.field_limit() == 3, "Lv1 上场上限 3（实际 %d）" % st.field_limit())

	# 累计阈值 [0,0,2,4,10,20,40]：2 点升 Lv2，再 2 点升 Lv3
	st.add_xp(2)
	_expect(st.level == 2, "累计 2 经验 → Lv2（实际 Lv%d）" % st.level)
	st.add_xp(2)
	_expect(st.level == 3, "累计 4 经验 → Lv3（实际 Lv%d）" % st.level)
	_expect(st.field_limit() == 5, "Lv3 上场上限 5（实际 %d）" % st.field_limit())

	# 每节点自动 +2：15 个节点共 30 点，加 4 金币买的 4 点 = 刚好到 Lv6(40)
	var st2 := _new_run(12)
	for i in 15:
		st2.add_xp(EveRunState.NODE_XP_REWARD)
	_expect(st2.xp == 30, "15 节点自动经验共 30（实际 %d）" % st2.xp)
	_expect(st2.level == 5, "只靠自动经验 → Lv5（实际 Lv%d）" % st2.level)
	st2.add_xp(EveRunState.BUY_XP_AMOUNT * 3)   # 再花 12 星币
	_expect(st2.level == 6, "自动 30 + 付费 12 → Lv6（实际 Lv%d）" % st2.level)

	# 满级后经验不再累积（超频走星币）
	st2.add_xp(100)
	_expect(st2.level == 6 and st2.xp == 42, "满级后经验封住（实际 %d）" % st2.xp)

	# 加速等级：4 星币 = 4 点
	var st3 := _new_run(13)
	st3.coin = 4
	var r := st3.levelup()
	_expect(bool(r.get("ok", false)) and st3.coin == 0 and st3.xp == 4,
			"加速等级 4 星币 = 4 点（coin=%d xp=%d）" % [st3.coin, st3.xp])
	_expect(st3.level == 3, "4 点经验 → Lv3（实际 Lv%d）" % st3.level)

	# 超频：满级后 16 星币 = 商店档 +1，封顶 8
	var st4 := _new_run(14)
	st4.level = 6
	st4.coin = 100
	_expect(st4.shop_tier() == 6, "Lv6 商店档 6（实际 %d）" % st4.shop_tier())
	st4.levelup()
	st4.levelup()
	_expect(st4.shop_tier() == 8, "两次超频 → 档 8（实际 %d）" % st4.shop_tier())
	_expect(st4.coin == 68, "超频每次 16 星币（100 → %d）" % st4.coin)
	r = st4.levelup()
	_expect(not bool(r.get("ok", true)), "超频封顶后被拒（原因：%s）" % String(r.get("reason", "")))
	st.queue_free()
	st2.queue_free()
	st3.queue_free()
	st4.queue_free()


## 信标与战败代价
##
## ⛔ 2026-10-01：「漏网」机制已删除。现在只有三句话 ——
##    打赢 = 不掉血；打输 = **阶段定值**；连败 = 每多一场 +2（封顶 +8）。
##    「打完后敌方还剩几艘」**完全不参与**扣血。
func _t_beacon_and_loss() -> void:
	var st := _new_run(21)

	# 遭遇战（battle）定值 8 —— 由「原基础 2 + 实测 Σ费用中位 6」并成
	var roster: Array = st.enemy_roster()
	_expect(st.node_index == 1 and roster.size() == 2,
			"节点 1 敌方 2 艘（实际 %d）" % roster.size())
	var preview := st.loss_preview()
	_expect(preview == 8, "节点 1 战败代价 = battle 定值 8（实际 %d）" % preview)

	# BOSS 节点定值 26 —— 交接文档 §13 的锚点（原 4 + 22）
	st.node_index = 15
	var boss := st.enemy_roster()
	var boss_preview := st.loss_preview()
	_expect(boss.size() == 6, "BOSS 编组 6 艘（实际 %d）" % boss.size())
	_expect(boss_preview == 26,
			"BOSS 战败代价 = 26，与交接文档 §13 的 −26 吻合（实际 %d）"
			% boss_preview)

	# ★★ 反向注入（2026-10-01）：**代价与编组规模无关**。
	#    同一个 battle 阶段下，编组 2 艘（Σ费用 2）与 4 艘（Σ费用 12）
	#    的战败代价必须**完全一样**。谁把「Σ 漏网舰船费用」加回来，这条立刻挂。
	st.node_index = 1
	var small := st.loss_preview()
	st.node_index = 12                 # battle · 4 艘 · Σ费用 12
	var big := st.loss_preview()
	_expect(small == big,
			"★ 不同编组规模的战败代价相同（2艘 %d / 4艘 %d）—— 漏网机制确已删除"
			% [small, big])
	# 阶段之间必须**有**区别（否则 LOSS_BASE 写成一张全同的表也没人发现）
	st.node_index = 5                  # elite
	var elite_v := st.loss_preview()
	_expect(elite_v != small,
			"★ 不同阶段的战败代价不同（battle %d / elite %d）" % [small, elite_v])

	# 结算真的扣信标
	st.node_index = 1
	st.beacon = 100
	var res := st.resolve_battle(1, [])
	_expect(st.beacon == 92, "打输 → 信标 100 − 8 = 92（实际 %d）" % st.beacon)
	_expect(int(res.get("damage", 0)) == 8, "结算返回的伤害 = 8")
	# 连胜连败
	_expect(st.lose_streak == 1 and st.win_streak == 0, "连败 +1")
	st.resolve_battle(0, [])
	_expect(st.win_streak == 1 and st.lose_streak == 0, "胜利清零连败")
	st.queue_free()


## 结局判定：信标归零 → 撤离；打完节点 15 → 通关
func _t_endings() -> void:
	var st := _new_run(31)
	st.node_index = 15
	st.beacon = 100
	st.resolve_battle(0, [])
	st.advance()
	_expect(st.phase == EveRunState.Phase.ENDING
			and st.ending == EveRunState.Ending.CLEARED,
			"节点 15 打完后收束到「通关」结局")

	var st2 := _new_run(32)
	st2.beacon = 2
	st2.resolve_battle(1)                      # battle 战败定值 8 > 剩余 2
	_expect(st2.beacon == 0, "信标被打到 0（实际 %d）" % st2.beacon)
	st2.advance()
	_expect(st2.phase == EveRunState.Phase.ENDING
			and st2.ending == EveRunState.Ending.EVACUATED,
			"信标归零后收束到「撤离」结局")

	# 推进节点会发收入 + 重摇商店（未锁定时）
	var st3 := _new_run(33)
	st3.coin = 10
	st3.node_index = 3
	var before := st3.coin
	st3.resolve_battle(0, [])
	st3.advance()
	_expect(st3.node_index == 4, "advance 推进到节点 4（实际 %d）" % st3.node_index)
	_expect(st3.coin == before + st3.income(),
			"推进时发收入 %d（%d → %d）" % [st3.income(), before, st3.coin])

	# 锁定后不重摇
	var st4 := _new_run(34)
	st4.set_shop_locked(true)
	var key0 := String(st4.offers[0].get("ship_key", ""))
	st4.node_index = 3
	st4.resolve_battle(0, [])
	st4.advance()
	_expect(String(st4.offers[0].get("ship_key", "")) == key0,
			"锁定后推进节点不重摇商店")
	st.queue_free()
	st2.queue_free()
	st3.queue_free()
	st4.queue_free()


func _new_run(p_seed: int) -> EveRunState:
	var st: EveRunState = EveRunState.new()
	add_child(st)
	st.start_run(p_seed)
	return st


# ══════════════════════════════════════════════════════════════════
#  第一段（续）：阶段 B 的数值口径
# ══════════════════════════════════════════════════════════════════

## B0：羁绊表必须与 `02_羁绊系统表.csv` 一致
##
## ⚠️ 上一版把阈值写成 [2,4] / [2,4,6] / [2,4,6]，那是从布局稿的 n/m 反推的示意值。
##    CSV 的真相是 势力[2,4] / 武器[3,6] / 防御[3,6] —— 这条断言就是防它再漂回去。
func _t_trait_table() -> void:
	var problems := EveTraitTable.validate()
	_expect(problems.is_empty(), "羁绊表自检通过（%s）" % str(problems))

	var th := {}
	for g in EveTraitTable.GROUPS:
		th[String(g["key"])] = g["tiers"]
	_expect(str(th.get("faction")) == str([2, 4]),
			"势力阈值 = [2,4]（实际 %s）" % str(th.get("faction")))
	_expect(str(th.get("weapon")) == str([3, 6]),
			"武器阈值 = [3,6]（实际 %s）" % str(th.get("weapon")))
	_expect(str(th.get("defense")) == str([3, 6]),
			"防御阈值 = [3,6]（实际 %s）" % str(th.get("defense")))

	# 档位解析：2 艘艾玛 = 一档；4 艘 = 二档；1 艘 = 无
	_expect(EveTraitTable.tier_of(&"faction", "艾玛", 1).is_empty(), "1 艘艾玛 → 未达档")
	_expect(int(EveTraitTable.tier_of(&"faction", "艾玛", 2)["n"]) == 2, "2 艘艾玛 → 一档")
	_expect(int(EveTraitTable.tier_of(&"faction", "艾玛", 4)["n"]) == 4, "4 艘艾玛 → 二档")

	# 未实装的特殊机制必须挂在 pending 里、不许假装生效
	var t4 := EveTraitTable.tier_of(&"faction", "艾玛", 4)
	_expect(not (t4.get("pending", PackedStringArray()) as PackedStringArray).is_empty(),
			"艾玛二档的「激光灼烧」如实标为未实装")
	var t2 := EveTraitTable.tier_of(&"faction", "艾玛", 2)
	_expect((t2.get("pending", PackedStringArray()) as PackedStringArray).is_empty(),
			"艾玛一档没有未实装项（装甲 +20% 是真加进去的）")


## B1：三连合成 —— 同 id 同星 ×3 → 升一星、可连锁、继承场上的格
func _t_merge() -> void:
	var keys := EveShipDatabase.by_cost(1)
	_expect(keys.size() >= 1, "1 费船可用于合成测试（%d 艘）" % keys.size())
	if keys.is_empty():
		return
	var key := StringName(keys[0]["ship_key"])

	# ① 连买 3 张 → 2★
	var st := _new_run(41)
	st.level = 6                       # 上限 8，买到的都能上场
	st.coin = 999
	_buy_same(st, key, 3)
	_expect(_stars_of(st, key) == [2],
			"买 3 张同名 → 得到 2★（实际 %s）" % str(_stars_of(st, key)))

	# ② 再买 6 张（共 9 张）→ 连锁出 3★
	_buy_same(st, key, 6)
	_expect(_stars_of(st, key) == [3],
			"累计 9 张 → 连锁到 3★（实际 %s）" % str(_stars_of(st, key)))

	# ③ 位置继承：场上 2 张 + 备战席 1 张 → 合成品留在【场上原来的格】
	var st2 := _new_run(42)
	st2.field.clear()
	st2.bench.clear()
	st2.field.append({"ship_key": key, "star": 1, "cell": Vector2i(9, 4)})
	st2.field.append({"ship_key": key, "star": 1, "cell": Vector2i(-1, -1)})
	st2.bench.append({"ship_key": key, "star": 1, "cell": Vector2i(-1, -1)})
	var did := st2._try_merge()
	_expect(did, "场上 2 + 备战席 1 → 触发合成")
	_expect(st2.field.size() == 1 and st2.bench.is_empty(),
			"三张被消耗成一张（上场 %d / 备战 %d）" % [st2.field.size(), st2.bench.size()])
	if st2.field.size() == 1:
		_expect(int(st2.field[0].get("star", 1)) == 2, "合成品是 2★")
		_expect(st2.field[0].get("cell", Vector2i(-1, -1)) == Vector2i(9, 4),
				"合成品继承场上的格 (9,4)（实际 %s）"
				% str(st2.field[0].get("cell", Vector2i(-1, -1))))

	# ④ 2★ 与 1★ 不混着凑（同星才算一组）
	var st3 := _new_run(43)
	st3.field.clear()
	st3.bench.clear()
	st3.bench.append({"ship_key": key, "star": 2, "cell": Vector2i(-1, -1)})
	st3.bench.append({"ship_key": key, "star": 1, "cell": Vector2i(-1, -1)})
	st3.bench.append({"ship_key": key, "star": 1, "cell": Vector2i(-1, -1)})
	st3._try_merge()
	_expect(_stars_of(st3, key) == [1, 1, 2],
			"2★ + 1★×2 不合成（实际 %s）" % str(_stars_of(st3, key)))

	st.queue_free()
	st2.queue_free()
	st3.queue_free()


## B2：上场上限（等级 + 2）是硬的 —— 满了就拒，并给出可读原因
func _t_field_cap() -> void:
	var keys := EveShipDatabase.by_cost(1)
	var st := _new_run(45)
	st.field.clear()
	st.bench.clear()
	_expect(st.field_limit() == 3, "Lv1 上场上限 3（实际 %d）" % st.field_limit())

	for i in 3:
		st.field.append({"ship_key": StringName(keys[i]["ship_key"]),
				"star": 1, "cell": Vector2i(7, i)})
	st.bench.append({"ship_key": StringName(keys[3 % keys.size()]["ship_key"]),
			"star": 1, "cell": Vector2i(-1, -1)})

	var r := st.deploy_from_bench(0, 7, 5)
	_expect(not bool(r.get("ok", true)), "满员时上场被拒（原因：%s）" % String(r.get("reason", "")))
	# 预览接口必须给出同一个结论 —— 提示与实际结果同源，不然会出现「说能放、放不下」
	var pv := st.preview_place(7, 5, &"bench", 0)
	_expect(not bool(pv.get("ok", true)), "预览接口同样拒绝（原因：%s）" % String(pv.get("reason", "")))
	_expect(not bool(st.preview_place(7, 0, &"bench", 0).get("ok", true)), "目标格被占用 → 预览拒绝")
	_expect(not bool(st.preview_place(5, 0, &"bench", 0).get("ok", true)), "隔离区（第 6 行）不能放")
	_expect(not bool(st.preview_place(2, 0, &"bench", 0).get("ok", true)), "敌方区（第 3 行）不能放")

	# 升级之后上限抬到 4。
	# ⚠️ 2026-09-20 起 add_xp【不再】自动补人（auto_deploy 已删）——
	#    升级只是「多了位置」，所以这里不用再重新摆一次：
	#    场上仍是上面那 3 艘、备战席仍是 1 艘，「腾出人口 → 放行」照样验得到。
	st.add_xp(2)
	_expect(st.field_limit() == 4, "Lv2 上场上限 4（实际 %d）" % st.field_limit())
	_expect(st.field.size() == 3, "升级不自动补人 —— 场上仍是 3 艘（实际 %d）" % st.field.size())
	st.field.resize(3)
	st.bench.clear()
	st.bench.append({"ship_key": StringName(keys[0]["ship_key"]),
			"star": 1, "cell": Vector2i(-1, -1)})
	var pv2 := st.preview_place(7, 5, &"bench", 0)
	_expect(bool(pv2.get("ok", true)), "腾出人口后预览放行（原因：%s）" % String(pv2.get("reason", "")))
	st.queue_free()


## B3：羁绊真的乘进舰船数值（不是只在窗里显示个数）
func _t_synergy() -> void:
	# 找 6 艘艾玛
	var amarr: Array = []
	for d in EveShipDatabase.all_ships():
		var tr: PackedStringArray = d.get("traits", PackedStringArray())
		if tr.size() > 0 and String(tr[0]) == "艾玛":
			amarr.append(d)
	_expect(amarr.size() >= 4, "艾玛船 ≥ 4 艘可凑满档（实际 %d）" % amarr.size())
	if amarr.size() < 4:
		return

	var st := _new_run(51)
	st.level = 6
	st.field.clear()
	st.bench.clear()
	for i in 6:
		if i < amarr.size():
			st.field.append({"ship_key": amarr[i]["ship_key"],
					"star": 1, "cell": Vector2i(-1, -1)})

	# 6 艘艾玛 → 二档（+44% 装甲）
	var act := st.active_synergies()
	var hit := {}
	for a in act:
		hit[String(a["member"])] = a
	_expect(hit.has("艾玛"), "6 艘艾玛 → 羁绊生效（生效清单 %s）" % str(hit.keys()))
	if hit.has("艾玛"):
		_expect(int(hit["艾玛"]["n"]) == 4, "艾玛取到二档 4（实际 %d）" % int(hit["艾玛"]["n"]))
		# ⚠️ 别在这句里写裸的 "%" —— 它要和 `% str(...)` 一起用，
		#    裸 % 会被当成格式说明符（"unsupported format character"），
		#    而这只是个 print 级别的错误，测试照样全绿，很容易漏掉。
		_expect(is_equal_approx(float(hit["艾玛"]["apply"].get("armor_pct", 0.0)), 0.44),
				"二档效果 = 装甲 ×1.44（apply=%s）" % str(hit["艾玛"]["apply"]))

	# 数值落地：装甲真的 ×1.44
	var ship := EveShipDatabase.instantiate_by_id(String(amarr[0]["ship_key"]), 0, 9001)
	var armor0 := float(ship.max_hp[&"armor"])
	var fleet: Array = [ship]
	st.apply_synergies_to(fleet)
	var armor1 := float(ship.max_hp[&"armor"])
	_expect(is_equal_approx(armor1, armor0 * 1.44),
			"装甲真被乘上 1.44（%.0f → %.0f）" % [armor0, armor1])

	# 只有 1 艘 → 不生效，且数值不该变
	st.field.resize(1)
	_expect(st.active_synergies().is_empty(), "1 艘艾玛 → 羁绊不生效")
	var ship2 := EveShipDatabase.instantiate_by_id(String(amarr[0]["ship_key"]), 0, 9002)
	var a0 := float(ship2.max_hp[&"armor"])
	st.apply_synergies_to([ship2] as Array)
	_expect(is_equal_approx(float(ship2.max_hp[&"armor"]), a0), "未达档时装甲不动")
	# ⚠️ EveShip 是 RefCounted，没有 queue_free —— 出作用域就回收
	st.queue_free()


## B5：拖放要用到的编制 API（部署 / 换位 / 撤回 / 出售 / 战斗期锁定）
func _t_drag_api() -> void:
	var keys := EveShipDatabase.by_cost(1)
	var st := _new_run(46)
	st.level = 3                        # 上限 5
	st.field.clear()
	st.bench.clear()
	st.bench.append({"ship_key": keys[0]["ship_key"], "star": 1, "cell": Vector2i(-1, -1)})
	st.bench.append({"ship_key": keys[1]["ship_key"], "star": 1, "cell": Vector2i(-1, -1)})

	var r := st.deploy_from_bench(0, 8, 5)
	_expect(bool(r.get("ok", false)), "备战席 → 棋盘 (8,5) 部署成功（%s）" % String(r.get("reason", "")))
	_expect(st.field.size() == 1 and st.bench.size() == 1,
			"编制变成 上场 1 / 备战席 1（实际 %d / %d）" % [st.field.size(), st.bench.size()])
	if st.field.size() == 1:
		_expect(st.field[0].get("cell", Vector2i(-1, -1)) == Vector2i(8, 5),
				"格号写进编制（实际 %s）" % str(st.field[0].get("cell", Vector2i(-1, -1))))

	r = st.move_field(0, 9, 2)
	_expect(bool(r.get("ok", false)) and st.field[0].get("cell", Vector2i(-1, -1)) == Vector2i(9, 2),
			"场上换位 → (9,2)")

	r = st.recall_to_bench(0)
	_expect(bool(r.get("ok", false)) and st.field.is_empty() and st.bench.size() == 2,
			"撤回备战席 → 上场 0 / 备战席 2")
	_expect(st.bench[1].get("cell", Vector2i(0, 0)) == Vector2i(-1, -1), "撤回后格号被清空")

	# 出售返还 = 原价 × 3^(star-1)：合成后再卖不亏
	st.coin = 0
	st.bench.clear()
	var cost := int(keys[0]["cost"])
	st.bench.append({"ship_key": keys[0]["ship_key"], "star": 2, "cell": Vector2i(-1, -1)})
	var back := st.sell_value(st.bench[0])
	_expect(back == cost * 3, "2★ 出售返还 3×原价 = %d（实际 %d）" % [cost * 3, back])
	r = st.sell_from_bench(0)
	_expect(bool(r.get("ok", false)) and st.coin == back,
			"出售到账 %d（实际 %d）" % [back, st.coin])

	# 战斗中一切编制改动被拒
	st.set_phase(EveRunState.Phase.BATTLE)
	_expect(not bool(st.deploy_from_bench(0, 7, 0).get("ok", true)), "战斗中部署被拒")
	_expect(not bool(st.move_field(0, 7, 0).get("ok", true)), "战斗中换位被拒")
	_expect(not bool(st.recall_to_bench(0).get("ok", true)), "战斗中撤回被拒")
	_expect(not bool(st.sell_from_bench(0).get("ok", true)), "战斗中出售被拒")
	st.queue_free()


# ══════════════════════════════════════════════════════════════════
#  第一段（续）：阶段 C 的数值口径
# ══════════════════════════════════════════════════════════════════

## C1：事件选项表自检
##
## ⚠️ 这里守的是三件事，都是「表一旦被改坏、面板会静默出丑」的类型：
##   ① 三个事件节点**共用同一套**选项（不是三套）—— 表就只有一份；
##   ② 每条效果的键必须在 `_apply_synergy` / `apply_event` 认得的词表里。
##      **拼错键名不会报错**，只会让那条增益变成空牌（玩家以为拿到 18% 装甲，
##      其实什么都没发生）—— 这是本表最容易烂的方式，必须断言。
##   ③ 每个 tag 都有配色（没有配色 = 卡片顶条变透明，一眼像坏了）。
func _t_event_table() -> void:
	var idx := EveNodeTable.event_indexes()
	_expect(idx.size() == 3 and idx[0] == 4 and idx[1] == 10 and idx[2] == 14,
			"事件节点 = 节点 4 / 10 / 14（实际 %s）" % str(idx))

	var opts := EveEventTable.all()
	_expect(opts.size() == 4, "事件选项 4 条（实际 %d）" % opts.size())

	# ① id 唯一
	var ids := {}
	var dup := ""
	for o in opts:
		var id := StringName(o.get("id", &""))
		if ids.has(id):
			dup = String(id)
		ids[id] = true
	_expect(dup == "", "id 互不重复（第一个重复项：%s）" % dup)
	_expect(not EveEventTable.has_id(&"__nope__"), "查不存在的 id 返回 false")
	_expect(EveEventTable.by_id(&"__nope__").is_empty(), "查不存在的 id 返回空表（不兜底）")

	# ② 键名合法 + 必填字段齐全
	var allowed := ["armor_pct", "shield_pct", "attack_pct", "cycle_pct",
			"speed_pct", "hull_flat", "shield_flat"]
	var bad_key := ""
	var missing := ""
	var empty_effect := ""
	var bad_color := ""
	for o in opts:
		var id := String(o.get("id", &""))
		for k in ["name", "tag", "icon", "desc", "effect"]:
			if String(o.get(k, "")).strip_edges() == "":
				missing = "%s.%s" % [id, k]
		var ap: Dictionary = o.get("apply", {})
		for k in ap.keys():
			if not allowed.has(String(k)):
				bad_key = "%s: %s" % [id, String(k)]
		# 逐艘增益（选 1 艘的选项）走 ship_apply，键表与 apply 同一套
		var sap: Dictionary = o.get("ship_apply", {})
		for k in sap.keys():
			if not allowed.has(String(k)):
				bad_key = "%s.ship_apply: %s" % [id, String(k)]
		var has_effect := not ap.is_empty() or not sap.is_empty()
		if bool(o.get("pick_ship", false)) or bool(o.get("free_advanced_roll", false)):
			has_effect = true
		# ⛔ leak_reduce 已随「漏网」机制删除（2026-10-01）
		for k in ["coin", "coin_per_node", "xp", "beacon_heal", "beacon_max"]:
			if int(o.get(k, 0)) != 0:
				has_effect = true
		if not has_effect:
			empty_effect = id
		var col := EveEventTable.tag_color(StringName(o.get("tag", &"")))
		if col.a <= 0.0 or (col.r + col.g + col.b) <= 0.0:
			bad_color = id
	_expect(bad_key == "", "apply 键名全在词表内（越界项：%s）" % bad_key)
	_expect(missing == "", "每条都有 name/tag/icon/desc/effect（缺项：%s）" % missing)
	_expect(empty_effect == "", "每条至少有一个效果字段（空牌：%s）" % empty_effect)
	_expect(bad_color == "", "每个 tag 都有配色（无配色：%s）" % bad_color)
	# 四条必须覆盖四个不同分类 —— 否则 4 选 3 的取舍会退化成「三条同类 + 一条陪跑」
	var tags := {}
	for o in opts:
		tags[StringName(o.get("tag", &""))] = true
	_expect(tags.size() == 4, "四个分类互不相同（实际 %s）" % str(tags.keys()))

	# ★★ 反向注入：**四条事件一条都不许给星币**（2026-10-01 用户裁决）
	#
	#   「主要是回合给的星币太多了，而且给星币不合适，还是改成这个文件里的那样吧。」
	#   交接文档 §7.2 的四条里一条都不给星币。
	#   把 `coin` / `coin_per_node` 加回任何一条 ⇒ 这条必挂。
	var payer := ""
	for o in opts:
		if int(o.get("coin", 0)) != 0 or int(o.get("coin_per_node", 0)) != 0:
			payer = String(o.get("id", ""))
	_expect(payer == "", "★ 反向注入：四条事件都不给星币（违规项：%s）" % payer)
	_expect(EveEventTable.count() == 4, "仍然是四选一（实际 %d）" % EveEventTable.count())
	_expect(EveEventTable.has_id(&"weapon_tune") and EveEventTable.has_id(&"armor_plate")
			and EveEventTable.has_id(&"beacon_repair") and EveEventTable.has_id(&"black_market"),
			"四条 id 与交接文档 §7.2 一致（weapon_tune / armor_plate / beacon_repair / black_market）")


## C2：事件效果真的落到状态机上（2026-10-01 按交接文档 §7.2 的四条重写）
func _t_event_apply() -> void:
	# ① 选船类：**没给目标必须被拒**，而且不许记成"已获取"
	#    （否则玩家点一下、什么都没拿到、这一条还没了 —— 静默损失一次事件）
	var st := _new_run(77)
	st.coin = 0
	st.beacon = 50
	var no_target := st.apply_event(&"weapon_tune")
	_expect(no_target.is_empty(), "★ 选船类没给目标 ⇒ 落地被拒（不是静默生效）")
	_expect(st.event_picks.is_empty(), "★ 被拒时不记「已获取」（否则白损失一次事件）")

	# ② 武器调校：只有**选中那一艘** ATK ×1.08
	st.field.clear()
	st.field.append({"ship_key": &"punisher", "star": 1, "cell": Vector2i(0, 0)})
	st.field.append({"ship_key": &"executioner", "star": 1, "cell": Vector2i(1, 0)})
	var opt := st.apply_event(&"weapon_tune", st.field_entries()[0])
	_expect(not opt.is_empty(), "apply_event 返回生效条目")
	var s0 := EveShipDatabase.instantiate_by_id("punisher", 0, 9001)
	var s1 := EveShipDatabase.instantiate_by_id("executioner", 0, 9002)
	_expect(s0 != null and s1 != null, "取到两艘 1 费船用于验证选船增益")
	if s0 != null and s1 != null:
		var atk0 := s0.attack
		var atk1 := s1.attack
		var idx_map: Array[int] = [0, 1]
		st.apply_field_buffs_to([s0, s1], idx_map)
		_expect(is_equal_approx(s0.attack, atk0 * 1.08),
				"武器调校：选中那艘 ATK ×1.08（%.1f → %.1f）" % [atk0, s0.attack])
		_expect(is_equal_approx(s1.attack, atk1),
				"★ 只有选中的那艘被强化（没选的那艘 %.1f 不变）" % atk1)

	# ③ 结构加固：结构 ×1.15
	var st2 := _new_run(78)
	st2.field.clear()
	st2.field.append({"ship_key": &"punisher", "star": 1, "cell": Vector2i(0, 0)})
	st2.apply_event(&"armor_plate", st2.field_entries()[0])
	var s2 := EveShipDatabase.instantiate_by_id("punisher", 0, 9003)
	if s2 != null:
		# ⚠️ EveShip 的血量是 `max_hp` / `hp` 两个 Dictionary（键 armor/hull/shield），
		#    **没有** `ship.armor` 这个属性 —— `layer_hp_adjust()` 写的就是这两个字典。
		var arm0: float = float(s2.max_hp[&"armor"])
		var idx2: Array[int] = [0]
		st2.apply_field_buffs_to([s2], idx2)
		_expect(is_equal_approx(float(s2.max_hp[&"armor"]), arm0 * 1.15),
				"结构加固：结构 ×1.15（%.1f → %.1f）" % [arm0, float(s2.max_hp[&"armor"])])

	# ④ 紧急维修：+10 且夹在上限内
	var st3 := _new_run(79)
	st3.beacon = 95
	st3.apply_event(&"beacon_repair")
	_expect(st3.beacon == 100, "紧急维修 +10 且夹在上限（95 → %d）" % st3.beacon)
	_expect(st3.apply_event(&"beacon_repair").is_empty(), "同一条不能二次选取")
	_expect(st3.apply_event(&"__nope__").is_empty(), "不存在的 id 落地被拒")

	# ⑤ 黑市情报：免费高级刷新 —— ★ 保底在**下一节点**落地（审查 R05）
	#    ⚠️ 故意把等级压到 1 —— 那一档 100% 只出 1 费，保底不生效就必然抓得到。
	#    ★ 2026-10-10：事件不再当场刷新（会被 `advance()` 的普通 roll 覆盖）
	#      ⇒ 必须 `advance()` 之后再检查货架。
	var st4 := _new_run(80)
	st4.level = 1
	st4.overtier = 0
	st4.set_phase(EveRunState.Phase.RESOLVE)
	var o4 := st4.apply_event(&"black_market")
	_expect(not o4.is_empty(), "黑市情报落地")
	st4.advance()
	var has_hi := false
	for d in st4.offers:
		if int((d as Dictionary).get("cost", 1)) >= 3:
			has_hi = true
	_expect(has_hi, "★ 黑市保底：下一节点 5 槽至少 1 艘 cost ≥ 3（1 级商店原本 100% 是 1 费）")

	# ⑥ 星币：选完事件**钱包不能变**（反向注入：不给星币）
	var st5 := _new_run(81)
	st5.coin = 7
	st5.field.clear()
	st5.field.append({"ship_key": &"punisher", "star": 1, "cell": Vector2i(0, 0)})
	st5.apply_event(&"weapon_tune", st5.field_entries()[0])
	_expect(st5.coin == 7, "★ 选完事件星币分文不动（7 → %d）" % st5.coin)
	_expect(st5.event_coin_per_node() == 0, "★ 没有「每节点收入 +N」这类事件（实际 %d）" % st5.event_coin_per_node())

	# ⑦ 面板拿到的选项带 taken 标记，且是复制品
	var st6 := _new_run(82)
	st6.apply_event(&"beacon_repair")
	var shown := st6.event_options()
	var taken_n := 0
	for d in shown:
		if bool((d as Dictionary).get("taken", false)):
			taken_n += 1
		(d as Dictionary)["__probe__"] = true
	_expect(taken_n == 1, "event_options 标出 1 条已获取（实际 %d）" % taken_n)
	_expect(not EveEventTable.all()[0].has("__probe__"),
			"event_options 返回的是复制品（没有污染常量表）")

	st.queue_free()
	st2.queue_free()
	st3.queue_free()
	st4.queue_free()


# ══════════════════════════════════════════════════════════════════
#  第一段（续）：阶段 C 的打捞（残骸 → 下单 → 延迟到账 → 占货位）
# ══════════════════════════════════════════════════════════════════

## C3：打捞整条链的数值口径
##
## 四个「必须成立」的东西，缺一个这条链就是假的：
##   ① 残骸只能从**战斗击毁**来（不能凭空发）；
##   ② 下单当场扣钱，但东西**不在本节点给**；
##   ③ 到账后占住货位，**付费刷新也刷不掉**；
##   ④ 买走要**解锁**（不解锁那个格子永远刷不动）、没买走要**过期**（不然白占一辈子）。
## C3：打捞整条链的数值口径（★ 2026-10-04 全面重写为多选版）
##
## ## 口径变更对照（旧 → 新）
## ##   残骸      单艘「取费用最高」 → **本回合全部阵亡（敌我）都在列表里**
## ##   打捞费    统一 ⌈费用×0.5⌉   → **我方 ×0.5 / 敌方 ×1.0**（两档博弈）
## ##   下单      `salvage_order()` 整框单选 → `salvage_order(idxs)` **逐艘勾选**
## ##   阶段      只在 PREP 可下单   → **只在 RESOLVE（结算页）可下单**
## ##   上限      无               → **最多 5 艘**（= 商店货位数）
## ##   钱不够    整单拒绝          → **买得起就买，买不起的跳过**（部分成交）
##
## 六个「必须成立」的东西，缺一个这条链就是假的：
##   ① 残骸只能从**战斗击毁**来（不能凭空发），且**一艘不漏**；
##   ② 两档定价真的按阵营分（我方半价 / 敌方全价）；
##   ③ **打捞在结算页**，不在准备阶段（时序直觉：第二回合就该到手）；
##   ④ 部分成交：钱不够时买得起的那几艘照样成交；
##   ⑤ 上限 5 艘：勾第 6 艘**买不了**（不静默截断）；
##   ⑥ 到账后占住货位、付费刷新刷不掉、买走解锁、没买走过期。
func _t_salvage() -> void:
	var st := _new_run(88)

	# ── ① 开局干净 ──
	_expect(st.wrecks.is_empty() and st.repair_queue.is_empty()
			and st.salvage_slots.is_empty(),
			"开局：无残骸 / 无修复队列 / 没占货位")
	_expect(st.salvage_info().is_empty(), "salvage_info 开局为空（HUD 打捞框走 empty 态）")
	_expect(st.salvage_cost_of(0) == 0, "无残骸时打捞费 = 0（越界不抛错）")

	# ── ② 残骸只能从战斗来，且【一艘不漏】──
	var d1 := EveShipDatabase.by_cost(1)[0]
	var d4 := EveShipDatabase.by_cost(4)[0]
	var d3 := EveShipDatabase.by_cost(3)[0]
	var r := st.resolve_battle(0, [d1.duplicate(true), d4.duplicate(true),
			d3.duplicate(true)])
	_expect(bool(r.get("wreck", false)), "结算返回值里带 wreck 标记")
	# ★ 核心变更：3 艘进 3 艘出（旧版这里只留 1 艘「最贵的」）
	_expect(st.wrecks.size() == 3,
			"★ 本回合 3 艘被击毁 → 残骸列表 3 艘（一艘不漏，实测 %d）"
			% st.wrecks.size())
	# 按费用降序（贵的在前）—— UI 列表从上到下就是「先看贵的」
	_expect(int((st.wrecks[0] as Dictionary).get("cost", 0)) == 4
			and int((st.wrecks[2] as Dictionary).get("cost", 0)) == 1,
			"★ 列表按费用降序（4 费 → 1 费），第 1 艘是最贵的")
	_expect(int(r.get("wreck_count", -1)) == 3,
			"结算返回值带 wreck_count = 3（结算页按钮要用）")

	# ── ③ 两档定价（用户定案的核心博弈）──
	# 喂进去的字典没有 team 键 ⇒ 默认按我方（0）算半价。
	var expect_own := maxi(1, int(ceil(4.0 * EveRunState.SALVAGE_COST_RATIO)))
	_expect(st.salvage_cost_of(0) == expect_own,
			"★ 我方 4 费残骸打捞费 = 4 × %.2f = %d（实测 %d）"
			% [EveRunState.SALVAGE_COST_RATIO, expect_own, st.salvage_cost_of(0)])
	# 手动把第 0 艘标成敌方 ⇒ 立刻变全价（**同一艘、两个价**）
	(st.wrecks[0] as Dictionary)["team"] = 1
	var expect_foe := maxi(1, int(ceil(4.0 * EveRunState.SALVAGE_COST_RATIO_ENEMY)))
	_expect(st.salvage_cost_of(0) == expect_foe,
			"★ 敌方 4 费残骸打捞费 = 4 × %.2f = %d（实测 %d）—— 比我方贵 %d"
			% [EveRunState.SALVAGE_COST_RATIO_ENEMY, expect_foe,
			st.salvage_cost_of(0), expect_foe - expect_own])
	_expect(expect_foe > expect_own,
			"★ 两档定价真的分开了：敌方 %d ◆ > 我方 %d ◆（否则「取舍」不成立）"
			% [expect_foe, expect_own])
	(st.wrecks[0] as Dictionary)["team"] = 0   # 还原，后面还要用它

	# ── ④ 阶段口径：结算页能打捞，准备阶段不能 ──
	# ⚠️ 旧版正好相反（旧版是 PREP 能打捞）—— 这条断言是「时序改对了」的唯一判据。
	_expect(bool(st.can_salvage().get("ok", false)),
			"★ 结算阶段（RESOLVE）可以打捞 —— 这就是「第二回合到手」的关键")
	st.set_phase(EveRunState.Phase.PREP)
	_expect(not bool(st.can_salvage().get("ok", false)),
			"★ 准备阶段（PREP）**不能**打捞（旧口径的反面，防止反悔白嫖）")
	st.set_phase(EveRunState.Phase.RESOLVE)

	# ── ⑤ 部分成交：钱不够时买得起的照样成交 ──
	st.coin = 0
	var none := st.salvage_order([0, 1, 2])
	_expect(not bool(none.get("ok", false)), "零钱下单被打捞被拒")
	_expect((none.get("skipped", []) as Array).size() == 3,
			"★ 三艘全因没钱被跳过（实测跳过 %d）"
			% (none.get("skipped", []) as Array).size())
	_expect(String(none.get("reason", "")).contains("星币不足"),
			"拒绝理由说清是钱不够：%s" % String(none.get("reason", "")))
	# ⚠️★ 买不起的**必须留在列表里**（用户定案「买得起就买，买不起弹提示」）：
	#    删掉就等于「钱不够 ⇒ 这批货永远没了」，那是判决不是提示。
	_expect(st.wrecks.size() == 3,
			"★ 一艘没买成 ⇒ 3 艘全部仍在列表里等下一轮（实测 %d）" % st.wrecks.size())
	# 4 费半价=2 + 3 费半价=2 + 1 费半价=1 ⇒ 合计 5（这个和是**独立算出来的**，
	# 不许直接读被测代码的结果 —— 那样这条断言就是自证）
	_expect(String(none.get("reason", "")).contains("5"),
			"★ 提示里报出真实总价（本批需 5 ◆，不是 0）—— 实际「%s」"
			% String(none.get("reason", "")))
	# 给够第一艘的钱 ⇒ 第一艘成交、后两艘跳过（**部分成交**）
	st.coin = 99
	var part := st.salvage_order([0, 1, 2])
	_expect(bool(part.get("ok", false)), "★ 钱够第一艘 ⇒ 部分成交成立")
	_expect((part.get("bought", []) as Array).size() >= 1,
			"★ 至少买到 1 艘（实测 %d）" % (part.get("bought", []) as Array).size())
	_expect(st.wrecks.size() == 3 - (part.get("bought", []) as Array).size(),
			"★ 只从列表移走买成的那几艘（剩 %d）" % st.wrecks.size())

	# ── ★ 越界下标必须给出**明确理由**，不能静默丢弃 ──
	#  场景：打捞掉一艘后 UI 没来得及重画，玩家点的是**旧列表**里的行 ⇒
	#  传进来的下标已经越界。旧实现把它全剔掉 → `picked` 为空 →
	#  报一句「没有勾选任何残骸」：玩家明明点了，却被告知"没勾选"，
	#  提示指错方向，看着就是「点了没反应」。（2026-10-05 修）
	# ⚠️ 必须先保证列表**非空** —— 否则会先撞上「没有可打捞的残骸」那条早退，
	#    测不到越界分支（第一次跑就是这么红的，断言的**前提**没摆对）。
	st.resolve_battle(0, [d1.duplicate(true)])
	st.set_phase(EveRunState.Phase.RESOLVE)
	_expect(st.wrecks.size() == 1, "前置：列表里有 1 艘可供越界测试")
	var oob := st.salvage_order([99])
	_expect(not bool(oob.get("ok", false)), "越界下标下单被拒")
	_expect(String(oob.get("reason", "")).contains("列表已变化"),
			"★★ 越界时理由说清是「列表已变化」（实际「%s」）"
			% String(oob.get("reason", "")))

	# 重新造一批残骸，接着测上限与到账
	var st2 := _new_run(89)
	var six: Array = []
	for i in 6:
		six.append((EveShipDatabase.by_cost(1)[i % 2].duplicate(true)))
	st2.resolve_battle(0, six)
	_expect(st2.wrecks.size() == 6, "造了 6 艘残骸（用于测上限）")

	# ── ⑥ 上限 5 艘（用户定案「最多选 5 艘」）──
	st2.coin = 999
	var cap := st2.salvage_order([0, 1, 2, 3, 4, 5])
	_expect((cap.get("bought", []) as Array).size()
			== EveRunState.SALVAGE_MAX_PICK,
			"★ 勾 6 艘只成交 %d 艘（= SALVAGE_MAX_PICK %d）"
			% [(cap.get("bought", []) as Array).size(), EveRunState.SALVAGE_MAX_PICK])
	_expect((cap.get("skipped", []) as Array).size() == 1,
			"★ 超出上限的那 1 艘进 skipped（不是静默丢掉）")
	_expect(st2.wrecks.size() == 1,
			"★ 超限的那 1 艘仍在列表（玩家可以下轮再捞），实测 %d" % st2.wrecks.size())
	_expect(EveRunState.SALVAGE_MAX_PICK == 5,
			"★ 上限 = 5（= 商店货位数 %d）" % EveRunState.SHOP_SLOTS)

	# ── ⑦ 到账：下一节点占住货位 ──
	var st3 := _new_run(90)
	var three: Array = []
	for i in 3:
		three.append((EveShipDatabase.by_cost(1)[i % 2].duplicate(true)))
	st3.resolve_battle(0, three)
	st3.coin = 99
	var ord3 := st3.salvage_order([0, 1, 2])
	var n3 := (ord3.get("bought", []) as Array).size()
	_expect(n3 == 3, "3 艘全成交（钱充足）")
	st3.advance()
	_expect(st3.repair_queue.is_empty(), "到账后修复队列清空")
	_expect(st3.salvage_slots.size() == n3,
			"★ 下一节点占住 %d 个货位（实际 %s）" % [n3, str(st3.salvage_slots)])
	_expect(st3.offers.size() == EveRunState.SHOP_SLOTS,
			"商店仍是 %d 个货位（打捞品是**顶掉**其中几个，不是多出来）"
			% EveRunState.SHOP_SLOTS)

	# ── ⑧ 付费刷新刷不掉它 —— 这条不成立，「延迟到账」就是诈骗 ──
	var before_key := String((st3.offers[0] as Dictionary).get("ship_key", ""))
	st3.coin = 50
	st3.refresh()
	_expect(String((st3.offers[0] as Dictionary).get("ship_key", "")) == before_key,
			"付费刷新不会刷掉打捞品（滚动 refresh 走的正是 roll_shop）")

	# ── ⑨ 买走 → 解锁（**买走一个解锁一个**，不是全解锁）──
	# ⚠️ 2026-10-04 修正：多选打捞会一次占住**多个**货位，
	#    只买走一个时**其余货位必须还占着**（那些是玩家还没花钱买的）。
	#    旧断言「买走后 salvage_slots 为空」在单选时代是对的，多选下是错的。
	var bought := st3.buy(0)
	_expect(bool(bought.get("ok", false)), "打捞品能正常买走")
	_expect(not st3.salvage_slots.has(0),
			"★ 买走的那个货位已解锁（实际占位 %s）" % str(st3.salvage_slots))
	_expect(st3.salvage_slots.size() == n3 - 1,
			"★ 没买走的 %d 艘仍占着货位（不能顺手解锁玩家的货）"
			% (n3 - 1))

	# ── ⑩ 没买走的打捞品在离开节点时作废 ──
	var st4 := _new_run(91)
	var one: Array = [d3.duplicate(true)]
	st4.resolve_battle(0, one)
	st4.coin = 99
	st4.salvage_order([0])
	st4.advance()
	_expect(st4.salvage_slots.size() == 1, "节点 N：打捞品已占位")
	st4.advance()
	_expect(st4.salvage_slots.is_empty(), "节点 N+1：没买走的打捞品作废、货位解锁")
	var stale = st4.offers[0]
	_expect(not (stale is Dictionary and (stale as Dictionary).has("from_node")),
			"作废后 0 号位不再是打捞品")

	# ── ⑪ ⚠️ 锁定列表（shop_locked）时 advance() **不重摇** ──
	#     过期清理必须自己动手，否则陈旧的打捞品会一直赖在货架上（而且不报错）
	var st5 := _new_run(92)
	st5.resolve_battle(0, [d3.duplicate(true)])
	st5.coin = 99
	st5.salvage_order([0])
	st5.advance()
	st5.set_shop_locked(true)
	st5.advance()
	_expect(st5.salvage_slots.is_empty(), "锁定列表时过期件也照样清掉")
	var stale5 = st5.offers[0]
	_expect(not (stale5 is Dictionary and (stale5 as Dictionary).has("from_node")),
			"锁定态下 0 号位也已换成普通报价")

	# ── ⑫ ★ 下一回合换成**新一批**残骸（不是累积）──
	#     用户原话：「下一回合有下一回合的打捞列表」。
	var st6 := _new_run(93)
	st6.resolve_battle(0, [d1.duplicate(true), d4.duplicate(true)])
	var first_batch := st6.wrecks.size()
	_expect(first_batch == 2, "第一批残骸 2 艘")
	st6.coin = 999
	st6.salvage_order([0])          # 只买走 1 艘
	_expect(st6.wrecks.size() == 1, "买走后列表里剩 1 艘（没买的仍可选）")
	# 再打一场 ⇒ 整批**重填**，上一批没买的作废
	st6.set_phase(EveRunState.Phase.RESOLVE)
	st6.resolve_battle(0, [d3.duplicate(true)])
	_expect(st6.wrecks.size() == 1,
			"★ 下一回合整批重填（上一批未打捞的作废，剩 %d 艘）" % st6.wrecks.size())
	_expect(int((st6.wrecks[0] as Dictionary).get("cost", 0)) == 3,
			"★ 新一批是本回合的 3 费船（证明不是残留的 1 费）")

	print("[打捞] 多选版：两档定价（我方 ×%.2f / 敌方 ×%.2f）· 上限 %d 艘 · "
			% [EveRunState.SALVAGE_COST_RATIO, EveRunState.SALVAGE_COST_RATIO_ENEMY,
			EveRunState.SALVAGE_MAX_PICK]
			+ "部分成交 ✓ · 第二节点到账 ✓ · 零选/换批 ✓")

	st.queue_free()
	st2.queue_free()
	st3.queue_free()
	st4.queue_free()
	st5.queue_free()
	st6.queue_free()


## ══════════════════════════════════════════════════════════════════
##  ★ C5 打捞范围 = **敌我双方**（2026-10-01 用户定案）
## ══════════════════════════════════════════════════════════════════
##
## 用户原话：「打捞要么只打捞我方的，要么打捞敌我双方的，
##            断然没有只打捞敌方的道理」。
##
## ⚠️ 为什么 C3 测不到这条：C3 是**直接把字典喂给 `resolve_battle()`**，
##    它绕过了 `EveBattleScene._on_battle_finished()` ——
##    而「谁被收进 destroyed」恰恰只发生在那里。
##    ⇒ 一个从来没测过的「收集侧」正好是病根所在，这就是必须新增 C5 的理由。
##
## 这里用 `_logi_probe_salvage_scope()` 现场跑一场**真战斗**，
## 只读它的返回值，不重算任何东西。
func _t_salvage_scope() -> void:
	var r: Dictionary = await _logi_probe_salvage_scope()
	_expect(bool(r.get("ok", false)), "能跑通一场真战斗并拿到打捞范围证据")
	# ① 我方阵亡者确实进了 destroyed 集合
	_expect(int(r.get("own_dead", 0)) > 0, "本场有我方舰船阵亡（否则这条测不到）")
	_expect(int(r.get("own_in_destroyed", -1)) == int(r.get("own_dead", -1)),
			"★ 我方阵亡者【全部】被收进打捞池 —— 结算页 destroyed=%d，扣掉敌方 %d ⇒ 我方 %d／%d"
			% [int(r.get("destroyed_count", -1)), int(r.get("enemy_dead", 0)),
			int(r.get("own_in_destroyed", -1)), int(r.get("own_dead", 0))])
	# ② 敌方也一样（不能为了修①把敌方丢了）
	_expect(int(r.get("enemy_in_destroyed", -1)) == int(r.get("enemy_dead", -1)),
			"敌方阵亡者同样全部在池内（%d/%d）"
			% [int(r.get("enemy_in_destroyed", -1)), int(r.get("enemy_dead", 0))])
	# ③ ★ 反向注入：同一场里，结算页的 destroyed 计数必须**大于纯敌方阵亡数** ——
	#    相等就说明「加我方」这件事没生效（收集侧还在只收敌方）
	_expect(int(r.get("destroyed_count", 0)) > int(r.get("enemy_pool_alone", 0)),
			"★★ 反向注入：结算页 destroyed=%d **严格大于**纯敌方阵亡数 %d —— 若相等，说明我方阵亡者没被收进去"
			% [int(r.get("destroyed_count", 0)), int(r.get("enemy_pool_alone", 0))])
	# ④ 挑出来的那艘仍然是**双方合池里最贵**的
	_expect(String(r.get("picked_key", "")) == String(r.get("best_key", "")),
			"残骸仍是合池里费用最高的一艘（%s）"
			% String(r.get("picked_name", "?")))

	print("[打捞范围] 我方阵亡 %d/%d · 敌方阵亡 %d/%d · 合池 %d 艘（纯敌方 %d 艘）· 产出 %s"
			% [int(r.get("own_in_destroyed", 0)), int(r.get("own_dead", 0)),
			int(r.get("enemy_in_destroyed", 0)), int(r.get("enemy_dead", 0)),
			int(r.get("pool_size", 0)), int(r.get("enemy_pool_alone", 0)),
			String(r.get("picked_name", "?"))])


## ══════════════════════════════════════════════════════════════════
##  ★ E1 后勤舰（2026-10-01 用户定案：「攻击要低、后勤要真」）
## ══════════════════════════════════════════════════════════════════
##
## 用户原话：「后勤舰是维修其他舰船的，但我发现后勤舰似乎也有攻击能力，
##            现在需要你给出具体数值，并检查其机制有效性。
##            因为后勤舰的攻击能力是要比较低的，甚至没有最好。」
##          「按照设定是加达里和米玛塔尔的船修盾，艾玛和盖伦特的船修甲」
##
## 这一组把上面两句变成可证伪的断言。四条：
##   ① 后勤舰的**实际火力**远低于同吨位攻击型（且没压到 0 —— 见源码注释）
##   ② 后勤舰能给**友军**修血（修量 > 0，且真的进了队友的 hp）
##   ③ 修哪一层 **读 `defense` 列**：盾抗→护盾、甲抗→装甲（8 艘逐艘核对）
##   ④ ★ **含自己**（2026-10-01 改口径）、不修结构、满血不修（三条边界）
func _t_logistics() -> void:
	# ── ① 攻击压制 ──
	var atk_of := func(id: String) -> float:
		var d := EveShipDatabase.by_id(id)
		return float(d.get("weapon_damage", 0.0))
	var tbl_of := func(id: String) -> float:
		var d := EveShipDatabase.by_id(id)
		return float(d.get("attack", 0.0))

	# 护卫档：攻击型 13 / 后勤 3
	_expect(is_equal_approx(atk_of.call("condor"), 13.0)
			and is_equal_approx(atk_of.call("bantam"), 3.0),
			"护卫：攻击型火力 13 · 后勤火力 3（实际 %.0f / %.0f）"
			% [atk_of.call("condor"), atk_of.call("bantam")])
	# 巡洋档：攻击型 40 / 后勤 10
	_expect(is_equal_approx(atk_of.call("caracal"), 40.0)
			and is_equal_approx(atk_of.call("osprey"), 10.0),
			"巡洋：攻击型火力 40 · 后勤火力 10（实际 %.0f / %.0f）"
			% [atk_of.call("caracal"), atk_of.call("osprey")])
	# 后勤 ≤ 攻击型的 1/3（留出「没压到 0」的余量，但不许接近）
	_expect(atk_of.call("bantam") <= atk_of.call("condor") / 3.0
			and atk_of.call("osprey") <= atk_of.call("caracal") / 3.0,
			"★ 后勤火力 ≤ 同吨位攻击型的 1/3")
	# ⚠️ 不许压到 0 —— 完全不能打的单位落单会让战斗僵住
	_expect(atk_of.call("bantam") > 0.0 and atk_of.call("osprey") > 0.0,
			"★ 后勤火力 > 0（压到 0 会让落单的后勤舰造成僵局）")
	# ★ 反向注入：`attack`（权威表原值）**必须没被改** ——
	#    改了它等于伪造设计侧数据，HUD 上会显示一个假的「攻击」
	_expect(is_equal_approx(tbl_of.call("bantam"), 12.0)
			and is_equal_approx(tbl_of.call("osprey"), 35.0),
			"★ 权威表的 attack 原值没被改（矮脚鸡 12 / 鱼鹰 35）")
	_expect(not is_equal_approx(atk_of.call("bantam"), tbl_of.call("bantam")),
			"★ 后勤船的「表列攻击」与「实际火力」**故意不同**（%0.f vs %0.f）"
			% [tbl_of.call("bantam"), atk_of.call("bantam")])

	# ── ② + ③ 修层：8 艘后勤舰逐艘核对（4 派系 × 2 吨位）──
	#    加达里 / 米玛塔尔 = 盾抗 → 修护盾
	#    艾玛 / 盖伦特     = 甲抗 → 修装甲
	var cases := {
		"bantam": &"shield", "burst": &"shield",
		"osprey": &"shield", "scythe": &"shield",
		"navitas": &"armor", "inquisitor": &"armor",
		"exequror": &"armor", "augoror": &"armor",
	}
	for id in cases.keys():
		var d := EveShipDatabase.by_id(String(id))
		_expect(StringName(d.get("logistics_layer", &"")) == cases[id],
				"%s（%s）修 %s"
				% [String(d.get("name", id)), String(d.get("faction_cn", "?")),
				"护盾" if cases[id] == &"shield" else "装甲"])
		_expect(float(d.get("logistics_repair", 0.0)) > 0.0,
				"%s 的修量 > 0" % String(d.get("name", id)))
	# ★ 非后勤船**不许**带修层 —— 否则是「半生效状态」（踩过：防御型显示修护盾）
	var dirty: Array[String] = []
	for s in EveShipDatabase.all_ships():
		if bool(s.get("is_logistics", false)):
			continue
		if not StringName(s.get("logistics_layer", &"")).is_empty() \
				or float(s.get("logistics_repair", 0.0)) > 0.0:
			dirty.append(String(s.get("name", "?")))
	_expect(dirty.is_empty(),
			"★ 非后勤船不许带修层/修量（实际脏数据：%s）" % str(dirty))

	# ── ② 真修：造一艘后勤 + 一艘受损友军，推进模拟器看血有没有涨 ──
	var medic := EveShipDatabase.instantiate_by_id("bantam", 0, 7001)
	var buddy := EveShipDatabase.instantiate_by_id("condor", 0, 7002)
	var foe := EveShipDatabase.instantiate_by_id("rifter", 1, 7003)
	_expect(medic != null and buddy != null and foe != null, "建船成功")
	_expect(medic.is_logistics_unit(), "后勤舰自己报 is_logistics_unit() = true")
	_expect(not buddy.is_logistics_unit(), "攻击型报 is_logistics_unit() = false")

	# ⚠️ EveBattleSimulator **extends RefCounted**，不是 Node ⇒ 不能 add_child()。
	#    （这是一处旧断言的写法错误，之前没被跑到；改为只做 setup/step。）
	var sim := EveBattleSimulator.new()
	sim.setup([medic, buddy], [foe])
	sim.set_time_limit(45.0)
	# 把友军打成半血（护盾层），且**明确比后勤舰低** —— 这样目标选择是确定的
	buddy.hp[&"shield"] = float(buddy.max_hp[&"shield"]) * 0.2
	var buddy_before := float(buddy.hp[&"shield"])
	# 推过 2 秒（> 一个修理周期）—— 用固定步长，不用墙钟
	var steps := int(ceil(2.2 / EveBattleSimulator.FIXED_STEP))
	for _i in steps:
		sim.step(EveBattleSimulator.FIXED_STEP)
		if sim.finished:
			break
	_expect(float(buddy.hp[&"shield"]) > buddy_before,
			"★ 友军护盾真的涨了（%.1f → %.1f）"
			% [buddy_before, float(buddy.hp[&"shield"])])
	_expect(medic.repaired_total > 0.0,
			"★ 后勤舰累计修入 > 0（实际 %.1f）" % medic.repaired_total)
	# ③ ★ 边界（2026-10-01 改口径）：后勤**可以修自己**。
	#    旧断言测的是「不修自己」，而那条规则正是「有效修入恒为 0」的根因
	#    （敌方总是先打最近的单位 ⇒ 后勤站在前排 ⇒ 只有它自己掉血 ⇒
	#      队友没伤、自己又不能修 ⇒ 可修窗口实测 0/724 帧）。
	#    ⚠️ 旧断言之所以是绿的，是因为它把 **buddy 打成半血** 之后
	#      再去看 medic 没涨血 —— 半血队友排在候选第一位，
	#      自然轮不到 medic。它**从来没有真正测到"排除自己"这条规则**。
	#    新断言必须能证伪这条：**把队友全部设成满血，只有自己掉血**，
	#    此时若仍"不修自己" ⇒ 返回 null ⇒ 血量不涨 ⇒ 断言挂。
	_expect(medic.is_logistics_unit(), "后勤能开工")
	# ⚠️ 必须**先把自己打伤**再选目标 —— 否则自己也是满血，
	#    新口径同样挑不出目标（"满血不修"那条边界会先命中），
	#    断言会与"不能修自己"的旧行为无法区分。
	var self_layer: StringName = medic.logistics_layer
	medic.hp[self_layer] = float(medic.max_hp[self_layer]) * 0.25
	var self_shield_before := float(medic.hp[self_layer])
	var picked: EveShip = sim._pick_repair_target(medic, [medic] as Array)
	_expect(picked == medic,
			"★ 队友全满血时，后勤**把自己选为修理目标**（否则就是空转）")
	var self_gain := medic.repair_ally(medic)
	_expect(self_gain > 0.0 and float(medic.hp[self_layer]) > self_shield_before,
			"★ 后勤真的能修自己（+%.1f，%s %.1f → %.1f）"
			% [self_gain, String(self_layer), self_shield_before,
					float(medic.hp[self_layer])])

	# ── ④ 边界：不修结构、不超上限、不满血不修 ──
	var t1 := EveShipDatabase.instantiate_by_id("rifter", 0, 7004)
	var m1 := EveShipDatabase.instantiate_by_id("bantam", 0, 7005)
	# 护盾扣空、结构也扣一半 —— 只该涨护盾
	t1.hp[&"shield"] = 0.0
	t1.hp[&"hull"] = float(t1.max_hp[&"hull"]) * 0.5
	var hull_before := float(t1.hp[&"hull"])
	var got := m1.repair_ally(t1)
	_expect(float(t1.hp[&"shield"]) > 0.0, "修到了护盾层")
	_expect(is_equal_approx(float(t1.hp[&"hull"]), hull_before),
			"★ 不修结构（结构 %.1f 没变）—— 能修结构等于第二条命，战斗会打不完"
			% hull_before)
	_expect(got > 0.0, "repair_ally 返回实际修入量（%.1f）" % got)
	# 修到满就不该再涨
	t1.hp[&"shield"] = float(t1.max_hp[&"shield"])
	var over := m1.repair_ally(t1)
	_expect(is_equal_approx(over, 0.0),
			"★ 满血不再修（返回 %.1f，不溢出）" % over)
	# 甲抗的后勤只修装甲，对护盾无能为力
	var m2 := EveShipDatabase.instantiate_by_id("augoror", 0, 7006)
	var t2 := EveShipDatabase.instantiate_by_id("augoror", 0, 7007)
	t2.hp[&"shield"] = 0.0
	t2.hp[&"armor"] = float(t2.max_hp[&"armor"]) * 0.3
	var shield_b := float(t2.hp[&"shield"])
	var armor_b := float(t2.hp[&"armor"])
	m2.repair_ally(t2)
	_expect(is_equal_approx(float(t2.hp[&"shield"]), shield_b)
			and float(t2.hp[&"armor"]) > armor_b,
			"★ 甲抗后勤（奥格诺级）修装甲、**不碰护盾**")

	print("[后勤舰] 火力 3/10（攻击型的 ~1/4）· 8 艘修层全对 · 修友军生效 · 三条边界成立")

	_t_logi_self_repair_forward()   # ★★ E2 反向注入（2026-10-01）


## ══════════════════════════════════════════════════════════════════
##  ★★ E2 反向注入：「后勤能修自己」到底有没有用
## ══════════════════════════════════════════════════════════════════
##
## 为什么必须有这一组：
##   上面 ③ 测的是「口径对不对」（能不能修自己）。
##   这一组测的是「**这条口径是不是真的产生了差别**」——
##   它防的是「口径改了但行为没变」，也防「有人以后又把自己排除掉」。
##
## 做法 = 同一场真实战斗跑两遍，两组只差**候选集合**一件事：
##   A（现行为）= 生产代码的 `_pick_repair_target`（含自己）
##   B（旧行为）= 本函数里的**影子选择器**（排除自己），
##                选到目标后**直接调用公开的 `repair_ally()`**
## 然后比「后勤自己的护盾剩多少」—— 这是唯一能区分两组、又不依赖
## 被测代码内部记账的量。
##
## ⛔ 绝不能只断「A > 0」：B 组同样是 0 时它也会通过，
##    分不清「修好了」和「两组都坏」。必须断 **A 显著优于 B**。
##
## ⚠️ 为什么用影子选择器而不是给生产代码加开关：
##    加开关等于让验收代码反向污染实现（红线：探针禁读中间变量）。
##    影子选择器只用公开的 `hp / max_hp` 复算，实现零改动。
func _t_logi_self_repair_forward() -> void:
	# ══ 判据：**后勤自己的护盾能不能被自己补上** ══
	#
	# ⛔ 不能用"整场战斗结束时的护盾剩多少"当判据 —— 实测那一版是
	#    16.0（含自己）vs 17.3（排除自己），**反而是排除自己的更高**。
	#    原因：生产代码含自己之后，同样的修理周期还要分给队友，
	#    修自己的份额被摊薄了。这个量**测不出"能不能修自己"**。
	# ⇒ 改为**直接测那一次修理的落点**：把队友全部设成满血、
	#    只让后勤自己掉血，然后看那一个周期里"血有没有涨"。
	#    这是唯一能把「含自己」与「排除自己」分开的构型。
	var r := _logi_self_probe()
	var self_gain := float(r["self_gain"])
	var ally_gain := float(r["ally_gain"])
	_expect(self_gain > 0.0,
			"★★ 含自己 ⇒ 队友全满血时后勤仍能给自己补血（+%.1f）" % self_gain)
	_expect(ally_gain > 0.0,
			"★ 含自己**不影响**给掉血队友修（+%.1f）—— 不是二选一"
			% ally_gain)
	# ★ 反向注入：把同一段逻辑换成"排除自己"的影子选择器，
	#   必须得到 **0** —— 否则说明上面那条不是被候选集合决定的。
	var shadow := _shadow_pick_excl_self(r["medic"] as EveShip, r["own"] as Array)
	_expect(shadow == null,
			"★★ 反向注入：同一局面下「排除自己」的影子选择器挑不出目标（返回 null）")


## 构造「队友全满血、只有后勤自己掉血」这个**唯一能区分两组**的局面，
## 并各推一个修理周期，返回双方的实际修入。
func _logi_self_probe() -> Dictionary:
	var medic := EveShipDatabase.instantiate_by_id("bantam", 0, 8821)
	var a1 := EveShipDatabase.instantiate_by_id("condor", 0, 8822)
	var f1 := EveShipDatabase.instantiate_by_id("rifter", 1, 8823)
	if medic == null or a1 == null or f1 == null:
		return {"self_gain": 0.0, "ally_gain": 0.0, "medic": null, "own": []}
	var own: Array[EveShip] = [medic, a1]
	var foes: Array[EveShip] = [f1]
	var sim: RefCounted = EveBattleSimulator.new()
	sim.setup(own, foes)

	# ── 局面 A：只有后勤自己掉血，队友满血 ──
	var layer: StringName = medic.logistics_layer
	medic.hp[layer] = float(medic.max_hp[layer]) * 0.20
	a1.hp[layer] = float(a1.max_hp[layer])          # 队友满血
	var before_self := float(medic.hp[layer])
	var picked: EveShip = sim._pick_repair_target(medic, own)
	var self_gain := 0.0
	if picked != null:
		self_gain = medic.repair_ally(picked)

	# ── 局面 B：队友掉血，后勤满血（验"不是二选一"）──
	medic.hp[layer] = float(medic.max_hp[layer])
	a1.hp[layer] = float(a1.max_hp[layer]) * 0.20
	var before_ally := float(a1.hp[layer])
	var picked2: EveShip = sim._pick_repair_target(medic, own)
	var ally_gain := 0.0
	if picked2 != null:
		ally_gain = medic.repair_ally(picked2)
	# 还原成"A 局面"供反向注入用（影子选择器要在同一局面下比）
	medic.hp[layer] = before_self
	a1.hp[layer] = float(a1.max_hp[layer])
	return {"self_gain": self_gain, "ally_gain": ally_gain,
			"medic": medic, "own": own}


## 影子选择器：**排除自己**（复刻 2026-10-01 之前的旧口径）。
## 只用公开的 hp / max_hp，不碰实现内部字段。
func _shadow_pick_excl_self(medic: EveShip, arr: Array) -> EveShip:
	var layer: StringName = medic.logistics_layer
	if layer.is_empty():
		return null
	var best: EveShip = null
	var best_frac := 1.0
	for s in arr:
		if s == medic or not s.alive or s.team != medic.team:
			continue
		var cap := float(s.max_hp.get(layer, 0.0))
		if cap <= 0.0:
			continue
		var frac := clampf(float(s.hp.get(layer, 0.0)) / cap, 0.0, 1.0)
		if frac >= 0.999:
			continue
		if frac < best_frac:
			best_frac = frac
			best = s
	return best


## ★★ C5 探针：跑一场**真战斗**，把「谁进了打捞池」这件事量出来。
##
## ⚠️ 为什么不能用 `_battle`（主验收那个场景）：它身上挂着完整的状态机推进，
##    再让它打第二场会把 `_stage` 序列搞乱。这里**独立实例化**一份，
##    并且用 `queue_free()` 收尾。
##
## ⚠️ 取证姿势必须是「读**产出**」而不是「读实现中间变量」：
##    ① 两边各数一遍真实阵亡数（读 `_own_ships` / `_enemy_ships` 的 `alive`）；
##    ② 读 `run.wreck` 的**实际产出**（谁被挑中了）；
##    ③ 反向注入：把「只收敌方」的影子池算一遍，证明它与实际产出的**挑选范围**不同。
##    ⛔ 不重算 `_on_battle_finished` 内部逻辑，也不碰 `destroyed` 数组本身
##      （那是实现细节，读它等于自己证明自己）。
##
## ⚠️ 本函数是**协程**（要 `await` 场景 `_ready`）⇒ 调用点必须 `await`。
func _logi_probe_salvage_scope() -> Dictionary:
	var packed: PackedScene = load(SCENE_PATH)
	if packed == null:
		return {"ok": false}
	var b: Variant = packed.instantiate()
	if b == null:
		return {"ok": false}
	add_child(b)
	# ⚠️⚠️ `EveBattleScene._ready()` 里有 `await get_tree().process_frame` ——
	#    `add_child()` 只同步执行到**第一个 await**，此刻 `run` / `hud` 都还是 null。
	#    不等这两帧，后面 `b.get("run")` 拿到 null，整段探针量到「0 艘」（踩过）。
	await get_tree().process_frame
	await get_tree().process_frame
	var st_probe = b.get("run")
	if st_probe == null:
		b.queue_free()
		return {"ok": false}
	# 把货架换成 5 款互不相同的 **1 费**船：便宜（买得起）、脆（保证有阵亡）。
	_force_offers_distinct(st_probe)
	for i in 5:
		st_probe.buy(i % 5)
	# 全部推上前线 —— 数量堆上去，对上节点 1 的敌人必有一场硬仗
	var deployed := 0
	for i in st_probe.bench.size():
		if bool(st_probe.deploy_from_bench(0, 4 + i, 4).get("ok", false)):
			deployed += 1
	# ⚠️⚠️ 这一段要的是「**我方也有阵亡**」——只顾着堆数量会打成碾压胜
	#    （实测：上 2 艘 1 费 vs 节点 1 的 2 艘，我方 0 损）。
	#    所以**只留 1 艘在前线**（其余撤回备战席）：1 打 2 必输，我方必有人阵亡，
	#    而敌方也会换掉/不换 —— 两边池子都能非空，反向注入才有意义。
	while st_probe.field.size() > 1:
		if not bool(st_probe.recall_to_bench(st_probe.field.size() - 1).get("ok", false)):
			break
	deployed = st_probe.field.size()
	# ⚠️⚠️ 必须**显式开战**：`_own_ships` 是在 `start_battle()` 里才建出来的
	#    （买入只进备战席、部署只写 `run.field`）。漏了这一步 ⇒ `_own_ships`
	#    恒为空 ⇒ 整段探针量到「0 艘」（踩过两次）。
	b.call("start_battle")
	# 让它把这一场打起来（与 `_step_battle_done` 同一姿势：一次快进 90 秒）
	b.call("debug_fast_forward_battle", 90.0)

	var sim = b.get("sim")
	var run_state = b.get("run")
	var own: Array = b.get("_own_ships")
	var enemy: Array = b.get("_enemy_ships")

	# ── ① 两边各数一遍真实阵亡 ──
	var own_dead := 0
	var enemy_dead := 0
	for s in own:
		if not s.alive:
			own_dead += 1
	for s in enemy:
		if not s.alive:
			enemy_dead += 1

	# ── ② 实际产出：`run.wrecks` 挑了谁（列表里**最贵**的那艘 = 第一项）──
	var picked_key := ""
	var picked_name := ""
	if run_state != null and not run_state.wrecks.is_empty():
		picked_key = String((run_state.wrecks[0] as Dictionary).get("ship_key", ""))
		picked_name = String((run_state.wrecks[0] as Dictionary).get("name", "?"))

	# ── ③ 合池 vs 纯敌方池：各自「费用最高」的那艘 ──
	#    ⛔ 这里只用来做**反向注入判据**（证明加了我方之后挑选范围变了），
	#      不是重算实现。两边都只用 `cost` 这一列公开数据。
	var all_dead: Array = []
	for s in own:
		if not s.alive:
			all_dead.append(s)
	for s in enemy:
		if not s.alive:
			all_dead.append(s)
	var best_key := _best_cost_key(all_dead)
	var enemy_only_key := _best_cost_key(
			all_dead.filter(func(s): return s.team != 0))

	# ── ④ ★ 关键判据：结算页里的 `destroyed` 计数（**公开产出**，不是中间变量）──
	#
	#    ⚠️ 这里曾经写成 `"own_in_destroyed": own_dead` —— 那是**自证**：
	#       直接把「真实阵亡数」抄进判据，无论收集侧漏没漏都会通过。
	#       反向注入实测只挂 1 条（而且是第④条产出），前三条全绿 ⇒ 判据是假的。
	#    现在改成读 `_result_payload["destroyed"]` —— 它是 `_build_result_payload()`
	#    写进结算页的**面向上层的数**（`_on_battle_finished` 里 destroyed.size()）。
	#    ⇒ 收集侧漏收我方 ⇒ 这个数就少 ⇒ 断言必挂。**判据与实现不再同源。**
	var payload: Dictionary = b.get("_result_payload")
	var destroyed_count := int(payload.get("destroyed", -1))

	var r := {
		"ok": sim != null and run_state != null and not payload.is_empty(),
		"own_dead": own_dead,
		"enemy_dead": enemy_dead,
		# ★ 真判据：结算页的计数应当 = 双方阵亡之和
		"own_in_destroyed": destroyed_count - enemy_dead,
		"enemy_in_destroyed": destroyed_count - own_dead,
		"destroyed_count": destroyed_count,
		"pool_size": all_dead.size(),
		"enemy_pool_alone": enemy_dead,
		"picked_key": picked_key,
		"picked_name": picked_name,
		"best_key": best_key,
		"enemy_only_best_key": enemy_only_key,
	}
	b.queue_free()
	return r


## 给定一批阵亡船，返回**费用最高**那艘的 ship_key（并列取先出现的）。
## ⚠️ 只用公开的 `ship_key` / `cost`，不读实现字段。
func _best_cost_key(arr: Array) -> String:
	var bk := ""
	var bc := -1
	for s in arr:
		var row: Dictionary = EveShipDatabase.by_id(String(s.ship_key))
		var c: int = int(row.get("cost", 1))
		if c > bc:
			bc = c
			bk = String(s.ship_key)
	return bk


## ══════════════════════════════════════════════════════════════════
##  ★ C4 残骸星级反解 + 「打捞框数字残留」的**反向注入**验收
## ══════════════════════════════════════════════════════════════════
##
## 这一组回答两个此前**没人验过**的问题：
##
##   ① 残骸的星级从哪来？
##      旧实现读 `EveShip.star`，而敌方舰队把星级烘进数值、从不写这个字段
##      ⇒ 恒为 1。断言必须能**证伪**这条（否则「1★」既可能对也可能是 bug）。
##
##   ② 打捞框的数字会不会残留？
##      「框里显示上一具残骸的数」是纯观感问题，没有断言就永远测不出来。
##      做法 = **反向注入**：造两具**数值不同**的残骸，中途换掉，
##      要求 `salvage_info()` 跟着变。若它不变，说明存在缓存/短路。
func _t_salvage_tier() -> void:
	# ── ① 幂等性：同一份证据算两次必须同解（判据禁含浮点 epsilon）──
	var a1 := EveRunState.derive_wreck_tier(80.0, 1.0, 80.0, 490.0)
	var a2 := EveRunState.derive_wreck_tier(80.0, 1.0, 80.0, 490.0)
	_expect(a1 == a2, "同一份证据两次反解同解（幂等）")

	# ── ② scale ≤ 1：能反解出真星级。构造「2★ 的读数」必定出 2 ──
	#    ⚠️ 基准 = atk_base 本身（`warhead_scale` 只乘 1.8^Δ，不乘别的系数）。
	var base_atk := 80.0
	var shot2 := base_atk * pow(EveRunState.STAR_MULT, 1.0)
	var t2 := EveRunState.derive_wreck_tier(shot2, 1.0, base_atk, 490.0)
	_expect(int(t2["star"]) == 2,
			"shot=%.1f（base 80 × 1.8）→ 反解 2★（实际 %d★）"
			% [shot2, int(t2["star"])])
	var t3 := EveRunState.derive_wreck_tier(
			base_atk * pow(EveRunState.STAR_MULT, 2.0), 1.0, base_atk, 490.0)
	_expect(int(t3["star"]) == 3, "3★ 读数 → 反解 3★（实际 %d★）" % int(t3["star"]))
	# 裸值（未强化）→ 1★。★ 这条是**防回归**的：基准多乘一个系数就会把它读成 2★
	var t1 := EveRunState.derive_wreck_tier(base_atk, 1.0, base_atk, 490.0)
	_expect(int(t1["star"]) == 1,
			"★ 裸读数（shot = base = %.0f）→ 1★（实际 %d★）" % [base_atk, int(t1["star"])])

	# ── ③ scale > 1：**故意不出高星**（逐节点星级没实装，星永远出 1）──
	#    这一条是**防回归**的：有人日后"顺手按 scale 往上猜"就会打破它。
	var tb := EveRunState.derive_wreck_tier(base_atk * 1.8, 1.8, base_atk, 490.0)
	_expect(int(tb["star"]) == 1,
			"★ 被放大过的敌掠袭舰队（scale 1.8）残骸判 1★，不按 scale 猜（实际 %d★）"
			% int(tb["star"]))

	# ── ④ 展示态：`tier_base_from` 把星折回裸值 ──
	var tb2 := EveRunState.tier_base_from(2, 80.0, 490.0)
	_expect(int(roundf(float(tb2["atk"]))) == 144,
			"2★ 打击 = 80 × 1.8 = 144（实际 %d）" % int(roundf(float(tb2["atk"]))))

	# ── ⑤ ★ 反向注入：换一具残骸 → salvage_info 的数**必须**跟着变 ──
	#    这是「数字残留」唯一的客观判据。
	var st := _new_run(91)
	var cheap := EveShipDatabase.by_id("condor")     # 1 费，attack 13
	var dear := EveShipDatabase.by_id("moa")         # 3 费，attack 35
	_expect(not cheap.is_empty() and not dear.is_empty(), "取证用船在表里")

	# ⚠️ 2026-10-04 多选后，`salvage_info()` 的 state 是 **"list"**，
	#    展示读数在 `items[0]` 里（不再有顶层 `atk`）。下面用一个取值口
	#    统一取，**判据形状变了、判据本身没变**。
	var first_atk := func(info: Dictionary) -> int:
		if String(info.get("state", "")) == "list":
			var its: Array = info.get("items", [])
			return int((its[0] as Dictionary).get("atk", -1)) if its.size() > 0 else -1
		return int(info.get("atk", -1))
	var first_base_exact := func(info: Dictionary) -> bool:
		if String(info.get("state", "")) == "list":
			var its2: Array = info.get("items", [])
			return bool((its2[0] as Dictionary).get("base_exact", false)) \
					if its2.size() > 0 else false
		return bool(info.get("base_exact", false))
	var first_star := func(info: Dictionary) -> int:
		if String(info.get("state", "")) == "list":
			var its3: Array = info.get("items", [])
			return int((its3[0] as Dictionary).get("star", 0)) if its3.size() > 0 else 0
		return int(info.get("star", 0))

	st.resolve_battle(0, [cheap.duplicate(true)],
			[{"star": 1, "atk_base": 13.0, "def_base": 90.0, "shot": 13.0, "m": 1.0}], 1.0)
	var i1 := st.salvage_info()
	_expect(first_atk.call(i1) == 13,
			"残骸① 打击读数 = 13（实际 %s）" % str(first_atk.call(i1)))
	var evt1 := int(i1.get("evt", -1))

	# 同一节点内再打一场、打掉一艘**不同**的敌舰 → 换代
	st.resolve_battle(0, [dear.duplicate(true)],
			[{"star": 1, "atk_base": 35.0, "def_base": 230.0, "shot": 35.0, "m": 1.0}], 1.0)
	var i2 := st.salvage_info()
	_expect(first_atk.call(i2) == 35,
			"★ 残骸换代后打击读数必须变成 35，不是沿用 13（实际 %s）"
			% str(first_atk.call(i2)))
	_expect(int(i2.get("evt", -1)) != evt1,
			"★ 世代号必须递增（%d → %d）—— UI 靠它判「要不要重画」"
			% [evt1, int(i2.get("evt", -1))])
	_expect(first_base_exact.call(i2), "未放大（scale 1.0）⇒ base_exact = true")

	# ── ⑥ 放大过的节点：base_exact 必须为 false（HUD 据此换措辞）──
	var st2 := _new_run(92)
	st2.resolve_battle(0, [dear.duplicate(true)],
			[{"star": 1, "atk_base": 35.0, "def_base": 230.0,
			  "shot": 35.0 * 1.8, "m": 1.8, "team": 1}], 1.8)
	var i3 := st2.salvage_info()
	_expect(not first_base_exact.call(i3),
			"★ scale 1.8 的节点 ⇒ base_exact = false（框上不许假装是原版裸值）")
	_expect(first_star.call(i3) == 1, "同上：星级不按 scale 猜，仍是 1★")

	# ── ⑦ 下单后世代号随修复品走、残骸展示态必须清空 ──
	# ⚠️ 打捞改成在**结算页**下单（阶段口径 2026-10-04 反转），别再用 PREP。
	st2.set_phase(EveRunState.Phase.RESOLVE)
	st2.coin = 50
	var o := st2.salvage_order([0])
	_expect(bool(o.get("ok", false)), "放大节点也能正常下单")
	_expect(st2.wrecks_display.is_empty(),
			"★ 下单后 wrecks_display 必须清空 —— 否则下一具残骸的展示读的是旧的")
	_expect(st2.salvage_info().get("state", "") == "repairing", "打捞框转 repairing")
	_expect(int(st2.salvage_info().get("evt", 0)) == int(i3.get("evt", 0)),
			"修复品继承下单那具的世代号")

	print("[残骸分级] 1★/2★/3★ 反解 · 放大节点判 1★ · 换代读数 13 → 35")

	# ── ⑧ ★★ 反向注入：证明世代号**真的在当判据用** ──
	#    做法：把世代号人为压回旧值，断言「UI 会认为没变、于是不重画」。
	#    若 UI 侧改成「一律重画」这件事仍然成立（不会误判），
	#    但反过来 —— 若 UI 侧改成「state 没变就 return」（旧 bug），
	#    那么下面这条 assert 会**抓到它**。这就是这组断言的牙齿。
	#
	#    ⚠️ 这里验的是 `EveRunState` 侧的输出契约（世代号必须单调），
	#       UI 侧的重画由 `_step_salvage_*` 的场景步覆盖。
	var st3 := _new_run(93)
	st3.resolve_battle(0, [cheap.duplicate(true)],
			[{"star": 1, "atk_base": 13.0, "def_base": 90.0, "shot": 13.0, "m": 1.0}], 1.0)
	var e_a := int(st3.salvage_info().get("evt", -1))
	st3.resolve_battle(0, [cheap.duplicate(true)],
			[{"star": 1, "atk_base": 13.0, "def_base": 90.0, "shot": 13.0, "m": 1.0}], 1.0)
	var e_b := int(st3.salvage_info().get("evt", -1))
	_expect(e_b > e_a,
			"★ 同型残骸连来两次，世代号仍必须递增（%d → %d）——"
			% [e_a, e_b]
			+ "否则「换了一具但 state 没变」时 UI 不重画，旧数就留在框上")
	_expect(st3.wreck_evt == e_b,
			"对外报的世代号与内部计数器一致（%d vs %d）" % [st3.wreck_evt, e_b])

	st.queue_free()
	st2.queue_free()
	st3.queue_free()


# ── 阶段 B 的小工具 ──────────────────────────────────────────────

## 把商店 5 格全部换成同一款船 —— 让「连买同名」在测试里可复现
func _force_offers(st: EveRunState, key: StringName) -> void:
	var d := EveShipDatabase.by_id(String(key))
	var arr: Array = []
	for i in EveRunState.SHOP_SLOTS:
		arr.append(d.duplicate(true))
	st.offers = arr


## 把商店 5 格换成 5 款【互不相同】的 1 费船。
##
## ⚠️ 为什么测试需要它：真实货架是随机的，偶尔会开出 3 张同名 →
##    触发三连合成 → 「备战席剩几艘」这类断言就变成掷骰子
##    （旧版本的 verify_run 就埋着这个雷，只是没踩到）。
func _force_offers_distinct(st: EveRunState, n: int = 5) -> void:
	var pool := EveShipDatabase.by_cost(1)
	var arr: Array = []
	for i in n:
		arr.append(pool[i % pool.size()].duplicate(true))
	st.offers = arr


## 把商店 5 格换成「当前编制里一艘都没有」的某款 1 费船，返回它的 key。
##
## 用途：想验「买进来的船去了哪里」时，必须保证它**不可能**凑成三连，
## 否则它会跟场上/备战席的同类合并，位置断言随即失去意义。
func _force_offers_fresh(st: EveRunState) -> StringName:
	var have := {}
	for e in st.all_owned():
		have[StringName(e.get("ship_key", &""))] = true
	for d in EveShipDatabase.by_cost(1):
		var k := StringName(d.get("ship_key", &""))
		if not have.has(k):
			_force_offers(st, k)
			return k
	return &""


## 确定性地连买 n 张同一款（每买一张就重填一次货架，因为买走会立刻重摇）
func _buy_same(st: EveRunState, key: StringName, n: int) -> void:
	for i in n:
		_force_offers(st, key)
		st.buy(0)


## 某款船在当前编制里的所有星级（升序）—— 用于断言合成结果
func _stars_of(st: EveRunState, key: StringName) -> Array:
	var out: Array = []
	for e in st.all_owned():
		if StringName(e.get("ship_key", &"")) == key:
			out.append(int(e.get("star", 1)))
	out.sort()
	return out


# ══════════════════════════════════════════════════════════════════
#  第二段：场景联动
# ══════════════════════════════════════════════════════════════════

func _run() -> EveRunState:
	return _battle.get("run")


func _step_start() -> void:
	var st := _run()
	print("[节点 1 准备] %s" % st.summary())
	_expect(st.node_index == 1, "开局在节点 1")
	_expect(st.phase == EveRunState.Phase.PREP, "开局处于准备阶段")
	_expect(st.coin == 5, "开局星币 5（实际 %d）" % st.coin)
	_expect(st.offers.size() == 5, "商店 5 张卡（实际 %d）" % st.offers.size())
	_expect(st.field.is_empty() and st.bench.is_empty(), "开局一艘船都没有")

	var bar = _battle.get("hud").get("command_bar")
	_expect(int(bar.get("beacon")) == 100, "顶条信标读数为 100")
	_expect(int(bar.get("node_index")) == 1, "顶条节点号为 1")
	_expect(int(bar.get("phase")) == 0, "顶条阶段名 = 准备")

	# 敌人已经站在场上了（准备阶段只是站着不动）
	_node1_enemy_comp = st.enemy_comp_id()
	_node1_loss = st.loss_preview()
	var foes: Array = _battle.get("_enemy_ships")
	_expect(foes.size() == 2, "节点 1 敌方 2 艘已就位（实际 %d）" % foes.size())
	if foes.size() > 0:
		_node1_enemy_shield = float(foes[0].max_hp[&"shield"])
		_node1_enemy_attack = float(foes[0].weapon_damage)
	print("      节点 1 战败代价 = %d（顶条应显示同一个数）" % _node1_loss)

	# ── 阶段 C 收尾：节点进场字幕 ────────────────────────────────
	# ⚠️ 无头下它是**看不见的**（没有显示器），所以不能靠截图验 ——
	#    验的是「横幅真的被唤起 / 文案与节点表逐字一致 / 字号真的放大」。
	#    这三条断掉时都不报错，症状分别是：字幕根本不弹、
	#    弹了但写错节点、以及「强化展示」根本没放大（退回成一行小字）。
	#
	# ⚠️ 全程**同步**调用（不 await 帧）：横幅自己挂在 `_process` 上推进寿命，
	#    中间一旦让出帧，下面这几条读数就成了跟真实时间赛跑。
	var hud = _battle.get("hud")
	var banner = hud.get("entry_banner")
	_expect(banner != null, "HUD 里挂了进场字幕层")
	if banner != null:
		_expect(int(banner.call("active_count")) == 1,
				"节点 1 进准备阶段时弹了进场字幕")
		_expect(String(banner.call("current_node_text"))
				== "节点 01 / %d" % EveNodeTable.TOTAL,
				"字幕节点号 = 节点 01 / %d（实际 %s）"
				% [EveNodeTable.TOTAL, banner.call("current_node_text")])
		_expect(String(banner.call("current_type_text")) == st.stage_label(),
				"字幕类型标签与节点表一致（实际 %s）" % banner.call("current_type_text"))
		_expect(String(banner.call("current_text")) == st.entry_line(),
				"字幕正文逐字等于本节点进场词")
		# 「放大」是这条交付的核心 —— 量字号，不靠肉眼判断
		var fs := int(banner.call("line_font_size"))
		_expect(fs >= 20, "进场词字号已放大（实际 %d px；战斗日志窗里那行只有 9px）" % fs)
		print("[进场字幕] %s · %s · %s（%d px）"
				% [banner.call("current_node_text"), banner.call("current_type_text"),
				banner.call("current_text"), fs])
		# 寿命：推过整条寿命后必须自己收掉。不收的话它会永远挂在屏幕上 ——
		# 而且下一节点的字幕会被上一节点的盖住（观感是「字幕不更新」）。
		var life := float(banner.call("life_seconds"))
		banner.call("tick", life + 0.1)
		_expect(int(banner.call("active_count")) == 0,
				"字幕到寿命会自己收（LIFE=%.1fs）" % life)
		_entry_banner_life = life
		# 收掉之后按真实路径再唤起一次：留给 `_step_start_battle` 验「开战即收」
		hud.call("show_entry", st.node_index, st.node_type(), st.entry_line())
		_expect(int(banner.call("active_count")) == 1, "收掉之后可以再次唤起字幕")


func _step_buy() -> void:
	var st := _run()
	# ⚠️ 先把货架换成 5 款互不相同的 1 费船。
	#    不这么做的话，随机货架偶尔会开出 3 张同名 → 触发三连合成 →
	#    「备战席几艘」这条断言就变成掷骰子（旧版本埋着这个雷）。
	_force_offers_distinct(st)
	for i in 5:
		st.buy(i % 5)
	print("[买完 5 张] %s · 备战席 %d 艘 · 上场 %d 艘"
			% [st.summary(), st.bench_used(), st.field.size()])
	_expect(st.coin == 0, "买 5 张 1 费后星币归零（实际 %d）" % st.coin)
	# ⚠️ 2026-09-20 云顶口径：买入【只进备战席】，绝不自动上场。
	#    这是「棋盘 / 备战席」两个操作面存在的理由，见 eve_run_state.buy()。
	_expect(st.field.is_empty(), "买入不自动上场（实际场上 %d 艘）" % st.field.size())
	_expect(st.bench.size() == 5, "5 张全进备战席（实际 %d 艘）" % st.bench.size())

	var hud = _battle.get("hud")
	var shop = hud.get("shop")
	if shop == null:
		shop = hud.get("shop_window")
	_expect(int(shop.get("bench_used")) == 5, "商店标题栏备战席读数 5／8")

	# 备战席的立绘应该已经有 5 格
	#
	# ⚠️ 2026-09-23：原先断言的是 arena.bench_stage（3D 备战层）的子节点数。
	#    备战席改画 2D 立绘后，那条路径整个不存在了（bench_stage 恒为 null，
	#    直接 get_child_count() 会崩）—— 换成断言 HUD 侧格带收到的名单。
	var bench_rail = hud.get("bench_rail")
	_expect(_rail_fleet_count(bench_rail) == 5,
			"备战席格带收到 5 格名单（实际 %d）" % _rail_fleet_count(bench_rail))


## 读 EveBenchRail 上的名单长度（-1 = 控件缺失 / 字段类型不对）
##
## ⚠️ 之所以包一层而不是内联 `rail.get("fleet").size()`：
##    返回的是 Variant，直接点方法在无头下会因「类型无法推断」报 Parse Error，
##    而且这里要区分「控件为 null」与「名单为空」两种情况。
func _rail_fleet_count(rail) -> int:
	if rail == null:
		return -1
	var f = rail.get("fleet")
	if f is Array:
		return (f as Array).size()
	return -1


## 备战席 → 棋盘（玩家手动拖 3 艘上场）。
##
## ⚠️ 这一段是【新流程的核心验证】：买完之后场上仍然是空的，
##    必须由玩家自己把船拖上去 —— 否则棋盘永远不会显形、备战席永远不用看。
func _step_deploy_first() -> void:
	var st := _run()
	var cells := [Vector2i(8, 3), Vector2i(8, 4), Vector2i(8, 6)]
	for c in cells:
		var r := st.deploy_from_bench(0, c.x, c.y)
		_expect(bool(r.get("ok", false)),
				"备战席 → 棋盘 (%d,%d)（%s）"
				% [c.x + 1, c.y + 1, String(r.get("reason", ""))])
	print("[拖上场 3 艘] %s · 备战席 %d 艘" % [st.summary(), st.bench.size()])
	_expect(st.field.size() == 3 and st.bench.size() == 2,
			"上场 3（Lv1 上限）· 备战席 2（实际 %d / %d）"
			% [st.field.size(), st.bench.size()])
	# 场上满了之后再拖会被拒 —— 上场上限是硬的
	var r4 := st.deploy_from_bench(0, 7, 1)
	_expect(not bool(r4.get("ok", true)),
			"Lv1 上限 3 已满 → 第 4 艘被拒（原因：%s）" % String(r4.get("reason", "")))


func _step_economy() -> void:
	var st := _run()
	st.coin = 34
	st.refresh()
	print("[刷新 / 加速等级] %s" % st.summary())
	_expect(st.coin == 32, "刷新扣 2（34 → %d）" % st.coin)
	st.levelup()
	st.levelup()
	_expect(st.level == 3, "连投两次加速等级 → Lv3（实际 Lv%d）" % st.level)
	_expect(st.coin == 24, "两次加速共扣 8（34 → %d）" % st.coin)
	# ⚠️ 升级【不】自动补人（2026-09-20 删除 auto_deploy）——
	#    上限从 3 抬到 5 只是「多了两个位置」，上不上人由玩家拖。
	_expect(st.field.size() == 3 and st.bench.size() == 2,
			"升级不自动补人 —— 场上仍是拖上去的 3 艘（实际 %d 上 / %d 备）"
			% [st.field.size(), st.bench.size()])
	# 上限既然到了 5，玩家就能自己再拖一艘上去
	var r := st.deploy_from_bench(0, 7, 5)
	_expect(bool(r.get("ok", false)),
			"上限 5 时再拖 1 艘上场（%s）" % String(r.get("reason", "")))
	_expect(st.field.size() == 4 and st.bench.size() == 1,
			"手动拖放后 4 艘上场 / 1 艘待命（实际 %d / %d）"
			% [st.field.size(), st.bench.size()])


func _step_levelup() -> void:
	var st := _run()
	# ⚠️ 这一步会重建舰队，所以必须发生在「开战」之前：
	#    准备阶段重建 = 正常；战斗中重建 = 会把正在打的船换掉。
	var foes: Array = _battle.get("_enemy_ships")
	_expect(foes.size() == 2, "开战前敌方仍是 2 艘")
	print("[开战前] %s" % st.summary())


func _step_start_battle() -> void:
	var st := _run()
	var arena = _battle.get("arena")
	var cam = arena.get("orion_cam")

	# ── 阶段 D①：开战镜头（推近 + 环绕）────────────────────────────
	# ⚠️ 在按下开战**之前**记下三个相机的量，之后逐条对账。
	#    这一条要捕获的是「begin_battle_shot 被删掉/写错」这种静默事故 ——
	#    没有它，开战与不开战在玩家眼里一模一样（镜头不动），但什么错都不报。
	var zoom_before := float(cam.get_zoom())
	var yaw_before := float(cam.get_yaw())
	_cam_yaw_before = yaw_before

	# ── 阶段 C 收尾：开战即收字幕 ────────────────────────────────
	# ⚠️ 这里**故意先重新唤起一次**再开战，而不是指望「步骤 1 唤起的那次刚好还活着」——
	#    靠时间差的话这条会随帧率/步骤耗时变成偶发假红。
	#    对应的真实场景就是「玩家在 4.2 秒内点了开战」：他不想再读那行字了。
	var hud_before = _battle.get("hud")
	hud_before.call("show_entry", st.node_index, st.node_type(), st.entry_line())
	var banner_before = hud_before.get("entry_banner")
	_expect(int(banner_before.call("active_count")) == 1, "开战前字幕在显示")

	_battle.call("start_battle")
	_expect(int(banner_before.call("active_count")) == 0,
			"点开战 → 字幕立刻收掉（不等它自己淡完）")
	print("[开战] phase=%d" % st.phase)
	_expect(st.phase == EveRunState.Phase.BATTLE, "点开战 → 进入战斗阶段")
	var bar = _battle.get("hud").get("command_bar")
	_expect(int(bar.get("phase")) == 1, "顶条阶段名 = 交战")
	_expect(is_equal_approx(float(bar.get("time_total")), st.battle_seconds()),
			"顶条倒计时切到战斗时限 %.0fs（实际 %.0f）"
			% [st.battle_seconds(), float(bar.get("time_total"))])
	var sim = _battle.get("sim")
	_expect(sim != null and not sim.finished, "战斗已经开始推进")

	# D①-a：视距**必须**变「近」。queue_zoom 是瞬时的（见 EveOrbitCamera.queue_zoom），
	#       所以这里能立刻断言，不用等收敛。
	#
	# ⚠️ 方向别搞反（这里踩过一次）：`EveOrbitCamera` 里
	#      distance = max_range · DISTANCE_SCALE / max(0.55, zoom)
	#    —— **zoom 越大，相机离得越近**。所以「推近」= zoom 数值**变大**。
	var zoom_after := float(cam.get_zoom())
	var ratio := zoom_after / maxf(0.001, zoom_before)
	_expect(zoom_after > zoom_before,
			"开战镜头推近：zoom %.3f → %.3f（%+.1f%% · zoom 越大离得越近）"
			% [zoom_before, zoom_after, (ratio - 1.0) * 100.0])
	# ⚠️ 硬写 1.55 是**故意**的：写死才能让「常量被顺手改掉」这件事亮红。
	_expect(absf(ratio - 1.55) < 0.02,
			"推近倍率 = BATTLE_VIEW_ZOOM 1.55（实际 ×%.3f）" % ratio)

	# D①-b：目标偏航角切到开战位（set_yaw_target 是收敛的，所以这一刻只验 target）
	var target_after: float = float(cam.get("_target_yaw"))
	_expect(is_equal_approx(target_after, ARENA_SCRIPT.BATTLE_VIEW_YAW),
			"开战镜头的目标方位 = BATTLE_VIEW_YAW %.2f（实际 %.2f）"
			% [ARENA_SCRIPT.BATTLE_VIEW_YAW, target_after])
	# ⚠️ 开战方位必须**不同于**默认方位 —— 否则「转镜头」这件事等于没发生：
	#    玩家在准备阶段随手复位过相机，开战再转到同一个角度，观感上毫无变化。
	_expect(not is_equal_approx(ARENA_SCRIPT.BATTLE_VIEW_YAW, ORBIT_CAM_SCRIPT.DEFAULT_YAW),
			"开战方位 ≠ 默认方位 %.2f（否则转了等于没转）"
			% ORBIT_CAM_SCRIPT.DEFAULT_YAW)
	_expect(not is_equal_approx(zoom_before, 0.0),
			"开战前的视距不是 0（zoom_before=%.3f，防止断言在退化输入上空转）"
			% zoom_before)
	print("      相机：zoom %.3f → %.3f（×%.2f）· yaw %.2f → 目标 %.2f"
			% [zoom_before, zoom_after, ratio, yaw_before, target_after])

	# ── 阶段 D④：阶段环境音 + BGM 切换 ───────────────────────────
	# ⚠️ 无头没有音频设备，**声音不会真的响**。所以这里验的是三件事：
	#    ① 三类音源都真的装载了（资产没落进 res://assets/audio 时会静默为空）；
	#    ② 阶段切换真的发了声音（amb 计数 +1）；
	#    ③ BGM 切到战斗段。
	#    这三条任何一条断了，实机表现都是「全程静音」且**无任何报错**。
	var audio = _battle.get("audio")
	_expect(audio != null, "场景里挂了音频层 EveAudio")
	if audio == null:
		return
	var s: Dictionary = audio.call("stats")
	_expect(bool(s.get("has_sfx", false)), "打击音库已装载（sfx）")
	_expect(bool(s.get("has_amb", false)), "环境音库已装载（ambience）")
	_expect(bool(s.get("has_music", false)), "音乐库已装载（music）")
	# ⚠️ 2026-10-10：战斗 BGM 名从旧的 "battle" 换成 V0.13 的战场段
	#    `border` / `border_final`（见 `eve_battle_scene._round_music()`，
	#    按 `run.node_index` 选段）⇒ 断言跟着改（改语义同步改断言）。
	#    这里只判「属于战斗段曲目」（`border*`），⛔ 不写死具体哪一首 ——
	#    曲目随 node_index 变，写死会把"正常换段"误判成失败。
	_expect(str(s.get("music_current", "")).begins_with("border"),
			"开战 → BGM 切到战斗段（实际 %s）" % str(s.get("music_current", "")))
	# ★ 2026-10-01 起音效有总开关（默认关）。断言跟着开关翻 ——
	#    ⚠️ 不能只写成"关掉就没声音"：那与"音频线断了"完全同构。
	#       双向测试在下面 `_t_d_*` 收尾处做。
	if _sfx_on(s):
		_expect(int(s.get("amb", 0)) > 0, "开战发了阶段环境音（amb=%d）" % int(s.get("amb", 0)))
	else:
		_expect(int(s.get("amb", 0)) == 0,
				"★ 音效总开关关闭 ⇒ 开战一声不发（amb=%d）" % int(s.get("amb", 0)))
	_expect(int(s.get("missing", 0)) == 0,
			"到目前为止没有「音源缺失被静默跳过」（missing=%d）" % int(s.get("missing", 0)))
	_audio_at_battle_start = s.duplicate()
	print("[音频] 开战时 sfx=%s amb=%s music=%s · amb 计数=%d · BGM=%s"
			% [s.get("has_sfx"), s.get("has_amb"), s.get("has_music"),
			int(s.get("amb", 0)), s.get("music_current")])

	# ══════════════════════════════════════════════════════════════
	#  ★★ 火力渐增（时限 60%）触发时**绝不能归零顶条倒计时**
	# ══════════════════════════════════════════════════════════════
	#  2026-10-04 修的真 bug：原来 `_process` 的 BATTLE 分支在
	#  `damage_multiplier() > 1.0` 时调 `set_stage(..., 0.0)` ——
	#  而火力渐增在时限的 60% 就开始（45s→27s 剩 18s；55s→33s 剩 22s），
	#  用户实机原话：「明明战斗还剩20多秒，结果一下就归零了」。
	#  修法：触发时只发日志。这条断言钉死它 —— 有牙齿的反向验证：
	#  把 `set_stage(..., 0.0)` 注回去，本条必红。
	var sim2 = _battle.get("sim")
	var bar2 = _battle.get("hud").get("command_bar")
	var t_before: float = float(bar2.get("time_left"))
	var limit: float = st.battle_seconds()
	# 直接把模拟时间推到火力渐增区（60% 之后一点），不真等 30 秒
	sim2.set("elapsed", limit * 0.65)
	_battle.call("_check_sudden_death")
	_expect(bool(_battle.get("_sd_announced")),
			"★ 火力渐增已触发（elapsed=%.0f > 60%%×%.0f）" % [limit * 0.65, limit])
	_expect(is_equal_approx(float(bar2.get("time_left")), t_before),
			"★★ 火力渐增触发后顶条倒计时**纹丝不动**（%.1f → %.1f）"
			% [t_before, float(bar2.get("time_left"))])
	_expect(float(bar2.get("time_left")) > 1.0,
			"★★ 倒计时仍剩 %.1f 秒（不是 0）——「还剩 20 多秒归零」钉死在这里"
			% float(bar2.get("time_left")))
	# 还原现场：后续步骤（_step_d_hit 等）要在「正常战斗」状态下跑
	sim2.set("elapsed", 0.0)
	_battle.set("_sd_announced", false)
	print("[倒计时] 火力渐增触发 · 顶条未被归零 · 现场已还原")


## ── 阶段 D②③：命中反馈 + 伤害数字 ────────────────────────────────
##
## ⚠️ 这一段的存在理由只有一个：**捕获静默断线**。
##    `sim.shot_fired` 那一行 connect 一旦丢掉（或 `_on_shot_fired` 里
##    `arena.fx_tracer` / `hud.pop_damage` 被注释掉），战斗在玩家眼里就是
##    「几艘船在飘、偶尔少一艘」—— **不报错、不崩溃、断言全绿**。
##    所以这里不看画面，直接数两个计数器（它们就是为这件事写的）。
func _step_d_hit() -> void:
	var st := _run()
	var arena = _battle.get("arena")
	var hud = _battle.get("hud")
	var cam = arena.get("orion_cam")

	# 先确认步进前是干净的（不然「有特效」可能是上一场残留）
	var fx0 := int(arena.get("battle_fx").call("active_count"))
	var feed0 := int(hud.get("damage_feed").call("active_count"))
	_expect(fx0 == 0, "开火前世界空间特效为 0（实际 %d）" % fx0)
	_expect(feed0 == 0, "开火前伤害飘字为 0（实际 %d）" % feed0)

	# ⚠️ 快进时长必须**够长**，否则这段断言会变成「在验锁定时间」而不是「在验反馈接线」。
	#
	#    锁定时长 = EveCombatCore.lock_duration(scan_res, signature)
	#             = 40000 / (scan · asinh(sig)²)
	#    护卫舰量级（scan 400 / sig 40）算出来约 **5.2 秒**；再加上接敌机动，
	#    3 秒时全场一艘都没锁定上 —— 那时 fx 计数当然是 0（实测踩过）。
	#    这里取 12 秒：足够走完「接敌 → 锁定 → 至少两轮开火」。
	const D_HIT_SECONDS := 12.0
	_battle.call("debug_fast_forward_battle", D_HIT_SECONDS)
	# ⚠️ 特效是有寿命的（曳光 0.16s / 爆点 0.28s），而 debug_fast_forward_battle
	#    在一次调用里把 360 个 tick 全跑完 —— 期间 spawn 出来的节点**没有被
	#    _process 回收的机会**（回收要等下一帧），所以读数必然 > 0。
	#    反过来说：这个计数器的语义是「这段时间里确实发生过开火」，
	#    而不是「此刻画面上有几条曳光」。
	var fx1 := int(arena.get("battle_fx").call("active_count"))
	var feed1 := int(hud.get("damage_feed").call("active_count"))
	# ★ 2026-10-01 起攻击特效有总开关（默认关，用户要求"闪屏竖线先关掉"）
	var bfx = arena.get("battle_fx")
	if bool(bfx.get("fx_enabled")):
		_expect(fx1 > 0, "%d 秒战斗产生了世界空间特效（曳光/爆点）—— 实际 %d 条"
				% [int(D_HIT_SECONDS), fx1])
	else:
		_expect(fx1 == 0, "★ 特效总开关关闭 ⇒ 不生成立体特效（实际 %d 条）" % fx1)
	# ★ 双向：打开开关必须真的出特效 —— 否则"关掉"这件事和"线断了"分不开
	bfx.set("fx_enabled", true)
	bfx.call("spawn_hit", Vector3.ZERO, 3)
	var fx_on := int(bfx.call("active_count"))
	bfx.call("clear")
	bfx.set("fx_enabled", false)
	bfx.call("spawn_hit", Vector3.ZERO, 3)
	var fx_off := int(bfx.call("active_count"))
	bfx.call("clear")
	_expect(fx_on > 0, "★ 打开特效开关 ⇒ spawn_hit 真的出特效（%d 条）" % fx_on)
	_expect(fx_off == 0, "★ 关掉特效开关 ⇒ spawn_hit 出 0 条（%d）" % fx_off)
	_expect(feed1 > 0, "%d 秒战斗产生了伤害飘字 —— 实际 %d 条"
			% [int(D_HIT_SECONDS), feed1])
	# 上限是硬的（见 EveBattleFx.MAX_FX / EveDamageFeed.MAX_POPUPS）——
	# 超过就会堆到无上限，无头验收会明显变慢、实机掉帧。
	_expect(fx1 <= 200, "特效数受上限约束（实际 %d，上限 140 附近）" % fx1)
	_expect(feed1 <= 60, "飘字数受上限约束（实际 %d，上限 48）" % feed1)

	# ── 阶段 D④：打击音 ──────────────────────────────────────────
	# ⚠️ 只断言「计数 > 0」是不够的 —— 那会被「音源缺失静默跳过」骗过去。
	#    所以这里同时看两条：① 真的播了；② 节流真的在吞；③ missing == 0。
	var audio = _battle.get("audio")
	if audio != null:
		var sa: Dictionary = audio.call("stats")
		if _sfx_on(sa):
			_expect(int(sa.get("fire", 0)) > 0,
					"战斗里真的播了开火音（fire=%d）" % int(sa.get("fire", 0)))
			_expect(int(sa.get("hit", 0)) > 0,
					"战斗里真的播了命中音（hit=%d）" % int(sa.get("hit", 0)))
			_expect(int(sa.get("fire_throttled", 0)) > 0,
					"开火节流真的在吞（被吞 %d 次 —— 不节流会变成噪音墙）"
					% int(sa.get("fire_throttled", 0)))
		else:
			_expect(int(sa.get("fire", 0)) == 0 and int(sa.get("hit", 0)) == 0
					and int(sa.get("boom", 0)) == 0,
					"★ 音效总开关关闭 ⇒ 整场战斗一声不发（fire/hit/boom = %d/%d/%d）"
					% [int(sa.get("fire", 0)), int(sa.get("hit", 0)), int(sa.get("boom", 0))])
		# ⚠️ 这条是「音源真的找得到」的唯一守卫：
		#    逻辑名写错 / ogg 没拷进 res://assets/audio 时，
		#    play_* 会**静默返回**，计数不涨但也不报错。
		_expect(int(sa.get("missing", 0)) == 0,
				"打击音没有静默缺源（missing=%d）" % int(sa.get("missing", 0)))
		print("[音频] 战斗 %ds：开火 %d（吞 %d）· 命中 %d（吞 %d）· 爆炸 %d"
				% [int(D_HIT_SECONDS), int(sa.get("fire", 0)),
				int(sa.get("fire_throttled", 0)), int(sa.get("hit", 0)),
				int(sa.get("hit_throttled", 0)), int(sa.get("boom", 0))])

	# D①-c：偏航**真的动了**（这才是「环绕」到位的判据）。
	#
	# ⚠️ 起点必须用 `_step_start_battle` 里**开战之前**取的那个值，
	#    不能在这一步开头取 —— stage 7 与 stage 8 之间隔了 30 帧，
	#    `set_yaw_target` 的收敛在 0.25 秒内就跑完了，那时读到的已经是终点值，
	#    于是这条断言会退化成「0.343 → 0.343」而永远失败（实测踩过）。
	var yaw_now := float(cam.get("yaw"))
	_expect(absf(yaw_now - _cam_yaw_before) > 0.05,
			"开战镜头真的转了方位（%.3f → %.3f，转了 %.3f 弧度）"
			% [_cam_yaw_before, yaw_now, absf(yaw_now - _cam_yaw_before)])
	# 并且已经收敛到目标（收敛在 0.25 秒内完成，12 秒后必然到位）
	var target_yaw := float(cam.get("_target_yaw"))
	_expect(absf(yaw_now - target_yaw) < 0.05,
			"偏航已收敛到开战目标（yaw %.3f / target %.3f，差 %.4f）"
			% [yaw_now, target_yaw, absf(yaw_now - target_yaw)])
	# 收敛后应当停在开战方位、且**不是**默认方位 —— 否则转了等于没转
	_expect(not is_equal_approx(yaw_now, ORBIT_CAM_SCRIPT.DEFAULT_YAW),
			"收敛后的方位 ≠ 默认方位 %.2f（实际 %.3f）"
			% [ORBIT_CAM_SCRIPT.DEFAULT_YAW, yaw_now])

	var sim = _battle.get("sim")
	_expect(not sim.finished, "%d 秒不足以打完节点 1（仍在交战 · 已用 %.1fs）"
			% [int(D_HIT_SECONDS), float(sim.elapsed)])
	print("[打击反馈] 特效 %d 条 · 飘字 %d 条 · 相机 zoom %.3f / yaw %.3f（起始 %.3f）"
			% [fx1, feed1, float(cam.get_zoom()), yaw_now, _cam_yaw_before])


## ── 开火线的**几何**验收（2026-10-01 用户要求「线两端连着开火方与被打击方」）──
##
## ⚠️ 为什么不能只数 `active_count()`：那个数只证明「有节点被建出来」，
##    证明不了它**摆在哪**。旧版把线做成 billboard 之后，节点数一样 >0，
##    但在屏幕上是一条竖线、根本不指向目标 —— 这正是用户说「看着很别扭」的东西。
##
## 这里的判据是**纯几何**、不引用任何实现中间变量：
##   ① 线的中心点 ≈ 开火方与被击方的中点（偏差 < 线长的一半）；
##   ② 线的长轴方向 ∥ 弹道方向（dot 的绝对值 → 1）；
##   ③ 材质不是 billboard（`billboard_mode == DISABLED`）—— 这条是钉旧病的。
##
## ⛔ 不许读 `_fx` 里的 `kind`/寿命之类内部状态当判据 —— 那必然自洽。
##    这里直接量 MeshInstance3D 的世界变换（红线：探针只读引擎产出）。
func _check_tracer_geometry() -> void:
	var arena = _battle.get("arena")
	var bfx = arena.get("battle_fx")
	if bfx == null:
		_expect(false, "竞技场里挂着特效层 EveBattleFx")
		return
	# 现场造一条：起点、终点都取成**好算的整数**，避免依赖场上船的残骸位置。
	var from_m := Vector3(0.0, 0.0, 30_000.0)
	var to_m := Vector3(0.0, 0.0, 0.0)
	bfx.set("fx_enabled", true)
	bfx.call("clear")
	bfx.call("spawn_tracer", from_m, to_m, true, 3)
	var node: Node3D = null
	for c in bfx.get_children():
		if c is MeshInstance3D:
			node = c
			break
	_expect(node != null, "一次开火 ⇒ 建出一条线（MeshInstance3D）")
	if node == null:
		return
	var mi := node as MeshInstance3D
	var q := mi.mesh as QuadMesh
	_expect(q != null, "线用的是 QuadMesh")
	var mat := mi.material_override as StandardMaterial3D
	_expect(mat != null, "线挂着 StandardMaterial3D")
	if mat != null:
		# ③ 钉旧病：billboard 会让线在屏幕上转成竖直
		_expect(mat.billboard_mode == BaseMaterial3D.BILLBOARD_DISABLED,
				"★ 开火线**不是** billboard（旧版闪屏竖线的病根）")
		_expect(mat.cull_mode == BaseMaterial3D.CULL_DISABLED,
				"★ 两面都渲染（否则从一侧看线会凭空消失）")
	var half := q.size.y * 0.5 if q != null else 0.0
	if half <= 0.0:
		_expect(false, "线长为 0 —— 建出来也看不见")
		return
	# ① 中心 ≈ 弹道中段的中点
	var expected_mid := from_m.lerp(to_m, half / maxf(0.001, (to_m - from_m).length()))
	var actual_mid := mi.global_transform.origin * float(BfxScript.METERS_PER_UNIT)
	var err := actual_mid.distance_to(expected_mid)
	_expect(err < half * BfxScript.METERS_PER_UNIT,
			"★ 线的中心落在弹道上（偏差 %.0f m < 半长 %.0f m）"
			% [err, half * BfxScript.METERS_PER_UNIT])
	# ② 长轴 ∥ 弹道（局部 +Y 是长度方向，转到世界后比对）
	var world_long := (mi.global_transform.basis * Vector3.UP).normalized()
	var ballistic := (to_m - from_m).normalized()
	var align := absf(world_long.dot(ballistic))
	_expect(align > 0.999,
			"★ 线的长轴平行于弹道（|dot| = %.4f，1.0 = 完全对齐）" % align)
	# ③ 颜色是「统一的亮黄」—— 用户明确要求黄色，不许按档位换色
	if mat != null:
		var c := mat.albedo_color
		_expect(c.r > 0.9 and c.g > 0.6 and c.b < 0.5,
				"★ 开火线是黄色（实测 rgb %.2f/%.2f/%.2f）" % [c.r, c.g, c.b])
	# ④ 长度必须**长短不一**：同一档位连发 8 条，长度不该一模一样
	#
	# ⚠️ 坑：`clear()` 用的是 `queue_free()`（**延迟**释放），所以老节点在
	#    本帧仍然是子节点 —— 「取第一个 MeshInstance3D」会 8 次都拿到同一个
	#    待删的旧节点（实测就是这样，8 个读数一模一样）。
	#    ⇒ 取**最后一个**子节点（刚建的那条）。
	var lens: Array[float] = []
	for i in 8:
		bfx.call("spawn_tracer", from_m, to_m, true, 3)
		var kids: Array = bfx.get_children()
		if kids.is_empty():
			continue
		var newest: Node = kids[kids.size() - 1]
		if newest is MeshInstance3D:
			lens.append(float((newest as MeshInstance3D).mesh.size.y))
	_expect(lens.size() >= 8, "连发 8 条都建出来了（实际 %d 条）" % lens.size())
	var lmin := 99.0
	var lmax := 0.0
	for l in lens:
		lmin = minf(lmin, l)
		lmax = maxf(lmax, l)
	_expect(lmax - lmin > 0.01,
			"★ 同档位连发 8 条，长度长短不一（%.3f ~ %.3f）—— 齐射才像弹幕" % [lmin, lmax])
	print("[开火线几何] 半长 %.2f 世界单位 · 中心偏差 %.0f m · 长轴对齐 %.4f · 长度 %.3f~%.3f · 色 rgb(%.2f,%.2f,%.2f)"
			% [half, err, align, lmin, lmax,
			mat.albedo_color.r if mat != null else 0.0,
			mat.albedo_color.g if mat != null else 0.0,
			mat.albedo_color.b if mat != null else 0.0])
	# ⚠️ 复位：这一段在特效层上做了破坏性操作（clear + 造假线），
	#    验完必须把开关与残留都恢复原状，否则后续步骤会看到脏数据。
	bfx.call("clear")
	bfx.set("fx_enabled", true)


## ── 反向注入：结算弹窗的延迟**真的接在时间轴上**吗 ─────────────────
##
## ⚠️ 上面那三条断言证明的是「打完时没弹、数据备好了」。但它们**证明不了**
##    根因是延迟 —— 如果弹窗整个坏了（`show_result` 断线），
##    它们会一模一样地全绿。这正是本工程反复栽过的「自检把 bug 当期望值」。
##
## 这条用**两个相反的极端**把因果钉死：
##   · 延迟 = 0（旧行为）⇒ `_on_battle_finished` 之后结算页**立刻**在台上；
##   · 延迟 = 1（新行为）⇒ 同一时刻结算页**不在**台上。
## 两个结果不同 ⇒ 「延迟」这个变量确实控制着弹窗出现时机。
##
## ⚠️ 在**独立的新场景实例**上跑，不碰当前这局的 `run` / `sim` 状态 ——
##    在这里改活着的那个实例会污染后面的 `_step_d_result`。
func _check_delay_controls_popup() -> void:
	var ps: PackedScene = load(SCENE_PATH)
	if ps == null:
		_expect(false, "能加载 battle_scene 用于反向注入")
		return
	var outcomes: Array = []
	for delay in [0.0, 1.0]:
		var s: Variant = ps.instantiate()
		add_child(s)
		# ⚠️ `_ready` 里有 `await get_tree().process_frame`，必须等它跑完
		#    才能拿到 `run` / `hud`（不等的话 get("run") 是 null）。
		await get_tree().process_frame
		await get_tree().process_frame
		var h = s.get("hud")
		var r = s.get("run")
		if h == null or r == null:
			_expect(false, "反向注入用的场景实例就绪（hud/run 非空）")
			s.queue_free()
			continue
		# 直接把字段设成待弹出态，再按 delay 决定走哪条路 ——
		# 这样绕开「真的打一场」，专注验时间轴本身。
		var own: Array = s.get("_own_ships")
		# 造一个「我方还有船活着」的局面（= 胜利，走延迟那条路）
		var m: EveShip = EveShipDatabase.instantiate_by_id("punisher", 0, 9001)
		own.append(m)
		s.set("_result_popup_timer", 0.0)
		s.set("_pending_result", {"probe": true})
		if delay > 0.0:
			# 新行为：写进延迟计时器，模拟「刚打完」
			s.set("_result_popup_timer", delay)
		else:
			# 旧行为：没有延迟 ⇒ 立刻消费
			s.call("_popup_result")
		outcomes.append(bool(h.call("result_is_open")))
		s.queue_free()
		await get_tree().process_frame
	_expect(outcomes.size() == 2, "两次极端都跑完了")
	if outcomes.size() != 2:
		return
	_expect(outcomes[0] == true,
			"★ 反向注入：延迟=0 ⇒ 打完**立刻**弹（旧行为复现）")
	_expect(outcomes[1] == false,
			"★ 反向注入：延迟=1 ⇒ 同一时刻**不弹**（新行为生效）")
	_expect(outcomes[0] != outcomes[1],
			"★★ 两条时间轴结果不同 ⇒ 「延迟」确实控制着弹窗出现时机"
					+ "（若两个都为 false，说明弹窗整个断了，上面三条断言是假绿）")
	print("[反向注入] 结算弹窗时机：延迟 0 → 台上=%s · 延迟 1 → 台上=%s"
			% [str(outcomes[0]), str(outcomes[1])])


func _step_battle_done() -> void:
	var st := _run()
	# 一次性快进 90 秒 —— 节点 1 时限 45 秒，必定收尾
	_battle.call("debug_fast_forward_battle", 90.0)
	var sim = _battle.get("sim")
	_expect(sim.finished, "快进后战斗已结束（用时 %.1fs）" % float(sim.elapsed))
	_expect(st.phase == EveRunState.Phase.RESOLVE, "进入结算阶段")

	# ══════════════════════════════════════════════════════════════════
	#  ★ 结算弹窗的 1 秒延迟（2026-10-01 用户要求）
	# ══════════════════════════════════════════════════════════════════
	#  用户原话：「每回合的结算弹窗需要在舰船被击毁后的一秒后弹出」。
	#
	#  ⚠️ 这一段是本轮的**主验收**，三条都要有牙齿：
	#    ① 打完的那一刻弹窗**还没弹**（否则「延迟」这个功能等于没做）；
	#    ② 这一秒里结算数据**已经算好存着**（否则到点弹出来的是空页）；
	#    ③ 到点之后弹出来，且数据与状态机同源。
	#
	#  ⚠️ 快进是在**一帧内**跑完 90 秒的，`_process` 那一秒根本走不到 ⇒
	#     这里用 `debug_flush_result_popup()` 显式催一下。这不是「绕过」，
	#     它走的正是 `_process` 到点那条路径（同一个 `_popup_result()`）。
	var hud0 = _battle.get("hud")
	var popup_timer0 := float(_battle.get("_result_popup_timer"))
	var pending0: Dictionary = _battle.get("_pending_result")
	# 只有「我方还有船活着」（= 赢了，场上爆的是敌舰）才该看满这一个延迟；
	# 我方全灭 / 未部署时没有爆炸可看，代码里会立刻弹（见 _on_battle_finished）。
	var own_alive := 0
	for s in _battle.get("_own_ships"):
		if s.alive:
			own_alive += 1
	if own_alive > 0:
		_expect(not bool(hud0.call("result_is_open")),
				"★ 打完那一刻结算页**还没弹**（延迟 %.1fs，先让击毁爆炸播完）"
				% BATTLE_SCRIPT.RESULT_POPUP_DELAY)
		_expect(popup_timer0 > 0.0,
				"★ 延迟倒计时正在走（%.2fs / %.2fs）"
				% [popup_timer0, BATTLE_SCRIPT.RESULT_POPUP_DELAY])
		_expect(not pending0.is_empty(),
				"★ 这一秒里结算数据**已经算好存着**（延迟弹的不是空页）")
		print("[结算延迟] 打完时 timer=%.2fs · 数据已备 %s · 结算页未弹"
				% [popup_timer0, str(not pending0.is_empty())])
	else:
		_expect(bool(hud0.call("result_is_open")),
				"我方全灭/未部署 ⇒ 没有爆炸可看，结算页**立刻弹**（不干等一秒）")
	# ⚠️ 这一秒里特效必须还在跑：最后那一下开火线/爆炸正是延迟的**目的**。
	_expect(float(BATTLE_SCRIPT.RESULT_POPUP_DELAY) >= 1.0,
			"★ 延迟 ≥ 1.0s（实际 %.2fs）—— 击毁爆炸寿命 0.75s，短了它就播不完"
			% BATTLE_SCRIPT.RESULT_POPUP_DELAY)
	# ★ 开火线是**实体几何**，不是屏幕空间的东西：
	#   验证「两端连着开火方与被打击方」这件事只能看世界坐标 ——
	#   取一个真实的开火，量它的中点到两船的偏差。
	_check_tracer_geometry()

	# ★★ 反向注入：证明「这一秒」真的在控制弹窗（而不是弹窗整个坏了）。
	#    ⛔ 只读常量本身不算数 —— 那只能证明「常量是 1.0」，
	#       证明不了它接在弹窗的时间轴上。必须真的走一遍两条时间轴。
	_check_delay_controls_popup()

	# 到点：走与 `_process` 完全相同的出口
	_battle.call("debug_flush_result_popup")
	_expect(bool(hud0.call("result_is_open")), "延迟到点 ⇒ 结算页上台")
	_expect(float(_battle.get("_result_popup_timer")) <= 0.0,
			"弹出后延迟计时器已归位（实际 %.2f）"
			% float(_battle.get("_result_popup_timer")))
	_expect(_battle.get("_pending_result").is_empty(),
			"弹出后待办数据已消费（不留残渣 —— 否则下一回合会弹出一张旧页）")

	# 期望的信标 = 100 −（阶段战败定值 + 连败递增）
	# ⛔ 2026-10-01：这里原来还要 +Σ「漏网舰船费用」，那个概念已删除。
	var base := int(EveRunState.LOSS_BASE.get(st.node_type(), 8))
	var leaked := 0
	for s in _battle.get("_enemy_ships"):
		if s.alive:
			leaked += 1
	var expect_dmg := base + st.loss_streak_bonus()
	print("[战斗结束] 胜方队=%d · 敌方存活 %d 艘（**不参与扣血**） · 定值 %d + 连败 %d = −%d · 信标 %d"
			% [int(sim.get("winner_team")), leaked, base,
			st.loss_streak_bonus() - (0 if st.lose_streak <= 1 else 0), expect_dmg, st.beacon])
	if leaked > 0:
		# ★★ 2026-10-01 **反向钉住**。
		#    旧断言写的是「全歼 → 只扣阶段基础伤害 base」——
		#    那正是玩家报的病：「为啥我打赢了信标还是会掉血啊？这不是有病吗，
		#    守卫成功了信标还掉血，那我不是白守卫了？」
		#    自检把 bug 当成了期望值，所以它一直是绿的。
		#    现在把方向反过来：全歼必须**一滴不掉**。
		#    （谁再把「无条件 beacon -= 基础伤害」加回去，这条立刻挂。）
		_expect(st.beacon == 100,
				"★ 全歼 → 信标一滴不掉（实际剩 %d；旧行为会白掉 %d）" % [st.beacon, base])

	# 每完成一个节点自动 +2 经验
	_expect(st.xp >= EveRunState.NODE_XP_REWARD,
			"节点结算后自动发 %d 点经验（当前累计 %d）"
			% [EveRunState.NODE_XP_REWARD, st.xp])
	# 顶条的信标读数必须与状态机一致
	var bar = _battle.get("hud").get("command_bar")
	_expect(int(bar.get("beacon")) == st.beacon,
			"顶条信标读数与状态机一致（%d / %d）" % [int(bar.get("beacon")), st.beacon])

	# ── 阶段 D④：结算音 + 击毁爆炸音 ─────────────────────────────
	var audio = _battle.get("audio")
	if audio != null:
		var sb: Dictionary = audio.call("stats")
		if _sfx_on(sb):
			_expect(int(sb.get("amb", 0)) > int(_audio_at_battle_start.get("amb", 0)),
					"战斗结束发了结算音（amb %d → %d）"
					% [int(_audio_at_battle_start.get("amb", 0)), int(sb.get("amb", 0))])
		_expect(int(sb.get("missing", 0)) == 0,
				"整场战斗没有静默缺源（missing=%d）" % int(sb.get("missing", 0)))
		# 击毁音只在真有船被打爆时才该响 —— 不硬断言 >0（节点 1 可能被全歼也可能没有），
		# 但「有击毁却没响」是断线，必须抓。
		var destroyed := 0
		for s in _battle.get("_enemy_ships"):
			if not s.alive:
				destroyed += 1
		if destroyed > 0 and _sfx_on(sb):
			_expect(int(sb.get("boom", 0)) > 0,
					"击毁 %d 艘 → 播了爆炸音（boom=%d）"
					% [destroyed, int(sb.get("boom", 0))])
		# ★★ 双向：打开必须真的响、关掉必须真的一声不响。
		#     放在这一段的最末尾做 —— 因为 `reset_stats()` 会把计数清零，
		#     放前面会影响上面那些「计数 > N」的断言。
		var keep := bool(audio.get("sfx_enabled"))
		audio.set("sfx_enabled", true)
		audio.call("reset_stats")
		audio.call("play_phase", 0)
		var on_cnt := int((audio.call("stats") as Dictionary).get("amb", 0))
		audio.set("sfx_enabled", false)
		audio.call("reset_stats")
		audio.call("play_phase", 0)
		var off_cnt := int((audio.call("stats") as Dictionary).get("amb", 0))
		audio.call("reset_stats")
		audio.set("sfx_enabled", keep)
		_expect(on_cnt > 0, "★ 打开音效开关 ⇒ play_phase 真的响（amb=%d）" % on_cnt)
		_expect(off_cnt == 0, "★ 关掉音效开关 ⇒ play_phase 一声不响（amb=%d）" % off_cnt)

		print("[音频] 收尾：爆炸 %d 声 · 环境音 %d 次 · BGM=%s"
				% [int(sb.get("boom", 0)), int(sb.get("amb", 0)),
				str(sb.get("music_current", ""))])

	# ── 舰船亮度：船壳提亮真的接上了 ───────────────────────────────
	# ⚠️ 这一组防的是两件**都不报错**的事：
	#    ① 提亮参数被改回恒等（1.0）⇒ 亮星云前的船又变回「一团没有细节的剪影」，
	#       只有把它和截图对照才看得出，跑测试完全无感；
	#    ② uniform 名字写错 / 没接到材质 ⇒ 参数设了没人读，同样静默。
	#    所以断言不能只看常量，必须**回读材质实例上的真实参数值**。
	var lifted := EveShipMaterial.cache_size()
	_expect(lifted > 0,
			"场上有舰船走了船壳着色器（材质实例 %d 个；=0 说明提亮路径整个没生效）"
			% lifted)
	var lift_min := 99.0
	var lift_bad := 0
	for k in EveShipMaterial._cache.keys():
		var sm = EveShipMaterial._cache[k]
		if not (sm is ShaderMaterial):
			continue
		var lv := float((sm as ShaderMaterial).get_shader_parameter("albedo_lift"))
		lift_min = minf(lift_min, lv)
		if not is_equal_approx(lv, EveShipMaterial.ALBEDO_LIFT):
			lift_bad += 1
	_expect(lift_bad == 0 and lift_min >= 1.5,
			"船壳提亮已接上（最小 lift=%.2f · 与常量一致 %d/%d）"
			% [lift_min, lifted - lift_bad, lifted])

	# ── 阶段 D①：结算时开战镜头收回 ────────────────────────────────
	# ⚠️ 不收回的后果：结算页浮在一个贴脸特写上，而且下一轮布阵会带着
	#    交战时那个斜视角进场 —— 而布阵是要正对棋盘的。
	var arena = _battle.get("arena")
	var cam = arena.get("orion_cam")
	_expect(is_equal_approx(float(cam.get_zoom()), ORBIT_CAM_SCRIPT.DEFAULT_ZOOM),
			"结算后视距已复位（zoom %.3f → 默认 %.3f）"
			% [float(cam.get_zoom()), ORBIT_CAM_SCRIPT.DEFAULT_ZOOM])
	_expect(is_equal_approx(float(cam.get("_target_yaw")), ORBIT_CAM_SCRIPT.DEFAULT_YAW),
			"结算后偏航目标已复位到 DEFAULT_YAW %.2f（实际 %.2f）"
			% [ORBIT_CAM_SCRIPT.DEFAULT_YAW, float(cam.get("_target_yaw"))])

	# ── 阶段 D⑤：结算页上台 ────────────────────────────────────────
	# ⚠️ 这一页取代了 RESOLVE_SECONDS 的定时自动推进。它必须**停在这里**
	#    等玩家点，不能自己翻页 —— 否则「这场打成什么样」没被传达。
	var hud = _battle.get("hud")
	_expect(bool(hud.call("result_is_open")), "战斗结束 → 结算页上台（不等定时器）")
	# 结算页的数据必须与「状态机的数字」同源（不是场景侧另算一份）
	var rw = hud.get("result_window")
	var rdata: Dictionary = rw.call("result_data")
	_expect(not rdata.is_empty(), "结算页拿到了数据")
	if not rdata.is_empty():
		_expect(int(rdata.get("beacon", -1)) == st.beacon,
				"结算页信标读数 = 状态机（页 %d / 机 %d）"
				% [int(rdata.get("beacon", -1)), st.beacon])
		_expect(int(rdata.get("beacon_before", -1)) - int(rdata.get("beacon", 0))
				== int(rdata.get("damage", -999)),
				"结算页「掉血量」= 变化前后之差（%d → %d = −%d）"
				% [int(rdata.get("beacon_before", 0)), int(rdata.get("beacon", 0)),
				int(rdata.get("damage", 0))])
		_expect(int(rdata.get("node", -1)) == st.node_index,
				"结算页节点号 = 状态机（页 %d / 机 %d）"
				% [int(rdata.get("node", -1)), st.node_index])
		_expect(bool(rdata.get("won", false)) == (int(sim.get("winner_team")) == 0),
				"结算页胜负 = 战斗结果的胜方（won=%s / winner_team=%d）"
				% [str(rdata.get("won", false)), int(sim.get("winner_team"))])
		print("[结算页] %s · 信标 %d（−%d） · 击毁 %d"
				% ["拦截成功" if bool(rdata.get("won", false)) else "拦截失败",
				int(rdata.get("beacon", 0)), int(rdata.get("damage", 0)),
				int(rdata.get("destroyed", 0))])
	# 结算页停着的时候，倒计时不该继续跑（它是「等玩家」，不是「读秒」）
	_expect(is_zero_approx(float(bar.get("time_total")))
			or int(bar.get("phase")) == 2,
			"结算期间顶条已切到结算态（阶段=%d · 时限=%.0f）"
			% [int(bar.get("phase")), float(bar.get("time_total"))])


## ── 阶段 D⑤：结算页的两个出口 ────────────────────────────────────
##
## ⚠️ 走的是**按钮自身的 pressed 信号**（`emit_signal("pressed")`），
##    不是直接调场景的 `_on_result_next`。
##    这两者在「信号没接线」时的表现完全不同：直调会通过，
##    而玩家点按钮什么都不会发生 —— 这正是本工程踩过的坑
##    （event_option_chosen 那一次就是靠走控件通道才捕获到）。
func _step_d_result() -> void:
	var st := _run()
	var hud = _battle.get("hud")
	var rw = hud.get("result_window")
	var node0 := st.node_index

	# ── ★ 反向注入：UI 里不许再有「漏网 / 被突破」────────────────────
	#    2026-10-01 整套机制删除。玩家看到这些词会问「我全活为什么还漏网」，
	#    而这个问题**没有答案** —— 它是内部算法泄漏到 UI 上造成的。
	var leak_ui := ""
	for n in rw.find_children("*", "Label", true, false):
		var t := String((n as Label).text)
		if t.contains("漏网") or t.contains("被突破") or t.contains("全漏"):
			leak_ui = t
	_expect(leak_ui.is_empty(),
			"★ 结算页没有「漏网 / 被突破 / 全漏」字样（读到「%s」）" % leak_ui)
	var cb = _battle.get("hud").get("command_bar")
	var ll = cb.get("_loss_label") if cb != null else null
	_expect(ll != null and not String(ll.text).contains("漏"),
			"★ 顶条写的是「战败 −N」而不是「若全漏 −N」（实际「%s」）"
			% ("" if ll == null else String(ll.text)))

	# ── 结算原因 ───────────────────────────────────────────────────
	# 四条分支里有两条在真实对局里很难稳定复现（`未部署` 要等准备倒计时走完、
	# `我方全灭` 要正好被打光）⇒ 直接测纯函数，这也正是它被抽出来的理由。
	# ⛔ 第二个参数现在只表示「敌方还剩几艘」，**不再参与扣血**。
	print("\n[结算原因] 四条分支（纯函数：三个事实进、一个字符串出）")
	_expect(BATTLE_SCRIPT.battle_end_reason(true, 0, 0) == "未部署",
			"场上一艘没上 ⇒ 未部署（实测 %s）" % BATTLE_SCRIPT.battle_end_reason(true, 0, 0))
	_expect(BATTLE_SCRIPT.battle_end_reason(false, 0, 3) == "敌方全灭",
			"敌舰全死 ⇒ 敌方全灭（实测 %s）" % BATTLE_SCRIPT.battle_end_reason(false, 0, 3))
	# ⚠️ 下面这条是**顺序守卫**：同归于尽时「敌方存活」也是 0，属"全歼"，
	#    判成「我方全灭」会让玩家以为"打输了"，其实是打平/全灭。
	_expect(BATTLE_SCRIPT.battle_end_reason(false, 0, 0) == "敌方全灭",
			"★ 双方同归于尽（敌方存活=0）也算全歼，**不许**说成「我方全灭」（实测 %s）"
			% BATTLE_SCRIPT.battle_end_reason(false, 0, 0))
	_expect(BATTLE_SCRIPT.battle_end_reason(false, 2, 0) == "我方全灭",
			"★ 剩下敌舰 + 我方 0 存活 ⇒ 我方全灭（实测 %s）"
			% BATTLE_SCRIPT.battle_end_reason(false, 2, 0))
	_expect(BATTLE_SCRIPT.battle_end_reason(false, 2, 1) == "僵持收场",
			"★ 双方都有存活 ⇒ 只可能是僵持收场（实测 %s）"
			% BATTLE_SCRIPT.battle_end_reason(false, 2, 1))

	# 结算页真的把它印出来了（纯函数对 ≠ 印对了）
	var sub: Label = rw.get("_subtitle")
	var sub_text := "" if sub == null else sub.text
	var hit := ""
	for r in PackedStringArray(["敌方全灭", "我方全灭", "僵持收场", "未部署"]):
		if sub_text.contains(r):
			hit = r
	_expect(not hit.is_empty(),
			"★ 结算页副标题写着结束原因（读到「%s」；原文「%s」）" % [hit, sub_text])

	# ── ★★ 超时判定必须与**帧率**无关（2026-10-01 修的真 bug）──────────
	#
	# 旧实现：`elif tick >= max_ticks`。而 `tick` 在 `_advance_one_tick` 里
	# **按帧累加**（`tick += 1`），`elapsed` 才是**按秒累加**（`elapsed += dt`）。
	# 两者只在 30fps 时相等 —— 60fps 下 tick 跑到 1350 只用了约 **22 秒**，
	# 而顶条按 `elapsed` 显示还剩 23 秒 ⇒ 玩家看到「还剩 20 多秒却判我超时」。
	#
	# ⇒ 判定改成 `elapsed >= time_limit_seconds()`。下面这条断言就是钉它的：
	#    同一场战斗分别用 1/30 与 1/60 推进，结束时的 elapsed 必须几乎相同。
	#    （谁把 `tick >= max_ticks` 写回来，这条立刻挂。）
	var sim_scr2: GDScript = load("res://scripts/core/eve_battle_simulator.gd")
	var ends: Array = []
	for dt2 in [1.0 / 30.0, 1.0 / 60.0]:
		var s2: Variant = sim_scr2.new()
		var m2: EveShip = EveShipDatabase.instantiate_by_id("punisher", 0, 7101)
		var f2: EveShip = EveShipDatabase.instantiate_by_id("slasher", 1, 7102)
		m2.armor_scale(200.0)                   # 双方都极厚 ⇒ 一定跑到火力渐增收尾
		f2.armor_scale(200.0)
		var owp2: Array[EveShip] = [m2]
		var fop2: Array[EveShip] = [f2]
		s2.setup(owp2, fop2)
		s2.set_time_limit(10.0)                 # 下限就是 10s
		var g2 := 0
		while not bool(s2.finished) and g2 < 60000:
			s2.step(dt2)
			g2 += 1
		ends.append(float(s2.elapsed))
	_expect(absf(ends[0] - ends[1]) < 3.0,
			"★ 超时判定与帧率无关：1/30 → %.1fs · 1/60 → %.1fs（差 %.1fs）"
			% [ends[0], ends[1], absf(ends[0] - ends[1])])

	# ── ★ 规则：超时**不再判负**（打到一方全灭为止）────────────────────
	# 用户：「自走棋就该在时限内战斗，直到被击毁」「这个因素必须排除」。
	# 收敛由火力渐增保证：时限后伤害继续涨（5 → 20 倍）。
	var s3: Variant = sim_scr2.new()
	var m3: EveShip = EveShipDatabase.instantiate_by_id("punisher", 0, 7201)
	var f3: EveShip = EveShipDatabase.instantiate_by_id("slasher", 1, 7202)
	m3.armor_scale(200.0)
	f3.armor_scale(200.0)
	var owp3: Array[EveShip] = [m3]
	var fop3: Array[EveShip] = [f3]
	s3.setup(owp3, fop3)
	s3.set_time_limit(10.0)
	var g3 := 0
	while float(s3.elapsed) < 12.0 and not bool(s3.finished) and g3 < 60000:
		s3.step(1.0 / 30.0)
		g3 += 1
	_expect(float(s3.elapsed) > 10.0 and not bool(s3.finished),
			"★ 过了时限战斗**仍在进行**（不判负）· 已用时 %.1fs"
			% float(s3.elapsed))
	_expect(float(s3.damage_multiplier()) > 5.0,
			"★ 火力渐增在时限后继续放大（实测 ×%.2f）" % float(s3.damage_multiplier()))

	_expect(bool(hud.call("result_is_open")), "点按钮前结算页仍在台上")
	var next_btn: Button = rw.get("_next_btn")
	var end_btn: Button = rw.get("_end_btn")
	_expect(next_btn != null and end_btn != null, "两个按钮都已建出来")
	if next_btn == null:
		return
	_expect(next_btn.text.contains("下一节点"),
			"非结局时主按钮是「继续 · 下一节点」（实际「%s」）" % next_btn.text)
	_expect(end_btn.visible, "非结局时「结束本局」可见")

	# ⚠️ 2026-10-04：点「继续」前若**还有残骸**，会先弹二次确认
	#    （用户要的「本回合不决定 → 永久作废」护栏）。
	#    这一步要验的是「继续 ⇒ 推进 + 清特效」，所以先把残骸清掉，
	#    让它走**静默推进**那条路（弹框那条由打捞专项步骤验）。
	var leftover: int = st.wrecks.size()
	st.wrecks.clear()
	st.wrecks_display.clear()
	_battle.call("_refresh_salvage_area")

	# 走控件自身通道点「继续」
	next_btn.emit_signal("pressed")
	_expect(not bool(hud.call("result_is_open")),
			"点「继续」后结算页收起（点前有 %d 艘残骸，已清）" % leftover)
	_expect(st.node_index == node0 + 1,
			"点「继续」推进到节点 %d（实际 %d）" % [node0 + 1, st.node_index])
	_expect(st.phase == EveRunState.Phase.PREP, "推进后回到准备阶段")
	# 推进节点时，上一场的特效 / 飘字必须清掉（否则爆炸会飘到下一轮布阵台上）
	_expect(int(_battle.get("arena").get("battle_fx").call("active_count")) == 0,
			"推进节点后残留特效已清空")
	_expect(int(hud.get("damage_feed").call("active_count")) == 0,
			"推进节点后残留飘字已清空")
	print("[结算页·继续] 节点 %d → %d · 特效与飘字已清" % [node0, st.node_index])


## ── 阶段 D⑥：设置窗 ──────────────────────────────────────────────
##
## ⚠️ 两道关都要过：
##    ① 顶条 ≡ 能**把窗打开**（信号链：command_bar → hud → scene）；
##    ② 窗里的控件点下去**真的改了 arena**（不是只改了自己的皮肤）。
##    第②种事故的表现是「开关看着能拨、画面纹丝不动」，必须验到后端。
func _step_d_settings() -> void:
	var hud = _battle.get("hud")
	var arena = _battle.get("arena")

	# ⚠️ 2026-09-28 起设置窗会**写盘**。验收脚本点过的每一个开关都会落进
	#    `user://settings.cfg` —— 不还原的话，玩家跑一次验收就丢一次自己的设置。
	#    所以开头存一份快照、结尾原样写回（只还原文件：arena 当前这局的
	#    画面状态无所谓，下一次启动读回的就是玩家原来的偏好）。
	var store = SETTINGS_SCRIPT.STORE
	var saved_before := store.load_all()

	_expect(not bool(hud.call("settings_is_open")), "设置窗默认是收起的")
	# ① 走顶条 ≡ 的信号链打开
	var bar = hud.get("command_bar")
	var opened := false
	if bar.has_signal("settings_requested"):
		bar.emit_signal("settings_requested")
		opened = bool(hud.call("settings_is_open"))
	_expect(opened, "顶条 ≡ → 设置窗打开（信号链完整）")
	if not opened:
		return

	var sw = hud.get("settings_window")
	# 打开时必须回写了真实状态 —— 否则玩家看到的开关与实际不符，
	# 点一下反而把状态改成了他不想要的那个。
	_expect(sw.call("get_toggle", "board") == (arena.get("board") != null
			and bool(arena.get("board").get("visible"))),
			"棋盘开关回写 = arena 实际状态（窗 %s / 场 %s）"
			% [str(sw.call("get_toggle", "board")),
			str(arena.get("board") != null and bool(arena.get("board").get("visible")))])

	# ② 点「棋盘」开关：走控件自身 pressed 通道，验 arena 真的变了
	var board_btn: Button = (sw.get("_toggles")["board"] as Dictionary)["btn"]
	var before := arena.get("board") != null and bool(arena.get("board").get("visible"))
	board_btn.emit_signal("pressed")
	var after := arena.get("board") != null and bool(arena.get("board").get("visible"))
	_expect(after != before,
			"点「棋盘」开关 → arena.board.visible %s → %s（后端真的动了）"
			% [str(before), str(after)])
	_expect(sw.call("get_toggle", "board") == after,
			"按钮自己的状态与 arena 同步（窗 %s / 场 %s）"
			% [str(sw.call("get_toggle", "board")), str(after)])
	# 再点一次拨回来，别把后续步骤的前提改掉
	board_btn.emit_signal("pressed")
	_expect((arena.get("board") != null and bool(arena.get("board").get("visible"))) == before,
			"再点一次拨回原状（棋盘回到 %s）" % str(before))

	# ③ 点天空盒：验 arena.background 真的换了（这条最容易「看着能点、实际没接线」）
	var bg_before: String = String(arena.call("current_background_id"))
	var bg_btns: Array = sw.get("_bg_btns")
	_expect(bg_btns.size() >= 2, "天空盒候选 ≥ 2 个（实际 %d）" % bg_btns.size())
	if bg_btns.size() >= 2:
		# 挑一个与当前**不同**的条目
		var pick := 0
		for i in bg_btns.size():
			if String(SETTINGS_SCRIPT.BACKGROUNDS[i]["id"]) != bg_before:
				pick = i
				break
		(bg_btns[pick] as Button).emit_signal("pressed")
		var bg_after: String = String(arena.call("current_background_id"))
		_expect(bg_after != bg_before,
				"点天空盒 → arena 背景 %s → %s（后端真的换了）" % [bg_before, bg_after])
		print("[设置窗] 天空盒 %s → %s · 棋盘开关往返正常" % [bg_before, bg_after])

	# ⑤ 暂停按钮（2026-09-28）：PVE 也要能停，而且停了就得真的停住
	#
	# ⚠️ 三条一起验才叫「暂停做对了」：
	#    ① 状态真的进了暂停；② 遮罩上台且吃掉鼠标（禁止操作的落点）；
	#    ③ 推进真的停了（`_process` 喂一个大 delta 也纹丝不动）。
	#    只验①的话，「暂停了但倒计时还在跑」这种假暂停会一路绿灯。
	var pause_btn: Button = sw.get("_pause_btn")
	_expect(pause_btn != null, "设置窗里有暂停按钮")
	if pause_btn != null:
		_expect(pause_btn.size.y >= 36.0,
				"暂停按钮比常规按钮大（高 %s ≥ 36）" % str(pause_btn.size.y))
		_expect(not bool(_battle.get("_paused")), "进场未暂停")
		pause_btn.emit_signal("pressed")
		_expect(bool(_battle.get("_paused")), "点暂停 → 主控进入暂停态")

		var veil = hud.get("pause_veil")
		_expect(veil != null and bool(veil.get("visible")), "暂停 → 全屏遮罩上台")
		if veil != null:
			_expect(int(veil.get("mouse_filter")) == Control.MOUSE_FILTER_STOP,
					"遮罩吃掉鼠标 = 暂停期间禁止操作")
			# ⚠️ 尺寸按 **hud 自己的 size** 比，不要写死 1920×1920 ——
			#    无头视口是 1920×1920，而真窗口是 1920×1080，
			#    写死屏幕坐标的断言换个视口就假失败（本工程既有教训）。
			var hud_size = hud.get("size")
			_expect(veil.get("size").x >= float(hud_size.x) - 1.0
					and veil.get("size").y >= float(hud_size.y) - 1.0,
					"遮罩铺满 HUD（%s vs %s）" % [str(veil.get("size")), str(hud_size)])
			# ⚠️ 遮罩若盖住设置窗，玩家点完暂停再关窗就再也点不回来（只能按空格）
			_expect(hud.get("settings_window").get_index() > veil.get_index(),
					"设置窗压在遮罩之上（不会被自己的暂停锁死）")

		var sim = _battle.get("sim")
		var t0 := float(sim.get("elapsed")) if sim != null else -1.0
		var phase0: int = int(_run().phase)
		_battle.call("_process", 5.0)
		var t1 := float(sim.get("elapsed")) if sim != null else -1.0
		_expect(absf(t1 - t0) < 0.0001, "暂停期间推进停摆（%.3f → %.3f）" % [t0, t1])
		_expect(int(_run().phase) == phase0, "暂停期间阶段不变（仍是 %d）" % phase0)

		pause_btn.emit_signal("pressed")
		_expect(not bool(_battle.get("_paused")), "再点一次 → 解除暂停")
		var veil2 = hud.get("pause_veil")
		_expect(veil2 == null or not bool(veil2.get("visible")), "解除暂停 → 遮罩收起")

	# ⑥ 音量滑杆：拖下去必须改到音频层，而且得落盘
	#
	# ⚠️ 「窗里的数字变了但音量没变」是这类控件最经典的假实现 ——
	#    所以断言打在 `EveAudio` 的字段上，不打在滑杆自己的 value 上。
	var sliders: Dictionary = sw.get("_sliders")
	var sfx_pack: Dictionary = sliders.get(&"sfx", {})
	var sfx_slider: HSlider = sfx_pack.get("slider", null)
	var audio = _battle.get("audio")
	if sfx_slider != null:
		sfx_slider.value = 0.25
		_expect(absf(float(audio.get("volume_sfx")) - 0.25) < 0.001,
				"音效滑杆 25%% → EveAudio.volume_sfx = %.3f"
				% float(audio.get("volume_sfx")))
		_expect(absf(float(store.load_all().get("sfx", -1.0)) - 0.25) < 0.001,
				"音量改动已写盘（user://settings.cfg）")
		sfx_slider.value = 0.60
		_expect(absf(float(audio.get("volume_sfx")) - 0.60) < 0.001,
				"滑杆拨回 60%% → volume_sfx = %.3f" % float(audio.get("volume_sfx")))

	# 总音量走 Master 总线 —— 与分档互相独立，调它不该动到分档值
	var master_pack: Dictionary = sliders.get(&"master", {})
	var master_slider: HSlider = master_pack.get("slider", null)
	if master_slider != null:
		var sfx_before := float(audio.get("volume_sfx"))
		master_slider.value = 0.50
		_expect(absf(float(audio.get("volume_master")) - 0.50) < 0.001
				and absf(float(audio.get("volume_sfx")) - sfx_before) < 0.001,
				"总音量只改 Master，不污染分档（sfx 仍 %.3f）" % sfx_before)
		master_slider.value = 1.0

	# 静音开关
	var mute_btn: Button = (sw.get("_toggles").get("mute", {}) as Dictionary).get("btn", null)
	if mute_btn != null:
		mute_btn.emit_signal("pressed")
		_expect(bool(audio.get("muted")), "静音开关 → audio.muted = true")
		mute_btn.emit_signal("pressed")
		_expect(not bool(audio.get("muted")), "再点一次 → 取消静音")

	# ⑦ 窗高必须**贴合内容**（底部空白 ≤ 12px）
	#
	# ⚠️ 这是 2026-09-29 用户实测报的病：窗被撑到 919px、底部空了 390px。
	#    根因是内容还没布局（窗宽=0）时就反推高度 —— autowrap 的提示行在 0 宽下
	#    折出几十行，量出 800+px。这类「无头全绿、实机难看」的洞必须钉死：
	#    空白 = 窗高 − 最后一个可见控件的底边，正常时应只剩底部内边距（8px）。
	# ⚠️ 量法**不依赖子项是否已布局**：无头环境里 Control 可能一次都没排过序，
	#    那时子项的 `position/size` 全是 0（实测：拿它算空白会得到 496px 的假失败）。
	#    `get_combined_minimum_size()` 是控件自己报的最小需求，不需要布局 ——
	#    而它恰恰就是「窗被撑大」这个病的判据：窗高应当 = 内容最小需求 + 窗框开销。
	#    （真实观感的「底部空白」由 `tools/probe_settings_fit.tscn` 出数：8~9px。）
	# ⚠️⚠️ 2026-10-10：这条断言会被**玩家存档的窗布局**污染 ——
	#    `user://window_layout.cfg` 里若 "设置" 被玩家收起来过（collapsed=true），
	#    建设置窗时 `_load_layout()` 就把它恢复成收起态 ⇒ 窗高只剩标题栏（27），
	#    断言假失败。验收必须与玩家存档隔离：先清掉这扇窗的布局记忆、按内容
	#    重推一次窗高，判完再**原样写回**（验收不该改变玩家的窗布局）。
	var layout_key := String(sw.call("_layout_key"))
	var saved_layout: Dictionary = WINDOW_STORE.load_window(layout_key)
	sw.call("reset_layout")     # 清 _user_rect / _collapsed / _height_owned
	sw.call("_fit_height")      # 按当前内容重新反推窗高（被测的就是这个语义）
	var sw_content = sw.get("content")
	# 窗框开销：标题栏 26 + 内容区上下内距 6/8（COMPACT density）+ 上下边框各 1
	var chrome := 42.0
	var want := chrome + float(sw_content.get_combined_minimum_size().y)
	_expect(absf(float(sw.get("size").y) - want) <= 4.0,
			"窗高贴合内容（窗高 %.0f vs 需求 %.0f）" % [float(sw.get("size").y), want])
	# ★ 2026-10-10 上限由 700 放宽到 780：新增的「重置 RESET」区（分隔线 + 标题 +
	#    按钮 + 说明行）让无头下的窗高从 661 长到 740。语义没变 ——
	#    这条防的是「未布局就量」把窗撑到 900+（见上面 `_fit_height` 的说明），
	#    780 仍远低于那个量级。
	_expect(float(sw.get("size").y) <= 780.0,
			"窗高没有失控（%.0f ≤ 780）" % float(sw.get("size").y))
	WINDOW_STORE.save_window(layout_key, saved_layout)   # 原样写回玩家存档

	# ④ 再点一次 ≡ 应当收起（同一个按钮负责开关）
	if bar.has_signal("settings_requested"):
		bar.emit_signal("settings_requested")
	_expect(not bool(hud.call("settings_is_open")), "再点 ≡ → 设置窗收起")
	# 收起前把窗再打开一次，交给下一步截图（OUT_SETTINGS）
	if bar.has_signal("settings_requested"):
		bar.emit_signal("settings_requested")
	_expect(bool(hud.call("settings_is_open")), "重新打开供截图")
	_expect(hud.get("settings_window").visible, "设置窗在台上（下一步截图）")

	# ⑧ ★ 2026-10-10 「恢复默认设置」（按钮 + Ctrl+F11 救命键）
	#
	# ⚠️ 判据打在**后端**（EveAudio 的字段 + 存档文件），⛔ 不打在按钮皮肤上 ——
	#    「按钮看着换了、设置没回默认」是这类控件最经典的假实现。
	var dflt: Dictionary = SETTINGS_SCRIPT.STORE.DEFAULTS
	# 先把音效拧歪（并落盘），制造一个"非默认"的局面
	sfx_slider.value = 0.20
	_expect(absf(float(audio.get("volume_sfx")) - 0.20) < 0.001,
			"前置：音效被调离默认（0.20）")
	# ① 按钮存在（按文案找 —— 位置会随分区调整而变）
	var reset_btn: Button = null
	for n in sw.get("content").find_children("*", "Button", true, false):
		if (n as Button).text == "恢复默认设置":
			reset_btn = n as Button
			break
	_expect(reset_btn != null, "★ 设置窗有「恢复默认设置」按钮")
	# ② 点它 ⇒ 后端真的回默认（音量）+ 存档回**哨兵值**
	if reset_btn != null:
		reset_btn.emit_signal("pressed")
	_expect(absf(float(audio.get("volume_sfx")) - float(dflt["sfx"])) < 0.001,
			"★★ 点「恢复默认设置」⇒ 音效回默认 %.2f（实际 %.2f）"
			% [float(dflt["sfx"]), float(audio.get("volume_sfx"))])
	_expect(absf(float(store.load_all().get("font_scale", -1.0)) - float(dflt["font_scale"])) < 0.001,
			"★★ 字号存档也回默认哨兵（%.1f）" % float(dflt["font_scale"]))
	_expect(String(store.load_all().get("resolution", "?")) == String(dflt["resolution"]),
			"★★ 分辨率存档回自适应哨兵（\"%s\"）" % String(dflt["resolution"]))
	# ③ Ctrl+F11 —— **窗关着也生效**（合成一个按键事件直接喂给它的 `_unhandled_input`）
	sfx_slider.value = 0.20
	var f11 := InputEventKey.new()
	f11.keycode = KEY_F11
	f11.ctrl_pressed = true
	f11.pressed = true
	sw.call("_unhandled_input", f11)
	_expect(absf(float(audio.get("volume_sfx")) - float(dflt["sfx"])) < 0.001,
			"★★ Ctrl+F11 ⇒ 同样回默认（实际 %.2f）" % float(audio.get("volume_sfx")))

	# ⑨ ★ 2026-10-10：标题栏右上角的 ✕（在折叠按钮**右边**）—— 点下去窗真的关掉。
	#
	# ⚠️ 放在**本步最后**：点完这枚按钮窗就关了，后面的步骤没窗可用。
	# ⚠️ 红线 9：新面板必须验「点下去有反应」—— 不能只断言按钮存在。
	var close_btn: Control = sw.get("_close_btn")
	_expect(close_btn != null, "★ 设置窗标题栏有 ✕ 关闭按钮")
	if close_btn != null:
		var hdr: Control = sw.get("header")
		var col_btn: Control = sw.get("_collapse_btn")
		_expect(col_btn != null, "设置窗有折叠按钮（✕ 要在它右边）")
		if hdr != null:
			_expect(close_btn.get_index() == hdr.get_child_count() - 1,
					"★ ✕ 在标题栏最右端（下标 %d / 共 %d）"
					% [close_btn.get_index(), hdr.get_child_count()])
		if col_btn != null:
			_expect(close_btn.get_index() == col_btn.get_index() + 1,
					"★★ ✕ 紧跟在折叠按钮右边（✕ %d / 折叠 %d）"
					% [close_btn.get_index(), col_btn.get_index()])
		var cb_ev := InputEventMouseButton.new()
		cb_ev.button_index = MOUSE_BUTTON_LEFT
		cb_ev.pressed = true
		cb_ev.position = close_btn.size * 0.5
		close_btn.gui_input.emit(cb_ev)
		_expect(not bool(hud.call("settings_is_open")),
				"★★ 点 ✕ ⇒ 设置窗关闭（走 HUD.hide_settings 收口）")

	# 收尾：把玩家的设置原样写回 —— 验收不该改变玩家的设置
	for k in saved_before.keys():
		store.save_one(k, saved_before[k])


func _step_next_node() -> void:
	var st := _run()
	var hud = _battle.get("hud")

	# ⚠️ 阶段 D 之后，推进节点有了**两条合法入口**：
	#    ① 玩家点结算页的「继续 · 下一节点」（_step_d_result 已经走过这条）；
	#    ② 无头脚本直调 debug_skip_resolve（旧脚本走的这条）。
	#    两条都通向同一个 _end_resolve，不必也不能重复走 ——
	#    所以这里先看结算页还在不在台上，在才需要推。
	hud.call("hide_settings")
	if bool(hud.call("result_is_open")):
		_battle.call("debug_skip_resolve")
		print("[推进节点 · 走 debug 入口] %s" % st.summary())
	else:
		print("[推进节点 · 已由结算页推进过] %s" % st.summary())

	_expect(st.node_index == 2, "推进到节点 2（实际 %d）" % st.node_index)
	_expect(st.phase == EveRunState.Phase.PREP, "回到准备阶段")

	var foes: Array = _battle.get("_enemy_ships")
	_expect(foes.size() == 2, "节点 2 敌人重新就位（实际 %d 艘）" % foes.size())
	_expect(st.enemy_comp_id() == _node1_enemy_comp,
			"节点 2 与节点 1 是同一张脸（%s）—— 这一手必须保住"
			% st.enemy_comp_id())
	if foes.size() > 0:
		var shield2 := float(foes[0].max_hp[&"shield"])
		var atk2 := float(foes[0].weapon_damage)
		print("      节点 1 护盾 %.0f / 攻击 %.0f → 节点 2 护盾 %.0f / 攻击 %.0f"
				% [_node1_enemy_shield, _node1_enemy_attack, shield2, atk2])
		_expect(is_equal_approx(shield2, _node1_enemy_shield * 1.25),
				"节点 2 护盾 = 节点 1 × 1.25（power_scale 生效）")
		_expect(is_equal_approx(atk2, _node1_enemy_attack * 1.25),
				"节点 2 攻击 = 节点 1 × 1.25")
	# 备战席格带要跟着清空（这一节点一艘都没买）
	# ⚠️ 2026-09-23：与上面 _step_buy 同一条改动 —— 3D 备战层已停用。
	var bench_rail2 = _battle.get("hud").get("bench_rail")
	_expect(_rail_fleet_count(bench_rail2) == st.bench.size(),
			"备战席格带名单与数据一致（%d / %d）"
			% [_rail_fleet_count(bench_rail2), st.bench.size()])

	# ── 阶段 C 收尾：换节点 → 字幕必须换成新节点的那一句 ──────────
	# ⚠️ 这条捕获的是「字幕弹了、但内容还是上一节点的」——
	#    因为文案是写进复用的 Label 里的，忘了重写就不会报错，
	#    玩家看到的是「同一句话刷两次」，很难被当成 bug 报上来。
	var banner2 = hud.get("entry_banner")
	if banner2 != null:
		_expect(int(banner2.call("active_count")) == 1,
				"推进到节点 2 后重新弹了字幕")
		_expect(String(banner2.call("current_node_text"))
				== "节点 02 / %d" % EveNodeTable.TOTAL,
				"字幕节点号跟着换了（实际 %s）" % banner2.call("current_node_text"))
		_expect(String(banner2.call("current_text")) == st.entry_line(),
				"字幕正文换成节点 2 的进场词")
		_expect(String(banner2.call("current_text"))
				!= String(EveNodeTable.by_index(1).get("line", "")),
				"字幕正文不再是节点 1 的那句")
		print("[进场字幕] 节点 2 换词确认 · %s（LIFE=%.1fs）"
				% [banner2.call("current_text"), _entry_banner_life])


# ══════════════════════════════════════════════════════════════════
#  第二段（续）：阶段 B5 拖放部署 —— 真的走一遍「拿起 → 拖动 → 落格」
# ══════════════════════════════════════════════════════════════════
#
# ⚠️ 这里不合成 InputEvent，而是直接调战斗场景的那几个私有入口
#    （_try_begin_drag / _update_drag / _end_drag）。
#    理由：合成鼠标事件的结果依赖窗口与缩放，不稳；
#    而真正会错的恰恰是「屏幕坐标 ↔ 格号」这层换算与编制写入 ——
#    两者都在那三个函数里，调它们等于跑完除「操作系统送事件」以外的全部逻辑。

## 第 (row,col) 格是否已被自己占着（本脚本的前置检查用）。
##
## ⚠️ 与 EveRunState._cell_taken 同口径，但那边是私有的、且要传 ignore 下标。
##    这里只回答「这一格能不能用」，够本脚本摆前置状态就行。
func _cell_occupied(st, row: int, col: int) -> bool:
	for e in st.field_entries():
		if e.get("cell", Vector2i(-1, -1)) == Vector2i(row, col):
			return true
	return false


## 当前拖动状态里的来源（&"bench" / &"field" / &""）—— 诊断用。
func _drag_source_of() -> StringName:
	return StringName(_battle.get("_drag").get("source", &""))


## 场上所有船所在的格（诊断用，失败信息里打出来一眼看出错位）
func _field_cells(st) -> Array:
	var out: Array = []
	for e in st.field_entries():
		var c: Vector2i = e.get("cell", Vector2i(-1, -1))
		out.append("(%d,%d)" % [c.x, c.y])
	return out


func _step_b_drag() -> void:
	var st := _run()
	# ══════════════════════════════════════════════════════════════════
	#  本段的人员记账（**必须先看懂这张表再改任何数字**）
	# ══════════════════════════════════════════════════════════════════
	#   起点：场上 3 / 备战席 ≤1
	#   ① 补买一艘（只进备战席，不动场上）        → 场上 3 / 备战席 2
	#   ② 撤回一艘（场上 → 备战席）              → 场上 2 / 备战席 3
	#   ③ 拖 bench[0] 到 (8,5)（部署）           → 场上 3 / 备战席 2
	#   ⇒ `_step_b_drop` 的断言必须是「场上 3 / 备战席 2」。
	#
	# ⚠️⚠️ 这里原本写的是「场上 4」——**错的**，而且错了很久没被发现：
	#    它假设起点 3 艘 + 拖放 1 艘 = 4，却漏算了 ②那一撤回。
	#    撤回后场上只剩 2，再部署一艘恰好回到 3。
	#    「4」这个期望值让 `_step_b_drop` 长期假红，而症状（上场数少 1）
	#    又长得像「拖放没生效 / 相机没回来」，于是被反复误判成别的 bug。
	#    ⇒ 改断言值之前，先核对上面这张表。数量守恒必须**逐笔**对。
	#
	# 另外：等级必须显式摆到 4（上限 6），**不能靠"前面几步刚好留在 4"** ——
	# 阶段 D 之后 `_step_levelup` 已把等级抬到 3、`_step_b_place` 又买过船，
	# 等级与编制都会漂。漂了的话本段的前提全部失效（幂等，重复跑也一样）。
	while st.level < 4:
		st.coin = 60
		st.levelup()
	_expect(st.level == 4, "本段前置：等级 4（实际 Lv%d）" % st.level)
	_expect(st.field_limit() == 6, "本段前置：Lv4 上场上限 6（实际 %d）" % st.field_limit())
	# 场上清到 3 艘（拖放那一艘上去正好 4）—— 多出来的撤回备战席。
	while st.field.size() > 3:
		var rc := st.recall_to_bench(st.field.size() - 1)
		if not bool(rc.get("ok", false)):
			break
	# ★ 目标格 (DRAG_ROW, DRAG_COL) 必须是空的（2026-09-20 挖出的隐性前提）
	#   ── 本段只断言了「场上 3 艘」，**没断言那 3 艘在哪几格**。
	#      而前序步骤各占一格：`_step_deploy_first` 放 (8,3)(8,4)(8,6)，
	#      `_step_economy` 又放了 (7,5)。船的**数量**对得上，位置却可能
	#      正好压住 (8,5) —— 于是 `preview_place` 返回
	#      「这一格已经有船了」，落点提示自然写不出行号。
	#   ⚠️ 症状极具误导性：报出来的是「提示里没写行号」「商店亮橙」
	#      「拖放后上场 4 艘（实际 3）」三条，看着像拖放坏了 / 相机没回来，
	#      根因其实只是**这一格不巧被占**。数量守恒 ≠ 位置可用。
	#   ⇒ 显式把占着目标格的船挪开（幂等：本来空着就空转）。
	var squatter := -1
	for i in st.field.size():
		if st.field[i].get("cell", Vector2i(-1, -1)) == Vector2i(DRAG_ROW, DRAG_COL):
			squatter = i
	if squatter >= 0:
		# ⚠️ 目标格用 EveBoard.own_zone_row0()（= ENEMY_ROWS + ISOLATION_ROWS = 7）算，
		#    不要写死 7 —— 棋盘分区是棋盘自己的口径，写死了改分区时不会报错。
		var own0 := EveBoard.own_zone_row0()
		var moved := st.move_field(squatter, own0, 0)
		_expect(bool(moved.get("ok", false)),
				"腾开目标格 (%d,%d)：占位船挪到 (%d,1)（%s）"
				% [DRAG_ROW, DRAG_COL, own0 + 1,
					String(moved.get("reason", ""))])
	_expect(not _cell_occupied(st, DRAG_ROW, DRAG_COL),
			"本段前置：目标格 (%d,%d) 空着（实际 %s）"
			% [DRAG_ROW, DRAG_COL,
				"被船占着" if _cell_occupied(st, DRAG_ROW, DRAG_COL) else "空"])
	# 备战席腾到 ≤ 1 艘，给本段"补买一艘 → 备战席 2"的断言留出位置。
	while st.bench.size() > 1:
		if not bool(st.sell_from_bench(st.bench.size() - 1).get("ok", false)):
			break
	_expect(st.field.size() == 3 and st.bench.size() <= 1,
			"本段前置：场上 3 / 备战席 ≤1（实际 %d / %d）"
			% [st.field.size(), st.bench.size()])

	# 补买一艘 —— ⚠️ 只进备战席（云顶口径），场上人数不变。
	# 挑一款「当前编制里一艘都没有」的，避免顺手凑成三连把断言变成掷骰子。
	var f0 := st.field.size()
	var fresh := _force_offers_fresh(st)
	var r := st.buy(0)
	_expect(bool(r.get("ok", false)),
			"补买一艘 %s（%s）" % [String(fresh), String(r.get("reason", ""))])
	_expect(st.field.size() == f0,
			"买入不动场上（%d → %d）" % [f0, st.field.size()])
	_expect(st.bench.size() == 2, "补买的进备战席（备战席 %d 艘）" % st.bench.size())

	# 再撤回一艘 —— 顺带把「场上 → 备战席」这条路也走一遍
	var r2 := st.recall_to_bench(st.field.size() - 1)
	_expect(bool(r2.get("ok", false)) and st.bench.size() == 3,
			"撤回一艘 → 备战席 3（%s）" % String(r2.get("reason", "")))

	# ★ 拖动源必须落在 bench[0]，而 bench[0] 那款不能有「第三张」在场上
	#   ── 2026-09-20 挖出的第四条隐性前提。本段下面写死「拖备战席第 0 格」，
	#      而 `deploy_from_bench` 成功后会触发 `_try_merge`：
	#      若 bench[0] 这一款在编制里凑满 3 张，三连合成会立刻把它变成 1 张 2★
	#      ⇒ **上场数不增反减**，断言报「拖放后上场 4 艘（实际 3）」。
	#      而实际证据（松手前来源=bench、松手后 (8,5) 里确有船）表明拖放本身没问题，
	#      是**合成把数字吃掉了**。
	#   ⇒ 把「编制里唯一的那一款」换到 bench[0]：它一定凑不出三连。
	#      `_force_offers_fresh` 挑的 `fresh` 正好是编制里没有的，刚买进来的那艘就是它。
	var fresh_idx := -1
	for i in st.bench.size():
		if StringName(st.bench[i].get("ship_key", &"")) == fresh:
			fresh_idx = i
	if fresh_idx > 0:
		var tmp: Dictionary = st.bench[0]
		st.bench[0] = st.bench[fresh_idx]
		st.bench[fresh_idx] = tmp
	elif fresh_idx < 0:
		# 没买到唯一款（货架被占等）—— 退而求其次：把任意一款 count==1 的换上来
		var counts := {}
		for e in st.all_owned():
			var k := StringName(e.get("ship_key", &""))
			counts[k] = int(counts.get(k, 0)) + 1
		for i in st.bench.size():
			if int(counts.get(StringName(st.bench[i].get("ship_key", &"")), 9)) == 1:
				var t2: Dictionary = st.bench[0]
				st.bench[0] = st.bench[i]
				st.bench[i] = t2
				break
	var lead := StringName(st.bench[0].get("ship_key", &""))
	var lead_n := 0
	for e in st.all_owned():
		if StringName(e.get("ship_key", &"")) == lead:
			lead_n += 1
	_expect(lead_n == 1,
			"本段前置：拖动源 %s 在编制里只有 1 份（实际 %d 份）—— 否则会三连合成"
			% [String(lead), lead_n])
	await get_tree().process_frame

	var hud = _battle.get("hud")
	var arena = _battle.get("arena")
	var board = arena.get("board")

	# 屏幕点取备战席第 0 格中心（刻意落在**格带上沿往上 6px** 处 —— 那里
	# 仍在命中区里，用来覆盖「玩家手抖、点在格子外面一点」这种情况）。
	# ⚠️ 这个点依赖 `HIT_ABOVE >= 6`（当前 10，见 EveBenchRail.HIT_ABOVE）：
	#    把它调到 6 以下这条断言就会挂，而挂在「命中区」而不是「格带本身」，
	#    排查时容易往错的方向找。
	var br: Rect2 = hud.call("bench_hit_rect")
	var slot0 := Vector2(br.position.x + br.size.x / 16.0, br.position.y + 6.0)
	var bi: int = hud.call("bench_slot_at", slot0)
	_expect(bi == 0, "屏幕点落在备战席第 0 格（实际 %d）" % bi)

	var sz: Rect2 = hud.call("sell_zone_rect")
	_expect(not sz.has_point(slot0), "备战席不在出售区里（两者不重叠）")

	var began: bool = _battle.call("_try_begin_drag", slot0)
	_expect(began, "在备战席上按下左键 → 拿起成功")

	var drag: Dictionary = _battle.get("_drag")
	_expect(not drag.is_empty(), "拖动状态已建立")
	_expect(StringName(drag.get("source", &"")) == &"bench", "拖动来源 = 备战席")
	_expect(board != null and board.visible, "拿起后棋盘自动显形")

	# 目标格 → 世界坐标（米）→ 屏幕坐标 → 再解析回格号：这一趟必须闭环。
	# ⚠️ 这条断言同时是【单位口径】的守门人：
	#    board_cell_to_meters 给米 / world_to_screen 吃米 / screen_to_cell 吃屏幕、
	#    吐世界单位再转格号。任意一环混了「米 ↔ 世界单位」（差 1000 倍）
	#    这里都会立刻变成 (-1,-1) 或错格 —— 而线上症状只是「拖不动船」，不报错。
	var world: Vector3 = arena.call("board_cell_to_meters", DRAG_ROW, DRAG_COL)
	var screen: Vector2 = arena.call("world_to_screen", world)
	var back: Vector2i = arena.call("screen_to_cell", screen)
	_expect(back == Vector2i(DRAG_ROW, DRAG_COL),
			"格 (%d,%d) → 屏幕 → 格 往返一致（实际 %s）"
			% [DRAG_ROW, DRAG_COL, str(back)])

	_battle.call("_update_drag", screen)
	drag = _battle.get("_drag")
	# ⚠️ 失败信息必须带上**提示全文 + 屏幕点 + 出售区矩形**（2026-09-20）：
	#    「提示没写行号」这一条有三种完全不同的死法，只说"缺行号"根本分不清：
	#      ① 落点被判成出售区   → hint = "出售 · 返还 ◆N"
	#      ② 落点被判成备战席   → hint = "放回备战席"
	#      ③ 落点算到了别的一格 → hint = "部署到 第 A 行第 B 列"（A≠9）
	#    把三者要用的数据一次打全，下一次挂掉时不用回来加打印。
	_expect(bool(drag.get("hint_ok", false)),
			"落点提示为「可以放」（提示：%s · 屏幕 %s · 出售区 %s）"
			% [String(drag.get("hint", "")), str(screen.round()),
				str(hud.call("sell_zone_rect"))])
	_expect(String(drag.get("hint", "")).contains("%d" % (DRAG_ROW + 1)),
			"提示里写明了行号（第 %d 行 · 实际提示「%s」· 屏幕 %s · 出售区 %s）"
			% [DRAG_ROW + 1, String(drag.get("hint", "")), str(screen.round()),
				str(hud.call("sell_zone_rect"))])
	# ★ 相机实况（纯 ASCII，保证在乱码日志里也读得到）
	#   这条**不是断言**，是把「投影为什么落在那里」所需的量一次打全：
	#   cam 位置 / 焦点 / 距离 / pitch / fov / viewport，缺一个就得再跑一轮。
	#   ⚠️ 必须写在 `var cam = arena.get(...)` **之后** —— 它要读 cam。
	#   （踩过：写在这里直接 Parse Error "Identifier cam not declared"。）

	# ★ 相机守卫：布阵取景必须真的收敛到位。
	#   ── 为什么单列一条（2026-09-20 挖出的隐蔽缺陷）────────────────
	#   无头模式下 `_process` 的 `delta` 是 0 ⇒ 收敛速度 = 0 ⇒ yaw / 距离
	#   **永远停在原处**，而 target 一直挂着、`_process` 也确实在跑。
	#   后果不是"视角不好看"：格子投影整体下移，格 (8,5) 落进商店窗的出售区，
	#   **玩家拖船到格子上会被卖掉**。而报出来的失败是
	#   「提示没写行号 / 商店亮橙 / 上场数少了 1」三条看似无关的断言。
	#   这条断言把根因直接钉在相机上。
	#
	#   ⚠️ 时机：收敛是**跨帧**的（约 0.25 秒），而本函数在"拿起"的**同一帧**
	#      里执行 —— 此刻 target 刚设上、current 还没动。直接断言 yaw 必然失败。
	#      所以这里手动推够步数再断言（等价于"等 0.25 秒"，
	#      但不受无头 delta=0 的影响，见 EveOrbitCamera.MIN_STEP_DELTA）。
	#
	# ⚠️⚠️ 推的那几步必须**走 arena._process 同款的两条收敛路径**（2026-09-20 二次纠错）
	#    ── 只调 cam._step() 是不够的，因为视距不由它决定 —— 决定视距的
	#       `max_range` 与焦点在 arena._apply_board_framing_smooth() 里收敛，
	#       而那个函数**只在 arena._process 里被调用**。
	#       只推 cam._step 的话：yaw 对得上、距离还停在战斗档 ⇒ 断言报
	#       「distance 106.3 < 90 失败」，看起来像相机没修好，其实是**验错了对象**。
	#    ── 先 _process 推距离/焦点收敛，再 _step 推 yaw 收敛，缺一不可。
	var cam = arena.get("orion_cam")
	if cam != null:
		var want_yaw: float = float(ARENA_SCRIPT.BOARD_VIEW_YAW)
		# ⚠️ 帧数必须**足够多**，不是"够 0.25 秒"就行（2026-09-20 三次纠错）：
		#    max_range 走的是 `lerpf(cur, want, delta/0.45)` —— 每帧只走 1/27 的差额，
		#    30 帧后仍有约 32% 的残差（实测 max_range 96 而非 75.4，
		#    于是 distance = 73.1 而不是设计的 57.3）。
		#    残差本身不是 bug（真实运行会跑满几百帧），但**验收必须等到稳定**，
		#    否则测出来的是"半路上"的取景，格子投影还压在商店窗上。
		#    ⇒ 推到差额收敛为止（上限 240 帧 ≈ 4 秒，真实运行远在此之内）。
		for _i in 240:
			arena.call("_process", 1.0 / 60.0)
		for _i in 60:
			cam.call("_step", 1.0 / 60.0)
		var yaw_now: float = float(cam.get("yaw"))
		var dist_now: float = float(cam.call("distance"))
		_expect(absf(yaw_now - want_yaw) < 0.05,
				"布阵取景：相机收敛到棋盘正对位（yaw %.3f / 目标 %.3f / 差 %.4f）"
				% [yaw_now, want_yaw, absf(yaw_now - want_yaw)])
		# ⚠️ 阈值 90 → 100（2026-09-22 备战席改版）。
		#    新取景（BOARD_VIEW_ZOOM 1.80 / CAMERA_FIT_MARGIN 1.18）的
		#    设计视距 = 33×1.18/1.8 → half_diag 30.59 → max_range 61.2
		#    → distance = 61.2 × 1.52 ≈ **93.0**。
		#    这条断言的语义是「视距已推近到布阵档（而不是停在战斗档 ~106）」，
		#    所以写「上限」而不是「等于某个数」—— 与音量守卫同一条口径。
		_expect(dist_now < 100.0,
				"布阵取景：视距已推近到布阵档（distance %.1f < 100 · max_range %.1f）"
				% [dist_now, float(cam.call("get_max_range"))])

	# 拖动中不该点亮出售区（指针在棋盘上）
	var shop = hud.get("shop_window")
	_expect(not bool(shop.get("selling")), "指针在棋盘上时商店保持常态（不亮橙）")

	# ⚠️ 这里【不记下屏幕点】给 stage 14 用。
	#    因为拿起舰船时相机会平滑对齐到棋盘正对面（约 0.25 秒），
	#    stage 12 到 stage 14 之间隔 30 帧，相机早就转正了 ——
	#    旧屏幕点对应的是别的格。落点必须在松手那一刻用当时的相机重算，
	#    这也正是真实玩家的行为（看着屏幕上的格子移动鼠标）。见 _step_b_drop。


func _step_b_drop() -> void:
	var st := _run()
	var arena = _battle.get("arena")
	var cam = arena.get("orion_cam")

	# ⚠️ 这一段以前是 `[DBG-drop]` 调试打印。**不要把它加回来** ——
	#    它当初掩盖了真正的问题：打印出来 dist=75.5（好值），
	#    而上一条断言却报 106.3（坏值）。两个值来自**不同的收敛路径**：
	#      · dist 好值 = stage 12 已经推过 cam._step + arena._process；
	#      · 106.3     = stage 12 断言那一刻，arena._process 还没被推过，
	#                    距离仍是战斗档。
	#    结论：验「视距」必须推 arena._process，验「yaw」才推 cam._step。
	#    现在 stage 12 两条都推了，这里不需要再补推。

	# 松手点必须用【松手这一刻】的相机重算，不能用 stage 12 存下的那个点。
	#
	#    原因：拿起舰船时相机会【平滑对齐到棋盘正对面】（约 0.25 秒，
	#    见 EveBattleArena.BOARD_VIEW_YAW）。stage 12 到 stage 14 之间隔了
	#    30 帧，相机早就转正了 27.7° —— 旧屏幕点此刻对应的是别的格。
	#
	#    而真实玩家本来就是「看着屏幕上的格子移动鼠标」的，
	#    所以重算才是对玩家行为的正确模拟，不是对断言的迁就。
	var world: Vector3 = arena.call("board_cell_to_meters", DRAG_ROW, DRAG_COL)
	var screen: Vector2 = arena.call("world_to_screen", world)
	var back: Vector2i = arena.call("screen_to_cell", screen)
	# 失败信息里带上 screen：这一条挂了通常是「屏幕点落进了商店窗」，
	# 有坐标才能一眼看出是哪一侧漂了，不用再回来加打印。
	_expect(back == Vector2i(DRAG_ROW, DRAG_COL),
			"相机对齐棋盘后 格 (%d,%d) → 屏幕 → 格 仍闭环（屏幕 %s · 实际 %s）"
			% [DRAG_ROW, DRAG_COL, str(screen.round()), str(back)])

	# ⚠️ 松手前先记下拖动来源 —— 「上场数没变」有两种完全不同的死法：
	#    ① source 不是 bench（被当成移动：3 艘 → 原地挪 → 仍是 3）
	#    ② source 是 bench 但 deploy 被拒（人口满 / 格被占）
	#    后者 `_end_drag` 会把 reason 写进日志，前者不会，所以来源必须自己记。
	var src_before := StringName(_drag_source_of())
	_battle.call("_end_drag", screen)
	var drag: Dictionary = _battle.get("_drag")
	_expect(drag.is_empty(), "松手后拖动状态已清空")

	_expect(st.field.size() == 3,
			"拖放后上场 3 艘（实际 %d · 松手前来源=%s · 场上格=%s）"
			% [st.field.size(), str(src_before), str(_field_cells(st))])
	_expect(st.bench.size() == 2, "备战席剩 2 艘（实际 %d）" % st.bench.size())
	var at_cell := false
	for e in st.field_entries():
		if e.get("cell", Vector2i(-1, -1)) == Vector2i(DRAG_ROW, DRAG_COL):
			at_cell = true
	_expect(at_cell, "上场名单里有第 %d 行第 %d 列这一格" % [DRAG_ROW + 1, DRAG_COL + 1])

	var board = arena.get("board")
	_expect(board != null and not board.visible, "松手后棋盘自动收起（它不是玩家手动开的）")
	var shop = _battle.get("hud").get("shop_window")
	_expect(not bool(shop.get("selling")), "松手后商店回到常态")
	# ⚠️ 2026-09-23：3D 备战层停用后，「已拿起」标记落在 EveBenchRail.dragging_index。
	#    `and` 是短路的，所以 bench_rail3 为 null 时不会去点 get()。
	var bench_rail3 = _battle.get("hud").get("bench_rail")
	_expect(bench_rail3 != null and int(bench_rail3.get("dragging_index")) == -1,
			"备战席的「已拿起」标记已复位")
	# 舰船退出布阵态，回到战斗尺寸（放大倍数必须【还原】，不能残留）
	_expect(not bool(arena.get("ships_board_mode")),
			"松手后舰船退出布阵态（ships_board_mode=false）")


func _step_b_place() -> void:
	# ⚠️ 编制里有格号 ≠ 3D 舰船真的站在那一格 —— 这两件事必须分别验。
	var st := _run()
	var arena = _battle.get("arena")
	var idx_map: Array = _battle.get("_own_field_index")
	var ships: Array = _battle.get("_own_ships")
	var entries := st.field_entries()

	var found := -1
	for i in entries.size():
		if entries[i].get("cell", Vector2i(-1, -1)) == Vector2i(DRAG_ROW, DRAG_COL):
			found = i
	_expect(found >= 0, "上场名单里能找到 (%d,%d) 那一项" % [DRAG_ROW, DRAG_COL])
	if found >= 0 and found < idx_map.size():
		var si: int = idx_map[found]
		# ⚠️ 先落到 EveShip 类型再读 body —— 直接 ships[si].body.position
		#    会在编译期走 Variant 通道，本工程把那种推断当错误。
		var ship_obj: EveShip = ships[si]
		var want: Vector3 = arena.call("board_cell_to_meters", DRAG_ROW, DRAG_COL)
		var got: Vector3 = ship_obj.body.position
		_expect(got.distance_to(want) < 1.0,
				"对应的 3D 舰船站在该格中心（偏差 %.2f 米）" % got.distance_to(want))

	# B4：羁绊窗的 n/m 必须来自真实上场名单（不是演示数据）
	var syn = _battle.get("hud").get("synergy_window")
	var rows: Array = syn.get("_rows")
	var amarr_ratio := ""
	for row in rows:
		if String(row.get("member", "")) == "艾玛":
			amarr_ratio = (row.get("ratio") as Label).text
	var counts := EveTraitTable.count(_battle.get("_own_ships"), &"faction")
	var real_n := int(counts.get("艾玛", 0))
	_expect(amarr_ratio == "%d/%d" % [real_n, EveTraitTable.max_tier(&"faction")],
			"羁绊窗艾玛读数 = 真实名单（窗里 %s · 实际 %d 艘艾玛）" % [amarr_ratio, real_n])
	print("[拖放后] %s · 羁绊窗艾玛 %s" % [st.summary(), amarr_ratio])


# ══════════════════════════════════════════════════════════════════
#  第二段（续）：阶段 C 的事件节点
# ══════════════════════════════════════════════════════════════════

## 事件节点：面板上台 + 四条都在 + 没有时限
##
## ⚠️ 直接把 node_index 拨到 4 再调 begin_prep()（而不是连打三场），
##    因为「事件节点的面板长什么样」与「前三场怎么打」无关 ——
##    让断言依赖三场随机战斗的结果，只会得到一个偶发失败的测试。
func _step_event_open() -> void:
	var st := _run()
	var hud = _battle.get("hud")
	var arena = _battle.get("arena")

	st.node_index = 4
	_battle.call("begin_prep")

	_expect(EveNodeTable.is_event(st.node_index), "节点 4 是事件节点")
	_expect(st.phase == EveRunState.Phase.PREP, "事件节点仍处于准备阶段（phase=PREP）")
	_expect(bool(hud.call("event_is_open")), "事件面板已上台")
	_expect(st.event_picks.is_empty(), "开局还没有任何事件增益")

	# 事件节点不该有战场：清场 + 不建舰队
	# ⚠️ `_ship_nodes` 是 arena 内部字典，用 get() 取避免类上暴露成公开 API
	var sn = arena.get("_ship_nodes")
	var n_ships := 0
	if sn != null:
		n_ships = (sn as Dictionary).size()
	_expect(n_ships == 0, "事件节点清空了战场（残留 %d 艘）" % n_ships)
	_expect((_battle.get("_own_ships") as Array).is_empty()
			and (_battle.get("_enemy_ships") as Array).is_empty(),
			"事件节点不建任何舰队（双方都是空的）")

	var ew = hud.get("event_window")
	var cards: Array = ew.get("_cards")
	var shown := 0
	for w in cards:
		if (w["root"] as Control).visible:
			shown += 1
	_expect(shown == EveEventTable.count(),
			"面板列出 %d 张卡（实际 %d）" % [EveEventTable.count(), shown])

	# 没有时限 —— 决策点不该被倒计时催
	_expect(is_zero_approx(st.battle_seconds()), "事件节点战斗时限 = 0（面板不被倒计时打断）")
	print("[事件节点] 节点 %d · %s · 面板 %d 张卡"
			% [st.node_index, st.stage_label(), shown])


## 事件「选 1 艘」的两段式：点卡 → 换选船面板 → 点船 → 落地 → 推进。
##
## ⚠️ 2026-10-01 起第一条（武器调校）是**需要选船**的 ⇒ 这里走的正是两段式。
##    仍然走**卡片自己的点击通道**（不是直接 emit 信号）——
##    「鼠标点上去没反应」是这类面板最典型的实装事故，必须验到控件层。
func _step_event_choose() -> void:
	var st := _run()
	var hud = _battle.get("hud")
	var ew = hud.get("event_window")

	var pick_id := StringName(EveEventTable.all()[0]["id"])
	_expect(bool(EveEventTable.by_id(pick_id).get("pick_ship", false)),
			"第一条（%s）是需要选船的 —— 本步骤验的就是两段式" % pick_id)
	var coin0 := st.coin
	var beacon0 := st.beacon

	var click := func(idx: int) -> void:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = true
		ew.call("_on_card_input", ev, idx)

	# ── ① 第一段：点四选一的卡 ⇒ **不该直接落地**，而是换成「选 1 艘船」 ──
	click.call(0)
	_expect(st.event_picks.is_empty(), "★ 点选船类卡之后**还没落地**（在等玩家点船）")
	_expect(String(_battle.get("_pending_event")) == String(pick_id),
			"记下了待落地的 id（实际 %s）" % String(_battle.get("_pending_event")))
	_expect(bool(ew.get("_pick_mode")), "事件面板切到「选船」模式（同一窗口，不新造面板）")
	var pick_cards: Array = _battle.get("_ship_pick_cache")
	_expect(pick_cards.size() > 0, "候选船只 ≥ 1（实际 %d）" % pick_cards.size())
	_expect(st.node_index == 4, "此时**还没**推进节点（仍在 %d）" % st.node_index)

	# ── ② 第二段：点一艘船 ⇒ 才真落地 + 推进 ──
	if pick_cards.size() > 0:
		click.call(0)
	_expect(not bool(hud.call("event_is_open")), "选完船面板收起")
	_expect(not bool(ew.get("_pick_mode")), "面板的选船模式已复位")
	_expect(String(_battle.get("_pending_event")) == "", "待落地 id 已清空")
	_expect(st.event_picks.size() == 1 and st.event_picks[0] == pick_id,
			"增益已落地（%s）" % str(st.event_picks))
	_expect(st.node_index == 5, "事件节点不占回合 → 直接推进到节点 5（实际 %d）" % st.node_index)
	_expect(st.phase == EveRunState.Phase.PREP, "推进后进入节点 5 的准备阶段")

	# 增益窗：第一条事件之后才出现，且读数与状态机一致
	var aw = hud.get("augments_window")
	_expect(bool(aw.get("visible")), "事件增益窗在拿到第一条后显形")
	var info: Array = st.picked_event_info()
	_expect(info.size() == 1, "增益窗数据 = 1 条（实际 %d）" % info.size())
	if info.size() == 1:
		var want := String(info[0].get("effect", ""))
		var rows: Array = aw.get("_rows")
		var got := ""
		if not rows.is_empty():
			got = (rows[0]["effect"] as Label).text
		_expect(got == want, "增益窗效果文案 = 表里的口径（窗里「%s」）" % got)

	# 这一条是**选船类**（永久 ATK +8%）—— 不碰星币、不碰信标。
	# ⚠️ 星币**会**变，但变的必须是 `advance()` 那笔节点收入，不是事件发的钱
	#    ⇒ 逐分对账，而不是粗暴断言「等于原来」。
	var inc := EveRunState.BASE_INCOME + mini(
			int(floor(float(coin0) / float(EveRunState.INTEREST_STEP))),
			EveRunState.INTEREST_MAX)
	_expect(st.coin == coin0 + inc,
			"★ 星币只涨了节点收入 +%d（事件不发现金）：%d → %d" % [inc, coin0, st.coin])
	_expect(st.beacon == beacon0, "信标未因增益变化（%d → %d）" % [beacon0, st.beacon])
	var nm := ""
	if not info.is_empty():
		nm = String(info[0].get("name", "—"))


	print("[事件选取] %s · 已获取 %d 条 · 节点 %d" % [nm, info.size(), st.node_index])


# ══════════════════════════════════════════════════════════════════
#  第二段（续）：阶段 C 的打捞（界面链路）
# ══════════════════════════════════════════════════════════════════

## 造一个「刚打完、有击毁」的结算现场 → 残骸出现在打捞框上。
##
## ⚠️ 不真打一场：要验的是「残骸 → 打捞框 → 到账」这条链，
##    真打一场只会把断言绑在随机战斗结果上（偶发失败的老配方）。
##    这里直接调 `run.resolve_battle(...)` —— 它是**结算的唯一入口**，
##    与主控 `_on_battle_finished` 用的是同一个函数，不存在「测了另一条路」。
func _step_salvage_wreck() -> void:
	## ★ 2026-10-04 改版：打捞区在结算页**下方**，逐艘一个「打捞」按钮。
	## 这一步验「打完 → 残骸进列表 → 结算页下方出现打捞区 → 逐行列全」。
	var st := _run()
	var hud = _battle.get("hud")

	st.resolve_battle(0, [EveShipDatabase.by_cost(1)[0].duplicate(true),
			EveShipDatabase.by_cost(4)[0].duplicate(true),
			EveShipDatabase.by_cost(3)[0].duplicate(true)])
	st.set_phase(EveRunState.Phase.RESOLVE)
	_battle.call("_refresh_run_ui")

	_expect(st.wrecks.size() == 3,
			"★ 本回合 3 艘被击毁 → 残骸列表 3 艘（实测 %d）" % st.wrecks.size())
	_expect(String(st.salvage_info().get("state", "")) == "list",
			"salvage_info 报 list 态")
	var items: Array = st.salvage_info().get("items", [])
	_expect(items.size() == 3, "items 有 3 项")
	_expect(int(items[0].get("cost", 0)) == 4, "列表第 1 项是最贵的 4 费（降序）")
	for it in items:
		var d2: Dictionary = it
		for k in ["idx", "name", "star", "cost", "team", "price", "atk", "def", "node"]:
			if not d2.has(k):
				_expect(false, "★ items 项缺字段「%s」" % k)
				break
	_expect(true, "★ items 每项都带齐 idx/name/star/cost/team/price/atk/def/node")

	# 打开结算页 ⇒ 打捞区应该自动出现（不是要点按钮才出现）
	var res_win = hud.get("result_window")
	hud.call("show_result", _salvage_result_payload(st))
	# ⚠️ 打捞区数据由主控**单独推**（入参是 `salvage_info()`，不是结算 payload），
	#    见 `_popup_result()` 的注释。走真实流程就不能省这一步。
	_battle.call("_refresh_salvage_area")
	var sec: Control = res_win.get("_salvage_section")
	_expect(bool(sec.visible),
			"★ 结算页**下方**的打捞区自动出现（不再要点按钮）")
	_expect((res_win.get("_salvage_list") as Node).get_child_count() == 3,
			"★ 打捞区列出 3 行（实测 %d）"
			% (res_win.get("_salvage_list") as Node).get_child_count())
	# 每行必须有一个「打捞」按钮，且带残骸下标
	var btns := _all_buttons((res_win.get("_salvage_list") as Node))
	_expect(btns.size() == 3, "★ 每行一个「打捞」按钮（实际 %d）" % btns.size())
	_expect(String((btns[0] as Button).text) == "打捞",
			"按钮文案是「打捞」（实际「%s」）" % String((btns[0] as Button).text))
	_expect(String((res_win.get("_salvage_warn") as Label).text).contains("3"),
			"★ 顶部红字警告写出还剩几艘（实际「%s」）"
			% String((res_win.get("_salvage_warn") as Label).text))
	_salvage_key = StringName((st.wrecks[0] as Dictionary).get("ship_key", &""))
	print("[残骸上台] 3 艘进列表 · 结算页下方打捞区 3 行 · 每行一个「打捞」按钮")


## 组一个「结算页 payload」给 `show_result()` 用。
##
## ⚠️ 不能直接拿 `resolve_battle()` 的返回值 —— 它没有 `node/stage/ending`
##    这些展示字段（主控侧补的）。这里只补打捞相关项，其余给默认值。
func _salvage_result_payload(st) -> Dictionary:
	return {
		"won": true, "damage": 0, "beacon": st.beacon,
		"beacon_before": st.beacon, "beacon_max": st.beacon_max(),
		"destroyed": 0, "alive": 0, "total": 0, "xp": 0,
		"node": st.node_index, "stage": "遭遇战", "ending": "",
		"wreck": not st.wrecks.is_empty(), "wreck_count": st.wrecks.size(),
		"wreck_name": String((st.wrecks[0] as Dictionary).get("name", ""))
			if not st.wrecks.is_empty() else "",
		"reason": "",
	}


## 点某一艘的「打捞」按钮 → 下单 → 该行消失（走**真实 UI 按钮通道**）。
##
## ⚠️ 必须走真实通道：「看着能点、点了没反应」是这类交互最典型的事故 ——
##    信号接线整行丢掉时，绘制、悬停、乃至直接调 run 的单测全都正常。
func _step_salvage_order() -> void:
	var st := _run()
	var hud = _battle.get("hud")
	var res_win = hud.get("result_window")

	st.resolve_battle(0, [EveShipDatabase.by_cost(1)[0].duplicate(true),
			EveShipDatabase.by_cost(4)[0].duplicate(true),
			EveShipDatabase.by_cost(3)[0].duplicate(true)])
	st.set_phase(EveRunState.Phase.RESOLVE)
	_battle.call("_refresh_run_ui")
	hud.call("show_result", _salvage_result_payload(st))
	_battle.call("_refresh_salvage_area")

	var coin0 := st.coin
	_expect(coin0 > 0, "下单前星币 %d" % coin0)
	var list_node: Node = res_win.get("_salvage_list")
	_expect(list_node.get_child_count() == 3, "打捞区 3 行")

	# ── 点第 1 行的「打捞」──
	var btns := _all_buttons(list_node)
	_expect(btns.size() == 3, "3 个「打捞」按钮")
	var coin_before := st.coin
	(btns[0] as Button).pressed.emit()
	_expect(st.coin < coin_before, "★ 点一下当场扣钱（%d → %d）" % [coin_before, st.coin])
	_expect((st.repair_queue as Array).size() == 1,
			"★ 1 艘进了修复队列（实际 %d）" % (st.repair_queue as Array).size())
	_expect(st.wrecks.size() == 2,
			"★ 打捞掉的从残骸列表移除（剩 %d）" % st.wrecks.size())
	_expect(list_node.get_child_count() == 2,
			"★ ★该行从打捞区消失（剩 %d 行）" % list_node.get_child_count())

	# ── 再点第 2 艘（验证可以逐艘点，不是一次性）──
	var btns2 := _all_buttons(list_node)
	_expect(btns2.size() == 2, "还剩 2 个按钮")
	(btns2[0] as Button).pressed.emit()
	_expect((st.repair_queue as Array).size() == 2, "第 2 艘也成交")
	_expect(st.wrecks.size() == 1, "残骸剩 1 艘")

	# ── 打捞区切到「暂无残骸」形态（参考图 2）──
	var queue_lb: Label = res_win.get("_salvage_queue")
	_expect(bool(queue_lb.visible), "★ 出现「修复队列（下回合到账）」行")
	_expect(String(queue_lb.text).contains("下回合到账"),
			"★ 队列行文案含「下回合到账」（实际「%s」）" % String(queue_lb.text))
	var coin_lb: Label = res_win.get("_salvage_coin")
	_expect(String(coin_lb.text).contains("持有"),
			"★ 出现「持有 N 星币」（实际「%s」）" % String(coin_lb.text))
	_expect(bool((res_win.get("_salvage_close_btn") as Button).visible),
			"★ 打捞完后出现「关闭」按钮（参考图 2）")
	_expect(not String((res_win.get("_salvage_warn") as Label).text).contains("3"),
			"★ 警告行不再说「3 艘」（已打完）")

	# ── 「继续」时还有残骸 ⇒ 必须弹二次确认（参考图 1 那条红字的护栏）──
	var ask: ConfirmationDialog = res_win.get("_salvage_ask")
	_battle.call("_on_result_next")
	_expect(bool(ask.visible),
			"★ 还有 1 艘没打捞就点「继续」→ 弹二次确认（不是直接推进）")
	_expect(st.node_index == 5, "确认前节点**不推进**（仍在 %d）" % st.node_index)
	ask.confirmed.emit()
	_expect(st.node_index == 6, "★ 确认放弃后才推进到节点 %d" % st.node_index)
	print("[打捞下单] 逐艘点成交 2 艘 · 打捞行即消 · 队列/持币显示 · 残留弹确认 ✓")


## 收集一个节点下的全部 Button（多行）。
func _all_buttons(n: Node) -> Array:
	var out: Array = []
	if n is Button:
		out.append(n)
	for c in n.get_children():
		out.append_array(_all_buttons(c))
	return out


## 继续 · 下一节点 → 打捞品在**下一节点**占住货位。
##
## ⚠️ 这一步是整条链的**时序判据**：结算页下单，货在下一节点到手
##    （用户原话：「第一回合打捞要到第三回合才到位不符合直觉，要第二回合」）。
func _step_salvage_arrive() -> void:
	var st := _run()
	var hud = _battle.get("hud")
	var res_win = hud.get("result_window")
	var shop = hud.get("shop_window")

	# ⚠️ 必须**先清干净**再测：这些步骤共用同一个 run/HUD，
	#    上一步已成交的货会**累积**，断言读到 4 而不是 2。
	st.repair_queue.clear()
	st.salvage_slots.clear()

	var node0 := st.node_index
	st.resolve_battle(0, [EveShipDatabase.by_cost(1)[0].duplicate(true),
			EveShipDatabase.by_cost(4)[0].duplicate(true)])
	st.set_phase(EveRunState.Phase.RESOLVE)
	_battle.call("_refresh_run_ui")
	hud.call("show_result", _salvage_result_payload(st))
	_battle.call("_refresh_salvage_area")

	# 两艘都点
	for _k in 2:
		var bs := _all_buttons(res_win.get("_salvage_list"))
		if bs.size() > 0:
			(bs[0] as Button).pressed.emit()
	var n_buy := (st.repair_queue as Array).size()
	_expect(n_buy == 2, "2 艘成交（实际 %d）" % n_buy)
	var first_key := String((st.repair_queue[0] as Dictionary).get("ship_key", ""))

	# ★ 点「继续 · 下一节点」（此时残骸已打完 ⇒ 静默推进，不该再弹框）
	hud.call("show_result", _salvage_result_payload(st))
	_battle.call("_on_result_next")
	_expect(st.node_index == node0 + 1,
			"★ 点继续后进节点 %d（旧口径要两轮才到 —— 这就是「太慢」的根因）"
			% st.node_index)
	_expect(st.repair_queue.is_empty(), "到账后修复队列清空")
	_expect(st.salvage_slots.size() == n_buy,
			"★ 打捞品占住 %d 个货位（实际 %s）" % [n_buy, str(st.salvage_slots)])
	_expect(String((st.offers[0] as Dictionary).get("ship_key", "")) == first_key,
			"0 号货位就是下单的那艘（%s）" % first_key)

	# ★ 付费刷新刷不掉它
	st.coin = 50
	st.refresh()
	_expect(String((st.offers[0] as Dictionary).get("ship_key", "")) == first_key,
			"刷新之后打捞品还在 0 号货位")

	# 卡面必须标出「修复」—— 5 张卡长得一样的话，玩家找不到自己花钱下的单
	hud.call("set_shop_offers", st.offers)
	var ws: Array = shop.get("_card_widgets")
	var label := (ws[0]["name"] as Label).text
	_expect(label.begins_with("修复"), "0 号卡面标出「修复」（实际「%s」）" % label)
	# ★ 价格格必须**留空**（2026-10-06 二改：用户不喜欢「已付」两个字）。
	#   ⚠️ 断言写成 `== ""` 而不是「不等于 1」：要钉的是**确实没有内容**，
	#     而不是「碰巧没写数字」—— 后者放任何别的文字进来都能过。
	var price_txt := (ws[0]["cost"] as Label).text
	_expect(price_txt == "",
			"★★ 打捞品价格格留空（实际「%s」）—— 既不写「已付」也不写数字"
			% price_txt)
	print("[打捞到账] 节点 %d 就占住 %d 个货位 · 卡面「%s」/ 价格格空 · 刷新刷不掉"
			% [st.node_index, n_buy, label])


## 买走 → 该货位解锁（**买走一个解锁一个**，不是全解锁）。
func _step_salvage_buy() -> void:
	var st := _run()
	var hud = _battle.get("hud")
	var shop = hud.get("shop_window")

	# ⚠️ 2026-10-05：**不再 `bench.clear()`**！
	#    原来这里清空备战席再买 —— 那是「验买走 → 解锁」的简写，
	#    但它掩盖了「备战席本来就有船时买打捞品」这条**真实路径**
	#    （用户实机就是带着几艘船去买的）。清空后一切正常、实机却不进席，
	#    正是这类「验收比真实场景干净」造成的盲区。
	var bench_before := st.bench.size()
	_expect(bench_before > 0,
			"前置：备战席本来就有 %d 艘（真实场景是带着船买打捞品）" % bench_before)
	st.coin = 50

	# ★★ 2026-10-06 用户口径：**打捞品取货不再收费**（治「双重扣费」）。
	#   打捞费已在结算页付清，到货后这一步只是把货从货位上拿走。
	#   ⚠️ 这条断言必须**盯住钱数**：只断言「船进了备战席」的话，
	#     重复扣费照样能通过（2026-10-05 那次就是这么漏的）。
	var coin_before: int = st.coin
	var offers_before = st.offers[0]
	_expect(offers_before is Dictionary and (offers_before as Dictionary).has("from_node"),
			"前置：0 号位确实是打捞品（带 from_node 标记）")

	# ★ 走**真实 UI 通道**：模拟玩家点第 0 张卡（不是直接调 run.buy）
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	shop.call("_on_card_input", ev, 0)

	_expect(st.coin == coin_before,
			"★★ 点打捞品 ⇒ **一个星币都不扣**（%d → %d）—— 双重扣费钉死在这里"
			% [coin_before, st.coin])
	_expect(st.bench.size() == bench_before + 1,
			"★★ 点卡片 ⇒ 打捞品**真的进了备战席**（%d → %d）"
			% [bench_before, st.bench.size()])
	_expect(not st.salvage_slots.has(0),
			"★ 买走的那个货位已解锁（实际占位 %s）" % str(st.salvage_slots))
	# 备战席里那一条必须**是打捞的那艘**，且表里查得到
	var added_key := StringName("")
	var added_star := 0
	if st.bench.size() > bench_before:
		var e: Dictionary = st.bench[st.bench.size() - 1]
		added_key = StringName(e.get("ship_key", &""))
		added_star = int(e.get("star", 1))
	_expect(added_key != StringName(""),
			"★★ 新进备战席那艘 ship_key 非空（实际「%s」）" % String(added_key))
	_expect(not EveShipDatabase.by_id(String(added_key)).is_empty(),
			"★★ 它在舰船表里查得到（%s）—— 否则备战席画不出来" % String(added_key))

	# ★ 反面：**普通报价必须照旧收费** —— 别把「打捞品免费」做成了「全场免费」。
	#   这类「过度修复」是免费改动的常见事故：修好一处、顺手免掉了整片。
	var normal_idx := -1
	for i in st.offers.size():
		var o = st.offers[i]
		if o is Dictionary and not (o as Dictionary).is_empty() \
				and not (o as Dictionary).has("from_node"):
			normal_idx = i
			break
	if normal_idx >= 0:
		var coin_n: int = st.coin
		var cost_n := int((st.offers[normal_idx] as Dictionary).get("cost", 0))
		st.buy(normal_idx)
		_expect(st.coin == coin_n - cost_n,
				"★★ 普通报价**照旧收费**（%d → %d，应扣 %d）"
				% [coin_n, st.coin, cost_n])
	else:
		_expect(false, "★ 找不到普通报价来测「照旧收费」（前置不成立）")
	# ★★ HUD 侧：备战席**画面**必须真的重绘出新数量。
	#    ⚠️ 原来这里写的是 `hud.call("bench_used")` —— 而 HUD **根本没有这个方法**，
	#    `has_method` 判假 ⇒ 整条断言被静默跳过（等于没测）。
	#    「写了一条永远不执行的断言」比没有断言更坏：它给人一种验过的错觉。
	#    ⇒ 改成读**画面侧的真实数据**：`bench_rail.fleet`（备战席轨道持有的名单）。
	var rail = hud.get("bench_rail")
	_expect(rail != null, "备战席轨道存在（画面侧对象）")
	var rail_fleet: Array = rail.get("fleet") if rail != null else []
	_expect(rail_fleet.size() == st.bench.size(),
			"★★ 备战席**画面**读到的船数 == 数据层（画面 %d / 数据 %d）"
			% [rail_fleet.size(), st.bench.size()])
	var rail_has_key := false
	for e in rail_fleet:
		if e is Dictionary and StringName((e as Dictionary).get("ship_key", &"")) == added_key:
			rail_has_key = true
			break
	_expect(rail_has_key,
			"★★ 备战席**画面**里真的出现了 %s 那一艘" % String(added_key))
	var after = st.offers[0]
	_expect(not (after is Dictionary and (after as Dictionary).has("from_node")),
			"解锁后 0 号位回到普通报价")
	print("[打捞收尾] 点卡片买入 → 备战席 %d → %d（新增 key=%s ★%d）· 货位解锁"
			% [bench_before, st.bench.size(), String(added_key), added_star])


## ══════════════════════════════════════════════════════════════════
##  ★★ 战斗时限归零 ⇒ 判负（2026-10-04 用户口径恢复）
## ══════════════════════════════════════════════════════════════════
##
## 用户原话：「在我们的设计里面，归零是该直接判负并扣除信标HP的，惩罚很严重的。」
##
## ⚠️ 放在链条**末端**：这一步真的会触发结算（弹结算页的 1 秒计时器），
##    插在中间会打乱后续步骤的状态。REQUIRED_STEPS 守卫保证它不被漏跑。
##
## ## 三条必须成立的（缺一条这条链就是假的）
## ##   ① `battle_end_reason` 的 timed_out 分支 —— 结算页要显示「时限耗尽」，
## ##      而不是笼统的「我方全灭」；
## ##   ② BATTLE 阶段触发 `_on_stage_timer_expired()` ⇒ 判负
## ##      （phase → RESOLVE、模拟器停转、`_timeout_forfeit` 置位）；
## ##   ③ 扣信标走的是**既有战败路径** —— 归零判负与「打输」扣的血必须是
## ##      同一个公式（⛔ 不许有第二份真相源）。
func _step_timer_forfeit() -> void:
	# ── ① 纯函数：timed_out 分支 ──
	_expect(BATTLE_SCRIPT.battle_end_reason(false, 2, 1, true) == "时限耗尽",
			"★ timed_out=true ⇒ 结算原因 =「时限耗尽」（实际「%s」）"
			% BATTLE_SCRIPT.battle_end_reason(false, 2, 1, true))
	# 未部署优先于超时（PREP 归零是另一条路，不能被盖掉）
	_expect(BATTLE_SCRIPT.battle_end_reason(true, 5, 0, true) == "未部署",
			"own_empty 优先于 timed_out（实际「%s」）"
			% BATTLE_SCRIPT.battle_end_reason(true, 5, 0, true))
	# 不传 timed_out（旧调用形态）不受影响 —— 兼容旧验收
	_expect(BATTLE_SCRIPT.battle_end_reason(false, 2, 1) != "时限耗尽",
			"不传 timed_out 时不误报「时限耗尽」（实际「%s」）"
			% BATTLE_SCRIPT.battle_end_reason(false, 2, 1))

	# ── ② 实测：BATTLE 阶段归零 → 判负 ──
	var st := _run()
	var hud = _battle.get("hud")
	st.set_phase(EveRunState.Phase.PREP)
	_battle.call("start_battle")
	_expect(st.phase == EveRunState.Phase.BATTLE, "前置：已进入战斗阶段")
	_battle.set("_timeout_forfeit", false)

	var beacon_before: int = st.beacon
	# ★ 走真实信号通道：command_bar 归零 → hud.stage_timer_expired → 主控
	hud.get("command_bar").call("tick", float(st.battle_seconds()) + 0.5)
	_expect(bool(_battle.get("_timeout_forfeit")),
			"★ 归零 ⇒ `_timeout_forfeit` 置位（判负已启动）")
	_expect(st.phase == EveRunState.Phase.RESOLVE,
			"★ 归零 ⇒ 直接进结算（phase=%d）" % st.phase)
	var sim = _battle.get("sim")
	_expect(sim == null or bool(sim.finished),
			"★ 模拟器已停转（结算页弹出了战斗还在打 = 幽灵战斗）")
	# 真实信号链：command_bar.timer_expired → hud → 主控（接线丢了就全空转）
	_expect(st.beacon < beacon_before or beacon_before <= 0,
			"★ 归零判负**真的扣了信标**（%d → %d）"
			% [beacon_before, st.beacon])
	# ── ③ 商店买卖的阶段闸门（2026-10-05 新增）──
	#  结算阶段商店面板**还摆着**，闸门必须关上 —— 否则玩家点卡片会被
	#  `buy()` 静默拒（卡片毫无变化）⇒ 理解成「买了没到手」。
	var shop2 = hud.get("shop_window")
	_expect(not bool(shop2.get("_buy_enabled")),
			"★ 结算阶段：商店买入闸门已关（_buy_enabled=false）")
	# 闸门关上时，点卡片**不许**派发买入请求
	var got_req := [false]
	var probe := func(_i: int): got_req[0] = true
	shop2.buy_requested.connect(probe)
	var ev2 := InputEventMouseButton.new()
	ev2.button_index = MOUSE_BUTTON_LEFT
	ev2.pressed = true
	shop2.call("_on_card_input", ev2, 0)
	shop2.buy_requested.disconnect(probe)
	_expect(not bool(got_req[0]),
			"★ 结算阶段点卡片 ⇒ **不派发买入请求**（不是发出去被静默拒）")

	print("[时限归零] 判负启动 · phase→RESOLVE · 模拟器停转 · 信标 %d → %d"
			% [beacon_before, st.beacon])
func _finish() -> void:
	# ★ 步骤守卫：任何一步漏跑都点名。
	#   这一步比任何单项断言都重要 —— 漏跑意味着"这条链根本没验"，
	#   而它此前**完全不报错**（见 REQUIRED_STEPS 的说明）。
	var missing: Array = []
	for step_name in REQUIRED_STEPS:
		if not _ran_steps.has(step_name):
			missing.append(step_name)
	_expect(missing.is_empty(),
			"全部 %d 个步骤都已执行（漏跑：%s）"
			% [REQUIRED_STEPS.size(), "无" if missing.is_empty() else str(missing)])

	print("")
	print("═══ 结果：%d 项通过 · %d 项失败 ═══" % [_pass, _fail])
	get_tree().quit(1 if _fail > 0 else 0)

# ══════════════════════════════════════════════════════════════════
#  工具
# ══════════════════════════════════════════════════════════════════

## 音效总开关当前是不是开着的。
## `stats()` 里不带这个字段 ⇒ 直接问音频节点。
## 有它才能把「音频线断了」和「音效被主动关掉」这两件事分开。
func _sfx_on(_stats_dict: Dictionary = {}) -> bool:
	if _battle == null:
		return false
	var a = _battle.get("audio")
	return a != null and bool(a.get("sfx_enabled"))


func _expect(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
		print("  [OK]   %s" % msg)
	else:
		_fail += 1
		print("  [FAIL] %s" % msg)


## 先执行下一步的逻辑，**再**截图。
##
## ⚠️⚠️ 顺序不能反过来（这里是踩过一个大坑的）：
##     `_shot()` 里有 `await RenderingServer.frame_post_draw` —— 一旦它排在
##     `next.call()` **前面**，`_shot_and` 就变成协程，会在 await 处让出控制权：
##     本次 `_process` 的 match 分支随即走完、`_stage` 已自增，等 frame_post_draw
##     到达时 `next.call()` 才恢复执行 —— 那时 `_stage` 早就不是原值了。
##     症状极具迷惑性：某些 `_step_*` **整个不执行**（连 print 都没有），
##     而它前后两步的断言却照常输出，看起来像"函数内部 return 了"。
##     stage D 的 `_step_d_hit()` 是同步重负载（快进 12 秒），改变了帧节奏，
##     把这个潜伏缺陷引爆（此前一直靠"帧数刚好够"蒙过去）。
##     修法 = 回调先行、截图后置 ⇒ 回调始终在同步上下文里跑。
func _shot_and(path: String, next: Callable) -> void:
	# 记名：`next` 是方法引用，拿不到函数名，所以由调用点显式登记。
	# ⚠️ 不登记的话 `_finish()` 的步骤守卫会误报这些步骤"漏跑"（假警报）。
	_ran_steps[_step_label(next)] = true
	next.call()
	await _shot(path, "")


## `_shot_and` 的记名用：方法引用 → 步骤名。
## GDScript 拿不到 Callable 的函数名，所以走一张反查表（在 `_dispatch` 里维护）。
func _step_label(fn: Callable) -> String:
	for step_name in STEP_CALLABLES:
		if STEP_CALLABLES[step_name] == fn:
			return step_name
	return str(fn)


func _shot(path: String, note: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img == null:
		push_error("截图失败")
		return
	var err := img.save_png(path)
	if err != OK:
		push_error("保存失败 %d" % err)
		return
	print("[截图] %s %s" % [note, ProjectSettings.globalize_path(path)])

# ══════════════════════════════════════════════════════════════════
#  阶段 D：舰船朝向
# ══════════════════════════════════════════════════════════════════

## D1：舰船 3D 模型朝向修正表自检
##
## ⚠️ 这张表错了**不会报错** —— 船只是在棋盘上倒着飞 / 斜着飞，
##    而尺寸、血条、位置、数值全都正常（用户实测磨难级才发现）。
##    所以必须有断言把它钉住。
##
## 断言四件：
##   ① 表结构自洽（validate：名单不重叠 / id 在名册里 / 偏角在 ±90° 内 / 全船覆盖 /
##      AXIS_REMAP 必须是旋转且第三轴 = 舰艏×船背）
##   ② **口径锚点** —— 三份名单各取代表，把最终偏航角逐艘算出来，
##      防「后人改名单或改数值」时无人察觉
##   ③ 名单规模 = 19 翻转 / 0 待定
##      （2026-09-23：原 7 艘待定由用户在交互式标定台裁定，落进 AXIS_REMAP，PENDING 清空；
##       2026-09-26：**FLIP 整份重建** 24 → 18 → 20；第五轮 `myrmidon` 移出 → **19**）
##   ④ **重映射锚点** —— M 必须把「舰艏」搬到世界 +X、**「船背」搬到世界 +Y**：
##      catalyst 舰艏 = 模型 −X、船背 = 模型 **+Z**（2026-09-26 四轮改正）
##      kestrel  舰艏 = 模型 +Y
##      myrmidon 舰艏 = 模型 +X、船背 = 模型 **+Y**（2026-09-26 四轮改正）
##      ⚠️ 第五轮：myrmidon 的 180° **不再走 FLIP** —— 它 `AXIS_REMAP` 第一行已声明
##         舰艏在模型 +X，那 180° 是多余的（详见 `eve_ship_yaw.gd` 里的证据块）。
##
## ⚠️ 2026-09-26 第四轮（`catalyst` / `myrmidon`）—— **真正的根因在这一轮才找到**：
##    前几轮（我和用户）都只在「180° / yaw」这个自由度里找答案，但两艘船的病根其实是
##    **`AXIS_REMAP` 的「船背」那一行指到了水平轴上** ⇒ 船在世界坐标里是**侧躺**的。
##    症状：俯视看到的是「高的那一面」、正侧看到的是「船顶面」 —— 用户原话
##    「下面一排第三幅图，**如果是俯视图，那标注就是正确的**」正是这个症状。
##    ⇒ 也解释了为什么「yaw 四选一」四格全否：**转圈修不了滚转**。
##
##    定案证据（三条独立）：
##      ① `sym_test2.py` 全库镜像对称：52 艘里 50 艘都是「横向=Z / 长=X / 上=Y」，
##         只有 `catalyst`（横向=Y 上=Z）与 `slasher`（横向=X 上=Z）离群。
##         ⚠️ 24 轮更新：`slasher` 现 spec `-Y,+Z,-X`（随 kestrel 翻案）⇒ 与 catalyst
##         同为「离群但已被 M 扶正」—— 「离群」不等于「错」，看 M 有没有扶正。
##      ② `_ship3d/<id>/ship.json` 的 `dims_raw` × glb 实测 ⇒ 反解**导出置换**：
##         44 艘走主流 `ZYX`（glb = 源z, 源y, 源x），由这批已确认正确的船确立
##         **「源 y 的正方向 = 上」**；而 catalyst 走 `XZY`、myrmidon 走 `YZX`：
##           · catalyst  XZY ⇒ glb (284.1, 88.6, 73.0) ⇒ glb Z = +源y ⇒ **上轴 = glb Z**
##           · myrmidon  YZX ⇒ glb (601.3, 310.6, 138.4) ⇒ **长X/上Y/宽Z = 主流姿态**
##      ③ 用户连续两轮的口述（"躺着的船，正侧看起来像俯视"）。
##
##    修正（**只动「船背」「侧向」两行，第一行一个字不碰** ⇒ 180° 语义不变、
##    `FLIP` 名单不受影响、② 的两条锚点照旧）：
##      catalyst  `"-X,+Y,-Z"` → `"-X,+Z,+Y"`   AXIS_DEG  `+0.06`  → `−1.63`
##      myrmidon  `"+X,+Z,-Y"` → `"+X,+Y,+Z"`   AXIS_DEG  `+10.41` → `+0.02`
##      ⚠️ AXIS_DEG 必须重算：残差是在「舰艏轴 × 侧向轴」平面上量的，换了 M 就换了平面。
##
##    前情（第三轮，结论仍成立）：两艘都**不是**「翻一下」能解决的 ——
##    那 7 艘用户说的是「一百八十度转一下就对了」，这两艘他说的是
##    「正视图相当特殊…得特殊处理」，**没说方向**。措辞里的差别是有信息的。
##    第三轮据此把 `myrmidon` 放进 FLIP、`catalyst` 移出 FLIP；
##    ⚠️ **第五轮再纠正**：`myrmidon` 那一步也是错的（同样属于「M 已含 180°」）⇒ 两艘现都在
##       `FLIP_REMOVED_20260926`。第三轮唯一站得住的只有「措辞有信息」这条方法论。
##    ⚠️ **教训**：`AXIS_REMAP` 第一行**和** `FLIP` 是同一个 180° 自由度的两种表达
##       （`M_new = R_y(180°)·M_old`）。一艘船的 180° 只许在一处表达 —— 判断前先查
##       `AXIS_REMAP` 里有没有 `-X` 之类「反向」声明。
##
## ⚠️ 2026-09-26 **FLIP 整份重建（24 → 18 条）**：旧名单是**真值的补集** ——
##    用户当年是对着 `yaw_sheet.png` 上那支**画反了的**「前方 →」箭头逐格判的
##    （判据「船头朝右的算对」，而实测 +Z 投在屏幕**左侧**）。
##    新判据 = `_e` 自发光贴图里「法线平行于舰艏轴」的自发光面聚在哪一端（那一端就是船尾）；
##    52 艘判得動 44，重建后与本表**零分歧**。证据全文：
##    `F:\evezzq\接手手册-2026-09-24\09_朝向问题盘点-2026-09-26.md`。
##    ⚠️ 因此下面 ② 里 abaddon / algos 两条锚点的「翻 / 不翻」是**互换过**的 —— 不是笔误。
func _t_ship_yaw() -> void:
	# ★ 47 轮：**先注入 `mesh_rot` provider，再 validate()**。
	#   `validate()` 的 ⑧⑨ 两条要算「模型轴 → 世界」的端到端方向，必须知道
	#   `mesh_rot`（glb 内层网格自带旋转）。它的提供者是 `EveShipVisual.mesh_rot_of`，
	#   而那是一个**懒注入**（首次被调用时才把 provider 交给 `EveShipYawTable`）。
	#   ⇒ 若不在这里先踢一脚，`validate()` 会在 provider 还没装上时运行 ⇒
	#     退化成"单位阵口径" ⇒ 全库 52 艘齐刷刷报"侧向飞"（**假失败**，实测踩过）。
	#   ⚠️ 这就是"隐式时序依赖"：**跑的顺序不同，结论不同** ——
	#      所以必须显式、且必须排在 validate 之前（不是"顺手先调用一下"）。
	_ZP_SCRIPT.call("mesh_rot_of", &"abaddon")
	# ★ 50 轮（红线 50c）：**再注入「几何机身长轴」provider**。
	#   `validate()` 的 ⑩ 条要判「`SHIP_AXES.bow` 是否真的平行于几何长轴」——
	#   这是唯一能抓住「表把舰艏标在横向轴上」的护栏（实机症状：横着飞/倒着飞，
	#   而 ①~⑨ 条**全部放行**，因为表内部自洽、长轴也确实在水平面内）。
	#   几何长轴来自 glb 的 AABB 最长边经 `mesh_rot` —— 与任何表无关（红线 50a）。
	EveShipYawTable.set_geo_long_provider(
			func(id: StringName) -> Vector3: return _geo_long_root(id))
	var problems := EveShipYawTable.validate()
	_expect(_mesh_rot_injected(), "47 轮：`mesh_rot` provider 已注入（否则 ⑧⑨ 会退回单位阵口径 ⇒ 假失败）")
	_expect(problems.is_empty(), "朝向修正表自检通过（%s）" % str(problems))

	# ②b ★ 红线 47：语义轴（bow / up）必须**逐艘登记**，不许再有"隐式默认值"
	#     22 轮之前 `BOW_AXIS` 是稀疏表 + 默认 +X ⇒ 51 艘**从未被真正标定**，
	#     新船一旦长轴 ≠ 舰艏轴就静默倒飞且**零报错**。这里把漏填变成硬失败。
	var missing: PackedStringArray = []
	for ship in EveShipAssetIndex.all():
		if not EveShipYawTable.SHIP_AXES.has(StringName(ship.id)):
			missing.append(String(ship.id))
	_expect(missing.is_empty(), "语义轴表覆盖全部 %d 艘（**漏登记的：%s**）"
			% [EveShipAssetIndex.EXPECTED_COUNT, str(missing)])
	_expect(EveShipYawTable.SHIP_AXES.size() == EveShipAssetIndex.EXPECTED_COUNT,
			"语义轴表无多余条目（%d 条 / 全船 %d 艘）"
			% [EveShipYawTable.SHIP_AXES.size(), EveShipAssetIndex.EXPECTED_COUNT])

	# ②c 语义轴口径锚点 —— 防后人把这两条改回去
	# ⚠️ 2026-09-27 第四十三轮 e（**用户裁决：以用户姿势表为最高真值**）：
	#   用户在「舰船建模方向姿势确认工具」里逐艘标定了 52 艘的 bow/up，全部落盘。
	#   用户在 43c 明确裁定：**「再遇到类似问题就直接修改既有语义，以我为准」**
	#   ⇒ 下面这些锚点从"旧 AI 语义"改成"用户标定语义"。**旧值一律作废。**
	#   用户标定的第一条规律：**舰艏不再是模型的 +X**（`abaddon` 用户标 bow=+Z），
	#   因为用户在工具里看到的参照系与 AI 早年的 PCA 判据不同。
	#   ⚠️ 别再拿"主流船 bow 应该 = +X"当锚点 —— 那是被本轮推翻的旧口径。
	# ⚠️⚠️ **2026-09-28 第十三版：全库 48 艘批量翻 up（+Y → −Y），锚点同步** ⚠️⚠️
	#   用户目视判读：48 轮 ±Z 旧表里"up=+Y"的语义被标定者搞反了 —
	#   `+Y` 那端在 EVE 模型里其实是**腹部**（光滑面），不是船背。
	#   ⇒ 全库 48 艘 `up:+Y → up:-Y` 批翻。
	#   ⇒ 这只是**语义符号翻号**（不绕 bow 轴），`AXIS_REMAP` 的 M
	#     由 `EveShipVisual._make_align(mesh_rot·bow, mesh_rot·up)`
	#     重新反解（48 艘全部唯一解，0 无解 / 0 多解）。
	#   ⇒ 4 艘离群（algos/catalyst/myrmidon/tristan）的 up 原本就不是 +Y，不参与翻转。
	# ⚠️⚠️ **2026-09-28 第二十五版：用户实机确认「全库都朝 +Z，必须全部朝 −Z」** ⚠️⚠️
	#   上一版（第二十四版）把「X+为左」按字面当成「世界 +X」⇒ 全库 bow 反到 +Z，用户实机确认是错的。
	#   ⇒ 实测确认符号：**目视「左」= 世界 −X**。
	#   ⇒ 按此重推，**全库 52 艘收敛到同一个答案：`bow:−Z up:−Y`**
	#     （用户原本要求的「舰艏朝前 + 腹部朝下」）。
	#   ⇒ 枚举验算 52/52 唯一解、0 无解。
	_expect(EveShipYawTable.bow_axis(&"abaddon") == Vector3(0.0, 0.0, -1.0)
			and EveShipYawTable.up_axis(&"abaddon") == Vector3(0.0, -1.0, 0.0),
			"全库统一：abaddon bow=−Z / up=−Y（实际 %s / %s）"
			% [str(EveShipYawTable.bow_axis(&"abaddon")), str(EveShipYawTable.up_axis(&"abaddon"))])
	_expect(EveShipYawTable.bow_axis(&"tristan") == Vector3(0.0, 0.0, -1.0)
			and EveShipYawTable.up_axis(&"tristan") == Vector3(0.0, -1.0, 0.0),
			"全库统一：tristan bow=−Z / up=−Y（实际 %s / %s）"
			% [str(EveShipYawTable.bow_axis(&"tristan")), str(EveShipYawTable.up_axis(&"tristan"))])
	_expect(EveShipYawTable.up_axis(&"algos") == Vector3(0.0, -1.0, 0.0)
			and EveShipYawTable.up_axis(&"catalyst") == Vector3(0.0, -1.0, 0.0),
			"全库统一：algos up=−Y / catalyst up=−Y（实际 %s / %s）"
			% [str(EveShipYawTable.up_axis(&"algos")), str(EveShipYawTable.up_axis(&"catalyst"))])

	# ②d ★★ 舰船体型刻度（用户 2026-09-28 定案）★★
	#    「以现在暴君级为最大、因卡萨斯级为最小，中间分 10 级：
	#      护卫=1、驱逐=3、巡洋=6、战巡=8、战列=10」
	#    ＋ 档内按真实长轴微调（±5%；上限由「战巡/战列」那对几何决定 = 5.66%）
	#    ⚠️ 防回归的**两条**重点：
	#      ① 战巡 / 战列 必须**有分支** —— 旧表只有 3 档，它们掉进 `_` 默认 1.0
	#         ⇒ 巡洋(1.35) 比战列(1.00) 还大（用户原话「暴君级比所有船都大」）；
	#      ② 相邻档的实测区间**不许重叠**（同档内微调不得吃掉吨位序）。
	_expect(EveShipVisual.tier_level(EveShip.Class.FRIGATE) == 1
			and EveShipVisual.tier_level(EveShip.Class.DESTROYER) == 3
			and EveShipVisual.tier_level(EveShip.Class.CRUISER) == 6
			and EveShipVisual.tier_level(EveShip.Class.BATTLE_CRUISER) == 8
			and EveShipVisual.tier_level(EveShip.Class.BATTLESHIP) == 10,
			"体型 10 级刻度：护卫1 / 驱逐3 / 巡洋6 / 战巡8 / 战列10")
	_expect(is_equal_approx(EveShipVisual.tier_base_length(EveShip.Class.FRIGATE), 2.184)
			and is_equal_approx(EveShipVisual.tier_base_length(EveShip.Class.BATTLESHIP), 4.212),
			"体型锚点：等级1=2.184（因卡萨斯）/ 等级10=4.212（暴君）")
	var cls_ladder := [EveShip.Class.FRIGATE, EveShip.Class.DESTROYER, EveShip.Class.CRUISER,
			EveShip.Class.BATTLE_CRUISER, EveShip.Class.BATTLESHIP]
	var s_spread: float = EveShipVisual.CLASS_SCALE_SPREAD
	var overlaps := []
	for i in range(0, 4):
		var hi: float = EveShipVisual.tier_base_length(cls_ladder[i]) * (1.0 + s_spread)
		var lo: float = EveShipVisual.tier_base_length(cls_ladder[i + 1]) * (1.0 - s_spread)
		if hi > lo:
			overlaps.append("档%d/档%d 叠 %.3f" % [i, i + 1, hi - lo])
	_expect(overlaps.is_empty(), "体型相邻档不重叠（S=%.2f；几何上限 5.66%%）—— %s"
			% [s_spread, "OK" if overlaps.is_empty() else str(overlaps)])
	_expect(EveShipVisual.target_hull_length(&"maller", EveShip.Class.CRUISER)
			< EveShipVisual.target_hull_length(&"apocalypse", EveShip.Class.BATTLESHIP),
			"暴君（巡洋 %.3f）必须小于灾难（战列 %.3f）—— 旧表里暴君是全库最大"
			% [EveShipVisual.target_hull_length(&"maller", EveShip.Class.CRUISER),
				EveShipVisual.target_hull_length(&"apocalypse", EveShip.Class.BATTLESHIP)])
	_expect(EveShipVisual.target_hull_length(&"slasher", EveShip.Class.FRIGATE)
			> EveShipVisual.target_hull_length(&"punisher", EveShip.Class.FRIGATE),
			"档内按真实长轴微调：伐木者(172m) > 惩罚者(66m)（实际 %.3f / %.3f）"
			% [EveShipVisual.target_hull_length(&"slasher", EveShip.Class.FRIGATE),
				EveShipVisual.target_hull_length(&"punisher", EveShip.Class.FRIGATE)])
	# 侧向轴 = bow × up（右手系），全库不得出现退化（零向量 = 两轴共线）
	var degenerate: PackedStringArray = []
	for ship2 in EveShipAssetIndex.all():
		var sid := StringName(ship2.id)
		var sd := EveShipYawTable.side_axis(sid)
		if sd.length() < 0.99:
			degenerate.append(String(sid))
	_expect(degenerate.is_empty(), "侧向轴 bow×up 全库非退化（退化的：%s）" % str(degenerate))

	# ② 锚点：extra_yaw() 不含 MODEL_YAW_FIX，
	#    所以翻转船的期望值 ≈ π（+ 它自己的主轴补偿 θ），保持船的期望值就是 θ。
	#
	# ⚠️ 2026-09-26：下面这两条锚点的「翻 / 不翻」**互换了** ——
	#   旧 FLIP 名单是「真值的补集」（用户当年对着画反了的「前方 →」箭头逐格判的），
	#   按 `_e` 自发光判据重建后：abaddon 从「翻」变「不翻」、algos 从「不翻」变「翻」。
	#   两艘都属于**判得動且信号极强**的那一档（abaddon 676 个喷口面 / algos 52 个），
	#   所以拿它们当口径锚点最能防「后人又把名单改回去」。
	#
	# ⚠️ 2026-09-26 第二十轮：`algos` **从 FLIP 移除** —— 与 catalyst / myrmidon 同病。
	#   algos 的 `AXIS_REMAP = "-X,+Z,+Y"` 第一行 `−X` 已含一次 180°（红线 27：180° 只许在一处表达）；
	#   再叠 FLIP 会**抵消**成倒飞。`algos` 当前 dot(−Z) = +1.0 = 朝敌 ✓。
	#   同步把 FLIP 名单从 19 减到 18。
	_expect(absf(EveShipYawTable.extra_yaw(&"abaddon")) < deg_to_rad(0.5),
			"地狱天使级 = 保持不动（只留主轴残差 −0.05°，实际 %.1f°）"
			% rad_to_deg(EveShipYawTable.extra_yaw(&"abaddon")))
	_expect(absf(EveShipYawTable.extra_yaw(&"algos")) < deg_to_rad(0.5),
			"阿尔格斯级 = 不再额外翻转（180° 已在 AXIS_REMAP 的 -X 行里，实际 %.2f°）"
			% rad_to_deg(EveShipYawTable.extra_yaw(&"algos")))
	# ⚠️ 2026-09-26 二次复核：`condor` 的锚点从 +88.64° 改成 0°。
	#   依据① 用户逐艘复核时的判读：「小鹰级弄错舰艏，应逆时针旋转 90 度」
	#        （= 把 +88.64 去掉，正是转 90°）；
	#   依据② 两条**独立**判据全库重测：
	#        · `nozzle_axis.py`（有向喷口法线反解真轴）：120 个面、集中度 1.000、δ = +0.00°
	#        · `sym_audit.py`（俯视轮廓镜像 IoU）：对称度 0.90、需修 −88.80°
	#   两判据在对照组（rifter / hyperion / apocalypse）上都给 |δ| < 0.05° ⇒ 可信。
	#   而 PCA 的 +88.64° 是**近正方投影噪声**（它的 XZ 投影 76.28×76.06 几乎是正方形）。
	_expect(absf(EveShipYawTable.extra_yaw(&"condor")) < deg_to_rad(0.001),
			"小鹰级 = 主轴残差 0°（实际 %.2f°）—— PCA 的 +88.64° 是近正方投影噪声"
			% rad_to_deg(EveShipYawTable.extra_yaw(&"condor")))
	# 2026-09-26 新增锚点：`raven` 的 +75.69° 同样是 PCA 伪影，旧值让乌鸦级
	# 在棋盘上**一直横躺着**（俯视图里船身横置）。两判据都指向 ≈0。
	_expect(absf(EveShipYawTable.extra_yaw(&"raven")) < deg_to_rad(0.001),
			"乌鸦级 = 主轴残差 0°（实际 %.2f°）—— 旧值 +75.69° 是 PCA 伪影、会横躺"
			% rad_to_deg(EveShipYawTable.extra_yaw(&"raven")))
	# 2026-09-26 新增锚点：`burst` 的 −7.85° 是形状噪声。
	#  ⚠️ 这条与用户判读「爆发级舰艏略歪，应顺时针旋转一点」**同向**：
	#    新值 0° 相对旧值 −7.85° 正是「顺时针 7.85°」。
	#  ⚠️ `burst` **本身在 FLIP 里**，所以 extra_yaw = 残差 0° + 翻转 180°。
	#    这里断言的是「主轴残差那部分已经归零」（把 FLIP 的 π 减掉再比）。
	# ⚠️ 2026-09-27 第四十三轮 e：`burst` 已不在 FLIP ⇒ 不再 +180°，直接断言 0°。
	_expect(absf(EveShipYawTable.extra_yaw(&"burst")) < deg_to_rad(0.001),
			"爆发级 = 主轴残差 0°、无翻转（实际 %.2f°）—— PCA 的 −7.85° 是形状噪声"
			% rad_to_deg(EveShipYawTable.extra_yaw(&"burst")))
	# ⚠️ 2026-09-26 **第五轮：`myrmidon` 改了 —— 它必须留在 FLIP 之外**。
	#   前几轮的判词（"确定要翻"）**已被推翻**，别再翻回来：
	#    · 旧理由（第三轮）：自发光法线和判据给 +15.5 ⇒ 判「喷口朝 +Z ⇒ 倒飞」。
	#      ⚠️ 那条判据正是「`FLIP` 名单整体取反」的同一族 —— 它给的是真值的**补集**；
	#      而且本船 `_e` **两端都有**轴向发光面 ⇒ 旧判据会自相抵消。**双重不可信。**
	#    · 新证据（用户 6 张 EVE 实机权威图 + 模型沿长轴 Z 展宽剖面，单位 = glb 原始）：
	#        X −300→−240 : 12 15 35    · −210→−60 : 52 136 138 138 127 73
	#        X  −30→+90  : 71 50 18 16 ·  +90→+300 : 56 18 … 31 29 23 16
	#      ⇒ 宽翼（Z>100）落在 X≈−200…−70，只占 −X 端往里 165 单位 = 全长 27%；
	#        +X 端要往里 436 单位（73%）才到宽翼 ⇒ **+X 端是长约全长 45% 的细长段**。
	#      ⇒ **舰艏 = 模型 +X**，与 `AXIS_REMAP` 第一行**声明一致** ⇒ 那 180° 是多余的。
	#    · 用户图逐项对得上：`俯视图`（舰艏在下）上端"引擎口"窄段仅 ~18% 就进宽翼；
	#      `仰视图` 宽翼在上 18~46%、下面 ~50% 是细长段。
	#    · 代入算式：`FLIP=false` ⇒ `yaw = −89.98°` ⇒ `R_y(−89.98)·(+X) ≈ +Z` ✅ 舰艏朝红球。
	#    · **第七轮**：`AXIS_DEG` 改为 **0.0** —— 长轴已竖直 ⇒ `yaw` 退化成"绕长轴"，PCA 残差不适用（见 ④）。
	#    ⚠️ **第十二轮**：舰艏已定为朝世界 **+Y**（竖直向上 = 朝向敌人）⇒ 上面那句「朝红球 +Z」的
	#       验算口径**只对水平姿态成立**，本船现在不适用；现行锚点是下面 ④ 的那一条。
	_expect(absf(EveShipYawTable.extra_yaw(&"myrmidon")) < 0.001,
			"弥尔米顿级 = 不翻转、无残差（实际 %.2f°）"
			% rad_to_deg(EveShipYawTable.extra_yaw(&"myrmidon")))
	_expect(not (EveShipYawTable.FLIP.has("myrmidon")),
			"弥尔米顿 = 不翻转（长轴竖直 ⇒ 那 180° 全部由 AXIS_REMAP 表达；再加 FLIP 会把它倒飞）")
	# ⚠️ 2026-09-26 第三轮：`catalyst` **必须留在 FLIP 之外**（本轮从名单里移除）。
	#   它自己的 `AXIS_REMAP = "-X,+Y,-Z"` 声明舰艏在模型 −X，代入算式验算：
	#     M = [[-1,0,0],[0,1,0],[0,0,-1]] ⇒ M·(-1,0,0) = +X（声明合法，下面 ④ 有锚点）
	#     FLIP=false ⇒ yaw = -89.94° ⇒ R_y(-89.94)·(+X) ≈ (+0.001, 0, +1) = **+Z** ✅
	#     FLIP=true  ⇒ yaw = +90.06° ⇒ R_y(+90.06)·(+X) = (0, 0, -1) = **−Z** ❌
	#   ⇒ 不许把它加回来。它的 `_e` 是空的（thr=0.15 只亮 0.04%、法线和恒为 0.000）
	#     ⇒ 没有第二条判据能兜底，只能靠上面这条算式 + 用户裁决。
	_expect(not (EveShipYawTable.FLIP.has("catalyst")),
			"促进级 = 不翻转（它的 AXIS_REMAP 已含 180°；再加 FLIP 会抵消成倒飞）")
	_expect(absf(EveShipYawTable.extra_yaw(&"tristan")) < deg_to_rad(0.001),
			"特里斯坦级 = 残差 0°（旧 −52.44° 是 XZ 平面口径，重映射后作废；实际 %.2f°）"
			% rad_to_deg(EveShipYawTable.extra_yaw(&"tristan")))

	# ③ 名单规模：7 艘原待定已全部裁定 ⇒ PENDING 清空
	#   ⚠️ 2026-09-26 五轮下来：**19 条**
	#      = 15（判据明确要求）
	#      + harbinger / inquisitor / vexor / scythe（第一轮用户逐艘复核追加）
	#      + myrmidon（第三轮误加）
	#      − catalyst（第一轮我误加，第三轮移除：它的 AXIS_REMAP 已含那 180°）
	#      − myrmidon（**第五轮移除**：同 catalyst 一类病，用户 6 张实机图为证）
	#   ⚠️ 别再退回 18 —— 那是「omen/thorax 无判据按原样保留」的旧版，
	#      用户已明确判读 omen/thorax/osprey「弄反了」⇒ 三条全部移出（见 FLIP_REMOVED_20260926）。
	#   ⚠️ `catalyst` 与 `myrmidon` 是**同一类病**（AXIS_REMAP 已含 180°，FLIP 再多一份 = 倒飞），
	#      两者都已在 FLIP_REMOVED_20260926 里，别只改一边。
	#
	# ⚠️ 2026-09-26 第二十轮：`algos` 同步移除（红线 27：180° 只许一处表达），
	#   ⇒ FLIP 名单 19 → 18。
	# ⚠️ 2026-09-26 第二十五轮：`inquisitor` 同步移除（用户实机报「倒着飞」，
	#   改 bow:-X 吸收掉那 180°）⇒ FLIP 名单 18 → 17。
	# ⚠️ 2026-09-27 第四十三轮 e：**用户姿势表成为唯一真值**后，全库重解
	#   发现 **不需要任何 FLIP** —— 52 艘的 (bow, up) 都能被纯旋转 `M` 表达，
	#   每艘的 180° 恰好由 `AXIS_REMAP` 的三行符号吸收（红线 27：180° 只许一处）。
	#   ⇒ `FLIP` 清空（17 → 0）。**别再往里加**：任何一艘加回 FLIP 都会瞬间倒飞。
	_expect(EveShipYawTable.FLIP.is_empty() and EveShipYawTable.PENDING.is_empty(),
			"名单 0 翻转 / 0 待定（实际 %d / %d）"
			% [EveShipYawTable.FLIP.size(), EveShipYawTable.PENDING.size()])
	_expect(not EveShipYawTable.is_pending(&"raven")
			and not EveShipYawTable.is_pending(&"rifter")
			and not EveShipYawTable.is_pending(&"abaddon"),
			"待定名单已清空（乌鸦 / 裂谷 / 地狱天使 都不在待定）")

	# ④ 重映射锚点：M·舰艏 = 世界 +X、M·船背 = 世界 +Y（舰艏方向 = 用户人工点选）
	#   ⚠️ 2026-09-26 第四轮：`catalyst` / `myrmidon` 的**「船背」那一行被改正** ——
	#      原来它指到了水平轴上（catalyst 指 +Y、myrmidon 指 +Z）⇒ 船在世界坐标里是
	#      **侧躺**的（俯视看到"高的那一面"、正侧看到"船顶面"）。推导见 `eve_ship_yaw.gd`
	#      里 `AXIS_REMAP` 上方那段（sym_test2 全库扫描 + ship.json 导出置换反解）。
	# ⚠️ 2026-09-27 第四十三轮 e：用户在姿势表里标定 catalyst `bow:+Z up:+X`
	#   ⇒ 重映射必须把「模型 +Z → 前方(−X，经 R_y 后即朝敌)」「模型 +X → 上方(+Y)」。
	#   旧锚点（`−X→前方 / +Z→上方`）是**旧语义**，已随用户裁定作废。
	#
	# ⚠️⚠️ 47 轮更新：断言**口径改为生产算式**（`zero_pose_basis`）。
	#    旧断言读的是 `M * 模型轴`（M 还没算 `R_y`、也没算 `mesh_rot`），
	#    它表达的是"**M 把网格轴送到哪**"；47 轮 M 重算后这个中间量的数值必然变
	#    （那 90° 已吸收进 M，mesh_rot 也被显式乘进来）⇒ 断言整体作废。
	#    真正不变的是**端到端结果**：`zero_pose_basis_no_roll·bow = −Z`、
	#    `zero_pose_basis_no_roll·up = +Y` —— 下面对 catalyst/kestrel/myrmidon 逐艘钉住。
	#
	# ⚠️⚠️ 48 轮：口径再收一层 —— 改用 **`zero_pose_basis_no_roll`**（静态链）。
	#    因为 48 轮按用户裁决加了 **全局滚转 `R_z(180°)`**（修「全库腹朝天」），
	#    它乘在 `zero_pose_basis` 最右 ⇒ `up` 必然从 `+Y` 翻成 `−Y`。
	#    而本条断言的**语义**是「用户标定的静态语义轴被送到 −Z / +Y」——
	#    这是**模型固有语义**，不该被下游的全局修正污染。
	#    ⇒ 静态锚点走 `zero_pose_basis_no_roll`（= 标定真值）；
	#      全局滚转**单独**在 ⑩ 条断言「全库 up 一致地被翻成 −Y」，
	#      这样「滚转有没有生效」「标定有没有漂」两件事**各自可证伪**（红线 40）。
	var zc := _ZP_SCRIPT.call("zero_pose_basis_no_roll", &"catalyst") as Basis
	_expect((zc * EveShipYawTable.bow_axis(&"catalyst")).normalized().distance_to(Vector3(0, 0, -1)) < 0.001
			and (zc * EveShipYawTable.up_axis(&"catalyst")).normalized().distance_to(Vector3.UP) < 0.001,
			"促进级：静态链把用户标定的 bow+Z / up+X 端到端送到 −Z / +Y（用户标定，48 轮口径）")
	# 历史（已被 23 轮推翻，留档防重犯）：20 轮曾把 kestrel 从 `+Y,-Z,-X` 改成 `-X,+Y,-Z`，
	#   理由是"30 艘 away 都走长轴=模型 +X"就强行让它的长轴也归 X ——
	#   **这是错的**：kestrel 长轴/舰艏本来就是模型 +Y，那次改动把舰艏错标在 +X、
	#   还把船背标在与真舰艏共线的 +Y 上 ⇒ 静默倒飞且几何退化，23 轮全盘作废。
	# ⚠️ 2026-09-26 第二十三轮：`kestrel` 定案 `"-Y,+Z,-X"`（用户判 6 宫格：舰艏 = +Y）。
	#   旧 `-X,+Y,-Z` 把舰艏错标在 +X、把船背错标在 +Y（与真舰艏共线）—— 全盘作废。
	#   spec 为**非 diag 型**：手推必须用**行语义**（token i = Basis 第 i 行），
	#   列语义会差一个转置（本次实测翻过车，被 validate 第⑧条 + probe_bow_axis 当场拦下）。
	#   ✅ 船背 +Z **已实机终审**（23 轮末，用户确认茶隼没肚皮朝天）⇒ 推定值升为真值，
	#   备选 "-Y,-Z,+X" 作废（不再需要）。行/列语义的坑留在 `eve_ship_yaw.gd` 表头注释里。
	# ⚠️ 2026-09-27 第四十三轮 e：改按**用户姿势表**（kestrel `bow:+Z up:+Y`）。
	#   模型 +Z → 世界 −X（经 R_y(−90°) 即 −Z 朝敌）；+Y → +Y（船背朝天）；+X → +Z。
	# ⚠️ 47 轮：断言口径同上改为**端到端**；48 轮再收为**静态链**（理由见 catalyst 段）。
	var zk := _ZP_SCRIPT.call("zero_pose_basis_no_roll", &"kestrel") as Basis
	_expect((zk * EveShipYawTable.bow_axis(&"kestrel")).normalized().distance_to(Vector3(0, 0, -1)) < 0.001
			and (zk * EveShipYawTable.up_axis(&"kestrel")).normalized().distance_to(Vector3.UP) < 0.001,
			"茶隼级：静态链端到端把用户标定的 bow+Z / up+Y 送到 −Z / +Y（48 轮口径）")
	# ⚠️ 2026-09-26 第二十四轮：`slasher` 随 kestrel 同款翻案，两者 spec 必须完全相同。
	var ms := EveShipYawTable.axis_remap(&"slasher")
	var mk := EveShipYawTable.axis_remap(&"kestrel")
	_expect(ms == mk,
			"伐木者级重映射：与茶隼级同款（用户标定 bow:+Z up:+Y，实际 %s）" % str(ms))
	# 2026-09-26 **第十二轮（本轮定案，推翻第九轮）**：myrmidon 的 spec = `"+Y,+X,-Z"`。
	#   · 用户 18:59 看**游戏实机图**裁决：「朝向应该朝向敌人，也就是转 180 度，现在是错的」。
	#   · 敌我方向是工程内事实：`eve_battle_arena.gd::deploy_enemy_z = −45`（我方 +45）
	#     ⇒ **敌人方向 = 世界 −Z**；相机在我方背后朝 −Z 看 ⇒ **画面向上 = 敌人方向**。
	#     ⇒ 「朝向敌人」= 舰艏朝世界 **+Y**（画面朝上）。第九轮给的是 −Y（朝下）⇒ 反了。
	#   · 第九轮的错因：它是在**离线六视图**上按「俯/仰不动 + 后视图翻 180°」判的 ——
	#     对着抽象六宫格判方向，漏掉「游戏里哪边是敌人」这个语境。
	#   · 本轮 = `T_new = R_x(180°)·T_old` ⇒ `M_new = R_x(180°)·M_old` ⇒ 逐行读出 `"+Y,+X,-Z"`。
	#     两个合法候选里选它的理由（详见 `eve_ship_yaw.gd` 第十轮注释块）：
	#       · **船背（模型 +Y）必须仍朝向相机** —— 全库所有船都是"相机看船背"；
	#         另一个候选 `"-Y,+X,+Z"` 会把船背翻到 −X ⇒ 玩家看到的是**船肚子**。
	#       · 实拍取证 `_pose3.py`：本候选与原图是同一面（棱角装甲），只是上下颠倒 + 左右镜像
	#         = 画面内真·转 180°；另一候选露出平滑的另一面。
	#   · 净效果：**舰艏（模型 +X）→ 世界 +Y = 节点局部 +Y ⇒ 舰艏朝上、朝向敌人**；
	#     模型 +Z（侧向）→ 世界 +Z（**不动**）。
	# ⚠️⚠️ **第十三轮（2026-09-26 19:30，用户当面纠正 ⇒ 最终定案）**：
	#   `"+Y,+X,-Z"`（`R_x(180°)` 绕**水平轴**翻跟头）→ **`"-Y,+X,+Z"`（`R_z(180°)` 绕**竖直轴**转身）**。
	#   用户原话：「不是整个船身上下颠倒，而是相当于人前后转一样 …… 你这么上下一颠倒，
	#   我们前面做的 6 视图完全不一样了」。两条 spec **都满足下面这条锚点** ⇒
	#   **锚点分不出对错**，只有用户看画面能分；别再拿锚点当"这次一定对"的理由。
	# ⚠️⚠️ **第十四轮（2026-09-26 19:44，用户当面纠正 ⇒ 现行定案）**：`"-Y,+X,+Z"` → **`"-Y,-X,-Z"`**。
	#   · 基准换成**用户认可的参考姿态**（第九轮 `"+Y,-X,+Z"` —— 见 `_ba9` 底排「这个图下面一排
	#     也是对的」/ `_ends9`「这个图是对的」，第十一轮已按它写入 Godot）
	#   · 180° 改走**机身纵轴（模型 X = 舰艏轴）** ⇒ 「人前后转」：舰艏**一个字没动**，
	#     只有「船背」「侧向」两轴翻过来（= 玩家看到船的**另一侧**）。
	#   · ⚠️ 第十二轮（绕模型 Y）与第十三轮（绕模型 Z）**都是垂直于舰艏的轴** ⇒ 两轮都把舰艏
	#     翻了头，那正是用户说的「上下颠倒」。
	#     **规律：180° 旋转 = 翻转"除旋转轴以外"那两个 token 的符号。**
	#   · ⚠️ 锚点只钉「矩阵长什么样」，**钉不住哪一版才对** —— 三轮 spec 都是合法旋转，
	#     差别只有用户看画面能分。别再拿锚点当"这次一定对"的理由（第十三轮已栽过一次）。
	# ⚠️ 2026-09-27 第四十三轮 e：改按**用户姿势表**（myrmidon `bow:+Y up:−Z`）。
	#   模型 +Y → 世界 −X（经 R_y(−90°) ⇒ −Z 朝敌）；+Z → −Y；+X → +Z。
	# ⚠️ 47 轮：`mm` 变量已不再单独使用（断言改为端到端口径）——
	#    这里保留一份**只为报错信息**能打出当前 spec，别改成断言输入（红线 40）。
	var mm := EveShipYawTable.axis_remap(&"myrmidon")
	# ⚠️ 2026-09-26 **第二十二轮定案（推翻第九~十四轮）**：spec 由 `-Y,-X,-Z` 改为
	#   **`-X,+Y,-Z`（与 30 艘主流船完全同构）**。
	#   · 病根不是「转 180° 该绕哪个轴」—— 那三轮都在同一根轴上打转，
	#     而真正的错是 **舰艏轴与船背轴共线**：老 spec 声明「模型 +X = 舰艏」
	#     同时又声明「模型 −X = 船背」，**同一根轴被当成两个语义**，几何上不可能。
	#   · 症状：`bow0 = (0,−1,0)`（舰艏竖直朝下）⇒ 单 yaw **任何值**都转不动它
	#     ⇒ 表现出来就是「这艘船的朝向改了 14 轮还改不好」。
	#   · 独立证据（两条，都与用户视觉判读无关）：
	#       ① `sym_test2.py` 全库镜像对称：52 艘里 50 艘「长=X / 上=Y / 宽=Z」，
	#          **myrmidon 在主流那一档**（不是离群的 catalyst / slasher）；
	#       ② `ship.json` 导出置换反解：myrmidon 走 `YZX` ⇒ glb (601.3,310.6,138.4)
	#          ⇒ **长X / 上Y / 宽Z**，同样是主流姿态。
	#   ⇒ 改后 `bow0 = (0,0,−1)`：水平、朝敌、船背朝天，与 50 艘完全一致。
	# ⚠️ 若用户实机看到它「不该平飞而该竖着飞」，回退方式是改 `AXIS_REMAP` 第一行，
	#    但**必须同时保证 BOW_AXIS 与它不共线**（`validate()` 第 ⑤ 条会拦）。
	#
	# ⚠️ 47 轮：断言口径改为**端到端** `zero_pose_basis`（同 catalyst/kestrel）。
	#   user 43e 标定 myrmidon `bow:+Y up:−Z`；47 轮重算 spec = `+Z,+Y,-X`。
	# ⚠️ 48 轮：同 catalyst/kestrel 收为**静态链**。
	var zm := _ZP_SCRIPT.call("zero_pose_basis_no_roll", &"myrmidon") as Basis
	_expect((zm * EveShipYawTable.bow_axis(&"myrmidon")).normalized().distance_to(Vector3(0, 0, -1)) < 0.001
			and (zm * EveShipYawTable.up_axis(&"myrmidon")).normalized().distance_to(Vector3.UP) < 0.001,
			"弥尔米顿：静态链端到端把用户标定的 bow+Y / up−Z 送到 −Z / +Y（48 轮口径）")

	# ── ⑤ **红线 46 全库锚点**（22 轮新增，本套回归里**最值钱**的一条）──────────
	#    「舰艏 ≡ 前进方向」能不能成立，取决于 setup 后的静止舰艏 `bow0`
	#    **是不是水平的**：不水平 ⇒ 单 yaw 转不动（几何死锁），
	#    而 22 轮之后运行时已换成完整旋转对齐，所以这条锚点同时也是
	#    「静止姿态必须朝敌 + 船背朝天」的护栏。
	#    ⚠️ 它**逐艘**查 52 艘、不取样 —— 取样会漏掉下一艘 myrmidon。
	#
	# ⚠️⚠️ 47 轮改写（**算式与 ⑨ 条同步**，红线 40）：
	#    旧的 `R_y(−90°+θ)·M` 在 47 轮**必然全库飘红**（实测 52/52 报异常）——
	#    因为 ① `MODEL_YAW_FIX(−90°)` 已被删除并吸收进 M 表；
	#         ② 少了 `mesh_rot`（`SHIP_AXES` 是网格空间的轴）。
	#    两条都是**口径问题、不是数据问题**：同一次落表下
	#    `zero_pose_basis` 口径的 52 艘**全绿**（见下面 47 轮锚点）。
	#    ⇒ 这里必须与生产算式同源，**不许再手写一份 R_y(−90°)·M**。
	#
	# ⚠️⚠️ 48 轮：本条锚点的**语义**是「用户标定的静止姿态有没有被正确地摆出来」，
	#    所以口径 = **静态链 `zero_pose_basis_no_roll`**（滚转是下游全局修正，
	#    不属于「标定对不对」这件事）。全局滚转单独由 ⑩ 条守（见下）。
	var bad_ids: Array[String] = []
	for s in EveShipAssetIndex.all():
		var sid := StringName(s.id)
		var zp := _ZP_SCRIPT.call("zero_pose_basis_no_roll", sid) as Basis
		var bow0 := (zp * EveShipYawTable.bow_axis(sid)).normalized()
		var up0 := (zp * EveShipYawTable.up_axis(sid)).normalized()
		if absf(bow0.x) > 0.01 or bow0.dot(Vector3(0.0, 0.0, -1.0)) < 0.99 or up0.dot(Vector3.UP) < 0.99:
			bad_ids.append(String(sid))
	_expect(bad_ids.is_empty(),
			"红线 46：52 艘静止舰艏全部「水平 + 朝敌 + 船背朝天」[静态链口径]（异常 %d 艘：%s）"
			% [bad_ids.size(), ", ".join(bad_ids) if not bad_ids.is_empty() else "无"])

	# ── ⑩ ★★53 轮改写（原 48 轮条）：**全局滚转必须保持关闭** ──
	#
	# ═══ 48 轮当初写了什么，为什么是错的 ═══
	#  48 轮用户报「船全部肚皮朝天」，于是加了一刀全局 `R_z(180°)` 扳回来，
	#  并把「`up` 必须被翻到 `(0,−1,0)`」+「`GLOBAL_ROLL_180` 必须为 true」
	#  写成了两条**验收断言**。⇒ 把一次**误诊**固化成了"应然状态"。
	#
	# ═══ 53 轮实测定案（`tools/probe_roll53.tscn`，两栏全库普查）═══
	#      合计 52 艘
	#        含滚转（true）      不达标：52   ← 52/52 船背朝 −Y = 全库肚皮朝天
	#        不含滚转（false）    不达标： 0   ← 52/52 舰艏朝敌 + 船背朝天
	#  即：这一刀**不是**在修某几艘船，它**本身就是病** —— 它把 52 艘
	#  本来正确的姿态一次性全翻过去。
	#
	#  根因：`zero_pose_basis_no_roll = R_y(yaw)·M·mesh_rot`，而 `M` 由
	#  `SHIP_AXES`（**用户 52 艘逐艘标定的真值**，红线 51d / `pose_table.json`）
	#  反解而来，**已经**把舰艏轴送到 −Z、船背轴送到 +Y。
	#  再叠一个 `R_z(180°)` 就是多此一举地翻回去。
	#  ⇒ 48 轮看到的"肚皮朝天"真凶是**运行时 `C` 与 `model.basis` 的基不一致**
	#    （见 `zero_pose_basis_no_roll` 上方那段 48 轮实测记录），不是 `up` 符号。
	#
	# ═══ 本条现在守什么 ═══
	#  · 开关必须是 `false`（回滚即飘红 —— 防止"`true`"被无意改回）；
	#  · 逐艘：`zero_pose_basis·up`   ≈ `(0,+1,0)`（**船背朝天**）；
	#  · 逐艘：`zero_pose_basis·bow`  ≈ `zero_pose_basis_no_roll·bow`
	#          （舰艏方位一格不动；`false` 时二者理应相同）；
	#  · 逐艘：`zero_pose_basis·bow` 必须指向敌人（−Z）+ 水平。
	#  ⚠️ 期望值**独立写成字面量**（红线 40）：`(0,+1,0)` / `(0,0,−1)`，
	#     不是"把另一栏取反"—— 后者会让"滚转没生效"也判绿。
	var roll_bad: Array[String] = []
	for s in EveShipAssetIndex.all():
		var sid := StringName(s.id)
		var zp_r := _ZP_SCRIPT.call("zero_pose_basis", sid) as Basis
		var zp_n := _ZP_SCRIPT.call("zero_pose_basis_no_roll", sid) as Basis
		var up_r := (zp_r * EveShipYawTable.up_axis(sid)).normalized()
		var bow_r := (zp_r * EveShipYawTable.bow_axis(sid)).normalized()
		var bow_n := (zp_n * EveShipYawTable.bow_axis(sid)).normalized()
		if up_r.distance_to(Vector3(0.0, 1.0, 0.0)) > 0.01 \
				or bow_r.distance_to(bow_n) > 0.01 \
				or absf(bow_r.x) > 0.01 \
				or bow_r.dot(Vector3(0.0, 0.0, -1.0)) < 0.99:
			roll_bad.append(String(sid))
	_expect(roll_bad.is_empty(),
			"53 轮：52 艘生产姿态全部「船背朝天(+Y) + 舰艏水平朝敌(−Z)」（异常 %d 艘：%s）"
			% [roll_bad.size(), ", ".join(roll_bad) if not roll_bad.is_empty() else "无"])
	# 开关必须关着（**自证断言有牙齿**，防止 48 轮那刀被无意改回）
	var _roll_on: bool = bool(_ZP_SCRIPT.get("GLOBAL_ROLL_180"))
	_expect(not _roll_on,
			"53 轮：`GLOBAL_ROLL_180` 必须为 **false**"
			+ "（true = 52 艘全被翻成肚皮朝天，见 probe_roll53 两栏普查）")

	# ── ⑥ ★45 轮新增：**「舰艏 ≡ 速度方向」已改成「朝目标优先」，别改回去** ──
	#   用户 45 轮实机原话：「船的舰艏和敌人方向全部是**垂直**的，不是相对的」。
	#   真因：22 轮红线 46 定「舰艏 = 速度方向」，而**默认战术是环绕**
	#   （`EveDestinyMotion.orbit_thrust`）⇒ 推力带强切向分量 ⇒ 速度方向
	#   **天然垂直**于视线 ⇒ 每艘船都"横着飞"。
	#   ⇒ 45 轮把朝向来源改成 **`body.aim_dir` 优先、速度方向兜底**。
	#
	#   ⚠️ 本条是**结构断言**（不真跑战斗 —— 那样会拖慢回归 10 倍）：
	#     它锁住「三个接口都在」，任何一个被删/改名都会 FAIL：
	#       ① `Body.aim_dir` 字段存在（模拟层→视觉层的唯一通道）
	#       ② `EveShipVisual.sync_from_body` 真的读了 `aim_dir`
	#       ③ `eve_battle_simulator` 真的每 tick 写 `aim_dir`
	#     ✅ **行为级**验收（真跑一局、逐帧量 `bow·敌向 ≥ 0.99`）在
	#        `tools/probe_bow_to_target.tscn` —— 那条**已做过反向验证**
	#        （退回旧版 ⇒ 最低 0.756，FAIL）。
	var body_probe: EveDestinyMotion.Body = EveDestinyMotion.Body.new(1)
	_expect(body_probe.aim_dir == Vector3.ZERO,
			"45 轮：`Body.aim_dir` 字段存在且默认零向量（零 = 本 tick 无目标）")
	# ⚠️ 用 `load()` + `source_code` 读源码，**不用 FileAccess.open("res://…")**
	#    —— 后者在导出包里读不到脚本源码（会静默拿到空串 ⇒ 断言恒假）。
	var sv_scr: GDScript = load("res://scripts/visual/eve_ship_visual.gd")
	var sv_txt := "" if sv_scr == null else sv_scr.source_code
	_expect(sv_txt.contains("body.aim_dir"),
			"45 轮：`sync_from_body` 必须读 `body.aim_dir`（朝向来源 = 目标方向优先）")
	var sim_scr: GDScript = load("res://scripts/core/eve_battle_simulator.gd")
	var sim_txt := "" if sim_scr == null else sim_scr.source_code
	# ⚠️ 必须**精确**到"写"（`aim_dir =`），只 contains("aim_dir") 会被注释里的
	#    说明文字骗过 —— 那样断言就恒真了（40 轮的同类陷阱）。
	_expect(sim_txt.contains(".aim_dir ="),
			"45 轮：`eve_battle_simulator` 必须每 tick 写 `body.aim_dir`（否则舰艏永远退化成朝速度）")

	# ══════════════════════════════════════════════════════════════════
	#  ★★ 46 轮：三条「舰艏朝向」关键不变量（每一条都对应一次实机投诉）
	# ══════════════════════════════════════════════════════════════════
	#
	#  46 轮用户原话：
	#    「我终于知道为啥不能让舰艏与速度方向保持一致了，因为**减速不能让舰船
	#      翻转舰艏方向**，这个需要理解现实车辆的**车头方向与速度的关系**。」
	#
	#  这一轮查出**三个**独立缺陷（都表现为"舰艏不朝敌人"）：
	#    ① `aim_dir` 带 Y 分量 ⇒ 舰艏一边偏航一边抬头 ⇒ 水平投影与敌人对不上；
	#    ② `_refresh_targets` 逐 tick 换目标 ⇒ 舰艏被 slerp 拉成"两个敌人的中间"；
	#    ③ 换目标瞬间的 `aim_dir` 瞬移（1288°/s）⇒ 船头"啪"地甩过去。
	#  下面三条把修法**锁死**（都是结构断言：改法被删就 FAIL）。
	#
	# ── ① `aim_dir` 必须在写入侧**拍平到水平面**（XZ）────────────────
	#   位置：`eve_battle_simulator._refresh_targets()`。
	#   为什么必须在这一侧：视觉层不该知道"盘面是平面作战"这条游戏语义
	#   （红线 40：语义只在一处表达）。写成 `d.y = 0.0` 是**硬锚点**——
	#   若有人删掉这行，Y 分量会回来，舰艏又开始"俯仰抖动"。
	_expect(sim_txt.contains("d.y = 0.0"),
			"46 轮：`aim_dir` 必须投影到水平面（`d.y = 0.0`）—— 否则 Y 分量会让舰艏俯仰抖动，"
			+ "水平投影与「敌人在哪个方向」对不上（实机看着=舰艏与敌人垂直）")
	# ── ② 换目标必须有**迟滞**（`SWITCH_MARGIN`）─────────────────────
	#   病象：两个候选评分接近时**逐 tick 翻转**（实测 `slasher` 的 `aim_dir`
	#   在 (−0.99,0,−0.17) ↔ (0.35,0,0.94) 之间每帧跳，相差 133°）
	#   ⇒ 舰艏被 `slerp` 平滑到"两者中间"⇒ 实机看着就是**舰艏与敌人垂直**。
	#   ⚠️ 试过"只把 `_score_target` 的 `W_STICKY` 调大"—— **无效**（提到
	#     2×W_IN_RANGE 仍是逐帧翻）。真正生效的是**比较那一步**的迟滞。
	_expect(sim_txt.contains("SWITCH_MARGIN"),
			"46 轮：`_refresh_targets` 必须有换目标迟滞（`SWITCH_MARGIN`）—— "
			+ "否则目标逐 tick 翻转，舰艏会指向「两个敌人的中间」（实机看着=与敌人垂直）")
	# ── ③ 舰艏必须有**角速度上限**（`FACING_MAX_DEG_PER_SEC`）────────
	#   物理依据 = 用户 46 轮的车头类比：改「车头方向」只能靠**转向**，
	#   而转向需要时间 ⇒ 不允许一帧内甩头（实测 `aim_dir` 换目标瞬间
	#   可跳 1288°/s，slerp 0.40 一帧被拉走一大截）。
	_expect(sv_txt.contains("FACING_MAX_DEG_PER_SEC") and sv_txt.contains("facing_max_step_deg"),
			"46 轮：舰艏必须有角速度上限（`FACING_MAX_DEG_PER_SEC` + `facing_max_step_deg`）"
			+ " —— 否则换目标时船头会「啪」地瞬移（真车转向要时间）")
	# ── ④ 角速度闸门必须**依赖 delta**（帧率无关）───────────────────
	#   若写成固定"每帧 1.5°"，则掉帧时船转得更慢、高刷屏转得更快
	#   ⇒ 观感随机器而变。签名里必须有 `delta` 参数。
	_expect(sv_txt.contains("sync_from_body(body: EveDestinyMotion.Body, alive: bool, delta: float"),
			"46 轮：`sync_from_body` 必须收 `delta`（角速度闸门要按时间步长走，才能帧率无关）")

	# ══════════════════════════════════════════════════════════════════
	#  47 轮锚点（2026-09-27）：**glb 内层网格旋转必须被提升到根节点**
	# ══════════════════════════════════════════════════════════════════
	#
	#  ── 用户原话（47 轮）────────────────────────────────────────────
	#   「我实机确认了，舰艏没有指向敌人，而且每艘船的舰艏指向都很不一样，
	#     很乱。前面我用工具修复过，怎么回事儿」
	#
	#  ── 真因（实测，非推理）────────────────────────────────────────
	#  官方 glb 的结构**从来不是**「根 = 几何体」：
	#      <id>.glb → 根 Node3D（单位阵）
	#                   └─ MeshInstance3D（**自带旋转**，逐艘不同）
	#  实测分布（`tools/probe_innerrot47.tscn` 全库普查）：
	#      R_y(180°) → 30 艘 · R_x(90°) → 3 艘（catalyst/kestrel/slasher）
	#      · 120° 斜轴 → 2 艘（myrmidon/tristan）…
	#  而 `SHIP_AXES`（`bow:+Z`）说的是**网格空间**的轴，
	#  我们的 `M` / `yaw` 却只写在**根节点空间** ⇒ 两者差着那一层
	#  ⇒ **每艘偏的量都不同** —— 正是用户看到的「逐艘各异的乱」。
	#
	#  ── 为什么以前所有探针全绿（红线 40 第 7 次现形）──────────────
	#  旧探针算 `v.quaternion * (model.basis * bow_local)` —— 这两个值
	#  **正是 `_bow_align` 的构造输入** ⇒ 必然 1.000（拿被测方验被测方）。
	#  改用 `mesh.global_transform.basis`（引擎自己连乘）后，**未修主代码**
	#  时读数掉到 **0.000**（舰艏与敌向垂直）—— 与用户 45 轮描述逐字吻合。
	#
	#  ── 判据（三条，全部指向同一个不变量）──────────────────────────
	#   ① 主代码必须调用 `_bake_mesh_rotation()` 且把结果乘进 `model.basis`
	#   ② 探针必须**不用** `hull_root.get_child(0)` 取模型（引擎链才是真值源）
	#   ③ 探针必须用**网格节点的 global_transform**（引擎连乘，不写乘号）
	_expect(sv_txt.contains("_bake_mesh_rotation"),
			"47 轮：`_build_hull_model` 必须把 glb 内层网格旋转提升到根节点（`_bake_mesh_rotation`）—— "
			+ "否则 `SHIP_AXES` 的网格空间轴与根节点空间的 M/yaw 错位，实机逐艘乱飞")
	_expect(sv_txt.contains("* mesh_rot") or sv_txt.contains("*mesh_rot"),
			"47 轮：提升上来的 `mesh_rot` 必须乘进 `model.basis`（漏乘 = 提升没生效，船会侧躺但数值全绿）")
	#  红线 40 的应用：**测量点必须与渲染点同源**。
	#  `get_child(0)` 假定模型是 hull_root 的第一个子节点，但 `_build_engines()`
	#  会往同一个父节点加 nozzle/omni/mi ⇒ 顺序一变读数就是假的（不报错）。
	_expect(not _probe_uses_getchild0("probe_worldbow47.gd"),
			"47 轮：`probe_worldbow47` 不许用 `hull_root.get_child(0)`（位置假定会静默失效）")
	_expect(not _probe_uses_getchild0("probe_bow_to_target.gd"),
			"47 轮：`probe_bow_to_target` 不许用 `hull_root.get_child(0)`（红线 40：测量点必须与渲染点同源）")
	_expect(not _probe_uses_getchild0("probe_brake_flip.gd"),
			"47 轮：`probe_brake_flip` 不许用 `hull_root.get_child(0)`（红线 40）")
	_expect(_probe_txt("probe_worldbow47.gd").contains("global_transform.basis"),
			"47 轮：`probe_worldbow47` 必须用**网格节点的 global_transform**（引擎连乘父子链，不写乘号）")
	_expect(_probe_txt("probe_screenbow47.gd").contains("unproject_position"),
			"47 轮：必须有**相机口径**探针（`unproject_position`）—— 前三层都是空间坐标，"
			+ "只有这一层验的是「屏幕上看起来朝哪」，与用户观感同源")

	# ══════════════════════════════════════════════════════════════════
	#  47 轮锚点（二）：**逐艘显式全局锚点 —— `R_y(−90°)·M·mesh_rot·bow = (0,0,−1)`**
	# ══════════════════════════════════════════════════════════════════
	#
	#  ── 为什么必须**逐艘显式**，不能用上面的 ⑤ 循环代替 ──────────────
	#  ⑤ 是「表内算表」，用的是 `YAW.bow_axis()` + `YAW.axis_remap()` 两个**表值**。
	#  43e 的教训正是：两张表**同时按同一个错口径写**，⑤ 照样全绿而实机全反。
	#  所以这里把 52 艘的期望值**逐条写死**（红线 40：期望值必须独立于被测方）。
	#  它能抓到 ⑤ 抓不到的两类错：
	#    · `mesh_rot` 提升没生效（`zero_pose_basis` 漏乘）—— M 表是对的但世界朝向错；
	#    *  M 表与 `SHIP_AXES` 同时漂移（同向改两张表 ⇒ validate/⑤ 全绿）。
	#
	#  ── 算式口径（48 轮定案的唯一真相源）────────────────────────────
	#    `EveShipVisual.zero_pose_basis_no_roll(id) = R_y(extra_yaw) · M · mesh_rot`
	#    （`MODEL_YAW_FIX(−90°)` 已删，吸收进 M 表；红线 27 同一自由度只许一处）
	#    ⇒ 期望 `zero_pose_basis_no_roll(id) · bow(id) ≈ (0,0,−1)`（敌在世界 −Z，红线 42）
	#      `zero_pose_basis_no_roll(id) · up(id)  ≈ (0,+1,0)`（船背朝天）
	#    ⚠️ 48 轮改用**静态链**：全局滚转是下游修正，本锚点守的是「M/mesh_rot 有没有对」
	#       ⇒ 不含滚转才看得清。滚转本身由上面 ⑩ 条逐艘守。
	#
	#  ⚠️ `mesh_rot` 来自**实际 glb**（`EveShipModel.instantiate`），不是表值 ⇒
	#     换 glb / 换贴图导出置换都会在这里现形。
	var zb_bad: Array[String] = []
	for s in EveShipAssetIndex.all():
		var sid := StringName(s.id)
		var zb := _ZP_SCRIPT.call("zero_pose_basis_no_roll", sid) as Basis
		var bw := (zb * EveShipYawTable.bow_axis(sid)).normalized()
		var uw := (zb * EveShipYawTable.up_axis(sid)).normalized()
		if bw.dot(Vector3(0.0, 0.0, -1.0)) < 0.999 or uw.dot(Vector3.UP) < 0.999:
			zb_bad.append("%s(bow=%s up=%s)" % [String(sid), str(bw.snappedf(0.01)), str(uw.snappedf(0.01))])
	_expect(zb_bad.is_empty(),
			"48 轮：52 艘 `zero_pose_basis_no_roll·bow` 逐艘朝敌 + 船背朝天（异常 %d 艘：%s）"
			% [zb_bad.size(), ", ".join(zb_bad) if not zb_bad.is_empty() else "无"])
	#  M 表必须真的**逐艘非平凡** —— 若退化成单位阵（比如重算脚本没落盘），
	#  上面那条会**整体飘红**；这条用来在飘红时**直接点名病根**，省一轮排查。
	var identity_m: Array[String] = []
	for s2 in EveShipAssetIndex.all():
		var sid2 := StringName(s2.id)
		if EveShipYawTable.axis_remap(sid2).is_equal_approx(Basis.IDENTITY):
			identity_m.append(String(sid2))
	_expect(identity_m.is_empty(),
			"47 轮：`AXIS_REMAP` 逐艘非平凡（退化成单位阵 = 重算未落盘，%d 艘：%s）"
			% [identity_m.size(), ", ".join(identity_m) if not identity_m.is_empty() else "无"])


## `EveShipYawTable` 的 `mesh_rot` provider 是否已装上（47 轮）。
func _mesh_rot_injected() -> bool:
	return EveShipYawTable._mesh_rot_cb.is_valid()


## 取某船的**几何机身长轴**（**根节点空间**，已归一化）—— 给 `validate()` ⑩ 条用。
##
## ── 口径（红线 50a / 50b）──────────────────────────────────────────
##   · 「机身长轴」= glb 网格 `AABB` 的**最长边**所对应的局部轴
##     —— 这是**纯几何事实**，与 `SHIP_AXES` / `AXIS_REMAP` **完全无关**
##     （这正是它有价值的原因：表错时它不会跟着错）。
##   · 「根节点空间」= 乘过 `mesh_rot` 之后（`SHIP_AXES` 是**网格空间**，
##     而 `validate()` ⑩ 条比的是网格空间的 `bow_axis`）——
##     ⚠️ 等等：⑩ 条里 `bow5` 是 `bow_axis()`（网格空间），
##        所以这里**不乘** `mesh_rot`，直接返回网格空间长轴。
##        （与 `bow_axis` 同空间才可比 —— 两个空间混用就是 47 轮那个坑。）
##   · 缓存：同一条船算过一次就不再加载 glb（`mesh_rot_of` 已经缓存了旋转，
##     这里多缓存一份 AABB 长轴，避免每次 `validate()` 重开 52 个 glb）。
func _geo_long_root(id: StringName) -> Vector3:
	if _geo_long_cache.has(id):
		return _geo_long_cache[id]
	var out := Vector3.ZERO
	var inst: Node3D = EveShipModel.instantiate(id, false)
	if inst != null:
		var mn := _first_mesh_of(inst)
		if mn != null and mn.mesh != null:
			var aabb: AABB = mn.mesh.get_aabb()
			var sz := aabb.size
			# 最长边 → 局部轴（网格空间；与 `SHIP_AXES` 同空间）
			if sz.x >= sz.y and sz.x >= sz.z:
				out = Vector3(1.0, 0.0, 0.0)
			elif sz.y >= sz.z:
				out = Vector3(0.0, 1.0, 0.0)
			else:
				out = Vector3(0.0, 0.0, 1.0)
		inst.free()
	_geo_long_cache[id] = out
	return out


var _geo_long_cache: Dictionary = {}


func _first_mesh_of(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n as MeshInstance3D
	for c in n.get_children():
		var got := _first_mesh_of(c)
		if got != null:
			return got
	return null


## 读一个探针脚本的源码 —— 与 `sv_txt` 同源口径（`load()` + `source_code`）。
## ⚠️ 不用 `FileAccess.open("res://…")`：导出后的工程里 `res://` 是二进制包，
##    源码读不全；`source_code` 走的是脚本资源，稳。
func _probe_txt(name: String) -> String:
	var scr: Variant = load("res://tools/%s" % name)
	if scr == null:
		return ""
	return String(scr.source_code)


## 探针里是否还有 `hull_root.get_child(0)` —— 47 轮明令禁止的写法。
##
## 理由：它假定「模型是 hull_root 的第 0 个子节点」，而 `_build_engines()`
## 会往同一个父节点加 nozzle/omni/mi ⇒ 顺序一变读数就是假的，**且不报错**。
## 这是红线 40（测量点必须与渲染点同源）的具体判据。
func _probe_uses_getchild0(name: String) -> bool:
	return _probe_txt(name).contains("hull_root.get_child(0)")
