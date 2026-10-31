extends RefCounted
class_name EveShipDatabase

## EVE 自走棋 —— 舰船数据库
##
## 职责分工（改数值前务必分清）：
##   EveShipTable  = 设计侧权威原值（52 艘 × 14 列，逐行直录，不许动）
##   本文件        = 把原值【派生】成 3D 战斗解算所需的字段 + 提供查询 API
##
## ⚠️ 这里出现的任何数字，都是【换算常数】，不是平衡数值。
##    平衡数值一律来自 EveShipTable；本文件只负责「格 → 米」「费用 → 吨位」
##    这类单位与档位的映射。想让某艘船变强，改的是 EveShipTable。
##
## ══════════════════════════════════════════════════════════════════
##  派生规则总表（全部集中在这三个常量里，改一个就能整体挪动）
## ══════════════════════════════════════════════════════════════════
##
##  ① 擂台尺度：CELL_METERS = 6000
##     权威表的射程/移速单位是【格】，必须有一个「一格等于多少米」的换算。
##     取 6000 米，与竞技场 default_formation() 的 row_step 同源 ——
##     这样「表里说射程 2 格」和「3D 里站位隔 2 排」在数值上就是同一件事。
##       → 射程 2 格 = 12 km / 3 格 = 18 km（落在 EVE 护卫~巡洋的真实区间内）
##       → 移速 0.10 格/秒 = 600 m/s（EVE 护卫实速 400~600，吻合）
##
##  ② 装甲与结构的拆分：ARMOR_SHARE = 0.65
##     权威表把「装甲/结构」合成了一列，而三层血量模型需要知道各自多少。
##     EVE 里同吨位船的装甲总是显著多于结构（结构是最后的 1/3 左右），
##     所以 65/35 拆。⚠️ 这是工程侧的推断，不是设计给定值 ——
##     设计侧一旦把这两列分开给，删掉这个常量、直接读两列即可。
##
##  ③ 攻速：ATTACK_CYCLE_SECONDS = 1.0
##     ⚠️ 重要：权威表的「攻击间隔」整列恒为 10，零区分度，
##        判定为占位值。工程的做法是【照实保留原值】到 ship.attack_interval
##        （HUD 要显示就显示 10），但战斗循环另读本常量。
##        设计侧给出真正的间隔梯度后，把这里改成读 attack_interval 即可，
##        调用点一处都不用动。
##
## ══════════════════════════════════════════════════════════════════

# ── 换算常数 ──────────────────────────────────────────────────────
## ★ 2026-10-10（审查 2#5）：武器/防御/定位的稳定 id（逻辑只认 id，不认中文）。
## ⚠️ 用 preload 常量引用（无头跑没有全局类缓存）。
const CIDS := preload("res://scripts/core/eve_combat_ids.gd")
## 定位标签（role_tag）要查的两份唯一真源：电子战名单 / 加强型战列名单。
## ⚠️ 依赖方向：这两个表都**不**引用本文件，单向，无环。
## ⚠️ 用 preload 常量而不是全局类名 —— 无头跑不一定有全局类缓存。
const TRAITS := preload("res://scripts/data/eve_trait_table.gd")
const PLANS := preload("res://scripts/data/eve_enemy_plans.gd")

## ★ 2026-10-10（i18n）：术语取词。舰船名**必须用 EVE 官方译名**
##（英文 = 官方英文原名，中文 = 官方简中译名）—— 见 `eve_terms.gd` 顶注。
const TERMS := preload("res://scripts/core/eve_terms.gd")

const CELL_METERS := 6000.0

## ── ★ 2026-10-29（用户定案）：12 艘战列舰按「普通/加强 × 盾抗/甲抗」四类重排 ──
##
## 用户原话：「5 费战列很贵，但买了之后扛不住打不赢，那不等于废物吗」。
## 所以这一档**不再按 0.65/0.35 拆装甲/结构**，三层血量直接按类别写死；
## 武器也换成**双通道**（主通道 100% / 副通道 50% 概率），副通道带满穿盾。
##
## ⛔ 「加强型」不是我们编的分类 —— 就是 `EveEnemyPlans` 里那 4 艘：
##    鹏鲲 / 死亡漩涡（盾抗）、地狱天使 / 亥伯龙神（甲抗）。
const BATTLESHIP_CLASS := {
	&"raven": &"common_shield", &"scorpion": &"common_shield",
	&"typhoon": &"common_shield", &"tempest": &"common_shield",
	&"megathron": &"common_armor", &"dominix": &"common_armor",
	&"armageddon": &"common_armor", &"apocalypse": &"common_armor",
	&"rokh": &"plus_shield", &"maelstrom": &"plus_shield",
	&"hyperion": &"plus_armor", &"abaddon": &"plus_armor",
}

## 三层血量 = [护盾, 装甲, 结构]，**按定位分两张表**。
##
## ★ 2026-10-29（用户定案）：「攻击型攻击强防御弱，防御型防御强攻击弱」。
##   四类只定「底子」（= 攻击型的血量），防御型另走 `BATTLESHIP_HP_TANK`。
##
##   ⛔ 为什么不用「底子 × 1.15 倍率」：190 × 1.15 = 218.5、250 × 1.15 = 287.5，
##   层层都出半格血，表列（商店卡面 / 图鉴）还得跟着凑整，两处永远差 1。
##   ⇒ 直接写整数，玩家看到的每一格就是战斗里那一条。
const BATTLESHIP_HP := {
	&"common_shield": [220.0, 320.0, 190.0],   ## 730（改前 600）
	&"common_armor": [110.0, 420.0, 190.0],    ## 720（改前 739）
	&"plus_shield": [250.0, 350.0, 200.0],     ## 800
	&"plus_armor": [150.0, 450.0, 200.0],      ## 800
}

