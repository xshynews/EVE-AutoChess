extends Node
## 48 轮 · **船背朝向** 相机口径探针。
##
## ═══ 为什么需要它（这是 47 轮之后暴露的"第五个自由度"）═══
##  47 轮把「舰艏朝敌」（= 两个水平自由度）修好了，但用户实机立刻报
##  「**现在船全部肚皮朝天**」—— 这是一个**统一方向**的错，与之前"每艘各异"完全不同
##  ⇒ 说明还有**一层全局的 180°** 没被处理。
##
##  ⚠️ 而 47 轮的三层口径**全都测不到它**：
##    · `probe_worldbow47` / `probe_screenbow47` 只测 `bow`（舰艏）—— 对 180° 无感；
##    · `probe_accept43e` 的 `up·天` 判据是**表内算表**（拿 `AXIS_REMAP` 反解 `up`），
##      两张表同向漂移时**照样全绿** ⇒ 正是红线 40 的镜像坑。
##  ⇒ 本条是**唯一**用引擎算出的世界量测「船背」的探针。
##
## ═══ 判据（红线 42：敌人恒在世界 −Z；相机在我方背后朝 −Z 看）═══
##  · 相机在上方 ⇒ 「船背朝天」= 世界 **+Y** ⇒ `up · (0,1,0) ≈ +1`
##  · 「肚皮朝天」      ⇔ `up · (0,1,0) ≈ −1`
##
## ═══ 口径（红线 40：读引擎算的量，不自复刻算式）═══
##  取**网格节点**的 `global_transform.basis`（引擎连乘父子链），
##  再用 `SHIP_AXES` 拿模型空间的 up 轴 ⇒ 世界 up。
##
##  ⚠️ 但要注意：`SHIP_AXES` 的 up 是**人工标定值**，它本身可能是错的
##     （"肚皮朝天"也可能**不是**变换错，而是 up 表标反了）。
##     所以本探针**同时**输出「独立于 up 表」的几何判据：
##       `bow × up_screen` —— 从屏幕上看舰艏在左还是右（左右手性），
##     两者交叉才能定位是「变换错」还是「up 表错」。
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
	# 取样覆盖：主流 + 三型非主流 spec（避免只测到一类）
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

	print("═══ 48 轮 · 船背朝向（世界量 + 屏幕量）═══")
	print("  判据：船背朝天 ⇒ up·(0,1,0) ≈ +1；**肚皮朝天 ⇒ ≈ −1**")
	print("")
	print("  %-12s | mesh节点世界 up           | up·天  | 屏幕bow向量(尾→艏)  | 判" % "ship")
	var updown := 0
	var total := 0
	var arena: Node = _battle.get("arena")
	var ships_layer: Node = arena.ships_layer
	for c in ships_layer.get_children():
		if not (c.has_method("sync_from_body") and c.get("ship") != null):
			continue
		var ship = c.get("ship")
		if not ship.alive or ship.team != 0:
			continue
		var mesh_n := _mesh_node_of(c)
		if mesh_n == null:
			continue
		var gb: Basis = mesh_n.global_transform.basis.orthonormalized()
		var sid: StringName = ship.ship_key
		var up_w: Vector3 = (gb * YAW.up_axis(sid)).normalized()
		var du := up_w.dot(Vector3.UP)
		total += 1
		# 屏幕量：舰尾→舰艏 的方向（把 bow 投到屏幕）
		var cam := _find_camera()
		var scr := ""
		if cam != null:
			var bow_w: Vector3 = (gb * YAW.bow_axis(sid)).normalized()
			var p0 := cam.unproject_position(mesh_n.global_position)
			var p1 := cam.unproject_position(mesh_n.global_position + bow_w * 200.0)
			scr = "(%+.0f,%+.0f)" % [p1.x - p0.x, p1.y - p0.y]
		var verdict := "背朝天 ✔" if du > 0.5 else ("**肚皮朝天** ✗" if du < -0.5 else "侧躺 ✗")
		if du < 0.5:
			updown += 1
		print("  %-12s | (%+.2f,%+.2f,%+.2f) | %+.3f | %-18s | %s"
				% [String(sid), up_w.x, up_w.y, up_w.z, du, scr, verdict])
	print("")
	print("  ── 我方 %d 艘：肚皮朝天/侧躺 %d 艘 ──" % [total, updown])
	if updown == 0:
		print("★★★ 船背全部朝天 ★★★")
	else:
		print("✗✗✗ 有 %d 艘船背没朝天 ⇒ 需要一层全局翻转修复 ✗✗✗" % updown)
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


func _find_camera() -> Camera3D:
	var stack: Array[Node] = [_battle]
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		if n is Camera3D and (n as Camera3D).current:
			return n
		for c in n.get_children():
			stack.append(c)
	return null
