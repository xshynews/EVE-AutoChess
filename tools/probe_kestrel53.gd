extends Node

## ★ 53 轮（第二版）· **kestrel / slasher 表项 vs 用户指认** 反解
##
## ══════════════════════════════════════════════════════════════════
##  用户 53 轮（第二版）原话
## ══════════════════════════════════════════════════════════════════
##  「舰艏还是朝向玩家的，这不对。kestrel_SIDE.png 里面船是茶隼，
##    **可以转 Z 轴，沿 X 轴转 180 度就合适了**。」
##
##  ⇒ 这是一个**可执行**的指令，不是形容词：
##     在现有姿态基础上，**沿模型 X 轴转 180°**，就对了。
##
## ══════════════════════════════════════════════════════════════════
##  这个探针干什么
## ══════════════════════════════════════════════════════════════════
##  ① 复现 `kestrel` / `slasher` 的**当前**世界姿态（走生产算式，零复刻）；
##  ② 在**表层面**穷举所有「轴翻转」组合（bow 取 ±X/±Y/±Z 的 6 种，
##     各自配 up 的合法正交解），算出每种组合下舰艏的世界方向；
##  ③ 找出**哪一种组合恰好等价于用户说的「沿 X 轴转 180°」**。
##
##  ⚠️ 红线 40：姿态算式**直接调** `EveShipVisual.zero_pose_basis()`，
##     不自己手推（手推已翻车三次，见 50d）。
##     「沿 X 轴转 180°」的等价判据在下面 `_rot_x_180_of()` 里显式写出。
##
##  用法：
##      Godot_v4.7.1-stable_win64_console.exe --headless \
##          --path "<工程>" --quit-after 900 \
##          res://tools/probe_kestrel53.tscn

const SIDE := preload("res://scripts/data/eve_ship_yaw.gd")

var _ids: PackedStringArray = ["kestrel", "slasher", "catalyst"]


func _ready() -> void:
	print("══════════════════════════════════════════════════════════════")
	print("  53b · kestrel/slasher 表项反解（用户指认：沿 X 轴转 180°）")
	print("══════════════════════════════════════════════════════════════")
	for sid in _ids:
		_one(sid)
	get_tree().quit()


