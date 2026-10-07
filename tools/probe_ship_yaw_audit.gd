extends Node

## 52 艘 3D 舰船朝向审计 —— 回答「全船统一 MODEL_YAW_FIX 到底对几艘」
##
## ══════════════════════════════════════════════════════════════════
##  它要回答的问题
## ══════════════════════════════════════════════════════════════════
##  `eve_ship_visual.gd` 里只有**一个**常量模型修正角：
##
##      const MODEL_YAW_FIX := -PI / 2.0
##
##  注释写的是「glb 里舰船的长轴是 +X，所以绕 Y 转 −90° 把它对到 +Z」。
##  这条只对「长轴真在 +X」的船成立。用户实测**磨难级朝向不对** ⇒
##  52 艘 glb 的长轴并不都在同一个轴上，需要**逐艘**修正。
##
## ── 这个探针怎么判 ────────────────────────────────────────────────
##  θ = 顶点在 XZ 平面上的 PCA 主方向与 +X 的夹角（见 probe_ship_render 的推导）。
##  绕 Y 转 a 会把方向 (cosθ, sinθ) 变成 (cos(θ−a), sin(θ−a))：
##    目标 +Z = (0,1)
##    当前实现 a = −π/2  ⇒  实际朝向 = (cos(θ+π/2), sin(θ+π/2)) = (−sinθ, cosθ)
##    与 +Z 的夹角 = **θ 本身**
##  ⇒ **θ 就是「当前朝向下长轴偏离 +Z 的角度」，不需要再换算。**
##
##  ⚠️ PCA 主方向是**轴**不是有向向量，所以 θ ∈ (−90°, +90°]，
##     它天然说不出「船头朝哪边」—— 那 180° 只能靠人眼标定。
##     本探针用「端部横截面积」给一个**猜测**：
##     EVE 舰船普遍是「舰艏尖瘦、舰尾宽厚（引擎块）」⇒ 瘦的那端 = 船头。
##     ⚠️ 这是启发式，不是定理（舰艏带叉的船会猜错）——
##        它只用来给人工标定一个「对得多」的初值，不是结论。
##
## ── 跑法（只读几何，可 headless）────────────────────────────────
##   "C:/godot/Godot_v4.7.1-stable_win64_console.exe" --headless \
##     --path "F:/evezzq/eve自走棋918" --quit-after 4000 \
##     res://tools/probe_ship_yaw_audit.tscn

const INDEX := preload("res://scripts/data/eve_ship_asset_index.gd")

## 顶点降采样步长（PCA / 端部取样用）。全量顶点太慢，隔 11 个取一个足够定方向。
const PCA_STEP := 11

## 端部取样比例：取主轴两端各 28% 的顶点算横截面积。
const TIP_FRAC := 0.28

## 判定「长轴歪了」的阈值（度）。低于此值肉眼看不出来，不值得进修正表。
const BAD_DEG := 12.0

var _holder: Node3D = null


func _ready() -> void:
	_holder = Node3D.new()
	add_child(_holder)

	var rows: Array = []
	for r in INDEX.ROWS:
		rows.append(r)
	rows.sort_custom(func(a, b): return String(a[0]) < String(b[0]))

	print("[YAW] ════ 52 艘朝向审计（当前实现 = 全船统一 −90°）════")
	print("[YAW] %-13s %8s %10s  %-18s %9s %9s  %s"
			% ["id", "θ(°)", "偏差(°)", "对齐后AABB/L", "−X端", "+X端", "判定 · 船头猜测"])
	var n_axis_bad := 0
	var n_flip_guess := 0
	for r in rows:
		var id := StringName(r[0])
		var d := _audit(id)
		if d.is_empty():
			print("[YAW] %-13s   —— 无模型 / 几何退化" % String(id))
			continue
		var th: float = d["theta"]
		var ab: Vector3 = d["aabb"]
		var pm: float = d["tip_m"]
		var pp: float = d["tip_p"]
		var deg := rad_to_deg(th)
		var head_side := "-X" if pm < pp else "+X"
		var verdict := "长轴 OK"
		if absf(deg) >= BAD_DEG:
			verdict = "⚠ 长轴歪 %.0f°" % absf(deg)
			n_axis_bad += 1
		if head_side == "-X":
			n_flip_guess += 1
		print("[YAW] %-13s %+8.1f %+10.1f  %5.2f×%5.2f×%5.2f  %9.4f %9.4f  %s · 船头≈%s"
				% [String(id), deg, deg, ab.x, ab.y, ab.z, pm, pp, verdict, head_side])

	print("")
	print("[YAW] ── 汇总 ──")
	print("[YAW]   长轴歪（|θ| ≥ %.0f°）: %d / %d" % [BAD_DEG, n_axis_bad, rows.size()])
	print("[YAW]   端部启发式猜「船头在 −X 端」: %d / %d（其余猜 +X 端）"
			% [n_flip_guess, rows.size()])
	_report_remapped()
	print("[YAW] ==== DONE ====")
	get_tree().quit()


