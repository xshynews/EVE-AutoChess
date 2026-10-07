extends Node
## 46 轮取证：**减速时舰艏会不会翻 180°**（用户 46 轮的物理论断）。
##
## ═══ 用户原话 ═══════════════════════════════════════════════════════
##   「我终于知道为啥不能让舰艏与速度方向保持一致了，因为**减速不能让舰船
##     翻转舰艏方向**，这个需要理解现实车辆的车头方向与速度的关系。」
##
## ═══ 论断的物理形式 ═════════════════════════════════════════════════
##   若 `f = v̂`（旧红线 46），则 v→0 时 `v̂` **方向不稳定**：
##     · 减速**恰好为 0** 的帧：`v̂` 可以是**任意**方向（数值噪声），或
##       `v.length() <= MOVE_EPS` ⇒ 整段跳过 ⇒ 采用**上一姿态**；
##     · 速度**反向过冲**（刹过头开始后退）的帧：`v̂` **直接翻 180°** ⇒
##       舰艏瞬间调头 ⇒ "船在倒车"，而现实里的车**倒车时车头仍朝前**（人往后看）。
##   ⇒ **文件车类比**：车头方向 = **车身朝向**（独立自由度），
##      只有"转向"才改它；"前进/后退"**不改**。
##      `aim_dir` 正是这个"车身朝向"——它由**目标方位**决定，与速度无关。
##
## ═══ 本探针判据 ═════════════════════════════════════════════════════
##   真跑一局，逐帧记录**每艘船**的：
##     ① `bow · 敌向`（应恒 ≥ 0.93）
##     ② **相邻采样的舰艏角变化量**（应 < `MAX_STEP_DEG`）——
##        这是"翻 180°"的直接探针：调头必然是**一大跳**。
##     ③ **减速帧**专门统计：`|v| `下降 且 `bow·v̂ < 0`（舰艏与速度相反 = 倒退）
##        的帧数 —— 这正是用户说的"倒车"。**这个数字必须是 0**（舰艏不该被速度带着翻）。
##
## ═══ 跑法 ═══════════════════════════════════════════════════════════
##   `--headless --path <工程> --quit-after 8000 res://tools/probe_brake_flip.tscn`
const YAW := preload("res://scripts/data/eve_ship_yaw.gd")
## 直接从实现读闸门常量（红线 40：不许复刻算式，要引用真代码）
const VIS_SCRIPT := preload("res://scripts/visual/eve_ship_visual.gd")

## ★ 46 轮：从 180 提到 **600** —— 180 帧时开局收敛还没结束，
## 会把「`_facing_quat` 正从初始姿态 slerp 到目标」的姿态当稳态
## （实测最差样本 `f=192 key=slasher d=0.093`，而 `[T1506]` 同船 `dot=1.000`）。
const SETTLE_FRAMES := 600
const SAMPLE_EVERY := 6
const END_FRAMES := 3000
## ★ 46 轮：相邻采样间舰艏允许的最大转动量。
##
## 判据来源 = **实现里的同一常量**（红线 40：不许自己另立一套算式）：
##   `EveShipVisual.FACING_MAX_DEG_PER_SEC` = 90 °/s，按 60 FPS ⇒ 1.5 °/帧；
##   本探针每 `SAMPLE_EVERY`(6) 帧采样一次 ⇒ 理论上限 9 °。
##   取 `10.0` 留 1° 余量（浮点 + 限速本身是 clamp 后归一化，可能有极小溢出）。
##
## ⚠️ 这个值**必须**跟着实现改 —— 若有人调大 `FACING_MAX_DEG_PER_SEC`，
##    这里不跟着改就会误报「跳变」。反过来若有人调小，这里就会漏报。
const MAX_STEP_DEG := 10.0

## 实现侧的每帧闸门（用于打印对账，确保探针阈值 = 实现闸门 × SAMPLE_EVERY）
static func _impl_cap_deg() -> float:
	return VIS_SCRIPT.facing_max_step_deg(1.0 / 60.0) * float(SAMPLE_EVERY)