func _one(sid: String) -> void:
	print("")
	print("════ %s ════" % sid)
	var id := StringName(sid)

	# ── 当前表值 ──
	var spec_remap: String = _remap_str(id)
	var spec_axes: String = _axes_str(id)
	print("  AXIS_REMAP = %s" % spec_remap)
	print("  SHIP_AXES  = %s" % spec_axes)

	# ── 当前世界姿态（引擎口径：zero_pose_basis 就是 model.basis）──
	var zp := EveShipVisual.zero_pose_basis(id)
	var bow_local: Vector3 = SIDE.bow_axis(id)
	var up_local: Vector3 = SIDE.up_axis(id)
	var bow_world := (zp * bow_local).normalized()
	var up_world := (zp * up_local).normalized()
	print("  当前 bow_local=%s  up_local=%s" % [_v(bow_local), _v(up_local)])
	print("  当前 舰艏(世界)=%s   船背(世界)=%s" % [_v(bow_world), _v(up_world)])

	# ── 用户要的「沿 X 轴转 180°」等价结果（三种读法全算）──
	#    用户原话：「船是茶隼，**可以转 Z 轴，沿 X 轴转 180 度就合适了**」
	#    ⚠️ 中文有歧义，三种读法都要试，靠**数据**分辨是哪一种：
	#      ① 绕**世界 X** 转 180°      ← `R_x(π) · zp`
	#      ② 绕**模型 X** 转 180°（模型空间右乘）← `zp · R_x(π)`
	#      ③ 绕**模型 X** 转 180°（世界空间左乘，轴取 zp·X）← 与 ② 不同
	var rx := Basis.from_euler(Vector3(PI, 0, 0))
	var r1_world := (rx * bow_world).normalized()
	var r2_model := (zp * rx * bow_local).normalized()
	var r3_left := (zp * rx * zp.inverse() * bow_world).normalized()
	print("")
	print("  【用户目标三种读法】沿 X 轴转 180° 后的舰艏方向：")
	print("    ① 绕世界X左乘  R_x·zp      → %s" % _v(r1_world))
	print("    ② 绕模型X右乘  zp·R_x      → %s" % _v(r2_model))
	print("    ③ 世界轴左乘   zp·R_x·zp⁻¹ → %s" % _v(r3_left))

	# ── 穷举：6 个 bow 轴 × 各自 up 的合法正交解 ──
	print("")
	print("  候选（bow 轴 → 世界舰艏方向；与三种读法的差角）：")
	var axis_names := ["+X", "-X", "+Y", "-Y", "+Z", "-Z"]
	var axis_vecs := [Vector3(1,0,0), Vector3(-1,0,0), Vector3(0,1,0),
			Vector3(0,-1,0), Vector3(0,0,1), Vector3(0,0,-1)]
	var hits: Array = []
	for i in axis_names.size():
		var b: Vector3 = axis_vecs[i]
		# up 候选：与 b 正交的 4 个轴向里挑（红线 53a：舰艏轴 ⊥ 船背轴）
		for j in axis_names.size():
			if i == j:
				continue
			var u: Vector3 = axis_vecs[j]
			if absf(b.dot(u)) > 0.5:
				continue       # 必须正交
			# 构造 spec：把 (b,u) 反解成 AXIS_REMAP 的行语义
			var spec := _spec_for(b, u)
			if spec == "":
				continue
			# 姿态 = R_y(yaw) · M(spec) · mesh_rot，yaw 不变
			var m := _parse_remap(spec)
			var mesh_rot: Basis = EveShipVisual.mesh_rot_of(id)
			var zp2 := Basis.from_euler(Vector3(0, SIDE.extra_yaw(id), 0)) * m * mesh_rot
			var bw2 := (zp2 * b).normalized()
			var uw2 := (zp2 * u).normalized()
			var d1 := rad_to_deg(bw2.angle_to(r1_world))
			var d2 := rad_to_deg(bw2.angle_to(r2_model))
			var d3 := rad_to_deg(bw2.angle_to(r3_left))
			var mark := ""
			if d2 < 5.0:
				mark = "★②"
				hits.append("%s (bow:%s up:%s) — 绕模型X" % [spec, axis_names[i], axis_names[j]])
			elif d1 < 5.0:
				mark = "★①"
				hits.append("%s (bow:%s up:%s) — 绕世界X" % [spec, axis_names[i], axis_names[j]])
			elif d3 < 5.0:
				mark = "★③"
				hits.append("%s (bow:%s up:%s) — 世界轴左乘" % [spec, axis_names[i], axis_names[j]])
			print("    %-4s %-18s bow:%-3s up:%-3s → 舰艏 %s 船背 %s  Δ①%.0f° Δ②%.0f° Δ③%.0f°" % [
					mark, spec, axis_names[i], axis_names[j], _v(bw2), _v(uw2), d1, d2, d3])

	print("")
	if hits.is_empty():
		print("  ⚠ 没有候选能精确等于「沿 X 转 180°」—— 用户指的可能是"
				+ "「绕模型 X 轴」或含 up 一起变，需再确认")
	else:
		print("  ★ 匹配「沿 X 轴转 180°」的候选：")
		for h in hits:
			print("     · %s" % h)


## 「沿 X 轴转 180°」在 spec 层面的等价形式：
##   绕 X 轴 180° ⇒ `R_x(180°)` ⇒ 矩阵 [[1,0,0],[0,-1,0],[0,0,-1]]
##   ⇒ 对**行语义** spec：第 0 行不变、第 1 行翻号、第 2 行翻号。
##
## ⚠️ 这里只是给人工读的**提示**，真正判定上面走枚举（不靠这条）。
func _rot_x_180_of(spec: String) -> String:
	var toks := spec.split(",")
	if toks.size() != 3:
		return ""
	var out := PackedStringArray()
	out.append(toks[0])                                  # 第 0 行不变
	out.append(_flip(toks[1]))                           # 第 1 行翻号
	out.append(_flip(toks[2]))                           # 第 2 行翻号
	return ",".join(out)


