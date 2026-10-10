extends Node

## ★ 2026-10-10 i18n（第一步：基础设施 + 试点）的回归自检。
##
## ⏸⏸ **2026-10-11 冻结**：英文版先不做（用户定调「现在时机不成熟」）。
## ⛔ 所以别再往这里加"新面迁移覆盖率"的段 —— 面都停了。
## ✅ 但这一套**继续跑**：它现在的主要价值是反过来的 ——
##    「**zh_CN 下取词必须逐字等于中文源文**」，也就是"i18n 化的代码没把中文版改坏"的护栏。
##    （`verify_run 592/0` 等其它套件也靠它兜底。）
## 解冻后它才恢复"英文覆盖率"的本职，那时 en 列的缺口会被逐条报出来。
##
## 判据三条（都对着「真值」而不是代码自己的说法）：
##  ① **CSV 是设计侧真值**：`i18n/strings.csv` 里每条 key，在 zh_CN / en 两个 locale 下
##     取出来的字符串必须与 CSV **逐字相同**（含大小写与标点）。
##  ② **两个 locale 都不许空**：某一列留空 ⇒ 英文版会回落成中文（不是崩，是"露馅"）
##     ⇒ 这里直接判红，逼着提交新文案时补齐两列。
##  ③ **试点真的接上了**：用 `en` 构造一次设置窗，它的标题必须是英文 ——
##     这条防的是「CSV 建好了，但代码里还是硬编码中文」这种假接线。

const CSV_PATH := "res://i18n/strings.csv"
const T := preload("res://scripts/core/eve_text.gd")
const SETTINGS_SCRIPT := preload("res://scripts/ui/panels/eve_settings.gd")
## 术语三方对拍用（④）。
const SHIP_TABLE := preload("res://scripts/data/eve_ship_table.gd")
const ASSET := preload("res://scripts/data/eve_ship_asset_index.gd")
const CIDS := preload("res://scripts/core/eve_combat_ids.gd")
const SDB := preload("res://scripts/core/eve_ship_database.gd")
## ⑤ 主菜单 UI 面（`_mode_txt/_card_txt/_stat_txt` 都是 static ⇒ 可静态调用）。
const MENU := preload("res://scripts/eve_main_menu.gd")
const TIERS := preload("res://scripts/data/eve_campaign_tiers.gd")
## 牌型名唯一真源（日志与牌桌共用 `R.type_name()`）。
const RULES := preload("res://scripts/card/ddz/ddz_rules.gd")
## 战斗阶段模块（`end_reason` 是**静态契约**，`verify_run` 直接调）。
const PHASE_BATTLE := preload("res://scripts/scene/eve_phase_battle.gd")
## 命令条（阶段名源文表 + key 表）。
const BAR_SCRIPT := preload("res://scripts/ui/panels/eve_command_bar.gd")

var _pass := 0
var _fail := 0