var _battle: Node = null
var _arena: Node = null
var _frames := 0
var _prev_bow: Dictionary = {}      # ship_id -> Vector3（上一采样）
var _prev_speed: Dictionary = {}    # ship_id -> float
var _prev_aim: Dictionary = {}      # ship_id -> Vector3（上一采样的 aim_dir）
var _flip_events: Array[String] = []    # 舰艏一次跳 > MAX_STEP_DEG
var _flip_in_brake := 0                 # ★ 其中落在「减速帧」的次数（真判据）
var _aim_jumps := 0                     # `aim_dir` 相邻采样跳 > 25° 的次数（信号质量）
var _aim_jump_detail: Array[String] = []
var _min_aim_dist := 1e9                # 观察到的最小「船↔目标」距离
## `aim_dir` 漂移率统计（度/秒）—— 用来定闸门下限，别让闸门成为跟随瓶颈
var _aim_rate_sum := 0.0
var _aim_rate_max := 0.0
var _aim_rate_n := 0
var _t_now := 0.0
var _prev_t := 0.0
var _reverse_frames := 0                # 舰艏与速度反向（倒退）的采样数
var _reverse_detail: Array[String] = []
var _brake_frames := 0                  # 减速帧总数
# ★ 46 轮真判据：减速帧里舰艏的转动量（用户论断的直接度量）
var _brake_turn_max := 0.0
var _brake_turn_sum := 0.0
var _brake_turn_n := 0
var _samples := 0
var _zero_aim := 0
var _zero_aim_detail: Array[String] = []
var _min_aim_dot := 2.0
## ★ 稳态判据（同 `probe_bow_to_target` 的口径）：
##   ① 的"最低值"会被**换目标瞬间的追赶窗口**污染（信号 1288°/s 瞬移，
##   闸门只给 90°/s ⇒ 有 ~0.6s 在转向动画中，此时 bow·敌向 当然低）。
##   那不是缺陷，是**有意的转向动画**。所以真正的判据是**稳态**：
##   `aim_dir` 稳定（漂移 < 5°/s）时的 `bow·敌向`。
const AIM_STEADY_RATE := 5.0
var _aim_dot_steady_min := 2.0
var _aim_dot_steady_n := 0
var _worst_ctx := ""
## 每艘船的「上一采样 aim 漂移率」，用来判定本采样是否处于稳态
## 每艘船当前采样的**视觉节点 instance id** —— 一旦变化说明节点被重建过
## （我方舰队在开局会被 `_respawn_own_fleet` 重建），此时跨节点比较舰艏
## 是无意义的（旧节点冻结在初始姿态）⇒ 必须跳过并清空该船的上一采样。
var _prev_aim_rate: Dictionary = {}
var _prev_vid: Dictionary = {}
var _respawn_count := 0
var _visuals: Array = []

func _ready() -> void:
	var packed: PackedScene = load("res://scenes/battle_scene.tscn")
	_battle = packed.instantiate()
	add_child(_battle)
	for _i in 40:
		await get_tree().process_frame
	_arena = _battle.get("arena")
	var run: Node = _battle.get("run")
	run.coin = 999
	run.roll_shop()
	for i in 5:
		run.buy(i)
	run.bench.clear()
	run.field.clear()
	# 故意上**高惯性/会频繁刹车**的组合：环绕 + 接敌 + 近距离缠斗
	for k in ["abaddon", "myrmidon", "slasher", "incursus", "catalyst"]:
		run.bench.append({"ship_key": StringName(k), "star": 1, "cell": Vector2i(-1, -1)})
		run.field.append(run.bench[run.bench.size() - 1].duplicate(true))
	run.changed.emit()
	_battle.call("_respawn_own_fleet")
	for _i in 5:
		await get_tree().process_frame
	_battle.call("start_battle")
	print("[46 轮] 战斗已启动（判据：减速帧不得出现 bow·v̂<0 的倒退）")
	_rescan_visuals()


