extends Node
class_name EveRunState

## EVE 自走棋 —— 一局的状态机（阶段 A / Playable Loop v0）
##
## ══════════════════════════════════════════════════════════════════
##  这个类存在的唯一理由：把「一局游戏」这条循环从战斗场景里拆出来。
## ══════════════════════════════════════════════════════════════════
##
## 在此之前，`eve_battle_scene.gd` 的 `_start_battle()` 一个人干完了
## 「随机抽舰队 + 开打 + 打完 4 秒自动重开」，所以玩家赢了输了都只是
## 「重开一局随机舰队」，星币/等级/信标全是 demo 假数据（见路线文档 §0）。
##
## 现在四个阶段的职责是分开的：
##
##     PREP     准备：倒计时 + 商店 + 买船 + 升级      ← play 的唯一决策窗口
##     BATTLE   战斗：锁定操作，只有相机可动
##     RESOLVE  结算：漏船扣信标 / 发经验发钱 / 推进节点
##     ENDING   结局：通关（节点 15 打完）或撤离（信标归零）
##
## ⚠️ 本类【不碰任何 3D / UI】。它只有数字与信号。
##    战斗场景负责把数字变成船和窗口，HUD 负责把数字变成字。
##    所以 `tools/verify_run.tscn` 能在无头环境里把整局跑完并断言数值。
##
## ── 数值口径全部来自交接文档 §8，一律照抄，不在这里做平衡调整 ──────
##    §8.1 收入    基础 +5 / 利息 min(⌊gold/10⌋,5) / 刷新 2 / 买经验 4→4点
##                 每节点自动 +2 经验
##    §8.2 等级    MAX_LEVEL 6 / LEVEL_XP 累计阈值 / LEVEL_CAP 上场上限
##    §8.3 概率    8 档（1~6 是等级，7/8 是满级后的超频档）
##
## ── 唯一一处【工程侧反解】的数值：战败的信标代价（见 LOSS_BASE 注释）────
##
## 变更清单（阶段 A）：
##   - 四阶段状态机 + 信号（changed / phase_changed / offers_changed /
##     log_event / run_ended）
##   - 经济与等级：买船 / 刷新 / 加速等级 / 每节点自动经验 / 利息收入
##   - 商店 8 档概率表抽取（唯一抽取入口 _roll_one）
##   - 备战席 8 格 + 上场（**买入只进备战席**，上场唯一入口 = 玩家拖放，
##   - 信标 100 起步、战败扣血、通关/撤离判定
##   - 敌方数值叠加：base → star(×1.8^Δ) → power_scale（交接文档 §6.4）

signal changed()                                  ## 任何状态变化（HUD 重刷）
signal phase_changed(phase: int)
signal offers_changed()
signal log_event(text: String, category: StringName)
signal run_ended(cleared: bool)

enum Phase { PREP, BATTLE, RESOLVE, ENDING }
enum Ending { NONE, CLEARED, EVACUATED }

# ══════════════════════════════════════════════════════════════════
#  权威常数（交接文档 §8 · 与云顶之弈同口径 · 勿动）
# ══════════════════════════════════════════════════════════════════

const MAX_LEVEL := 6
## 下标 = 目标等级，值是【累计】经验阈值
const LEVEL_XP: Array[int] = [0, 0, 2, 4, 10, 20, 40]
## 上场上限 = 等级 + 2
const LEVEL_CAP: Array[int] = [0, 3, 4, 5, 6, 7, 8]
const BUY_XP_AMOUNT := 4
const BUY_XP_COST := 4
const NODE_XP_REWARD := 2
## 满级后每投 16 星币买经验 → 商店品质 +1 档（超频 1 / 超频 2）
const OVERTIER_COST := 16
const MAX_TIER := 8

## ── 战败追加伤害（连败递增，2026-10-01）────────────────────────
## 把「战胜不掉血」修掉之后，玩家只在**输**的时候掉血，而单场战败伤害
## 在后期也就 14~26 —— 连输三四场才掉得完 100 点信标，节奏偏松。
## 用户要求：「十多回合如果在后面几回合连续输，那真的会被打掉的。」
## ⇒ 连败每多一场 +2，封顶 +8。
## ⚠️ **第一场不加**（`lose_streak <= 1` 返回 0）—— 这样 BOSS 首败仍是
##    交接文档 §13 反解出来的那个锚点 −26，既有验收不被打破。
const LOSS_STREAK_STEP := 2
const LOSS_STREAK_BONUS_MAX := 8

const REFRESH_COST := 2
const START_GOLD := 5
const START_BEACON := 100
const SHOP_SLOTS := 5
const BENCH_SLOTS := 8
const BASE_INCOME := 5
const INTEREST_STEP := 10
const INTEREST_MAX := 5

## 商店概率 8 档（交接文档 §8.3 冻结表）。值 = [1费, 2费, 3费, 4费, 5费]
##
## ⚠️ `shop_tier()` 是唯一的档位算法，`_roll_one()` 是唯一的抽取入口 ——
##    别在别处再造一份映射，那正是「两处真相源会漂移」的老坑。
const SHOP_ODDS := {
	1: [100, 0, 0, 0, 0],
	2: [80, 20, 0, 0, 0],
	3: [60, 30, 10, 0, 0],
	4: [50, 30, 20, 0, 0],
	5: [40, 20, 25, 15, 0],
	6: [30, 25, 25, 15, 5],
	7: [22, 25, 26, 17, 10],
	8: [15, 22, 28, 20, 15],
}

## ══════════════════════════════════════════════════════════════
##  ★ 战败的信标代价（2026-10-01 简化：**删掉「漏网」机制**）
## ══════════════════════════════════════════════════════════════
##  用户原话：「漏网机制我理解不了，删除，我真没发现这玩意儿有啥用」
##
##  **现在的规则只有三句话：**
##      打赢  → 信标一滴不掉
##      打输  → 信标掉【本表按阶段给定的定值】
##      连败  → 每多一场 +2，封顶 +8（见 `LOSS_STREAK_*`）
##
##  ⛔ **不再有「漏了几艘船」这个概念** —— 原来那一项
##     `Σ 漏网舰船费用` 已整个删除，代价只跟「这是什么类型的节点」有关。
##
##  数值怎么来的（不是拍脑袋）：
##     旧公式 = 阶段基础(battle2/elite3/boss4) + Σ漏网舰船费用
##     实测 15 个节点的 Σ费用：battle 2~12（**中位 6**）· elite 7~11（中位 11）· boss 22
##     ⇒ 把中位并进基础值 ⇒ battle 2+6=**8** · elite 3+11=**14** · boss 4+22=**26**
##     ⇒ ★ BOSS **−26** 这个交接文档 §13 的锚点**保持不变**
##
##  ⚠️ 取舍（改定值必然带来）：编组规模不再影响代价 ——
##     前期小编组节点（原 4）变 8、后期小编组（原 14）也变 8。
##     这是「简单」的代价，用户要的就是简单。**要恢复规模感，
##     正解是调这张表或按节点索引分档 —— 不要把 Σ 加回来。**
const LOSS_BASE := {
	&"battle": 8,
	&"elite": 14,
	&"boss": 26,
	&"event": 0,
}

## 星级的数值倍率（交接文档 §6.4：star ×1.8^Δ）
const STAR_MULT := 1.8

# ── 打捞（阶段 C 第二件）────────────────────────────────────────────
#
# 设计规格（路线文档 §阶段C）：「战斗中击毁的敌船 → 残骸 → 玩家逐艘勾选
# → 延迟到账并占商店槽位」。四句话各自对应一个必须有的机制：
#
#   ① 击毁 → 残骸      = 残骸**只能从战斗里来**，不能凭空发。所以打捞是
#                        「打得好」的奖励，而不是一个独立商店。
#   ② 一个节点的生命周期 = 战斗结算时出现，玩家在这个节点的**结算页**上决定；
#                        再进下一节点还没选就整批漂走。
#                        这样它永远是一个**当下就要决定**的东西，不会攒着。
#   ③ 延迟到账 + 占槽位 = 下单当场付钱，但**不在本节点给你**；下个节点的
#                        商店里，它会**顶掉一个槽位**（且刷新不掉）。
#   ④ **敌我双方都进列表**（2026-10-01 定案）：原先只捞敌方，等于
#                        「打赢赔本货、输赢无所谓」。我方那几艘也进，
#                        但**定价不同**（见下）。
#
# 于是取舍是干净的：**用「少一个槽位」+ 一笔打捞费，换一艘你现在买不到的船**
# （敌方编组里有高费船，而你的商店档位受等级限制摇不出来）。
# 这条也解释了为什么不能「下单立刻给」——那样它只是打八折的购买，没有代价。
#
# ★★ 2026-10-04 用户定案：**两档定价**，制造「捞谁的取舍」：
#   我方残骸 × **0.5**（半价回收自己的船 —— 亏了要花钱补回来）
#   敌方残骸 × **1.0**（全价 —— 抢对面的要付溢价）
#   两档差价就是玩家每回合要做的博弈：钱只够捞一艘时，捞回自己死掉的
#   3 费划算，还是抢敌方那艘 4 费划算。
const SALVAGE_COST_RATIO := 0.5    ## ★ 我方残骸打捞费 = ⌈费用 × 0.5⌉，下限 1
const SALVAGE_COST_RATIO_ENEMY := 1.0  ## ★ 敌方残骸打捞费 = ⌈费用 × 1.0⌉，下限 1

## ★ 一次最多能勾几艘（2026-10-04 用户定案）。
## 为什么要有上限：下一节点的商店只有 `SHOP_SLOTS`(5) 个货位，
## 打捞品要**顶掉**货位 —— 勾 6 艘就必然有 1 艘无处可放。
## 勾到第 6 艘时**直接拒绝并提示**（不静默截断，否则玩家会以为自己勾上了）。
const SALVAGE_MAX_PICK := 5

## 星级上限。3 张 1★ → 2★，3 张 2★ → 3★（云顶同口径）—— 所以 9 张同名 1★ 才是满星。
const MAX_STAR := 3