func _ok(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
		print("  ✓ %s" % msg)
	else:
		_fail += 1
		print("  ✗ [FAIL] %s" % msg)


func _ready() -> void:
	await get_tree().process_frame
	print("═══ verify_i18n ═══")
	_t_csv_matches()
	_t_pilot_wired()
	_t_language_switch()
	_t_terms()
	_t_menu_wired()
	_t_settings_wired()
	_t_result_wired()
	_t_shop_wired()
	_t_dossier_wired()
	_t_ddz_wired()
	_t_battle_wired()
	print("")
	print("═══ RESULT passed=%d failed=%d ═══" % [_pass, _fail])
	print("VERIFY_DONE failed=%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


## 读 CSV（⛔ 别用 Godot 的翻译资源当判据 —— 那等于拿实现验实现）。
##
## ⚠️⚠️ **必须走真 CSV 解析**（`_csv_cols`），⛔ 别 `line.split(",")`：
##    文案里带逗号是常态（"One deck, three opponents. ..."），`csv` 模块会把它
##    整段加引号写进 CSV ⇒ 按逗号裸切会把一句切成好几列，验收就**假失败**
##    （10-10 迁移主菜单时踩到：9 条长文案全被判「与 CSV 不一致」，其实是一致的）。
func _read_csv() -> Array:
	var rows: Array = []
	var f := FileAccess.open(CSV_PATH, FileAccess.READ)
	if f == null:
		return rows
	var header := true
	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line == "":
			continue
		var cols := _csv_cols(line)
		if header:
			header = false
			continue
		if cols.size() >= 3:
			rows.append({
				"key": String(cols[0]).strip_edges(),
				"en": String(cols[1]).strip_edges(),
				"zh": String(cols[2]).strip_edges(),
			})
	return rows


## 拆一行 CSV（RFC 4180 够用的子集）：字段可被 `"` 包起来，内部 `""` = 一个 `"`。
## ⚠️ 只处理**单行**；本工程的文案里没有换行（有换行的话 CSV 会跨行，届时再说）。
static func _csv_cols(line: String) -> PackedStringArray:
	var out := PackedStringArray()
	var cur := ""
	var in_q := false
	var i := 0
	var n := line.length()
	while i < n:
		var c := line[i]
		if in_q:
			if c == '"':
				if i + 1 < n and line[i + 1] == '"':
					cur += '"'
					i += 2
					continue
				in_q = false
				i += 1
				continue
			cur += c
			i += 1
			continue
		if c == '"':
			in_q = true
			i += 1
			continue
		if c == ",":
			out.append(cur)
			cur = ""
			i += 1
			continue
		cur += c
		i += 1
	out.append(cur)
	return out


func _t_csv_matches() -> void:
	print("── ① CSV ↔ 翻译资源逐条对拍 ──")
	var rows := _read_csv()
	_ok(rows.size() > 0, "读到翻译源 %s（%d 条）" % [CSV_PATH, rows.size()])
	if rows.is_empty():
		return
	var bad_both := 0
	var bad_zh := 0
	var bad_en := 0
	for r in rows:
		var k := StringName(r["key"])
		if String(r["zh"]) == "" or String(r["en"]) == "":
			bad_both += 1
			print("      ✗ %s 有空列（zh=「%s」en=「%s」）" % [r["key"], r["zh"], r["en"]])
			continue
		if T.lookup(k, "zh_CN") != String(r["zh"]):
			bad_zh += 1
			print("      ✗ %s：zh_CN 取到「%s」，CSV 是「%s」"
					% [r["key"], T.lookup(k, "zh_CN"), r["zh"]])
		if T.lookup(k, "en") != String(r["en"]):
			bad_en += 1
			print("      ✗ %s：en 取到「%s」，CSV 是「%s」"
					% [r["key"], T.lookup(k, "en"), r["en"]])
	_ok(bad_both == 0, "★ 每条 key 的 en / zh_CN 两列都非空（缺 %d 条）" % bad_both)
	_ok(bad_zh == 0, "★ zh_CN 逐字与 CSV 一致（不一致 %d 条）" % bad_zh)
	_ok(bad_en == 0, "★ en 逐字与 CSV 一致（不一致 %d 条）" % bad_en)

	# 缺翻译时的**回落**：源语言是中文 ⇒ project.godot 的 fallback 必须是 zh_CN
	var fb := String(ProjectSettings.get_setting("internationalization/locale/fallback", ""))
	_ok(fb == "zh_CN", "★ fallback locale = zh_CN（实际「%s」）—— 英文缺条回落中文而不是露出 key" % fb)
	# 未登记的 key ⇒ 返回调用点给的**中文源文**（⛔ 不许把 key 直接甩给玩家）
	var miss := T.t(&"__NO_SUCH_KEY__", "兜底中文")
	_ok(miss == "兜底中文", "★ 未登记的 key 返回调用点给的中文源文（实际「%s」）" % miss)


func _t_pilot_wired() -> void:
	print("── ② 试点接线（设置窗标题 / ✕ tooltip）──")
	var zh_title := T.lookup(&"SETTINGS_TITLE", "zh_CN")
	var en_title := T.lookup(&"SETTINGS_TITLE", "en")
	_ok(zh_title == "设置" and en_title == "Settings",
			"SETTINGS_TITLE：zh「%s」/ en「%s」" % [zh_title, en_title])

	# 切到 en 构造一次设置窗：标题必须**跟着变**（防「CSV 建好了代码还硬编码」）
	T.set_locale("en")
	var sw: Variant = SETTINGS_SCRIPT.new()
	sw.set("persist_layout", false)      # ⛔ 别写玩家的窗口布局档
	add_child(sw)
	_ok(String(sw.get("window_title")) == "Settings",
			"★ 用 en 构造 ⇒ 设置窗标题是「Settings」（实际「%s」）" % String(sw.get("window_title")))
	# ★ 布局键**不能**跟着文案变（否则切语言 = 布局存档换键 = 窗口布局"丢失"）
	_ok(String(sw.call("_layout_key")) == "battle_settings",
			"★★ 布局存档键与文案无关（实际「%s」）" % String(sw.call("_layout_key")))
	sw.queue_free()

	T.set_locale("zh_CN")
	var sw2: Variant = SETTINGS_SCRIPT.new()
	sw2.set("persist_layout", false)
	add_child(sw2)
	_ok(String(sw2.get("window_title")) == "设置",
			"★ 切回 zh_CN 构造 ⇒ 标题回到「设置」（实际「%s」）" % String(sw2.get("window_title")))
	sw2.queue_free()


## ③ 「语言」行 + 落盘 / 读盘 —— ⏸ **冻结期判据是反的：这行必须不存在**。
##
## ⚠️ **不调 `_pick_language()`** —— 它会 `reload_current_scene()`，把自检自己拆了。
##    这里只验「取词 → 落盘 → apply_saved 读回」这条链。
## ⚠️ 会写 `user://settings.cfg` ⇒ 先存快照、结尾**原样写回**（不能动玩家的偏好）。
##
## ⏸ 2026-10-11 英文版冻结（`EveText.LANGUAGE_ENABLED == false`）后，这段改成验三件事：
##    ① 设置窗**不建**语言行；② `apply_saved()` **忽略**存档里已存的语言、强制 zh_CN
##       （否则之前手滑切过 English 的玩家一进游戏还是半成品英文 —— 这条是硬伤）；
##    ③ 开关常量确实还在（⛔ 别手滑删掉，解冻要翻的就是它）。
##    解冻后（`true`）请把 ①② 改回正向判据（行要存在 / 存档语言要生效）。
func _t_language_switch() -> void:
	print("── ③ 语言行（⏸ 冻结期：应隐藏）+ 落盘 / 读盘 ──")
	var store = SETTINGS_SCRIPT.STORE
	var snap := store.load_all()
	var before_locale := T.current()

	# ⓪ 冻结开关还在，且是 false
	_ok(T.LANGUAGE_ENABLED == false,
			"⏸ 冻结开关 `EveText.LANGUAGE_ENABLED` 仍存在且为 false"
			+ "（解冻就翻这一个常量；实际 %s）" % str(T.LANGUAGE_ENABLED))

	# ① 设置窗里**没有**语言行（按按钮数组找，别按位置找）
	T.set_locale("zh_CN")
	var sw: Variant = SETTINGS_SCRIPT.new()
	sw.set("persist_layout", false)
	add_child(sw)
	var btns: Array = sw.get("_lang_btns")
	_ok(btns.size() == 0,
			"⏸ 冻结期设置窗**没有**「语言」行（按钮数 %d，应为 0）" % btns.size())
	sw.queue_free()

	# ② 冻结期：存档里就算存了 en，`apply_saved()` 也必须把它拉回 zh_CN
	T.save_locale("en")
	_ok(String(store.load_all().get("language", "")) == "en",
			"★ 落盘链路仍通（写进 settings.cfg 的 language=en）")
	T.set_locale("en")                       # 先拧到别处，再让 apply_saved 拉回来
	T.apply_saved()
	_ok(T.current() == T.DEFAULT_LOCALE,
			"⏸ 冻结期 apply_saved 忽略存档语言、强制 %s（实际 %s）"
					% [T.DEFAULT_LOCALE, T.current()])

	# ③ 存档里是空串 / 不认识的值时回落默认
	T.save_locale("")
	T.apply_saved()
	_ok(T.current() == T.DEFAULT_LOCALE,
			"★ 存档为空 ⇒ 回落默认 locale（%s）" % T.current())
	T.save_locale("de")
	T.apply_saved()
	_ok(T.current() == T.DEFAULT_LOCALE, "★ 不认识的 locale ⇒ 回落默认（%s）" % T.current())

	# 收尾：玩家的设置与运行态**原样还原**
	for k in snap.keys():
		store.save_one(k, snap[k])
	T.set_locale(before_locale)


## ⑤ 主菜单 UI 面（i18n 第 3 步）。
##
## ⛔ 这条防的是「**CSV 建好了，代码里还是硬编码中文**」的假接线 ——
##    判据不是「CSV 里有这条」，而是**用 en 真的取一遍**。
##
## ⚠️ 走 `MENU._mode_txt()` 等 **static** 取词函数：它们不碰实例状态，
##    ⛔ 别为了测这个去 `new()` 一个主菜单（会拉底图/音频/存档，重且不稳）。
##
## ★ 还有一条**覆盖率**：`MENU.STAT_KEYS` 里登记的每一条，在 en 下都必须
##    **真的有译文**（取词 == 中文源文 ⇒ 说明 CSV 没登记 ⇒ 英文版露中文）。
func _t_menu_wired() -> void:
	print("── ⑤ 主菜单 UI 面（en 下真的变英文）──")
	var before := T.current()

	var mode := {"id": "campaign", "name": "任务关卡", "meta": ""}
	var card := {"id": "guard_border", "name": "守卫边境", "code": "GUARD THE BORDER · 第 1 难度"}

	T.set_locale("zh_CN")
	_ok(MENU._mode_txt(mode, "name") == "任务关卡",
			"★ zh_CN：模式名逐字不变（实际「%s」）" % MENU._mode_txt(mode, "name"))
	_ok(MENU._card_txt(card, "name") == "守卫边境",
			"★ zh_CN：卡片名逐字不变（实际「%s」）" % MENU._card_txt(card, "name"))
	_ok(MENU._stat_txt("对手") == "对手",
			"★ zh_CN：stats 键逐字不变（实际「%s」）" % MENU._stat_txt("对手"))

	T.set_locale("en")
	_ok(MENU._mode_txt(mode, "name") == "Campaign",
			"★★ en：模式名真的变英文（实际「%s」）" % MENU._mode_txt(mode, "name"))
	_ok(MENU._card_txt(card, "name") == "Guard the Border",
			"★★ en：卡片名真的变英文（实际「%s」）" % MENU._card_txt(card, "name"))
	_ok(MENU._stat_txt("对手") == "Opponents",
			"★★ en：stats 键真的变英文（实际「%s」）" % MENU._stat_txt("对手"))
	_ok(MENU._stat_txt("15 回合") == "15 rounds",
			"★ en：stats 值真的变英文（实际「%s」）" % MENU._stat_txt("15 回合"))
	_ok(T.t("CARD_TODO", "待开发") == "Coming soon",
			"★ en：未开放按钮「待开发」⇒「Coming soon」（实际「%s」）"
			% T.t("CARD_TODO", "待开发"))
	# ⚠️ 文案里的 `%s` 要写成 `%%s`（否则被当成占位符 ⇒ "not enough arguments"）
	_ok(T.t("MENU_START", "▶　开始%s") % "Campaign" == "▶ Start Campaign",
			"★ en：「开始」按钮是整句带 %%s，不是拼出来的（实际「%s」）"
			% (T.t("MENU_START", "▶　开始%s") % "Campaign"))

	# ── ⛔⛔ 「任务关卡」副标题：拼好之后**不许再取词** ────────────────
	#    事故（2026-10-11）：渲染处拿已格式化的 meta 又过了一遍 `T.t()` ⇒
	#    `T.t("MODE_CAMPAIGN_META", "15 回合 · 共 3 个难度")` **命中** CSV，
	#    返回的是模板 ⇒ 界面显示裸「%d 回合 · 共 %d 个难度」。
	#    ⇒ 构造只许在 `_campaign_meta()`，渲染只许走 `_mode_meta()`（不取词）。
	T.set_locale("zh_CN")
	var meta_zh := MENU._campaign_meta()
	_ok(meta_zh == "15 回合 · 共 3 个难度",
			"★ zh_CN：副标题 = 15 回合 · 共 3 个难度（实际「%s」）" % meta_zh)
	_ok(not meta_zh.contains("%"),
			"⛔⛔ zh_CN：副标题里不许残留占位符 %%（实际「%s」）" % meta_zh)
	_ok(MENU._mode_meta({"meta": meta_zh}) == meta_zh,
			"⛔⛔ 渲染 `_mode_meta()` 原样返回、不再取词（实际「%s」）"
					% MENU._mode_meta({"meta": meta_zh}))
	T.set_locale("en")
	var meta_en := MENU._campaign_meta()
	_ok(not meta_en.contains("%") and meta_en.to_lower().contains("round"),
			"★★ en：副标题是英文且已代入数字（实际「%s」）" % meta_en)

	# ── 覆盖率 A：`STAT_KEYS` 登记的每一条都要真有英文 ──────────────
	var miss := PackedStringArray()
	var cn_keys := PackedStringArray()
	for cn in MENU.STAT_KEYS.keys():
		cn_keys.append(String(cn))
	for cn in cn_keys:
		var k := String(MENU.STAT_KEYS[cn])
		T.set_locale("en")
		var got_en := T.t(k, cn)
		T.set_locale("zh_CN")
		var got_zh := T.t(k, cn)
		if got_en == cn:
			miss.append("%s(en 没译文)" % k)
		elif got_zh != cn:
			miss.append("%s(zh≠源文:%s)" % [k, got_zh])
	_ok(miss.is_empty(),
			"★★ stats 表 %d 条在两个 locale 都对得上（缺/不符 %d：%s）"
			% [cn_keys.size(), miss.size(), ", ".join(miss)])

	# ── 覆盖率 B：**用真数据**拼出来的每个 key 都必须真在 CSV 里 ────
	#    ⛔ 这条专治「key 拼错（大小写 / 前缀）⇒ en 静默回落中文」——
	#       10-10 真实踩到：字段名没 `to_upper()` ⇒ `MODE_CAMPAIGN_name` 查不到，
	#       中文版**完全看不出来**，英文版整页还是中文。
	var miss_key := PackedStringArray()
	var n_key := 0
	var modes: Array = [{"id": "campaign"}, {"id": "credits"}]
	for m in MENU.EXTRA_MODES:
		modes.append({"id": String(m["id"])})
	for m in modes:
		for f in ["name", "meta"]:
			var k := MENU._mode_key(m, f)
			n_key += 1
			if T.lookup(k, "en") == k:
				miss_key.append(k)
	var cards: Array = []
	for r in TIERS.ROWS:
		cards.append({"id": String(r["id"])})
	for m in MENU.EXTRA_MODES:
		for c in m["cards"]:
			cards.append({"code": String(c["code"])})
	for c in cards:
		for f in ["name", "desc"]:
			var k2 := "CARD_%s_%s" % [MENU._card_key(c), f.to_upper()]
			n_key += 1
			if T.lookup(k2, "en") == k2:
				miss_key.append(k2)
	_ok(miss_key.is_empty(),
			"★★★ 真数据拼出的 %d 个 key 在 en 下都有译文（缺 %d：%s）"
			% [n_key, miss_key.size(), ", ".join(miss_key)])

	T.set_locale(before)


## ⑥ 设置窗 UI 面。
##
## 同 ⑤ 的口径：判据不是「CSV 里有这条」，而是**用真数据拼出来的 key 在 en 下真有译文**
## （⛔ 防「key 拼错 ⇒ 静默回落中文」—— 中文版完全看不出来）。
## 另外再**真的取一次词**：`_names()` 是 static ⇒ 不用 new 一扇窗就能验。
func _t_settings_wired() -> void:
	print("── ⑥ 设置窗 UI 面（en 下真的变英文）──")
	var before := T.current()
	var miss := PackedStringArray()
	var n := 0

	for it in SETTINGS_SCRIPT.VOLUME_KINDS:
		var k := "SET_VOL_%s" % String(it["k"]).to_upper()
		n += 1
		if T.lookup(k, "en") == k:
			miss.append(k)
	for it in SETTINGS_SCRIPT.BACKGROUNDS:
		var kb := "SET_BG_%s" % String(it["id"]).to_upper()
		n += 1
		if T.lookup(kb, "en") == kb:
			miss.append(kb)
	for it in SETTINGS_SCRIPT.MOODS:
		var km := "SET_MOOD_%d" % int(it["v"])
		n += 1
		if T.lookup(km, "en") == km:
			miss.append(km)
	# 直接写在代码里的那批（分区标题 / 开关 / 动作 / 提示 / 开关标记）
	for k in ["SET_GROUP_AUDIO", "SET_GROUP_DISPLAY", "SET_GROUP_INTERFACE",
			"SET_GROUP_RENDER", "SET_GROUP_BATTLE_UI", "SET_GROUP_ACTION",
			"SET_GROUP_RESET", "SET_MUTE", "SET_FONT_SCALE", "SET_TOGGLE_FOG",
			"SET_TOGGLE_RINGS", "SET_TOGGLE_BOARD", "TOGGLE_ON", "TOGGLE_OFF",
			"SET_ACT_CAMERA", "SET_ACT_RESTART", "SET_ACT_BACK_BATTLE",
			"SET_ACT_BACK_LOUNGE", "SET_PAUSE_RESUME", "SET_PAUSE_PAUSE",
			"SET_RESET_DONE", "SET_HINT_BATTLE", "SET_HINT_MENU_DESKTOP",
			"SET_HINT_MENU_MOBILE", "SET_HINT_LOUNGE", "RES_AUTO",
			"SET_UISCALE_AUTO", "SET_LANG", "SET_RES_NOTE",
			"WINDOW_COLLAPSE_TIP"]:
		n += 1
		if T.lookup(k, "en") == k:
			miss.append(k)
	_ok(miss.is_empty(),
			"★★★ 设置窗 %d 个 key 在 en 下都有译文（缺 %d：%s）"
			% [n, miss.size(), ", ".join(miss)])

	T.set_locale("en")
	var vols := SETTINGS_SCRIPT._names(SETTINGS_SCRIPT.VOLUME_KINDS, "SET_VOL", "k")
	_ok(String(vols[0]["name"]) == "Master",
			"★★ en：音量首档取词「Master」（实际「%s」）" % String(vols[0]["name"]))
	_ok(T.t("SET_MUTE", "静音") == "Mute",
			"★ en：静音 ⇒「Mute」（实际「%s」）" % T.t("SET_MUTE", "静音"))
	_ok(T.t("SET_ACT_RESTART", "重开一局") == "Restart run",
			"★ en：重开一局 ⇒「Restart run」（实际「%s」）"
			% T.t("SET_ACT_RESTART", "重开一局"))
	T.set_locale("en")
	var moods := SETTINGS_SCRIPT._names(SETTINGS_SCRIPT.MOODS, "SET_MOOD", "v")
	# ⛔ 这条专治「`String(int)` 炸」：`MOODS` 的 id 字段是 **int**，
	#    `_names()` 里写成 `String(d["v"])` 会在**开窗那一刻**抛
	#    `Invalid call 'String' constructor`（中文版同样中招，10-10 刚踩）。
	_ok(String(moods[0]["name"]) == "Clear" and String(moods[1]["name"]) == "Atmospheric",
			"★★ en：氛围两档取词（实际「%s」「%s」）"
			% [String(moods[0]["name"]), String(moods[1]["name"])])
	T.set_locale("zh_CN")
	var vols2 := SETTINGS_SCRIPT._names(SETTINGS_SCRIPT.VOLUME_KINDS, "SET_VOL", "k")
	_ok(String(vols2[0]["name"]) == "总音量",
			"★ zh_CN：音量首档逐字回「总音量」（实际「%s」）" % String(vols2[0]["name"]))
	T.set_locale(before)


## ⑦ 结算页 UI 面。
##
## ⚠️ 结算页的文案**没有静态取词函数**（它们散在 `_build_contents` / `show_result` 里），
##    所以这里只能做「key 覆盖率」+ 抽查三条真的取词。真接线由 `verify_run` 兜
##    （zh_CN 下逐字不变 ⇒ 592 条断言一条都没改）。
func _t_result_wired() -> void:
	print("── ⑦ 结算页 UI 面（en 下真的变英文）──")
	var before := T.current()
	var miss := PackedStringArray()
	var keys := ["RESULT_TITLE", "RESULT_WIN", "RESULT_LOSE", "RESULT_SUB",
			"RESULT_SUB_FMT", "RESULT_STAGE_SKIRMISH", "RESULT_KILL",
			"RESULT_SHIPS_0", "RESULT_SHIPS_N", "RESULT_ALIVE", "RESULT_XP",
			"RESULT_WRECK", "RESULT_WRECK_N", "RESULT_NONE", "RESULT_END",
			"RESULT_NEXT", "RESULT_AGAIN", "RESULT_SALVAGE_TITLE",
			"RESULT_SALVAGE_HINT", "RESULT_SALVAGE_CLOSE_TIP",
			"RESULT_SALVAGE_ROW", "RESULT_SALVAGE_BTN", "RESULT_SALVAGE_WARN",
			"RESULT_SALVAGE_EMPTY", "RESULT_SALVAGE_QUEUE", "RESULT_COIN",
			"RESULT_SALVAGE_ASK_TITLE", "RESULT_SALVAGE_ASK_OK",
			"RESULT_SALVAGE_ASK_CANCEL", "RESULT_ENDING_CLEARED",
			"RESULT_ENDING_BEACON"]
	for k in keys:
		if T.lookup(k, "en") == k:
			miss.append(k)
	_ok(miss.is_empty(),
			"★★★ 结算页 %d 个 key 在 en 下都有译文（缺 %d：%s）"
			% [keys.size(), miss.size(), ", ".join(miss)])

	T.set_locale("en")
	_ok(T.t("RESULT_WIN", "拦截成功") == "Interception Successful",
			"★ en：胜利标题 ⇒「Interception Successful」（实际「%s」）"
			% T.t("RESULT_WIN", "拦截成功"))
	_ok(T.t("RESULT_SALVAGE_WARN", "⚠ 不决定就作废（%d 艘）") % 3
					== "⚠ Deciding later forfeits them (3 ships)",
			"★ en：打捞警告行的 %%d 仍能填（实际「%s」）"
			% (T.t("RESULT_SALVAGE_WARN", "⚠ 不决定就作废（%d 艘）") % 3))
	T.set_locale("zh_CN")
	_ok(T.t("RESULT_WIN", "拦截成功") == "拦截成功",
			"★ zh_CN：胜利标题逐字不变（实际「%s」）" % T.t("RESULT_WIN", "拦截成功"))
	T.set_locale(before)


## ⑧ 商店 UI 面。
func _t_shop_wired() -> void:
	print("── ⑧ 商店 UI 面（en 下真的变英文）──")
	var before := T.current()
	var miss := PackedStringArray()
	var keys := ["SHOP_TITLE", "SHOP_COIN_UNIT", "SHOP_REFRESH", "SHOP_LEVELUP",
			"SHOP_LOCK", "SHOP_LOCKED", "SHOP_BOUGHT", "SHOP_SALVAGE",
			"SHOP_CARD_STAT", "SHOP_DEF_SHIELD", "SHOP_DEF_ARMOR",
			"SHOP_SALVAGE_HEAD", "SHOP_SALVAGE_HINT", "SHOP_SALVAGE_HEAD_N",
			"SHOP_WRECK_STAT", "SHOP_WRECK_BOOSTED", "SHOP_WRECK_DEFENSE",
			"SHOP_WRECK_ORDER", "SHOP_NEXT_NODE", "SHOP_REPAIRING",
			"SHOP_NEXT_NODE_SLOT", "SHOP_BENCH", "SHOP_SELL_HINT"]
	for k in keys:
		if T.lookup(k, "en") == k:
			miss.append(k)
	_ok(miss.is_empty(),
			"★★★ 商店 %d 个 key 在 en 下都有译文（缺 %d：%s）"
			% [keys.size(), miss.size(), ", ".join(miss)])

	# ★ 卡面那行是「整句带 4 个占位」—— 判据是**占位符数量不变**，
	#   否则英文版会静默丢掉一个参数（`%` 少一个就直接报错）。
	T.set_locale("en")
	var st := T.t("SHOP_CARD_STAT", "%s · %s\n攻 %d　%s %d")
	_ok(st.count("%s") == 3 and st.count("%d") == 2,
			"★★ en：卡面整句仍带 3 个 %%s + 2 个 %%d（实际「%s」）" % st)
	_ok(T.t("SHOP_TITLE", "商店") == "Shop",
			"★ en：商店标题 ⇒「Shop」（实际「%s」）" % T.t("SHOP_TITLE", "商店"))
	_ok(T.t("SHOP_BENCH", "备战席 %d / %d") % [3, 8] == "Bench 3 / 8",
			"★ en：备战席计数仍能填（实际「%s」）"
			% (T.t("SHOP_BENCH", "备战席 %d / %d") % [3, 8]))
	T.set_locale("zh_CN")
	_ok(T.t("SHOP_BENCH", "备战席 %d / %d") % [3, 8] == "备战席 3 / 8",
			"★ zh_CN：备战席计数逐字不变（实际「%s」）"
			% (T.t("SHOP_BENCH", "备战席 %d / %d") % [3, 8]))
	T.set_locale(before)


## ⑨ 舰船档案 UI 面。
func _t_dossier_wired() -> void:
	print("── ⑨ 舰船档案 UI 面（en 下真的变英文）──")
	var before := T.current()
	var miss := PackedStringArray()
	var keys := ["DOSSIER_TITLE", "DOSSIER_EMPTY_H", "DOSSIER_EMPTY_P",
			"DOSSIER_NONE", "DOSSIER_HP_SHIELD", "DOSSIER_HP_ARMOR",
			"DOSSIER_HP_HULL", "DOSSIER_ATTR_ATTACK", "DOSSIER_ATTR_INTERVAL",
			"DOSSIER_ATTR_RANGE", "DOSSIER_ATTR_SPEED", "DOSSIER_ATTR_SIG",
			"DOSSIER_ATTR_CLASS", "DOSSIER_RANGE", "DOSSIER_SPEED",
			"DOSSIER_ROLE_NONE", "DOSSIER_META", "DOSSIER_ROLE",
			"DOSSIER_LOGI", "DOSSIER_TRAIT_ACTIVE", "DOSSIER_TRAIT_AWAY"]
	for k in keys:
		if T.lookup(k, "en") == k:
			miss.append(k)
	_ok(miss.is_empty(),
			"★★★ 档案窗 %d 个 key 在 en 下都有译文（缺 %d：%s）"
			% [keys.size(), miss.size(), ", ".join(miss)])

	# ★★ 这三条是 EVE 官方名词（Shield / Armor / Hull）—— 不是本作自造词，
	#    意译会直接违反用户 2026-10-10 定的硬约束 ⇒ 逐字钉死。
	T.set_locale("en")
	_ok(T.t("DOSSIER_HP_SHIELD", "护盾") == "Shield",
			"★★ en：护盾 ⇒「Shield」（实际「%s」）" % T.t("DOSSIER_HP_SHIELD", "护盾"))
	_ok(T.t("DOSSIER_HP_ARMOR", "装甲") == "Armor",
			"★★ en：装甲 ⇒「Armor」（实际「%s」）" % T.t("DOSSIER_HP_ARMOR", "装甲"))
	_ok(T.t("DOSSIER_HP_HULL", "结构") == "Hull",
			"★★ en：结构 ⇒「Hull」（实际「%s」）" % T.t("DOSSIER_HP_HULL", "结构"))
	_ok(T.t("DOSSIER_ROLE", "定位　%s%s") % ["Attack", ""]
					== "Role　Attack",
			"★ en：定位行两个占位都能填（实际「%s」）"
			% (T.t("DOSSIER_ROLE", "定位　%s%s") % ["Attack", ""]))
	T.set_locale("zh_CN")
	_ok(T.t("DOSSIER_ROLE", "定位　%s%s") % ["攻击", "（后勤）"]
					== "定位　攻击（后勤）",
			"★ zh_CN：定位行逐字不变（实际「%s」）"
			% (T.t("DOSSIER_ROLE", "定位　%s%s") % ["攻击", "（后勤）"]))
	T.set_locale(before)


## ⑩ 斗地主牌桌 UI 面（最大的一块：94 条中文）。
##
## ⚠️ 覆盖率用「CSV 里所有 `DDZ_` / `CARD_TYPE_` 前缀的 key」扫一遍 ——
##    ⛔ 别手抄 key 清单：牌桌文案最密，手抄必漏，而且漏了**不报错**（静默回落中文）。
func _t_ddz_wired() -> void:
	print("── ⑩ 斗地主牌桌 UI 面（en 下真的变英文）──")
	var before := T.current()
	var miss := PackedStringArray()
	var n := 0
	for r in _read_csv():
		var k := String(r["key"])
		if not (k.begins_with("DDZ_") or k.begins_with("CARD_TYPE_")):
			continue
		n += 1
		if T.lookup(k, "en") == k:
			miss.append(k)
	_ok(miss.is_empty(),
			"★★★ 牌桌 %d 个 key 在 en 下都有译文（缺 %d：%s）"
			% [n, miss.size(), ", ".join(miss)])

	# ★★ 牌型名走**枚举 id** 拼 key（`R.TYPE_IDS`）—— 判据是「15 个牌型全覆盖」，
	#    少一个就说明 `TYPE_IDS` 与 `Type` 枚举**顺序对不齐**（那类 bug 中文版看不出来）。
	for i in RULES.TYPE_IDS.size():
		var cn := RULES.type_name(i)
		if T.lookup("CARD_TYPE_%s" % String(RULES.TYPE_IDS[i]), "en") \
				== "CARD_TYPE_%s" % String(RULES.TYPE_IDS[i]):
			miss.append("CARD_TYPE_%s" % String(RULES.TYPE_IDS[i]))
	_ok(miss.is_empty(), "★★ 15 个牌型 id 与 TYPE_IDS 对齐（缺 %d）" % miss.size())

	T.set_locale("en")
	_ok(RULES.type_name(1) == "Single",
			"★★ en：单 ⇒「Single」（实际「%s」）" % RULES.type_name(1))
	_ok(RULES.type_name(13) == "Bomb",
			"★★ en：炸弹 ⇒「Bomb」（实际「%s」）" % RULES.type_name(13))
	_ok(RULES.type_name(14) == "Rocket",
			"★★ en：王炸 ⇒「Rocket」（实际「%s」）" % RULES.type_name(14))
	_ok(T.t("DDZ_ROLE_LANDLORD", "地主") == "Landlord",
			"★ en：地主 ⇒「Landlord」（实际「%s」）" % T.t("DDZ_ROLE_LANDLORD", "地主"))
	_ok(T.t("DDZ_SEAT_1", "下家") == "Next",
			"★ en：下家 ⇒「Next」（实际「%s」）—— 方位由 SEAT_DIR 定，名字别反"
			% T.t("DDZ_SEAT_1", "下家"))
	_ok(T.t("DDZ_BTN_START", "开始游戏") == "Start Game",
			"★ en：开始游戏 ⇒「Start Game」（实际「%s」）"
			% T.t("DDZ_BTN_START", "开始游戏"))
	T.set_locale("zh_CN")
	_ok(RULES.type_name(1) == "单" and RULES.type_name(14) == "王炸",
			"★ zh_CN：牌型名逐字不变（实际「%s」「%s」）"
			% [RULES.type_name(1), RULES.type_name(14)])
	_ok(T.t("DDZ_SEAT_1", "下家") == "下家",
			"★ zh_CN：下家逐字不变（实际「%s」）" % T.t("DDZ_SEAT_1", "下家"))
	T.set_locale(before)


## ⑪ 战斗核心面（HUD / 命令条 / 战斗日志 / prep·battle 阶段）。
func _t_battle_wired() -> void:
	print("── ⑪ 战斗核心面（en 下真的变英文）──")
	var before := T.current()
	var miss := PackedStringArray()
	var n := 0
	for r in _read_csv():
		var k := String(r["key"])
		if not (k.begins_with("HUD_") or k.begins_with("LOG_")
				or k.begins_with("BAR_") or k.begins_with("PREP_")
				or k.begins_with("BATTLE_")):
			continue
		n += 1
		if T.lookup(k, "en") == k:
			miss.append(k)
	_ok(miss.is_empty(),
			"★★★ 战斗面 %d 个 key 在 en 下都有译文（缺 %d：%s）"
			% [n, miss.size(), ", ".join(miss)])

	# ★ 结束原因：`end_reason()` 返回**中文源文**（592 条断言的契约），
	#   `reason_txt()` 负责取词 ⇒ 判据是「源文不变 + 取词能变英文」。
	for cn in ["未部署", "时限耗尽", "我方全灭", "僵持收场", "敌方全灭"]:
		if not PHASE_BATTLE.REASON_KEYS.has(cn):
			miss.append("REASON:" + cn)
	_ok(miss.is_empty(), "★★ 五种结束原因都登记了 key（缺 %d）" % miss.size())
	_ok(PHASE_BATTLE.end_reason(true, 0, 0) == "未部署",
			"★★ zh_CN：未部署判定逐字不变（契约）（实际「%s」）"
			% PHASE_BATTLE.end_reason(true, 0, 0))
	T.set_locale("en")
	_ok(PHASE_BATTLE.reason_txt("未部署") == "Not Deployed",
			"★★ en：未部署 ⇒「Not Deployed」（实际「%s」）"
			% PHASE_BATTLE.reason_txt("未部署"))
	_ok(PHASE_BATTLE.reason_txt("敌方全灭") == "Enemy Wiped",
			"★★ en：敌方全灭 ⇒「Enemy Wiped」（实际「%s」）"
			% PHASE_BATTLE.reason_txt("敌方全灭"))
	_ok(T.t("BAR_START", "✦ 开战") == "✦ Engage",
			"★ en：开战按钮 ⇒「✦ Engage」（实际「%s」）" % T.t("BAR_START", "✦ 开战"))
	_ok(T.t("LOG_CAT_SALVAGE", "打捞") == "Salvage",
			"★ en：日志分类打捞 ⇒「Salvage」（实际「%s」）"
			% T.t("LOG_CAT_SALVAGE", "打捞"))
	T.set_locale("zh_CN")
	_ok(PHASE_BATTLE.reason_txt("未部署") == "未部署",
			"★ zh_CN：结束原因逐字不变（实际「%s」）"
			% PHASE_BATTLE.reason_txt("未部署"))
	T.set_locale(before)

	# ★ 命令条阶段名：`PHASE_NAMES`（源文）与 `PHASE_KEYS`（key）必须**等长**，
	#    错一位就是「准备阶段显示成结算」—— 那类 bug 只在切语言后才会被玩家看到。
	_ok(BAR_SCRIPT.PHASE_NAMES.size() == BAR_SCRIPT.PHASE_KEYS.size(),
			"★★ 命令条 PHASE_NAMES(%d) 与 PHASE_KEYS(%d) 等长"
			% [BAR_SCRIPT.PHASE_NAMES.size(), BAR_SCRIPT.PHASE_KEYS.size()])


## ④ 术语段：舰船 / 吨位 / 势力 / 武器 / 防御 / 定位。
##
## ⚠️⚠️ 这几条是**硬约束**（用户 2026-10-10 定）：
##     「舰船、羁绊一定要遵循 EVE 官方的翻译，意译在这个时候是绝对不行的」。
##
##     所以判据不是「CSV 里有这条」，而是**三方对拍**：
##       · 中文 ← 权威表（EveShipTable.ROWS / CLASS_NAMES_BY_COST / CIDS.*_LABEL）
##       · 英文 ← **官方英文原名**（EveShipAssetIndex.ROWS 的 name_en，
##                机生成自 ESI typeID ⇒ 人改不动 ⇒ 意译无处藏身）
##       · CSV  ← 上面两者的产物（tools/pipeline/gen_i18n_terms.py），必须逐字一致
##
##     ⛔ 这条防的正是历史上真实发生过的那次事故：交接的源 CSV 把
##        Cyclone / Hurricane 的中文名**对调**了 —— 而 EVE 官方恰恰是
##        `Cyclone = 飓风级` / `Hurricane = 暴风级`（与字面意思相反）。
##        只靠人眼永远发现不了；三方对拍一跑就红。
func _t_terms() -> void:
	print("── ④ 术语段：舰船 / 吨位 / 势力 / 武器 / 防御 / 定位 ──")
	var by_key := {}
	for r in _read_csv():
		by_key[String(r["key"])] = r

	# ── 舰船 ──────────────────────────────────────────────────
	var en_of := {}
	for a in ASSET.ROWS:
		en_of[String(a[0])] = String(a[2])
	var missing := PackedStringArray()
	var bad_zh := PackedStringArray()
	var bad_en := PackedStringArray()
	for row in SHIP_TABLE.ROWS:
		var sid := String(row[0])
		var k := "SHIP." + sid
		if not by_key.has(k):
			missing.append(sid)
			continue
		if String(by_key[k]["zh"]) != String(row[1]):
			bad_zh.append("%s(CSV=%s 表=%s)" % [sid, by_key[k]["zh"], row[1]])
		if not en_of.has(sid):
			bad_en.append("%s(资产索引查不到)" % sid)
		elif String(by_key[k]["en"]) != en_of[sid]:
			bad_en.append("%s(CSV=%s 官方=%s)" % [sid, by_key[k]["en"], en_of[sid]])
	_ok(missing.is_empty(),
			"★ %d 艘每艘都有 SHIP.<id> 键（缺 %d：%s）"
			% [SHIP_TABLE.ROWS.size(), missing.size(), ", ".join(missing)])
	_ok(bad_zh.is_empty(),
			"★ 舰船中文名与权威表逐字一致（不一致 %d：%s）"
			% [bad_zh.size(), ", ".join(bad_zh)])
	_ok(bad_en.is_empty(),
			"★★ 舰船英文名 == 官方原名（资产索引 name_en，⛔ 不许意译）（不一致 %d：%s）"
			% [bad_en.size(), ", ".join(bad_en)])

	# ── 吨位 / 势力 / 武器 / 防御 / 定位：中文必须等于代码里的表 ──
	var pairs := []      # [{key, cn, src}]
	for c in SHIP_TABLE.CLASS_NAMES_BY_COST.keys():
		pairs.append({"key": "CLASS." + str(int(c)),
			"cn": String(SHIP_TABLE.CLASS_NAMES_BY_COST[c]), "src": "CLASS_NAMES_BY_COST"})
	for cn in SHIP_TABLE.FACTION_INDEX.keys():
		var fid: StringName = StringName(CIDS.FACTION_FROM_CN.get(String(cn), &""))
		pairs.append({"key": "FACTION." + String(fid),
			"cn": String(cn), "src": "FACTION_INDEX"})
	for id in CIDS.WEAPON_LABEL.keys():
		pairs.append({"key": "WEAPON." + String(id),
			"cn": String(CIDS.WEAPON_LABEL[id]), "src": "CIDS.WEAPON_LABEL"})
	for id in CIDS.DEFENSE_LABEL.keys():
		pairs.append({"key": "DEFENSE." + String(id),
			"cn": String(CIDS.DEFENSE_LABEL[id]), "src": "CIDS.DEFENSE_LABEL"})
	for id in CIDS.ROLE_LABEL.keys():
		pairs.append({"key": "ROLE." + String(id),
			"cn": String(CIDS.ROLE_LABEL[id]), "src": "CIDS.ROLE_LABEL"})

	var bad := PackedStringArray()
	for p in pairs:
		var k := String(p["key"])
		if not by_key.has(k):
			bad.append("%s 缺键" % k)
		elif String(by_key[k]["zh"]) != String(p["cn"]):
			bad.append("%s(CSV=%s %s=%s)" % [k, by_key[k]["zh"], p["src"], p["cn"]])
	_ok(bad.is_empty(),
			"★ 吨位/势力/武器/防御/定位 %d 条：键齐全且中文 == 代码里的表（不一致 %d：%s）"
			% [pairs.size(), bad.size(), ", ".join(bad)])

	# ── 运行时真的取到词（不是"CSV 建好了但代码还硬编码"）──
	var before := T.current()
	T.set_locale("en")
	var d: Dictionary = SDB.by_id("condor")
	var ship: Variant = SDB.instantiate_by_id("condor", 0, 1)
	_ok(String(d.get("name", "")) == "Condor",
			"★★ en 下 by_id(\"condor\") 的名字 = 「Condor」（实际「%s」）" % d.get("name", ""))
	_ok(ship != null and ship.ship_name == "Condor",
			"★★ en 下实例的 ship_name 也跟着变（实际「%s」）"
			% (ship.ship_name if ship != null else "?"))
	var laser_ship: Variant = SDB.instantiate_by_id("punisher", 0, 2)
	_ok(ship != null and ship.weapon_label() == "Missile Launcher",
			"★ en 下武器显示名走 EVE 官方市场分组名（condor 导弹 ⇒「%s」）"
			% (ship.weapon_label() if ship != null else "?"))
	_ok(laser_ship != null and laser_ship.weapon_label() == "Energy Turret"
			and laser_ship.defense_label() == "Armor" and laser_ship.role_label() == "Defense",
			"★ en 下激光炮/甲抗/防御型 ⇒「%s / %s / %s」"
			% [laser_ship.weapon_label() if laser_ship != null else "?",
			   laser_ship.defense_label() if laser_ship != null else "?",
			   laser_ship.role_label() if laser_ship != null else "?"])
	T.set_locale("zh_CN")
	var d2: Dictionary = SDB.by_id("condor")
	_ok(String(d2.get("name", "")) == "小鹰级",
			"★ 切回 zh_CN ⇒ 逐字回到「小鹰级」（实际「%s」）" % d2.get("name", ""))
	# ⛔ 逻辑键**不许**被翻（否则羁绊静默失效）
	_ok(ship != null and String(ship.weapon_type) == "导弹",
			"★★ 武器的**逻辑键** weapon_type 仍是中文「导弹」（实际「%s」）"
			% (ship.weapon_type if ship != null else "?"))
	T.set_locale(before)
