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
		apply_star(ship, star)
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
	# ★ 2026-10-31：电子战落点（锁定减伤 + 干扰），必须在羁绊之后
	_apply_ew(out, run.ew_lock_reduce())
	return out


## ★★ 2026-10-31（用户定案）：电子战的**落点** —— 重现 EVE 的锁定机制。
##
## 给电子船写两样东西，**来源不同、⛔ 别合并**：
##   · `ew_lock_reduce` ← 羁绊档位（2/4 艘 = 30%，6 艘 = 40%，见 `eve_trait_table.gd`）
##                        效果 = 它**正锁定的那一艘**输出 ×(1−该值)
##   · `jam_chance`     ← **舰种**（护卫 5% / 巡洋 10%），与羁绊等级无关，可叠加
##                        效果 = 每个干扰周期独立掷一次，命中 ⇒ 目标 10 秒不能开火
##
## ⚠️ 减伤**不在这里乘**，只写字段：锁定关系每 tick 都变（换目标 / 目标被打死），
##    真正的乘法在 `EveBattleSimulator._ew_step()` 里逐帧重算。
##    在这里乘一次的话，玩家一换目标就永远消不掉旧目标的减伤。
##
## ⚠️ `jam_chance` 给**双方**（对称）：PvP 里两支舰队都走这条链，
##    只给我方会让先手方白拿一个机制。敌方编组本来就有 8 艘电子船
##    （`eve_enemy_plans.gd`），不给字段等于「同样的船敌方是白板」。
##
## ⚠️ 只有电子船才有 jam ⇒ 非电子船 `jam_chance = 0`，模拟器里一刀拦掉。
func _apply_ew(out: Array[EveShip], lock_reduce: float) -> void:
	for s in out:
		if not EveTraitTable.EW_SHIP_KEYS.has(String(s.ship_key)):
			continue
		s.is_ew = true
		s.ew_lock_reduce = lock_reduce
		s.jam_chance = EveShip.jam_chance_for_class(s.ship_class)
		# 开局先攒一个周期：第一发干扰在 JAM_CYCLE 秒后才掷，
		# 避免开局瞬间就有人被哑火（玩家还没看懂发生了什么）。
		s.jam_timer = EveShip.JAM_CYCLE


## 按编组自己的电子船数量算**这一支舰队**的电子战档位（PvP 对手用）。
##
## ⚠️ 与 `EveRunState.ew_lock_reduce()` 的区别：那个读的是「玩家自己的 run」，
##    这个只数传入的舰队 —— PvP 里对手的 run 不在这台机器上。
static func ew_lock_reduce_of(fleet: Array[EveShip]) -> float:
	var n := 0
	for s in fleet:
		if EveTraitTable.EW_SHIP_KEYS.has(String(s.ship_key)):
			n += 1
	var t := EveTraitTable.tier_of(&"ew", "电子战", n)
	if t.is_empty():
		return 0.0
	return float((t.get("apply", {}) as Dictionary).get("ew_lock_reduce", 0.0))


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
		apply_star(ship, star)
		apply_doctrine(ship)
		out.append(ship)
	if with_traits and not out.is_empty():
		EveRunState.apply_fleet_traits(out)
	# ★ 2026-10-31：PvP 对手的电子战档位按**它自己的编组**算（run 不在这台机器上）
	_apply_ew(out, ew_lock_reduce_of(out))
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
		# ★ 2026-10-30：BOSS 节点的主坦（cost ≥ 5 的加强型战列）额外吃一层 `bs_damp`。
		#   只作用于那一艘：玩家卡住的是「打不动主坦」，不是前排清不掉。
		#   其余节点 `bs_damp` 缺省 1.0 ⇒ 这一行对前 14 关是空操作。
		var sc := run.enemy_scale()
		if int(d.get("cost", 1)) >= 5:
			sc *= run.boss_bs_damp()
		EveRunState.apply_enemy_scaling(ship, 1, sc)
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
	# ★ 2026-10-31：电子战落到**敌方**这一侧。
	#   ⚠️ 档位按敌方编组自己数（`ew_lock_reduce_of`），不读玩家的 run ——
	#      读玩家的 run 会让「我方凑了 6 艘电子船」变成「敌方也能削我们」，
	#      那是把玩家自己攒的羁绊反过来打自己。
	#   ⚠️ 敌方电子船照样会掷干扰（jam 是对称机制），移速/火力不受影响。
	_apply_ew(out, ew_lock_reduce_of(out))
	return out


