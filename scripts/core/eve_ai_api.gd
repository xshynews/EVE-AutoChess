extends RefCounted

## EVE 自走棋 —— AI 操作面（2026-10-26）
##
## 存在的唯一理由：让外部 AI 能像玩家一样操作这一局。
##
## ══════════════════════════════════════════════════════════════════
##  三条设计红线
## ══════════════════════════════════════════════════════════════════
##  ① **不另造第二份真相源**。每个动作都走玩家点击的同一条代码路径
##     （HUD 信号 → 场景 handler → EveRunState），规则只在 RunState 里判一次。
##     AI 作弊式地直接改 run.coin 之类的事一律不做 —— 那样验证不了真实玩法。
##  ② **只读快照必须完整**。AI 看不到画面就只能靠 state，所以快照要把
##     「玩家此刻能据以决策的所有信息」都给全（经济 / 商店 / 备战 / 上场 /
##     羁绊 / 敌我血量 / 阶段 / 倒计时 / 哪个窗口开着）。
##  ③ **截图是补充不是替代**。文字快照给结构化事实，截图给画面构图，
##     两者都发，AI 自己决定信谁。
##
## 协议见 `eve_ai_bridge.gd`（TCP 9081，一行一个 JSON）。

const SHOT_DIR := "user://ai_shots"

var _scene: Node = null


func bind_scene(s: Node) -> void:
	if s != null and s.has_method("ai_snapshot"):
		_scene = s
	else:
		_scene = null


## 当前战斗场景。主菜单 / 无战斗时为 null。
func active_scene() -> Node:
	if _scene != null and is_instance_valid(_scene):
		return _scene
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	_scene = _find(tree.current_scene, 0)
	return _scene


## ⚠️ 必须**返回**节点：GDScript 里对象是「引用的值传递」，
##    在函数内给形参重新赋值不会写回调用方的变量（早版本这么写，结果永远找不到）。
func _find(n: Node, depth: int) -> Node:
	if n == null or depth > 8:
		return null
	if n.has_method("ai_snapshot"):
		return n
	for c in n.get_children():
		var hit: Node = _find(c, depth + 1)
		if hit != null:
			return hit
	return null


## 执行一条命令。返回 {"ok": bool, "data": ..., "error": ...}。
## ⚠️ 这个函数**可能是协程**（screenshot / wait 要等帧），调用方必须 await。
##
## 路由：先按场景种类分（menu / intro / battle），再进各自的命令表。
## 这样 AI 从开机画面起就能全程操作，不必先「人造点击」进一局。
func execute(cmd: String, args: Dictionary) -> Dictionary:
	var sc := active_scene()
	var kind := String(sc.call("ai_kind")) if sc != null else "none"

	# ── 任何场景都通用的命令 ────────────────────────────────────────
	match cmd:
		"ping":
			return {"ok": true, "data": {"pong": true}}
		"info":
			return {"ok": true, "data": {
				"game": ProjectSettings.get_setting("application/config/name", "EVE"),
				"version": ProjectSettings.get_setting("application/config/version", "?"),
				"godot": Engine.get_version_info(),
				"scene": kind,
			}}
		"state":
			if sc == null:
				return {"ok": false, "error": "no scene with ai_snapshot"}
			# 每个场景自己造快照（menu / intro / battle 各一份），
			# API 只负责转发 —— 否则加一个新场景就要回来改这里。
			return {"ok": true, "data": sc.call("ai_snapshot")}
		"screenshot":
			if sc == null:
				return {"ok": false, "error": "no scene"}
			return await _screenshot(sc, String(args.get("name", "shot")))
		"wait":
			var secs := clampf(float(args.get("seconds", 0.5)), 0.0, 30.0)
			var tree := Engine.get_main_loop() as SceneTree
			if tree != null and secs > 0.0:
				await tree.create_timer(secs).timeout
			sc = active_scene()
			kind = String(sc.call("ai_kind")) if sc != null else "none"
			return {"ok": true, "data": sc.call("ai_snapshot") if sc != null else {"scene": "none"}}
		"quit":
			var tree2 := Engine.get_main_loop() as SceneTree
			if tree2 != null:
				tree2.quit(0)
			return {"ok": true, "data": {}}
		_:
			pass

	if sc == null:
		return {"ok": false, "error": "没有可操作的场景（既不在主菜单也不在战斗中）"}

	match kind:
		"menu":
			return await _menu_cmd(sc, cmd, args)
		"intro":
			return _intro_cmd(sc, cmd, args)
		"battle":
			return await _battle_cmd(sc, cmd, args)
	return {"ok": false, "error": "未知场景种类: %s" % kind}


