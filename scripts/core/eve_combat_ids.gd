extends RefCounted
class_name EveCombatIds

## 战斗语义 ID —— **逻辑只认 id，不认中文**（审查 2#5）
##
## ══════════════════════════════════════════════════════════════════
##  要解决的两个病
## ══════════════════════════════════════════════════════════════════
##  ① **拼错一个字不会报错**。旧写法 `weapon_type == "导弹"`：把表里的
##     "导弹" 打成 "导弹炮"，判断直接落进 elseif ⇒ 导弹船被当成炮塔算命中率，
##     而且**一条报错都没有**（静默走默认分支）。
##  ② **文案一改逻辑就崩**。中文字面量同时兼任「主键」和「显示名」，
##     将来上多语言（审查 2#6）时逻辑会跟着文案一起翻车。
##
## ⇒ 修法：数值表里的中文是**设计侧原值**（保持逐字不改，`verify_data_source`
##   在对拍它），在**装配时**映射成稳定 ASCII id；逻辑一律比 id，
##   显示名走 `*_LABEL` 表（将来 i18n 只换这三张表）。
##
##  ⚠️ 映射**只有这一处**。⛔ 别在别处再写一份 `"盾抗" if ... else "甲抗"`。

# ── 武器 ──
const W_LASER := &"laser"          ## 激光炮
const W_HYBRID := &"hybrid"        ## 混合炮
const W_PROJECTILE := &"proj"      ## 射弹炮
const W_MISSILE := &"missile"      ## 导弹

# ── 防御 ──
const D_SHIELD := &"shield"        ## 盾抗
const D_ARMOR := &"armor"          ## 甲抗

# ── 定位 ──
const R_ATTACK := &"attack"        ## 攻击型
const R_DEFENSE := &"defense"      ## 防御型
const R_LOGI := &"logi"            ## 后勤

# ── 势力 ──
## ★ 2026-10-10（i18n）：与武器/防御/定位同一套「中文 → ASCII id」口径。
##    i18n 的术语键是 `FACTION.<id>`，所以这里必须有一份 id（⛔ 不能从
##    `EveShip.Faction` 的枚举序号推 —— 序号是另一套口径，混用必错）。
const F_AMARR := &"amarr"
const F_CALDARI := &"caldari"
const F_GALLENTE := &"gallente"
const F_MINMATAR := &"minmatar"

## 中文（= `EveShipTable.ROWS` 的原始值）→ id
const WEAPON_FROM_CN := {
	"激光炮": W_LASER, "混合炮": W_HYBRID, "射弹炮": W_PROJECTILE, "导弹": W_MISSILE,
}
const DEFENSE_FROM_CN := {"盾抗": D_SHIELD, "甲抗": D_ARMOR}
const ROLE_FROM_CN := {"攻击型": R_ATTACK, "防御型": R_DEFENSE, "后勤": R_LOGI}
const FACTION_FROM_CN := {
	"艾玛": F_AMARR, "加达里": F_CALDARI, "盖伦特": F_GALLENTE, "米玛塔尔": F_MINMATAR,
}

## id → 中文显示名（**将来做多语言只动这几张表**）
const WEAPON_LABEL := {
	W_LASER: "激光炮", W_HYBRID: "混合炮", W_PROJECTILE: "射弹炮", W_MISSILE: "导弹",
}
const DEFENSE_LABEL := {D_SHIELD: "盾抗", D_ARMOR: "甲抗"}
const ROLE_LABEL := {R_ATTACK: "攻击型", R_DEFENSE: "防御型", R_LOGI: "后勤"}
const FACTION_LABEL := {
	F_AMARR: "艾玛", F_CALDARI: "加达里", F_GALLENTE: "盖伦特", F_MINMATAR: "米玛塔尔",
}


static func weapon_id_of(cn: String) -> StringName:
	return StringName(WEAPON_FROM_CN.get(cn, &""))


static func defense_id_of(cn: String) -> StringName:
	return StringName(DEFENSE_FROM_CN.get(cn, &""))


static func role_id_of(cn: String) -> StringName:
	return StringName(ROLE_FROM_CN.get(cn, &""))


## 未知取值校验 —— 返回非空 = 表里出现了**不认识的**取值
##（拼错一个字，或设计侧新增了没登记的取值）。
##
## ⚠️ 这是"拼错字"的**唯一**拦截点：映射表查不到 ⇒ 这里报出来。
## ⛔ 别改成"查不到就当默认值"—— 那正是原来那个静默 bug。
static func unknown_values(weapon_cn: String, defense_cn: String,
		role_cn: String) -> PackedStringArray:
	var out := PackedStringArray()
	var w := weapon_cn.strip_edges()
	var d := defense_cn.strip_edges()
	var r := role_cn.strip_edges()
	if not WEAPON_FROM_CN.has(w):
		out.append("武器=%s" % w)
	if not DEFENSE_FROM_CN.has(d):
		out.append("防御=%s" % d)
	if not ROLE_FROM_CN.has(r):
		out.append("定位=%s" % r)
	return out


## 整行（`EveShipTable.ROWS` 的一行）的未知取值校验。
static func unknown_values_of_row(row: Array) -> PackedStringArray:
	if row.size() < 7:
		return PackedStringArray(["行长度不足（%d）" % row.size()])
	return unknown_values(String(row[3]), String(row[4]), String(row[6]))


# ══════════════════════════════════════════════════════════════════
#  `EveShip._extra` 的键名常量
# ══════════════════════════════════════════════════════════════════
#
#  `_extra` 是个**无类型字典**（保留权威表原值），读它时手写字符串键
#  同样是"拼错不报错"。常用键在这里给常量，读取点一律用常量。
const X_SIGNATURE := "signature"
const X_WEAPON_TYPE := "weapon_type"
const X_EXPLOSION_RADIUS := "explosion_radius"
const X_EXPLOSION_VELOCITY := "explosion_velocity"
const X_ATTACK := "attack"
const X_ARMOR_STRUCT := "armor_struct"
