extends Control

## 交互式试听台 v2 —— 矩阵拖拽拍板版（非无头，不进验收套件）：2026-10-14「斗地主音效」。
##
## 布局（横轴 × 纵轴）：
##   三列 = 确定 | EVE 池 | UNO 池；每行 = 一个牌桌音效事件。
##   · 候选按钮（EVE / UNO 列）：**点击试听**；按住拖动可带走；
##   · 确定格：把候选 **拖进来** 完成拍板（可跨行拖；再拖一个即替换；右键清除）；
##   · 「其他 UNO」行：未被自动分组的隔离区文件，可拖去任意事件。
## 拍板结果：底部「复制拍板结果」→ 剪贴板 + 控制台；另存 user://ddz_sfx_picks.json
## （仓库外，重开自动回填）。本场景对工程 **零写入**（不动 EveAudio / assets/audio）。
##
## ── ⛔ 只读纪律 ──────────────────────────────────────────────
##  · 不写任何工程状态、不碰 assets/audio 正式三目录（会被 _scan_dir 扫进音库）；
##  · 隔离区文件若编辑器还没导入，走 load_from_file() 兜底照样能听。
## 跑法：编辑器打开本场景按 **F6**；无头冒烟 --quit-after 120 看汇总行。
## 拍板方式：点「复制拍板结果」→ 把剪贴板内容发给 AI，走隔离区 README 的入库流程。

const Cell := preload("res://tools/probe_sfx_cell.gd")

## 隔离区（候选素材，⛔ 不被 _scan_dir 扫描）
const CAND_DIR := "res://assets/audio_candidates"
const DIR_BY_POOL := {
	"sfx": "res://assets/audio/sfx/",
	"amb": "res://assets/audio/ambience/",
}
const PICKS_PATH := "user://ddz_sfx_picks.json"
## 音量滑杆默认值 = 设置里 sfx 总线的滑块默认（听感对齐游戏内）
const DEFAULT_VOL := 0.6

## ── 事件表（纵轴）──────────────────────────────────────────────
## [事件名, [[EVE音库, EVE键]...], [候选分组名...]]
## ★ EVE 候选语义出处见 assets/audio/README.md（interface 音库 bank 级可靠）；
## ★ UNO 分组见 _uno_group()；Kenney（CC0 可商用）分组见 _kenney_group()；
##   拍板后本表即「音效映射常量区」雏形，原样搬走。
const EVENTS: Array = [
	["发牌", [["sfx", "fire_light_01"], ["sfx", "fire_light_02"], ["sfx", "fire_light_03"]], ["发牌", "发牌K"]],
	["选牌", [["amb", "tick_01"], ["amb", "tick_02"]], ["选牌", "选牌K"]],
	["取消选牌", [["amb", "tick_03"], ["amb", "tick_02"]], ["选牌", "取消K"]],
	["叫分 1", [["amb", "count_1_01"]], ["叫分", "叫分K"]],
	["叫分 2", [["amb", "count_2_01"]], ["叫分", "叫分K"]],
	["叫分 3", [["amb", "count_3_01"]], ["叫分", "叫分K"]],
	["抢地主", [["amb", "count_2_02"], ["amb", "phase_prep_01"]], ["抢", "叫分", "抢K"]],
	["不抢", [["amb", "tick_urgent_01"], ["amb", "count_2_02"]], ["过牌", "叫分", "取消K"]],
	["出牌", [["sfx", "hit_light_01"], ["sfx", "hit_light_02"], ["sfx", "hit_light_03"], ["sfx", "fire_light_04"]], ["出牌", "出牌K"]],
	["炸弹 / 火箭", [["sfx", "boom_05"], ["sfx", "boom_06"], ["sfx", "boom_07"]], ["炸弹", "炸弹K"]],
	["过牌", [["amb", "tick_02"], ["amb", "tick_03"]], ["过牌", "过牌K"]],
	["非法操作 / 拒绝", [["amb", "tick_urgent_01"], ["amb", "tick_urgent_02"]], ["拒绝", "拒绝K"]],
	["胜利", [["amb", "phase_end_01"], ["amb", "phase_resolve_01"], ["amb", "resolve_01"]], ["胜负", "胜负K"]],
	["失败", [["amb", "resolve_02"], ["amb", "resolve_01"], ["amb", "phase_end_01"]], ["胜负", "胜负K"]],
]

const COL_BG := Color(0.012, 0.02, 0.028)
const COL_TEXT := Color(0.78, 0.85, 0.90)
const COL_DIM := Color(0.52, 0.60, 0.66)
const COL_SLOT := Color(0.06, 0.10, 0.14)

