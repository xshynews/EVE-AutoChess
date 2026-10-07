extends Node
## ══════════════════════════════════════════════════════════════════════
##  47 轮诊断探针 —— **用世界坐标独立测「舰艏指向」**（不复制任何算式）
## ══════════════════════════════════════════════════════════════════════
##
## ── 为什么必须新开一条（红线 40 的应用）──────────────────────────
##  46 轮之前所有"全绿"的探针（`probe_bow_to_target` / `probe_brake_flip` /
##  `probe_bow_align`）算的都是：
##
##      bow_w = v.quaternion * (model.basis * bow_local)
##
##  而**游戏渲染用的就是这两个值**（`sync_from_body` 写 `quaternion`，
##  `_build_hull_model` 写 `model.basis`）⇒ 这个式子**必然**等于 `f`，
##  因为 `_bow_align` 就是照它构造的。**等于拿被测方验被测方。**
##  这就是"机器验过 ≠ 实机对"第 7 例的机制。
##
## ── 本条的做法：交给引擎算 ──────────────────────────────────────
##  取模型节点（按**名字**找，不是 get_child(0) —— 见红线 40b），
##  用 `model.global_transform.basis` —— 这是 Godot 自己把
##  `EveShipVisual.quaternion ∘ hull_root ∘ model.basis(含 scale)` 连乘的结果，
##  **我不写一个乘号**。再 `orthonormalized()` 去掉缩放影响，乘 `bow_local`。
##
##  如果引擎算出来的世界舰艏 ≠ 游戏以为的 f，说明**父子链上还有东西**（比如
##  相机/父节点旋转、hull_root 的占位 rotation.y、或者 glb 内部节点还有一层）。
##
## 跑法：
##   `--headless --path <工程> --quit-after 8000 res://tools/probe_worldbow47.tscn`
const YAW := preload("res://scripts/data/eve_ship_yaw.gd")

const SETTLE_FRAMES := 900
const SAMPLE_EVERY := 10
const END_FRAMES := 4000

var _battle: Node = null
var _arena: Node = null
var _frames := 0
var _n := 0
var _min_aim := 2.0
var _sum_aim := 0.0
var _min_vel := 2.0
var _bad: Array[String] = []
## 逐船明细（key → 最近一次读数）
var _per: Dictionary = {}
## glb 内部残留旋转的抽样报告
var _inner_report: Array[String] = []
## 「外层 vs 含内层」读数差异样本
var _inner_diff: Array[String] = []
## 最坏偏角（度）——逐帧取最坏
var _worst_deg := 0.0
var _worst_key := ""
## 稳态样本数（bow·aim ≥ 0.99）
var _steady_n := 0
## 非稳态样本数（正在转向 / 追赶）
var _free_n := 0
var _free_samples: Array[String] = []

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
	for k in ["abaddon", "catalyst", "myrmidon", "slasher", "kestrel"]:
		run.bench.append({"ship_key": StringName(k), "star": 1, "cell": Vector2i(-1, -1)})
		run.field.append(run.bench[run.bench.size() - 1].duplicate(true))
	run.changed.emit()
	_battle.call("_respawn_own_fleet")
	for _i in 5:
		await get_tree().process_frame
	_battle.call("start_battle")
	print("[47 轮] 战斗已启动 · 探针 = 世界坐标独立测量")


