extends RefCounted
class_name EveBattleSimulator

## EVE 自走棋 —— 战斗模拟器
##
## 把 combat_core（数学）+ destiny_motion（物理）串成一场完整战斗。
## 固定步长推进，可脱离渲染层运行（便于无头回归测试）。
##
## 变更清单（初版）：
##   - 固定 30Hz 步进
##   - 自动索敌（就近目标 + 射程优先）
##   - 锁定流程（锁定时间由扫描分辨率与信号半径决定）
##   - 开火判定（角速度驱动命中率）
##   - 电容管理（激光炮耗电，干涸后停修理）
##   - 电子战（网子减速 / 扰断静默 / ECM 打断）
##   - 战斗日志输出（供 HUD 消费）

signal unit_destroyed(ship: EveShip)
signal shot_fired(attacker: EveShip, target: EveShip, hit: bool, quality: int, damage: float)
signal battle_finished(winner_team: int)

const TICK_RATE := 30.0
const FIXED_STEP := 1.0 / TICK_RATE
const MAX_TICKS := 30 * 180   ## 最长 180 秒，超时判平
##
## 为什么是 180 秒而不是 120 秒：
##   实测一局 5v6 在 120 秒时只打完约 2 艘船 —— 因为接敌本身要 15~30 秒，
##   加上锁定 3.5 秒、命中率 ~43%、抗性削减 35%，
##   实际有效 DPS 远低于账面。180 秒对应「接敌 + 两轮集火」的完整节奏，
##   也是玩家能接受的自走棋单回合时长上限。
##
## ★ 2026-10-01 起：**超时一律判负**（原来是按剩余总血量判胜负）。
##   配合【火力渐增】一起看 —— 后者的目的因此变得更单纯：
##   不是"保证比分出高低"，而是**给玩家在时限内清场的机会**。
##   （时限本身来自节点表：遭遇 45s / 精英 55s / BOSS 70s。）

## 火力渐增（sudden death）起始时间与最大倍率
##
## 实测调参记录（5v5 镜像局）：
##   START=90s / MAX=4x  -> 102.6s 首杀，180s 收尾时剩 3v1（胜负明确，但仍超时）
##   START=75s / MAX=5x  -> 首杀提前到 ~85s，能在 180s 内彻底打完
##
## 取 75s 的理由：前 75 秒足够展示接敌/锁定/走位等战术行为，
## 之后进入收尾，既不浪费观众耐心，也保证结局由中盘优势决定。
##
## ⚠️ 2026-09-20（阶段 A）改为**按本场时限的比例**，不再写死绝对秒数。
##    原因：节点的战斗时限来自节点表（遭遇战 45s / 精英 55s / BOSS 70s），
##    写死的 75s 起点在这些时限下永远不会触发，"火力渐增保证收尾"这一层保护
##    就整个失效了。
##    改成比例后：不论时限多长，前 60% 是正常的 EVE 战斗节奏，
##    后 40% 线性放大到 5 倍。
##
## ★ 2026-10-01：超时改成"一律判负"之后，这一层的作用变成
##    **给玩家一个在时限内清场的机会** —— 没有它，45 秒里连两轮集火都打不完，
##    每一局都会超时判负。
const SUDDEN_DEATH_FRACTION := 0.60  ## 时限的前 60% 正常打，之后开始放大
const SUDDEN_DEATH_MAX_MULT := 5.0   ## 到时限时伤害放大到 5 倍

## ★ 2026-10-01：去掉「时限耗尽判负」之后，**收敛由火力渐增保证** ——
##   过了时限，伤害在 5 倍基础上继续涨（每秒 +OVERTIME_RAMP），封顶
##   SUDDEN_DEATH_HARD_CAP。血量有限而倍率无上限 ⇒ 必然在有限时间内分出胜负。
const OVERTIME_RAMP := 0.75          ## 超时后每秒再多涨多少倍
const SUDDEN_DEATH_HARD_CAP := 20.0

## 安全网：极端情况（理论上到不了）下强制收尾，避免一场战斗永远不结束。
## 按**剩余总血量**判 —— 这时候确实谁也打不死谁，比"一律判负"讲道理。
const HARD_STOP_MULT := 3.0

## ★★ 时限换算 —— **全工程唯一**把 max_ticks 换成秒的地方。
##
## ⚠️ 2026-10-01 修了一个真 bug：超时判定原来写 `tick >= max_ticks`，
##    而 `tick` 是**按帧累加**的（`_advance_one_tick` 里 `tick += 1`），
##    `elapsed` 才是**按秒累加**的。两者只在 30fps 时相等 ——
##    60fps 下 tick 跑到 1350 只用了约 22 秒，顶条（按 elapsed 显示）
##    却还剩 23 秒 ⇒ 玩家看到「还剩 20 多秒却判我超时」。
##
##    ⛔ 判定**必须**用秒（本函数），不许再用 tick —— 帧率一变就错位。
func time_limit_seconds() -> float:
	return float(max_ticks) / TICK_RATE

