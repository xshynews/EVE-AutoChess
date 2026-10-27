extends Node

## 完整对局探针：1 人类 + 3 AI，跑满 17 回合。
##
## 这是「多人回合在单机模式下开启」的最小验证：
##   · PvE 回合 → 按 PVE_SOURCE_NODE 取炼狱编组（吃羁绊 / 1.4 倍率）
##   · PvP 回合 → 用 EveBattleSimulator 真打对手的舰队
##   · 事件回合 → 跳过（留给 UI）
##   · 掉血 / 淘汰 / 名次全走 EveMatchState
##
## 跑法：godot --headless res://tools/probe_full_match.tscn

const RUN := preload("res://scripts/core/eve_run_state.gd")
const MATCH := preload("res://scripts/core/eve_match_state.gd")
const PLAYER := preload("res://scripts/core/eve_match_player.gd")
const BRAIN := preload("res://scripts/core/eve_ai_brain.gd")
const FACTORY := preload("res://scripts/scene/eve_fleet_factory.gd")
const SIM := preload("res://scripts/core/eve_battle_simulator.gd")

const FIXED := 1.0 / 30.0
const AI_NAMES := ["AI-铁猫", "AI-秃鹫", "AI-巨像"]

func _ready() -> void:
	var players: Array = []
	var you = RUN.new()
	you.set_difficulty("inferno")
	you.start_run()
	players.append(PLAYER.new(you, "你", false))
	for nm in AI_NAMES:
		var r = RUN.new()
		r.set_difficulty("inferno")
		r.start_run()
		var p = PLAYER.new(r, String(nm), true)
		p.brain = BRAIN.new("inferno")
		players.append(p)

	var m = MATCH.new(players, 424242)
	print("=== 完整对局：1 人类 + %d AI · %d 回合 ===" % [AI_NAMES.size(), MATCH.TOTAL_ROUNDS])
	print("")

	var guard := 0
	while not m.finished and guard < 40:
		guard += 1
		var kind := m.round_kind()
		var lbl := m.round_label()
		print("── 全局 %2d 回合  %s  %s" % [m.global_round(), lbl, kind_name(kind)])

		# ① 所有玩家各打各的准备回合（人类位也由 brain 代打，探针里没有鼠标）
		for i in players.size():
			var pp = players[i]
			if not pp.is_alive():
				continue
			if pp.brain != null:
				pp.brain.take_prep_turn(pp.run)
			else:
				# 人类位：探针里用 brain 代打，真实游戏里这里是鼠标操作
				var b = BRAIN.new("inferno")
				b.take_prep_turn(pp.run)

		# ② 按回合类型分派
		if kind == MATCH.RoundKind.PVP:
			for pair in m.make_pairings():
				var a: int = pair[0]
				var b: int = pair[1]
				if b < 0:
					continue
				var res := fight(players[a].run, players[b].run)
				var win := -1
				if res["winner"] == 0:
					win = a
				elif res["winner"] == 1:
					win = b
				m.apply_outcome({
					"a": a, "b": b, "winner": win,
					"a_alive": res["a_alive"], "b_alive": res["b_alive"] })
				print("     %s(%d艘) vs %s(%d艘) → %s ｜ 存活 %d : %d" % [
					players[a].display_name, res["a_n"], players[b].display_name, res["b_n"],
					("红方胜" if win == a else ("蓝方胜" if win == b else "平局")),
					res["a_alive"], res["b_alive"]])
		elif kind == MATCH.RoundKind.CAROUSEL:
			# 事件回合：留给 UI（探针里直接跳过）
			print("     （事件回合，跳过）")
		else:
			# PvE / BOSS：每个活人各打电脑编组
			for i in players.size():
				var pp = players[i]
				if not pp.is_alive():
					continue
				var src: int = m.pve_source_node()
				if src > 0:
					pp.run.node_index = src
					pp.run.comp_source_node = src
				var res2 := fight_pve(pp.run)
				m.apply_outcome({
					"a": i, "b": -1, "a_won": (res2["winner"] == 0),
					"a_alive": res2["a_alive"], "b_alive": res2["b_alive"] })
				print("     %s vs %s（%d 艘）→ %s" % [
					pp.display_name, String(pp.run.enemy_comp_name()), res2["b_n"],
					("胜" if res2["winner"] == 0 else "败")])
		print("     血量：" + hp_line(players))
		m._check_end()
		if m.finished:
			break
		m._next_round()

	print("")
	print("=== 对局结束 ===")
	var alive := m.alive_players()
	print("存活 %d 人：%s" % [alive.size(), hp_line(players)])
	var rank := players.duplicate()
	rank.sort_custom(func(x, y): return x.hp > y.hp)
	var out: PackedStringArray = []
	for i in rank.size():
		out.append("%d.%s(%d)" % [i + 1, rank[i].display_name, rank[i].hp])
	print("名次：" + "  ".join(out))
	get_tree().quit(0)

## 两名玩家的舰队对打，返回结果字典
func fight(ra: EveRunState, rb: EveRunState) -> Dictionary:
	var f := FACTORY.new()
	var red: Array = f.build_own(ra, 0)
	var blue: Array = f.build_own(rb, 1)
	if red.is_empty() or blue.is_empty():
		return {"winner": -1, "a_alive": 0, "b_alive": 0, "a_n": red.size(), "b_n": blue.size()}
	var sim := SIM.new()
	sim.set_seed(absi(ra.enemy_roster_seed() + rb.enemy_roster_seed()))
	sim.setup(red, blue)
	sim.set_time_limit(60.0)
	sim.set_ai_level(3)
	var steps := 0
	while not sim.finished and steps < 1800:
		sim.step(FIXED)
		steps += 1
	var wa := 0
	var wb := 0
	for s in sim.ships:
		if not s.alive:
			continue
		if s.team == 0:
			wa += 1
		else:
			wb += 1
	return {"winner": sim.winner_team, "a_alive": wa, "b_alive": wb,
		"a_n": red.size(), "b_n": blue.size()}

## 玩家 vs 电脑编组
func fight_pve(run: EveRunState) -> Dictionary:
	var f := FACTORY.new()
	var own: Array = f.build_own(run, 0)
	var foe: Array = f.build_enemy(run)
	if own.is_empty():
		return {"winner": 1, "a_alive": 0, "b_alive": foe.size(), "b_n": foe.size()}
	var sim := SIM.new()
	sim.set_seed(absi(run.enemy_roster_seed()))
	sim.setup(own, foe)
	sim.set_time_limit(60.0)
	sim.set_ai_level(3)
	var steps := 0
	while not sim.finished and steps < 1800:
		sim.step(FIXED)
		steps += 1
	var wa := 0
	var wb := 0
	for s in sim.ships:
		if not s.alive:
			continue
		if s.team == 0:
			wa += 1
		else:
			wb += 1
	return {"winner": sim.winner_team, "a_alive": wa, "b_alive": wb, "b_n": foe.size()}

func kind_name(k: int) -> String:
	match k:
		0: return "打怪"
		1: return "PvP"
		2: return "事件"
		3: return "BOSS"
	return "?"

func hp_line(players: Array) -> String:
	var out: PackedStringArray = []
	for p in players:
		if p.is_alive():
			out.append("%s=%d" % [p.display_name, p.hp])
		else:
			out.append("%s=X" % p.display_name)
	return " ".join(out)