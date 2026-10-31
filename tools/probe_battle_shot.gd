extends Node

## 探针：**开战运镜**每一拍的实际画面（2026-10-31）。
##
## 玩家诉求链：
##   「两军对垒，是不是可以加个环绕的主将相互靠近的机制？」
##   → 用户定案 B 方案（分层站位 + 30 秒主力压上）
##   → 但 A/B 实测证明数值差只有 4~5 km，3/4 远视角下看不出
##   → 用户定案：**加 2 秒开战运镜**（表现层，不进 sim，TTK 不变）
##
## 本探针解决的问题：运镜参数（俯角 / 拉远倍率 / 三拍时刻）**没法靠算**，
## 只能看画面 —— 俯角抬到多少才「看得清两军」，拉远多少才「不切船」，
## 这三拍连起来是不是真的读得出「对峙 → 压上」。
##
## ── 跑法 ────────────────────────────────────────────────────────────
##   "$GODOT_BIN" --path . --quit-after 900 res://tools/probe_battle_shot.tscn
##   ⚠️ 不要加 --headless（要看像素）
##
## 产物：outputs/shot_t*.png（6 帧）+ outputs/shot_strip.png（横向拼接，
##       一屏看完整个运镜 —— 交给用户看图用，不用逐张点）
##
## ⚠️⚠️ 手法上有两条硬约束（都是踩过的坑）：
##   ① **关掉 arena 的 _process**，运镜由本探针手动 `step_battle_shot` 驱动。
##      不关的话每张截图之间引擎又跑了 N 帧，t 不可控 ——
##      同一个参数跑两次得到不同画面，那就没法调参了。
##   ② **一帧只推进一步、只在 _process 里推进**（不在同一个协程里连推 6 次）。
##      第一版就是在同一个 `_step_shoot()` 里 `await frame_post_draw` 连拍 6 张，
##      结果 6 张 PNG **字节数完全一样**（PIL 全像素 diff = 0）——
##      相机 global_position 明明每张都在变，说明是读回拿到了同一帧的纹理。
##      拆成"每帧一步"就正常了。

const SCENE_PATH := "res://scenes/battle_scene.tscn"
const OUT_DIR := "res://outputs"
## 常量从**脚本**上读（不是从实例 get）—— 常量属于脚本
const ARENA := preload("res://scripts/scene/eve_battle_arena.gd")

## 采样时刻（秒）—— 三拍的关键点都覆盖：起手 / 拍①中 / 拍①末 / 拍②定住 / 拍③中 / 落地
const SAMPLES := [0.0, 0.4, 0.8, 1.2, 1.6, 2.0]

## 每张截图之间空几帧（给渲染 + 读回留时间）
const GAP_FRAMES := 3

var _battle: Node = null
var _arena: Node = null
var _cam: Node = null

var _frame := 0
var _stage := 0
var _sample_i := 0
var _busy := false
var _finishing := false
var _paths: Array = []
var _done := false


func _ready() -> void:
	var win := get_window()
	if win != null:
		win.size = Vector2i(1920, 1080)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var packed: PackedScene = load(SCENE_PATH)
	_battle = packed.instantiate()
	add_child(_battle)


func _process(_dt: float) -> void:
	if _done or _busy:
		return
	_frame += 1
	match _stage:
		0:
			if _frame >= 30:
				_stage = 1
				_step_buy()
		1:
			if _frame >= 60:
				_stage = 2
				_step_deploy()
		2:
			if _frame >= 90:
				_stage = 3
				_start_shot()
		3:
			_busy = true
			await _shoot_next()
			_busy = false


func _run_state():
	return _battle.get("run")


func _step_buy() -> void:
	var st = _run_state()
	for i in 5:
		st.buy(i % 5)
	print("[买船] %s" % st.summary())


func _step_deploy() -> void:
	var st = _run_state()
	var placed := 0
	for i in 5:
		if bool(st.deploy_from_bench(0, 8, 5 + i).get("ok", false)):
			placed += 1
	print("[布阵] 上场 %d 艘 / 备战席 %d" % [placed, st.bench.size()])


func _start_shot() -> void:
	_arena = _battle.get("arena")
	_cam = _arena.get("orion_cam")
	# ⚠️ 关掉 arena 的每帧跟随/运镜推进 —— 运镜由本探针手动步进
	_arena.set_process(false)

	print("\n" + "=".repeat(78))
	print("开战运镜逐拍取样（arena._process 已关闭，由探针手动步进）")
	print("=".repeat(78))
	print("  起点：zoom %.4f · yaw %.4f · pitch %.4f · 视距 %.2f"
			% [float(_cam.get_zoom()), float(_cam.get_yaw()),
				float(_cam.get_pitch()), float(_cam.call("get_distance"))])

	_battle.call("start_battle")
	print("  开战：运镜启动 active=%s · 视距 %.2f · max_range %.2f"
			% [str(_arena.call("battle_shot_active")),
				float(_cam.call("get_distance")), float(_cam.get_max_range())])