## ── 残骸的星级：**只能用来自店面的证据，不能用当前场上读数** ────────
##
## ⚠️ 2026-10-01 修的一个真 bug（会「看着对、其实错」）：
##    原来 `_set_wreck_from()` 拿的是 `EveShip.star`，而**敌方舰队是把星级
##    烘进数值里的**（`apply_enemy_scaling()` 只放大 atk/shield/armor，
##    `ship.star` 从不被写）⇒ 这个字段**恒为 1**。
##    后果：节点 10 的 1★ 敌舰（power_scale ≈ 1.8）被打捞上来，
##    到玩家手里变成 1★ 的裸船，比玩家自己商店买的还弱 —— 打捞直接失去意义。
##
## ⚠️ 而且「从场上读数」这条路是走不通的：结算弹窗延迟 1 秒弹出，
##    `resolve_battle()` 那一刻舰队还活着、字段还准；但在那之后
##    主控会重建舰队，等到 HUD 真要画打捞框时，敌船对象已经**不在场上**了。
##    ⇒ 残骸必须在**结算那一刻**把证据抄下来，事后再读一定是陈的。
##
## 本函数 = 结算期「反解」与展示期「复算」**共用的唯一一份纯函数**。
## 返回 {star, atk_base, def_base}：
##   §1 shot / scale ≤ 1 → 由 `shot` 反解出星级（对**我方**舰船有真实含义）
##      门槛：`shot ≥ atk_base × 1.8^(k−1) × (1 − TOL)`
##      ⚠️ 基准就是 `atk_base` 本身，**不乘任何 0.5** ——
##         `warhead_scale(m)` 做的是 `weapon_damage *= m`、`attack *= m`，
##         1★ 的读数就等于权威表原值。凭空加一个 0.5 会把 1★ 读成 2★
##         （实测：裸 13 会被判成 2★ 并显示 23）。
##   §2 scale > 1        → **击杀的是被放大过的敌掠袭舰队**，不是原版敌舰。
##      此时星级反解无意义（逐节点星级的机制没实装，星永远出 1），
##      一律判 1★；补偿改走**费用**：残骸自带打折、且是玩家当前商店档位
##      摇不出来的高费船。⛔ 别在 §2 里"顺手按 scale 往上猜"——
##      猜出来的数字没有任何依据。
##   ★ 判据只用整数，不含浮点 epsilon ⇒ 与序列化/调用点无关（幂等）。
static func derive_wreck_tier(shot: float, scale: float,
		atk_base: float, def_base: float) -> Dictionary:
	const TOL := 0.12
	var star := 1
	if scale <= 1.0 + TOL:
		for k in range(MAX_STAR, 1, -1):
			if shot >= atk_base * pow(STAR_MULT, float(k - 1)) * (1.0 - TOL):
				star = k
				break
	return {"star": star, "atk_base": atk_base, "def_base": def_base}


## 把证据还原成「星级对应的裸数值」。
##
## ⚠️ 只在「未放大」（scale ≤ 1）时成立 —— 放大的那支算出的裸值只是参考，
##    HUD 一个数字都不许按它显示（见 `WreckDisplay`）。
static func tier_base_from(star: int, atk_base: float, def_base: float) -> Dictionary:
	var d := pow(STAR_MULT, float(maxi(1, star) - 1))
	return {"atk": atk_base * d, "def": def_base * d}

# ══════════════════════════════════════════════════════════════════
#  状态
# ══════════════════════════════════════════════════════════════════

var phase: int = Phase.PREP
## 上一场的胜负（`advance()` 判「第 15 节点要不要重打」用）
var last_won: bool = true
## BOSS 重打了多少次（只为日志与验收，不参与数值）
var boss_attempts: int = 0

var coin: int = START_GOLD
var level: int = 1
var xp: int = 0
var beacon: int = START_BEACON
var node_index: int = 1
var overtier: int = 0                      ## 满级后的超频档（0 = 未超频）
var win_streak: int = 0
var lose_streak: int = 0
var shop_locked: bool = false
var ending: int = Ending.NONE

## 备战席（≤ BENCH_SLOTS）。元素 = {"ship_key": StringName, "star": int}
var bench: Array[Dictionary] = []
## 上场（≤ field_limit()）。元素 = {"ship_key": StringName, "star": int, "cell": Vector2i}
##
## ⚠️ `cell` 是【棋盘格】（阶段 B 起）：(-1,-1) = 还没被玩家摆过，位置由 arena 的
##    默认阵型给。存格号而不是存世界坐标，是因为「棋盘是布阵台」——
##    接敌线（compute_deploy_z）每个节点都会变，存绝对坐标会让摆好的阵型
##    在下一节点悄悄漂走；存格号则永远钉在棋盘上。
##    真正的世界坐标在每个准备阶段由 EveBattleArena 现算（落格 → 世界坐标）。
## ⚠️ 进场的**唯一入口**是 `deploy_from_bench()`（玩家从备战席拖到棋盘）——
##    2026-09-20 起不再有任何「自动上场」。理由见 buy() 与本文件
##    「已删除：auto_deploy()」那一节。
var field: Array[Dictionary] = []
## 商店 5 个槽位。元素 = EveShipDatabase 的派生 Dictionary（已售出的槽位会被立刻重摇）
var offers: Array = []

## 已获取的事件增益（EveEventTable 的 id，按获取顺序）。
## ⚠️ 存 id 而不是存 Dictionary：效果一律**现查表**再落地，
##    这样改表里的数值只需改一处，存档里的旧 id 也不会带着过期的数值。
var event_picks: Array[StringName] = []

## ★★ 2026-10-04 打捞改为**多选列表**（用户定案）。
##
## 原来这里是**单个** `wreck: Dictionary`（且 `_set_wreck_from()` 只挑「费用最高」
## 的一艘，其余全丢）。现在：本回合敌我双方**所有**被击毁的舰船都进这个列表，
## 玩家在**结算页**逐艘勾选，最多 5 艘。
## 元素结构 = EveShipDatabase 派生 Dictionary + 以下附加键：
##   "team"     → 0=我方 / 1=敌方（**定价用**，决定 ×0.5 还是 ×1）
##   "wreck_id" → 本列表内的稳定下标（UI 勾选与下单都靠它，跨帧不变）
##   "from_node"→ 下单时才写，标记「这是修复品」
##
## ⚠️ 生命周期仍然是**恰好一个节点**：新一次结算时整体 `clear()` 重填。
var wrecks: Array[Dictionary] = []

## 残骸的世代号。每产生**一批**新残骸 +1，**过期/下单都不动它**。
##
## ⚠️ 为什么不把世代号塞进元素里就完事：
##    `wrecks[i] = best.duplicate()` 换的是 Dictionary **引用**，
##    UI 侧拿它比对时看不出差别 —— UI 需要一个
##    「单调递增、永不复用」的号才能可靠地判「这是不是新的一批」。
var wreck_evt: int = 0

## 残骸数值展示用的持久记录。**与 `wrecks` 一一对应的并行数组**。
##
## ⚠️ 为什么必须单独存：`wrecks[i]` 是 `EveShipDatabase` 的派生 Dictionary，
##    它里面**没有** star 键的语义（那是权威表原值列，不是星级）；
##    而结算那 1 秒延迟里舰队会被重建 ⇒ 事后再去数舰船对象一定数不到。
##    所以证据（三个整数 + 阵营）在结算那一刻抄下来，随残骸一起过期。
##    第 i 项的结构 = {"star":…, "atk_base":…, "def_base":…, "m":…, "team":…}
var wrecks_display: Array[Dictionary] = []

## 已下单、下个节点到账的修复队列。元素同 `wrecks` 的一项。
## 用 Array 而不是单个：一局里可能连续两个节点都打捞，前一件还没买走。
var repair_queue: Array[Dictionary] = []

## 被「修复品」占住的商店槽位号。刷新（含付费刷新）**不许**重摇这些槽位，
## 否则玩家花钱下的单会被一次刷新刷掉 —— 那就是「说了延迟到账却没到账」。
var salvage_slots: Array[int] = []

var rng := RandomNumberGenerator.new()

var _pools: Dictionary = {}                ## cost → Array[Dictionary]（52 艘派生一次就够）


# ══════════════════════════════════════════════════════════════════
#  开局
# ══════════════════════════════════════════════════════════════════

## 开一局新的。p_seed = 0 时用系统随机；>0 时固定种子（回归用）。
func start_run(p_seed: int = 0) -> void:
	if p_seed == 0:
		rng.randomize()
	else:
		rng.seed = p_seed

	coin = START_GOLD
	level = 1
	xp = 0
	beacon = START_BEACON
	node_index = 1
	overtier = 0
	win_streak = 0
	lose_streak = 0
	shop_locked = false
	ending = Ending.NONE
	bench.clear()
	field.clear()
	offers.clear()
	wrecks.clear()
	wrecks_display.clear()
	wreck_evt = 0
	repair_queue.clear()
	salvage_slots.clear()
	_build_pools()

	phase = Phase.PREP
	roll_shop()
	log_event.emit("一局开始：信标 %d · 星币 %d · 15 个节点" % [beacon, coin], &"system")
	log_event.emit("节点 1／%d · %s" % [EveNodeTable.TOTAL, entry_line()], &"hint")
	changed.emit()
	phase_changed.emit(phase)


func _build_pools() -> void:
	if not _pools.is_empty():
		return
	for c in range(1, 6):
		_pools[c] = EveShipDatabase.by_cost(c)


# ══════════════════════════════════════════════════════════════════
#  商店
# ══════════════════════════════════════════════════════════════════

## 当前商店档位（1~8）。等级 1~6；满级后每超频一次 +1 档，封顶 8。
func shop_tier() -> int:
	return clampi(level + overtier, 1, MAX_TIER)


## 重摇 5 个槽位 —— 但**跳过被修复品占住的槽位**（`salvage_slots`）。
##
## ⚠️ 这条是「延迟到账」能不能成立的关键。玩家已经为打捞付过钱了，
##    如果一次刷新就把它刷掉，玩家看到的是「花了钱、什么都没拿到」。
##    `refresh()`（付费刷新）走的就是这个函数，所以锁定必须做在这里，
##    光在 `advance()` 里塞进去是不够的。
func roll_shop() -> void:
	var locked: Dictionary = {}
	for i in salvage_slots:
		if i >= 0 and i < offers.size():
			locked[i] = offers[i]
	offers.clear()
	for i in SHOP_SLOTS:
		offers.append(locked[i] if locked.has(i) else _roll_one())
	offers_changed.emit()
	changed.emit()


## 单槽抽取 —— **全工程唯一的抽取入口**
##
## 两步：① 按当前档位的概率表摇出费用档；② 在该费用档里等概率取一艘船。
func _roll_one() -> Dictionary:
	_build_pools()
	var odds: Array = SHOP_ODDS[shop_tier()]
	var total := 0
	for v in odds:
		total += int(v)
	var r := rng.randi_range(1, total)
	var cost := 1
	var acc := 0
	for i in odds.size():
		acc += int(odds[i])
		if r <= acc:
			cost = i + 1
			break
	var pool: Array = _pools.get(cost, [])
	if pool.is_empty():
		pool = _pools.get(1, [])
	if pool.is_empty():
		return {}
	return pool[rng.randi_range(0, pool.size() - 1)]


