extends Node

## 无头验证脚本 —— 轨道相机（长按左键拖拽转视角）行为回归
##
## 用法：
##   godot_console.exe --headless --path <工程> --quit-after 4000 ^
##       res://tools/verify_camera.tscn
##
## 验证内容（每条都是「手感」的可量化代理指标）：
##   1. 收敛曲线 —— 必须是【指数收敛】而不是瞬时到位
##      判据：首帧位移 ≈ 总位移 × speed（speed = min(1, 5*dt)），
##            且 20 帧内走完 80% 以上（dt=1/60 时约 0.25s 收敛）
##   2. 死区 —— 累积位移 ≤4px 时角度【完全不变】
##   3. 垂直灵敏度 = 水平的一半
##   4. pitch 限位 ±(PI/2 - 0.05)，且能穿越 0 翻到另一侧半球
##   5. 拖拽不破坏「自动取景跟随」——焦点仍跟着舰队走
##   6. 复位 —— 回到 EVE 原版初始机位（yaw=-.58, pitch=.72, zoom=1）
##   7. 缩放 —— 滚轮走推进量曲线，不是线性改 zoom

const BATTLE_SCRIPT := preload("res://scripts/eve_battle_scene.gd")
const ORBIT_SCRIPT := preload("res://scripts/scene/eve_orbit_camera.gd")

var _battle: Node = null
var _arena = null
var _cam = null
var _fails := 0
var _t := 0


func _ready() -> void:
	print("=".repeat(72))
	print("[轨道相机验证] 长按左键拖拽转视角 —— 手感回归")
	print("=".repeat(72))

	var packed: PackedScene = load("res://scenes/battle_scene.tscn")
	_battle = packed.instantiate()
	add_child(_battle)

	# 等场景把 arena / 相机建起来
	await get_tree().process_frame
	await get_tree().process_frame

	_arena = _battle.get("arena")
	if _arena == null:
		_fail("arena 为空")
		_finish()
		return
	_cam = _arena.get("orion_cam")
	if _cam == null:
		_fail("orion_cam 为空（轨道相机未挂载）")
		_finish()
		return

	_test_defaults()
	_test_dead_zone()
	_test_convergence_curve()
	_test_axis_sensitivity()
	_test_pitch_limit()
	_test_hemisphere_flip()
	_test_zoom_curve()
	_test_reset()
	await _test_follow_still_works()

	_finish()


# ------------------------------------------------------------------ 用例

func _test_defaults() -> void:
	_section("1. 默认机位（EVE 原版初始值）")
	var yaw: float = _cam.get_yaw()
	var pitch: float = _cam.get_pitch()
	var zoom: float = _cam.get_zoom()
	_check("yaw   = %.4f rad (%.1f°)" % [yaw, rad_to_deg(yaw)],
			absf(yaw - (-0.58)) < 0.001, "应为 -0.58")
	_check("pitch = %.4f rad (%.1f°)" % [pitch, rad_to_deg(pitch)],
			absf(pitch - 0.72) < 0.001, "应为 0.72")
	_check("zoom  = %.4f" % zoom,
			absf(zoom - ORBIT_SCRIPT.DEFAULT_ZOOM) < 0.001,
			"应为 DEFAULT_ZOOM=%.4f" % ORBIT_SCRIPT.DEFAULT_ZOOM)
	# 相机必须在焦点上方（pitch>0 → 俯视）
	var cam: Camera3D = _arena.get("camera")
	var focus: Vector3 = _cam.get_focus()
	_check("相机在焦点上方 (dy=%.2f)" % (cam.position.y - focus.y),
			cam.position.y > focus.y, "俯视才行，否则看不到战场")
	# 相机必须真的看向焦点
	var fwd := -cam.global_transform.basis.z
	var want := (focus - cam.position).normalized()
	_check("相机朝向对齐焦点 (dot=%.4f)" % fwd.dot(want),
			fwd.dot(want) > 0.9999, "look_at 必须命中焦点")