var _player: AudioStreamPlayer
var _vol := DEFAULT_VOL
var _ext_files: Array[String] = []
var _uno_by_group := {}  # 分组名 -> [文件名...]
var _picks := {}         # 事件 -> 路径（user:// 持久化，仓库外）
var _slots := {}         # 事件 -> Cell
var _export_btn: Button


func _ready() -> void:
	# ⚠ 必须用 and_offsets 版本：set_anchors_preset 只改锚点不保证撑满（0 尺寸根会保住 0 矩形）
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ext_files = _scan_candidates()
	for fn: String in _ext_files:
		var g := _uno_group(fn)
		if not _uno_by_group.has(g):
			_uno_by_group[g] = []
		_uno_by_group[g].append(fn)
	_load_picks()
	_build_ui()
	print("[probe] 试听台就绪：事件=%d · 外部文件=%d · UNO 分组=%s（隔离区 %s）"
			% [EVENTS.size(), _ext_files.size(), str(_uno_by_group.keys()), CAND_DIR])


# ══════════════════════════════════════════════════════════════════
#  UI（代码建，风格照牌桌：冷色 / 细线 / 信息优先）
# ══════════════════════════════════════════════════════════════════

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = COL_BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 16.0
	root.offset_top = 12.0
	root.offset_right = -16.0
	root.offset_bottom = -12.0
	root.add_theme_constant_override("separation", 8)
	add_child(root)

	var title := Label.new()
	title.text = "斗地主音效拍板台 —— 点击试听 · 拖入左列「确定」格（可跨行拖 / 右键清除）"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", COL_TEXT)
	root.add_child(title)

	# ── 表头：确定 | EVE | UNO ──
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	root.add_child(head)
	_header_cell(head, "事件", 150.0)
	_header_cell(head, "确定（拖入拍板）", 230.0)
	_header_cell(head, "EVE 池（interface 音库 + sfx 短音）", -1.0)
	_header_cell(head, "UNO / Kenney 候选池（assets/audio_candidates/）", -1.0)

	# ── 矩阵主体（滚动）──
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 4)
	scroll.add_child(rows)
	for e: Array in EVENTS:
		rows.add_child(_event_row(e[0], e[1], e[2]))
	rows.add_child(_misc_row())

	# ── 底部：音量 + 导出 ──
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 12)
	root.add_child(foot)
	var vol_label := Label.new()
	vol_label.text = "音量"
	vol_label.add_theme_color_override("font_color", COL_DIM)
	foot.add_child(vol_label)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = _vol
	slider.custom_minimum_size = Vector2(220.0, 24.0)
	slider.value_changed.connect(_on_vol_changed)
	foot.add_child(slider)
	_export_btn = Button.new()
	_export_btn.text = "复制拍板结果"
	_export_btn.focus_mode = Control.FOCUS_NONE
	_export_btn.pressed.connect(_on_export)
	foot.add_child(_export_btn)


func _header_cell(parent: Control, text_value: String, width: float) -> void:
	var lb := Label.new()
	lb.text = text_value
	lb.add_theme_color_override("font_color", COL_DIM)
	lb.add_theme_font_size_override("font_size", 14)
	if width > 0.0:
		lb.custom_minimum_size = Vector2(width, 0.0)
	else:
		lb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lb.size_flags_stretch_ratio = 1.0
	parent.add_child(lb)


func _event_row(event_name: String, eve_pairs: Array, uno_groups: Array) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var name_label := Label.new()
	name_label.text = event_name
	name_label.custom_minimum_size = Vector2(150.0, 30.0)
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.add_theme_color_override("font_color", COL_TEXT)
	name_label.add_theme_font_size_override("font_size", 15)
	row.add_child(name_label)

	var slot: Cell = Cell.new()
	slot.setup_slot(event_name)
	slot.play_requested.connect(_play_path)
	slot.picked.connect(_on_picked)
	slot.cleared.connect(_on_cleared)
	if _picks.has(event_name):
		var p := String(_picks[event_name])
		slot.fill_slot(p, _short_name(p.get_file()))
	row.add_child(slot)
	_slots[event_name] = slot

	var eve_flow := HFlowContainer.new()
	eve_flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	eve_flow.size_flags_stretch_ratio = 1.0
	eve_flow.add_theme_constant_override("h_separation", 4)
	eve_flow.add_theme_constant_override("v_separation", 4)
	row.add_child(eve_flow)
	for pair: Array in eve_pairs:
		var key: String = pair[1]
		var c: Cell = Cell.new()
		c.setup_candidate(DIR_BY_POOL[pair[0]] + key + ".ogg", key)
		c.play_requested.connect(_play_path)
		eve_flow.add_child(c)

	var uno_flow := HFlowContainer.new()
	uno_flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	uno_flow.size_flags_stretch_ratio = 1.15
	uno_flow.add_theme_constant_override("h_separation", 4)
	uno_flow.add_theme_constant_override("v_separation", 4)
	row.add_child(uno_flow)
	for g: String in uno_groups:
		for fn: String in _uno_by_group.get(g, []):
			var c2: Cell = Cell.new()
			c2.setup_candidate(CAND_DIR + "/" + fn, _short_name(fn))
			c2.play_requested.connect(_play_path)
			uno_flow.add_child(c2)
	return row


