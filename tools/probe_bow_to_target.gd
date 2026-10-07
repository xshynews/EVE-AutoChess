extends Node
## 45 轮验收：**实机跑一局，逐帧量「舰艏 与 敌向」的夹角**。
##
## ═══ 为什么必须新开一条（45 轮的教训）═══════════════════════════════════
##   22 轮的红线 46 把判据定为 `bow · v̂ = 1`（`tools/probe_bow_align.gd`），
##   它**永远为 1** —— 因为 `sync_from_body` 就是按 `v̂` 摆的，等于拿被测方验被测方。
##   于是 45 轮用户实机看到「舰艏与敌人方向**垂直**」时，全部已有探针都是绿的。
##
## ═══ 判据（三层，越往下越接近用户的实际观感）═══════════════════════════
##   ① **结构**：`body.aim_dir` 非零时必须真的主导朝向
##   ② **稳态均值**（★ 主判据）：`bow·敌向` 的**均值** ≥ `MEAN_MIN`
##      —— 用户看的是"这局打得怎么样"，不是单帧极值。
##      旧版（只看速度）实测均值 ≈ **0.87**（≈30° 长期偏），一眼就"不相对"。
##   ③ **瞬时下限**：单帧最低 ≥ `TOL`（允许 slerp 惯性造成的转向滞后）
##      —— 急转向瞬间必然滞后，这是**有意保留**的"船有惯性"观感，
##         所以下限比均值宽松。
##   ⚠️ 三条期望值**独立给定**（用户口径 + 红线 46 兜底），不从 `_facing_quat` 反推。
##
## ═══ 跑法 ═══════════════════════════════════════════════════════════
##   `--headless --path <工程> --quit-after 8000 res://tools/probe_bow_to_target.tscn`
##   （headless 即可：只读 `quaternion` 与 `body`，不截图）
const YAW := preload("res://scripts/data/eve_ship_yaw.gd")

## ★ 46 轮：从 180 提到 **600**。
##
## 原因（实测）：180 帧时**开局收敛还没结束** —— `_facing_quat` 正从初始姿态
## slerp 到首个目标方向，此时 `bow·敌向` 当然低（实测最低 −0.015）。
## 那不是缺陷，是"刚起飞正在转向"；把它算进"瞬时下限"就是**假失败**。
## 同款修正见 `probe_brake_flip.gd`（那边还额外要求"舰艏自身稳定"）。
##
## ⚠️ 另外 46 轮给 `_refresh_targets` 加了 **换目标迟滞**（`SWITCH_MARGIN`），
##    换目标次数从"逐帧"降到个位数 ⇒ 收敛窗口也大幅减少，
##    所以这里提高 `SETTLE_FRAMES` 后**瞬时下限**也能真正达标。
const SETTLE_FRAMES := 600      # 前 10 秒不采样（让 slerp 收敛到稳态）
const SAMPLE_EVERY := 10
const END_FRAMES := 3000        # 采到第 3000 帧（≈50 秒）
const TOL := 0.93               # 单帧瞬时下限（≈21°，覆盖急转向滞后）
const MEAN_MIN := 0.985         # ★ 稳态均值下限（≈10°，用户观感判据）
const MEAN_MIN_VEL := 0.985     # 无目标时必须严格朝速度（红线 46）

var _battle: Node = null
var _arena: Node = null
var _frames := 0
var _samples := 0
var _aim_sum := 0.0
var _aim_n := 0
var _aim_min := 2.0
var _vel_sum := 0.0
var _vel_n := 0
var _vel_min := 2.0
var _bad_aim: Array[String] = []
var _bad_vel: Array[String] = []
var _visuals: Array = []