func _test_dead_zone() -> void:
	_section("2. 拖拽死区（4 像素内不动相机）")
	#
	# ⚠️ reset() 只清【当前角度】，不清【排入的 target】。
	#    如果上一节留下了未收敛的 target，step() 会带着残余继续走，
	#    于是「死区内 yaw 未变」这条会在 Δ≈1.1e-3 上假失败（本测试实测过）。
	#    正确做法：reset() 之后先把收敛推干净，再取基准。
	_cam.reset()
	for i in 400:
		_cam.step(1.0 / 60.0)
	var before_yaw: float = _cam.get_yaw()
	var before_pitch: float = _cam.get_pitch()

	# 模拟按下 + 3 次 1px 微动（合计 3px，仍在死区内）
	_press(Vector2(900, 540))
	for i in 3:
		_move(Vector2(1, 0), Vector2(900 + i + 1, 540))
	# 推进几帧看有没有偷跑
	for i in 5:
		_cam.step(1.0 / 60.0)

	var after_yaw: float = _cam.get_yaw()
	var after_pitch: float = _cam.get_pitch()
	_check("3px 微动后 yaw 未变 (Δ=%.6f)" % absf(after_yaw - before_yaw),
			absf(after_yaw - before_yaw) < 1e-9, "死区内必须完全不响应")
	_check("3px 微动后 pitch 未变 (Δ=%.6f)" % absf(after_pitch - before_pitch),
			absf(after_pitch - before_pitch) < 1e-9, "死区内必须完全不响应")

	# 松开 —— 位移 < 死区，handle_input 应返回 false（让上层去选船）
	var consumed: bool = _arena.handle_camera_input(_make_up(Vector2(903, 540)))
	_check("松手事件未被相机消费（应交给选船）", not consumed,
			"≤4px 的松开必须返回 false")

	# 再测：越过死区后必须响应
	_cam.reset()
	_press(Vector2(900, 540))
	_move(Vector2(10, 0), Vector2(910, 540))
	var moved: float = absf(float(_cam.get_yaw()) - float(_cam.get_target_yaw()))
	_check("越过死区后 target 已改变 (Δtarget=%.5f)" % moved, moved > 1e-6,
			"10px 应触发排入")
	_cam.end_drag()


