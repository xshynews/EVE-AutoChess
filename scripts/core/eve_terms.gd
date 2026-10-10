extends RefCounted

## ⏸⏸ **2026-10-11 冻结**：英文版现在时机不成熟，先不做。
## 这一层保留（它在 zh_CN 下原样返回中文，不影响中文版任何行为），但⛔ 不再扩展。
## 解冻条件：英文文案过审 + UI 面迁完。详见 `i18n/README.md` 顶部。

## 术语取词 —— 舰船 / 吨位 / 势力 / 武器 / 防御 / 定位 / 羁绊名的**唯一显示出口**
##
## ══════════════════════════════════════════════════════════════════
##  为什么单独一层（而不是在数据表里直接写 `tr()`）
## ══════════════════════════════════════════════════════════════════
##  ① **这些名字必须用 EVE 官方译名**（用户 2026-10-10 定调：
##     「舰船、羁绊一定要遵循 EVE 官方的翻译，意译在这个时候是绝对不行的」）。
##       · 英文 = EVE 官方英文原名 —— 来源 `EveShipAssetIndex` 的 `name_en`
##         （由 ESI `/universe/ids/` 拿 typeID 再取 name，不是人写的）；
##       · 中文 = EVE 官方简中译名 —— 来源 `EveShipTable.ROWS`
##         （带 typeID 的资产索引可交叉验证，见 `verify_i18n`）。
##     两边都在 `i18n/strings.csv` 的**术语段**里，由
##     `tools/pipeline/gen_i18n_terms.py` 从表生成 ⇒ ⛔ **别手改术语行**。
##
##  ② ★★ **中文仍然是逻辑主键**：羁绊效果表 `EveTraitTable.EFFECTS`、
##     `count()`、`ship_has()` 全都按中文查表。所以**只换显示名，不换逻辑键**
##     —— ⛔ 把 `EveTraitTable.members()[i]["name"]` 或 `EveShip.weapon_type`
##     改成英文 = 羁绊静默失效（凑齐了却不加属性，且一条报错都没有）。
##     显示一律走本模块。
##
##  ③ ⚠️ 取不到 key（表里新加了船/词但没重跑生成器）⇒ 回落调用点给的
##     **中文源文**，⛔ 不会把 `SHIP.xxx` 这种 key 甩给玩家。
##     这种「看着正常、其实没翻」的状态由 `verify_i18n` 逐条报出来。
##
##  ★ 2026-10-10 立。术语段的键一律 ASCII 且由 id 推导（⛔ 不用中文当 key）。

const T := preload("res://scripts/core/eve_text.gd")
const CIDS := preload("res://scripts/core/eve_combat_ids.gd")

const K_SHIP := "SHIP."
const K_CLASS := "CLASS."
const K_FACTION := "FACTION."
const K_WEAPON := "WEAPON."
const K_DEFENSE := "DEFENSE."
const K_ROLE := "ROLE."


# ──────────────────────────────────────────────────────────── 舰船 / 吨位
## 舰船显示名。`ship_key` = 权威表的 ASCII 主键（`condor` / `executioner` …）。
##
## ⚠️ 一律**显式传中文源文**当兜底 —— 别图省事写 `T.t("SHIP." + key)`，
##    那样漏翻时玩家会看到 `SHIP.condor`。
static func ship(ship_key: StringName, cn: String) -> String:
	var k := String(ship_key)
	if k.is_empty():
		return cn
	return T.t(StringName(K_SHIP + k), cn)


## 吨位（= 费用档）显示名。`cost` 1~5。
static func ship_class(cost: int, cn: String) -> String:
	return T.t(StringName(K_CLASS + str(cost)), cn)


# ──────────────────────────────────────────────────────────── 势力 / 羁绊
## 势力显示名。入参 = 权威表里的中文原值（`艾玛` …）。
static func faction(cn: String) -> String:
	var id: StringName = StringName(CIDS.FACTION_FROM_CN.get(cn, &""))
	return faction_by_id(id, cn)


## 势力显示名（已知 id 时用这个，省一次中文→id 映射）。
static func faction_by_id(id: StringName, cn: String) -> String:
	if String(id).is_empty():
		return cn
	return T.t(StringName(K_FACTION + String(id)), cn)


## 武器显示名。入参 = `EveCombatIds` 的武器 id（`CIDS.W_LASER` …）。
## ⚠️ **别传中文**（中文→id 的映射只该在装配时做一次）。
static func weapon(id: StringName) -> String:
	var cn := String(CIDS.WEAPON_LABEL.get(id, ""))
	if cn.is_empty():
		return String(id)
	return T.t(StringName(K_WEAPON + String(id)), cn)


static func defense(id: StringName) -> String:
	var cn := String(CIDS.DEFENSE_LABEL.get(id, ""))
	if cn.is_empty():
		return String(id)
	return T.t(StringName(K_DEFENSE + String(id)), cn)


static func role(id: StringName) -> String:
	var cn := String(CIDS.ROLE_LABEL.get(id, ""))
	if cn.is_empty():
		return String(id)
	return T.t(StringName(K_ROLE + String(id)), cn)


## 羁绊**成员**显示名。入参 = 羁绊表里的中文原值（`艾玛` / `激光炮` / `甲抗` …）。
##
## ⚠️ 三组的成员名恰好就是势力 / 武器 / 防御 —— 键**复用**那三张表，
##    ⛔ 别另立 `TRAIT.*` 一套（两份一定会分叉）。
static func trait_member(group: StringName, cn: String) -> String:
	match group:
		&"faction":
			return faction(cn)
		&"weapon":
			return weapon(CIDS.weapon_id_of(cn))
		&"defense":
			return defense(CIDS.defense_id_of(cn))
	return cn


## 羁绊**分组**名（「势力 FACTION」/「武器 WEAPON」/「防御 DEFENSE」）。
##
## ⚠️ 这三条是**本作自己的 UI 文案**（不是 EVE 术语）⇒ 手写在 `strings.csv` 里，
##    不归生成器管。
static func trait_group(group: StringName, cn: String) -> String:
	return T.t(StringName("TRAITGROUP." + String(group)), cn)
