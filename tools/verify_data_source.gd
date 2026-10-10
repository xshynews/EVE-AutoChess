extends Node

## 数据源交叉验收：**仓库里的 CSV ↔ 游戏里用的 GDScript 表**（审查 2#4）
##
## ══════════════════════════════════════════════════════════════════
##  为什么需要这条
## ══════════════════════════════════════════════════════════════════
##  `scripts/data/*.gd` 里的表是**人工从 CSV 搬过来的**（CSV 以前只存在作者电脑上，
##  别人拿不到）。搬过来的东西就会漂：改了一边忘了另一边，游戏里的数值
##  和设计稿就悄悄分家 —— 而且**没有任何东西会报错**。
##  ⇒ 现在 CSV 进了仓库（`data/source_csv/`），就可以让两边对拍：
##     以 CSV 为设计侧真值，逐列比对 GDScript 表。
##
##  ⚠️ 两个来源必须**互相独立**：这里读的是 CSV 原文（`FileAccess`），
##     比对的是 `EveShipTable.ROWS` 常量 —— 没有共用同一张表（红线：严禁共用）。
##
##  ⚠️ 只比对**有明确映射**的列。像 `装甲/结构` 这种合并列，CSV 只有一个数，
##     拆分规则在 `eve_ship_database.gd` 里 ⇒ 比的是合并列本身。
##
## 用法：
##   Godot_v4.7.2-stable_win64_console.exe --headless \
##     --path "<工程>" --quit-after 4000 res://tools/verify_data_source.tscn

const SHIP_TABLE := preload("res://scripts/data/eve_ship_table.gd")
const ENEMY := preload("res://scripts/data/eve_enemy_comps.gd")
const NODES := preload("res://scripts/data/eve_node_table.gd")

const SHIP_CSV := "res://data/source_csv/01_舰船数值全表.csv"
const COMP_CSV := "res://data/source_csv/03_敌人编组表.csv"
const NODE_CSV := "res://data/source_csv/04_节点表_遥望边境.csv"

## ★★ **已登记的有意分歧**（CSV 是设计稿快照，落地时改过）。
##
## ⚠️⚠️ 白名单不是"消音器"。三条使用规则：
##   ① 每条必须写**理由**，且理由只能是"**已知的有意改动**"；
##   ② 只允许 `cols` 里列出的列不同 —— 同一行的**别的列**漂了照样红；
##   ③ 拿它掩盖新漂移 = 把这条验收直接废掉（宁可不加）。
const KNOWN_DIFF := {
	"executioner": {
		"cols": ["中文名"],
		"why": "正名：磨难级 → 刽子手级（只改显示名，见 MEMORY 红线 1）",
	},
	"arbitrator": {
		"cols": ["船ID", "中文名", "护盾", "装甲/结构", "攻击"],
		"why": "该船已下线，行位换成 maller（主宰级换装，V0.13 已删 arbitrator 资产）",
	},
}

var _pass := 0
var _fail := 0