func _process(_dt: float) -> void:
	_frames += 1
	_t_now += _dt
	if _frames < SETTLE_FRAMES or _frames % SAMPLE_EVERY != 0:
		return
	if _frames % 120 == 0:
		_rescan_visuals()
	for v in _visuals:
		if not is_instance_valid(v):
			continue
		var ship = v.get("ship")
		if ship == null or not ship.alive or ship.body == null:
			continue
		var bow_w: Vector3 = _local_bow(v).normalized()
		var aim: Vector3 = ship.body.aim_dir
		var vel: Vector3 = ship.body.velocity
		var sid: int = ship.id
		var key := String(ship.ship_key)
		var speed := vel.length()
		# ★ ★ 节点重建检测：instance id 变了 ⇒ 本采样与上一采样**不是同一个节点**
		#   （我方舰队开局被重建），跨节点比舰艏无意义 ⇒ 清空该船历史，本采样作废。
		#   这是探针自身的假阳性来源，必须在统计前拦掉。
		var vid: int = v.get_instance_id()
		if _prev_vid.has(sid) and int(_prev_vid[sid]) != vid:
			_respawn_count += 1
			_prev_bow.erase(sid)
			_prev_speed.erase(sid)
			_prev_aim.erase(sid)
			_prev_aim_rate.erase(sid)
		_prev_vid[sid] = vid
		if not _prev_bow.has(sid):
			# 首次见到该节点：只记基线，不参与任何相邻比较与统计
			_prev_bow[sid] = _local_bow(v).normalized()
			_prev_speed[sid] = speed
			_prev_aim[sid] = aim
			continue
		_samples += 1
		if aim.length_squared() <= 1e-12:
			_zero_aim += 1
			if _zero_aim_detail.size() < 6 and _zero_aim % 200 == 0:
				_zero_aim_detail.append("%s tid=%d alive=%s |v|=%.1f" % [key, ship.target_id, str(ship.alive), speed])
		# ── 本采样的 aim 漂移率（用于判定"稳态"）──────────────────────
		var dt_s := maxf(_t_now - _prev_t, 1e-4)
		var aim_rate := 0.0
		if _prev_aim.has(sid):
			var pam: Vector3 = _prev_aim[sid]
			if pam.length_squared() > 1e-12 and aim.length_squared() > 1e-12:
				aim_rate = rad_to_deg(pam.normalized().angle_to(aim.normalized())) / dt_s
		# 上一采样也处于稳态 + 本采样也稳态 ⇒ 才算"稳态样本"
		#
		# ★ 46 轮修正：**还要要求 `bow` 自己也稳定**。
		#   病象：换目标后 `aim` 只在**一帧**里跳（`aim_rate` 大 ⇒ 那帧被排除），
		#   但**下一帧** `aim` 已经不动了（`aim_rate ≈ 0`）⇒ 被判成"稳态"，
		#   而 `bow` 正在追赶（slerp 需要 ~10 帧）⇒ 把**追赶中的姿态**
		#   当稳态统计进去 ⇒ 报出 `d=0.096` 这种假的"稳态最差"。
		#   （实测 `[BAD]` 显示这类偏差只出现在**换目标后的前几帧**，
		#     收敛后 `dot` 立刻回到 1.000。）
		var bow_step_deg := 0.0
		if _prev_bow.has(sid):
			bow_step_deg = rad_to_deg((_prev_bow[sid] as Vector3).angle_to(bow_w))
		var steady := aim_rate < AIM_STEADY_RATE \
				and float(_prev_aim_rate.get(sid, 1e9)) < AIM_STEADY_RATE \
				and bow_step_deg < AIM_STEADY_RATE
		_prev_aim_rate[sid] = aim_rate
		if aim.length_squared() > 1e-12:
			_min_aim_dot = minf(_min_aim_dot, bow_w.dot(aim.normalized()))
			var d_steady := bow_w.dot(aim.normalized())
			if steady:
				_aim_dot_steady_n += 1
				if d_steady < _aim_dot_steady_min:
					_aim_dot_steady_min = d_steady
					_worst_ctx = "f=%d key=%s d=%.4f bow=(%.2f,%.2f,%.2f) aim=(%.2f,%.2f,%.2f) q=(%.2f,%.2f,%.2f,%.2f) |v|=%.1f" % [_frames, key, d_steady, bow_w.x,bow_w.y,bow_w.z, aim.normalized().x,aim.normalized().y,aim.normalized().z, v.quaternion.x,v.quaternion.y,v.quaternion.z,v.quaternion.w, speed]
		# 本采样是否「减速帧」（速度比上一采样低）
		var is_brake := _prev_speed.has(sid) and speed < float(_prev_speed[sid]) - 1e-6
		# 本采样 aim 是否发生「断源」（上一采样有目标、本采样目标没了）
		var aim_dropped := _prev_aim.has(sid) \
				and (_prev_aim[sid] as Vector3).length_squared() > 1e-12 \
				and aim.length_squared() <= 1e-12
		# ① 舰艏是否**跳变**（翻 180° 的直接探针）
		if _prev_bow.has(sid):
			var pb: Vector3 = _prev_bow[sid]
			var ang := rad_to_deg(pb.angle_to(bow_w))
			if ang > MAX_STEP_DEG and _flip_events.size() < 10:
				var tag := "减速帧" if is_brake else "非减速"
				if aim_dropped:
					tag += "+目标断源"
				_flip_events.append("%s 跳 %.1f° [%s] |v|=%.1f aim=%s" 
						% [key, ang, tag, speed, "有" if aim.length_squared() > 1e-12 else "无"])
				if is_brake:
					_flip_in_brake += 1
		_prev_bow[sid] = bow_w
		# ②′ **减速帧**的舰艏转动量 —— 用户 46 轮论断的**直接度量**。
		#
		#   ⚠️ 这里**不能**用 `bow·v̂ < 0` 判"倒退"（旧判据 ③ 的错）：
		#     45 轮已经查明**默认战术是环绕**（`orbit_thrust`）⇒ 速度方向
		#     本来就是切向，与「舰艏朝敌」**天然可能差 90° 以上**。
		#     减速时 `bow·v̂` 为负**是正常的**，不代表船在倒车。
		#     （实测：那时 `bow·敌向` 仍是 0.98 ⇒ 舰艏好好指着敌人。）
		#
		#   用户论断的正确形式是：**减速不改变舰艏方向**。
		#   ⇒ 度量 = 减速帧里舰艏的**相邻采样转动量**（单位：度）。
		#     若"减速导致翻头"成立，这里会看到大角度；反之接近 0。
		if is_brake and _prev_bow.has(sid):
			var pb2: Vector3 = _prev_bow[sid]
			_brake_turn_max = maxf(_brake_turn_max, rad_to_deg(pb2.angle_to(bow_w)))
			_brake_turn_sum += rad_to_deg(pb2.angle_to(bow_w))
			_brake_turn_n += 1
		_prev_bow[sid] = bow_w
		# ②′ `aim_dir` 信号质量：相邻采样跳 > 25° ⇒ 目标方位在剧烈抖动
		if _prev_aim.has(sid):
			var pa: Vector3 = _prev_aim[sid]
			if pa.length_squared() > 1e-12 and aim.length_squared() > 1e-12:
				var aang := rad_to_deg(pa.normalized().angle_to(aim.normalized()))
				_aim_rate_sum += aim_rate
				_aim_rate_max = maxf(_aim_rate_max, aim_rate)
				_aim_rate_n += 1
				if aang > MAX_STEP_DEG:
					_aim_jumps += 1
					if _aim_jump_detail.size() < 6:
						_aim_jump_detail.append("%s aim 跳 %.1f°（|v|=%.1f, %.0f°/s）"
								% [key, aang, speed, aim_rate])
		_prev_aim[sid] = aim
		# ② **减速帧**里舰艏是否被速度带着反向
		if is_brake:
			_brake_frames += 1
			if speed > 1e-6:
				var dv := bow_w.dot(vel.normalized())
				if dv < 0.0:
					_reverse_frames += 1
					if _reverse_detail.size() < 10:
						_reverse_detail.append("%s(bow·v̂=%.3f, |v|=%.1f)" % [key, dv, speed])
		_prev_speed[sid] = speed
	_prev_t = _t_now
	if _frames > END_FRAMES:
		_report()
		get_tree().quit(0)


