extends Node
## ══════════════════════════════════════════════════════════════════════
##  47 轮 · **穷举坐实 `AXIS_REMAP` 序列化方向**（彻底不推）
## ══════════════════════════════════════════════════════════════════════
##
## ── 为什么要穷举 ══════════════════════════════════════════════════════
##  前一条 `probe_specdir47` 用的测试矩阵**恰好对称**（行 == 列），
##  两种取法给出同一个 spec ⇒ **区分不出来**。
##  30+ 艘 diag 型 spec 正是这么"看起来没问题"骗过好几轮的。
##
## ── 做法 ═════════════════════════════════════════════════════════════
##  取一个**非对称**的旋转矩阵 m，然后：
##    ① 枚举全部 48 个合法 spec（3! × 2³ 符号），用**生产解析器**读回；
##    ② 找出读回 == m 的那个 spec —— 那就是"生产代码认的写法"；
##    ③ 再验证「用 `m[r]`（行）拼出来的 spec」与它是否相同。
##
##  ⚠️ 这一步必须做：`probe_remap47` 要用它写 52 行新表，
##     写反了 = 全库倒飞，而且不报错（44 轮原样踩过）。
##
## 跑法：
##   `--headless --path <工程> --quit-after 300 res://tools/probe_specbrute47.tscn`
const YAW := preload("res://scripts/data/eve_ship_yaw.gd")

const AXT := ["+X", "-X", "+Y", "-Y", "+Z", "-Z"]

func _ready() -> void:
	print("═══ 47 轮 · 穷举坐实 spec 序列化方向 ═══")
	# ★ 决定性：构造**真正非对称**的矩阵（含轴交换 + 符号翻转）。
	#   绕 (1,1,0) 转 120° 恰好对称（列==行），区分不出 —— 换掉。
	#   用三根轴分别映射到不同轴的**置换型**：x→+Y, y→−Z, z→+X
	#   （行与列必然不同：列 = [±Y,±Z,±X] 的逆置换）
	var m := Basis(
		Vector3(0, 1, 0),    # 列0：目标 x 轴映射到 +Y
		Vector3(0, 0, -1),   # 列1：目标 y 轴映射到 −Z
		Vector3(1, 0, 0))    # 列2：目标 z 轴映射到 +X
	m = m.orthonormalized()
	print("  目标矩阵 m：")
	print("    列 x=%s y=%s z=%s" % [_v(m.x), _v(m.y), _v(m.z)])
	print("    行 r0=%s r1=%s r2=%s" % [_v(m[0]), _v(m[1]), _v(m[2])])
	print("    转置列 t.x=%s t.y=%s t.z=%s"
			% [_v(m.transposed().x), _v(m.transposed().y), _v(m.transposed().z)])
	print("    逆矩阵列 i.x=%s i.y=%s i.z=%s"
			% [_v(m.inverse().x), _v(m.inverse().y), _v(m.inverse().z)])

	# ① 枚举 48 个 spec，找读回 == m 的
	var hits: Array[String] = []
	for i in 6:
		for j in 6:
			for k in 6:
				var sp := "%s,%s,%s" % [AXT[i], AXT[j], AXT[k]]
				var b: Basis = YAW.parse_axis_remap(sp)
				if _same(b, m):
					hits.append(sp)
	print("  ① 读回 == m 的 spec：%s" % (", ".join(hits) if hits.size() > 0 else "（无）"))

	# ② 用「行」拼的 spec 与它比
	var spec_rows := "%s,%s,%s" % [_t(m[0]), _t(m[1]), _t(m[2])]
	var spec_cols := "%s,%s,%s" % [_t(m.x), _t(m.y), _t(m.z)]
	print("  ② 取行拼出 = %s ；取列拼出 = %s" % [spec_rows, spec_cols])
	print("     行拼出的在命中集里？ %s" % ("★ 是" if spec_rows in hits else "否"))
	print("     列拼出的在命中集里？ %s" % ("★ 是" if spec_cols in hits else "否"))

	# ③ 反过来：随机几个非对称矩阵，验证「取行」永远能命中
	var bad := 0
	for t in 12:
		var mm := Basis(Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5).normalized(),
				deg_to_rad(90.0)).orthonormalized()
		var sr := "%s,%s,%s" % [_t(mm[0]), _t(mm[1]), _t(mm[2])]
		var back: Basis = YAW.parse_axis_remap(sr)
		if not _same(back, mm):
			bad += 1
	print("  ③ 随机 12 个非对称矩阵：」取行」拼 spec 读回不一致 %d 个" % bad)
	print("  ⇒ 结论：spec 应当取 **%s**"% (
			"行" if bad == 0 else "列（取行不行）"))
	get_tree().quit(0)


func _same(a: Basis, b: Basis) -> bool:
	for r in 3:
		if a[r].distance_to(b[r]) > 0.01:
			return false
	return true


func _t(v: Vector3) -> String:
	var ax := 0
	var best := -1.0
	for i in 3:
		if absf(v[i]) > best:
			best = absf(v[i])
			ax = i
	return "%s%s" % [("+" if v[ax] >= 0.0 else "-"), "XYZ"[ax]]


func _v(v: Vector3) -> String:
	return "[%+.2f,%+.2f,%+.2f]" % [v.x, v.y, v.z]
