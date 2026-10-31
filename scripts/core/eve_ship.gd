extends RefCounted
class_name EveShip

## EVE 自走棋 —— 舰船实体
##
## 一艘船 = 物理状态（Body）+ 战斗状态（三层血量/电容）+ 静态属性（吨位/派系/武器）
##
## 变更清单（初版）：
##   - 三层血量 shield/armor/hull
##   - 四类伤害抗性
##   - 电容（开火耗电，干涸后无法主动修理）
##   - 武器循环（advance_cycle 累积开火次数）
##   - 姿态 + 目标 锁定

## 派系
enum Faction { AMARR, CALDARI, GALLENTE, MINMATAR }

## 吨位
##
## ⚠️ 2026-09-20 扩容：从 3 档（护卫/驱逐/巡洋）扩到 5 档。
##    理由是权威数值表（EveShipTable）按费用分了 5 档，
##    战巡 / 战列原本挤在 CRUISER 里会让吨位相关的姿态、交战距离全部算错。
##    枚举序号与 EveShipTable.CLASS_NAMES_BY_COST 的键（费用）一一对应：
##      FRIGATE=0 ↔ cost 1 / DESTROYER=1 ↔ cost 2 / … / BATTLESHIP=4 ↔ cost 5
##    新增吨位时【必须同步改】下面三个表：
##      CLASS_NAMES / default_stance_for_class / default_engage_ratio
enum Class { FRIGATE, DESTROYER, CRUISER, BATTLE_CRUISER, BATTLESHIP }

## ★ 2026-10-10（审查 2#5）：武器/防御/定位的稳定 id（逻辑只认 id、不认中文）。
## ⚠️ 用 preload 常量引用（无头跑没有全局类缓存）。
const CIDS := preload("res://scripts/core/eve_combat_ids.gd")

## ★ 2026-10-10（i18n）：术语取词（见 `eve_terms.gd` 顶注）。
const TERMS := preload("res://scripts/core/eve_terms.gd")

const FACTION_NAMES := {
	Faction.AMARR: "艾玛",
	Faction.CALDARI: "加达里",
	Faction.GALLENTE: "盖伦特",
	Faction.MINMATAR: "米玛塔尔",
}

const CLASS_NAMES := {
	Class.FRIGATE: "护卫舰",
	Class.DESTROYER: "驱逐舰",
	Class.CRUISER: "巡洋舰",
	Class.BATTLE_CRUISER: "战列巡洋舰",
	Class.BATTLESHIP: "战列舰",
}

## 费用 → 吨位（权威数值表用费用当吨位档）
const CLASS_BY_COST := {
	1: Class.FRIGATE,
	2: Class.DESTROYER,
	3: Class.CRUISER,
	4: Class.BATTLE_CRUISER,
	5: Class.BATTLESHIP,
}

## 派系标志色（概念图配色：艾玛青铜金 / 加达里灰蓝 / 盖伦特橄榄绿 / 米玛塔尔锈棕）
const FACTION_COLORS := {
	Faction.AMARR: Color(0.72, 0.58, 0.30),
	Faction.CALDARI: Color(0.38, 0.47, 0.56),
	Faction.GALLENTE: Color(0.44, 0.50, 0.34),
	Faction.MINMATAR: Color(0.53, 0.35, 0.26),
}

# --- 静态属性 ---
var id: int = 0
var ship_name: String = ""
var faction: int = Faction.AMARR
var ship_class: int = Class.FRIGATE
var team: int = 0                    ## 0 = 己方, 1 = 敌方
var cost: int = 1                    ## 商店费用（同时就是吨位档 1~5）
## 星级。权威表默认 1；三连合成（阶段 B）会把它抬到 2 / 3，
## 数值倍率 ×1.8^(star-1)（交接文档 §6.4 的 star 叠加）。
var star: int = 1
var traits: PackedStringArray = []   ## 羁绊标签