## 本场的 tick 上限。由 `set_time_limit()` 按节点时限设置；
## 不设时回落到 MAX_TICKS（180 秒），保证旧的调试脚本行为不变。
var max_ticks: int = MAX_TICKS


## 设置本场战斗时限（秒）。由 EveBattleScene 在开打前按节点表调用。
##
## ⚠️ 下限 10 秒：时限太短会让「接敌」都跑不完，
##    结果变成两队在射程外站桩 —— 那不是"快"而是"坏"。
func set_time_limit(seconds: float) -> void:
	max_ticks = maxi(int(10.0 * TICK_RATE), int(seconds * TICK_RATE))


## 当前时间点的伤害倍率（供 _fire_once 使用）
##
## 设计意图：时限的前 60% 是完全正常的 EVE 战斗节奏（接敌 / 锁定 / 试探），
## 让玩家看清各船的表现；之后进入「加速收尾」，把伤害放大，
## **让清场这件事在时限内变得可能**。
##
## ★ 2026-10-01（第二次改）：**超时不再判负**（用户：「自走棋就该打到被击毁」）。
##   这一层于是回到它本来的职责：**保证战斗收敛** ——
##   时限后伤害继续涨（5 → 20 倍），双方血量有限 ⇒ 必然分出胜负。
func damage_multiplier() -> float:
	var limit := time_limit_seconds()
	var start := limit * SUDDEN_DEATH_FRACTION
	if elapsed <= start:
		return 1.0
	var span := maxf(1.0, limit - start)
	var t := clampf((elapsed - start) / span, 0.0, 1.0)
	if elapsed <= limit:
		return lerpf(1.0, SUDDEN_DEATH_MAX_MULT, t)
	# ★ 过了时限**继续涨**（不封顶意义上）⇒ 战斗必然收敛，不需要硬判负。
	return minf(SUDDEN_DEATH_MAX_MULT + (elapsed - limit) * OVERTIME_RAMP,
			SUDDEN_DEATH_HARD_CAP)

## 战斗日志（HUD 消费）
class LogEntry:
	var time: float
	var category: StringName   ## fire / damage / break / ewar / system / economy
	var text: String
	func _init(p_time: float, p_cat: StringName, p_text: String) -> void:
		time = p_time
		category = p_cat
		text = p_text

var ships: Array[EveShip] = []
var elapsed: float = 0.0
var tick: int = 0
var finished: bool = false
var winner_team: int = -1
var log_entries: Array[LogEntry] = []
var _next_target_refresh: float = 0.0
var _ship_by_id: Dictionary = {}

## 索敌/开火的分频调度（借鉴参考实现：不同系统跑不同频率）
const TARGET_REFRESH_INTERVAL := 5.0 / TICK_RATE   ## 每 5 tick
const LOCK_REFRESH_INTERVAL := 5.0 / TICK_RATE


func setup(own_ships: Array[EveShip], enemy_ships: Array[EveShip]) -> void:
	ships.clear()
	_ship_by_id.clear()
	log_entries.clear()
	elapsed = 0.0
	tick = 0
	finished = false
	winner_team = -1
	# 时限回到默认（180s），由调用方决定是否用 set_time_limit() 收窄。
	# ⚠️ 必须在这里重置而不是依赖新实例 —— 复用同一个模拟器重开一局时，
	#    上一场的时限会静默地留在身上。
	max_ticks = MAX_TICKS

	for s in own_ships:
		ships.append(s)
	for s in enemy_ships:
		ships.append(s)
	for s in ships:
		_ship_by_id[s.id] = s

	_log(&"system", "战斗开始：%d v %d" % [own_ships.size(), enemy_ships.size()])


## 推进一帧
func step(dt: float = FIXED_STEP) -> void:
	if finished:
		return

	# 按固定步长推进（避免变帧率影响物理）
	var remaining := dt
	while remaining > 0.0 and not finished:
		var step_dt: float = minf(FIXED_STEP, remaining)
		_advance_one_tick(step_dt)
		remaining -= step_dt


