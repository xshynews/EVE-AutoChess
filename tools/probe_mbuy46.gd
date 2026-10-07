extends Node
## 46 轮：对拍「C 是否吸收 geo」两种写法，判据 = 舰艏与目标方向夹角。
const YAW := preload("res://scripts/data/eve_ship_yaw.gd")
const IDX := preload("res://scripts/data/eve_ship_asset_index.gd")

func _ready() -> void:
	var bad_old := 0
	var bad_new := 0
	var n := 0
	for sh in IDX.all():
		var sid := StringName(sh.id)
		var bow_local: Vector3 = YAW.bow_axis(sid)
		var up_local: Vector3 = YAW.up_axis(sid)
		var yaw := -PI / 2.0 + YAW.extra_yaw(sid)
		var M: Basis = YAW.axis_remap(sid)
		var geo := Basis.from_euler(Vector3(0, yaw, 0)) * M
		var C := _make_align(geo * bow_local, geo * up_local)
		var f := Vector3(0, 0, -1)
		var L := Basis.looking_at(f, Vector3.UP)
		# 旧：C 不吸收 geo，运行时乘 bow_local ⇒ 空间不匹配
		var old_bow: Vector3 = (L * C * bow_local).normalized()
		# 新：C' = C·geo，运行时乘 bow_local
		var new_bow: Vector3 = (L * C * geo * bow_local).normalized()
		n += 1
		if old_bow.dot(f) < 0.99: bad_old += 1
		if new_bow.dot(f) < 0.99: bad_new += 1
	print("全库 %d 艘：旧(C 不吸收 geo) 不朝敌 %d · 新(C'=C·geo) 不朝敌 %d" % [n, bad_old, bad_new])
	get_tree().quit(0)

static func _make_align(bow0: Vector3, up0: Vector3) -> Basis:
	var b := bow0.normalized()
	var u := up0 - b * b.dot(up0)
	if u.length_squared() < 1e-8:
		u = Vector3.UP - b * b.dot(Vector3.UP)
		if u.length_squared() < 1e-8:
			u = Vector3(0,0,1) - b * b.dot(Vector3(0,0,1))
	u = u.normalized()
	var l := b.cross(u).normalized()
	var p := Basis(b, u, l)
	var q := Basis(Vector3(0,0,-1), Vector3(0,1,0), Vector3(1,0,0))
	return q * p.transposed()
