extends RefCounted

## 舰队装配器 —— 把 `EveRunState` 的「名单 + 数字」变成战场上的 `EveShip` 实例。
##
## ══════════════════════════════════════════════════════════════════
##  为什么从 eve_battle_scene.gd 里搬出来
## ══════════════════════════════════════════════════════════════════
##  这两条造队链原本长在 2400 行的战斗主控里，却只依赖 `run` 与一个自增 id，
##  与场景树 / 相机 / 输入 / HUD **零耦合** —— 是主控里最"纯"的一块。
##  搬出来之后可以只喂一个 `EveRunState` 单独跑断言，不必起整个战斗场景。
##
## ⚠️ 数值叠加顺序（两条链必须与 `eve_run_state.gd` 的对应注释对齐）：
##      玩家：base → star(×STAR_MULT^Δ) → 羁绊 → 事件 → 逐艘永久增益
##      敌方：base → star → power_scale
##
## ⚠️ `instantiate_by_id` 失败（船表里没有这个 key）时**跳过**该条目，
##    因此 `last_idx_map` 与 `build_own()` 的返回值**严格同下标对齐** ——
##    拖放布阵靠这个映射把「场上第 i 艘」翻回「名单第 idx_map[i] 条」，
##    两者一旦错位就会改错船（见 `eve_battle_scene._own_field_index` 的说明）。

## 跨「敌我两支舰队」唯一的实例 id 计数器。一局内不复用即可，无需跨局唯一。
var next_id: int = 1

## 最近一次 `build_own()` 里「返回数组下标 → run.field_entries() 下标」的映射。
var last_idx_map: Array[int] = []


## 重开一局：id 计数器归零、清掉上次的映射。
func reset() -> void:
	next_id = 1
	last_idx_map = []


## 玩家舰队 = 上场名单。
##
## ⚠️ 每次准备阶段都**重新造实例** ⇒ 上一节点打残的血量不会带过来 ——
##    这是自走棋的基本盘（每回合开打前全员满血）。
## 从任意 run 建一支舰队。
##
## ⚠️ 2026-10-27：`team` 参数是为**多人对战**加的。
##    以前只有单机用（恒为 0 = 己方），所以没人发现它写死了。
##    PvP 时两支舰队都要走这个函数，第二支必须给 team=1，
##    否则双方都是「自己人」—— 模拟器一方开打就直接判完（实测 1 步结束）。
func build_own(run: EveRunState, team: int = 0) -> Array[EveShip]:
	var out: Array[EveShip] = []
	var idx_map: Array[int] = []
	var entries := run.field_entries()
	for i in entries.size():
		var e: Dictionary = entries[i]
		var key := String(e.get("ship_key", ""))
		var star := int(e.get("star", 1))
		var ship := EveShipDatabase.instantiate_by_id(key, team, next_id)
		if ship == null:
			continue
		next_id += 1
		ship.star = star
		if star > 1:
			var m := pow(EveRunState.STAR_MULT, float(star - 1))
			ship.warhead_scale(m)
			ship.armor_scale(m)
			_star_scale_repair(ship, m)
		apply_doctrine(ship)
		out.append(ship)
		idx_map.append(i)
	last_idx_map = idx_map
	# 羁绊：从【真实上场名单】统计，只加在带该羁绊的船上
	run.apply_synergies_to(out)
	# 事件增益：**全队**（面板文案写的就是「全队」），所以放在最后、
	# 且不受羁绊的「只加带该羁绊的船」那条约束。
	run.apply_events_to(out)
	# 逐艘的**永久**增益（武器调校 / 结构加固）—— 走 idx_map，不能用 out[i]↔field[i]
	run.apply_field_buffs_to(out, idx_map)
	return out


## 按**外部名单**建一支舰队（真联机用：对手的编制是网络送来的）。
##
## `entries[i]` = {"ship_key": String, "star": int}
## ⚠️ 走的是和 `build_own` 同一条实例化/星级缩放链，只是数据源换成外部；
##    羁绊用 `apply_fleet_traits` 近似（对手自己的 run 不在这台机器上）。
func build_from_entries(entries: Array, team: int, with_traits: bool = true) -> Array[EveShip]:
	var out: Array[EveShip] = []
	for e in entries:
		var d: Dictionary = e
		var key := String(d.get("ship_key", ""))
		var star := int(d.get("star", 1))
		var ship := EveShipDatabase.instantiate_by_id(key, team, next_id)
		if ship == null:
			continue
		next_id += 1
		ship.star = star
		if star > 1:
			var m := pow(EveRunState.STAR_MULT, float(star - 1))
			ship.warhead_scale(m)
			ship.armor_scale(m)
			_star_scale_repair(ship, m)
		apply_doctrine(ship)
		out.append(ship)
	if with_traits and not out.is_empty():
		EveRunState.apply_fleet_traits(out)
	last_idx_map = []
	return out