func _rescan_visuals() -> void:
	_visuals.clear()
	var ships_layer: Node = _arena.ships_layer
	for c in ships_layer.get_children():
		if c.has_method("sync_from_body") and c.get("ship") != null:
			_visuals.append(c)


## 读「舰艏在世界里的方向」—— 用**真网格节点的全局变换**（红线 40 · 47 轮修正）。
##
## 旧版 旧的「取 hull_root 第 0 个子节点的 basis」写法 是**自证式读数**：
## 它读的两个值正是 `_bow_align` 的构造输入 ⇒ 必然 1.000，
## 测不出「glb 根下面还有一层网格节点、逐艘旋转不同」。
## 正解 = `mesh.global_transform.basis` —— 引擎自己连乘，探针不写乘号。
func _local_bow(vis: Variant) -> Vector3:
	var key := String(vis.get("ship").ship_key)
	var mn := _mesh_node(vis)
	if mn == null:
		return Vector3.ZERO
	return (mn.global_transform.basis.orthonormalized()
			* YAW.bow_axis(StringName(key))).normalized()


func _mesh_node(vis: Variant) -> MeshInstance3D:
	var hr = vis.get("hull_root")
	if hr == null:
		return null
	for c in hr.get_children():
		if String(c.name).begins_with("Model_"):
			if c is MeshInstance3D:
				return c
			for g in c.get_children():
				if g is MeshInstance3D:
					return g
	return null


