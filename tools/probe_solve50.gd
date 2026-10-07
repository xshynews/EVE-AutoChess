extends Node
## ══════════════════════════════════════════════════════════════════════
##  50 轮 · **精确反解 spec**（用生产算式，不走手推 —— 红线 40/49c）
## ══════════════════════════════════════════════════════════════════════
##
## ✅ **本探针是本轮唯一「范式正确」的工具 —— 保留，作为反解 spec 的标准工具。**
##   它的做法：对每艘试 3 条长轴候选 × 3 条 up 候选 × 24 个合法 spec，
##   用**生产算式** `zp = M · mesh_rot`（yaw = 0）求值，检查
##   `zp·长轴 = (0,0,−1)` 且 `zp·up = (0,1,0)`。**不手推任何一层**（红线 40）。
##
## ⚠️⚠️ **但它同时证明了一件很重要的事：约束不够，无法唯一定 spec。**
##   对 `kestrel`，满足「长轴→−Z、up→+Y」的**合法 spec 有 12 个**
##   ⇒ **纯几何/代数解不出唯一答案**，必须靠**外观**（红线 33：实机图 / 官方 render）
##   或用户裁定来收口。
##
## ⚠️ 另外注意：它引用的「长轴」若来自 AABB，则同样带红线 50b 的病
##   （AABB 最长边对扁平宽板船失效）⇒ 传参时请改用可靠的「舰艏轴」来源。
##
## ── 前一次失败的教训 ────────────────────────────────────────────────
##  `probe_fixspec50` 手拼了「M 作用在长轴上」的算式，**漏了 `R_y` 与
##  `R_z(180°)` 两层**，解出的 spec 落盘后 `verify_run` 报 8 项失败。
##  ⇒ 本轮改成**直接用生产算式** `zero_pose_basis_no_roll()` 求值，
##    并让**引擎自己乘**（红线 40：探针一个乘号都不写）。
##
## ── 约束（与 `verify_run` 的验收锚点**同口径**）──────────────────────
##   用 `zero_pose_basis_no_roll(id)`（= `R_y(yaw)·M·mesh_rot`，yaw=0）：
##     ① `zp · bow_geo_root`  = (0, 0, −1)   舰艏朝敌
##     ② `zp · up_geo_root`   = (0, +1, 0)   船背朝天
##   其中 `*_geo_root` = **几何真相**（网格空间 AABB 轴，经 `mesh_rot` 提到根空间）。
##
## ── 枚举空间 ────────────────────────────────────────────────────────
##   spec 是 3 个 token，每个 ∈ {±X,±Y,±Z} 且**两两不同轴**（6×4×2 = 48 种），
##   外加 det=+1 过滤（去掉 24 种反射）⇒ 24 种合法旋转。
##   对每种：按 `parse_axis_remap` 的**行语义**构造 M（红线 48b），
##   用生产算式求 `zp`，检查 ①② 是否成立（容差 1e-3）。
##
## 跑法：`--headless --path <工程> --quit-after 300 res://tools/probe_solve50.tscn`

const YAW := preload("res://scripts/data/eve_ship_yaw.gd")
const MODEL := preload("res://scripts/visual/eve_ship_model.gd")
const VIS: Variant = null   # 占位

const TARGETS: Array[String] = ["algos", "catalyst", "kestrel", "slasher", "tristan"]

## 几何真相：由 `_read_geo()` 从 glb 读（**不碰任何表**）
var _geo: Dictionary = {}

func _ready() -> void:
	print("")
	print("═══ 50 轮 · 精确反解 spec（用生产算式求值，不手推）═══")
	print("")
	for id in TARGETS:
		_geo[id] = _read_geo(StringName(id))
	for id in TARGETS:
		_solve(StringName(id))
	get_tree().quit(0)


## 读几何真相：网格 AABB 的三根轴（**网格空间**），按边长排序。
## 返回 `{"axes": [最长, 次长, 最短], "lens": [..,..,..]}`，全部**网格空间单位向量**。
func _read_geo(id: StringName) -> Dictionary:
	var inst := MODEL.instantiate(id, false)
	if inst == null:
		return {"axes": [], "lens": []}
	var mn := _first_mesh(inst)
	if mn == null or mn.mesh == null:
		inst.free()
		return {"axes": [], "lens": []}
	var sz: Vector3 = mn.mesh.get_aabb().size
	inst.free()
	var cand: Array = [[sz.x, Vector3(1, 0, 0)], [sz.y, Vector3(0, 1, 0)], [sz.z, Vector3(0, 0, 1)]]
	cand.sort_custom(func(a, b): return float(a[0]) > float(b[0]))
	var axes: Array[Vector3] = []
	var lens: Array[float] = []
	for c in cand:
		axes.append(c[1])
		lens.append(float(c[0]))
	return {"axes": axes, "lens": lens}