# --- 权威表原值（EveShipTable 直录字段，一律不做二次加工）---
#
# ⚠️ 这些字段是【设计侧口径】，与下面的战斗派生字段（optimal_range 等）并存：
#    原值用于 HUD 展示与羁绊统计，派生值用于 3D 战斗解算。
#    想让 HUD 显示别的口径，改的是展示层，不是这里。
var ship_key: StringName = &""       ## 主键：condor / punisher / apocalypse …
var weapon_type: StringName = &""    ## 激光炮 / 混合炮 / 射弹炮 / 导弹（**显示用**）
var defense_type: StringName = &""   ## 盾抗 / 甲抗（**显示用**）
var role: StringName = &""           ## 攻击型 / 防御型 / 后勤（**显示用**）
var is_logistics: bool = false       ## 权威表「后勤」列
## ★ 2026-10-10（审查 2#5）：**逻辑用**的稳定 ASCII id（见 `EveCombatIds`）。
## ⛔ 判断分支一律比这三个，**别比上面那三个中文**（拼错不报错 + 文案一改逻辑就崩）。
var weapon_id: StringName = &""      ## laser / hybrid / proj / missile
var defense_id: StringName = &""     ## shield / armor
var role_id: StringName = &""        ## attack / defense / logi
var attack: float = 0.0              ## 权威表「攻击」原值
var range_cells: int = 2             ## 权威表「射程」，单位【格】
var speed_cells: float = 0.1         ## 权威表「移速」，单位【格/秒】
var armor_struct: float = 0.0        ## 权威表「装甲/结构」合并值（未拆分）
var attack_interval: float = 0.0     ## 权威表「攻击间隔」原值（全表恒为 10，疑为占位）

# --- 物理 ---
var body: EveDestinyMotion.Body = null

# --- 三层血量 ---
var hp: Dictionary = {&"shield": 0.0, &"armor": 0.0, &"hull": 0.0}
var max_hp: Dictionary = {&"shield": 0.0, &"armor": 0.0, &"hull": 0.0}
var resists: Dictionary = {
	&"shield": PackedFloat32Array([0.0, 0.2, 0.4, 0.5]),
	&"armor": PackedFloat32Array([0.5, 0.35, 0.25, 0.1]),
	&"hull": PackedFloat32Array([0.0, 0.0, 0.0, 0.0]),
}

# --- 电容 ---
var cap: float = 0.0
var cap_max: float = 0.0
var cap_regen: float = 0.0
var cap_use: float = 0.0
var cap_dry: bool = false

# --- 修理 ---
var passive_shield: float = 0.0
var active_shield: float = 0.0
var active_armor: float = 0.0
var active_hull: float = 0.0

# --- ★ 后勤（2026-10-01 用户定案：「后勤舰是维修其他舰船的」）---
#
# ⚠️ 与上面那组 `active_*` 的区别，别混：
#   `active_*` 是 **EVE 原生的自修**（`EveCombatCore.repair()` 在跑，
#     只写自己 `ship.hp`，而且会被电容干涸掐断）。
#   下面这组是**自走棋特有的「给友军修」**，由 `EveBattleSimulator`
#     按 `logistics_cycle` 循环触发，**不看电容**（后勤船的电容太小，
#     再叠一层消耗会让它整场修不出来，实测意义不大）。
var logistics_repair: float = 0.0     ## 每次修理量（点）
var logistics_layer: StringName = &"" ## 修哪一层：&"shield" 或 &"armor"
## ★ 2026-10-28：后勤舰**同时修两层**。下面这组是「另一层」那一笔：
##   层 = 主修层的对面（护盾 ↔ 装甲，⛔ 不含结构），量 = 主修量 × 3/7（向下取整）。
##   由 `EveBattleSimulator` 在同一个 `logistics_cycle` 里紧跟着再修一次。
var logistics_repair_secondary: float = 0.0
var logistics_layer_secondary: StringName = &""
var logistics_cycle: float = 2.0      ## 修理间隔（秒）
var logistics_timer: float = 0.0      ## 距下次修理的倒计时
var repaired_total: float = 0.0       ## 本场累计修了多少（给 HUD / 验收）

# --- 武器 ---
var weapon_cycle: float = 1.0          ## 每次开火间隔（秒）
var weapon_timer: float = 0.0
var weapon_damage: float = 0.0
var weapon_profile: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0, 1.0])
var optimal_range: float = 0.0
var falloff: float = 0.0
var tracking: float = 0.0
var signature_resolution: float = 0.0

# --- 行为 ---
var stance: int = EveCombatCore.Stance.KEEP
var desired_range: float = 0.0
var target_id: int = -1
var lock_elapsed: float = 0.0
var lock_total: float = 0.0
var locked: bool = false
var alive: bool = true

