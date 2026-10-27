extends RefCounted
class_name EveEnemyPlans

## EVE 自走棋 —— 敌方「程序化编组」配方表
##
## ══════════════════════════════════════════════════════════════════
##  这是什么 / 为什么要有它
## ══════════════════════════════════════════════════════════════════
##  ★ 2026-10-27（用户定案）：把原来「困难/炼狱各挂一张静态替换表」的做法
##    （`EveCampaignTiers.HARD_COMPS` / `INFERNO_COMPS`）整个换掉 ——
##    改成**逐节点写死配方 + 按池随机抽船**：
##
##      简单   ：仍然用节点表里的静态编组（`EveEnemyComps`），**不变**
##      普通   ：本表 + 难度倍率 ×1.10 · 不吃羁绊
##      困难   ：本表 + 难度倍率 ×1.20 · 吃羁绊   ← 舰船随机**与普通完全相同**
##      炼狱   ：本表 + 难度倍率 ×1.40 · 吃羁绊 + 壁垒
##
##    ⚠️ 「困难与普通随机出来的船相同」这一条**必须成立** —— 用户原话
##       「困难难度的舰船随机与上面的相同」。所以配方里的随机只由
##       `(本局种子, 节点号)` 决定，**不含难度**（见 `EveRunState.enemy_roster_seed()`）。
##       三档的差别只有倍率与羁绊，抽签本身是同一支签。
##
## ══════════════════════════════════════════════════════════════════
##  两条读表须知
## ══════════════════════════════════════════════════════════════════
##  ① **有放回**抽签：`_pick_n` 允许抽到重复的船
##     （现有静态编组本身就大量重复，如 `["kestrel","condor","kestrel","condor"]`）。
##     ⛔ 唯一例外是 N12 的「一个种族一艘」，那里天然互不相同。
##  ② 「电子战或者后勤」= 两类池**合并**后再抽（`SUPPORT_*`），
##     不是「先选类别再选船」。所以 8 艘里每艘等概率。
##
## ⚠️ 本文件**只产 id 列表**，碰不到数值 —— 倍率、羁绊、壁垒全在下游
##    （`EveFleetFactory.build_enemy`）按生产链施加。想改数值别来这儿。
##
## ── 池里的船从哪来 ────────────────────────────────────────────────
##   `NORMAL_*`  = 非电子战、非后勤的「普通」船（★ 2026-10-27 已按用户要求
##                 把攻击型/防御型的数值抹平，见 `eve_ship_table.gd` 顶注）
##   `SUPPORT_*` = 电子战 ∪ 后勤，就是用户口中的「电子战或者后勤」

## ⚠️ 船名 id 的**唯一真源**在 `eve_ship_table.gd`；本文件的池全是 id 引用。
##    「哪些是电子战船」的唯一真源在 `eve_trait_table.gd.EW_SHIP_KEYS` ——
##    `SUPPORT_*` 两个池必须与它保持一致，`_static_init()` 会自检。
const TRAITS := preload("res://scripts/data/eve_trait_table.gd")
const SHIP_TABLE := preload("res://scripts/data/eve_ship_table.gd")
## ⚠️ 用 preload 常量而不是全局类名 —— 无头跑不一定有全局类缓存
## （本工程既有的踩坑记录，见 `eve_ship_database.gd` 顶注）。
const COMPS := preload("res://scripts/data/eve_enemy_comps.gd")

# ══════════════════════════════════════════════════════════════════
#  兵源池
# ══════════════════════════════════════════════════════════════════

# ── 护卫（cost 1）──
const NORMAL_FRIGATE: PackedStringArray = ["kestrel", "incursus", "rifter", "punisher"]
const SUPPORT_FRIGATE: PackedStringArray = [
	"condor", "tristan", "slasher", "executioner",     # 电子战（EW_SHIP_KEYS 的护卫半边）
	"bantam", "navitas", "burst", "inquisitor",        # 后勤
]

# ── 驱逐（cost 2）──
const ATTACK_DESTROYER: PackedStringArray = ["corax", "algos", "thrasher", "coercer"]
const DEFENSE_DESTROYER: PackedStringArray = ["cormorant", "catalyst", "talwar", "dragoon"]
const ANY_DESTROYER: PackedStringArray = [
	"cormorant", "corax", "catalyst", "algos",         # 加达里 / 盖伦特
	"talwar", "thrasher", "dragoon", "coercer",        # 米玛塔尔 / 艾玛
]

# ── 巡洋（cost 3）──
const NORMAL_CRUISER: PackedStringArray = ["caracal", "thorax", "rupture", "maller"]
const SUPPORT_CRUISER: PackedStringArray = [
	"moa", "vexor", "stabber", "omen",                 # 电子战（EW_SHIP_KEYS 的巡洋半边）
	"osprey", "exequror", "scythe", "augoror",         # 后勤
]

