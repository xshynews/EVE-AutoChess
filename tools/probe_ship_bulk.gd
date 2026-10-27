extends Node

## 舰船「体量」分析探针 —— 补 `probe_ship_size` 的盲区。
##
## ══════════════════════════════════════════════════════════════════
##  为什么还要一个（`probe_ship_size` 已经量了世界船长了）
## ══════════════════════════════════════════════════════════════════
##  `probe_ship_size` 只量**最长轴**，并据此判「相邻档是否重叠」——
##  它永远给出「✓ 不重叠」，因为归一化**恰好钉住了最长轴**。
##
##  但玩家报的是：「巡洋，尤其是暴君等船那是真的大，比战列都大」。
##  这句话在**最长轴**上不成立（暴君 3.21 < 战列 4.2），
##  在**体量**（长×宽×高的整体）上却成立 —— 因为归一化只钉长度，
##  敦实的船（暴君 宽/长=0.87）宽度照样巨大。
##
##  本探针把「屏幕上长 × 宽 × 高」换算成一个可比数：
##      体积指数 = 屏幕长³ × (中轴/真实长) × (短轴/真实长)
##  等价于「屏幕体积 / 真实最长轴³」，用于同口径横向比大小。
##
##  跑法：
##    godot_console.exe --headless --path <工程> res://tools/probe_ship_bulk.tscn

const VIS := preload("res://scripts/visual/eve_ship_visual.gd")

var _rows: Array = []         ## [{id, cn, cost, cls, dims, dim, screen_len, vol, wide}]


func _ready() -> void:
	_collect()
	print("=".repeat(92))
	print("[体量分析] 归一化基准 HULL_REF_LENGTH=%.3f · 放大 VISUAL_EXAGGERATION=%.2f · 档内微调 ±%.0f%%"
			% [VIS.HULL_REF_LENGTH, VIS.VISUAL_EXAGGERATION, VIS.CLASS_SCALE_SPREAD * 100.0])
	print("           分段：① 归一化(钉最长轴) → ② 吨位档基准(体积等效尺度 E) → ③ 档内微调")
	print("                 ④ 体积等效：屏幕长 = 档基准 × (真实长 / E)，E = 长^%.2f × 体积^%.2f"
			% [VIS.SIZE_BLEND, (1.0 - VIS.SIZE_BLEND) / 3.0])
	print("                 ⑤ 体积指数 = 屏幕长³ × (横梁/真实长) × (高度/真实长)  ← 「看着多大」的真口径")
	print("=".repeat(92))
	_print_ladder()
	_print_by_class()
	_print_ranking()
	_print_monotonic()
	get_tree().quit()


func _collect() -> void:
	for a in EveShipAssetIndex.all():
		if a == null:
			continue
		var cls := int(EveShip.CLASS_BY_COST.get(int(a.cost), -1))
		if cls < 0:
			continue
		var sid := StringName(a.id)
		# `ShipAsset.dims` 已排序 = (横梁, 高度, 长轴)
		var dims: Array[float] = []
		for v in a.dims:
			dims.append(float(v))
		if dims.size() < 3:
			continue
		var beam := dims[0]
		var height := dims[1]
		var mx := dims[2]
		var sl := VIS.target_hull_length(sid, cls)
		# 体积指数 = 屏幕长³ × (横梁/长) × (高度/长)
		var vol := sl * sl * sl * (beam / maxf(mx, 0.001)) * (height / maxf(mx, 0.001))
		_rows.append({
			"id": sid, "cn": String(a.cn),
			"cost": int(a.cost), "cls": cls, "dim": mx, "sl": sl,
			"vol": vol, "wide": beam / maxf(mx, 0.001),
			"beam": beam, "height": height,
			"dims": "%.1f×%.1f×%.1f" % [beam, height, mx],
		})


## ① 吨位档基准（可改的旋钮）
func _print_ladder() -> void:
	print("")
	print("── ① 吨位 → 屏幕最长轴（档基准 = 可改旋钮）──")
	print("%-9s %-5s %-10s %-14s" % ["吨位", "刻度", "档基准长", "档内范围(±%.0f%%)" % (VIS.CLASS_SCALE_SPREAD * 100.0)])
	for cls in _tiers():
		var base := VIS.tier_base_length(cls)
		print("%-9s %-5d %-10.3f %.3f ~ %.3f" % [_cn(cls), VIS.tier_level(cls), base,
				base * (1.0 - VIS.CLASS_SCALE_SPREAD),
				base * (1.0 + VIS.CLASS_SCALE_SPREAD)])