## ★★ 2026-10-27：指挥层盘面语义（阵型 + 集火用）。
##
## ⚠️ 这两个字段是**纯呈现层**的 —— 由 `EveBattleSimulator._refresh_command`
##    每 5 tick 写一次（真正决定行为的是模拟器里的 `_flagship` / `_focus_target`），
##    视觉层（`EveShipVisual`）只读它们来画标记。
##    ⛔ **不要把逻辑判据建在这两个字段上**：它们是"上一条指令的产物"，
##       比模拟器内部状态晚最多 5 tick；拿它们做判断会引入时序 bug。
##    放在 `EveShip` 而不是让视觉层反查模拟器，是为了让视觉层**不需要**
##    持有模拟器引用（现在它只认识 `EveShip`）。
var is_flagship: bool = false        ## 本舰是当前本队旗舰（吨位最高）
var is_focused: bool = false         ## 本舰是敌方全队正在集火的目标

# --- 统计 ---
var damage_dealt: float = 0.0
var damage_taken: float = 0.0
var kills: int = 0

## 最近一次开火时刻（模拟器时间，秒）。用于「沉默多久 = 该压上去了」这条闸。
## 初值 -999 ⇒ 开局不算沉默（否则第一 tick 全队就脱队）。
var last_fire_at: float = -999.0

## ★ 2026-10-30：**最近一发**是否掷中了「穿盾」（`shot_fired` 里没有这个信息）。
##
## 由模拟器每发写入，供战斗播报条区分「穿透」与「命中」。
## ⚠️ 它是**瞬时**状态，不要拿去做统计或结算 —— 只服务于那一帧的文案。
var last_hit_pierced: bool = false

# --- ★★ 电子战（2026-10-31 用户定案：重现 EVE 的**锁定**机制）---
#
## 干扰节奏（电子战）。放在这里而不是模拟器，是为了让
## `EveFleetFactory`（开局攒第一个周期）和 `EveBattleSimulator`（逐帧掷）
## **读同一份** —— ⛔ 别在两边各写一个 5.0。
##
## `JAM_CYCLE` = 每 5 秒掷一次（不是每发都掷：开火间隔 0.6~1.5 秒，
##   逐发掷会让 6 艘电子船的目标几乎永久哑火，见 `_ew_step` 的说明）。
## `JAM_DURATION` = 命中后 10 秒不能开火（用户定案）。
const JAM_CYCLE := 5.0
const JAM_DURATION := 10.0

## 电子船的干扰命中率（用户定案：护卫 5% / 巡洋 10%）。
##
## ⚠️ 放在 `EveShip` 而不是工厂，因为**三个**地方要读它
##    （工厂造队 / `EveRunState.apply_fleet_traits` 给敌方补 / 测试探针），
##    放工厂会跟 run_state 形成循环引用。
## ⚠️ 驱逐 / 战巡 / 战列**不在电子战兵源里**（`EW_SHIP_KEYS` 只取护卫 + 巡洋），
##    所以后三档不会出现在实战中 —— 写出来是给「以后扩兵源」留的口子，
##    同时也是对「为什么只有两档」的显式回答（⛔ 别删成 if/else）。
static func jam_chance_for_class(cls: int) -> float:
	match cls:
		Class.FRIGATE:
			return 0.05
		Class.DESTROYER:
			return 0.06
		Class.CRUISER:
			return 0.10
		Class.BATTLE_CRUISER:
			return 0.13
		_:
			return 0.15

#
# 口径变更（重要，看旧注释前先看这里）：
#   旧实现 = 羁绊给**敌方全体**加开火间隔（`enemy_cycle_pct`）。
#   新实现 = 电子船对它**正锁定的那一艘**削输出（`ew_lock_reduce`），
#            外加每艘电子船自带的干扰（`jam_chance`）。
#   ⇒ 减伤的落点从「敌方全体」变成「电子船的攻击目标」，
#     这正是用户要的「电子船正在攻击谁，谁的伤害就直接降低」。
#
# ⚠️ `ew_lock_reduce` 由**羁绊档位**写（2/4 艘 30% / 6 艘 40%），
#    `jam_chance` 由**舰种**写（护卫 5% / 巡洋 10%），两者来源不同，
#    ⛔ 别合并成一个字段。
var is_ew: bool = false            ## 本舰是电子战舰（判据 `EveTraitTable.EW_SHIP_KEYS`）
var ew_lock_reduce: float = 0.0    ## 它锁定的目标输出 ×(1 − 该值)
var jam_chance: float = 0.0        ## 每个干扰周期独立掷一次的命中率
var jam_timer: float = 0.0         ## 距下次掷干扰的倒计时（秒）
var jam_disabled: float = 0.0      ## 被干扰后**不能开火**的剩余秒数

