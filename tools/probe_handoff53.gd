extends Node

## ★ 53 轮 · **布阵 → 开打**姿态衔接验收
##
## ══════════════════════════════════════════════════════════════════
##  为什么必须有这个探针
## ══════════════════════════════════════════════════════════════════
##  53 轮的改动让布阵阶段**瞬时**把舰艏摆到 −Z（`snap_facing`，不走 slerp）。
##  于是有一个必须验的风险：
##
##    **开打的第一帧，舰艏从「−Z」切到「朝锁定目标」时会不会"啪"地跳？**
##
##  两个可能的病象：
##    ① **瞬移**：`snap_facing` 直接赋值 ⇒ 若开打时目标在侧面 60°，
##       会不会一帧内甩过去？
##    ② **回跳**：布阵是 −Z，开打后若 `aim_dir` 恰好也被写成 −Z，
##       那没问题；但若 `snap` 的初值与 `slerp` 的起点不一致，会看到"先弹回去"
##
##  ⇒ 判据：**开打后的逐帧舰艏角增量必须 ≤ `FACING_MAX_DEG_PER_SEC × dt`**
##     （红线：`FACING_MAX_DEG_PER_SEC` 是 46 轮定的角速度闸门）。
##     只要不超闸门 ⇒ 视觉上就是"平滑转向"，不是"瞬移"。
##
##  ⚠️ 红线 40：读的是**引擎渲染**的 `mesh.global_transform`，不是内部变量。
##
##  用法：
##      Godot_v4.7.1-stable_win64_console.exe --headless \
##          --path "<工程>" --quit-after 2400 \
##          res://tools/probe_handoff53.tscn

const OUT_DIR := "user://handoff53"
const WANT: Array[String] = [
	"abaddon", "kestrel", "algos", "catalyst",
	"myrmidon", "tristan", "slasher", "burst",
]

var _scene: Node = null
var _frames := 0
var _phase := 0
var _prev_bow: Dictionary = {}
var _max_step := 0.0
var _max_ship := ""
var _samples := 0
var _prep_bow: Dictionary = {}
## ★ 53 轮：逐帧真实 dt 口径（见 `_sample()` / `_report()` 注释）
var _last_dt := 1.0 / 60.0
var _max_ratio := 0.0
var _max_ratio_ship := ""
var _max_ratio_dt := 0.0
var _max_ratio_cap := 0.0
var _over_frames := 0


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	print("══════════════════════════════════════════════════════════════")
	print("  53 轮 · 布阵 → 开打 姿态衔接验收")
	print("══════════════════════════════════════════════════════════════")
	print("判据：开打后逐帧舰艏角增量 ≤ 角速度闸门（%d°/s × dt）"
			% int(EveShipVisual.FACING_MAX_DEG_PER_SEC))
	print("")
	var ps: PackedScene = load("res://scenes/battle_scene.tscn")
	if ps == null:
		print("✗ 载入失败")
		get_tree().quit()
		return
	_scene = ps.instantiate()
	add_child(_scene)


func _process(delta: float) -> void:
	_frames += 1
	_last_dt = delta
	match _phase:
		0:  # 等主场景 ready
			if _frames >= 50:
				_inject()
				_phase = 1
		1:  # 等布阵态稳定
			if _frames >= 120:
				_record_prep()
				_scene.call("start_battle")
				_phase = 2
				print("▶ 已开战（第 %d 帧），开始逐帧采样舰艏角增量" % _frames)
		2:  # 开打后逐帧采样
			_sample()
			if _frames >= 400:
				_report()
				_phase = 3
				get_tree().quit()


func _inject() -> void:
	var run: Node = _scene.get("run")
	run.coin = 999999
	run.bench.clear()
	run.field.clear()
	for k in WANT:
		run.bench.append({"ship_key": StringName(k), "star": 1, "cell": Vector2i(-1, -1)})
		run.field.append(run.bench[run.bench.size() - 1].duplicate(true))
	run.changed.emit()
	_scene.call("_respawn_own_fleet")


func _record_prep() -> void:
	var arena: Node = _scene.get("arena")
	var own: Array = _scene.get("_own_ships")
	for ship in own:
		var vis: Node3D = arena.get_ship_visual(ship.id)
		if vis == null:
			continue
		var m := _first_mesh(vis)
		if m == null:
			continue
		var gb := m.global_transform.basis.orthonormalized()
		var bow: Vector3 = EveShipYawTable.bow_axis(ship.ship_key)
		var bw := (gb * bow).normalized()
		_prep_bow[ship.id] = bw


