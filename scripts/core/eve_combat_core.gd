extends RefCounted
class_name EveCombatCore

## EVE 自走棋 —— 战斗数学核心
##
## 公式来源：EVE 官方战斗数学（参考 carbonengine/destiny 与 EVE 客户端行为逆向）
## 本文件只做纯数学，不依赖任何节点，可在无头模式下单独测试。
##
## 变更清单（初版）：
##   - 三层血量 shield / armor / hull，逐层穿透
##   - 四类伤害 EM / THERMAL / KINETIC / EXPLOSIVE，带抗性
##   - 炮塔命中：范围系数 x 追踪系数（角速度驱动）
##   - 电容回充：4 * cap_regen * (sqrt(f) - f)
##   - 锁定时间：40000 / (scan_res * asinh(sig)^2)

const DAMAGE_TYPES := 4
const LAYERS: Array[StringName] = [&"shield", &"armor", &"hull"]

## 伤害类型索引（与 EVE 一致）
enum Dmg { EM = 0, THERMAL = 1, KINETIC = 2, EXPLOSIVE = 3 }

## 命中质量档位
enum HitQuality { MISS, BARELY, LIGHT, HIT, PENETRATING, SMASHING, WRECKING }

## 战斗姿态（取自 EVE 客户端 motion() 的官方语义）
enum Stance { APPROACH, KEEP, ORBIT, KITE, MANUAL }


static func clampf01(v: float) -> float:
	return clampf(v, 0.0, 1.0)


# ---------------------------------------------------------------- 伤害与抗性