func _test_convergence_curve() -> void:
	_section("3. 收敛曲线（必须是指数收敛，不是瞬时到位）")
	_cam.reset()
	var start_yaw: float = _cam.get_yaw()

	# 一次性排入一次固定幅度的拖拽，然后逐帧推进记录轨迹
	_cam.queue_orbit_rad(100.0, 0.0)
	var target: float = _cam.get_target_yaw()
	var total := absf(target - start_yaw)

	var trace: Array[float] = []
	for i in 20:
		_cam.step(1.0 / 60.0)
		trace.append(absf(float(_cam.get_yaw()) - start_yaw))

	var f1 := trace[0]
	var f20 := trace[19]
	var ratio_first := f1 / maxf(1e-9, total)
	var ratio_20 := f20 / maxf(1e-9, total)

	# speed = min(1, 5 * 1/60) = 0.08333…
	var expect_first := 5.0 / 60.0
	_check("首帧位移占比 = %.4f (期望 %.4f)" % [ratio_first, expect_first],
			absf(ratio_first - expect_first) < 0.005,
			"首帧必须恰好走 speed 那一份 —— 走多了就是瞬时到位")
	_check("20 帧后走完 %.1f%%" % (ratio_20 * 100.0), ratio_20 > 0.80,
			"20 帧(0.33s)应走完 80% 以上")
	_check("收敛是单调的（无过冲）",
			_is_monotonic(trace), "指数收敛不该反弹")
	# 后半程每帧位移必须小于前半程 —— 这就是「越接近越慢」
	var early := trace[4] - trace[3]
	var late := trace[19] - trace[18]
	_check("减速特性：第5帧步长 %.5f > 第20帧步长 %.5f" % [early, late],
			early > late, "越接近目标步长越小才叫丝滑")

	# 再推进足够多帧 —— 必须吸附到 target 附近并清空 target
	#
	# ⚠️ 为什么容忍 0.0001 的残差：
	#    这是 EVE 原版的吸附阈值（orbitStopAngle = .0001 弧度）。
	#    JS 里同样是 `if (|left| < .0001) yaw = target;`，
	#    所以【参考程序也会留残差】，它本来就不是「精确归零」的设计。
	#    0.0001 rad ≈ 0.0057°，换算到 1080p 上不足半个像素。
	#    这里断言 < 0.0002（即阈值的两倍，留一点浮点余量），
	#    而不是 1e-6 —— 后者是照着「应该归零」的错误预期写的。
	var tgt = _cam.get_target_yaw()
	# ⚠️ 要推到真正吸附为止，不能只推固定帧数。
	#
	#    原因：step() 的收尾动作在「左位移 < orbitStopAngle」那一帧才发生，
	#    而固定 60 帧后残留还有 ~1.1e-3 —— 比阈值大 10 倍。
	#    这不是引擎 bug，而是【测试自己没推够】：指数收敛在阈值前的
	#    最后一段每帧只走 8.3%，从 1e-3 收到 1e-4 还需要 ~26 帧。
	#    原断言写 < 0.0002 本身没错，错的是上面只推了 60 帧。
	#    这里改成「推到 target 清空或上限」，两种资源都覆盖到。
	var frames := 0
	while frames < 400:
		_cam.step(1.0 / 60.0)
		frames += 1
		if is_nan(float(_cam.get_target_yaw())):
			break
	var final_yaw: float = _cam.get_yaw()
	var err := absf(final_yaw - target)
	_check("最终吸附残差 = %.8f (< 原版阈值 0.0002，推了 %d 帧)" % [err, frames],
			err < 0.0002,
			"应在 EVE 原版阈值内 —— 不是精确归零")
	# ⚠️ 必须在【推进之后】读 target，不能读推进前缓存的 tgt。
	#    原写法 `var tgt = get_target_yaw()` 放在循环之前，读的是
	#    「刚排入、尚未收敛」时的非 NaN 值，于是这条永远 FAIL ——
	#    而它想验证的（清空）其实已经发生了。
	#    这是典型的「基准取早了一帧」，与上面残差那条同源。
	_check("收敛后 target 被清空", is_nan(float(_cam.get_target_yaw())),
			"清空后下次拖拽才从当前值重新起步")


func _test_axis_sensitivity() -> void:
	_section("4. 垂直灵敏度 = 水平的一半（EVE 原版 /2）")
	# ⚠️ 幅度必须小到不会撞 pitch 限位 ——
	#    第一版用了 200px，pitch 位移 1.2 rad 直接被 clamp 到极限，
	#    比值算出来 0.3337（被截断后的残值），断言假失败。
	#    pitch 可用行程很小（±1.52，初值 0.72 → 上行仅 0.8），
	#    所以用 20px（位移 0.12 rad）安全。
	var probe := 20.0
	_cam.reset()
	_cam.queue_orbit_rad(0.0, probe)
	var dy := absf(float(_cam.get_target_pitch()) - float(_cam.get_pitch()))
	_cam.reset()
	_cam.queue_orbit_rad(probe, 0.0)
	var dx := absf(float(_cam.get_target_yaw()) - float(_cam.get_yaw()))

	var ratio := dy / maxf(1e-9, dx)
	_check("垂直/水平 位移比 = %.4f (%.5f / %.5f)" % [ratio, dy, dx],
			absf(ratio - 0.5) < 0.001, "必须恰好 1/2")

	# 方向：右拖 yaw 减小，下拖 pitch 增大（画面跟着鼠标走）
	_cam.reset()
	var y0: float = _cam.get_yaw()
	_cam.queue_orbit_rad(50.0, 0.0)
	_check("右拖 → yaw 减小 (Δ=%.5f)" % (float(_cam.get_target_yaw()) - y0),
			float(_cam.get_target_yaw()) < y0, "右拖应让场景右移")
	_cam.reset()
	var pp0: float = _cam.get_pitch()
	_cam.queue_orbit_rad(0.0, 50.0)
	_check("下拖 → pitch 增大 (Δ=%.5f)" % (float(_cam.get_target_pitch()) - pp0),
			float(_cam.get_target_pitch()) > pp0, "下拖应抬高相机")

	# 灵敏度绝对值核对：move = 0.012（attached）
	_cam.reset()
	_cam.queue_orbit_rad(100.0, 0.0)
	var expect_dx := 0.012 * 100.0
	_check("水平灵敏度 = %.5f (期望 %.5f = 0.012×100)" % [
			absf(float(_cam.get_target_yaw()) - (-0.58)), expect_dx],
			absf(absf(float(_cam.get_target_yaw()) - (-0.58)) - expect_dx) < 1e-6,
			"必须用 orbitMoveAttached = .012")


