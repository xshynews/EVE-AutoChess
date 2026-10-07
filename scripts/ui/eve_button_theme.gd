extends RefCounted
class_name EveButtonTheme

## ★ 字号缩放（2026-10-07）：⛔ 别直接调 `add_theme_font_size_override`，
## 一律走 `FONT.fs(node, 设计字号)` —— 它同时记住设计字号（供改滑块时就地重算）。
## ⚠️ 子类（`extends eve_window.gd` 的那 9 个）靠**继承**拿到这个常量，
##    它们自己再写一个会撞名（基类已有同名成员 ⇒ 子类编译失败，本工程踩过）。
const FONT := preload("res://scripts/ui/eve_font.gd")

## EVE 自走棋 —— 可替换按钮样式库
##
## 设计目标与 EveBackgroundLibrary 完全对称：
##   把「按钮长什么样」从 UI 代码里剥出来变成【一条数据】。
##   换皮肤 = 改一个 id / 加一条记录，不改任何 UI 构建逻辑。
##
## ── 为什么要做这一层 ──────────────────────────────────────────────
##
##   现在按钮样式是散在 eve_hud_root.gd / eve_combat_log.gd 里的
##   _style_button() 硬编码（颜色、边框、圆角、内边距全写死）。
##   这样的问题：
##     ① 想换一套视觉（比如做「艾玛金色调」主题）要改多处，容易漏；
##     ② 战斗日志的筛选按钮和底栏的姿态按钮应该长一样，但现在是两份代码；
##     ③ 设计师想调按钮观感，得改 .gd 文件 —— 不合理。
##
##   抽成数据表之后，改样式只动本文件，且天然一致。
##
## ── 状态构成 ──────────────────────────────────────────────────────
##
##   一个按钮有 5 个状态样式：normal / hover / pressed / disabled / focus。
##   Godot 的 Button 需要逐个 add_theme_stylebox_override。
##   本模块的 apply() 一次性把 5 个状态全设好，调用方不用关心细节。

## 一套按钮皮肤 = 一组颜色 + 一组几何参数
##
## ⚠️ 内部类名不能叫 Skin —— Godot 有同名原生类，会报
##    "Class 'Skin' hides a native class" 并导致整个脚本编译失败。
##    这类冲突不报行号，只报在文件级，排查时优先怀疑类名。
class ButtonSkin extends RefCounted:
	var id: String = ""
	var display_name: String = ""
	## 底色（4 个状态）
	var bg_normal: Color = Color(0.09, 0.12, 0.14, 0.85)
	var bg_hover: Color = Color(0.14, 0.19, 0.22, 0.92)
	var bg_pressed: Color = Color(0.18, 0.26, 0.29, 0.95)
	var bg_disabled: Color = Color(0.07, 0.09, 0.10, 0.60)
	## 边框色（4 个状态）
	var border_normal: Color = Color(0.22, 0.32, 0.34, 1.0)
	var border_hover: Color = Color(0.33, 0.89, 0.76, 1.0)
	var border_pressed: Color = Color(0.33, 0.89, 0.76, 1.0)
	var border_disabled: Color = Color(0.16, 0.20, 0.22, 1.0)
	## 文字色
	var text_normal: Color = Color(0.78, 0.85, 0.85, 1.0)
	var text_hover: Color = Color(0.33, 0.89, 0.76, 1.0)
	var text_pressed: Color = Color(0.33, 0.89, 0.76, 1.0)
	var text_disabled: Color = Color(0.42, 0.48, 0.49, 1.0)
	## 几何
	var border_width: int = 1
	var corner_radius: int = 0        ## 0 = 直角（用户明确要求直角）
	var pad_h: int = 10               ## 左右内边距
	var pad_v: int = 6                ## 上下内边距
	var font_size: int = 13
	## 选中态（toggle_mode = true 且 button_pressed）专用底色
	var bg_checked: Color = Color(0.18, 0.26, 0.29, 0.95)
	var note: String = ""