func _advance_one_tick(dt: float) -> void:
	elapsed += dt
	tick += 1

	# --- 1. 索敌（分频：每 5 tick） ---
	if elapsed >= _next_target_refresh:
		_next_target_refresh = elapsed + TARGET_REFRESH_INTERVAL
		_refresh_targets()

	# --- 2. 电容 + 修理 ---
	for ship in ships:
		if not ship.alive:
			continue
		_update_capacitor(ship, dt)
		EveCombatCore.repair(
			ship.hp, ship.max_hp, ship.passive_shield,
			ship.active_shield, ship.active_armor, ship.active_hull,
			ship.cap_dry, dt
		)

	# --- 2b. ★ 后勤舰：给友军修（2026-10-01 用户定案）---
	#
	# ⚠️ 为什么必须**紧跟在自修之后**、且单独一轮循环：
	#    ① 紧跟在后面：同一帧里「先扣护盾（被打）→ 再自修 → 再被友军修」
	#       的顺序是确定的，验收才能定死数字。放到运动/开火之后就变成
	#       「本帧打进去的伤害这一帧就被修掉」，读数会随帧序漂。
	#    ② 单独一轮：需要「全队的血」都更新完才挑得出最该修的那一艘。
	#       混在上面那个 for 里，先遍历到的后勤舰会按**上一帧**的血选目标。
	#
	# ⚠️ 目标选择：**同层百分比最低的友军（含自己）**。
	#    · 用「百分比」而不是「绝对差值」—— 否则后勤舰永远在给大船修，
	#      小船被放生（大船掉 100 点绝对值远大于小船掉 50 点，但小船
	#      可能已经掉了一半血）。这条是自走棋里最常见的「奶妈不奶脆皮」。
	#    · ★ **含自己**（2026-10-01 改，原先排除）：敌方总是先打最近的单位，
	#      而后勤就站在前排 ⇒ 大多数局面里**只有后勤自己在掉血**。
	#      排除自己会让它全程空转（实测可修窗口 0/724 帧）。
	#      详见 `_pick_repair_target` 的说明。
	_replenish_own_ships(ships, dt)

	# --- 3. 运动 ---
	for ship in ships:
		if not ship.alive:
			continue
		_apply_motion(ship, dt)
		EveDestinyMotion.integrate_body(ship.body, ship.body.acceleration, dt)

	# --- 4. 锁定与开火 ---
	for ship in ships:
		if not ship.alive:
			continue
		_update_lock(ship, dt)
		if ship.locked:
			_try_fire(ship, dt)

	# --- 5. 胜负判定 ---
	_check_outcome()


# ------------------------------------------------------------------ 索敌

## 46 轮：**换目标次数**（tick 级累计）—— 防抖的量化指标。
## 用途：`tools/probe_brake_flip.tscn` 判据④。
## 抖动会表现为这个数字巨大（逐帧换目标 ⇒ 3000 帧 × 5 艘 = 1.5 万量级），
## 加了迟滞后应显著下降（目标稳定在几十~几百）。
var _target_switches := 0