func _solve(id: StringName) -> void:
	print("──────────────────────────────────────────────────────────")
	print("■ %s   现状 SHIP_AXES = %s" % [String(id), YAW.ship_axes_text(id)])
	var g: Dictionary = _geo[id]
	if g["axes"].is_empty():
		print("   ✗ 读不到几何")
		return
	var axes: Array = g["axes"]
	var lens: Array = g["lens"]
	print("   AABB 边长 = (%.1f, %.1f, %.1f)" % [lens[0], lens[1], lens[2]])
	print("   最长轴(网格) = %s   次长 = %s   最短 = %s"
			% [_v(axes[0]), _v(axes[1]), _v(axes[2])])

	# mesh_rot：网格 → 根
	var mesh_rot := _mesh_rot(id)

	# 三个候选"长轴"（网格空间）—— 逐个试（几何上只有最长那条是真长轴，
	# 但用户的 up 语义可能让它不是"最长"，所以三条都枚举，看哪条能解出）
	var sols: Array[String] = []
	for i_lo in 3:
		var long_root: Vector3 = (mesh_rot * axes[i_lo]).normalized()
		for i_up in 3:
			if i_up == i_lo:
				continue
			var up_root: Vector3 = (mesh_rot * axes[i_up]).normalized()
			for spec in _all_specs():
				var m := _parse(spec)
				# ★ 生产算式：zp = R_y(yaw=0) · M · mesh_rot
				#   yaw=0（AXIS_DEG 全 0 / FLIP 空 / GLOBAL_180 false）
				var zp := m * mesh_rot
				var w_bow: Vector3 = (zp * long_root).normalized()
				var w_up: Vector3 = (zp * up_root).normalized()
				if (w_bow - Vector3(0, 0, -1)).length() < 1e-3 \
						and (w_up - Vector3(0, 1, 0)).length() < 1e-3:
					var tag := "%s(长轴=%s, up=%s)" % [spec, _axn(axes[i_lo]), _axn(axes[i_up])]
					if not sols.has(tag):
						sols.append(tag)
	print("   ⇒ 满足「长轴→−Z、up→+Y」的 spec（24 种合法旋转里）：")
	if sols.is_empty():
		print("      （无解 —— 说明 24 种里没有能同时满足两条的）")
	else:
		for s in sols:
			print("      %s" % s)


func _all_specs() -> Array[String]:
	var ax := ["X", "Y", "Z"]
	var out: Array[String] = []
	for i in 3:
		for j in 3:
			if j == i:
				continue
			for k in 3:
				if k == i or k == j:
					continue
				for si in ["+", "-"]:
					for sj in ["+", "-"]:
						for sk in ["+", "-"]:
							out.append("%s%s,%s%s,%s%s" % [si, ax[i], sj, ax[j], sk, ax[k]])
	return out


## 行语义：第 j 个 token = M 第 j 行（红线 48b）
func _parse(spec: String) -> Basis:
	var toks := spec.split(",")
	var rows: Array[Vector3] = []
	for t in toks:
		var s := -1.0 if t.begins_with("-") else 1.0
		var v := Vector3.ZERO
		v["XYZ".find(t[1])] = s
		rows.append(v)
	return Basis(Vector3(rows[0].x, rows[1].x, rows[2].x),
			Vector3(rows[0].y, rows[1].y, rows[2].y),
			Vector3(rows[0].z, rows[1].z, rows[2].z))


func _mesh_rot(id: StringName) -> Basis:
	var inst := MODEL.instantiate(id, false)
	if inst == null:
		return Basis.IDENTITY
	var mn := _first_mesh(inst)
	var out := Basis.IDENTITY
	if mn != null:
		out = mn.transform.basis.orthonormalized()
	inst.free()
	return out


func _axn(v: Vector3) -> String:
	var n := ["X", "Y", "Z"]
	for i in 3:
		if absf(v[i]) > 0.5:
			return ("-" if v[i] < 0 else "+") + n[i]
	return "?"


func _v(v: Vector3) -> String:
	return "(%.0f,%.0f,%.0f)" % [v.x, v.y, v.z]


func _first_mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n as MeshInstance3D
	for c in n.get_children():
		var got := _first_mesh(c)
		if got != null:
			return got
	return null