## 防御型（比同类的攻击型厚 ~15%）。**加强型全是防御型**，所以它只有这一张。
##
##   普通盾 250/370/220=840 · 普通甲 125/485/220=830
##   加强盾 290/400/230=920 · 加强甲 175/520/230=925
##
## ⚠️ 战力口径（EHP × DPS，用来定「谁都不吃亏」）：
##   普通盾 攻 730×80=58400 / 防 840×70=58800
##   普通甲 攻 720×80=57600 / 防 830×70=58100
##   ⇒ 两档差 < 1%，买哪艘都不亏；差的是**打法**（攻坚 vs 站桩）。
##
## ⛔ 不要把攻击型的血往下砍来「对称」：用户买 5 费战列的核心诉求就是
##    「扛得住」（2026-10-29 原话：「买了之后扛不住打不赢，那不等于废物吗」）。
const BATTLESHIP_HP_TANK := {
	&"common_shield": [250.0, 370.0, 220.0],
	&"common_armor": [125.0, 485.0, 220.0],
	&"plus_shield": [290.0, 400.0, 230.0],
	&"plus_armor": [175.0, 520.0, 230.0],
}

## 穿盾率（Sins of a Solar Empire 的相位导弹式）：**每发掷一次**，掷中就直接越过
## 护盾落到装甲（装甲空了再落到结构），掷不中照常先吃护盾。
##
## ⛔ 不做「主/副两条通道各自结算」——那样甲抗战列撞满盾时 80 点会白扔，
##    等于打不动任何盾抗船（用户原案的隐患，2026-10-29 讨论后弃用）。
## ✅ 单通道 + 概率穿盾：每发伤害永远落地，DPS 与改前完全一致，
##    而且天然留出「护盾击穿装备」的通道 —— 装备未来就是把这一格拉高。
##
## 档位：甲抗 > 盾抗（甲抗船就是硬啃装甲的），加强型 > 普通型。
## ⚠️ 这几个数按用户原案的副通道占比（20/100 · 20/120 · 50/150）顺出来，
##    想调就改这一张表，别去改战斗解算。
const BATTLESHIP_SHIELD_PIERCE := {
	&"common_shield": 0.20,
	&"common_armor": 0.30,
	&"plus_shield": 0.25,
	&"plus_armor": 0.40,
}

const ARMOR_SHARE := 0.65

## ★★ 2026-10-31（用户定案）：**TTK 旋钮**（全局，一次性改 52 艘）。
##
## 用户原话：「战斗时间还是 60 秒，我说的 TTK 是舰队对轰时候的时间，
##   现在明显偏长了，我得提高些数值让它短点」
##   ⇒ **时限不变**，只让「双方打光」发生得更早。60 秒窗口里正常一局
##     只用到 39 秒（实测 96 局：平均 38.8 / 中位 41.4 / 90% 分位 45.1），
##     剩下 20 秒是「打完等结算」，玩家体感就是拖。
##
## 为什么是「伤害 ↑ + 血量 ↓」双向夹，而不是只加伤害：
##   · 只加伤害 ⇒ 先手方优势被放大（谁先开火谁赢），高射速小船受益大于大船；
##   · 只降血量 ⇒ 维修 / 后勤的相对价值被稀释（固定修量占比变大）。
##   两个一起动，双方同船同改，胜负关系基本不动。
##
## ⚠️ 这两个系数乘在 `derive()` 的出口，但**只作用于实战字段**：
##    `weapon_damage` / `shield` / `armor` / `hull` / `armor_struct`。
##    ⛔ `attack`（权威表原值）**不乘** —— 它是设计侧数据，
##       `verify_run` 有一条断言专门守它（「权威表的 attack 原值没被改」）。
##    ⇒ 界面上「攻击 12」与「实际每发 14.4」允许不一致，这是项目既有口径
##      （后勤船显示 12、实际打 3 是同一套逻辑）。
## ⚠️ `armor_struct` 乘了 —— 它是 HUD 的「总血」来源，跟实战血量必须一致，
##    否则界面显示的血会比实际多 18%，玩家会以为算法坏了。
## ⚠️ ⛔ 别在 `EveFleetFactory` / 羁绊里再乘一次，那会变成平方。
## ⚠️ 战列舰的 `BATTLESHIP_HP` 也吃 −15%（2026-10-29 才给它 +15% 血），
##    这一条正好被抵消 —— 是**有意的**：用户现在要的是整体缩短对轰时间。
const TTK_DAMAGE_MULT := 1.20
const TTK_HP_MULT := 0.85
## Fallback default for attack interval (sec/shot).
## 2026-10-27: the table now carries a real gradient; this is only
## the fallback when the column is missing.
const ATTACK_CYCLE_SECONDS := 1.0

## ══════════════════════════════════════════════════════════════
##  ★ 2026-10-29（用户定案）：「加强型单独加一个出现概率减少，
##  不能和普通的战列一个出现概率」
## ══════════════════════════════════════════════════════════════
##  商店按费用分池（`by_cost`），同费等概率 ⇒ 4 艘加强型战列和 8 艘普通战列
##  一样常出现。可加强型的三层血量比普通型厚一档（920/925 vs 840/830）、
##  穿盾率也高一档 ⇒ 它应该是「抽到就是运气」，不是常规选项。
##
##  权重 0.70 的含义（5 费池 8 普通 + 4 加强，总权重 8 + 4×0.7 = 10.8）：
##    普通战列每艘 **9.3%** · 加强型每艘 **6.5%** · 加强型 = 普通战列的 **70%**
##    （用户口径：「如果普通战列是 10%，那加强型至少应该是 7% 左右」）
##
##  ⚠️ 绝对份额到不了 10% / 7% —— 12 艘的占比必须合计 100%，
##     按 4×7 + 8×10 = 108% 的写法无法成立 ⇒ 只能等比缩到 9.3% / 6.5%，
##     **比值 0.7 才是真正被满足的那个约束**。
##
##  ⚠️ 只影响**出现频率**，⛔ 不改价格 / 不改数值 —— 抽到仍然是 5 费，
##     强度不变，只是更难刷到。
##  ⚠️ 新加带权重的船就写进这张表，`pick_from_pool()` 会自动读到；
##     表里没有的船一律权重 1.0（= 现在的等概率）。
const SHOP_WEIGHT := {
	&"rokh": 0.7, &"maelstrom": 0.7,
	&"hyperion": 0.7, &"abaddon": 0.7,
}

