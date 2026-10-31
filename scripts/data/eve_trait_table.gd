extends RefCounted
class_name EveTraitTable

## EVE 自走棋 —— 羁绊表
##
## ══════════════════════════════════════════════════════════════════
##  数据来源（唯一真源）
## ══════════════════════════════════════════════════════════════════
##  `data/source_csv/02_羁绊系统表.csv`
##  12 行逐条直录：阈值与效果文本一字不改。
##
##  羁绊的三条线全部来自权威数值表的三列，没有额外发明：
##    势力 FACTION ← EveShipTable.faction （4 条）
##    武器 WEAPON  ← EveShipTable.weapon  （4 条）
##    防御 DEFENSE ← EveShipTable.defense （2 条）
##
## ── ⚠️ 2026-09-20 修正（阶段 B）──────────────────────────────────
##  上一版把三组的阈值统一写成 [2,4] / [2,4,6] / [2,4,6]，
##  那是从 V3 布局稿的 n/m 分母反推的**示意值**，不是设计数值。
##  CSV 的真相是：
##    势力 [2, 4]      武器 [3, 6]      防御 [3, 6]
##  武器/防御的第一档要 3 艘、满档要 6 艘 —— 比示意值严格得多，
##  这直接决定「凑羁绊」是不是一个真决策，所以必须按表改回来。
##
## ── 效果的落地口径 ──────────────────────────────────────────────
##  CSV 的效果文本里有两类东西：
##    ①【可被现有战斗核心消费的数值】—— 装甲/护盾/攻击/攻击间隔/移速/固定血量。
##       这些写成 `apply` 字典，由 EveRunState.apply_synergies_to() 真正乘进舰船。
##    ②【特殊机制】—— 灼烧 / 溅射 / 闪避 / 暴击 / 破甲 / 微晕 / 无敌 / 回血…
##       战斗核心（EveCombatCore）里目前没有这些机制，**不编**。
##       它们逐条列在 `pending` 里，UI 用 tooltip 如实展示「这条还没实装」，
##       绝不在工程里假装生效 —— 假装生效比不生效更糟。
##
##  ── 加成的受益范围 ────────────────────────────────────────────
##  按云顶的常规读法：**只有带该羁绊的船吃到加成**（艾玛 +20% 装甲 = 场上艾玛船 +20%）。
##  CSV 没写范围，这是一次明确的工程选择；若设计要「全队受益」，
##  改 EveRunState.apply_synergies_to() 里的 _affected() 一处即可。

## ★ 2026-10-10（i18n）：术语取词（见 `eve_terms.gd` 顶注）。
##
## ⛔⛔ **`name` 是逻辑键、`label` 才是显示名**。`EFFECTS` 按 `name` 查表、
##   `count()` 按 `name` 计数、`ship_has()` 按 `name` 比较 ——
##   把 `name` 翻成英文 = 羁绊静默失效（凑齐了不加属性、一条报错都没有）。
const TERMS := preload("res://scripts/core/eve_terms.gd")

## 分组顺序 = 舰队构成窗的显示顺序。tiers 来自 CSV 的「一档阈值 / 二档阈值」。
const GROUPS: Array = [
	{"key": &"faction", "label": "势力 FACTION", "tiers": [2, 4]},
	{"key": &"weapon", "label": "武器 WEAPON", "tiers": [3, 6]},
	{"key": &"defense", "label": "防御 DEFENSE", "tiers": [3, 6]},
	# ★ 2026-10-26 新增（用户：「新加两个羁绊，电子战和后勤」）。
	#   后勤的来源**不是新造的**：权威表第 13 列 `logistics` 早就有值（8 艘，每族 2 艘），
	#   而且维修机制是真的在跑（见 eve_ship.logistics_repair / _repair_one）。
	#   所以这条线只是「把已有的那件事放大」，不需要新机制。
	#   ⚠️ 单成员组：组里只有「后勤」一条 ⇒ 计数 = 场上后勤船数。
	{"key": &"logi", "label": "后勤 LOGISTICS", "tiers": [2, 4]},
	# ★ 2026-10-26 新增（用户：「新加两个羁绊，电子战和后勤」）。
	#   兵源（用户定：**每族一艘护卫 + 一艘巡洋**，共 8 艘 —— 战列太难拿，
	#   而电子战必须是「中期就能凑出来」的羁绊）。
	#   ⚠️ 阈值 [2,4,6]：和武器/防御同口径（3 档、6 艘满档）。
	#   数值 5% / 10% / 15% 由用户直接指定（「从 5% 以 5% 递增到 15%」）。
	#   效果 = **削敌方**（攻击间隔 ×(1+5~15%)），是全表唯一一条负向羁绊，
	#   落在 `EveFleetFactory.build_enemy` 那一侧，见 `EveRunState.enemy_cycle_pct()`。
	{"key": &"ew", "label": "电子战 ELECTRONIC WARFARE", "tiers": [2, 4, 6]},
]


