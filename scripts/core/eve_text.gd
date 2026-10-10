extends RefCounted

## 文案取词入口（i18n）—— **玩家可见文字的唯一出口**。
##
## ══════════════════════════════════════════════════════════════════
##  为什么要有这一层，而不是到处直接写 `tr()`
## ══════════════════════════════════════════════════════════════════
##  ① **回落语义集中在一条**：源语言是中文，英文表只覆盖了一部分。
##     走 `TranslationServer` 的 fallback（project.godot 里 `locale/fallback="zh_CN"`）
##     能自动回落，但**回调函数里没有 `tr()`**（不是 Object 的方法）——
##     所以统一从这里取。
##  ② **自检好写**：`tools/verify_i18n` 拿 CSV 当设计侧真值，
##     逐条对拍「key 在两个 locale 下都取得到、且与 CSV 一致」。
##  ③ ⛔ **别把逻辑挂在文案上**（工程红线）：这一层只管**显示**。
##
## ⚠️ 翻译源 = `i18n/strings.csv`（`keys,en,zh_CN`），Godot 导入成
##    `i18n/strings.<locale>.translation`，条目登在 `project.godot` 的
##    `internationalization/locale/translations`。
##
## ⚠️⚠️ **提交新文案时：只要写进 CSV 就必须同时补齐所有 locale 列**
##    （缺的那列会回落中文 —— 那是预期行为，但等于"英文版露了中文"，
##     自检 `verify_i18n` 会逐条报出来）。
##
## ══════════════════════════════════════════════════════════════════
##  ⏸⏸ 冻结（2026-08-11 用户定调）：**英文版现在时机不成熟，先不做**
## ══════════════════════════════════════════════════════════════════
##  这一层**保留但不再推进**：CSV 里大量 en 列是占位/直译、没过审，
##  UI 面也只迁了一半 ⇒ 玩家切到 en 会看到中英混杂的半成品。
##  ⛔ 不要再往 `i18n/strings.csv` 加 key、不要跑 `add_i18n_*_rows.py`、
##     不要迁移新的 UI 面，除非用户明确解冻。
##  ✅ 已迁的保留不动：默认 locale = zh_CN ⇒ 取词原样返回中文，
##     中文版行为逐字不变（`verify_i18n` 就是这条的护栏）。
##  解冻顺序：先补英文文案本身 → 再迁剩余面 → 最后才开放设置窗「语言」行。
##  详见 `i18n/README.md` 顶部的冻结说明。
##
## ★ 2026-10-10 立：用户定调「以后肯定要出英文版，EVE 欧服玩家很多」。
## ★ 2026-10-11 按下：先不做，时机未到。

## 支持的 locale —— 顺序 = 设置窗「语言」行的顺序。
## ⏸ 冻结中：**只有 zh_CN 对外可用**；`en` 留着是为了自检（`verify_i18n` 要切过去对拍）。
const LOCALES: Array = [
	{"code": "zh_CN", "name": "简体中文"},
	{"code": "en", "name": "English"},
]
## 默认 / 源语言。⛔ 别改成 "en" —— 绝大多数文案还没英文，会露一堆中文。
const DEFAULT_LOCALE := "zh_CN"

## ★★ **「语言」开关（唯一真源）—— ⏸ 冻结中，`false`。**
##
## `false` = **不向玩家提供语言选择**：设置窗不建「语言」行，
##          且 `apply_saved()` **忽略存档里已存的 language**（强制 zh_CN）。
##          第二点是必须的：否则之前手滑切过 English 的玩家，一进游戏还是半成品英文。
##
## 解冻（英文文案过审 + UI 面迁完之后）：把这个常量改成 `true`，
## 设置窗那一行会自己回来 —— 代码一直在，只是被这个开关挡着。
## ⛔ 别在别处再写一个"是否支持英文"的判断，只认这一个常量。
const LANGUAGE_ENABLED := false

## 语言选择的落盘（`user://settings.cfg` 的 `language` 项）。
const STORE := preload("res://scripts/core/eve_settings_store.gd")

static var _locale: String = DEFAULT_LOCALE


## 当前 locale（"zh_CN" / "en"）。
static func current() -> String:
	return _locale


static func is_supported(code: String) -> bool:
	for l in LOCALES:
		if String(l["code"]) == code:
			return true
	return false


## 切换 locale。⚠️ 只改**运行时**的翻译服务；要不要落盘 / 重载场景由调用方决定。
static func set_locale(code: String) -> bool:
	if not is_supported(code):
		push_warning("[EveText] 不支持的 locale：%s" % code)
		return false
	_locale = code
	TranslationServer.set_locale(code)
	return true


## 取词。`key` 取不到任何翻译时返回 `fallback`（缺省 = key 本身，便于开发期一眼看出漏翻）。
##
## ⚠️ 调用点一律写成 `T.t(&"SETTINGS_TITLE", "设置")` —— 第二参是**中文源文**
##    （既是兜底，也是"这句中文本来就长这样"的活文档；CSV 里那条 zh_CN 必须与它一致，
##     自检会对拍）。
static func t(key: StringName, fallback: String = "") -> String:
	var s := String(TranslationServer.translate(key))
	if s == String(key):
		return fallback if fallback != "" else String(key)
	return s


## 某个 locale 的**显示名**（"简体中文" / "English"）。空参 = 当前。
static func locale_label(code: String = "") -> String:
	var c := code if code != "" else _locale
	for l in LOCALES:
		if String(l["code"]) == c:
			return String(l["name"])
	return c


## 从设置存档读语言并应用。**各场景 `_ready` 的第一句**就该调它 ——
## ⚠️ 必须早于任何 UI 构建：文案是**建的时候**取词的，晚了就换不回去。
static func apply_saved() -> void:
	var code := String(STORE.load_all().get("language", ""))
	# ⏸ 冻结期：**忽略**存档里已存的语言（可能有人手滑切过 English），一律回落 zh_CN。
	#    解冻后（`LANGUAGE_ENABLED = true`）这段自然失效，存档里的选择重新生效。
	set_locale(code if (LANGUAGE_ENABLED and is_supported(code)) else DEFAULT_LOCALE)


## 把语言选择写进设置存档（调用方负责 `set_locale`）。
static func save_locale(code: String) -> void:
	STORE.save_one("language", code)


## 某个 locale 下这条 key 取到什么（自检用）。
static func lookup(key: StringName, code: String) -> String:
	var prev := TranslationServer.get_locale()
	TranslationServer.set_locale(code)
	var s := String(TranslationServer.translate(key))
	TranslationServer.set_locale(prev)
	return s