## 某艘船的刷新权重（1.0 = 常规等概率）。
static func shop_weight(ship_id: StringName) -> float:
	return float(SHOP_WEIGHT.get(ship_id, 1.0))

## 从**同一费用档**的池子里抽一艘，尊重 `SHOP_WEIGHT`。
##
## ⚠️ 消费**恰好一次** `rng.randf()`：商店序列由固定种子复现，
##    少掷或多掷一次都会让整条商店链错位。
##
## ⚠️ 池子里全是权重 1.0 时**退回原来的 `randi_range`** ——
##    1~4 费池一艘都不带权重，走加权路径会白白改掉它们的既有抽样序列
##    （老存档/老探针的复现性会全变）。
static func pick_from_pool(pool: Array, rng: RandomNumberGenerator) -> Dictionary:
	if pool.is_empty():
		return {}
	# ⚠️ 池子里是 `derive()` 的产物，主键叫 **`ship_key`**（`id` 只在原始表行上）。
	var total := 0.0
	var weighted := false
	for row in pool:
		var w := shop_weight(StringName(row.get("ship_key", &"")))
		total += w
		if w < 1.0:
			weighted = true
	if not weighted:
		return pool[rng.randi_range(0, pool.size() - 1)]
	var roll := rng.randf() * total
	var acc := 0.0
	for row in pool:
		acc += shop_weight(StringName(row.get("ship_key", &"")))
		if roll <= acc:
			return row
	return pool[pool.size() - 1]


## ── ★ 2026-10-25 全局移速倍率（用户：「舰船速度目视过慢」）──────────
##
## 根因是单位换算：`speed_cells` 单位是「格/秒」，而一格 = `CELL_METERS` = 6000 m，
## 世界单位 1.0 = 1000 m ⇒ 护卫 0.10 格/s 折算成 **0.60 世界单位/秒**。
## 屏幕上（跟随视距 19.7、约 62 px/世界单位）只有 **37 px/s**，
## 而一艘船本身约 250 px 宽 —— 穿过自己的舰体长度要 7 秒，接敌 20 km 要 33 秒。
##
## 所以统一放大 2.5 倍：护卫 1.5 世界单位/s（约 93 px/s），接敌 13 秒。
##
## ⚠️ **只乘 `max_speed`，⛔ 不要连带乘 `agility`**（2026-10-25 推导，别再"顺手对称改"）：
##    `drag_rate = friction / (mass × agility)`
##    `maximum_acceleration = drag_rate × speed_fraction × max_speed`   ∝ max_speed / agility
##    `stop_distance = max(radius×4, max_speed / drag_rate)`             ∝ max_speed × agility
##    只放大 `max_speed` ⇒ 加速度同倍涨、`stop_distance` 同倍涨，
##    接敌/到位的速度曲线形状**完全不变**，只是整段快 k 倍。
##    若同时放大 `agility`：加速度会被抵消回原值，而 `stop_distance` 变 k² 倍
##    ⇒ 船到点前会先"爬"很久，环绕半径也跟着虚胖 —— 手感反而更差。
##
## ⚠️ 只改这里，**不动 `eve_ship_table.gd` 的权威值**（`speed_cells` 仍是设计真值）。
const SPEED_SCALE := 2.5

## ── ★ 后勤舰（2026-10-01 用户定案：「攻击要低，后勤要真」）──────────────
##
## 起因：用户实机发现「后勤舰似乎也有攻击能力」，要求 ——
##   「后勤舰的攻击能力是要比较低的，甚至没有最好。」
##   同时「后勤舰是维修其他舰船的」这一条此前**根本没实现**。
##
## 体检结果（`tools/probe_logistics.tscn`，改前）：
##   ① 攻击：护卫后勤 12 vs 攻击型 13（92%）· 巡洋后勤 35 vs 攻击型 40（88%）
##      ⇒ 后勤舰就是一艘**完整的战斗力**，只是名字带「后勤」。
##   ② 修理：`EveCombatCore.repair()` 只接收本船对象、**没有「目标友军」参数**
##      ⇒ 那 2.0/s 是回充自己，对队友零贡献。主动修（active_*）全表恒 0。
##      45 秒里自愈 90 点，而同期输出 540 点 ⇒ 「后勤」名不副实。
##
## ── 两条修正 ────────────────────────────────────────────────────
##
##  A. 攻击压到功能的 1/4 左右（`LOGISTICS_ATTACK`）。
##     ⚠️ 不压到 0 是**故意的**：自走棋里「完全不能打」的单位如果落单，
##        会变成一场谁都打不死的僵局（战斗必须能收敛，见
##        `eve_destiny_motion.gd` 的 KEEP 说明）。留一点点火力保证它
##        仍会被打死、也仍能补掉残血，但**绝不再是主力输出**。
##     档位取 current 攻击型的 1/4 再取整：13→3、40→10，中间档线性插值。
##
##  B. 新增**真·修理**：每 `LOGISTICS_REPAIR_CYCLE` 秒，给「同层血量
##     百分比最低的友军」修一次，修**护盾或装甲**。
##     —— 修哪一层**不按派系名硬编码**，读权威表的 `defense` 列：
##        盾抗（加达里 / 米玛塔尔）→ 修护盾；甲抗（艾玛 / 盖伦特）→ 修装甲。
##        这样以后派系配比变了也不用改代码（表是唯一真源）。
##     速率随吨位档走（`LOGISTICS_REPAIR`），与攻击同源：越大的船修得越多。
const LOGISTICS_ATTACK := {
	1: 3.0,    # 护卫（原 12）
	2: 5.0,    # 驱逐
	3: 10.0,   # 巡洋（原 35）
	4: 14.0,   # 战巡
	5: 18.0,   # 战列
}
## 每次修理量（点 / 次）。间隔 2 秒 ⇒ 实际速率 = 本值 ÷ 2。
const LOGISTICS_REPAIR := {
	1: 12.0,
	2: 24.0,
	3: 56.0,
	4: 84.0,
	5: 120.0,
}
## 修理循环间隔（秒）。取 2.0 是 EVE 里「装甲维修器」的典型周期。
const LOGISTICS_REPAIR_CYCLE := 2.0

