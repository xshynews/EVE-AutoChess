extends "res://scripts/ui/eve_window.gd"

## EVE 自走棋 —— 舰船档案窗（右列上）
##
## 内容口径 = 云顶之弈的棋子信息面板（用户原话「参考云顶之弈的棋子信息」）：
##   立绘 → 名称 + 星级 → 羁绊（n/m + 是否生效）→ 三层血量 →
##   六格属性 → 特性 → 装备 2 格
##
## ── 两态（V3 稿定稿）────────────────────────────────────────────
##   收起 172 × 128：默认。只有一枚淡淡的机库剪影 + 「点击舰船查看」
##   展开 172 × 320：点到舰船（战场 / 备战席 / 商店卡任一处）才展开
##   展开后底边落在 y=376，右下战斗日志从 y=384 起 —— 刚好不打架。
##
## ── 立绘 ────────────────────────────────────────────────────────
##   官方 1024px 渲染图 → 语义分割抠像 → 512×512 透明底画布，
##   落在 res://assets/ships/<id>.png，由 EveShipArt 取用并缓存。
##   缺图自动退回程序化侧影（见 _Portrait）。
##
## 变更清单（实装版）：
##   - 收起 / 展开两态 + 动画无关的瞬时切换
##   - 三组羁绊行（势力 / 武器 / 防御），带 n/m 与生效高亮
##   - 属性按【权威表原值】显示（攻击 / 攻击间隔 / 射程格 / 移速格），
##     只有「信号半径 / 吨位」是工程派生值（权威表没有这两列）

## ★ 2026-10-10（审查 2#5）：`_extra` 键名常量（拼错键不报错 ⇒ 用常量）。
const CIDS := preload("res://scripts/core/eve_combat_ids.gd")
## ★ 2026-10-10（i18n）：术语取词（见 `eve_terms.gd` 顶注）。
const TERMS := preload("res://scripts/core/eve_terms.gd")
## ★ 2026-10-10（i18n）：文案取词（见 `eve_text.gd` 顶注）。
const T := preload("res://scripts/core/eve_text.gd")

const W_COLLAPSED := 128.0
const H_COLLAPSED := 128.0
const H_EXPANDED := 320.0

var ship: EveShip = null

var _portrait: Control
var _name_label: Label
var _meta_label: Label
var _star_label: Label
var _trait_rows: Array[Dictionary] = []
var _bars: Dictionary = {}
var _hp_labels: Dictionary = {}
var _stat_labels: Dictionary = {}
var _trait_box: VBoxContainer
var _eq_row: HBoxContainer

var _built := false


func _ready() -> void:
	# ★ 本窗**自己**实现收起/展开（128 ↔ 320）⇒ ⛔ 关掉 EveWindow 的通用的收起，
	#   否则两套收起会互相打架（一个收一个展，看起来像抽风）。
	collapsible = false
	persist_layout = false   # 它自己管高度，别让玩家的拖动记录压过 128/320
	window_title = T.t("DOSSIER_TITLE", "舰船档案")
	density = Density.COMPACT
	show_status_text = false
	super._ready()
	_build_contents()
	_built = true
	collapse()


## 收起 = 只有提示；展开 = 完整内容
##
## ⚠️ 切的是两个内容盒的 visible，不是 content 的 ——
##    content 是 EveWindow 的内容容器，把它隐藏了收起态也是一片空白。
func _set_expanded(on: bool) -> void:
	if _empty_box:
		_empty_box.visible = not on
	if _full_box:
		_full_box.visible = on
	set_window_height(H_EXPANDED if on else H_COLLAPSED)


func collapse() -> void:
	ship = null
	_set_expanded(false)


# ------------------------------------------------------------------ 构建