## 电子战的兵源（8 艘 = 4 族 × 护卫 1 + 巡洋 1）。
##
## ⚠️ **权威船表里没有「电子战」这一列**（52 艘只有 faction/weapon/defense/logistics），
##    所以名单只能记在这里 —— 但它必须像权威列一样是**唯一真源**：
##    计数、档案行、商店预览全走同一份，⛔ 别在别处再抄一份。
##
## ── 名单怎么来的（★ 2026-10-27 用户改过一次，别按旧名单推理）────────────
##  · 规则由用户定：**每族出护卫 1 + 巡洋 1，共 4×2 = 8 艘**。
##  · 成员由用户逐艘点名：
##      加达里 小鹰级 / 巨鸟级 · 盖伦特 特里斯坦级 / 狂怒者级
##      米玛塔尔 伐木者级 / 刺客级 · 艾玛 刽子手级 / 启示级
##  · ⚠️ 其中 lore 上最像电子战的只有 3 艘（特里斯坦/狂怒者＝无人机 ECM、
##    伐木者＝停滞缠绕），其余是游戏性指派 —— ⛔ 不要倒过来编 lore。
##  · ⚠️ 权威船表里**没有「电子战」这一列**，所以名单只能记在这里；但它必须
##    像权威列一样是**唯一真源**（计数 / 档案行 / 商店预览全走同一份）。
##  · ⚠️ 用户同时把这几艘的**数值归一**了（见 `eve_ship_table.gd` 对应行）：
##    攻击型的攻击降到同族防御型档位、防御型的血降到攻击型档位 ⇒ 电子战船
##    的战斗力被刻意抹平。改这几艘的数值前先看清那条注释。
##  · 全表里 lore 上最像电子战的还有毒蝎级（ECM 战列）与末日沙场级（毁电战列），
##    但用户明确要求兵源只取护卫 + 巡洋 ⇒ 这两艘**不在本羁绊里**。
const EW_SHIP_KEYS: PackedStringArray = [
	"condor", "moa",           # 加达里（小鹰级 / 巨鸟级）
	"tristan", "vexor",        # 盖伦特（特里斯坦级 / 狂怒者级）
	"slasher", "stabber",      # 米玛塔尔（伐木者级 / 刺客级）
	"executioner", "omen",     # 艾玛（刽子手级 / 启示级）
]

## 电子战羁绊的识别色（紫 = 「干扰 / 异常」的通用语义，刻意不用任何一族识别色，
## 因为这条羁绊是**跨族**的）。
## ★ 2026-10-31：抽出来当常量 —— 羁绊窗色块、档案行、商店/抽奖卡面标签
##   全部读这一份，⛔ 别在 UI 里再写一遍 `Color(0.66, 0.55, 0.95)`（改了必然漂移）。
const EW_COLOR := Color(0.66, 0.55, 0.95)

