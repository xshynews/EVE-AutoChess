extends Node

## 隔离探针：吨位标识的**缩小采样**损耗定位。
##
## 目的：回答「纹理烘多大 / 用什么过滤 / 要不要 mip」——把分辨率压缩拆成可单变量的对照。
##
## ══════════════════════════════════════════════════════════════════
## ⚠️ 墨量怎么量才是准的 —— 两块底做**有限差分**，不要用 luma 直接换算
## ══════════════════════════════════════════════════════════════════
##   天真的做法：alpha ≈ (luma - bg) / (255 - bg)。**这个式子在 Godot 里是错的** ——
##   它隐含假设「合成发生在 sRGB 空间」，而 Godot 的 2D 合成是 linear 空间做完再转 sRGB，
##   于是所有**部分覆盖**的像素（抗锯齿边缘、被缩细的线）都被系统性低估。
##   更要命的是「部分覆盖越多、被扣得越狠」，正好把要比较的东西污染掉：
##      曾出现的假象：24px+LINEAR 65~80% **低于** 48px+LINEAR 85~90%（前者部分覆盖更多），
##      而同一批数据里 24px **1:1 原生**渲染也只有 86% —— 1:1 本应 100%，**自相矛盾**。
##      这个矛盾就是指标坏掉的证据，别照着它改代码。
##
##   正解：**同一符号画在两块不同底上**，逐像素取差分。
##   ⚠️ 符号方向别记错（这个错真犯过）：白色图标压在底上，
##        底越亮 ⇒ 白与底的反差越小 ⇒ **底越亮、增量越小**，于是
##            (luma_B - luma_A) / (luma_B_bg - luma_A_bg) = **1 - alpha**
##        要 alpha 得再取 `1 -`。写成 alpha 直接等于它，会把「细线全丢掉（α≈0）」
##        误读成「α≈1」，方向整个反过来。
##   自检：画**三个**已知半透白（0.25 / 0.50 / 0.75），三个都必须读回原值 ±0.03。
##        ⚠️ **不能只放一个 α=0.5** —— 符号写反时 α 与 1-α 在 0.5 处相等，
##           单点自检会被这个对称点蒙过去（踩过，就是上面那个错的来源）。
##        读不回就说明差分法在这种渲染配置下也不可信，**此时任何数字都别信**。
##
## ⚠️ 必须**非 headless** 跑：headless 用 dummy 渲染器，get_image() 读不到内容。

const TIERS := [1, 2, 3, 4, 5]
const BG_A := Color(0.32, 0.32, 0.32)
const BG_B := Color(0.47, 0.47, 0.47)
const COL_STEP := 116
const PAIR_STEP := 74          # 同一 case 的 A / B 两行间距
const HEAD := 40               # 顶部给半透白自检块留位置
## 自检用的已知 alpha：**必须 ≥2 个，且不关于 0.5 对称**（见头注释的踩坑记录）
const SWATCH := [0.25, 0.50, 0.75]

## 第 1 行 = 当前实装口径（**守门项：细线保留率应 ≥90%**）。
## 后续行都是反面对照 —— 与第 1 行比即可看出每个变量的代价。
const CASES := [
	{"name": "12px + LINEAR ★实装", "w": 12.0, "f": CanvasItem.TEXTURE_FILTER_LINEAR},
	{"name": "12px + NEAREST", "w": 12.0, "f": CanvasItem.TEXTURE_FILTER_NEAREST},
	{"name": "12px + LINEAR_WITH_MIPMAPS（对照）", "w": 12.0,
		"f": CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS},
]

var _sv: SubViewport
var _done := false


func _ready() -> void:
	_sv = SubViewport.new()
	_sv.size = Vector2i(COL_STEP * TIERS.size() + 40, HEAD + PAIR_STEP * CASES.size() * 2 + 30)
	_sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_sv.transparent_bg = false
	add_child(_sv)
	for ci in CASES.size():
		var ctl := Control.new()
		ctl.size = Vector2(_sv.size)
		ctl.texture_filter = CASES[ci]["f"]
		ctl.draw.connect(_on_draw.bind(ctl, ci))
		_sv.add_child(ctl)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	_measure()


## 第 ci 个方案、第 half 行（0 = A 底 / 1 = B 底）的行顶 y
func _row_y(ci: int, half: int) -> float:
	return float(HEAD + ci * PAIR_STEP * 2 + half * PAIR_STEP)