## ── 内置皮肤表 ────────────────────────────────────────────────────
##
## ⚠️ 风格铁律（用户明确要求，改样式前先读）：
##    半透明深灰面板 + 1px 细边框 + 直角 + 灰青文字。
##    禁止金属边框、禁止金色、禁止发光边。
##    —— 所以 corner_radius 一律 0，border_width 一律 1。
static func builtin_skins() -> Array[ButtonSkin]:
	var out: Array[ButtonSkin] = []

	# 默认皮肤：当前 HUD 正在用的那一套，抽出来作为基线
	var d := ButtonSkin.new()
	d.id = "default"
	d.display_name = "默认（灰青直角）"
	d.note = "现有 HUD 样式，抽出来作为基线；改这里等于改全局按钮观感"
	out.append(d)

	# 强调皮肤：边框更亮，用于「主要操作」按钮（如确认、开始战斗）
	var a := ButtonSkin.new()
	a.id = "accent"
	a.display_name = "强调（高对比边框）"
	a.bg_normal = Color(0.10, 0.16, 0.18, 0.90)
	a.bg_hover = Color(0.16, 0.25, 0.27, 0.95)
	a.border_normal = Color(0.33, 0.89, 0.76, 0.65)
	a.text_normal = Color(0.86, 0.94, 0.93, 1.0)
	a.note = "主要行动按钮；边框常态就带青"
	out.append(a)

	# 素净皮肤：无边框，用于密集排列的次级按钮（如战斗日志的分类页签）
	var p := ButtonSkin.new()
	p.id = "plain"
	p.display_name = "素净（无边框）"
	p.bg_normal = Color(0.08, 0.11, 0.12, 0.45)
	p.bg_hover = Color(0.13, 0.18, 0.20, 0.75)
	p.border_width = 0
	p.pad_h = 8
	p.note = "密集排布用；靠底色区分而不是边框"
	out.append(p)

	# ── V3 布局稿实装用的三套（2026-09-20）────────────────────────
	#
	# V3 稿定稿时把 UI 面积从 51.2% 压到 19.5%，按钮跟着瘦了一圈：
	#   常规 22px 高 / 11px 字 / 左右各 8px 内边距
	#   主按钮 26px 高 / 12px 字（顶条的「✦ 开战」）
	#   警告按钮（商店的「↻ 刷新」）用橙，因为它花钱
	# ⚠️ 高度不在这三套里 —— 由调用方 custom_minimum_size 给，
	#    这样同一套色能用在 22 / 26 / 30 三种高度上。

	# 常规
	var hud := ButtonSkin.new()
	hud.id = "hud"
	hud.display_name = "HUD 常规（V3 稿）"
	hud.bg_normal = Color(0.118, 0.157, 0.180, 0.85)
	hud.bg_hover = Color(0.16, 0.21, 0.24, 0.92)
	hud.bg_pressed = Color(0.20, 0.28, 0.31, 0.95)
	hud.bg_disabled = Color(0.086, 0.110, 0.125, 0.60)
	hud.border_normal = Color(0.42, 0.55, 0.60, 0.50)
	hud.border_hover = Color(0.55, 0.78, 0.82, 0.90)
	hud.border_pressed = Color(0.55, 0.78, 0.82, 1.00)
	hud.border_disabled = Color(0.42, 0.55, 0.60, 0.28)
	hud.text_normal = Color(0.70, 0.82, 0.85)
	hud.text_hover = Color(0.86, 0.94, 0.96)
	hud.text_pressed = Color(0.92, 0.97, 0.99)
	hud.text_disabled = Color(0.35, 0.43, 0.47)
	hud.pad_h = 8
	hud.pad_v = 2
	hud.font_size = 11
	hud.note = "V3 稿常规按钮；高度由调用方给 22"
	out.append(hud)

	# 主按钮（顶条「✦ 开战」）
	var hud_main := ButtonSkin.new()
	hud_main.id = "hud_main"
	hud_main.display_name = "HUD 主按钮（青底）"
	hud_main.bg_normal = Color(0.275, 0.455, 0.518, 0.62)
	hud_main.bg_hover = Color(0.345, 0.545, 0.610, 0.78)
	hud_main.bg_pressed = Color(0.400, 0.620, 0.685, 0.92)
	hud_main.border_normal = Color(0.549, 0.780, 0.820, 1.00)
	hud_main.border_hover = Color(0.700, 0.900, 0.940, 1.00)
	hud_main.border_pressed = Color(0.850, 0.960, 0.980, 1.00)
	hud_main.text_normal = Color(0.918, 0.969, 0.980)
	hud_main.text_hover = Color(1.0, 1.0, 1.0)
	hud_main.text_pressed = Color(1.0, 1.0, 1.0)
	hud_main.pad_h = 12
	hud_main.pad_v = 3
	hud_main.font_size = 12
	hud_main.note = "V3 稿主行动按钮；高度 26"
	out.append(hud_main)

	# 花钱按钮（商店「↻ 刷新」）
	var hud_warn := ButtonSkin.new()
	hud_warn.id = "hud_warn"
	hud_warn.display_name = "HUD 警示（橙 · 花钱操作）"
	hud_warn.bg_normal = Color(0.282, 0.188, 0.102, 0.70)
	hud_warn.bg_hover = Color(0.360, 0.240, 0.130, 0.85)
	hud_warn.bg_pressed = Color(0.440, 0.290, 0.155, 0.95)
	hud_warn.border_normal = Color(0.878, 0.522, 0.302, 0.70)
	hud_warn.border_hover = Color(1.00, 0.680, 0.450, 0.95)
	hud_warn.border_pressed = Color(1.00, 0.780, 0.560, 1.00)
	hud_warn.text_normal = Color(0.941, 0.769, 0.604)
	hud_warn.text_hover = Color(1.00, 0.870, 0.740)
	hud_warn.text_pressed = Color(1.00, 0.930, 0.850)
	hud_warn.pad_h = 8
	hud_warn.pad_v = 2
	hud_warn.font_size = 11
	hud_warn.note = "花钱的操作；高度 26"
	out.append(hud_warn)

	return out


