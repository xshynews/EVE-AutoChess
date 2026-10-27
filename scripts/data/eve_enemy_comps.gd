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
		# 2026-10-27 N7 增一艘后勤/电子战护卫（对齐程序化配方）
		"ships": ["catalyst", "talwar", "coercer", "corax", "burst"],
	},
	"pirate_pack": {
		"name": "突击狼群", "formation": "FRONT",
		# 2026-10-27 N8 新增两艘后勤/电子战护卫
		"ships": ["slasher", "rifter", "thrasher", "talwar", "burst", "navitas"],
	},
	"elite_sniper": {
		"name": "远程狙击组", "formation": "BACK",
		# 2026-10-27 N9 增一艘电子战/后勤巡洋 + 两艘后勤/电子战护卫
		"ships": ["drake", "ferox", "caracal", "osprey", "condor", "bantam"],
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
	#  ⛔ 2026-10-27：这里曾经有 12 个「难度专用编组」，**全部删除**。
	# ══════════════════════════════════════════════════════════════
	#
	# 删掉的：amarr_lance / amarr_wall / caldari_wing / minmatar_rush /
	#   minmatar_pack / caldari_sniper / logi_convoy / boss_overlord /
	#   caldari_wolfpack / wolfpack_light / pirate_lord_escort /
	#   pirate_lord_light / overlord_escort
	#
	# 为什么能删：它们**只**被 `EveCampaignTiers` 的 `comp_overrides` 引用，
	#   而那个机制已整条废止 —— 普通 / 困难 / 炼狱的编组现在由
	#   `EveEnemyPlans` 按节点配方 + 本局种子现摇（见其文件头）。
	#   删之前已确认全工程（含 tools / docs）再无引用点，实测无回归。
	#
	# ⚠️ 留这段注释是为了让以后翻 git 的人看懂**为什么少了十几个编组**，
	#    而不是以为被谁误删了。
	# ⚠️ 本表现在只剩**简单档**用的那 10 个基础编组（节点表 `comp` 字段指向）：
	#    简单档 `random_comps = false`，是唯一还吃静态编组的档。
	#    ⛔ 别顺手把这些也删了 —— N1/N2 的「同一张脸」教学就靠它。
}

## 站位模板全集（阶段 C 消费，这里只做合法性校验）
const FORMATIONS: Array[String] = [
	"FRONT", "MID", "BACK", "SPREAD", "ESCORT", "WEDGE", "STANDOFF",
]


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


# ── 运行时注册的程序化编组 ────────────────────────────────────────
#
# ★ 2026-10-27：难度 2/3/4 档的编组不再是静态表，而是 `EveEnemyPlans` 按
#   节点配方 + 本局种子**现摇**出来的（同一局同一关恒定，见
#   `EveRunState.enemy_roster_seed()`）。摇完登记到这里，好让
#   「编组名 / 阵型 / 成员数」这些既有查询继续只有一个入口 ——
#   否则每个调用点都要自己去问 run，迟早有人漏一处，HUD 就显示「未知编组」。
#
# ⚠️ 必须是 `static var`：`COMPS` 是设计期静态表、这里是运行期产物，
#    两者分开存；往 const 里写会直接报错。
# ⚠️ `EveRunState.start_run()` 会调 `clear_runtime()` —— 否则同进程重开
#    一局时，上一局的编组会残留在内存里。
static var _runtime: Dictionary = {}


## 登记一副程序化编组（本局有效）。⛔ 只由 `EveRunState` 调，别在别处调。
static func register_runtime(comp_id: String, name: String, formation: String,
		ships: PackedStringArray) -> void:
	var arr: Array = []
	for s in ships:
		arr.append(String(s))
	_runtime[comp_id] = {"name": name, "formation": formation, "ships": arr}


## 清空程序化编组（每次 `start_run` 调一次）
static func clear_runtime() -> void:
	_runtime.clear()


## 取一个编组。运行时登记的优先；再退到静态表；都没有返回 {}
static func by_id(comp_id: String) -> Dictionary:
	if _runtime.has(comp_id):
		return _runtime[comp_id]
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


## 编组是否存在（静态表或本局运行时登记的都算）
static func has_comp(comp_id: String) -> bool:
	return _runtime.has(comp_id) or COMPS.has(comp_id)


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
		"STANDOFF":
			# ★ 保持距离（2026-10-27 用户为 N9 指定）：
			#   整队在部署线**之后再后退 2 格 = 12 km**，横向 12 km 大幅铺开。
			#   ⭐ 这不是"站得更靠后"的装饰 —— 它把"玩家必须自己压上去"写成了几何：
			#      退 12 km 后，2 格射程（12 km）的船开局全部在射程外，
			#      3 格射程（导弹，18 km）也只剩约 6 km 余量。
			#   ⛔ 用 `toward_own` 的方向乘，别写死正负号：我方编组若借用这个模板
			#      （toward_own = −1），应当朝反方向退，而不是退到我方半场里去。
			for i in count:
				var col := i % 3
				var row := i / 3
				out.append(Vector3((float(col) - 1.0) * 12_000.0, 0.0,
						z_center - toward_own * (12_000.0 + float(row) * 6_000.0)))
		_:
			# MID / 未知名 → 通用 4 列阵列（与 arena 原实现逐字一致）
			for i in count:
				var col := i % 4
				var row := i / 4
				out.append(Vector3((float(col) - 1.5) * 8_000.0, 0.0,
						z_center + toward_own * float(row) * 6_000.0))
	return out
