extends RefCounted
class_name EveProgressStore
## 存档格式版本号工具（⛔ 用 preload 常量，别裸写 class_name —— 无头跑没有类缓存）。
const SAVE_SCHEMA := preload("res://scripts/core/eve_save_schema.gd")


## 跨局进度存档（`user://progress.cfg`）
##
## ⛔ **不要合并进 `EveSettingsStore`。**
##    那个文件按设计只存「玩家偏好」（音量 / 背景 / 心情，见 MEMORY 第 1 章），
##    而本文件存的是「玩家**玩到哪了**」—— 两者语义不同、生命周期也不同。
##    混在一起的典型症状：「上局收尾关掉的开关 ⇒ 下局开局也是关的」
##    （设置窗那一轮踩过，所以特意分成两个文件）。
##
## ⚠️ 目前是**最小实现**：只有 `intro_seen`。
##    以后加「通关难度 / 各难度进度 / 最高波次」都往 `DEFAULTS` 里加一条即可 ——
##    那张表是**唯一真相源**（加字段先加那里）。

const PATH := "user://progress.cfg"
const SECTION := "progress"

## ★ 2026-10-10（审查 2#3）：格式版本（详见 `EveSaveSchema` 顶注四条规则）。
## 1 = 引入版本号机制本身（0 → 1：无实际迁移）。
const SCHEMA_VERSION := 1

const DEFAULTS := {
	## 「守卫边境」的开场剧情是否已看过。看过 ⇒ 下次直接进对局，不再拦人。
	"intro_seen": false,
}


## 读全部：缺文件 / 缺项 / 类型不符 一律回落默认值并告警（不抛错）。
static func load_all() -> Dictionary:
	var out := DEFAULTS.duplicate(true)
	var cfg := ConfigFile.new()
	var err := cfg.load(PATH)
	if err == ERR_FILE_NOT_FOUND:
		return out                                   # 首次启动，天然走默认
	if err != OK:
		push_warning("[进度存档] 读取失败（%d），使用默认值" % err)
		return out
	# ★ 2026-10-10（审查 2#3）：按版本号决定要不要迁移（0 = 老档，同样能读）。
	if SAVE_SCHEMA.needs_migration(PATH, SAVE_SCHEMA.version(cfg), SCHEMA_VERSION):
		_migrate(cfg, SAVE_SCHEMA.version(cfg))
	for key in DEFAULTS.keys():
		if not cfg.has_section_key(SECTION, key):
			continue
		var v: Variant = cfg.get_value(SECTION, key)
		if typeof(v) != typeof(DEFAULTS[key]):
			push_warning("[进度存档] %s 类型不符（期望 %d 得到 %d），使用默认值"
					% [key, typeof(DEFAULTS[key]), typeof(v)])
			continue
		out[key] = v
	return out


static func save_all(d: Dictionary) -> void:
	var cfg := ConfigFile.new()
	cfg.load(PATH)                                   # 不存在也无所谓，save 会建
	for key in DEFAULTS.keys():
		cfg.set_value(SECTION, key, d.get(key, DEFAULTS[key]))
	SAVE_SCHEMA.stamp(cfg, SCHEMA_VERSION)         # ★ 写盘永远盖版本号
	var err := cfg.save(PATH)
	if err != OK:
		push_warning("[进度存档] 写入失败（%d）" % err)


## 旧版本存档 → 当前版本的**就地迁移**（只改 `cfg`，⛔ 不写盘；必须**幂等**）。
## 0 → 1：仅引入版本号机制，键名与含义都没变 ⇒ 无事可做。
static func _migrate(_cfg: ConfigFile, _from_v: int) -> void:
	pass


## 读 → 改一个键 → 全量写回。不动其它键。
static func save_one(key: String, value: Variant) -> void:
	var d := load_all()
	d[key] = value
	save_all(d)


static func intro_seen() -> bool:
	return bool(load_all()["intro_seen"])


static func mark_intro_seen() -> void:
	save_one("intro_seen", true)
	print("[进度存档] 开场剧情已标记为看过 → 下次直接进对局")


## 供验收 / 调试用：把进度重置回默认（开发者想再看一次开场时调它）。
static func reset() -> void:
	save_all(DEFAULTS.duplicate(true))
