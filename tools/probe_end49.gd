extends Node
## 49 轮 · **终局归因**：走**完整生产 setup**（`_build_hull_model`），
## 量与工具轴杆**同口径**的那根几何轴。
##
## ═══ 为什么必须走完整 setup ═══
##  `model.basis = zero_pose_basis(...)` **只是第一步**；
##  真正的朝向是 `sync_from_body()` 里 `look_at` 那一步（用烘焙好的 `C`）。
##  `probe_min49` 只做第一步 ⇒ 量到的是"还没对准"的中间态（所以看着 90° 歪）。
##  ⇒ 本探针复刻 `probe_bow_align` 的路：new() → set ship → _build_hull_model
##     → sync_from_body 收敛 → **再读网格节点的 world basis**。
##
## ═══ 判据（对用户唯一有意义的那条）═══
##  「用户在工具里看到轴杆指哪」必须 == 「实机里几何体对应部位朝哪」。
##  工具轴杆现在摆 = `零姿态下该轴的世界方向`（因为工具里的船就是零姿态）。
##  实机零姿态下该轴的世界方向 = `zp · (网格局部轴)`，而网格局部轴 = `bow_axis`。
##  ⚠️ 所以两边**本来就该相等**，且 `zp` 里已含 `mesh_rot` ——
##     `probe_min49` 的 90° 落差是它自己**多乘了一次**造成的假警报。
##  本探针改用**引擎连乘**读网格世界基，与 `zero_pose_basis` 对拍。

const IDX := preload("res://scripts/data/eve_ship_asset_index.gd")
const YAW := preload("res://scripts/data/eve_ship_yaw.gd")
const VIS := preload("res://scripts/visual/eve_ship_visual.gd")

var _L: Array[String] = []


func _ready() -> void:
	VIS.mesh_rot_of(&"abaddon")
	_L.append("═══ 49 轮终局归因：完整 setup 后量「工具轴 vs 实机几何轴」═══")
	_L.append("")
	_L.append("  %-11s %-20s %-20s %-8s %s" % [
		"id", "工具轴杆(世界)", "实机几何轴(世界)", "落差°", "结论"])
	var bad := 0
	var worst := 0.0
	var worst_id := ""
	var rows := IDX.all()
	rows.sort_custom(func(a, b): return String(a.id) < String(b.id))
	for s in rows:
		var sid := StringName(s.id)
		# ── 工具侧：工具里船=零姿态 ⇒ 轴杆方向 = zp·语义轴 ──
		var zp: Basis = VIS.zero_pose_basis(sid)
		var tool_dir := (zp * YAW.bow_axis(sid)).normalized()
		# ── 实机侧：走完整 setup ──
		var vis: Variant = VIS.new()
		var sh := EveShip.new()
		sh.ship_key = sid
		vis.set("ship", sh)
		var hr := Node3D.new()
		hr.name = "Hull"
		vis.set("hull_root", hr)
		vis.add_child(hr)
		var model := EveShipModel.instantiate(sid)
		if model == null:
			vis.free(); continue
		vis.call("_build_hull_model", model)
		add_child(vis)
		# 跑几帧让 sync_from_body 把朝向收敛到静止姿态
		await get_tree().process_frame
		var mesh := _first_mesh(vis)
		if mesh == null:
			vis.queue_free(); await get_tree().process_frame; continue
		# ⚠️ 用**引擎连乘**读世界基，不自己写乘号（红线 40）
		var gb := mesh.global_transform.basis.orthonormalized()
		# 几何体"舰艏"局部轴：从 model 层的 basis 反解出该船语义轴在网格空间的表示
		var game_dir := (gb * YAW.bow_axis(sid)).normalized()
		var deg := rad_to_deg(acos(clampf(tool_dir.dot(game_dir), -1.0, 1.0)))
		var ok := deg <= 0.5
		if not ok:
			bad += 1
			if deg > worst:
				worst = deg; worst_id = String(sid)
		_L.append("  %-11s (%+.2f,%+.2f,%+.2f)   (%+.2f,%+.2f,%+.2f)   %8.2f  %s" % [
			String(sid), tool_dir.x, tool_dir.y, tool_dir.z,
			game_dir.x, game_dir.y, game_dir.z, deg, "一致" if ok else "★不一致"])
		vis.queue_free()
		await get_tree().process_frame
	_L.append("")
	_L.append("  ⇒ 不一致 %d / %d · 最大 %.2f°（%s）" % [
		bad, rows.size(), worst, worst_id if worst_id != "" else "无"])
	_write()
	get_tree().quit(0)


func _first_mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n
	for c in n.get_children():
		var r := _first_mesh(c)
		if r != null:
			return r
	return null


func _write() -> void:
	for l in _L:
		print(l)