## 买第 index 个槽位。返回 {"ok": bool, "reason": String, "data": Dictionary}
##
## ══════════════════════════════════════════════════════════════════
##  ⚠️ 买入【只进备战席】，**绝不自动上场**（2026-09-20 用户定稿）
## ══════════════════════════════════════════════════════════════════
##  用户原话：「我是要先购买，购买后舰船就出现在备战席，不然备战席拿来干嘛？
##             然后备战席再拖到棋盘上，这样棋盘的显示与关闭才有操作上的意义。」
##
##  这是云顶之弈的口径。旧实现买完会顺手 `auto_deploy()`，理由是
##  「买了东西不出现在战场上会让人以为系统是假的」—— 那条理由是错的：
##  它顺手把两个系统都变成了死的：
##    ① **备战席**：永远 0~1 艘、永远不用看，8 个格子形同装饰；
##    ② **棋盘**：既然买完自己就上场，玩家一辈子不需要手动落格，
##       于是「拖动时才显形」这条视觉规则永远触发不了。
##  失去这两条之后，玩家看到的就是「花了钱 → 船自己会打」，
##  和阶段 A 那套假系统没有区别。棋盘与备战席是这个游戏【仅有的两个操作面】，
##  不能由引擎替玩家按掉。
func buy(index: int) -> Dictionary:
	if phase != Phase.PREP:
		return _deny("只有准备阶段能买船")
	if index < 0 or index >= offers.size():
		return _deny("槽位不存在")
	var raw = offers[index]
	if raw == null or not (raw is Dictionary) or (raw as Dictionary).is_empty():
		return _deny("槽位已空")
	var d: Dictionary = raw
	# ★★ 2026-10-06 用户口径：**打捞品取货不再收费**（治「双重扣费」）。
	#
	#   用户原话：「我第1回合打捞了伐木者级，花费了1星币，然后被扣费了，
	#   到第2回合，伐木者级到了商店，我点击之后，又扣了我1星币，
	#   这就导致双重扣费，这不对，所以改成第1回合的结算的时候扣费吧，
	#   到后面商店选择的时候不要扣费」
	#
	#   ⇒ 打捞费已在**结算页**付清（见 `salvage_order()` 的 `coin -= c`）；
	#     打捞品在商店里占一个货位、等玩家取走 —— 那一步是**取货，不是购买**。
	#     再收一次 `cost` 就是同一艘船收两遍钱。
	#
	#   ⚠️ 判据用 `from_node`：它是打捞品的**既有标记**（卡面的「修复」前缀
	#     也靠它判），语义一致 ——「是打捞来的」⇒「钱已经付过了」。
	#   ⚠️ 这也顺带治好了 2026-10-05 那个「打捞品买了没进备战席」：
	#     打捞已经花掉星币，到第 2 回合常常**买不起**第二次 ⇒ `buy()` 被拒
	#     （只有战斗日志一行提示）⇒ 玩家以为点了没反应。免费之后不会再被拒。
	var is_salvage := d.has("from_node")
	var cost := 0 if is_salvage else int(d.get("cost", 1))
	if coin < cost:
		return _deny("星币不足（需 %d，现有 %d）" % [cost, coin])
	if bench.size() >= BENCH_SLOTS:
		return _deny("备战席已满（%d / %d）—— 先拖一艘上场或卖掉" % [bench.size(), BENCH_SLOTS])

	coin -= cost
	# 星级取报价自带的（普通货架没有 star 键 → 默认 ★1；
	# 打捞来的修复品可能是敌方编组的星级，这里一并继承）。
	var entry := _make_entry(StringName(d.get("ship_key", &"")), int(d.get("star", 1)))
	bench.append(entry)
	# ★ 2026-10-01 用户定稿：买走的那格**留空**，不立刻补新船。
	#
	#   用户原话：「我买一艘那个地方就给我空着，别马上补充上来一艘，
	#             这样凑二星三星就太容易了。除非点击刷新商店，不然不补」
	#
	#   这正是云顶的口径：槽位空着，直到玩家**花钱刷新**或**进入下一回合**
	#   （`advance()` 里会 `roll_shop()` 整体重摇 —— 那是回合刷新，不是补货）。
	#   ⛔ 别把 `_roll_one()` 加回这里：一买就补等于"想买几艘有几艘"，
	#      凑二星三星的成本直接归零。
	offers[index] = {}
	# ⚠️ 若买走的正是「修复品」占的那个槽位，必须**解锁**它。
	#    不解锁的话，之后每次刷新都会把这个槽位当成锁定槽位保留下来 ——
	#    等于玩家买完之后，那个格子再也刷不动了（而且完全不报错）。
	salvage_slots.erase(index)
	# 日志必须写明「去备战席」，否则玩家会以为买失败了（东西不在战场上）。
	# ⚠️ 打捞品走另一句：它是**取货**（钱早在结算页付过），
	#    写成「−0 ◆」会让玩家以为自己捡了便宜，写「−N ◆」则是重复扣费。
	if is_salvage:
		log_event.emit("%s → 备战席（打捞费已在结算页付清，取货免费）"
				% String(d.get("name", "?")), &"buy")
	else:
		log_event.emit("%s −%d ◆ → 备战席（拖到棋盘上场）"
				% [String(d.get("name", "?")), cost], &"buy")

	# 三连合成照旧在买入那一刻结算（云顶同款）：同 id 同星满 3 张立刻升星。
	# 合成品留在它原来的位置 —— 备战席凑的留备战席、场上凑的留场上
	# （见 _merge_once 的「位置继承」）。
	var merged := _try_merge()
	if not merged and bench.size() >= BENCH_SLOTS:
		log_event.emit("备战席已满 %d／%d —— 拖一艘上场，或者拖到商店右下角出售"
				% [bench.size(), BENCH_SLOTS], &"hint")

	offers_changed.emit()
	changed.emit()
	return {"ok": true, "reason": "", "data": d}


## 造一条新的编制记录。cell = (-1,-1) 表示「位置交给默认阵型」
static func _make_entry(key: StringName, star: int) -> Dictionary:
	return {"ship_key": key, "star": star, "cell": Vector2i(-1, -1)}


## 付费刷新（2 星币）
func refresh() -> Dictionary:
	if phase != Phase.PREP:
		return _deny("只有准备阶段能刷新")
	if coin < REFRESH_COST:
		return _deny("星币不足（刷新需 %d）" % REFRESH_COST)
	coin -= REFRESH_COST
	roll_shop()
	log_event.emit("刷新加速列表 −%d ◆" % REFRESH_COST, &"buy")
	return {"ok": true, "reason": "", "data": {}}


## B03 加速等级：4 星币 = 4 点经验；满级后 16 星币 = 超频 +1 档
func levelup() -> Dictionary:
	if phase != Phase.PREP:
		return _deny("只有准备阶段能加速等级")
	if level < MAX_LEVEL:
		if coin < BUY_XP_COST:
			return _deny("星币不足（加速等级需 %d）" % BUY_XP_COST)
		coin -= BUY_XP_COST
		log_event.emit("加速等级 −%d ◆ · 经验 +%d" % [BUY_XP_COST, BUY_XP_AMOUNT], &"buy")
		add_xp(BUY_XP_AMOUNT)
	else:
		if overtier >= MAX_TIER - MAX_LEVEL:
			return _deny("加速列表已到最高档（超频 %d）" % (MAX_TIER - MAX_LEVEL))
		if coin < OVERTIER_COST:
			return _deny("星币不足（超频需 %d）" % OVERTIER_COST)
		coin -= OVERTIER_COST
		overtier += 1
		log_event.emit("加速列表 超频档 %d／%d（商店品质 +1）"
				% [overtier, MAX_TIER - MAX_LEVEL], &"buy")
		roll_shop()
	changed.emit()
	return {"ok": true, "reason": "", "data": {}}


func set_shop_locked(on: bool) -> void:
	shop_locked = on
	log_event.emit("加速列表已锁定（本节点结束后不重摇）" if on
			else "加速列表已解锁", &"system")
	changed.emit()


# ══════════════════════════════════════════════════════════════════
#  打捞（阶段 C 第二件）
# ══════════════════════════════════════════════════════════════════
#
#  残骸从哪来：**战斗击毁的船，敌我双方都算**（`resolve_battle` 的 destroyed 参数）。
#    ⚠️ 2026-10-01 之前**只有敌方**，玩家原话：
#    「打捞要么只打捞我方的，要么打捞敌我双方的，断然没有只打捞敌方的道理」。
#  残骸怎么走：战斗结算时出现 → 准备阶段可下单 → 下个节点顶掉 1 个货位 → 买走。
#  为什么这样设计、为什么不能「下单立刻给」，见 SALVAGE_COST_RATIO 上方那段。

## ★★ 某一艘残骸的打捞费（2026-10-04 多选后**按艘**算）。
##
## 定价**看阵营**（用户定案的两档博弈）：
##   我方（team 0）→ ×0.5   敌方（team 1）→ ×1.0
##
## ⚠️ 参数是**下标**不是 Dictionary —— 定价必须从 `wrecks[i]["team"]` 取，
##    不能让调用方自己传 team（两处判阵营必然分叉）。
## ⛔ 越界/空列表一律返回 0（**不抛错**：UI 可能在列表变空的同帧还在问价）。
func salvage_cost_of(idx: int) -> int:
	if idx < 0 or idx >= wrecks.size():
		return 0
	var w: Dictionary = wrecks[idx]
	var c := int(w.get("cost", 1))
	var ratio := SALVAGE_COST_RATIO if int(w.get("team", 0)) == 0 \
			else SALVAGE_COST_RATIO_ENEMY
	return maxi(1, int(ceil(float(c) * ratio)))


## ★ 勾选若干艘的**合计**打捞费（供 UI 实时显示「已选 N 艘 · 需 M ◆」）。
## ⚠️ 这是「全部勾中的总价」，**不是**「实际会付的价」——
##    买得起几艘要另问 `salvage_affordable()`（部分成交，见 `salvage_order()`）。
func salvage_cost_of_picks(idxs: Array) -> int:
	var sum := 0
	for i in idxs:
		sum += salvage_cost_of(int(i))
	return sum


## 照当前星币，**这批勾选里买得起几艘**（按勾选顺序贪心）。
## 贪心而不是「按费用排序」：玩家是自己勾的，那个顺序本身就是意图。
func salvage_affordable(idxs: Array) -> int:
	var left := coin
	var n := 0
	for i in idxs:
		var c := salvage_cost_of(int(i))
		if c <= left:
			left -= c
			n += 1
	return n


## 现在能不能打捞（**整批**的准入，不是某一艘）。返回 {"ok": bool, "reason": String}
##
## ⚠️ 阶段口径 2026-10-04 放宽：打捞在**结算页（RESOLVE）**上做，
##    不再是「准备阶段」。理由 = 时序直觉（用户原话）：
##    「第一回合打捞要到第三回合才到位，这不符合直觉，要到第二回合」。
##    在结算页下单 ⇒ 点「继续」进下一节点就顶掉货位，**正好第二回合到手**。
##    准备阶段（PREP）现在**不再**允许打捞 —— 那是「上一回合的旧账」，
##    留着只会让玩家能反悔白嫖已付的钱。
func can_salvage() -> Dictionary:
	if phase != Phase.RESOLVE:
		return {"ok": false, "reason": "只能在战斗结算页打捞"}
	if wrecks.is_empty():
		return {"ok": false, "reason": "没有可打捞的残骸"}
	return {"ok": true, "reason": ""}


