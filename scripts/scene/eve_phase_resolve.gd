extends RefCounted

## 结算 / 结局阶段（RESOLVE · ENDING）—— 状态机三拆之一。
##
## ══════════════════════════════════════════════════════════════════
##  它负责什么
## ══════════════════════════════════════════════════════════════════
##  · 结算页的「延迟弹出」（`popup_timer`）与「兼容旧调用方的定时收尾」（`resolve_timer`）
##    —— **两个方向相反的计时器**，是这一阶段最容易搞混的东西，所以单独放一处。
##  · 结算 payload 的**唯一组装点**（立刻弹 / 延迟弹两条路必须拿到同一份数据）。
##  · 结算页的两个出口（继续 / 结束本局）与节点推进、结局收束。
##
## ⚠️⚠️ **状态归属**：这 4 个字段是**本模块**的，不在地图上：
##      `resolve_timer` · `popup_timer` · `pending_result` · `payload`
##    主控用 **get/set 透传属性**暴露它们（`eve_battle_scene._result_popup_timer`
##    等）—— 验收脚本直接 `_battle.get/set(...)` 读写的正是这些。
##    （实测确认：`Object.get()` / `Object.set()` 都会调用 GDScript 属性访问器。）
##
## ⚠️ 依赖**显式注入**（`setup()`）：
##    · `run` / `hud` / `audio` / `arena` 是稳定对象 ⇒ 直接传；
##    · `sim` 会被建/销毁 ⇒ 用 Callable 现取；
##    · `begin_prep` / `restart_run` / 打捞两处刷新 / 我方存活数 是主控动作 ⇒ Callable。

## 结算页弹出延迟（秒）。★ 契约常量：`EveBattleScene.RESULT_POPUP_DELAY` 就是它。
const POPUP_DELAY := 1.0

const RUN_STORE := preload("res://scripts/core/eve_run_store.gd")

## 「结算页**收起**」的计时器（老逻辑；正常玩法恒为 -1，只有验收/调试显式设它）。
var resolve_timer := -1.0
## 「结算页**弹出**」的倒计时。> 0 = 数据已算好、页还没弹（验收要断言的中间态）。
var popup_timer := -1.0
## 延迟期间攒下的结算数据（到点原样交给 HUD）。
var pending_result: Dictionary = {}
## 最近一次组装出来的 payload（`pending_result` 的同一份引用）。
var payload: Dictionary = {}

var _run: EveRunState = null
var _hud: EveHudRoot = null
var _audio: EveAudio = null
var _arena: EveBattleArena = null
var _sim_cb: Callable = Callable()
var _begin_prep_cb: Callable = Callable()
var _restart_cb: Callable = Callable()
var _refresh_salvage_cb: Callable = Callable()
var _confirm_wrecks_cb: Callable = Callable()
var _own_stats_cb: Callable = Callable()


func setup(p_run: EveRunState, p_hud: EveHudRoot, p_audio: EveAudio,
		p_arena: EveBattleArena, p_sim: Callable, p_begin_prep: Callable,
		p_restart: Callable, p_refresh_salvage: Callable,
		p_confirm_wrecks: Callable, p_own_stats: Callable) -> void:
	_run = p_run
	_hud = p_hud
	_audio = p_audio
	_arena = p_arena
	_sim_cb = p_sim
	_begin_prep_cb = p_begin_prep
	_restart_cb = p_restart
	_refresh_salvage_cb = p_refresh_salvage
	_confirm_wrecks_cb = p_confirm_wrecks
	_own_stats_cb = p_own_stats


## 重开一局：把两个计时器与攒下的数据都清掉。
##
## ⚠️ 不清的话会出现「上一局结束时正好处在延迟中 → 玩家点了结束本局 →
##    1 秒后新一局的布阵台上弹出一张旧结算页」。
func reset() -> void:
	resolve_timer = -1.0
	popup_timer = -1.0
	pending_result = {}
	payload = {}


# ══════════════════════════════════════════════════════════════════
#  进入结算：组装数据（唯一真相源）
# ══════════════════════════════════════════════════════════════════

