extends RefCounted
class_name EveRunStore

## **对局存档**（`user://run.cfg`）—— 把「一局打到一半」存下来（审查 2#2）
##
## ══════════════════════════════════════════════════════════════════
##  为什么需要它
## ══════════════════════════════════════════════════════════════════
##  一局 15 个节点、动辄半小时。而 `EveRunState` **从来只活在内存里** ——
##  关掉游戏 / 手机切后台被系统杀掉 / 编辑器崩一次，这一局**整个没了**。
##  （工程里存盘的只有设置、剧情进度、娱乐币、窗口布局，没有"对局本身"。）
##
## ── 三条口径 ──────────────────────────────────────────────────────
##   ① **只有真实会话才写盘**：`session_active` 由**主菜单**在切场景前置位。
##      ⛔ 不加这道闸的话，40 多个直接加载 `battle_scene` 的 probe/verify
##         跑一次就把玩家"继续上一局"覆盖成测试里那一局。
##   ② **不做跨版本迁移**：对局是"半途状态"，硬迁移很容易造出一个诡异的局
##      ⇒ `schema_version` 不一致就**直接丢弃**（比载入一个错乱的局好得多）。
##   ③ 写盘时机由调用方决定（当前 = 每次进入新的准备阶段前，见 `eve_battle_scene`）。

## ⛔ 用 preload 常量引用存档版本号工具（无头跑没有全局类缓存）。
const SAVE_SCHEMA := preload("res://scripts/core/eve_save_schema.gd")

const PATH := "user://run.cfg"
const SECTION := "run"
const KEY := "data"

## 格式版本。⚠️ 与 ① 配套：**不一致即丢弃**，所以这个数字变了老档就自动作废。
const SCHEMA_VERSION := 1

## 是否允许写盘（惯例同 `EveWindowStore.persist`；自检里置 false）。
static var persist := true

## ★ 「这一局是从主菜单真实开始的吗」—— 防自检污染存档的闸门（见顶注 ①）。
static var session_active := false

## 主菜单点「继续上一局」时置位；battle_scene 启动时读它决定是否恢复。
static var resume_requested := false


static func _write_allowed() -> bool:
	return persist and session_active


## 有没有可继续的一局（主菜单据此显示「继续上一局」）。
static func has_run() -> bool:
	return FileAccess.file_exists(PATH)


## 存一局。`d` 为 `EveRunState.to_dict()` 的产物；空 ⇒ 不写。
static func save_run(d: Dictionary) -> void:
	if d.is_empty() or not _write_allowed():
		return
	var cf := ConfigFile.new()
	cf.set_value(SECTION, KEY, d)
	SAVE_SCHEMA.stamp(cf, SCHEMA_VERSION)          # ★ 写盘永远盖版本号
	var err := cf.save(PATH)
	if err != OK:
		push_warning("[对局存档] 写盘失败（%d）" % err)


## 读一局。返回 {} = 没有 / 读失败 / **版本不符（直接丢弃）**。
static func load_run() -> Dictionary:
	var cf := ConfigFile.new()
	if cf.load(PATH) != OK:
		return {}
	var v := SAVE_SCHEMA.version(cf)
	if v != SCHEMA_VERSION:
		# ★ 口径 ②：对局存档**不做迁移**，版本不符就丢（宁可从头再来，
		#   也不要载入一个字段含义已经变了的半途状态）。
		push_warning("[对局存档] schema_version=%d ≠ 当前 %d —— 丢弃这一局（不迁移）"
				% [v, SCHEMA_VERSION])
		clear()
		return {}
	var d = cf.get_value(SECTION, KEY, {})
	return d if d is Dictionary else {}


## 删档（重开一局 / 结局 / 版本不符时调）。
## ⚠️ 同样受 `session_active` 闸门保护 —— 否则自检里的 `restart_run()`
##    会把**玩家真实的那一局**删掉（"自检污染存档"的老毛病）。
static func clear() -> void:
	if not _write_allowed():
		return
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
