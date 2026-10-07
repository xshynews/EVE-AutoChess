extends RefCounted
class_name EveTierIcon

## EVE 自走棋 —— 吨位（= 费用档）几何标识
##
## ══════════════════════════════════════════════════════════════════
## 5 个符号的规则（用户 2026-09-23 口述 + 13 图鉴页实测复核）
## ══════════════════════════════════════════════════════════════════
##   1 护卫舰    三角形（**底边即底线**，闭合三角，无间隙）
##   2 驱逐舰    三角 + 下方一条独立横线
##   3 巡洋舰    上面三角形 + 下面长方形 —— 且**以三角形最长边为长方形的长**
##               （即「屋顶 + 墙」的房子：45° 屋顶 + 竖直侧边 + 底边）
##   4 战列巡洋舰 巡洋舰符号 + 下面再加一横
##   5 战列舰    巡洋舰符号，但下面**改成三角形**
##               （底部是向上尖的 Λ 凹口 ⇒ 整体读作箭镞形）
##
##   ⚠️ 五个符号**共用同一个屋顶**（顶点与屋檐同位），只在下半部分逐级生长：
##      外框比（高 : 宽）= 0.50 / 0.71 / 0.90 / 1.10 / 1.21
##      官方同项实测      = 0.50 / 0.70 / 0.90 / 1.10 / 1.20  ⇒ 逐项命中
##   ⚠️ 是**描边**不是实心块面。旧版把 3/4/5 读成「拱形实心」是错的（已废）。
##
## ══════════════════════════════════════════════════════════════════
## ⚠️ 为什么是「预烘贴图」而不是 _draw 现画 —— 锯齿的唯一解
## ══════════════════════════════════════════════════════════════════
##   project.godot **没开 msaa_2d**（只有 msaa_3d=1 + screen_space_aa=1），
##   而 Godot 4 的 `draw_polyline` 只有 1px 描边、`draw_polygon` 没有
##   antialiased 参数 ⇒ 2D 侧画这个符号必然是硬锯齿。
##   开 `msaa_2d` 是**全局**改动：HUD 里大量「像素对齐的 1px 边框」
##   （格带边框、棋盘线、窗口边）会一起被揉成半透明灰边。
##   ⇒ 边缘覆盖率**离线算**：`C:\godot\_export\tier_icons.py`
##     在 16x 超采样画布上描边，再盒式降采样到 48px 宽。
##
## ⚠️ 纹理 = **符号自身包围盒**（不留白），宽固定 24px = 显示宽度的 **2 倍**。
##
##    **2:1 是硬口径，不是随手定的** —— 双线性在 2:1 下是精确的 2x2 盒平均
##    （采样点落在纹素正中，四纹素权重各 1/4）；到 4:1 就退化成「跳采样」，
##    只混相邻 2 个纹素、另 2 个根本没被读到 ⇒ 细线掉墨 + 斜边摩尔纹。
##    实测（`tools/probe_tier_icon` 隔离探针，12px 显示，最细的独立横线）：
##        48px + mip 链 **56%** · 48px + 仅 LINEAR 85% · **24px + 仅 LINEAR ~95%**
##    ⇒ 纹理尺寸必须是显示尺寸的整数倍，且**倍数 ≤ 2**。
##      改 TIER_SIZE 就离开这个关系（不是不能改，是要同时改烘图脚本重烘）。
##
## ⚠️ 纹理导入必须 `mipmaps/generate=false`（已写进 .import）——
##    2:1 已是最优采样，套 mip 反而先平均一遍再采样，白掉墨。
## ⚠️ 调用方控件要设 `texture_filter = TEXTURE_FILTER_LINEAR`；
##    若设成 `..._WITH_MIPMAPS` 会把上一行的代价吃回来。
##
## 用法：
##   EveTierIcon.draw(self, cell.position + Vector2(5, 5), 12.0, cost, col)

## 贴图目录。约定：`res://assets/ui/tier/tier_<cost>.png`
const DIR := "res://assets/ui/tier/"

## 纹理缓存。Key = cost（1~5），Value = Texture2D 或 null（未命中也要缓存，
## 避免每帧对不存在的路径反复做 ResourceLoader.exists 的磁盘探测）。
static var _tex: Dictionary = {}


## 取某一吨位的符号贴图。越界会钳到 1~5；资源缺失返回 null（调用方负责跳过）。
static func texture(cost: int) -> Texture2D:
	var c := clampi(cost, 1, 5)
	if _tex.has(c):
		return _tex[c]
	var t: Texture2D = null
	var p := "%stier_%d.png" % [DIR, c]
	if ResourceLoader.exists(p):
		t = load(p) as Texture2D
	_tex[c] = t
	return t


## 是否存在该吨位的贴图（验收用）
static func has_icon(cost: int) -> bool:
	return texture(cost) != null


## 符号的宽高比（高 ÷ 宽）。取不到纹理时退回 1.0。
##
## ⚠️ 不在这里写「吨位 → 高宽」的设计表 —— 那是**第二份真相源**：
##    贴图本身就是按规则烘出来的，比例读纹理即可，改规则只改烘图脚本。
static func aspect(cost: int) -> float:
	var t := texture(cost)
	if t == null or t.get_width() <= 0:
		return 1.0
	return float(t.get_height()) / float(t.get_width())


## 把符号画在 [param at]（**左上角**），符号的**外框宽** = [param width_px]。
##
## ⚠️ 传的是宽度而不是高度：5 个吨位的宽度是常量（10 设计单位）、高度随吨位长
##    （0.50~1.21 倍宽）。按宽度对齐才能让五个符号的**屋顶同位** ——
##    这也是官方图鉴的排布口径。
static func draw(ci: CanvasItem, at: Vector2, width_px: float, cost: int,
		col: Color) -> void:
	var t := texture(cost)
	if t == null or width_px <= 2.0:
		return
	# +0.5 后 floor = 四舍五入到整数像素；纹理是整数倍缩小时这条决定边缘糊不糊
	var d := Vector2(width_px, width_px * aspect(cost))
	ci.draw_texture_rect(t, Rect2((at + Vector2(0.5, 0.5)).floor(), d), false, col)


## 以 [param center] 为**外框中心**画（居中版）
static func draw_centered(ci: CanvasItem, center: Vector2, width_px: float,
		cost: int, col: Color) -> void:
	var d := Vector2(width_px, width_px * aspect(cost))
	draw(ci, center - d * 0.5, width_px, cost, col)


## 吨位中文名（与 EveShipTable.CLASS_NAMES_BY_COST 同源，不另立一份真相）
static func label(cost: int) -> String:
	return String(EveShipTable.CLASS_NAMES_BY_COST.get(clampi(cost, 1, 5), ""))