## ★★ 下单打捞（多选版）：**当场扣钱**，但东西下个节点才到账（延迟到账）。
##
## `idxs` = 玩家在列表里勾选的下标数组（可空 ⇒ 什么都不打捞）。
##
## ## 四条口径（改之前先读 SALVAGE_COST_RATIO 上方那段）
## ##   ① **部分成交**（用户定案「买得起就买，买不起弹提示」）：
## ##      按勾选顺序逐艘扣钱，**买得起就买、买不起就跳过**，
## ##      最后返回「实际买到哪几艘 + 哪几艘因没钱被跳过」，由 UI 弹提示。
## ##      ⛔ 不是「钱不够就整单拒绝」—— 那样玩家得多试几次，很烦。
## ##   ② **上限 `SALVAGE_MAX_PICK`(5)**：下一节点商店只有 5 个货位，
## ##      超出的那几艘**买不了**（跳过 + 提示），不是静默截断。
## ##   ③ 剩下的**没买的仍留在列表里** —— 玩家还可以再勾一次别的，
## ##      但**本节点不能再拖到下一节点**（生命周期仍是一个节点）。
## ##   ④ 货位的竞争是**玩家的责任**：钱只够买 2 艘却勾了 4 艘时，
## ##      买得起的 2 艘进队列，剩下的跳过 —— 不做二次分摊。
##
## ⚠️ 故意**不检查备战席是否满**：到账是「占商店货位」而不是「进备战席」，
##    玩家可以到账后先把备战席腾出来再买。在这里挡一刀只会变成莫名其妙的拒绝。
##
## 返回 = {"ok", "reason", "bought": Array[int], "skipped": Array[int],
##          "paid": int, "names": Array[String], "data": Array[Dictionary]}
func salvage_order(idxs: Array = []) -> Dictionary:
	var v := can_salvage()
	if not bool(v.get("ok", false)):
		return _deny(String(v.get("reason", "打捞失败")))
	if wrecks.is_empty():
		return _deny("没有可打捞的残骸")

	# ── ① 先把勾选去重、剔除越界下标（UI 可能传来重复项）──
	#
	# ⚠️⚠️ 2026-10-05：越界**不能静默丢弃**！
	#    场景：玩家打捞掉一艘后 UI 没来得及重画，他点的是**旧列表**里的行 ⇒
	#    传来的下标已经越界 ⇒ 全部被剔掉 ⇒ `picked` 为空 ⇒
	#    返回一句「没有勾选任何残骸」—— 玩家明明点了，却被告知「没勾选」，
	#    他会当成「点了没反应」，而且这句提示**指错了方向**。
	#    ⇒ 明确报「列表已变化，请重新选择」，让玩家知道该刷新。
	var picked: Array[int] = []
	var dropped := 0
	for x in idxs:
		var i := int(x)
		if i >= 0 and i < wrecks.size() and not picked.has(i):
			picked.append(i)
		else:
			dropped += 1
	if picked.is_empty() and dropped > 0:
		return _deny("残骸列表已变化 —— 请按最新的列表重新选择")

	# ── ② 交易：按勾选顺序「买得起就买」──
	var bought: Array[int] = []
	var skipped: Array[int] = []
	var names: Array[String] = []
	var paid := 0
	# ⚠️⚠️ 勾选总价必须在**删列表之前**算出来（见下方 ③ 的注释）。
	#    实测踩过：钱为 0 时 3 艘全被 skip 并从 wrecks 删掉，
	#    事后再算「本批需多少」得到 0 —— 提示文案变成「需 0 ◆」，
	#    玩家完全看不懂哪里错了。
	var picked_total := salvage_cost_of_picks(picked)
	for i in picked:
		if bought.size() >= SALVAGE_MAX_PICK:
			skipped.append(i)          # 货位满了 ⇒ 超出部分买不了
			continue
		var c := salvage_cost_of(i)
		if c > coin:
			skipped.append(i)          # 钱不够 ⇒ 跳过（已勾的更便宜的那些还能买）
			continue
		coin -= c
		paid += c
		bought.append(i)
		names.append(String(wrecks[i].get("name", "?")))

	# ── ③ 进队列 ──
	var out: Array[Dictionary] = []
	for i in bought:
		var item: Dictionary = (wrecks[i] as Dictionary).duplicate()
		item["from_node"] = node_index
		# 世代号随修复品一起走 —— 到账时主控要靠它区分「新到货」与「上一件旧货」。
		item["evt"] = wreck_evt
		out.append(item)
	# ⚠️⚠️ 只删**买成的**（`bought`），**买不起的必须留在列表里**（用户定案：
	#    「买得起就买，买不起弹提示」）—— 留着玩家才能换组合再试，
	#    一删掉就等于「钱不够 ⇒ 这批货永远没了」，那不是提示，是判决。
	#    ⛔ 删下标一律**倒序**：正序删会让后面的下标前移，指错船
	#      （与 2026-09-17「打捞上错船」同类）。
	for i in range(wrecks.size() - 1, -1, -1):
		if bought.has(i):
			wrecks.remove_at(i)
			if i < wrecks_display.size():
				wrecks_display.remove_at(i)

	if bought.is_empty():
		return {
			"ok": false, "reason": _short_of_msg(picked, skipped, picked_total),
			"bought": bought, "skipped": skipped, "paid": 0,
			"names": [] as Array[String], "data": [] as Array[Dictionary],
		}
	# ⚠️⚠️ 必须真的**进队列**（2026-10-04 自查抓到）：重构时把「构造 out」与
	#    「入队」拆成了两段，忘了写 `repair_queue.append_array(out)` ——
	#    症状是**钱扣了、货没了**（最坏的一类：玩家白花钱）。
	#    ⇒ 凡是「钱已扣」的功能，必须有一条断言证明「东西真的到了」。
	repair_queue.append_array(out)
	log_event.emit("打捞下单：%s −%d ◆ · 下节点到账（顶掉 %d 个货位）"
			% [", ".join(names), paid, bought.size()], &"salvage")
	changed.emit()
	return {
		"ok": true, "reason": "", "bought": bought, "skipped": skipped,
		"paid": paid, "names": names, "data": out,
	}


## 「一艘都没买成」的提示文案。
##
## ⚠️ 这里区分两种「买不起」，因为玩家该知道**下一步该做什么**：
##   · 货位满了但还有钱 → 提示是货位不够（这跟钱无关，攒钱也没用）
##   · 纯粹星币不够     → 报出还差多少
##
## ⚠️ `need` 必须由调用方**在删列表之前**算好传进来：那时列表里的船已经被
##    移走了，现算会得到 0（实测踩过：「本批需 0 ◆，现有 0 ◆」）。
func _short_of_msg(picked: Array[int], skipped: Array[int], need: int) -> String:
	if picked.is_empty():
		return "没有勾选任何残骸"
	if picked.size() > SALVAGE_MAX_PICK:
		return "最多只能打捞 %d 艘（商店货位数）" % SALVAGE_MAX_PICK
	return "星币不足：本批需 %d ◆，现有 %d ◆" % [need, coin]


## 给 HUD 的展示数据（★ 结算页打捞浮层的**唯一输入源**）。
##
## ## 三条口径
## ##   ① **列表形态**（2026-10-04 多选）：`state=="list"` 时带 `items` 数组，
## ##      每项自带上桌要显示的全部字段（舰名/星级/阵营/单价/数值）。
## ##      UI **不许**自己再算一遍价钱或星级 —— 那是本函数存在的唯一理由。
## ##   ② 保留 `state=="repairing"`：已下单未到账的修复品，商店面板要显示。
## ##   ③ 空 = `{}`（无残骸且无在途）。
##
## ## ⚠️ `base_exact` 是**判据**不是装饰（见 derive_wreck_tier() §2）。
##    为 false 时（残骸来自被放大过的敌掠袭舰队），数值**不许**
##    反向折算「原版裸值」—— 那会明显偏离船表，玩家一眼看出不对。
##    此时 UI 应显示「敌掠袭 · 强化版」而不是假装它是原版船。
func salvage_info() -> Dictionary:
	if not wrecks.is_empty():
		var items: Array[Dictionary] = []
		for i in wrecks.size():
			var w: Dictionary = wrecks[i]
			var dv: Dictionary = wrecks_display[i] if i < wrecks_display.size() else {}
			var star := int(dv.get("star", int(w.get("star", 1))))
			var atk_base := float(dv.get("atk_base", w.get("attack", 0.0)))
			var def_base := float(dv.get("def_base", w.get("armor_struct", 0.0)))
			var m := float(dv.get("m", 1.0))
			var tb := tier_base_from(star, atk_base, def_base)
			items.append({
				"idx": i,
				"name": String(w.get("name", "?")),
				"star": star,
				"cost": int(w.get("cost", 1)),
				"team": int(w.get("team", 0)),
				"price": salvage_cost_of(i),
				"atk": int(roundf(float(tb["atk"]))),
				"def": int(roundf(float(tb["def"]))),
				"scan_res": int(w.get("scan_res", 0)),
				"cap": int(roundf(float(w.get("cap_max", 0.0)))),
				"base_exact": m <= 1.0 + 0.12,
				# ★ 打捞区每行前缀「节点 N ·」（参考图 1 的排版）
				"node": node_index,
			})
		return {
			"state": "list",
			"items": items,
			"total": wrecks.size(),
			"max_pick": SALVAGE_MAX_PICK,
			"coin": coin,
			"evt": wreck_evt,
			# ★ 已下单未到账的（在途）—— 结算页打捞区的「修复队列（下回合到账）」行读它。
			#    ⚠️ 之前没这个键 ⇒ UI 那一行永远空白（实测漏过）。
			"queue": repair_queue.duplicate(true),
			# 向后兼容的顶层字段（旧商店框读它；多选下它等于「列表第一艘」）
			"name": String((wrecks[0] as Dictionary).get("name", "?")),
			"cost": int((wrecks[0] as Dictionary).get("cost", 1)),
		}
	if not repair_queue.is_empty():
		var it: Dictionary = repair_queue[0]
		return {
			"state": "repairing",
			"name": String(it.get("name", "?")),
			"star": int(it.get("star", 1)),
			"cost": int(it.get("cost", 1)),
			"price": 0,
			"total": repair_queue.size(),
			"evt": int(it.get("evt", 0)),
		}
	return {}


## 把任意形态的「船」统一成派生 Dictionary（EveShip / Dictionary / ship_key）。
##
## ⚠️ **全工程只有这一处做「怎么算一艘船」的判定**。`_cost_of` 也走它 ——
##    这个判据原本在 `_cost_of` 里写了一份，加打捞时又写了一份，
##    两处一旦分叉就会出现「信标记了账、残骸却认不出来」这种半边生效的怪事。
##    返回 {} = 认不出来。
static func _as_ship_dict(e) -> Dictionary:
	if e == null:
		return {}
	if e is EveShip:
		var s: EveShip = e
		var d := EveShipDatabase.by_id(String(s.ship_key))
		if d.is_empty():
			return {}
		var out := d.duplicate()
		out["star"] = s.star
		return out
	if e is Dictionary:
		var dd: Dictionary = e
		if dd.is_empty():
			return {}
		# 只给了 key 的裸字典 → 现查表补全
		if dd.has("ship_key") and not dd.has("name"):
			return EveShipDatabase.by_id(String(dd["ship_key"]))
		return dd
	if e is String or e is StringName:
		return EveShipDatabase.by_id(String(e))
	return {}


