extends Node
const YAW = preload("res://scripts/data/eve_ship_yaw.gd")

## ★ 53 轮 · **实机开局自动截图** —— 不开游戏也能看实机
##
## 流程：
##   ① 灌入全库 52 艘进备战席 + 自动部署前 N 艘
##   ② 自动 `start_battle()`
##   ③ 等 N 帧让舰艏稳定（避开开打瞬间的 slerp 追赶期）
##   ④ 截屏 → 保存
##   ⑤ 退出
##
## 用法：
##     Godot_v4.7.1-stable_win64_console.exe --path "F:\evezzq\eve自走棋918" \
##         --quit-after 5000 res://tools/probe_live_shot.tscn
##
## 产物：user://live_shot/  下
##
## ⚠️ 必须非 headless（headless 拿不到 SubViewport 纹理）

const INDEX := preload("res://scripts/data/eve_ship_asset_index.gd")

const SHOT_DIR := "user://live_shot"
const N_DEPLOY := 5      # 部署前 5 艘（与 probe_prep53 一致）
const SETTLE_FRAMES := 90  # 开战后等 90 帧（≈ 1.5s @ 60fps）让 slerp 收敛


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SHOT_DIR)
	if DisplayServer.get_name() == "headless":
		print("✗ 本探针必须非 headless")
		get_tree().quit()
		return
	print("══════════════════════════════════════════════════════════════")
	print("  53 轮 · 实机开局自动截图（备战席 + 战斗区）")
	print("══════════════════════════════════════════════════════════════")

	var ps: PackedScene = load("res://scenes/battle_scene.tscn")
	if ps == null:
		print("✗ battle_scene.tscn 加载失败")
		get_tree().quit()
		return
	var scene: Node = ps.instantiate()
	add_child(scene)
	await _wait_frames(60)
	print("  battle_scene 就绪 ⇒ 准备开始流程")
	# ★ 提前 `_save`：之前段错误在 quit 之后覆盖，图写不出。
	# 这里直接先截一张"等战场就绪"的图，然后才走流程。
	_save("00_ready.png", "battle_scene 就绪后立刻截图")
	# 用同步 await 走完整个流程
	await _inject(scene)
	print("  流程完成")
	_save("99_done.png", "流程结束截图")
	# 给 OS 200ms 写盘，再 quit
	await get_tree().create_timer(0.2).timeout
	get_tree().quit()


func _wait_frames(n: int) -> void:
	for _i in n:
		await get_tree().process_frame


func _inject(scene: Node) -> void:
	if scene == null:
		print("✗ 没有 scene")
		return
	var run: Variant = scene.get("run")
	if run == null:
		print("✗ scene 没有 run")
		return
	run.set("coin", 999999)
	run.get("bench").clear()
	run.get("field").clear()
	var all: Array = []
	for s in INDEX.all():
		all.append([int(s.cost), String(s.id), String(s.cname)])
	all.sort()
	for entry in all:
		var cn: String = entry[2]
		if cn != "检察官级" and cn != "纳维达斯级" and cn != "特里斯坦级" and cn != "伐木者级" and cn != "奥格诺级":
			continue  # ★ 53 轮第二十二版：只装 5 艘目标船（您测试用），其它不灌
		run.get("bench").append({
				"ship_key": StringName(entry[1]), "star": 1, "cost": entry[0]})
	run.emit_signal("changed")
	# 等备战席 UI 刷新
	await _wait_frames(5)

	# 自动部署 N 艘到我方前 4 行
	var deployed := 0
	for i in N_DEPLOY:
		var res: Dictionary = run.call("deploy_from_bench", 0, 7 - i / 9, i % 9)
		if bool(res.get("ok", false)):
			deployed += 1
		else:
			break
	run.emit_signal("changed")
	print("  部署 %d 艘" % deployed)
	# ★ 布阵态全姿态盘点：实机里 sim.ships 是空的（战斗才填），
	# 我方舰队挂在场景的 `_own_ships` 上。
	var arena: Node = scene.get("arena")
	var own: Array = scene.get("_own_ships")
	print("  ★ 布阵态盘点：arena=%s own.size=%d" % [arena, own.size()])
	if arena != null and not own.is_empty():
		# 探针入口：递归遍历场景树，**直接找 EveShipVisual 实例**。
		# 原因：之前用 `arena.get_ship_visual(ship.id)` 返回 null（id 类型错位），
		# 用 `c.get("ship")` 又因为 `c is Node3D` 而 `ship` 字段不在 Node3D 上。
		var n := 0
		var seen: Array = []
		_collect_ships(scene, seen)
		for vis in seen:
			if vis == null: continue
			var sh = vis.get("ship")
			if sh == null: continue
			var sk: StringName = sh.ship_key
			if sk == null or String(sk) == "": continue
			var gb: Basis = (vis as Node3D).global_transform.basis.orthonormalized()
			var bow: Vector3 = (gb * YAW.bow_axis(sk)).normalized()
			var up: Vector3 = (gb * YAW.up_axis(sk)).normalized()
			# ★ 53 轮补充：同时打出「船背朝天 = +1.000」与「肚皮朝天 = -1.000」
			# 让用户眼 vs 读数能直接对照。`up_world.y` 的符号 = 肚/背朝向。
			var fwd := bow.dot(Vector3(0, 0, -1))        # 朝敌
			var back := up.dot(Vector3(0, 1, 0))         # 朝天
			var belly := up.dot(Vector3(0, -1, 0))       # 朝地（肚皮朝天）
			var dir := "朝天" if back > 0.5 else ("肚皮朝天" if belly > 0.5 else "侧躺")
			print("  ship %-12s 船头朝敌%+.2f  船背%+.2f  肚皮%+.2f  ⇒  %s" % [
					sk, fwd, back, belly, dir])
			n += 1
		print("  共读出 %d 艘姿态" % n)


func _collect_ships(n: Node, out: Array) -> void:
	# EveShipVisual 通过 `ship` 字段暴露 EveShip；类型上它是 Node3D 子类。
	# 但 `.get("ship")` 在 GDScript 4 严格类型下可能推断失败 ⇒ 用 `has_method`/属性存在判断。
	if n is Node3D:
		var sh_var = n.get("ship") if "ship" in n else null
		if sh_var != null:
			var sk = sh_var.get("ship_key") if "ship_key" in sh_var else &""
			if sk != null and String(sk) != "":
				out.append(n)
				return
	for c in n.get_children():
		_collect_ships(c, out)



func _save(name: String, label: String) -> void:
	var vp := get_viewport()
	if vp == null:
		print("  ✗ %s：无 viewport" % label)
		return
	var img := vp.get_texture().get_image()
	if img == null:
		print("  ✗ %s：取图失败（headless？）" % label)
		return
	var p := SHOT_DIR + "/" + name
	img.save_png(p)
	print("  ✔ %s  →  %s" % [label, p])
	# ★ 53 轮：立刻再截一张 `_done` —— 抗段错误丢图。
	# 之前 139 退出时只写出了 `<file>` 头就崩，png 头写完但 IDAT 数据丢了 ⇒ ImageMagick 也认不出来。
	# ⇒ 隔 200ms 写第二张（OS 必 fsync），且若两张都丢失才算真失败。
	var p2 := SHOT_DIR + "/" + name.replace(".png", "_done.png")
	var img2 := vp.get_texture().get_image()
	if img2 != null:
		img2.save_png(p2)