## 输出侧倍率（1.0 = 正常）。被电子船锁定时 < 1。
##
## ⚠️ 与 `incoming_mult`（受击侧）方向相反，别写混：
##      `incoming_mult` 改「我挨打疼不疼」，`outgoing_mult` 改「我打得疼不疼」。
##    电子战的"减伤"是**削敌方输出**，所以必须走这一侧 ——
##    走 `incoming_mult` 会让「敌方全体打我变轻」，那就不是锁定机制了。
## ⚠️ 每 tick 由 `EveBattleSimulator._ew_step()` 从 1.0 重算，
##    ⛔ 不要在其他地方累乘（会被下一帧复位冲掉）。
var outgoing_mult: float = 1.0

## ★ 2026-10-31（用户定案）：装备槽容器。
##
## 长度 = 该舰**吨位**对应的槽位数（护卫/驱逐 1 · 巡洋/战巡 2 · 战列 3），
## 由 `EveFleetFactory.apply_doctrine()` 统一 `resize` —— 那是所有造队链
## （我方 / 敌方 / PvP / 档案预览）唯一的公共入口。
##
## ⚠️ 这里**只放容器**，⛔ 不要在 `EveShip` 里再抄一份「按 cost 查槽位」的表：
##    那份表的真源是 `EveRunState.EQUIP_SLOTS_BY_COST`（掉落 / UI / 验收都读它），
##    抄一份必然分叉（「界面说 2 格、实际只有 1 格」）。
## ⚠️ 元素结构与背包同源（`EveRunState.roll_equip`），空槽 = `{}`。
var equips: Array[Dictionary] = []

## 受到的伤害倍率（1.0 = 正常）。炼狱 BOSS 的「装甲墙」按专注度给 0.15~1.0（连续）。
##
## ⚠️ 与 `resists` 是两回事：抗性是**按伤害类型**逐层算的（EVE 规则），
##    装甲墙是**整艘船**的机制折扣 —— 跑的是"你有多专精"，不是"你的伤害类型对不对"。
##    所以它不进 resists，而是单独乘在结算前的原始伤害上。
## ⚠️ 取值来自 `EveRunState.barrier_mult_for()`；2026-11-01 之前这里是 0.1 的开关。
var incoming_mult: float = 1.0

## 穿甲：对**装甲层**的无视抗性比例（0.25 = 无视 25% 装甲抗性）。
## 来源：武器羁绊「激光炮 6/6」。由 `EveRunState._apply_synergy` 写入，
## 模拟器在 `apply_damage()` 时传给战斗核心（只影响 armor 层）。
var armor_pierce: float = 0.0

## 穿盾：每一发**掷一次**，命中概率就直接越过护盾落到装甲（装甲空则落结构）。
##
## ★ 2026-10-29（用户定案，Sins 式）：12 艘战列舰各自带一个 0~1 的穿盾率
## （见 `EveShipDatabase.BATTLESHIP_SHIELD_PIERCE`），其余 40 艘为 0 ⇒ 行为完全不变。
## ⚠️ 和 `armor_pierce` 不是一回事：那个是「无视装甲抗性」，这个是「跳过整层护盾」。
## 🔮 未来「护盾击穿装备」就是把这一个值拉高（拉到 1.0 = Stellaris 鱼雷式全穿）。
var shield_pierce: float = 0.0

# --- 原始数据（保留武器类型名、导弹参数等未结构化字段） ---
var _extra: Dictionary = {}


static func create(p_id: int, p_name: String, p_faction: int, p_class: int,
		p_team: int, p_cost: int) -> EveShip:
	var s := EveShip.new()
	s.id = p_id
	s.ship_name = p_name
	s.faction = p_faction
	s.ship_class = p_class
	s.team = p_team
	s.cost = p_cost
	s.body = EveDestinyMotion.Body.new(p_id)
	return s


