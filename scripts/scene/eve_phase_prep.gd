extends RefCounted

## ★ 2026-10-11（i18n）：文案取词（见 `eve_text.gd` 顶注）。
const T := preload("res://scripts/core/eve_text.gd")

## 准备阶段（PREP）里**可独立的那一块**：事件节点四选一。
##
## ══════════════════════════════════════════════════════════════════
##  为什么只搬这一块（而不是整个 begin_prep）
## ══════════════════════════════════════════════════════════════════
##  `begin_prep()` 牵动约 20 处**主控自己的**东西（建队 / 摆位 / 三个指纹 /
##  HUD 刷新 / 存档）—— 把它搬出去只能得到「二十个回调的适配器」：
##  行数少了、耦合一处没少。所以它留在主控（它是**装配协调器**，不是阶段逻辑）。
##
##  而「事件节点四选一」是另一回事：它自带状态（`pending_event` /
##  `ship_pick_cache`）、有自己的面板流转（四选一 ⇄ 选 1 艘船），
##  与战斗/结算完全无关 —— 这才是能独立成单元的一块。
##
## ⚠️⚠️ **状态归属**：这 3 个字段是**本模块**的：
##      `pending_event` · `ship_pick_cache` · `busy`
##    前两个是**契约**（验收脚本 `_battle.get("_pending_event")` /
##    `get("_ship_pick_cache")`）⇒ 主控用 get/set 透传属性暴露。
##    `busy` 被主控的 `_refresh_run_ui` 读（准备期间不重建舰队）⇒ 同样透传。
##
## ⚠️ 依赖**显式注入**：`run` / `hud` / 结算模块（写 `resolve_timer`）为引用；
##    `refresh_run_ui` / `clear_field` / `begin_prep` 是主控动作 ⇒ Callable。

var pending_event: StringName = &""
## 事件「选 1 艘」的候选（上场优先、备战席兜底）。
##
## ⚠️ 卡片里塞的是**条目本体**（引用），选完直接改它 ——
##    不记"第几格"：那样上下场一换位就指错人。
var ship_pick_cache: Array = []
## ★ 2026-10-30「双舰强化」（`pick_count: 2`）：玩家点的**第一艘**。
##   为空 = 还没开始选 / 是单船事件。第二艘点完立刻清空。
var _pick_first: Dictionary = {}
## 正在重建舰队 / 装载面板 —— 这期间 `_refresh_run_ui` 不要再来一次重建。
var busy := false
## ★ 2026-10-28 联机事件回合（`versus.round_kind() == CAROUSEL`）：
##   面板逻辑完全复用，只是选完**不推进节点**（联机没有节点推进）。
##   ⇒ 由 `EveBattleScene.begin_prep()` 每次进入回合时设值；单机恒 false。
var versus_event := false
## ★ 2026-10-31 舰船抽奖窗是否开着（炼狱专属）。
##   true 期间 `on_lottery_draw` / `on_lottery_finished` 才受理，
##   且节点**不会**推进 —— 抽奖窗关掉那一刻才继续（见 `_advance_after_event`）。
var lottery_open := false

var _run: EveRunState = null
var _hud: EveHudRoot = null
var _resolve = null
var _refresh_ui_cb: Callable = Callable()
var _clear_field_cb: Callable = Callable()
var _begin_prep_cb: Callable = Callable()


func setup(p_run: EveRunState, p_hud: EveHudRoot, p_resolve,
		p_refresh_ui: Callable, p_clear_field: Callable,
		p_begin_prep: Callable) -> void:
	_run = p_run
	_hud = p_hud
	_resolve = p_resolve
	_refresh_ui_cb = p_refresh_ui
	_clear_field_cb = p_clear_field
	_begin_prep_cb = p_begin_prep


# ══════════════════════════════════════════════════════════════════
#  进入事件节点
# ══════════════════════════════════════════════════════════════════