# ── 战列（cost 5）：★ 用户点名的「加强型」= 每族一艘 ──
## 用户 2026-10-27 原话：「加强型的舰船为艾玛的地狱天使，盖伦特的亥伯龙神，
## 米玛塔尔的死亡漩涡，加达里的鹏鲲」。
const REINFORCED_BATTLESHIP: PackedStringArray = [
	"abaddon",     # 艾玛 · 地狱天使级
	"hyperion",    # 盖伦特 · 亥伯龙神级
	"maelstrom",   # 米玛塔尔 · 死亡漩涡级
	"rokh",        # 加达里 · 鹏鲲级
]

# ── N15 的「两艘攻击型战巡」：按随机到的战列取**同族的攻击型战巡池**再抽 ──
##
## ⛔ 必须走「池 + `_pick_n`」，不许用 match 写死某一艘单船（原来是那么写的，
##    被用户 2026-10-27 打回：「是该随机的要随机，你这个给我写死了干啥」）。
##    各族现在恰好只有 1 种攻击型战巡（表里 `role = 攻击型` 的那些），所以
##    两艘**必然同款** —— 但那是**池的结构**决定的，不是代码写死的；
##    以后加船 / 改 role，这里一行不用动就会自动参与随机。
## ⚠️ 别为了「看起来更随机」把它们换成该族的**全部**战巡：用户 N15 原话是
##    「两艘**攻击型**战巡」，防御型的 ferox / myrmidon / hurricane / harbinger
##    不在内。（N9 写的是「一艘战巡」—— 那一处才是不分攻击/防御的。）
const AMARR_ATTACK_BC: PackedStringArray = ["prophecy"]
const GALLENTE_ATTACK_BC: PackedStringArray = ["brutix"]
const MINMATAR_ATTACK_BC: PackedStringArray = ["cyclone"]
const CALDARI_ATTACK_BC: PackedStringArray = ["drake"]

# ── 单势力切片（N8 / N11 / N13 用）──
const MINMATAR_SUPPORT_CRUISER: PackedStringArray = ["stabber", "scythe"]
const MINMATAR_DESTROYER: PackedStringArray = ["talwar", "thrasher"]
const CALDARI_CRUISER: PackedStringArray = ["caracal", "moa", "osprey"]
const CALDARI_DESTROYER: PackedStringArray = ["cormorant", "corax"]
const CALDARI_BC: PackedStringArray = ["drake", "ferox"]
## N11 的 3 艘护卫 —— 用户 2026-10-27 定案「限定加达里」（「从加达里舰船中随机」
## 这条总限制也管护卫）。加达里的电子战/后勤护卫只有小鹰 / 矮脚鸡两种，
## 要出 3 艘必然重复（有放回，符合须知 ①）。
const CALDARI_SUPPORT_FRIGATE: PackedStringArray = ["condor", "bantam"]
const GALLENTE_BC: PackedStringArray = ["brutix", "myrmidon"]
const GALLENTE_SUPPORT_CRUISER: PackedStringArray = ["vexor", "exequror"]
const GALLENTE_DESTROYER: PackedStringArray = ["catalyst", "algos"]
const GALLENTE_SUPPORT_FRIGATE: PackedStringArray = ["tristan", "navitas"]

# ── 双势力切片（N9 / N15 用）──
const CALDARI_AMARR_BC: PackedStringArray = ["drake", "ferox", "prophecy", "harbinger"]
const CALDARI_AMARR_NORMAL_CRUISER: PackedStringArray = ["caracal", "maller"]
const CALDARI_AMARR_SUPPORT_CRUISER: PackedStringArray = [
	"moa", "osprey", "omen", "augoror",
]

## N15 的两个「势力组」—— 由随机到的加强型战列决定（用户规则：
## 「战列战巡必须为同一种族」，其余巡洋/护卫则从那两个种族的池里出）。
const SPECTRUM_AG := "ag"     ## 艾玛 + 盖伦特
const SPECTRUM_CM := "cm"     ## 加达里 + 米玛塔尔
const AG_SUPPORT_CRUISER: PackedStringArray = ["omen", "augoror", "vexor", "exequror"]
const AG_SUPPORT_FRIGATE: PackedStringArray = [
	"executioner", "inquisitor", "tristan", "navitas",
]
const CM_SUPPORT_CRUISER: PackedStringArray = ["moa", "osprey", "stabber", "scythe"]
const CM_SUPPORT_FRIGATE: PackedStringArray = ["condor", "bantam", "slasher", "burst"]

# ── N12：一个种族一艘，每族 3 种巡洋全在池里（含电子战 / 后勤）──
const AMARR_CRUISER: PackedStringArray = ["maller", "omen", "augoror"]
const GALLENTE_CRUISER: PackedStringArray = ["thorax", "vexor", "exequror"]
const MINMATAR_CRUISER: PackedStringArray = ["rupture", "stabber", "scythe"]

