extends Node

## 舰船资产对账 —— 52 艘逐条核对「立绘 / 模型 / typeID / 尺寸」是否同一艘船
##
## 跑法：
##   "C:/godot/Godot_v4.7.1-stable_win64_console.exe" --headless \
##     --path "F:/evezzq/eve自走棋918" --quit-after 900 \
##     res://tools/verify_ship_assets.tscn
##
## ── 为什么要有这个工具 ──────────────────────────────────────────
## 用户的原话：「别最后我点的惩罚者级的立绘，上去的是其他船就糟糕了」。
## 名字对不上人看得出来，但**文件名全对、内容装错船**是看不出来的。
## 所以这里做三层：
##   ① 静态层：索引条数 / id↔英文名互推 / 立绘与模型文件都存在且以 id 命名
##   ② 结构层：索引与权威数值表 **双向** 比对（表里多一艘船也会被抓）
##   ③ 内容层：把每个 .glb 真的载进引擎，量出包围盒，
##             与索引里记的**已排序尺寸三元组**比对 ——
##             尺寸不对 = 这个文件里装的是另一艘船，当场点名。
## 第③层才是真正的保险：它不信任任何文件名。

const TOL_RATIO := 0.03     ## 相对容差 3%
const TOL_ABS := 0.5        ## 绝对容差 0.5 m（索引里尺寸保留两位小数）

var _fail := 0


func _ready() -> void:
	print("═══ 舰船资产对账（立绘 ↔ 模型 ↔ typeID）═══")

	# ── ① 静态层
	var p1 := EveShipAssetIndex.audit()
	_report("① 静态层（条数 / 命名 / 文件存在）", p1)

	# ── ② 结构层：与权威数值表双向比对
	var p2 := EveShipAssetIndex.cross_check_with_table()
	_report("② 结构层（索引 ↔ EveShipTable 双向）", p2)

	# ── ③ 内容层：载入 GLB 量包围盒
	print("")
	print("③ 内容层（载入 GLB 实测包围盒 vs 期望尺寸）")
	var rows := EveShipAssetIndex.all()
	rows.sort_custom(func(a, b): return a.id < b.id)

	print("%-14s %-8s %-5s %-22s %-22s %s"
			% ["id", "typeID", "费用", "期望尺寸(排序)", "实测尺寸(排序)", "结果"])
	var n_ok := 0
	for a in rows:
		var line := "%-14s %-8d %-5d %-22s " % [a.id, a.typeid, a.cost,
				_fmt(a.dims)]
		var got := _measure(a.model)
		if got.size() != 3:
			print(line + "%-22s [失败] 无法载入/无网格" % "-")
			_fail += 1
			continue
		line += "%-22s " % _fmt(got)
		if _close(got, a.dims):
			print(line + "[OK]")
			n_ok += 1
		else:
			print(line + "[不符] !! 尺寸对不上 —— 这个文件里装的不是 %s" % a.id)
			_fail += 1

	# ── 立绘侧也无图集抽样，确认立绘真的能解码
	print("")
	var noart := 0
	for a in rows:
		if EveShipArt.portrait(a.id) == null:
			print("[立绘缺失] ", a.id)
			noart += 1
	if noart == 0:
		print("④ 立绘层：52 张全部可解码 [OK]")
	else:
		print("④ 立绘层：%d 张缺失 [失败]" % noart)
		_fail += noart

	print("")
	print("── 内容层 %d/%d 通过 ──" % [n_ok, rows.size()])

	# ── ⑤ 材质层：52 艘逐条确认材质被还原
	#    glb 里的材质是**退化**的（glTF 表达不了 Blender 的 ColorRamp 中间节点），
	#    实测引擎里拿到的是 `metallic = spec 原值`（0.345/0.682/0.780），
	#    正确值是 0/0.80/0.95。EveShipMaterial 负责换成 ship_hull.gdshader。
	#    这一层防的是「某艘船的 `_s` 没装进工程 → 它悄悄退回退化材质」——
	#    那种情况画面上只是"这艘船有点灰"，肉眼查不出是哪艘。
	print("")
	print("⑤ 材质层（逐艘换成 ship_hull.gdshader 且 albedo / spec 图非空）")
	EveShipMaterial.clear_cache()
	var bad_mat := PackedStringArray()
	var total_surf := 0
	var n_emis := 0
	for a in rows:
		if not ResourceLoader.exists(a.model):
			bad_mat.append("%s 模型文件不存在" % a.id)
			continue
		var ps2: PackedScene = load(a.model)
		if ps2 == null:
			bad_mat.append("%s 无法载入" % a.id)
			continue
		var root2: Node = ps2.instantiate()
		EveShipMaterial.apply(root2, a.id)
		var st := EveShipMaterial.last_stats
		total_surf += int(st.get("surfaces", 0))
		n_emis += int(st.get("has_emissive", 0))
		if not EveShipMaterial.is_upgraded(root2):
			bad_mat.append("%s 材质没换上（表面=%d 缺图跳过=%d 非BaseMaterial3D=%d）" % [
					a.id, int(st.get("surfaces", -1)),
					int(st.get("no_spec", -1)), int(st.get("not_base", -1))])
		else:
			for mi in _meshes(root2):
				var mesh: Mesh = mi.mesh
				if mesh == null:
					continue
				for i in mesh.get_surface_count():
					var sm := mi.get_active_material(i) as ShaderMaterial
					if sm == null:
						continue
					if sm.get_shader_parameter("spec_tex") == null \
							or sm.get_shader_parameter("albedo_tex") == null:
						bad_mat.append("%s 表面 %d 贴图缺失" % [a.id, i])
		root2.free()
	if bad_mat.is_empty():
		print("  52 艘 / %d 个表面全部换成还原材质，贴图齐全 [OK]" % total_surf)
		print("  其中 glb 自带自发光的船 = %d（当前应为 0：`_e` 还没进 glb）" % n_emis)
	else:
		print("  [%d 个问题]" % bad_mat.size())
		for p in bad_mat:
			print("   - ", p)
		_fail += bad_mat.size()

	print("")
	if _fail == 0:
		print("═══ 全部通过（失败项 0）═══")
	else:
		print("═══ 有 %d 项失败 ═══" % _fail)
	get_tree().quit()


