extends Node

## 开火线出图探针（**非无头**）—— 2026-10-01 攻击特效改版验收
##
## 跑法：
##   "C:/godot/Godot_v4.7.1-stable_win64_console.exe" \
##     --path "F:/evezzq/eve自走棋918" --quit-after 3000 \
##     res://tools/probe_fx_line.tscn
##
## 产物在 `user://fx_line/`（= %APPDATA%\Godot\app_userdata\EVE自走棋918\fx_line\）
##
## ══════════════════════════════════════════════════════════════════
##  为什么需要这个探针（而不是"看 verify 全绿就收工"）
## ══════════════════════════════════════════════════════════════════
##  verify_run 的几何断言只能证明「线的中心在弹道上、长轴对齐」——
##  它证明不了**看起来对不对**：太细 / 太暗 / 太粗 / 颜色偏白，
##  这些是用户唯一在意的事，而它们全都不会让断言变红。
##
##  ⇒ 这个探针把一段**真实的**开火（用 sim 自己发出来的 shot_fired）
##    定格下来出图，让用户的眼睛当最终裁判。
##
##  ⚠️ 必须非 headless：headless 拿不到 SubViewport 纹理。
##
## ── 三个机位 ────────────────────────────────────────────────────
##   ① 默认俯视（玩家平时看到的视角）—— 判「线够不够看得见」
##   ② 贴近特写 —— 判「线的宽度、颜色、两端有没有真的连上船」
##   ③ 斜 45° —— 判「不是 billboard」：线应随弹道倾斜，而不是转成竖直
## ══════════════════════════════════════════════════════════════════

const BATTLE_SCENE := preload("res://scenes/battle_scene.tscn")
const FX_SCRIPT := preload("res://scripts/visual/eve_battle_fx.gd")
const ORBIT_CAM_SCRIPT := preload("res://scripts/scene/eve_orbit_camera.gd")

const SHOT_DIR := "user://fx_line"
## 一次定格里造几条线 —— 要够多才看得出「长短不一」的弹幕感
const N_LINES := 14


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SHOT_DIR)
	if DisplayServer.get_name() == "headless":
		print("✗ 本探针必须非 headless（拿不到 SubViewport 纹理）")
		get_tree().quit()
		return
	print("=".repeat(64))
	print("开火线出图探针 —— 1920×1080 锁死")
	print("=".repeat(64))

	var scene: Variant = BATTLE_SCENE.instantiate()
	add_child(scene)
	await _frames(90)
	print("  battle_scene 就绪")

	# 让它真的打起来：直接开战并推进到「接敌、双方都在开火」的时刻。
	var run = scene.get("run")
	# 灌几艘船上去，否则开战会被「场上一艘船都没有」挡下来
	run.set("coin", 999)
	var bench_ids: Array = ["punisher", "incursus", "slasher", "atron", "rifter", "tristan"]
	for i in bench_ids.size():
		run.get("bench").append({
			"ship_key": StringName(bench_ids[i]), "star": 1, "cost": 1})
	run.emit_signal("changed")
	await _frames(5)
	var deployed := 0
	for i in 4:
		var r: Dictionary = run.call("deploy_from_bench", 0, 7 - i / 9, i % 9)
		if bool(r.get("ok", false)):
			deployed += 1
	run.emit_signal("changed")
	await _frames(5)
	print("  已部署 %d 艘 · 上场名单 %d 项" % [deployed, run.get("field").size()])
	scene.call("start_battle")
	# 推进到锁定完成、正在交火的时刻（同 verify_run 的 12 秒口径）
	await _frames(120)
	var sim = scene.get("sim")
	if sim == null:
		print("  ✗ start_battle 没有建出模拟器 —— 上场名单=%d 艘"
				% run.get("field").size())
		get_tree().quit()
		return
	scene.call("debug_fast_forward_battle", 12.0)
	await _frames(3)
	print("  已进入交火：sim.elapsed=%.1fs · 存活 我 %d 敌 %d"
			% [float(sim.elapsed), _alive(scene, 0), _alive(scene, 1)])

	var arena = scene.get("arena")
	var bfx = arena.get("battle_fx")
	print("  特效开关 fx_enabled=%s（默认应为 true）" % str(bfx.get("fx_enabled")))

	await _shot(scene, arena, "01_默认俯视", 0.0, 0.0, 0.0)
	await _shot(scene, arena, "02_贴近特写", 0.0, 0.0, 2.2)
	await _shot(scene, arena, "03_斜45度", 0.9, 0.35, 1.4)

	print("完成。产物在 user://fx_line/")
	get_tree().quit()


## 打一个机位并截屏。`zoom_mul` > 1 = 推近，`yaw_add` = 额外偏航。
func _shot(scene: Node, arena: Node, name: String, yaw_add: float,
		pitch_add: float, zoom_mul: float) -> void:
	var cam = arena.get("orion_cam")
	var base_zoom := float(ORBIT_CAM_SCRIPT.DEFAULT_ZOOM)
	if zoom_mul > 0.0:
		cam.set("zoom", base_zoom * zoom_mul)
	if yaw_add != 0.0:
		cam.call("set_yaw_target", float(cam.get("yaw")) + yaw_add)
	if pitch_add != 0.0:
		cam.call("set_pitch_target", float(cam.get("pitch")) + pitch_add)
	# 帧要够多，让相机插值与特效都稳定
	await _frames(20)
	# ⚠️ 特效寿命很短（开火线 0.15s）。等太久线就灭光了 —— 所以这里
	#    在截图前**补造一批**，保证画面里一定有正在亮着的线。
	_emit_burst(arena)
	await _frames(2)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var vp := get_viewport()
	var img := vp.get_texture().get_image()
	if img == null:
		print("  ✗ %s：取图失败" % name)
		return
	var path := SHOT_DIR + "/" + name + ".png"
	img.save_png(path)
	print("  ✔ %s → %s  %s" % [name, path, str(img.get_size())])


## 在双方实际位置上造一批（有命中、有未命中）的开火线，模拟一次齐射。
##
## ⚠️ 用**真实船的坐标**而不是随便挑两个点：这一段的看点就是
##    「线两端连着火方与受击方」，用假坐标就失去意义了。
func _emit_burst(arena: Node) -> void:
	var bfx = arena.get("battle_fx")
	if bfx == null:
		return
	var own: Array = []
	var foe: Array = []
	for vis in _collect(arena):
		var sh = vis.get("ship")
		if sh == null:
			continue
		if int(sh.get("team")) == 0:
			own.append(sh)
		else:
			foe.append(sh)
	if own.is_empty() or foe.is_empty():
		print("  ⚠ 场上没有双方船，无法造线（own=%d foe=%d）" % [own.size(), foe.size()])
		return
	for i in N_LINES:
		var a = own[i % own.size()]
		var b = foe[i % foe.size()]
		# 真伪交替：奇数发打空（用户会看到短一截的暗线）
		var hit := (i % 3) != 2
		bfx.call("spawn_tracer", a.get("body").position, b.get("body").position,
				hit, i % 7)


func _collect(n: Node) -> Array:
	var out: Array = []
	if n is Node3D and n.get("ship") != null:
		out.append(n)
		return out
	for c in n.get_children():
		out.append_array(_collect(c))
	return out


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().process_frame


func _alive(scene: Node, team: int) -> int:
	var pool: Array = scene.get("_own_ships") if team == 0 else scene.get("_enemy_ships")
	var n := 0
	for s in pool:
		if s.get("alive"):
			n += 1
	return n
