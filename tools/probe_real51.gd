extends Node3D
## ══════════════════════════════════════════════════════════════════════
##  51 轮 · **实机姿态实测（走生产 setup，零战斗零随机）**
## ══════════════════════════════════════════════════════════════════════
##
## ── 用途：回答用户 51 轮的诉求 ────────────────────────────────────
##   「我用工具定下舰船应该有朝向，然后你进游戏看建模，一个一个翻转建模，
##     直到翻转来和工具定下的一样了……如果出现参照系的数据不一样，那就记下不一样。」
##   ⇒ 本条 = 「**记下不一样**」的机器版：逐艘问
##      「实机里，**模型的哪根轴**被送到了「该朝的方向」上？」
##      再与 `SHIP_AXES` 的 `bow` 逐艘比对。
##
## ── 为什么走生产 setup（红线 40 的铁律）─────────────────────────
##   前两版我都**自己搭挂载链**，两次都错：
##     · 第一版：既写 `model.basis = zero_pose_basis`，又在 `root` 套 `looking_at·C` ⇒ 重复
##     · 第二版：跑真实战斗读 `aim_dir`，但分批 `_stage` 后战斗状态脏了 ⇒ 大量"无目标"
##   ⇒ 本版：**实例化 `EveShipVisual` 本体，调它自己的 `setup()`**
##     （生产入口），再喂一个已知 `aim_dir` 调它自己的 `sync_from_body()`。
##     全程零复刻，读的还是**引擎实际渲染出来的** `mesh.global_transform`。
##
## ── 判据（唯一）────────────────────────────────────────────────
##   设 `A` = 我喂进去的 `aim_dir`。读 `mesh.global_transform.basis`，
##   问「模型的哪根轴（±X/±Y/±Z）经它最贴近 `A`」。
##   这根轴 **就是实机里承担"舰艏"语义的那根模型轴**，
##   必须 `== SHIP_AXES.bow`。
##   ⚠️ 期望值用的是 `A`（我独立喂的输入），**不是从表反推**（红线 40：期望值独立）。
##
## 跑法（headless 即可）：
##   ... res://tools/probe_real51.tscn [-- --ids=a,b] [-- --aim=x,y,z]
##   不给 --ids = 全库 52 艘。默认 aim = (0,0,-1)（朝敌，红线 42）。

const YAW := preload("res://scripts/data/eve_ship_yaw.gd")
const VISUAL := preload("res://scripts/visual/eve_ship_visual.gd")
const SHIP := preload("res://scripts/core/eve_ship.gd")
const MOTION := preload("res://scripts/core/eve_destiny_motion.gd")
const ASSET := preload("res://scripts/data/eve_ship_asset_index.gd")

func _ready() -> void:
	var ids := _parse_ids()
	var aim := _parse_aim()
	print("[51·实机实测] 共 %d 艘 · aim=%s（走生产 setup，零复刻）" % [ids.size(), str(aim)])
	print("id           实机bow(引擎)   SHIP_AXES    一致?     mesh_rot    实机up(引擎)")
	print("------------------------------------------------------------------------")
	var bad: Array = []
	for id in ids:
		var sid := StringName(id)
		var got: String = await _real_bow(sid, aim)
		var dec: String = _fmt(YAW.bow_axis(sid))
		var got_up: String = await _real_up(sid, aim)
		var ok: bool = (got == dec)
		if not ok:
			bad.append([id, got, dec])
		print("%-12s %-14s %-12s %-8s %-11s %s" % [id, got, dec, "✔" if ok else "✘", _fmt_rot(sid), got_up])
	print("")
	print("═══ 合计 %d 艘 · 不一致 %d 艘 ═══" % [ids.size(), bad.size()])
	for b in bad:
		print("   ✘ %-12s 实机 bow=%s   表 bow=%s" % [b[0], b[1], b[2]])
	get_tree().quit(0)


func _parse_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--ids="):
			for s in a.substr(6).split(",", false):
				out.append(s.strip_edges())
	if out.is_empty():
		for s in ASSET.all():
			out.append(String(s.id))
	return out


