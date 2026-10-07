extends Node
## 48 轮 · 打印 `algos`/`catalyst`/`myrmidon` 的 M 矩阵与拆 spec 的中间值。
const YAW := preload("res://scripts/data/eve_ship_yaw.gd")
const IDS := ["algos", "catalyst", "myrmidon", "abaddon"]


func _ready() -> void:
	print("═══ 3 艘的 M 矩阵解剖 ═══")
	for id in IDS:
		var sid := StringName(id)
		var mr: Basis = EveShipVisual.mesh_rot_of(sid)
		var bow: Vector3 = YAW.bow_axis(sid)
		var up: Vector3 = YAW.up_axis(sid)
		var side_m: Vector3 = bow.cross(up).normalized()
		var T := Basis(Vector3(0, 0, -1), Vector3(0, 1, 0), Vector3(1, 0, 0))
		var S := Basis(mr * bow, mr * up, mr * side_m)
		var m: Basis = T * S.inverse()
		print("── %s ──" % id)
		print("   mesh_rot = [%s | %s | %s]" % [_v(mr.x), _v(mr.y), _v(mr.z)])
		print("   bow=%s up=%s side_m=%s" % [_v(bow), _v(up), _v(side_m)])
		print("   S(列)    = [%s | %s | %s]" % [_v(S.x), _v(S.y), _v(S.z)])
		print("   M(列)    = [%s | %s | %s]" % [_v(m.x), _v(m.y), _v(m.z)])
		# 按列拆 spec
		var spec_col := ""
		for i in 3:
			spec_col += _tok(m[i]) + ("," if i < 2 else "")
		var spec_row := ""
		for i in 3:
			spec_row += _tok(Vector3(m[0][i], m[1][i], m[2][i])) + ("," if i < 2 else "")
		print("   按【列】拆 = %s" % spec_col)
		print("   按【行】拆 = %s" % spec_row)
		print("   装回列版 = [%s|%s|%s]" % [_v(YAW.parse_axis_remap(spec_col).x),
				_v(YAW.parse_axis_remap(spec_col).y), _v(YAW.parse_axis_remap(spec_col).z)])
		print("")
	get_tree().quit(0)


func _tok(v: Vector3) -> String:
	var ax := 0
	var best := -1.0
	for i in 3:
		if absf(v[i]) > best:
			best = absf(v[i])
			ax = i
	return ("+" if v[ax] >= 0.0 else "-") + "XYZ"[ax]


func _v(v: Vector3) -> String:
	return "(%+.2f,%+.2f,%+.2f)" % [v.x, v.y, v.z]
