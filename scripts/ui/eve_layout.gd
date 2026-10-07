extends RefCounted
class_name EveLayout

## EVE 自走棋 —— **设计空间 / 内容居中**唯一真相源（★ 2026-10-07）
##
## ══════════════════════════════════════════════════════════════════
##  为什么需要它
## ══════════════════════════════════════════════════════════════════
##  工程是 `stretch/mode=canvas_items` + `aspect=expand`，设计基准 **1920×1080**。
##  16:9 的窗口（1920×1080 / 2560×1440 / 3840×2160 …）里，设计空间**恒等于**
##  1920×1080 ⇒ 所有绝对坐标天然对齐，什么都不用做。
##
##  ⚠️ 但分辨率档里有一半是 **4:3 / 16:10**（1920×1200、1680×1050、1920×1440 …）。
##     `expand` 的行为是「等比缩放到铺满，超出的方向暴露更多空间」⇒
##     设计空间变成 1920×1200 之类。那时按 1920×1080 排的内容就会**贴在左上**，
##     底部/右侧露出一条空的背景 —— 玩家看到的是「UI 跑了」。
##
##  ⇒ 解法（`origin()`）：设计空间比基准大的部分**平均分成两半**，
##     内容整体平移过去 = 视觉上在窗口里居中。多出来的边缘露的是
##     各场景自己的背景（星空 / 舱壁），不是黑边 —— 这是选 `expand` 而不是
##     `keep` 的理由：`keep` 会加黑边，观感更差。
##
##  ⚠️ **只在 content_scale_factor = 1.0 的场景用**（主菜单 / 牌桌 / 桌面端战场）。
##     紧凑档（移动端）有自己的居中逻辑：`EveHudRoot.compact_rects()`
##     直接按设计空间排、本来就居中，⛔ 再叠一层 origin 会重复偏移。

## 设计基准 = `project.godot` 的 viewport 尺寸（与 `EveResolution.BASE` 同源）。
const BASE := Vector2(1920.0, 1080.0)


## 当前设计空间（= 视口 ÷ 拉伸倍数）。
##
## ⚠️⚠️ **从窗口算，不读控件自己的 `size`** —— 这个函数会在
##    「刚设完 `content_scale_factor`、Control 的布局还没跑」那一帧被调用，
##    此时 `size` 还是上一档的旧值（实测过的坑：拿旧值算 ⇒ 底部两条摆错位置）。
##    拉伸口径与 project.godot 对齐：canvas_items + expand ⇒
##        scale = min(视口 / 1920×1080) × content_scale_factor
##        设计空间 = 视口 / scale
static func design_space(win: Window) -> Vector2:
	if win != null:
		var vp := Vector2(win.size)
		var k := minf(vp.x / BASE.x, vp.y / BASE.y) * maxf(1.0, win.content_scale_factor)
		if k > 0.0001 and vp.x > 4.0 and vp.y > 4.0:
			return vp / k
	return BASE


## 内容居中偏移（≥ 0；16:9 时恒为 `Vector2.ZERO`）。
##
## ⚠️ 它**必须**在「画」和「点」两侧同时生效 —— 只加在绘制上就是
##    「看着能点、点了没反应」（工程红线 9：画与点同源）。
##
## ⚠️⚠️ 实测过的坑（2026-10-07）：**无头模式下不能从窗口推**。
##    无头时 `window.size` 是个假的 `(64,64)`，按 `design_space` 的口径反推出
##    **1920×1920**（恰好等于 headless 的视口）⇒ 偏移 (0,420) ⇒
##    581 条几何断言会**整体下移 420px** 而原因极难看出来。
##    ⇒ 无头一律返回零偏移。居中逻辑本身由 `origin_of()` 这个**纯函数**保证，
##      自检直接喂设计空间验它（与 `compact_rects()` 同一套办法）。
static func origin(win: Window) -> Vector2:
	if DisplayServer.get_name() == "headless":
		return Vector2.ZERO
	return origin_of(design_space(win))


## **纯函数**：设计空间 → 居中偏移（自检直接喂值，不依赖真实窗口）。
##
## 设计空间比基准大的那部分**平均分两半**：内容居中，多出来的边缘露背景。
static func origin_of(design: Vector2) -> Vector2:
	return Vector2(maxf(0.0, (design.x - BASE.x) * 0.5),
			maxf(0.0, (design.y - BASE.y) * 0.5))
