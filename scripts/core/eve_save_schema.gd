extends RefCounted
class_name EveSaveSchema

## 所有 `user://*.cfg` 存档的**格式版本号**（统一一处，四个存档共用）。
##
## ══════════════════════════════════════════════════════════════════
##  为什么现在才加（2026-10-10 · 审查 2#3）
## ══════════════════════════════════════════════════════════════════
##  本项目已经因为**改项目名 ⇒ `user://` 目录改名**吃过一次存档迁移的亏
##  （见 `eve_user_dir.gd`）—— 而当时**没有任何版本号**可以用来判断
##  "这份存档是哪一版写的"，只能靠猜（"某个键在不在"）。
##  每加一个字段就多一次这种猜。⇒ 从这一版起，每个存档都在
##  `[meta] schema_version` 里写下自己的格式版本；读盘按它决定是否迁移。
##
##  ── 规则（写新的存档模块时照抄这四条）──────────────────────────────
##   ① `SCHEMA_VERSION` 常量放在**各自模块**里（每份存档独立演进，互不影响）；
##   ② **写盘永远盖版本号**（`stamp()`）—— 顺手写，不额外判断；
##   ③ 读盘先 `version()`：`0` = 早于本机制的老档（也必须能读！）；
##      小于当前 ⇒ 跑迁移；**大于**当前 ⇒ 只警告、**绝不改写**（别把新版玩家的档写坏）；
##   ④ 迁移函数**必须幂等**（可能因写盘失败被重复执行）。
##
##  ⚠️ 本模块**只读不写**：`version()` 不会在任何一处改盘；只有各模块的
##     `save_*()` 才会写。⇒ 自检里调 `load_*()` 不会污染玩家存档这一条仍然成立。

const SECTION := "meta"
const KEY := "schema_version"


## 读某份存档的格式版本。返回 0 = 没有版本号（早于本机制，或文件不存在）。
static func version(cf: ConfigFile) -> int:
	if cf == null:
		return 0
	return int(cf.get_value(SECTION, KEY, 0))


## 盖上当前版本号（各模块**写盘前**调一次）。
static func stamp(cf: ConfigFile, version_current: int) -> void:
	if cf == null:
		return
	cf.set_value(SECTION, KEY, version_current)


## 统一判定「读到的版本 vs 当前版本」，返回**是否需要跑迁移**。
##
## ⚠️ 只有这一处做这个判断 —— 四份存档各写一份必然分叉（本工程的老毛病）。
## [param path] 仅用于日志。
static func needs_migration(path: String, loaded_v: int, current_v: int) -> bool:
	if loaded_v > current_v:
		push_warning("[存档] %s 的 schema_version=%d **高于**当前 %d —— 可能是旧版程序在读新版档，只读不改（新字段会被忽略）"
				% [path, loaded_v, current_v])
		return false
	return loaded_v < current_v
