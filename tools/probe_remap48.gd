extends Node
## 48 轮 · **`AXIS_REMAP` 纯代数重算器（零假设版）**。
##
## ═══ 为什么必须重写（47 轮穷举器的病根）═══
##  47 轮的 `_solve_spec` 判据是：
##      `f·bow = −Z` 且 `f·up = +Y` 且 `f·side = +X`
##  其中 `up` / `side` 取自 `YAW.up_axis()` / `bow×up` —— 即**从 `SHIP_AXES` 读**。
##  问题不在"读表"本身（这是对的），而在**它把 up 钉到 +Y 就宣布成功**：
##  当 `(bow, up, side)` 三者的**手性**与 `(−Z, +Y, +X)` 的手性**相反**时，
##  方程**无解**，但穷举器仍会返回一个"看起来命中"的 spec（浮点容差内），
##  那支解 = **镜像**（det = −1）或**多一个 180°**。
##
## ═══ 本版口径（唯一解，可验证）═══
##  把 `mesh_rot·[bow, up, side]` 当成**源基**（三个正交单位列），
##  把 `[−Z, +Y, side_target]` 当成**目标基**，其中
##      `side_target = (−Z) × (+Y) = (+X)`  （由前两列**唯一确定**，不许自由）
##  同理源侧的第三列必须用 `side_m = bow × up`（而不是任何别的写法）。
##  ⇒ `M = T · S⁻¹`，且**两侧都强制 det = +1**（`_ortho` 里断言）。
##
##  ⚠️ 若某艘船的 `(bow, up)` 使得 `side_m = bow×up` 与 `+X` 不匹配，
##     则说明该船的 bow/up 语义**本身**有问题 ⇒ 打印出来、**不硬塞**。
##     （红线 40：宁可报错，不许给一个"看着对"的值。）
##
## 产出 → `user://bow_calib/remap48.txt`
##
## ── 跑法 ──
##   `--headless --path <工程> --quit-after 400 res://tools/probe_remap48.tscn`
const YAW := preload("res://scripts/data/eve_ship_yaw.gd")


func _ready() -> void:
	print("═══ 48 轮 · AXIS_REMAP 纯代数重算（零假设）═══")
	# 目标基（列）：bow → −Z · up → +Y · side → +X
	var T := Basis(Vector3(0, 0, -1), Vector3(0, 1, 0), Vector3(1, 0, 0))
	var lines: Array[String] = []
	var n := 0
	var bad: Array[String] = []
	var ids: Array = []
	for k in YAW.AXIS_REMAP.keys():
		ids.append(String(k))
	ids.sort()
	for id in ids:
		var sid := StringName(id)
		var mr: Basis = EveShipVisual.mesh_rot_of(sid)
		var bow: Vector3 = YAW.bow_axis(sid)
		var up: Vector3 = YAW.up_axis(sid)
		var side_m: Vector3 = bow.cross(up)
		if side_m.length_squared() < 1e-8:
			bad.append("%s: bow 与 up 共线" % id)
			continue
		side_m = side_m.normalized()
		# 源基：mesh_rot 作用后的三轴（列）
		var S := Basis(mr * bow, mr * up, mr * side_m)
		var S2 := _ortho(S)
		if S2.is_empty():
			bad.append("%s: 源基退化" % id)
			continue
		# M = T · S⁻¹
		var m: Basis = T * (S2["basis"] as Basis).inverse()
		# ── 自检：三条判据 + det + 正交 ──
		var gm: Basis = m * mr
		var gb: Vector3 = (gm * bow).normalized()
		var gu: Vector3 = (gm * up).normalized()
		var gs: Vector3 = (gm * side_m).normalized()
		var ok := gb.distance_to(Vector3(0, 0, -1)) < 0.002 \
				and gu.distance_to(Vector3(0, 1, 0)) < 0.002 \
				and gs.distance_to(Vector3(1, 0, 0)) < 0.002 \
				and absf(m.determinant() - 1.0) < 0.002 \
				and (m * m.transposed()).is_equal_approx(Basis.IDENTITY)
		# ── 转成 spec（每个 token = 该列）──
		var spec := _to_spec(m)
		# ★★ 往返自检（红线 40 的根本防线）：spec 装回去必须还原同一个 M。
		#    没有这一步，"拆 spec 时行列写反"会**静默**产生一张看着像对的错表
		#    —— 48 轮实测踩过（`algos`/`catalyst` 拆出了列语义下才对的 spec，
		#       但当时按行语义拆 ⇒ 装回游戏 up 落 +Z 而不是 +Y）。
		var m_rt: Basis = YAW.parse_axis_remap(spec)
		var rt_ok: bool = _basis_close(m_rt, m, 0.002)
		# ★★ 48 轮：**spec 可表达性**检查 —— M 是否真的是 ±1 置换矩阵。
		#    非置换（含 0.707 之类）⇒ `AXIS_REMAP` 这张表**根本表达不了**该船，
		#    硬拆出来的 spec 装回游戏就是错的（往返自检会失败）。
		#    实测：`algos` / `catalyst` / `myrmidon`（mesh_rot 为 90°/120° 斜轴的船）。
		var perm := _is_permutation(m)
		lines.append("\t&\"%s\": \"%s\"," % [id, spec])
		n += 1
		if not perm:
			bad.append("%s: **M 不是 ±1 置换矩阵（spec 表达不了）**\n       M = [%s | %s | %s]"
					% [id, _v(m[0]), _v(m[1]), _v(m[2])])
		elif not rt_ok:
			bad.append("%s: **spec 往返不一致** spec=%s" % [id, spec])
		if not ok:
			bad.append("%s: 自检未过 bow=%s up=%s side=%s det=%+.3f"
					% [id, _v(gb), _v(gu), _v(gs), m.determinant()])
		print("  %-12s %-13s bow=%s up=%s side=%s det%+.0f rt=%s perm=%s %s"
				% [id, spec, _v(gb), _v(gu), _v(gs), m.determinant(),
				   ("✔" if rt_ok else "✗"), ("✔" if perm else "✗"), ("✔" if ok else "✗")])
	print("")
	print("── 共 %d 艘 · 自检未过 %d 艘 ──" % [n, bad.size()])
	for b in bad:
		print("   ✗ %s" % b)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://bow_calib"))
	var f := FileAccess.open("user://bow_calib/remap48.txt", FileAccess.WRITE)
	if f != null:
		f.store_line("# 48 轮 AXIS_REMAP 纯代数重算（M = T·S⁻¹，S = mesh_rot·[bow,up,bow×up]）")
		for l in lines:
			f.store_line(l)
		f.close()
		print("已写出：%s" % ProjectSettings.globalize_path("user://bow_calib/remap48.txt"))
	get_tree().quit(0)


