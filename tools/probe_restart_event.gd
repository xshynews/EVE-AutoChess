extends Node
## 【探针 · 长期保留】在**事件节点按 R 重开**这条链路（2026-10-30 玩家反馈第 5 条）
##
## 验的是：「开一局 → 第一次事件弹出时按 R 重开，
## 新局多 5 星币、事件面板原位保留、后面的事件效果会叠」。
##
## ── 为什么单独留一个探针，不塞进 verify_run ──────────────────────
##  `verify_run` 是**线性**的 stage 流，事件步骤之后紧跟着打捞/结算，
##  而重开会把局面打回节点 1 —— 插在中间会连带毁掉后面所有步骤的前置状态。
##  单独一个探针既不动那条流，又能单独跑（十几秒）。
##
## ── 实测到的旧行为（反向注入验证，2026-10-30）───────────────────
##  去掉 `restart_run()` 里的 `hud.hide_event()` 之后：
##    · 面板仍开着（event_is_open=true）
##    · 点一条**不需要选船**的选项 ⇒ 星币 5 → **10**、节点 1 → **2**、增益落地
##  这就是玩家报告的全部三个症状。⚠️ 注意必须点 pick_ship=false 的那条 ——
##  点第 0 张（武器调校）会走选船分支、新局没船提前 return，
##  那样写出来的断言是**假绿**（反向注入也照样绿）。
##
## 复现方式与 `verify_run._step_event_open` 同一口径：直接把 node_index
## 拨到事件节点 4 再 `begin_prep()` —— 不去真打前三场（那会让结果随
## 随机战斗波动，变成偶发假红）。
##
## 跑法：
##   "$GODOT" --headless --path . --quit-after 400 res://tools/probe_restart_event.tscn
##   退出码 0 = 全过；1 = 有失败项

const SCENE_PATH := "res://scenes/battle_scene.tscn"

var _fails := 0
var _n := 0


func _ready() -> void:
	var win := get_window()
	if win != null:
		win.size = Vector2i(1920, 1080)
	var packed: PackedScene = load(SCENE_PATH)
	var battle = packed.instantiate()
	add_child(battle)
	await _frames(4)

	var st = battle.get("run")
	var hud = battle.get("hud")
	var ew = hud.get("event_window")
	print("[0] 开局 node=%d coin=%d phase=%d" % [st.node_index, st.coin, st.phase])

	# ── ① 拨到事件节点 4，让事件面板上台 ──
	st.node_index = 4
	battle.call("begin_prep")
	await _frames(3)

	_ck(bool(hud.call("event_is_open")), "事件面板已弹出（前置条件）")
	_ck(int(st.coin) == 5, "弹出时星币 = 5（实际 %d）" % st.coin)
	var coin_at_event := int(st.coin)
	print("[1] event_open=%s · visible=%s · coin=%d"
			% [str(hud.call("event_is_open")), str(ew.get("visible")), st.coin])

	# 记下卡片数量：面板若真收起，这批卡片不该再吃点击
	print("[1] 卡片 %d 张 · 选项 %d 条"
			% [(ew.get("_cards") as Array).size(), (ew.get("_options") as Array).size()])

	# ── ② 按 R = restart_run() ──
	battle.call("restart_run")
	await _frames(3)

	_ck(not bool(hud.call("event_is_open")), "★ 按 R 后事件面板已收（event_is_open=false）")
	_ck(not bool(ew.get("visible")), "★ 事件窗 visible=false")
	_ck(int(st.coin) == 5, "★ 重开后星币 = 5（实际 %d）" % st.coin)
	_ck(int(st.node_index) == 1, "重开后回到节点 1（实际 %d）" % st.node_index)
	_ck(st.phase == EveRunState.Phase.PREP, "重开后处于准备阶段")
	_ck(String(battle.get("_pending_event")) == "", "待落地事件 id 已清空")
	_ck(not bool(battle.get("_prep_phase").get("versus_event")), "versus_event 已复位")
	_ck((st.event_picks as Array).is_empty(),
			"事件增益清空（实际 %d 条）" % (st.event_picks as Array).size())
	print("[2] 重开后 node=%d coin=%d event_open=%s"
			% [st.node_index, st.coin, str(hud.call("event_is_open"))])

	# ── ③ 反向：在新局里强行再点一下那张旧卡（模拟「面板没关干净」的后果）──
	#    ⚠️ 必须点**不需要选船**的那一条：
	#       第 0 张（武器调校）走 `pick_ship` 分支，新局没船 ⇒ 提前 return，
	#       点了什么都不会发生 —— 那样的断言是**假绿**（反向注入也照样绿）。
	#       真正会落地的是 `pick_ship == false` 的选项。
	var pick_idx := -1
	var opts: Array = ew.get("_options")
	for i in opts.size():
		var oid := StringName(opts[i].get("id", &""))
		if not bool(EveEventTable.by_id(oid).get("pick_ship", false)):
			pick_idx = i
			break
	_ck(pick_idx >= 0, "面板里存在「不需要选船」的选项（下标 %d / 共 %d）"
			% [pick_idx, opts.size()])

	var coin_before := int(st.coin)
	var picks_before: int = (st.event_picks as Array).size()
	var node_before := int(st.node_index)
	if pick_idx >= 0:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = true
		ew.call("_on_card_input", ev, pick_idx)
	await _frames(2)
	_ck((st.event_picks as Array).size() == picks_before,
			"收起后点卡片不落地事件（picks 仍 %d）" % picks_before)
	_ck(int(st.coin) == coin_before,
			"收起后点卡片不多给星币（%d → %d）" % [coin_before, st.coin])
	_ck(int(st.node_index) == node_before,
			"点卡片也不会推进节点（仍在 %d）" % st.node_index)

	print("")
	print("════ RESULT: %s · %d 项 · %d 失败 ════"
			% ["PASS" if _fails == 0 else "FAIL", _n, _fails])
	print("[对照] 事件节点当时 coin=%d，重开后 coin=%d" % [coin_at_event, st.coin])
	get_tree().quit(1 if _fails > 0 else 0)


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().process_frame


func _ck(ok: bool, msg: String) -> void:
	_n += 1
	if ok:
		print("  OK   %s" % msg)
	else:
		_fails += 1
		print("  FAIL %s" % msg)
