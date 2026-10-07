extends RefCounted
class_name EveNodeTable

## EVE 自走棋 —— 15 节点装配表（甲部 F）
##
## ⚠️ 本文件是【唯一真源】。节点的顺序 / 类型 / 编组 / power_scale /
##    战斗时限 / 进场词一律照抄，**不许在别处二次定义**（包括不许在
##    battle_scene 里写 set_stage(1, "接敌", 60.0) 这种字面量）。
##
## 数据来源：`F:\eve-chess\重启交接-2026-09-17\附件\04_节点表_遥望边境.csv`
##    15 行逐条直录，只把「450 tick = 45s」这种展示串换成秒数（秒数在 CSV 里
##    本来就有，只是写在等号右边），没有做任何取舍或合并。
##
## ── 四种节点类型（交接文档 §5.2）──────────────────────────────
##    battle 遭遇战  45s   常规
##    elite  精英    55s   心跳节点
##    event  事件    无战斗  四选一（阶段 C 实装；本阶段表里保留类型与进场词）
##    boss   BOSS    70s   通关战
##
## ── 节点 2 是「全表最聪明的一手」（交接文档 §7 原文）────────────
##    同一张脸 + scale 1.25，不用任何文字就完成了「你该升级了」的教学。
##    ⚠️ 所以 comp 必须保持 pirate_scout 不变 —— 换成新编组这一手就废了。

const TOTAL := 15

## 全表。键名与 CSV 列一一对应（type/comp/scale/time/line）。
const ROWS: Array = [
	{"index": 1, "type": &"battle", "comp": "pirate_scout", "scale": 1.00, "time": 45.0,
		"line": "前方发现两艘散兵级。信号识别为游荡掠夺者。"},
	{"index": 2, "type": &"battle", "comp": "pirate_scout", "scale": 1.25, "time": 45.0,
		"line": "同一批掠夺者又回来了 —— 这次它们装填得更足。"},
	{"index": 3, "type": &"battle", "comp": "pirate_raider", "scale": 1.00, "time": 45.0,
		"line": "三艘舰船呈散兵线展开。这次不是一个方向来的。"},
	{"index": 4, "type": &"event", "comp": "", "scale": 1.0, "time": 0.0,
		"line": "边境信标闪了一下。附近有个废弃中继站。"},
	{"index": 5, "type": &"elite", "comp": "elite_vanguard", "scale": 1.00, "time": 55.0,
		"line": "旗舰信号 —— 精锐先锋，装甲厚得不像海盗。"},
	{"index": 6, "type": &"battle", "comp": "pirate_raider", "scale": 1.30, "time": 45.0,
		"line": "劫掠小队的主力来了。同一套编组，火力更足。"},
	{"index": 7, "type": &"battle", "comp": "pirate_wing", "scale": 1.00, "time": 45.0,
		"line": "四艘舰船压上隔离带 —— 掠袭联队。"},
	{"index": 8, "type": &"battle", "comp": "pirate_pack", "scale": 1.00, "time": 45.0,
		"line": "全部米玛塔尔船体。它们比你快。"},
	{"index": 9, "type": &"elite", "comp": "elite_sniper", "scale": 1.00, "time": 55.0,
		"line": "敌方停在远处，一动不动。它们在等你先进射程。"},
	{"index": 10, "type": &"event", "comp": "", "scale": 1.0, "time": 0.0,
		"line": "信标扫描到一处可回收的补给残骸带。"},
	{"index": 11, "type": &"battle", "comp": "pirate_convoy", "scale": 1.00, "time": 45.0,
		"line": "护航编队。注意最后排那艘 —— 它在给全队回血。"},
	{"index": 12, "type": &"battle", "comp": "pirate_battlegroup", "scale": 1.00, "time": 45.0,
		"line": "四艘巡洋级，四个势力，四种武器。海盗战群。"},
	{"index": 13, "type": &"battle", "comp": "elite_phalanx", "scale": 1.10, "time": 45.0,
		"line": "六艘盖伦特方阵，装甲叠加，全队持续回血。"},
	{"index": 14, "type": &"event", "comp": "", "scale": 1.0, "time": 0.0,
		"line": "最后一次补给窗口。前方就是海盗王的旗舰信号。"},
	{"index": 15, "type": &"boss", "comp": "boss_pirate_lord", "scale": 1.00, "time": 70.0,
		"line": "地狱天使级。边境海盗王本人。"},
]

## 首领节点（1-based）—— 顶条进度方块描边为橙用的就是这张表
const BOSS_INDEXES: Array[int] = [9, 12, 15]

## 类型 → 中文标签（顶条的阶段标签）
const TYPE_LABELS := {
	&"battle": "遭遇战",
	&"elite": "精英战",
	&"event": "事件",
	&"boss": "首领战",
}


## 取第 index 个节点（1-based）。越界返回 {}。
static func by_index(index: int) -> Dictionary:
	if index < 1 or index > ROWS.size():
		return {}
	return ROWS[index - 1]


static func count() -> int:
	return ROWS.size()


## 类型的中文标签
static func label_of(type_key: StringName) -> String:
	return String(TYPE_LABELS.get(type_key, "遭遇战"))


## 是否事件节点（无战斗，面板见 `EveEventTable`）
static func is_event(index: int) -> bool:
	var r := by_index(index)
	return not r.is_empty() and StringName(r["type"]) == &"event"


## 全部事件节点的下标（1-based）。**唯一真源** ——
## 「一局能拿几条事件增益」「事件窗的 n/m 分母是多少」都从这里取，
## 别在 UI 里写死 3（表一改就会对不上）。
static func event_indexes() -> Array[int]:
	var out: Array[int] = []
	for r in ROWS:
		if StringName(r["type"]) == &"event":
			out.append(int(r["index"]))
	return out