## ── 第二遍：做过 AXIS_REMAP 的船，残差必须**重算** ──────────────────
##
## 旧 AXIS_DEG 是在「模型 XZ 平面」上量的，前提是「长轴在 X / 上在 Y」。
## 船一旦被 M 转过，那个平面里根本没有长轴 ⇒ 旧数字无意义。
## 这里把 M 并进 pre-transform，于是量的是「舰艏轴 × 侧向轴」平面，
## 语义变成「主轴相对**舰艏方向**的偏角」，正好就是引擎 yaw 要减的那个角。
##
## ⚠️ 两条**不写进表**的判据（写进去就是把船拧成横着飞）：
##   ① degen ≥ 0.5 ⇒ 平面近似各向同性，PCA 由噪声决定 ⇒ θ 置 0（信任人工舰艏）
##   ② |θ| > 45° ⇒ 人工标的舰艏轴**不是**长轴 ⇒ 置 0 并报 CONFLICT 给人复核
func _report_remapped() -> void:
	var ids: Array = EveShipYawTable.AXIS_REMAP.keys()
	if ids.is_empty():
		return
	print("")
	print("[YAW] ════ AXIS_REMAP 船：残差重算（口径与上面同源，只多乘了一个 M）════")
	print("[YAW] %-12s %-12s %9s %8s  %9s %9s %9s  %s"
			% ["id", "spec", "新θ(°)", "退化度", "L(舰艏)", "H(船背)", "W(侧向)", "判定"])
	for id in ids:
		var sid := StringName(id)
		var spec: String = EveShipYawTable.AXIS_REMAP[id]
		var model := EveShipModel.instantiate(sid, false)
		if model == null:
			print("[YAW] %-12s   —— 无模型" % String(sid))
			continue
		_holder.add_child(model)
		var m := EveShipYawTable.axis_remap(sid)
		var sc := _xz_principal_angle(model, Transform3D(m, Vector3.ZERO))
		var deg: float = rad_to_deg(float(sc["theta"]))
		var dg: float = float(sc["degen"])
		var keep: bool = absf(deg) <= 45.0 and dg < 0.5
		# 船体三尺寸：绕 Y 转 θ 之后再量 AABB ⇒ x=沿舰艏 / y=沿船背 / z=沿侧向
		var rot := Basis.from_euler(Vector3(0.0, sc["theta"], 0.0))
		var ab: Vector3 = _aabb_of(model, Transform3D(rot * m, Vector3.ZERO)).size
		var verdict: String = "θ=%.2f" % deg if keep else "θ=0 ⚠ %s" % (
				"退化(PCA不可信)" if dg >= 0.5 else "CONFLICT 舰艏轴≠长轴")
		print("[YAW] %-12s %-12s %+9.2f %8.3f  %9.1f %9.1f %9.1f  %s"
				% [String(sid), spec, deg, dg, ab.x, ab.y, ab.z, verdict])
		model.queue_free()


func _audit(id: StringName) -> Dictionary:
	var model := EveShipModel.instantiate(id, false)
	if model == null:
		return {}
	_holder.add_child(model)

	var sc := _xz_principal_angle(model)
	var theta: float = sc["theta"]
	var rot := Basis.from_euler(Vector3(0.0, theta, 0.0))
	var aabb := _aabb_of(model, Transform3D(rot, Vector3.ZERO))
	if aabb.size.length() < 0.0001:
		model.queue_free()
		return {}

	# 端部横截面积：主轴两端各取 TIP_FRAC，量该段顶点在 (y,z) 上的包围面积。
	# 瘦（面积小）的一端 = 舰艏。
	var tip_p := _tip_area(model, rot, aabb, +1)
	var tip_m := _tip_area(model, rot, aabb, -1)

	var l := maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z))
	l = maxf(l, 0.0001)
	model.queue_free()
	return {"theta": theta, "aabb": aabb.size / l, "tip_p": tip_p, "tip_m": tip_m}


## 端部横截面积（在 rot 空间里，取主轴端点侧的一段顶点，量其 y/z 包围盒面积）
func _tip_area(n: Node, rot: Basis, aabb: AABB, side: int) -> float:
	var pts: PackedVector3Array = []
	_collect_xyz(n, Transform3D(rot, Vector3.ZERO), pts)
	if pts.is_empty():
		return 0.0
	var lo := aabb.position.x
	var hi := aabb.position.x + aabb.size.x
	var span := maxf(0.0001, hi - lo)
	var cut_hi := hi - TIP_FRAC * span
	var cut_lo := lo + TIP_FRAC * span
	var mn := Vector3(1e9, 1e9, 1e9)
	var mx := Vector3(-1e9, -1e9, -1e9)
	var found := false
	for p in pts:
		if side > 0:
			if p.x < cut_hi:
				continue
		else:
			if p.x > cut_lo:
				continue
		found = true
		mn = mn.min(p)
		mx = mx.max(p)
	if not found:
		return 0.0
	var s := mx - mn
	return s.y * s.z        # 横截面「胖瘦」的代理量