## 成员（显示名 + 颜色）。颜色约定：
##   派系用 EVE 官方识别色（艾玛金 / 加达里青 / 盖伦特绿 / 米玛塔尔红），
##   武器统一用冷青（它们本来就同类），防御统一用橙（都是抗性）。
static func members(group: StringName) -> Array[Dictionary]:
	match group:
		&"faction":
			return [
				{"name": "艾玛",     "label": TERMS.trait_member(&"faction", "艾玛"),     "color": EveWindow.C_FACTION_AMARR},
				{"name": "加达里",   "label": TERMS.trait_member(&"faction", "加达里"),   "color": EveWindow.C_FACTION_CALDARI},
				{"name": "盖伦特",   "label": TERMS.trait_member(&"faction", "盖伦特"),   "color": EveWindow.C_FACTION_GALLENTE},
				{"name": "米玛塔尔", "label": TERMS.trait_member(&"faction", "米玛塔尔"), "color": EveWindow.C_FACTION_MINMATAR},
			]
		&"weapon":
			return [
				{"name": "激光炮", "label": TERMS.trait_member(&"weapon", "激光炮"), "color": EveWindow.C_WEAPON},
				{"name": "混合炮", "label": TERMS.trait_member(&"weapon", "混合炮"), "color": EveWindow.C_WEAPON},
				{"name": "射弹炮", "label": TERMS.trait_member(&"weapon", "射弹炮"), "color": EveWindow.C_WEAPON},
				{"name": "导弹",   "label": TERMS.trait_member(&"weapon", "导弹"),   "color": EveWindow.C_WEAPON},
			]
		&"defense":
			return [
				{"name": "甲抗", "label": TERMS.trait_member(&"defense", "甲抗"), "color": EveWindow.C_DEFENSE},
				{"name": "盾抗", "label": TERMS.trait_member(&"defense", "盾抗"), "color": EveWindow.C_DEFENSE},
			]
		&"logi":
			# 单成员：整条羁绊就是「场上后勤船的数量」。颜色取卡面 N 标的绿（同一语义）。
			return [
				{"name": "后勤", "label": TERMS.trait_member(&"logi", "后勤"),
						"color": Color(0.52, 0.86, 0.68)},
			]
		&"ew":
			# 单成员，同「后勤」的理由。紫色见 `EW_COLOR` 的说明。
			return [
				{"name": "电子战", "label": TERMS.trait_member(&"ew", "电子战"),
						"color": EW_COLOR},
			]
	return []


