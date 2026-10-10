extends RefCounted
class_name EveShipAssetIndex

## EVE 自走棋 —— 舰船资产索引（**机生成，不要手改**）
##
## 生成器：`tools/pipeline/_gen_ship_index.py`
## 数据链：`01_舰船数值全表.csv` → `eve_ship_table.gd`(id/中文名/势力/费用)
##         + ESI `/universe/ids/`(id → typeID) → `_ship_manifest.json`
##         + `eve_ship_build.py`(typeID → 模型) → 本文件
##
## ── 这张表存在的唯一理由 ────────────────────────────────────────
## 用户的要求：「别最后我点的惩罚者级的立绘，上去的是其他船就糟糕了」。
## 错配的根源永远是**按顺序取资源**（第 N 个文件 / 第 N 行）。本表让
## 「id → typeID → 模型文件 → 立绘文件」逐行绑死，
## 全工程只允许 `by_id(id)` 查询，**禁止任何按位置取用**。
##
## ── dims 是干什么的 ────────────────────────────────────────────
## 前四列都是"名字"，名字错了人看不出。dims 是**尺寸三元组（已排序）**：
## 把 assets/ships3d/<id>.glb 载进引擎量出包围盒，与 dims 比对，
## 数值不对就说明这个 .glb 里装的是**另一艘船** —— 这是唯一能穿透
## "文件名正确但内容错误"的检查。

## 一艘船的资产身份
class ShipAsset:
	var id: String
	var typeid: int
	var name_en: String
	var cn: String
	var cost: int
	var dims: PackedFloat32Array       ## 已排序的 (横梁, 高度, 长轴)
	var model: String
	var portrait: String

	func _init(p: Dictionary) -> void:
		id = String(p["id"])
		typeid = int(p["typeid"])
		name_en = String(p["name_en"])
		cn = String(p["cn"])
		cost = int(p["cost"])
		dims = p["dims"]
		model = String(p["model"])
		portrait = String(p["portrait"])


## 期望条目数 —— 与数据表的 52 行严格一致，verify 会对账
const EXPECTED_COUNT := 52