## ★★ 2026-10-28 用户定案：**后勤舰同时修两层**。
##
##   原修层（`logistics_repair`）保持原值不动；
##   另一层（`logistics_repair_secondary`）按 **3 : 7** 派生 ——
##   即「原修层 7 点，衍生层 3 点」，**向下取整**（用户：「就低不就高」）。
##
##   用户原话：「所有后勤舰船，原来修盾的，以原来修盾量为7，衍生出3的修甲量，
##              反之亦然，比如，矮脚鸡级现在的修盾量为每两秒修12点，
##              那衍生出的修甲量为5」
##   ⇒ 12 × 3 / 7 = 5.14 → **5**；56 × 3 / 7 = 24 → **24**（正好整除）。
##
##   ⚠️ 反向同样乘 3/7（不是 7/3）：装甲主修的船，衍生护盾 = 装甲量 × 3/7。
##      若按 7/3 反推，巡洋会变成「甲 56 + 盾 130」，明显过头 —— 已跟用户确认过。
##   ⚠️ 只派生**护盾 / 装甲**两层，**不碰结构**（结构是最后一道血，能修＝两条命）。
const LOGISTICS_SECONDARY_NUM := 3.0
const LOGISTICS_SECONDARY_DEN := 7.0

# ── 伤害类型分布（EM, THERMAL, KINETIC, EXPLOSIVE）────────────────
# 注：PackedFloat32Array 的构造不是常量表达式，GDScript 里不能用 const 承载。
static var PROFILE_LASER := PackedFloat32Array([0.5, 0.5, 0.0, 0.0])        # 激光：电磁+热能
static var PROFILE_HYBRID := PackedFloat32Array([0.0, 0.5, 0.5, 0.0])       # 混合炮：热能+动能
static var PROFILE_PROJECTILE := PackedFloat32Array([0.0, 0.0, 0.55, 0.45]) # 射弹：动能+爆炸
static var PROFILE_MISSILE := PackedFloat32Array([0.0, 0.0, 0.0, 1.0])      # 导弹：纯爆炸

## 武器 → 伤害分布
static var WEAPON_PROFILE := {
	&"激光炮": PROFILE_LASER,
	&"混合炮": PROFILE_HYBRID,
	&"射弹炮": PROFILE_PROJECTILE,
	&"导弹": PROFILE_MISSILE,
}

## 武器 → 失准距离（米）。导弹必中，没有 falloff（它的「射程」是硬截止）。
const WEAPON_FALLOFF := {
	CIDS.W_LASER: 3000.0,
	CIDS.W_HYBRID: 4000.0,
	CIDS.W_PROJECTILE: 6000.0,
	CIDS.W_MISSILE: 0.0,
}

## 武器 → 追踪速度基准（护卫舰水平，再按吨位衰减）
## ⚠️ 2026-10-01 实测修正：这组值原本偏低约 **2.2 倍**，导致战斗打不完。
##
##   命中率 = 0.5 ^ (angular / tracking)²   （双方信号分辨率相同时抵消）
##   angular = 横向相对速度 / 距离
##
##   实测实机开局（节点1 · 护卫档）：双方相距 ~7 km、各 600 m/s 对穿
##   ⇒ 横向相对速度 ~1200 m/s ⇒ angular ≈ 0.17 rad/s。
##   配原来的 0.090 ⇒ y = 1.9 ⇒ 命中率 ≈ 8%（**实测只有 3.4%**）——
##   205 炮中 7 发，45 秒内双方**零伤亡**，于是每局都"超时判负"。
##
##   ⛔ 别用"贴脸"测这件事：双方重叠时 angular = 0 ⇒ 命中率 100%，
##      看上去"20 秒全歼"，那是假象（见 tools/probe_fire.gd 顶部说明）。
##
##   新值按「中距离互殴命中率 ≈ 60%」反解：
##     0.5^y² = 0.6 ⇒ y = 0.858 ⇒ tracking = angular / y ≈ 0.20
##   三档保持原有快慢关系（激光 < 混合 < 射弹），整体 ×2.2。
##   ⚠️ 0.200 那一版实测命中率只到 25%（仍是"45 秒打不完"）——
##      说明实机 angular 比我按 0.17 估的更高（反推 ≈ 0.29，
##      因为船会收敛到 ~6.6 km 的 `desired_range`，距离越近角速度越大）。
##      按"要 50% ⇒ tracking = angular / 0.858" 再取一档，×3.3 倍。
##      ⚠️ 这仍是**要调的旋钮**（战斗手感），不是定论。
const WEAPON_TRACKING := {
	CIDS.W_LASER: 0.300,
	CIDS.W_HYBRID: 0.330,
	CIDS.W_PROJECTILE: 0.520,
	CIDS.W_MISSILE: 999.0,
}