func _refresh_targets() -> void:
	for ship in ships:
		if not ship.alive:
			continue
		# ECM 期间火控链路中断，无法重新索敌
		if ship.is_jammed(elapsed):
			continue
		var best: EveShip = null
		var best_score := -INF
		var cur_score := -INF
		var cur: EveShip = _ship_by_id.get(ship.target_id)
		for other in ships:
			if not other.alive or other.team == ship.team:
				continue
			if not _is_valid_target(other):
				continue
			var dist := ship.body.position.distance_to(other.body.position)
			var score := _score_target(ship, other, dist)
			if other == cur:
				cur_score = score
			if score > best_score:
				best_score = score
				best = other
		# ★★ 46 轮：**换目标迟滞（hysteresis）** —— 真正的防抖在这里。
		#
		#   为什么必须放在"比较"这一步、而不是 `_score_target` 的粘性项里：
		#     `_score_target` 的粘性只给**当前目标**加分，但**每 tick 重新比较**
		#     时它仍可能被另一个候选反超（两个候选评分接近时反复拉锯）
		#     ⇒ 实测 `slasher` **逐帧翻目标**（`[W2]` 抓到的
		#       `aim=(-0.99,0,-0.17)` ↔ `(0.35,0,0.94)`，相差 133°）
		#     ⇒ 舰艏被 slerp 平滑到"两个目标的中间" ⇒ 实机看着就是
		#       **舰艏与敌人垂直**（用户 45 轮投诉的真根因）。
		#   做法：新目标必须**显著优于**当前目标（超出 `SWITCH_MARGIN`）才允许换。
		#     比例用**相对**裕度（1.5%）而不是绝对分 —— 因为
		#     `W_IN_RANGE`(1e7) 是主要量级，绝对分差不好定。
		#   ⚠️ 三条仍然允许**立刻换**（迟滞不该造成"死锁在尸体上"）：
		#     ① 当前目标不可用（死了 / 不在 `_ship_by_id` 里）；
		#     ② 新目标**够得着**而当前目标**够不着**（先打能打的）；
		#     ③ 本次比较里当前目标根本没参与评分（`cur_score` 仍是 −INF）。
		const SWITCH_MARGIN := 0.015
		var best_reach := best != null and _in_reach(ship, best)
		var cur_reach := cur != null and cur.alive and _in_reach(ship, cur)
		var must_switch := cur == null or not cur.alive or cur_score <= -INF \
				or (best_reach and not cur_reach)
		if best != null and best.id != ship.target_id \
				and (must_switch or best.id == -1 \
				or best_score > cur_score * (1.0 + SWITCH_MARGIN) + 1.0):
			ship.target_id = best.id
			ship.locked = false
			ship.lock_elapsed = 0.0
			_target_switches += 1
			_log(&"system", "%s 锁定目标：%s" % [ship.ship_name, best.ship_name])

	# ★ 45 轮：**每 tick 刷新「舰艏该朝哪」** —— 视觉层只读 `body.aim_dir`。
	#
	# 为什么必须在这里写、而不是在视觉层自己选目标：
	#   · 选目标（换目标）与「舰艏指哪」是**两个不同的生命周期**：
	#     前者只在换目标时变（`best.id != target_id`），后者**每 tick 都要更新**
	#     （目标在动 ⇒ 方向一直在变）。分开写才不会漏帧。
	#   · 用户 45 轮实机诉求：「船的舰艏和敌人方向全部是垂直的，不是相对的」
	#     —— 真因是红线 46 让舰艏 = **速度方向**，而默认战术是 `orbit_thrust`
	#     （环绕）⇒ 速度方向**天然垂直**于视线 ⇒ 舰艏看着就是"横着飞"。
	#     EVE 玩家的正确直觉 = **舰艏朝向敌人**（朝向才是 EVE 太空战的语言）。
	#   · ⚠️ 目标死了 / 目标 id 丢失 ⇒ 写 **零向量**（视觉层据此退回"朝速度方向"），
	#     不要保留上一帧的旧方向（那会让船"盯着尸体看"）。
	#
	# ★★ 46 轮修正：`aim_dir` **必须投影到水平面（XZ）**，丢掉 Y 分量 ★★
	#
	#   病象（实测 `tools/probe_brake_flip.tscn` 逐帧抓到的现场）：
	#     同一艘 slasher 相邻帧的 `aim` 在
	#       `(-0.02, -0.73, 0.68)` ↔ `(-0.02, +0.57, -0.82)` 之间**垂直跳变**。
	#   ⇒ `|aim.y|` 高达 0.73 意味着「敌人在我正下方 47°」——
	#     而棋盘作战里**所有舰船都在同一平面**，这显然不是玩家看到的画面。
	#   为什么会有 Y：`Body.position` 是**完整 3D**（`EveDestinyMotion` 无 Y 约束）
	#     ⇒ 初始高度差 + 机动 / 环绕的切向都会贡献 Y，且**逐帧噪声很大**
	#     ⇒ 归一化后放大成"大幅俯仰"。
	#   后果：`Basis.looking_at(f, UP)` 要一边偏航一边**抬头/低头**
	#     ⇒ 舰艏的**水平投影**与「敌人在哪个方向」对不上
	#     ⇒ 实机上看着就是用户 45 轮描述的「**舰艏和敌人方向垂直**」。
	#     （⚠️ 这才是那条投诉的完整根因链：`aim_dir` 语义 + Y 污染 两件事叠加。）
	#
	#   修法：**在写入侧**（唯一真相源）把方向拍平到 XZ 平面。
	#     · 太空战在盘面上是**平面作战** ⇒ 舰艏只需要水平朝向，这是正确的语义；
	#     · 拍平后 `f` 恒 ⊥ UP ⇒ `looking_at` 的退化兜底分支**永不触发**；
	#     · 视觉层因此不需要知道任何"盘面语义"（红线 40：语义只在一处表达）。
	#   ⚠️ 拍平后若水平分量恰好为 0（敌人在正上方/正下方，理论上不该发生）
	#     ⇒ 长度退化 ⇒ 写零向量，视觉层退回"朝速度方向"，绝不写 NaN。
	for ship in ships:
		if not ship.alive or ship.body == null:
			continue
		var tgt: EveShip = _ship_by_id.get(ship.target_id)
		if tgt != null and tgt.alive and tgt.body != null:
			var d := tgt.body.position - ship.body.position
			d.y = 0.0
			ship.body.aim_dir = d.normalized() if d.length_squared() > 1e-12 else Vector3.ZERO
		else:
			ship.body.aim_dir = Vector3.ZERO


## 目标是否「够得着」= 距离在 optimal + falloff 之内。
##
## 46 轮抽出成独立函数，因为「够不着就换人」这条规则现在被**两处**引用
## （`_score_target` 的粘性衰减 + `_refresh_targets` 的换目标迟滞），
## 口径必须**只有一份**（红线 40：复刻必然漂移）。
func _in_reach(ship: EveShip, other: EveShip) -> bool:
	if other == null or other.body == null:
		return false
	var dist := ship.body.position.distance_to(other.body.position)
	return dist <= ship.optimal_range + ship.falloff


