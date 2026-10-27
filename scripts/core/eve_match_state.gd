class_name EveMatchState
extends RefCounted

## 多人对局的「房间」：回合推进 / 配对 / 掉血 / 淘汰 / 胜负。
##
## ⚠️ 这是整个多人架构里**唯一的新概念**。单机的 15 个节点在这里被重新解释为
##    「阶段 x 回合」；`EveRunState`（舰队经济）原样复用；
##    `EveBattleSimulator` 本来就是两队对战，PvP 零成本。
##
## 结构来源：云顶之弈（见 docs/多人对战架构-AI对战与人机.md）。

## 回合种类
enum RoundKind {
	PVE,       ## 打电脑编组（对应现在的敌方节点）
	PVP,       ## 打另一名玩家的舰队
	CAROUSEL,  ## 选秀（= 现在的事件节点）
	BOSS,      ## 阶段末 BOSS
}

## 阶段 1 只有 3 回合且全 PvE（云顶同口径：新手期别和人打）
## ── 回合结构（2026-10-27 用户定案：按云顶节奏，多做几个回合）─────────
##
## 云顶口径（维基）：每阶段 7 回合；第 1 阶段只有 3 回合且全 PvE；
## 每阶段第 3 回合后插一次选秀；每阶段最后一回合打电脑。
##
## 本工程总回合数 = 3 + 7 + 7 = **17 回合**（原来是 15 个节点）。
## 完整排表见 docs/多人对战架构-AI对战与人机.md 第二节。
const STAGE1_ROUNDS := 3
const ROUNDS_PER_STAGE := 7
## 每阶段第 4 回合是选秀（云顶：第 3 回合后触发）
const CAROUSEL_ROUND := 4
## 总阶段数（含第 1 阶段）
const TOTAL_STAGES := 3
## 总回合数（供 HUD / 结算展示）
const TOTAL_ROUNDS := STAGE1_ROUNDS + ROUNDS_PER_STAGE * (TOTAL_STAGES - 1)

## ── PvE 回合的编组来源（2026-10-27 用户逐回合指定）────────────────
##
## 用户原话的配置：
##   阶段 1 的 PvE 回合   → 炼狱第 1 / 2 / 3 回合
##   2-3 → 炼狱第5 · 2-4 → 炼狱第6 · 2-6 → 炼狱第7 · 2-7 → 炼狱第8
##   3-3 → 炼狱第10 · 3-4 → 炼狱第11 · 3-7 → 炼狱第15
##
## ⚠️ **炼狱配方里没有第 10 节点** —— 4 / 10 / 14 是事件节点，
##    `EveEnemyPlans` 只给 1,2,3,5,6,7,8,9,11,12,13,15 这 12 个战斗节点出编组。
##    所以 3-3 我按顺序落到 **9**（远程压制组：战巡 + 普通巡洋 + 支援巡洋，
##    STANDOFF 阵型「保持距离」）。如果你要的是别的节点，改这一行即可。
##
## 其余 PvE 配置一律按炼狱档：吃羁绊 / 阵型站位 / ×1.40 倍率 /
## AI 等级 3 / armor_pierce 壁垒。
const PVE_SOURCE_NODE := {
	"1-1": 1, "1-2": 2, "1-3": 3,
	"2-3": 5, "2-4": 6, "2-6": 7, "2-7": 8,
	"3-3": 9, "3-4": 11, "3-7": 15,
}

## 多人 PvE 回合统一按炼狱档跑（用户定案：吃羁绊 + 1.4 难度系数）
const PVE_DIFFICULTY := "inferno"


## 本回合的 PvE 编组来源节点；不是 PvE 回合返回 0
func pve_source_node() -> int:
	if round_kind() != RoundKind.PVE and round_kind() != RoundKind.BOSS:
		return 0
	return int(PVE_SOURCE_NODE.get(round_label(), 0))

signal round_started(stage: int, round: int, kind: RoundKind)
signal round_resolved(results: Array)
signal player_eliminated(idx: int)
signal match_over(winner_idx: int)

var players: Array = []          ## Array[EveMatchPlayer]
var stage := 1
var round := 1
var finished := false
var seed := 0

var _rng := RandomNumberGenerator.new()


func _init(p_players: Array = [], p_seed := 0) -> void:
	players = p_players
	seed = p_seed
	_rng.seed = p_seed if p_seed != 0 else randi()


## 本阶段总共有几回合
func rounds_in_stage() -> int:
	return STAGE1_ROUNDS if stage == 1 else ROUNDS_PER_STAGE


## 本回合是什么类型
##
## ⚠️ 事件（CAROUSEL）不只第 4 回合：云顶现代版本在选秀之外还有
##    **强化回合**（augment，约在每阶段第 1 / 第 2 回合）。本工程把
##    「事件四选一」映射到这两类机会上，所以一个 7 回合阶段里有两个事件位：
##      · 第 1 回合 = 强化（augment）位
##      · 第 4 回合 = 选秀（carousel）位
## ⚠️ 判定顺序：先问「用户把这一回合配成 PvE 了吗」，再走阶段模板。
##    这样 PVE_SOURCE_NODE 是唯一真源 —— 用户加一行配置，这一回合就变成打怪，
##    不用再来改 round_kind（以前就是两边各写一半，结果配了 PvE 却显示 PvP）。
func round_kind() -> RoundKind:
	if stage == 1:
		return RoundKind.PVE
	if PVE_SOURCE_NODE.has(round_label()):
		# 阶段最后一回合的 PvE 是 BOSS（掉血更疼、视觉上也不同）
		return RoundKind.BOSS if round == ROUNDS_PER_STAGE else RoundKind.PVE
	if round == 1:
		return RoundKind.CAROUSEL      ## 强化位
	if round == CAROUSEL_ROUND:
		return RoundKind.CAROUSEL      ## 选秀位
	if round == ROUNDS_PER_STAGE:
		return RoundKind.BOSS
	return RoundKind.PVP


