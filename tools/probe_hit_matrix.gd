extends SceneTree

const CORE := preload("res://scripts/core/eve_combat_core.gd")
const DB := preload("res://scripts/core/eve_ship_database.gd")
const CIDS := preload("res://scripts/core/eve_combat_ids.gd")

const COSTS := [1, 2, 3, 4, 5]
const NAMES := {1: "护卫", 2: "驱逐", 3: "巡洋", 4: "战巡", 5: "战列"}

func _init() -> void:
	var rep := {}
	for d in DB.all_ships():
		if String(d.get("weapon_id", "")) != String(CIDS.W_LASER):
			continue
		var c: int = d.get("cost", 0)
		if not rep.has(c):
			rep[c] = d
	var CMS: float = DB.CELL_METERS
	var SS: float = DB.SPEED_SCALE
	var dist := 9000.0
	var head := PackedStringArray()
	for c in COSTS:
		head.append(NAMES[c])
	print("基础命中率矩阵（9000m · 非环绕）")
	print("      " + "   ".join(head))
	for a in COSTS:
		if not rep.has(a):
			continue
		var da: Dictionary = rep[a]
		var row := PackedStringArray()
		for t in COSTS:
			if not rep.has(t):
				row.append("   -  ")
				continue
			var dt: Dictionary = rep[t]
			var va := float(da.get("speed_cells", 0.0)) * CMS * SS
			var vt := float(dt.get("speed_cells", 0.0)) * CMS * SS
			var ang := (va + vt) / dist
			var rr: Dictionary = CORE.turret_chance_to_hit(
					float(da.get("optimal_range", 0.0)), float(da.get("falloff", 0.0)),
					float(da.get("tracking", 0.0)), float(da.get("signature_resolution", 0.0)),
					float(dt.get("signature", 0.0)), float(da.get("optimal_range", 0.0)), ang,
					a - t, false)
			row.append("%5.0f%%" % (float(rr["chance"]) * 100.0))
		print(NAMES[a] + "  " + "   ".join(row))
	print("")
	print("环绕阵型下的矩阵（应全部 -20% 相对值）")
	print("      " + "   ".join(head))
	for a in COSTS:
		if not rep.has(a):
			continue
		var db: Dictionary = rep[a]
		var row2 := PackedStringArray()
		for t in COSTS:
			if not rep.has(t):
				row2.append("   -  ")
				continue
			var dc: Dictionary = rep[t]
			var va2 := float(db.get("speed_cells", 0.0)) * CMS * SS
			var vt2 := float(dc.get("speed_cells", 0.0)) * CMS * SS
			var ang2 := (va2 + vt2) / dist
			var r2: Dictionary = CORE.turret_chance_to_hit(
					float(db.get("optimal_range", 0.0)), float(db.get("falloff", 0.0)),
					float(db.get("tracking", 0.0)), float(db.get("signature_resolution", 0.0)),
					float(dc.get("signature", 0.0)), float(db.get("optimal_range", 0.0)), ang2,
					a - t, true)
			row2.append("%5.0f%%" % (float(r2["chance"]) * 100.0))
		print(NAMES[a] + "  " + "   ".join(row2))
	quit(0)