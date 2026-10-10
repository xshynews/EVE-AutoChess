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
func build_own(run: EveRunState) -> Array[EveShip]:
	var out: Array[EveShip] = []
	var idx_map: Array[int] = []
	var entries := run.field_entries()
	for i in entries.size():
		var e: Dictionary = entries[i]
		var key := String(e.get("ship_key", ""))
		var star := int(e.get("star", 1))
		var ship := EveShipDatabase.instantiate_by_id(key, 0, next_id)
		if ship == null:
			continue
		next_id += 1
		ship.star = star
		if star > 1:
			var m := pow(EveRunState.STAR_MULT, float(star - 1))
			ship.warhead_scale(m)
			ship.armor_scale(m)
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
	return out


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
