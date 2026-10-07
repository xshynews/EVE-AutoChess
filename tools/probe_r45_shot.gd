extends Node
## 45 轮实机取证：跑一局 → 稳定后截 3 张图（0s / 2s / 4s），存到 `user://r45_*.png`。
## 必须**非 headless**（截图要真实渲染上下文）。
const YAW := preload("res://scripts/data/eve_ship_yaw.gd")

var _battle: Node = null
var _arena: Node = null
var _lines: Array[String] = []

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
	for k in ["abaddon", "catalyst", "myrmidon"]:
		run.bench.append({"ship_key": StringName(k), "star": 1, "cell": Vector2i(-1, -1)})
		run.field.append(run.bench[run.bench.size() - 1].duplicate(true))
	run.changed.emit()
	_battle.call("_respawn_own_fleet")
	for _i in 5:
		await get_tree().process_frame
	_battle.call("start_battle")
	print("[r45] 战斗启动")
	await get_tree().create_timer(3.0).timeout

	for shot in 3:
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		if img != null:
			img.save_png("user://r45_%d.png" % shot)
		_log_state(shot)
		# ★ 47 轮：额外拍一张**俯视全景** —— 从正上方看整个战场，
		#   一眼就能判「52 艘舰艏是否都朝着敌人（−Z）」。
		await _shot_top_down(shot)
		await get_tree().create_timer(2.0).timeout

	for s in _lines:
		print(s)
	get_tree().quit(0)


## 把相机搬到战场正上方拍一张 —— 敌人恒在世界 −Z（红线 42）。
func _shot_top_down(shot: int) -> void:
	var cam := _find_camera()
	if cam == null:
		_lines.append("  ⚠️ 找不到相机，跳过俯视图")
		return
	_cam_backup = {&"pos": cam.global_position, &"xf": cam.global_transform}
	cam.global_position = Vector3(0.0, 42.0, 0.0)
	cam.look_at(Vector3(0.0, 0.0, 0.0), Vector3(0.0, 0.0, -1.0))
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img != null:
		img.save_png("user://r47_top_%d.png" % shot)
	# 还原机位
	cam.global_transform = _cam_backup[&"xf"]


func _find_camera() -> Camera3D:
	var stack: Array[Node] = [_battle]
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		if n is Camera3D and (n as Camera3D).current:
			return n
		for c in n.get_children():
			stack.append(c)
	return null

var _cam_backup: Dictionary = {}


func _log_state(shot: int) -> void:
	var ships_layer: Node = _arena.ships_layer
	_lines.append("── 第 %d 张（t≈%d s）──" % [shot, 3 + shot * 2])
	for c in ships_layer.get_children():
		if not (c.has_method("sync_from_body") and c.get("ship") != null):
			continue
		var ship = c.get("ship")
		if not ship.alive or ship.body == null:
			continue
		var key := String(ship.ship_key)
		# ★ 47 轮：改用**真网格节点的世界基**（引擎自己连乘父子链），
		#   旧版 `quaternion * (model.basis * bow)` 是自证式读数，
		#   测不出「glb 内层还有一层旋转」—— 那正是实机全乱的真因。
		var mesh_n := _mesh_node_of(c)
		if mesh_n == null:
			_lines.append("  %-12s 找不到网格节点" % key)
			continue
		var bow_w: Vector3 = (mesh_n.global_transform.basis.orthonormalized()
				* YAW.bow_axis(ship.ship_key)).normalized()
		var aim: Vector3 = ship.body.aim_dir
		var vel: Vector3 = ship.body.velocity
		var da := bow_w.dot(aim.normalized()) if aim.length_squared() > 1e-12 else NAN
		var dv := bow_w.dot(vel.normalized()) if vel.length() > 1e-6 else NAN
		_lines.append("  %-12s bow·敌向=%+.3f   bow·v̂=%+.3f" % [key, da, dv])


func _mesh_node_of(vis: Variant) -> MeshInstance3D:
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
