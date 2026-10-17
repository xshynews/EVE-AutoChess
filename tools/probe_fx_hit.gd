extends Node

## 受击反馈出图探针（**非无头**）—— 2026-10-17
##
## 跑法：
##   "$GODOT_BIN" --path . --quit-after 3000 res://tools/probe_fx_hit.tscn
##
## 产物在 `user://fx_hit/`（真实路径会打印出来）。
##
## ── 它验的是什么 ────────────────────────────────────────────────
##  verify_run 只能断言「特效节点被建出来」「flash_count 递增」——
##  它证明不了**看起来对不对**：船体泛光是不是太亮/太暗/像塑料、
##  护盾色和装甲色能不能一眼分开、闪光会不会盖掉船体细节。
##  这些只能靠眼睛。
##
## ⇐ 所以这里真的打一场，然后对**双方的实船**分别施加三种受击层，
##   在特写机位下定格。
##
## ⚠️ 必须非 headless：headless 拿不到 SubViewport 纹理。
##
## ── 三个机位 ────────────────────────────────────────────────────
##   ① 默认俯视 —— 判「战斗常态下看不看得出被打」
##   ② 贴近特写 —— 判「颜色分层、泛光强度」
##   ③ 斜 45°   —— 判「船体轮廓有没有被泛光糊掉」
## ══════════════════════════════════════════════════════════════════

const BATTLE_SCENE := preload("res://scenes/battle_scene.tscn")
const ORBIT_CAM_SCRIPT := preload("res://scripts/scene/eve_orbit_camera.gd")

const SHOT_DIR := "user://fx_hit"
## 施加的三种层，轮流分配给场上的船
const LAYERS: Array[StringName] = [&"shield", &"armor", &"hull"]


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SHOT_DIR)
	if DisplayServer.get_name() == "headless":
		print("✗ 本探针必须非 headless（拿不到 SubViewport 纹理）")
		get_tree().quit()
		return
	print("=".repeat(64))
	print("受击反馈出图探针 —— 1920×1080 锁死")
	print("产物目录：%s" % ProjectSettings.globalize_path(SHOT_DIR))
	print("=".repeat(64))

	var scene: Variant = BATTLE_SCENE.instantiate()
	add_child(scene)
	await _frames(90)

	var run = scene.get("run")
	run.set("coin", 999)
	var bench_ids: Array = ["punisher", "incursus", "slasher", "atron", "rifter", "tristan"]
	for i in bench_ids.size():
		run.get("bench").append({
			"ship_key": StringName(bench_ids[i]), "star": 1, "cost": 1})
	run.emit_signal("changed")
	await _frames(5)
	for i in 4:
		run.call("deploy_from_bench", 0, 7 - i / 9, i % 9)
	run.emit_signal("changed")
	await _frames(5)

	scene.call("start_battle")
	await _frames(120)
	var sim = scene.get("sim")
	if sim == null:
		print("  ✗ start_battle 没有建出模拟器")
		get_tree().quit()
		return
	scene.call("debug_fast_forward_battle", 12.0)
	await _frames(3)
	print("  已进入交火：sim.elapsed=%.1fs" % float(sim.elapsed))

	# ⚠️ **停掉战斗推进**再出图。
	#    battle_scene 的 `_process` 每帧都会 `sim.step()`，也就是每帧都在
	#    产生新的命中爆点 —— 不停的话，`clear()` 之后 3 帧又堆回来了，
	#    出图看到的是"一圈大方框"而不是船体闪光。
	#    停掉后船定格（正是截图想要的），相机的插值在自己的节点上，不受影响。
	scene.set_process(false)

	var arena = scene.get("arena")
	# ★ 接线验证：真实战斗（经 `_on_shot_fired`）到底有没有触发船体闪光。
	#   探针后面会手动再施加一遍做视觉对比，所以这里必须在**手动之前**读。
	var total_flash := 0
	for v in _collect(arena):
		total_flash += int(v.call("flash_count"))
	print("  真实战斗触发 flash_hit 次数 = %d（0 = 接线断了）" % total_flash)

	await _shot_overlay_opaque(arena)
	await _shot(arena, "01_默认俯视", 0.0, 0.0, 0.0)
	await _shot(arena, "02_贴近特写", 0.0, 0.0, 2.2)
	await _shot(arena, "03_斜45度", 0.9, 0.35, 1.4)

	print("完成。")
	get_tree().quit()


## 渲染路径自检：把 overlay 拉满 alpha=1 且冻住包络。
##
## 判读：船体应整片变成纯青蓝。**如果船体形状完整变色** ⇒ overlay 通了；
## 如果毫无变化 ⇒ `material_overlay` 在这条渲染路径上没生效，得换方案。
func _shot_overlay_opaque(arena: Node) -> void:
	var vis_list := _collect(arena)
	if vis_list.is_empty():
		return
	var cam = arena.get("orion_cam")
	cam.set("zoom", float(ORBIT_CAM_SCRIPT.DEFAULT_ZOOM) * 2.2)
	await _frames(20)
	for v in vis_list:
		v.call("flash_hit", &"shield")
		# 冻住包络：`_process` 见到 life<=0 会 early-return，不再改 alpha
		v.set("_flash_life", 0.0)
		var m = v.get("_flash_mat")
		if m != null:
			m.set("albedo_color", Color(0.15, 0.85, 1.0, 1.0))
	await _frames(2)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img == null:
		print("  ✗ 00_overlay不透明测试：取图失败")
		return
	img.save_png(SHOT_DIR + "/00_overlay不透明测试.png")
	print("  ✔ 00_overlay不透明测试（船体应整片青蓝）")
	# 收尾：把 alpha 归零，别影响后面几张
	for v in vis_list:
		var m2 = v.get("_flash_mat")
		if m2 != null:
			m2.set("albedo_color", Color(1.0, 1.0, 1.0, 0.0))