func _flip(t: String) -> String:
	var s := t.strip_edges()
	if s.begins_with("-"):
		return "+" + s.substr(1)
	return "-" + s


## 把 (舰艏轴 b, 船背轴 u) 反解成 `AXIS_REMAP` 的 **行语义** spec。
##
## 行语义（红线 48b）：第 j 个 token = `M` 第 j 行 = 世界第 j 分量 ← 模型哪个分量。
## 我们要的 M 满足：`M · b = −Z`（舰艏朝敌）、`M · u = +Y`（船背朝天）。
## 第三行由前两行叉乘确定（右手系）。
##
## ⚠️ 为了让候选覆盖全，这里**不**假设 b/u 就是模型轴 —— 只把 b/u 当作
##    "把模型哪根轴定义为舰艏/船背"，M 由 `(b,u)` 直接构造：
##        M⁻¹ = P = Basis(b, u, l)   (列 = 三根轴)  ⇒  M = Pᵀ，再取标准基映射。
func _spec_for(b: Vector3, u: Vector3) -> String:
	# 用 `_make_align` 的同一数学（生产函数，零复刻）
	var c := EveShipVisual._make_align(b, u)
	# c 把 b→−Z、u→+Y。
	# ⚠️ 行语义（红线 48b）：`Basis` 的 `x`/`y`/`z` **属性就是三行**
	#    （Godot 的 `basis.x` 是第 0 行，不是第 0 列 —— 这点与"基向量=列"的
	#     直觉相反，但 `Basis(rows...)` 构造 + `.x` 读回的实测行为如此）。
	#    → 43 轮起本工程统一按「`x` = 第 0 行」处理，spec token 依次取 x/y/z。
	var rows := PackedStringArray()
	rows.append(_row_token(c.x))
	rows.append(_row_token(c.y))
	rows.append(_row_token(c.z))
	return ",".join(rows)


## 把一行（3 个 -1/0/1 分量）写成 spec token，如 `-X` / `+Y` / `+Z`。
func _row_token(row: Vector3) -> String:
	var ax := ["X", "Y", "Z"]
	var best := 0
	var bestv := 0.0
	for i in 3:
		var a := absf(row[i])
		if a > bestv:
			bestv = a
			best = i
	var sign := "+"
	if row[best] < 0.0:
		sign = "-"
	return sign + ax[best]


func _parse_remap(spec: String) -> Basis:
	var toks := spec.split(",")
	var rows: Array[Vector3] = []
	for t in toks:
		var s := t.strip_edges()
		var neg := s.begins_with("-")
		var ch := s.substr(1, 1).to_upper()
		var v := Vector3.ZERO
		match ch:
			"X": v = Vector3(1, 0, 0)
			"Y": v = Vector3(0, 1, 0)
			"Z": v = Vector3(0, 0, 1)
		if neg:
			v = -v
		rows.append(v)
	return Basis(rows[0], rows[1], rows[2])


func _remap_str(id: StringName) -> String:
	var lines := FileAccess.get_file_as_string("res://scripts/data/eve_ship_yaw.gd")
	for ln in lines.split("\n"):
		if ln.contains("\"%s\":" % String(id)) and ln.contains("\"+"):
			var p := ln.find("\"")
			var q := ln.find("\"", p + 1)
			if p >= 0 and q > p:
				return ln.substr(p + 1, q - p - 1)
	return "?"


func _axes_str(id: StringName) -> String:
	var lines := FileAccess.get_file_as_string("res://scripts/data/eve_ship_yaw.gd")
	for ln in lines.split("\n"):
		if ln.contains("\"%s\":" % String(id)) and ln.contains("bow:"):
			var p := ln.find("\"")
			var q := ln.find("\"", p + 1)
			if p >= 0 and q > p:
				return ln.substr(p + 1, q - p - 1)
	return "?"


func _v(v: Vector3) -> String:
	return "(%.2f,%+.2f,%+.2f)" % [v.x, v.y, v.z]
