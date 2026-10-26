extends SceneTree

## 截图"读图"工具 —— 把 PNG 转成**文字**，供看不到图片的会话做布局诊断。
##
## 为什么存在：本会话的 Read 工具读图片后返回内容被系统清空，等于看不见截图；
## 而布局问题的第一手证据就在截图里。⇒ 用像素统计把它编码成文本。
##
## 跑法：
##   "$GODOT" --headless --path . --script res://tools/ascii_shot.gd -- <png> [列数]
##
## 输出三块：
##   ① 亮度 ASCII 图（越高越亮；面板边框 / 文字会显形）
##   ② 颜色分类图（C 青 / G 金 / R 红 / E 绿 / B 蓝 / W 白 / . 灰）
##   ③ 分块统计（8×4 块的亮度均值和最大亮度 ⇒ 哪块有内容、哪块被切边）

const RAMP := " .:-=+*#%@"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		print("[ascii] 用法: --script res://tools/ascii_shot.gd -- <png路径> [列数]")
		quit(1)
		return
	var path: String = args[0]
	var cols: int = int(args[1]) if args.size() > 1 else 100
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		print("[ascii] 读不到文件: ", path)
		quit(1)
		return
	var img := Image.new()
	var err := img.load_png_from_buffer(bytes)
	if err != OK:
		print("[ascii] 解码失败 err=", err)
		quit(1)
		return
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	# ★ 可选裁剪：`-- <png> <cols> [x0 y0 w h]` —— 把两张图裁到同一块 UI 上逐像素比。
	var crop_x0 := 0
	var crop_y0 := 0
	var crop_w := img.get_width()
	var crop_h := img.get_height()
	if args.size() >= 6:
		crop_x0 = int(args[2])
		crop_y0 = int(args[3])
		crop_w = mini(int(args[4]), img.get_width() - crop_x0)
		crop_h = mini(int(args[5]), img.get_height() - crop_y0)
		var cut := img.get_region(Rect2i(crop_x0, crop_y0, crop_w, crop_h))
		img = cut
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	var iw := img.get_width()
	var ih := img.get_height()
	var rows := maxi(8, int(round(float(cols) * float(ih) / float(iw) * 0.5)))
	print("[ascii] %s" % path)
	print("[ascii] 原图 %dx%d · 采样 %d列 x %d行" % [iw, ih, cols, rows])

	# ── 采样（每格取块内均值 + 块内最大亮度）──
	var lum := PackedFloat32Array()
	var cls := PackedByteArray()
	var peak := PackedFloat32Array()
	for r in rows:
		for c in cols:
			var x0 := int(float(c) * iw / float(cols))
			var x1 := maxi(x0 + 1, int(float(c + 1) * iw / float(cols)))
			var y0 := int(float(r) * ih / float(rows))
			var y1 := maxi(y0 + 1, int(float(r + 1) * ih / float(rows)))
			var sr := 0.0
			var sg := 0.0
			var sb := 0.0
			var n := 0
			var mx := 0.0
			for y in range(y0, y1, maxi(1, (y1 - y0) / 4)):
				for x in range(x0, x1, maxi(1, (x1 - x0) / 4)):
					var col := img.get_pixel(x, y)
					var l := 0.2126 * col.r + 0.7152 * col.g + 0.0722 * col.b
					sr += col.r
					sg += col.g
					sb += col.b
					n += 1
					mx = maxf(mx, l)
			sr /= float(n)
			sg /= float(n)
			sb /= float(n)
			var ml := 0.2126 * sr + 0.7152 * sg + 0.0722 * sb
			lum.append(ml)
			peak.append(mx)
			cls.append(_classify(sr, sg, sb, ml))

	print("\n===== ① 亮度图（每 5 行标一次行号，列号 0/25/50/75 在标尺上）=====")
	print("     0         2         4         6         8")
	print("     0123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789")
	for r in rows:
		var line := ""
		for c in cols:
			var p := 0
			if r * cols + c < peak.size():
				p = int(round(peak[r * cols + c] * 9.0))
			line += RAMP[p]
		print("%3d |%s" % [r, line])

	print("\n===== ② 颜色分类图 =====")
	for r in rows:
		var line := ""
		for c in cols:
			line += _glyph(cls[r * cols + c])
		print("%3d |%s" % [r, line])

	print("\n===== ③ 分块统计（8 列 × 6 行块：均值/峰值，单位 0-99）=====")
	var bx := 8
	var by := 6
	for b in by:
		var line := ""
		for c2 in bx:
			var c0 := int(float(c2) * cols / float(bx))
			var c1 := maxi(c0 + 1, int(float(c2 + 1) * cols / float(bx)))
			var r0 := int(float(b) * rows / float(by))
			var r1 := maxi(r0 + 1, int(float(b + 1) * rows / float(by)))
			var s := 0.0
			var mx := 0.0
			var n2 := 0
			for r in range(r0, r1):
				for c in range(c0, c1):
					s += lum[r * cols + c]
					mx = maxf(mx, peak[r * cols + c])
					n2 += 1
			line += "%02d/%02d " % [int(round(s / float(n2) * 99.0)),
					int(round(mx * 99.0))]
		print("行%d |%s" % [b, line])

	print("\n===== ④ 非背景像素的外接框（亮度 > 0.16 视为有内容）=====")
	var min_x := iw
	var max_x := -1
	var min_y := ih
	var max_y := -1
	for y in range(0, ih, 3):
		for x in range(0, iw, 3):
			var col2 := img.get_pixel(x, y)
			var l2 := 0.2126 * col2.r + 0.7152 * col2.g + 0.0722 * col2.b
			if l2 > 0.16:
				min_x = mini(min_x, x)
				max_x = maxi(max_x, x)
				min_y = mini(min_y, y)
				max_y = maxi(max_y, y)
	print("x: %d..%d / %d   y: %d..%d / %d" % [min_x, max_x, iw, min_y, max_y, ih])
	print("左%d 右%d 上%d 下%d（离边像素）" % [min_x, iw - 1 - max_x, min_y, ih - 1 - max_y])

	# ── ⑤ 配色直方图 + 关键语义色的外接框 ──
	# 靠它识别「这是哪个界面」：金色 = 星币/星级，红 = 结构，青 = 强调，纯白 = 大标题。
	var hist := {}
	var gold_box := Rect2i()
	var white_box := Rect2i()
	var gold_n := 0
	var white_n := 0
	for y in range(0, ih, 2):
		for x in range(0, iw, 2):
			var cc := img.get_pixel(x, y)
			var key := "%02x%02x%02x" % [int(cc.r * 15.0), int(cc.g * 15.0),
					int(cc.b * 15.0)]
			hist[key] = int(hist.get(key, 0)) + 1
			var ll := 0.2126 * cc.r + 0.7152 * cc.g + 0.0722 * cc.b
			if ll > 0.62 and cc.r > 0.55 and cc.g > 0.42 and cc.b < cc.g * 0.75:
				gold_n += 1
				gold_box = _grow(gold_box, x, y)
			if ll > 0.86 and absf(cc.r - cc.g) < 0.06 and absf(cc.g - cc.b) < 0.06:
				white_n += 1
				white_box = _grow(white_box, x, y)
	var keys := hist.keys()
	keys.sort_custom(func(a: String, b: String) -> bool:
		return int(hist[a]) > int(hist[b]))
	var total := float((iw / 2 + 1) * (ih / 2 + 1))
	print("\n===== ⑤ 主色（RGB 各 4bit 量化，采样 1/4 像素，共 %d）=====" % int(total))
	for i in mini(14, keys.size()):
		var k: String = keys[i]
		print("  #%s  %5.1f%%" % [k, 100.0 * float(hist[k]) / total])
	print("\n===== ⑥ 语义色区域 =====")
	print("  金色像素 %d 个 · 外接框 %s" % [gold_n, str(gold_box)])
	print("  纯白像素 %d 个 · 外接框 %s" % [white_n, str(white_box)])

	# ── ⑦ 网格取色：每格取中心 3x3 平均，打印 hex —— 用来认出「哪块是 HUD 面板、哪块是星空」──
	print("\n===== ⑦ 网格取色（30×12，格心 hex；左上=第0格）=====")
	var gx := 30
	var gy := 12
	for b in gy:
		var line := ""
		for c2 in gx:
			var cx := int((float(c2) + 0.5) * iw / float(gx))
			var cy := int((float(b) + 0.5) * ih / float(gy))
			var acc := Color(0, 0, 0, 0)
			var n3 := 0
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var px := clampi(cx + dx, 0, iw - 1)
					var py := clampi(cy + dy, 0, ih - 1)
					acc += img.get_pixel(px, py)
					n3 += 1
			acc /= float(n3)
			line += "%02x%02x%02x " % [int(acc.r * 255.0), int(acc.g * 255.0),
					int(acc.b * 255.0)]
		print("%2d|%s" % [b, line])

	# ── ⑧ 连通块：把「非纯黑」的区域找出来，按面积排序 —— 能直接看出有几块面板、是否贴边 ──
	print("\n===== ⑧ 连通块（1/4 降采样，亮度>0.07 为前景，8 连通；坐标已还原到原图）=====")
	var ds := 4
	var mw := iw / ds
	var mh := ih / ds
	var mask := PackedByteArray()
	mask.resize(mw * mh)
	for my in mh:
		for mx in mw:
			var hit := false
			for sy in range(my * ds, my * ds + ds, 2):
				for sx in range(mx * ds, mx * ds + ds, 2):
					var pc := img.get_pixel(sx, sy)
					if 0.2126 * pc.r + 0.7152 * pc.g + 0.0722 * pc.b > 0.07:
						hit = true
			mask[my * mw + mx] = 1 if hit else 0
	var seen := PackedByteArray()
	seen.resize(mw * mh)
	var comps: Array = []
	for my in mh:
		for mx in mw:
			if mask[my * mw + mx] == 0 or seen[my * mw + mx] == 1:
				continue
			var stack: Array = [Vector2i(mx, my)]
			seen[my * mw + mx] = 1
			var cnt := 0
			var x0 := mx
			var x1 := mx
			var y0 := my
			var y1 := my
			while not stack.is_empty():
				var p: Vector2i = stack.pop_back()
				cnt += 1
				x0 = mini(x0, p.x)
				x1 = maxi(x1, p.x)
				y0 = mini(y0, p.y)
				y1 = maxi(y1, p.y)
				for dy2 in range(-1, 2):
					for dx2 in range(-1, 2):
						var q := Vector2i(p.x + dx2, p.y + dy2)
						if q.x < 0 or q.y < 0 or q.x >= mw or q.y >= mh:
							continue
						if mask[q.y * mw + q.x] == 1 and seen[q.y * mw + q.x] == 0:
							seen[q.y * mw + q.x] = 1
							stack.append(q)
			if cnt >= 60:
				comps.append({"n": cnt, "r": Rect2i(x0 * ds, y0 * ds,
						(x1 - x0 + 1) * ds, (y1 - y0 + 1) * ds)})
	comps.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["n"]) > int(b["n"]))
	for i in mini(14, comps.size()):
		var r: Rect2i = comps[i]["r"]
		print("  #%d 面积%6d  矩形 x %4d..%4d  y %4d..%4d  (宽%d 高%d)  %s"
				% [i, int(comps[i]["n"]), r.position.x, r.position.x + r.size.x,
					r.position.y, r.position.y + r.size.y, r.size.x, r.size.y,
					"贴左边" if r.position.x <= 2 else ""])

	# ── ⑨ 细长亮线（面板边框 / 分隔线）：找「比左右各 5px 都亮」的像素，
	#    取每列最长连续段 ⇒ 直接量出面板的竖边框与横边框（背景星云是平滑的，不算）。
	print("\n===== ⑨ 竖线（x · 最长连续段 y0..y1 · 长度）=====")
	var lumf := PackedFloat32Array()
	lumf.resize(iw * ih)
	for y in ih:
		for x in iw:
			var c0 := img.get_pixel(x, y)
			lumf[y * iw + x] = 0.2126 * c0.r + 0.7152 * c0.g + 0.0722 * c0.b
	var vbest: Array = []
	for x in range(5, iw - 5):
		var run := 0
		var best := 0
		var by0 := 0
		var by1 := 0
		var cy0 := 0
		for y in ih:
			var l := lumf[y * iw + x]
			var nb := (lumf[y * iw + x - 5] + lumf[y * iw + x + 5]) * 0.5
			if l > 0.045 and l - nb > 0.012 and l >= lumf[y * iw + x - 1] \
					and l >= lumf[y * iw + x + 1]:
				if run == 0:
					cy0 = y
				run += 1
				if run > best:
					best = run
					by0 = cy0
					by1 = y
			else:
				run = 0
		if best >= 80:
			vbest.append({"x": x, "n": best, "y0": by0, "y1": by1})
	vbest.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["n"]) > int(b["n"]))
	for i in mini(16, vbest.size()):
		var v: Dictionary = vbest[i]
		print("  x=%4d  长%4d  y %4d..%4d" % [int(v["x"]), int(v["n"]),
				int(v["y0"]), int(v["y1"])])

	print("\n===== ⑩ 横线（y · 最长连续段 x0..x1 · 长度）=====")
	var hbest: Array = []
	for y in range(5, ih - 5):
		var run := 0
		var best := 0
		var bx0 := 0
		var bx1 := 0
		var cx0 := 0
		for x in iw:
			var l := lumf[y * iw + x]
			var nb := (lumf[(y - 5) * iw + x] + lumf[(y + 5) * iw + x]) * 0.5
			if l > 0.045 and l - nb > 0.012 and l >= lumf[y * iw + x - 1] \
					and l >= lumf[y * iw + x + 1]:
				if run == 0:
					cx0 = x
				run += 1
				if run > best:
					best = run
					bx0 = cx0
					bx1 = x
			else:
				run = 0
		if best >= 80:
			hbest.append({"y": y, "n": best, "x0": bx0, "x1": bx1})
	hbest.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["n"]) > int(b["n"]))
	for i in mini(16, hbest.size()):
		var hv: Dictionary = hbest[i]
		print("  y=%4d  长%4d  x %4d..%4d" % [int(hv["y"]), int(hv["n"]),
				int(hv["x0"]), int(hv["x1"])])
	quit(0)


