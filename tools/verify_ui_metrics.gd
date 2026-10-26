extends Node
## UI 度量基线自检（★ 2026-10-21）
##
## ⚠️ 为什么单独一套：`eve_ui_metrics.gd` 是**全站尺寸与字号的唯一来源**，
##    它一旦算错，症状是「某个页面莫名变小 / 字挤在一起」，不会报错。
##    ⇒ 用确定性的数字把「比例 → 像素」这一步钉死。
##
## ⚠️ 本测试**不需要真的跑在安卓上**：度量是纯函数，直接喂真实机型设计空间即可。
##    手机分支用 `EveUiScale.force_mobile` 开闸（与 `verify_ui_scale` 同一手法）。

const METRICS := preload("res://scripts/ui/eve_ui_metrics.gd")
const SCALE := preload("res://scripts/ui/eve_ui_scale.gd")
const HUD := preload("res://scripts/ui/eve_hud_root.gd")

## 与 `verify_ui_scale.PHONES` 同源的机型设计空间
const VIVO := Vector2(1784, 800)
const NARROW := Vector2(1422, 800)
const BIG := Vector2(2370, 1067)

var _pass := 0
var _fail := 0
var _old_force := false


func _ok(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
		print("  ✓ " + msg)
	else:
		_fail += 1
		print("  ✗ " + msg)


func _near(a: float, b: float, eps: float = 0.6) -> bool:
	return absf(a - b) <= eps


func _ready() -> void:
	_old_force = SCALE.force_mobile
	print("═══ UI 度量基线 自检 ═══")
	_t_desktop_unchanged()
	_t_mobile_scale()
	_t_ratio_monotonic()
	_t_touch_floor()
	_t_cross_check_hud()
	_t_settings_single_source()
	SCALE.force_mobile = _old_force
	print("═══ RESULT passed=%d failed=%d ═══" % [_pass, _fail])
	get_tree().quit(1 if _fail > 0 else 0)


## [1] ★★ 桌面端必须逐值回落 `fallback` —— 这是「Windows 逐像素不变」的保证。
##     任何调用方写 `METRICS.t1(d, 14)`，桌面端拿到的必须**正好**是 14。
func _t_desktop_unchanged() -> void:
	print("[1] 桌面档：一律回落 fallback（⛔ 不许按比例算）")
	SCALE.force_mobile = false
	_ok(METRICS.t1(VIVO, 14) == 14, "t1 回落 fallback 14")
	_ok(METRICS.t2(VIVO, 15) == 15, "t2 回落 fallback 15")
	_ok(METRICS.t3(VIVO, 9) == 9, "t3 回落 fallback 9")
	_ok(METRICS.t4(VIVO, 9) == 9, "t4 回落 fallback 9")
	_ok(_near(METRICS.c1_h(VIVO, 26.0), 26.0), "c1_h 回落 26（原顶条按钮高）")
	_ok(_near(METRICS.c3_h(VIVO, 26.0), 26.0), "c3_h 回落 26")
	_ok(_near(METRICS.c4_h(VIVO, 40.0), 40.0), "c4_h 回落 40（原顶条高）")
	_ok(_near(METRICS.side_w(VIVO, 172.0), 172.0), "side_w 回落 172（原桌面侧列）")
	_ok(_near(METRICS.edge(VIVO, 8.0), 8.0), "edge 回落 8")
	_ok(_near(METRICS.gap(VIVO, 10.0), 10.0), "gap 回落 10")


## [2] ★ 手机档：按主菜单实测比例算出的像素值
func _t_mobile_scale() -> void:
	print("[2] 手机档 @1784×800：比例 → 像素（对齐主菜单实测）")
	SCALE.force_mobile = true
	_ok(METRICS.t1(VIVO, 14) == 26, "★ T1 = 26（主菜单模式名同款，实际 %d）" % METRICS.t1(VIVO, 14))
	_ok(METRICS.t2(VIVO, 15) == 22, "T2 = 22（实际 %d）" % METRICS.t2(VIVO, 15))
	_ok(METRICS.t3(VIVO, 9) == 13, "T3 = 13（实际 %d）" % METRICS.t3(VIVO, 9))
	_ok(METRICS.t4(VIVO, 9) == 9, "T4 = 9（实际 %d）" % METRICS.t4(VIVO, 9))
	_ok(_near(METRICS.c1_h(VIVO, 48.0), 100.0), "★ C1 主操作高 = 100（实际 %.1f）" % METRICS.c1_h(VIVO, 48.0))
	_ok(_near(METRICS.c2_w(VIVO, 88.0), 160.56), "C2 系统按钮宽 ≈ 160（实际 %.1f）" % METRICS.c2_w(VIVO, 88.0))
	_ok(_near(METRICS.c2_h(VIVO, 48.0), 110.0), "C2 系统按钮高 = 110（实际 %.1f）" % METRICS.c2_h(VIVO, 48.0))
	_ok(_near(METRICS.c3_h(VIVO, 48.0), 56.0), "★ C3 行内次操作 = 56（实际 %.1f）" % METRICS.c3_h(VIVO, 48.0))
	_ok(_near(METRICS.c4_h(VIVO, 64.0), 64.0), "C4 顶条 = 64（实际 %.1f）" % METRICS.c4_h(VIVO, 64.0))
	_ok(_near(METRICS.side_w(VIVO, 242.0), 321.12), "★ 侧列宽 = 18%%W ≈ 321（实际 %.1f）" % METRICS.side_w(VIVO, 242.0))
	_ok(_near(METRICS.edge(VIVO, 25.0), 51.736), "页边距 ≈ 52（实际 %.1f）" % METRICS.edge(VIVO, 25.0))
	_ok(_near(METRICS.gap(VIVO, 24.0), 24.084), "列间距 ≈ 24（实际 %.1f）" % METRICS.gap(VIVO, 24.0))


## [3] 比例必须**随屏高单调**：换机型只缩放、不跳档
func _t_ratio_monotonic() -> void:
	print("[3] 跨机型单调：800 → 1067 高，刻度只放大不缩小")
	SCALE.force_mobile = true
	var a := METRICS.snapshot(VIVO)
	var b := METRICS.snapshot(BIG)
	_ok(b["t1"] > a["t1"], "T1 随屏高变大（%d → %d）" % [a["t1"], b["t1"]])
	_ok(b["t2"] > a["t2"], "T2 随屏高变大（%d → %d）" % [a["t2"], b["t2"]])
	_ok(b["c1_h"] > a["c1_h"], "C1 随屏高变大（%.0f → %.0f）" % [a["c1_h"], b["c1_h"]])
	_ok(_near(b["side_w"], 426.6, 1.0), "大屏侧列宽 = 18%%W ≈ 426.6（实际 %.1f）" % b["side_w"])
	# 同高不同宽的窄屏：高度刻度不变、宽度刻度变窄（⛔ 不能一起缩）
	var n := METRICS.snapshot(NARROW)
	_ok(n["c1_h"] == a["c1_h"], "同屏高（800）⇒ C1 不变（1422 与 1784 都是 %.0f）" % n["c1_h"])
	_ok(n["side_w"] < a["side_w"], "窄屏侧列更窄（%.0f < %.0f）" % [n["side_w"], a["side_w"]])
	_ok(n["t1"] == a["t1"], "同屏高 ⇒ 字号不变（%d）" % n["t1"])


## [4] ★ 触控下限：任何档位都不许低于 48，字号不许低于 9
func _t_touch_floor() -> void:
	print("[4] 触控 / 字号下限（极小空间也不许塌）")
	SCALE.force_mobile = true
	var tiny := Vector2(640, 480)
	_ok(METRICS.c1_h(tiny, 48.0) >= 48.0, "640×480 ⇒ C1 ≥ 48（实际 %.1f）" % METRICS.c1_h(tiny, 48.0))
	_ok(METRICS.c3_h(tiny, 48.0) >= 48.0, "640×480 ⇒ C3 ≥ 48（实际 %.1f）" % METRICS.c3_h(tiny, 48.0))
	_ok(METRICS.c4_h(tiny, 64.0) >= 48.0, "640×480 ⇒ C4 ≥ 48（实际 %.1f）" % METRICS.c4_h(tiny, 64.0))
	_ok(METRICS.t4(tiny, 9) >= 9, "640×480 ⇒ T4 ≥ 9（实际 %d）" % METRICS.t4(tiny, 9))
	# 防 0 / 负设计空间把比例算成 0
	var zero := Vector2.ZERO
	_ok(METRICS.t1(zero, 14) >= 9 and METRICS.side_w(zero, 242.0) > 0.0,
			"设计空间为 0 ⇒ 仍给出可用值（T1 %d / 侧列 %.1f）"
			% [METRICS.t1(zero, 14), METRICS.side_w(zero, 242.0)])


## [5] 交叉校验：C4 必须与 HUD 已验收的顶条高一致（防两处各写一个数）
func _t_cross_check_hud() -> void:
	print("[5] 与既有实装交叉校验（防两套数字漂移）")
	SCALE.force_mobile = true
	_ok(_near(METRICS.c4_h(VIVO, 64.0), HUD.MOBILE_TOP_H),
			"★ C4 顶条高 == EveHudRoot.MOBILE_TOP_H（%.0f == %.0f）"
			% [METRICS.c4_h(VIVO, 64.0), HUD.MOBILE_TOP_H])
	# 侧列必须比主菜单模式列窄一档（这是「折中」选项的定义，别被悄悄改成 22.4%）
	const MENU_MODE_W_RATIO := 0.2242
	_ok(METRICS.R_SIDE < MENU_MODE_W_RATIO,
			"★ 侧列比例 18% < 主菜单 22.4%（折中档，⛔ 别改成对齐）")
	_ok(_near(METRICS.R_T1 / METRICS.R_T2, 26.0 / 22.0, 0.02),
			"★ T1:T2 == 26:22（与主菜单同源，实际 %.3f）" % (METRICS.R_T1 / METRICS.R_T2))


## [6] ★★ 设置窗只允许**一个**宽度真相源（2026-10-21 阶段 0-2）
##
## 历史问题：`settings_rect()` 的手机分支返回 `0.72W`，而手机实际走的
## `mobile_rects()["settings"]` 是 `0.5W` ⇒ 同一扇窗两套公式，改一处另一处不变。
## 现在两者必须给出相同的**尺寸**（y 故意不同：手机档要在顶条以下居中）。
func _t_settings_single_source() -> void:
	print("[6] 设置窗：宽度只允许一个真相源（0.5W，⛔ 不再是 0.72W）")
	SCALE.force_mobile = true
	var r: Rect2 = HUD.settings_rect(VIVO)
	var m: Rect2 = HUD.mobile_rects(VIVO)["settings"]
	_ok(_near(r.size.x, m.size.x),
			"★ settings_rect 与 mobile_rects 宽度一致（%.1f == %.1f）" % [r.size.x, m.size.x])
	_ok(_near(r.size.y, m.size.y),
			"★ 高度一致 min(0.70H, 560)（%.1f == %.1f）" % [r.size.y, m.size.y])
	_ok(r.size.x < VIVO.x * 0.6,
			"★ 宽度不再是 0.72W（%.1f < 半屏上界 %.1f）" % [r.size.x, VIVO.x * 0.6])
