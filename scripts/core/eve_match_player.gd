class_name EveMatchPlayer
extends RefCounted

## 房间里的一名参与者（人 / AI / 以后的网友）。
##
## ⚠️ 它**不是**一局游戏，只是「谁在玩」。一局游戏的私有状态全在 `run` 里
##    （舰队 / 备战席 / 星币 / 等级 / 羁绊）—— 那份 `EveRunState` 单机已经在用，
##    原样复用，一行不改。
##
## `hp` 就是单机里的「信标」，但掉法从「按节点固定扣」改成
## 「按对方存活单位数 x 回合权重扣」（云顶口径，见 docs/多人对战架构）。

const START_HP := 100

var display_name := "玩家"
var is_ai := false
var hp := START_HP
var eliminated := false
var place := 0                ## 名次（淘汰时填）

## 这名玩家的全部私有对局状态（复用单机那份）
var run = null

## AI 玩家的决策器；人类玩家为 null
var brain = null


func _init(p_run = null, p_name := "玩家", p_ai := false) -> void:
	run = p_run
	display_name = p_name
	is_ai = p_ai
	hp = START_HP


func is_alive() -> bool:
	return not eliminated and hp > 0


## 掉血；返回是否因此被淘汰
## 房主权威血量校正（联机 SYNC 用）。
## ⚠️ 不做胜负判定，只把数值与淘汰态对齐 —— 判定仍归房主。
func set_hp_sync(v: int) -> void:
	hp = maxi(0, v)
	if hp <= 0:
		eliminated = true


func take_damage(amount: int) -> bool:
	if amount <= 0:
		return false
	hp = maxi(0, hp - amount)
	if hp <= 0:
		eliminated = true
		return true
	return false


## 这名玩家当前上场了几艘（配对 / 展示用）
func field_count() -> int:
	return run.field.size() if run != null else 0


## 羁绊摘要（配对界面给对手看的）
func trait_summary() -> Array:
	return run.active_synergies() if run != null else []