## ── 主菜单命令表 ────────────────────────────────────────────────
func _menu_cmd(sc: Node, cmd: String, args: Dictionary) -> Dictionary:
	# 鼠标层是所有场景通用的
	match cmd:
		"ui_map":
			return _res(sc.call("ai_ui_map"))
		"mouse_move":
			return _res(sc.call("ai_mouse_move", float(args.get("x", 0)), float(args.get("y", 0))))
		"cursor_visible":
			return _res(sc.call("ai_cursor_visible", bool(args.get("on", true))))
		"cursor_lock":
			return _res(sc.call("ai_cursor_lock", bool(args.get("on", true))))
		"hover":
			return await _res(await sc.call("ai_hover", float(args.get("x", 0)), float(args.get("y", 0))))
		"ui_click":
			return await _res(await sc.call("ai_ui_click", String(args.get("query", ""))))
		"ui_click_path":
			return await _res(await sc.call("ai_ui_click_path", String(args.get("path", ""))))
		"mouse_click":
			return await _res(await sc.call("ai_mouse_click", float(args.get("x", 0)), float(args.get("y", 0)), int(args.get("button", 1))))
		"mouse_down":
			return await _res(await sc.call("ai_mouse_down", float(args.get("x", 0)), float(args.get("y", 0)), int(args.get("button", 1))))
		"mouse_up":
			return _res(sc.call("ai_mouse_up", float(args.get("x", 0)), float(args.get("y", 0)), int(args.get("button", 1))))
		"mouse_drag":
			return await _res(await sc.call("ai_mouse_drag", float(args.get("ax", 0)), float(args.get("ay", 0)),
					float(args.get("bx", 0)), float(args.get("by", 0)), int(args.get("steps", 12))))
		"mouse_path":
			return await _res(await sc.call("ai_mouse_path", _pts(args.get("points", [])), bool(args.get("hold", false))))
		"start":
			return _res(sc.call("ai_start", int(args.get("difficulty_index", -1)),
					String(args.get("difficulty_id", ""))))
		"continue":
			return _res(sc.call("ai_continue"))
		"select_mode":
			return _res(sc.call("ai_select_mode", int(args.get("index", 0))))
		"select_difficulty":
			return _res(sc.call("ai_select_difficulty", int(args.get("index", 0))))
		"settings":
			return _res(sc.call("ai_settings", bool(args.get("on", true))))
		"replay_intro":
			return _res(sc.call("ai_replay_intro"))
		"quit_game":
			return _res(sc.call("ai_quit_game"))
		"restart":
			# 语义统一：主菜单的「重开」就是开一局新的
			return _res(sc.call("ai_start", int(args.get("difficulty_index", -1)),
					String(args.get("difficulty_id", ""))))
		"pause":
			# 主菜单没有暂停态，收/开设置窗是唯一的「遮罩」
			return _res(sc.call("ai_settings", bool(args.get("on", true))))
		_:
			return {"ok": false, "error": "主菜单里没有命令 %s（可用：start/continue/select_mode/select_difficulty/settings/replay_intro）" % cmd}


## ── 开场剧情命令表 ──────────────────────────────────────────────
func _intro_cmd(sc: Node, cmd: String, args: Dictionary) -> Dictionary:
	match cmd:
		"next":
			return _res(sc.call("ai_next"))
		"skip_talk":
			return _res(sc.call("ai_skip_talk"))
		"finish":
			return _res(sc.call("ai_finish"))
		"pause":
			return _res(sc.call("ai_pause", bool(args.get("on", true))))
		"seek":
			return _res(sc.call("ai_seek", float(args.get("t", 0.0))))
		"restart":
			# 片头没有「重开」，直接整段结束进战斗
			return _res(sc.call("ai_finish"))
		_:
			return {"ok": false, "error": "片头里没有命令 %s（可用：next/skip_talk/finish/pause/seek）" % cmd}