## 目标评分 —— 决定「打谁」。
##
## ⚠️ 这是让战斗收敛的关键，不能只按距离排。
## 只按距离会出问题：射程短的护卫舰去追最远的巡洋舰，
## 结果所有船挤在中间地带，谁都打不着谁（实测卡在 9km 空转 120 秒）。
##
## 评分维度（由高到低权重）：
##   1. 能否打到：射程内的目标绝对优先（这是唯一的硬约束）
##   2. 打了有没有用：优先能破防的（抗性低 / 自身伤害高的目标）
##   3. 威胁度：优先血少的（先集火秒掉，形成数量优势滚雪球）
##   4. 距离：同样条件下就近
func _score_target(ship: EveShip, other: EveShip, dist: float) -> float:
	const W_IN_RANGE := 10_000_000.0
	const W_THREAT := 1_000_000.0
	const W_SQUISHY := 500.0
	# ★ 46 轮：**不要指望调大这个值来防抖**（试过，无效）。
	#   实测把它提到 `20_000_000`（= 2 × W_IN_RANGE）后，`slasher` **仍然逐帧
	#   翻目标** —— 因为 `_refresh_targets` 每 tick 重新比较，另一个候选
	#   只要在某一项上多拿一点就能反超。防抖的正确位置 = 换目标**比较**那一步
	#   （见 `_refresh_targets` 的 `SWITCH_MARGIN` 迟滞）。
	#   这里保留 5 万只作为"轻微偏好"，别删：删了会让 `W_SQUISHY` 等
	#   次要项主导排序，实测更容易抖。
	const W_STICKY := 50_000.0

	var score := -dist

	# 1. 射程：能在 optimal+falloff 内打到才算「够得着」
	if dist <= ship.optimal_range + ship.falloff:
		score += W_IN_RANGE
		# 越靠 optimal 越好（falloff 边缘命中率衰减严重）
		var range_quality := 1.0 - clampf(
			(dist - ship.optimal_range) / maxf(1.0, ship.falloff), 0.0, 1.0)
		score += W_IN_RANGE * 0.2 * range_quality

	# 2. 威胁：优先集火残血目标（数量优势是自走棋胜负手）
	var hp_ratio := other.total_hp() / maxf(1.0, other.total_max_hp())
	score += W_THREAT * (1.0 - hp_ratio) * 0.5

	# 3. 好打程度：目标信号半径越大越容易被炮塔命中
	score += W_SQUISHY * float(other._extra.get("signature", 40.0))

	# 4. 粘性：轻微偏好当前目标。
	#    ⚠️ 46 轮结论：**防抖不能靠这里**（实测把它从 5 万提到 2000 万仍然逐帧翻
	#       目标 —— 因为每 tick 重新比较时，另一个候选仍可能反超）。
	#       真正的迟滞在 `_refresh_targets` 的 `SWITCH_MARGIN`。
	#       这里保留一个小权重即可，别删（删了会让 `W_SQUISHY` 等次要项
	#       主导排序，实测更容易抖）。
	if other.id == ship.target_id:
		score += W_STICKY

	return score


## 目标是否合法（基础筛选，避免极端不合理的追猎）
func _is_valid_target(_other: EveShip) -> bool:
	# 目前不做额外限制：即使够不着也先锁定并前往，否则会站着不动
	# 未来可加：ECM 舰优先、旗舰优先、保护己方残血等规则
	return true


func _update_lock(ship: EveShip, dt: float) -> void:
	if ship.locked:
		return
	var target: EveShip = _ship_by_id.get(ship.target_id)
	if target == null or not target.alive:
		ship.target_id = -1
		return
	# ECM 期间锁定进度不推进；干扰结束后从零重新读锁定条
	if ship.is_jammed(elapsed):
		ship.lock_elapsed = 0.0
		return
	ship.lock_elapsed += dt
	if ship.lock_elapsed >= ship.lock_total:
		ship.locked = true


# ------------------------------------------------------------------ 开火

func _try_fire(ship: EveShip, dt: float) -> void:
	var target: EveShip = _ship_by_id.get(ship.target_id)
	if target == null or not target.alive:
		ship.target_id = -1
		ship.locked = false
		return

	# ECM 会打断已有的锁定
	if ship.is_jammed(elapsed):
		ship.locked = false
		ship.lock_elapsed = 0.0
		return

	# 电容不足无法开火
	if ship.cap_max > 0.0 and ship.cap_dry:
		return

	# 武器循环
	ship.weapon_timer -= dt
	while ship.weapon_timer <= 0.0:
		ship.weapon_timer += maxf(0.1, ship.weapon_cycle)
		_fire_once(ship, target)
		# 同一 tick 内连射时目标可能已被前一发击毁 ⇒ 停火，
		# 否则 kills 重复累加、unit_destroyed 重复发出
		if not target.alive:
			break


