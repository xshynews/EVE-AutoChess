extends RefCounted
class_name EveTraitTable

## EVE 自走棋 —— 羁绊表
##
## ══════════════════════════════════════════════════════════════════
##  数据来源（唯一真源）
## ══════════════════════════════════════════════════════════════════
##  `F:\eve-chess\重启交接-2026-09-17\附件\02_羁绊系统表.csv`
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

## 分组顺序 = 舰队构成窗的显示顺序。tiers 来自 CSV 的「一档阈值 / 二档阈值」。
const GROUPS: Array = [
	{"key": &"faction", "label": "势力 FACTION", "tiers": [2, 4]},
	{"key": &"weapon", "label": "武器 WEAPON", "tiers": [3, 6]},
	{"key": &"defense", "label": "防御 DEFENSE", "tiers": [3, 6]},
]

## 成员（显示名 + 颜色）。颜色约定：
##   派系用 EVE 官方识别色（艾玛金 / 加达里青 / 盖伦特绿 / 米玛塔尔红），
##   武器统一用冷青（它们本来就同类），防御统一用橙（都是抗性）。
static func members(group: StringName) -> Array[Dictionary]:
	match group:
		&"faction":
			return [
				{"name": "艾玛",     "color": EveWindow.C_FACTION_AMARR},
				{"name": "加达里",   "color": EveWindow.C_FACTION_CALDARI},
				{"name": "盖伦特",   "color": EveWindow.C_FACTION_GALLENTE},
				{"name": "米玛塔尔", "color": EveWindow.C_FACTION_MINMATAR},
			]
		&"weapon":
			return [
				{"name": "激光炮", "color": EveWindow.C_WEAPON},
				{"name": "混合炮", "color": EveWindow.C_WEAPON},
				{"name": "射弹炮", "color": EveWindow.C_WEAPON},
				{"name": "导弹",   "color": EveWindow.C_WEAPON},
			]
		&"defense":
			return [
				{"name": "甲抗", "color": EveWindow.C_DEFENSE},
				{"name": "盾抗", "color": EveWindow.C_DEFENSE},
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
				"apply": {"attack_pct": 0.10}, "pending": ["无视 10% 装甲"]},
			6: {"text": "攻击 ×1.21 · 无视 25% 装甲",
				"apply": {"attack_pct": 0.21}, "pending": ["无视 25% 装甲"]},
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
			return String(g["label"])
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


## 一艘船在某组里归属哪一条（档案窗显示「这艘船属于哪个势力」用）
static func group_of_ship(ship: EveShip, group: StringName) -> String:
	if ship == null:
		return ""
	match group:
		&"faction": return ship.faction_name()
		&"weapon":  return String(ship.weapon_type)
		&"defense": return String(ship.defense_type)
	return ""


## 某艘船是否带某条羁绊 —— 羁绊加成的受益范围判定
static func ship_has(ship: EveShip, group: StringName, member: String) -> bool:
	if ship == null:
		return false
	return group_of_ship(ship, group) == member