## ★★ 从「本节点被击毁的船」里做出一**批**残骸。**敌我双方都在内，一艘不漏**。
##
## ## 2026-10-04 用户定案，与旧版的四处差异
## ##   ① **不再只挑「费用最高的一艘」** —— 原来那个筛选逻辑整条删掉了。
## ##      玩家原话：「本回合所有被击毁的船都进打捞列表」。
## ##   ② 旧的、还没下单的残骸在这里**整批作废** —— 生命周期恰好一个节点。
## ##   ③ 每条都带 `"team"`（0 我方 / 1 敌方）—— **定价要靠它**分两档。
## ##   ④ 产出**按费用降序**排（贵的在前）：UI 列表从上到下就是「先看贵的」，
## ##      而 `sources` 的下标对应关系在排序后**必须重算**（见下）。
##
## ⚠️ 2026-10-01 起 `sources` 是并行数组，抄下「结算那一刻」的**原始属性证据**
##    （星级 / 裸攻击 / 裸防御）。原因见 `derive_wreck_tier()` 上方那段 ——
##    结算弹窗延迟 1 秒 + 舰队重建，事后再去读 `EveShip` 上的字段一定是陈的。
##    ⇒ **排序时必须把 sources 跟着一起搬**，否则星级会张冠李戴
##      （这类「两个并行数组排序后错位」的 bug 最隐蔽：数量对得上、值全错）。
##
## 签名兼容：`destroyed` 不传 / 元素是派生 Dictionary 时，
## 星级一律取 1（无证据 ⇒ 不假装知道），不会崩。
func _set_wreck_from(destroyed: Array, sources: Array = [],
		power_scale: float = 1.0) -> void:
	wrecks.clear()
	wrecks_display.clear()
	wreck_evt += 1
	if destroyed.is_empty():
		return

	# ── ① 先把 (残骸, 证据, 阵营) 打包成同下标的三元组 ──
	#    ⚠️ 阵营从 `EveShip.team` 取；派不上（传字典进来）时默认 0（按我方半价算，
	#    比让玩家多付钱安全）。
	var rows: Array[Dictionary] = []
	for i in destroyed.size():
		var e = destroyed[i]
		var d := _as_ship_dict(e)
		if d.is_empty():
			continue
		var src: Dictionary = {}
		if i < sources.size() and sources[i] is Dictionary:
			src = sources[i]
		var team := 0
		if e is EveShip:
			team = int((e as EveShip).team)
		elif src.has("team"):
			team = int(src.get("team", 0))
		rows.append({"ship": d, "src": src, "team": team})

	# ── ② 按费用降序排（贵的前面），并排进两个输出数组 ──
	#    ⚠️ 排序键必须**显式**给 compare 函数：Array.sort_unstable() 直接调用时
	#       传的是**元素本身**（Dictionary），不是下标。
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int((a["ship"] as Dictionary).get("cost", 1)) \
				> int((b["ship"] as Dictionary).get("cost", 1)))

	var m := maxf(0.01, power_scale)
	for r in rows:
		var d: Dictionary = (r["ship"] as Dictionary).duplicate()
		var src: Dictionary = r["src"]
		# ── 证据：优先权威表裸值（sources 为空时现查一次表，口径同一份）──
		var dbase := EveShipDatabase.by_id(String(d.get("ship_key", "")))
		var atk_base := float(src.get("atk_base", dbase.get("attack", 1.0)))
		var def_base := float(src.get("def_base", dbase.get("armor_struct", 1.0)))
		var shot := float(src.get("shot", atk_base * m))
		var tier := derive_wreck_tier(shot, m, atk_base, def_base)
		var star := int(tier["star"])
		d["star"] = star
		d["team"] = int(r["team"])
		wrecks.append(d)
		wrecks_display.append({
			"star": star, "atk_base": atk_base, "def_base": def_base,
			"m": m, "team": int(r["team"]), "evt": wreck_evt,
		})

	# ── ③ 一行汇总日志（逐艘打日志会把战斗日志刷爆）──
	var own_n := 0
	for w in wrecks:
		if int(w.get("team", 0)) == 0:
			own_n += 1
	log_event.emit("残骸 %d 艘（我方 %d · 敌方 %d）—— 可在结算页挑选打捞"
			% [wrecks.size(), own_n, wrecks.size() - own_n], &"salvage")


## ⚠️ **延迟到账的落地点**，由 `advance()` 调用。
## 槽位从 0 开始占，并记进 `salvage_slots` —— 本节点内所有刷新都绕开它们。
func _deliver_repairs() -> void:
	if repair_queue.is_empty():
		return
	salvage_slots.clear()
	for i in repair_queue.size():
		if i >= SHOP_SLOTS:
			break
		offers[i] = repair_queue[i]
		salvage_slots.append(i)
	for it in repair_queue:
		log_event.emit("修复完成：%s ★%d 已占货位（本节点刷新刷不掉）"
				% [String(it.get("name", "?")), int(it.get("star", 1))], &"salvage")
	repair_queue.clear()
	offers_changed.emit()


## 没买走的修复品在**离开节点时作废** —— 「只占 1 个节点」这个成本才成立。
##
## ⚠️ 这里自己把槽位重摇掉，不依赖后面的 `roll_shop()`：
##    `shop_locked = true` 时 `advance()` 会**跳过** roll_shop，
##    那时陈旧的修复品会一直挂在货架上（而且不报错）。
##
## ⚠️ 2026-10-01：**同时清掉卡面可能读到的陈旧数值**。
##    `offers[i]` 被重摇成普通报价之后，它身上若还挂着 `from_node` 系列键
##    （star / evt），商店画卡时会读到上一件修复品的星级 —— 那就是
##    「打捞框里的数字有残留」的同一个病根，只不过换了个地方暴露。
func _expire_repairs() -> void:
	if salvage_slots.is_empty():
		return
	for i in salvage_slots:
		if i < 0 or i >= offers.size():
			continue
		var o = offers[i]
		# 只清「还是修复品」的槽位；玩家买走后那里已经是新摇的报价了
		if o is Dictionary and (o as Dictionary).has("from_node"):
			offers[i] = _roll_one()
	salvage_slots.clear()


# ══════════════════════════════════════════════════════════════════
#  等级与经验
# ══════════════════════════════════════════════════════════════════

## 上场上限 = 等级 + 2
func field_limit() -> int:
	return LEVEL_CAP[clampi(level, 1, MAX_LEVEL)]


## 本级内已获得的经验
func xp_in_level() -> int:
	if level >= MAX_LEVEL:
		return 0
	return xp - LEVEL_XP[level]


## 升到下一级还需要多少经验（满级后返回 0）
func xp_need() -> int:
	if level >= MAX_LEVEL:
		return 0
	return LEVEL_XP[level + 1] - LEVEL_XP[level]


## 加经验并处理升级。
##
## ⚠️ 这条是**两条腿**里的第 ① 条（交接文档 §5.3：「补漏不是新增设计」）：
##    云顶的经验 = ① 每回合自动 +2 ＋ ② 4 金币买 4 点，我们原来只搬了 ②。
##    漏了 ① 的后果是不主动点「加速等级」的玩家整关卡在 Lv1
##    （人口 3、商店 100% 只出 1 费船），而 BOSS 是 6 艘。
func add_xp(amount: int) -> void:
	if amount <= 0:
		return
	if level >= MAX_LEVEL:
		# 满级后经验没有去处（超频走硬币，不走经验），不再累积，
		# 免得顶栏挂一个永远不动的「40 / 40」。
		return
	xp += amount
	while level < MAX_LEVEL and xp >= LEVEL_XP[level + 1]:
		level += 1
		# ⚠️ 升级【不】把人推上场（2026-09-20）：上限抬高只是「多了位置」，
		#    上谁、上几艘是玩家的决定。见「已删除：auto_deploy()」。
		log_event.emit("等级提升 → Lv.%d（上场上限 %d —— 备战席的船可以再拖上去一艘）"
				% [level, field_limit()], &"economy")
	changed.emit()


# ══════════════════════════════════════════════════════════════════
#  备战席 / 上场
# ══════════════════════════════════════════════════════════════════

## ── 已删除：auto_deploy()（2026-09-20）────────────────────────────
##
## 原实现：把备战席的船按购入顺序自动补进场上空位，买船 / 升级 / 卖掉场上的船
## 都会顺手调它一次。**整条机制已移除，不要再恢复。**
##
## ── 为什么删（用户 2026-09-20 定稿，对齐云顶之弈）──────────────────
##  原文：「我是要先购买，购买后舰船就出现在备战席，不然备战席拿来干嘛？
##         然后备战席再拖到棋盘上，这样棋盘的显示与关闭才有操作上的意义。」
##
##  「自动上场」这条捷径的代价是同时废掉两个系统：
##    ① **备战席**退化成「0~1 艘的过道」，8 个格子和那条轨道永远不需要看；
##    ② **棋盘**永远不必显形 —— 玩家从不手动落格，
##       于是「格子只在拖动时显形」这条视觉规则一次也触发不了。
##  剩下玩家能看到的就只有「花钱 → 船自己会打」，与阶段 A 的假系统无异。
##
##  现在：进场只有 `deploy_from_bench()`，退场只有 `recall_to_bench()` /
##  `sell_from_field()`。三处触发点（buy / add_xp / _do_sell）里那句
##  `auto_deploy()` 也一并删掉 —— 否则「卖掉场上的一艘，备战席自动顶上来」
##  同样会替玩家做决定。
##
## ⚠️ 由此带来的一条**玩法后果**（如实记录）：开局场上是一艘都没有的。
##    玩家必须自己从备战席拖到棋盘，否则开战直接判负（见 _forfeit_no_deploy）。
##    这是云顶之弈本来就要玩家学的那一课，不是缺陷。


# ══════════════════════════════════════════════════════════════════
#  三连合成（阶段 B1）
# ══════════════════════════════════════════════════════════════════

## 三连合成：同 id 同星 ×3 → 升一星。
##
## ── 三条口径 ────────────────────────────────────────────────────
##  ① **同 id 同星**才算一组 —— 2★ 和 1★ 不混着凑（云顶同口径）。
##  ② **合成品继承场上的位置**：三张里只要有一张在场上，升星后的船就留在
##     那个格子里（`cell` 一起继承）。否则合成品留在备战席。
##     这条决定了「把两张放场上、第三张买进来」是一个有效打法 ——
##     如果合成品总是落回备战席，玩家每次升星都要重新摆位。
##  ③ **可连锁**：3×1★ → 2★ 之后，如果场上已有两张 2★，会立刻再合成 3★。
##     所以用 while 循环而不是 if。
##
## 返回 true 表示这一轮至少合成了一次。
func _try_merge() -> bool:
	var any := false
	# 上限 8 次 —— 结构上最多 3 层连锁，8 是防御性的（防止逻辑写错时空转）。
	for _guard in 8:
		if not _merge_once():
			break
		any = true
	return any


func _merge_once() -> bool:
	# 找第一组满足「同 id 同星且满 3 张」的
	var key := &""
	var star := 0
	for star_level in range(1, MAX_STAR):
		var seen := {}
		for e in all_owned():
			var k := StringName(e.get("ship_key", &""))
			var s := int(e.get("star", 1))
			if s != star_level:
				continue
			var tag := "%s@%d" % [String(k), s]
			seen[tag] = int(seen.get(tag, 0)) + 1
			if int(seen[tag]) >= 3:
				key = k
				star = s
				break
		if star > 0:
			break
	if star == 0:
		return false

	# 收集这三张：优先消费场上的（合成品就能留在场上）
	var field_hits: Array[int] = []
	var bench_hits: Array[int] = []
	for i in field.size():
		if _is_same(field[i], key, star):
			field_hits.append(i)
	for i in bench.size():
		if _is_same(bench[i], key, star):
			bench_hits.append(i)
	if field_hits.size() + bench_hits.size() < 3:
		return false

	var keep_in_field := not field_hits.is_empty()
	var take_field: Array[int] = []
	var take_bench: Array[int] = []
	var need := 3
	for i in field_hits:
		if need == 0:
			break
		take_field.append(i)
		need -= 1
	for i in bench_hits:
		if need == 0:
			break
		take_bench.append(i)
		need -= 1

	# 继承位置：先摘出「保留的那一张」，别的删掉
	var inherited := Vector2i(-1, -1)
	if keep_in_field:
		inherited = field[take_field[0]].get("cell", Vector2i(-1, -1))
	else:
		inherited = bench[take_bench[0]].get("cell", Vector2i(-1, -1))

	# 倒序删除（先删大下标，免得前面的下标失效）
	var drop_field: Array[int] = take_field.duplicate()
	drop_field.sort()
	drop_field.reverse()
	for i in drop_field:
		field.remove_at(i)
	var drop_bench: Array[int] = take_bench.duplicate()
	drop_bench.sort()
	drop_bench.reverse()
	for i in drop_bench:
		bench.remove_at(i)

	var merged := _make_entry(key, star + 1)
	merged["cell"] = inherited
	if keep_in_field:
		field.append(merged)
	else:
		bench.append(merged)

	var d := EveShipDatabase.by_id(String(key))
	var nm := String(d.get("name", String(key)))
	log_event.emit("★ 三连合成：%s ×3 → %s★%d%s" % [
			nm, nm, star + 1, "（留在场上）" if keep_in_field else "（留在备战席）"],
			&"economy")
	return true