func _report(title: String, problems: PackedStringArray) -> void:
	print("")
	if problems.is_empty():
		print(title + "  [OK]")
	else:
		print(title + "  [%d 个问题]" % problems.size())
		for p in problems:
			print("   - ", p)
		_fail += problems.size()


## 载入一个 .glb，返回**排序后**的包围盒尺寸三元组。
##
## 取排序后的三元组而不是原始 (x,y,z)：源的轴序经 Blender Z-up 与
## glTF Y-up 两次换轴后会变，但三个数的大小关系不变。比不变的量，
## 才不会被换轴 bug 骗过去（这个 pipeline 真踩过 —— 见 SKILL 铁律②）。
func _measure(path: String) -> PackedFloat32Array:
	if not ResourceLoader.exists(path):
		return PackedFloat32Array()
	var ps := load(path)
	if ps == null or not (ps is PackedScene):
		return PackedFloat32Array()
	# ⚠️ 必须显式标 Node —— PackedScene.instantiate() 的返回类型推不出来
	var root: Node = (ps as PackedScene).instantiate()
	if root == null:
		return PackedFloat32Array()
	add_child(root)          # 进树之后 global_transform 才可信
	var acc := AABB()
	var has := false
	for mi in _meshes(root):
		var a: AABB = mi.get_aabb()
		var xf: Transform3D = mi.global_transform
		for i in 8:
			var c := a.get_endpoint(i)
			var w := xf * c
			if not has:
				acc = AABB(w, Vector3.ZERO)
				has = true
			else:
				acc = acc.expand(w)
	root.queue_free()
	if not has:
		return PackedFloat32Array()
	var s: PackedFloat32Array = [acc.size.x, acc.size.y, acc.size.z]
	var arr := Array(s)
	arr.sort()
	return PackedFloat32Array(arr)


func _meshes(n: Node) -> Array:
	var out := []
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(_meshes(c))
	return out


func _close(got: PackedFloat32Array, want: PackedFloat32Array) -> bool:
	if got.size() != want.size():
		return false
	for i in got.size():
		var d: float = absf(got[i] - want[i])
		if d > TOL_ABS and d > TOL_RATIO * maxf(absf(want[i]), 1.0):
			return false
	return true


func _fmt(v: PackedFloat32Array) -> String:
	if v.size() != 3:
		return "-"
	return "%.1f × %.1f × %.1f" % [v[0], v[1], v[2]]