func _build_contents() -> void:
	# 收起态的提示（与展开态互斥显示）
	_empty_box = VBoxContainer.new()
	_empty_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_empty_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_empty_box.add_theme_constant_override("separation", 5)
	content.add_child(_empty_box)

	var ic := EveIcon.make(&"hangar", 30, Color(0.55, 0.78, 0.82, 0.30), 1.4)
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_empty_box.add_child(ic)

	var h := Label.new()
	h.text = T.t("DOSSIER_EMPTY_H", "点击舰船查看")
	h.add_theme_color_override("font_color", Color(0.561, 0.651, 0.686))
	FONT.fs(h, 11)
	h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_box.add_child(h)

	var p := Label.new()
	p.text = T.t("DOSSIER_EMPTY_P", "战场 / 备战席 / 商店卡\n任一处点选即可")
	p.add_theme_color_override("font_color", C_TEXT_FAINT)
	FONT.fs(p, 9)
	p.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_box.add_child(p)

	# ── 以下是展开态内容（先建好，整体切 visible）──
	#
	# ⚠️ separation 必须压到 3：320 高的窗（扣掉 26 标题栏 + 14 内边距 = 280）
	#    要装下「立绘 / 名称 / 元信息 / 3 羁绊行 / 3 血条 / 6 属性 / 定位 / 2 装备格」，
	#    按 4 算会超出约 20px —— 表现为最底下两个装备格被窗底裁掉（实测过一次）。
	_full_box = VBoxContainer.new()
	_full_box.add_theme_constant_override("separation", 3)
	_full_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(_full_box)

	# 立绘位
	_portrait = _Portrait.new()
	_portrait.custom_minimum_size = Vector2(0, 38)
	_full_box.add_child(_portrait)

	# 名称 + 星级
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	_full_box.add_child(head)

	_name_label = Label.new()
	_name_label.text = T.t("DOSSIER_NONE", "未选中")
	_name_label.add_theme_color_override("font_color", Color(0.918, 0.969, 0.980))
	FONT.fs(_name_label, 12)
	_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(_name_label)

	_star_label = Label.new()
	_star_label.text = ""
	_star_label.add_theme_color_override("font_color", C_GOLD)
	FONT.fs(_star_label, 10)
	_star_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(_star_label)

	_meta_label = Label.new()
	_meta_label.text = ""
	_meta_label.add_theme_color_override("font_color", C_TEXT_DIM)
	FONT.fs(_meta_label, 9)
	_meta_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_full_box.add_child(_meta_label)

	# 羁绊 3 行（势力 / 武器 / 防御）
	_trait_box = VBoxContainer.new()
	_trait_box.add_theme_constant_override("separation", 1)
	_full_box.add_child(_trait_box)
	for g in EveTraitTable.GROUPS:
		_trait_rows.append(_build_trait_row(g["key"]))

	_full_box.add_child(make_divider())

	# 三层血量
	for item in [
		[T.t("DOSSIER_HP_SHIELD", "护盾"), "shield", C_SHIELD],
		[T.t("DOSSIER_HP_ARMOR", "装甲"), "armor", C_ARMOR],
		[T.t("DOSSIER_HP_HULL", "结构"), "hull", C_HULL],
	]:
		var bar_row := make_bar_row(String(item[0]), item[2], 1.0, 26.0, 44.0)
		_full_box.add_child(bar_row["row"])
		_bars[item[1]] = bar_row["bar"]
		_hp_labels[item[1]] = bar_row["num"]

	_full_box.add_child(make_divider())

	# 六格属性（2 列 × 3 行）
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 0)
	_full_box.add_child(grid)
	for item in [
		[T.t("DOSSIER_ATTR_ATTACK", "攻击"), "attack"],
		[T.t("DOSSIER_ATTR_INTERVAL", "攻击间隔"), "interval"],
		[T.t("DOSSIER_ATTR_RANGE", "射程"), "range"],
		[T.t("DOSSIER_ATTR_SPEED", "移速"), "speed"],
		[T.t("DOSSIER_ATTR_SIG", "信号半径"), "sig"],
		[T.t("DOSSIER_ATTR_CLASS", "吨位"), "class"],
	]:
		var row := _build_attr(String(item[0]), String(item[1]))
		grid.add_child(row["root"])
		_stat_labels[item[1]] = row["value"]

	_full_box.add_child(make_divider())

	# 特性 / 定位
	_role_label = Label.new()
	_role_label.text = T.t("DOSSIER_ROLE_NONE", "定位　—")
	_role_label.add_theme_color_override("font_color", C_TEXT_DIM)
	FONT.fs(_role_label, 10)
	_role_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_role_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_full_box.add_child(_role_label)

	# 装备 2 格
	_eq_row = HBoxContainer.new()
	_eq_row.add_theme_constant_override("separation", 5)
	_full_box.add_child(_eq_row)
	for i in 2:
		var slot := EveSlot.new()
		slot.custom_minimum_size = Vector2(30, 30)
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_eq_row.add_child(slot)


var _empty_box: VBoxContainer
var _full_box: VBoxContainer
var _role_label: Label