## 进入事件节点：清空战场 → 面板上台 → 等玩家点。
##
## 为什么**不建任何舰队**（明明可以先摆好我方舰队再让玩家挑）：
##   事件节点没有敌方编组，硬凑一支「我方面对一个空战场」的阵型，
##   只会让玩家以为这里也要开打。清场 + 面板全屏中心，语义最干净：
##   「这一格不是战斗，是一个决定」。挑完立刻进下一节点的正常准备阶段。
##
## 倒计时传 0.0：顶条 `tick()` 见到 `time_left <= 0` 就原地返回，
## 不会再广播 `timer_expired` —— 决策点**没有时限**（与云顶海克斯一致）。
func enter_event_node() -> void:
	busy = true
	# ★ 2026-10-30：进新事件 = 上一条「选 2 艘」的中间态作废（重开/连点都靠这条兜底）。
	_pick_first = {}
	_run.set_phase(EveRunState.Phase.PREP)
	_hud.set_phase(0)
	_hud.set_selling(false)
	_hud.set_bench_drag(-1)
	_resolve.resolve_timer = -1.0

	# 清场 + 三个指纹归零（都在主控那边，一次调用做完）
	_clear_field_cb.call()

	_refresh_ui_cb.call()
	# ★ 2026-10-28 联机事件回合：编号口径换成**回合号**。
	#   `event_clock()` 单机 == node_index（一字不变），联机 = 战斗场景写入的真实回合号。
	#   联机没有 4/10/14 这套节点位，所以「哪些节点能选」那句提示要换掉，
	#   否则玩家会看到一串不对应本局的节点号。
	var ref := _run.event_clock()
	_hud.set_stage(ref,
			T.t("PREP_AUG_STAGE", "%s · 选择增益") % _run.stage_label(), 0.0)
	_hud.set_loss_cost(0)
	_hud.set_start_button(T.t("PREP_AUG_BTN", "选择增益"), false)

	_hud.append_log({
		"time": 0.0, "category": &"system",
		"text": T.t("PREP_NODE_LINE", "节点 %d／%d · %s · %s") % [
			ref, EveNodeTable.TOTAL, _run.stage_label(),
			_run.entry_line(),
		] if not versus_event else T.t("PREP_ROUND_LINE", "第 %d 回合 · %s · %s") % [
			ref, _run.stage_label(), _run.entry_line(),
		],
	})
	var hint := T.t("PREP_AUG_HINT",
			"增益里选一条 —— 节点 %s 共用这一套，已获取的不能再选") % _event_idx_text()
	if versus_event:
		hint = T.t("PREP_AUG_HINT_ROUND", "增益里选一条 —— 已获取的不能再选")
	_hud.append_log({
		"time": 0.0, "category": &"hint",
		"text": hint,
	})
	var sub := T.t("PREP_PICK_ONE", "节点 %d · %d 选 1") % [ref, EveEventTable.count()]
	if versus_event:
		sub = T.t("PREP_PICK_ONE_ROUND", "第 %d 回合 · %d 选 1") % [ref, EveEventTable.count()]
	_hud.show_event(_run.event_options(), _run.entry_line(), sub)
	busy = false


func _event_idx_text() -> String:
	var parts := PackedStringArray()
	for i in EveNodeTable.event_indexes():
		parts.append(str(i))
	return " / ".join(parts)


func _ship_pick_cards() -> Array:
	var src: Array = []
	src.append_array(_run.field_entries())
	src.append_array(_run.bench_entries())
	var out: Array = []
	for e in src:
		var d := EveShipDatabase.by_id(String(e.get("ship_key", "")))
		if d.is_empty():
			continue
		var st := int(e.get("star", 1))
		out.append({
			"id": StringName("pick_%d" % out.size()),
			"name": String(d.get("name", "?")),
			"tag": T.t("PREP_TAG_FLEET", "舰队"),
			"icon": &"armor_plate",
			"desc": T.t("PREP_SHIP_STAT", "★%d · 吨位 %d\nATK %d · 结构 %d") % [
				st, int(d.get("cost", 1)), int(d.get("attack", 0)), int(d.get("armor", 0))],
			"entry": e,
		})
	return out


# ══════════════════════════════════════════════════════════════════
#  玩家选择（面板回传）
# ══════════════════════════════════════════════════════════════════

