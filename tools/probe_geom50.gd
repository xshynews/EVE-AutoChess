extends Node
## ══════════════════════════════════════════════════════════════════════
##  50 轮 · **不依赖任何语义轴**的最终判据（红线 40 终极形态）
## ══════════════════════════════════════════════════════════════════════
##
## ⛔ **结论部分已证伪 —— 读数仍可用，判据不可用**（2026-09-27 第 50 轮末）
##   本探针「不碰表」这一点是**对的**（红线 50a 输入侧污染的正解方向），
##   但它输出的「长轴 = 舰艏轴」**是错的** —— AABB 最长边对「扁平宽板 / 四翼展开」
##   船取到的是**翼展 / 板长**（kestrel 长宽比仅 1.27）。
##   ⇒ **尺寸读数（三边长 / 长宽比）可靠**，`长轴方向` 字段**只对细长机身船可靠**。
##   据此改的表已全部回滚。详见 `03_3D模型朝向标定.md §16`（红线 50b / 50c）。
##
## ── 为什么必须再开一条 ──────────────────────────────────────────────
##  前三层口径（复刻算式 / 静态零姿态 / 语义轴世界基）**全都依赖
##  `SHIP_AXES` 或 `AXIS_REMAP`** —— 表和约定一旦错，三层一起错、且互相印证。
##  用户实机说不对、机器说全绿 ⇒ 必须**完全不碰表**测一次。
##
## ── 本条做法：只看「几何体实际长什么样」──────────────────────────
##  ① 取网格的**顶点包围盒**（引擎给的 `get_aabb()`，经世界变换）
##     · 最长边 = 机身长轴方向（**朝向**：舰艏在长轴哪一端仍未知）
##     · 该方向水平投影应指向敌人（否则船"横着飞"）
##  ② 测**舰艏端**（长轴两端谁是舰艏）需要外观知识 —— 这条不做，
##     改由「船体上下不对称性」判断：
##     · 取网格世界 AABB 的 Y 尺寸中心，比较顶点分布的**质心偏移**
##       EVE 船体上部结构多（驾驶舱/炮塔）⇒ 质心在世界 Y 上**偏上**
##  ③ 最硬的一条：**把船渲染出来给人看**
##     · 用 SubViewport 从**正上方**（俯视，up = 世界 −Z）拍一张，
##       再沿世界 −Z（敌向）拍一张，导出 PNG
##     · 有了图，用户一眼就能判「舰艏朝哪、背朝哪」，不用信任何数字
##
## 跑法（要真相机 ⇒ 非 headless）：
##   `--path <工程> --quit-after 900 res://tools/probe_geom50.tscn`

const YAW := preload("res://scripts/data/eve_ship_yaw.gd")

const TEST_IDS: Array[String] = ["abaddon", "kestrel", "myrmidon", "slasher"]
const SHOT_DIR := "user://geom50"

var _battle: Node = null
var _arena: Node = null
var _frames := 0

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SHOT_DIR)
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
	for k in TEST_IDS:
		run.bench.append({"ship_key": StringName(k), "star": 1, "cell": Vector2i(-1, -1)})
		run.field.append(run.bench[run.bench.size() - 1].duplicate(true))
	run.changed.emit()
	_battle.call("_respawn_own_fleet")
	for _i in 5:
		await get_tree().process_frame
	_battle.call("start_battle")
	print("[50 轮·几何] 战斗已启动 · 口径 = AABB + 顶点质心（不碰任何语义轴表）")


