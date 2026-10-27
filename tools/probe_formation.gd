extends Node

## 阵型 + 集火 行为体检（无头）—— 「旗舰带队跟得住吗、集火真集火了吗、还收敛吗」
##
## ══════════════════════════════════════════════════════════════════
##  为什么必须有这个探针（而不是只看 verify_run 的断言）
## ══════════════════════════════════════════════════════════════════
##  `verify_run` 验的是**契约**（旗舰选谁、target_id 是否唯一、槽位算式对不对），
##  它**量不出**实战里最要命的三件事：
##    ① **收敛性**：集火把全队火力压在一个人身上，是不是反而打不完？
##       （自走棋红线：战斗必须分出胜负 —— 45 轮"超时判负"的老病根）
##    ② **队形是否真的保持**：跟班会不会被甩下、或者全挤成一团？
##    ③ **集火是否真的持续**：会不会每 5 tick 换一次目标
##       （全队换目标 = 全员重新锁定 3.5 秒 ⇒ 谁都开不了火）。
##
## ⚠️ 本探针**只读**：不写存档、不改任何表。
##
## ── 判据 ─────────────────────────────────────────────────────────
##   · 收敛率：跑的每一局都必须在 MAX_TICKS 内 `finished`
##   · 队形离散度：各船到「旗舰身后槽位」的平均距离（越小越整齐）
##   · 目标切换率：`switch_count / elapsed`（目标：远低于 1 次/秒）
##   · 同一时刻全队 target_id 唯一性

const RUN := preload("res://scripts/core/eve_run_state.gd")
const SIM := preload("res://scripts/core/eve_battle_simulator.gd")
const DB := preload("res://scripts/core/eve_ship_database.gd")
const PLANS := preload("res://scripts/data/eve_enemy_plans.gd")

## 对称对局（同一艘船对同一艘船）—— 用来暴露"谁都打不死谁"这种收敛问题
const MIRROR := "punisher"
## 典型中局阵容（3 种吨位混合，覆盖"旗舰是战列、跟班是护卫"的真实形状）
const MIXED := ["abaddon", "omen", "cormorant", "punisher", "punisher"]

var _lines: PackedStringArray = PackedStringArray()


func _ready() -> void:
	_lines.append("# 阵型 + 集火 行为体检")
	_lines.append("")
	_case("镜像 3v3（%s）" % MIRROR, [MIRROR, MIRROR, MIRROR], [MIRROR, MIRROR, MIRROR], 9101)
	_case("镜像 5v5（%s）" % MIRROR, [MIRROR, MIRROR, MIRROR, MIRROR, MIRROR],
			[MIRROR, MIRROR, MIRROR, MIRROR, MIRROR], 9102)
	_case("混编 5v5（旗舰=战列）", MIXED, MIXED, 9103)
	_case("混编 5v5 vs 镜像护卫 5", MIXED, [MIRROR, MIRROR, MIRROR, MIRROR, MIRROR], 9104)
	# ★ 真实节点：N9 是「远程压制组 STANDOFF」，最容易出现"谁都够不着"
	_case("N9 程序化编组 vs 混编", MIXED, _plan_ids(9, 9105), 9105)
	_case("N15 程序化编组 vs 混编", MIXED, _plan_ids(15, 9106), 9106)
	# ★ 真实开局口径：arena 的 `deploy_standoff_ratio` 只有 1.15
	#   （两队质心相距 ≈ 15 km，**多数船开局就在射程内**）。
	#   这一例就是为了回答「玩家在真局里到底看不看得见队形」——
	#   上面 6 例的 28~40 km 间距比真实开局远得多。
	_case("镜像 5v5 · 真实开局间距（14 km）",
			[MIRROR, MIRROR, MIRROR, MIRROR, MIRROR],
			[MIRROR, MIRROR, MIRROR, MIRROR, MIRROR], 9107, 7_000.0)

	print("\n".join(_lines))
	get_tree().quit()


