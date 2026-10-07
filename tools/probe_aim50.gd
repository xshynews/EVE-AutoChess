extends Node
## ══════════════════════════════════════════════════════════════════════
##  50 轮 · **实机舰艏指向归因**（用户：「实机舰艏不朝向敌人」）
## ══════════════════════════════════════════════════════════════════════
##
## ⛔ **被输入侧污染 —— 读它的结论前先读这条**（2026-09-27 第 50 轮末）
##   本探针读的「舰艏轴」来自 `SHIP_AXES` / `AXIS_REMAP`，**与 `_bow_align` 共用同一张表**
##   ⇒ 表若错，它跟着错、还报 +1.0000（红线 50a 输入侧污染）。
##   本轮它确实读出 `bow·敌向 = +1.0000` 但实机不对 —— 这正是「全绿但实机乱」的样例。
##   另：它的 `up·天 ≥ 0.9` 判据也写错了（48 轮全局滚转后 up 语义落 −Y），报 8/8 假失败。
##   ⇒ **留档用**；要判「实机朝向」须改用**不引用任何表**的口径（几何 / 像素）。
##
## ── 为什么要新开（红线 40）──────────────────────────────────────────
##  已有探针 `probe_worldbow47` 报「bow·敌向 = 1.00000 全绿」，
##  `probe_screenbow47` 报「8/8 朝上」——**但用户实机看还是不对**。
##  ⇒ 矛盾 ⇒ **不许信任何一方，重新独立测**。
##
## ── 本条的做法：走**完整生产 setup**，读**引擎连乘的世界量** ────────
##  ① 读 `EveShipVisual.quaternion`（引擎里节点的实际旋转）
##  ② 读网格节点 `mesh.global_transform.basis`（**引擎连乘父子链**，我不写乘号）
##  ③ 同时测三个语义轴：bow（舰艏）· up（船背）· side（侧向）
##     —— 只看 bow 会被「船滚了但舰艏对」骗过（红线 31 的第⑤个自由度）。
##
## ── 判据（三条同时）────────────────────────────────────────────────
##  · bow · 敌向  ≥ 0.99    舰艏朝敌
##  · up  · (0,+1,0) ≥ 0.9  船背朝天（**48 轮的全库滚转**，不该被破坏）
##  · |side · 敌向| ≤ 0.15  侧向不朝敌（船体不侧躺）
##
## 跑法：
##   `--headless --path <工程> --quit-after 900 res://tools/probe_aim50.tscn`

const YAW := preload("res://scripts/data/eve_ship_yaw.gd")

## 覆盖 4 类 `mesh_rot`：R_y(180°) 主流 / R_x(90°) / 120° 斜轴 / 非 diag spec
const TEST_IDS: Array[String] = [
	"abaddon",   # 主流 R_y(180°) + spec +Z,-Y,+X
	"incursus",  # 主流
	"catalyst",  # R_x(90°) + spec +Z,+X,+Y
	"kestrel",   # R_x(90°) + spec -X,+Z,+Y
	"myrmidon",  # 120° 斜轴 + spec +Z,+Y,-X
	"tristan",   # 120° 斜轴 + spec -X,+Y,-Z
	"omen",      # 主流
	"slasher",   # R_x(90°) + spec -X,+Z,+Y
]

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
	for k in TEST_IDS:
		run.bench.append({"ship_key": StringName(k), "star": 1, "cell": Vector2i(-1, -1)})
		run.field.append(run.bench[run.bench.size() - 1].duplicate(true))
	run.changed.emit()
	_battle.call("_respawn_own_fleet")
	for _i in 5:
		await get_tree().process_frame
	_battle.call("start_battle")
	print("[50 轮] 战斗已启动 · 探针 = 完整生产 setup · 引擎世界量")


func _process(_dt: float) -> void:
	_frames += 1
	# 采样窗口取**稳态后**：aim_dir 是每 tick 刷的，slerp 收敛需要时间。
	# ⚠️ 47 轮那两条探针正是在**不同时刻**采样 ⇒ 结论互相矛盾。
	#    本条统一在 600 帧之后单点采样，且**同时打印两者**。
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
	print("")
	print("═══ 50 轮 · 实机舰艏指向归因（第 %d 帧）═══" % _frames)
	print("")
	print("  ship       | team | bow·敌向 | up·天  | |side·敌向| | 口径")
	print("  -----------|------|---------|--------|-----------|------")

	var n_own := 0
	var bad_bow: Array[String] = []
	var bad_up: Array[String] = []
	var bad_side: Array[String] = []

	for v in ships_layer.get_children():
		if not v.has_method("sync_from_body"):
			continue
		var ship = v.get("ship")
		if ship == null or not ship.alive or ship.body == null:
			continue
		var model := _find_model(v)
		if model == null:
			continue
		var mesh_n := _mesh_node(model)
		if mesh_n == null:
			continue

		# ★ 引擎连乘的世界基 —— 一个字都不手写
		var wb: Basis = mesh_n.global_transform.basis.orthonormalized()

		var key := String(ship.ship_key)
		var is_own: bool = ship.team == 0
		if is_own:
			n_own += 1

		# 语义轴（表是唯一真相源）
		var bow_l: Vector3 = YAW.bow_axis(ship.ship_key)
		var up_l: Vector3 = YAW.up_axis(ship.ship_key)
		var side_l: Vector3 = YAW.side_axis(ship.ship_key)

		var bow_w := (wb * bow_l).normalized()
		var up_w := (wb * up_l).normalized()
		var side_w := (wb * side_l).normalized()

		# 敌向：我方看 team1，敌方看 team0
		var enemy_dir := Vector3(0.0, 0.0, -1.0) if is_own else Vector3(0.0, 0.0, 1.0)
		# 更严谨：用**真实最近的敌舰位置**算，不用常量
		var nearest := _nearest_enemy(ship)
		if nearest != Vector3.ZERO:
			enemy_dir = nearest.normalized()

		var d_bow := bow_w.dot(enemy_dir)
		var d_up := up_w.dot(Vector3.UP)
		var d_side := absf(side_w.dot(enemy_dir))

		print("  %-10s | %d    | %+.4f | %+.4f | %.4f    | %s"
				% [key, ship.team, d_bow, d_up, d_side,
				"我方" if is_own else "敌方"])

		if is_own:
			if d_bow < 0.99:
				bad_bow.append("%s(%+.3f)" % [key, d_bow])
			if d_up < 0.9:
				bad_up.append("%s(%+.3f)" % [key, d_up])
			if d_side > 0.15:
				bad_side.append("%s(%.3f)" % [key, d_side])

	print("")
	print("── 我方 %d 艘 ──" % n_own)
	print("   舰艏不朝敌 %d 艘：%s" % [bad_bow.size(), ", ".join(bad_bow) if bad_bow.size() > 0 else "无"])
	print("   船背不朝天 %d 艘：%s" % [bad_up.size(), ", ".join(bad_up) if bad_up.size() > 0 else "无"])
	print("   侧向朝敌 %d 艘：%s" % [bad_side.size(), ", ".join(bad_side) if bad_side.size() > 0 else "无"])
	print("")
	if bad_bow.size() == 0 and bad_up.size() == 0 and bad_side.size() == 0:
		print("★★★ 50 轮口径全绿：舰艏朝敌 + 船背朝天 + 不侧躺 ★★★")
	else:
		print("✗✗✗ 50 轮口径发现问题 ⇒ 与 47 轮探针矛盾 ⇒ 采样时刻/口径差异 ✗✗✗")


## 用**真实敌舰位置**算敌向（不用世界常量）—— 避免「常量 vs 实际布局」错位。
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
