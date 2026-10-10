extends RefCounted

## 拖放布阵控制器 —— 从 `eve_battle_scene.gd`（2400 行）里搬出的**整个拖放交互**。
##
## ══════════════════════════════════════════════════════════════════
##  一次拖动的完整生命周期（五个入口，别把逻辑散到别处去）
## ══════════════════════════════════════════════════════════════════
##     begin_drag   按下：这一下是想拿船，还是想转视角？
##     update_drag  移动：幽灵跟手 · 棋盘显形 · 落点高亮 · 写一句「松手会怎样」
##     end_drag     松手：按落点分派到 部署 / 换位 / 撤回 / 出售
##     cancel_drag  取消：ESC / 右键，等于落点「哪儿都不是」
##     finish_drag  收尾：拖动期间的所有临时状态在这里一次清干净（唯一出口）
##
## ⚠️⚠️ **拖动状态字典由主控持有**（`eve_battle_scene._drag`，验收脚本 `verify_run`
##     直接 `_battle.get("_drag")` 读它）⇒ 本控制器**只对它 `clear()` / `merge()`**，
##     ⛔ **绝不 `drag = {...}` 重新赋值**（重新赋值会让主控那个变量指向别的字典，
##     两边从此各说各话，症状是「拖到一半界面和状态对不上」）。
##
## ⚠️ 依赖是**显式注入**的（`setup()`），不是 `get_parent()` / 场景树查找：
##     · `run` / `arena` / `hud` 是**稳定对象**（主控 `_ready` 里各建一次，之后不换）。
##     · `_own_ships` / `_own_field_index` 会被**重新赋值**（重建舰队时）⇒ 用 Callable
##       回主控现取，⛔ 不能在这里缓存数组（缓存的是旧数组）。
##     · `_refresh_run_ui` / `_log_synergies` 是主控的收尾动作 ⇒ 用 Callable 回调。

## 屏幕上「点中一艘舰船」的判定半径（像素）。
## ⚠️ 单一来源：主控的「点击选中最近舰船」也用它（`DEPLOY.PICK_RADIUS`）——
##    ⛔ 别在两处各写一份 60.0。
const PICK_RADIUS := 60.0

## ★ 与主控**共享同一个字典对象**（见顶注）。空字典 = 没在拖。
var drag: Dictionary = {}

## 本次拖动点亮的棋盘是不是「自动的」（松手要还原）。
##
## ⚠️ 玩家用 KEY_B 手动开的棋盘不该被一次拖放顺手关掉 —— 他开棋盘是在核对格子。
##    所以只还原「因为这次拖动才亮起来」的棋盘。
var board_auto := false

var _run: EveRunState = null
var _arena: EveBattleArena = null
var _hud: EveHudRoot = null
var _own_ships_cb: Callable = Callable()
var _own_field_index_cb: Callable = Callable()
var _refresh_ui_cb: Callable = Callable()
var _log_synergies_cb: Callable = Callable()


## 主控 `_ready` 里接线一次。参数见顶注的「显式注入」。
func setup(p_run: EveRunState, p_arena: EveBattleArena, p_hud: EveHudRoot,
		p_drag: Dictionary, p_own_ships: Callable, p_own_field_index: Callable,
		p_refresh_ui: Callable, p_log_synergies: Callable) -> void:
	_run = p_run
	_arena = p_arena
	_hud = p_hud
	drag = p_drag
	_own_ships_cb = p_own_ships
	_own_field_index_cb = p_own_field_index
	_refresh_ui_cb = p_refresh_ui
	_log_synergies_cb = p_log_synergies


## 玩家手动开 / 关棋盘（KEY_B、设置窗的「棋盘」开关）。
##
## ⚠️ 这会把「自动点亮」标记清掉 ⇒ 松手时**不会**顺手把这块棋盘关掉 ——
##    玩家手动开的棋盘是在核对格子，不该被一次拖放夺走控制权。
func mark_board_manual() -> void:
	board_auto = false


## 按下左键时试着拿起一艘船。拿起来了 → true（本次左键从此归拖放）
func begin_drag(pos: Vector2) -> bool:
	if _run == null or _run.phase != EveRunState.Phase.PREP:
		return false          # 战斗中锁操作，是阶段 A 就定下的规矩

	# ① 备战席：轨道几何只有 HUD 知道（格宽 = size.x / 8），所以问它落在第几格
	var bi := _hud.bench_slot_at(pos)
	var bench := _run.bench_entries()
	if bi >= 0 and bi < bench.size():
		_set_drag(make_drag(bench[bi], &"bench", bi))
		drag["screen"] = pos
		_begin_drag_visual()
		return true

	# ② 我方场上舰船：屏幕距离最近的一艘
	var si := own_ship_at(pos)
	var fmap: Array = _own_field_index_cb.call()
	if si >= 0 and si < fmap.size():
		var fi: int = fmap[si]
		var entries := _run.field_entries()
		if fi >= 0 and fi < entries.size():
			_set_drag(make_drag(entries[fi], &"field", fi))
			drag["screen"] = pos
			_begin_drag_visual()
			return true

	return false