## 「其他 UNO」行：未被自动分组的文件，可拖去任意事件（无确定格）
func _misc_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var name_label := Label.new()
	name_label.text = "其他候选（可拖去任意事件）"
	name_label.custom_minimum_size = Vector2(380.0, 30.0)
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.add_theme_color_override("font_color", COL_DIM)
	name_label.add_theme_font_size_override("font_size", 14)
	row.add_child(name_label)
	var flow := HFlowContainer.new()
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	flow.add_theme_constant_override("h_separation", 4)
	flow.add_theme_constant_override("v_separation", 4)
	row.add_child(flow)
	for fn: String in _uno_by_group.get("其他", []):
		var c: Cell = Cell.new()
		c.setup_candidate(CAND_DIR + "/" + fn, _short_name(fn))
		c.play_requested.connect(_play_path)
		flow.add_child(c)
	return row


# ══════════════════════════════════════════════════════════════════
#  UNO 分组（按文件名归类到事件行；未命中 →「其他」）
# ══════════════════════════════════════════════════════════════════

func _uno_group(fn: String) -> String:
	# Kenney（CC0）候选走独立映射，见 _kenney_group()
	var k := _kenney_group(fn)
	if k != "":
		return k
	if fn.begins_with("uno_FL_Card_Play_"):
		return "出牌"
	if fn.begins_with("uno_Jingle_Classic_"):
		return "胜负"
	match fn:
		"uno_FL_Card_Deal.wav", "uno_FL_Card_Shuffle_01.wav", "uno_FL_Card_Shuffle_02.wav", \
		"uno_Sfx_Card_Deck_Appear.wav":
			return "发牌"
		"uno_FL_Card_Select.wav", "uno_Sfx_Card_Choice_Click.wav":
			return "选牌"
		"uno_Sfx_Card_Choice_Popup.wav", "uno_Sfx_Card_Function_0_Start.wav":
			return "叫分"
		"uno_Sfx_Active_Player_Turn_Able_Play.wav":
			return "抢"
		"uno_Sfx_Card_Function_0_Fold.wav", "uno_Sfx_Card_Function_0_Process.wav", \
		"uno_Sfx_Card_Function_0_Clockwise.wav", "uno_Sfx_Card_Function_0_Anticlockwise.wav":
			return "过牌"
		"uno_Sfx_Card_Common_Shockware_Heavy.wav", "uno_Sfx_Card_Common_Shockware_Light.wav", \
		"uno_Play_Sfx_Card_Function_Wild_Color_Splash.wav", "uno_Play_Sfx_Card_Function_Wild_Color_Splash02.wav", \
		"uno_Play_Sfx_Card_Function_Wild_Color_Splash03.wav", "uno_Play_Sfx_Card_Function_Wild_Color_Splash04.wav":
			return "炸弹"
		"uno_Sfx_Card_Error_Warning.wav":
			return "拒绝"
		_:
			return "其他"


