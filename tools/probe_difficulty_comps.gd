extends Node
## 逐节点对比四个难度的敌方编组 / 规模 / 强度倍率。
##
## 为什么要有它：扫荡报表里「困难」和「炼狱」成绩一模一样，
## 用户怀疑是 bug。这个探针直接读**数据表**给出权威答案，
## 不用真的去打一局（打一局还受机器人强度干扰）。
##
## 跑法：
##   "$GODOT_BIN" --headless --path . res://tools/probe_difficulty_comps.tscn

const RUN := preload("res://scripts/core/eve_run_state.gd")
const TIERS := preload("res://scripts/data/eve_campaign_tiers.gd")

func _ready() -> void:
	var rows: Array[String] = []
	rows.append("节点 | " + " | ".join(TIERS.difficulties().map(func(d): return String(d["name"]))))
	var comp := {}
	var size := {}
	var scale := {}
	for d in TIERS.difficulties():
		var r := RUN.new()
		r.start_run(12345)
		r.set_difficulty(String(d["id"]))
		var c: Array[String] = []
		var s: Array[String] = []
		var k: Array[String] = []
		for n in range(1, EveNodeTable.TOTAL + 1):
			# 直接按节点号取（run 内部就是查表，不走战斗）
			r.node_index = n
			c.append("%s×%d" % [r.enemy_comp_id(), r.enemy_comp_size()])
			s.append("%.2f" % r.enemy_scale())
			k.append("" if r.key_mechanic() == "" else r.key_mechanic())
		comp[String(d["id"])] = c
		size[String(d["id"])] = s
		scale[String(d["id"])] = k

	for n in range(EveNodeTable.TOTAL):
		var line := "节点 %2d | " % (n + 1)
		for d in TIERS.difficulties():
			var id := String(d["id"])
			var mech := String(scale[id][n])
			line += "%s %s%s | " % [comp[id][n], size[id][n], " [" + mech + "]" if mech != "" else ""]
		rows.append(line)

	for l in rows:
		print(l)
	var f := FileAccess.open("user://difficulty_comps.txt", FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(rows))
		f.close()
	print("[SHOT] " + ProjectSettings.globalize_path("user://difficulty_comps.txt"))
	get_tree().quit()