## 应用一套数值（方便从数据表批量构建）
func apply_stats(stats: Dictionary) -> void:
	max_hp[&"shield"] = float(stats.get("shield", 0.0))
	max_hp[&"armor"] = float(stats.get("armor", 0.0))
	max_hp[&"hull"] = float(stats.get("hull", 1.0))
	hp[&"shield"] = max_hp[&"shield"]
	hp[&"armor"] = max_hp[&"armor"]
	hp[&"hull"] = max_hp[&"hull"]

	resists[&"shield"] = stats.get("shield_resists", PackedFloat32Array([0.0, 0.2, 0.4, 0.5]))
	resists[&"armor"] = stats.get("armor_resists", PackedFloat32Array([0.5, 0.35, 0.25, 0.1]))
	resists[&"hull"] = stats.get("hull_resists", PackedFloat32Array([0.0, 0.0, 0.0, 0.0]))

	passive_shield = float(stats.get("passive_shield", 0.0))
	active_shield = float(stats.get("active_shield", 0.0))
	active_armor = float(stats.get("active_armor", 0.0))
	active_hull = float(stats.get("active_hull", 0.0))

	# ★ 后勤：修友军的量 / 层 / 周期。非后勤船三项分别是 0 / 空 / 2 秒，
	#   在 `EveBattleSimulator` 里用 `logistics_repair > 0.0` 一刀拦掉。
	logistics_repair = float(stats.get("logistics_repair", 0.0))
	logistics_layer = StringName(stats.get("logistics_layer", &""))
	logistics_repair_secondary = float(stats.get("logistics_repair_secondary", 0.0))
	logistics_layer_secondary = StringName(stats.get("logistics_layer_secondary", &""))
	logistics_cycle = maxf(0.1, float(stats.get("logistics_cycle", 2.0)))
	logistics_timer = logistics_cycle
	repaired_total = 0.0

	cap_max = float(stats.get("cap_max", 0.0))
	cap = cap_max
	cap_regen = float(stats.get("cap_regen", 0.0))
	cap_use = float(stats.get("cap_use", 0.0))

	weapon_cycle = float(stats.get("weapon_cycle", 1.0))
	weapon_timer = weapon_cycle
	weapon_damage = float(stats.get("weapon_damage", 0.0))
	# ★ 2026-10-29：战列舰的穿盾率（其余船 0）。装备将来直接改这个字段即可。
	shield_pierce = float(stats.get("shield_pierce", 0.0))
	weapon_profile = stats.get("weapon_profile", PackedFloat32Array([0.0, 0.0, 0.0, 1.0]))
	optimal_range = float(stats.get("optimal_range", 0.0))
	falloff = float(stats.get("falloff", 0.0))
	tracking = float(stats.get("tracking", 0.0))
	signature_resolution = float(stats.get("signature_resolution", 400.0))

	traits = stats.get("traits", PackedStringArray())

	# 权威表原值（存在就覆盖；不存在说明这艘船是程序临时造的，保持默认）
	ship_key = StringName(stats.get("ship_key", ""))
	weapon_type = StringName(stats.get("weapon_type", ""))
	defense_type = StringName(stats.get("defense_type", ""))
	role = StringName(stats.get("role", ""))
	# ★ 逻辑 id（可能来自派生字典，也可能没有 ⇒ 兜底现算一次，别留空）
	weapon_id = StringName(stats.get("weapon_id", CIDS.weapon_id_of(String(weapon_type))))
	defense_id = StringName(stats.get("defense_id", CIDS.defense_id_of(String(defense_type))))
	role_id = StringName(stats.get("role_id", CIDS.role_id_of(String(role))))
	is_logistics = bool(stats.get("is_logistics", false))
	attack = float(stats.get("attack", weapon_damage))
	range_cells = int(stats.get("range_cells", 2))
	speed_cells = float(stats.get("speed_cells", 0.1))
	armor_struct = float(stats.get("armor_struct", max_hp[&"armor"] + max_hp[&"hull"]))
	attack_interval = float(stats.get("attack_interval", 0.0))

	body.max_speed = float(stats.get("max_speed", 300.0))
	body.mass = float(stats.get("mass", 1_200_000.0))
	body.agility = float(stats.get("agility", 3.0))
	body.radius = float(stats.get("radius", 50.0))
	body.speed_fraction = 1.0

	# 交战距离：按吨位压进射程内（护卫靠贴身拉角速度，巡洋站边缘）
	desired_range = optimal_range * default_engage_ratio(ship_class)
	# 姿态：按吨位给默认值，玩家可在 HUD 上逐船改写
	stance = default_stance_for_class(ship_class)
	lock_total = EveCombatCore.lock_duration(float(stats.get("scan_res", 400.0)),
			float(stats.get("signature", 40.0)))
	lock_elapsed = 0.0


