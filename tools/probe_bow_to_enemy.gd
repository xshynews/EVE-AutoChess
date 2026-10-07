extends Node
## 全库 52 艘朝敌审计 —— 第二十轮开局
##
## ══════════════════════════════════════════════════════════════════
##  任务
## ══════════════════════════════════════════════════════════════════
##  用户：「我方很多船都不是朝着敌人的」+「像人前后转一样把它们朝敌」
##  ⇒ 实读 52 艘的 bow 世界向量，跟「−Z」（敌人在那一侧）对齐。
##  bow · (−Z) < 0 = 背对敌人 = 不朝敌 ⇒ 后续要按"人前后转" = R_y(180°)
##  ⇒ 在 AXIS_REMAP 上同时翻 X 行、Z 行的符号，**不动 Y 行**。
##
##  口径 = 红线 37 同一公式：
##    total_yaw = MODEL_YAW_FIX + AXIS_DEG[id] + (PI if FLIP)
##    bow      = R_y(total_yaw) * M * (1, 0, 0)
##
##  跑法：
##    "C:/godot/Godot_v4.7.1-stable_win64_console.exe" --headless \
##      --path "F:/evezzq/eve自走棋918" --quit-after 3000 \
##      res://tools/probe_bow_to_enemy.tscn
##  产物：user://bow_to_enemy_report.txt

const INDEX := preload("res://scripts/data/eve_ship_asset_index.gd")
const YAW := preload("res://scripts/data/eve_ship_yaw.gd")
const SHIP_TABLE := preload("res://scripts/data/eve_ship_table.gd")

const MODEL_YAW_FIX := -PI / 2.0
const ENEMY_DIR := Vector3(0.0, 0.0, -1.0)   # 敌人在世界 −Z 那一侧

var _lines: Array[String] = []


func _ready() -> void:
	# 1. id → 派系 映射（用主表）
	var faction_of: Dictionary = {}
	for row in SHIP_TABLE.ROWS:
		faction_of[String(row[0])] = String(row[2])

	# 2. 拿全库
	var all_ships: Array = INDEX.all()
	all_ships.sort_custom(func(a, b):
		if a.cost != b.cost:
			return a.cost < b.cost
		return a.id < b.id)

	_lines.append("══════════════════════════════════════════════════════════════════")
	_lines.append("  52 艘朝敌审计（敌人方向 = 世界 −Z）")
	_lines.append("  bow · (−Z) < 0 ⇒ 背对敌人 ⇒ 后续要 R_y(180°)")
	_lines.append("══════════════════════════════════════════════════════════════════")
	_lines.append("")

	var n_away := 0
	var n_face := 0
	var detail: Array = []   # [{id, dot, spec, flip, away, faction, cost}, ...]
	for ship in all_ships:
		var id := StringName(ship.id)
		var dot := _dot_to_enemy(id)
		if is_nan(dot):
			_lines.append("  %-13s  —— 无模型 / 几何退化" % String(id))
			continue
		var is_away := dot < 0.0
		if is_away:
			n_away += 1
		else:
			n_face += 1
		detail.append({
			"id": String(id),
			"dot": dot,
			"spec": String(YAW.AXIS_REMAP.get(id, "·")),
			"flip": String(id) in YAW.FLIP,
			"away": is_away,
			"faction": String(faction_of.get(String(id), "?")),
			"cost": int(ship.cost),
		})

	detail.sort_custom(func(a, b): return float(a["dot"]) < float(b["dot"]))

	_lines.append("背对敌人（dot < 0）：%d / %d" % [n_away, all_ships.size()])
	_lines.append("朝向敌人（dot ≥ 0）：%d / %d" % [n_face, all_ships.size()])
	_lines.append("")
	_lines.append("── 按背对程度从重到轻 ──")
	_lines.append("  %-13s %8s  %-14s %-5s  %-12s  %s" % ["id", "dot(−Z)", "AXIS_REMAP", "FLIP", "派系/cost", "处置"])
	for d in detail:
		_lines.append("  %-13s %+8.4f  %-14s %-5s  %-12s  %s" % [
			String(d["id"]), float(d["dot"]), String(d["spec"]),
			("Y" if bool(d["flip"]) else "·"),
			"%s/c%d" % [String(d["faction"]), int(d["cost"])],
			("✅ 朝敌" if not bool(d["away"]) else "❌ 背敌 → 需 R_y(180°)"),
		])

	_lines.append("")
	_lines.append("── 派系 × 吨位 分布（背敌 / 朝敌）──")
	var cells: Dictionary = {}
	for d in detail:
		var key := "%-8s / cost%d" % [String(d["faction"]), int(d["cost"])]
		if not cells.has(key):
			cells[key] = {"away": 0, "face": 0, "names_away": []}
		if bool(d["away"]):
			cells[key]["away"] += 1
			(cells[key]["names_away"] as Array).append(String(d["id"]))
		else:
			cells[key]["face"] += 1
	for k in cells.keys():
		var v: Dictionary = cells[k]
		var names: Array = v["names_away"]
		var names_s := ("  ← 背敌:" + ", ".join(names)) if not names.is_empty() else ""
		_lines.append("  %-22s  背敌 %d   朝敌 %d%s" % [k, int(v["away"]), int(v["face"]), names_s])

	# 3. 给一份"可执行建议"：只对 away 的船，给出 R_y(180°) 后的新 AXIS_REMAP
	_lines.append("")
	_lines.append("── 17 艘 FLIP 朝敌名单（已生效）──")
	var flip_arr: Array = []
	for s in YAW.FLIP:
		flip_arr.append(String(s))
	flip_arr.sort()
	_lines.append("  " + ", ".join(flip_arr))
	_lines.append("")
	_lines.append("── 处置预案：对 away 的船做 R_y(180°) = 同时翻 X/Z 行、不动 Y 行 ──")
	_lines.append("    翻号规则：第 1 行（世界 X）符号翻、第 3 行（世界 Z）符号翻、第 2 行（世界 Y）不动")
	_lines.append("    注：'没进 AXIS_REMAP 的船' 走的是默认 +X,+Y,+Z ⇒ 翻后变 -X,+Y,-Z，仍需写进表才能生效")
	_lines.append("")
	_lines.append("  %-13s %-14s  →  %-14s  %s" % ["id", "原 AXIS_REMAP", "新 AXIS_REMAP", "注意"])
	for d in detail:
		if not bool(d["away"]):
			continue
		var sid := String(d["id"])
		var old_spec: String = String(d["spec"])
		var new_spec := _apply_y_flip(old_spec, YAW.axis_remap(StringName(sid)))
		var note := ""
		if old_spec == "·":
			note = "原本没 remap ⇒ 翻后须进表"
		_lines.append("  %-13s %-14s  →  %-14s  %s" % [sid, old_spec, new_spec, note])

	var f := FileAccess.open("user://bow_to_enemy_report.txt", FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(_lines))
		f.close()
		print("[BOW] 报告已写 user://bow_to_enemy_report.txt")
	for s in _lines:
		print(s)
	get_tree().quit(0)