func _grow(r: Rect2i, x: int, y: int) -> Rect2i:
	if r.size.x <= 0:
		return Rect2i(x, y, 1, 1)
	var x0 := mini(r.position.x, x)
	var y0 := mini(r.position.y, y)
	var x1 := maxi(r.position.x + r.size.x - 1, x)
	var y1 := maxi(r.position.y + r.size.y - 1, y)
	return Rect2i(x0, y0, x1 - x0 + 1, y1 - y0 + 1)


## 亮度 + 色相 → 一个字节类目。调色板按本工程 UI 的真实配色定：
## 面板底青灰、强调青 C_ACCENT、星币金 C_GOLD、警告橙 C_WARN、结构红 C_HULL。
func _classify(r: float, g: float, b: float, l: float) -> int:
	if l < 0.06:
		return 0                     # 近黑
	var mx := maxf(r, maxf(g, b))
	var mn := minf(r, minf(g, b))
	var sat := 0.0 if mx <= 0.001 else (mx - mn) / mx
	if sat < 0.14:
		return 6 if l > 0.70 else (5 if l > 0.36 else 1)   # 白 / 亮灰 / 暗灰
	var h := 0.0
	var d := mx - mn
	if mx == r:
		h = fmod((g - b) / d, 6.0)
	elif mx == g:
		h = (b - r) / d + 2.0
	else:
		h = (r - g) / d + 4.0
	h *= 60.0
	if h < 0.0:
		h += 360.0
	if h < 20.0 or h >= 335.0:
		return 2                     # 红
	if h < 50.0:
		return 3                     # 橙
	if h < 70.0:
		return 4                     # 金
	if h < 160.0:
		return 5 if l > 0.30 else 4  # 绿 → 归到"暖"
	if h < 200.0:
		return 7                     # 青
	if h < 265.0:
		return 8                     # 蓝
	return 2                         # 紫 → 归红


func _glyph(k: int) -> String:
	match k:
		0: return " "
		1: return "."
		2: return "R"
		3: return "O"
		4: return "G"
		5: return "E"
		6: return "W"
		7: return "C"
		8: return "B"
	return "?"
