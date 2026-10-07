extends Node
## 48 轮 · **姿态表是否把船翻了的仲裁探针**。
##
## ═══ 问题 ═══
##  用户实机：「船全部肚皮朝天」——**统一方向**的翻转（背朝下），不是逐艘各异。
##  `SHIP_AXES` 已与用户工具 `pose_table.json` 逐条核对**完全一致** ⇒ 表值无罪。
##  ⇒ 只能是 `AXIS_REMAP`（姿态 M）把 up 送到了 −Y（翻了 180°）。
##
## ═══ 判据（红线 40：只用引擎算的世界量，不用任何表的自洽性）═══
##  对每艘船，独立算三条**真值链**：
##    ① `zero_pose_basis(id)` —— 生产函数，端到端
##    ② `Basis.from_euler(0,extra,0) * axis_remap(id) * mesh_rot_of(id)` —— 手工拼
##    两者必须逐位相同（否则说明生产函数里有别的东西）。
##  再算 `f·up_model` 与 `(0,1,0)` 的点积与夹角：
##    `+1.000` = 船背朝天 ✔ ； `−1.000` = **肚皮朝天** ✗
##
##  ⚠️ 关键：这里的 `up_model` 取自 `pose_table.json`（**用户工具标定**），
##     不是我推的、不是从 M 反解的 ⇒ 基准独立。
const YAW := preload("res://scripts/data/eve_ship_yaw.gd")

const IDS := ["abaddon", "catalyst", "kestrel", "slasher", "inquisitor",
		"myrmidon", "tristan", "algos", "omen", "burst"]


func _ready() -> void:
	print("═══ 48 轮 · 姿态表仲裁（up 到底朝天还是朝地）═══")
	print("")
	print("  %-12s | zero_pose·up      dot(天) | axremap·up       dot(天) | 一致? | 判" % "ship")
	var flip := 0
	var total := 0
	for id in IDS:
		var sid := StringName(id)
		var mr: Basis = EveShipVisual.mesh_rot_of(sid)
		var up: Vector3 = YAW.up_axis(sid)
		# ① 生产函数
		var zp: Basis = EveShipVisual.zero_pose_basis(sid)
		var u1: Vector3 = (zp * up).normalized()
		# ② 手工拼（独立复刻 —— 只为交叉校验生产函数，判据仍用 ①）
		var man: Basis = Basis.from_euler(Vector3(0, YAW.extra_yaw(sid), 0)) \
				* YAW.axis_remap(sid) * mr
		var u2: Vector3 = (man * up).normalized()
		var same: bool = u1.distance_to(u2) < 0.0001
		var d1: float = u1.dot(Vector3.UP)
		var verdict := "背朝天 ✔" if d1 > 0.5 else ("**肚皮朝天** ✗" if d1 < -0.5 else "侧躺 ✗")
		total += 1
		if d1 < 0.5:
			flip += 1
		print("  %-12s | (%+.2f,%+.2f,%+.2f) %+.3f | (%+.2f,%+.2f,%+.2f) %+.3f |  %s  | %s"
				% [id, u1.x, u1.y, u1.z, d1, u2.x, u2.y, u2.z, u2.dot(Vector3.UP),
				   ("✔" if same else "✗"), verdict])
	print("")
	print("  ── %d 艘中 %d 艘船背没朝天 ──" % [total, flip])
	# ── 关键对照：把 M 的第 2 行符号翻掉会怎样 ──
	print("")
	print("  ── 对照：M 第 2 行翻号（−Y → +Y）后的 up·天 ──")
	for id in IDS:
		var sid2 := StringName(id)
		var mr2: Basis = EveShipVisual.mesh_rot_of(sid2)
		var up2: Vector3 = YAW.up_axis(sid2)
		var m_bad: Basis = YAW.axis_remap(sid2)
		# 翻第 2 行
		var m_new := Basis(m_bad.x, -m_bad.y, m_bad.z)
		var f2: Basis = Basis.from_euler(Vector3(0, YAW.extra_yaw(sid2), 0)) * m_new * mr2
		var uu: Vector3 = (f2 * up2).normalized()
		var bb: Vector3 = (f2 * YAW.bow_axis(sid2)).normalized()
		print("  %-12s up·天 %+.3f | bow %s | det %+.2f"
				% [id, uu.dot(Vector3.UP), _v3(bb), m_new.determinant()])
	get_tree().quit(0)


func _v3(v: Vector3) -> String:
	return "(%+.2f,%+.2f,%+.2f)" % [v.x, v.y, v.z]
