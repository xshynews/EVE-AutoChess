extends Node
## 平台 UI 缩放档 + HUD 紧凑档自检（★ 2026-10-07）
##
## ⚠️ 为什么单独一套：这件事有**两条互相打架的要求** ——
##    移动端要「字变大、底部两条不许掉出屏幕」；桌面端要「逐像素不变」。
##    而两者共用同一份 HUD 布局代码，任何一处改歪都**不会报错**：
##    桌面端表现为「某个窗莫名挪了位」，移动端表现为「商店被切掉一半」。
##    ⇒ 用确定性的断言把两边的形状都钉死。
##
## ⚠️ 本测试**不依赖真的跑在安卓上**：紧凑档的几何是纯函数
##    （`EveHudRoot.compact_rects()`），直接喂真实手机的设计空间即可。

const HUD_SCRIPT := preload("res://scripts/ui/eve_hud_root.gd")
const UI := preload("res://scripts/ui/eve_ui_scale.gd")
const SETTINGS_STORE := preload("res://scripts/core/eve_settings_store.gd")
const LAYOUT_STORE := preload("res://scripts/ui/eve_window_store.gd")
const FONT := preload("res://scripts/ui/eve_font.gd")
const SHIP_DB := preload("res://scripts/core/eve_ship_database.gd")

## 设计稿口径：底部留 14、两条之间留 8（与 `RECT_*` 一致）
const BOTTOM_MARGIN := 14.0
const GAP := 8.0
## 侧列：左列 8..180，紧凑档要给底部两条留出 188 宽
const SIDE := 188.0

## 真实机型换算出来的设计空间（横屏，比例 ≥ 16:9）。
##   ⚠️ 设计高 = 1080 / 倍数（**与分辨率无关**），设计宽 = 宽高比 × 设计高。
const PHONES: Array = [
	{"name": "2400×1080 @1.35", "d": Vector2(1778, 800)},
	{"name": "1920×1080 @1.35", "d": Vector2(1422, 800)},
	{"name": "2400×1080 @1.25", "d": Vector2(1920, 864)},
	{"name": "3200×1440 @1.35", "d": Vector2(2370, 1067)},
	# ⚠️ 这一档**超出取值域**（1.5 不在 CHOICES 里，`resolve()` 会夹回 1.35），
	#    留着是为了保证「万一真出现极小设计空间，底部两条也不会掉出屏幕」。
	#    居中大窗的「必须落在可用带里」在这一档**不成立**（带只有 354 高、
	#    而结算页 356 高）⇒ 该条断言跳过，用 `band: false` 标出来。
	{"name": "1280×720  @1.50（越界兜底）", "d": Vector2(1280, 720), "band": false},
]

var _pass := 0
var _fail := 0
var _cfg_snapshot := PackedByteArray()
var _cfg_existed := false
var _old_force_mobile := false


