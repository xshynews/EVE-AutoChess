extends Node
## ⛔⛔ **【口径错 · 仅留档 · 不要当证据引用】** ⛔⛔
##  本探针 **结论错误**（报 90°/180° 落差 = 假警报）。
##  真因同 `probe_link49`：重复乘 `mesh_rot`（`zp` 已含，红线 48a / 49b）。
##  ✅ 正确范本 = `tools/probe_end49.gd`。
##
## 49 轮 · **最小归因**：把「工具轴杆」与「实机几何体」放在同一句话里比对。
##
## 只做一件事：对每艘船打印 4 个数，让 90°/180° 的来源无处可藏。
##   ① `zp·bow_axis`            ← 工具轴杆现在摆的方向（工具改后）
##   ② `mesh_world · bow_axis`  ← 实机几何体真身（网格节点 world basis 乘语义轴）
##   ③ `mesh_world · X/Y/Z`     ← 实机几何体三根局部轴在世界里朝哪（对照用）
##   ④ `mesh_rot`               ← glb 内层网格自带旋转（红线 48）
##
## ⚠️ ② 与 ① 差多少 = 工具与实机的真实落差。
##    若为 0° ⇒ 工具里看到的就是实机；否则用户永远调不好。

const IDX := preload("res://scripts/data/eve_ship_asset_index.gd")
const YAW := preload("res://scripts/data/eve_ship_yaw.gd")
var SV: Variant = load("res://scripts/visual/eve_ship_visual.gd")

var _L: Array[String] = []


func _ready() -> void:
	SV.call("mesh_rot_of", &"abaddon")
	_L.append("═══ 49 轮最小归因 ═══")
	_L.append("")
	_L.append("  %-11s %-20s %-20s %-8s %s" % [
		"id", "①工具轴杆", "②实机几何体", "落差°", "④mesh_rot"])
	for sid_s in ["abaddon", "incursus", "catalyst", "kestrel", "slasher",
			"myrmidon", "tristan", "algos", "punisher", "vexor"]:
		var sid := StringName(sid_s)
		var zp: Basis = SV.call("zero_pose_basis", sid)
		var mr: Basis = SV.call("mesh_rot_of", sid)
		var tool_dir := (zp * YAW.bow_axis(sid)).normalized()
		var model := EveShipModel.instantiate(sid)
		if model == null:
			continue
		add_child(model)
		model.basis = zp
		await get_tree().process_frame
		var mesh := _first_mesh(model)
		if mesh == null:
			model.queue_free(); await get_tree().process_frame; continue
		var gb := mesh.global_transform.basis.orthonormalized()
		var game_dir := (gb * YAW.bow_axis(sid)).normalized()
		var deg := rad_to_deg(acos(clampf(tool_dir.dot(game_dir), -1.0, 1.0)))
		_L.append("  %-11s (%+.2f,%+.2f,%+.2f)   (%+.2f,%+.2f,%+.2f)   %8.2f  %s" % [
			sid_s, tool_dir.x, tool_dir.y, tool_dir.z,
			game_dir.x, game_dir.y, game_dir.z, deg, _k(mr)])
		model.queue_free()
		await get_tree().process_frame
	_L.append("")
	_L.append("  注：落差 = ①/② 的夹角。0° ⇒ 工具里看到的就是实机（用户可据此调）。")
	_write()
	get_tree().quit(0)


func _k(m: Basis) -> String:
	if m.is_equal_approx(Basis.IDENTITY):
		return "单位阵"
	if m.is_equal_approx(Basis.from_euler(Vector3(0, PI, 0))):
		return "R_y(180°)"
	if m.is_equal_approx(Basis.from_euler(Vector3(PI / 2, 0, 0))):
		return "R_x(+90°)"
	if m.is_equal_approx(Basis.from_euler(Vector3(-PI / 2, 0, 0))):
		return "R_x(−90°)"
	return "斜轴(det%.0f)" % m.determinant()


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