## 把伤害分布归一化成 4 项权重（总和不为一则平均）
static func normalize_damage_profile(profile: PackedFloat32Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(DAMAGE_TYPES)
	out.fill(0.0)
	if profile == null:
		out.fill(0.25)
		return out
	var total := 0.0
	for i in DAMAGE_TYPES:
		var v: float = maxf(0.0, profile[i]) if i < profile.size() else 0.0
		out[i] = v
		total += v
	if total <= 0.0:
		out.fill(0.25)
		return out
	for i in DAMAGE_TYPES:
		out[i] /= total
	return out


## 本层实际生效的伤害倍率（1 - 抗性），带归一化权重
static func damage_factor(profile: PackedFloat32Array, resists: PackedFloat32Array) -> float:
	var mix := normalize_damage_profile(profile)
	var sum := 0.0
	for i in DAMAGE_TYPES:
		var r: float = clampf(resists[i] if i < resists.size() else 0.0, 0.0, 0.999999)
		sum += mix[i] * (1.0 - r)
	return sum


# ---------------------------------------------------------------- 运动学

## 相对运动解算 —— 无格子棋盘的判定基石
## 返回 distance / radial / transversal / angular
##   radial       径向速度（接近为负、远离为正）
##   transversal  切向速度（决定炮塔能否跟上）
##   angular      角速度 = transversal / distance  ← 命中率的真正决定因素
static func relative_motion(own_pos: Vector3, own_vel: Vector3,
		target_pos: Vector3, target_vel: Vector3) -> Dictionary:
	var rel_pos := target_pos - own_pos
	var distance := rel_pos.length()
	var radial_unit := rel_pos.normalized() if distance > 1e-9 else Vector3(1, 0, 0)
	var rel_vel := target_vel - own_vel
	var radial := rel_vel.dot(radial_unit)
	var transversal_vec := rel_vel - radial_unit * radial
	var transversal := transversal_vec.length()
	var angular := 0.0
	if distance > 1e-9:
		angular = transversal / distance
	elif transversal > 1e-9:
		angular = INF
	return {
		"distance": distance,
		"radial": radial,
		"transversal": transversal,
		"angular": angular,
	}


# ---------------------------------------------------------------- 炮塔命中

## 炮塔命中概率
##   range_factor     = 0.5 ^ ((distance - optimal) / falloff)^2
##   tracking_factor  = 0.5 ^ ((angular * sig_resolution) / (tracking * sig))^2
static func turret_chance_to_hit(optimal: float, falloff: float, tracking: float,
		signature_resolution: float, target_signature: float,
		distance: float, angular: float) -> Dictionary:
	var range_factor := 0.0
	if falloff > 0.0:
		var x: float = maxf(0.0, distance - optimal) / falloff
		range_factor = pow(0.5, x * x)
	else:
		range_factor = 1.0 if distance <= optimal else 0.0

	var tracking_factor := 0.0
	if tracking > 0.0 and is_finite(angular):
		var y: float = (angular * signature_resolution) / maxf(0.001, tracking * maxf(1.0, target_signature))
		tracking_factor = pow(0.5, y * y)
	else:
		tracking_factor = 1.0 if is_zero_approx(angular) else 0.0

	return {
		"chance": clampf01(range_factor * tracking_factor),
		"range_factor": range_factor,
		"tracking_factor": tracking_factor,
	}


## 期望伤害倍率（含 1% 毁灭打击 x3）
static func turret_expected_multiplier(chance_to_hit: float) -> float:
	var chance := clampf01(chance_to_hit)
	var wrecking: float = minf(chance, 0.01)
	var normal: float = chance - wrecking
	var result := wrecking * 3.0
	if normal > 0.0:
		result += normal * ((0.01 + chance) / 2.0 + 0.49)
	return result


## 单次命中质量判定
static func turret_hit_quality(chance_to_hit: float, roll: float) -> Dictionary:
	var chance := clampf01(chance_to_hit)
	var r := clampf(roll, 0.0, 0.9999999)
	if r >= chance:
		return {"hit": false, "quality": HitQuality.MISS, "multiplier": 0.0}
	if r < 0.01:
		return {"hit": true, "quality": HitQuality.WRECKING, "multiplier": 3.0}
	var multiplier := r + 0.49
	var quality := HitQuality.HIT
	if multiplier < 0.625:
		quality = HitQuality.BARELY
	elif multiplier < 0.75:
		quality = HitQuality.LIGHT
	elif multiplier < 1.0:
		quality = HitQuality.HIT
	elif multiplier < 1.25:
		quality = HitQuality.PENETRATING
	else:
		quality = HitQuality.SMASHING
	return {"hit": true, "quality": quality, "multiplier": multiplier}


## 导弹伤害应用（爆炸半径 / 爆炸速度 / 信号半径 三方取最小）
static func missile_application(explosion_radius: float, explosion_velocity: float,
		damage_reduction_factor: float, target_signature: float, target_speed: float) -> float:
	if explosion_radius <= 0.0:
		return 1.0
	var sig: float = maxf(1.0, target_signature)
	var factors: Array[float] = [1.0, sig / explosion_radius]
	if target_speed > 0.0:
		var drf: float = maxf(0.01, damage_reduction_factor)
		var base: float = (explosion_velocity * sig) / (explosion_radius * target_speed)
		factors.append(pow(base, drf))
	var result: float = factors[0]
	for f in factors:
		result = minf(result, f)
	return maxf(0.0, result)


# ---------------------------------------------------------------- 锁定

## 锁定时间（EVE 官方公式）
static func lock_duration(scan_resolution: float, signature_radius: float) -> float:
	var scan: float = maxf(1.0, scan_resolution)
	var sig: float = maxf(1.0, signature_radius)
	return maxf(0.1, 40000.0 / (scan * pow(asinh(sig), 2.0)))


# ---------------------------------------------------------------- 伤害应用

## 按 shield -> armor -> hull 逐层穿透
## 返回 applied（实际生效量）/ applied_by_type / remaining / breaks（破层事件）
static func apply_damage(hp: Dictionary, resists: Dictionary, amount: float,
		profile: PackedFloat32Array, bypass_resists: bool = false) -> Dictionary:
	var remaining: float = maxf(0.0, amount)
	var applied := 0.0
	var applied_by_type := PackedFloat32Array()
	applied_by_type.resize(DAMAGE_TYPES)
	applied_by_type.fill(0.0)
	var mix := normalize_damage_profile(profile)
	var breaks: Array[StringName] = []

	for layer in LAYERS:
		if remaining <= 0.0:
			break
		var current: float = maxf(0.0, hp.get(layer, 0.0))
		if current <= 0.0:
			continue
		var layer_resists: PackedFloat32Array = resists.get(layer, PackedFloat32Array([0, 0, 0, 0]))
		var factors := PackedFloat32Array()
		factors.resize(DAMAGE_TYPES)
		var factor_sum := 0.0
		for i in DAMAGE_TYPES:
			var r: float = 0.0
			if not bypass_resists:
				r = clampf(layer_resists[i] if i < layer_resists.size() else 0.0, 0.0, 0.999999)
			factors[i] = mix[i] * (1.0 - r)
			factor_sum += factors[i]
		if factor_sum <= 0.0:
			continue

		var available := remaining * factor_sum
		if available + 1e-7 >= current:
			var used := current / factor_sum
			for i in DAMAGE_TYPES:
				applied_by_type[i] += used * factors[i]
			hp[layer] = 0.0
			remaining = maxf(0.0, remaining - used)
			applied += current
			breaks.append(layer)
		else:
			for i in DAMAGE_TYPES:
				applied_by_type[i] += remaining * factors[i]
			hp[layer] = current - available
			applied += available
			remaining = 0.0

	return {
		"applied": applied,
		"applied_by_type": applied_by_type,
		"remaining": remaining,
		"breaks": breaks,
	}


# ---------------------------------------------------------------- 电容

## 电容回充（EVE 官方曲线）
##   recharge = 4 * cap_regen * (sqrt(f) - f)
## 干涸判定：<1% 触发，恢复到 15% 解除
static func update_capacitor(cap: float, cap_max: float, cap_regen: float,
		cap_use: float, cap_dry: bool, dt: float) -> Dictionary:
	if cap_max <= 0.0:
		return {"cap": cap, "cap_dry": cap_dry, "dry_changed": false, "recharge": 0.0, "drain": 0.0}

	var was_dry := cap_dry
	var raw_fraction := clampf01(cap / cap_max)
	var recharge_fraction: float = raw_fraction
	if cap <= 0.01:
		recharge_fraction = maxf(0.0004, raw_fraction)
	var recharge: float = 4.0 * maxf(0.0, cap_regen) * (sqrt(recharge_fraction) - recharge_fraction)
	var drain: float = 0.0 if cap_dry else maxf(0.0, cap_use)

	var new_cap := clampf(cap + (recharge - drain) * maxf(0.0, dt), 0.0, cap_max)
	var new_dry := cap_dry
	if not cap_dry and new_cap <= 0.01:
		new_dry = true
	elif cap_dry and new_cap >= cap_max * 0.15:
		new_dry = false

	return {
		"cap": new_cap,
		"cap_dry": new_dry,
		"dry_changed": was_dry != new_dry,
		"recharge": recharge,
		"drain": drain,
	}


## 护盾被动回充 + 主动修理（电容干涸时主动修理停止）
## 修理（护盾被动回充 + 主动修盾/甲/结构）
##
## ⚠️ 自走棋语境下的重要修正（踩坑记录，改动前必读）：
##
##   EVE 原版里主动修理是「永动机」—— 开着修甲就能扛住同吨位火力，
##   所以 EVE 的小规模 PVP 常常打成「谁也打不死谁」，靠队友集火破局。
##
##   但自走棋【单回合必须分出胜负】，修理如果不能被打穿，
##   整局就会卡到 180 秒超时（实测：总输出 27,272 伤害中
##   有 23,891 被修理抵消，净伤只有 3,381，180 秒零击杀）。
##
##   → 所以主动修理速率要压到「明显低于同吨位火力」的水平，
##     定位从「永动机」改为「延迟死亡的缓冲」，只影响节奏不影响胜负。
##
##   参数 REPAIR_ACTIVE_SCALE 就是这层缩放。取 0.35 时：
##     护卫主动修甲 18/s -> 6.3/s，180 秒 1134 点，
##     对比其承受伤害 ~2727，占比 42% —— 明显削血但仍能被击穿。
const REPAIR_ACTIVE_SCALE := 0.35

static func repair(hp: Dictionary, max_hp: Dictionary, passive_shield: float,
		active_shield: float, active_armor: float, active_hull: float,
		cap_dry: bool, dt: float) -> Dictionary:
	var applied := {"shield": 0.0, "armor": 0.0, "hull": 0.0}
	if hp.get(&"hull", 0.0) <= 0.0:
		return applied
	var seconds: float = maxf(0.0, dt)
	var powered := not cap_dry

	# 被动护盾回充：这是 EVE 的真实公式（峰值出现在 25% 护盾时），
	# 速率天然很低，不需要额外缩放。
	var shield_max: float = maxf(0.0, max_hp.get(&"shield", 0.0))
	var shield_fraction := clampf01(hp.get(&"shield", 0.0) / shield_max) if shield_max > 0.0 else 0.0
	var passive: float = 4.0 * maxf(0.0, passive_shield) * (sqrt(shield_fraction) - shield_fraction)

	var shield_before: float = hp.get(&"shield", 0.0)
	var active_s := maxf(0.0, active_shield) * REPAIR_ACTIVE_SCALE if powered else 0.0
	hp[&"shield"] = minf(shield_max, shield_before + (passive + active_s) * seconds)
	applied["shield"] = hp[&"shield"] - shield_before

	if powered:
		for layer in [&"armor", &"hull"]:
			var before: float = hp.get(layer, 0.0)
			var active: float = (active_armor if layer == &"armor" else active_hull) \
					* REPAIR_ACTIVE_SCALE
			hp[layer] = minf(maxf(0.0, max_hp.get(layer, 0.0)), before + maxf(0.0, active) * seconds)
			applied[layer] = hp[layer] - before

	return applied


# ---------------------------------------------------------------- 综合抗性

## 用 EHP 加权算综合抗性（用于 HUD 显示单一抗性数）
static func aggregate_resists(shield: float, armor: float, hull: float,
		shield_resists: PackedFloat32Array, armor_resists: PackedFloat32Array,
		hull_resists: PackedFloat32Array) -> PackedFloat32Array:
	var s: float = maxf(0.0, shield)
	var a: float = maxf(0.0, armor)
	var h: float = maxf(0.0, hull)
	var hp_total: float = maxf(1.0, s + a + h)
	var out := PackedFloat32Array()
	out.resize(DAMAGE_TYPES)
	for i in DAMAGE_TYPES:
		var ehp := 0.0
		ehp += s / maxf(0.001, 1.0 - (shield_resists[i] if i < shield_resists.size() else 0.0))
		ehp += a / maxf(0.001, 1.0 - (armor_resists[i] if i < armor_resists.size() else 0.0))
		ehp += h / maxf(0.001, 1.0 - (hull_resists[i] if i < hull_resists.size() else 0.0))
		out[i] = clampf(1.0 - hp_total / maxf(hp_total, ehp), 0.0, 0.999)
	return out


# ---------------------------------------------------------------- 胜负

static func resolve_outcome(own_hull: float, target_hull: float) -> Dictionary:
	var own_dead := own_hull <= 0.0
	var target_dead := target_hull <= 0.0
	if not own_dead and not target_dead:
		return {"finished": false, "winner": &"", "phase": &"running"}
	var winner: StringName = &"draw"
	if own_dead and not target_dead:
		winner = &"target"
	elif target_dead and not own_dead:
		winner = &"own"
	return {"finished": true, "winner": winner, "phase": winner}