static func available_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for s in builtin_skins():
		out.append(s.id)
	return out


static func find(id: String) -> ButtonSkin:
	for s in builtin_skins():
		if s.id == id:
			return s
	return null


## 把一套皮肤应用到一个按钮上 —— 这是本模块唯一的对外动作
##
## 调用方只需要：
##     EveButtonTheme.apply(btn, "accent")
## 不用关心 5 个状态、不用关心 StyleBox 怎么造。
static func apply(btn: Button, skin_id: String = "default") -> void:
	var s := find(skin_id)
	if s == null:
		push_warning("未知按钮皮肤 '%s'，回退 default（可用：%s）"
				% [skin_id, ", ".join(available_ids())])
		s = find("default")
	if s == null or btn == null:
		return

	# 文字色（4 态）
	btn.add_theme_color_override("font_color", s.text_normal)
	btn.add_theme_color_override("font_hover_color", s.text_hover)
	btn.add_theme_color_override("font_pressed_color", s.text_pressed)
	btn.add_theme_color_override("font_disabled_color", s.text_disabled)
	# 选中态文字（toggle 按钮用）
	btn.add_theme_color_override("font_focus_color", s.text_normal)
	FONT.fs(btn, s.font_size)

	# 5 个状态的样式盒
	btn.add_theme_stylebox_override("normal", _make_box(s, s.bg_normal, s.border_normal))
	btn.add_theme_stylebox_override("hover", _make_box(s, s.bg_hover, s.border_hover))
	btn.add_theme_stylebox_override("pressed", _make_box(s, s.bg_pressed, s.border_pressed))
	btn.add_theme_stylebox_override("disabled", _make_box(s, s.bg_disabled, s.border_disabled))
	# toggle 按钮「已选中但没被按住」时用的是 hover/pressed，
	# 但有些主题会去读 "hover_pressed"，这里一并设上避免露馅
	btn.add_theme_stylebox_override("hover_pressed",
			_make_box(s, s.bg_checked, s.border_pressed))
	btn.add_theme_stylebox_override("focus",
			_make_box(s, s.bg_normal, s.border_hover))


static func _make_box(s: ButtonSkin, bg: Color, border: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	if s.border_width > 0:
		box.border_color = border
		box.set_border_width_all(s.border_width)
	else:
		box.set_border_width_all(0)
	box.set_corner_radius_all(s.corner_radius)
	box.content_margin_left = s.pad_h
	box.content_margin_right = s.pad_h
	box.content_margin_top = s.pad_v
	box.content_margin_bottom = s.pad_v
	return box


## 从外部 JSON 加载皮肤（与背景库同款机制，便于美术改样式不改代码）
##
## JSON 格式：
##   { "skins": [ { "id": "amarr_gold", "display_name": "艾玛",
##       "bg_normal": [0.1,0.12,0.14,0.85], "border_normal": [0.72,0.58,0.30,1.0],
##       ... } ] }
## 颜色字段用 4 元数组；缺省字段沿用默认值。
static func load_from_json(json_path: String) -> Array[ButtonSkin]:
	var out: Array[ButtonSkin] = []
	if not FileAccess.file_exists(json_path):
		return out
	var text := FileAccess.get_file_as_string(json_path)
	if text.is_empty():
		return out
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return out
	var list = parsed.get("skins", [])
	if typeof(list) != TYPE_ARRAY:
		return out
	for raw in list:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var s := ButtonSkin.new()
		s.id = str(raw.get("id", ""))
		if s.id.is_empty():
			continue
		s.display_name = str(raw.get("display_name", s.id))
		s.note = str(raw.get("note", ""))
		for key in ["bg_normal", "bg_hover", "bg_pressed", "bg_disabled",
				"border_normal", "border_hover", "border_pressed", "border_disabled",
				"text_normal", "text_hover", "text_pressed", "text_disabled",
				"bg_checked"]:
			var v = raw.get(key, null)
			if typeof(v) == TYPE_ARRAY and v.size() >= 4:
				s.set(key, Color(float(v[0]), float(v[1]), float(v[2]), float(v[3])))
		for key in ["border_width", "corner_radius", "pad_h", "pad_v", "font_size"]:
			if raw.has(key):
				s.set(key, int(raw.get(key)))
		out.append(s)
	return out