## 费用（吨位）→ 体型/机动档位。这些是「渲染与解算尺度」，不是平衡数值。
##   mass 吨位质量（kg）/ agility 惯性 / radius 模型半径（m）/ sig 信号半径（m）
##   scan_res 扫描分辨率（m）/ sig_res 武器信号分辨率（m）
const CLASS_PROFILE := {
	1: {"mass": 1_150_000.0, "agility": 3.2, "radius": 34.0,
		"signature": 36.0, "scan_res": 620.0, "sig_res": 120.0},
	2: {"mass": 4_600_000.0, "agility": 5.2, "radius": 62.0,
		"signature": 95.0, "scan_res": 460.0, "sig_res": 200.0},
	3: {"mass": 12_000_000.0, "agility": 9.0, "radius": 110.0,
		"signature": 245.0, "scan_res": 280.0, "sig_res": 400.0},
	4: {"mass": 20_000_000.0, "agility": 11.5, "radius": 150.0,
		"signature": 330.0, "scan_res": 220.0, "sig_res": 500.0},
	5: {"mass": 40_000_000.0, "agility": 14.0, "radius": 220.0,
		"signature": 420.0, "scan_res": 180.0, "sig_res": 600.0},
}

## 吨位 → 追踪衰减（横越大船转不过来）
const TRACKING_DECAY_BY_COST := {
	1: 1.0, 2: 1.5, 3: 2.0, 4: 2.5, 5: 3.0,
}

# ── 抗性档位 ──────────────────────────────────────────────────────
#
# ⚠️ 这五个必须是 static var 而不是 const：
#    PackedFloat32Array([...]) 的构造在 GDScript 里不是常量表达式
#    （const 会报 "isn't a constant expression"）。这个坑在旧版
#    eve_ship_database.gd 的 PROFILE_* 上已经踩过一次，注释也写在那儿了。
#
# 盾抗船：护盾层强（动能/爆炸抗高），装甲层弱。
# 甲抗船：装甲层强（电磁/热能抗高），护盾层弱。
# 结构层永远 0 抗 —— 这是 EVE 的规则，也是「结构是最后一道血」的由来。
#
# ⚠️ 上面三行是 2026-10-29 **之前**的口径，保留做沿革参考；现行口径见下一段。
## ★ 2026-10-29（用户定案）：**抗性全归 0**。
##
## 用户原话：「EVE 里面的抗性是要做多类型的子弹，每个种族的子弹都是多类型的，
##   而不是绑定发射器……所以我说没用。」
## 本作每艘船焊死一种武器（激光炮永远只打电磁/热能），玩家没有"换弹种针对目标"
## 这个动作 ⇒ 抗性退化成**单向的减伤税**，只会拉长 TTK，让玩家觉得"打得费劲"。
##
## ⛔ 别再按 EVE 的直觉把数字填回去：那不是遗漏，是**故意的 0**。
## ⚠️ 四类武器的伤害分布（`PROFILE_*`）**保留不动** —— 将来真做多弹种时直接复用；
##    当前所有层抗性为 0 ⇒ `damage_factor()` 恒等 1.0，分布不影响结果。
static var SHIELD_TANK_SHIELD_RESISTS := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
static var SHIELD_TANK_ARMOR_RESISTS := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
static var ARMOR_TANK_SHIELD_RESISTS := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
static var ARMOR_TANK_ARMOR_RESISTS := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
static var HULL_RESISTS := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])


## 表自检（脚本加载时自动跑一次）。
##
## 在这里做而不是写测试脚本，是因为「设计侧改完数值忘了某列」这类问题
## 必须在【启动那一刻】就喊出来 —— 否则要等战斗打起来才发现某艘船是空壳。
static func _static_init() -> void:
	var problems := EveShipTable.validate()
	for p in problems:
		push_warning("[EveShipTable] 数据有问题：%s" % p)


# ═══════════════════════════════════════════════════════════ 派生规则

## 战列舰的穿盾率；其余 40 艘为 0（走原来的「先盾后甲」顺序）。
static func battleship_pierce(bs_class: StringName) -> float:
	return float(BATTLESHIP_SHIELD_PIERCE.get(bs_class, 0.0))