## 我方**存活船里有几成**处在「够得着主目标」的位置（0..1）。
##
## ⚠️ 与主代码 `_fleet_covered` 的判据**故意不同**（那边用槽位、且要求全员）：
##    验收要能独立于被测方发现「覆盖判据写歪了」—— 两边写得一样就抓不出错。
func _in_reach_ratio(sim, team: int) -> float:
	var focus: EveShip = sim.focus_target_of(team)
	var in_reach := 0
	var alive := 0
	for s in sim.ships:
		if not s.alive or s.team != team:
			continue
		alive += 1
		if focus != null and focus.alive \
				and s.body.position.distance_to(focus.body.position) \
						<= s.optimal_range + s.falloff:
			in_reach += 1
	return float(in_reach) / float(alive) if alive > 0 else 0.0


## 两队**质心**间距（米）。用质心而不是"最近两艘"：质心对单舰机动不敏感，
## 量的才是「两军拉开多远」。
func _centroid_gap(sim) -> float:
	var c0 := Vector3.ZERO
	var c1 := Vector3.ZERO
	var n0 := 0
	var n1 := 0
	for s in sim.ships:
		if s.team == 0:
			c0 += s.body.position
			n0 += 1
		else:
			c1 += s.body.position
			n1 += 1
	if n0 == 0 or n1 == 0:
		return 0.0
	return (c0 / float(n0)).distance_to(c1 / float(n1))


func _plan_ids(node: int, seed_: int) -> Array:
	var out: Array = []
	for sid in PLANS.ship_ids(node, seed_):
		out.append(String(sid))
	return out