## 战斗结束 → 算好 payload、起弹窗倒计时；`immediate` = 立刻弹（全灭 / 未部署时）。
##
## ⚠️ 数据必须**在这里**算好：`resolve_battle()` 已经跑过了，隔一秒再算会二次扣血。
##    所以整包存进 `pending_result`，到点原样交给 HUD。
func arm_result(res: Dictionary, won: bool, beacon_before: int,
		destroyed: int, end_reason: String, immediate: bool) -> void:
	payload = build_payload(res, won, beacon_before, destroyed, end_reason)
	pending_result = payload
	popup_timer = POPUP_DELAY
	resolve_timer = -1.0
	if immediate:
		popup()


## 组装结算页的入参。
##
## ⚠️ 抽出来是因为「立刻弹出」与「延迟一秒弹出」两条路都要拿到**同一份**数据。
##    两处各拼一遍字典的话，改一个字段必然漏改另一处 ——
##    而漏改的表现是「某个数在结算页上不对」，不报错。
##
## `won` 从 `res` 里再取一次而不是由调用方传：调用方传的是 `res.get("won")`，
## 两个参数同源，多传一个只会给将来「传错值」留口子。
func build_payload(res: Dictionary, won: bool, beacon_before: int,
		destroyed: int, end_reason: String) -> Dictionary:
	var own: Dictionary = _own_stats_cb.call()
	payload = {
		"won": won,
		"damage": int(res.get("damage", 0)),
		"beacon": _run.beacon,
		"beacon_before": beacon_before,
		"beacon_max": _run.beacon_max(),
		"destroyed": destroyed,
		"alive": int(own.get("alive", 0)),
		"total": int(own.get("total", 0)),
		"xp": EveRunState.NODE_XP_REWARD,
		"wreck": not _run.wrecks.is_empty(),
		"wreck_count": _run.wrecks.size(),
		"wreck_name": String((_run.wrecks[0] as Dictionary).get("name", "")) \
				if not _run.wrecks.is_empty() else "",
		"node": _run.node_index,
		"stage": _run.stage_label(),
		"ending": ending_code(),
		"reason": end_reason,
	}
	return payload


## 结局代号（"cleared" / "evacuated" / ""）—— 结算页据此换按钮。
func ending_code() -> String:
	if _run.phase != EveRunState.Phase.ENDING:
		return ""
	return "cleared" if _run.ending == EveRunState.Ending.CLEARED else "evacuated"


# ══════════════════════════════════════════════════════════════════
#  阶段推进（由主控 `_process` 的 RESOLVE 分支调）
# ══════════════════════════════════════════════════════════════════

func tick(delta: float) -> void:
	# ⚠️ 阶段 D 起，RESOLVE 阶段**不再自动推进** —— 结算页停在那里等玩家点
	#    「继续 · 下一节点」。`resolve_timer` 只剩一条路会用：无头验收 / 调试
	#    路径显式设了它（那种情况下仍按定时器收尾，免得旧脚本全要改）。
	#
	# ★ 2026-10-01：结算页**弹出**也有一个计时器（方向相反的另一个）。
	#   期间让 `arena.sync_ships` 与特效继续跑 —— 这一秒的看点就是最后那一下
	#   开火线与击毁爆炸（用户要求「击毁后一秒弹出」）。
	#   ⚠️ `sim.step()` **不在这里**：战斗已结束，`finished` 后 `sim.step` 是空转；
	#      不调它反而让 `elapsed` 冻在结束时刻，结算页那行日志的时间戳才是对的。
	if popup_timer > 0.0:
		popup_timer -= delta
		if popup_timer <= 0.0:
			popup()
	var sim = _sim_cb.call()
	if sim != null:
		_arena.sync_ships(sim.ships, delta)
	if resolve_timer > 0.0:
		resolve_timer -= delta
		if resolve_timer <= 0.0:
			_hud.hide_result()
			end_resolve()


# ══════════════════════════════════════════════════════════════════
#  结算页
# ══════════════════════════════════════════════════════════════════