## N2 的「30% 出一艘电子战或后勤护卫」——用户指定的概率，别顺手改。
const SUPPORT_FRIGATE_CHANCE := 0.30
## N7 的同类概率（巡洋版）。
const SUPPORT_CRUISER_CHANCE := 0.30


# ══════════════════════════════════════════════════════════════════
#  逐节点元信息（名字 + 阵型）
# ══════════════════════════════════════════════════════════════════
##
## ⚠️ 只有**战斗节点**在这里；N4 / N10 / N14 是事件节点，不在表里
##    （`EveRunState.enemy_roster_ids()` 会先挡掉事件节点）。
##
## ⚠️ 阵型是**编组设计的一部分**（用户 N9 明确指定「保持距离」），
##    所以普通档也必须 `enemy_formation = true`，否则 N9 的 STANDOFF 白写。
const NODE_META: Dictionary = {
	1: {"name": "游荡掠夺者", "formation": "FRONT"},
	2: {"name": "游荡掠夺者 · 增援", "formation": "SPREAD"},
	3: {"name": "劫掠小队", "formation": "SPREAD"},
	5: {"name": "精英前卫", "formation": "WEDGE"},
	6: {"name": "劫掠小队 · 混编", "formation": "ESCORT"},
	7: {"name": "游荡袭击组", "formation": "SPREAD"},
	8: {"name": "米玛塔尔劫掠组", "formation": "FRONT"},
	9: {"name": "远程压制组", "formation": "STANDOFF"},
	11: {"name": "加达里导弹狼群", "formation": "SPREAD"},
	12: {"name": "四族巡洋战群", "formation": "SPREAD"},
	13: {"name": "盖伦特重装方阵", "formation": "SPREAD"},
	15: {"name": "边境霸主", "formation": "ESCORT"},
}


## 本节点是不是「程序化编组」节点（事件节点没有编组）
static func has_plan(node_index: int) -> bool:
	return NODE_META.has(node_index)


# ══════════════════════════════════════════════════════════════════
#  表自检（脚本加载时自动跑一次）
# ══════════════════════════════════════════════════════════════════
##
## 与 `EveEnemyComps._static_init` 同一个理由：池里写错一个船 id 不会报错，
## 只会在某个节点安静地少一艘敌人 —— 要打到第 13 关才发现。
##
## ★ 额外盯一件事：`SUPPORT_*` 是「电子战 ∪ 后勤」的**副本**。
##   电子战名单的真源在 `EveTraitTable.EW_SHIP_KEYS`、后勤的真源在船表的
##   `logistics` 列 —— 两边一旦漂移（比如用户又改一次电子战名单），
##   副本会悄悄错位，而 N2/N7 的 30% 抽签就会抽出「按设计不该出现」的船。
##   所以这里逐艘对账，不允许靠人眼维护。
static func _static_init() -> void:
	for p in validate():
		push_warning("[EveEnemyPlans] 数据有问题：%s" % p)


