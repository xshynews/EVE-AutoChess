extends Node

## PvP 对战探针：两个玩家（各自由 brain 决策）真跑一场战斗。
##
## 目的：证明「1 人类 + 1 AI」这条路是通的 —— EveBattleSimulator 本来就吃
## 「红方舰队 / 蓝方舰队」，不关心蓝方是人、AI 还是写死的编组。
##
## 跑法：godot --headless res://tools/probe_pvp_battle.tscn

const RUN := preload("res://scripts/core/eve_run_state.gd")
const MATCH := preload("res://scripts/core/eve_match_state.gd")
const PLAYER := preload("res://scripts/core/eve_match_player.gd")
const BRAIN := preload("res://scripts/core/eve_ai_brain.gd")
const FACTORY := preload("res://scripts/scene/eve_fleet_factory.gd")
const SIM := preload("res://scripts/core/eve_battle_simulator.gd")

const FIXED := 1.0 / 30.0

func _ready() -> void:
	var players: Array = []
	# ⚠️ 探针里双方都由 brain 驱动 —— 目的是验证「两个独立 run 的舰队能对打」。
	#    真实集成时红方的 brain 换成人类输入（鼠标操作同一个 run），其余不变。
	for nm in ["红方", "蓝方"]:
		var run = RUN.new()
		run.start_run()
		var p = PLAYER.new(run, String(nm), true)
		p.brain = BRAIN.new("normal")
		players.append(p)

	print("=== PvP 对战探针 ===")
	print("双方各由 brain 打 3 个准备回合（买船 + 布阵）")
	for turn in 3:
		for i in players.size():
			var pp = players[i]
			if pp.brain != null:
				pp.brain.take_prep_turn(pp.run)
			print("  回合 %d 后 %s：上场 %d 艘 / 备战 %d 艘 / ◆%d / Lv%d / hp %d" % [
				turn + 1, pp.display_name, pp.run.field.size(), pp.run.bench.size(),
				pp.run.coin, pp.run.level, pp.hp])

	# 建双方舰队 —— build_own 对任意 run 都成立，这就是 PvP 零成本的原因
	var factory := FACTORY.new()
	var red: Array = factory.build_own(players[0].run)
	var blue: Array = factory.build_own(players[1].run, 1)
	print("")
	print("红方舰队 %d 艘：%s" % [red.size(), fleet_names(red)])
	print("蓝方舰队 %d 艘：%s" % [blue.size(), fleet_names(blue)])
	if red.is_empty() or blue.is_empty():
		print("!! 有一方是空舰队，打不了"); get_tree().quit(1); return

	# 真跑战斗
	var sim := SIM.new()
	sim.set_seed(20261027)
	sim.setup(red, blue)
	sim.set_time_limit(60.0)
	sim.set_ai_level(1)
	var steps := 0
	while not sim.finished and steps < 60 * 60:
		sim.step(FIXED)
		steps += 1
	var winner := -1
	if sim.finished:
		winner = sim.winner_team
	print("")
	print("=== 战斗结果 ===")
	print("模拟步数 %d（%.1f 秒游戏时间）" % [steps, float(steps) * FIXED])
	var red_alive := 0
	var blue_alive := 0
	for s in sim.ships:
		if not s.alive:
			continue
		if s.team == 0:
			red_alive += 1
		else:
			blue_alive += 1
	print("红方存活 %d／%d · 蓝方存活 %d／%d" % [red_alive, red.size(), blue_alive, blue.size()])
	if winner == 0:
		print("胜者：红方")
	elif winner == 1:
		print("胜者：蓝方")
	else:
		print("平局 / 超时（winner_team=%d）" % winner)
	# 掉血口径：输方 hp -= 对方存活数 x 回合权重
	print("")
	print("按多人规则结算掉血：")
	var w := 1.0 + 0.25 * 1.0
	# ⚠️ 掉血的是**输方**，扣的量 = 对方存活数 x 回合权重
	if winner == 0:
		var d0 := int(ceil(float(red_alive) * w))
		print("  蓝方（输）hp %d -> %d（-%d = 红方存活 %d x 权重 %.2f）" % [
				players[1].hp, players[1].hp - d0, d0, red_alive, w])
	elif winner == 1:
		var d1 := int(ceil(float(blue_alive) * w))
		print("  红方（输）hp %d -> %d（-%d = 蓝方存活 %d x 权重 %.2f）" % [
				players[0].hp, players[0].hp - d1, d1, blue_alive, w])
	get_tree().quit(0)

func fleet_names(fleet: Array) -> String:
	var out: PackedStringArray = []
	for s in fleet:
		out.append("%s★%d" % [s.ship_name, s.star])
	return " ".join(out)