## 效果表。结构：[组][成员][阈值] = {"text", "apply", "pending"}
##
## `apply` 的键（EveShip 侧消费）：
##   armor_pct      装甲 +x（乘 max_hp.armor / max_hp.hull）
##   shield_pct     护盾 +x（乘 max_hp.shield）
##   hull_flat      结构 +固定值
##   shield_flat    护盾 +固定值
##   attack_pct     攻击 ×(1+x)（同时乘 weapon_damage 与展示用 attack）
##   cycle_pct      开火间隔 ×(1−x)
##   speed_pct      移速 ×(1+x)
##   armor_pierce   对装甲层的穿甲比例（0~1，1 = 完全无视装甲抗性）
##
## ⚠️ CSV 的表头是「二档效果(累计)」—— 二档取该列的值**替换**一档，不是叠加。
##    （数值上也是自洽的：激光炮 ×1.21 = 1.1²，两种读法同值。）
const EFFECTS: Dictionary = {
	&"faction": {
		"艾玛": {
			2: {"text": "装甲 +20%",
				"apply": {"armor_pct": 0.20}, "pending": []},
			4: {"text": "装甲 +44% · 激光灼烧 3s",
				"apply": {"armor_pct": 0.44}, "pending": ["激光灼烧 3s"]},
		},
		"加达里": {
			2: {"text": "护盾 +20%",
				"apply": {"shield_pct": 0.20}, "pending": []},
			4: {"text": "护盾 +44% · 导弹溅射",
				"apply": {"shield_pct": 0.44}, "pending": ["导弹溅射"]},
		},
		"盖伦特": {
			2: {"text": "攻击间隔 ×0.85",
				"apply": {"cycle_pct": 0.15}, "pending": []},
			4: {"text": "攻击间隔 ×0.85 · 每第 5 次普攻双倍",
				"apply": {"cycle_pct": 0.15}, "pending": ["每第 5 次普攻双倍"]},
		},
		"米玛塔尔": {
			2: {"text": "移速 ×1.2",
				"apply": {"speed_pct": 0.20}, "pending": []},
			4: {"text": "移速 ×1.2 · 射弹炮 15% 闪避",
				"apply": {"speed_pct": 0.20}, "pending": ["射弹炮 15% 闪避"]},
		},
	},
	&"weapon": {
		"激光炮": {
			3: {"text": "攻击 ×1.1 · 无视 10% 装甲",
				"apply": {"attack_pct": 0.10, "armor_pierce": 0.10}, "pending": []},
			6: {"text": "攻击 ×1.21 · 无视 25% 装甲",
				"apply": {"attack_pct": 0.21, "armor_pierce": 0.25}, "pending": []},
		},
		"混合炮": {
			3: {"text": "攻击 ×1.1 · 命中减速 15%",
				"apply": {"attack_pct": 0.10}, "pending": ["命中减速 15%"]},
			6: {"text": "攻击 ×1.21 · 暴击率 25%",
				"apply": {"attack_pct": 0.21}, "pending": ["暴击率 25%"]},
		},
		"射弹炮": {
			3: {"text": "攻击 ×1.1 · 暴击 ×1.5（10%）",
				"apply": {"attack_pct": 0.10}, "pending": ["暴击 ×1.5（10%）"]},
			6: {"text": "攻击 ×1.21 · 命中破甲 −5% × 3 层",
				"apply": {"attack_pct": 0.21}, "pending": ["命中破甲 −5% × 3 层"]},
		},
		"导弹": {
			3: {"text": "攻击 ×1.1 · 必中，盾拦 50%",
				"apply": {"attack_pct": 0.10}, "pending": ["必中，盾拦 50%"]},
			6: {"text": "攻击 ×1.21 · 首击微晕 0.5s",
				"apply": {"attack_pct": 0.21}, "pending": ["首击微晕 0.5s"]},
		},
	},
	&"defense": {
		"甲抗": {
			3: {"text": "结构 +150",
				"apply": {"hull_flat": 150.0}, "pending": []},
			6: {"text": "结构 +300 · 每秒回复 5",
				"apply": {"hull_flat": 300.0}, "pending": ["每秒回复 5"]},
		},
		"盾抗": {
			3: {"text": "护盾 +150",
				"apply": {"shield_flat": 150.0}, "pending": []},
			6: {"text": "护盾 +300 · 破盾 1s 无敌",
				"apply": {"shield_flat": 300.0}, "pending": ["破盾 1s 无敌"]},
		},
	},
	# ★ 2026-10-26 新增「后勤」。**只放大已有的维修机制**（不编新机制）：
	#   维修量 = LOGISTICS_REPAIR[cost]（12 / 56 / 120 点每次），间隔 2.0s。
	#
	#   数值来自 `tools/sim_winrate.gd` 的 ②c 实测（40 种子 × 3 节点 = 120 局/格，
	#   固定编队只改倍率，把「倍率价值」和「多带后勤船的成本」剥开量）：
	#     2 档 +30%：胜 77/120 → 77/120、存活 3.4 → 3.5 —— **完全测不出差别**
	#     2 档 +50%：胜 77 → 79、存活 3.4 → 3.6   ⇒ 一档给 50% 才有「凑出来了」的手感
	#     4 档 +75%·间隔×0.8：胜 77 → 80、存活 3.2 → **4.0**（+0.8 艘，最明显的收益）
	#     4 档 +120%·间隔×0.7：与上一行**完全同值**（胜 80 / 存活 4.0）⇒ 维修已经饱和
	#         （兜底的治疗被「目标已死/已满」吃掉），再往上加是无效数值。
	#   ⛔ 所以 4 档停在 +75%·×0.8；⛔ 别把 2 档退回 30%（实测等于没有）。
	#
	#   ⚠️ 读表注意：同一张表里「我挨伤」是**上涨**的（1074 → 1189 → 2185）。
	#      那不是变弱 —— 维修让战斗拖长，总挨伤自然变多，但**存活数同时上涨**
	#      （4 档 3.2 → 4.0）。判后勤的收益只能看 `存活`，⛔ 别看 `挨伤`。
	#      同理「我输出」会**下降**（少了 2 艘火力船），那是编队成本，不是羁绊减益。
	#
	#   对比口径：势力 4 档是全族 +44% 装甲；后勤 4 档高得多，但**只对后勤船生效**，
	#   且后勤船攻击只有同级一半（LOGISTICS_ATTACK 10 vs 40），多带的后勤船本身就是机会成本。
	&"logi": {
		"后勤": {
			2: {"text": "维修量 +50%",
				"apply": {"repair_pct": 0.50}, "pending": []},
			4: {"text": "维修量 +75% · 维修间隔 ×0.8",
				"apply": {"repair_pct": 0.75, "repair_cycle_pct": 0.20}, "pending": []},
		},
	},
	# ★ 2026-10-26 新增「电子战」。**唯一一条削敌方的羁绊**：
	#   把敌方全体开火间隔 ×(1 + 5% / 10% / 15%)（不是加给自己的船）。
	#
	#   数值换算（给设计侧对账用）：
	#     +5%  ⇒ 敌方 DPS ×1/1.05 = 0.952（−4.8%）  ⇒ 我方等效血 +5.0%
	#     +10% ⇒ ×1/1.10 = 0.909（−9.1%）           ⇒ +10.0%
	#     +15% ⇒ ×1/1.15 = 0.870（−13.0%）          ⇒ +15.0%
	#   ⇒ 满档 15% ≈ **全队** +15% 等效血（不分势力、不挑武器）。
	#
	#   ★ 2026-10-26 实测（`sim_winrate` ②c：固定 6 船队，只把敌方间隔乘 m；
	#     40 种子 × 3 节点 = 120 局/格）：
	#       m=1.00  胜 102/120 · 存活 3.4 · 我挨伤 803
	#       m=1.05  胜 111/120 · 存活 3.4 · 我挨伤 780（−2.9%）
	#       m=1.10  胜 107/120 · 存活 3.5 · 我挨伤 764（−4.9%）
	#       m=1.15  胜 112/120 · 存活 3.5 · 我挨伤 743（−7.5%）
	#     ⇒ 挨伤**单调**下降（数值口径可信），胜率 +5~8pp（样本内偏噪但方向一致）。
	#     ⚠️ 实测挨伤只降 7.5% 而不是 13%：敌方 DPS 变低 ⇒ 战斗变长 ⇒ 多挨几轮，
	#        所以「等效血 +15%」是上限，真实收益约一半。别照字面把 15% 当 +15% 血。
	#   比「势力 4 档 +44%」弱，但势力那条只加本族；而且电子战是乘在敌方输出上，
	#   与任何加血/加甲/维修都是**乘法叠加**，不会贬值。
	#   ⚠️ `enemy_cycle_pct` 由 `EveRunState.enemy_cycle_pct()` 取出，
	#     在 `EveFleetFactory.build_enemy()` 里落到敌舰 —— ⛔ 别在 `_apply_synergy` 里加，
	#     那是「给自己的船」的管道，落到敌方要换一侧（见那里的注释）。
	#
	# ★★ 2026-10-31 改档（用户定案，**重做机制**，不是调数值）：
	#   旧档 2/4/6 = 敌方全体开火间隔 +5/10/15%。实测满档只值 −7.5% 挨伤，
	#   用户判为「废物」。新档改成「重现 EVE 锁定机制」：
	#
	#     档位 | 锁定目标减伤 | 敌方全体开火间隔
	#     2 艘 |    −30%      |        —
	#     4 艘 |    −30%      |      +10%
	#     6 艘 |    −40%      |      +20%
	#
	#   ⚠️ 关键差异：**减伤只作用于「该电子船正锁定的那一艘」**，不是敌方全体。
	#     3 艘电子船锁 3 个目标 ⇒ 3 个目标被削；锁同一个目标 ⇒ 只削一次（取最强）。
	#     所以覆盖面是玩家的**编队选择**，不是羁绊等级 —— 这是与旧档的本质区别。
	#
	#   ★★ 2026-10-31（第二轮，用户：「按你的建议落地」）：2/4 档 20% → **30%**。
	#     第一轮 20/20/40 的 A/B（120 局/格，见 `tools/sim_winrate.gd`
	#     `_ew_ab_experiment()`）测出 2 档 **−1pp（白给）**、4 档 +7pp（不如旧档 +10pp）。
	#     原因是「只锁一艘 × 只有 20%」在 3~6 艘敌人面前覆盖面太小。
	#     提到 30% 是用户原话给过的上限（「减伤需要高达 20% 到 30%」），
	#     ⛔ 没有加「同时削 2 个目标」—— 那会让玩家看不懂自己在削谁，
	#        也破坏「重现 EVE 锁定」这个可解释的核心。
	#     6 档保持 40% 不动（第一轮已达标、且是用户亲口定的数）。
	#
	#   ⚠️ 旧档的实测记录保留在下方，它是「为什么 15% 间隔不够」的证据链：
	#     m=1.00 胜 102/120 · 挨伤 803 / m=1.05 胜 111 · 780 / m=1.10 胜 107 · 764
	#     / m=1.15 胜 112 · 743（−7.5%）
	&"ew": {
		"电子战": {
			2: {"text": "锁定目标伤害 −30%",
				"apply": {"ew_lock_reduce": 0.30}, "pending": []},
			4: {"text": "锁定目标伤害 −30% · 敌方攻击间隔 +10%",
				"apply": {"ew_lock_reduce": 0.30, "enemy_cycle_pct": 0.10}, "pending": []},
			6: {"text": "锁定目标伤害 −40% · 敌方攻击间隔 +20%",
				"apply": {"ew_lock_reduce": 0.40, "enemy_cycle_pct": 0.20}, "pending": []},
		},
	},
}


