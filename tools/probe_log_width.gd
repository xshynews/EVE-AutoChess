extends Node

## 战斗日志「信息丢失」探针
##
## ══════════════════════════════════════════════════════════════════
##  在查什么（玩家反馈：「战斗日志会丢失信息，某些信息有时候有有时候没有」）
## ══════════════════════════════════════════════════════════════════
##  两条完全不同的"丢法"，必须分开量：
##   ① **显示侧截断**：日志窗宽 172，单行不换行 + 溢出省略号。
##      文本长度不同 ⇒ 被吃掉的尾巴不同 ⇒ 同一类信息（比如「+12」那个数值）
##      在短船名时看得见、长船名时看不见。这才是"有时候有有时候没有"。
##   ② **写入侧丢弃**：`HIDDEN_CATS` 整类不上屏、`_trim()` 砍到 120 行、
##      `_entries` 400→300。这些是**条目级**丢失。
##
##  本探针量 ①：造真实 CombatLog 面板（172 宽，与生产同尺寸），灌典型日志，
##  逐行比 `文字实宽` vs `可用宽`，输出截断率与被截掉的尾巴。
##
##  ⚠️ 用真实字体测量（`get_theme_font`），不估字宽 —— 中英混排估不准。
##  ⚠️ 必须等布局完成（两帧）后再量，否则 `size.x` 还是 0。

const LOG_SCRIPT := preload("res://scripts/ui/panels/eve_combat_log.gd")

## 生产尺寸（`eve_hud_root.RECT_LOG` = 172 × 200 附近）
const PANEL_W := 172.0
const PANEL_H := 200.0

## 典型日志样本 —— 全部照抄生产里真实出现的模板，只把船名换成不同长度。
const SAMPLES := [
	{"t": 3.1, "cat": &"system", "team": -1, "tx": "战斗开始：6 v 6"},
	{"t": 5.2, "cat": &"break", "team": 0, "tx": "裂谷级 的护盾被击穿"},
	{"t": 6.0, "cat": &"break", "team": 1, "tx": "惩罚者级 的装甲被击穿"},
	{"t": 7.4, "cat": &"damage", "team": 1, "tx": "裂谷级 已被摧毁"},
	{"t": 8.9, "cat": &"repair", "team": 0, "tx": "惩罚者级 → 裂谷级 装甲 +12"},
	{"t": 9.5, "cat": &"repair", "team": 0, "tx": "守夜者级 → 惩罚者级 护盾 +8"},
	{"t": 11.0, "cat": &"damage", "team": 0, "tx": "守夜者级 已被摧毁"},
	{"t": 12.2, "cat": &"economy", "team": -1, "tx": "结算：击沉 3 艘 · 获得 12 星币"},
	{"t": 13.0, "cat": &"damage", "team": 1, "tx": "末日沙场级 已被摧毁"},
	{"t": 14.1, "cat": &"system", "team": 1, "tx": "旗舰 末日沙场级 集火点名：守夜者级"},
	{"t": 15.0, "cat": &"repair", "team": 0, "tx": "执政官级 → 末日沙场级 结构 +24"},
	{"t": 16.3, "cat": &"system", "team": -1, "tx": "僵持过久 —— 按剩余战力判定收场"},
]

var _fail := 0
var _log = null


func _ready() -> void:
	print("═══ 战斗日志截断探针（面板 %.0f×%.0f）═══" % [PANEL_W, PANEL_H])
	await get_tree().process_frame

	_log = LOG_SCRIPT.new()
	_log.size = Vector2(PANEL_W, PANEL_H)
	add_child(_log)
	# ⚠️ 两帧：一帧建布局，一帧让 ScrollContainer 算内宽
	await get_tree().process_frame
	await get_tree().process_frame

	for s in SAMPLES:
		_log.call("append_entry", {"time": s["t"], "category": s["cat"],
				"team": s["team"], "text": s["tx"]})
	await get_tree().process_frame
	await get_tree().process_frame

	_measure()
	print("\n结论：被截断 %d / %d 行" % [_fail, SAMPLES.size()])
	get_tree().quit(0 if _fail == 0 else 1)


## 逐行量：文字实宽 vs Label 可用宽
func _measure() -> void:
	var list: VBoxContainer = _log.get("_list")
	if list == null:
		print("✗ 拿不到 _list")
		_fail += 1
		return
	var rows := list.get_child_count()
	print("列表行数 = %d（样本 %d）" % [rows, SAMPLES.size()])
	if rows != SAMPLES.size():
		print("⚠️ 行数对不上：有 %d 行没上屏（HIDDEN_CATS / 裁剪）"
				% (SAMPLES.size() - rows))

	print("\n%-4s %-9s %-30s %7s %7s  %s" % ["t", "类别", "文本", "文字px", "可用px", "判定"])
	for i in rows:
		var row := list.get_child(i) as HBoxContainer
		# 最后一个子节点就是正文 Label（时间戳 / 阵营字 / 色块 都在它前面）
		var lbl: Label = null
		for c in row.get_children():
			if c is Label and c != row.get_child(0) and c != row.get_child(1):
				lbl = c
		if lbl == null:
			continue
		var f := lbl.get_theme_font("font")
		var fs := lbl.get_theme_font_size("font_size")
		var need := f.get_string_size(lbl.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var have := lbl.size.x
		var cut := need > have
		if cut:
			_fail += 1
		var verdict := "✗ 截断 %.0fpx" % (need - have) if cut else "✓ 完整"
		print("%-4.1f %-9s %-30s %7.1f %7.1f  %s"
				% [float(SAMPLES[i]["t"] if i < SAMPLES.size() else 0),
					String(SAMPLES[i]["cat"] if i < SAMPLES.size() else "?"),
					lbl.text, need, have, verdict])

	# 额外：算出「总共能放下几个汉字」，给方案当依据
	var probe := Label.new()
	probe.text = "中"
	probe.add_theme_font_override("font", lbl_any_font(list))
	probe.add_theme_font_size_override("font_size", 9)
	var per_zh := probe.get_theme_font("font").get_string_size(
			"中", HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x
	probe.queue_free()
	print("\n单字宽 ≈ %.2fpx（9 号字）⇒ 一行最多约 %.1f 个汉字"
			% [per_zh, 0.0 if per_zh <= 0.0 else _usable(list) / per_zh])


func lbl_any_font(list: VBoxContainer) -> Font:
	for i in mini(3, list.get_child_count()):
		for c in (list.get_child(i) as HBoxContainer).get_children():
			if c is Label:
				return (c as Label).get_theme_font("font")
	return null


func _usable(list: VBoxContainer) -> float:
	for i in mini(3, list.get_child_count()):
		var row := list.get_child(i) as HBoxContainer
		for c in row.get_children():
			if c is Label and c.text.length() > 4:
				return (c as Label).size.x
	return 0.0
