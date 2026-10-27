extends Node

## 多人对战回合结构探针（场景版）
##
## ⚠️ 为什么必须是场景而不是 `--script`：
##    `godot --headless --script x.gd` 走 SceneTree 模式，**不注册 class_name
##    全局类**，连 EveRunState 自己都解析不了 EveShip / EveCampaignTiers，
##    报一堆 "Identifier not declared"。挂成 autoload 也不行（加载早于类缓存）。
##    从场景进就没这个问题 —— 场景加载会建全局类缓存。
##
## 跑法：godot --headless res://tools/probe_match_rounds.tscn

const RUN := preload("res://scripts/core/eve_run_state.gd")
const MATCH := preload("res://scripts/core/eve_match_state.gd")
const PLAYER := preload("res://scripts/core/eve_match_player.gd")
const BRAIN := preload("res://scripts/core/eve_ai_brain.gd")

func _ready() -> void:
	var players: Array = []
	var names := ["你", "AI-铁猫", "AI-秃鹫", "AI-巨像"]
	for i in names.size():
		var run = RUN.new()
		run.start_run()
		var p = PLAYER.new(run, String(names[i]), i > 0)
		if i > 0:
			p.brain = BRAIN.new("normal")
		players.append(p)

	var m = MATCH.new(players, 12345)
	m.round_started.connect(func(st, rd, kd):
		print("  全局 %2d 回合  阶段 %d-%d／%d  %s" % [m.global_round(), st, rd, m.rounds_in_stage(), kind_name(kd)])
	)
	m.player_eliminated.connect(func(i):
		print("   X %s 被淘汰（hp 归零）" % players[i].display_name)
	)
	m.match_over.connect(func(w):
		print("== 对局结束，胜者 = %s" % (players[w].display_name if w >= 0 else "无"))
	)

	print("开房间：%d 人（1 人类 + %d AI），起始 hp %d" % [players.size(), players.size() - 1, PLAYER.START_HP])
	print("")
	# 先让 AI brain 各跑一次准备回合，验证决策链路是通的
	print("── 让 AI brain 各跑一次准备回合 ──")
	for i in players.size():
		var pp = players[i]
		if not pp.is_ai or pp.brain == null:
			continue
		var before = int(pp.run.bench.size())
		pp.brain.take_prep_turn(pp.run)
		print("   %s：备战席 %d -> %d，星币 %d，羁绊 %d 组激活" % [
				pp.display_name, before, int(pp.run.bench.size()), int(pp.run.coin), pp.run.active_synergies().size()])
	print("")
	# 空跑 12 回合：只验证回合结构 / 配对 / 掉血
	print("")
	print("── 完整 17 回合排表 ──")
	for _step in 20:
		if m.finished:
			break
		var res: Array = m.advance()
		for r in res:
			var a: int = r["a"]
			var b: int = r["b"]
			if b < 0:
				print("   . %s 轮空" % players[a].display_name)
			else:
				print("   . %s(%dhp, %d艘)  VS  %s(%dhp, %d艘)" % [
						players[a].display_name, players[a].hp, players[a].field_count(),
						players[b].display_name, players[b].hp, players[b].field_count()])
			# 假造结果让掉血/淘汰跑起来（A 胜，B 剩 2 艘）
			m.apply_outcome({ "a": a, "b": b, "winner": a, "a_alive": 3, "b_alive": 2 })
		for r2 in res:
			m.apply_outcome({ "a": r2["a"], "b": -1, "winner": -1, "a_alive": 0, "b_alive": 0 })
		print("   => 血量：" + hp_line(players))
		m._next_round()

	print("")
	print("")
	print("── 每回合编组配置（PvE 回合）──")
	var rr := RUN.new()
	rr.set_difficulty("inferno")
	for lbl in ["1-1", "1-2", "1-3", "2-3", "2-4", "2-6", "2-7", "3-3", "3-4", "3-7"]:
		var src: int = MATCH.PVE_SOURCE_NODE.get(lbl, 0)
		rr.node_index = src
		rr.comp_source_node = src
		var roster: Array = rr.enemy_roster()
		var nm := ""
		var formation := ""
		if not roster.is_empty():
			nm = String(rr.enemy_comp_name())
		print("  %s → 炼狱 N%-2d  %s（%d 艘）" % [lbl, src, nm, roster.size()])
	print("")
	print("进度：" + JSON.stringify(m.progress()))
	print("最终血量：" + hp_line(players))
	get_tree().quit(0)

func kind_name(k: int) -> String:
	match k:
		0: return "PvE（电脑编组）"
		1: return "PvP（玩家对战）"
		2: return "选秀 Carousel"
		3: return "BOSS"
	return "?"

func hp_line(players: Array) -> String:
	var out: PackedStringArray = []
	for p in players:
		if p.is_alive():
			out.append("%s=%d" % [p.display_name, p.hp])
		else:
			out.append("%s=淘汰" % p.display_name)
	return " ".join(out)