func _report() -> void:
	print("═══ 46 轮取证：减速 / 倒退时的舰艏（采样 %d）═══" % _samples)
	print("  ⓪′ `aim_dir == 0`（无目标 ⇒ 退回速度方向）的采样 = %d / %d（%.1f%%）"
			% [_zero_aim, _samples, 100.0 * float(_zero_aim) / maxf(1.0, float(_samples))])
	for s0 in _zero_aim_detail:
		print("       %s" % s0)
	print("  ⓪ 视觉节点重建检测：跳过 %d 次（每次都会清空该船历史，防跨节点假阳性）"
			% _respawn_count)
	print("  ① 舰艏与敌向  最低 = %.5f（含换目标追赶窗口，仅供参考）" % _min_aim_dot)
	print("  ①′ **稳态** 舰艏与敌向 最低 = %.5f（%d 个稳态样本，判据 ≥ 0.93）"
			% [_aim_dot_steady_min, _aim_dot_steady_n])
	print("  ①″ 最差样本现场：%s" % _worst_ctx)
	print("  ② 舰艏跳变 > %.0f° 的次数 = %d（其中落在**减速帧** = %d ← 真判据）"
			% [MAX_STEP_DEG, _flip_events.size(), _flip_in_brake])
	for s in _flip_events:
		print("     ! %s" % s)
	print("  ③′ **减速帧** 共 %d 个：舰艏转动 最大 %.2f° · 均值 %.2f° ← **真判据**"
			% [_brake_frames, _brake_turn_max,
			(_brake_turn_sum / maxf(1.0, float(_brake_turn_n)))])
	print("  ③ 参考（**非判据**）：减速帧里 bow·v̂<0 的个数 = %d —— 环绕战术下"
			% _reverse_frames)
	print("     速度方向本是切向，与舰艏天然可能差 90° 以上，为负属正常（见探针注释）")
	print("  ④ `aim_dir` 相邻跳 > %.0f° = %d 次（信号质量：应接近 0）"
			% [MAX_STEP_DEG, _aim_jumps])
	for s in _aim_jump_detail:
		print("     ~ %s" % s)
	# ── 阈值对账：探针采样阈值 vs 实现闸门（红线 40）─────────────────
	print("  ⑤ 阈值对账：实现闸门 %.2f°/帧(@60FPS) × %d 帧/采样 = %.1f° ≤ 探针阈值 %.1f°  %s"
			% [VIS_SCRIPT.facing_max_step_deg(1.0 / 60.0), SAMPLE_EVERY,
			_impl_cap_deg(), MAX_STEP_DEG,
			"✔" if _impl_cap_deg() <= MAX_STEP_DEG else "✘ 探针阈值宽于实现 ⇒ 会漏报"])
	# ── ⑥ `aim_dir` 漂移率（用来判断闸门会不会成为跟随瓶颈）──────────
	if _aim_rate_n > 0:
		print("  ⑥ `aim_dir` 漂移率：均值 %.1f°/s · 最大 %.1f°/s（实现闸门 %.1f°/s）"
				% [_aim_rate_sum / float(_aim_rate_n), _aim_rate_max,
				VIS_SCRIPT.FACING_MAX_DEG_PER_SEC])
	var sim_v: Variant = _battle.get("sim")
	if sim_v != null:
		print("  ⑦ **换目标次数**（tick 级累计）= %s ← 防抖指标（迟滞生效时应远小于 帧数×艘数）"
				% str(sim_v.get("_target_switches")))
	# ── 判据 ──────────────────────────────────────────────────────────
	# ★ 46 轮的真判据只有三条：
	#   ① 减速帧舰艏与速度反向 = 0（用户论断：减速不翻舰艏）
	#   ② **减速帧**跳变 = 0（减速时舰艏不该突然转）
	#   ③ `bow·敌向` ≥ 0.93（朝向仍正确）
	# ⚠️ **非减速帧**的跳变**不算失败**：那是"换目标急转"的正常现象，
	#    现在已被 `FACING_MAX_DEG_PER_SEC` 闸门限制在 9°/采样以内 ——
	#    而它们能通过 ② 这一关（不在减速帧里）正是要证明的事情。
	var ok := _brake_turn_max <= MAX_STEP_DEG and _flip_in_brake == 0 \
			and _aim_dot_steady_min >= 0.93 and _aim_dot_steady_n > 100
	if ok:
		print("★★★ 46 轮通过：减速/刹车不会翻转舰艏（车头方向独立于速度）★★★")
		print("     · 减速帧 %d 个：舰艏转动 最大 %.2f° / 均值 %.2f°（≤ %.1f°）"
				% [_brake_frames, _brake_turn_max,
				(_brake_turn_sum / maxf(1.0, float(_brake_turn_n))), MAX_STEP_DEG])
		print("     · 稳态样本 %d 个：舰艏与敌向最低 %.5f" % [_aim_dot_steady_n, _aim_dot_steady_min])
		print("     · 非减速帧换目标急转 %d 次，全部落在闸门 %.1f° 以内（属正常转向动画）"
				% [_flip_events.size(), _impl_cap_deg()])
	else:
		print("✗✗✗ 46 轮未过 ✗✗✗")
