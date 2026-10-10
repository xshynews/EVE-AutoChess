extends RefCounted
class_name EveResolution

## EVE 自走棋 —— **窗口分辨率档**唯一真相源（★ 2026-10-07）
##
## ══════════════════════════════════════════════════════════════════
##  它解决什么
## ══════════════════════════════════════════════════════════════════
##  玩家反馈「要能调整分辨率」。工程原本写死 1920×1080（`project.godot` 的
##  `viewport_width/height` + `stretch/mode=canvas_items`），窗口能拖但没有任何
##  档位可选，小屏用户只能手动拖边框。
##
## ── 为什么档位表长这样 ────────────────────────────────────────────
##  **照抄用户 2026-10-07 给的截图**（13 档，从上到下就是设置窗里的顺序）。
##  图里最高是 `2560×1440` 并标了「推荐」；用户同时要求「最高 4K」
##  ⇒ 在**顶部补** `3840×2160`，其余 13 档一字不改、顺序不变。
##
## ── ⚠️ 「推荐」≠ 默认值 ──────────────────────────────────────────
##  图里标「推荐」的是 2560×1440，但**默认档不是它** ——
##  在一台 1366×768 的笔记本上默认 2560×1440 会直接顶出屏幕。
##  ⇒ 默认（存档 = 空串）走 `default_index()`：**按屏幕可用区挑能放下的最大档**。
##    设置窗里那一档的高亮表示「当前生效的分辨率」，不是「你选过它」。
##
## ── ⚠️ 三条边界 ──────────────────────────────────────────────────
##  ① **headless 不应用**：自检跑在无头模式下，viewport 尺寸是钉死的
##     1920×1920（工程红线）—— 真去 `win.size = ...` 会把所有几何断言带歪。
##  ② **移动端不应用**：安卓是全屏，窗口尺寸没有意义（也没有可选的余地）。
##  ③ 分辨率是**根窗口**属性、跨场景一直留着 ⇒ 和 `EveUiScale` 一样，
##     不能只在一个场景里设，三个场景的 `_ready` 都要表态（都走 `apply_from_settings`）。
##
## ── 「最高 4K」是怎么成立的 ──────────────────────────────────────
##  `canvas_items` + `aspect=expand` ⇒ 2D 画布按 min 比例等比缩放，
##  4K（3840×2160）正好是 1920×1080 的 2 倍 ⇒ 设计空间仍是我们排好的
##  1920×1080，UI 一像素不歪，而 3D 战场跑在原生 4K 上。
##  **非 16:9 的档**（4:3 / 16:10）会让设计空间变大 ⇒ 内容要居中，
##  见 `EveLayout.origin()`。

## 设计基准 = `project.godot` 的 viewport 尺寸。⛔ 别在这里改成别的值 ——
## 整套 HUD / 主菜单 / 牌桌的绝对坐标都是按它排的。
const BASE := Vector2i(1920, 1080)

## 存档里表示「自动」的值（= 跟随屏幕，由 `default_index()` 算）。
const AUTO := ""

## ★ 2026-10-10 「自适应」档在设置窗里的显示名。
##
## ⚠️ 它就是上面那个 `AUTO` 哨兵 —— 之前只有内部语义（存档为空串时生效），
##    设置窗里**没有入口** ⇒ 玩家一旦选过任何一档就再也回不到"自适应"。
##    现在把它做成分辨率块里的**第一颗按钮**（`_res_btns[0]`）。
## ⚠️ 「自适应」= 每次应用（场景启动 / 玩家选它）时**按当前屏幕可用区重算**，
##    所以换台机器、换显示器（再进任意场景）都会重新挑最合适的一档。
const AUTO_LABEL := "自适应"

## 可选档位。**顺序 = 设置窗里的显示顺序**（用户给的图，从上到下）。
## ⚠️ 表增删不受限，但存档用的是 `key`（字符串）不是下标 ——
##    工程惯例：写进代码/存档的「位置」先问「这列表会增删吗」⇒ 用 id 找。
const CHOICES: Array = [
	{"key": "3840x2160", "w": 3840, "h": 2160},
	{"key": "2560x1440", "w": 2560, "h": 1440, "recommend": true},
	{"key": "2048x1152", "w": 2048, "h": 1152},
	{"key": "1920x1440", "w": 1920, "h": 1440},
	{"key": "1920x1200", "w": 1920, "h": 1200},
	{"key": "1920x1080", "w": 1920, "h": 1080},
	{"key": "1856x1392", "w": 1856, "h": 1392},
	{"key": "1792x1344", "w": 1792, "h": 1344},
	{"key": "1680x1050", "w": 1680, "h": 1050},
	{"key": "1600x1200", "w": 1600, "h": 1200},
	{"key": "1600x900", "w": 1600, "h": 900},
	{"key": "1440x900", "w": 1440, "h": 900},
	{"key": "1400x1050", "w": 1400, "h": 1050},
	{"key": "1366x768", "w": 1366, "h": 768},
]


## 这一档在**当前平台**是否生效（桌面端才有「窗口分辨率」这回事）。
##
## ⚠️ 与 `EveUiScale.is_enabled()`（只移动端）**正好相反**，别记混：
##    · 界面缩放：手机把 1080 设计高铺满 ⇒ 字太小，要放大 —— **只移动端**。
##    · 分辨率  ：桌面窗口可调 —— 手机上全屏，没有可调的余地 —— **只桌面端**。
static func is_enabled() -> bool:
	if OS.has_feature("mobile"):
		return false
	# ⚠️ 无头模式**一律不生效**：自检的 viewport 是钉死的 1920×1920，
	#    真去改窗口尺寸会把所有几何断言带歪（而且它根本没有"窗口"）。
	return DisplayServer.get_name() != "headless"


