extends Node
## ══════════════════════════════════════════════════════════════════════
##  47 轮 · **相机口径**取证 —— 舰艏在屏幕上到底指向哪
## ══════════════════════════════════════════════════════════════════════
##
## ── 为什么要第三层口径 ═══════════════════════════════════════════════
##  已有两层：① 复刻算式（自证，已废）② 网格节点世界基（引擎算，已是硬证据）。
##  但用户看的是**屏幕**。这一层用 `Camera3D.unproject_position()` 把
##  「舰艏点」和「舰尾点」投到像素坐标，再看屏幕上的方向向量：
##
##      屏幕向上（−Y 像素） = 世界 −Z = 敌人方向（红线 42）
##      ⇒ 判据：每艘船的「舰尾→舰艏」在屏幕上应指向**上方**
##
##  这一层的价值：它顺带把「相机是否真的架在我方背后朝 −Z 看」也验了
##  ——红线 42 的语境若被破坏，这里会立刻暴露。
##
## 跑法（必须非 headless，要真相机）：
##   `<godot> --path <工程> --quit-after 1200 res://tools/probe_screenbow47.tscn`
const YAW := preload("res://scripts/data/eve_ship_yaw.gd")

var _battle: Node = null
var _arena: Node = null

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
	# 覆盖 4 类几何：R_y(180°) / R_x(90°) / 120°斜轴
	for k in ["abaddon", "catalyst", "kestrel", "myrmidon", "tristan",
			"incursus", "omen", "slasher"]:
		run.bench.append({"ship_key": StringName(k), "star": 1, "cell": Vector2i(-1, -1)})
		run.field.append(run.bench[run.bench.size() - 1].duplicate(true))
	run.changed.emit()
	_battle.call("_respawn_own_fleet")
	for _i in 5:
		await get_tree().process_frame
	_battle.call("start_battle")
	await get_tree().create_timer(3.0).timeout
	_report()
	get_tree().quit(0)


func _report() -> void:
	var cam := _find_camera()
	if cam == null:
		print("✗ 找不到当前相机")
		return
	print("═══ 47 轮 · 相机口径：舰艏在屏幕上指向哪 ═══")
	print("  相机 pos = %s" % str(cam.global_position))
	print("  （判据：屏幕「上」= 世界 −Z = 敌向；舰尾→舰艏 应指向屏幕上方）")
	print("  ⚠️ 只判**我方**舰船：敌方（team != 0）本来就应该背对我方 ——")
	print("     把敌人也算进来会得到一堆「✗ 不朝上」，那是**假失败**（实测踩过）。")
	print("  %-12s | %-6s | %-10s | %-22s | %s"
			% ["ship", "team", "world·敌向", "屏幕 dx,dy(px)", "判定"])
	var ok_n := 0
	var bad_n := 0
	var ships_layer: Node = _arena.ships_layer
	for c in ships_layer.get_children():
		if not (c.has_method("sync_from_body") and c.get("ship") != null):
			continue
		var ship = c.get("ship")
		if not ship.alive or ship.body == null:
			continue
		# ★ 只判我方（team 0）；敌方舰船背对我方是**正确行为**，不该计入。
		var team := int(ship.team)
		if team != 0:
			continue
		var mesh_n := _mesh_node_of(c)
		if mesh_n == null:
			continue
		var wb: Basis = mesh_n.global_transform.basis.orthonormalized()
		var b := (wb * YAW.bow_axis(ship.ship_key)).normalized()
		# 舰艏点 / 舰尾点：从网格世界位置沿 ±舰艏轴 各偏一点
		var xf := mesh_n.global_transform
		var center := xf.origin
		var p_bow := center + b * 1.0
		var p_stern := center - b * 1.0
		var s_bow := cam.unproject_position(p_bow)
		var s_stern := cam.unproject_position(p_stern)
		var d := s_bow - s_stern
		var dy := d.y   # 屏幕 y 向下为正 ⇒ 指向上方 = dy < 0
		var da := b.dot(Vector3(0.0, 0.0, -1.0))
		var verdict := "✔ 朝上（=敌人）" if dy < -1.0 else "✗ 不朝上"
		var snap := "up" if dy < -1.0 else ("dn" if dy > 1.0 else "side")
		if dy < -1.0:
			ok_n += 1
		else:
			bad_n += 1
		print("  %-12s | %-6d | %+9.4f | (%+8.1f,%+8.1f) %-4s | %s"
				% [String(ship.ship_key), team, da, d.x, d.y, snap, verdict])
	print("  ── 我方朝上 %d 艘 · 不朝上 %d 艘 ──" % [ok_n, bad_n])
	if bad_n == 0 and ok_n > 0:
		print("★★★ 相机口径全绿：屏幕上所有舰船都朝敌人 ★★★")
	else:
		print("✗✗✗ 相机口径发现问题 ✗✗✗")


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


func _find_camera() -> Camera3D:
	var stack: Array[Node] = [_battle]
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		if n is Camera3D and (n as Camera3D).current:
			return n
		for c in n.get_children():
			stack.append(c)
	return null