func _fire_once(ship: EveShip, target: EveShip) -> void:
	var motion := EveCombatCore.relative_motion(
		ship.body.position, ship.body.velocity,
		target.body.position, target.body.velocity
	)
	var distance: float = motion["distance"]
	var angular: float = motion["angular"]

	var multiplier := 0.0
	var hit := false
	var quality := EveCombatCore.HitQuality.MISS

	var weapon_type := String(ship._extra.get("weapon_type", ""))

	if weapon_type == "导弹":
		# 导弹必中，但伤害受爆炸半径/速度与目标信号/速度衰减
		var dmg_factor := EveCombatCore.missile_application(
			float(ship._extra.get("explosion_radius", 50.0)),
			float(ship._extra.get("explosion_velocity", 3000.0)),
			1.0,
			_effective_signature(target),
			target.body.velocity.length()
		)
		# 超出射程无伤害
		if distance > ship.optimal_range:
			return
		multiplier = dmg_factor
		hit = dmg_factor > 0.01
		quality = EveCombatCore.HitQuality.HIT
	else:
		# 炮塔：射程 x 追踪
		var app := EveCombatCore.turret_chance_to_hit(
			ship.optimal_range, ship.falloff, ship.tracking,
			ship.signature_resolution, _effective_signature(target),
			distance, angular
		)
		var roll := randf()
		var result := EveCombatCore.turret_hit_quality(float(app["chance"]), roll)
		hit = result["hit"]
		quality = result["quality"]
		multiplier = float(result["multiplier"])

	if not hit:
		shot_fired.emit(ship, target, false, EveCombatCore.HitQuality.MISS, 0.0)
		return

	# 结算伤害
	# ⚠️ 乘上 damage_multiplier()：90 秒后进入火力渐增，
	#    保证一局必定收尾（详见该函数的说明）。
	var raw_damage := ship.weapon_damage * multiplier * damage_multiplier()
	var result := EveCombatCore.apply_damage(
		target.hp, target.resists, raw_damage, ship.weapon_profile, false
	)
	var applied := float(result["applied"])

	ship.damage_dealt += applied
	target.damage_taken += applied

	if ship.cap_max > 0.0:
		ship.cap = maxf(0.0, ship.cap - ship.cap_use * 0.35)

	shot_fired.emit(ship, target, true, quality, applied)
	_log(&"fire", "%s → %s  %s  %.0f 伤害" % [
		ship.ship_name, target.ship_name, _quality_text(quality), applied
	])

	# 破层事件
	for layer in result["breaks"]:
		_log(&"break", "%s 的%s被击穿" % [target.ship_name, _layer_text(layer)])

	if target.hp[&"hull"] <= 0.0:
		target.alive = false
		ship.kills += 1
		_log(&"damage", "%s 已被摧毁" % target.ship_name)
		unit_destroyed.emit(target)


## 目标有效信号半径（被网子缠住会变小 → 更容易被打中）
func _effective_signature(target: EveShip) -> float:
	var sig := float(target._extra.get("signature", 40.0))
	if target.webbed_until > elapsed:
		sig *= 0.4
	return maxf(1.0, sig)


# ------------------------------------------------------------------ 运动

func _apply_motion(ship: EveShip, dt: float) -> void:
	var target: EveShip = _ship_by_id.get(ship.target_id)
	if target == null or not target.alive:
		# 无目标时缓慢停下
		ship.body.acceleration = -ship.body.velocity * 0.5
		return

	# --- 交战距离：强制收敛到「双方都够得着」的区间 ---
	# 传对手射程进去，避免出现「我站在你打不到的地方，你也不追」的僵局
	var want_range := ship.engagement_range(target.optimal_range)

	# --- 硬性接近：超出自己的有效射程就用「螺旋接近」顶上去 ---
	# 自走棋的硬性要求：战斗必须收敛，不能变成马拉松。
	# 用 spiral 而非直线，是为了在接敌阶段就建立角速度，
	# 否则追踪机制整段失效（详见 EveDestinyMotion.spiral_thrust 的说明）。
	var distance := ship.body.position.distance_to(target.body.position)
	if distance > ship.optimal_range + ship.falloff:
		var accel_close := EveDestinyMotion.spiral_thrust(
			ship.body, target.body, want_range, elapsed, dt)
		ship.body.acceleration = accel_close
		return

	var accel := EveDestinyMotion.command_to_acceleration(
		ship.body, target.body, ship.stance, want_range,
		dt, elapsed
	)
	ship.body.acceleration = accel


