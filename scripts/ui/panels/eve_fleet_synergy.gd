extends "res://scripts/ui/eve_window.gd"

## EVE 自走棋 —— 舰队构成（羁绊）窗
##
## V3 稿尺寸 172 × 268，左上。三组：势力 / 武器 / 防御。
## 每行 = 色块 + 名称(58px) + 档位条 + 计数(26px)。
##
## 档位条的含义（云顶同款读法）：
##   底槽是「满档」，填充 = 当前计数 / 满档分母，两个刻度 = 第 1 档 / 第 2 档。
##   跨过第 1 档的行整行提亮（含名称与计数），未到的降到 62% 透明度。
##
## ⚠️ 只显示「凑了几个」，不显示「凑齐后加什么」——
##    加成数值设计侧还没给，工程里不编（详见 EveTraitTable 的说明）。
##
## 变更清单（实装版）：
##   - 三组 × （4/4/2）条，行内自绘档位条
##   - set_fleet() 接任意含 traits 的对象数组（EveShip / Dictionary 都行）

var _rows: Array[Dictionary] = []


func _ready() -> void:
	window_title = "舰队构成"
	density = Density.COMPACT
	super._ready()
	_build_contents()


func _build_contents() -> void:
	content.add_theme_constant_override("separation", 2)

	for g in EveTraitTable.GROUPS:
		var key: StringName = g["key"]

		var gh := make_group_header(String(g["label"]))
		content.add_child(gh)

		for m in EveTraitTable.members(key):
			var row := _build_row(key, String(m["name"]), m["color"])
			content.add_child(row["root"])
			_rows.append(row)


func _build_row(group: StringName, member: String, color: Color) -> Dictionary:
	var root := HBoxContainer.new()
	root.add_theme_constant_override("separation", 5)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# 色块（12×12，中间挖一个深色小方块 —— V3 稿的 .syn i.ic）
	var chip := PanelContainer.new()
	chip.custom_minimum_size = Vector2(12, 12)
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var chip_sb := StyleBoxFlat.new()
	chip_sb.bg_color = color
	chip_sb.border_color = Color(1, 1, 1, 0.22)
	chip_sb.set_border_width_all(1)
	chip_sb.set_corner_radius_all(0)
	chip_sb.content_margin_left = 3
	chip_sb.content_margin_right = 3
	chip_sb.content_margin_top = 3
	chip_sb.content_margin_bottom = 3
	chip.add_theme_stylebox_override("panel", chip_sb)
	var inner := ColorRect.new()
	inner.color = Color(0.016, 0.027, 0.035, 0.72)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(inner)
	root.add_child(chip)

	var name_label := Label.new()
	name_label.text = member
	name_label.add_theme_color_override("font_color", C_TEXT)
	FONT.fs(name_label, 11)
	name_label.custom_minimum_size = Vector2(58, 0)
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# ⚠️ 必须是 PASS 而不是 IGNORE：tooltip 只有能收到鼠标事件的控件才弹得出来。
	#    整行（root）保持 IGNORE —— 它是容器，一旦 STOP 会挡住窗口的拖动。
	name_label.mouse_filter = Control.MOUSE_FILTER_PASS
	root.add_child(name_label)

	var bar := _SynBar.new()
	bar.fill_color = color
	bar.custom_minimum_size = Vector2(0, 6)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.mouse_filter = Control.MOUSE_FILTER_PASS
	bar.set_ticks_for(EveTraitTable.GROUPS, group)
	root.add_child(bar)

	var ratio := Label.new()
	ratio.text = "0/%d" % EveTraitTable.max_tier(group)
	ratio.add_theme_color_override("font_color", C_TEXT_DIM)
	FONT.fs(ratio, 10)
	ratio.custom_minimum_size = Vector2(26, 0)
	ratio.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ratio.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ratio.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(ratio)

	return {
		"root": root, "group": group, "member": member,
		"bar": bar, "ratio": ratio, "name": name_label,
	}