## 屏幕点选了我方第几艘（`_own_ships` 的下标；-1 = 没点中）
func own_ship_at(pos: Vector2) -> int:
	var ships: Array = _own_ships_cb.call()
	var best := -1
	var best_d := PICK_RADIUS
	for i in ships.size():
		var ship: EveShip = ships[i]
		if not ship.alive:
			continue
		var sp := _arena.world_to_screen(ship.body.position + Vector3(0, 4, 0))
		var d := sp.distance_to(pos)
		if d < best_d:
			best_d = d
			best = i
	return best


## 组装拖动状态。各字段的含义见主控 `_drag` 的声明处。
static func make_drag(e: Dictionary, source: StringName, index: int) -> Dictionary:
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
	if _arena.board != null:
		if not _arena.board.visible:
			board_auto = true
		_arena.show_board_for_deploy()
	# ── 布阵尺寸（2026-09-20 用户要求）──────────────────────────────
	# 舰船切到布阵态（放大 BOARD_EXAGGERATION 倍，实测原尺寸只有 0.39 格宽，
	# 连拖拽命中半径都点不中）。幂等，连续拖拽重复调用无害。
	_arena.set_ships_board_mode(true)
	# 从备战席拿的：格带上标出「这格被拿起了」，并让那一格**不画立绘**。
	# （EveBenchRail._draw 按 dragging_index 跳过该格，否则会和幽灵重叠成两艘；
	#  3D 版当年靠 bench_stage.set_hidden_index 做同一件事，已随 3D 层停用。）
	if StringName(drag["source"]) == &"bench":
		_hud.set_bench_drag(int(drag["index"]))
	update_drag(drag["screen"])


## 拖动中：幽灵跟手 · 落点高亮 · 把「松手会怎样」写进幽灵的第二行
func update_drag(pos: Vector2) -> void:
	if drag.is_empty():
		return
	drag["screen"] = pos

	var source := StringName(drag["source"])
	var index := int(drag["index"])
	var over_sell := _hud.sell_zone_rect().has_point(pos)
	var bi := _hud.bench_slot_at(pos)
	var cell: Vector2i = _arena.screen_to_cell(pos)
	var on_mine := cell.x >= 0 and _arena.board != null and _arena.board.is_mine_zone(cell.x)

	# 落点判定所需的「事实」在这里现取（棋盘预览 / 备战席是否还有位），
	# 「怎么措辞」的规则交给纯函数 `resolve_hint` —— 那份文案是玩家可见的，
	# 单独可测（见 verify_battle_hint）。
	var pv: Dictionary = {}
	if on_mine:
		pv = _run.preview_place(cell.x, cell.y, source, index)
	var d := resolve_hint(source, over_sell, on_mine, pv, bi >= 0,
			_run.can_recall(), _run.bench_used(), EveRunState.BENCH_SLOTS,
			cell, int(drag["refund"]))
	drag["hint"] = d["hint"]
	drag["hint_ok"] = d["ok"]

	# 棋盘高亮：只高亮「真的落得下」的格子。
	# ⚠️ 无效格也给高亮的话，玩家会以为能放 —— 高亮本身就是一句承诺。
	if _arena.board != null:
		if on_mine and bool(d["ok"]):
			_arena.board.highlight(cell.x, cell.y)
		else:
			_arena.board.clear_highlight()

	# 出售区跟随高亮（只在指针真的进了商店窗时亮）
	_hud.set_sell_hot(over_sell)
	# 备战席：悬停格提示「松手就落这一格」
	_hud.set_bench_hover(-1 if over_sell else bi)
	_hud.set_drag_ghost(ghost_payload(drag))


## 「松手会怎样」的**纯规则**：把所有落点的分支收在这一处，输入是事实、输出是文案。
##
## ⚠️ 这是**玩家可见文案的唯一来源** —— 被拒的静默路径必须给「指对方向」的理由
##    （红线：⛔ 别摆「看着能点、点了没反应」的东西）。单独抽出来是为了能脱离
##    拖拽上下文直接断言每个分支。
static func resolve_hint(source: StringName, over_sell: bool, on_mine: bool,
		place: Dictionary, on_bench: bool, can_recall: bool,
		bench_used: int, bench_max: int, cell: Vector2i, refund: int) -> Dictionary:
	if over_sell:
		return {"hint": "出售 · 返还 ◆%d" % refund, "ok": true}
	if on_mine:
		var ok := bool(place.get("ok", false))
		if ok:
			if source == &"bench":
				return {"hint": "部署到 第 %d 行第 %d 列" % [cell.x + 1, cell.y + 1], "ok": true}
			return {"hint": "移动到这里", "ok": true}
		var why := String(place.get("reason", ""))
		return {"hint": why if why != "" else "不能放在这里", "ok": false}
	if on_bench:
		if source == &"field":
			if can_recall:
				return {"hint": "撤回备战席", "ok": true}
			return {"hint": "备战席已满（%d／%d）" % [bench_used, bench_max], "ok": false}
		return {"hint": "放回备战席", "ok": true}
	return {"hint": "拖到下方部署区 · 或拖到商店出售", "ok": false}