func _on_draw(ctl: Control, ci: int) -> void:
	var w: float = CASES[ci]["w"]
	for half in 2:
		var y := _row_y(ci, half)
		var bg := BG_A if half == 0 else BG_B
		ctl.draw_rect(Rect2(0.0, y - 6.0, _sv.size.x, PAIR_STEP + 10.0), bg, true)
		for i in TIERS.size():
			EveTierIcon.draw(ctl, Vector2(20.0 + i * COL_STEP, y), w, TIERS[i], Color.WHITE)
	# 半透白自检块（只在 ci=0 画，避免重复叠加）
	# ⚠️ **三个已知值，不能只放一个 α=0.5** —— 符号写反时 α 与 1-α 在 0.5 处相等，
	#    单点自检会被这个对称点蒙过去（这个坑真踩过）。
	if ci == 0:
		for half in 2:
			for k in SWATCH.size():
				ctl.draw_rect(Rect2(_sv.size.x - 76.0 + k * 24.0, _row_y(0, half) - 4.0, 20.0, 26.0),
					Color(1.0, 1.0, 1.0, SWATCH[k]), true)


func _measure() -> void:
	if _done:
		return
	_done = true
	var img := _sv.get_texture().get_image()
	img.save_png("user://tier_probe.png")
	var la := BG_A.get_luminance() * 255.0
	var lb := BG_B.get_luminance() * 255.0
	var den := lb - la
	print("[TIER] 读回 %s   底 A=%.1f B=%.1f Δ=%.2f" % [str(img.get_size()), la, lb, den])

	# ── 自检：三个已知 alpha 的白块都必须读回原值 ──
	var bad := 0
	for k in SWATCH.size():
		var chk := _alpha(img, int(_sv.size.x) - 74 + k * 24, _row_y(0, 0) + 2, 12, 12, den) / maxf(0.001, 12.0 * 12.0)
		if absf(chk - SWATCH[k]) > 0.03:
			bad += 1
		print("[TIER] 自检 · 已知 alpha=%.2f → 读回 %.3f  %s"
			% [SWATCH[k], chk, "OK" if absf(chk - SWATCH[k]) <= 0.03 else "✗ 偏差 %.3f" % (chk - SWATCH[k])])
	print("[TIER] 差分法%s" % ["有效" if bad == 0 else "⚠️ 不可信（%d/3 偏差），下面的数字全部作废" % bad])

	# 纹理实况：尺寸 / 格式 / Σalpha（理论式的输入，必须自己可见）
	for i in TIERS.size():
		var c: int = TIERS[i]
		var im := EveTierIcon.texture(c).get_image()
		var s := 0.0
		for yy in im.get_height():
			for xx in im.get_width():
				s += im.get_pixel(xx, yy).a
		print("[TIER] 纹理 tier_%d  %s  fmt=%d  Σalpha=%.1f  aspect=%.3f"
			% [c, str(im.get_size()), im.get_format(), s, EveTierIcon.aspect(c)])

	# ⚠️ 只报**同一吨位跨方案的相对值**，不报「保留率」。
	#    曾经这里有一列「理论墨量 = Σalpha × (显示宽/纹理宽)²」，实测值总是它的 1.3~2.3 倍，
	#    查不出是采样端还是我的理论式错（同一份数据既能推出 86% 也能推出 172%）。
	#    **一个解释不了偏差的绝对指标比没有指标更坏** —— 它会把判断带偏，
	#    所以换成纯相对口径：同一吨位的 α 总量，越大 = 细线保留越多。
	print("[TIER] %-30s %s" % ["方案（α 总量，★ 行为基准 100%）", "各吨位"])
	var base: Array = []
	for ci in CASES.size():
		var w: float = CASES[ci]["w"]
		var row := ""
		for i in TIERS.size():
			var c: int = TIERS[i]
			var x := int(20.0 + i * COL_STEP)
			var h := int(ceil(w * EveTierIcon.aspect(c))) + 1
			var got := _alpha(img, x, _row_y(ci, 0), int(w), h, den)
			if ci == 0:
				base.append(got)
			row += "  t%d=%5.1f(%3.0f%%)" % [c, got, 100.0 * got / maxf(0.001, base[i])]
		print("[TIER] %-30s%s" % [CASES[ci]["name"], row])
	get_tree().quit()


## 同一矩形在 A / B 两块底上的差分 ⇒ **alpha 之和**（与色彩空间无关）
##
## ⚠️ `1 -` 不能省：白色图标压在底上，底越亮增量越小（见头注释）。
func _alpha(img: Image, x: int, y_a: float, w: int, h: int, den: float) -> float:
	var sa := 0.0
	var sb := 0.0
	var ya := int(y_a)
	var yb := int(y_a) + PAIR_STEP
	for yy in h:
		for xx in w:
			sa += img.get_pixel(x + xx, ya + yy).get_luminance() * 255.0
			sb += img.get_pixel(x + xx, yb + yy).get_luminance() * 255.0
	return float(w * h) - (sb - sa) / den
