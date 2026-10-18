extends RefCounted
class_name EveMobileLayout

## 安卓线 · 移动端布局**唯一真源**（L1）。
##
## ══════════════════════════════════════════════════════════════════
##  这条线解决什么
## ══════════════════════════════════════════════════════════════════
##  桌面截图固定 1920×1080；真机是「约 2340×1080 + 安全区 + content_scale_factor」。
##  三者逻辑视口不同 ⇒ 桌面调好的坐标到手机上必然偏。
##  ⇒ 移动端**不再直接复用桌面坐标**，而是先问本模块要：
##      · 安全区（`safe_rect`）
##      · 逻辑视口（`logical_size`）
##      · 可用内容区（`content_rect`，= 安全区再留边）
##      · 面板宽度 / 触摸最小尺寸
##
##  ★ 本模块**不改桌面行为**：所有调用方都必须先过 `EveUiScale.is_mobile()`。
##    ⛔ 不要在桌面场景里读它 —— 桌面有自己那套 1920×1080 坐标。
##
##  ★ 为什么参数可覆盖：真机实测前，任何默认值都是猜的。L3 调参工具把结果写进
##    `user://mobile_layout.cfg`，本模块优先读它 ⇒ 不重新导包也能校准。
##
##  单位说明：
##    · `screen_*` / `safe_px`  = **物理像素**
##    · 其余 rect / size        = **逻辑像素**（= 场景里 Control 用的坐标）
##    · 换算系数 k = logical / screen
##      （`canvas_items + expand` + `content_scale_factor` 已经体现在 logical 里，
##        所以这里**只做比例换算**，⛔ 不要再乘一次 content_scale_factor）

const CFG_PATH := "user://mobile_layout.cfg"
const SECTION := "layout"
const BASE := Vector2(1920.0, 1080.0)

## 默认值（真机实测前先用这些；L3 会覆盖）
const DEFAULT_UI_SCALE := 1.0
const DEFAULT_PANEL_W_FRAC := 0.72
const DEFAULT_TOUCH_MIN := 44.0
## 内容区在安全区基础上再留的边（逻辑像素）
const DEFAULT_CONTENT_PAD := 12.0

static var _loaded := false
static var _ov: Dictionary = {}


# ══════════════════════════════════════════════════════════ 读数

static func screen_px() -> Vector2:
	var s := DisplayServer.screen_get_size()
	return Vector2(maxf(1.0, float(s.x)), maxf(1.0, float(s.y)))


static func logical_size(tree: SceneTree) -> Vector2:
	if tree == null or tree.root == null:
		return BASE
	var r := tree.root.get_visible_rect().size
	return Vector2(maxf(1.0, r.x), maxf(1.0, r.y))


## 安全区（逻辑像素）。优先用调参覆盖；否则由「物理安全区 × 换算系数」得到。
static func safe_rect(tree: SceneTree) -> Rect2:
	_load()
	var lv := logical_size(tree)
	if bool(_ov.get("safe_override", false)):
		var l := maxf(0.0, float(_ov.get("safe_left", 0.0)))
		var t := maxf(0.0, float(_ov.get("safe_top", 0.0)))
		var r := maxf(0.0, float(_ov.get("safe_right", 0.0)))
		var b := maxf(0.0, float(_ov.get("safe_bottom", 0.0)))
		return Rect2(l, t, maxf(1.0, lv.x - l - r), maxf(1.0, lv.y - t - b))
	var d := derive(screen_px(), DisplayServer.get_display_safe_area(), lv)
	return d["safe"]


## 安全区内的可用内容区（再留 `content_pad`）。
static func content_rect(tree: SceneTree) -> Rect2:
	var s := safe_rect(tree)
	var pad := maxf(0.0, float(_ov.get("content_pad", DEFAULT_CONTENT_PAD)))
	var r := s.grow(-pad)
	if r.size.x < 1.0 or r.size.y < 1.0:
		return s
	return r


## 把 1920×1080 设计稿等比塞进逻辑视口的系数（只用于「旧坐标迁移」，不是布局真源）。
static func fit_scale(tree: SceneTree) -> float:
	var lv := logical_size(tree)
	return minf(lv.x / BASE.x, lv.y / BASE.y)


static func ui_scale() -> float:
	_load()
	return clampf(float(_ov.get("ui_scale", DEFAULT_UI_SCALE)), 0.5, 3.0)


static func panel_w_frac() -> float:
	_load()
	return clampf(float(_ov.get("panel_w_frac", DEFAULT_PANEL_W_FRAC)), 0.3, 1.0)


static func touch_min() -> float:
	_load()
	return maxf(24.0, float(_ov.get("touch_min", DEFAULT_TOUCH_MIN)))