## XZ 平面主方向：对顶点做 2D 协方差、取主特征向量的角度
##
## [param pre] 会先乘到顶点上 —— 用来把「轴重映射」M 并进来：
##   传 M 时，这里的 XZ 平面正好是「舰艏轴 b × 侧向轴 u」张成的水平面，
##   于是同一段代码既能量普通船，也能量做过 AXIS_REMAP 的船（口径必然同源）。
##
## 返回 Dictionary：
##   theta = 主方向与 +X 的夹角（弧度）。绕 Y 旋转 +theta 即可把主方向对到 +X：
##     方向向量 (cosθ, sinθ) --绕Y转 a--> (cos(a−θ), sin(θ−a))
##     要它等于 (1,0) ⇒ a = θ
##   degen = λ₂/λ₁ ∈ [0,1]，**平面内两轴等长度**的量度。
##     接近 1 ⇒ 该平面近似各向同性 ⇒ PCA 主轴由噪声决定，**θ 不可信**（必须置 0）。
##     condor / raven 就落在这里（两轴差 0.3% / 3.5%），这正是它们当初进 PENDING 的原因。
func _xz_principal_angle(root: Node, pre := Transform3D()) -> Dictionary:
	var pts: PackedVector2Array = []
	_collect_xz(root, pre, pts)
	if pts.size() < 4:
		return {"theta": 0.0, "degen": 1.0}
	var n := float(pts.size())
	var mean := Vector2.ZERO
	for p in pts:
		mean += p
	mean /= n
	var cxx := 0.0
	var czz := 0.0
	var cxz := 0.0
	for p in pts:
		var d := p - mean
		cxx += d.x * d.x
		czz += d.y * d.y
		cxz += d.x * d.y
	var tr := cxx + czz
	var dif := sqrt((cxx - czz) * (cxx - czz) + 4.0 * cxz * cxz)
	var l1 := 0.5 * (tr + dif)
	return {
		"theta": 0.5 * atan2(2.0 * cxz, cxx - czz),
		"degen": 0.0 if l1 < 1e-12 else 0.5 * (tr - dif) / l1,
	}


func _collect_xz(n: Node, xf: Transform3D, out: PackedVector2Array) -> void:
	var here := xf
	if n is Node3D:
		here = xf * (n as Node3D).transform
	if n is MeshInstance3D:
		var mesh: Mesh = (n as MeshInstance3D).mesh
		if mesh != null:
			for si in mesh.get_surface_count():
				var arrays := mesh.surface_get_arrays(si)
				if arrays.size() <= Mesh.ARRAY_VERTEX:
					continue
				var vs: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var i := 0
				while i < vs.size():
					var p := here * vs[i]
					out.append(Vector2(p.x, p.z))
					i += PCA_STEP
	for c in n.get_children():
		_collect_xz(c, here, out)


func _collect_xyz(n: Node, xf: Transform3D, out: PackedVector3Array) -> void:
	var here := xf
	if n is Node3D:
		here = xf * (n as Node3D).transform
	if n is MeshInstance3D:
		var mesh: Mesh = (n as MeshInstance3D).mesh
		if mesh != null:
			for si in mesh.get_surface_count():
				var arrays := mesh.surface_get_arrays(si)
				if arrays.size() <= Mesh.ARRAY_VERTEX:
					continue
				var vs: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var i := 0
				while i < vs.size():
					out.append(here * vs[i])
					i += PCA_STEP
	for c in n.get_children():
		_collect_xyz(c, here, out)


## 子树的 AABB（从 [param pre] 起算，无视本节点自身的 transform）
##
## ⚠️ 必须逐级累乘 transform：glb 里网格常挂在带缩放的中间节点下，
##    只取 MeshInstance3D.transform 会漏掉父级缩放，量出来的包围盒偏小。
func _aabb_of(root: Node, pre: Transform3D) -> AABB:
	var parts: Array[AABB] = []
	_collect_aabb(root, pre, parts)
	if parts.is_empty():
		return AABB()
	var a := parts[0]
	for i in range(1, parts.size()):
		a = a.merge(parts[i])
	return a


func _collect_aabb(n: Node, xf: Transform3D, out: Array[AABB]) -> void:
	var here := xf
	if n is Node3D:
		here = xf * (n as Node3D).transform
	if n is MeshInstance3D:
		var a := (n as MeshInstance3D).get_aabb()
		var mn := Vector3(1e9, 1e9, 1e9)
		var mx := Vector3(-1e9, -1e9, -1e9)
		for i in 8:
			var p := here * a.get_endpoint(i)
			mn = mn.min(p)
			mx = mx.max(p)
		out.append(AABB(mn, mx - mn))
	for c in n.get_children():
		_collect_aabb(c, here, out)