func _test_pitch_limit() -> void:
	_section("5. pitch 限位 ±(PI/2 - 0.05)")
	_cam.reset()
	# 疯狂往下拖 —— 必须被夹住，不能翻过正上方
	for i in 40:
		_cam.queue_orbit_rad(0.0, 200.0)
		for j in 8:
			_cam.step(1.0 / 60.0)
	var limit := PI * 0.5 - 0.05
	# 注意 target 已被清空，看实际 pitch
	var p: float = _cam.get_pitch()
	_check("上抬到极限后 pitch = %.5f (limit=%.5f)" % [p, limit],
			p <= limit + 1e-6, "不得越过限位")
	_check("确实顶到了限位附近 (差 %.5f)" % (limit - p),
			limit - p < 0.01, "应该能接近限位")

	_cam.reset()
	for i in 40:
		_cam.queue_orbit_rad(0.0, -200.0)
		for j in 8:
			_cam.step(1.0 / 60.0)
	var p2: float = _cam.get_pitch()
	_check("下压到极限后 pitch = %.5f" % p2, p2 >= -limit - 1e-6,
			"不得越过负限位")


func _test_hemisphere_flip() -> void:
	_section("6. pitch 可穿越 0 翻到另一侧半球")
	_cam.reset()
	# 连续下压 —— pitch 应能从 +0.72 一路降到负数（相机从上方转到下方）
	var seen_negative := false
	var crossed_zero := false
	var prev: float = float(_cam.get_pitch())
	for i in 30:
		_cam.queue_orbit_rad(0.0, -100.0)
		for j in 6:
			_cam.step(1.0 / 60.0)
		var cur: float = _cam.get_pitch()
		if prev > 0.0 and cur <= 0.0:
			crossed_zero = true
		if cur < 0.0:
			seen_negative = true
		prev = cur
	_check("穿越了 0（俯视 → 侧视 → 仰视）", crossed_zero,
			"pitch 应能连续穿过 0")
	_check("到达负 pitch = %.4f" % prev, seen_negative,
			"应能翻到另一侧半球")

	# ⚠️ 必须【重新排入一个小的负 pitch 并推到收敛】，不能只 empty-loop。
	#
	#    上面那个循环把 pitch 一路压到 -1.5208（负限位），并且
	#    step() 一旦收敛（两轴 target 都清空）就会在开头直接 return false，
	#    此后无论再推多少帧都不会调 apply_to_camera()。
	#    所以「多推 400 帧」是无效的 —— 相机永远停在限位那一帧的世界位置。
	#    实测：那时相机还在焦点上方（dy=+63.84），因为 pitch 顶到
	#    -1.5208 后 sin(pitch)*dist ≈ -0.999*dist 与……等等，这里其实
	#    暴露了另一个值得记的事实：限位附近 cos(pitch) 趋近 0，
	#    相机几乎正对焦点下方，look_at 用的 up 向量接近退化。
	# 正确测法是给一个【远离限位】的负 pitch，让翻转结论干净。
	#    用 set_pitch_target 走与拖拽同一条 target/current 收敛路径。
	_cam.reset()
	_cam.set_pitch_target(-0.5)
	for i in 200:
		_cam.step(1.0 / 60.0)
	var p_neg: float = _cam.get_pitch()
	_check("翻到负 pitch 且远离限位 (pitch=%.4f)" % p_neg,
			p_neg < -0.05 and p_neg > -(PI * 0.5 - 0.05), "应停在下半球但未贴限位")

	var cam: Camera3D = _arena.get("camera")
	var focus: Vector3 = _cam.get_focus()
	var dy := cam.global_position.y - focus.y
	_check("负 pitch 时相机在焦点下方 (dy=%.2f)" % dy, dy < 0.0,
			"半球翻转的判据")


