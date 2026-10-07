extends Node
## 44 轮交叉对账：把 Godot 真代码的中间量**逐项打印**，与 Python 独立复算对比。
## 目的：定位「Godot 说 52/52 朝敌」vs「Python 说 48/52 背敌」的矛盾。
## ⚠️ 只读，不写任何表。
const YAW := preload("res://scripts/data/eve_ship_yaw.gd")
const IDX := preload("res://scripts/data/eve_ship_asset_index.gd")

func _ready() -> void:
	print("═══ 44 轮交叉对账（真代码中间量）═══")
	var ids: Array = ["abaddon", "kestrel", "burst", "armageddon", "algos", "catalyst", "myrmidon", "tristan"]
	for sid_s in ids:
		var sid := StringName(sid_s)
		var M: Basis = YAW.axis_remap(sid)
		var bow_m: Vector3 = YAW.bow_axis(sid)
		var up_m: Vector3 = YAW.up_axis(sid)
		var ey: float = YAW.extra_yaw(sid)
		var yaw: float = -PI / 2.0 + ey
		var R := Basis.from_euler(Vector3(0.0, yaw, 0.0))
		var Rs := R * M
		print("--- %s  spec=%s  SHIP_AXES=%s" % [sid_s, _spec_of(sid_s), _axes_str_of(sid_s)])
		print("     M = %s" % _bstr(M))
		print("     bow_model=%s up_model=%s extra_yaw=%.4f" % [str(bow_m), str(up_m), ey])
		print("     R_y(%.2f°) = %s" % [rad_to_deg(yaw), _bstr(R)])
		print("     M·bow_model=%-28s  R·M·bow_model=%s" % [str(M * bow_m), str(Rs * bow_m)])
		print("     M·up_model =%-28s  R·M·up_model =%s" % [str(M * up_m), str(Rs * up_m)])

	# 全库统计（真代码）
	var cnt := {}
	var bad: PackedStringArray = PackedStringArray()
	for s in IDX.all():
		var sid2 := StringName(s.id)
		var M2: Basis = YAW.axis_remap(sid2)
		var yaw2: float = -PI / 2.0 + YAW.extra_yaw(sid2)
		var R2 := Basis.from_euler(Vector3(0.0, yaw2, 0.0)) * M2
		var w := (R2 * YAW.bow_axis(sid2)).normalized()
		var key := "%d,%d,%d" % [roundi(w.x), roundi(w.y), roundi(w.z)]
		cnt[key] = int(cnt.get(key, 0)) + 1
		if w.dot(Vector3(0, 0, -1)) < 0.99:
			bad.append("%s(%s)" % [String(s.id), key])
	print("═══ 全库 52 艘 · R·M·bow 世界方向分布 = %s" % str(cnt))
	print("═══ 非朝敌 %d 艘：%s" % [bad.size(), ", ".join(bad) if bad.size() > 0 else "无"])
	get_tree().quit()


func _bstr(b: Basis) -> String:
	return "[X:%s Y:%s Z:%s]" % [str(b.x.snappedf(0.01)), str(b.y.snappedf(0.01)), str(b.z.snappedf(0.01))]


func _spec_of(id: String) -> String:
	return String(YAW.AXIS_REMAP.get(StringName(id), "—"))


func _axes_str_of(id: String) -> String:
	return String(YAW.SHIP_AXES.get(StringName(id), "—"))
