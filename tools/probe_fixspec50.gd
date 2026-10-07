extends Node
## ══════════════════════════════════════════════════════════════════════
##  50 轮 · **反解正确 spec**（对 5 艘「表 bow 不在长轴上」的船）
## ══════════════════════════════════════════════════════════════════════
##
## ⛔⛔ **本探针双重作废 —— 仅供留档，禁止使用**（2026-09-27 第 50 轮末）
##   ① 前提错：它服务的那个判据「AABB 最长边 = 舰艏轴」**已被证伪**
##      （详见 `probe_tabgeom50.gd` 头部 / `03_3D模型朝向标定.md §16`，红线 50b）。
##   ② 算式错：它**手推**了「`M` 作用在长轴上」的链路，**漏了 `R_y` 与 `R_z(180°)`
##      两层**（38/48 轮才加进生产算式）⇒ 解出的 spec 落盘即崩（红线 40 / 49c 第三次翻车）。
##   ✅ **正确范式 = `probe_solve50.gd`**：直接用生产算式 `zp = M · mesh_rot`（yaw=0）
##      枚举求值，**不手推任何一层**。要反解 spec 请用它。
##
## ── 输入 ────────────────────────────────────────────────────────────
##  · `AXIS_REMAP[id]` 现状（要改的对象）
##  · `SHIP_AXES[id]` 现状（要改的对象）
##  · 几何真相：`EveShipModel` 加载原始 glb 后，读**网格节点**的
##    `transform.basis`（= `mesh_rot`）+ mesh 的 AABB 最长边（= 机身长轴在**网格空间**）
##
## ── 要解的方程 ──────────────────────────────────────────────────────
##  `zero_pose_basis(id) = R_z(180°) · R_y(yaw) · M · mesh_rot`
##   要求：`zero_pose · geo_long_mesh` 落在**世界水平面内**（y ≈ 0）
##        `zero_pose · bow_model`      = 世界 −Z（舰艏朝敌）
##
##  其中 `geo_long_mesh` = 机身长轴在**模型根空间**的方向
##                      = `mesh_rot · (AABB 最长边局部轴)`
##  ⇒ `M` 只需把 `geo_long_mesh` 送到 ±Z（世界水平面内），
##     再选对符号（哪端是舰艏 —— 本例 5 艘全部已由用户实机/工具定过，
##     见 `pose_table.json` 的 2023 旧裁决，**符号沿用用户既有值**）。
##
## ── 输出 ────────────────────────────────────────────────────────────
##  打印每艘船的：① 几何长轴（模型根空间）② 现状 spec 的诊断
##                ③ **候选 spec 列表**（枚举 6 个 ±轴 × 2 符号 = 24 个
##                   合法对角置换，筛出「长轴落 ±Z 且行列式 = +1」的全部解）
##  ⚠️ 本条只**列出候选**，不自动落盘 —— 最终由用户 6 宫格判「哪端是舰艏」。
##
## 跑法：`--headless --path <工程> --quit-after 200 res://tools/probe_fixspec50.tscn`

const YAW := preload("res://scripts/data/eve_ship_yaw.gd")
const MODEL := preload("res://scripts/visual/eve_ship_model.gd")

const TARGETS: Array[String] = ["algos", "catalyst", "kestrel", "slasher", "tristan"]

func _ready() -> void:
	print("")
	print("═══ 50 轮 · 反解正确 spec（5 艘「表 bow 不在机身长轴上」）═══")
	print("")

	for id in TARGETS:
		_analyze(StringName(id))

	get_tree().quit(0)