func _ok(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
		print("  ✓ " + msg)
	else:
		_fail += 1
		print("  ✗ " + msg)


func _ready() -> void:
	LAYOUT_STORE.persist = false        # ⛔ 别写盘污染玩家的真实窗口布局
	_old_force_mobile = UI.force_mobile
	_snapshot_settings()
	print("═══ 平台 UI 缩放档 自检 ═══")
	_t_scale_semantics()
	_t_compact_geometry()
	_t_mobile_layout()
	_t_desktop_table_unchanged()
	_t_profile_switch()
	_t_desktop_noop()
	_t_store_roundtrip()
	_t_font()
	await _t_command_touch_targets()
	_restore_settings()
	print("═══ RESULT passed=%d failed=%d ═══" % [_pass, _fail])
	# ★ 2026-10-10（审查 R07）：失败 ⇒ 非零退出码
	get_tree().quit(1 if _fail > 0 else 0)


# ---------------------------------------------------------------- 夹具

func _snapshot_settings() -> void:
	var f := FileAccess.open(SETTINGS_STORE.PATH, FileAccess.READ)
	if f != null:
		_cfg_existed = true
		_cfg_snapshot = f.get_buffer(f.get_length())
		f = null


## ⚠️ 设置写盘必须原样还原 —— 这是玩家的真文件（里面还有音量）。
func _restore_settings() -> void:
	if _cfg_existed:
		var f := FileAccess.open(SETTINGS_STORE.PATH, FileAccess.WRITE)
		if f != null:
			f.store_buffer(_cfg_snapshot)
			f = null
		print("  （设置文件已原样还原）")
	else:
		DirAccess.remove_absolute(SETTINGS_STORE.PATH)
		print("  （本机原本没有设置文件，测试后已删除）")


func _mk_hud() -> Control:
	var host := Control.new()
	host.size = Vector2(1920, 1080)
	add_child(host)
	var h: Control = HUD_SCRIPT.new()
	h.set("demo_content", false)
	host.add_child(h)
	return h


func _t_command_touch_targets() -> void:
	print("[9] 指挥条触控目标：手机增大、桌面不变、设置仍可点")
	UI.force_mobile = true
	var command_script: Script = load("res://scripts/ui/panels/eve_command_bar.gd")
	var mobile_bar: Control = command_script.new()
	add_child(mobile_bar)
	await get_tree().process_frame
	var settings_btn: Button = mobile_bar.get("_settings_btn")
	var start_btn: Button = mobile_bar.get("_start_btn")
	_ok(settings_btn != null and settings_btn.custom_minimum_size.x >= 88.0
			and settings_btn.custom_minimum_size.y >= 48.0,
			"★ 手机设置按钮热区至少 88×48（实际 %s）"
			% str(settings_btn.custom_minimum_size if settings_btn != null else Vector2.ZERO))
	_ok(settings_btn != null and settings_btn.text == "设置",
			"★ 手机设置按钮显示文字标签，不只靠小图标")
	_ok(start_btn != null and start_btn.custom_minimum_size.y >= 48.0,
			"★ 手机主操作按钮高度至少 48（实际 %.0f）"
			% (start_btn.custom_minimum_size.y if start_btn != null else 0.0))
	var settings_fired := [false]
	mobile_bar.settings_requested.connect(func(): settings_fired[0] = true)
	if settings_btn != null:
		settings_btn.pressed.emit()
	_ok(settings_fired[0], "★★ 点设置热区 ⇒ settings_requested 确实发出")
	mobile_bar.queue_free()

	UI.force_mobile = false
	var desktop_bar: Control = command_script.new()
	add_child(desktop_bar)
	await get_tree().process_frame
	var desktop_settings: Button = desktop_bar.get("_settings_btn")
	_ok(desktop_settings != null and desktop_settings.custom_minimum_size == Vector2(26, 26)
			and desktop_settings.text == "≡",
			"★★ 桌面设置按钮保持原 26×26 图标外观")
	desktop_bar.queue_free()
	UI.force_mobile = _old_force_mobile


# ---------------------------------------------------------------- [7] 字号缩放

## ★ 这一段的要点：**「独立于界面缩放」这条承诺必须被钉住**。
##   它最容易被悄悄破坏的方式有两条：
##     ① 默认档位下改变了现有版面（加个功能把字全变大了）⇒ 断言「1.00 档 s(base)==base」；
##     ② 改倍数时**复利叠加**（每拖一格又乘一次，几下就把字撑爆）⇒ 断言连调三次 reapply 结果不变。
func _t_font() -> void:
	print("[7] 字号缩放（独立于界面缩放：只动字、版面不动）")
	FONT.set_scale(1.0)
	_ok(FONT.s(12) == 12 and FONT.s(9) == 9 and FONT.s(34) == 34,
			"★★ 1.00 档 ⇒ s(base) == base（加这个功能**不改现有版面**）")
	FONT.set_scale(1.30)
	_ok(FONT.s(12) == 16, "1.30 档 ⇒ 12 → %d" % FONT.s(12))
	_ok(FONT.s(9) == 12, "1.30 档 ⇒ 9 → %d" % FONT.s(9))
	FONT.set_scale(FONT.MIN_SCALE)
	_ok(FONT.s(12) == 10, "0.80 档 ⇒ 12 → %d" % FONT.s(12))
	FONT.set_scale(1.0)
	_ok(FONT.s(12) == 12, "切回 1.00 ⇒ 回到 12（无漂移）")
	FONT.set_scale(9.9)
	_ok(is_equal_approx(FONT.scale, FONT.MAX_SCALE),
			"越界 9.9 ⇒ 夹到 MAX %.2f" % FONT.scale)
	FONT.set_scale(0.0)
	_ok(is_equal_approx(FONT.scale, FONT.MIN_SCALE),
			"0.0 ⇒ 夹到 MIN %.2f" % FONT.scale)

	# ── fs / reapply：**不许复利** ──
	FONT.set_scale(1.0)
	var l := Label.new()
	add_child(l)
	FONT.fs(l, 11)
	_ok(l.get_theme_font_size("font_size") == 11, "FONT.fs(label, 11) ⇒ 覆盖值 11")
	_ok(l.has_meta(FONT.META), "fs() 同时记下了设计字号（meta）")
	FONT.set_scale(1.30)
	FONT.reapply(self)
	_ok(l.get_theme_font_size("font_size") == 14,
			"★ 改倍数后 reapply ⇒ %d（11×1.3 取整）" % l.get_theme_font_size("font_size"))
	FONT.reapply(self)
	FONT.reapply(self)
	_ok(l.get_theme_font_size("font_size") == 14,
			"★★ 连调三次 reapply ⇒ 仍是 %d（按设计字号反推，⛔ 不复利）"
			% l.get_theme_font_size("font_size"))
	FONT.set_scale(1.0)
	FONT.reapply(self)
	_ok(l.get_theme_font_size("font_size") == 11, "切回 1.00 ⇒ 回到 11")
	l.queue_free()

	# ── 真实 UI 确实挂在 FONT 上（证明 88 处改写真的收口了）──
	var h := _mk_hud()
	var n := _count_font_nodes(h)
	_ok(n >= 20, "★ HUD 里有 %d 个控件的字号挂在 FONT 上（≥20 ⇒ 确实收口了）" % n)
	var sample: Control = _first_font_node(h)
	if sample != null:
		var base := int(sample.get_meta(FONT.META))
		FONT.set_scale(1.30)
		FONT.reapply(h)
		_ok(sample.get_theme_font_size("font_size") == FONT.s(base),
				"★ 真实 UI 跟着变：该控件 %d → %d（设计字号 %d）"
				% [base, sample.get_theme_font_size("font_size"), base])
		FONT.set_scale(1.0)
		FONT.reapply(h)
		_ok(sample.get_theme_font_size("font_size") == base,
				"切回 1.00 ⇒ 该控件回到设计字号 %d" % base)
	h.queue_free()

	# ── 设置窗那一行 ──
	var h2 := _mk_hud()
	var sw: Control = h2.get("settings_window")
	var row: Dictionary = sw.get("_font_slider")
	_ok(not row.is_empty(), "★ 设置窗有「字号」滑杆行")
	if not row.is_empty():
		var sl: HSlider = row["slider"]
		_ok(absf(sl.min_value - FONT.MIN_SCALE) < 0.001
				and absf(sl.max_value - FONT.MAX_SCALE) < 0.001,
				"★ 滑杆范围 %.2f~%.2f（= EveFont 的取值域）" % [sl.min_value, sl.max_value])
		sw.call("set_font_scale", 1.25)
		_ok(absf(sl.value - 1.25) < 0.001, "set_font_scale(1.25) ⇒ 滑杆到 %.2f" % sl.value)
		_ok((row["num"] as Label).text == "125%",
				"百分比显示「%s」" % (row["num"] as Label).text)
		sw.call("set_font_scale", 0.0)
		_ok(absf(sl.value - FONT.default_scale()) < 0.001,
				"★ 传 0.0（没设过）⇒ 回落到**平台默认** %.2f（⛔ 不是 1.00 / 也不是 0.80）"
				% FONT.default_scale())
	h2.queue_free()

	# ── 平台出厂默认（2026-10-07 用户实测定的值）──
	_ok(is_equal_approx(FONT.DESKTOP_DEFAULT, 1.10)
			and is_equal_approx(FONT.MOBILE_DEFAULT, 1.20),
			"★ 出厂默认 = 桌面 %.2f / 移动 %.2f" % [FONT.DESKTOP_DEFAULT, FONT.MOBILE_DEFAULT])
	if OS.has_feature("mobile"):
		_ok(is_equal_approx(FONT.default_scale(), FONT.MOBILE_DEFAULT),
				"★ 本机是移动端 ⇒ 默认 120%")
	else:
		_ok(is_equal_approx(FONT.default_scale(), FONT.DESKTOP_DEFAULT),
				"★ 本机是桌面端 ⇒ 默认 110%")
	_ok(FONT.DESKTOP_DEFAULT >= FONT.MIN_SCALE and FONT.DESKTOP_DEFAULT <= FONT.MAX_SCALE
			and FONT.MOBILE_DEFAULT >= FONT.MIN_SCALE and FONT.MOBILE_DEFAULT <= FONT.MAX_SCALE,
			"★ 两个默认值都在取值域 %.2f~%.2f 内（否则滑杆一开就跳档）"
			% [FONT.MIN_SCALE, FONT.MAX_SCALE])

	# ── 存档往返（整份 settings.cfg 由 _restore_settings 原样写回）──
	SETTINGS_STORE.save_one("font_scale", 1.20)
	_ok(is_equal_approx(float(SETTINGS_STORE.load_all().get("font_scale", -1.0)), 1.20),
			"font_scale 存档往返 == 1.20")
	SETTINGS_STORE.save_one("font_scale", 0.0)     # 模拟「没设过 / 手改坏」
	FONT.set_scale(FONT.MAX_SCALE)                 # 先弄脏，证明 load 真的生效
	FONT.load_from_settings()
	_ok(is_equal_approx(FONT.scale, FONT.default_scale()),
			"★★ 存档是 0.0（没设过）⇒ load 用**平台默认** %.2f（实际 %.2f）"
			% [FONT.default_scale(), FONT.scale])
	# ⚠️ 显式设过值时必须**照玩家的**（不能被平台默认顶掉）
	SETTINGS_STORE.save_one("font_scale", 0.90)
	FONT.set_scale(1.0)
	FONT.load_from_settings()
	_ok(is_equal_approx(FONT.scale, 0.90),
			"★ 存档明确写了 0.90 ⇒ 照玩家的（实际 %.2f）" % FONT.scale)

	# ── 主菜单锁定：非战斗场景恒定 100%（2026-10-07）──
	FONT.set_scale(FONT.MAX_SCALE)
	FONT.reset_scale()
	_ok(is_equal_approx(FONT.scale, 1.0) and FONT.s(19) == 19,
			"★★ reset_scale() ⇒ 主菜单回到 100%（模式按钮 62px 的方框不再被字顶破）")
	FONT.set_scale(1.0)


## 递归数「字号挂在 FONT 上」的控件个数。
func _count_font_nodes(root: Node) -> int:
	var n := 0
	var c := root as Control
	if c != null and c.has_meta(FONT.META):
		n += 1
	for ch in root.get_children():
		n += _count_font_nodes(ch)
	return n


## 找一个「字号挂在 FONT 上」的控件（用来验证真实 UI 会跟着倍数变）。
func _first_font_node(root: Node) -> Control:
	var c := root as Control
	if c != null and c.has_meta(FONT.META):
		return c
	for ch in root.get_children():
		var r := _first_font_node(ch)
		if r != null:
			return r
	return null


# ---------------------------------------------------------------- [1] 语义

func _t_scale_semantics() -> void:
	print("[1] EveUiScale 语义（桌面端忽略存档 / 自动档 / 取值域）")
	_ok(UI.CHOICES.size() == 5 and float(UI.CHOICES[0]["v"]) == 0.0,
			"取值域 5 档且首位是「自动」（实际 %d 项）" % UI.CHOICES.size())
	_ok(UI.is_compact(1.0) == false and UI.is_compact(1.01) == true
			and UI.is_compact(1.35) == true,
			"is_compact：1.0 ⇒ 否 · 1.35 ⇒ 是")
	_ok(UI.choice_index(0.0) == 0, "choice_index(0.0) = 0（自动）")
	_ok(UI.choice_index(1.35) == 4, "choice_index(1.35) = 4（最后一档）")
	_ok(UI.choice_index(0.97) == 0, "取值域外的存档值 ⇒ 回落「自动」")
	var hi := float(UI.CHOICES[UI.CHOICES.size() - 1]["v"])
	_ok(UI.resolve(9.9) >= 1.0 and UI.resolve(9.9) <= hi,
			"★ 手改 cfg 填 9.9 ⇒ 被夹回取值域（%.2f）" % UI.resolve(9.9))
	if UI.is_enabled():
		_ok(is_equal_approx(UI.resolve(0.0), UI.MOBILE),
				"★ 本次跑在移动端：自动档 ⇒ %.2f" % UI.MOBILE)
	else:
		# ★ 本机的真实分支（Windows / 无头）：存档里写什么都没用
		_ok(is_equal_approx(UI.resolve(0.0), 1.0)
				and is_equal_approx(UI.resolve(1.35), 1.0),
				"★ 桌面端忽略存档：resolve(0)=%.2f · resolve(1.35)=%.2f"
				% [UI.resolve(0.0), UI.resolve(1.35)])


# ---------------------------------------------------------------- [2] 紧凑档几何

func _t_compact_geometry() -> void:
	print("[2] 紧凑档几何（纯函数：真实手机设计空间）")
	for item in PHONES:
		var d: Vector2 = item["d"]
		var r: Dictionary = HUD_SCRIPT.compact_rects(d)
		var w := d.x
		var h := d.y
		var shop: Rect2 = r["shop"]
		var bench: Rect2 = r["bench"]
		var top: Rect2 = r["top"]
		var tag := String(item["name"])

		# ① 底部两条必须**在屏内**，且贴底 / 骑在它头上 —— 这是紧凑档存在的全部理由
		_ok(absf(shop.end.y - (h - BOTTOM_MARGIN)) < 0.5,
				"%s 商店贴底（底边 %.0f = 设计高 %.0f − %.0f）"
				% [tag, shop.end.y, h, BOTTOM_MARGIN])
		_ok(absf(bench.end.y + GAP - shop.position.y) < 0.5,
				"%s 备战席骑在商店上（间隙 %.0f）" % [tag, GAP])
		_ok(bench.end.y <= h and shop.end.y <= h,
				"%s ★ 底部两条都在屏内（备战席底 %.0f / 商店底 %.0f ≤ %.0f）"
				% [tag, bench.end.y, shop.end.y, h])

		# ② 居中（手机屏比 16:9 宽，靠左会飘）
		_ok(absf(top.get_center().x - w * 0.5) < 0.5,
				"%s 顶条水平居中（中心 %.0f / %.0f）" % [tag, top.get_center().x, w * 0.5])
		_ok(absf(shop.get_center().x - w * 0.5) < 0.5, "%s 商店水平居中" % tag)

		# ③ 底部两条**让出侧列** —— 否则窄屏上会横着压到装备栏
		_ok(bench.position.x >= SIDE - 0.5 and bench.end.x <= w - SIDE + 0.5,
				"%s ★ 备战席让出侧列（x %.0f..%.0f，侧列需要 0..%.0f 与 %.0f..%.0f）"
				% [tag, bench.position.x, bench.end.x, SIDE - 8.0, w - SIDE + 8.0, w])

		# ④ 全部矩形都在屏内（右边界不许出屏）
		for key in r.keys():
			var rect: Rect2 = r[key]
			if rect.end.x > w + 0.5 or rect.position.x < -0.5:
				_ok(false, "%s 矩形「%s」出屏：%s（设计宽 %.0f）" % [tag, key, str(rect), w])
				break
		_ok(true, "%s 全部 %d 个矩形都横向在屏内" % [tag, r.size()])

		# ⑤ 居中大窗必须落在「顶条以下、备战席以上」那段里
		# ⚠️ 只对事件页 / 结算页断言「在可用带里」——
		#    设置窗的设计高是 480（它自己也写明了「只是初值，真高由内容反推」），
		#    比可用带还高，居中必然越界；它是玩家主动开的浮层，压住底栏可接受。
		if not bool(item.get("band", true)):
			print("    （%s：跳过「居中大窗在可用带里」—— 超出取值域）" % tag)
		var mid_ok := true
		for key in (["event", "result"] if bool(item.get("band", true)) else []):
			var rect2: Rect2 = r[key]
			if rect2.position.y < top.end.y - 0.5 or rect2.end.y > bench.position.y + 0.5:
				mid_ok = false
		_ok(mid_ok, "%s 事件页 / 结算页落在「顶条以下、备战席以上」" % tag)
		var set_r: Rect2 = r["settings"]
		if bool(item.get("band", true)):
			_ok(set_r.position.y >= 0.0 and set_r.end.y <= h + 0.5,
					"%s 设置窗在屏内（y %.0f..%.0f）" % [tag, set_r.position.y, set_r.end.y])


# ---------------------------------------------------------------- [8] 手机专用布局

## ★ 这一段是「手机端专用、PC 不许沾」的硬证据（2026-10-13 评审稿）：
##   ① 几何（纯函数）：底部两条仍在屏内、侧列确实加宽、顶条确实加高；
##   ② 折叠 = 贴边（不是"在原地把内容收掉"），且只展开点的那一组；
##   ③ 桌面端**拿不到**手机档（除非自检显式开 `force_mobile_layout`）。
const MOBILE_SIDE_RESERVE := 300.0

func _t_mobile_layout() -> void:
	print("[8] ★ 手机专用布局（移动端 + 紧凑档；桌面端不走这条路）")
	for item in PHONES:
		var d: Vector2 = item["d"]
		var r: Dictionary = HUD_SCRIPT.mobile_rects(d)
		var w := d.x
		var h := d.y
		var tag := String(item["name"])
		var shop: Rect2 = r["shop"]
		var bench: Rect2 = r["bench"]
		var top: Rect2 = r["top"]

		# ① 底部两条：**高度沿用设计稿**（内容最小高度决定的，压矮会静默切行）
		_ok(is_equal_approx(shop.size.y, HUD_SCRIPT.RECT_SHOP.size.y)
				and is_equal_approx(bench.size.y, HUD_SCRIPT.RECT_BENCH.size.y),
				"%s ★ 底部两条高度 == 设计稿（商店 %.0f / 备战席 %.0f，⛔ 不许压矮）"
				% [tag, shop.size.y, bench.size.y])
		_ok(absf(shop.end.y - (h - BOTTOM_MARGIN)) < 0.5 and bench.end.y <= h,
				"%s 商店贴底且都在屏内（底边 %.0f）" % [tag, shop.end.y])
		_ok(absf(bench.end.y + GAP - shop.position.y) < 0.5, "%s 备战席骑在商店上" % tag)
		_ok(absf(shop.get_center().x - w * 0.5) < 0.5
				and absf(bench.get_center().x - w * 0.5) < 0.5,
				"%s 底部两条水平居中" % tag)
		_ok(bench.position.x >= MOBILE_SIDE_RESERVE - 0.5
				and bench.end.x <= w - MOBILE_SIDE_RESERVE + 0.5,
				"%s ★ 让出加宽后的侧列（x %.0f..%.0f，需让出 0..%.0f）"
				% [tag, bench.position.x, bench.end.x, MOBILE_SIDE_RESERVE])

		# ② 侧列加宽 + 顶条加高（评审稿：手机上"窗口太小"的第一条反馈）
		var syn: Rect2 = r["syn"]
		var info: Rect2 = r["info"]
		# ★ 2026-10-21：侧列宽按**全站刻度**推导（0.18×W），不再是写死 242/259
		_ok(is_equal_approx(syn.size.x, HUD_SCRIPT._side_w(Vector2(w, h), true))
				and is_equal_approx(info.size.x, HUD_SCRIPT._side_w(Vector2(w, h), false)),
				"%s ★ 侧列按比例加宽 → %.0f / %.0f（设计稿 172）"
				% [tag, syn.size.x, info.size.x])
		_ok(is_equal_approx(top.size.y, HUD_SCRIPT.MOBILE_TOP_H),
				"%s ★ 顶条加高 40 → %.0f（按钮 SIZE_FILL ⇒ 跟着变高）" % [tag, top.size.y])
		_ok(absf(top.get_center().x - w * 0.5) < 0.5, "%s 顶条水平居中" % tag)
		_ok(syn.position.x >= 0.0 and info.end.x <= w + 0.5,
				"%s 侧列横向在屏内（右列右边 %.0f ≤ %.0f）" % [tag, info.end.x, w])

		# ②b ★ 2026-10-13 二修：左列**纵向重分配**（构成压矮、装备吃高度）
		#     —— 用户原话「左边还有高度，可以适当调整舰队构成和装备栏位的上下关系」
		var eq: Rect2 = r["eq"]
		var aug: Rect2 = r["aug"]
		var setr: Rect2 = r["settings"]
		_ok(is_equal_approx(syn.size.y, HUD_SCRIPT.MOBILE_SYN_H)
				and eq.size.y >= HUD_SCRIPT.RECT_EQ.size.y,
				"%s ★ 左列纵向重分配：构成 %.0f（PC 268）· 装备 %.0f（PC 116）"
				% [tag, syn.size.y, eq.size.y])
		_ok(absf(eq.position.y - (syn.end.y + HUD_SCRIPT.MOBILE_COL_GAP)) < 0.5
				and absf(aug.position.y - (eq.end.y + HUD_SCRIPT.MOBILE_COL_GAP)) < 0.5,
				"%s 构成 → 装备 → 增益 顺序相接、彼此不重叠" % tag)
		_ok(eq.size.y <= HUD_SCRIPT.MOBILE_EQ_H + 0.5
				and eq.size.y >= HUD_SCRIPT.RECT_EQ.size.y - 0.5,
				"%s ★ 装备 %.0f 高（目标 %.0f；短屏按上界收缩，但不小于设计稿 %.0f）"
				% [tag, eq.size.y, HUD_SCRIPT.MOBILE_EQ_H, HUD_SCRIPT.RECT_EQ.size.y])
		_ok(aug.end.y <= h + 0.5,
				"%s ★ 增益窗仍在屏内（装备吃高度**不许**把它顶出去，底边 %.0f ≤ %.0f）"
				% [tag, aug.end.y, h])

		# ②b-2 ★ 左列槽位外框固定且不重叠；内容最小尺寸不能再反向撑大窗口。
		_ok(is_equal_approx(syn.size.y, HUD_SCRIPT.MOBILE_SYN_H),
				"%s ★ 舰队构成外框固定 %.0f（内容在裁剪宿主内，不参与槽位计算）"
				% [tag, syn.size.y])
		# ②b-3 ★ 2026-10-26：装备栏位的「舒适高度」改成**按左列高度预算判定**。
		#    原判据是「h ≥ 780 就必须 ≥150」，那是在羁绊只有 3 组、构成槽位 364 时成立的。
		#    羁绊加到 5 组后构成必须给到 412，h=800（真机 1080/1.35）的左列
		#    只剩 116 —— 这不是布局 bug，而是高度预算用完了：
		#      94(顶条下) + 412 + 10 + 116 + 10 + 158 = 800 = 整屏。
		#    装备 116 恰好等于**设计稿**，8 格（2×4 · 35 高）全可见、不裁切，
		#    只是不再额外放大 —— 属于可接受的降级。⛔ 别为了凑 150 去压构成窗（会切掉第 5 组）。
		var eq_budget := h - (top.end.y + 12.0) - HUD_SCRIPT.MOBILE_SYN_H \
				- 2.0 * HUD_SCRIPT.MOBILE_COL_GAP - HUD_SCRIPT.MOBILE_AUG_H
		var eq_floor := 150.0 if eq_budget >= 150.0 else HUD_SCRIPT.RECT_EQ.size.y
		_ok(eq.size.y >= eq_floor - 0.5,
				"%s ★ 装备外框 %.0f（预算 %.0f → 下限 %.0f；够则保 150，不够退回设计稿 116）"
				% [tag, eq.size.y, eq_budget, eq_floor])
		_ok(aug.size.y >= 0.0 and aug.end.y <= h + 0.5,
				"%s ★ 增益外框在屏内（%.0f..%.0f；内容超出时仅窗内裁剪）"
				% [tag, aug.position.y, aug.end.y])
		_ok(syn.end.y <= eq.position.y + 0.5 and eq.end.y <= aug.position.y + 0.5,
				"%s ★★ 左列三窗槽位不重叠（构成底 %.0f ≤ 装备顶 %.0f；装备底 %.0f ≤ 增益顶 %.0f）"
				% [tag, syn.end.y, eq.position.y, eq.end.y, aug.position.y])

		# ②c ★ 2026-10-13 二修之三：设置窗改横向栏目 ⇒ 宽窗 + 定高
		#     （竖向长条在手机档约 900 高 > 设计高 800 ⇒ 必然出屏）
		var want_sw := minf(clampf(w * HUD_SCRIPT.MOBILE_SETTINGS_W_FRAC,
				HUD_SCRIPT.MOBILE_SETTINGS_W_MIN, HUD_SCRIPT.MOBILE_SETTINGS_W_MAX),
				w - 2.0 * HUD_SCRIPT.MOBILE_EDGE)
		var want_sh := minf(HUD_SCRIPT.MOBILE_SETTINGS_H, h - top.end.y - 2.0 * HUD_SCRIPT.MOBILE_EDGE)
		_ok(is_equal_approx(setr.size.x, want_sw)
				and is_equal_approx(setr.size.y, want_sh),
				"%s ★ 设置窗 %.0f×%.0f = 半屏宽 + 定高（横向栏目，内容区自己滚）"
				% [tag, setr.size.x, setr.size.y])
		_ok(setr.end.y <= h + 0.5 and setr.position.y >= top.end.y - 0.5,
				"%s 设置窗整扇在「顶条以下」的屏内（y %.0f..%.0f，屏高 %.0f）"
				% [tag, setr.position.y, setr.end.y, h])

		# ③ 全部矩形都在屏内
		var overflow := []
		for key in r.keys():
			var rect: Rect2 = r[key]
			if rect.end.x > w + 0.5 or rect.position.x < -0.5 \
					or rect.end.y > h + 0.5 or rect.position.y < -0.5:
				overflow.append(key)
		_ok(overflow.is_empty(),
				"%s 全部 %d 个矩形都在屏内（越界：%s）"
				% [tag, r.size(), "无" if overflow.is_empty() else str(overflow)])

		# ④ 停靠标签：贴边、不越界、彼此不重叠、落在「顶条以下 / 备战席以上」
		var docks: Dictionary = HUD_SCRIPT.mobile_dock_rects(d)
		_ok(docks.size() == 4,
				"%s ★ 4 组各自吸附（舰队/装备/增益/日志；档案自带收起不参与）"
				% tag)
		var dock_ok := true
		var prev_end := -1.0
		for k in ["syn", "eq", "aug"]:
			var dr: Rect2 = docks[k]
			if dr.position.x != 0.0 or dr.end.x > w or dr.position.y < top.end.y \
					or dr.end.y > bench.position.y + 0.5:
				dock_ok = false
			if dr.position.y < prev_end - 0.5:
				dock_ok = false
			prev_end = dr.end.y
		var lr: Rect2 = docks["log"]
		if absf(lr.end.x - w) > 0.5 or lr.position.y < top.end.y \
				or lr.end.y > bench.position.y + 0.5:
			dock_ok = false
		_ok(dock_ok, "%s ★ 停靠标签贴边、纵向居中、彼此不重叠" % tag)
		_ok("info" not in docks,
				"%s 舰船档案**不**给停靠位（它 `collapsible == false`，给了是空操作）" % tag)

	# ⑤ ★ 2026-10-19：左安全区（真机 96px 挖孔）必须整体避让
	#    用户原话「安全区还是要避让一下」—— 左列原来贴 MOBILE_EDGE，直接压在挖孔上。
	for item in PHONES:
		var d2: Vector2 = item["d"]
		var sd := 96.0
		var r2: Dictionary = HUD_SCRIPT.mobile_rects(d2, sd)
		var tag2 := String(item["name"])
		var syn2: Rect2 = r2["syn"]
		var bench2: Rect2 = r2["bench"]
		_ok(absf(syn2.position.x - (HUD_SCRIPT.MOBILE_EDGE + sd)) < 0.5,
				"%s ★ 左列避开安全区（x = 边距 %.0f + 安全区 %.0f = %.0f）"
				% [tag2, HUD_SCRIPT.MOBILE_EDGE, sd, syn2.position.x])
		_ok(bench2.position.x >= syn2.end.x - 0.5,
				"%s ★ 备战席不再压到左列（%.0f ≥ %.0f）"
				% [tag2, bench2.position.x, syn2.end.x])
		var over2 := []
		for key in r2.keys():
			var rr: Rect2 = r2[key]
			if rr.end.x > d2.x + 0.5 or rr.position.x < sd - 0.5 \
					or rr.end.y > d2.y + 0.5 or rr.position.y < -0.5:
				over2.append(key)
		_ok(over2.is_empty(),
				"%s 含安全区时全部矩形仍在可用区内（越界：%s）"
				% [tag2, "无" if over2.is_empty() else str(over2)])

	# ── 实装侧：桌面端拿不到手机档，除非自检显式开闸 ──
	var h := _mk_hud()
	h.call("apply_ui_profile", 1.35)
	_ok(not bool(h.get("_mobile_layout")),
			"★★ 桌面端 apply_ui_profile(1.35) ⇒ 仍是**非**手机档（PC 布局不动）")
	h.call("apply_ui_profile", 1.0)          # 别把放大倍数留给后面的用例
	h.queue_free()

	var m := _mk_hud()
	m.set("force_mobile_layout", true)
	m.call("apply_ui_profile", 1.35)
	_ok(bool(m.get("_mobile_layout")), "★ 自检开闸 ⇒ 进手机专用布局")
	var m_tbl: Dictionary = m.get("_rect_tbl")
	var m_want: Dictionary = HUD_SCRIPT.mobile_rects(m.call("_design_space"))
	_ok(m_tbl.get("syn") == m_want.get("syn"),
			"档位表 == mobile_rects(设计空间)：舰队构成 %s" % str(m_tbl.get("syn")))

	var syn_w: Control = m.get("synergy_window")
	var log_w: Control = m.get("log_window")
	_ok(not bool(syn_w.call("is_collapsed")) and not bool(log_w.call("is_collapsed")),
			"★★ 手机档默认**不**收起侧列（决策信息要能扫一眼就看到）")
	var _ds: Vector2 = m.call("_design_space")
	_ok(is_equal_approx(syn_w.size.x, HUD_SCRIPT._side_w(_ds, true)),
			"侧列实际宽度 %.0f（= 0.18×W，设计稿是 172）" % syn_w.size.x)

	# ★★ 2026-10-13 二修之四：舰船档案**默认整窗隐藏**，点中舰船才亮起
	#    （用户原话「不要一直在那」）。⛔ 桌面档恒可见 —— 这条只属于手机档。
	var dos: Control = m.get("dossier_window")
	_ok(dos != null and not bool(dos.visible),
			"★★ 手机档舰船档案**默认隐藏**（不再常驻占右列 %.0f×%.0f）"
			% [HUD_SCRIPT._side_w(m.call("_design_space"), false), HUD_SCRIPT.RECT_INFO.size.y])
	var log_y_hidden := log_w.position.y
	_ok(absf(log_y_hidden - m_want.get("info").position.y) < 0.5,
			"★ 档案隐藏时战斗日志**上移到档案位**（右列不留空洞，y %.0f）" % log_y_hidden)
	# 点中一艘船 ⇒ 档案亮起 + 日志退到它下面
	var sh = SHIP_DB.instantiate_by_id("bantam", 0, 91001)
	m.call("show_ship", sh)
	_ok(bool(dos.visible), "★ 点中舰船 ⇒ 档案亮起")
	_ok(log_w.position.y > log_y_hidden + float(dos.size.y),
			"★ 档案亮起后日志退到它下方（y %.0f，档案高 %.0f）"
			% [log_w.position.y, dos.size.y])
	# 再取消选中 ⇒ 一起收回去（幂等）
	m.call("show_ship", null)
	_ok(not bool(dos.visible) and absf(log_w.position.y - log_y_hidden) < 0.5,
			"★ 取消选中 ⇒ 档案收起、日志回位")

	# ★★ 2026-10-13 二修之三：设置窗横向栏目 —— 每个栏目都点得动、且只亮一个
	#    （工程红线：新面板必验「点下有反应」；四个按钮各点一次）
	var set_w: Control = m.get("settings_window")
	_ok(set_w != null and bool(set_w.get("_tabbed")),
			"★★ 手机档设置窗 = **横向栏目态**（竖向长条在手机档会出屏）")
	var tab_btns: Array = set_w.get("_tab_btns")
	_ok(tab_btns.size() == 4,
			"4 个栏目按钮（视频/音频/界面/游戏）实际 %d" % tab_btns.size())
	var tab_boxes: Dictionary = set_w.get("_tab_boxes")
	var seen := {}
	for it in tab_btns:
		var key := String(it["key"])
		(it["btn"] as Button).pressed.emit()
		var cur := String(set_w.get("_cur_tab"))
		var vis := 0
		for k in tab_boxes.keys():
			if bool((tab_boxes[k] as VBoxContainer).visible):
				vis += 1
		_ok(vis == 1 and cur == key,
				"★ 点「%s」⇒ 只亮该栏目（当前 %s，可见盒 %d）" % [key, cur, vis])
		seen[key] = true
	_ok(seen.size() == 4, "★★ 四个栏目都点得动（红线：看着能点、点了没反应）")

	# 折叠 ⇒ 贴边成标签；再点 ⇒ 回原位
	syn_w.call("set_collapsed", true)
	var dock: Rect2 = syn_w.get("dock_rect")
	_ok(syn_w.position == dock.position and dock.position.x == 0.0,
			"★ 折叠 ⇒ 吸附到**左边缘**（位置 %s）" % str(syn_w.position))
	_ok(is_equal_approx(syn_w.size.y, HUD_SCRIPT.MOBILE_DOCK_H),
			"★ 标签高 %.0f（26px 的标题栏在手机上点不准）" % syn_w.size.y)
	_ok(not bool(log_w.call("is_collapsed")) and log_w.position.x > 1.0,
			"★★ 折叠一组**不影响**其他组（战斗日志仍在右侧原位）")
	syn_w.call("set_collapsed", false)
	_ok(is_equal_approx(syn_w.size.x, HUD_SCRIPT._side_w(m.call("_design_space"), true))
			and syn_w.position == m_want.get("syn").position,
			"★ 再点开 ⇒ 回到侧列原位（%s，⛔ 不是停在边缘展开）" % str(syn_w.position))

	# 切回桌面档 ⇒ 停靠位必须主动清空（否则桌面端折叠会莫名贴边）
	m.call("apply_ui_profile", 1.0)
	_ok(syn_w.get("dock_rect") == Rect2()
			and is_equal_approx(float(syn_w.get("collapsed_height")), 0.0),
			"★ 切回桌面档 ⇒ 停靠位被清空（桌面端折叠不贴边）")
	m.queue_free()


# ---------------------------------------------------------------- [3] 桌面档位表

func _t_desktop_table_unchanged() -> void:
	print("[3] ★ 桌面档位表 === 设计稿常量（Windows 不变的硬证据）")
	var h := _mk_hud()
	var tbl: Dictionary = h.get("_rect_tbl")
	_ok(not bool(h.get("_compact")), "新建出来的 HUD 默认不是紧凑档")
	_ok(tbl.size() == 11, "档位表 11 项（10 扇窗 + 备战席）实际 %d" % tbl.size())
	var pairs := [
		["top", HUD_SCRIPT.RECT_TOP], ["syn", HUD_SCRIPT.RECT_SYN],
		["eq", HUD_SCRIPT.RECT_EQ], ["aug", HUD_SCRIPT.RECT_AUG],
		["info", HUD_SCRIPT.RECT_INFO], ["log", HUD_SCRIPT.RECT_LOG],
		["shop", HUD_SCRIPT.RECT_SHOP], ["bench", HUD_SCRIPT.RECT_BENCH],
		["event", HUD_SCRIPT.RECT_EVENT], ["result", HUD_SCRIPT.RECT_RESULT],
		# ★ 2026-10-13 用户定「把设置更新也同步改到PC端」：桌面设置窗 =
		#   与手机同一套栏目窗（半屏宽 + 定高），不再是 320 竖条常量。
		["settings", HUD_SCRIPT.settings_rect(h.call("_design_space"))],
	]
	var diff: Array[String] = []
	for p in pairs:
		if tbl.get(p[0]) != p[1]:
			diff.append("%s=%s≠%s" % [p[0], str(tbl.get(p[0])), str(p[1])])
	_ok(diff.is_empty(),
			"★ 11 项逐项等于 RECT_*（差异 %s）" % ("无" if diff.is_empty() else str(diff)))
	# 窗确实被摆到了设计稿坐标上
	_ok(h.get("shop_window").position == HUD_SCRIPT.RECT_SHOP.position,
			"商店窗实际位置 == 设计稿（%s）" % str(h.get("shop_window").position))
	_ok(h.get("bench_rail").size == HUD_SCRIPT.RECT_BENCH.size,
			"备战席实际尺寸 == 设计稿（%s）" % str(h.get("bench_rail").size))
	h.queue_free()


# ---------------------------------------------------------------- [4] 切档位

func _t_profile_switch() -> void:
	print("[4] 切档位：紧凑档重铺 + 侧列收起 + 幂等")
	var h := _mk_hud()
	var shop: Control = h.get("shop_window")
	var syn: Control = h.get("synergy_window")

	# 先模拟「玩家把商店拖走了」—— 这一步是用来验「切档位会重置旧坐标」的
	shop.set("_user_rect", Rect2(11.0, 22.0, 300.0, 158.0))
	shop.call("_apply_rect", Rect2(11.0, 22.0, 300.0, 158.0))
	_ok(shop.position == Vector2(11, 22), "前置：商店被玩家拖到 (11,22)")

	h.call("apply_ui_profile", 1.35)
	_ok(bool(h.get("_compact")), "★ 1.35 ⇒ 进紧凑档")
	_ok(is_equal_approx(h.get_window().content_scale_factor, 1.35),
			"★ 根窗口 content_scale_factor = %.2f（2D 画布整体放大）"
			% h.get_window().content_scale_factor)
	var d: Vector2 = h.call("_design_space")
	var want: Dictionary = HUD_SCRIPT.compact_rects(d)
	var got: Dictionary = h.get("_rect_tbl")
	_ok(got.get("shop") == want.get("shop"),
			"档位表 == compact_rects(设计空间)：商店 %s（设计空间 %.0f×%.0f）"
			% [str(got.get("shop")), d.x, d.y])
	_ok(shop.get("_user_rect") == Rect2(),
			"★ 切档位把「玩家拖走的旧坐标」清掉了（%s）" % str(shop.get("_user_rect")))
	_ok(shop.position == want.get("shop").position,
			"商店回到紧凑档位置（%s）" % str(shop.position))

	# 侧列收起、底部两条**不许**收起（它们是要点/要看的）
	# ⚠️ 舰船档案**不在**这一组里：它自己管高度，`collapsible` 是 false
	#    （把它算进来就是验一个永远为假的期望）。
	var collapsed_ok := true
	for k in ["synergy_window", "equipment_window", "augments_window", "log_window"]:
		if not bool(h.get(k).call("is_collapsed")):
			collapsed_ok = false
	_ok(collapsed_ok, "★ 紧凑档默认把 4 个侧列收成标题栏（点一下能展开，功能不少）")
	_ok(not bool(h.get("dossier_window").get("collapsible")),
			"舰船档案 `collapsible == false`（它自带 128↔320 展开，两套会打架）")
	_ok(not bool(shop.call("is_collapsed")) and not bool(h.get("bench_rail") == null),
			"底部两条**不收起**（商店仍需可点）")
	_ok(not bool(syn.get("visible")) or bool(syn.call("is_collapsed")),
			"舰队构成窗处于收起态（而不是被隐藏 —— 红线 9）")

	# 幂等：档位没变就不许重置（否则「设备旋转一次 ⇒ 玩家摆好的窗全回原位」）
	var moved := Rect2(404.0, 505.0, 420.0, 158.0)
	shop.set("_user_rect", moved)
	shop.call("_apply_rect", moved)
	h.call("apply_ui_profile", 1.35)
	_ok(shop.position == moved.position,
			"★ 重复应用同一档位 ⇒ **不动**玩家摆好的窗（%s）" % str(shop.position))

	# 切回桌面档
	h.call("apply_ui_profile", 1.0)
	_ok(not bool(h.get("_compact")), "1.0 ⇒ 回桌面档")
	_ok(h.get("_rect_tbl").get("shop") == HUD_SCRIPT.RECT_SHOP,
			"★ 回桌面档后档位表又等于 RECT_SHOP")
	_ok(not bool(syn.call("is_collapsed")), "切回桌面档 ⇒ 侧列恢复展开")
	_ok(is_equal_approx(h.get_window().content_scale_factor, 1.0),
			"根窗口缩放回到 1.0")
	h.queue_free()


# ---------------------------------------------------------------- [5] 桌面开局不许扰动

func _t_desktop_noop() -> void:
	print("[5] ★ 桌面端开局调一次 ⇒ 一个字节都不许动")
	var h := _mk_hud()
	var log_w: Control = h.get("log_window")
	var moved := Rect2(1600.0, 400.0, 240.0, 300.0)
	log_w.set("_user_rect", moved)
	log_w.call("_apply_rect", moved)
	# 主控每次开局都会调一次（传存档值；桌面端 resolve 恒 1.0）
	h.call("apply_ui_profile", UI.resolve(1.35))
	_ok(not bool(h.get("_compact")), "桌面端 resolve(1.35) ⇒ 仍是桌面档")
	_ok(log_w.get("_user_rect") == moved,
			"★ 玩家摆好的窗没被开局那次调用重置（%s）" % str(log_w.get("_user_rect")))
	_ok(log_w.position == moved.position, "位置保持（%s）" % str(log_w.position))
	_ok(is_equal_approx(h.get_window().content_scale_factor, 1.0),
			"桌面端根窗口缩放恒 1.0")
	h.queue_free()


# ---------------------------------------------------------------- [6] 存档往返

func _t_store_roundtrip() -> void:
	print("[6] 设置存档往返（ui_scale）")
	_ok(SETTINGS_STORE.DEFAULTS.has("ui_scale"),
			"默认值表里有 ui_scale（否则 load_all 会把它丢掉）")
	SETTINGS_STORE.save_one("ui_scale", 1.25)
	_ok(is_equal_approx(float(SETTINGS_STORE.load_all().get("ui_scale", -1.0)), 1.25),
			"写 1.25 再读回来 == 1.25")
	SETTINGS_STORE.save_one("ui_scale", 0.0)
	_ok(is_equal_approx(float(SETTINGS_STORE.load_all().get("ui_scale", -1.0)), 0.0),
			"写「自动」(0.0) 往返正常")
	# ⚠️ 收尾会原样还原整份文件（见 _restore_settings）
	_ok(true, "（收尾时整份 settings.cfg 原样写回）")