func _parse_aim() -> Vector3:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--aim="):
			var p := a.substr(6).split(",", false)
			if p.size() == 3:
				return Vector3(float(p[0]), float(p[1]), float(p[2])).normalized()
	return Vector3(0, 0, -1)


## ★ 核心：走**生产** `setup()` + `sync_from_body()`，读引擎渲染结果。
func _real_bow(sid: StringName, aim: Vector3) -> String:
	var ship: Variant = SHIP.new()
	ship.ship_key = sid
	ship.team = 0
	ship.body = MOTION.Body.new()

	var vis: Variant = VISUAL.new()
	add_child(vis)
	# ★ 生产入口：setup() 内部会 _build_hull() → _build_hull_model() → _capture_bow_axes()
	vis.call("setup", ship)

	# 喂已知 aim，走生产 sync_from_body（完整旋转对齐 + 角速度闸门）
	#   ⚠️ 多推几帧让 slerp 收敛（FACING_LERP = 0.12 ⇒ 约 40 帧后收敛到 1e-4）
	ship.body.aim_dir = aim
	ship.body.velocity = Vector3.ZERO
	for _i in 60:
		vis.call("sync_from_body", ship.body, true, 1.0 / 60.0)
		await get_tree().process_frame

	# 读**引擎渲染出来的** mesh 世界旋转
	var mn := _first_mesh(vis)
	var out := "无mesh"
	if mn != null:
		var gb := mn.global_transform.basis.orthonormalized()
		out = _which_axis_to(gb, aim)
	vis.queue_free()
	return out


## 同法读「船背轴落到哪」—— 用来判断 up 是否也跟着偏（区分"绕长轴滚"与"整船转向"）
func _real_up(sid: StringName, aim: Vector3) -> String:
	var ship: Variant = SHIP.new()
	ship.ship_key = sid
	ship.team = 0
	ship.body = MOTION.Body.new()
	var vis: Variant = VISUAL.new()
	add_child(vis)
	vis.call("setup", ship)
	ship.body.aim_dir = aim
	ship.body.velocity = Vector3.ZERO
	for _i in 60:
		vis.call("sync_from_body", ship.body, true, 1.0 / 60.0)
		await get_tree().process_frame
	var mn := _first_mesh(vis)
	var out := "无mesh"
	if mn != null:
		var gb := mn.global_transform.basis.orthonormalized()
		out = _which_axis_to(gb, Vector3.UP)   # 船背应朝天（+Y）
	vis.queue_free()
	return out


func _which_axis_to(gb: Basis, target: Vector3) -> String:
	var names := ["+X", "-X", "+Y", "-Y", "+Z", "-Z"]
	var vecs := [Vector3(1,0,0), Vector3(-1,0,0), Vector3(0,1,0), Vector3(0,-1,0), Vector3(0,0,1), Vector3(0,0,-1)]
	var best := 0
	var bv := -2.0
	for i in vecs.size():
		var w: Vector3 = (gb * vecs[i]).normalized()
		var d := w.dot(target)
		if d > bv:
			bv = d
			best = i
	return names[best]


func _fmt(v: Vector3) -> String:
	var names := ["+X", "-X", "+Y", "-Y", "+Z", "-Z"]
	var vecs := [Vector3(1,0,0), Vector3(-1,0,0), Vector3(0,1,0), Vector3(0,-1,0), Vector3(0,0,1), Vector3(0,0,-1)]
	var best := 0
	var bv := -2.0
	for i in vecs.size():
		var d := v.normalized().dot(vecs[i])
		if d > bv:
			bv = d
			best = i
	return names[best]


func _fmt_rot(sid: StringName) -> String:
	var b: Basis = VISUAL.mesh_rot_of(sid)
	return "%.0f°" % rad_to_deg(Basis.IDENTITY.get_rotation_quaternion().angle_to(b.get_rotation_quaternion()))


func _first_mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n as MeshInstance3D
	for c in n.get_children():
		var got := _first_mesh(c)
		if got != null:
			return got
	return null