func _ready() -> void:
	print("═══ verify_data_source（CSV ↔ GDScript 表对拍）═══")
	_t_ship_csv()
	_t_enemy_comps_csv()
	_t_node_csv()
	print("")
	print("═══ RESULT passed=%d failed=%d ═══" % [_pass, _fail])
	print("VERIFY_DONE failed=%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


func _ok(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
		print("  ✓ %s" % msg)
	else:
		_fail += 1
		print("  ✗ [FAIL] %s" % msg)


# ---------------------------------------------------------------- CSV 读入
## 极简 CSV 读入（支持双引号包裹的字段；本项目的数据表没有跨行字段）。
func _read_csv(path: String) -> Array:
	var out: Array = []
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_warning("[数据源] 打不开 %s" % path)
		return out
	var first := true
	while not f.eof_reached():
		var line := f.get_line()
		if first:
			# ⚠️ UTF-8 BOM：Excel 存的 CSV 会在首行前带 `\ufeff`，
			#    不剥掉的话第一列名会变成 "\ufeff船ID"（踩过）。
			line = line.trim_prefix("\ufeff")
			first = false
		if line.strip_edges().is_empty():
			continue
		out.append(_split_csv(line))
	return out


func _split_csv(line: String) -> Array:
	var out: Array = []
	var cur := ""
	var in_q := false
	for i in line.length():
		var ch := line[i]
		if in_q:
			if ch == "\"":
				in_q = false
			else:
				cur += ch
		else:
			if ch == "\"":
				in_q = true
			elif ch == ",":
				out.append(cur)
				cur = ""
			else:
				cur += ch
	out.append(cur)
	return out


# ---------------------------------------------------------------- ① 舰船表
func _t_ship_csv() -> void:
	print("── 01_舰船数值全表.csv ↔ EveShipTable.ROWS ──")
	var rows := _read_csv(SHIP_CSV)
	if rows.is_empty():
		_ok(false, "读得到舰船 CSV")
		return
	_ok((rows[0] as Array).size() >= 14,
			"CSV 表头 14 列（实际 %d）" % (rows[0] as Array).size())
	var body: Array = rows.slice(1)
	var table: Array = SHIP_TABLE.ROWS
	_ok(body.size() == table.size(),
			"★ CSV 行数 == 表行数（%d vs %d）" % [body.size(), table.size()])
	var n: int = mini(body.size(), table.size())
	var bad := 0
	var known_rows := 0
	for i in n:
		var c: Array = body[i] as Array
		var r: Array = table[i] as Array
		var diffs := _diff_ship_row(c, r)
		# 已登记的有意分歧：只放行 `cols` 里列出的列
		var known: Dictionary = KNOWN_DIFF.get(str(c[0]).strip_edges(), {})
		if not known.is_empty() and not diffs.is_empty():
			var allowed: Array = known.get("cols", [])
			var real: Array = []
			for d in diffs:
				var col := String(d).split("(")[0]
				if not allowed.has(col):
					real.append(d)
			if real.is_empty():
				known_rows += 1
				continue
			diffs = real
		if not diffs.is_empty():
			bad += 1
			if bad <= 6:
				print("      ✗ 第 %d 行（%s）：%s"
						% [i + 1, str(c[0]), ", ".join(diffs)])
	_ok(bad == 0,
			"★ 逐艘逐列与 CSV 一致（不一致 %d 行 / 共 %d 行）" % [bad, n])
	print("      · 另有 %d 行属**已登记的有意分歧**（理由见 KNOWN_DIFF）" % known_rows)
	# ★★ 对拍函数**自证牙齿**（红线：断言必须先确认真的会执行）——
	#     上一版这里 `String(bool)` 直接报错，把「后勤」列整列比空了却照样全绿。
	#     ⇒ 用同一行的「表值转字符串再比」当基准，然后**故意改一列**看它抓不抓得到。
	if table.size() > 0:
		var t0: Array = (table[0] as Array).duplicate()
		var c0: Array = []
		for v in t0:
			c0.append(str(v))
		_ok(_diff_ship_row(c0, t0).is_empty(),
				"对拍函数自证：同源两行 ⇒ 判为一致")
		c0[9] = str(int(t0[9]) + 3)          # 攻击 +3
		var d1 := _diff_ship_row(c0, t0)
		_ok(d1.size() == 1 and String(d1[0]).begins_with("攻击"),
				"对拍函数自证：改「攻击」一列 ⇒ 恰好 1 处差异（实际 %d 处：%s）"
				% [d1.size(), ", ".join(d1)])


## 返回不一致的列描述（空 = 完全一致）。列序与 CSV 表头一致。
func _diff_ship_row(c: Array, r: Array) -> Array:
	var out: Array = []
	if c.size() < 14 or r.size() < 14:
		out.append("列数不足（CSV %d / 表 %d）" % [c.size(), r.size()])
		return out
	var spec: Array = [
		["船ID", 0, "s"], ["中文名", 1, "s"], ["势力", 2, "s"], ["武器", 3, "s"],
		["防御", 4, "s"], ["费用", 5, "i"], ["定位", 6, "s"], ["护盾", 7, "i"],
		["装甲/结构", 8, "i"], ["攻击", 9, "i"], ["射程", 10, "i"],
		["移速", 11, "f"], ["攻击间隔", 12, "i"], ["后勤", 13, "b"],
	]
	for s in spec:
		var col := String(s[0])
		var idx := int(s[1])
		var kind := String(s[2])
		var a := str(c[idx]).strip_edges()
		var b := str(r[idx]).strip_edges()
		var same := false
		match kind:
			"s":
				same = (a == b)
			"i":
				same = (a.to_int() == b.to_int())
			"f":
				same = absf(a.to_float() - b.to_float()) < 1e-6
			"b":
				same = (a == "是" or a.to_lower() == "true") == (b.to_lower() == "true")
		if not same:
			out.append("%s(CSV=%s 表=%s)" % [col, a, b])
	return out


# ---------------------------------------------------------------- ② 敌方编组
func _t_enemy_comps_csv() -> void:
	print("── 03_敌人编组表.csv ↔ EveEnemyComps.COMPS ──")
	var rows := _read_csv(COMP_CSV)
	if rows.is_empty():
		_ok(false, "读得到编组 CSV")
		return
	var body: Array = rows.slice(1)
	_ok(body.size() == ENEMY.COMPS.size(),
			"★ CSV 编组数 == 表项数（%d vs %d）" % [body.size(), ENEMY.COMPS.size()])
	var bad := 0
	for row in body:
		var a: Array = row
		var id := String(a[0]).strip_edges()
		if not ENEMY.COMPS.has(id):
			bad += 1
			print("      ✗ 编组 %s 不在 EveEnemyComps.COMPS" % id)
			continue
		var want := int(String(a[3]).strip_edges())      # 艘数
		var got := ENEMY.size_of(id)
		if want != got:
			bad += 1
			print("      ✗ 编组 %s 艘数 CSV=%d 表=%d" % [id, want, got])
	_ok(bad == 0, "★ 编组 id + 艘数与 CSV 一致（不一致 %d）" % bad)


# ---------------------------------------------------------------- ③ 节点表
func _t_node_csv() -> void:
	print("── 04_节点表_遥望边境.csv ↔ EveNodeTable ──")
	var rows := _read_csv(NODE_CSV)
	if rows.is_empty():
		_ok(false, "读得到节点 CSV")
		return
	var body: int = rows.size() - 1
	_ok(body == NODES.TOTAL,
			"★ 节点 CSV 行数 == EveNodeTable.TOTAL（%d vs %d）" % [body, NODES.TOTAL])