static func _is_same(e: Dictionary, key: StringName, star: int) -> bool:
	return StringName(e.get("ship_key", &"")) == key and int(e.get("star", 1)) == star


# ══════════════════════════════════════════════════════════════════
#  拖放部署（阶段 B5）
# ══════════════════════════════════════════════════════════════════
#
# ⚠️ 这里只管【编制】，不管 3D 与鼠标：
#    鼠标 → 格号 的换算在 EveBattleScene（它才知道相机与棋盘），
#    格号 → 世界坐标 也在那一侧（arena.board_cell_to_world）。
#    本类只回答「这一步允许吗、编制怎么变」。

## 拿起备战席第 index 艘，放到棋盘的 (row, col) 格。
func deploy_from_bench(bench_index: int, row: int, col: int) -> Dictionary:
	if phase != Phase.PREP:
		return _deny("只有准备阶段能布阵")
	if bench_index < 0 or bench_index >= bench.size():
		return _deny("这一格是空的")
	if not _cell_ok(row, col):
		return _deny("只能放在我方部署区（棋盘下 4 行）")
	if field.size() >= field_limit():
		return _deny("上场已满 %d／%d —— 先把场上一艘拖回备战席（或出售）"
				% [field.size(), field_limit()])
	if _cell_taken(row, col, -1):
		return _deny("这一格已经有船了")

	var e: Dictionary = bench[bench_index]
	e["cell"] = Vector2i(row, col)
	field.append(e)
	bench.remove_at(bench_index)
	var d := EveShipDatabase.by_id(String(e.get("ship_key", &"")))
	log_event.emit("%s★%d 上场 → 第 %d 行第 %d 列（%d／%d）" % [
			String(d.get("name", String(e.get("ship_key", "?")))), int(e.get("star", 1)),
			row + 1, col + 1, field.size(), field_limit()], &"deploy")
	changed.emit()
	return {"ok": true, "reason": "", "data": {}}


## 把场上第 index 艘挪到棋盘的 (row, col) 格
func move_field(field_index: int, row: int, col: int) -> Dictionary:
	if phase != Phase.PREP:
		return _deny("只有准备阶段能布阵")
	if field_index < 0 or field_index >= field.size():
		return _deny("这一格是空的")
	if not _cell_ok(row, col):
		return _deny("只能放在我方部署区（棋盘下 4 行）")
	if _cell_taken(row, col, field_index):
		return _deny("这一格已经有船了")
	field[field_index]["cell"] = Vector2i(row, col)
	changed.emit()
	return {"ok": true, "reason": "", "data": {}}


## 把场上第 index 艘撤回备战席（腾出人口）
func recall_to_bench(field_index: int) -> Dictionary:
	if phase != Phase.PREP:
		return _deny("只有准备阶段能调整编制")
	if field_index < 0 or field_index >= field.size():
		return _deny("这一格是空的")
	if bench.size() >= BENCH_SLOTS:
		return _deny("备战席已满（%d／%d）" % [bench.size(), BENCH_SLOTS])
	var e: Dictionary = field[field_index]
	e["cell"] = Vector2i(-1, -1)
	bench.append(e)
	field.remove_at(field_index)
	var d := EveShipDatabase.by_id(String(e.get("ship_key", &"")))
	log_event.emit("%s★%d 撤回备战席（上场 %d／%d）" % [
			String(d.get("name", "?")), int(e.get("star", 1)),
			field.size(), field_limit()], &"deploy")
	changed.emit()
	return {"ok": true, "reason": "", "data": {}}


## 出售返还的星币。
##
## ⚠️ 口径：合成品按 **3^(star-1) 张原价**返还 ——
##    2★ 是 3 张 1★ 合成的，所以退 3 倍；3★ 是 9 张，退 9 倍。
##    这样「合成"然后再卖」不亏不赚，玩家不会因为怕亏而不敢合成。
func sell_value(entry: Dictionary) -> int:
	var key := String(entry.get("ship_key", ""))
	var d := EveShipDatabase.by_id(key)
	var cost := int(d.get("cost", 1))
	return cost * int(pow(3.0, float(maxi(0, int(entry.get("star", 1)) - 1))))


func sell_from_bench(bench_index: int) -> Dictionary:
	if phase != Phase.PREP:
		return _deny("只有准备阶段能出售")
	if bench_index < 0 or bench_index >= bench.size():
		return _deny("这一格是空的")
	var e: Dictionary = bench[bench_index]
	return _do_sell(e, bench_index, true)


func sell_from_field(field_index: int) -> Dictionary:
	if phase != Phase.PREP:
		return _deny("只有准备阶段能出售")
	if field_index < 0 or field_index >= field.size():
		return _deny("这一格是空的")
	var e: Dictionary = field[field_index]
	return _do_sell(e, field_index, false)


func _do_sell(e: Dictionary, index: int, from_bench: bool) -> Dictionary:
	var back := sell_value(e)
	var d := EveShipDatabase.by_id(String(e.get("ship_key", "")))
	coin += back
	if from_bench:
		bench.remove_at(index)
	else:
		field.remove_at(index)
	log_event.emit("出售 %s★%d → 返还 %d ◆（星币 %d）" % [
			String(d.get("name", "?")), int(e.get("star", 1)), back, coin], &"sell")
	# ⚠️ 卖掉场上的船【不】自动从备战席补人（2026-09-20）——
	#    那同样是在替玩家做「谁上场」的决定。见「已删除：auto_deploy()」。
	changed.emit()
	return {"ok": true, "reason": "", "data": {"refund": back}}


static func _cell_ok(row: int, col: int) -> bool:
	# 棋盘 11×11、我方部署区 = 下 4 行（7..10）、隔离区不可放。
	# ⚠️ 这三个数的真源在 EveBoard（COLS/ROWS/ENEMY_ROWS/ISOLATION_ROWS）。
	#    这里只做「显然不可能」的兜底拦截，真正的分区判定由调用方
	#    用 board.is_placeable_for_player() 先做一遍 —— 两份判定的职责不同：
	#    那边管「画出来的格子能不能放」，这边管「编制上允许吗」。
	return row >= 7 and row <= 10 and col >= 0 and col <= 10


## 第 (row,col) 格是否已被自己占用（ignore = 允许自己占着的那个下标）
func _cell_taken(row: int, col: int, ignore_field_index: int) -> bool:
	for i in field.size():
		if i == ignore_field_index:
			continue
		var c = field[i].get("cell", Vector2i(-1, -1))
		if c is Vector2i and c.x == row and c.y == col:
			return true
	return false


## 落点预览：这一格现在能不能落（拖放时显示提示用）。
##
## ⚠️ 它存在的唯一理由是**让提示与实际结果共用一份判定**。
##    如果拖动时另写一套「能不能放」的判断，两套迟早会分叉，
##    症状是「提示说能放、松手却被拒」或者反过来 —— 玩家只会觉得游戏坏了。
func preview_place(row: int, col: int, source: StringName, index: int) -> Dictionary:
	if phase != Phase.PREP:
		return {"ok": false, "reason": "只有准备阶段能布阵"}
	if not _cell_ok(row, col):
		return {"ok": false, "reason": "只能放在我方部署区（棋盘下 4 行）"}
	if source == &"bench":
		if index < 0 or index >= bench.size():
			return {"ok": false, "reason": "这一格是空的"}
		if field.size() >= field_limit():
			return {"ok": false, "reason": "上场已满 %d／%d" % [field.size(), field_limit()]}
		if _cell_taken(row, col, -1):
			return {"ok": false, "reason": "这一格已经有船了"}
		return {"ok": true, "reason": ""}
	if index < 0 or index >= field.size():
		return {"ok": false, "reason": "这一格是空的"}
	if _cell_taken(row, col, index):
		return {"ok": false, "reason": "这一格已经有船了"}
	return {"ok": true, "reason": ""}


## 备战席还有没有空位（拖回预览用）
func can_recall() -> bool:
	return bench.size() < BENCH_SLOTS


## 上场的船（按上场顺序）—— 战斗场景按这个顺序造 EveShip 并摆位
func field_entries() -> Array[Dictionary]:
	return field


func bench_entries() -> Array[Dictionary]:
	return bench


## 拥有的全部船（上场 + 备战席），羁绊统计与三连合成用这一份
func all_owned() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.append_array(field)
	out.append_array(bench)
	return out


func bench_used() -> int:
	return bench.size()


# ══════════════════════════════════════════════════════════════════
#  羁绊（阶段 B3）
# ══════════════════════════════════════════════════════════════════
#
# ⚠️ 只统计【上场的船】—— 与云顶同口径（备战席不参与羁绊）。
#    这也是「备战席要不要留牌」这个决策的来源：留 2 张艾玛在备战席
#    不会给你任何加成，必须放上场。

## 当前生效的羁绊档位。
##
## 返回 [{group, member, count, n, text, apply, pending}]，按组的显示顺序排列。
func active_synergies() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for g in EveTraitTable.GROUPS:
		var key: StringName = g["key"]
		var counts := EveTraitTable.count(field, key)
		for m in EveTraitTable.members(key):
			var name := String(m["name"])
			var n := int(counts.get(name, 0))
			var t := EveTraitTable.tier_of(key, name, n)
			if t.is_empty():
				continue
			out.append({
				"group": key, "member": name, "count": n,
				"n": int(t["n"]), "text": String(t["text"]),
				"apply": t.get("apply", {}), "pending": t.get("pending", PackedStringArray()),
			})
	return out


## 把生效的羁绊乘进一支舰队，返回生效清单（供 HUD / 日志用）。
##
## ⚠️ 受益范围：只有**带该羁绊的船**吃到加成（艾玛 +20% 装甲 = 场上艾玛船 +20%）。
##    CSV 没写范围，这是工程侧的一次明确选择；要改成全队受益，
##    把下面 `EveTraitTable.ship_has(...)` 那个判断去掉即可。
##
## ⚠️ 数值叠加顺序（在 EveBattleScene._build_own_fleet 里）：
##      base → star(×1.8^Δ) → **synergy**（本函数）
##    星级在前、羁绊在后：羁绊的固定值加成（结构 +150）不会被星级放大，
##    这与「星级放大的是船本身的底子」这条口径一致。
func apply_synergies_to(fleet: Array) -> Array[Dictionary]:
	var act := active_synergies()
	if act.is_empty():
		return act
	for s in fleet:
		if not (s is EveShip):
			continue
		var ship: EveShip = s
		for a in act:
			if not EveTraitTable.ship_has(ship, a["group"], String(a["member"])):
				continue
			_apply_synergy(ship, a.get("apply", {}))
	return act