# ------------------------------------------------------------------ 电容

func _update_capacitor(ship: EveShip, dt: float) -> void:
	# 开火时会额外耗电（已在开火时扣），这里跑回充与干涸状态机
	var result := EveCombatCore.update_capacitor(
		ship.cap, ship.cap_max, ship.cap_regen,
		ship.cap_use * 0.5, ship.cap_dry, dt
	)
	ship.cap = float(result["cap"])
	var was_dry := ship.cap_dry
	ship.cap_dry = bool(result["cap_dry"])
	if ship.cap_dry != was_dry:
		if ship.cap_dry:
			_log(&"ewar", "%s 电容干涸，主动修理停止" % ship.ship_name)
		else:
			_log(&"ewar", "%s 电容已恢复" % ship.ship_name)


# ------------------------------------------------------------------ ★ 后勤

## 后勤舰给友军修血。每 `logistics_cycle` 秒触发一次。
##
## ⚠️ 三条口径（改之前先读 `eve_ship_database.gd` 文件头的 A/B 两段）：
##   ① ★ **只修同队、且含自己**（2026-10-01 改，原先不含自己）——
##      「含自己」是 `_pick_repair_target()` 的命门，理由见该函数头长注释，
##      一句话：敌方恒先打最近 ⇒ 后勤站前排 ⇒ 只有后勤自己掉血 ⇒ 不含自己 = 全程空转。
##   ② 目标 = **同层百分比最低**的那一艘（不是绝对差值最低）。
##      绝对差值会让后勤舰永远盯着大船，脆皮被放生。
##   ③ 一帧最多修一艘（一个后勤舰一个目标）。
##      多目标会让「后勤越多越无敌」，整局会打不完（同 REPAIR_ACTIVE_SCALE 的教训）。
##
## ⚠️ 计时用 `dt` 累加而不是墙钟：验收在无头环境里按固定步长推进，
##    用墙钟会让「45 秒」这件事在测试与实际之间对不上
##    （红线 14「音频节流吃 sim.elapsed 不吃墙钟」是同一个道理）。
func _replenish_own_ships(ships_arr: Array, dt: float) -> void:
	# 只收集「能当后勤的活船」，先做完一轮再动手 —— 免得遍历中改状态。
	var medics: Array = []
	for s in ships_arr:
		if s.alive and s.is_logistics_unit():
			medics.append(s)
	if medics.is_empty():
		return
	for m in medics:
		m.logistics_timer -= dt
		if m.logistics_timer > 0.0:
			continue
		# 倒计时到点：**先重置再找目标**（找不到目标也不该把计时器留成负数，
		# 否则下一帧立刻再触发一次，节流形同虚设）。
		m.logistics_timer = m.logistics_cycle
		var t := _pick_repair_target(m, ships_arr)
		if t == null:
			continue
		# ⚠️ 显式标注 float：`m` 来自无类型 Array ⇒ 它的方法返回 Variant，
		#    `:=` 推断会报 "Cannot infer the type"（踩过）。
		var gained: float = m.repair_ally(t)
		if gained > 0.0:
			_log(&"repair", "%s → %s %s +%d" % [
					m.ship_name, t.ship_name, _layer_text(m.logistics_layer),
					int(roundf(gained))])


## 挑一个最该修的友军。返回 null = 没有可修的。
##
## 判据 = **那一层的剩余百分比最低**，且未满血、未阵亡。
## ⚠️ 百分比用 `hp / max_hp`，两层各自的分母不同 —— 这是对的：
##    甲抗船的装甲池天生比盾抗船的厚，用同一把尺子量才是公平的。
##
## ★★ 2026-10-01 修：**候选集合改为「含自己在内」**。
##
## 旧版把自己排除在外（理由写着「自己的回充走原生路径，两套不叠加」）。
## 那条理由本身没错，但它导致了一个**真实的空转 bug**：
##
##   敌方索敌 `_score_target` 的主项是 `-dist` ⇒ **双方都先打最近的船**。
##   编队里后勤站位与攻击型一样靠前 ⇒ 后勤成了最近目标 ⇒ 两艘敌舰从开战
##   起全程锁死后勤（实测 f=0 到结束，敌1/敌2 的 `target_id` 一直是后勤）。
##   于是**队友全程一滴血都没掉**，而后勤自己又不能修自己
##   ⇒ 可修窗口 **0/724 帧 = 0.0%**，`repaired_total` 恒为 0。
##   ⇒ 修量调到 ×2 / ×4 / 周期减半 都还是 0（`probe_logi_throughput` 实测）。
##
## 云顶之弈的辅助单位（索拉卡 / 璐璐这类）**治疗目标包含自己**，正是因为
## 「最近的先被打」在那边同样成立 —— 辅助不能自保就会变成废人。
## 加上自己之后实测可修窗口 **0% → 20.7%**（同上探针）。
##
## ⚠️ 与原生回充的关系：两者**不冲突也不重复**。原生回充是 `EveCombatCore.repair()`
##    里那条 EVE 公式（`passive_shield` 峰值 2.0/s，只在护盾层）；
##    这里是每 `logistics_cycle` 秒一次的主动修理。一个是被动小水流、
##    一个是主动大剂量，叠在同一层上是**设计意图**（后勤能给自己续命），
##    不是重复计数 —— 血池是同一本账，谁写进去都算数，不存在"算了两次"。
func _pick_repair_target(medic: EveShip, ships_arr: Array) -> EveShip:
	var layer: StringName = medic.logistics_layer
	if layer.is_empty():
		return null
	var best: EveShip = null
	var best_frac := 1.0
	for s in ships_arr:
		# ⛔ 只排除「死的 / 敌方的」，**不再排除自己**（见上方说明）。
		if not s.alive:
			continue
		if s.team != medic.team:
			continue
		var cap := float(s.max_hp.get(layer, 0.0))
		if cap <= 0.0:
			continue
		var frac := clampf(float(s.hp.get(layer, 0.0)) / cap, 0.0, 1.0)
		if frac >= 0.999:
			continue                       # 满血不修（别浪费修理周期）
		if frac < best_frac:
			best_frac = frac
			best = s
	return best