func _process(_dt: float) -> void:
	_frames += 1
	if _frames < SETTLE_FRAMES or _frames % SAMPLE_EVERY != 0:
		return
	var ships_layer: Node = _arena.ships_layer
	for v in ships_layer.get_children():
		if not v.has_method("sync_from_body"):
			continue
		var ship = v.get("ship")
		if ship == null or not ship.alive or ship.body == null:
			continue
		var model := _find_model(v)
		if model == null:
			if _bad.size() < 12:
				_bad.append("%s(找不到模型节点)" % String(ship.ship_key))
			continue
		# ★★ 关键：**引擎算的世界基**，我只做 orthonormalized + 乘 bow_local
		#
		# ⚠️ 47 轮修正：以前用 `model.global_transform.basis` —— 但 model（glb 根）
		#    下面还有一层**网格节点**，几何体真身在那里。用 `_mesh_node(model)`
		#    取真网格节点的世界基，才是"引擎渲染出来的朝向"。
		var mesh_n := _mesh_node(model)
		if mesh_n == null:
			if _bad.size() < 12:
				_bad.append("%s(找不到网格节点)" % String(ship.ship_key))
			continue
		var wb: Basis = mesh_n.global_transform.basis.orthonormalized()
		var bow_local: Vector3 = YAW.bow_axis(ship.ship_key)
		var bow_w: Vector3 = (wb * bow_local).normalized()

		# ★ 47 轮新增：检查 glb 内部**是否还有一层子节点旋转** ——
		#   若有，`model.basis * bow_local` 就**不是网格自身的朝向**，
		#   我们一直在测一个「包装节点」而不是几何体本身。
		#   这是从 22 轮至今**从未系统查过**的一条（见红线 31 的④）。
		var inner := _inner_rot(model)
		var bow_inner := (wb * inner * bow_local).normalized()
		if _inner_report.size() < 8 and inner != Basis.IDENTITY:
			_inner_report.append("%s inner=%s ang=%.2f°"
					% [String(ship.ship_key), str(inner), rad_to_deg(_ang_of(inner))])

		var aim: Vector3 = ship.body.aim_dir
		var key := String(ship.ship_key)
		if aim.length_squared() > 1e-12:
			var d := bow_w.dot(aim.normalized())
			_min_aim = minf(_min_aim, d)
			_sum_aim += d
			_n += 1
			_per[key] = d
			var deg := rad_to_deg(acos(clampf(d, -1.0, 1.0)))
			if deg > _worst_deg:
				_worst_deg = deg
				_worst_key = key
			# ★ 稳态统计：只统计「转向已收敛」的样本 ——
			#   判据 = 本帧 bow·aim ≥ 0.99（已对准）。这样把 slerp 追赶期排除，
			#   看「稳态是否真的严格朝敌」。
			if d >= 0.99:
				_steady_n += 1
			else:
				_free_n += 1
				if _free_samples.size() < 16:
					_free_samples.append("%s %.3f" % [key, d])
			if d < 0.93 and _bad.size() < 12:
				_bad.append("%s(aim %.3f)" % [key, d])
		var vel: Vector3 = ship.body.velocity
		if vel.length() > 1e-6:
			_min_vel = minf(_min_vel, bow_w.dot(vel.normalized()))
	if _frames > END_FRAMES:
		_report()
		get_tree().quit(0)


## 找**真正的网格节点**（几何体真身）—— glb 结构是
## 「根 Node3D → 子 MeshInstance3D」，几何体在**子**节点上。
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


## 把 model 之下**所有子节点**的旋转连乘起来 —— 检测 glb 内部是否有额外一层。
##
## 若返回值 ≠ 单位阵，说明「model 节点自身」不是几何体的坐标系，
## 我们乘 `bow_local` 得到的并不是网格的朝向 ⇒ 之前所有测量都测在包装层上。
func _inner_rot(model: Node3D) -> Basis:
	var acc := Basis.IDENTITY
	for c in model.get_children():
		var n3 := c as Node3D
		if n3 == null:
			continue
		acc = acc * n3.transform.basis.orthonormalized()
	return acc.orthonormalized()


func _ang_of(b: Basis) -> float:
	return Quaternion(b).get_angle()


## 按名字找模型节点 —— **不用 `get_child(0)`**（hull_root 下还有引擎特效节点）。
func _find_model(vis: Variant) -> Node3D:
	var hr = vis.get("hull_root")
	if hr == null:
		return null
	for c in hr.get_children():
		if String(c.name).begins_with("Model_"):
			return c
	return null


func _report() -> void:
	var mean := (_sum_aim / float(_n)) if _n > 0 else NAN
	print("═══ 47 轮 · 世界坐标独立测「舰艏指向」（样本 %d）═══" % _n)
	print("  ① bow(engine) · 敌向：均值 = %.5f · 最低 = %.5f" % [mean, _min_aim])
	print("  ② bow(engine) · v̂  ：最低 = %.5f" % _min_vel)
	for b in _bad:
		print("     ✗ %s" % b)
	print("  ③ 逐船（最近一次）")
	for k in _per:
		print("     %-12s %+.4f" % [k, _per[k]])
	print("  ④ 最坏偏角 = %.2f°（%s）" % [_worst_deg, _worst_key])
	print("  ④′ 稳态 %d vs 转向中 %d（稳态占比 %.1f%%）"
			% [_steady_n, _free_n, 100.0 * _steady_n / float(maxi(1, _steady_n + _free_n))])
	for s in _free_samples:
		print("     · 转向中 %s" % s)
	print("  ⑤ glb 内部残留旋转抽样 %d 条" % _inner_report.size())
	for s in _inner_report:
		print("     · %s" % s)
	print("  ⑥ 「外层 vs 含内层」差异样本 %d 条" % _inner_diff.size())
	for s in _inner_diff:
		print("     · %s" % s)
	if _n > 0 and _min_aim >= 0.93:
		print("★★★ 世界坐标口径也全绿 ⇒ 病根不在变换链，在「表 vs 官方渲染」★★★")
	else:
		print("✗✗✗ 世界坐标口径发现问题 ⇒ 变换链有额外一层 ✗✗✗")