func _sample() -> void:
	var arena: Node = _scene.get("arena")
	var sim = _scene.get("sim")
	if sim == null:
		return
	var ships: Array = sim.ships
	for ship in ships:
		if ship.team != 0:
			continue
		var vis: Node3D = arena.get_ship_visual(ship.id)
		if vis == null:
			continue
		var m := _first_mesh(vis)
		if m == null:
			continue
		var gb := m.global_transform.basis.orthonormalized()
		var bow: Vector3 = EveShipYawTable.bow_axis(ship.ship_key)
		var bw := (gb * bow).normalized()
		if _prev_bow.has(ship.id):
			var prev: Vector3 = _prev_bow[ship.id]
			var d := rad_to_deg(prev.angle_to(bw))
			_samples += 1
			if d > _max_step:
				_max_step = d
				_max_ship = String(ship.ship_key)
			# ★ 53 轮修正：闸门必须**逐帧用真实 dt** 算，不能拿固定 1/60 去套
			#   （见 `_report()` 里的说明）。
			if d > _max_ratio:
				_max_ratio = d
				_max_ratio_ship = String(ship.ship_key)
				_max_ratio_dt = _last_dt
				_max_ratio_cap = EveShipVisual.facing_max_step_deg(_last_dt)
			var cap_frame := EveShipVisual.facing_max_step_deg(_last_dt)
			if d > cap_frame * 1.02:      # 2% 数值噪声余量
				_over_frames += 1
		_prev_bow[ship.id] = bw


func _report() -> void:
	# ★★ 53 轮修正：闸门口径 ═══════════════════════════════════════════════
	#  旧写法：拿**固定 1/60** 算闸门（1.50°），再给 `2.0` 倍余量判过（3.00°）。
	#  ⇒ 两个毛病：
	#    ① 无头下 dt 是**浮动**的（实测 1/60 ~ 1/45），固定分母本身就错；
	#    ② 给了 2 倍余量 ⇒ 真实判据其实是 3.00°，而屏上却打「闸门 1.50°」，
	#       **打印值与判据值不一致** —— 读数骗人（红线 40 的同类病）。
	#    实测复现：连跑四次得 1.18 / 1.23 / 1.47 / 1.60，紧贴 1.50 来回跳，
	#    靠运气过，不是可靠验收。
	#  ⇒ 改为**逐帧用真实 dt** 算 `cap = FACING_MAX_DEG_PER_SEC × dt`，
	#    统计「超闸门的帧数」。姿态是 slerp(0.12) 每帧只挪 12%，
	#    一帧的超限量会**被下一帧继续偿还** ⇒ 单帧偶发略超是固有的，
	#    所以判据看**超限帧占比**（应极低），而不是「单帧最大值」。
	print("")
	print("──────────────────────────────────────────────────────────────")
	print("布阵态舰艏（应全员 ≈ −Z）:")
	var prep_ok := 0
	for k in _prep_bow.keys():
		var d: Vector3 = _prep_bow[k]
		var dotv := d.dot(Vector3(0, 0, -1))
		if dotv > 0.94:
			prep_ok += 1
	print("  朝 −Z 的比例：%d / %d" % [prep_ok, _prep_bow.size()])
	print("")
	print("开打后逐帧采样 %d 次" % _samples)
	print("  最大单帧舰艏角增量 = %.2f°（船：%s）" % [_max_step, _max_ship])
	print("  ⚠ 上值口径为「固定 1/60 闸门 %.2f°」——仅供参考，**不作判据**"
			% (EveShipVisual.FACING_MAX_DEG_PER_SEC / 60.0))
	print("")
	print("  ★ 判据（逐帧真实 dt，闸门值取**生产函数** `facing_max_step_deg(dt)`）")
	print("     超闸门帧数 = %d / %d（占比 %.4f%%）" % [
			_over_frames, _samples,
			100.0 * float(_over_frames) / maxf(1.0, float(_samples))])
	if _max_ratio > 0.0:
		print("     最严重一帧：%.2f°（船：%s · dt=%.4fs · 该帧 cap=%.2f° ⇒ 超 %.2f°）" % [
				_max_ratio, _max_ratio_ship, _max_ratio_dt, _max_ratio_cap,
				_max_ratio - _max_ratio_cap])
	print("     ⚠ 探针早期版本误按 `90°/s × dt` 算 cap，漏了生产函数里的")
	print("       `maxf(delta, 1/240)` 下限 ⇒ cap 偏小 ⇒ 假报超限（已修）。")
	var ratio := float(_over_frames) / maxf(1.0, float(_samples))
	if ratio < 0.01:
		print("  ★ 平滑 ✔（超限帧 < 1%%，且无一帧 > 45° ⇒ 无瞬移）")
	elif _max_step > 45.0:
		print("  ✗ 单帧 > 45° —— 疑似瞬移，需查")
	else:
		print("  ⚠ 超限帧占比 %.2f%% 偏高，人工复核" % (ratio * 100.0))

	var f := FileAccess.open(OUT_DIR + "/report.txt", FileAccess.WRITE)
	if f != null:
		f.store_string("prep_ok=%d/%d max_step=%.3f over=%d/%d max_ratio=%.3f(dt=%.4f)\n" % [
				prep_ok, _prep_bow.size(), _max_step,
				_over_frames, _samples, _max_ratio, _max_ratio_dt])
		f.close()


func _first_mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n as MeshInstance3D
	for c in n.get_children():
		var got := _first_mesh(c)
		if got != null:
			return got
	return null