func _build_trait_row(group: StringName) -> Dictionary:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var chip := ColorRect.new()
	chip.custom_minimum_size = Vector2(10, 10)
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(chip)

	var nm := Label.new()
	nm.text = "—"
	nm.add_theme_color_override("font_color", C_TEXT)
	FONT.fs(nm, 10)
	nm.custom_minimum_size = Vector2(50, 0)
	nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(nm)

	var ratio := Label.new()
	ratio.text = "0/0"
	ratio.add_theme_color_override("font_color", Color(0.918, 0.969, 0.980))
	FONT.fs(ratio, 9)
	ratio.custom_minimum_size = Vector2(24, 0)
	ratio.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(ratio)

	var state := Label.new()
	state.text = ""
	state.add_theme_color_override("font_color", C_TEXT_FAINT)
	FONT.fs(state, 9)
	state.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	state.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	state.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(state)

	_trait_box.add_child(row)
	return {"group": group, "chip": chip, "name": nm, "ratio": ratio, "state": state}


func _build_attr(key: String, id: String) -> Dictionary:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var k := Label.new()
	k.text = key
	k.add_theme_color_override("font_color", C_TEXT_DIM)
	FONT.fs(k, 9)
	k.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(k)

	var v := Label.new()
	v.text = "—"
	v.add_theme_color_override("font_color", Color(0.733, 0.851, 0.882))
	FONT.fs(v, 9)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(v)

	return {"root": row, "value": v}


# ------------------------------------------------------------------ 数据绑定

func set_ship(p_ship: EveShip) -> void:
	if p_ship == null:
		collapse()
		return
	ship = p_ship
	if not _built:
		return
	_set_expanded(true)

	_name_label.text = ship.ship_name
	_star_label.text = "★ %d" % _stars_for_cost(ship.cost)
	_meta_label.text = T.t("DOSSIER_META", "%s · %s · %d 费") % [
		ship.faction_name(), ship.class_name_cn(), ship.cost]

	var art: _Portrait = _portrait
	art.ship = ship
	art.queue_redraw()

	# 属性（权威表原值优先，缺了才退回派生值）
	_stat_labels["attack"].text = "%d" % int(ship.attack)
	_stat_labels["interval"].text = "%d" % int(ship.attack_interval)
	_stat_labels["range"].text = T.t("DOSSIER_RANGE", "%d 格") % ship.range_cells
	_stat_labels["speed"].text = T.t("DOSSIER_SPEED", "%.2f 格/s") % ship.speed_cells
	_stat_labels["sig"].text = "%d m" % int(_extra_stat(CIDS.X_SIGNATURE, 0.0))
	_stat_labels["class"].text = ship.class_name_cn()

	_role_label.text = T.t("DOSSIER_ROLE", "定位　%s%s") % [
		ship.role_label(),
		(T.t("DOSSIER_LOGI", "（后勤）") if ship.is_logistics else "")]

	_refresh_traits()
	_refresh_live()


func _extra_stat(key: String, fallback: float) -> float:
	if ship._extra.has(key):
		return float(ship._extra[key])
	return fallback


func _stars_for_cost(cost: int) -> int:
	if cost >= 5:
		return 3
	if cost >= 3:
		return 2
	return 1


## 羁绊三行：显示「这艘船的归属 + 该归属在舰队里的计数」
##
## 计数用的是【场上舰队】，不是只这艘船 —— 所以档位由 hud_root 喂进来。
var _fleet: Array = []


func set_fleet(ships: Array) -> void:
	_fleet = ships
	if ship != null:
		_refresh_traits()


func _refresh_traits() -> void:
	for row in _trait_rows:
		var group: StringName = row["group"]
		# ⚠️ 显式标注 String：三元表达式的两个分支类型不同（String / String 字面量）
		#    时 GDScript 会退回 Variant，用 := 推断会报错。
		var mine: String = EveTraitTable.group_of_ship(ship, group) if ship != null else ""
		var chip: ColorRect = row["chip"]
		var nm: Label = row["name"]
		var ratio: Label = row["ratio"]
		var state: Label = row["state"]

		if mine.is_empty():
			chip.color = Color(0.30, 0.36, 0.40)
			nm.text = "—"
			ratio.text = "0/%d" % EveTraitTable.max_tier(group)
			state.text = ""
			continue

		var counts := EveTraitTable.count(_fleet, group)
		var n := int(counts.get(mine, 0))
		var full := EveTraitTable.max_tier(group)
		var active := EveTraitTable.is_active(group, n)

		chip.color = _trait_color(group, mine)
		# ★ i18n：显示名走取词；`mine` 仍是**逻辑键**（`count()` / `_trait_color()` 都按它查）。
		nm.text = TERMS.trait_member(group, mine)
		ratio.text = "%d/%d" % [n, full]
		if active:
			state.text = T.t("DOSSIER_TRAIT_ACTIVE", "已生效")
			state.add_theme_color_override("font_color", C_OK)
		else:
			state.text = T.t("DOSSIER_TRAIT_AWAY", "差 %d 档") % _tiers_away(group, n)
			state.add_theme_color_override("font_color", C_TEXT_FAINT)