func _case(title: String, own_ids: Array, foe_ids: Array, seed_: int,
		standoff := 14_000.0) -> void:
	var own: Array[EveShip] = []
	var foe: Array[EveShip] = []
	var uid := 1
	for sid in own_ids:
		own.append(DB.instantiate_by_id(String(sid), 0, uid))
		uid += 1
	for sid in foe_ids:
		foe.append(DB.instantiate_by_id(String(sid), 1, uid))
		uid += 1

	var sim := SIM.new()
	sim.set_seed(seed_)
	sim.setup(own, foe)
	_place(own, -1, standoff)
	_place(foe, 1, standoff)

	# ── 统计量 ──
	var switch_count := 0
	var last_targets: Dictionary = {}      ## ship id → target id（用于数切换）
	var focus_ok := 0                      ## 每次抽样时"全队同目标"的次数
	var focus_samples := 0
	var slot_err_sum := 0.0                ## 跟班到槽位的距离和（整场）
	var slot_err_n := 0
	var approach_sum := 0.0                ## ★ 只统计「接敌前」——队形是给人看的那一段
	var approach_n := 0
	var first_contact := -1.0              ## 首次有任何船进入自己射程的时刻（<0 = 未接敌）
	var max_t := 0.0
	# ── 火力诊断（为什么集火会拖长战斗？）──
	# ⚠️ 用**数组当可变盒子**累加，不能用 `var shots := 0` 直接闭包累加：
	#    GDScript 的 lambda 对局部变量是**按值捕获** ⇒ `shots += 1` 改的是副本，
	#    外面永远是 0（实测本探针第一版就踩了这个坑，读数全是「开火 0 次」）。
	#    数组是引用类型，`acc[0] += 1` 才能传出来。
	var fire := [0, 0.0]                   ## [开火次数, 总伤害]
	var sep_sum := 0.0                     ## 两队质心距离之和（抽样）
	var sep_n := 0
	var stale_ticks := 0                   ## 有船够不着自己目标的抽样次数
	var total_ship_samples := 0
	var cover_sum := 0.0                   ## ★ 「在射程内」船数比例之和
	var cover_n := 0                       ## ★ 抽样次数

	sim.shot_fired.connect(func(_a, _t, _hit, _q, d): fire[0] += 1; fire[1] += float(d))

	var guard := 0
	while not sim.finished and guard < SIM.MAX_TICKS * 4:
		sim.step(SIM.FIXED_STEP)
		guard += 1
		max_t = sim.elapsed
		if guard % 5 != 0:
			continue
		# ── 两队质心距离 ──
		var c0 := Vector3.ZERO
		var c1 := Vector3.ZERO
		var n0 := 0
		var n1 := 0
		for s in sim.ships:
			if not s.alive:
				continue
			if s.team == 0:
				c0 += s.body.position
				n0 += 1
			else:
				c1 += s.body.position
				n1 += 1
		if n0 > 0 and n1 > 0:
			sep_sum += (c0 / float(n0)).distance_to(c1 / float(n1))
			sep_n += 1
		# ── 够不着目标的比例 ──
		for s in sim.ships:
			if not s.alive:
				continue
			total_ship_samples += 1
			var tg: EveShip = sim._ship_by_id.get(s.target_id)
			if tg == null or not tg.alive or s.body.position.distance_to(tg.body.position) \
					> s.optimal_range + s.falloff:
				stale_ticks += 1
		# ── 目标切换统计 ──
		for s in sim.ships:
			if not s.alive:
				continue
			if last_targets.has(s.id) and int(last_targets[s.id]) != s.target_id:
				switch_count += 1
			last_targets[s.id] = s.target_id
		# ── 全队同目标（只看双方各自）──
		for team in [0, 1]:
			var ids := {}
			for s in sim.ships:
				if s.alive and s.team == team:
					ids[s.target_id] = true
			if ids.size() > 0:
				focus_samples += 1
				if ids.size() == 1:
					focus_ok += 1
		# ── 首次接敌（任何船够得着自己的目标）──
		if first_contact < 0.0:
			for s in sim.ships:
				if not s.alive:
					continue
				var t: EveShip = sim._ship_by_id.get(s.target_id)
				if t != null and t.alive and s.body.position.distance_to(t.body.position) \
						<= s.optimal_range + s.falloff:
					first_contact = sim.elapsed
					break
		# ── 队形离散度（只量我方跟班）──
		var flag: EveShip = sim.flagship_of(0)
		var heading := _heading(sim, 0, flag)
		if flag != null and flag.alive:
			for s in sim.ships:
				if not s.alive or s.team != 0 or s == flag:
					continue
				var slot := SIM.formation_slot(flag, heading, _slot_of(sim, s, flag))
				var err := s.body.position.distance_to(slot)
				slot_err_sum += err
				slot_err_n += 1
				# ★ 「接敌前」才是玩家真的在看队形的那一段；一进混战，
				#   船本来就该散开去咬人，那时的槽位误差没有意义。
				if first_contact < 0.0:
					approach_sum += err
					approach_n += 1
		# ── ★ 全队「在射程内」的比例 ──
		#   ★★ 本版阵型**不再解散**（用户定案「不许各自接战」），所以这个数
		#     直接反映「有多少跟班真的在开火、还是只是排队跟着」。
		#     ⚠️ 用**比例**而不是「全员都在」：5v5 里只要一艘掉队就全变 0，
		#        读数失去分辨力（实测第一版就这么写，多个用例恒为 0%）。
		#     ⚠️ 判据用「各自实际位置 vs 主目标」的粗口径，与主代码
		#        `_fleet_covered`（用槽位）**故意不同**：验收要独立于被测方。
		var cr := _in_reach_ratio(sim, 0)
		cover_sum += cr
		cover_n += 1

	var verdict := "✅ 收敛" if sim.finished else "❌ 未收敛"
	if not sim.finished:
		verdict += "（跑了 %.1fs 仍未分胜负）" % max_t
	else:
		# ⚠️ 「时限内」才是玩家视角的合格线：节点时限 45/55/70s，
		#    但结算层按 180s（`MAX_TICKS`）兜底 ⇒ 拿 180s 当判据。
		var in_limit := max_t <= SIM.MAX_TICKS / SIM.TICK_RATE
		verdict += "，用时 %.1fs %s，胜方 team=%d，剩余我方 %d / 敌方 %d" % [
				max_t, "（✅ 在 180s 兜底内）" if in_limit else "（⚠️ 超过 180s 兜底）",
				sim.winner_team,
				_count_alive(sim, 0), _count_alive(sim, 1)]

	_lines.append("## %s" % title)
	_lines.append("")
	_lines.append("- %s" % verdict)
	_lines.append("- 首次接敌：%s" % ("—（全程未接敌）" if first_contact < 0.0
			else "%.1fs" % first_contact))
	_lines.append("- 集火一致性：%d/%d 次抽样为「全队同目标」（%.1f%%）"
			% [focus_ok, focus_samples,
					100.0 * float(focus_ok) / maxf(1.0, float(focus_samples))])
	_lines.append("- 目标切换：%d 次 / %.1fs = **%.2f 次/秒**（越低越好；换目标=重新锁定）"
			% [switch_count, max_t, float(switch_count) / maxf(0.1, max_t)])
	_lines.append("- ★ 队形离散度（**接敌前**，玩家真在看的那一段）：**%.0f m**"
			% (approach_sum / maxf(1.0, float(approach_n))))
	_lines.append("- ★ 在射程内比例：**%.0f%%**（抽样均值）—— 跟班真的在开火，不是排队跟着"
			% (100.0 * cover_sum / maxf(1.0, float(cover_n))))
	_lines.append("- 队形离散度（整场含混战）：%.0f m"
			% (slot_err_sum / maxf(1.0, float(slot_err_n))))
	_lines.append("- ★ 火力：开火 %d 次 · 总伤害 %.0f · 平均 %.2f 伤害/次"
			% [fire[0], fire[1], fire[1] / maxf(1.0, float(fire[0]))])
	_lines.append("- ★ 两队质心距离（抽样均值）：%.0f m" % (sep_sum / maxf(1.0, float(sep_n))))
	_lines.append("- ★ 目标在射程外的样本占比：%.1f%%（越低越好 —— 高说明「锁了却打不着」）"
			% (100.0 * float(stale_ticks) / maxf(1.0, float(total_ship_samples))))
	_lines.append("- 旗舰：我方 %s / 敌方 %s" % [
			_nm(sim.flagship_of(0)), _nm(sim.flagship_of(1))])
	_lines.append("")
	print("[%s] %s | 接敌前队形 %.0f m | 集火 %.0f%%" % [
			title, verdict, approach_sum / maxf(1.0, float(approach_n)),
			100.0 * float(focus_ok) / maxf(1.0, float(focus_samples))])