## 推进到下一个采样点并截图（每帧只调一次）
func _shoot_next() -> void:
	if _sample_i >= SAMPLES.size():
		_finish_probe()
		return
	var t: float = float(SAMPLES[_sample_i])
	if _sample_i > 0:
		var prev: float = float(SAMPLES[_sample_i - 1])
		_arena.call("step_battle_shot", t - prev)
	# 给渲染几帧时间再读回（读回太急会拿到上一帧，见文件头的坑）
	for _i in GAP_FRAMES:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw

	var path := "%s/shot_t%.1f.png" % [OUT_DIR, t]
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(path))
	_paths.append(path)
	var cam3d: Camera3D = _cam.get("camera")
	print("  t=%.1fs  zoom %.4f · yaw %.4f · pitch %.4f · 视距 %.2f · 进度 %.0f%% · hash=%d"
			% [t, float(_cam.get_zoom()), float(_cam.get_yaw()),
				float(_cam.get_pitch()), float(_cam.call("get_distance")),
				float(_arena.call("battle_shot_progress")) * 100.0, _hash(img)])
	if cam3d != null:
		print("       cam=(%.2f, %.2f, %.2f) focus=%s"
				% [cam3d.global_position.x, cam3d.global_position.y,
					cam3d.global_position.z, str(_cam.get_focus())])
	_sample_i += 1


func _finish_probe() -> void:
	# ⚠️ 防重入：`_shoot_next` 在采样跑完后每帧都会进来，
	#    而这函数里有 await ⇒ 不挡住的话会并发跑出**多个集成检查**，
	#    每个都 `begin_battle_shot` 把 t 重置回 0 —— 运镜永远到不了头。
	#    实测症状：控制台刷了几十行"收尾 active=true"，像相机死住了。
	if _finishing:
		return
	_finishing = true
	print("  收尾：运镜 active=%s（必须 false —— 否则相机会被钉死）"
			% str(_arena.call("battle_shot_active")))
	_strip()
	await _check_integration()
	_done = true
	print("\n产物：%s + shot_strip.png" % OUT_DIR)
	get_tree().quit()


## 集成检查：**把 arena 的 _process 恢复**，再真跑一遍运镜。
##
## ⚠️ 上面对比图是"关掉 _process、手动步进"拍的 —— 那验的是**插值曲线**，
##    验不了「_process 里的运镜分支到底有没有接上」。
##    而后者才是实机的路径：分支写错 / 忘了 return / 忘了清标记，
##    实机表现分别是「运镜完全不发生」「跟随和运镜打架」「相机彻底死住」，
##    三种都不会报错。⇒ 必须真跑一次。
func _check_integration() -> void:
	_arena.set_process(true)
	_arena.call("begin_battle_shot")
	var cam0 := float(_cam.get_zoom())
	var yaw0 := float(_cam.get_yaw())
	# 等真实 2.6 秒（运镜 2 秒 + 余量），期间全靠 arena._process 自己推进
	var elapsed := 0.0
	while elapsed < 2.6:
		await get_tree().process_frame
		elapsed += get_process_delta_time()
	var still := bool(_arena.call("battle_shot_active"))
	var yaw1 := float(_cam.get_yaw())
	var zoom1 := float(_cam.get_zoom())
	print("\n" + "-".repeat(78))
	print("[集成] 真跑 %.2fs（arena._process 已恢复，不手动步进）" % elapsed)
	print("  运镜是否已结束：%s（必须 true）" % str(not still))
	print("  yaw %.3f → %.3f（应 ≈ BATTLE_VIEW_YAW %.2f）"
			% [yaw0, yaw1, ARENA.BATTLE_VIEW_YAW])
	print("  zoom %.3f → %.3f" % [cam0, zoom1])
	print("  跟随是否恢复：%s" % str(not still))


func _hash(img: Image) -> int:
	if img == null or img.is_empty():
		return -1
	var sum := 0
	var w := img.get_width()
	var h := img.get_height()
	for i in 64:
		var x := (i * 37 + 11) % w
		var y := (i * 53 + 7) % h
		sum = (sum * 31 + int(img.get_pixel(x, y).to_rgba32() & 0xFFFFFF)) & 0x7FFFFFFF
	return sum


## 六帧横向拼一条，一屏看完整个运镜
func _strip() -> void:
	var imgs: Array = []
	var w := 0
	var h := 0
	for p in _paths:
		var im := Image.load_from_file(ProjectSettings.globalize_path(String(p)))
		if im == null or im.is_empty():
			continue
		var k := 640.0 / float(im.get_width())
		im.resize(640, int(float(im.get_height()) * k), Image.INTERPOLATE_BILINEAR)
		if im.get_format() != Image.FORMAT_RGBA8:
			im.convert(Image.FORMAT_RGBA8)
		imgs.append(im)
		w += im.get_width()
		h = maxi(h, im.get_height())
	if imgs.is_empty():
		return
	var strip := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	strip.fill(Color.BLACK)
	var x := 0
	for im in imgs:
		strip.blit_rect(im, Rect2i(0, 0, im.get_width(), im.get_height()), Vector2i(x, 0))
		x += im.get_width()
	strip.save_png(ProjectSettings.globalize_path("%s/shot_strip.png" % OUT_DIR))
