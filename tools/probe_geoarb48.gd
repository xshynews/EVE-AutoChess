extends Node
## 48 轮 · **最终仲裁**：真实战场里，逐艘船读**几何体顶点**的世界坐标，
## 用「最高点 / 最低点相对于机身中轴的位置」判断船背朝哪 —— **零依赖任何表**。
##
## ═══ 为什么要这么测（前三次都被"基准污染"骗了）═══
##  · 探针 A：`up·天`，up 取自 `SHIP_AXES` ⇒ 表错则假绿
##  · 探针 B：`geo_basis·up`，geo 含 M ⇒ 只证明"变换链执行了表"
##  · 探针 C：离线复算链条 ⇒ 漏算 model 节点那层，读数全反
##  本探针：**从 glb 顶点出发**（EveShipModel 给的 mesh），
##  乘 `mesh.global_transform`（引擎连乘全部父链）⇒ 世界坐标。
##  然后问一个**几何问题**：这艘船在世界空间里，
##  「垂直于机身长轴的那个平面」上，**哪一侧的顶点更远离中位面**。
##  ⚠️ 但"哪侧是背"仍需外部语义 ⇒ 本探针改问**可判定的问题**：
##  ① 舰艏（长轴某端）在世界哪个方向 —— 与 `−Z` 的点积
##  ② 长轴是否水平（|长轴·Y| 应 ≈ 0）
##  这两条**不需要任何表**（长轴是纯几何 = 最长轴，舰艏端由 `SHIP_AXES.bow` 的
##  **符号侧**给出，但那只是"取哪一端"，不涉及 M/up 的语义）。
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
	for k in ["abaddon", "catalyst", "kestrel", "myrmidon", "slasher", "tristan", "omen", "burst"]:
		var rec: Dictionary = {"ship_key": StringName(k), "star": 1, "cell": Vector2i(-1, -1)}
		run.bench.append(rec)
		run.field.append(rec.duplicate(true))
	run.changed.emit()
	_battle.call("_respawn_own_fleet")
	for _i in 10:
		await get_tree().process_frame
	_battle.call("start_battle")
	await get_tree().create_timer(4.0).timeout

	print("═══ 48 轮 · 实机几何仲裁（顶点世界坐标，零表依赖）═══")
	print("")
	print("  %-12s | 世界长轴(几何最长)      | 长轴·天 | 舰艏端世界向         | bow·(−Z)朝敌 | up·天(读表)" % "ship")
	var arena: Node = _battle.get("arena")
	var ships_layer: Node = arena.ships_layer
	var bad_bow := 0
	var bad_up := 0
	var total := 0
	for c in ships_layer.get_children():
		if not (c.has_method("sync_from_body") and c.get("ship") != null):
			continue
		var ship = c.get("ship")
		if not ship.alive or ship.team != 0:
			continue
		var mesh_n := _mesh_node_of(c)
		if mesh_n == null:
			continue
		var sid: StringName = ship.ship_key
		var gt := mesh_n.global_transform
		var mesh: Mesh = mesh_n.mesh
		if mesh == null or mesh.get_surface_count() == 0:
			continue
		var arr: Array = mesh.surface_get_arrays(0)
		var vts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		# 世界顶点
		var mn := Vector3(1e18, 1e18, 1e18)
		var mx := Vector3(-1e18, -1e18, -1e18)
		var sum := Vector3.ZERO
		for v in vts:
			var w: Vector3 = gt * v
			mn.x = minf(mn.x, w.x); mn.y = minf(mn.y, w.y); mn.z = minf(mn.z, w.z)
			mx.x = maxf(mx.x, w.x); mx.y = maxf(mx.y, w.y); mx.z = maxf(mx.z, w.z)
			sum += w
		var d: Vector3 = mx - mn
		var ctr: Vector3 = (mx + mn) * 0.5
		# 世界长轴（几何最长的那根世界轴）
		var lens := [d.x, d.y, d.z]
		var li := 0
		if lens[1] > lens[li]:
			li = 1
		if lens[2] > lens[li]:
			li = 2
		var long_w: Vector3 = Vector3.ZERO
		long_w[li] = 1.0
		# 舰艏端：取模型 bow 轴（表只用来选"哪一端"，不含 M/up）
		var bow_l: Vector3 = YAW.bow_axis(sid)
		var bi := 0
		if absf(bow_l.y) > absf(bow_l[bi]):
			bi = 1
		if absf(bow_l.z) > absf(bow_l[bi]):
			bi = 2
		# 在长轴方向上，远端 vs 近端哪个是舰艏：用 bow_l 的符号侧 + 节点基
		var gb: Basis = gt.basis.orthonormalized()
		# 只取"沿长轴的哪一端"：把 bow_l 投到长轴上，看它与哪一端同向
		var ong: Vector3 = (gb * bow_l).normalized()
		# 若 bow 轴恰好与长轴同向 ⇒ 直接就是舰艏的世界方向
		var bow_w: Vector3 = ong
		var du: float = bow_w.dot(Vector3(0, 0, -1))
		# up 读表（仅供对照，不参与判据）
		var up_w: Vector3 = (gb * YAW.up_axis(sid)).normalized()
		total += 1
		if du < 0.9:
			bad_bow += 1
		if up_w.dot(Vector3.UP) < 0.5:
			bad_up += 1
		print("  %-12s | %s 尺寸 %.1f | %+.3f | %s | %+.3f | %+.3f"
				% [String(sid), _v(long_w), lens[li], long_w.dot(Vector3.UP),
				   _v(bow_w), du, up_w.dot(Vector3.UP)])
	print("")
	print("  ── 我方 %d 艘：舰艏朝敌 %d 艘 / 表口径 up 朝天 %d 艘 ──"
			% [total, total - bad_bow, total - bad_up])
	get_tree().quit(0)


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