## 返回问题清单（空 = 全对）
static func validate() -> PackedStringArray:
	var out := PackedStringArray()
	var cost_of := {}
	var is_logi := {}
	var role_of := {}
	var fac_of := {}
	for row in SHIP_TABLE.ROWS:
		var sid := String(row[0])
		cost_of[sid] = int(row[5])
		is_logi[sid] = bool(row[13])
		role_of[sid] = String(row[6])
		fac_of[sid] = String(row[2])

	# ① 所有池里的 id 都得在船表里
	for pool_name in _all_pools().keys():
		for sid in _all_pools()[pool_name]:
			if not cost_of.has(String(sid)):
				out.append("%s 引用了不存在的船 id：%s" % [pool_name, sid])

	# ② SUPPORT_* 必须 == 电子战 ∪ 后勤（逐吨位对账）
	var ew := {}
	for k in TRAITS.EW_SHIP_KEYS:
		ew[String(k)] = true
	out.append_array(_check_support("SUPPORT_FRIGATE", SUPPORT_FRIGATE, 1, ew, is_logi, cost_of))
	out.append_array(_check_support("SUPPORT_CRUISER", SUPPORT_CRUISER, 3, ew, is_logi, cost_of))

	# ③ 节点元信息：阵型必须是 `EveEnemyComps` 认识的那几种
	for idx in NODE_META.keys():
		var fm := String(NODE_META[idx]["formation"])
		if not COMPS.FORMATIONS.has(fm):
			out.append("N%d 的阵型未知：%s" % [int(idx), fm])

	# ④ 每个战斗节点都真的造得出船（用固定种子跑一遍配方）
	for idx in NODE_META.keys():
		var ships := ship_ids(int(idx), 20261027)
		if ships.is_empty():
			out.append("N%d 配方造出 0 艘船" % int(idx))
		for sid in ships:
			if not cost_of.has(String(sid)):
				out.append("N%d 配方产出了不存在的船 id：%s" % [int(idx), sid])

	# ⑤ N15 的战列→战巡配对必须严丝合缝：
	#    同族 + 都是货真价实的**攻击型**战巡（cost 4 且 role = 攻击型）。
	#    ⛔ 这条不是形式主义 —— 用户规则「战列战巡必须为同一种族」就是靠它守的。
	for bs in REINFORCED_BATTLESHIP:
		var bc_key := String(bs)
		var pool := _attack_bc_pool_of(bc_key)
		if pool.is_empty():
			out.append("N15：%s 没有对应的攻击型战巡池" % bc_key)
		for bc in pool:
			var bcs := String(bc)
			if int(cost_of.get(bcs, -1)) != 4:
				out.append("N15：%s 的战巡池成员 %s 不是战巡（cost=%d）"
						% [bc_key, bcs, int(cost_of.get(bcs, -1))])
			if String(role_of.get(bcs, "?")) != "攻击型":
				out.append("N15：%s 的战巡池成员 %s 不是攻击型（role=%s）"
						% [bc_key, bcs, String(role_of.get(bcs, "?"))])
			if String(fac_of.get(bcs, "?")) != String(fac_of.get(bc_key, "?")):
				out.append("N15：%s（%s）的战巡池成员 %s 不同族（%s）"
						% [bc_key, String(fac_of.get(bc_key, "?")), bcs,
							String(fac_of.get(bcs, "?"))])

	# ⑥ 配方定义表（`RECIPE_STEPS`）里的池名必须都存在 —— 它是拿给其他 AI 看的，
	#    写错池名会让对方算出一个根本不存在的池。
	var known := _all_pools()
	for ni in RECIPE_STEPS.keys():
		for step in RECIPE_STEPS[ni]:
			for key in ["pool", "else_pool"]:
				var pname := String(step.get(key, ""))
				if pname == "" or known.has(pname) or DERIVED_POOLS.has(pname):
					continue
				out.append("N%d 的配方定义引用了不存在的池 %s" % [int(ni), pname])
	return out