## 原始行：id / typeid / name_en / cn / cost / dims(已排序)
const ROWS: Array = [
	["bantam", 582, "Bantam", "矮脚鸡级", 1, [66.40, 70.70, 78.60]],
	["condor", 583, "Condor", "小鹰级", 1, [27.57, 76.06, 76.28]],
	["kestrel", 602, "Kestrel", "茶隼级", 1, [24.95, 78.55, 99.72]],
	["incursus", 594, "Incursus", "因卡萨斯级", 1, [29.10, 29.34, 68.86]],
	["navitas", 592, "Navitas", "纳维达斯级", 1, [38.34, 50.69, 90.67]],
	["tristan", 593, "Tristan", "特里斯坦级", 1, [47.99, 49.34, 75.54]],
	["burst", 599, "Burst", "爆发级", 1, [17.91, 105.76, 124.30]],
	["rifter", 587, "Rifter", "裂谷级", 1, [28.76, 98.32, 120.61]],
	["slasher", 585, "Slasher", "伐木者级", 1, [35.90, 81.61, 172.26]],
	# ⚠️ 2026-10-06：中文名「磨难级」是错的（英文名 Executioner ⇒ 刽子手级）。
	#    本表第 3 列（英文名）才是模型真身，第 4 列只是显示名 —— 改名不影响取模型。
	["executioner", 589, "Executioner", "刽子手级", 1, [18.77, 41.87, 71.69]],
	["inquisitor", 590, "Inquisitor", "检察官级", 1, [20.68, 52.90, 100.45]],
	["punisher", 597, "Punisher", "惩罚者级", 1, [27.41, 36.60, 65.51]],
	["corax", 32876, "Corax", "渡鸦级", 2, [53.62, 98.14, 258.17]],
	["cormorant", 16238, "Cormorant", "海燕级", 2, [43.02, 161.71, 247.49]],
	["algos", 32872, "Algos", "阿尔格斯级", 2, [49.48, 106.83, 238.79]],
	["catalyst", 16240, "Catalyst", "促进级", 2, [72.97, 88.60, 284.12]],
	["talwar", 32878, "Talwar", "弯刀级", 2, [46.76, 106.11, 262.98]],
	["thrasher", 16242, "Thrasher", "长尾鲛级", 2, [61.98, 67.72, 266.65]],
	["coercer", 16236, "Coercer", "强制者级", 2, [48.16, 114.95, 281.35]],
	["dragoon", 32874, "Dragoon", "龙骑兵级", 2, [44.20, 96.89, 255.58]],
	["caracal", 621, "Caracal", "狞獾级", 3, [148.52, 317.64, 435.67]],
	["moa", 623, "Moa", "巨鸟级", 3, [87.10, 228.44, 329.24]],
	["osprey", 620, "Osprey", "鱼鹰级", 3, [159.50, 239.39, 367.76]],
	["exequror", 634, "Exequror", "送葬者级", 3, [88.17, 134.19, 291.47]],
	["thorax", 627, "Thorax", "托勒克斯级", 3, [83.92, 139.93, 306.74]],
	["vexor", 626, "Vexor", "狂怒者级", 3, [118.48, 188.31, 223.26]],
	["rupture", 629, "Rupture", "断崖级", 3, [79.73, 186.55, 274.99]],
	["scythe", 631, "Scythe", "镰刀级", 3, [112.95, 196.96, 339.79]],
	["stabber", 622, "Stabber", "刺客级", 3, [57.88, 95.40, 347.13]],
	["maller", 624, "Maller", "暴君级", 3, [171.45, 197.61, 227.55]],
	["augoror", 625, "Augoror", "奥格诺级", 3, [76.63, 110.80, 174.51]],
	["omen", 2006, "Omen", "启示级", 3, [102.13, 125.54, 296.54]],
	["drake", 24698, "Drake", "幼龙级", 4, [104.27, 256.53, 519.86]],
	["ferox", 16227, "Ferox", "猛鲑级", 4, [151.94, 280.78, 503.65]],
	["brutix", 16229, "Brutix", "布鲁提克斯级", 4, [195.94, 282.12, 366.70]],
	["myrmidon", 24700, "Myrmidon", "弥尔米顿级", 4, [138.41, 310.58, 601.28]],
	["cyclone", 16231, "Cyclone", "飓风级", 4, [163.94, 181.75, 513.92]],
	["hurricane", 24702, "Hurricane", "暴风级", 4, [69.36, 209.09, 485.55]],
	["harbinger", 24696, "Harbinger", "先驱者级", 4, [79.27, 216.00, 394.88]],
	["prophecy", 16233, "Prophecy", "先知级", 4, [130.16, 256.33, 327.55]],
	["raven", 638, "Raven", "乌鸦级", 5, [221.83, 746.09, 778.11]],
	["rokh", 24688, "Rokh", "鹏鲲级", 5, [181.65, 223.85, 1019.97]],
	["scorpion", 640, "Scorpion", "毒蝎级", 5, [333.16, 652.23, 726.91]],
	["dominix", 645, "Dominix", "多米尼克斯级", 5, [315.14, 482.19, 996.62]],
	["hyperion", 24690, "Hyperion", "亥伯龙神级", 5, [507.11, 640.62, 1494.69]],
	["megathron", 641, "Megathron", "万王宝座级", 5, [384.74, 441.14, 1059.43]],
	["maelstrom", 24694, "Maelstrom", "死亡漩涡级", 5, [263.25, 819.00, 1481.50]],
	["tempest", 639, "Tempest", "狂暴级", 5, [154.06, 857.99, 908.90]],
	["typhoon", 644, "Typhoon", "台风级", 5, [202.97, 302.81, 1059.52]],
	["abaddon", 24692, "Abaddon", "地狱天使级", 5, [263.56, 385.64, 1245.59]],
	["apocalypse", 642, "Apocalypse", "灾难级", 5, [232.55, 398.17, 1529.35]],
	["armageddon", 643, "Armageddon", "末日沙场级", 5, [208.45, 283.03, 1048.17]],
]