## 全局回合号（1..TOTAL_ROUNDS），跨阶段连续编号
##
## ⚠️ 阶段 1 只有 3 回合（不是 7），所以公式要分两段：
##    阶段 1 ⇒ 直接用 round（1..3）
##    阶段 >=2 ⇒ 3 + (stage-2)*7 + round
func global_round() -> int:
	if stage <= 1:
		return round
	return STAGE1_ROUNDS + (stage - 2) * ROUNDS_PER_STAGE + round


## 人类可读的回合标签，如 "2-4"
func round_label() -> String:
	return "%d-%d" % [stage, round]


func alive_players() -> Array:
	var out: Array = []
	for p in players:
		if p != null and p.is_alive():
			out.append(p)
	return out


## 掉血权重：越后期输一次越疼（云顶口径）。
## 单机的 loss_curve 是「每节点固定扣」，多人改成「随回合数递增」。
func damage_weight() -> float:
	var total := (stage - 1) * ROUNDS_PER_STAGE + round
	return 1.0 + float(total) * 0.25


## 给 PvP 回合配对：每名存活玩家随机抽一名**不同的存活玩家**。
## ⚠️ 人数为奇数时有一人轮空（云顶同口径：轮空不掉血也不打）。
func make_pairings() -> Array:
	var alive := alive_players()
	var idxs: Array = []
	for i in players.size():
		if players[i] != null and players[i].is_alive():
			idxs.append(i)
	# 洗牌
	for i in range(idxs.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp = idxs[i]
		idxs[i] = idxs[j]
		idxs[j] = tmp
	var pairs: Array = []
	var k := 0
	while k + 1 < idxs.size():
		pairs.append([idxs[k], idxs[k + 1]])
		k += 2
	if k < idxs.size():
		pairs.append([idxs[k], -1])     ## 轮空
	return pairs


## 推进一回合；返回本回合的结果数组（给上层拿去跑模拟 / 刷 HUD）
func advance() -> Array:
	if finished:
		return []
	var kind := round_kind()
	round_started.emit(stage, round, kind)
	var results: Array = []
	if kind == RoundKind.PVP:
		for pair in make_pairings():
			results.append({
				"kind": kind,
				"a": pair[0],
				"b": pair[1],
				"stage": stage,
				"round": round,
			})
	else:
		# PvE / BOSS / 选秀：每个存活玩家各打各的
		for i in players.size():
			if players[i] != null and players[i].is_alive():
				results.append({
					"kind": kind,
					"a": i,
					"b": -1,
					"stage": stage,
					"round": round,
				})
	round_resolved.emit(results)
	_check_end()
	return results


## 一回合的模拟结果回来之后调用：结算掉血 / 淘汰 / 推进回合。
## `outcome` 形如 {"a": i, "b": j, "winner": i, "a_alive": 3, "b_alive": 5}
func apply_outcome(outcome: Dictionary) -> void:
	if finished:
		return
	var a: int = outcome.get("a", -1)
	var b: int = outcome.get("b", -1)
	if a < 0 or a >= players.size():
		return
	var pa = players[a]
	if b >= 0 and b < players.size():
		var pb = players[b]
		var w: int = outcome.get("winner", -1)
		var dmg := 0
		if w == a:
			dmg = int(round(float(outcome.get("b_alive", 0)) * damage_weight()))
			pb.take_damage(dmg)
			if pb.eliminated:
				player_eliminated.emit(b)
		elif w == b:
			dmg = int(round(float(outcome.get("a_alive", 0)) * damage_weight()))
			pa.take_damage(dmg)
			if pa.eliminated:
				player_eliminated.emit(a)
		# 平局：双方都不掉血（云顶同口径）
		return
	# PvE / BOSS：输了扣血，扣的量 = 敌方存活数 x 回合权重
	#
	# ⚠️⚠️ 2026-10-27 修：这里原来读 outcome["winner"] 当**玩家下标**用，
	#     但调用方传的是 EveBattleSimulator 的 **winner_team**（0=己方 / 1=敌方）。
	#     两者数值空间不同 ⇒ 玩家下标正好是 1 的那个人（队里第二个）
	#     永远判定成"获胜"，全程不掉血（实测 hp 恒定 100）。
	#     改用显式的 a_won 布尔，杜绝这种"两个 0/1 撞车"。
	var a_won: bool = bool(outcome.get("a_won", false))
	if not a_won:
		var d2: int = int(round(float(outcome.get("b_alive", 0)) * damage_weight()))
		if pa.take_damage(d2):
			player_eliminated.emit(a)


func _next_round() -> void:
	round += 1
	if round > rounds_in_stage():
		round = 1
		stage += 1


func _check_end() -> void:
	var alive := alive_players()
	if alive.size() <= 1:
		finished = true
		var win := -1
		if alive.size() == 1:
			win = players.find(alive[0])
		match_over.emit(win)


## 当前进度描述（HUD / 日志用）
func progress() -> Dictionary:
	return {
		"stage": stage,
		"round": round,
		"rounds_in_stage": rounds_in_stage(),
		"kind": round_kind(),
		"alive": alive_players().size(),
		"total": players.size(),
		"finished": finished,
	}