func _test_zoom_curve() -> void:
	_section("7. 缩放（滚轮 = 纯指数乘法，瞬时生效）")
	#
	# ⚠️ 参考程序【有两条滚轮路径】，别抄错了：
	#    ① 主画布 #combatRadar（战斗场景用这条）：
	#         zoom = clamp(zoom * exp(-deltaY * .002), .55, 360)   ← 瞬时
	#    ② 独立画布 #zoomCanvas：
	#         combatOfficialCameraQueueZoom()  ← 走 zoomPower=9 推进量曲线
	#    第一版误把 ② 抄了进来，方向还反了（上滚滚成拉远）。
	#
	_cam.reset()
	var z0: float = _cam.get_zoom()
	var d0: float = _cam.get_distance()

	# 上滚（浏览器 deltaY < 0）→ zoom 变大 → 镜头推近
	_cam.queue_zoom_delta(-120.0)
	var z1: float = _cam.get_zoom()
	var d1: float = _cam.get_distance()
	_check("上滚 → zoom 变大 %.4f → %.4f" % [z0, z1], z1 > z0,
			"⚠️ 上滚必须推近（exp(-deltaY*.002) 的性质）")
	_check("上滚 → 视距变小 %.2f → %.2f" % [d0, d1], d1 < d0,
			"zoom 与 distance 反相关")
	_check("缩放瞬时生效（不需要收敛帧）", not _cam.is_animating(),
			"滚轮是离散事件，不该有收敛尾巴")

	# 精确核对公式：一格 120 单位 → 倍率 exp(0.24) ≈ 1.27125
	var expect := exp(0.24)
	_check("上滚一格倍率 = %.5f (期望 %.5f)" % [z1 / z0, expect],
			absf(z1 / z0 - expect) < 1e-5, "必须等于 exp(0.24)")

	# 下滚一格应回到原值（乘性对称）
	_cam.queue_zoom_delta(120.0)
	_check("下滚一格回到原值 (err=%.8f)" % absf(_cam.get_zoom() - z0),
			absf(_cam.get_zoom() - z0) < 1e-6, "乘性操作应严格可逆")

	# 上限
	for k in 60:
		_cam.queue_zoom_delta(-120.0)
	var zmax: float = _cam.get_zoom()
	_check("极限放大 zoom = %.4f (cap=360)" % zmax, absf(zmax - 360.0) < 1e-6,
			"必须夹在 360")
	for k in 60:
		_cam.queue_zoom_delta(120.0)
	var zmin: float = _cam.get_zoom()
	_check("极限缩小 zoom = %.4f (floor=0.55)" % zmin, absf(zmin - 0.55) < 1e-6,
			"必须夹在 0.55")

	# 远近端对称性 —— 纯指数乘法【没有】zoomPower=9 那种偏斜，
	# 上滚两格再下滚两格必须严格回原位（这是 ① 与 ② 的判据）
	_cam.reset()
	_cam.queue_zoom_delta(-120.0)
	_cam.queue_zoom_delta(-120.0)
	_cam.queue_zoom_delta(120.0)
	_cam.queue_zoom_delta(120.0)
	_check("上2格+下2格严格回位 (err=%.8f)" % absf(_cam.get_zoom() - ORBIT_SCRIPT.DEFAULT_ZOOM),
			absf(_cam.get_zoom() - ORBIT_SCRIPT.DEFAULT_ZOOM) < 1e-9,
			"纯乘性才是参考程序主画布的手感")


