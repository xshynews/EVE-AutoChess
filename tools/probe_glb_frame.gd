extends Node

## glb 导入后的**节点树与变换**取证 —— 回答一个必须先钉死的问题：
##
##     `EveShipModel.instantiate(id)` 返回的那个 Node3D，
##     它自己身上有没有变换？网格挂在它自己身上，还是挂在子节点上？
##
## ══════════════════════════════════════════════════════════════
##  为什么必须先问这个
## ══════════════════════════════════════════════════════════════
##  `eve_ship_visual._build_hull_model()` 里写的是：
##
##      model.basis = Basis.from_euler(Vector3(0, yaw, 0)) * M
##
##  `basis =` 是**整体赋值**。于是「glb 自带的那个根节点旋转」会不会被这一句
##  **覆盖掉**，完全取决于它落在树的哪一层：
##
##    · 若网格/旋转就在 `model` 自己身上  ⇒ 自带旋转被**丢弃**
##          ⇒ 最终朝向 = R_y(yaw)·M · v（v = mesh 原始顶点）
##    · 若 `model` 是 identity 的包壳、glb 节点是它的子节点 ⇒ 自带旋转**保留**
##          ⇒ 最终朝向 = R_y(yaw)·M · T_node · v
##
##  这两个算式差一个 T_node（实测 rifter 的 T_node 就是绕 Y −90°），
##  **差 90° 而且不会报任何错**。所以离线渲染（`front24.py` / `glb_tex.py`）
##  到底该不该把 glb 节点变换算进去，只能在这里读出来，不能推。
##
## 跑法（只读，可 headless）：
##   "C:/godot/Godot_v4.7.1-stable_win64_console.exe" --headless \
##     --path "F:/evezzq/eve自走棋918" --quit-after 4000 \
##     res://tools/probe_glb_frame.tscn

const IDS := ["rifter", "catalyst", "myrmidon", "kestrel", "tristan",
		"slasher", "condor", "raven", "punisher", "abaddon"]


func _ready() -> void:
	print("[FRM] ════ glb 导入后的节点树 ════")
	for id in IDS:
		var model := EveShipModel.instantiate(StringName(id), false)
		if model == null:
			print("[FRM] %-12s —— 无模型" % id)
			continue
		add_child(model)
		var lines: Array[String] = []
		_walk(model, 0, Transform3D(), lines)
		var t := model.transform
		print("[FRM] %-12s 根=%s(%s) 根有变换=%s" % [
			id, model.name, model.get_class(),
			"是" if t != Transform3D() else "否"])
		for l in lines:
			print("[FRM]    " + l)
		remove_child(model)
		model.queue_free()
	print("[FRM] ==== DONE ====")
	get_tree().quit()


func _walk(n: Node, depth: int, parent: Transform3D, out: Array[String]) -> void:
	var here := parent
	if n is Node3D:
		here = parent * (n as Node3D).transform
	var extra := ""
	if n is MeshInstance3D:
		var m: Mesh = (n as MeshInstance3D).mesh
		var sc := m.get_surface_count() if m != null else -1
		var nv := 0
		if m != null:
			for si in sc:
				var a := m.surface_get_arrays(si)
				if a.size() > Mesh.ARRAY_VERTEX:
					nv += (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		extra = "  mesh=%s surf=%d verts=%d" % [m.resource_name if m else "?", sc, nv]
	if n is Node3D:
		var x := (n as Node3D).transform
		var e := x.basis.get_euler()
		extra += "  T=%s  R(deg)=%s  S=%s" % [
			_s(x.origin), _s(Vector3(rad_to_deg(e.x), rad_to_deg(e.y), rad_to_deg(e.z))),
			_s(x.basis.get_scale())]
	out.append("%s%s (%s)%s" % ["  ".repeat(depth), n.name, n.get_class(), extra])
	for c in n.get_children():
		_walk(c, depth + 1, here, out)


func _s(v: Vector3) -> String:
	return "(%.2f, %.2f, %.2f)" % [v.x, v.y, v.z]