func _process(_dt: float) -> void:
	_frames += 1
	if _frames != 600:
		return
	_report()
	await _shot()
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
	print("")
	print("═══ 50 轮·几何口径（第 %d 帧）═══" % _frames)
	print("")
	print("  ship     | 长轴方向(世界)          | 水平投影·敌向 | |Y分量| | 长轴/次轴/最短")
	print("  ---------|------------------------|--------------|--------|---------------")

	for v in ships_layer.get_children():
		if not v.has_method("sync_from_body"):
			continue
		var ship = v.get("ship")
		if ship == null or not ship.alive or ship.body == null or ship.team != 0:
			continue
		var model := _find_model(v)
		if model == null:
			continue
		var mesh_n := _mesh_node(model)
		if mesh_n == null:
			continue
		var mesh := mesh_n.mesh
		if mesh == null:
			continue

		# ★ 网格**局部** AABB → 用引擎的世界变换把三根轴送出去
		var aabb: AABB = mesh.get_aabb()
		var wb: Basis = mesh_n.global_transform.basis.orthonormalized()
		var sz: Vector3 = aabb.size
		# 找最长边对应的局部轴（0=X,1=Y,2=Z）
		var axes: Array[Vector3] = [Vector3.RIGHT, Vector3.UP, Vector3.BACK]
		var lens: Array[float] = [sz.x, sz.y, sz.z]
		var order := [0, 1, 2]
		order.sort_custom(func(a, b): return lens[a] > lens[b])
		var long_axis_local: Vector3 = axes[order[0]]
		var long_w: Vector3 = (wb * long_axis_local).normalized()

		# 敌向（真实最近敌舰）
		var enemy_dir := _nearest_enemy(ship)
		if enemy_dir == Vector3.ZERO:
			enemy_dir = Vector3(0.0, 0.0, -1.0)
		var horiz := Vector3(long_w.x, 0.0, long_w.z)
		var h_len := horiz.length()
		var d_h := (horiz / h_len).dot(enemy_dir) if h_len > 1e-6 else 0.0

		print("  %-8s | (%+.3f, %+.3f, %+.3f) | %+.4f       | %.3f  | %.1f/%.1f/%.1f"
				% [String(ship.ship_key), long_w.x, long_w.y, long_w.z, d_h,
				absf(long_w.y), lens[order[0]], lens[order[1]], lens[order[2]]])

	print("")
	print("  判据说明：")
	print("   · 「水平投影·敌向」= 长轴的水平投影与该船到敌舰方向的夹角余弦")
	print("     +1 = 机身指着敌人（✔）· 0 = 横着飞（✗ 45 轮那种病）")
	print("   · 「|Y分量|」= 长轴的俯仰程度，大 = 船头朝天/朝地")
	print("   · ⚠️ 长轴的**哪一端**是舰艏，本条测不出来（需要外观）⇒ 看图")


func _nearest_enemy(ship) -> Vector3:
	var ships_layer: Node = _arena.ships_layer
	var best := INF
	var best_dir := Vector3.ZERO
	for v in ships_layer.get_children():
		var o = v.get("ship")
		if o == null or not o.alive or o.body == null:
			continue
		if o.team == ship.team:
			continue
		var d: Vector3 = o.body.position - ship.body.position
		d.y = 0.0
		var l := d.length()
		if l > 1e-6 and l < best:
			best = l
			best_dir = d / l
	return best_dir


## 从**正上方**（俯视）拍一张 —— 判「舰艏朝哪、背朝哪」用。
func _shot() -> void:
	var cam := Camera3D.new()
	add_child(cam)
	var target := _ships_centroid()
	# 俯视：站在船上方，往 −Y 看，up 取世界 −Z（这样"屏幕上"= 敌人方向）
	cam.global_position = target + Vector3(0.0, 60.0, 0.0)
	cam.look_at(target, Vector3(0.0, 0.0, -1.0))
	cam.current = true
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	var path := SHOT_DIR + "/top50.png"
	img.save_png(path)
	print("  [图] 俯视图已存 %s（Path=%s）" % [path, ProjectSettings.globalize_path(path)])
	print("      ⚠️ 俯视时「屏幕上方 = 世界 −Z = 敌人方向」")
	cam.queue_free()


func _ships_centroid() -> Vector3:
	var acc := Vector3.ZERO
	var n := 0
	var ships_layer: Node = _arena.ships_layer
	for v in ships_layer.get_children():
		if not v.has_method("sync_from_body"):
			continue
		var s = v.get("ship")
		if s == null or not s.alive or s.body == null:
			continue
		acc += v.global_position
		n += 1
	return acc / float(maxi(1, n))
