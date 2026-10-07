extends Node

## 无头探测 —— 球幕 UV 与参考程序球面投影的对齐情况
##
## 目的：确认我方 SphereMesh 的等距柱状 UV 起点（u 的 0 点）与
##       参考程序 atan(ray.x, ray.z) 的起点是否一致。
##
## 做法：不靠读源码猜，直接【采样真实网格的顶点 UV】——
##       构造一个与 EveBackground 里参数完全相同的 SphereMesh，
##       枚举其顶点，找出「世界方向 → (u,v)」的实际映射。
##
## 用法：
##   godot_console.exe --headless --path <工程> --quit-after 2000 ^
##       res://tools/probe_sky_uv.tscn

const SKY_RADIUS := 12_000.0


func _ready() -> void:
	print("=".repeat(72))
	print("[球幕 UV 探测] SphereMesh 的等距柱状映射实测")
	print("=".repeat(72))

	var sphere := SphereMesh.new()
	sphere.radius = SKY_RADIUS
	sphere.height = SKY_RADIUS * 2.0
	sphere.is_hemisphere = false
	sphere.radial_segments = 96
	sphere.rings = 48

	var arrays := sphere.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	print("顶点数 = %d" % verts.size())

	# ── 1. 先确认 v（纬度）方向：球顶=0 还是 1 ──
	print("\n" + "-".repeat(72))
	print("1. v（纬度轴）的朝向")
	print("-".repeat(72))
	var top_v := -1.0
	var bot_v := -1.0
	var top_dir := Vector3.ZERO
	var bot_dir := Vector3.ZERO
	var max_y := -INF
	var min_y := INF
	for i in verts.size():
		if verts[i].y > max_y:
			max_y = verts[i].y
			top_v = uvs[i].y
			top_dir = verts[i].normalized()
		if verts[i].y < min_y:
			min_y = verts[i].y
			bot_v = uvs[i].y
			bot_dir = verts[i].normalized()
	print("  最高顶点 y=%+.1f  dir.y=%+.4f  v=%.4f" % [max_y, top_dir.y, top_v])
	print("  最低顶点 y=%+.1f  dir.y=%+.4f  v=%.4f" % [min_y, bot_dir.y, bot_v])
	print("  参考程序: dir.y=+1(天顶) → v=0 ; dir.y=-1(天底) → v=1")
	var v_ok := (top_v < 0.01 and bot_v > 0.99)
	print("  [%s] v 朝向与参考程序%s" % [
		"OK  " if v_ok else "FAIL", "一致" if v_ok else "【相反】—— 需要翻转 v"])

	# ── 2. 再确认 u（经度轴）的起点 ──
	print("\n" + "-".repeat(72))
	print("2. u（经度轴）的起点：参考程序 u = atan(dir.x, dir.z)/(2PI) + 0.5")
	print("-".repeat(72))
	# 沿球赤道一圈采样，比较「实测 u」与「参考公式 u」
	print("  %-28s %-10s %-12s %-12s %s" % [
		"方向 (赤道面)", "实测u", "参考u", "差(归一)", "说明"])
	var worst := 0.0
	var samples := [
		[0.0, 0.0, 1.0],    # +Z
		[1.0, 0.0, 0.0],    # +X
		[0.0, 0.0, -1.0],   # -Z
		[-1.0, 0.0, 0.0],   # -X
	]
	for s in samples:
		var dir := Vector3(s[0], s[1], s[2]).normalized()
		var measured := _lookup_uv(sphere, dir)
		var ref := atan2(dir.x, dir.z) / (2.0 * PI) + 0.5
		var diff := _wrap01(measured.x - ref)
		if diff > 0.5:
			diff -= 1.0
		worst = maxf(worst, absf(diff))
		print("  %-28s %-10.4f %-12.4f %+.4f      %s" % [
			str(s), measured.x, ref, diff,
			"+Z 基准" if absf(s[2] - 1.0) < 0.01 else ""])
	print("\n  最大偏差 = %.4f (= %.1f 度经度)" % [worst, worst * 360.0])
	if worst < 0.02:
		print("  [OK  ] 经度起点与参考程序一致，无需额外 Y 旋转补偿")
	else:
		print("  [FAIL] 经度起点相差 %.1f 度 —— 星空会绕 Y 轴整体偏转" % (worst * 360.0))

	# ── 3. 求 pitch bias 的正确值（粗扫 + 精修）──
	print("\n" + "-".repeat(72))
	print("3. sky_pitch_bias 扫描 —— 求「画面中央拍到星云带」的取值")
	print("-".repeat(72))
	# 目标采样纬度：默认 +41.5°（官方 caldari c16 的星云带中心）。
	# 换图后必须重传 —— 每张全景图的星云带纬度不同：
	#   godot --headless --path <工程> --quit-after 4000 \
	#       res://tools/probe_sky_uv.tscn -- --lat=-32.5
	var target_lat := _user_float("--lat", 41.5)
	print("  目标采样纬度（由 --lat= 传入）= %+.1f°" % target_lat)
	# ⚠️ 关键认识 ①：默认机位是【俯视】，视线朝下。
	#    球幕绕 X 正向旋转会把「下方」的天球内容送到视线方向上，
	#    所以要让中央视线拍到【北天】的星云带，需要【正的】pitch bias。
	#    之前取 -83° 是把方向搞反了（实测落在 -89.6° = 正对天底）。
	#
	# ⚠️ 关键认识 ②：视线【不是】纯 YZ 平面内的向量。
	#    实测真机相机朝向 = (0.412, -0.659, -0.629)，带 x 分量。
	#    原因是轨道相机用 look_at(focus)，其 up 由 up×(target-pos) 解出，
	#    相机绕 Y 转到 -33° 附近时这个 up 不再平行于世界 up，
	#    整个相机 basis 被【额外多转约 43°】。
	#    所以「只绕 X 转」会得到 -41.2°，而真机是 -121.9° —— 差 80°。
	#    本函数必须按真机朝向 (0.412,-0.659,-0.629) 来扫。
	var fwd := Vector3(0.412, -0.659, -0.629).normalized()
	# 球幕世界变换 W = Ry(yaw)·Rx(pitch)（Godot YXZ 序），
	# 转进球幕空间是左乘 W⁻¹ = Rx(-pitch)·Ry(-yaw)；
	# yaw 项不影响 local.y，故扫描时只体现 pitch。
	# 用「先绕 X 转正向 pitch」的逆旋转来模拟，符号与实际 W⁻¹ 一致。
	var raw_lat := (0.5 - _lookup_uv(sphere, fwd).y) * 360.0
	print("  相机【真机】视线世界 dir = (%.3f, %.3f, %.3f)" % [fwd.x, fwd.y, fwd.z])
	print("  不旋转球幕时采样纬度 = %+.1f°" % raw_lat)
	print("")
	print("  粗扫（步长 10°）：")
	print("  bias(°)    局部dir.y    采样v      纬度(°)   像素行   与目标差")
	print("  " + "-".repeat(72))

	var results: Array = []
	for k in 37:
		var bias_deg := -180.0 + k * 10.0
		results.append([bias_deg, _sample_lat(sphere, fwd, bias_deg)])
	for r in results:
		var d: float = absf(float(r[1]) - target_lat)
		print("  %+7.1f   %+9.4f  %7.4f  %+8.1f  %7d   %5.1f  %s" % [
			r[0], _local_y(fwd, r[0]), _sphere_dir_to_v(sphere, fwd, r[0]),
			r[1], int(round(_sphere_dir_to_v(sphere, fwd, r[0]) * 2048.0)),
			d, "<== 粗扫最优" if d < 5.0 else ""])

	# 精修：在粗扫最优附近以 1° 步长细扫
	var coarse_best: float = 180.0
	var coarse_err := 1e9
	for r in results:
		var e: float = absf(float(r[1]) - target_lat)
		if e < coarse_err:
			coarse_err = e
			coarse_best = r[0]

	var best_bias := coarse_best
	var best_lat: float = _sample_lat(sphere, fwd, coarse_best)
	var best_err := coarse_err
	var k2 := -12
	while k2 <= 12:
		var bias_deg := coarse_best + k2
		var lat: float = _sample_lat(sphere, fwd, bias_deg)
		var e: float = absf(lat - target_lat)
		if e < best_err:
			best_err = e
			best_bias = bias_deg
			best_lat = lat
		k2 += 1

	print("")
	print("  粗扫最优 bias = %+.1f°（误差 %.1f°）→ 精修（步长 1°）" % [
		coarse_best, coarse_err])
	print("  → 最佳 bias = %+.1f°   采样纬度 = %+.1f°   误差 = %.2f°"
			% [best_bias, best_lat, best_err])
	# 像素行：v = 0.5 - lat/180，行号 = v · 高
	print("     像素行 %.0f / 2048（v = %.4f）" % [
		(0.5 - best_lat / 180.0) * 2048.0, 0.5 - best_lat / 180.0])
	var hit := best_err <= 5.0
	print("  [%s] 最佳偏置%s命中目标纬度 %+.1f°（±5°）" % [
		"OK  " if hit else "WARN", "" if hit else "未", target_lat])

	# ── 4. 360 度环绕时的连续性（接缝检查）──
	print("\n" + "-".repeat(72))
	print("4. 环绕 360 度时 u 的连续性（接缝检查）")
	print("-".repeat(72))
	var prev_u := -1.0
	var max_jump := 0.0
	var n := 72
	for i in n + 1:
		var a := TAU * float(i) / float(n)
		var dir := Vector3(sin(a), 0.0, cos(a))
		var u := _lookup_uv(sphere, dir).x
		if prev_u >= 0.0:
			var d := absf(u - prev_u)
			# 允许跨越 0/1 边界
			d = minf(d, absf(d - 1.0))
			max_jump = maxf(max_jump, d)
		prev_u = u
	print("  每 %.0f 度采样一次，相邻 u 最大跳变 = %.4f" % [360.0 / n, max_jump])
	print("  [%s] u 连续（无接缝跳变）" % ("OK  " if max_jump < 0.05 else "FAIL"))

	print("\n" + "=".repeat(72))
	print("探测结束")
	print("=".repeat(72))
	get_tree().quit(0)