## 输出的字段分两类：
##   ① 权威原值（ship_key / weapon_type / attack / range_cells …）—— 直通，不加工
##   ② 派生值（armor / hull / optimal_range / max_speed …）—— 由换算常数算出
static func derive(row: Dictionary) -> Dictionary:
	var cost := int(row["cost"])
	var cls := int(EveShip.CLASS_BY_COST.get(cost, EveShip.Class.FRIGATE))
	var weapon := String(row["weapon"])
	var defense := String(row["defense"])
	# ★ 2026-10-10（审查 2#5）：中文原值是**设计侧真值**（保持逐字不改），
	#   逻辑一律用稳定 ASCII id —— 映射只有 `EveCombatIds` 一处。
	var weapon_id := CIDS.weapon_id_of(weapon)
	var defense_id := CIDS.defense_id_of(defense)

	# --- ① 装甲 / 结构 拆分（见文件头规则 ②）---
	var armor_struct := float(row["armor_struct"])
	var armor := roundf(armor_struct * ARMOR_SHARE)
	var hull := armor_struct - armor
	var shield := float(row["shield"])

	# ★ 2026-10-29：战列舰**不拆**，三层血量按类别 + 定位写死
	#   （攻击型 `BATTLESHIP_HP` / 防御型 `BATTLESHIP_HP_TANK`）。
	#   ⚠️ 判据用 role id（不是在比中文），映射只有 `EveCombatIds` 一处。
	var bs_class: StringName = BATTLESHIP_CLASS.get(StringName(row["id"]), &"")
	if bs_class != &"":
		var tank := CIDS.role_id_of(String(row["role"])) == CIDS.R_DEFENSE
		var hp3: Array = (BATTLESHIP_HP_TANK if tank else BATTLESHIP_HP)[bs_class]
		shield = float(hp3[0])
		armor = float(hp3[1])
		hull = float(hp3[2])

	# ★ 2026-10-31（用户定案）：TTK 收缩 —— 三层血量统一 ×0.85。
	#   ⚠️ 放在战列特例**之后**：战列那三层的来源是 `BATTLESHIP_HP`，同样要吃系数。
	#   ⚠️ `armor_struct`（HUD 显示用的合并值）也要一起乘，否则界面显示的总血
	#      会比实战多 18% —— 玩家会以为算错了。
	shield *= TTK_HP_MULT
	armor *= TTK_HP_MULT
	hull *= TTK_HP_MULT
	armor_struct *= TTK_HP_MULT

	# --- ② 抗性档位 ---
	# ⚠️ 判据用 **id**（不是在比中文）：拼错字会在 `EveCombatIds.unknown_values`
	#    那一关被拦下，而不是在这里静默走"甲抗"分支。
	var shield_tank := (defense_id == CIDS.D_SHIELD)
	var s_res := SHIELD_TANK_SHIELD_RESISTS if shield_tank else ARMOR_TANK_SHIELD_RESISTS
	var a_res := SHIELD_TANK_ARMOR_RESISTS if shield_tank else ARMOR_TANK_ARMOR_RESISTS

	# --- ③ 格 → 米 ---
	var range_cells := int(row["range_cells"])
	var speed_cells := float(row["speed_cells"])
	var optimal := float(range_cells) * CELL_METERS
	var max_speed := speed_cells * CELL_METERS * SPEED_SCALE

	# --- ④ 体型档位 ---
	var cp: Dictionary = CLASS_PROFILE.get(cost, CLASS_PROFILE[1])
	var decay: float = float(TRACKING_DECAY_BY_COST.get(cost, 1.0))

	# --- ⑤ 后勤船：低攻击 + 真修理（2026-10-01 用户定案，见文件头 A/B 两段）---
	#
	# ⚠️ 这里**不改权威表的 attack**，而是另给一个派生值让战斗用它。
	#    理由：`ship.attack` 是权威表原值，HUD 的「攻击」格子要照实显示；
	#    改它等于伪造设计侧数据（红线：平衡数值一律来自 EveShipTable）。
	#    所以口径是：**表说多少就是多少，但后勤船的「武器」另有一套**
	#    —— 就像现实里补给舰的炮只是自卫武器。
	var is_logi := bool(row["logistics"])
	var logi_atk := float(LOGISTICS_ATTACK.get(cost, LOGISTICS_ATTACK[1])) if is_logi else 0.0
	# ⚠️ 修哪一层、每次修多少 —— **两个都要 `is_logi` 守卫**。
	#    漏了守卫会留下「半生效状态」：非后勤船也带着一个 `logistics_layer`，
	#    只靠下游 `logistics_repair > 0` 那一刀拦着。那种写法在探针/调试窗口
	#    里会显示成「茶隼级 修哪一层 = 护盾」—— 明明是防御型。踩过一次。
	# ⛔ 层别按派系名硬编码：表里 4 派系 × 2 防御是 13/13 严格对齐，
	#    但那是**数据的巧合**，真正该信的是 `defense` 这一列本身。
	var logi_layer := (&"shield" if defense_id == CIDS.D_SHIELD else &"armor") if is_logi else &""
	var logi_repair := float(LOGISTICS_REPAIR.get(cost, LOGISTICS_REPAIR[1])) if is_logi else 0.0
	# ★ 2026-10-28：衍生层 = 主修层之外的另一层（护盾 ↔ 装甲，⛔ 不含结构）。
	#   量 = floor(主修量 × 3 / 7) —— 口径见 `LOGISTICS_SECONDARY_NUM` 的上方注释。
	var logi_layer_2 := (&"armor" if logi_layer == &"shield" else &"shield") if is_logi else &""
	# ⚠️ 显式 `: float`：`floor()` 在 4.7 的返回推导是 Variant，
	#    而本项目把该警告当错误 ⇒ `:=` 会让整个文件编译失败
	#    （整条依赖链跟着挂，`verify_audio` 就是被这条打成红的）。
	var logi_repair_2: float = floor(logi_repair * LOGISTICS_SECONDARY_NUM
			/ LOGISTICS_SECONDARY_DEN) if is_logi else 0.0

	# 2026-10-27: fire rate (sec/shot) now comes from the table column.
	# Alpha scales with cycle so DPS = damage/cycle stays identical,
	# which keeps the existing balance untouched.
	var cycle := float(row.get("attack_interval", ATTACK_CYCLE_SECONDS))
	if cycle <= 0.0:
		cycle = ATTACK_CYCLE_SECONDS

	# `weapon_damage` 既是战斗用的「每发伤害」，也是 DPS 的唯一分母来源。
	# ⚠️ 第一次抄成 `attack` 而非 `attack x cycle` 会让全表 DPS 差一个数量级。
	# ★ 2026-10-31：TTK 收缩 —— 每发伤害 ×1.2（射速不变 ⇒ DPS +20%）。
	var weapon_damage := (logi_atk if is_logi else float(row["attack"])) * cycle \
			* TTK_DAMAGE_MULT
	var shield_pierce := battleship_pierce(bs_class)

	return {
		# ── 身份 ──
		"ship_key": StringName(row["id"]),
		# ★ 2026-10-10（i18n）：**显示名走取词**（英文 = EVE 官方原名，中文 = 官方译名）。
		#   ⚠️ 权威表 `EveShipTable.ROWS` 里那一列**保持中文原值不动** ——
		#     它是设计侧真值（`verify_data_source` 在逐列对拍）。
		#     默认 locale 是 zh_CN ⇒ 取词原样返回中文 ⇒ 既有断言/截图全不变。
		"name": TERMS.ship(StringName(row["id"]), String(row["name"])),
		"name_cn": String(row["name"]),
		"en": String(row["id"]).capitalize(),
		"faction": int(EveShipTable.FACTION_INDEX.get(String(row["faction"]), 0)),
		"faction_cn": String(row["faction"]),
		"class": cls,
		"cost": cost,
		# 羁绊标签 = V3 稿「舰队构成」窗的三组：势力 / 武器 / 防御
		"traits": PackedStringArray([String(row["faction"]), weapon, defense]),

		# ── 权威原值（HUD 展示用这套）──
		"weapon_type": StringName(weapon),
		"defense_type": StringName(defense),
		"role": StringName(row["role"]),
		# ★ 逻辑用的稳定 id（见 `EveCombatIds` 顶注）。⛔ 显示仍走上面那三个中文原值。
		"weapon_id": weapon_id,
		"defense_id": defense_id,
		"role_id": CIDS.role_id_of(String(row["role"])),
		"is_logistics": bool(row["logistics"]),
		# ⛔ 2026-10-31 修正：这里**不许**乘 TTK 系数。
		#   项目把 `attack` 当作「权威表原值」的代言（`verify_run` 有一条
		#   「★ 权威表的 attack 原值没被改」在守着它）。要改攻击力走
		#   `weapon_damage`（实战值）—— 两者本来就允许不同：
		#   后勤船显示 12、实际打 3 就是既有设计（见 `weapon_damage` 的注释）。
		"attack": float(row["attack"]),
		"range_cells": range_cells,
		"speed_cells": speed_cells,
		"attack_interval": float(row["attack_interval"]),
		"armor_struct": armor_struct,
		"shield": shield,

		# ── 派生：三层血量 ──
		"armor": armor,
		"hull": hull,
		"shield_resists": s_res,
		"armor_resists": a_res,
		"hull_resists": HULL_RESISTS,

		# ── 派生：武器 ──
		# ⚠️ `weapon_damage` 用的是 **logi_atk**（后勤船的低位武器），
		#    而 `attack` 仍是权威表原值 —— 这是**故意的**：
		#      · HUD「攻击」格子显示权威表值（设计侧数据，不许伪造）
		#      · 战斗解算用 weapon_damage（后勤船的自卫火力）
		#    ⛔ 别为了让这两个数一致而改 `attack` —— 那会让
		#       `warhead_scale()` 放大出来的 HUD 数字变成假的。
		#       （`warhead_scale` 同时乘两者，所以星级/关卡缩放仍然同步。）
		"weapon_damage": weapon_damage,
		# ★ 2026-10-29：战列舰每发「无视护盾、直接落下一层」的概率；其余船为 0。
		"shield_pierce": shield_pierce,
		"weapon_cycle": cycle,
		"shots_per_second": 1.0 / cycle,
		"weapon_profile": WEAPON_PROFILE.get(StringName(weapon), PROFILE_MISSILE),
		"optimal_range": optimal,
		"falloff": float(WEAPON_FALLOFF.get(weapon_id, 0.0)),
		"tracking": float(WEAPON_TRACKING.get(weapon_id, 0.1)) / decay,
		"signature_resolution": float(cp["sig_res"]),

		# ── 派生：物理 ──
		"max_speed": max_speed,
		"mass": float(cp["mass"]),
		"agility": float(cp["agility"]),
		"radius": float(cp["radius"]),
		"signature": float(cp["signature"]),
		"scan_res": float(cp["scan_res"]),

		# ── 派生：修理 ──
		# `passive_shield` 保留给「护盾自然回充」那套 EVE 原生公式
		# （`EveCombatCore.repair()` 在跑），非后勤船也是 2.0 —— 它是**物理**，不是后勤。
		# ⚠️ 2026-10-01 前它是后勤专属的 2.0，那是把两种语义混成了一个字段。
		"passive_shield": 2.0,
		"active_shield": 0.0,
		"active_armor": 0.0,
		"active_hull": 0.0,
		# ★ 真·后勤：循环给友军修 `logi_layer` 这一层，每次 `logi_repair` 点。
		"logistics_layer": logi_layer,
		"logistics_repair": logi_repair,
		"logistics_cycle": LOGISTICS_REPAIR_CYCLE,
		# ★ 2026-10-28：同一循环里**再补一笔**给另一层（护盾 ↔ 装甲）。
		"logistics_layer_secondary": logi_layer_2,
		"logistics_repair_secondary": logi_repair_2,

		# ── 派生：电容（占位，权威表没有这一维）──
		"cap_max": 300.0 + armor_struct * 0.6,
		"cap_regen": 3.0 + float(cost) * 1.2,
		"cap_use": 2.0 + float(cost) * 0.8,

		# ── 派生：导弹参数（只有导弹船用得上）──
		"explosion_radius": float(cp["radius"]) * 1.5,
		"explosion_velocity": 3000.0,
	}