## ── 战斗场景命令表 ──────────────────────────────────────────────
func _battle_cmd(sc: Node, cmd: String, args: Dictionary) -> Dictionary:
	match cmd:
		"ui_map":
			return _res(sc.call("ai_ui_map"))
		"calibrate_mouse":
			return await _res(await sc.call("ai_calibrate_mouse"))
		"cell_point":
			return _res(sc.call("ai_cell_point", int(args.get("row", 0)), int(args.get("col", 0))))
		"verify_point":
			return await _res(await sc.call("ai_verify_point", float(args.get("x", 0)), float(args.get("y", 0)), String(args.get("path", ""))))
		"mouse_move_vp":
			return await _res(await sc.call("ai_mouse_move_vp", float(args.get("x", 0)), float(args.get("y", 0))))
		"ui_click":
			return await _res(await sc.call("ai_ui_click", String(args.get("query", ""))))
		"ui_click_path":
			return await _res(await sc.call("ai_ui_click_path", String(args.get("path", ""))))
		"close_settings":
			return await _res(await sc.call("ai_close_settings"))
		"mouse_move":
			return _res(sc.call("ai_mouse_move", float(args.get("x", 0)), float(args.get("y", 0))))
		"mouse_click":
			return await _res(await sc.call("ai_mouse_click", float(args.get("x", 0)), float(args.get("y", 0)), int(args.get("button", 1))))
		"mouse_down":
			return await _res(await sc.call("ai_mouse_down", float(args.get("x", 0)), float(args.get("y", 0)), int(args.get("button", 1))))
		"mouse_up":
			return _res(sc.call("ai_mouse_up", float(args.get("x", 0)), float(args.get("y", 0)), int(args.get("button", 1))))
		"mouse_drag":
			return await _res(await sc.call("ai_mouse_drag", float(args.get("ax", 0)), float(args.get("ay", 0)),
					float(args.get("bx", 0)), float(args.get("by", 0)), int(args.get("steps", 12))))
		"hover":
			return await _res(await sc.call("ai_hover", float(args.get("x", 0)), float(args.get("y", 0))))
		"cursor_lock":
			return await _res(await sc.call("ai_cursor_lock", bool(args.get("on", true))))
		"buy":
			return _res(sc.call("ai_buy", int(args.get("index", 0))))
		"refresh":
			return _res(sc.call("ai_refresh"))
		"levelup":
			return _res(sc.call("ai_levelup"))
		"shop_lock":
			return _res(sc.call("ai_set_shop_lock", bool(args.get("on", false))))
		"deploy":
			return _res(sc.call("ai_deploy", int(args.get("bench", 0)),
					int(args.get("row", 0)), int(args.get("col", 0))))
		"move":
			return _res(sc.call("ai_move", int(args.get("field", 0)),
					int(args.get("row", 0)), int(args.get("col", 0))))
		"recall":
			return _res(sc.call("ai_recall", int(args.get("field", 0))))
		"sell":
			if String(args.get("source", "bench")) == "field":
				return _res(sc.call("ai_sell_field", int(args.get("index", 0))))
			return _res(sc.call("ai_sell_bench", int(args.get("index", 0))))
		"stance":
			return _res(sc.call("ai_stance", int(args.get("ship_id", 0)), int(args.get("stance", 1))))
		"start_battle":
			sc.call("ai_start_battle")
			return {"ok": true, "data": {}}
		"pause":
			sc.call("ai_pause", bool(args.get("on", true)))
			return {"ok": true, "data": {}}
		"restart":
			sc.call("ai_restart")
			return {"ok": true, "data": {}}
		"back_to_menu":
			sc.call("ai_back_to_menu")
			return {"ok": true, "data": {}}
		"fast_forward":
			sc.call("ai_fast_forward", float(args.get("seconds", 10.0)))
			return {"ok": true, "data": {}}
		"event_choose":
			return _res(sc.call("ai_event_choose", StringName(str(args.get("id", "")))))
		"event_ship":
			return _res(sc.call("ai_event_ship", int(args.get("index", 0))))
		"result_next":
			sc.call("ai_result_next")
			return {"ok": true, "data": {}}
		"result_end":
			sc.call("ai_result_end")
			return {"ok": true, "data": {}}
		"salvage":
			return _res(sc.call("ai_salvage", int(args.get("index", 0))))
		"salvage_zero":
			sc.call("ai_salvage_zero")
			return {"ok": true, "data": {}}
		"dialog_confirm":
			return _res(sc.call("ai_dialog_confirm"))
		"dialog_cancel":
			return _res(sc.call("ai_dialog_cancel"))
		"camera":
			return _res(sc.call("ai_camera", args))
		"frame":
			return _res(sc.call("ai_frame", String(args.get("mode", "battle"))))
		"focus":
			return await _res(await sc.call("ai_focus", args))
		"colors":
			return _res(sc.call("ai_colors", args))
		"ui_map":
			return _res(sc.call("ai_ui_map"))
		"mouse_move":
			return _res(sc.call("ai_mouse_move", float(args.get("x", 0)), float(args.get("y", 0))))
		"mouse_click":
			# ⚠️ 这几个是协程（里面要等帧），.call() 拿到的是协程句柄
			#    而不是返回值 —— 必须 await（不 await 会静默返回空）。
			return await _res(await sc.call("ai_mouse_click", float(args.get("x", 0)), float(args.get("y", 0)), int(args.get("button", 1))))
		"mouse_drag":
			return await _res(await sc.call("ai_mouse_drag", float(args.get("ax", 0)), float(args.get("ay", 0)),
					float(args.get("bx", 0)), float(args.get("by", 0)), int(args.get("steps", 12))))
		"mouse_path":
			return await _res(await sc.call("ai_mouse_path", _pts(args.get("points", [])), bool(args.get("hold", false))))
		"shell":
			return _res(sc.call("ai_shell", bool(args.get("on", false))))
		"markers":
			return _res(sc.call("ai_markers", bool(args.get("on", false))))
		_:
			return {"ok": false, "error": "unknown cmd: %s" % cmd}


