extends Node
## ══════════════════════════════════════════════════════════════════════
##  47 轮 · **坐实 `AXIS_REMAP` 的序列化方向**（不推，靠枚举实测）
## ══════════════════════════════════════════════════════════════════════
##
## ── 为什么不再纸上推 ══════════════════════════════════════════════════
##  44 轮就栽过："纸上按『第 i 个 token = 矩阵第 i 行』建模，
##  真代码构造时多转置一次" ⇒ 差一个转置、不报错、船倒着飞。
##  `probe_remap47` 的往返自检已经**实测到**写出的 spec 读回来不一致，
##  所以现在改用**枚举对拍**定它的真方向。
##
## ── 做法 ═════════════════════════════════════════════════════════════
##  我自己算出的旋转矩阵 `m`（列式）。要给出一个 spec，使得
##  `parse_axis_remap(spec) == m`。未知 = spec 该取 `m` 的行还是列。
##  两个候选都试，用**生产解析器**读回来比对，谁对用谁。
##
## 跑法：
##   `--headless --path <工程> --quit-after 600 res://tools/probe_specdir47.tscn`
const YAW := preload("res://scripts/data/eve_ship_yaw.gd")

## 一个非对称、可区分的测试矩阵（每行/列端点都不同，转置一定露馅）
const TEST_SPECS := ["+Y,-X,+Z", "-X,-Y,+Z", "+Z,-Y,+X", "-Z,+Y,-X"]

func _ready() -> void:
	print("═══ 47 轮 · AXIS_REMAP 序列化方向对拍 ═══")
	for sp in TEST_SPECS:
		var b: Basis = YAW.parse_axis_remap(sp)
		print("  spec %-12s → 行: [%s] [%s] [%s]"
				% [sp, _v(b[0]), _v(b[1]), _v(b[2])])
		print("                列: [%s] [%s] [%s]"
				% [_v(b.x), _v(b.y), _v(b.z)])

	# ★ 决定性判定：拿一个已知矩阵 m，用两种候选序列化，看哪个能被读回 m
	print("\n── 判定：spec 到底该取「行」还是「列」──")
	var m := Basis(
		Vector3(0, 0, -1),   # 列0
		Vector3(0, 1, 0),    # 列1
		Vector3(1, 0, 0))    # 列2
	# 候选 A：spec token = m 的行
	var spec_rows := "%s,%s,%s" % [_t(m[0]), _t(m[1]), _t(m[2])]
	# 候选 B：spec token = m 的列
	var spec_cols := "%s,%s,%s" % [_t(m.x), _t(m.y), _t(m.z)]
	for cand in [["A 取行", spec_rows], ["B 取列", spec_cols]]:
		var back: Basis = YAW.parse_axis_remap(String(cand[1]))
		var same := true
		for r in 3:
			if back[r].distance_to(m[r]) > 0.001:
				same = false
		print("  %s spec=%-12s 读回==m ? %s" % [cand[0], cand[1], ("★ 是" if same else "否")])
	get_tree().quit(0)


func _t(v: Vector3) -> String:
	var ax := 0
	var best := -1.0
	for i in 3:
		if absf(v[i]) > best:
			best = absf(v[i])
			ax = i
	return "%s%s" % [("+" if v[ax] >= 0.0 else "-"), "XYZ"[ax]]


func _v(v: Vector3) -> String:
	return "%+.0f,%+.0f,%+.0f" % [v.x, v.y, v.z]
