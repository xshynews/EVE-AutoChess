extends Node
## ══════════════════════════════════════════════════════════════════════
##  52 轮 · **真实战斗里，舰艏到底朝哪**（用户实机问题的直接取证）
## ══════════════════════════════════════════════════════════════════════
##
## ── 用户诉求（52 轮原话）─────────────────────────────────────────
##   「标出来的 8 艘，全部和工具里不一样。为什么会出现我工具里定好了方向，
##     到了游戏实机里面还是会乱七八糟？说好了知道舰艏舰尾左右上下在哪很重要，
##     但还是一点也改不了，到底咋回事啊？」
##
## ── 本条要回答的三件事 ───────────────────────────────────────────
##   ① 真实战斗里，我方每艘船的**舰艏实际指向**（世界向量）
##   ② 它与该船**锁定的目标**方向的夹角（`sync_from_body` 的设计契约：应≈0）
##   ③ 它与**敌人方向（−Z）**的夹角（用户的期望：应≈0）
##   把 ② 和 ③ 分开报 —— 这是判「是姿态链问题还是索敌问题」的分水岭。
##
## ── ⚠️ 与 51 轮那版的区别（那次我错在拿 −Z 当靶子）──────────────
##   51 轮我用 `−Z` 当靶子，误报一片；因为 `sync_from_body` 的语义是
##   「舰艏 ≡ aim_dir（朝**目标**）」，不是「舰艏 ≡ −Z」。
##   本版**两个都报**，并且明确指出：**目标的选取在模拟层，不在姿态层**。
##
## 跑法（非 headless 才能截图；只看数也可 headless）
##   ... res://tools/probe_fight52.tscn
## 输出：`user://fight52/battle_top.png`（战场俯视 + 标注）

const YAW := preload("res://scripts/data/eve_ship_yaw.gd")

var _battle: Node = null
var _arena: Node = null

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute("user://fight52")
	print("[52·实机] 起真实战斗")
	var packed: PackedScene = load("res://scenes/battle_scene.tscn")
	_battle = packed.instantiate()
	add_child(_battle)
	for _i in 50:
		await get_tree().process_frame
	_arena = _battle.get("arena")
	var run: Node = _battle.get("run")
	run.coin = 999999
	run.roll_shop()
	for i in 5:
		run.buy(i)
	# 强制把我方 8 艘摆上场（覆盖几艘常见船）
	var want: Array[String] = ["abaddon", "kestrel", "algos", "catalyst",
			"myrmidon", "tristan", "slasher", "burst"]
	run.bench.clear()
	run.field.clear()
	for k in want:
		run.bench.append({"ship_key": StringName(k), "star": 1, "cell": Vector2i(-1, -1)})
		run.field.append(run.bench[run.bench.size() - 1].duplicate(true))
	run.changed.emit()
	_battle.call("_respawn_own_fleet")
	for _i in 10:
		await get_tree().process_frame
	_battle.call("start_battle")
	print("[52·实机] 战斗已启动，等 150 帧让它打起来")
	for _i in 150:
		await get_tree().process_frame

	_report()
	await _shot()
	get_tree().quit(0)


func _report() -> void:
	var ships_layer: Node = _arena.get("ships_layer")
	print("")
	print("═══ 真实战斗 · 我方舰船朝向实测（读引擎渲染的 mesh.global_transform）═══")
	print("船            舰艏→世界      与目标夹角   与敌向(−Z)夹角   目标数")
	print("------------------------------------------------------------------------")
	for v in ships_layer.get_children():
		if not v.has_method("sync_from_body"):
			continue
		var s = v.get("ship")
		if s == null or s.body == null or s.team != 0:
			continue
		var mn := _first_mesh(v)
		if mn == null:
			continue
		var gb := mn.global_transform.basis.orthonormalized()
		# 舰艏世界方向 = 该船表里 bow 轴经引擎变换后的方向
		var bow_local: Vector3 = YAW.bow_axis(s.ship_key)
		var bow_world := (gb * bow_local).normalized()
		var aim: Vector3 = s.body.aim_dir
		var a_aim := -1.0
		if aim.length_squared() > 1e-12:
			a_aim = rad_to_deg(bow_world.angle_to(aim.normalized()))
		var a_enemy := rad_to_deg(bow_world.angle_to(Vector3(0, 0, -1)))
		var nt: int = 0
		var tl = s.body.get("targets")
		if tl is Array:
			nt = (tl as Array).size()
		print("%-13s %-14s %-12s %-16s %d" % [
			String(s.ship_key), _fmt(bow_world),
			("%.1f°" % a_aim) if a_aim >= 0.0 else "无目标",
			"%.1f°" % a_enemy, nt])
	print("")


func _shot() -> void:
	# 战场俯视：相机在高处往下看，屏幕上 = −Z（敌向）
	var cam := Camera3D.new()
	add_child(cam)
	cam.fov = 55.0
	cam.global_position = Vector3(0, 120, 0.01)
	cam.look_at_from_position(Vector3(0, 120, 0.01), Vector3(0, 0, 0), Vector3(0, 0, -1))
	cam.current = true
	for _i in 5:
		await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png("user://fight52/battle_top.png")
	print("[52·实机] 俯视图 → %s" % ProjectSettings.globalize_path("user://fight52/battle_top.png"))
	cam.queue_free()


func _fmt(v: Vector3) -> String:
	return "(%.2f, %.2f, %.2f)" % [v.x, v.y, v.z]


func _first_mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n as MeshInstance3D
	for c in n.get_children():
		var got := _first_mesh(c)
		if got != null:
			return got
	return null