## 交战距离（自走棋语义，与武器 optimal_range 解耦）
##
## ⚠️ 核心原则：EVE 里玩家可以拒绝交战（往外跑、保持距离），
##    但自走棋【必须强制交战】—— 否则一局永远打不完。
##    实测过：不做强制，双方会在 9~12km 来回拉锯，120 秒零击杀。
##
## 所以交战距离取「自己想要的」与「对方够得着的」两者的较小值：
##   如果对方射程只有 9km，我就算想站 22km 也没意义，
##   因为我退到 22km 对方打不着、我自己也懒得追 → 僵局。
##
## ⚠️ 关于对方容差系数（0.9 而非 1.05）：
##    早期版本用 opponent_optimal * 1.05，含义是「站到对方射程边缘外 5%」。
##    这恰恰制造了僵局 —— 你以为够得着，其实双方都落在 falloff 右半支，
##    命中率极低，谁也打不死谁（实测 180 秒只有 4 个击杀）。
##    改成 0.9 表示「主动站进对方射程内侧 10%」，
##    让交火发生在高命中区间，战斗才能真正推进。
func engagement_range(opponent_optimal: float = -1.0) -> float:
	var want := minf(desired_range, optimal_range)
	if opponent_optimal <= 0.0:
		return want
	# 对方的有效射程（主动压进内侧，留 10% 容错）
	var reachable := opponent_optimal * 0.9
	# 取较小值：保证双方都落在高命中区间
	return minf(want, reachable)


## 默认战术姿态（按吨位）
##
## ⚠️ 这是让 EVE 战斗深度「真正生效」的关键设计，不能随便填。
##
## 原理：命中率由角速度(angular)决定，而角速度只在你**环绕**时才有。
##   纯径向跟随(follow) → 角速度恒为 0 → 追踪属性完全失效 → 必中。
##   所以必须有船主动环绕，追踪/信号半径这一整套机制才有意义。
##
## 分吨位的理由（对应 EVE 真实玩法）：
##   护卫舰：小、快、转向灵活 → 靠环绕拉高角速度来规避大船火力。
##           这是护卫舰唯一的生存手段，必须默认环绕。
##   驱逐舰及以上：都靠射程正面输出，被贴近就吃亏；而且吨位越大转向越迟钝，
##           环绕产生的角速度会先害自己打不中。所以只有护卫舰环绕。
func default_stance_for_class(cls: int) -> int:
	# 只有护卫舰靠环绕生存（小、快、转向灵活，拉高角速度规避大船火力）。
	# 驱逐以上一律「保持距离」：吨位越大转向越迟钝，
	# 环绕产生的角速度会先害自己打不中（自身的 tracking 跟不上），
	# 而且大船有射程优势，绕过去贴身是纯亏。
	if cls == Class.FRIGATE:
		return EveCombatCore.Stance.ORBIT
	return EveCombatCore.Stance.KEEP


## 按吨位给出「站位于射程的哪个位置」的系数
##
## ⚠️ 这个表直接决定战斗能否在限时内收敛，改动前务必理解：
##
##   range_factor 的公式是 0.5^((d - optimal)/falloff)^2 —— 抛物线，
##   在 d = optimal 处取最大值 1.0，两侧对称衰减。
##   所以【站在正好 optimal 处】看似最优，其实是最危险的平衡点：
##   对手只要稍微拉开一点，双方就同时掉进 falloff 的右半支，
##   命中率断崖下跌 → 互相打不死 → 180 秒僵持（实测过，
##   均距稳定卡在 12.8km 时全程只有 4 个击杀，战斗无法收敛）。
##
##   把站位压到射程【内侧】（系数 < 1）就获得了容错：
##   距离波动时仍落在抛物线的高原区，命中率稳定。
##   代价是单次伤害略低，但换来「一定能分出胜负」。
##
## 分吨位的理由（对应 EVE 真实玩法）：
##   护卫舰：小快灵，靠环绕拉高角速度规避大船火力 → 必须贴进射程深处。
##   驱逐舰：有射程优势但脆 → 站在中段，兼顾输出与安全。
##   巡洋舰：又大又慢、转向迟钝，环绕产生的角速度会害自己打不中
##           → 保持距离正面输出，但也要站在射程内侧而非边缘。
func default_engage_ratio(cls: int) -> float:
	match cls:
		Class.FRIGATE:
			return 0.55   # 顶进射程内 55% 处，拉满角速度
		Class.DESTROYER:
			return 0.78   # 站在射程 78% 处
		Class.CRUISER:
			return 0.82   # 不再站 1.0（射程边缘），压到 82% 留出容错
		Class.BATTLE_CRUISER:
			return 0.84   # 越大的船越怕落进 falloff 右半支，站位越往里收
		Class.BATTLESHIP:
			return 0.86
		_:
			return 0.80

