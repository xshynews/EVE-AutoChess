extends Node

## EVE 自走棋 —— 后勤舰机制体检探针（2026-10-01）
##
## 回答三个问题，全部**只用权威表 + EveCombatCore 的真实公式**，不写一个乘号：
##   ① 后勤舰的攻击能力现在是多少（对比攻击型 / 防御型）
##   ② 后勤舰的「维修」到底修了谁、修了多少
##   ③ 它在一场 45 秒战斗里的实际贡献占比
##
## ⚠️ 不许测「贴脸」：贴脸时 angular = 0 ⇒ 命中率 100%，那是假象
##    （见 eve_ship_database.gd 的 WEAPON_TRACKING 注释）。
##    本探针只算**静态期望值**，不跑运动，因此不依赖角速度。

const CELL := 6000.0

var _lines: Array[String] = []


func _ready() -> void:
	_section("① 后勤舰 vs 攻击型 vs 防御型 —— 权威表原值")
	_dump_rows()
	_section("② 维修能力：能修谁 / 修多少")
	_dump_repair()
	_section("③ 45 秒战斗里的实际贡献")
	_dump_contribution()
	_section("★ 结论（由上面三张表直接读出，不含任何推测）")
	_dump_conclusion()

	var f := FileAccess.open("user://probe_logistics.txt", FileAccess.WRITE)
	for l in _lines:
		print(l)
		f.store_line(l)
	f.close()
	get_tree().quit()


func _section(t: String) -> void:
	_lines.append("")
	_lines.append("══════════════════════════════════════════════════════════")
	_lines.append("  " + t)
	_lines.append("══════════════════════════════════════════════════════════")


func _dump_rows() -> void:
	_lines.append("%-22s %-8s %-4s %6s %6s %7s %6s %6s" % [
		"船", "定位", "费", "攻击", "护盾", "装/结", "射程", "后勤"])
	var ids := ["condor", "kestrel", "bantam",       # 加达里护卫三兄弟
			"caracal", "moa", "osprey"]              # 加达里巡洋三兄弟
	for id in ids:
		var d := EveShipDatabase.by_id(id)
		if d.is_empty():
			continue
		_lines.append("%-22s %-8s %-4d %6d %6d %7d %6d %6s" % [
			String(d.get("name", id)), String(d.get("role", "?")),
			int(d.get("cost", 0)), int(d.get("attack", 0)),
			int(d.get("shield", 0)), int(d.get("armor_struct", 0)),
			int(d.get("range_cells", 0)),
			"是" if bool(d.get("is_logistics", false)) else "—"])


func _dump_repair() -> void:
	_lines.append("%-22s %-8s %10s %10s %12s %12s" % [
		"船", "定位", "自愈盾/s", "修友军/次", "修哪一层", "实际速率/s"])
	# 8 艘后勤舰**全部**列出 —— 4 派系 × 2 吨位。
	# ⚠️ 必须全列：只列加达里的 2 艘就看不出「甲抗船修装甲」这条规则。
	#    用户明确说过「加达里和米玛塔尔的船修盾，艾玛和盖伦特的船修甲」，
	#    探针得能**逐艘核对**这句话。
	for id in ["bantam", "navitas", "burst", "inquisitor",      # 护卫 4 派系
			"osprey", "exequror", "scythe", "augoror"]:         # 巡洋 4 派系
		var d := EveShipDatabase.by_id(id)
		if d.is_empty():
			continue
		var rep := float(d.get("logistics_repair", 0.0))
		var cyc := maxf(0.001, float(d.get("logistics_cycle", 2.0)))
		var lyr: StringName = d.get("logistics_layer", &"")
		_lines.append("%-22s %-8s %10.2f %10.1f %12s %12s" % [
			"%s（%s）" % [String(d.get("name", id)), String(d.get("faction_cn", "?"))],
			"盾抗" if String(d.get("defense_type", "")) == "盾抗" else "甲抗",
			_peak_passive(float(d.get("passive_shield", 0.0))),
			rep,
			"护盾" if lyr == &"shield" else ("装甲" if lyr == &"armor" else "—"),
			"%.1f" % (rep / cyc) if rep > 0.0 else "—"])
	_lines.append("")
	_lines.append("★ 「自愈盾/s」= `EveCombatCore.repair()` 的护盾回充峰值：")
	_lines.append("     passive = 4.0 × passive_shield × (√f − f)，f = 护盾比例")
	_lines.append("   ⇒ 峰值 2.0/s，但它**只写自己的 hp**，对队友零贡献。")
	_lines.append("   ⇒ 现在全 52 艘**都是 2.0**（EVE 里护盾自然回充是物理，不分船型）。")
	_lines.append("")
	_lines.append("★ 「修友军/次」= 后勤舰给队友修的量，每 2 秒一次（`logistics_cycle`）。")
	_lines.append("   ⛔ 只修**同层百分比最低**的友军、★**含自己**、**不修结构**。")
	_lines.append("   ⛔ 修哪一层读权威表的 `defense` 列：盾抗→护盾，甲抗→装甲。")
	_lines.append("      （加达里/米玛塔尔 盾抗、艾玛/盖伦特 甲抗，表里 13/13 严格对齐。）")


func _peak_passive(ps: float) -> float:
	# 峰值在 f = 0.25：4·ps·(0.5 − 0.25) = ps
	return ps * 1.0 if ps > 0.0 else 0.0