## Kenney 候选分组（kenney_casino_ = Casino Audio 拟音 / kenney_ui_ = Interface Sounds）。
## 分组名与 EVENTS 第三列的「xxK」对应；未命中返回 ""（落「其他」隔离行）。
func _kenney_group(fn: String) -> String:
	if fn.begins_with("kenney_casino_"):
		if fn.begins_with("kenney_casino_card-slide") \
				or fn.begins_with("kenney_casino_card-shove") \
				or fn.begins_with("kenney_casino_card-shuffle"):
			return "发牌K"
		if fn.begins_with("kenney_casino_card-place"):
			return "出牌K"
		if fn.begins_with("kenney_casino_chips-stack"):
			return "叫分K"
		if fn.begins_with("kenney_casino_chips-collide"):
			return "抢K"
		return ""
	if fn.begins_with("kenney_ui_"):
		if fn.begins_with("kenney_ui_select") or fn.begins_with("kenney_ui_pluck"):
			return "选牌K"
		if fn.begins_with("kenney_ui_back"):
			return "取消K"
		if fn.begins_with("kenney_ui_confirmation"):
			return "叫分K"
		if fn.begins_with("kenney_ui_maximize") or fn.begins_with("kenney_ui_minimize") \
				or fn.begins_with("kenney_ui_glass"):
			return "胜负K"
		if fn.begins_with("kenney_ui_drop"):
			return "出牌K"
		if fn.begins_with("kenney_ui_glitch"):
			return "炸弹K"
		if fn.begins_with("kenney_ui_switch") or fn.begins_with("kenney_ui_tick"):
			return "过牌K"
		if fn.begins_with("kenney_ui_error"):
			return "拒绝K"
		return ""
	# Sci-fi Sounds（70 个）：爆炸/金属撞击归「炸弹K」，其余（激光/引擎/舱门/护盾）
	# 落「其他候选」——给自走棋 UI 试听台用，斗地主事件不强行挂
	if fn.begins_with("kenney_scifi_"):
		if fn.begins_with("kenney_scifi_explosionCrunch") \
				or fn.begins_with("kenney_scifi_lowFrequency_explosion") \
				or fn.begins_with("kenney_scifi_impactMetal"):
			return "炸弹K"
		return ""
	return ""


func _short_name(fn: String) -> String:
	return fn.trim_prefix("kenney_casino_").trim_prefix("kenney_scifi_") \
			.trim_prefix("kenney_ui_").trim_prefix("uno_") \
			.trim_suffix(".wav").trim_suffix(".ogg")


# ══════════════════════════════════════════════════════════════════
#  拍板结果（user:// 持久化 + 剪贴板导出）
# ══════════════════════════════════════════════════════════════════

func _on_picked(event_name: String, path: String) -> void:
	_picks[event_name] = path
	_save_picks()


func _on_cleared(event_name: String) -> void:
	_picks.erase(event_name)
	_save_picks()


func _save_picks() -> void:
	var f := FileAccess.open(PICKS_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(_picks, "\t"))


func _load_picks() -> void:
	if not FileAccess.file_exists(PICKS_PATH):
		return
	var f := FileAccess.open(PICKS_PATH, FileAccess.READ)
	if f == null:
		return
	var data: Variant = JSON.parse_string(f.get_as_text())
	if data is Dictionary:
		_picks = data


func _on_export() -> void:
	var lines: Array[String] = []
	for e: Array in EVENTS:
		var ev: String = e[0]
		if _picks.has(ev):
			lines.append("%s → %s" % [ev, String(_picks[ev]).get_file()])
	var txt := "\n".join(lines)
	DisplayServer.clipboard_set(txt)
	print("[probe] 拍板结果（已复制到剪贴板）：\n", txt)
	_export_btn.text = "已复制 %d 项 ✓" % lines.size()
	get_tree().create_timer(2.0).timeout.connect(func() -> void:
		_export_btn.text = "复制拍板结果")


# ══════════════════════════════════════════════════════════════════
#  播放
# ══════════════════════════════════════════════════════════════════

func _play_path(path: String) -> void:
	var stream := _load_stream(path)
	if stream == null:
		push_warning("[probe] 加载失败：%s" % path)
		return
	if _player == null:
		_player = AudioStreamPlayer.new()
		add_child(_player)
	_player.stream = stream
	# 音量口径与工程一致：gain = lin²（见 assets/audio/README.md「平方曲线」）
	_player.volume_db = linear_to_db(_vol * _vol)
	_player.play()


## 优先走编辑器导入缓存；隔离区刚丢进来的文件可能还没导入 ⇒ load_from_file 兜底
func _load_stream(path: String) -> AudioStream:
	if ResourceLoader.exists(path):
		var s: AudioStream = load(path)
		if s != null:
			return s
	if path.ends_with(".ogg"):
		return AudioStreamOggVorbis.load_from_file(path)
	if path.ends_with(".mp3"):
		return AudioStreamMP3.load_from_file(path)
	if path.ends_with(".wav"):
		return AudioStreamWAV.load_from_file(path)
	return null


func _scan_candidates() -> Array[String]:
	var out: Array[String] = []
	for fn: String in DirAccess.get_files_at(CAND_DIR):
		if fn.ends_with(".import") or fn.ends_with(".uid") or fn.ends_with(".md") \
				or fn.ends_with(".txt"):
			continue
		out.append(fn)
	out.sort()
	return out


func _on_vol_changed(v: float) -> void:
	_vol = v
	if _player != null:
		_player.volume_db = linear_to_db(_vol * _vol)


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			get_tree().quit()
