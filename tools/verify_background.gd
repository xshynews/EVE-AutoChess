extends Node

## 背景替换验证工具 —— 逐个切换背景，报告落地状态并核查天空盒几何
##
## 用法：
##   godot_console.exe --headless --path <工程> --quit-after N \
##       res://tools/verify_background.tscn -- --bg=caldari_c06 --lat=41.5
##
##   --bg=<id>   只测这一个背景（省略则遍历库里全部）
##   --lat=<deg> 期望的中央视线采样纬度。省略时第 5 项只报告、不计失败
##               （目标纬度因图而异，遍历全部背景时无法共用一个值）
##               ⚠️ 换图要跟着改 —— 每张全景图的内容带纬度不同。
##                  例：nebula_duo 最亮带 +17.5°，配 bias +40° 时
##                      中心采样 -5.8°，所以要 --lat=-5.8
##
## 不带参数时：遍历库里所有背景，各报一次状态；
##             非 headless 下再各截一张到 user://bg_<id>.png
##
## ⚠️ 截图必须在【非 headless】下才拿得到像素；
##    但「背景是否加载成功」「天球姿态是否正确」这类判断在 headless 下也能跑，
##    所以本工具两种模式都兼容：headless 时跳过截图只报状态。
##
## ── 本工具已随「天空盒更正」重写 ──────────────────────────────────
## 旧版在报「背景板可见 / 背景板几何」，那是错误前提（参考程序是天空盒）
## 的产物。现在改成核查天空盒的三件事：
##   ① 球幕是否可见、贴图尺寸是否是 2:1（等距柱状的硬要求）
##   ② 天球姿态（rotation_degrees）是否与配置一致
##   ③ 相机中央视线实际采样到贴图的哪个纬度 —— 这是判断
##      「星云到底有没有入画」的唯一客观依据

const SCENE_PATH := "res://scenes/battle_scene.tscn"

var _battle: Node = null
var _arena: Node = null
var _warmup := 60
var _frame := 0
var _pending: Array[String] = []
var _shot_index := 0
var _headless := false
var _fails := 0
## 期望的中央视线采样纬度（用 --lat= 传；默认 41.5 = 官方 caldari c16 的星云带中心）
var _target_lat := 41.5
## 是否显式传了 --lat=。没传时第 5 项只报告不计失败：
## 目标纬度因图而异（见顶注），遍历全部背景时套同一个默认值必然误报。
var _lat_explicit := false


func _ready() -> void:
	_headless = DisplayServer.get_name() == "headless"

	var args := OS.get_cmdline_user_args()
	var only := ""
	for a in args:
		if a.begins_with("--bg="):
			only = a.substr(5)
		elif a.begins_with("--lat="):
			var lv := a.substr(6)
			if lv.is_valid_float():
				_target_lat = lv.to_float()
				_lat_explicit = true

	var packed: PackedScene = load(SCENE_PATH)
	_battle = packed.instantiate()
	add_child(_battle)

	# 下一帧再取 arena（_ready 里 arena 才建好）
	await get_tree().process_frame
	await get_tree().process_frame
	_arena = _battle.get("arena")

	if only.is_empty():
		for id in EveBackgroundLibrary.available_ids():
			_pending.append(id)
	else:
		_pending.append(only)

	print("[背景验证] 共 %d 个待测背景；headless=%s" % [_pending.size(), _headless])
	print("[背景验证] 可用背景：%s" % ", ".join(EveBackgroundLibrary.available_ids()))


func _process(_dt: float) -> void:
	if _pending.is_empty():
		return
	_frame += 1
	if _frame < _warmup:
		# 预热：让相机 / 战斗 / 首帧背景都稳定下来再开始测
		return

	_frame = 0
	var id: String = _pending.pop_front()
	_apply_specific(id)
	_report(id)

	# 切换背景后必须等若干帧：材质的贴图上传 + shader 变体编译不在同一帧完成。
	# ⚠️ 2 帧不够（实测截到的是上一张背景）。给 12 帧，约 0.2 秒。
	# ⚠️ headless 下不渲染，`frame_post_draw` 永远不会发出 ⇒ 改等 process_frame，
	#    否则进程挂死（判断逻辑不依赖像素，等帧只为让状态稳定）。
	for i in 12:
		if _headless:
			await get_tree().process_frame
		else:
			await RenderingServer.frame_post_draw

	if _headless:
		if _pending.is_empty():
			_finish()
		return

	var img := get_viewport().get_texture().get_image()
	if img != null:
		var out := "user://bg_%s.png" % id
		var err := img.save_png(out)
		if err == OK:
			print("[截图] %s -> %s" % [id, ProjectSettings.globalize_path(out)])
			_shot_index += 1
		else:
			push_error("截图保存失败 %s err=%d" % [out, err])
	else:
		push_error("拿不到 viewport 图像")

	if _pending.is_empty():
		_finish()