## 屏幕可用区尺寸（已扣掉任务栏）。拿不到（无头 / 异常）⇒ 回落 BASE。
static func usable_size() -> Vector2i:
	var r := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	if r.size.x < 320 or r.size.y < 240:
		# 无头 / 虚拟显示 / 驱动没起来 —— 一律回落设计基准，
		# ⛔ 别把 0×0 或垃圾值当成"屏幕很小"，那会让默认档塌到最小那一档。
		return BASE
	return r.size


## 按屏幕可用区挑「自动」该用哪一档。
##
## 规则（两级）：
##   ① 优先挑**能完整放下的最大 16:9 档** —— 16:9 与设计基准同比例，
##      不会触发布局居中偏移，是"什么都不用特殊处理就最好看"的那一类；
##   ② 屏幕小到没有 16:9 档放得下（极端情况）⇒ 退而取能放下的**最大面积档**；
##   ③ 连最小档都放不下 ⇒ 给最小档，让玩家至少看得见东西。
##
## ⚠️ 为什么不是「面积最大的那一档」：4:3 的 `1856×1392` 面积比 `2048×1152` 大，
##    在一台 2560×1392 的屏上会当选 —— 于是新玩家第一次启动拿到一个
##    **4:3 窗口**（内容居中、两边空）。这不是"错"，但绝不是好默认。
static func default_index() -> int:
	var avail := usable_size()

	# ① 能放下的最大 16:9
	var best := -1
	var best_area := -1
	for i in CHOICES.size():
		var it: Dictionary = CHOICES[i]
		var w := int(it["w"])
		var h := int(it["h"])
		if not _is_16_9(w, h):
			continue
		if w <= avail.x and h <= avail.y and w * h > best_area:
			best = i
			best_area = w * h
	if best >= 0:
		return best

	# ② 任何能放下的档里取面积最大
	for i in CHOICES.size():
		var w2 := int(CHOICES[i]["w"])
		var h2 := int(CHOICES[i]["h"])
		if w2 <= avail.x and h2 <= avail.y and w2 * h2 > best_area:
			best = i
			best_area = w2 * h2
	if best >= 0:
		return best

	# ③ 兜底：最小档
	var mini := 0
	for i in CHOICES.size():
		if int(CHOICES[i]["w"]) * int(CHOICES[i]["h"]) \
				< int(CHOICES[mini]["w"]) * int(CHOICES[mini]["h"]):
			mini = i
	return mini


## 是不是 16:9（与设计基准同比例）。
##
## ⚠️ 用**容差比较**而不是交叉相乘：`1366×768`（= 683:384）是最常见的笔记本分辨率，
##    它与 16:9 只差 0.05%，但交叉相乘判不出来 —— 那会把它排除在"自动"之外。
##    容差 0.01 足够松（容纳 1366×768）又足够紧（`1920×1200` 差 0.18，判得出）。
static func _is_16_9(w: int, h: int) -> bool:
	if h <= 0:
		return false
	return absf(float(w) / float(h) - 16.0 / 9.0) < 0.01


## 存档值（key 字符串）→ 生效档位下标。空串 / 认不出的 key ⇒ `default_index()`。
static func resolve_index(saved: String) -> int:
	if saved == AUTO:
		return default_index()
	for i in CHOICES.size():
		if String(CHOICES[i]["key"]) == saved:
			return i
	return default_index()


## 当前生效的档位下标（读存档）。
static func current_index() -> int:
	return resolve_index(String(STORE.load_all().get("resolution", AUTO)))


## 把窗口设成某一档，并在屏幕可用区里**居中**。
##
## ⚠️ 只在 `is_enabled()` 为真时动手；无头 / 移动端直接返回（见顶注三条边界）。
## ⚠️ 居中要算**可用区**而不是整屏：整屏居中会把标题栏顶到任务栏里。
static func apply_index(win: Window, idx: int) -> void:
	if win == null or idx < 0 or idx >= CHOICES.size():
		return
	if not is_enabled():
		return
	var want := Vector2i(int(CHOICES[idx]["w"]), int(CHOICES[idx]["h"]))
	if win.size != want:
		win.size = want
	_center(win)


## 开局 / 换分辨率后调它：读盘 → 应用。三个场景的 `_ready` 都要调一次。
static func apply_from_settings(win: Window) -> void:
	apply_index(win, current_index())


## 把窗口在屏幕可用区里居中。
static func _center(win: Window) -> void:
	var avail := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	if avail.size.x < 320 or avail.size.y < 240:
		return
	var p := avail.position + (avail.size - win.size) / 2
	if win.position != p:
		win.position = p


## 档位的显示名（`"2560 × 1440"`；标了「推荐」的那一档前面加 `★`）。
##
## ⚠️ 用 `×` 而不是 `x`（与用户给的图一致）；⚠️ 推荐标记做成**前缀**而不是后缀：
##    设置窗宽只有 320、两列排，后缀会让最长的那一行刚好顶到按钮边缘。
static func label_of(idx: int) -> String:
	if idx < 0 or idx >= CHOICES.size():
		return ""
	var it: Dictionary = CHOICES[idx]
	var s := "%d × %d" % [int(it["w"]), int(it["h"])]
	return ("★ " + s) if bool(it.get("recommend", false)) else s


## 设置存档（读盘用）。
const STORE := preload("res://scripts/core/eve_settings_store.gd")
