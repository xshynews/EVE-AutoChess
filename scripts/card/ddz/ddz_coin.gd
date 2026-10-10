extends RefCounted
## 存档格式版本号工具（⛔ 用 preload 常量，别裸写 class_name —— 无头跑没有类缓存）。
const SAVE_SCHEMA := preload("res://scripts/core/eve_save_schema.gd")

## 娱乐币 —— **娱乐总汇（棋牌室）的记分货币**。
##
## ★ 2026-10-06 用户拍板：**先做方案 A（纯记分）**，但**字段按 B/C 设计**。
##   - A = 只累计，**不设底金、不惩罚** ⇒ 余额可以为负，输光没有任何后果。
##   - B/C 要用到的东西（累计下注、破产次数）**现在就留字段**，
##     将来加"底金 / 保底 / 用自走棋成绩兑换"时**不用改存档格式**。
##
## ⛔ **与自走棋的星币完全分开**（用户视频定位：两者是两条经济线）：
##   星币是按「每节点 3~6」平衡的**局内**经济；娱乐币一局动辄几百上千
##   ⇒ 混在一起会把自走棋的经济平衡冲垮。
##
## ⚠️ 会写盘（`user://card_coin.cfg`）⇒ 自检/探针必须
##   `persist = false` 或**存快照 + 原样写回**（工程里踩过"自检污染存档"的坑）。

const SAVE_PATH := "user://card_coin.cfg"
const SECTION := "card"

## ★ 2026-10-10（审查 2#3）：格式版本（详见 `EveSaveSchema` 顶注四条规则）。
const SCHEMA_VERSION := 1

## 余额（A 方案：**可以为负**）
static var coin := 0
static var net := 0          ## 累计净胜
static var games := 0
static var wins := 0
## ★ B/C 预留（现在只记，不参与任何判定）
static var staked := 0       ## 累计下注额 ⇒ 做"底金"时用它算入场门槛
static var bankrupt := 0     ## 破产次数 ⇒ 做"保底/救济"时用它

static var loaded := false
## ⚠️ 自检把它设成 false ⇒ `record()` 不写盘（避免污染玩家存档）
static var persist := true


static func load_it() -> void:
	if loaded:
		return
	loaded = true
	var cf := ConfigFile.new()
	if cf.load(SAVE_PATH) != OK:
		return
	coin = int(cf.get_value(SECTION, "coin", 0))
	net = int(cf.get_value(SECTION, "net", 0))
	games = int(cf.get_value(SECTION, "games", 0))
	wins = int(cf.get_value(SECTION, "wins", 0))
	staked = int(cf.get_value(SECTION, "staked", 0))
	bankrupt = int(cf.get_value(SECTION, "bankrupt", 0))


static func save_it() -> void:
	if not persist:
		return
	var cf := ConfigFile.new()
	# ⚠️ 2026-10-10：**必须先 load** —— 旧实现直接 new 一个空的 ConfigFile 再 save，
	#    会把文件里**其它段**（现在有 `[meta] schema_version`）整段抹掉。
	cf.load(SAVE_PATH)
	cf.set_value(SECTION, "coin", coin)
	cf.set_value(SECTION, "net", net)
	cf.set_value(SECTION, "games", games)
	cf.set_value(SECTION, "wins", wins)
	cf.set_value(SECTION, "staked", staked)
	cf.set_value(SECTION, "bankrupt", bankrupt)
	SAVE_SCHEMA.stamp(cf, SCHEMA_VERSION)          # ★ 写盘永远盖版本号
	cf.save(SAVE_PATH)


## 结算一局。`delta` = 娱乐币增减（+ = 赚）。`won` = 玩家这局算不算赢。
static func record(delta: int, won: bool) -> void:
	load_it()
	coin += delta
	net += delta
	games += 1
	if won:
		wins += 1
	staked += absi(delta)
	save_it()


## 只给自检用：把内存状态清零（⛔ 不动磁盘；`persist` 另设）。
static func reset_for_test() -> void:
	coin = 0
	net = 0
	games = 0
	wins = 0
	staked = 0
	bankrupt = 0
	loaded = true


## 千分位格式化（纯逻辑，自检可测）。
static func fmt(v: int) -> String:
	var body := str(absi(v))
	var out := ""
	var c := 0
	for i in range(body.length() - 1, -1, -1):
		out = body[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = "," + out
	return ("-" if v < 0 else "") + out
