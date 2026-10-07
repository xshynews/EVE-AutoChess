extends Node
## ⛔⛔ **【口径错 · 仅留档 · 不要当证据引用】** ⛔⛔
##  本探针 **结论错误**（报「52/52 差 90°/180°」= 假警报）。
##  真因：它自己把 `zp`（**已含 `mesh_rot`**）又乘了一次 `bow_axis` ⇒ 重复乘（红线 48a / 49b）。
##  ✅ 正确范本 = `tools/probe_end49.gd`（走**完整生产 setup**，
##     读 `mesh.global_transform.basis` 与 `zero_pose_basis·bow` 对拍，一个乘号都不手写）。
##  保留本文件只为留档「口径重复乘」这个坑的现场。
##
## 49 轮 · **「工具看到的 = 实机摆的」一致性验收**。
##
## ═══ 这条断言才是用户真正要的 ═══
##  用户原话：
##    「我那个工具是不是白花 token 来写了？我定了舰船的朝向，
##      那按照我定的再全部定其他地方的位置不就行了？怎么还能天天调」
##
##  ⇒ 唯一有意义的判据：**工具里轴杆指的世界方向 == 实机里模型的那个轴的世界方向**。
##    两者一致 ⇒ 用户在工具里"以眼为准"定的方向，到实机一定对。
##    两者不一致 ⇒ 用户永远调不好（因为看的不是一个东西）。
##
## ═══ 做法（完全走两边各自的真代码）═══
##   工具侧：`probe_bow_box._axis_dir_to_world()` —— 但那是工具内部函数，
##           本探针读**工具落盘的轴杆方向**更硬核：复刻工具的**入口链**
##          `EveShipVisual.zero_pose_basis()`（就是工具现在调的那个）。
##           ⚠️ 红线 40：工具与本探针**都调同一个生产函数** ⇒ 天然同源；
##             真正要防的是"工具体姿态"与"轴杆链"用了不同基（49 轮的坑）。
##
##   实机侧：`EveShipModel.instantiate()` → 取 **MeshInstance3D 的
##           `global_transform.basis`**（引擎连乘父子链，不自己写乘号，红线 40）
##           ⇒ 这是"用户实机看到的那条船"的真身。
##
##   判据（逐艘 52）：
##     · `工具轴杆 · 实机模型对应轴` ≈ 1.000  ⇔ 两边指向同一个世界方向
##     · 逐轴报出偏差角，> 0.1° 即 FAIL 并点名
##
## 输出：`user://link49.txt`

const IDX := preload("res://scripts/data/eve_ship_asset_index.gd")
const YAW := preload("res://scripts/data/eve_ship_yaw.gd")
var SV: Variant = load("res://scripts/visual/eve_ship_visual.gd")

const TOL_DEG := 0.1

var _L: Array[String] = []


func _ready() -> void:
	SV.call("mesh_rot_of", &"abaddon")
	_L.append("═══ 49 轮 · 「工具轴杆 ↔ 实机模型轴」一致性验收 ═══")
	_L.append("")
	_L.append("  %-13s %-27s %-27s %8s  %s" % [
		"id", "工具轴杆方向(世界)", "实机模型轴方向(世界)", "偏差°", "结论"])
	var rows := IDX.all()
	rows.sort_custom(func(a, b): return String(a.id) < String(b.id))
	var bad := 0
	var worst := 0.0
	var worst_id := ""
	for s in rows:
		var sid := StringName(s.id)
		# ── 工具侧：工具现在用 `zero_pose_basis` 把「模型语义轴」送到世界 ──
		var zp: Basis = SV.call("zero_pose_basis", sid)
		# ── 实机侧：真造一个模型节点，读网格节点的 world basis ──
		var model := EveShipModel.instantiate(sid)
		if model == null:
			_L.append("  %-13s  —— 无模型" % String(sid))
			continue
		add_child(model)
		model.basis = zp                       # ← 与实机 `_build_hull_model` 同一句
		await get_tree().process_frame
		var mesh := _first_mesh(model)
		if mesh == null:
			_L.append("  %-13s  —— 无网格" % String(sid))
			model.queue_free(); continue
		# ⚠️⚠️ 口径（红线 48a，这里踩过）：
		#   `SHIP_AXES` 的轴是**网格空间**的轴，而 `zero_pose_basis()` **已经乘了**
		#   `mesh_rot`。所以实机几何体的世界朝向 = `mesh.global_transform.basis · 局部轴`，
		#   而 `local 轴` 就**是** `bow_axis()` —— **不能再乘一次 mesh_rot**，
		#   也不能拿 `zp · bow_axis` 去比（那是"经过 zp 的模型空间轴"，
		#   与几何体实际朝向差了 mesh_rot 那 90°/180°）。
		#   ⇒ 正确写法：**只经引擎连乘读网格的世界基**，再用它乘语义轴。
		var gb := mesh.global_transform.basis.orthonormalized()
		var game_bow := (gb * YAW.bow_axis(sid)).normalized()
		var tool_bow_world := (zp * YAW.bow_axis(sid)).normalized()
		var deg := rad_to_deg(acos(clampf(tool_bow_world.dot(game_bow), -1.0, 1.0)))
		var ok := deg <= TOL_DEG
		if not ok:
			bad += 1
			if deg > worst:
				worst = deg; worst_id = String(sid)
		_L.append("  %-13s (%+.2f,%+.2f,%+.2f)      (%+.2f,%+.2f,%+.2f)    %8.3f  %s" % [
			String(sid), tool_bow_world.x, tool_bow_world.y, tool_bow_world.z,
			game_bow.x, game_bow.y, game_bow.z, deg, "同向" if ok else "★不同向"])
		model.queue_free()
		await get_tree().process_frame
	_L.append("")
	_L.append("  ⇒ 不一致 %d / %d 艘 · 最大偏差 %.3f°（%s）" % [
		bad, rows.size(), worst, worst_id if worst_id != "" else "无"])
	_L.append("")
	_L.append("  ⚠️ 注意本条只证明「工具链 == 实机链」（同一个生产函数 ⇒ 必过）。")
	_L.append("     真正会翻车的是「**工具里那条船的姿态**」是否也 == 实机 ——")
	_L.append("     那由 `probe_bow_box._load_current()` 决定（49 轮已改成 zp）。")
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
	var f := FileAccess.open("user://link49.txt", FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(_L))
		f.close()