static func _trait_color(group: StringName, member: String) -> Color:
	for m in EveTraitTable.members(group):
		if String(m["name"]) == member:
			return m["color"]
	return C_TEXT_DIM


static func _tiers_away(group: StringName, n: int) -> int:
	for g in EveTraitTable.GROUPS:
		if g["key"] == group:
			var t: Array = g["tiers"]
			for tier in t:
				if n < int(tier):
					return int(tier) - n
	return 0


## 每帧刷新会变的东西（血条）
func _process(_delta: float) -> void:
	if ship == null or not _built or not is_visible_in_tree():
		return
	_refresh_live()


func _refresh_live() -> void:
	if ship == null:
		return
	for key in ["shield", "armor", "hull"]:
		var bar: ProgressBar = _bars[key]
		var num: Label = _hp_labels[key]
		var mx: float = maxf(1.0, ship.max_hp[StringName(key)])
		bar.max_value = mx
		bar.value = ship.hp[StringName(key)]
		num.text = "%d" % int(ship.hp[StringName(key)])


# ------------------------------------------------------------------ 立绘

## 官方渲染立绘 + 全息格栅底。缺图时退回程序化侧影（不会留空框）。
##
## 底（深色 + 格栅 + 1px 内框）是【档案窗的视觉语言】，无论有没有贴图都画；
## 船体贴图叠在底之上，所以立体感来自「真实舰体 + 舱室格栅」的层叠。
## 资源与命名见 EveShipArt。
class _Portrait extends Control:
	var ship: EveShip = null
	var _tex: Texture2D = null

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, Color(0.028, 0.038, 0.046, 0.95))
		draw_rect(Rect2(Vector2(0.5, 0.5), size - Vector2(1, 1)),
				Color(0.42, 0.55, 0.60, 0.30), false, 1.0)

		# 底纹
		var col := Color(0.42, 0.55, 0.60, 0.10)
		var x := 0.0
		while x < size.x:
			draw_line(Vector2(x, 0), Vector2(x, size.y), col, 1.0)
			x += 12.0

		if ship == null:
			return
		if _tex == null:
			_tex = EveShipArt.portrait(ship.ship_key)
		if _tex != null:
			EveShipArt.draw_ship(self, r, ship.ship_key)
			return
		var cx := size.x * 0.5
		var cy := size.y * 0.5
		var fc := ship.faction_color()
		var c := Color(fc.r, fc.g, fc.b, 0.85)
		var dim := Color(fc.r, fc.g, fc.b, 0.35)
		# 侧视舰影：细长梭形，舰首在右
		var L := clampf(26.0 + float(ship.cost) * 7.0, 26.0, size.x * 0.80)
		var T := clampf(3.0 + float(ship.cost) * 1.4, 3.0, 11.0)
		var hull := PackedVector2Array([
			Vector2(cx - L * 0.50, cy),
			Vector2(cx - L * 0.22, cy - T * 0.60),
			Vector2(cx + L * 0.16, cy - T * 0.85),
			Vector2(cx + L * 0.50, cy),
			Vector2(cx + L * 0.16, cy + T * 0.85),
			Vector2(cx - L * 0.22, cy + T * 0.60),
			Vector2(cx - L * 0.50, cy),
		])
		draw_polyline(hull, c, 1.4, true)
		# 舰桥
		draw_line(Vector2(cx - L * 0.10, cy - T * 0.50),
				Vector2(cx - L * 0.10, cy - T * 0.50 - 5.0), c, 1.3)
		draw_line(Vector2(cx + L * 0.06, cy - T * 0.50),
				Vector2(cx + L * 0.06, cy - T * 0.50 - 3.5), c, 1.3)
		# 引擎尾焰
		draw_line(Vector2(cx - L * 0.50, cy),
				Vector2(cx - L * 0.50 - 6.0, cy), dim, 2.2)