## 在球面上找最接近给定【方向】的顶点，返回其 UV
##
## 之所以不解析求 UV：SphereMesh 的 UV 分配是引擎内部实现，
## 直接量测比推断可靠（尤其 u 的起点容易差一个常量）。
func _lookup_uv(sphere: SphereMesh, dir: Vector3) -> Vector2:
	var arrays := sphere.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var best := Vector2.ZERO
	var best_dot := -2.0
	var d := dir.normalized()
	for i in verts.size():
		var vd := verts[i].normalized()
		var dot := vd.dot(d)
		if dot > best_dot:
			best_dot = dot
			best = uvs[i]
	return best


func _wrap01(x: float) -> float:
	var r := fmod(x, 1.0)
	if r < 0.0:
		r += 1.0
	return r


## 读命令行用户参数：--key=value（`--` 之后的那些）
func _user_float(key: String, fallback: float) -> float:
	for a in OS.get_cmdline_user_args():
		if a.begins_with(key + "="):
			var v := a.substr(key.length() + 1)
			if v.is_valid_float():
				return v.to_float()
	push_warning("未收到 %s=<数值>，用默认值 %.1f" % [key, fallback])
	return fallback


## 球幕世界变换 W = Ry(180)·Rx(bias)，世界方向转进球幕空间是左乘 W⁻¹
func _sky_local(fwd: Vector3, bias_deg: float) -> Vector3:
	var w_inv := (Basis.from_euler(Vector3.ZERO)
			.rotated(Vector3.RIGHT, -deg_to_rad(bias_deg))
			* Basis.from_euler(Vector3(0.0, deg_to_rad(-180.0), 0.0)))
	return (w_inv * fwd).normalized()


func _local_y(fwd: Vector3, bias_deg: float) -> float:
	return _sky_local(fwd, bias_deg).y


func _sphere_dir_to_v(sphere: SphereMesh, fwd: Vector3, bias_deg: float) -> float:
	return _lookup_uv(sphere, _sky_local(fwd, bias_deg)).y


## 某个 bias 下，画面中央采样到的纬度（度）
##
## ⚠️ 系数是 180 不是 360：v = 0.5 - asin(y)/π ⇒ asin(y) = π(0.5-v)
##    ⇒ 纬度(度) = asin(y)·180/π = (0.5 - v)·180。写成 360 会【差一倍】，
##    导致「报告纬度」与「贴图纬度带」分属两种单位，看似命中实则差一倍。
func _sample_lat(sphere: SphereMesh, fwd: Vector3, bias_deg: float) -> float:
	return (0.5 - _sphere_dir_to_v(sphere, fwd, bias_deg)) * 180.0