## 敌方舰队 = 节点表指定的编组（EveEnemyComps）。
##
## 数值叠加顺序严格按交接文档 §6.4 的冻结口径：base → star → power_scale。
func build_enemy(run: EveRunState) -> Array[EveShip]:
	var out: Array[EveShip] = []
	for d in run.enemy_roster():
		var ship := EveShipDatabase.instantiate_by_id(
				String(d.get("ship_key", "")), 1, next_id)
		if ship == null:
			continue
		next_id += 1
		EveRunState.apply_enemy_scaling(ship, 1, run.enemy_scale())
		apply_doctrine(ship)
		out.append(ship)
	# ★ 2026-10-23：困难 / 炼狱档，敌方也吃自己的羁绊。
	# ⚠️ 统计口径是「这一支敌方编组本身」，不是玩家的 run.field ——
	#    所以海盗王的 6 艘同派系船会吃到满档，而不是白板。
	if bool(run.enemy_tier_row().get("enemy_traits", false)):
		EveRunState.apply_fleet_traits(out)
	# ★ 2026-10-26：电子战羁绊（全表唯一一条「削敌方」的）—— 落点必须在这一侧。
	#   `cycle_scale(1+pct)` = 开火更慢；敌方输出按 1/(1+pct) 衰减（15% ⇒ −13% DPS）。
	#   ⚠️ 不能写进 `_apply_synergy`：那条管道只遍历**自己的**舰队。
	var jam := run.enemy_cycle_pct()
	if jam > 0.0:
		for s in out:
			s.cycle_scale(1.0 + jam)
	# ★ 2026-10-24：炼狱 BOSS 的「壁垒」—— 玩家没凑出钥匙时，敌方全体只吃 10% 伤害。
	# ⚠️ 乘在**受击侧**（`ship.incoming_mult`），不改敌方的输出 ——
	#    壁垒是「打不动」，不是「它打你更疼」。
	var barrier := run.boss_barrier_mult()
	if barrier < 1.0:
		for s in out:
			s.incoming_mult = barrier
	return out


## ★★ 2026-10-28（用户：「2星后勤肯定要涨维修量啊，所以也按比例涨」）：
##    星级放大**两层后勤修量**，倍率与攻击 / 血量同源（`STAR_MULT^(star-1)`）。
##
##    口径：两层**各自**乘倍率后**向下取整**（就低不就高，与 `LOGISTICS_REPAIR`
##    和衍生层 `floor(主修×3/7)` 是同一条规矩）：
##      矮脚鸡（cost 1）1★ 盾 12 · 甲 5 → 2★ 盾 21 · 甲 9 → 3★ 盾 38 · 甲 16
##      巡洋（cost 3）  1★ 盾 56 · 甲 24 → 2★ 盾 100 · 甲 43 → 3★ 盾 181 · 甲 77
##
##    ⛔ 别改走 `EveShip.repair_scale()`：那是**不取整**的通道（羁绊 / 事件用），
##       星级若也从那儿过，面板上会出现 21.6 这种半血点，且 3:7 的读数会被打断。
static func _star_scale_repair(ship: EveShip, m: float) -> void:
	if ship.logistics_repair <= 0.0 or ship.logistics_layer.is_empty():
		return
	ship.logistics_repair = floor(ship.logistics_repair * m)
	ship.logistics_repair_secondary = floor(ship.logistics_repair_secondary * m)


## 战术二次校正
##
## apply_stats 已按吨位给了默认姿态与交战距离。
## 这里只处理一个例外：射程极远的船如果也去贴身，它的射程优势就白给了。
## 所以远程船强制拉开，其余保持吨位默认。
static func apply_doctrine(ship: EveShip) -> void:
	if ship.optimal_range >= 20000.0 and ship.stance == EveCombatCore.Stance.ORBIT:
		# 巡洋级射程 + 环绕 = 自废武功（自己转向慢，绕起来打不中别人）
		ship.stance = EveCombatCore.Stance.KEEP
	# 交战距离兜底：不能小于 2km（不然会撞在一起）
	ship.desired_range = maxf(2000.0, ship.desired_range)


## 舰队名单（用于「上场 N／M 艘」日志）。
static func names_of(fleet: Array[EveShip]) -> PackedStringArray:
	var out := PackedStringArray()
	for s in fleet:
		out.append(s.ship_name)
	return out