## 统一包装成 {ok, data}。
## ⚠️ 早版本直接把 RunState 的返回字典当响应发出去，结果桥只认
##    "data" / "error" 两个键，里面的 reason / 其它字段**全被丢掉** ——
##    AI 那头只看到 {"ok":false}，完全不知道「为什么没生效」。
func _res(v: Variant) -> Dictionary:
	var payload: Variant = _slim(v)
	var ok := true
	if v is Dictionary:
		ok = bool((v as Dictionary).get("ok", true))
	return {"ok": ok, "data": payload}


## 把「整张权威船表行」压成 AI 真正要看的十几个字段。
##
## 为什么必须做：run.offers / buy() 返回里带的是完整船表行
## （resist 数组、爆炸半径、质量、签名半径等 50+ 字段）。一次 state 能到几十 KB，
## AI 的上下文会被这些它永远不看的东西吃光。投影只留决策相关项。
func _slim_ship_row(d: Dictionary) -> Dictionary:
	var out := {
		"ship_key": d.get("ship_key", ""),
		"name": d.get("name_cn", d.get("name", "")),
		"cost": int(d.get("cost", 1)),
		"star": int(d.get("star", 1)),
		"class": int(d.get("class", 0)),
		"faction_cn": d.get("faction_cn", ""),
		"role": d.get("role", ""),
		"weapon_type": d.get("weapon_type", ""),
		"defense_type": d.get("defense_type", ""),
		"traits": d.get("traits", []),
		"attack": d.get("attack", 0),
		"shield": d.get("shield", 0),
		"armor": d.get("armor", 0),
		"hull": d.get("hull", 0),
		"optimal_range": d.get("optimal_range", 0),
		# 2026-10-27：射速三件套也导出（用户要求补的数据）
		"weapon_cycle": d.get("weapon_cycle", 0.0),
		"weapon_damage": d.get("weapon_damage", 0.0),
		"shots_per_second": d.get("shots_per_second", 0.0),
		"max_speed": d.get("max_speed", 0.0),
		"range_cells": d.get("range_cells", 0),
		"speed_cells": d.get("speed_cells", 0.0),
		"is_logistics": bool(d.get("is_logistics", false)),
	}
	if d.has("cell"):
		out["cell"] = d["cell"]
	if d.has("index"):
		out["index"] = int(d["index"])
	return out