func _heading(sim, team: int, flag: EveShip) -> Vector3:
	if flag == null or flag.body == null:
		return Vector3.ZERO
	var v := flag.body.velocity
	v.y = 0.0
	if v.length() > flag.body.max_speed * 0.05:
		return v
	var f: EveShip = sim.focus_target_of(team)
	if f == null or f.body == null:
		return Vector3.ZERO
	var d := f.body.position - flag.body.position
	d.y = 0.0
	return d


## 复刻 `_slot_index` 的排序口径（吨位降序 + id 升序，排除旗舰）。
## ⚠️ 这里**故意**独立写一遍而不是调主代码的私有方法 —— 探针要能独立发现
##    "主代码排序口径被改坏了"，复用它就只会跟着一起错（红线 40）。
func _slot_of(sim, ship: EveShip, flag: EveShip) -> int:
	var mates: Array = []
	for s in sim.ships:
		if s.alive and s.team == ship.team and s != flag:
			mates.append(s)
	mates.sort_custom(func(a, b):
		if a.ship_class != b.ship_class:
			return a.ship_class > b.ship_class
		return a.id < b.id)
	return maxi(0, mates.find(ship))


func _count_alive(sim, team: int) -> int:
	var n := 0
	for s in sim.ships:
		if s.alive and s.team == team:
			n += 1
	return n


func _nm(s: EveShip) -> String:
	return "—" if s == null else "%s★%d" % [s.ship_name, s.star]


## 与 `EveBattleArena.default_formation()` 同口径的两排布阵。
func _place(fleet: Array[EveShip], side: int, standoff := 14_000.0) -> void:
	var col := 0
	var row := 0
	for s in fleet:
		var x := (float(col) - 1.5) * 8_000.0
		var z := float(side) * (standoff + float(row) * 6_000.0)
		s.body.position = Vector3(x, 0.0, z)
		s.body.previous_position = s.body.position
		s.body.aim_dir = Vector3(0.0, 0.0, -float(side))
		col += 1
		if col >= 4:
			col = 0
			row += 1
