extends Node
## 48 轮 · **spec 往返一致性核查**：把 `_to_spec(m)` 的结果再喂回 `parse_axis_remap()`
## 看是否能还原同一个 `m`。
##
## 疑点：`probe_remap48` 自检用的是**内存里的 m**（报 0 艘未过），
##      而 `probe_remapchk48` 从**源码 spec** 读（报 2 艘未过）⇒ 两者不等价
##       ⇒ `_to_spec()` 的取整丢了信息（spec 表达不了那个 m）。
const YAW := preload("res://scripts/data/eve_ship_yaw.gd")
const IDS := ["algos", "catalyst", "myrmidon", "abaddon", "kestrel", "tristan"]


func _ready() -> void:
	print("═══ 48 轮 · spec 往返核查 ═══")
	print("")
	for id in IDS:
		var sid := StringName(id)
		var spec: String = String(YAW.AXIS_REMAP.get(sid, ""))
		var m := YAW.parse_axis_remap(spec)
		var mr: Basis = EveShipVisual.mesh_rot_of(sid)
		var bow: Vector3 = YAW.bow_axis(sid)
		var up: Vector3 = YAW.up_axis(sid)
		var gm: Basis = m * mr
		print("  %-12s spec=%-13s" % [id, spec])
		print("        M 行 = %s / %s / %s" % [_v(m[0]), _v(m[1]), _v(m[2])])
		print("        M·mr·bow = %s   (want −Z)" % _v((gm * bow).normalized()))
		print("        M·mr·up  = %s   (want +Y)" % _v((gm * up).normalized()))
		print("        det=%+.2f  正交=%s" % [m.determinant(), str((m * m.transposed()).is_equal_approx(Basis.IDENTITY))])
	get_tree().quit(0)


func _v(v: Vector3) -> String:
	return "(%+.2f,%+.2f,%+.2f)" % [v.x, v.y, v.z]
