extends RefCounted
class_name EveEnemyComps

## EVE 自走棋 —— 敌人编组表（甲部 E）
##
## ⚠️ 本文件是【唯一真源】。编组 ID / 显示名 / 站位模板 / 成员列表一律照抄。
##
## 数据来源：`data/source_csv/03_敌人编组表.csv`
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

	# ══════════════════════════════════════════════════════════════
	#  困难 / 炼狱专用：单轴编组（每关一个明确考点）
	# ══════════════════════════════════════════════════════════════
	# 为什么基础表不够：基础编组多半把 2~4 种武器混在一起，
	#   ⇒ 玩家买什么都能打，没有「可读的考点」。
	# 这里改成整组同一派系：
	#   ① 敌方因此吃到满档势力 / 防御羁绊（数值真的差一档）；
	#   ② 武器构成单一 ⇒ 玩家的**防御选择**有了唯一正确答案；
	#   ③ 敌方防御单一 ⇒ 玩家的**武器选择**也有了正确答案。
	# ⚠️ 这些编组只在 `EveCampaignTiers.DIFFICULTIES[].comp_overrides`
	#    指向它们时才生效 —— 基础表（简单 / 普通）一行不动。
	"amarr_lance": {
		"name": "艾玛长枪队", "formation": "FRONT",
		"ships": ["punisher", "executioner", "coercer"],
	},
	"amarr_wall": {
		"name": "艾玛铁壁", "formation": "WEDGE",
		"ships": ["dragoon", "coercer", "executioner", "maller"],
	},
	"caldari_wing": {
		"name": "加达里导弹联队", "formation": "SPREAD",
		"ships": ["kestrel", "condor", "cormorant", "corax"],
	},
	"minmatar_rush": {
		"name": "米玛塔尔突击队", "formation": "FRONT",
		"ships": ["slasher", "rifter", "thrasher", "talwar"],
	},
	"minmatar_pack": {
		"name": "米玛塔尔狼群", "formation": "FRONT",
		"ships": ["slasher", "rifter", "thrasher", "talwar", "stabber"],
	},
	"caldari_sniper": {
		"name": "加达里狙击阵", "formation": "BACK",
		"ships": ["drake", "ferox", "caracal", "moa"],
	},
	"logi_convoy": {
		"name": "双后勤护航", "formation": "ESCORT",
		"ships": ["osprey", "scythe", "moa", "rupture"],
	},
	"boss_overlord": {
		"name": "边境霸主", "formation": "ESCORT",
		# ★ 2026-10-24：炼狱 BOSS 改成**纯艾玛重甲群**（单一派系 + 单一武器）。
		#   理由：BOSS 的壁垒要靠「激光炮 6/6 的穿甲」破解，那敌人自己就得是
		#   **装甲墙** —— 否则穿甲这个机制在 BOSS 关没有意义。
		#   6 艘同派系 ⇒ 它自己吃满 势力4(装甲+44%) / 甲抗6(结构+300)。
		"ships": ["abaddon", "prophecy", "maller", "omen", "dragoon", "coercer"],
	},

	# ══════════════════════════════════════════════════════════════
	#  ★★ 2026-10-24：反「小船海」编组（阶段 A 难度重构的第二块）
	# ══════════════════════════════════════════════════════════════
	#
	# ── 为什么必须有这一组 ──────────────────────────────────────
	#   探针实测（tools/sim_winrate.gd「②b / ②c」）暴露了一个死结：
	#   **只买 1 费护卫舰**（点点点打法）反而比认真组队更容易通关，四档
	#   通关率全是 94%。逐场看命中率，原因一目了然：
	#
	#       护卫舰海（信号半径 36 + 环绕姿态）→ 敌方命中率 **5%**
	#       巡洋编队（信号半径 120+）        → 敌方命中率 **25%**
	#
	#   命中公式里的 `angular × sig_res / (tracking × sig)` 让小口径炮塔
	#   完全打不中高速小目标，而**导弹的 tracking 是 999（必中）**，
	#   只受爆炸半径限制 ⇒ 只有「数量够多的小号导弹船」能真的清掉小船海。
	#   这就是现实中「轻导弹/火箭打护卫舰」的对应物，也因此是**唯一**腿。
	#
	# ── 为什么是 12 艘这种"看起来很多"的规模 ─────────────────────
	#   因为杀伤力全部来自**导弹数量**：小导弹单发伤害低，8 艘只能说
	#   稍微削一下（实测：8 艘 ×1.15 打护卫舰海，我方仍 100% 胜），
	#   12 艘才越过"玩家修理量"这个阈值（实测：我方 0% 胜）。
	#   ⚠️ 阈值非常陡（10 艘 100% → 11 艘 13% → 12 艘 0%）：这是
	#      「持续修理 vs 累计伤害」的临界点性质，不是噪声。
	#      所以**别指望用"稍微加两艘"来做微调** —— 微调请改节点数或曲线。
	#
	# ── 为什么它仍然是"考点"而不是"数值墙" ───────────────────────
	#   因为它是**可读、可解**的：
	#     · 编组名与构成一眼可见（一整套加达里小导弹船）；
	#     · 解法在玩家手里 —— 别再堆 1 费小船，改带 2~3 费的中型船
	#       （实测：会玩编队对 12 艘狼群 100% 胜，同一场里 1 费海 0% 胜）；
	#     · 它不动玩家的钱、格子、概率，只是"这关的敌人换了一种打法"。
	#
	# ⚠️ 只在 `EveCampaignTiers` 的 `comp_overrides` 指向时生效。
	#    **简单档一行不动**（它的 comp_overrides 是空字典）。
	"caldari_wolfpack": {
		"name": "加达里导弹狼群", "formation": "SPREAD",
		# 12 艘：全部是加达里小导弹船（1~2 费），整组吃满 导弹/盾抗 羁绊
		"ships": ["kestrel", "condor", "kestrel", "condor", "cormorant", "corax",
				"kestrel", "condor", "cormorant", "corax", "kestrel", "condor"],
	},
	"wolfpack_light": {
		"name": "加达里导弹游骑", "formation": "SPREAD",
		# ★ 困难 / 炼狱的**中间水位**：4 艘小导弹 + 2 艘巡洋导弹船。
		#   为什么不用纯狼群：纯狼群的水位是"0% 或 100%"的断崖
		#   （6 艘 100% → 8 艘 0%），没有中间地带，无法做"会玩能过"的考点。
		#   掺两艘巡洋把杀伤拉到中间，考点仍然单一可读（整组加达里）。
		"ships": ["kestrel", "condor", "cormorant", "corax", "moa", "caracal"],
	},
	"pirate_lord_escort": {
		"name": "海盗王护航群", "formation": "ESCORT",
		# BOSS 本体（原 `boss_pirate_lord` 逐字保留）+ 6 艘小导弹护航。
		#
		# ── 为什么 BOSS 必须挂反小船编组（这是全局最关键的改动）────────
		#   ⚠️ 通关判定只有一个闸门 = **打得过 BOSS**。只要 BOSS 不带
		#      必中武器，"只堆 1 费护卫舰"的打法就能靠"打不中我"免费蹭过终局：
		#      中段哪怕连输几关（总代价 < 100），信标也不会归零
		#      ⇒ 玩家走到 N15、赢一场、通关。
		#      所以**中间节点再怎么设计都拦不住小船海**，反小船考点必须落在 BOSS 上。
		#
		#   实测（16 局/格 · 普通口径 ×1.05 · 不吃的羁绊）：
		#       乱点 0% / 会玩 29% / 认真 46%  ← 正是"不换船就过不去"
		"ships": ["abaddon", "myrmidon", "drake", "caracal", "scythe", "thorax",
				"kestrel", "condor", "cormorant", "corax", "kestrel", "condor"],
	},
	"pirate_lord_light": {
		"name": "海盗王近卫群", "formation": "ESCORT",
		# 普通档 BOSS：原海盗王 + **3 艘**小导弹护航。
		#
		# ⚠️ 这里的 3 艘是**实测调出来的水位**，理由是"终局闸门"这个位置很特殊：
		#   · 只要 BOSS 不带必中武器，"只堆 1 费护卫舰"就能靠"打不中我"
		#     免费赢下终局 ⇒ 中段输多少都不影响通关（信标够用）；
		#   · 2 艘时实测：乱点 69% / 会玩 75% / 认真 81% —— 还是分不开；
		#   · 4 艘时乱点掉到 31%（略低于普通档目标 35~45%）；
		#   · 6 艘时又把认真玩的人一起打死（16 局 0 通关）。
		#   3 艘 = 让"小船海"在终局失效，同时正经编队还能过。
		"ships": ["abaddon", "myrmidon", "drake", "caracal", "scythe", "thorax",
				"kestrel", "condor", "cormorant"],
	},
	"overlord_escort": {
		"name": "霸主护航小队", "formation": "ESCORT",
		# 困难档 BOSS = 装甲墙本体（纯艾玛，保住"穿甲机制"的意义）+ 3 艘小导弹。
		#
		# ⚠️ 这一格的斜率极陡（导弹必中 ⇒ 每多一艘都是**确定性**伤害，
		#    不像炮塔受命中率波动影响），实测三档：
		#      3 艘 → 乱点 13% / 认真 75%
		#      4 艘 → 乱点  6% / 认真 63~75%
		#      5 艘 → 乱点  0% / 认真 44%
		#    取 3 艘：乱点落在困难档目标（10~25%）里。认真的那侧仍偏高
		#    （目标 55~65%），但再抬护航就会把"会玩"一起打死 —— 那是墙不是考点。
		# ⚠️ 炼狱不用这一组，见 `INFERNO_COMPS`。
		"ships": ["abaddon", "prophecy", "maller", "omen", "dragoon", "coercer",
				"kestrel", "condor", "cormorant"],
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


## 编组是否存在（难度档的 comp_overrides 回退判定用）
static func has_comp(comp_id: String) -> bool:
	return COMPS.has(comp_id)


## 站位模板 → 具体坐标（世界米，与 `EveBattleArena.default_formation()` 同口径）
##
## ★ 2026-10-23（阶段 C 第一刀）：`formation` 字段**从这里开始被真正消费**。
##   口径：`toward_own` = 靠向我方的方向符号 —— 敌方 +1（z 越大越贴近我方），
##   我方 −1。列距/行距沿用 arena 的 8km / 6km，保证模板阵不比通用阵列更挤。
##
## ⚠️ 本函数**只算位置**，不改姿态、不改 `desired_range`。
##    站位只决定「开局谁先接敌、谁被集火」，交战逻辑仍由战斗核心负责。
static func formation_positions(formation: String, count: int, z_center: float,
		toward_own: float) -> Array[Vector3]:
	var out: Array[Vector3] = []
	match formation:
		"FRONT":
			# 横列压线：6 列单排（超过 6 艘才起第二排）——近战编组全部顶在最前
			for i in count:
				var col := i % 6
				var row := i / 6
				out.append(Vector3((float(col) - 2.5) * 6_000.0, 0.0,
						z_center + toward_own * float(row) * 4_000.0))
		"BACK":
			# 后排：整体后撤 4km，行距 8km —— 远程编组拉开纵深，
			# 让近战编组必须先穿过它的前排
			for i in count:
				var col := i % 4
				var row := i / 4
				out.append(Vector3((float(col) - 1.5) * 8_000.0, 0.0,
						z_center - toward_own * 4_000.0
						+ toward_own * float(row) * 8_000.0))
		"SPREAD":
			# 散开：列距拉到 11km、行距压到 4km，横向铺开规避溅射
			for i in count:
				var col := i % 6
				var row := i / 6
				out.append(Vector3((float(col) - 2.5) * 11_000.0, 0.0,
						z_center + toward_own * float(row) * 4_000.0))
		"ESCORT":
			# 护航：0 号（旗舰）居中，其余分左右两翼、逐排后撤
			for i in count:
				if i == 0:
					out.append(Vector3(0.0, 0.0, z_center))
					continue
				var rank := (i - 1) / 2 + 1
				var side := -1.0 if (i - 1) % 2 == 0 else 1.0
				out.append(Vector3(side * (6_000.0 + float(rank) * 2_000.0), 0.0,
						z_center - toward_own * float(rank) * 6_000.0))
		"WEDGE":
			# 楔形：尖端指向我方，越往后越宽
			for i in count:
				if i == 0:
					out.append(Vector3(0.0, 0.0, z_center))
					continue
				var rank := (i - 1) / 2 + 1
				var side := -1.0 if (i - 1) % 2 == 0 else 1.0
				out.append(Vector3(side * float(rank) * 7_000.0, 0.0,
						z_center - toward_own * float(rank) * 7_000.0))
		_:
			# MID / 未知名 → 通用 4 列阵列（与 arena 原实现逐字一致）
			for i in count:
				var col := i % 4
				var row := i / 4
				out.append(Vector3((float(col) - 1.5) * 8_000.0, 0.0,
						z_center + toward_own * float(row) * 6_000.0))
	return out