## 给数组每项补上它在数组里的下标（商店卡号 / 备战席格号）。
func _with_index(arr: Variant) -> Variant:
	var out: Array = []
	if arr is Array:
		for i in (arr as Array).size():
			var v: Variant = _slim((arr as Array)[i])
			if v is Dictionary and not (v as Dictionary).has("index"):
				(v as Dictionary)["index"] = i
			out.append(v)
	return out


## 递归瘦身：遇到船表行就投影，其它结构原样保留。
func _slim(v: Variant) -> Variant:
	if v is Dictionary:
		var d: Dictionary = v
		if d.has("ship_key") and (d.has("armor_resists") or d.has("weapon_profile")):
			return _slim_ship_row(d)
		var out := {}
		for k in d.keys():
			out[k] = _slim(d[k])
		return out
	if v is Array:
		var arr: Array = []
		for x in v:
			arr.append(_slim(x))
		return arr
	return v


## 把 [[x,y],...] 转成 PackedVector2Array 供鼠标路径用。
func _pts(v: Variant) -> Array:
	var out: Array = []
	if v is Array:
		for p in v:
			if p is Array and (p as Array).size() >= 2:
				out.append(Vector2(float((p as Array)[0]), float((p as Array)[1])))
	return out


func _ending_name(e: int) -> String:
	match e:
		1: return "CLEARED"     ## 通关（15 节点全过）
		2: return "EVACUATED"   ## 信标归零，撤离
	return "NONE"


func _phase_name(p: int) -> String:
	match p:
		0: return "PREP"
		1: return "BATTLE"
		2: return "RESOLVE"
		3: return "ENDING"
	return "?"


func _ships(arr: Variant) -> Array:
	var out: Array = []
	if not (arr is Array):
		return out
	for s in arr:
		if s == null:
			continue
		out.append({
			"id": int(s.id),
			"name": String(s.ship_name),
			"key": String(s.ship_key),
			"team": int(s.team),
			"star": int(s.star),
			"alive": bool(s.alive),
			"stance": int(s.stance),
			"hp": {"shield": float(s.hp.get(&"shield", 0.0)),
				"armor": float(s.hp.get(&"armor", 0.0)),
				"hull": float(s.hp.get(&"hull", 0.0))},
			"max_hp": {"shield": float(s.max_hp.get(&"shield", 0.0)),
				"armor": float(s.max_hp.get(&"armor", 0.0)),
				"hull": float(s.max_hp.get(&"hull", 0.0))},
			"pos_m": [s.body.position.x, s.body.position.y, s.body.position.z] if s.body != null else [0, 0, 0],
			"damage_dealt": float(s.damage_dealt),
			"kills": int(s.kills),
		})
	return out