# ═══════════════════════════════════════════════════════════ 查询 API

## 全部 52 艘（派生后）
static func all_ships() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for row in EveShipTable.rows_as_dicts():
		out.append(derive(row))
	return out


## 按费用（= 吨位档）筛选 —— 商店用
static func by_cost(cost: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for s in all_ships():
		if int(s["cost"]) == cost:
			out.append(s)
	return out


## 按主键取（condor / punisher / apocalypse …）。找不到返回 {}
static func by_id(ship_id: String) -> Dictionary:
	var row := EveShipTable.find_row(ship_id)
	return derive(row) if not row.is_empty() else {}


# ═══════════════════════════════════════════════════════════ 定位标签

## 定位五档（**互斥**，52 艘恰好分完：17 + 15 + 8 + 8 + 4）
##
## ★ 2026-10-28（用户定案）：「最顶上的分类要加个定位，把攻击、防御、后勤、
##   电子战、加强型加进去」。
##
## ── 为什么不是直接读表里的 `role` ──────────────────────────────
##  表里的 `role` 只有三种（攻击型 20 / 防御型 24 / 后勤 8），
##  而**电子战**和**加强型**不在那一列：
##    · 电子战 = `EveTraitTable.EW_SHIP_KEYS` 的 8 艘（羁绊维度，跨 role）
##    · 加强型 = `EveEnemyPlans.REINFORCED_BATTLESHIP` 的 4 艘战列（用户 10-27 点名）
##  这两个名单都是**别处的唯一真源** ⇒ 这里只做「查」，⛔ 绝不复制名单。
##
## ── 互斥的取法（优先级 ew > command > role）─────────────────────
##  电子战船在表里仍标着「攻击型 / 防御型」（那份注释说得很清楚：
##  那是定位标签不是数值档）。若两档都算，同一艘船会出现两次、五档合计 60+。
##  收成互斥后：攻击 17 · 防御 15 · 后勤 8 · 电子战 8 · 加强型 4 = 52。
##  ⇒ 「攻击型」这一档**不包括**电子战船，UI 上要让玩家能看见这个口径
##    （图鉴每档 chip 后的数字就是干这个的）。
const ROLE_TAGS: Array[StringName] = [
	&"attack", &"defense", &"logistics", &"ew", &"command",
]

## 档位 → 中文（唯一真源。HUD / 图鉴都从这里取）
const ROLE_LABELS := {
	&"attack": "攻击型",
	&"defense": "防御型",
	&"logistics": "后勤",
	&"ew": "电子战",
	&"command": "加强型",
}

## 档位 → 识别色（★ 2026-11-01：抽奖池卡面的定位标签要上色，抽出来当唯一真源）。
##
## ⚠️ 与 `EveTraitTable.EW_COLOR` / `LOGI_COLOR` **同值但不同源**：
##    那两个是**羁绊**的颜色（电子战 / 后勤羁绊），这里是**定位**的颜色。
##    眼下 ew / logistics 两档的值刻意取得一模一样 —— 玩家看到的"紫色 = 电子战"
##    在卡面和羁绊窗里必须是同一个紫，⛔ 别让两处漂移。
##
## 选色理由：加强型取战场金（唯一的"顶级"档），攻击型取警示红、防御型取护盾蓝 ——
## 三档在深底卡面上要**一眼分得开**，别用同色系的三档灰。
const ROLE_COLORS := {
	&"attack": Color(0.90, 0.45, 0.42),
	&"defense": Color(0.45, 0.68, 0.92),
	&"logistics": Color(0.52, 0.86, 0.68),
	&"ew": Color(0.66, 0.55, 0.95),
	&"command": Color(0.95, 0.78, 0.35),
}


## 档位 → 识别色。未知档返回中性灰（⛔ 不返回白：白色在卡面上会抢标题）。
static func role_color(tag: StringName) -> Color:
	return ROLE_COLORS.get(tag, Color(0.6, 0.65, 0.68))


## 一艘船的定位档。未知 id 返回 `&""`。
static func role_tag(ship_id: String) -> StringName:
	if ship_id.is_empty():
		return &""
	if TRAITS.EW_SHIP_KEYS.has(ship_id):
		return &"ew"
	if PLANS.REINFORCED_BATTLESHIP.has(ship_id):
		return &"command"
	var d := by_id(ship_id)
	if d.is_empty():
		return &""
	match String(d.get("role", "")):
		"后勤":
			return &"logistics"
		"防御型":
			return &"defense"
		_:
			return &"attack"


## 定位档 → 中文
static func role_label(tag: StringName) -> String:
	return String(ROLE_LABELS.get(tag, ""))


## 某一档有多少艘（图鉴 chip 上的数字）
static func count_by_role(tag: StringName) -> int:
	var n := 0
	for s in all_ships():
		if role_tag(String(s["ship_key"])) == tag:
			n += 1
	return n


## 按派系取
static func by_faction(faction: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for s in all_ships():
		if int(s["faction"]) == faction:
			out.append(s)
	return out


## 按 id 取（0-based，兼容旧的调用点）
static func at(index: int) -> Dictionary:
	var list := all_ships()
	if index < 0 or index >= list.size():
		return {}
	return list[index]


## 表规模
static func count() -> int:
	return EveShipTable.ROWS.size()


## 规模摘要 —— 给 HUD / 自检用
##   返回 {"total": 52, "by_cost": {1: 12, …}, "by_faction": {0: 13, …}}
static func summary() -> Dictionary:
	var by_cost := {}
	var by_faction := {}
	for s in all_ships():
		var c := int(s["cost"])
		by_cost[c] = int(by_cost.get(c, 0)) + 1
		var f := int(s["faction"])
		by_faction[f] = int(by_faction.get(f, 0)) + 1
	return {"total": count(), "by_cost": by_cost, "by_faction": by_faction}


# ═══════════════════════════════════════════════════════════ 实例化

## 构建一艘可用的舰船实例（按表序号）
static func instantiate(index: int, team: int, ship_id: int) -> EveShip:
	return _instantiate_from(at(index), team, ship_id)


## 构建一艘可用的舰船实例（按主键，推荐用这个）
static func instantiate_by_id(key: String, team: int, ship_id: int) -> EveShip:
	return _instantiate_from(by_id(key), team, ship_id)


static func _instantiate_from(data: Dictionary, team: int, ship_id: int) -> EveShip:
	if data.is_empty():
		return null
	var ship := EveShip.create(
		ship_id,
		String(data["name"]),
		int(data["faction"]),
		int(data["class"]),
		team,
		int(data["cost"])
	)
	ship.apply_stats(data)
	ship._extra = data
	return ship
