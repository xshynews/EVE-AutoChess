extends RefCounted
class_name EveUiScale

## EVE 自走棋 —— UI 缩放档（平台默认值 + 取值域）**唯一真相源**
##
## ══════════════════════════════════════════════════════════════════
##  为什么需要它
## ══════════════════════════════════════════════════════════════════
##  工程是 `stretch/mode=canvas_items` + 1920×1080 设计空间（project.godot）。
##  手机（横屏 1080 高、6 寸多）把 1080 设计高铺满整块屏 ⇒
##  一个设计像素只有约 0.7mm，而战斗 HUD 里最小的字号是 **9px**
##  —— 那是给显示器定的尺寸，手机上读不出来（用户 2026-10-07 收到实机反馈）。
##
## ── 放大的代价：这是数学，不是审美 ────────────────────────────────
##  设计高 = 1080 / 倍数（**与屏幕分辨率无关**，只要屏比 16:9 宽）：
##      1.00 → 1080      1.15 → 939      1.25 → 864
##      1.35 →  800      1.50 → 720
##  设计高变小 ⇒ 底部的商店 / 备战席会掉出屏幕。
##  ⇒ **放大必须与「紧凑档」同时生效**（见 `EveHudRoot.apply_ui_profile()`）。
##
## ── 为什么桌面端一个字节都不变 ──────────────────────────────────
##  `is_enabled()` 只在 `OS.has_feature("mobile")` 为真时才为真。
##  桌面端读到的存档值**一律不作数**（回到 1.0）⇒
##    ① Windows 版的行为与从前完全一致（用户 2026-10-07 明确要求）；
##    ② 无头自检跑在桌面分支上，不会被某台安卓设备存下来的倍数污染
##       （headless 视口是 1920×1920，一旦被放大，HUD 布局就会变，
##         verify_run 那 581 条断言会莫名其妙地红）。

## 设置里「自动」的取值。存档存的也是这个语义：0 = 跟随平台。
const AUTO := 0.0

## 移动端默认倍数。
##
## ⚠️ 定在 1.35 而不是更大，是有具体约束的（不是随手取的数）：
##    设计高 800 时备战席顶边在 480，而左列展开后的最低点是装备栏底边 452
##    ⇒ 还留得住 28px 间隙。再往上一档（1.5 → 设计高 720）就会贴住。
const MOBILE := 1.35

## 桌面端恒定 1.0 —— 分辨率交给窗口尺寸解决，不需要缩放。
const DESKTOP := 1.0

## 设置窗里可选的倍数。`v = 0` 必须在首位（= 「自动」）。
##
## ⚠️ 全表**只在这里**维护：设置窗的按钮、取值校验、回写高亮都读它。
const CHOICES: Array = [
	{"name": "自动", "v": AUTO},
	{"name": "100%", "v": 1.00},
	{"name": "115%", "v": 1.15},
	{"name": "125%", "v": 1.25},
	{"name": "135%", "v": 1.35},
]


## 这是不是移动平台（安卓 / iOS）。
static func is_mobile() -> bool:
	return OS.has_feature("mobile")


## 缩放档在**当前平台**是否生效。
##
## ⚠️ 只有移动端生效 —— 这是「Windows 端保持不变」这条要求的技术落点：
##    桌面端连设置项都不显示（见 eve_settings.gd），存档值也不会被应用。
static func is_enabled() -> bool:
	return is_mobile()


## 本平台的出厂默认倍数。
static func default_scale() -> float:
	return MOBILE if is_mobile() else DESKTOP


## 存档值 → 实际倍数。
##
## ⚠️ 桌面端**忽略存档**：桌面用户的体验不该被「上一台设备的选择」改变
##    （user:// 在换机时不会同步，所以理论上碰不到；但云端备份 / 手动拷贝
##      存档是真实存在的，别留这个坑）。
static func resolve(saved: float) -> float:
	if not is_enabled():
		return DESKTOP
	if saved <= 0.0:
		return default_scale()
	# ★ 夹回**取值域本身**（= `CHOICES` 表），⛔ 不是随手写的 1.0~2.0：
	#   设计高 = 1080 / 倍数，1.5 在 16:9 手机上只剩 720 ——
	#   那时结算页（设计高 356）在「顶条以下、备战席以上」已经放不下。
	#   手改 cfg 填个 9.9 不该把 HUD 拆了，夹住就好。
	var lo := float(CHOICES[1]["v"])
	var hi := float(CHOICES[CHOICES.size() - 1]["v"])
	return clampf(saved, lo, hi)


## 存档值 → 设置窗里该亮第几个按钮（找不到就回落「自动」）。
static func choice_index(saved: float) -> int:
	for i in CHOICES.size():
		if is_equal_approx(float(CHOICES[i]["v"]), saved):
			return i
	return 0


## 非战斗场景（主菜单 / 开场 / 牌桌）**必须把缩放归 1.0**。
##
## ⚠️⚠️ `content_scale_factor` 是**根窗口**的属性，跨场景切换会一直留着 ——
##    少了这一句，就变成「进过一次战场 ⇒ 回主菜单也被放大」，而主菜单是
##    按 1920×1080 死坐标 + 1:1 烘好的背景图做的（放大就散了）。
##    所以每个非战斗场景的 `_ready()` 都要表一次态。
##
## ⚠️ 它不是「把玩家的设置清掉」：值仍在 `settings.cfg` 里，
##    下次进战场照样按档位放大。
static func apply_scene_default(win: Window) -> void:
	if win != null and not is_equal_approx(win.content_scale_factor, DESKTOP):
		win.content_scale_factor = DESKTOP


## 需要紧凑档吗（= 设计空间比 1080 矮，底部两条必须改成贴底）。
static func is_compact(scale: float) -> bool:
	return scale > 1.001