## 表自检（脚本加载时自动跑一次）
##
## 与 EveShipDatabase._static_init 同一个理由：少写一个成员或一个档位不会报错，
## 只会在某个玩家凑齐羁绊时安静地什么都不加 —— 那种问题极难发现。
static func _static_init() -> void:
	for p in validate():
		push_warning("[EveTraitTable] 数据有问题：%s" % p)


## 返回问题清单（空 = 全对）
static func validate() -> PackedStringArray:
	var out := PackedStringArray()
	for g in GROUPS:
		var key: StringName = g["key"]
		var tiers: Array = g["tiers"]
		var tbl: Dictionary = EFFECTS.get(key, {})
		if tbl.is_empty():
			out.append("组 %s 没有效果表" % key)
			continue
		for m in members(key):
			var name := String(m["name"])
			if not tbl.has(name):
				out.append("%s 的成员「%s」缺效果" % [key, name])
				continue
			for t in tiers:
				var e: Dictionary = tbl[name].get(int(t), {})
				if e.is_empty():
					out.append("%s / %s 缺 %d 档效果" % [key, name, int(t)])
					continue
				if String(e.get("text", "")).is_empty():
					out.append("%s / %s 的 %d 档没有效果文本" % [key, name, int(t)])
	return out


## 某一组的档位阈值表
static func tiers_of(group: StringName) -> Array:
	for g in GROUPS:
		if g["key"] == group:
			return g["tiers"]
	return []