static var _by_id: Dictionary = {}
static var _by_typeid: Dictionary = {}


static func _ensure() -> void:
	if not _by_id.is_empty():
		return
	for r in ROWS:
		var a := ShipAsset.new({
			"id": r[0], "typeid": r[1], "name_en": r[2], "cn": r[3], "cost": r[4],
			"dims": PackedFloat32Array(r[5]),
			"model": "res://assets/ships3d/%s.glb" % r[0],
			"portrait": "res://assets/ships/%s.png" % r[0],
		})
		_by_id[a.id] = a
		_by_typeid[a.typeid] = a


## 按 id 取资产身份。查不到时返回 null（调用方必须自己处理，别用默认值兜）。
static func by_id(ship_id: StringName) -> ShipAsset:
	_ensure()
	return _by_id.get(String(ship_id))


## 按 typeID 反查（排障用：拿到一个模型文件，确认它是哪艘船）
static func by_typeid(t: int) -> ShipAsset:
	_ensure()
	return _by_typeid.get(t)


static func all() -> Array:
	_ensure()
	return _by_id.values()


## 索引与数据表是否对得上 —— **双向**比对，返回问题列表。
##
## 单向检查（索引里的每条都能在表里找到）不够：表里多出一艘船、
## 而索引没跟上时，那艘船在引擎里就没有模型可用，且不会报错。
## 所以两个方向都要查，任何一边多出来的都要点名。
static func cross_check_with_table() -> PackedStringArray:
	var problems: PackedStringArray = []
	_ensure()
	var from_index := {}
	for a in all():
		from_index[a.id] = true
	var from_table := {}
	for row in EveShipTable.ROWS:
		from_table[String(row[0])] = true
	for id in from_table.keys():
		if not from_index.has(id):
			problems.append("数据表有 %s，索引里没有" % id)
	for id in from_index.keys():
		if not from_table.has(id):
			problems.append("索引有 %s，数据表里没有" % id)
	return problems


## 资产完整性自检 —— 返回问题列表，空数组表示 52 艘的关联全部成立。
##
## 检查：条数 / id 与英文名可互推 / 立绘存在且文件名 == id /
##       模型存在且文件名 == id / dims 是三个正数。
## 注意这里**不**校验模型内容 —— 那需要真载入 GLB 量包围盒，
## 由 tools/verify_ship_assets.gd 做（静态函数没法安全加载资源）。
static func audit() -> PackedStringArray:
	var problems: PackedStringArray = []
	_ensure()
	if ROWS.size() != EXPECTED_COUNT:
		problems.append("索引条数 %d ≠ 期望 %d" % [ROWS.size(), EXPECTED_COUNT])
	for a in all():
		if a.id != a.name_en.to_lower():
			problems.append("%s id 与英文名 %s 不一致" % [a.id, a.name_en])
		if a.portrait.get_file().get_basename() != a.id:
			problems.append("%s 立绘文件名 %s 与 id 不符" % [a.id, a.portrait])
		if not FileAccess.file_exists(a.portrait):
			problems.append("%s 缺立绘 %s" % [a.id, a.portrait])
		if a.model.get_file().get_basename() != a.id:
			problems.append("%s 模型文件名 %s 与 id 不符" % [a.id, a.model])
		if not FileAccess.file_exists(a.model):
			problems.append("%s 缺模型 %s" % [a.id, a.model])
		if a.dims.size() != 3:
			problems.append("%s dims 不是三元组" % a.id)
		else:
			for v in a.dims:
				if v <= 0.0:
					problems.append("%s dims 含非正数" % a.id)
					break
	return problems
