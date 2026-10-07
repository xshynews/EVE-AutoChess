extends RefCounted
class_name EveEnemyComps

## EVE 自走棋 —— 敌人编组表（甲部 E）
##
## ⚠️ 本文件是【唯一真源】。编组 ID / 显示名 / 站位模板 / 成员列表一律照抄。
##
## 数据来源：`F:\eve-chess\重启交接-2026-09-17\附件\03_敌人编组表.csv`
##
## ── 为什么是手写配方而不是「让敌人也跑一套买船逻辑」（交接文档 §6.1）──
##    手写编组的收益是难度可控、可复现、可单点调节 ——
##    改一个节点的难度不需要重跑整体平衡。
##
## ── 成员列表的顺序有意义 ────────────────────────────────────
##    它是【编成】的书写顺序（旗舰打底 → 输出 → 后勤），
##    将来接站位模板时下标要与布局数组一一对应（交接文档 §6.3）。
##
## ── 关于 formation 字段（站位模板）────────────────────────────
##    FRONT / MID / BACK / SPREAD / ESCORT / WEDGE 六种。
##    ⚠️ 本阶段（A）**尚未消费**它：A 阶段的目标是「一局游戏这条循环」，
##       敌方站位沿用 `EveBattleArena.default_formation()` 的通用阵列。
##       理由见路线文档 §3①：站位一旦有两份真相源就会漂移。
##       模板排布属于阶段 C，届时由 arena 把「行号」换算成 z 坐标，
##       本表只负责「第 i 个成员站第几行」。
##    字段照实保留，是因为它是权威数据 —— 删掉就丢了信息。

## 编组。键 = 编组 ID（与节点表的 comp 列一一对应）
const COMPS: Dictionary = {
	"pirate_scout": {
		"name": "游荡掠夺者", "formation": "FRONT",
		"ships": ["slasher", "incursus"],
	},
	"pirate_raider": {
		"name": "劫掠小队", "formation": "SPREAD",
		"ships": ["kestrel", "thrasher", "punisher"],
	},
	"pirate_wing": {
		"name": "掠袭联队", "formation": "FRONT",
		"ships": ["catalyst", "talwar", "coercer", "corax"],
	},
	"pirate_pack": {
		"name": "突击狼群", "formation": "FRONT",
		"ships": ["slasher", "rifter", "thrasher", "talwar"],
	},
	"elite_sniper": {
		"name": "远程狙击组", "formation": "BACK",
		"ships": ["drake", "ferox", "caracal"],
	},
	"pirate_convoy": {
		"name": "海盗护航队", "formation": "ESCORT",
		"ships": ["osprey", "stabber", "coercer", "talwar"],
	},
	"pirate_battlegroup": {
		"name": "海盗战群", "formation": "SPREAD",
		"ships": ["moa", "thorax", "omen", "rupture"],
	},
	"elite_vanguard": {
		"name": "精锐先锋", "formation": "WEDGE",
		"ships": ["dragoon", "coercer", "incursus", "catalyst"],
	},
	"elite_phalanx": {
		"name": "重装方阵", "formation": "SPREAD",
		"ships": ["incursus", "tristan", "algos", "catalyst", "thorax", "vexor"],
	},
	"boss_pirate_lord": {
		"name": "边境海盗王", "formation": "ESCORT",
		"ships": ["abaddon", "myrmidon", "drake", "caracal", "scythe", "thorax"],
	},
}

## 站位模板全集（阶段 C 消费，这里只做合法性校验）
const FORMATIONS: Array[String] = ["FRONT", "MID", "BACK", "SPREAD", "ESCORT", "WEDGE"]


## 表自检（脚本加载时自动跑一次）
##
## 与 EveShipDatabase._static_init 同一个理由：编组里写错一个船 id
## 不会报错，只会在某个节点安静地少一艘敌人 —— 那种问题要打到第 13 关才发现。
static func _static_init() -> void:
	for p in validate():
		push_warning("[EveEnemyComps] 数据有问题：%s" % p)


## 返回问题清单（空 = 全对）
static func validate() -> PackedStringArray:
	var out := PackedStringArray()
	var known := {}
	for row in EveShipTable.ROWS:
		known[String(row[0])] = true
	for id in COMPS.keys():
		var c: Dictionary = COMPS[id]
		var ships: Array = c["ships"]
		if ships.is_empty():
			out.append("%s 没有成员" % id)
		if not FORMATIONS.has(String(c["formation"])):
			out.append("%s 的站位模板未知：%s" % [id, c["formation"]])
		for s in ships:
			if not known.has(String(s)):
				out.append("%s 引用了不存在的船 id：%s" % [id, s])
	return out


## 取一个编组。不存在返回 {}
static func by_id(comp_id: String) -> Dictionary:
	if not COMPS.has(comp_id):
		return {}
	return COMPS[comp_id]


static func display_name(comp_id: String) -> String:
	var c := by_id(comp_id)
	return String(c.get("name", "未知编组")) if not c.is_empty() else "未知编组"


static func ship_ids(comp_id: String) -> Array:
	var c := by_id(comp_id)
	return c.get("ships", []) if not c.is_empty() else []


static func size_of(comp_id: String) -> int:
	return ship_ids(comp_id).size()
