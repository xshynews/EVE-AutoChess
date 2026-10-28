extends Node

const MATCH := preload("res://scripts/core/eve_match_state.gd")
const PLAYER := preload("res://scripts/core/eve_match_player.gd")

func _ready() -> void:
	print("=== 名次结算规则验证 ===")
	# 造 4 个玩家：2 存活（不同 hp）+ 2 淘汰
	var ps: Array = []
	var a = PLAYER.new(null, "你", false); a.hp = 42; ps.append(a)
	var b = PLAYER.new(null, "AI-铁猫", true); b.hp = 88; ps.append(b)
	var c = PLAYER.new(null, "AI-秃鹫", true); c.hp = 0; c.eliminated = true; ps.append(c)
	var d = PLAYER.new(null, "AI-巨像", true); d.hp = 12; d.eliminated = true; ps.append(d)
	var m = MATCH.new(ps, 1)
	m.finished = true
	print("match.finished = ", m.finished)
	# 复刻 _versus_finish 的排序逻辑
	var rows: Array = []
	for q in ps:
		rows.append({"name": q.display_name, "hp": q.hp, "is_ai": q.is_ai, "alive": q.is_alive()})
	rows.sort_custom(func(x, y):
		if bool(x["alive"]) != bool(y["alive"]):
			return bool(x["alive"])
		return int(x["hp"]) > int(y["hp"]))
	var line := ""
	for i in rows.size():
		var r = rows[i]
		var tg := "[AI]" if bool(r.get("is_ai", false)) else ""
		var st := "存活" if bool(r.get("alive", false)) else "淘汰"
		line += "%d.%s%s(%s %d)  " % [i + 1, tg, String(r.get("name","?")), st, int(r.get("hp",0))]
	print("名次：", line)
	# 期望：1.AI-铁猫(存活88) 2.你(存活42) 3.AI-巨像(淘汰12) 4.AI-秃鹫(淘汰0)
	get_tree().quit(0)