## 某一组的档位上限（= 显示成 n/m 的那个 m）
static func max_tier(group: StringName) -> int:
	var t := tiers_of(group)
	return int(t[t.size() - 1]) if not t.is_empty() else 0


## 判断某个计数是否已跨过「第一档」（用于 UI 的生效高亮）
static func is_active(group: StringName, count: int) -> bool:
	var t := tiers_of(group)
	return count >= int(t[0]) if not t.is_empty() else false


## 当前计数落在了哪一档。返回 {} 表示还没到第一档。
##
## 返回 {"n": int, "text": String, "apply": Dictionary, "pending": PackedStringArray}
static func tier_of(group: StringName, member: String, count: int) -> Dictionary:
	var t := tiers_of(group)
	if t.is_empty():
		return {}
	var hit := 0
	for v in t:
		if count >= int(v):
			hit = int(v)
	if hit == 0:
		return {}
	var tbl: Dictionary = EFFECTS.get(group, {})
	var e: Dictionary = tbl.get(member, {}).get(hit, {})
	if e.is_empty():
		return {}
	var pending := PackedStringArray()
	for p in e.get("pending", []):
		pending.append(String(p))
	return {
		"n": hit,
		"text": String(e.get("text", "")),
		"apply": e.get("apply", {}),
		"pending": pending,
	}