func _analyze(id: StringName) -> void:
	print("──────────────────────────────────────────────────────────────")
	print("■ %s" % String(id))

	var spec_now := ""
	# 直接从表读原文（AXIS_REMAP 无 text API 时用 ship_axes 报告的现状）
	print("   现状 SHIP_AXES = %s" % YAW.ship_axes_text(id))

	# ── 几何真相：网格节点的 basis（= mesh_rot）+ AABB 最长边 ────────────
	var inst := MODEL.instantiate(id, false)
	if inst == null:
		print("   ✗ 加载失败")
		return
	var mn := _first_mesh(inst)
	if mn == null:
		print("   ✗ 找不到网格节点")
		inst.free()
		return
	var mesh_rot: Basis = mn.transform.basis.orthonormalized()
	var mesh := mn.mesh
	var aabb: AABB = mesh.get_aabb()
	var axes: Array[Vector3] = [Vector3.RIGHT, Vector3.UP, Vector3.BACK]
	var lens: Array[float] = [aabb.size.x, aabb.size.y, aabb.size.z]
	var order := [0, 1, 2]
	order.sort_custom(func(a, b): return lens[a] > lens[b])

	print("   mesh_rot = %s" % str(mesh_rot))
	print("   AABB 边长 = (%.1f, %.1f, %.1f)  最长局部轴 = %s"
			% [aabb.size.x, aabb.size.y, aabb.size.z, str(axes[order[0]])])

	# 机身长轴在**模型根空间**（= mesh_rot 之后）
	var long_root_a: Vector3 = (mesh_rot * axes[order[0]]).normalized()
	var long_root_b: Vector3 = -long_root_a
	print("   几何长轴(模型根空间) = ±(%+.3f, %+.3f, %+.3f)"
			% [long_root_a.x, long_root_a.y, long_root_a.z])
	inst.free()

	# 另外两根轴（次长、最短）—— 用于判"船背朝哪"
	# 需要再加载一次拿 AABB（上面 free 了）
	inst = MODEL.instantiate(id, false)
	mn = _first_mesh(inst)
	aabb = mn.mesh.get_aabb()
	var mid_axis_root: Vector3 = (mesh_rot * axes[order[1]]).normalized()
	var min_axis_root: Vector3 = (mesh_rot * axes[order[2]]).normalized()
	print("   次长轴(模型根空间) = (%+.3f, %+.3f, %+.3f)"
			% [mid_axis_root.x, mid_axis_root.y, mid_axis_root.z])
	print("   最短轴(模型根空间) = (%+.3f, %+.3f, %+.3f)"
			% [min_axis_root.x, min_axis_root.y, min_axis_root.z])
	inst.free()

	# ── 枚举全部 24 个"符号置换"spec，筛「长轴 → ±Z 水平」的解 ───────────
	print("")
	print("   候选 spec（把 geo 长轴送到世界 ±Z，且 det=+1）：")
	var found := 0
	for perm in _permutations3():
		for signs in _sign_combos3():
			# spec 行语义：第 j 个 token = M 第 j 行
			var rows: Array[Vector3] = []
			for j in 3:
				var v := Vector3.ZERO
				var ax: int = perm[j]          # 第 j 个 token 指到世界第 perm[j] 轴
				v[ax] = signs[j]
				rows.append(v)
			var m := _make_m(rows)
			if absf(m.determinant() - 1.0) > 1e-6:
				continue
			# 该 M 作用在**模型空间**：M · long_root 应落 ±Z
			var w: Vector3 = m * long_root_a
			if absf(w.z) < 0.999:
				continue
			if absf(w.y) > 0.02:
				continue
			# 同时 M · mid_axis 应落 ±Y（船背竖直）
			var wm: Vector3 = m * mid_axis_root
			if absf(wm.y) < 0.999:
				continue
			found += 1
			print("     %s   → geo长轴→%s · 次长轴→%s"
					% [_spec_text(rows), _v3(w), _v3(wm)])
	print("   共 %d 个解" % found)
	print("")


func _permutations3() -> Array:
	return [[0, 1, 2], [0, 2, 1], [1, 0, 2], [1, 2, 0], [2, 0, 1], [2, 1, 0]]


func _sign_combos3() -> Array:
	var out := []
	for a in [1.0, -1.0]:
		for b in [1.0, -1.0]:
			for c in [1.0, -1.0]:
				out.append([a, b, c])
	return out


## 行语义 ⇒ `M[i][j] = rows[j][i]`（红线 48b）
func _make_m(rows: Array[Vector3]) -> Basis:
	var r0: Vector3 = rows[0]
	var r1: Vector3 = rows[1]
	var r2: Vector3 = rows[2]
	return Basis(Vector3(r0.x, r1.x, r2.x),
			Vector3(r0.y, r1.y, r2.y),
			Vector3(r0.z, r1.z, r2.z))


func _spec_text(rows: Array[Vector3]) -> String:
	var names := ["X", "Y", "Z"]
	var out: Array[String] = []
	for r in rows:
		var ax := 0
		if absf(r.y) > 0.5:
			ax = 1
		elif absf(r.z) > 0.5:
			ax = 2
		var s := "-" if r[ax] < 0.0 else "+"
		out.append("%s%s" % [s, names[ax]])
	return ",".join(out)


func _v3(v: Vector3) -> String:
	return "(%+.2f,%+.2f,%+.2f)" % [v.x, v.y, v.z]


func _first_mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n as MeshInstance3D
	for c in n.get_children():
		var got := _first_mesh(c)
		if got != null:
			return got
	return null
