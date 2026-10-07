extends Node
const YAW := preload("res://scripts/data/eve_ship_yaw.gd")

func _ready() -> void:
	for id_v in ["burst", "catalyst", "myrmidon", "inquisitor", "kestrel", "slasher"]:
		var id := StringName(id_v)
		var M := YAW.axis_remap(id)
		var MODEL_YAW_FIX := -PI / 2.0
		var yaw := MODEL_YAW_FIX + YAW.extra_yaw(id)
		var base := Basis.from_euler(Vector3(0.0, yaw, 0.0)) * M
		var bow_local := YAW.bow_axis(id)
		var up_local := YAW.up_axis(id)
		var bow0 := (base * bow_local).normalized()
		var up0 := (base * up_local).normalized()
		print("[", id_v, "] in_FLIP=", id_v in YAW.FLIP, " extra_yaw(deg)=", rad_to_deg(YAW.extra_yaw(id))-rad_to_deg(MODEL_YAW_FIX), "  bow0=", bow0, "  up0=", up0, "  dot(-Z)=", bow0.dot(Vector3(0,0,-1)))
	get_tree().quit(0)
