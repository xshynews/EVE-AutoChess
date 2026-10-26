extends Node
## 护盾曲面贴花 · 真实战斗出图探针（非无头）
##
## 跑法：
##   "$GODOT_BIN" --path . res://tools/probe_shield_impact.tscn
##
## 验的是：① 真实战斗 shield 分支接线；② 覆盖率与槽位上限；③ 复用计数；④ 出图。

const BATTLE_SCENE := preload("res://scenes/battle_scene.tscn")
const SHOT_DIR := "user://shield_impact"

var _cam: Camera3D
var _arena = null

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SHOT_DIR)
	if DisplayServer.get_name() == "headless":
		print("X 必须非 headless")
		get_tree().quit()
		return
	print("=".repeat(64))
	print("护盾曲面贴花探针 —— 产物：%s" % ProjectSettings.globalize_path(SHOT_DIR))
	print("=".repeat(64))

	var scene: Variant = BATTLE_SCENE.instantiate()
	add_child(scene)
	await _frames(60)

	var run = scene.get("run")
	run.set("coin", 999)
	# 五档各一艘：护卫 / 驱逐 / 巡洋 / 战巡 / 战列 —— 验证锚点数按吨位档变化
	var bench_ids: Array = ["punisher", "cormorant", "caracal", "hurricane", "raven"]
	for i in bench_ids.size():
		run.get("bench").append({"ship_key": StringName(bench_ids[i]), "star": 1, "cost": 1})
	run.emit_signal("changed")
	await _frames(4)
	for i in 5:
		run.call("deploy_from_bench", 0, 7 - i / 9, i % 9)
	run.emit_signal("changed")
	await _frames(4)

	scene.call("start_battle")
	await _frames(90)
	var sim = scene.get("sim")
	if sim == null:
		print("X start_battle 没建出模拟器")
		get_tree().quit()
		return
	scene.call("debug_fast_forward_battle", 14.0)
	await _frames(2)
	print("  交火中 sim.elapsed=%.1fs" % float(sim.elapsed))
	print("  吸附上限 %.0f°" % load("res://scripts/visual/eve_shield_impact.gd").SNAP_MAX_ANGLE_DEG)

	scene.set_process(false)

	var arena = scene.get("arena")
	_arena = arena
	var total := 0
	var reused := 0
	var ships_with_fx := 0
	var rejected := 0
	var best_vis: Node3D = null
	var best_live := -1
	for v in _collect(arena):
		var fx = v.get("_shield_fx")
		if fx != null and is_instance_valid(fx):
			ships_with_fx += 1
			total += int(fx.total_hits)
			reused += int(fx.snap_reuse)
			rejected += int(fx.rejected)
			var live := 0
			for s in fx._slots:
				if s.node.visible:
					live += 1
			if live > best_live:
				best_live = live
				best_vis = v
	print("  护盾贴花：船数=%d 命中=%d 复用=%d 超限丢弃=%d 单船最多可见槽=%d" % [ships_with_fx, total, reused, rejected, best_live])
	# 数值验收：船艏 / 引擎 是否各有 ≥5 个锚点
	for v in _collect(arena):
		var fx = v.get("_shield_fx")
		if fx == null or not is_instance_valid(fx):
			continue
		var bow: Vector3 = fx._bow
		var nb := 0
		var ns := 0
		for s in fx._slots:
			if s.dir.dot(bow) > 0.55:
				nb += 1
			if s.dir.dot(-bow) > 0.55:
				ns += 1
		print("    %s：锚点=%d 船艏=%d 引擎=%d" % [String(v.name), fx._slots.size(), nb, ns])
		break
	if total == 0:
		print("  X 接线断了：真实战斗没有产生护盾贴花")

	await _frames(4)

	# 调试：把我们的贴花染成实心红，和游戏自带的蓝色命中环区分开
	if OS.get_cmdline_user_args().has("--red"):
		for v in _collect(arena):
			var fx = v.get("_shield_fx")
			if fx != null and is_instance_valid(fx):
				for sl in fx._slots:
					sl.mat.set_shader_parameter("debug_solid", true)
					sl.mat.shader = null
					sl.mat.shader = load("res://scripts/visual/fx_shield_decal.gdshader")
					sl.mat.set_shader_parameter("debug_solid", true)

	if best_vis != null:
		await _shot_close(best_vis, "01_decal_close")
	await _shot_wide(arena, "02_battle_wide")

	print("完成。")
	get_tree().quit()

func _collect(arena) -> Array:
	var out: Array = []
	for id in arena._ship_nodes.keys():
		var n = arena._ship_nodes[id]
		if n != null and is_instance_valid(n):
			out.append(n)
	return out

func _ensure_cam() -> void:
	if _cam != null and is_instance_valid(_cam):
		return
	_cam = Camera3D.new()
	_cam.fov = 38.0
	_cam.near = 0.05
	_cam.far = 8000.0
	add_child(_cam)
	_cam.make_current()

func _shot_close(vis: Node3D, tag: String) -> void:
	# 轨道相机每帧都会覆盖相机变换 ⇒ 先停掉它，再直接摆相机。
	# 机位取「最近一个可见贴花」的法线方向，否则贴花会转到船背面看不见。
	var orbit = _arena.get("orion_cam")
	var center: Vector3 = vis.global_position
	var fx = vis.get("_shield_fx")
	var target := center
	if fx != null and is_instance_valid(fx):
		var best = null
		for sl in fx._slots:
			if sl.node.visible:
				if best == null or sl.t < best.t:
					best = sl
		if best != null:
			var aabb: AABB = best.node.mesh.get_aabb()
			target = best.node.global_transform * aabb.get_center()
			print("    贴花中心 %s（t=%.2f）" % [str(target), float(best.t)])
	if orbit != null:
		orbit.set_process(false)
		# 直接拿视口当前相机，避免抓到一个没在渲染的引用
		var cam3d: Camera3D = get_viewport().get_camera_3d()
		if cam3d == null:
			cam3d = orbit.get("camera")
		if cam3d != null:
			var n := (target - center)
			if n.length() < 0.001:
				n = Vector3(0, 1, 0)
			n = n.normalized()
			var pos := target + n * 4.6 + Vector3(0, 0.6, 0)
			cam3d.global_position = pos
			cam3d.look_at(target, Vector3.UP)
			print("    机位 %s → %s" % [str(pos), str(target)])
	await _frames(3)
	# 手动放一发炮击亮痕，让截图正好卡在它存在的 0.11 秒里
	var attacker := target + Vector3(9.0, 3.0, 7.0)
	_arena.call("fx_artillery", attacker * 1000.0, target * 1000.0, 4)
	await _frames(1)
	await _save(tag)

func _shot_wide(arena, tag: String) -> void:
	var orbit = arena.get("orion_cam")
	if orbit != null:
		orbit.set("attached", true)
		orbit.set("zoom", 3.32)
		orbit.set("_target_zoom", 3.32)
	await _frames(20)
	await _save(tag)

func _save(tag: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [SHOT_DIR, tag]
	img.save_png(path)
	print("  [SHOT] %s %dx%d" % [ProjectSettings.globalize_path(path), img.get_width(), img.get_height()])

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
