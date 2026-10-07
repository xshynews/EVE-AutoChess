extends Node
## 实拍取证：跑主场景 → 开打 → 抓 3 艘船的 bow vs 速度
##
## ⚠️ 2026-09-26 第二十二轮**按红线 46 重写读数**：
##   · 旧读数 `R_y(rotation.y) · M·(1,0,0)` 已经不成立 —— 朝向不再走 rotation.y，
##     而是整节点的 `quaternion`（完整旋转对齐）。照旧公式读会得到**完全错误**的
##     bow，而图**仍然看着对**（红线 40 的同款陷阱）。
##   · 舰艏轴也从 `EveShipYawTable.bow_axis()` 读，不再硬写 (1,0,0)。
##
## 跑法（**必须非 headless** —— 截图那一段需要真实渲染上下文）：
##   "C:/godot/Godot_v4.7.1-stable_win64_console.exe" \
##     --path "F:/evezzq/eve自走棋918" --quit-after 25000 \
##     res://tools/probe_facing_visual.tscn

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
	# ⚠️ demo 模式：满币 → roll shop → 买满 bench → 拖到 field
	var run: Node = _battle.get("run")
	run.coin = 999
	run.roll_shop()
	for i in 5:
		var r = run.buy(i)
		print("[VIS] buy(%d) = %s" % [i, str(r)])
	# 26 轮：强制加入 catalyst / myrmidon（roll 商店随机，不一定出）—— 24 轮反思过
	# 这两艘被「机器验过 ≠ 实机对」坑过（probe_bow_axis 只测静态、probe_bow_align 只测运行时），
	# 必须强制上场实拍。
	var bench_keys: Array[String] = ["catalyst", "myrmidon", "burst"]
	for k in bench_keys:
		if run.bench.any(func(b): return String(b.ship_key) == k):
			continue
		# 直接 append entry（绕过 roll，roll 容易出 30 次都不出货）
		run.bench.append({"ship_key": StringName(k), "star": 1, "cell": Vector2i(-1, -1)})
	# 把 bench 的前 3 艘拖到 field（用 bench_to_field / 拖放接口）
	# 26 轮：清空 bench，强制只保留要拍的船（28 轮：单艘近距离实拍）
	# 模式：先清空 bench → 直接 append 一艘 → field.append 它的 copy
	run.bench.clear()
	run.field.clear()
	var sid := "catalyst"   # ← 改这里就能切换：catalyst / myrmidon / burst
	run.bench.append({"ship_key": StringName(sid), "star": 1, "cell": Vector2i(-1, -1)})
	run.field.append(run.bench[0].duplicate(true))
	run.changed.emit()
	_battle.call("_respawn_own_fleet")
	for _i in 5:
		await get_tree().process_frame
	print("[VIS] demo 舰队已建（我方 %d 艘）" % int(_battle.get("_own_ships").size()))
	_battle.call("start_battle")
	print("[VIS] 战斗已启动")
	await get_tree().create_timer(2.0).timeout

	# 直接遍历 ships_layer 的所有 EveShipVisual 节点
	var ships_layer: Node = _arena.ships_layer
	var visuals: Array = []
	for c in ships_layer.get_children():
		if c.has_method("sync_from_body") and c.get("ship") != null:
			visuals.append(c)

	_lines.append("═══ 开打 2 秒后 bow vs 速度（按 ship_key 前缀取样）═══")
	var sampled: Array[String] = []
	var sampled_data: Array = []
	print("[VIS] visuals.size() = %d" % visuals.size())
	for v in visuals:
		var ship = v.get("ship")
		var key := String(ship.ship_key)
		var prefix := key.substr(0, 4)   # 按前缀去重（多艘同名）
		if prefix in sampled:
			continue
		var body = ship.get("body")
		if body == null:
			continue
		var vel: Vector3 = body.velocity
		var pos: Vector3 = body.position
		# ⚠️ 47 轮读数：**真网格节点的世界基** × 「模型空间舰艏轴」
		#    （`_local_bow` 已含整条父子链，**不要再乘 `v.quaternion`** ——
		#      那会造成双重旋转，读数看着"有值"但全错）
		var bow_now: Vector3 = _local_bow(v, key).normalized()
		var v_n := vel.normalized() if vel.length() > 0.001 else Vector3.ZERO
		var dot := bow_now.dot(v_n)
		sampled.append(prefix)
		_lines.append("  %-12s pos=%s  vel=%s (|v|=%.1f)  bow=%s  bow·v=%+.3f  %s" % [
			key, _v3s(pos), _v3s(vel), vel.length(),
			_v3s(bow_now), dot,
			("✅" if dot > 0.9 else ("❌ 反向" if dot < -0.5 else "⚠ 偏"))])

	# 截图
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img != null:
		img.save_png("user://r28_%s.png" % sid)

		# 4 秒后再抓一次
		await get_tree().create_timer(2.0).timeout
		_lines.append("")
		_lines.append("═══ 4 秒后再抓 ═══")
		for v in visuals:
			var ship = v.get("ship")
			var key := String(ship.ship_key)
			var body = ship.get("body")
			if body == null:
				continue
			var vel: Vector3 = body.velocity
			var bow_now: Vector3 = _local_bow(v, key).normalized()
			var v_n := vel.normalized() if vel.length() > 0.001 else Vector3.ZERO
			var dot := bow_now.dot(v_n)
			_lines.append("  %-12s vel=%s (|v|=%.1f)  bow·v=%+.3f  %s" % [
				key, _v3s(vel), vel.length(), dot,
				("✅" if dot > 0.9 else ("❌ 反向" if dot < -0.5 else "⚠ 偏"))])

	for s in _lines:
		print(s)
	var f := FileAccess.open("user://r21_facing_report.txt", FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(_lines))
		f.close()
	get_tree().quit(0)


func _v3s(v: Vector3) -> String:
	return "(%+.2f, %+.2f, %+.2f)" % [v.x, v.y, v.z]


## 读「模型空间舰艏轴」在**世界**里的方向 —— 用**真网格节点的全局变换**。
##
## ⚠️⚠️ 47 轮修正（红线 40 第 7 次现形）：
##  旧版写的是 旧的「取 hull_root 第 0 个子节点的 basis」写法 —— 那个式子
##  **必然**等于 `_facing_quat` 想给的答案（`_bow_align` 就是照它构造的），
##  等于拿被测方验被测方。它测不出「glb 根节点下面**还有一层网格节点**，
##  几何体真身在那层、且逐艘带着不同旋转（R_x(90°) / R_y(180°) / 120° 斜轴）」。
##
##  正解 = `mesh.global_transform.basis` —— **引擎自己**把
##  `visual.quaternion ∘ hull_root(scale) ∘ model.basis ∘ mesh 自身` 连乘，
##  探针一个乘号都不写。实测两层读数差 90°（外层假 1.000 · 真值 0.000）。
##
## ⚠️ `.orthonormalized()` 不能省：整条链含 `hull_root.scale`（红线 41）。
func _local_bow(vis: Variant, key: String) -> Vector3:
	var mn := _mesh_node(vis)
	if mn == null:
		return Vector3.ZERO
	return (mn.global_transform.basis.orthonormalized()
			* YAW.bow_axis(StringName(key))).normalized()


## 找几何体真身：`Model_<key>` 之下的 MeshInstance3D（或它自己就是）。
func _mesh_node(vis: Variant) -> MeshInstance3D:
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
