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
## 正在重建舰队 / 装载面板 —— 这期间 `_refresh_run_ui` 不要再来一次重建。
var busy := false

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
	_run.set_phase(EveRunState.Phase.PREP)
	_hud.set_phase(0)
	_hud.set_selling(false)
	_hud.set_bench_drag(-1)
	_resolve.resolve_timer = -1.0

	# 清场 + 三个指纹归零（都在主控那边，一次调用做完）
	_clear_field_cb.call()

	_refresh_ui_cb.call()
	_hud.set_stage(_run.node_index,
			T.t("PREP_AUG_STAGE", "%s · 选择增益") % _run.stage_label(), 0.0)
	_hud.set_loss_cost(0)
	_hud.set_start_button(T.t("PREP_AUG_BTN", "选择增益"), false)

	_hud.append_log({
		"time": 0.0, "category": &"system",
		"text": T.t("PREP_NODE_LINE", "节点 %d／%d · %s · %s") % [
			_run.node_index, EveNodeTable.TOTAL, _run.stage_label(),
			_run.entry_line(),
		],
	})
	_hud.append_log({
		"time": 0.0, "category": &"hint",
		"text": T.t("PREP_AUG_HINT",
					"四条增益里选一条 —— 节点 %s 共用这一套，已获取的不能再选")
					% _event_idx_text(),
	})
	_hud.show_event(_run.event_options(),
			_run.entry_line(),
			T.t("PREP_PICK_ONE", "节点 %d · %d 选 1")
					% [_run.node_index, EveEventTable.count()])
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
		ship_pick_cache = _ship_pick_cards()
		if ship_pick_cache.is_empty():
			# 连备战席都是空的 ⇒ 这条根本没法落地，让玩家换一条
			_hud.append_log({"time": 0.0, "category": &"hint",
					"text": T.t("PREP_NO_SHIP", "一艘船都没有 ——「%s」要指定一艘船，先换一条")
							% String(opt0.get("name", id))})
			return
		pending_event = id
		_hud.hide_event()
		_hud.show_ship_pick(ship_pick_cache,
				T.t("PREP_PICK_SHIP", "选 1 艘船 —— 本局永久生效"),
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
	pending_event = &""
	_hud.hide_ship_pick()
	_apply_event_and_advance(id, entry)


## 落地 + 推进。选船路径与四选一路径**共用这一段** —— 推进逻辑只有一份。
func _apply_event_and_advance(id: StringName, target: Dictionary) -> void:
	var opt := _run.apply_event(id, target)
	if opt.is_empty():
		_hud.append_log({"time": 0.0, "category": &"hint",
				"text": T.t("PREP_AUG_FAIL",
						"这条增益没生效（已获取过，或没选到船）—— 换一条")})
		# 退回四选一：选船那条路径已经把面板收起来了，得把它放回来
		if not _hud.event_is_open():
			_hud.show_event(_run.event_options(), _run.entry_line(),
					T.t("PREP_PICK_ONE", "节点 %d · %d 选 1")
							% [_run.node_index, EveEventTable.count()])
		return
	_hud.hide_event()

	# 事件节点不占一个回合：选完直接推进到下一节点，走它的正常准备阶段。
	_run.advance()
	if _run.phase == EveRunState.Phase.ENDING:
		_hud.set_phase(2)
		_hud.set_stage(_run.node_index, T.t("PREP_RUN_OVER", "本局结束"), 0.0)
		_hud.set_start_button(T.t("PREP_AGAIN", "↻ 再来一局"), true)
		return
	_begin_prep_cb.call()
