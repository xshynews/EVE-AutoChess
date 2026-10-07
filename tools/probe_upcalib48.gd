extends Node
## 48 轮 · **船背朝向** 校准探针（基准独立版）。
##
## ═══ 为什么重写（48 轮自省）═══
##  旧版 `probe_screenup48` 用 `YAW.up_axis(sid)` 拿"模型空间 up"，再乘节点世界基。
##  这**只能证明"变换链忠实执行了 SHIP_AXES"** —— 一旦 `SHIP_AXES` 的 up 本身标错，
##  探针会跟着一起错，输出 **假绿**（全库 `up·天 = +1.000`）。
##  这正是红线 40 的镜像坑：**拿被测对象当基准**。
##
## ═══ 本版判据（基准 = 几何，零依赖 SHIP_AXES）═══
##  · 取**网格顶点**的世界坐标（网格节点 `global_transform` × 顶点），
##  · 算世界包围盒三边尺寸 ⇒ **最薄的一边 = 船背法线方向**（出厂坐标系是平铺的），
##  · 再看"船背该朝哪一侧"：EVE 舰船顶面**装备/上层建筑更多 ⇒ 顶面顶点更密/更外扩**。
##
##  ⚠️ 本探针**完全不读** `SHIP_AXES` / `AXIS_REMAP` / `FLIP`
##     ⇒ 可以作为"另一张表对不对"的**独立基准**。
##
## ═══ 输出 ═══
##  逐艘打印：世界三轴尺寸（排序）+ 最薄轴 + 建议 up 轴 + 与现表是否一致。
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
	await get_tree().create_timer(3.0).timeout

	print("═══ 48 轮 · 船背校准（几何真值，不读 SHIP_AXES）═══")
	print("")
	print("  %-12s | 世界三轴尺寸(排序)        | 最薄轴 | 现表 up | 一致? | up·天" % "ship")
	var arena: Node = _battle.get("arena")
	var ships_layer: Node = arena.ships_layer
	var bad := 0
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
		# ── 世界顶点包围盒 ──
		var gb: Basis = mesh_n.global_transform.basis
		var go: Vector3 = mesh_n.global_transform.origin
		var mesh: Mesh = mesh_n.mesh
		if mesh == null or mesh.get_surface_count() == 0:
			continue
		var arr: Array = mesh.surface_get_arrays(0)
		var vts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var mn := Vector3(1e18, 1e18, 1e18)
		var mx := Vector3(-1e18, -1e18, -1e18)
		for v in vts:
			var w: Vector3 = go + gb * v
			mn.x = minf(mn.x, w.x); mn.y = minf(mn.y, w.y); mn.z = minf(mn.z, w.z)
			mx.x = maxf(mx.x, w.x); mx.y = maxf(mx.y, w.y); mx.z = maxf(mx.z, w.z)
		var d: Vector3 = mx - mn
		# 排序取最薄
		var ax := [Vector3(d.x, 0, 0), Vector3(0, d.y, 0), Vector3(0, 0, d.z)]
		var lens := [d.x, d.y, d.z]
		var order := [0, 1, 2]
		order.sort_custom(func(a, b): return lens[a] < lens[b])
		var thin_i: int = order[0]
		var thin_name: String = "XYZ"[thin_i]
		# 现表 up（仅用于"对照"，不参与判据）
		var cur_up: Vector3 = YAW.up_axis(sid)
		var cur_name: String = _axis_name(cur_up)
		var same: bool = cur_name[1] == thin_name
		# 世界 up（读现表 up 乘节点基）—— 只为展示"现表口径下船背朝哪"
		var up_w: Vector3 = (gb.orthonormalized() * cur_up).normalized()
		total += 1
		if not same:
			bad += 1
		print("  %-12s | %6.1f /%6.1f /%6.1f |   %s    | %-7s |  %s  | %+.3f"
				% [String(sid), lens[order[0]], lens[order[1]], lens[order[2]],
				   thin_name, cur_name, ("✔" if same else "✗"), up_w.dot(Vector3.UP)])
	print("")
	print("  ── 取样 %d 艘：现表 up 与几何最薄轴不符 %d 艘 ──" % [total, bad])
	get_tree().quit(0)


func _axis_name(v: Vector3) -> String:
	var ax := ["X", "Y", "Z"]
	var i := 0
	if absf(v.y) > absf(v.x) and absf(v.y) >= absf(v.z):
		i = 1
	elif absf(v.z) > absf(v.x) and absf(v.z) > absf(v.y):
		i = 2
	return ("+" if v[i] >= 0.0 else "-") + ax[i]


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
