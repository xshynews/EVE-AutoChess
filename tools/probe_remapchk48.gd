extends Node
## 48 轮 · **验证 `_solve_spec` 自己的判据是否真的被满足**。
##
## 疑点：`AXIS_REMAP` 里 45 艘是 `+Z,-Y,+X` ⇒ 第 2 行 = `-Y`
##       ⇒ `M` 把模型的某根轴映到世界 `−Y`。
## 而 `_solve_spec` 要求 `f·up = +Y`，其中 `f = R_y(extra)·M·mesh_rot`。
## ⚠️ `R_y` 绕 Y 轴转 ⇒ **改不动 Y 分量** ⇒ `f·up` 的 Y 分量 ≡ `(M·mesh_rot·up).y`
##    ⇒ 判据要成立，必须 `M·mesh_rot·up = +Y`。
## 本探针直接复算这条：若结果不是 +Y，则 47 轮的重算器**判据与产物不自洽**。
const YAW := preload("res://scripts/data/eve_ship_yaw.gd")
const IDS := ["abaddon", "catalyst", "kestrel", "slasher", "inquisitor",
		"myrmidon", "tristan", "algos", "omen", "burst", "dominix", "raven",
		"apocalypse", "maelstrom", "tempest"]


func _ready() -> void:
	print("═══ 48 轮 · AXIS_REMAP 自洽性核查 ═══")
	print("")
	print("  %-12s | spec        | Mr·up            | Mr·bow           | M·Mᵀ≈I | det" % "ship")
	var bad_up := 0
	for id in IDS:
		var sid := StringName(id)
		var m: Basis = YAW.axis_remap(sid)
		var mr: Basis = EveShipVisual.mesh_rot_of(sid)
		var up: Vector3 = YAW.up_axis(sid)
		var bow: Vector3 = YAW.bow_axis(sid)
		var mm: Basis = m * mr
		var mu: Vector3 = (mm * up).normalized()
		var mb: Vector3 = (mm * bow).normalized()
		var ortho: bool = (m * m.transposed()).is_equal_approx(Basis.IDENTITY)
		var du: float = mu.dot(Vector3.UP)
		if du < 0.99:
			bad_up += 1
		print("  %-12s | %-11s | %s %+.3f | %s |  %s  | %+.2f"
				% [id, YAW.AXIS_REMAP.get(sid, "?"), _v(mu), du, _v(mb),
				   ("✔" if ortho else "✗"), m.determinant()])
	print("")
	print("  ── M·mesh_rot·up 不是 +Y 的船：%d / %d ──" % [bad_up, IDS.size()])
	print("  （若 >0 ⇒ 47 轮重算器的判据「f·up=+Y」与产物不自洽）")
	get_tree().quit(0)


func _v(v: Vector3) -> String:
	return "(%+.2f,%+.2f,%+.2f)" % [v.x, v.y, v.z]