func _test_reset() -> void:
	_section("8. 复位")
	_cam.reset()
	_cam.queue_orbit_rad(300.0, 120.0)
	for i in 60:
		_cam.step(1.0 / 60.0)
	_cam.queue_zoom_delta(-120.0)
	var dirtied := absf(float(_cam.get_yaw()) - (-0.58)) > 0.01
	_check("复位前确实被改动过", dirtied, "测试前置条件")

	_arena.reset_camera()
	_check("复位后 yaw = %.4f" % float(_cam.get_yaw()),
			absf(float(_cam.get_yaw()) - (-0.58)) < 0.001, "应回 -0.58")
	_check("复位后 pitch = %.4f" % float(_cam.get_pitch()),
			absf(float(_cam.get_pitch()) - 0.72) < 0.001, "应回 0.72")
	_check("复位后 zoom = %.4f" % float(_cam.get_zoom()),
			absf(float(_cam.get_zoom()) - ORBIT_SCRIPT.DEFAULT_ZOOM) < 0.001,
			"应回 DEFAULT_ZOOM=%.4f" % ORBIT_SCRIPT.DEFAULT_ZOOM)


## ⚠️ 这条最容易漏：拖拽改了角度之后，自动取景跟随必须仍然工作。
##    旧实现每帧 _apply_camera_angles() 覆盖角度，新实现只改 focus ——
##    要验证「角度不被抢走」且「焦点仍在跟随」。
##
##    ⚠️ 判据写法（这里第一版写错，出了假失败）：
##       拖到收敛完毕后再取基准，然后比较「引擎自己跑的 120 帧」前后的角度。
##       第一版在【收敛过程中】就取了基准（只推进 90 帧、还差最后一点残余），
##       于是引擎继续把残余收完，Δ=0.0007 被误判成「角度被覆盖」。
##       现在先推到 target 清空（真正静止）再取基准。
func _test_follow_still_works() -> void:
	_section("9. 拖拽后自动取景跟随仍工作（角度不被抢走）")
	_cam.reset()
	_cam.queue_orbit_rad(150.0, 60.0)
	# 推到彻底收敛（target 被清空）才取基准
	for i in 300:
		_cam.step(1.0 / 60.0)
	var still := is_nan(float(_cam.get_target_yaw())) \
			and is_nan(float(_cam.get_target_pitch()))
	_check("已彻底收敛才取基准（target 已清空）", still, "测试前置条件")

	var yaw_after: float = _cam.get_yaw()
	var pitch_after: float = _cam.get_pitch()
	# 基准必须确实偏离了默认机位（否则「没被覆盖」是废话）
	_check("拖拽后角度确实偏离默认 (yaw %.4f / pitch %.4f)" % [
			yaw_after, pitch_after],
			absf(yaw_after - (-0.58)) > 0.1 and absf(pitch_after - 0.72) > 0.05,
			"测试前置条件：得先真的转过去")

	# ── 先往场上放一艘**探针舰**（理由见文件末尾那条注释）──────────
	#
	# ⚠️ 2026-10-01：布阵阶段场上本来就没有船 —— 开局 `field` 是空的
	#    （买船不自动上场，要玩家自己拖），而敌舰从这天起也改成
	#    「点开战才出现」。旧版这条断言能过，唯一原因是**当时敌舰已经
	#    站在场上了** ⇒ 它其实没测"跟随"，测的是"场上有敌舰"。
	#    所以这里自己放一艘：跟随要有东西可跟，才验得出来。
	var probe: EveShip = EveShipDatabase.instantiate_by_id("punisher", 0, 777)
	var probe_want := Vector3(12.0, 0.0, 6.0)
	_check("造出探针舰船用于验证跟随", probe != null, "测试前置条件")
	var probe_node: Node3D = null
	if probe != null:
		probe_node = _arena.call("spawn_ship_visual", probe)
		probe_node.position = probe_want

	# 让战斗推进一会儿，触发 _process 的跟随逻辑
	var focus_before: Vector3 = _cam.get_focus()
	for i in 120:
		await get_tree().process_frame

	var yaw_now: float = _cam.get_yaw()
	var pitch_now: float = _cam.get_pitch()
	_check("120 帧后 yaw 未被覆盖 (Δ=%.8f)" % absf(yaw_now - yaw_after),
			absf(yaw_now - yaw_after) < 1e-9,
			"⚠️ 被覆盖说明有代码在钉角度，拖拽会失效")
	_check("120 帧后 pitch 未被覆盖 (Δ=%.8f)" % absf(pitch_now - pitch_after),
			absf(pitch_now - pitch_after) < 1e-9,
			"⚠️ 同上")

	# 焦点必须还在跟着舰队（不能是死值）。
	#
	# ⚠️ 2026-10-01 改判据：原来断的是「120 帧里焦点动了 > 0」——
	#    它成立的前提是"此刻镜头正好在过渡中"。现在直接比对
	#    **焦点 vs 那艘探针舰的位置**：这才是"跟随"的语义本身，
	#    焦点被钉死（旧的覆盖式实现）会立刻被抓到。
	var focus_after: Vector3 = _cam.get_focus()
	var d_before := focus_before.distance_to(probe_want)
	var d_after := focus_after.distance_to(probe_want)
	# ⚠️ 判据用「朝目标收敛了」而不是「已经到位」——
	#    焦点是 lerp(delta/0.8) 平滑过去的，而**无头环境的 delta 是跑满帧率**的，
	#    120 帧实际推进的模拟时间远小于 2 秒 ⇒ 断言到位会变成"看机器快慢"的假失败。
	#    真正要抓的是「取景被钉死」（那样 d_after 不会变），所以断收敛比例。
	_check("焦点朝场上那艘船收敛（距离 %.3f → %.3f，120 帧里动了 %.3f）" % [
			d_before, d_after, focus_before.distance_to(focus_after)],
			probe != null and d_after < d_before * 0.5 and d_after < 5.0,
			"距离不缩 = 取景被钉死在别处（跟随失效）")
	if probe != null and probe_node != null:
		_arena.call("remove_ship_visual", probe.id)
	_check("焦点跟随幅度合理 (< 20 单位，无抖动跳变)",
			focus_before.distance_to(focus_after) < 20.0,
			"跟随是 0.8s 时间常数的 lerp，不该暴走")

	# 相机必须仍然精确指向焦点，且距离与 distance() 一致
	#
	# ⚠️ 用 global_position：相机挂在 arena 下，position 是局部坐标。
	var cam: Camera3D = _arena.get("camera")
	var d := cam.global_position.distance_to(focus_after)
	_check("相机与焦点距离与 distance() 一致 (%.2f vs %.2f)" % [
			d, float(_cam.get_distance())],
			absf(d - float(_cam.get_distance())) < 0.01,
			"apply_to_camera 必须用 focus 定位")
	var fwd := -cam.global_transform.basis.z
	var want := (focus_after - cam.global_position).normalized()
	_check("相机仍精确朝向焦点 (dot=%.6f)" % fwd.dot(want),
			fwd.dot(want) > 0.9999, "转过去之后也不能失焦")

	# 拖拽状态不应被 _process 干扰
	_check("dragging 状态为 false（已松手）", not bool(_cam.is_dragging()),
			"松手后必须复位")