## 把一条羁绊的 `apply` 字典落到一艘船上
static func _apply_synergy(ship: EveShip, apply: Dictionary) -> void:
	if apply.is_empty():
		return
	var scale := {}
	var add := {}
	var armor := 1.0 + float(apply.get("armor_pct", 0.0))
	if not is_equal_approx(armor, 1.0):
		scale[&"armor"] = armor
		scale[&"hull"] = armor
	var shield := 1.0 + float(apply.get("shield_pct", 0.0))
	if not is_equal_approx(shield, 1.0):
		scale[&"shield"] = shield
	if apply.has("hull_flat"):
		add[&"hull"] = float(apply["hull_flat"])
	if apply.has("shield_flat"):
		add[&"shield"] = float(apply["shield_flat"])
	if not scale.is_empty() or not add.is_empty():
		ship.layer_hp_adjust(scale, add)

	var atk := 1.0 + float(apply.get("attack_pct", 0.0))
	if not is_equal_approx(atk, 1.0):
		ship.warhead_scale(atk)
	var cyc := 1.0 - float(apply.get("cycle_pct", 0.0))
	if not is_equal_approx(cyc, 1.0):
		ship.cycle_scale(cyc)
	var spd := 1.0 + float(apply.get("speed_pct", 0.0))
	if not is_equal_approx(spd, 1.0):
		ship.speed_scale(spd)


# ══════════════════════════════════════════════════════════════════
#  事件增益（阶段 C · 节点 4 / 10 / 14）
# ══════════════════════════════════════════════════════════════════
#
#  选项表在 `EveEventTable`（唯一真源，三个事件节点共用同一套）。
#  这里只负责「把 id 落地成数值」，以及把效果乘进舰队。

## 供事件面板使用：全部选项 + 每条是否已获取。
##
## ⚠️ 返回的是**复制品**（duplicate），面板可以随便在上面加字段，
##    不会污染常量表 —— 常量表被就地改过的话，那局结束也修不回来。
func event_options() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for o in EveEventTable.all():
		var d: Dictionary = (o as Dictionary).duplicate()
		d["taken"] = event_picks.has(StringName(d["id"]))
		out.append(d)
	return out


## 这一条现在还能不能选。
func can_pick_event(id: StringName) -> bool:
	if not EveEventTable.has_id(id):
		return false
	if event_picks.has(id) and not EveEventTable.ALLOW_REPICK:
		return false
	return true


## 落一条事件增益。返回 {} = 无效或被拒（面板因此可以放心重入）。
##
## 顺序很重要，别调换：
##   ① 先记 id（之后所有查询都以它为准）
##   ② 再落「一次性」效果（星币 / 经验 / 信标）
##   ③ 再写日志（add_xp 可能触发升级日志，晚写会被插到前面去）
##   ④ 最后 changed.emit()（HUD 重刷）
## `target` 只有「需要选船」的选项才会用到（武器调校 / 结构加固），
## 传的是**那一条 entry 本体**（`field_entries()` / `bench_entries()` 里的元素）。
## 没给目标时**直接拒绝**（返回 {}），不静默落地一个"全队生效"的假效果。
func apply_event(id: StringName, target: Dictionary = {}) -> Dictionary:
	if not can_pick_event(id):
		return {}
	var opt := EveEventTable.by_id(id)

	# ── 需要选船的：先校验目标，再落增益 ──
	# ⚠️ 校验放在 `event_picks.append` **之前** —— 否则选了个空目标却已经
	#    把这条记成"已获取"，玩家就白白损失一次事件机会。
	if bool(opt.get("pick_ship", false)):
		if target.is_empty():
			return {}
		_bump_entry_buff(target, opt.get("ship_apply", {}))

	event_picks.append(id)

	var parts := PackedStringArray()
	var gain := int(opt.get("coin", 0))
	if gain > 0:
		coin += gain
		parts.append("星币 +%d" % gain)
	var per_node := int(opt.get("coin_per_node", 0))
	if per_node > 0:
		parts.append("每节点收入 +%d" % per_node)
	var exp := int(opt.get("xp", 0))
	if exp > 0:
		parts.append("经验 +%d" % exp)

	# 信标：**上限与当前值同步抬高**。
	# ⚠️ 只抬上限在满血时会变成「一点效果都没有」（100/100 → 100/120），
	#    玩家会以为选了个空牌。扩容的语义天然包含「这 20 点就是新到账的」。
	var bmax := int(opt.get("beacon_max", 0))
	if bmax > 0:
		beacon += bmax
		parts.append("信标 +%d / 上限 +%d" % [bmax, bmax])
	var heal := int(opt.get("beacon_heal", 0))
	if heal > 0:
		var before := beacon
		beacon = mini(beacon_max(), beacon + heal)
		parts.append("信标回复 %d" % (beacon - before))
	if bool(opt.get("free_advanced_roll", false)):
		free_advanced_roll()
		parts.append("免费高级刷新（保底 1 艘 cost ≥ 3）")
	if bool(opt.get("pick_ship", false)) and not target.is_empty():
		parts.append("%s 永久强化" % _entry_name(target))

	log_event.emit("事件增益「%s」—— %s" % [String(opt.get("name", id)),
			", ".join(parts) if not parts.is_empty()
			else EveEventTable.effect_text(opt)], &"economy")

	if exp > 0:
		add_xp(exp)

	changed.emit()
	return opt


## 已获取的增益（给 HUD 的「事件增益」窗用）。
## 元素 = {id, name, tag, icon, effect, color}
func picked_event_info() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id in event_picks:
		var o := EveEventTable.by_id(id)
		if o.is_empty():
			continue
		out.append({
			"id": id,
			"name": String(o.get("name", id)),
			"tag": StringName(o.get("tag", &"")),
			"icon": StringName(o.get("icon", &"diamond")),
			"effect": EveEventTable.effect_text(o),
			"color": EveEventTable.tag_color(StringName(o.get("tag", &""))),
		})
	return out


## 给第 index 艘上场舰船挂一条**永久（本局内）**增益。
##
## 增益直接写在**那条 entry 上** —— 条目是跨节点持久的，所以"永久"天然成立，
## 不需要另开一张表去维护"哪艘船带什么"。Dictionary 是引用类型 ⇒ 就地改即可，
## 上场 ↔ 备战席之间换位也跟着走。
## ⚠️ 三连合成时 buffs 会丢（合成造的是新条目）—— 已知取舍：
##    另两条路（buff 跟着合进去 / 给合并加一层映射）都比"丢了"复杂得多。
func _bump_entry_buff(e: Dictionary, add: Dictionary) -> void:
	if add.is_empty() or e.is_empty():
		return
	var b: Dictionary = e.get("buffs", {})
	for k in add.keys():
		b[k] = float(b.get(k, 0.0)) + float(add[k])
	e["buffs"] = b


func _entry_name(e: Dictionary) -> String:
	var d := EveShipDatabase.by_id(String(e.get("ship_key", "")))
	return String(d.get("name", String(e.get("ship_key", "?"))))


## 把「挂在这一格上的永久增益」加到对应舰船上。
##
## `idx_map[i]` = 第 i 艘船对应的 `field` 下标（由 `_build_own_fleet` 同步维护，
## 拖放也用它）。⚠️ 必须走这张映射，不能假 ship[i] ↔ field[i] ——
## `instantiate_by_id` 失败时 `_build_own_fleet` 会 `continue`，两者就会错位。
func apply_field_buffs_to(fleet: Array, idx_map: Array[int]) -> void:
	for i in fleet.size():
		if i >= idx_map.size():
			break
		var fi := idx_map[i]
		if fi < 0 or fi >= field.size():
			continue
		var b: Dictionary = field[fi].get("buffs", {})
		if b.is_empty():
			continue
		_apply_synergy(fleet[i], b)


## 事件「黑市情报」：**免费**高级刷新，且 5 个槽位至少 1 艘 cost ≥ 3。
##
## ⚠️ 用**事后替换**而不是「重摇到满足为止」——
##    商店 1 级时 cost ≥ 3 的概率是 0，重摇会变成没有上界的死循环
##    （交接文档 §7.2 原文）。
## ⚠️ 替换位置固定为**最左**那个非打捞槽位（玩家视线落点，也是断言与截图的确定位置）。
## ⚠️ 对挂着的打捞船**豁免**：它是一次事件奖励，玩家并没有主动点「刷新」这个按钮，
##    「拿了个奖励，却赔掉一艘刚到手的东西」这个观感不成立（交接文档 §7.2 原文）。
func free_advanced_roll() -> void:
	roll_shop()
	var target := -1
	for i in offers.size():
		if not salvage_slots.has(i):
			target = i
			break
	if target < 0:
		return
	var cur: Dictionary = offers[target]
	if int(cur.get("cost", 1)) >= 3:
		return                                    # 已经满足保底，不动它
	var cand: Array = []
	for c in range(3, 6):
		cand.append_array(_pools.get(c, []))
	if cand.is_empty():
		push_warning("[事件] 黑市刷新找不到 cost ≥ 3 的船（船表为空？）")
		return
	offers[target] = cand[rng.randi_range(0, cand.size() - 1)]
	log_event.emit("黑市情报：免费高级刷新（保底 1 艘 cost ≥ 3）", &"economy")
	offers_changed.emit()
	changed.emit()


## 事件带来的「每节点收入」增量
func event_coin_per_node() -> int:
	var sum := 0
	for id in event_picks:
		sum += int(EveEventTable.by_id(id).get("coin_per_node", 0))
	return sum


## ⛔ 2026-10-01 删除：原来有个 `event_leak_reduce()`（事件减免漏网伤害）。
##    漏网机制整个删掉了，而按交接文档 §7.2 重写的四条事件**本来就没有**
##    `leak_reduce` 字段 ⇒ 它恒为 0，是死代码。以后要做「减伤」类事件，
##    直接在这里加一个新的减免项挂在 `loss_damage()` 上即可。


## 信标上限（事件可以把上限抬高）
func beacon_max() -> int:
	var add := 0
	for id in event_picks:
		add += int(EveEventTable.by_id(id).get("beacon_max", 0))
	return START_BEACON + add


## 把事件增益乘进一支舰队。
##
## ⚠️ 与 `apply_synergies_to` 的**关键差别**：羁绊只加在「带该羁绊的船」上，
##    而事件增益是**全队**的（面板文案写的是「全队」）。
##    两个函数都复用 `_apply_synergy` 那套键，所以数值口径（乘法叠加）一致。
##
## 叠加顺序（在 `EveBattleScene._build_own_fleet` 里）：
##      base → star(×1.8^Δ) → 羁绊 → **事件增益**
##    事件放在最后：它是玩家用「事件机会」换来的，不该被星级反算进去。
func apply_events_to(fleet: Array) -> Array[Dictionary]:
	var act := picked_event_info()
	if act.is_empty():
		return act
	for s in fleet:
		if not (s is EveShip):
			continue
		var ship: EveShip = s
		for a in act:
			var o := EveEventTable.by_id(a["id"])
			_apply_synergy(ship, o.get("apply", {}))
	return act


# ══════════════════════════════════════════════════════════════════
#  节点与回合
# ══════════════════════════════════════════════════════════════════

func current_node() -> Dictionary:
	return EveNodeTable.by_index(node_index)


func node_type() -> StringName:
	var n := current_node()
	return StringName(n.get("type", &"battle")) if not n.is_empty() else &"battle"


