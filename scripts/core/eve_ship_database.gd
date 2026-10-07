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
const CELL_METERS := 6000.0
const ARMOR_SHARE := 0.65
const ATTACK_CYCLE_SECONDS := 1.0

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
	"激光炮": 3000.0,
	"混合炮": 4000.0,
	"射弹炮": 6000.0,
	"导弹": 0.0,
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
	"激光炮": 0.300,
	"混合炮": 0.330,
	"射弹炮": 0.520,
	"导弹": 999.0,
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
static var SHIELD_TANK_SHIELD_RESISTS := PackedFloat32Array([0.0, 0.45, 0.55, 0.60])
static var SHIELD_TANK_ARMOR_RESISTS := PackedFloat32Array([0.50, 0.30, 0.20, 0.10])
static var ARMOR_TANK_SHIELD_RESISTS := PackedFloat32Array([0.0, 0.20, 0.40, 0.50])
static var ARMOR_TANK_ARMOR_RESISTS := PackedFloat32Array([0.60, 0.35, 0.25, 0.10])
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

## 原始行 → 工程用的完整数值 Dictionary
##
## 输出的字段分两类：
##   ① 权威原值（ship_key / weapon_type / attack / range_cells …）—— 直通，不加工
##   ② 派生值（armor / hull / optimal_range / max_speed …）—— 由换算常数算出
static func derive(row: Dictionary) -> Dictionary:
	var cost := int(row["cost"])
	var cls := int(EveShip.CLASS_BY_COST.get(cost, EveShip.Class.FRIGATE))
	var weapon := String(row["weapon"])
	var defense := String(row["defense"])

	# --- ① 装甲 / 结构 拆分（见文件头规则 ②）---
	var armor_struct := float(row["armor_struct"])
	var armor := roundf(armor_struct * ARMOR_SHARE)
	var hull := armor_struct - armor
	var shield := float(row["shield"])

	# --- ② 抗性档位 ---
	var shield_tank := (defense == "盾抗")
	var s_res := SHIELD_TANK_SHIELD_RESISTS if shield_tank else ARMOR_TANK_SHIELD_RESISTS
	var a_res := SHIELD_TANK_ARMOR_RESISTS if shield_tank else ARMOR_TANK_ARMOR_RESISTS

	# --- ③ 格 → 米 ---
	var range_cells := int(row["range_cells"])
	var speed_cells := float(row["speed_cells"])
	var optimal := float(range_cells) * CELL_METERS
	var max_speed := speed_cells * CELL_METERS

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
	var logi_layer := (&"shield" if defense == "盾抗" else &"armor") if is_logi else &""
	var logi_repair := float(LOGISTICS_REPAIR.get(cost, LOGISTICS_REPAIR[1])) if is_logi else 0.0

	return {
		# ── 身份 ──
		"ship_key": StringName(row["id"]),
		"name": String(row["name"]),
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
		"is_logistics": bool(row["logistics"]),
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
		"weapon_damage": logi_atk if is_logi else float(row["attack"]),
		"weapon_cycle": ATTACK_CYCLE_SECONDS,
		"weapon_profile": WEAPON_PROFILE.get(StringName(weapon), PROFILE_MISSILE),
		"optimal_range": optimal,
		"falloff": float(WEAPON_FALLOFF.get(weapon, 0.0)),
		"tracking": float(WEAPON_TRACKING.get(weapon, 0.1)) / decay,
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