## 对账一个 SUPPORT_* 池：内容必须恰好 = 该吨位的（电子战 + 后勤）
static func _check_support(pool_name: String, pool: PackedStringArray, cost: int,
		ew: Dictionary, is_logi: Dictionary, cost_of: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	var want := {}
	for sid in ew.keys():
		if int(cost_of.get(sid, -1)) == cost:
			want[sid] = "电子战"
	for sid in is_logi.keys():
		if bool(is_logi[sid]) and int(cost_of.get(sid, -1)) == cost:
			want[sid] = "后勤"
	var got := {}
	for sid in pool:
		got[String(sid)] = true
		if not want.has(String(sid)):
			out.append("%s 里的 %s 既不是电子战也不是后勤（本吨位）" % [pool_name, sid])
	for sid in want.keys():
		if not got.has(sid):
			out.append("%s 漏了%s船 %s" % [pool_name, want[sid], sid])
	return out


## 全部池（对账用）
static func _all_pools() -> Dictionary:
	return {
		"NORMAL_FRIGATE": NORMAL_FRIGATE, "SUPPORT_FRIGATE": SUPPORT_FRIGATE,
		"ATTACK_DESTROYER": ATTACK_DESTROYER, "DEFENSE_DESTROYER": DEFENSE_DESTROYER,
		"ANY_DESTROYER": ANY_DESTROYER,
		"NORMAL_CRUISER": NORMAL_CRUISER, "SUPPORT_CRUISER": SUPPORT_CRUISER,
		"REINFORCED_BATTLESHIP": REINFORCED_BATTLESHIP,
		"AMARR_ATTACK_BC": AMARR_ATTACK_BC, "GALLENTE_ATTACK_BC": GALLENTE_ATTACK_BC,
		"MINMATAR_ATTACK_BC": MINMATAR_ATTACK_BC, "CALDARI_ATTACK_BC": CALDARI_ATTACK_BC,
		"MINMATAR_SUPPORT_CRUISER": MINMATAR_SUPPORT_CRUISER,
		"MINMATAR_DESTROYER": MINMATAR_DESTROYER,
		"CALDARI_CRUISER": CALDARI_CRUISER, "CALDARI_DESTROYER": CALDARI_DESTROYER,
		"CALDARI_BC": CALDARI_BC,
		"CALDARI_SUPPORT_FRIGATE": CALDARI_SUPPORT_FRIGATE,
		"GALLENTE_BC": GALLENTE_BC, "GALLENTE_SUPPORT_CRUISER": GALLENTE_SUPPORT_CRUISER,
		"GALLENTE_DESTROYER": GALLENTE_DESTROYER,
		"GALLENTE_SUPPORT_FRIGATE": GALLENTE_SUPPORT_FRIGATE,
		"CALDARI_AMARR_BC": CALDARI_AMARR_BC,
		"CALDARI_AMARR_NORMAL_CRUISER": CALDARI_AMARR_NORMAL_CRUISER,
		"CALDARI_AMARR_SUPPORT_CRUISER": CALDARI_AMARR_SUPPORT_CRUISER,
		"AG_SUPPORT_CRUISER": AG_SUPPORT_CRUISER, "AG_SUPPORT_FRIGATE": AG_SUPPORT_FRIGATE,
		"CM_SUPPORT_CRUISER": CM_SUPPORT_CRUISER, "CM_SUPPORT_FRIGATE": CM_SUPPORT_FRIGATE,
		"AMARR_CRUISER": AMARR_CRUISER, "GALLENTE_CRUISER": GALLENTE_CRUISER,
		"MINMATAR_CRUISER": MINMATAR_CRUISER,
	}


## 池子清单（对外）—— 「还能抽到谁」的唯一真源。
##
## ⚠️ 想把配方交给别的 AI / 工具时**必须连它一起给**：只给抽签结果的话，
##    对方只知道「抽到过谁」，不知道池子里还剩什么。
static func pools() -> Dictionary:
	return _all_pools()


## ══════════════════════════════════════════════════════════════════
##  配方定义（机器可读）—— 给「其他 AI / 工具」消费的「怎么抽」
## ══════════════════════════════════════════════════════════════════
##
## 步的**先后 = 编组里的位置先后**。四种步：
##
##   {"kind": "draw", "pool": <池名>, "n": <几艘>}
##        从池里**有放回**抽 n 艘。
##   {"kind": "fixed", "ship": <船 id>}
##        按用户规格**钉死**的船（全工程只有 N8 的刺客级 —— 用户点名要的）。
##   {"kind": "chance_draw", "p": <概率>, "pool": <池名>, "else_pool": <池名>}
##        以概率 p 从 pool 抽 1 艘，否则从 else_pool 抽 1 艘。
##   {"kind": "chance_replace", "p": <概率>, "pool": <池名>, "of": <第几步的下标>}
##        以概率 p 把第 `of` 步抽出的**随机一艘**换成从 pool 抽的 1 艘。
##
## ⚠️ 所有抽签**有放回**（用户 2026-10-27：「没有特别规定，就是允许重复」）
##    ⇒ 同一步内抽到重复的船是**正常**的，别当成 bug。
##
## ⚠️ 本表是 `_make()` 的说明书，必须与它一致。`tools/probe_enemy_comps.gd`
##    会拿「按本表数出来的可能性总数」跟**真实抽样**对账，不一致会当场报出来。
const RECIPE_STEPS := {
	1: [{"kind": "draw", "pool": "NORMAL_FRIGATE", "n": 2}],
	2: [{"kind": "draw", "pool": "NORMAL_FRIGATE", "n": 2},
			{"kind": "chance_replace", "p": 0.30, "pool": "SUPPORT_FRIGATE", "of": 0}],
	3: [{"kind": "draw", "pool": "DEFENSE_DESTROYER", "n": 1},
			{"kind": "draw", "pool": "NORMAL_FRIGATE", "n": 2},
			{"kind": "chance_replace", "p": 0.30, "pool": "SUPPORT_FRIGATE", "of": 1}],
	5: [{"kind": "draw", "pool": "DEFENSE_DESTROYER", "n": 1},
			{"kind": "draw", "pool": "ATTACK_DESTROYER", "n": 1},
			{"kind": "draw", "pool": "NORMAL_FRIGATE", "n": 2},
			{"kind": "chance_replace", "p": 0.30, "pool": "SUPPORT_FRIGATE", "of": 2}],
	6: [{"kind": "draw", "pool": "NORMAL_CRUISER", "n": 1},
			{"kind": "draw", "pool": "ANY_DESTROYER", "n": 1},
			{"kind": "draw", "pool": "SUPPORT_FRIGATE", "n": 2}],
	7: [{"kind": "chance_draw", "p": 0.30, "pool": "SUPPORT_CRUISER",
			"else_pool": "NORMAL_CRUISER"},
			{"kind": "draw", "pool": "ANY_DESTROYER", "n": 2},
			{"kind": "draw", "pool": "SUPPORT_FRIGATE", "n": 2}],   ## 2026-10-27 N7 增一艘支援护卫
	8: [{"kind": "fixed", "ship": "stabber"},
			{"kind": "draw", "pool": "MINMATAR_SUPPORT_CRUISER", "n": 1},
			{"kind": "draw", "pool": "MINMATAR_DESTROYER", "n": 2},
			{"kind": "draw", "pool": "SUPPORT_FRIGATE", "n": 2}],   ## 2026-10-27 N8 新增两艘支援护卫
	9: [{"kind": "draw", "pool": "CALDARI_AMARR_BC", "n": 1},
			{"kind": "draw", "pool": "CALDARI_AMARR_NORMAL_CRUISER", "n": 1},
			{"kind": "draw", "pool": "CALDARI_AMARR_SUPPORT_CRUISER", "n": 2},
			{"kind": "draw", "pool": "SUPPORT_FRIGATE", "n": 2}],   ## 2026-10-27 N9 增一支援巡洋 + 两支援护卫
	11: [{"kind": "draw", "pool": "CALDARI_BC", "n": 1},
			{"kind": "draw", "pool": "CALDARI_CRUISER", "n": 2},
			{"kind": "draw", "pool": "CALDARI_DESTROYER", "n": 2},
			{"kind": "draw", "pool": "CALDARI_SUPPORT_FRIGATE", "n": 3}],
	12: [{"kind": "draw", "pool": "CALDARI_CRUISER", "n": 1},
			{"kind": "draw", "pool": "GALLENTE_CRUISER", "n": 1},
			{"kind": "draw", "pool": "MINMATAR_CRUISER", "n": 1},
			{"kind": "draw", "pool": "AMARR_CRUISER", "n": 1},
			{"kind": "draw", "pool": "ANY_DESTROYER", "n": 2},
			{"kind": "draw", "pool": "SUPPORT_FRIGATE", "n": 2}],
	13: [{"kind": "draw", "pool": "GALLENTE_BC", "n": 2},
			{"kind": "draw", "pool": "GALLENTE_SUPPORT_CRUISER", "n": 2},
			{"kind": "draw", "pool": "GALLENTE_DESTROYER", "n": 2},
			{"kind": "draw", "pool": "GALLENTE_SUPPORT_FRIGATE", "n": 3}],
	15: [{"kind": "draw", "pool": "REINFORCED_BATTLESHIP", "n": 1},
			{"kind": "draw", "pool": "ATTACK_BC_OF_BATTLESHIP", "n": 2,
				"note": "战列同族的攻击型战巡池（见 _attack_bc_pool_of）"},
			{"kind": "draw", "pool": "SPECTRUM_SUPPORT_CRUISER", "n": 4,
				"note": "战列属艾玛/盖伦特取 AG_SUPPORT_CRUISER，否则取 CM_SUPPORT_CRUISER"},
			{"kind": "draw", "pool": "SPECTRUM_SUPPORT_FRIGATE", "n": 4,
				"note": "同上，取 AG_SUPPORT_FRIGATE / CM_SUPPORT_FRIGATE"}],
}

## N15 的三个**派生池**名字（按随机到的战列动态选），不在 `pools()` 里
const DERIVED_POOLS: PackedStringArray = [
	"ATTACK_BC_OF_BATTLESHIP", "SPECTRUM_SUPPORT_CRUISER", "SPECTRUM_SUPPORT_FRIGATE",
]


## 整份机器可读规格（给其他 AI / 工具一次拿走）
static func spec() -> Dictionary:
	var nodes: Array = []
	var keys := RECIPE_STEPS.keys()
	keys.sort()
	for i in keys:
		nodes.append({
			"node": int(i),
			"name": name_of(int(i)),
			"formation": formation_of(int(i)),
			"steps": RECIPE_STEPS[i],
		})
	var pool_dump: Dictionary = {}
	var pl := _all_pools()
	var pnames := pl.keys()
	pnames.sort()
	for nm in pnames:
		pool_dump[String(nm)] = Array(pl[nm])
	return {
		"generator": "EveEnemyPlans.spec()",
		"repeats": "所有抽签有放回 ⇒ 允许重复（同一步内抽到同一艘船是正常的）",
		"seed_rule": "roster_seed = absi(comp_seed_base * 104729 + node_index * 7919) + 1；"
				+ "comp_seed_base 是本局种子（随机开局时取一个随机数）",
		"difficulty_shared": "普通 / 困难 / 炼狱共用同一套配方，种子不含难度 ⇒ 同局同关"
				+ "三档摇出一模一样的船；只有简单档走节点表静态编组（不随机）。",
		"derived_pools": Array(DERIVED_POOLS),
		"pools": pool_dump,
		"nodes": nodes,
	}


static func name_of(node_index: int) -> String:
	var m: Dictionary = NODE_META.get(node_index, {})
	return String(m.get("name", "")) if not m.is_empty() else ""


static func formation_of(node_index: int) -> String:
	var m: Dictionary = NODE_META.get(node_index, {})
	return String(m.get("formation", "")) if not m.is_empty() else ""


## 造一副编组。返回 `{"name": String, "formation": String, "ships": PackedStringArray}`。
##
## ⚠️ **纯函数**：同一个 `(node_index, seed)` 永远给同一副编组 —— 这是
##    「重载存档不换脸」与「探针可复现」两条要求的共同基础，别改成读全局随机。
static func build(node_index: int, seed: int) -> Dictionary:
	if not NODE_META.has(node_index):
		return {}
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	return {
		"name": name_of(node_index),
		"formation": formation_of(node_index),
		"ships": _make(node_index, rng),
	}


## 只要 id 列表（`EveRunState.enemy_roster_ids()` 的入口）
static func ship_ids(node_index: int, seed: int) -> PackedStringArray:
	var b := build(node_index, seed)
	return b.get("ships", PackedStringArray()) if not b.is_empty() else PackedStringArray()


# ══════════════════════════════════════════════════════════════════
#  逐节点配方
# ══════════════════════════════════════════════════════════════════
static func _make(node_index: int, rng: RandomNumberGenerator) -> PackedStringArray:
	match node_index:
		1:
			# 两艘普通型护卫
			return _pick_n(rng, NORMAL_FRIGATE, 2)

		2:
			# 两艘护卫（30% 出一艘电子战或后勤）
			return _escort_frigates(rng)

		3:
			# 劫掠小队：随机一艘防御型驱逐 + 两艘按 N2
			var a := PackedStringArray([_pick(rng, DEFENSE_DESTROYER)])
			a.append_array(_escort_frigates(rng))
			return a

		5:
			# 精英战：N3 再添一艘攻击型驱逐（共 4）
			var b := PackedStringArray([
				_pick(rng, DEFENSE_DESTROYER), _pick(rng, ATTACK_DESTROYER)])
			b.append_array(_escort_frigates(rng))
			return b

		6:
			# 劫掠小队 · 混编：1 普通巡洋 + 1 驱逐 + 2 电子战/后勤护卫（共 4）
			var c := PackedStringArray([_pick(rng, NORMAL_CRUISER), _pick(rng, ANY_DESTROYER)])
			c.append_array(_pick_n(rng, SUPPORT_FRIGATE, 2))
			return c

		7:
			# 1 巡洋（30% 换电子战/后勤）+ 2 驱逐 + 2 电子战/后勤护卫（共 5）
			# ★ 2026-10-27 用户定案：支援护卫 1 → 2
			var d := PackedStringArray([_cruiser_with_chance(rng),
					_pick(rng, ANY_DESTROYER), _pick(rng, ANY_DESTROYER)])
			d.append_array(_pick_n(rng, SUPPORT_FRIGATE, 2))
			return d

		8:
			# 米玛塔尔专场：刺客级 + 1 电子战/后勤巡洋 + 2 驱逐 + 2 电子战/后勤护卫（共 6）
			# ★ 2026-10-27 用户定案：新增两艘后勤/电子战护卫
			var e := PackedStringArray(["stabber", _pick(rng, MINMATAR_SUPPORT_CRUISER)])
			e.append_array(_pick_n(rng, MINMATAR_DESTROYER, 2))
			e.append_array(_pick_n(rng, SUPPORT_FRIGATE, 2))
			return e

		9:
			# 加达里/艾玛 混池：战巡 + 普通巡洋 + 2 电子战/后勤巡洋
			# + 2 电子战/后勤护卫（共 6）
			# ★ 2026-10-27 用户定案：支援巡洋 1 → 2，另加两艘支援护卫
			# ★ 阵型 STANDOFF「保持距离」—— 这几艘要玩家自己压上去
			var i9 := PackedStringArray([
				_pick(rng, CALDARI_AMARR_BC),
				_pick(rng, CALDARI_AMARR_NORMAL_CRUISER),
			])
			i9.append_array(_pick_n(rng, CALDARI_AMARR_SUPPORT_CRUISER, 2))
			i9.append_array(_pick_n(rng, SUPPORT_FRIGATE, 2))
			return i9

		11:
			# 加达里导弹狼群：1 战巡 + 2 巡洋（3 种巡洋全在随机池）+ 2 驱逐
			# + 3 电子战/后勤护卫（共 8）
			var f := PackedStringArray([_pick(rng, CALDARI_BC)])
			f.append_array(_pick_n(rng, CALDARI_CRUISER, 2))
			f.append_array(_pick_n(rng, CALDARI_DESTROYER, 2))
			f.append_array(_pick_n(rng, CALDARI_SUPPORT_FRIGATE, 3))
			return f

		12:
			# 四族巡洋各一艘（含电子战/后勤）+ 2 随机驱逐 + 2 电子战/后勤护卫（共 8）
			var g := PackedStringArray([
				_pick(rng, CALDARI_CRUISER),
				_pick(rng, GALLENTE_CRUISER),
				_pick(rng, MINMATAR_CRUISER),
				_pick(rng, AMARR_CRUISER),
			])
			g.append_array(_pick_n(rng, ANY_DESTROYER, 2))
			g.append_array(_pick_n(rng, SUPPORT_FRIGATE, 2))
			return g

		13:
			# 盖伦特专场（按吨位随机抽）：2 战巡 + 2 电子战/后勤巡洋 + 2 驱逐
			# + 3 电子战/后勤护卫（共 9）
			# ⚠️ 盖伦特的电子战/后勤护卫**只有 2 艘**（特里斯坦 / 纳维达斯），
			#    要出 3 艘 ⇒ 必然重复一艘。用户 2026-10-27 已确认「允许重复」。
			var h := PackedStringArray()
			h.append_array(_pick_n(rng, GALLENTE_BC, 2))
			h.append_array(_pick_n(rng, GALLENTE_SUPPORT_CRUISER, 2))
			h.append_array(_pick_n(rng, GALLENTE_DESTROYER, 2))
			h.append_array(_pick_n(rng, GALLENTE_SUPPORT_FRIGATE, 3))
			return h

		15:
			return _n15(rng)

	return PackedStringArray()


## N2 的两艘护卫：基础从「普通护卫」抽，另有 30% 概率把**其中一艘**换成
## 电子战或后勤护卫（只换一艘 —— 用户写的是「出现**一艘**电子战或者后勤护卫」）。
static func _escort_frigates(rng: RandomNumberGenerator) -> PackedStringArray:
	var out := _pick_n(rng, NORMAL_FRIGATE, 2)
	if rng.randf() < SUPPORT_FRIGATE_CHANCE:
		out[rng.randi_range(0, out.size() - 1)] = _pick(rng, SUPPORT_FRIGATE)
	return out


## N7 的那艘巡洋：普通巡洋，30% 概率整艘换成电子战或后勤巡洋。
static func _cruiser_with_chance(rng: RandomNumberGenerator) -> String:
	if rng.randf() < SUPPORT_CRUISER_CHANCE:
		return _pick(rng, SUPPORT_CRUISER)
	return _pick(rng, NORMAL_CRUISER)


## N15 · 终盘编组（共 11 艘）
##
## 用户的势力规则（照抄，别自作主张放宽）：
##   · 先随机一艘**加强型战列**；
##   · **两艘战巡必须是同一种族**（所以同一族只有 1 种攻击型战巡 ⇒ 两艘同款）；
##   · 其余「4 巡洋 + 4 护卫」（电子战/后勤）只能从**两个种族的并集**里出：
##       战列 = 艾玛 / 盖伦特 ⇒ 巡洋护卫取 { 艾玛, 盖伦特 }
##       战列 = 加达里 / 米玛塔尔 ⇒ 巡洋护卫取 { 加达里, 米玛塔尔 }
static func _n15(rng: RandomNumberGenerator) -> PackedStringArray:
	var bs := _pick(rng, REINFORCED_BATTLESHIP)
	var spectrum := _spectrum_of(bs)
	var out := PackedStringArray([bs])
	out.append_array(_pick_n(rng, _attack_bc_pool_of(bs), 2))
	out.append_array(_pick_n(rng, _support_cruisers_of(spectrum), 4))
	out.append_array(_pick_n(rng, _support_frigates_of(spectrum), 4))
	return out


## 加强型战列 → 势力组。用户规则：艾玛/盖伦特一组，加达里/米玛塔尔一组。
static func _spectrum_of(bs: String) -> String:
	match bs:
		"abaddon", "hyperion":
			return SPECTRUM_AG
		_:
			return SPECTRUM_CM


## 战列 → 同族的**攻击型战巡池**（N15 的两艘从池里抽，见池常量的注释）。
## ⚠️ 这是「规则映射」（战列→哪个池），不产生随机性；随机在调用处的 `_pick_n`。
static func _attack_bc_pool_of(bs: String) -> PackedStringArray:
	match bs:
		"abaddon":
			return AMARR_ATTACK_BC
		"hyperion":
			return GALLENTE_ATTACK_BC
		"maelstrom":
			return MINMATAR_ATTACK_BC
		_:
			return CALDARI_ATTACK_BC


static func _support_cruisers_of(spectrum: String) -> PackedStringArray:
	return AG_SUPPORT_CRUISER if spectrum == SPECTRUM_AG else CM_SUPPORT_CRUISER


static func _support_frigates_of(spectrum: String) -> PackedStringArray:
	return AG_SUPPORT_FRIGATE if spectrum == SPECTRUM_AG else CM_SUPPORT_FRIGATE


# ══════════════════════════════════════════════════════════════════
#  抽签工具
# ══════════════════════════════════════════════════════════════════
static func _pick(rng: RandomNumberGenerator, pool: PackedStringArray) -> String:
	if pool.is_empty():
		return ""
	return pool[rng.randi_range(0, pool.size() - 1)]


## 抽 n 艘（**有放回**，见文件头须知 ①）
static func _pick_n(rng: RandomNumberGenerator, pool: PackedStringArray,
		n: int) -> PackedStringArray:
	var out := PackedStringArray()
	for i in n:
		out.append(_pick(rng, pool))
	return out