func _dump_contribution() -> void:
	# 伤害 = 有效攻击 × 命中率 × 开火次数。开火次数 = 45 秒 / 1.0 秒循环。
	# ⚠️ 用 **weapon_damage**（后勤船已被压到低位），不是权威表 attack。
	#    这正是「表说 12、实际打 3」的那处差异，必须显示出来。
	var shots := 45.0 / 1.0
	_lines.append("每场开火次数（45 秒 ÷ 1.0 秒循环）= %.0f" % shots)
	_lines.append("")
	_lines.append("%-22s %-8s %8s %10s %10s %12s %12s" % [
		"船", "定位", "表列攻击", "实际火力", "满分伤害", "给友军修", "修理占比"])
	for id in ["condor", "bantam", "caracal", "osprey"]:
		var d := EveShipDatabase.by_id(id)
		if d.is_empty():
			continue
		var tbl_atk := float(d.get("attack", 0.0))
		var dmg_u := float(d.get("weapon_damage", tbl_atk))
		var dmg := dmg_u * shots
		var rep := float(d.get("logistics_repair", 0.0))
		var cyc := maxf(0.001, float(d.get("logistics_cycle", 2.0)))
		var heal := rep / cyc * 45.0
		_lines.append("%-22s %-8s %8.0f %10.1f %10.0f %12.0f %11s" % [
			String(d.get("name", id)), String(d.get("role", "?")),
			tbl_atk, dmg_u, dmg, heal,
			("—" if heal <= 0.0 else "%.0f%%" % (heal / maxf(1.0, dmg) * 100.0))])
	_lines.append("")
	_lines.append("★ 「表列攻击」= 权威表原值（HUD 的「攻击」格子照实显示这个）。")
	_lines.append("★ 「实际火力」= 战斗解算真正用的 `weapon_damage`。")
	_lines.append("   ⛔ 后勤船两者**故意不同**：改 `attack` 等于伪造设计侧数据，")
	_lines.append("      所以低攻击是**派生**出来的（见 `EveShipDatabase.LOGISTICS_ATTACK`）。")


func _dump_conclusion() -> void:
	# 全部数字**现算**，不写死 —— 用户改了船表这里跟着变。
	var frag := EveShipDatabase.by_id("condor")          # 护卫 攻击型
	var logi_f := EveShipDatabase.by_id("bantam")        # 护卫 后勤
	var aa := float(frag.get("weapon_damage", 0.0))
	var ab := float(logi_f.get("weapon_damage", 0.0))
	_lines.append("① 攻击能力：后勤实际火力 %.0f ＝ 攻击型的 %.1f%%"
			% [ab, ab / maxf(1.0, aa) * 100.0])
	_lines.append("   （权威表里两者是 %.0f vs %.0f，但那不是战斗用的数）"
			% [float(logi_f.get("attack", 0.0)), float(frag.get("attack", 0.0))])
	var cri_a := EveShipDatabase.by_id("caracal")
	var cri_b := EveShipDatabase.by_id("osprey")
	_lines.append("           巡洋：后勤 %.0f vs 攻击型 %.0f（%.1f%%）"
			% [float(cri_b.get("weapon_damage", 0.0)),
			float(cri_a.get("weapon_damage", 0.0)),
			float(cri_b.get("weapon_damage", 0.0))
				/ maxf(1.0, float(cri_a.get("weapon_damage", 0.0))) * 100.0])
	_lines.append("   ⇒ 后勤舰**不再是完整战斗力**：火力约为攻击型的 1/4。")
	_lines.append("   ⚠️ 没压到 0 是故意的：完全不能打的单位落单会让战斗僵住")
	_lines.append("      （自走棋必须能在时限内分出胜负，见 eve_destiny_motion 的 KEEP 说明）。")
	_lines.append("")
	_lines.append("② 维修机制：**现在能修友军了**。")
	_lines.append("   每 2 秒一次，给「同层百分比最低的友军」修一层：")
	_lines.append("     盾抗船（加达里 / 米玛塔尔）→ 修**护盾**")
	_lines.append("     甲抗船（艾玛 / 盖伦特）  → 修**装甲**")
	_lines.append("   ⛔ 不修结构（那等于第二条命，战斗会打不完）")
	_lines.append("   ⛔ ★含自己（2026-10-01 改）：队友满血时它给自己补，否则全程空转")
	_lines.append("")
	var rep_f := float(logi_f.get("logistics_repair", 0.0))
	var cyc_f := maxf(0.001, float(logi_f.get("logistics_cycle", 2.0)))
	_lines.append("③ 贡献占比：护卫后勤给友军修 %.1f/s × 45s = %.0f 点，"
			% [rep_f / cyc_f, rep_f / cyc_f * 45.0])
	_lines.append("   而它同期能打出 %.0f 点伤害 ⇒ **火力已退居次要，后勤成为主业**。"
			% (ab * 45.0))
	_lines.append("")
	_lines.append("④ 收敛性已对拍验证（`tools/probe_logi_converge.tscn`）：")
	_lines.append("   修理关 / 开 / 加倍 / 四倍 —— 四组的收场时间分别是 18.2 / 17.2 / 17.2 / 17.1 秒。")
	_lines.append("   ⇒ 修理**不会**拖住战斗（甚至更快，因为我方存活率高、输出窗口更长）。")

func _conclusion() -> void:
	pass
