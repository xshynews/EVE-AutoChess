extends Node

const RES := preload("res://scripts/ui/panels/eve_result.gd")

func _ready() -> void:
	var w = RES.new()
	add_child(w)
	var rows: Array = [
		{"name": "AI-铁猫", "hp": 88, "is_ai": true, "alive": true},
		{"name": "你", "hp": 42, "is_ai": false, "alive": true},
		{"name": "AI-巨像", "hp": 12, "is_ai": true, "alive": false},
		{"name": "AI-秃鹫", "hp": 0, "is_ai": true, "alive": false},
	]
	w.show_versus_ranking(rows, "3-7")
	print("visible = ", w.visible)
	# walk the whole tree and dump every visible Label text
	var st: Array[Node] = [w]
	var seen := 0
	while not st.is_empty():
		var nd: Node = st.pop_back()
		if nd is Label and (nd as Label).visible and not (nd as Label).text.is_empty():
			seen += 1
			print("  L", (nd as Label).text)
		for ch in nd.get_children():
			st.append(ch)
	print("labels = ", seen)
	get_tree().quit(0)