## tooltip 文本：生效的档位 + 已实装/未实装的分界
##
## ⚠️ 未实装的特殊机制必须如实写出来。UI 上加一行「（特殊机制未实装）」
##    比让玩家以为「凑齐了就有效果」要诚实得多。
static func tooltip_for(group: StringName, member: String, count: int) -> String:
	var lines := PackedStringArray()
	for v in tiers_of(group):
		var e: Dictionary = EFFECTS.get(group, {}).get(member, {}).get(int(v), {})
		var reached := count >= int(v)
		lines.append("%s%d 艘：%s" % ["▸ " if reached else "· ", int(v),
				String(e.get("text", "—"))])
		if reached and not e.get("pending", []).is_empty():
			lines.append("    未实装：%s" % ", ".join(PackedStringArray(e["pending"])))
	lines.append("")
	lines.append("当前 %d 艘（%s）" % [count, group_label(group)])
	return "\n".join(lines)


static func group_label(group: StringName) -> String:
	for g in GROUPS:
		if g["key"] == group:
			# ★ 2026-10-10（i18n）：显示名走取词（`TRAITGROUP.*` 是**本作自己的**
			#   UI 文案，不是 EVE 术语 ⇒ 手写在 strings.csv 里，不归生成器管）。
			return TERMS.trait_group(group, String(g["label"]))
	return ""


## 统计一支舰队在某一组的羁绊计数
##
## ships 里每个元素只要有 traits（PackedStringArray）就能算，
## 不要求是 EveShip —— 商店卡预览、场上舰队、备战席都能用同一个函数。
##   → {"艾玛": 2, "激光炮": 1, …}
static func count(ships: Array, group: StringName) -> Dictionary:
	var known := {}
	for m in members(group):
		known[m["name"]] = 0
	for s in ships:
		var traits: PackedStringArray = _traits_of(s)
		var hit := ""
		# ⚠️ 一艘船在每一组里只贡献 1 点。
		#    不能把 traits 全扫一遍加总 —— 一旦以后 traits 里出现同组两个标签就会算重复。
		#    这里按「命中该组成员即止」来写，天然防止重复计数。
		if group == &"faction":
			hit = _first_in(traits, ["艾玛", "加达里", "盖伦特", "米玛塔尔"])
		elif group == &"weapon":
			hit = _first_in(traits, ["激光炮", "混合炮", "射弹炮", "导弹"])
		elif group == &"defense":
			hit = _first_in(traits, ["甲抗", "盾抗"])
		elif group == &"logi":
			hit = "后勤" if _is_logi(s) else ""
		elif group == &"ew":
			hit = "电子战" if _is_ew(s) else ""
		if hit != "" and known.has(hit):
			known[hit] = int(known[hit]) + 1
	return known


## 取出一个元素的三组羁绊标签。
##
## ⚠️ 三种来源，最后一种是【必须有】的：
##    ① EveShip            —— 战斗场景里的实例（自带 traits）
##    ② 商店卡的字典        —— EveShipDatabase 派生出来的，带 traits
##    ③ **编制条目**        —— EveRunState.field / bench 里的
##                            {"ship_key", "star", "cell"}，**没有 traits**。
##    ③ 如果不在里回查数据库，count() 对编制永远返回 0 ——
##    症状是「凑齐 4 艘艾玛，羁绊窗一个都不亮、装甲也没加」，而且不报错。
##    （2026-09-20 阶段 B 实测踩到：test-first 写的这条断言把这个洞逮住了。）
static func _traits_of(s) -> PackedStringArray:
	if s == null:
		return PackedStringArray()
	if s is EveShip:
		return (s as EveShip).traits
	if s is Dictionary:
		var d: Dictionary = s
		# ⚠️ 这里必须写 `: Variant`，不能写 `:=` ——
		#    Dictionary.get() 返回 Variant，用 := 推断会被本工程的
		#    「推断自 Variant」警告当成错误，直接让整个脚本编译不过。
		var direct: Variant = d.get("traits", null)
		if direct is PackedStringArray and not (direct as PackedStringArray).is_empty():
			return direct
		var k := String(d.get("ship_key", ""))
		if k != "":
			var row := EveShipDatabase.by_id(k)
			var derived: Variant = row.get("traits", null)
			if derived is PackedStringArray:
				return derived
	return PackedStringArray()