## 把 Basis 拆回 spec：**第 i 个 token = Basis 第 i 行**。
##
## ⚠️⚠️ 48 轮实测（两次踩坑后定案，勿再改）：
##   `parse_axis_remap` 的构造是：
##       `Basis( (r0.x,r1.x,r2.x), (r0.y,r1.y,r2.y), (r0.z,r1.z,r2.z) )`
##   而 Godot 的 `Basis(a,b,c)` 三参数 = **列** ⇒
##       `M 的第 0 列 = (r0.x, r1.x, r2.x)` ⇒ `M[i][j] = r_j[i]`
##   ⇒ **`M` 的第 j 行 = `r_j` = spec 第 j 个 token**（行语义）。
##
##   ⚠️ 取行**不能**写 `Vector3(m[i].x, m[i].y, m[i].z)` ——
##       Godot 的 `m[i]` 返回的是**第 i 列**（实测 `m[0] == m.x`），
##       那样取到的是列 ⇒ 对 diag 型 spec 恰好等价（所以 30+ 艘船从没暴露），
##       对**非 diag 型**（algos / catalyst / myrmidon / kestrel …）**差一个转置**。
##       正确取法：`Vector3(m.x[i], m.y[i], m.z[i])`。
func _to_spec(m: Basis) -> String:
	var out: Array[String] = []
	for i in 3:
		var r := Vector3(m.x[i], m.y[i], m.z[i])   # ← 第 i 行（勿写成 m[i]）
		var ax := 0
		var best := -1.0
		for j in 3:
			var a := absf(r[j])
			if a > best:
				best = a
				ax = j
		out.append(("%s%s" % ["+" if r[ax] >= 0.0 else "-", "XYZ"[ax]]))
	return ",".join(out)


## 强制正交归一 + det=+1（det<0 = 镜像 ⇒ 拒绝，红线 39/27）。
func _ortho(b: Basis) -> Dictionary:
	var x := b.x.normalized()
	var y := b.y - x * x.dot(b.y)
	if y.length_squared() < 1e-10:
		return {}
	y = y.normalized()
	var z := x.cross(y).normalized()
	var out := Basis(x, y, z)
	if out.determinant() < 0.0:
		return {}
	return {"basis": out}


func _v(v: Vector3) -> String:
	return "(%+.2f,%+.2f,%+.2f)" % [v.x, v.y, v.z]


## 两个 Basis 是否逐元素接近（往返自检用）。
func _basis_close(a: Basis, b: Basis, eps: float) -> bool:
	for i in 3:
		if a[i].distance_to(b[i]) > eps:
			return false
	return true


## `M` 是否是 **±1 置换矩阵** —— 即 `AXIS_REMAP` 的 spec 能否精确表达它。
## 判据：每列/每行有且仅有一个 ±1，其余为 0。
func _is_permutation(m: Basis) -> bool:
	for i in 3:
		var col := m[i]
		var big := 0
		for j in 3:
			var a := absf(col[j])
			if a > 0.999:
				big += 1
			elif a > 0.001:
				return false
		if big != 1:
			return false
	return true