func _print_by_class() -> void:
	print("")
	print("── ② 逐艘（档内按体积指数降序）──")
	print("%-12s %-14s %-4s %-16s %-8s %-8s %s" % [
			"ID", "中文名", "费", "真实 短×中×长(m)", "屏幕长", "体积指数", "宽/长"])
	for cls in _tiers():
		var sub: Array = []
		for r in _rows:
			if r["cls"] == cls:
				sub.append(r)
		sub.sort_custom(func(x, y): return float(x["vol"]) > float(y["vol"]))
		print("")
		print("  ▼ %s（%d 艘）" % [_cn(cls), sub.size()])
		for r in sub:
			print("%-12s %-14s %-4d %-16s %-8.3f %-8.3f %.2f" % [
					r["id"], r["cn"], r["cost"], r["dims"], r["sl"], r["vol"], r["wide"]])


## ③ 跨吨位总排序 —— 用户看到的「暴君比战列大」就藏在这里
func _print_ranking() -> void:
	var all := _rows.duplicate()
	all.sort_custom(func(x, y): return float(x["vol"]) > float(y["vol"]))
	print("")
	print("── ③ 体积指数总排序（前 12 / 后 6）──")
	print("%-4s %-12s %-14s %-9s %-4s %s" % ["#", "ID", "中文名", "吨位", "费", "体积指数"])
	for i in all.size():
		if i < 12 or i >= all.size() - 6:
			print("%-4d %-12s %-14s %-9s %-4d %.2f" % [
					i + 1, all[i]["id"], all[i]["cn"], _cn(all[i]["cls"]),
					all[i]["cost"], all[i]["vol"]])
		elif i == 12:
			print("     …")


## ④ 档序单调性：高档位的**最小**体积指数 ≥ 低档位的**最大**体积指数？
func _print_monotonic() -> void:
	print("")
	print("── ④ 档序单调性（体量口径）──")
	var t := _tiers()
	var bad := 0
	for i in range(t.size() - 1):
		var hi := _max_vol(t[i])
		var lo := _min_vol(t[i + 1])
		var ok := lo >= hi
		if not ok:
			bad += 1
		print("  %-9s 最大 %.2f  vs  %-9s 最小 %.2f   %s" % [
				_cn(t[i]), hi, _cn(t[i + 1]), lo,
				"✓ 不重叠" if ok else "✗ 重叠 %.2f" % (hi - lo)])
	print("  ⇒ %s" % ("★ 体量档序严格单调 ✓（玩家看到的「小/大」由吨位决定）" if bad == 0
			else "⚠ 有 %d 处重叠 —— 这就是「巡洋比战列大」的来源" % bad))
	_print_compactness()
	_print_sweep()


## ⑤ 紧缩度 c = (横梁 × 高度) / 长轴² —— 体积等效尺度的**唯一**形状变量
##
## 推导（这是标定旋钮的数学基础，别跳过）：
##   屏幕最长轴 sl = B(档) × (真实长 a / E)，E = a^w × V^((1−w)/3)
##   体积指数 = sl³ × (横梁/a) × (高度/a) = sl³ × V / a³   （V = 包围盒体积）
##                     = B³ × (V / a³)^w  = B³ × c^w
##   ⇒ **同档内的体积指数只由 c 决定**；档与档之间只由 B 决定。
##   ⇒ 档序不重叠的充要条件（相邻档 lo→hi）：
##        3·ln(B_hi / B_lo)  ≥  w · ln(c_max_lo / c_min_hi)
##   左边是**可调的档差**，右边是**形状噪声**（现在是 w 的系数）。
func _print_compactness() -> void:
	print("")
	print("── ⑤ 紧缩度 c = 横梁×高度/长轴²（同档体积差的唯一来源）──")
	print("%-9s %-8s %-8s %-8s %s" % ["吨位", "c 最小", "c 最大", "极差", "最极端的船"])
	for cls in _tiers():
		var lo := INF
		var hi := -INF
		var lo_id := ""
		var hi_id := ""
		for r in _rows:
			if r["cls"] != cls:
				continue
			var c := _compactness(r)
			if c < lo:
				lo = c
				lo_id = String(r["cn"])
			if c > hi:
				hi = c
				hi_id = String(r["cn"])
		print("%-9s %-8.4f %-8.4f %-8.2f 细长 %s ↔ 敦实 %s" % [
				_cn(cls), lo, hi, hi / maxf(lo, 1e-6), lo_id, hi_id])
	print("")
	print("  相邻档允许的最大 w（越小越安全；w=0 ⇒ 纯粹按吨位定大小）:")
	for i in range(_tiers().size() - 1):
		var k_lo := _cmax(_tiers()[i])
		var k_hi := _cmin(_tiers()[i + 1])
		var b_lo := VIS.tier_base_length(_tiers()[i])
		var b_hi := VIS.tier_base_length(_tiers()[i + 1])
		if k_lo <= 0.0 or k_hi <= 0.0 or b_lo <= 0.0 or b_hi <= 0.0:
			continue
		var w_max := 3.0 * log(b_hi / b_lo) / log(k_lo / k_hi)
		print("    %s → %s：%.3f" % [_cn(_tiers()[i]), _cn(_tiers()[i + 1]), w_max])