func _apply_specific(id: String) -> void:
	if _arena == null:
		push_error("arena 为空，无法切换背景")
		return
	var ok: bool = _arena.call("set_background", id)
	if not ok:
		print("[背景验证] ✗ %s 应用失败" % id)
		_fails += 1


## 报告每个背景的落地状态 —— 这是判断「有没有真的换上去」的依据
func _report(id: String) -> void:
	var bg = _arena.get("background")
	if bg == null:
		print("[背景验证] ✗ background 节点为空")
		_fails += 1
		return

	var cur: String = bg.call("current_id")
	var e := EveBackgroundLibrary.find(id)
	var mode_name := "?"
	var intensity := 0.0
	var tex_w := 0
	var tex_h := 0
	if e != null:
		mode_name = ["equirect", "none"][e.mode]
		intensity = e.intensity
		if e.mode != EveBackgroundLibrary.Mode.MODE_NONE and ResourceLoader.exists(e.path):
			var t: Texture2D = load(e.path)
			if t != null:
				tex_w = t.get_width()
				tex_h = t.get_height()

	# ⚠️ 打印实际接到的相机朝向，避免「场景结构变了导致取错节点、
	#    但输出格式照旧」这种假验证。采样纬度是相机朝向的函数，
	#    朝向不对时所有纬度读数都是废的、却看不出来。
	var cam = bg.get("_camera")
	if cam != null:
		var f: Vector3 = -cam.global_transform.basis.z
		print("[背景验证] 采样用相机朝向 dir=(%.3f, %.3f, %.3f)  俯角=%.1f°" % [
			f.x, f.y, f.z, rad_to_deg(asin(clampf(-f.y, -1.0, 1.0)))])

	print("")
	print("=".repeat(72))
	print("[背景验证] id=%s  当前=%s  模式=%s  强度=%.2f" % [id, cur, mode_name, intensity])

	# ── 1. id 是否真的应用成功 ──
	var applied := (cur == id)
	print("  1. 应用成功 ......... %s" % _mark(applied))
	if not applied and e != null and e.mode != EveBackgroundLibrary.Mode.MODE_NONE:
		_fails += 1

	# ── 2. 球幕节点可见性 ──
	var sky = bg.get("_sky_node")
	var sky_vis: bool = sky != null and sky.visible
	var expect_vis := e != null and e.mode == EveBackgroundLibrary.Mode.MODE_EQUIRECT
	var vis_ok := (sky_vis == expect_vis)
	print("  2. 球幕可见性 ....... %s  (实测=%s 期望=%s)" % [
		_mark(vis_ok), sky_vis, expect_vis])
	if not vis_ok:
		_fails += 1

	if e == null or e.mode == EveBackgroundLibrary.Mode.MODE_NONE:
		print("  (纯色模式，跳过几何核查)")
		return

	# ── 3. 贴图必须是 2:1（等距柱状的硬要求）──
	var ratio := 0.0
	if tex_h > 0:
		ratio = float(tex_w) / float(tex_h)
	var ratio_ok := absf(ratio - 2.0) < 0.02
	print("  3. 贴图 %dx%d  比例=%.4f (等距柱状须为 2.0) %s" % [
		tex_w, tex_h, ratio, _mark(ratio_ok)])
	if not ratio_ok and tex_w > 0:
		print("       ⚠️ 非 2:1 的图贴到球面上会被拉伸变形")
		_fails += 1

	# ── 4. 天球姿态 ──
	if sky != null:
		var rot: Vector3 = sky.rotation_degrees
		var expect_pitch: float = e.sky_pitch_bias
		if absf(expect_pitch) < 0.01:
			expect_pitch = float(bg.get("SKY_PITCH_BIAS_DEG"))
		var expect_yaw := float(bg.get("YAW_FIX_DEG"))
		var rot_ok := absf(rot.x - expect_pitch) < 0.01 and absf(rot.y - expect_yaw) < 0.01
		print("  4. 天球姿态 ......... %s  pitch=%.1f° yaw=%.1f° (期望 %.1f° / %.1f°)" % [
			_mark(rot_ok), rot.x, rot.y, expect_pitch, expect_yaw])
		if not rot_ok:
			_fails += 1

	# ── 5. 相机中央视线实际采样到的纬度（最关键的一条）──
	#    这是判断「星云到底有没有入画」的唯一客观依据。
	#    旧实现是靠「块均值跨度 span」间接试出来的，容易被别的参数干扰。
	var s: Array = bg.call("sample_center_latitude")
	var lat: float = s[0]
	var v: float = s[1]
	var row: float = s[2]
	# 目标纬度由 --lat= 传入（默认 41.5 = 官方 caldari c16 的星云带中心）。
	# ⚠️ 不要硬编码某一个图的星云带纬度 —— 每张全景图的内容带位置不同，
	#    硬编码会让「换了图就跑不过」和「没换图也跑不过」混在一起，
	#    分不清是工具过时还是背景真的没配好。
	#    例：nebula_duo 的星云带在【南纬 -32.5°】，与 caldari 正好相反。
	if not _lat_explicit:
		print("  5. 中央视线采样纬度 . [INFO]  v=%.4f  纬度=%+.1f°  像素行 %.0f / %d  (未传 --lat=，只报告)"
				% [v, lat, row, tex_h if tex_h > 0 else 2048])
	var lat_ok := absf(lat - _target_lat) <= 15.0
	if _lat_explicit:
		print("  5. 中央视线采样纬度 . %s  v=%.4f  纬度=%+.1f°  像素行 %.0f / %d  (目标 %+.1f°±15°)"
				% [_mark(lat_ok), v, lat, row, tex_h if tex_h > 0 else 2048, _target_lat])
	if _lat_explicit and not lat_ok:
		print("       ⚠️ 偏离目标纬度，画面中央会拍到贴图里的空白区")
		_fails += 1

	# ── 6. 【与图无关的客观判据】整屏视野内的平均亮度 ──
	#    第 5 项是「算出来的纬度 vs 配置的目标」——它只能证明配置自洽。
	#    这一项直接问贴图：「你【这一屏】看到的这块亮不亮」，所以能抓出
	#    「纬度算对了但横向取景跑掉了」这种情况。
	#
	#    ⚠️ 必须取【整屏网格平均】，不能只取中央那一个像素。
	#       第一版就是取单像素，结果 nebula_duo 报 1.03x「未入画」——
	#       而实际上：波段的纬向平均是亮的（-15~-45 都是 101~127），
	#       只是默认机位经度上那一点恰好偏暗。
	#       单像素测量的方差太大，会把「报错」和「运气」混在一起。
	if e != null and not e.path.is_empty():
		_check_view_brightness(e.path, bg)

	# ── 7. 球幕绘制次序（棋盘会不会被星云盖掉的开关）──
	_check_sky_draw_order(bg, e)