## 延迟到点 / 特例提前触发：把攒下的结算数据交给结算页。
##
## ⚠️ 幂等：重复调用第二次会被 `pending_result` 已清空这件事挡住 ——
##    `tick` 的倒计时与「我方全灭立刻弹」两条路都可能调到它。
func popup() -> void:
	if pending_result.is_empty():
		return
	_hud.show_result(pending_result)
	# ★ 打捞区单独推一次（2026-10-04 改版）。
	#    ⚠️ 为什么不能靠 `show_result()` 自己取：`res` 是**结算 payload**
	#    （{won, beacon, wreck_count, …}），**没有** `state` / `items` ——
	#    拿它当 `salvage_info()` 用，打捞区会永远显示「空」。
	#    ⇒ 两个数据源形状不同，必须由主控显式各推一次。
	_refresh_salvage_cb.call()
	pending_result = {}
	popup_timer = -1.0


## 「继续 · 下一节点」→ 推进节点（走的是与旧定时器同一个出口 `end_resolve`）。
func on_result_next() -> void:
	if _run == null:
		return
	# 结局已经发生（信标归零 / 通关）：这一页上的按钮已经换成「再来一局」，
	# 但玩家也可能在这一刻按 ESC / 快捷键，统一在这里兜住。
	if _run.phase == EveRunState.Phase.ENDING:
		_hud.hide_result()
		_restart_cb.call()
		return
	if _run.phase != EveRunState.Phase.RESOLVE:
		return
	# ⚠️ 还有残骸没打捞就点「继续」⇒ 先问一句。
	#    玩家确认放弃才推进；没有残骸时**静默推进**，不给玩家添堵。
	if not _run.wrecks.is_empty():
		_confirm_wrecks_cb.call()
		return
	_hud.hide_result()
	end_resolve()


## 「结束本局」→ 放弃这一局、重开。
##
## ⚠️ 不是「退出进程」：一个自走棋原型里把窗口关掉没有意义，
##    玩家的意图是「这局不打了」，所以落地为 `restart_run()`。
func on_result_end() -> void:
	if _hud:
		_hud.hide_result()
	if _run != null and _run.phase == EveRunState.Phase.ENDING:
		# 已经结算过结局了，只需要把页面收掉 + 刷一次按钮
		_hud.set_start_button("↻ 再来一局", true)
		return
	_hud.append_log({"time": 0.0, "category": &"hint", "text": "已结束本局 —— 重新开始"})
	_restart_cb.call()


## 结算结束 → 推进节点（或收束到结局）
##
## ⚠️ 阶段 D 之后，本函数的调用方从「定时器到点」变成了「玩家点继续」。
##    `resolve_timer` 因此不再被设值（保留字段是为了兼容验收的 `debug_skip_resolve`
##    与旧的无头调用方）。
func end_resolve() -> void:
	resolve_timer = -1.0
	# 阶段 D④：节点推进音。放在 advance() 之前 —— 它代表「这一节点结束了」，
	# 而不是「下一节点开始了」。
	_audio.play_node_advance()
	_run.advance()
	if _run.phase == EveRunState.Phase.ENDING:
		_hud.set_phase(2)
		_hud.set_stage(_run.node_index, "本局结束", 0.0)
		_hud.set_start_button("↻ 再来一局", true)
		return
	# 事件节点不用在这里特判 —— `begin_prep()` 第一个分支就会转给事件节点。
	_begin_prep_cb.call()


# ══════════════════════════════════════════════════════════════════
#  结局 / 调试入口
# ══════════════════════════════════════════════════════════════════

## `run.run_ended` 的处理器（通关 / 撤离）。
func on_run_ended(cleared: bool) -> void:
	# ★ 2026-10-10（审查 2#2）：局已结束 ⇒ **对局存档作废**（没有"继续"可言）。
	RUN_STORE.clear()
	_hud.set_start_button("↻ 再来一局", true)
	_hud.append_log({
		"time": 0.0, "category": &"economy" if cleared else &"damage",
		"text": "═══ 本局结束：%s · 节点 %d／%d · 信标 %d ═══" % [
			"通关" if cleared else "撤离", _run.node_index,
			EveNodeTable.TOTAL, _run.beacon,
		],
	})


## `debug_skip_resolve` 的主体：立刻弹 → 收起 → 推进（验收用）。
func skip() -> void:
	if _run != null and _run.phase == EveRunState.Phase.RESOLVE:
		popup()
		_hud.hide_result()
		end_resolve()