## 当前总血量（三层之和，用于胜负判定与 HUD）
func total_hp() -> float:
	return hp[&"shield"] + hp[&"armor"] + hp[&"hull"]


## 火力放大（星级 / power_scale）。
##
## ⚠️ 与 armor_scale 分开是**故意的**，因为敌方的 power_scale
##    「只放大 atk / shield / armor，不碰 speed / atk_speed / atk_range」
##    （交接文档 §6.4 冻结口径）。拆成两个方法后，
##    谁被放大、谁不被放大在读代码时就是一眼可见的。
##
## `attack` 是权威表原值（HUD 展示用），`weapon_damage` 是战斗解算值，
## 两者必须同步放大 —— 否则会出现「面板写 30、实际打 50」的错觉。
func warhead_scale(m: float) -> void:
	weapon_damage *= m
	attack *= m


## 防御放大。这里的「armor」是权威表的合并列（装甲/结构），
## 所以 armor 与 hull 两层一起放大 —— 它们本来就是那一列的拆分结果。
func armor_scale(m: float) -> void:
	for layer in [&"shield", &"armor", &"hull"]:
		max_hp[layer] = float(max_hp[layer]) * m
		hp[layer] = float(max_hp[layer])


func total_max_hp() -> float:
	return max_hp[&"shield"] + max_hp[&"armor"] + max_hp[&"hull"]


## 羁绊用的【分层血量】调整：scale 是乘数、add 是加值，两者可同时给。
##
## ⚠️ 为什么要单独一个方法，而不复用 armor_scale：
##    armor_scale 会把三层一起乘（那是「星级 / 关卡缩放」的口径：整船变强）；
##    而羁绊表里的加成是【指名到层】的 ——
##      「装甲 +20%」只动装甲（权威表的「装甲/结构」合并列 ⇒ 装甲 + 结构两层）；
##      「护盾 +20%」只动护盾；
##      「结构 +150」「护盾 +150」是**固定值**，乘数表达不了。
##    混用会让「艾玛 +20% 装甲」变成「艾玛全船 +20%」，那不是表里写的。
##
## 调整后把 current 拉满 —— 羁绊只在准备阶段生效，开打前全员满血。
func layer_hp_adjust(scale: Dictionary, add: Dictionary) -> void:
	for layer in [&"shield", &"armor", &"hull"]:
		var m := float(scale.get(layer, 1.0))
		var a := float(add.get(layer, 0.0))
		if is_equal_approx(m, 1.0) and is_zero_approx(a):
			continue
		max_hp[layer] = float(max_hp[layer]) * m + a
		hp[layer] = float(max_hp[layer])


## 开火间隔缩放 —— 羁绊「攻击间隔 ×0.85」用（乘数 < 1 = 打得更快）。
##
## ⚠️ 下限 0.05 秒是防御性的：表里的乘数一旦被写成 0，
##    战斗循环会在一帧里塞进无穷多次开火。
func cycle_scale(m: float) -> void:
	weapon_cycle = clampf(weapon_cycle * m, 0.05, 60.0)


## 本船能不能当后勤（修友军）。判据只看「修量 > 0」，不看 `role` 字符串 ——
## 名字与数值分叉时以数值为准（`role` 是给 HUD 看的）。
func is_logistics_unit() -> bool:
	return logistics_repair > 0.0 and not logistics_layer.is_empty()