func _ready() -> void:
	var packed: PackedScene = load("res://scenes/battle_scene.tscn")
	_battle = packed.instantiate()
	add_child(_battle)
	for _i in 40:
		await get_tree().process_frame
	_arena = _battle.get("arena")

	# demo 模式：满币 → 买满 bench → 拖到 field（与 probe_facing_visual 同源流程）
	var run: Node = _battle.get("run")
	run.coin = 999
	run.roll_shop()
	for i in 5:
		run.buy(i)
	run.bench.clear()
	run.field.clear()
	# 上 4 艘：一艘主流 + 三艘历史上被坑过的（catalyst / myrmidon / slasher）
	for k in ["abaddon", "catalyst", "myrmidon", "slasher"]:
		run.bench.append({"ship_key": StringName(k), "star": 1, "cell": Vector2i(-1, -1)})
		run.field.append(run.bench[run.bench.size() - 1].duplicate(true))
	run.changed.emit()
	_battle.call("_respawn_own_fleet")
	for _i in 5:
		await get_tree().process_frame
	_battle.call("start_battle")
	print("[45 轮] 战斗已启动")

	_rescan_visuals()
	print("[45 轮] 视觉节点 %d 个（先跑 %d 帧不采样）" % [_visuals.size(), SETTLE_FRAMES])


func _process(_dt: float) -> void:
	_frames += 1
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
		# ⚠️ 读数口径 = 整节点 quaternion × **模型空间舰艏轴**
		#    （红线 41：model.basis 含缩放 ⇒ 必须 orthonormalized；
		#      红线 46：朝向走 quaternion，不再走 rotation.y）
		var bow_w: Vector3 = _local_bow(v).normalized()
		var aim: Vector3 = ship.body.aim_dir
		var key := String(ship.ship_key)
		if aim.length_squared() > 1e-12:
			var d := bow_w.dot(aim.normalized())
			_aim_sum += d
			_aim_n += 1
			_aim_min = minf(_aim_min, d)
			if d < TOL and _bad_aim.size() < 8:
				_bad_aim.append("%s(%.3f)" % [key, d])
		else:
			var vel: Vector3 = ship.body.velocity
			if vel.length() > 1e-6:
				var d2 := bow_w.dot(vel.normalized())
				_vel_sum += d2
				_vel_n += 1
				_vel_min = minf(_vel_min, d2)
				if d2 < TOL and _bad_vel.size() < 8:
					_bad_vel.append("%s(%.3f)" % [key, d2])
		_samples += 1
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
## ⚠️ 旧版 旧的「取 hull_root 第 0 个子节点的 basis」写法 是**自证式读数** ——
##   它读的两个值正是 `_bow_align` 的构造输入，必然得 1.000，
##   测不出「glb 根节点下面还有一层网格节点、且逐艘旋转不同」。
##   改用 `mesh.global_transform.basis`（引擎自己连乘父子链）后，
##   在**未修主代码**时读数会掉到 0.0（垂直）—— 那正是用户实机看到的。
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
	var aim_mean := (_aim_sum / float(_aim_n)) if _aim_n > 0 else NAN
	var vel_mean := (_vel_sum / float(_vel_n)) if _vel_n > 0 else NAN
	print("═══ 45 轮验收：舰艏朝向（采样 %d · 有目标 %d · 无目标 %d）═══"
			% [_samples, _aim_n, _vel_n])
	print("  ① 有目标 bow·敌向：均值 = %.5f（下限 %.3f）· 最低 = %.5f（下限 %.3f）"
			% [aim_mean, MEAN_MIN, _aim_min, TOL])
	for b in _bad_aim:
		print("     ✗ 瞬时超阈 %s" % b)
	print("  ② 无目标 bow·v̂   ：均值 = %.5f（下限 %.3f）· 最低 = %.5f"
			% [vel_mean, MEAN_MIN_VEL, _vel_min])
	for b in _bad_vel:
		print("     ✗ 瞬时超阈 %s" % b)

	var ok := true
	if _aim_n == 0 or _samples == 0:
		ok = false
		print("  ✗ 没采到有效样本（战斗没打起来？）")
	if _aim_n > 0 and (aim_mean < MEAN_MIN or _aim_min < TOL):
		ok = false
	if _vel_n > 0 and (vel_mean < MEAN_MIN_VEL or _vel_min < TOL):
		ok = false
	if ok:
		print("★★★ 45 轮验收通过：舰艏朝敌人（有目标 · 均值 & 下限）· 朝速度（无目标）★★★")
	else:
		print("✗✗✗ 45 轮验收未过 ✗✗✗")