## ⑥ 旋钮扫描：在**不改常量**的前提下，用公式重算「若取 (LOW,HIGH,w)」
##    会怎样 —— 直接告出哪一组能做到档序零重叠。
func _print_sweep() -> void:
	print("")
	print("── ⑥ 旋钮扫描（LOW/HIGH/w → 档序重叠处数 / 体积极差）──")
	print("%-7s %-7s %-6s %-9s %-11s %-11s %s" % [
			"LOW", "HIGH", "倍率", "w", "重叠处", "同档体积差", "结论"])
	var best := {}
	for low in [1.10, 1.30, 1.60, 1.90]:
		for high in [3.10, 3.60, 4.10, 4.60]:
			for w in [0.0, 0.15, 0.30, 0.45, 0.60]:
				var r := _eval(low, high, w)
				var ok := int(r["bad"]) == 0
				if ok and (best.is_empty() or float(r["spread"]) < float(best["spread"])):
					best = {"low": low, "high": high, "w": w,
							"bad": 0, "spread": r["spread"]}
				if w in [0.0, 0.30, 0.60] or ok:
					print("%-7.2f %-7.2f %-6.2f %-9.2f %-11d %-11.2f %s" % [
							low, high, high / low, w, int(r["bad"]), float(r["spread"]),
							"★ 零重叠" if ok else "重叠 %d 处" % int(r["bad"])])
	print("")
	if best.is_empty():
		print("  ⚠ 扫描范围内没有零重叠的组合 —— 需要继续放宽 HIGH")
	else:
		print("  ★ 推荐（零重叠里形状影响最大者）：LOW=%.2f HIGH=%.2f（档差 %.2f 倍）w=%.2f"
				% [float(best["low"]), float(best["high"]),
						float(best["high"]) / float(best["low"]), float(best["w"])])
		print("    同档内体积极差 %.2f 倍 —— 越小越「同档看着一样大」"
				% float(best["spread"]))


## 用尝试参数重算全部船的体积指数，返回 {bad, spread}
func _eval(low: float, high: float, w: float) -> Dictionary:
	var vols: Dictionary = {}
	for r in _rows:
		var a := float(r["dim"])
		var c := _compactness(r)
		# E 只用到 c^((1-w)/3) 的比值 ⇒ sl = B × c^(-(1-w)/3)
		var lv := VIS.tier_level(int(r["cls"]))
		var b := low + (high - low) * float(lv - 1) / 9.0
		var sl := b * pow(maxf(c, 1e-9), -(1.0 - w) / 3.0)
		if sl <= 0.0:
			continue
		# 体积指数 = sl³ × c
		var vi := sl * sl * sl * c
		vols[r["id"]] = vi
	var bad := 0
	for i in range(_tiers().size() - 1):
		var hi := -INF
		var lo := INF
		for r in _rows:
			if r["cls"] == _tiers()[i]:
				hi = maxf(hi, float(vols.get(r["id"], 0.0)))
			elif r["cls"] == _tiers()[i + 1]:
				lo = minf(lo, float(vols.get(r["id"], 0.0)))
		if lo < hi:
			bad += 1
	# 同档内体积极差（取各档极端值的最大者）
	var spread := 0.0
	for cls in _tiers():
		var mx := -INF
		var mn := INF
		for r in _rows:
			if r["cls"] == cls:
				mx = maxf(mx, float(vols.get(r["id"], 0.0)))
				mn = minf(mn, float(vols.get(r["id"], 0.0)))
		if mn > 0.0:
			spread = maxf(spread, mx / mn)
	return {"bad": bad, "spread": spread}


func _compactness(r: Dictionary) -> float:
	var a := maxf(float(r["dim"]), 1e-6)
	return float(r["beam"]) * float(r["height"]) / (a * a)


func _cmax(cls: int) -> float:
	var m := -INF
	for r in _rows:
		if r["cls"] == cls:
			m = maxf(m, _compactness(r))
	return m


func _cmin(cls: int) -> float:
	var m := INF
	for r in _rows:
		if r["cls"] == cls:
			m = minf(m, _compactness(r))
	return m


func _tiers() -> Array:
	return [EveShip.Class.FRIGATE, EveShip.Class.DESTROYER, EveShip.Class.CRUISER,
			EveShip.Class.BATTLE_CRUISER, EveShip.Class.BATTLESHIP]


func _min_vol(cls: int) -> float:
	var m := INF
	for r in _rows:
		if r["cls"] == cls:
			m = minf(m, float(r["vol"]))
	return m


func _max_vol(cls: int) -> float:
	var m := -INF
	for r in _rows:
		if r["cls"] == cls:
			m = maxf(m, float(r["vol"]))
	return m


func _cn(cls: int) -> String:
	match cls:
		EveShip.Class.FRIGATE:        return "护卫舰"
		EveShip.Class.DESTROYER:      return "驱逐舰"
		EveShip.Class.CRUISER:        return "巡洋舰"
		EveShip.Class.BATTLE_CRUISER: return "战列巡洋"
		EveShip.Class.BATTLESHIP:     return "战列舰"
		_:                            return "?"