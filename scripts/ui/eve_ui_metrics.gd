extends RefCounted
## 全站 UI 度量基线（★ 2026-10-21 用户定）
##
## ══════════════════════════════════════════════════════════════════
##  这套刻度的**唯一来源** = 主菜单手机档的实测比例（已真机验收）。
##  目的：其他页面不再各写一套魔数，而是按同一根尺子推导尺寸与字号。
## ══════════════════════════════════════════════════════════════════
##
## 实测基准（vivo V2353DA，设计空间 1783.7 × 800）：
##   模式列宽 400 = 22.42%W · 一级模式行 100 = 12.5%H · 二级子项 84 = 10.5%H
##   系统按钮 160×110 = 8.97%W × 13.75%H · 页边距 52/40 = 2.92%W × 5%H
##   字号 26 / 22 / 13 = 3.25% / 2.75% / 1.63% × H
##
## ⛔⛔ 三条硬约束：
##   ① **桌面端一律返回调用方给的 `fallback`** —— 保证「Windows 逐像素不变」。
##      调用方写法：`METRICS.t1(d, 14)`（手机按比例、桌面仍是原来的 14）。
##   ② 纯函数：只吃传入的设计空间，⛔ 不读 `size` / 不读 `get_tree()`
##      ⇒ 可在无头验收里直接喂真实机型尺寸断言。
##   ③ 字号是**设计字号**（交给 `FONT.fs()` 的值），实际渲染还要 × 字号档（移动端默认 1.20）。
##
## ⚠️ 为什么 `fallback` 而不是内部判平台：模块保持零依赖、零状态，
##    判平台的责任留在调用方（各面板本来就知道自己是哪个页面）。

const SCALE := preload("res://scripts/ui/eve_ui_scale.gd")

# ── 字号（占屏高）────────────────────────────────────────────────
const R_T1 := 0.0325     ## 主标题（主菜单模式名 26 @800）
const R_T2 := 0.0275     ## 正文 / 关键数值（22 @800）
const R_T3 := 0.0163     ## 次要说明（13 @800）
const R_T4 := 0.0113     ## 微标签（9 @800）

# ── 控件（高度占屏高，宽度占屏宽）────────────────────────────────
const R_C1 := 0.125      ## 主操作（一级模式行 100 @800）
const R_C2_W := 0.090    ## 系统按钮宽（160 @1784）
const R_C2_H := 0.1375   ## 系统按钮高（110 @800）
const R_C3 := 0.070      ## 行内次操作（56 @800）
const R_C4 := 0.080      ## 系统条 / 顶条（64 @800）

# ── 窗口与间距 ──────────────────────────────────────────────────
const R_SIDE := 0.180    ## 侧列宽（321 @1784；主菜单同级 400 = 22.4%，折中取 18%）
const R_EDGE := 0.029    ## 页边距（52 @1784）
const R_GAP := 0.0135    ## 列间距（24 @1784）

## 触控下限（手机手指）：任何控件高都不许低于这个值
const TOUCH_MIN := 48.0
## 字号下限：再小就看不清
const FONT_MIN := 9


# ── 内部 ────────────────────────────────────────────────────────

## 有效设计空间（防 0/负值把比例算成 0）。
static func _d(d: Vector2) -> Vector2:
	return Vector2(maxf(320.0, d.x), maxf(240.0, d.y))


## 手机档才按比例算；桌面档直接回落 `fallback`。
static func _on(fallback: Variant) -> bool:
	return SCALE.is_mobile() and fallback != null


# ── 字号刻度 ────────────────────────────────────────────────────

static func t1(d: Vector2, fallback: int = 26) -> int:
	if not _on(fallback):
		return fallback
	return maxi(FONT_MIN, int(round(_d(d).y * R_T1)))


static func t2(d: Vector2, fallback: int = 22) -> int:
	if not _on(fallback):
		return fallback
	return maxi(FONT_MIN, int(round(_d(d).y * R_T2)))


static func t3(d: Vector2, fallback: int = 13) -> int:
	if not _on(fallback):
		return fallback
	return maxi(FONT_MIN, int(round(_d(d).y * R_T3)))


static func t4(d: Vector2, fallback: int = 9) -> int:
	if not _on(fallback):
		return fallback
	return maxi(FONT_MIN, int(round(_d(d).y * R_T4)))


# ── 控件刻度 ────────────────────────────────────────────────────

## C1 主操作高（开始 / 出牌 / 结算主按钮）。
static func c1_h(d: Vector2, fallback: float = 48.0) -> float:
	if not _on(fallback):
		return fallback
	return maxf(TOUCH_MIN, _d(d).y * R_C1)


## C2 系统按钮宽（设置 / 返回）。
static func c2_w(d: Vector2, fallback: float = 88.0) -> float:
	if not _on(fallback):
		return fallback
	return maxf(88.0, _d(d).x * R_C2_W)


static func c2_h(d: Vector2, fallback: float = 48.0) -> float:
	if not _on(fallback):
		return fallback
	return maxf(TOUCH_MIN, _d(d).y * R_C2_H)


## C3 行内次操作高（提示 / 托管 / 小按钮）。
static func c3_h(d: Vector2, fallback: float = 48.0) -> float:
	if not _on(fallback):
		return fallback
	return maxf(TOUCH_MIN, _d(d).y * R_C3)


## C4 系统条高（HUD 顶条）。★ 刻意不跟 C1 拔高 —— 顶条是系统条，不是模式行。
static func c4_h(d: Vector2, fallback: float = 64.0) -> float:
	if not _on(fallback):
		return fallback
	return maxf(TOUCH_MIN, _d(d).y * R_C4)


# ── 窗口与间距 ──────────────────────────────────────────────────

## 侧列宽（舰队构成 / 装备 / 战斗日志）。⛔ 不是 C 档，宽度跟屏宽走。
static func side_w(d: Vector2, fallback: float = 242.0) -> float:
	if not _on(fallback):
		return fallback
	return _d(d).x * R_SIDE


## 页边距。
static func edge(d: Vector2, fallback: float = 25.0) -> float:
	if not _on(fallback):
		return fallback
	return _d(d).x * R_EDGE


## 列 / 行间距。
static func gap(d: Vector2, fallback: float = 24.0) -> float:
	if not _on(fallback):
		return fallback
	return _d(d).x * R_GAP


# ── 自检辅助 ────────────────────────────────────────────────────

## 当前生效的整套刻度（供探针 / 验收打印，⛔ 不参与布局计算）。
static func snapshot(d: Vector2) -> Dictionary:
	return {
		"t1": t1(d), "t2": t2(d), "t3": t3(d), "t4": t4(d),
		"c1_h": c1_h(d), "c2_w": c2_w(d), "c2_h": c2_h(d),
		"c3_h": c3_h(d), "c4_h": c4_h(d),
		"side_w": side_w(d), "edge": edge(d), "gap": gap(d),
	}