## 喂一支舰队进来刷新。ships 里每个元素只要有 traits 就行（EveShip / Dictionary 皆可）
func set_fleet(ships: Array) -> void:
	for row in _rows:
		var group: StringName = row["group"]
		var counts := EveTraitTable.count(ships, group)
		var n := int(counts.get(row["member"], 0))
		var full := EveTraitTable.max_tier(group)
		var active := EveTraitTable.is_active(group, n)

		var bar: _SynBar = row["bar"]
		bar.pct = float(n) / maxf(1.0, float(full))
		bar.active = active
		bar.queue_redraw()

		var ratio: Label = row["ratio"]
		ratio.text = "%d/%d" % [n, full]

		# ⚠️ name_label 必须在这里先声明 —— 下面挂 tooltip 就要用它。
		#    挪到后面去会让整个脚本解析失败（"Identifier not declared"），
		#    连带把 eve_hud_root / battle_scene 全拖垮，症状是 HUD 少一半窗口。
		var name_label: Label = row["name"]

		# 效果文本走 tooltip，不占行宽。
		# ⚠️ 172px 宽塞不下「生效效果」文字列（V3 稿明确删掉了那一列），
		#    但「凑齐了加什么」是玩家必须能查到的 —— 所以挂 tooltip。
		#    未实装的特殊机制也在这段文本里如实写明（见 EveTraitTable.tooltip_for）。
		var tip := EveTraitTable.tooltip_for(group, String(row["member"]), n)
		row["root"].tooltip_text = tip
		name_label.tooltip_text = tip
		ratio.tooltip_text = tip

		# 未达档的行整行压暗（V3 稿的 .syn.off{opacity:.62}）
		if active:
			name_label.add_theme_color_override("font_color", Color(0.918, 0.969, 0.980))
			ratio.add_theme_color_override("font_color", Color(0.918, 0.969, 0.980))
			row["root"].modulate = Color(1, 1, 1, 1)
		else:
			name_label.add_theme_color_override("font_color", C_TEXT)
			ratio.add_theme_color_override("font_color", C_TEXT_DIM)
			row["root"].modulate = Color(1, 1, 1, 0.62)


# ------------------------------------------------------------------ 自绘档位条

class _SynBar extends Control:
	var fill_color: Color = Color.WHITE
	var pct: float = 0.0
	## 档位刻度（归一化位置，如 [0.5] 表示「第一档在 50% 处」）
	var ticks: Array[float] = []
	var active: bool = false

	## 按羁绊表把 tiers 换算成刻度位置
	##
	## 例：势力 tiers=[2,4] → 满档 4 → 刻度在 0.5 处（第 1 档）；
	##     武器 tiers=[2,4,6] → 满档 6 → 刻度在 0.333 / 0.667 处。
	## ⚠️ 最后一段刻度不外显（0.667 那根是「第 2 档」，但 6 是满格，
	##    画在 1.0 处会跟右边框重合）—— 所以只画到倒数第二档。
	func set_ticks_for(groups: Array, group: StringName) -> void:
		ticks.clear()
		for g in groups:
			if g["key"] != group:
				continue
			var t: Array = g["tiers"]
			var full := float(t[t.size() - 1])
			for i in range(t.size() - 1):
				ticks.append(float(t[i]) / full)

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.102, 0.129, 0.149, 0.92))
		var w := size.x * clampf(pct, 0.0, 1.0)
		if w > 0.5:
			var c := fill_color
			draw_rect(Rect2(Vector2.ZERO, Vector2(w, size.y)),
					Color(c.r, c.g, c.b, 1.0 if active else 0.6))
		for f in ticks:
			var x := size.x * f
			draw_line(Vector2(x, -1.0), Vector2(x, size.y + 1.0),
					Color(0.86, 0.92, 0.94, 0.50), 1.0)