## 给**友军**（或自己）修一层血。返回实际修进去的点数（0 = 没修到）。
##
## ⚠️ 三条口径，改之前先想清楚：
##   ① **只修 `logistics_layer` 那一层**（盾抗船修盾 / 甲抗船修甲）。
##      不修结构 —— 结构在 EVE 里是「最后一道血」，能修结构就等于
##      给了第二条命，战斗会打不完（同 `REPAIR_ACTIVE_SCALE` 的教训）。
##   ② **不超上限**：到顶就 0，不会把溢出的量挪给别的层。
##   ③ ★ **可以修自己**（2026-10-01 改口径，原先是"不修自己"）。
##      旧口径导致后勤全程空转：敌方总是先打最近的单位，而后勤就站在前排
##      ⇒ 队友没伤、自己又不能修 ⇒ 实测可修窗口 0/724 帧。
##      详见 `EveBattleSimulator._pick_repair_target` 的完整说明。
##
## ⚠️ 参数名叫 `target` 而不是 `ally`：它现在**可以是自己**。
##    名字留在调用点上会被读成"只对友军"，所以这里只说 target。
func repair_ally(target: EveShip) -> float:
	return _repair_layer(target, logistics_layer, logistics_repair)


## ★ 2026-10-28 衍生层那一笔（另一层护盾/装甲，量 = 主修 × 3/7）。
##
## 与 `repair_ally` 是**两笔独立结算**：各自挑自己那层里最缺的目标
## （挑人逻辑在 `EveBattleSimulator._replenish_own_ships`）。
## 返回值同样是「实际修进去的点数」，0 = 没修到（目标那层已满 / 没目标）。
func repair_ally_secondary(target: EveShip) -> float:
	return _repair_layer(target, logistics_layer_secondary, logistics_repair_secondary)


## 修一层的共用实现。三条口径见 `repair_ally` 的注释（只修这一层 / 不超上限 / 可修自己）。
func _repair_layer(target: EveShip, layer: StringName, amount: float) -> float:
	if target == null or not target.alive:
		return 0.0
	if layer.is_empty() or amount <= 0.0:
		return 0.0
	var cap := float(target.max_hp.get(layer, 0.0))
	if cap <= 0.0:
		return 0.0
	var before := float(target.hp.get(layer, 0.0))
	target.hp[layer] = minf(cap, before + amount)
	var gained := float(target.hp[layer]) - before
	repaired_total += gained
	return gained


## 移速缩放 —— 羁绊「移速 ×1.2」用。
func speed_scale(m: float) -> void:
	if body != null:
		body.max_speed = maxf(1.0, body.max_speed * m)


## 后勤维修强化 —— 羁绊「后勤」用（2026-10-26）。
##
## `amount_mult` 乘每次修理量，`cycle_mult` 乘修理间隔（<1 = 修得更勤）。
## ⚠️ 非后勤船 `logistics_repair` 是 0 ⇒ 直接返回，不留「半生效状态」。
## ⛔ 间隔下限 0.3s：再快就低于战斗 tick 的可读分辨率，视觉上变成持续回血。
func repair_scale(amount_mult: float, cycle_mult: float) -> void:
	if logistics_repair <= 0.0 or logistics_layer.is_empty():
		return
	logistics_repair *= amount_mult
	# ★ 2026-10-28：衍生层同乘 —— 否则羁绊只强化主修，两层比例会被悄悄改掉。
	logistics_repair_secondary *= amount_mult
	logistics_cycle = maxf(0.3, logistics_cycle * cycle_mult)


## ★ 2026-10-10（i18n）：以下三个是**显示名**，走 `EveTerms` 取词
##   （英文 = EVE 官方原名，中文 = 官方译名）。
##
## ⛔⛔ **`FACTION_NAMES` / `CLASS_NAMES` 这两张表本身不许翻**，上面那三个
##   `weapon_type` / `defense_type` / `role` 字段同理 —— 它们是
##   `EveTraitTable.EFFECTS` 与 `count()` 的**逻辑键**（中文查表）。
##   把它们换成英文 = 羁绊静默失效（凑齐了却不加属性、一条报错都没有）。
func faction_name() -> String:
	var cn := String(FACTION_NAMES.get(faction, ""))
	return TERMS.faction(cn) if cn != "" else "未知"


func class_name_cn() -> String:
	# key = 费用档（`CLASS.<cost>`），中文兜底取自 `CLASS_NAMES`。
	var cn := String(CLASS_NAMES.get(ship_class, ""))
	return TERMS.ship_class(cost, cn) if cn != "" else "未知"


## 武器显示名（激光炮 / 混合炮 …）。⚠️ 不是 `weapon_type` —— 那个是逻辑键。
func weapon_label() -> String:
	return TERMS.weapon(weapon_id)


func defense_label() -> String:
	return TERMS.defense(defense_id)


func role_label() -> String:
	return TERMS.role(role_id)


func faction_color() -> Color:
	return FACTION_COLORS.get(faction, Color.GRAY)