func stage_label() -> String:
	return EveNodeTable.label_of(node_type())


## 本节点的战斗时限（秒）。事件节点返回 0。
func battle_seconds() -> float:
	var n := current_node()
	return float(n.get("time", 45.0)) if not n.is_empty() else 45.0


func enemy_comp_id() -> String:
	var n := current_node()
	return String(n.get("comp", "")) if not n.is_empty() else ""


func enemy_comp_name() -> String:
	return EveEnemyComps.display_name(enemy_comp_id())


func enemy_comp_size() -> int:
	return EveEnemyComps.size_of(enemy_comp_id())


func enemy_scale() -> float:
	var n := current_node()
	return float(n.get("scale", 1.0)) if not n.is_empty() else 1.0


## 本节点的进场词（唯一真源 = EveNodeTable.ROWS[].line）。
##
## ⚠️ 转公开是给「节点进场字幕」用的 —— 在那之前场景侧是自己去读
##    `current_node().get("line")` 的，那种取法一多就会有人顺手改措辞。
func entry_line() -> String:
	var n := current_node()
	return String(n.get("line", "")) if not n.is_empty() else ""


## 当前节点的敌方编组（派生数据，尚未实例化）。
##
## ⚠️ 每次调用都返回**新造的数据**，调用方每次都要新造 EveShip ——
##    上一节点打残的血量绝不能带到下一节点，这是自走棋的基本盘。
func enemy_roster() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id in EveEnemyComps.ship_ids(enemy_comp_id()):
		var d := EveShipDatabase.by_id(String(id))
		if not d.is_empty():
			out.append(d)
	return out


## 下回合收入 = 基础 5 + 利息 min(⌊coin/10⌋, 5)
func interest() -> int:
	return mini(int(floor(float(coin) / float(INTEREST_STEP))), INTEREST_MAX)


func income() -> int:
	return BASE_INCOME + interest() + event_coin_per_node()


# ══════════════════════════════════════════════════════════════════
#  战斗结算
# ══════════════════════════════════════════════════════════════════

## 战败的信标代价 —— **只跟「这是什么类型的节点」有关**（见 `LOSS_BASE`）。
##
## ⛔ 2026-10-01：这里原来还 +Σ「漏网舰船费用」，那个概念已删除。
##    它让「我 3 艘全活却因为敌人没死光而掉血」这件事变得无法解释，
##    而它对玩家的**唯一**作用就是制造这种困惑。
func loss_damage() -> int:
	return int(LOSS_BASE.get(node_type(), 8))


## 连败追加伤害。`lose_streak` 已在 `resolve_battle` 里加过本场，
## 所以第一场（= 1）返回 0。
func loss_streak_bonus() -> int:
	if lose_streak <= 1:
		return 0
	return mini((lose_streak - 1) * LOSS_STREAK_STEP, LOSS_STREAK_BONUS_MAX)


## 战败代价预测 —— 开战前挂在顶条上的那个数字（硬核判据 H2：代价必须提前可见）
##
## ⚠️ 算的是「**这一场真的输了**会掉多少」⇒ 必须带上连败加成，
##    否则顶条上的数字会比实际少，那就违背了「代价提前可见」这条判据。
##    （战胜 = 0 伤害，顶条写的是「战败 −N」，语义本来就是"最坏情况"。）
func loss_preview() -> int:
	return loss_damage() + loss_streak_bonus()


## 取费用。裸 int 直接当费用（漏怪单测里允许只传数字）。
## 「怎么算一艘船」交给 `_as_ship_dict`（唯一判定处），这里不自己再认一遍。
## ⛔ 2026-10-01 删除：这里原来有个 `_cost_of()`，它**只**服务于已删除的
##    「Σ 漏网舰船费用」那一项。别再照着它加回来。
##    （`_as_ship_dict` 打捞还在用，保留。）

## 一帧一帧的伤害倍率（数值叠加顺序见 apply_enemy_scaling）
##
## destroyed = 本节点**被击毁**的敌舰（EveShip / Dictionary / ship_key 混着放都行）。
## 它只用来生成残骸（打捞），不参与信标记账 —— 信标只按「输没输」算。
##
## ⚠️ 2026-10-01 新增两个**可选**关键字参数（不是位置参数，别调换）：
##   `sources[i]` 与 `destroyed[i]` 一一对应，是本节点第 i 艘敌舰的
##     {"star","atk_base","def_base","m"} —— 结算那一刻的原始证据。
##     不传时自动退化为「现查船表 + 按 power_scale 假定」。
##   `power_scale` = 本节点敌方倍率，`sources` 缺失时用它倒推。
##   两者都缺省时行为与旧版一致（验收里的老调用点不用改）。
func resolve_battle(winner_team: int, destroyed: Array = [],
		sources: Array = [], power_scale: float = 1.0) -> Dictionary:
	if phase == Phase.ENDING:
		return {}
	var won: bool = winner_team == 0

	# ⚠️ 顺序：**先更新连胜/连败，再算伤害** —— 伤害里的「连败递增」要用到本场。
	if won:
		win_streak += 1
		lose_streak = 0
	elif winner_team == 1:
		lose_streak += 1
		win_streak = 0
	# 平局（-1）两边都不动 —— 云顶也是这个口径

	# ★★ 战胜 = **零代价**（2026-10-01 修的致命 bug）
	#
	# 原来这里是无条件 `beacon -= leak_damage(leaked)`，而 `leak_damage()` 里
	# （`leak_damage` 现名 `loss_damage`，且不再接 leaked 参数）
	# 「类型基础伤害」那一项是**永远加上**的（battle 2 / elite 3 / boss 4）
	# ⇒ **全歼敌人也每回合掉 2~4 点信标**，15 个节点光这一项就掉 30~45。
	# 玩家原话：「为啥我打赢了信标还是会掉血啊？这不是有病吗，
	#            守卫成功了信标还掉血，那我不是白守卫了？」
	#
	# 现在的口径：**赢 = 不掉血**；打输了按「阶段定值 + 连败递增」扣。
	var dmg := 0
	if not won:
		dmg = loss_damage() + loss_streak_bonus()
	var before := beacon
	beacon = maxi(0, beacon - dmg)
	last_won = won
	log_event.emit("节点 %d 结算：%s · 信标 %d → %d"
			% [node_index, "拦截成功" if won else "拦截失败",
			before, beacon],
			&"economy" if won else &"damage")
	if win_streak >= 2:
		log_event.emit("连胜 %d" % win_streak, &"hint")
	elif lose_streak >= 2:
		log_event.emit("连败 %d" % lose_streak, &"hint")

	# 每完成一个节点自动 +2 经验（交接文档 §5.3 NODE_XP_REWARD）
	add_xp(NODE_XP_REWARD)

	# 残骸：击毁的敌船里最贵的一艘（旧的没下单的残骸在这里作废）
	_set_wreck_from(destroyed, sources, power_scale)

	phase = Phase.RESOLVE
	phase_changed.emit(phase)
	changed.emit()
	return {"damage": dmg, "beacon": beacon, "won": won,
			"wreck": not wrecks.is_empty(),
			"wreck_count": wrecks.size()}


## 结算结束 → 推进节点（或收束到结局）
func advance() -> void:
	if phase == Phase.ENDING:
		return
	if beacon <= 0:
		_finish(false)
		return
	var at_last := node_index >= EveNodeTable.TOTAL
	if at_last and last_won:
		_finish(true)
		return
	# ★ 第 15 节点**打输了 ⇒ 重打**（交接文档 §5.4「BOSS 重打不推进节点」）。
	#
	# ⚠️ 原来这里是无条件 `_finish(true)` —— 打输了 BOSS 也照样算通关。
	#    那是本次修掉的一个真 bug，不只是手感问题。
	#    重打照常结算收入与商店（等于多给一个准备回合），
	#    直到打赢、或信标归零撤离（`beacon <= 0` 那条在上面拦住了）。
	if at_last:
		boss_attempts += 1
		log_event.emit("BOSS 重打 —— 节点不推进（第 %d 次重试）" % boss_attempts, &"hint")
	else:
		node_index += 1
	var inc := income()
	coin += inc
	log_event.emit("收入 +%d（基础 %d · 利息 %d）" % [inc, BASE_INCOME, interest()], &"economy")
	# 打捞的两步，顺序不能换：
	#   ① 先让上一节点的修复品**过期**（没买走就没了，并解锁槽位）；
	#   ② 再让本节点的到账**落位**（占掉槽位、记进 salvage_slots）。
	# 反过来的话，上一件还没买走的修复品会被新到账的覆盖掉 —— 玩家付了钱却看不到东西。
	_expire_repairs()
	if shop_locked:
		log_event.emit("加速列表已锁定，沿用上一轮报价", &"hint")
		# 锁定态下不重摇，但上一段可能刚重摇过个别槽位（过期清理），
		# 这是对的：过期的是「该消失的东西」，与锁不锁定无关。
	else:
		roll_shop()
	_deliver_repairs()
	log_event.emit("节点 %d／%d · %s · %s"
			% [node_index, EveNodeTable.TOTAL, stage_label(), entry_line()], &"hint")

	phase = Phase.PREP
	phase_changed.emit(phase)
	changed.emit()


func _finish(cleared: bool) -> void:
	ending = Ending.CLEARED if cleared else Ending.EVACUATED
	phase = Phase.ENDING
	if cleared:
		log_event.emit("全部 %d 个节点通过 —— 遥望边境已肃清" % EveNodeTable.TOTAL, &"economy")
	else:
		log_event.emit("信标归零 —— 撤离（止步于节点 %d／%d）"
				% [node_index, EveNodeTable.TOTAL], &"damage")
	phase_changed.emit(phase)
	run_ended.emit(cleared)
	changed.emit()


func set_phase(p: int) -> void:
	phase = p
	phase_changed.emit(phase)
	changed.emit()


# ══════════════════════════════════════════════════════════════════
#  敌方数值叠加（交接文档 §6.4 冻结顺序：base → star → power_scale）
# ══════════════════════════════════════════════════════════════════

## 把星级与 power_scale 叠到一艘船上。
##
## ⚠️ 两条口径不能改：
##   ① 顺序是 base → star(×1.8^Δ) → power_scale（先乘星级，再乘关卡缩放）
##   ② power_scale **只放大 atk / shield / armor**，不碰 speed / atk_speed / atk_range。
##      这里的「armor」是权威表的合并列（装甲/结构），
##      所以 armor 与 hull 两层一起放大 —— 它就是那一列的拆分结果。
static func apply_enemy_scaling(ship: EveShip, star: int, power_scale: float) -> void:
	if ship == null:
		return
	var s: float = pow(STAR_MULT, float(maxi(0, star - 1))) * maxf(0.01, power_scale)
	if is_equal_approx(s, 1.0):
		return
	ship.warhead_scale(s)
	ship.armor_scale(s)


# ══════════════════════════════════════════════════════════════════
#  工具
# ══════════════════════════════════════════════════════════════════

static func _deny(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "data": {}}


## 给 UI 一行摘要（顶条 / 自检用）
func summary() -> String:
	return "节点 %d/%d · Lv.%d(%d/%d) · 星币 %d · 信标 %d · 上场 %d/%d" % [
		node_index, EveNodeTable.TOTAL, level, xp_in_level(), xp_need(),
		coin, beacon, field.size(), field_limit(),
	]