## 居中面板矩形（设置窗 / 联机面板用）：宽度取安全区的一个比例，垂直起点贴安全区顶。
static func panel_rect(tree: SceneTree, max_w: float = 1200.0,
		h: float = 0.0, frac: float = -1.0) -> Rect2:
	var s := safe_rect(tree)
	var f := frac if frac > 0.0 else panel_w_frac()
	var w := minf(max_w, s.size.x * f)
	var x := s.position.x + (s.size.x - w) * 0.5
	var hh := h if h > 0.0 else s.size.y
	return Rect2(x, s.position.y, w, minf(hh, s.size.y))


## 一次拿全，给调试覆盖层 / 验收 / L3 调参用。
static func snapshot(tree: SceneTree) -> Dictionary:
	var lv := logical_size(tree)
	var d := derive(screen_px(), DisplayServer.get_display_safe_area(), lv)
	return {
		"screen_px": screen_px(),
		"logical": lv,
		"safe": safe_rect(tree),
		"content": content_rect(tree),
		"insets": d["insets"],
		"px_per_logical": d["px_per_logical"],
		"fit_scale": fit_scale(tree),
		"ui_scale": ui_scale(),
		"panel_w_frac": panel_w_frac(),
		"touch_min": touch_min(),
	}


# ══════════════════════════════════════════════════════════ 纯换算（可无头断言）

## 物理安全区 → 逻辑安全区。**纯函数**：不读 DisplayServer，便于验收固定输入。
## `screen_px` 物理屏幕尺寸；`safe_px` 物理安全区；`logical` 逻辑视口尺寸。
static func derive(screen_px: Vector2, safe_px: Rect2i, logical: Vector2) -> Dictionary:
	var ss := Vector2(maxf(1.0, screen_px.x), maxf(1.0, screen_px.y))
	var lv := Vector2(maxf(1.0, logical.x), maxf(1.0, logical.y))
	var k := Vector2(lv.x / ss.x, lv.y / ss.y)
	var sr: Rect2
	if safe_px.size.x <= 0 or safe_px.size.y <= 0:
		sr = Rect2(Vector2.ZERO, lv)          # 设备不报安全区 ⇒ 视为全屏
	else:
		var pos := Vector2(safe_px.position) * k
		var size := Vector2(safe_px.size) * k
		var x0 := clampf(pos.x, 0.0, lv.x)
		var y0 := clampf(pos.y, 0.0, lv.y)
		var x1 := clampf(pos.x + size.x, 0.0, lv.x)
		var y1 := clampf(pos.y + size.y, 0.0, lv.y)
		sr = Rect2(x0, y0, maxf(1.0, x1 - x0), maxf(1.0, y1 - y0))
	return {
		"safe": sr,
		"insets": {
			"left": sr.position.x,
			"top": sr.position.y,
			"right": maxf(0.0, lv.x - (sr.position.x + sr.size.x)),
			"bottom": maxf(0.0, lv.y - (sr.position.y + sr.size.y)),
		},
		"px_per_logical": Vector2(ss.x / lv.x, ss.y / lv.y),
	}


# ══════════════════════════════════════════════════════════ 覆盖（L3 调参写这里）

static func overrides() -> Dictionary:
	_load()
	return _ov.duplicate()


## 写覆盖。只认白名单键，防止调参工具把乱七八糟的东西写进来。
static func save_overrides(d: Dictionary) -> void:
	var allow := ["ui_scale", "panel_w_frac", "touch_min", "content_pad",
			"safe_override", "safe_left", "safe_right", "safe_top", "safe_bottom"]
	var cf := ConfigFile.new()
	cf.load(CFG_PATH)                      # 保留未知键（向前兼容）
	for k in d.keys():
		if allow.has(String(k)):
			cf.set_value(SECTION, String(k), d[k])
	cf.save(CFG_PATH)
	invalidate()


static func clear_overrides() -> void:
	if FileAccess.file_exists(CFG_PATH):
		DirAccess.remove_absolute(CFG_PATH)
	invalidate()


static func invalidate() -> void:
	_loaded = false
	_ov = {}


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	_ov = {}
	var cf := ConfigFile.new()
	if cf.load(CFG_PATH) != OK:
		return
	for k in ["ui_scale", "panel_w_frac", "touch_min", "content_pad",
			"safe_left", "safe_right", "safe_top", "safe_bottom"]:
		if cf.has_section_key(SECTION, k):
			_ov[k] = float(cf.get_value(SECTION, k))
	if cf.has_section_key(SECTION, "safe_override"):
		_ov["safe_override"] = bool(cf.get_value(SECTION, "safe_override"))