## 7. 球幕的 render_priority 必须为负
##
## ⚠️ 这条看着像「渲染细节」，实际是【棋盘在不在屏幕上】的总开关。
##
##   球幕 shader 的 fragment 里写了 `ALPHA = 1.0;` —— 只要 shader 给 ALPHA
##   赋过值，Godot 就把这个材质判成【透明】，球幕因此进的是透明队列，
##   而不是「背景」。透明队列按【到相机的距离从远到近】排序，而球幕的
##   AABB 中心在竞技场原点、棋盘的中心在 global z = -11.1（相机在 +z 侧）
##   → 棋盘更远 → 棋盘先画 → 半径 12000 的球幕后画 → 把整块 11×11 棋盘
##   刷成星云。
##
##   症状极具迷惑性：大的网格全没了，唯独 6×6 的落点高亮格还在
##   （它在 z = +6.9，比球幕中心更近，排序上反而活了下来）。
##   实测排查时先怀疑了 MeshInstance3D / AABB / 顶点数据，全是冤枉的 ——
##   真凶就是这一行排序。详见 eve_background.gd 的 SKY_RENDER_PRIORITY。
func _check_sky_draw_order(bg: Node, e: EveBackgroundLibrary.Entry) -> void:
	if e != null and e.mode == EveBackgroundLibrary.Mode.MODE_NONE:
		print("  7. 球幕绘制次序 ..... [跳过] 纯色模式无球幕")
		return
	var mat: Material = bg.get("_sky_material")
	if mat == null:
		print("  7. 球幕绘制次序 ..... [跳过] 拿不到球幕材质")
		return
	var prio: int = mat.render_priority
	var ok := prio < 0
	print("  7. 球幕绘制次序 ..... %s  render_priority=%d（必须 < 0）" % [_mark(ok), prio])
	if not ok:
		print("       ⚠️ 球幕会排在透明队列里【比棋盘更靠后】画 ——")
		print("          棋盘 AABB 中心 z=-11.1 比球幕中心（竞技场原点）更远离相机，")
		print("          表现是「11×11 网格全消失，只有落点高亮格还在」。")
		print("          修法见 eve_background.gd 的 SKY_RENDER_PRIORITY。")
		_fails += 1


