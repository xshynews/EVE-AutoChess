extends SceneTree

const DB := preload("res://scripts/core/eve_ship_database.gd")

func _init() -> void:
	var bad := 0
	for d in DB.all_ships():
		var is_logi := bool(d.get("is_logistics", false))
		var cyc := float(d.get("weapon_cycle", 1.0))
		var dps := float(d.get("weapon_damage", 0.0)) / maxf(0.001, cyc)
		var expect := float(d.get("attack", 0.0))
		if is_logi:
			continue		# 后勤船用低位自卫火力，是刻意设计
		if absf(dps - expect) > 0.01:
			bad += 1
			print("  偏差 %s dps=%.2f expect=%.2f" % [d.get("name_cn","?"), dps, expect])
	print("DPS 守恒（非后勤）: %d 艘不一致（应为 0）" % bad)
	var n := 0
	for d in DB.all_ships():
		if not bool(d.get("is_logistics", false)):
			continue
		n += 1
		if n <= 2:
			var cy2 := float(d.get("weapon_cycle", 1.0))
			print("  后勤 %s: 权威 attack=%.0f, 战斗 DPS=%.1f" % [d.get("name_cn","?"), float(d.get("attack",0.0)), float(d.get("weapon_damage",0.0)) / maxf(0.001, cy2)])
	print("后勤船共 %d 艘（刻意压低自卫火力）" % n)
	quit(0)