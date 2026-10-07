extends RefCounted
class_name EveEventTable

## EVE 自走棋 —— 事件（废弃中继站）四选一选项表
##
## ⚠️ 本文件是【唯一真源】，并且是**全局固定的一套**。
##    节点 4 / 10 / 14 三个事件节点**共用这同一个 OPTIONS 数组**。
##
##    为什么不做成「每个节点一套选项」（交接文档与路线文档都点名过）：
##    一旦把选项表挂到节点上，立刻就是「三处各写一份、改一处漏两处」的分叉 ——
##    而且玩家会看到三张完全不同的事件面板，却以为自己进入了三个不同系统。
##    共用一套 + 「已获取的不能再选」，三次事件自然形成「4 选 3」的取舍，
##    不需要第二张表就能做出递进感（`ALLOW_REPICK = false` 那条）。
##
## ── 效果字段词表（别自己造新键，落地函数只有两个）────────────
##   `apply`          战斗加成，直接喂给 `EveRunState._apply_synergy`
##                    可用键：armor_pct（同时放大装甲与结构）/ shield_pct /
##                    attack_pct / cycle_pct（攻击间隔 −N%）/ speed_pct /
##                    hull_flat / shield_flat
##   `pick_ship`      true = 要先选 1 艘船才生效（武器调校 / 结构加固）
##   `ship_apply`     选了船之后加在**那一艘**上的永久增益（键同 `_apply_synergy`）
##   `beacon_heal`    信标结构值 +N（夹在上限内）
##   `free_advanced_roll` true = 免费高级刷新，保底 1 艘 cost ≥ 3
##
## ⛔ **不要再加回「给星币」的选项**（2026-10-01 用户裁决）：
##    「主要是回合给的星币太多了，而且给星币不合适。」
##    交接文档 §7.2 的四条里一条都不给星币。
##  （`coin` / `coin_per_node` 两个键的**支持代码保留**，只是当前没人用。）
##   `xp`             立即获得经验
##   `beacon_heal`    立即回复信标
##   `beacon_max`     信标**上限** +N（同时会把当前值一起抬高，见 apply_event）
##   ⛔ `leak_reduce` 已随「漏网」机制一起删除（2026-10-01），不要再写这个字段
##
## ── 设计口径 ────────────────────────────────────────────────
##   四条选项刻意覆盖**四个不同角度**（舰队 / 火力 / 经济 / 信标），
##   而且**必须四条都有用** —— 四选三的取舍才有意义。若某条一眼就是废牌，
##   那它就不该在表里（玩家会永远跳过它，等于选项只有三条）。

## 已获取的选项能否再次选择。
## false = 云顶口径（同一枚强化不会刷第二次）；三次事件 ⇒ 玩家必然放弃一条。
## 想改成可叠加（拿两次军械实验室 = +32% 火力）只需把它翻成 true。
const ALLOW_REPICK := false

## 分类 → 显示色（与 EveWindow 的语义色对齐，不要另起一套）
const TAG_COLORS := {
	&"舰队": Color(0.85, 0.68, 0.28),     # 装甲金
	&"火力": Color(0.88, 0.52, 0.30),     # 警告橙
	&"经济": Color(0.91, 0.76, 0.35),     # 星币金
	&"信标": Color(0.35, 0.70, 0.90),     # 护盾蓝
}

## 四条选项。`id` 是主键（规则 1：关联靠 id 不靠名字）。
const OPTIONS: Array = [
	{
		"id": &"weapon_tune",
		"name": "武器调校",
		"tag": &"火力",
		"icon": &"railgun",
		"desc": "选 1 艘船\n永久 ATK +8%（向下取整，最低 +1）",
		"effect": "选 1 艘 · 永久 ATK +8%",
		"pick_ship": true,
		"ship_apply": {"attack_pct": 0.08},
	},
	{
		"id": &"armor_plate",
		"name": "结构加固",
		"tag": &"舰队",
		"icon": &"armor_plate",
		"desc": "选 1 艘船\n永久最大结构值 +15%（向下取整，最低 +1）",
		"effect": "选 1 艘 · 永久结构 +15%",
		"pick_ship": true,
		"ship_apply": {"armor_pct": 0.15},
	},
	{
		"id": &"beacon_repair",
		"name": "紧急维修",
		"tag": &"信标",
		"icon": &"beacon",
		"desc": "信标结构值 +10\n（不超过上限）",
		"effect": "信标 +10（上限 100）",
		"beacon_heal": 10,
	},
	{
		"id": &"black_market",
		"name": "黑市情报",
		"tag": &"经济",
		"icon": &"coin",
		"desc": "免费高级刷新\n5 个槽位至少 1 艘 cost ≥ 3",
		"effect": "免费高级刷新（保底 1 艘 cost ≥ 3）",
		"free_advanced_roll": true,
	},
]


## 全部选项（返回的是**表本身的引用**，调用方只读，别就地改）
static func all() -> Array:
	return OPTIONS


static func count() -> int:
	return OPTIONS.size()


## 按 id 取一条。找不到返回 {}（**不返回兜底项** —— 静默兜底会让错配的 id
## 看起来像"选了个别的"，而那正是最难查的一类 bug）。
static func by_id(id: StringName) -> Dictionary:
	for o in OPTIONS:
		if StringName(o["id"]) == id:
			return o
	return {}


static func has_id(id: StringName) -> bool:
	return not by_id(id).is_empty()


static func tag_color(tag: StringName) -> Color:
	return TAG_COLORS.get(tag, Color(0.55, 0.78, 0.82))


## 一条效果的中文摘要（日志 / 增益窗共用，避免两处各写一份文案）
static func effect_text(option: Dictionary) -> String:
	return String(option.get("effect", ""))
