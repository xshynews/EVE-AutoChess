extends Node

## 权威数值表自检 —— 无头跑，把派生结果打出来对照 CSV
##
## 跑法：
##   "C:/godot/Godot_v4.7.1-stable_win64_console.exe" --headless \
##     --path "F:/evezzq/eve自走棋918" --quit-after 200 \
##     res://tools/verify_ship_table.tscn

func _ready() -> void:
	print("═══ EveShipTable 自检 ═══")

	var problems := EveShipTable.validate()
	if problems.is_empty():
		print("[OK] 表结构无问题")
	else:
		for p in problems:
			print("[问题] ", p)

	var s := EveShipDatabase.summary()
	print("总船数 %d（CSV 期望 52）" % int(s["total"]))
	print("按费用：", s["by_cost"])
	print("按派系：", s["by_faction"])
	print("换算常数：格 = %.0f m · 装甲占比 %.2f · 攻速基准 %.2f s"
			% [EveShipDatabase.CELL_METERS, EveShipDatabase.ARMOR_SHARE,
			EveShipDatabase.ATTACK_CYCLE_SECONDS])

	print("")
	print("── 抽样（对照 CSV 原值）──")
	print("%-14s %-10s %-4s %-6s %-6s %-6s %-6s %-8s %-10s %-8s %s"
			% ["id", "中文名", "费", "护盾", "装甲", "结构", "攻击",
			"射程", "移速", "攻速", "羁绊"])
	for key in ["condor", "kestrel", "tristan", "slasher", "punisher",
			"cormorant", "corax", "moa", "vexor", "rupture",
			"drake", "hurricane", "prophecy", "raven", "hyperion",
			"apocalypse", "maelstrom", "dominix"]:
		var d := EveShipDatabase.by_id(key)
		if d.is_empty():
			print("[缺失] ", key)
			continue
		print("%-14s %-10s %-4d %-6d %-6d %-6d %-6d %-8s %-10s %-8s %s"
				% [key, d["name"], int(d["cost"]), int(d["shield"]),
				int(d["armor"]), int(d["hull"]), int(d["attack"]),
				"%d 格" % int(d["range_cells"]),
				"%.2f 格/s" % float(d["speed_cells"]),
				"%.2f s" % float(d["weapon_cycle"]),
				" / ".join(d["traits"])])

	print("")
	print("── 派生到战斗侧的口径 ──")
	for key in ["condor", "punisher", "apocalypse"]:
		var d := EveShipDatabase.by_id(key)
		print("%s：射程 %.0f m（失准 %.0f）· 移速 %.0f m/s · 追踪 %.4f · 信号 %.0f m · 吨位 %d"
				% [key, d["optimal_range"], d["falloff"], d["max_speed"],
				d["tracking"], d["signature"], int(d["class"])])

	print("")
	print("── 实例化 ──")
	var sh := EveShipDatabase.instantiate_by_id("punisher", 0, 1)
	if sh == null:
		print("[失败] 实例化为 null")
	else:
		print("%s · %s · %s · 血 %.0f/%.0f/%.0f · 总血 %.0f · 姿态 %d"
				% [sh.ship_name, sh.faction_name(), sh.class_name_cn(),
				sh.max_hp[&"shield"], sh.max_hp[&"armor"], sh.max_hp[&"hull"],
				sh.total_max_hp(), sh.stance])
		print("  权威原值：key=%s 武器=%s 防御=%s 定位=%s 后勤=%s 间隔=%.0f"
				% [sh.ship_key, sh.weapon_type, sh.defense_type, sh.role,
				str(sh.is_logistics), sh.attack_interval])

	print("═══ 自检结束 ═══")
	# ★ 2026-10-10（审查 R07）：表结构有问题或实例化失败 ⇒ 非零退出码。
	#   （本脚本是"打印对照"型，没有统一断言计数 ⇒ 用这两个确定信号当判据。）
	get_tree().quit(1 if (not problems.is_empty() or sh == null) else 0)
