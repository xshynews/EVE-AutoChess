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
	print("           分段：① 归一化(只钉最长轴) → ② 吨位档基准长 → ③ 档内 ±5%")
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
			"dims": "%.1f×%.1f×%.1f" % [beam, height, mx],
		})


## ① 吨位档基准（可改的旋钮）
func _print_ladder() -> void:
	print("")
	print("── ① 吨位 → 屏幕最长轴（档基准 = 可改旋钮）──")
	print("%-9s %-5s %-10s %-14s" % ["吨位", "刻度", "档基准长", "档内范围(±5%)"])
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