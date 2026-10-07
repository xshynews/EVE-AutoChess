extends Node
## 48 轮 · **Godot Basis 取值语义**最终确认（一次问清，别再来回猜）。
const YAW := preload("res://scripts/data/eve_ship_yaw.gd")


func _ready() -> void:
	print("═══ Godot Basis 语义实测 ═══")
	var spec := "+Y,+Z,+X"
	var m := YAW.parse_axis_remap(spec)
	print("spec = %s" % spec)
	print("  m.x (第0列) = %s" % _v(m.x))
	print("  m.y (第1列) = %s" % _v(m.y))
	print("  m.z (第2列) = %s" % _v(m.z))
	print("  m[0]        = %s" % _v(m[0]))
	print("  m[1]        = %s" % _v(m[1]))
	print("  m[2]        = %s" % _v(m[2]))
	print("")
	# 用"喂单位向量看输出"这个**不可争辩**的方式确认 M 的语义
	print("  行为检验（M·v 的结果 = v 的像）：")
	for tok in ["+X", "-X", "+Y", "-Y", "+Z", "-Z"]:
		var v: Vector3 = YAW._axis_vec(tok)
		print("    M · %-3s = %s" % [tok, _v(m * v)])
	print("")
	print("  ⇒ 对比上面 m[0..2]，确认 spec token i 与 M 第 i 行的关系")
	get_tree().quit(0)


func _v(v: Vector3) -> String:
	return "(%+.0f,%+.0f,%+.0f)" % [v.x, v.y, v.z]
