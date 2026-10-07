extends Node
## 后勤修理「有效吞吐」体检 —— 回答「为什么玩家觉得修得少」。
##
## ⛔ 本探针**不读实现中间变量**（那必然自洽），只用公开接口做两件事：
##    ① 用真实 `EveBattleSimulator` 跑满 45 秒，读 `repaired_total`（累积**有效**修入）
##    ② 用同一条影子判据（照抄公开的 hp/max_hp 比例）独立复算「有没有可修目标」
##
## ★ 要证伪的假设：
##    修量本身不小，但**有效修入被「可修窗口」卡死** —— 目标护盾满着时找不到目标，
##    护盾被打空后又被原生被动回充顶起来，留给后勤的窗口极窄。
##    若假设成立，则**把每次修量翻 4 倍，有效修入几乎不涨**。

const OUT_PATH := "user://probe_logi_throughput.txt"
const SIM_SECONDS := 45.0


func _ready() -> void:
	var lines: PackedStringArray = []
	lines.append("后勤修理「有效吞吐」体检\n")
	lines.append("全部读数来自真实 EveBattleSimulator，45 秒固定步进。\n")
	lines.append("「有效修入」= EveShip.repaired_total（只累计**真进了血池**的量）。\n\n")

	_case(lines, "A 现状（护卫 12/次 · 2s 周期）", 1.0, 1.0)
	_case(lines, "B 修量 ×2", 2.0, 1.0)
	_case(lines, "C 修量 ×4", 4.0, 1.0)
	_case(lines, "D 修量 ×4 + 周期减半 1s", 4.0, 0.5)

	var txt := "\n".join(lines)
	_write(txt)
	print(txt)
	get_tree().quit()


func _case(lines: PackedStringArray, title: String, atk_mult: float, cycle_mult: float) -> void:
	var medic := EveShipDatabase.instantiate_by_id("bantam", 0, 8101)
	var ally1 := EveShipDatabase.instantiate_by_id("condor", 0, 8102)
	var ally2 := EveShipDatabase.instantiate_by_id("condor", 0, 8103)
	var foe1 := EveShipDatabase.instantiate_by_id("rifter", 1, 8104)
	var foe2 := EveShipDatabase.instantiate_by_id("rifter", 1, 8105)
	if medic == null or ally1 == null or foe1 == null:
		lines.append("[%s] 建船失败\n" % title)
		return

	# ⚠️ 只改**实例字段**，不动常量 —— 探针不许污染全局。
	medic.logistics_repair *= atk_mult
	medic.logistics_cycle *= cycle_mult
	medic.logistics_timer = medic.logistics_cycle

	var own: Array[EveShip] = [medic, ally1, ally2]
	var foes: Array[EveShip] = [foe1, foe2]
	var sim: RefCounted = EveBattleSimulator.new()
	sim.setup(own, foes)
	sim.set_time_limit(SIM_SECONDS)

	var steps := int(ceil((SIM_SECONDS + 8.0) / EveBattleSimulator.FIXED_STEP))
	var open_frames := 0      # 有可修目标的帧数（影子判据）
	var trace: PackedStringArray = []
	var frames := 0
	for i in steps:
		sim.step(EveBattleSimulator.FIXED_STEP)
		if sim.finished:
			break
		frames += 1
		# 影子判据：照抄公开逻辑（同层百分比最低、非自己、同队、未满血、存活）
		if medic.alive and _shadow_pick(medic, own) != null:
			open_frames += 1
		if frames % 150 == 0:
			var a: EveShip = ally1
			trace.append("      f%4d 后勤盾%.1f · 队友1 盾%.1f 甲%.1f 活:%s" % [
					frames, float(medic.hp[&"shield"]),
					float(a.hp[&"shield"]), float(a.hp[&"armor"]), str(a.alive)])

	var repaired := float(medic.repaired_total)
	var per := float(medic.logistics_repair)
	var rate := per / maxf(0.01, float(medic.logistics_cycle))
	var window_pct := float(open_frames) / maxf(1.0, float(frames)) * 100.0

	lines.append("── %s ─────────────────────────────\n" % title)
	lines.append("  每次修 %.1f 点 · 周期 %.2fs ⇒ 名义速率 %.1f /秒\n" % [
			per, float(medic.logistics_cycle), rate])
	lines.append("  ★ 45 秒**实际有效修入**：%.1f 点 ⇒ 平均 **%.2f /秒**\n" % [
			repaired, repaired / SIM_SECONDS])
	var eff := 0.0
	if rate > 0.0:
		eff = (repaired / SIM_SECONDS) / rate * 100.0
	lines.append("  ★ 有效利用率 %.1f%%（名义速率的百分之几真进了血池）\n" % eff)
	lines.append("  ★ 可修窗口：%d/%d 帧 = **%.1f%%** 的时间才有活可干\n" % [
			open_frames, frames, window_pct])
	lines.append("  收场 %.1fs · 我方存活 %d/3 · 敌方存活 %d/2\n" % [
			float(sim.elapsed), _alive(own), _alive(foes)])
	lines.append("  轨迹（每 150 帧）:\n")
	for line in trace:
		lines.append(line + "\n")
	lines.append("\n")


## 影子判据：照抄 `_pick_repair_target` 的公开口径（**含自己**，2026-10-01 版）。
## ⚠️ 这份是**独立复算**，不是读实现中间变量 —— 它只用公开的 `hp / max_hp`。
func _shadow_pick(medic: EveShip, arr: Array) -> EveShip:
	var layer: StringName = medic.logistics_layer
	if layer.is_empty():
		return null
	var best: EveShip = null
	var best_frac := 1.0
	for s in arr:
		# 只排除死的 / 敌方的 —— **不排除自己**
		if not s.alive or s.team != medic.team:
			continue
		var cap := float(s.max_hp.get(layer, 0.0))
		if cap <= 0.0:
			continue
		var frac := clampf(float(s.hp.get(layer, 0.0)) / cap, 0.0, 1.0)
		if frac >= 0.999:
			continue
		if frac < best_frac:
			best_frac = frac
			best = s
	return best


func _alive(arr: Array) -> int:
	var n := 0
	for s in arr:
		if s.alive:
			n += 1
	return n


func _write(text: String) -> void:
	var f := FileAccess.open(OUT_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(text)
	f.close()