## 战斗场景的全量快照。AI 的所有决策都基于它 + 截图。
##
## 由 eve_battle_scene.ai_snapshot() 经 EveAiBridge.battle_snapshot() 转调，
## 不直接挂在 API 的 state 上 —— 那样主菜单 / 片头就没法自己报快照。
func build_battle_snapshot(sc: Node) -> Dictionary:
	var run = sc.get("run")
	var hud = sc.get("hud")
	var sim = sc.get("sim")
	var d := {}
	d["scene"] = "battle"
	# [versus] expose the room so an external observer can see opponents
	if sc != null and sc.get("versus") != null:
		var vs = sc.versus
		var ps: Array = []
		for q in vs.players:
			if q == null:
				continue
			ps.append({
				"name": q.display_name, "is_ai": q.is_ai,
				"hp": q.hp, "alive": q.is_alive(),
				"field": (q.run.field.size() if q.run != null else 0),
				"coin": (q.run.coin if q.run != null else 0),
				"level": (q.run.level if q.run != null else 0),
				"traits": (q.run.active_synergies().size() if q.run != null else 0),
			})
		d["versus"] = {
			"progress": vs.progress(),
			"label": vs.round_label(),
			"pve_source": vs.pve_source_node(),
			"players": ps,
		}
	# 实际生效的难度（别再被菜单选中态骗了）
	d["difficulty_id"] = String(run.difficulty_id)
	d["difficulty_name"] = String(run.difficulty_row().get("name", "?"))
	d["enemy_scale"] = float(run.enemy_scale())
	d["phase"] = int(run.phase)
	d["phase_name"] = _phase_name(int(run.phase))
	d["paused"] = bool(sc.call("ai_is_paused"))
	d["node"] = {
		"index": int(run.node_index),
		"total": int(EveNodeTable.TOTAL),
		"type": String(run.node_type()),
		"label": String(run.stage_label()),
		"battle_seconds": float(run.battle_seconds()),
	}
	d["economy"] = {
		"coin": int(run.coin),
		"level": int(run.level),
		"xp": int(run.xp),
		"xp_need": int(run.xp_need()),
		"overtier": int(run.overtier),
		"beacon": int(run.beacon),
		"beacon_max": int(run.beacon_max()),
		"interest": int(run.interest()),
		"income": int(run.income()),
		"loss_preview": int(run.loss_preview()),
	}
	d["field_limit"] = int(run.field_limit())
	# 结局与胜负：AI 跑完整局后要能判定「通关 / 撤离」，并统计胜率
	d["ending"] = int(run.ending)
	d["ending_name"] = _ending_name(int(run.ending))
	d["last_won"] = bool(run.last_won)
	d["win_streak"] = int(run.win_streak)
	d["lose_streak"] = int(run.lose_streak)
	# 棋盘几何：AI 要布阵就必须知道「哪些格能放」。行 0 是最远（敌方侧）。
	d["board"] = {
		"rows": 11, "cols": 11,
		"own_zone_row0": 7,          ## 我方部署区 = 行 7..10
		"enemy_rows": [0, 3],        ## 敌方出现区 = 行 0..3
		"isolation_rows": [4, 6],    ## 隔离区 = 行 4..6（谁都不能放）
	}
	d["timer_left"] = int(hud.stage_seconds_left()) if hud != null else -1
	d["shop"] = {
		# ⚠️ offers 是**数组**，下标就是商店卡号 —— AI 发 buy 要用它。
		#     slim 之后原字典里没有 index 键，这里显式补上。
		"offers": _with_index(run.offers),
		"locked": bool(run.shop_locked),
		"refresh_cost": int(EveRunState.REFRESH_COST),
		"buy_xp_cost": int(EveRunState.BUY_XP_COST),
	}
	d["bench"] = run.bench_entries()
	d["field"] = run.field_entries()
	d["synergies"] = run.active_synergies()
	d["own"] = _ships(sc.call("ai_own_ships"))
	d["enemy"] = _ships(sc.call("ai_enemy_ships"))
	d["ui"] = {
		"result_open": bool(hud.result_is_open()) if hud != null else false,
		"event_open": bool(hud.event_is_open()) if hud != null else false,
		"settings_open": bool(hud.settings_is_open()) if hud != null else false,
	}
	d["salvage"] = run.salvage_info()
	# 事件节点：四选一 / 选船两个子状态 + 可选项（AI 靠它决定发哪条命令）
	d["event"] = sc.call("ai_event_state")
	# 确认框：弹着的时候 AI 必须先应答它，否则下一步指令全部石沉大海
	d["dialog"] = sc.call("ai_dialog_state")
	if sim != null:
		d["battle"] = {
			"elapsed": float(sim.elapsed),
			"tick": int(sim.tick),
			"finished": bool(sim.finished),
			"winner_team": int(sim.winner_team),
			"damage_multiplier": float(sim.damage_multiplier()),
		}
	else:
		d["battle"] = null
	return d


## 截图：等一帧绘制完成再抓，否则拿到的是上一帧（或空图）。
func _screenshot(sc: Node, name: String) -> Dictionary:
	var safe := name if name != "" else "shot"
	for ch in [":", "*", "?", "\"", "<", ">", "|", "/", "\\"]:
		safe = safe.replace(ch, "_")
	await RenderingServer.frame_post_draw
	var vp := sc.get_viewport()
	if vp == null:
		return {"ok": false, "error": "no viewport"}
	var tex := vp.get_texture()
	if tex == null:
		return {"ok": false, "error": "no viewport texture"}
	var img := tex.get_image()
	if img == null or img.is_empty():
		return {"ok": false, "error": "empty image"}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOT_DIR))
	var path := "%s/%s.png" % [SHOT_DIR, safe]
	var err := img.save_png(path)
	if err != OK:
		return {"ok": false, "error": "save_png failed: %d" % err}
	return {"ok": true, "data": {
		"path": ProjectSettings.globalize_path(path),
		"width": img.get_width(),
		"height": img.get_height(),
	}}