## 幽灵要显示的内容（与 HUD 侧 `_DragGhost.apply` 的字段约定一致）
static func ghost_payload(d: Dictionary) -> Dictionary:
	return {
		"active": true,
		"name": String(d.get("name", "—")),
		"star": int(d.get("star", 1)),
		"cost": int(d.get("cost", 1)),
		"color": d.get("color", Color.GRAY),
		"hint": String(d.get("hint", "")),
		"hint_ok": bool(d.get("hint_ok", false)),
		"screen": d.get("screen", Vector2.ZERO),
	}


## 松手：按落点分派动作。整个拖放**唯一的生效点**。
##
## 落点优先级：出售区 → 棋盘格 → 备战席轨道 → 什么都不做（静默放回）。
func end_drag(pos: Vector2) -> void:
	if drag.is_empty():
		return
	var source := StringName(drag["source"])
	var index := int(drag["index"])

	# ⚠️ 顺序不能反：**先清拖动状态，再执行落点动作**。
	#    因为动作会 emit changed，而 _refresh_run_ui 在「拖动中」是跳过舰队重建的。
	#    先动作后清理的话：船确实上前了（数据对了），但战场上不会出现它 ——
	#    要等下一次 changed 才补上，玩家看到的现象是「松手没反应」。
	finish_drag()

	var res: Dictionary = {"ok": false, "reason": ""}
	if _hud.sell_zone_rect().has_point(pos):
		# 出售。日志（含返还金额）由 RunState 自己发，这里不重复写一行
		if source == &"bench":
			res = _run.sell_from_bench(index)
		else:
			res = _run.sell_from_field(index)
	else:
		var cell: Vector2i = _arena.screen_to_cell(pos)
		var on_mine := cell.x >= 0 and _arena.board != null and _arena.board.is_mine_zone(cell.x)
		if on_mine:
			if source == &"bench":
				res = _run.deploy_from_bench(index, cell.x, cell.y)
			else:
				res = _run.move_field(index, cell.x, cell.y)
		elif source == &"field" and _hud.bench_slot_at(pos) >= 0:
			res = _run.recall_to_bench(index)
		# else：备战席里的船放回备战席 / 丢在空白处 → 静默放回，不打日志

	# 被拒时把原因告诉玩家（这是唯一一处「为什么没生效」的出口）
	if not bool(res.get("ok", false)):
		var why := String(res.get("reason", ""))
		if why != "":
			_hud.append_log({"time": 0.0, "category": &"hint", "text": why})

	# 兜底再刷一次：RunState 的 changed 已经刷过一遍，这次是给
	# 「动作被拒但界面仍需回正」（例如高亮、备战席 hover）收尾。
	_refresh_ui_cb.call()
	_log_synergies_cb.call()


## 取消：ESC / 右键。落点当成「哪儿都不是」，一个字节的数据都不改。
func cancel_drag(msg: String = "") -> void:
	if drag.is_empty():
		return
	if msg != "":
		_hud.append_log({"time": 0.0, "category": &"hint", "text": msg})
	finish_drag()


## 收尾：拖动期间的所有临时状态，全在这里一次清干净。
##
## ⚠️ 以后每加一个「拖动时才会出现的副作用」，它的清理就写在这里 ——
##    只有这一个出口。这就是把拖动状态做成单份字典的收益。
func finish_drag() -> void:
	drag.clear()                                  # ⛔ 清空，不是重新赋值（见顶注）
	_hud.set_drag_ghost({})
	_hud.set_bench_drag(-1)
	_hud.set_bench_hover(-1)
	_hud.set_sell_hot(false)
	if _arena.board != null:
		_arena.board.clear_highlight()
		if board_auto and _arena.board.visible:
			# 走 hide_board()（不是 board.set_board_visible）——
			# 取景交回 _process 的舰队跟随，那条路径同样是平滑的，不会跳。
			_arena.hide_board()
	board_auto = false
	# 舰船退出布阵态，回到战斗尺寸（与 _begin_drag_visual 的进入成对）
	_arena.set_ships_board_mode(false)


## 把一份新状态**并入**主控持有的字典（⛔ 不能整体替换，见顶注）。
func _set_drag(fresh: Dictionary) -> void:
	drag.clear()
	drag.merge(fresh)