static func _first_in(traits: PackedStringArray, pool: Array) -> String:
	for t in traits:
		if pool.has(String(t)):
			return String(t)
	return ""


## 是不是后勤船（羁绊「后勤」的唯一判据）。
##
## ⚠️ 三种来源都要认（与 `_traits_of` 同一套理由）：
##   ① `EveShip.is_logistics`（权威表第 13 列）
##   ② 派生字典的 `is_logistics`（商店卡 / 图鉴）
##   ③ 编制条目 `{ship_key, ...}` —— 没有 is_logistics，必须回查数据库
## ⛔ 别拿 `role == "后勤"` 当主键：`role` 是显示字段，权威判据是 `logistics` 列。
static func _is_logi(s) -> bool:
	if s == null:
		return false
	if s is EveShip:
		return (s as EveShip).is_logistics
	if s is Dictionary:
		var d: Dictionary = s
		var direct: Variant = d.get("is_logistics", null)
		if direct != null:
			return bool(direct)
		var k := String(d.get("ship_key", ""))
		if k != "":
			return bool(EveShipDatabase.by_id(k).get("is_logistics", false))
	return false


## 是不是电子战船（羁绊「电子战」的唯一判据）。
##
## ⚠️ 与 `_is_logi` 同一套三种来源的口径：EveShip 用 `ship_key`、字典先看
##    自带的 `is_ew`（测试/预览可以显式声明），否则回查 `ship_key`。
##    ⛔ 判据只有 `EW_SHIP_KEYS` 一份 —— 派生字典里**不另存** `is_ew`
##    （避免「表改了、字典没改」的两份真相）。
## ★ 2026-10-31（用户：「巨鸟等船的卡牌上没有电子战羁绊标签，这不行，加上」）：
##   UI 卡面需要判「这艘船是不是电子战舰」，但 `_is_ew()` 是私有约定。
##   这里开一个**公开入口**，卡面 / 商店 / 抽奖窗统一走它 ——
##   ⛔ 别在 UI 里自己 `EW_SHIP_KEYS.has(...)` 抄一遍（那就成了第二真相源）。
##   ⚠️ 参数同时接受 `EveShip` 与船表 Dictionary（商店/抽奖手里都是 Dictionary）。
static func is_ew_ship(s) -> bool:
	return _is_ew(s)


static func _is_ew(s) -> bool:
	if s == null:
		return false
	if s is EveShip:
		return EW_SHIP_KEYS.has(String((s as EveShip).ship_key))
	if s is Dictionary:
		var d: Dictionary = s
		var direct: Variant = d.get("is_ew", null)
		if direct != null:
			return bool(direct)
		return EW_SHIP_KEYS.has(String(d.get("ship_key", "")))
	return false


## 一艘船在某组里归属哪一条（档案窗显示「这艘船属于哪个势力」用）
static func group_of_ship(ship: EveShip, group: StringName) -> String:
	if ship == null:
		return ""
	match group:
		&"faction": return ship.faction_name()
		&"weapon":  return String(ship.weapon_type)
		&"defense": return String(ship.defense_type)
		&"logi":    return "后勤" if ship.is_logistics else ""
		&"ew":      return "电子战" if _is_ew(ship) else ""
	return ""


## 某艘船是否带某条羁绊 —— 羁绊加成的受益范围判定
static func ship_has(ship: EveShip, group: StringName, member: String) -> bool:
	if ship == null:
		return false
	return group_of_ship(ship, group) == member