func _dot_to_enemy(id: StringName) -> float:
	var total_yaw := MODEL_YAW_FIX
	if YAW.AXIS_DEG.has(id):
		total_yaw += deg_to_rad(float(YAW.AXIS_DEG[id]))
	if String(id) in YAW.FLIP:
		total_yaw += PI
	if YAW.GLOBAL_180:
		total_yaw += PI
	var M := YAW.axis_remap(id)
	var bow := Basis.from_euler(Vector3(0.0, total_yaw, 0.0)) * M * Vector3(1.0, 0.0, 0.0)
	return bow.dot(ENEMY_DIR)


## R_y(180°) 在 AXIS_REMAP 上的代数效果：
##   · 让 spec 的世界 X 行、Z 行同时翻号；Y 行不动（绕 Y 转不动 Y 轴向量）。
##   · 实际 = R_y(180) * M
##   ⇒ 用矩阵乘法算出新 M 的三行（行 = "世界 i 轴 ← 模型某轴"），
##     再翻译回 spec 字符串。
func _apply_y_flip(spec: String, M: Basis) -> String:
	var Ry180 := Basis.from_euler(Vector3(0.0, PI, 0.0))
	var new_M := Ry180 * M
	# new_M 的列 = 模型 X/Y/Z 在世界坐标下的投影；
	# spec 字符串的第 i 行 = "世界 i 轴 = 模型某轴 ±1"
	# ⇒ spec 第 i 行 = 找 new_M 第 i 列中绝对值最大的分量所在模型轴 + 符号。
	var lines: Array[String] = []
	for i in 3:
		var col := Vector3.ZERO
		match i:
			0: col = new_M.x
			1: col = new_M.y
			2: col = new_M.z
		var ax := ""
		var sg := ""
		var best := 0.0
		for k in 3:
			var v := col[k]
			if absf(v) > absf(best):
				best = v
				ax = ["X", "Y", "Z"][k]
				sg = "+" if v > 0 else "-"
		lines.append("%s%s" % [sg, ax])
	return ",".join(lines)