## 面板回传：玩家选了某一条。
##
## ⚠️ 校验一律走 `run.apply_event()` 的返回值（空 = 无效 / 已获取），
##    这里不再自己判一遍「是不是选过了」—— 两份判据一定会漂移。
func on_event_chosen(id: StringName) -> void:
	if _run == null or _run.phase != EveRunState.Phase.PREP:
		return
	if not _hud.event_is_open():
		return
	# ★ 需要选船的（武器调校 / 结构加固）：先收起四选一，让玩家点一艘船。
	#   ⛔ 不在这里直接 `apply_event` —— 没有目标的话它会返回 {}，
	#      面板那边看起来就像"点了没反应"。
	var opt0 := EveEventTable.by_id(id)
	if bool(opt0.get("pick_ship", false)):
		_pick_first = {}
		ship_pick_cache = _ship_pick_cards()
		if ship_pick_cache.is_empty():
			# 连备战席都是空的 ⇒ 这条根本没法落地，让玩家换一条
			_hud.append_log({"time": 0.0, "category": &"hint",
					"text": T.t("PREP_NO_SHIP", "一艘船都没有 ——「%s」要指定一艘船，先换一条")
							% String(opt0.get("name", id))})
			return
		pending_event = id
		_hud.hide_event()
		var need_n := int(opt0.get("pick_count", 1))
		_hud.show_ship_pick(ship_pick_cache,
				T.t("PREP_PICK_SHIP", "选 1 艘船 —— 本局永久生效") if need_n < 2
						else "选第 1 艘 —— 两艘必须**同费**",
				T.t("PREP_NODE_NAME", "节点 %d · %s")
						% [_run.node_index, String(opt0.get("name", id))])
		return
	_apply_event_and_advance(id, {})


func on_event_ship_picked(index: int) -> void:
	if _run == null or _run.phase != EveRunState.Phase.PREP or pending_event == &"":
		return
	if index < 0 or index >= ship_pick_cache.size():
		return
	var entry: Dictionary = ship_pick_cache[index].get("entry", {})
	var id := pending_event
	# ★ 2026-10-30「双舰强化」：第一次点击只是**记下来**，然后只留「同费」的候选
	#   让玩家点第二艘。⛔ 不能在第一次点击时就落地 —— `apply_event()` 要求
	#   两艘同时给，否则会返回 {}，事件就被白白消耗掉。
	var need_n := int(EveEventTable.by_id(id).get("pick_count", 1))
	if need_n >= 2 and _pick_first.is_empty():
		_pick_first = entry
		var cost := _entry_cost(entry)
		var same: Array = []
		# ⚠️ 按**下标**排掉刚点的那一艘，⛔ 不要用 `e2 == entry` 比较字典：
		#    两艘同名同星的船（都在备战席、`cell` 都是 -1,-1）字典值完全相同，
		#    值比较会把合法的第二艘也排掉，玩家会看到"没有第二艘同费船"。
		for i in ship_pick_cache.size():
			if i == index:
				continue
			var c: Dictionary = ship_pick_cache[i]
			var e2: Dictionary = c.get("entry", {})
			if e2.is_empty():
				continue
			if _entry_cost(e2) == cost:
				same.append(c)
		if same.is_empty():
			# 同费的其它船一艘都没有 ⇒ 这条落地不了，退回四选一
			_hud.append_log({"time": 0.0, "category": &"hint",
					"text": "没有第二艘 %d 费船 ——「双舰强化」需要两艘同费，换一条增益吧" % cost})
			_pick_first = {}
			pending_event = &""
			_hud.hide_ship_pick()
			_hud.show_event(_run.event_options(), _run.entry_line(),
					T.t("PREP_PICK_ONE", "节点 %d · %d 选 1")
							% [_run.event_clock(), EveEventTable.count()])
			return
		# ⚠️ 候选里也把「第一艘」剔掉（玩家不能把同一艘船升两次）
		ship_pick_cache = same
		_hud.hide_ship_pick()
		_hud.show_ship_pick(same, "选第 2 艘 —— 必须同为 %d 费" % cost,
				T.t("PREP_NODE_NAME", "节点 %d · %s")
						% [_run.node_index, String(EveEventTable.by_id(id).get("name", id))])
		return
	var first := _pick_first
	_pick_first = {}
	pending_event = &""
	_hud.hide_ship_pick()
	_apply_event_and_advance(id, first if not first.is_empty() else entry,
			entry if not first.is_empty() else {})


## 一条 entry 的费用档（`cost`）。取不到时按 1 费算 —— 同费判据用它，
## 不能让一条脏数据把整条事件卡死。
func _entry_cost(e: Dictionary) -> int:
	return maxi(1, int(EveShipDatabase.by_id(
			String(e.get("ship_key", ""))).get("cost", 1)))


