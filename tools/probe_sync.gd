extends Node

const MATCH := preload("res://scripts/core/eve_match_state.gd")
const PLAYER := preload("res://scripts/core/eve_match_player.gd")
const RUN := preload("res://scripts/core/eve_run_state.gd")

func _ready() -> void:
	print("=== 回合时钟 / 超时判负 / AI 经济同步 验证 ===")
	var m = MATCH.new([], 1)
	print("ROUND_TIME = ", MATCH.ROUND_TIME, "s")
	# ① 倒计时累积
	m.round_elapsed = 0.0
	for i in 30:
		m.round_elapsed += 1.0 / 30.0   # 一帧
	print("30 帧后 round_elapsed = %.2f（应 ≈1.00）" % m.round_elapsed)
	# ② 超时判定
	m.round = 1; m.stage = 2   # 2-1 是事件回合，应豁免
	print("事件回合 timed_out = ", m.round_timed_out(), "（应 false）")
	m.round_elapsed = 200.0
	print("200s 后事件回合 timed_out = ", m.round_timed_out(), "（应 false，豁免）")
	m.round = 2   # 2-2 是 PvP
	print("PvP 200s timed_out = ", m.round_timed_out(), "（应 true）")
	m.round_elapsed = 89.0
	print("PvP 89s timed_out = ", m.round_timed_out(), "（应 false）")
	m.round_elapsed = 91.0
	print("PvP 91s timed_out = ", m.round_timed_out(), "（应 true）")
	# ③ AI 经济同步：resolve_battle 在 PREP 阶段可用
	var r = RUN.new()
	r.start_run()
	var c0 = r.coin
	var res = r.resolve_battle(0, [], [], 1.0, [])
	print("AI resolve_battle(PREP) ok = ", res.has("damage"), " coin %d -> %d" % [c0, r.coin])
	r.advance()
	print("advance 后 node_index = ", r.node_index, " phase = ", r.phase)
	get_tree().quit(0)