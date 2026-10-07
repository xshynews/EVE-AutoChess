extends Node
## ══════════════════════════════════════════════════════════════════════
##  50 轮 · **表 vs 几何真相**逐艘对账（红线 40 的终极形态）
## ══════════════════════════════════════════════════════════════════════
##
## ⛔⛔ **判据已被证伪 —— 仅供留档，禁止用来判对错**（2026-09-27 第 50 轮末）
##   本探针的核心假设「`mesh.get_aabb()` 最长边 = 舰艏轴」**只在细长机身船上成立**。
##   对「扁平宽板 / 四翼展开」船，AABB 最长边是**翼展 / 板长**，不是舰艏轴：
##     · kestrel  AABB(99.7, 78.6, 25.0)  长宽比仅 **1.27**（四翼展开护卫舰）
##     · slasher  AABB(172.3, 81.6, 35.9) 长宽比 2.11（与 kestrel 同构）
##     · catalyst AABB(284.1, 88.6, 73.0) 长宽比 3.21（宽板）
##   本探针当时报「52 艘里 5 艘差 90°」，**据此改的 10 处表已全部回滚**，
##   `verify_run` 恢复 386/0。详见 `03_3D模型朝向标定.md §16`（红线 50b / 50c）。
##   ✅ 仍可参考的部分：它对「细长机身船」的英文报告是可靠的（47 艘）。
##
## ── 病象 ────────────────────────────────────────────────────────────
##  `probe_aim50`（读语义轴 `SHIP_AXES`）报「bow·敌向 = +1.0000 全绿」；
##  `probe_geom50`（读 AABB 最长边，**不碰表**）报「kestrel −0.775 / slasher −0.004」
##  ⇒ **两者矛盾** ⇒ 至少有一方在说谎。
##
## ── 本条要回答的唯一问题 ────────────────────────────────────────────
##  「表里声明的 `bow` 轴，在几何体上**真的是机身长轴**吗？」
##
##  做法：对每艘船
##    ① `geo_long_world` = 网格 AABB 最长边经**引擎世界变换**后的方向（纯几何）
##    ② `bow_world`      = `SHIP_AXES` 声明的 bow，经**同一世界变换**（表口径）
##    ③ 夹角 = `|geo_long_world · bow_world|`
##       ≈ 1 ⇒ 表说的 bow 就是长轴（✔ 自洽）
##       ≈ 0 ⇒ **表把横向/竖向轴错标成了舰艏**（✗ 表错）
##
##  ⚠️ 为什么用 `|·|`：本条只判「是不是长轴」，不判「哪一端是舰艏」
##     （后者需要外观知识，见 `probe_geom50` 的俯视图）。
##
## 跑法：`--headless --path <工程> --quit-after 900 res://tools/probe_tabgeom50.tscn`

const YAW := preload("res://scripts/data/eve_ship_yaw.gd")
const VIS: Variant = null   # 占位，见 _ready 里 load（const 不能 load）

var _battle: Node = null
var _arena: Node = null
var _frames := 0

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
	# 全库 52 艘一次性上阵（分两批，避免场上过挤）
	var ids: Array = YAW.all_ship_ids()
	if ids.size() == 0:
		push_error("拿不到全库 id 列表")
		get_tree().quit(1)
		return
	for k in ids:
		run.bench.append({"ship_key": StringName(k), "star": 1, "cell": Vector2i(-1, -1)})
		run.field.append(run.bench[run.bench.size() - 1].duplicate(true))
	run.changed.emit()
	_battle.call("_respawn_own_fleet")
	for _i in 5:
		await get_tree().process_frame
	_battle.call("start_battle")
	print("[50 轮·表↔几何] 全库 %d 艘上阵" % ids.size())


func _process(_dt: float) -> void:
	_frames += 1
	if _frames != 600:
		return
	_report()
	get_tree().quit(0)


func _find_model(vis: Variant) -> Node3D:
	var hr = vis.get("hull_root")
	if hr == null:
		return null
	for c in hr.get_children():
		if String(c.name).begins_with("Model_"):
			return c
	return null


func _mesh_node(model: Node3D) -> MeshInstance3D:
	if model is MeshInstance3D:
		return model
	for c in model.get_children():
		if c is MeshInstance3D:
			return c
		for g in c.get_children():
			if g is MeshInstance3D:
				return g
	return null


func _report() -> void:
	var ships_layer: Node = _arena.ships_layer
	var rows: Array[String] = []
	var n_bad := 0

	for v in ships_layer.get_children():
		if not v.has_method("sync_from_body"):
			continue
		var ship = v.get("ship")
		if ship == null or ship.body == null or ship.team != 0:
			continue
		var model := _find_model(v)
		if model == null:
			continue
		var mesh_n := _mesh_node(model)
		if mesh_n == null or mesh_n.mesh == null:
			continue

		var key := String(ship.ship_key)
		var wb: Basis = mesh_n.global_transform.basis.orthonormalized()

		# ① 纯几何长轴（网格 AABB 最长边，经**引擎世界变换**）
		var aabb: AABB = mesh_n.mesh.get_aabb()
		var axes: Array[Vector3] = [Vector3.RIGHT, Vector3.UP, Vector3.BACK]
		var lens: Array[float] = [aabb.size.x, aabb.size.y, aabb.size.z]
		var order := [0, 1, 2]
		order.sort_custom(func(a, b): return lens[a] > lens[b])
		var geo_long: Vector3 = (wb * axes[order[0]]).normalized()

		# ② 表声明的 bow（同一世界变换）
		var bow_l: Vector3 = YAW.bow_axis(ship.ship_key)
		var bow_w: Vector3 = (wb * bow_l).normalized()

		# ③ 夹角（用 |·| 只判"是不是长轴"）
		var cos_al: float = absf(geo_long.dot(bow_w))
		var deg := rad_to_deg(acos(clampf(cos_al, -1.0, 1.0)))
		var ok := deg <= 20.0   # 容差 20°（AABB 对斜轴船有量化误差）
		if not ok:
			n_bad += 1
		var spec := String(YAW.ship_axes_text(ship.ship_key))

		rows.append("  %-11s %-16s geo·表=%+.3f(%5.1f°) %s | geo=(%+.2f,%+.2f,%+.2f) bow=(%+.2f,%+.2f,%+.2f)"
				% [key, spec, cos_al, deg, "✔" if ok else "✗ 表错",
				geo_long.x, geo_long.y, geo_long.z, bow_w.x, bow_w.y, bow_w.z])

	rows.sort()
	print("")
	print("═══ 50 轮·表↔几何 逐艘对账（第 %d 帧）═══" % _frames)
	print("  判据：|几何长轴 · 表 bow| ≥ 0.94（≤20°）⇒ 表说的 bow 确实是机身长轴")
	print("")
	for r in rows:
		print(r)
	print("")
	print("── 共 %d 艘 · 表与几何对不上 %d 艘 ──" % [rows.size(), n_bad])
	if n_bad == 0:
		print("★★★ 全库自洽：`SHIP_AXES` 声明的 bow 都是真实机身长轴 ★★★")
	else:
		print("✗✗✗ 有 %d 艘的表中 bow **不是**机身长轴 ⇒ 这才是「舰艏不朝敌」的真根因 ✗✗✗" % n_bad)