## 落地 + 推进。选船路径与四选一路径**共用这一段** —— 推进逻辑只有一份。
## `target2` 只给「选 2 艘」的事件（`pick_count: 2`）用。
func _apply_event_and_advance(id: StringName, target: Dictionary,
		target2: Dictionary = {}) -> void:
	var opt := _run.apply_event(id, target, target2)
	if opt.is_empty():
		_hud.append_log({"time": 0.0, "category": &"hint",
				"text": T.t("PREP_AUG_FAIL",
						"这条增益没生效（已获取过，或没选到船）—— 换一条")})
		# 退回四选一：选船那条路径已经把面板收起来了，得把它放回来
		if not _hud.event_is_open():
			_hud.show_event(_run.event_options(), _run.entry_line(),
					T.t("PREP_PICK_ONE", "节点 %d · %d 选 1")
							% [_run.event_clock(), EveEventTable.count()])
		return
	_hud.hide_event()

	# ★★ 2026-10-31（用户定案，仅炼狱）：黑市情报选完先开**舰船抽奖窗口**。
	#
	#   ⚠️ 位置必须在 `apply_event()` **之后** —— 抽奖是这一条的追加奖励，
	#      事件本身（免费高级刷新预约 + 本批半价）已经在上面落地了。
	#      提前 return 会让抽奖把它盖掉（顺序错了就是"抽了船但没刷新"）。
	#   ⚠️ 抽奖窗是**打断式**的：真正的推进在 `on_lottery_finished()` 里，
	#      这里 ⛔ 不能顺手再 `advance()`（会把节点推两次）。
	if _run.can_open_lottery(id) and not versus_event:
		lottery_open = true
		_hud.show_lottery(_run.lottery_pool(),
				"抽奖池已摊开 —— 点一张卡许愿（只能选一艘），抽中它额外返星币",
				T.t("PREP_NODE_NAME", "节点 %d · %s")
						% [_run.node_index, String(opt.get("name", id))])
		return

	_advance_after_event()


## 抽奖窗的「抽取」：从**同一个合并池**里连抽 `DRAW_TIMES` 次，结果回画到窗口。
##
## ★ 2026-10-31 用户纠正：原来是一星/二星两个池子各抽一次，现在合并成一个池，
##   所以是"同一个池抽两次" —— 两抽**允许抽到同一艘**（各自独立掷点）。
##   总产出仍然是 2 艘，和发版前的强度一致；变的只是概率结构
##   （原先是必得 1 艘一星 + 必得 1 艘二星，现在是 2 次 32/44 一星、12/44 二星）。
##
## ⚠️ 每次都要**单独**调 `lottery_draw()`。一次调用内部只掷一次随机
##    （`pick_from_pool` 可能消费一次 randf）—— ⛔ 不要在 run 里写一个
##    "一次抽两艘"的函数：那会让「第几次随机数对应哪艘船」变成不可对账的。
func on_lottery_draw(wish_key: StringName, wish_star: int) -> void:
	if _run == null or not lottery_open:
		return
	var results: Array = []
	for i in range(EveRunState.LOTTERY_DRAW_TIMES):
		results.append(_run.lottery_draw(wish_key, wish_star))
	_hud.show_lottery_result(results)


## 抽奖窗的「完成」：收起窗口，继续走这条事件原本的推进。
func on_lottery_finished() -> void:
	if not lottery_open:
		return
	lottery_open = false
	_hud.hide_lottery()
	_advance_after_event()


## 事件之后的推进（抽奖路径与普通路径共用这一段）。
func _advance_after_event() -> void:
	# ★ 2026-10-28 联机事件回合：**不推进节点**。
	#   联机那套 17 回合表没有 node_index 的概念（敌方编组来自 `PVE_SOURCE_NODE`
	#   映射），事件由 `versus.round_kind() == CAROUSEL` 触发 ⇒ 选完只把面板收起，
	#   直接回到准备阶段，回合推进权仍在房主 / 回合倒计时手上。
	#   ⚠️ 单机这条永远是 false，走下面的 `advance()`，行为与改动前一致。
	if versus_event:
		_begin_prep_cb.call()
		return

	# 事件节点不占一个回合：选完直接推进到下一节点，走它的正常准备阶段。
	_run.advance()
	if _run.phase == EveRunState.Phase.ENDING:
		_hud.set_phase(2)
		_hud.set_stage(_run.node_index, T.t("PREP_RUN_OVER", "本局结束"), 0.0)
		_hud.set_start_button(T.t("PREP_AGAIN", "↻ 再来一局"), true)
		return
	_begin_prep_cb.call()