## 打一个机位并截屏。
func _shot(arena: Node, name: String, yaw_add: float,
		pitch_add: float, zoom_mul: float) -> void:
	var cam = arena.get("orion_cam")
	var base_zoom := float(ORBIT_CAM_SCRIPT.DEFAULT_ZOOM)
	if zoom_mul > 0.0:
		cam.set("zoom", base_zoom * zoom_mul)
	if yaw_add != 0.0:
		cam.call("set_yaw_target", float(cam.get("yaw")) + yaw_add)
	if pitch_add != 0.0:
		cam.call("set_pitch_target", float(cam.get("pitch")) + pitch_add)
	await _frames(20)

	# ⚠️ `debug_fast_forward_battle()` 一次跑完几百 tick，期间 `_process` 没机会
	#    回收 —— 场景里会堆着最多 MAX_FX(140) 个**停在 t=0** 的命中爆点/曳光。
	#    不清理的话它们会盖在船上，出图看到的是"一圈大方块"而不是船体闪光。
	#    （真实战斗逐帧推进时不会有这个现象，这是探针特有的假象。）
	var bfx = arena.get("battle_fx")
	if bfx != null:
		bfx.call("clear")
		await _frames(3)

	# 特效寿命只有 0.18~0.38s ⇒ 截图前**重新施加**一遍，保证画面里正在亮。
	# ⚠️ 不造命中爆点：那个 billboard 方片在特写下有 3 个世界单位宽，
	#    会把船体本身糊住 —— 这一版要看的是**船体泛光**，不是爆点。
	_apply_hits(arena, false)
	await _frames(2)
	_dump_flash_state(arena)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img == null:
		print("  ✗ %s：取图失败" % name)
		return
	var path := SHOT_DIR + "/" + name + ".png"
	img.save_png(path)
	print("  ✔ %s → %s  %s" % [name, ProjectSettings.globalize_path(path), str(img.get_size())])


## 对场上的船轮流施加 shield / armor / hull 三种受击反馈。
##
## `with_fx` = 同时造命中爆点（截图时要有，否则只有船体泛光、没有打击点）。
func _apply_hits(arena: Node, with_fx: bool) -> void:
	var bfx = arena.get("battle_fx")
	if bfx != null:
		bfx.set("fx_enabled", true)
	var vis_list := _collect(arena)
	var n := 0
	for v in vis_list:
		var sh = v.get("ship")
		if sh == null:
			continue
		var lay: StringName = LAYERS[n % LAYERS.size()]
		v.call("flash_hit", lay)
		# ⚠️ 定格在**峰值**：`flash_hit` 之后 alpha 是满的，但 `await` 几帧
		#    就衰减到 0.07 了（实测），截图会拍成"快灭了"的样子。
		#    把 life 置 0 ⇒ `_process` 早退且不再改 alpha，画面停在命中瞬间。
		v.set("_flash_life", 0.0)
		if with_fx:
			arena.call("fx_hit", sh.get("body").position, 5, lay)
		print("      %s → %s" % [String(sh.get("ship_name")), String(lay)])
		n += 1
	print("    施加受击：%d 艘（shield/armor/hull 轮换）" % n)
	# 自查：overlay 到底有没有铺到船体网格上（0 = 收集失败，什么都看不见）
	if not vis_list.is_empty():
		var meshes = vis_list[0].get("_flash_meshes")
		print("    探针自查：首艘船 overlay 网格数 = %d"
				% (0 if meshes == null else (meshes as Array).size()))


## 打印 overlay 的真实状态（判断「没效果」到底是没建、没挂、还是 alpha 掉了）
func _dump_flash_state(arena: Node) -> void:
	var vis_list := _collect(arena)
	if vis_list.is_empty():
		print("    [状态] 没有船")
		return
	var v = vis_list[0]
	var mat = v.get("_flash_mat")
	var meshes = v.get("_flash_meshes")
	var a := -1.0
	if mat != null:
		a = float(mat.get("albedo_color").a)
	var overlay_ok := 0
	if meshes != null:
		for mi in meshes:
			if mi != null and mi.get("material_overlay") != null:
				overlay_ok += 1
	print("    [状态] flash_life=%.3f · alpha=%.3f · 网格 %d · 已挂 overlay %d"
			% [float(v.get("_flash_life")), a,
			(0 if meshes == null else (meshes as Array).size()), overlay_ok])


func _collect(n: Node, out: Array = []) -> Array:
	for c in n.get_children():
		if c is EveShipVisual:
			out.append(c)
		_collect(c, out)
	return out


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