# ------------------------------------------------------------------ 结算

func _check_outcome() -> void:
	var own_alive := 0
	var enemy_alive := 0
	for s in ships:
		if not s.alive:
			continue
		if s.team == 0:
			own_alive += 1
		else:
			enemy_alive += 1

	if own_alive == 0 and enemy_alive == 0:
		_finish(-1)
	elif enemy_alive == 0:
		_finish(0)
	elif own_alive == 0:
		_finish(1)
	elif elapsed >= time_limit_seconds() * HARD_STOP_MULT:
		# ★ 2026-10-01（第二次改）：**取消超时判负**。
		#
		#   用户原话：「自走棋就该在时限内战斗，直到被击毁」
		#             「这个因素必须排除，这不对，非常不符合自走棋直觉」
		#   ⇒ 战斗只以**一方全灭**结束（上面三条分支）。收敛由火力渐增保证。
		#
		#   这里只剩**安全网**：真到了 3 倍时限还分不出（理论上不可能，
		#   那时伤害已经 20 倍），才按剩余血量强制收尾。
		#
		# ⚠️ 判定用 `elapsed`（秒），**不用 tick** —— tick 按帧累加，
		#    帧率一变就和顶条对不上（这正是本次修的那个 bug）。
		_log(&"system", "僵持过久 —— 按剩余战力判定收场")
		var own_hp := _total_hp_of_team(0)
		var foe_hp := _total_hp_of_team(1)
		_finish(0 if own_hp >= foe_hp else 1)


func _total_hp_of_team(team: int) -> float:
	var total := 0.0
	for s in ships:
		if s.alive and s.team == team:
			total += s.total_hp()
	return total


func _finish(team: int) -> void:
	if finished:
		return
	finished = true
	winner_team = team
	var text := "平局"
	if team == 0:
		text = "己方胜利"
	elif team == 1:
		text = "己方战败"
	_log(&"system", "战斗结束：%s（用时 %.1fs）" % [text, elapsed])
	battle_finished.emit(team)


# ------------------------------------------------------------------ 工具

func _log(category: StringName, text: String) -> void:
	log_entries.append(LogEntry.new(elapsed, category, text))
	# 限制日志长度，避免长局内存膨胀
	if log_entries.size() > 2000:
		log_entries = log_entries.slice(log_entries.size() - 1500)


static func _quality_text(q: int) -> String:
	match q:
		EveCombatCore.HitQuality.WRECKING: return "毁灭打击"
		EveCombatCore.HitQuality.SMASHING: return "重创"
		EveCombatCore.HitQuality.PENETRATING: return "穿透"
		EveCombatCore.HitQuality.HIT: return "命中"
		EveCombatCore.HitQuality.LIGHT: return "轻伤"
		EveCombatCore.HitQuality.BARELY: return "擦过"
		_: return "未命中"


static func _layer_text(layer: StringName) -> String:
	match layer:
		&"shield": return "护盾"
		&"armor": return "装甲"
		_: return "结构"


## 战斗统计（供结算面板）
func statistics() -> Dictionary:
	var total_dealt := 0.0
	for s in ships:
		total_dealt += s.damage_dealt
	return {
		"duration": elapsed,
		"ticks": tick,
		"winner": winner_team,
		"total_damage": total_dealt,
		"log_count": log_entries.size(),
	}