## 星级缩放的**唯一实现**（`build_own` / `build_from_entries` / `build_preview` 共用）。
##
## ⚠️ 2026-10-30：抽出来是因为**第三处**要用了（档案窗点备战席的船）——
##    同一段「星级 = 攻击/装甲/后勤各乘 STAR_MULT^(star-1)」原本在
##    `build_own` 与 `build_from_entries` 里各抄了一份，再抄第三份必然分叉：
##    症状是「备战席点开是 ★1 的攻击力，上场后变 ★★」，玩家会以为数值在漂。
static func apply_star(ship: EveShip, star: int) -> void:
	ship.star = star
	if star <= 1:
		return
	var m := pow(EveRunState.STAR_MULT, float(star - 1))
	ship.warhead_scale(m)
	ship.armor_scale(m)
	_star_scale_repair(ship, m)


## 单条 entry → **展示用** EveShip。给「点备战席的船 → 右上档案窗」用。
##
## ⚠️ 备战席的船是**纯数据**（`{"ship_key","star"}`，见 `EveRunState.bench`）：
##    它没有 3D 实体，也不在 `_own_ships` 里 ⇒ 3D 拾取永远点不中它，
##    而档案窗的 `set_ship()` 只吃 `EveShip`。所以这里现造一个**一次性**实例。
##    ⛔ 别把它塞进 `_own_ships` / `all_owned()`：那会让它被当成在场单位
##      计进羁绊，也会被模拟器拿去打。
##
## ⚠️ **只做星级缩放，不叠羁绊 / 事件 / 逐艘增益** —— 那三样都是「在场上才成立」
##    的加成，备战的船还没上场。档案窗自己会写「本舰未上场，不计入」。
## ⚠️ `id` 给 0：不参与战斗，不需要唯一 id（`next_id` 也不占号）。
func build_preview(entry: Dictionary) -> EveShip:
	var key := String(entry.get("ship_key", ""))
	var ship := EveShipDatabase.instantiate_by_id(key, 0, 0)
	if ship == null:
		return null
	apply_star(ship, int(entry.get("star", 1)))
	return ship


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
	# ★ 2026-10-30（玩家反馈 / 用户定案）：
	#   ①「后勤船放在后排，射程同步吨位」→ 后排由模拟器的 `LAYER_BACK` 站位负责；
	#      **姿态**这一层后勤必须一律「保持距离」——护卫级后勤的吨位默认是环绕，
	#      绕起来就贴着敌人修血，等于把唯一的续航送进敌阵。
	#   ②「电子战和普通型采取环绕」→ 护卫 / 驱逐级明确给 ORBIT
	#      （巡洋以上仍走下面的远程规则：环绕对他们自己是纯亏，见该规则注释）。
	var tag := EveShipDatabase.role_tag(String(ship.ship_key))
	if tag == &"logistics" or ship.is_logistics_unit():
		ship.stance = EveCombatCore.Stance.KEEP
	elif tag == &"ew" and ship.ship_class <= EveShip.Class.DESTROYER:
		ship.stance = EveCombatCore.Stance.ORBIT
	if ship.optimal_range >= 20000.0 and ship.stance == EveCombatCore.Stance.ORBIT:
		# 巡洋级射程 + 环绕 = 自废武功（自己转向慢，绕起来打不中别人）
		ship.stance = EveCombatCore.Stance.KEEP
	# 交战距离兜底：不能小于 2km（不然会撞在一起）
	ship.desired_range = maxf(2000.0, ship.desired_range)

	# ★ 2026-10-31（用户定案）：给装备槽**定长度**（按吨位，空槽 = {}）。
	# ⚠️ 放在这里而不是各条造队链，是因为 `apply_doctrine` 是唯一公共入口：
	#    我方 / 敌方 / PvP / 档案预览四条链都调用它 ⇒ 只写一处，四条都对齐。
	#    ⛔ 少写一条链的症状是「那支舰队的船一格装备都装不上」，
	#    而且不会报错（数组长度 0，`resize` 之前永远是空的）。
	var n_slots := EveRunState.equip_slots_for_cost(ship.cost)
	if ship.equips.size() != n_slots:
		ship.equips.resize(n_slots)


## 舰队名单（用于「上场 N／M 艘」日志）。
static func names_of(fleet: Array[EveShip]) -> PackedStringArray:
	var out := PackedStringArray()
	for s in fleet:
		out.append(s.ship_name)
	return out
