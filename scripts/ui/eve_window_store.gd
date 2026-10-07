extends RefCounted
class_name EveWindowStore

## 浮窗**布局**存档（`user://window_layout.cfg`）
##
## 存的是「玩家把窗口拖到哪、拉成多大、收起了没有」——
## ⛔ **不要合并进 `EveSettingsStore`（settings.cfg）也不要合并进 `EveProgressStore`**：
##   · `settings.cfg` 的 `DEFAULTS` 是**固定键表**（load_all 会按表逐项校验类型），
##     而窗口布局的键是**动态的**（有几扇窗就有几条）⇒ 塞进去会让那张表失去意义；
##   · `progress.cfg` 存的是「玩到哪了」，与布局无关。
##   两者分开的理由见 `eve_progress_store.gd` 开头的注释 —— 同一套口径。
##
## ⚠️ **验收脚本必须先 `persist = false`**：否则跑一次自检就把玩家的窗口布局冲掉了
##    （与 `ddz_coin.gd` / `verify_run` 里对 `settings.cfg` 的做法一致）。

const PATH := "user://window_layout.cfg"
const SECTION := "windows"

## 是否写盘。验收里置 false（⛔ 别忘——写盘会污染玩家的真实布局）。
static var persist := true


## 读一扇窗的布局。返回 {} = 没记录过（用设计稿的位置）。
## 字段：`x` `y` `w` `h`（float，视口坐标）、`collapsed`（bool）。
static func load_window(key: String) -> Dictionary:
	if key == "":
		return {}
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return {}
	var v: Variant = cfg.get_value(SECTION, key, {})
	if v is Dictionary:
		return (v as Dictionary).duplicate()
	return {}


## 写一扇窗的布局。`d` 为空 ⇒ 删除该键（= 恢复设计稿位置）。
static func save_window(key: String, d: Dictionary) -> void:
	if not persist or key == "":
		return
	var cfg := ConfigFile.new()
	cfg.load(PATH)          # 不存在就用空的（不报错）
	var touched := false
	if d.is_empty():
		# ⚠️ **先判存在再删**：`erase_section_key()` 对不存在的键会报
		#    `Cannot erase key ... from nonexistent section` —— 不致命，
		#    但会刷屏。而这条路径在**运行时**真的会走到：
		#    `EveWindow.reset_layout()` ← 切换 UI 缩放档（移动端）。
		if cfg.has_section_key(SECTION, key):
			cfg.erase_section_key(SECTION, key)
			touched = true
	else:
		cfg.set_value(SECTION, key, d)
		touched = true
	# ⚠️ 什么都没改就**别写盘** —— 否则一次「重置全部窗口」会把一个
	#    0 字节的 cfg 落到玩家目录里（无害但很脏，而且下次 load 会失败）。
	if touched:
		cfg.save(PATH)


## 清空全部记录（设置窗里的「重置窗口布局」用）
static func clear_all() -> void:
	if not persist:
		return
	var cfg := ConfigFile.new()
	cfg.load(PATH)
	cfg.erase_section(SECTION)
	cfg.save(PATH)