# ------------------------------------------------------------------ 输入模拟

func _press(pos: Vector2) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	e.position = pos
	_arena.handle_camera_input(e)


func _make_up(pos: Vector2) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = false
	e.position = pos
	return e


func _move(rel: Vector2, pos: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.relative = rel
	e.position = pos
	_arena.handle_camera_input(e)


# ------------------------------------------------------------------ 断言

func _is_monotonic(a: Array[float]) -> bool:
	for i in range(1, a.size()):
		if a[i] < a[i - 1] - 1e-9:
			return false
	return true


func _section(title: String) -> void:
	print("\n" + "-".repeat(72))
	print(title)
	print("-".repeat(72))


func _check(label: String, ok: bool, hint: String = "") -> void:
	if ok:
		print("  [OK]   %s" % label)
	else:
		_fails += 1
		print("  [FAIL] %s   <- %s" % [label, hint])


func _fail(msg: String) -> void:
	_fails += 1
	print("  [FAIL] %s" % msg)


func _finish() -> void:
	print("\n" + "=".repeat(72))
	if _fails == 0:
		print("[结果] 全部通过 —— 轨道相机手感与 EVE 原版一致")
	else:
		print("[结果] 失败项 = %d" % _fails)
	print("=".repeat(72))
	get_tree().quit(0 if _fails == 0 else 1)
