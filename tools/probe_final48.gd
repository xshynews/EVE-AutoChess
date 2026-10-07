extends Node
## 48 轮 · **实机端到端最终验证**：真实战场里，逐艘船打印
##   ① 几何体的世界 `up`（用 `SHIP_AXES` 的 up 轴 × 网格节点世界基）
##   ② 几何体的世界 `bow`（同上）
##   ③ 屏幕坐标（相机口径）
## 并且**同时**打印"如果只看几何、不看表"的两个量：
##   ④ 世界包围盒的三轴尺寸（判断船是横躺还是竖躺）
##
## ⚠️ 这是第三次尝试"不依赖表的判据"。前两次都失败：
##    · `up·天` 用表 ⇒ 假绿
##    · `geo_basis·up` ⇒ 只证明变换链执行了表
##    · 上下半展宽 ⇒ kestrel/slasher 结论相反
## 本次**只输出数据、不下结论**，把判断权交给用户（红线 40）。
const YAW := preload("res://scripts/data/eve_ship_yaw.gd")

var _battle: Node = null


func _ready() -> void:
	var packed: PackedScene = load("res://scenes/battle_scene.tscn")
	_battle = packed.instantiate()
	add_child(_battle)
	for _i in 60:
		await get_tree().process_frame
	var run: Node = _battle.get("run")
	run.coin = 999
	run.roll_shop()
	for i in 5:
		run.buy(i)
	run.bench.clear()
	run.field.clear()
	# 覆盖全部 6 种 spec 型 + 主流
	for k in ["abaddon", "omen", "catalyst", "algos", "kestrel", "slasher",
			"inquisitor", "myrmidon", "tristan"]:
		var rec: Dictionary = {"ship_key": StringName(k), "star": 1, "cell": Vector2i(-1, -1)}
		run.bench.append(rec)
		run.field.append(rec.duplicate(true))
	run.changed.emit()
	_battle.call("_respawn_own_fleet")
	for _i in 10:
		await get_tree().process_frame
	_battle.call("start_battle")
	await get_tree().create_timer(3.5).timeout

	print("═══ 48 轮 · 实机端到端数据 ═══")
	print("")
	print("  %-12s | spec        | 世界bow(表口径)      | 世界up(表口径)       | 世界几何尺寸(长/中/薄)" % "ship")
	var arena: Node = _battle.get("arena")
	var ships_layer: Node = arena.ships_layer
	for c in ships_layer.get_children():
		if not (c.has_method("sync_from_body") and c.get("ship") != null):
			continue
		var ship = c.get("ship")
		if not ship.alive:
			continue
		var mesh_n := _mesh_node_of(c)
		if mesh_n == null:
			continue
		var sid: StringName = ship.ship_key
		var gb: Basis = mesh_n.global_transform.basis.orthonormalized()
		var bw: Vector3 = (gb * YAW.bow_axis(sid)).normalized()
		var uw: Vector3 = (gb * YAW.up_axis(sid)).normalized()
		# 几何尺寸（世界）
		var d := _geo_extent(mesh_n)
		var team := "我" if ship.team == 0 else "敌"
		print("  %-12s | %-11s | %s | %s | %.1f / %.1f / %.1f  [%s]"
				% [String(sid), String(YAW.AXIS_REMAP.get(sid, "?")),
				   _v(bw), _v(uw), d.x, d.y, d.z, team])
	print("")
	print("  ── 判据提示（红线 42：敌人恒在 −Z）──")
	print("   · 舰艏朝敌 ⇒ 世界 bow ≈ (0,0,−1)")
	print("   · 船背朝天 ⇒ 世界 up  ≈ (0,1,0)")
	get_tree().quit(0)


func _geo_extent(m: MeshInstance3D) -> Vector3:
	var mesh: Mesh = m.mesh
	if mesh == null or mesh.get_surface_count() == 0:
		return Vector3.ZERO
	var arr: Array = mesh.surface_get_arrays(0)
	var vts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var gt := m.global_transform
	var mn := Vector3(1e18, 1e18, 1e18)
	var mx := Vector3(-1e18, -1e18, -1e18)
	for v in vts:
		var w: Vector3 = gt * v
		mn.x = minf(mn.x, w.x); mn.y = minf(mn.y, w.y); mn.z = minf(mn.z, w.z)
		mx.x = maxf(mx.x, w.x); mx.y = maxf(mx.y, w.y); mx.z = maxf(mx.z, w.z)
	return mx - mn


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


func _v(v: Vector3) -> String:
	return "(%+.2f,%+.2f,%+.2f)" % [v.x, v.y, v.z]