func _check_view_brightness(path: String, bg: Node) -> void:
	var t: Texture2D = load(path)
	if t == null:
		return
	var img: Image = t.get_image()
	if img == null:
		print("  6. 整屏视野亮度 ..... [跳过] 取不到图像数据（可能是 VRAM 压缩纹理）")
		return
	var cam: Camera3D = bg.get("_camera")
	var sky: Node3D = bg.get("_sky_node")
	if cam == null or sky == null:
		return

	var iw := img.get_width()
	var ih := img.get_height()
	var basis := cam.global_transform.basis
	var fwd := -basis.z
	var right := basis.x
	var up := basis.y
	var tan_v := tan(deg_to_rad(cam.fov) * 0.5)
	var vp := get_viewport().get_visible_rect().size
	var aspect := vp.x / maxf(vp.y, 1.0)
	var tan_h := tan_v * aspect
	var sky_inv := sky.global_transform.basis.inverse()

	# 9x5 网格覆盖整屏；越界时夹取到边缘（球幕是环绕的，u 自然回绕）
	var acc := 0.0
	var n := 0
	var lo := 2.0
	var hi := -1.0
	var cx_luma := 0.0
	for iy in 5:
		for ix in 9:
			var sx := float(ix) / 4.0 - 1.0
			var sy := float(iy) / 4.0 - 1.0
			var dir := (fwd + right * (sx * tan_h) + up * (sy * tan_v)).normalized()
			var local := (sky_inv * dir).normalized()
			var v := 0.5 - asin(clampf(local.y, -1.0, 1.0)) / PI
			var u := fposmod(atan2(local.x, local.z) / TAU, 1.0)
			var c := img.get_pixel(clampi(int(u * iw), 0, iw - 1),
					clampi(int(v * ih), 0, ih - 1))
			var l := 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
			if ix == 4 and iy == 2:
				cx_luma = l
			acc += l
			n += 1
			lo = minf(lo, l)
			hi = maxf(hi, l)
	var frame_avg := acc / float(n)

	# 全图亮度分布：粗网格采样（64x32 = 2048 点），排序后取分位数。
	#
	# ⚠️ 基准【不能】用「全图平均亮度」。第一版就是拿均值比，结果
	#    官方 caldari c16 报 0.80x「未入画」，而这张图的截图明明是
	#    一屏完整星云（肉眼确认过）。原因：caldari 是整体偏暗的图
	#    （均值 0.212，暗极 0.115），而它的星云带是 0.34 —— 视野里
	#    只要包含了暗天区，均值就会被拉到 0.17，看着像「没入画」。
	#
	#    真正要判的是「有没有对着空天」，所以基准应当是
	#    【贴图里最暗那部分天区的亮度】—— 用 5% 分位代表。
	var lums: Array[float] = []
	for gy in 32:
		for gx in 64:
			var p := img.get_pixel(int((gx + 0.5) * iw / 64.0), int((gy + 0.5) * ih / 32.0))
			lums.append(0.2126 * p.r + 0.7152 * p.g + 0.0722 * p.b)
	lums.sort()
	var tex_avg := 0.0
	for l in lums:
		tex_avg += l
	tex_avg /= float(lums.size())
	var dark_ref: float = lums[int(lums.size() * 0.05)]

	var ratio := frame_avg / tex_avg if tex_avg > 0.001 else 0.0
	var lift := frame_avg / dark_ref if dark_ref > 0.001 else 0.0
	var span := hi - lo
	# 判据：① 视野明显亮于「空天」（不是对着黑天）
	#       ② 视野内有明暗结构（不是一块均匀的布）
	var ok := lift >= 1.35 and span >= 0.05
	print("  6. 整屏视野亮度 ..... %s  视野均 %.3f  全图均 %.3f  空天(5%%) %.3f"
			% [_mark(ok), frame_avg, tex_avg, dark_ref])
	print("       相对空天 %.2fx  相对全图 %.2fx  明暗跨度 %.3f  中心点 %.3f"
			% [lift, ratio, span, cx_luma])
	if not ok:
		print("       ⚠️ %s" % ("视野亮度接近空天 —— 星云未入画"
				if lift < 1.35 else "视野内明暗跨度过小 —— 像一块均匀的布"))
		_fails += 1


func _mark(ok: bool) -> String:
	return "[OK  ]" if ok else "[FAIL]"


func _finish() -> void:
	print("")
	print("=".repeat(72))
	if _fails == 0:
		print("[结果] 全部通过（失败项=0）")
	else:
		print("[结果] 失败项 = %d" % _fails)
	if not _headless:
		print("[截图] 共 %d 张" % _shot_index)
	print("=".repeat(72))
	get_tree().quit(0 if _fails == 0 else 1)
