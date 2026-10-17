extends Control
## 战斗音效试听台（2026-10-17 · 打击感改造批次 1）
##
## ══════════════════════════════════════════════════════════════════
##  为什么需要它
## ══════════════════════════════════════════════════════════════════
##  用户在 2026-10-01 关掉全部战斗音效，原话是「音效和攻击的动画都不是认真做的，
##  所以看着听着很别扭」。⇒ **音源本身没被否，被否的是呈现质量**。
##
##  本台子的用途：在动任何默认值之前，让你先把「每个音色族到底长什么样」听一遍，
##  并听一次**真实密度**的齐射（0.07 秒 6 发 + 命中 + 炸毁）——
##  单听一发永远觉得"还行"，放进实战密度才会暴露问题。
##
##  ⚠️ 本台子**只改运行时**：`sfx_enabled = true` 与音量都只在本次运行有效，
##     不写存档、不改 `SFX_ENABLED_DEFAULT`。关掉窗口即恢复"游戏默认静音"。
##
## ── 跑法（必须非 headless）────────────────────────────────────────
##   用编辑器打开本场景按 F6，或
##   "$GODOT_BIN" --path . --quit-after 999999 res://tools/probe_combat_sfx_listen.tscn
##
##  听完请口头告我：① 哪几个音色族不能忍 ② 整体是"太脆/太闷/太吵"哪一种。
## ==================================================================

const AUDIO := preload("res://scripts/core/eve_audio.gd")

## 试听项：key → 人话名
const ITEMS: Array = [
	["fire_light", "开火 · 轻型（护卫/轻武器）"],
	["fire", "开火 · 常规（巡洋）"],
	["fire_heavy", "开火 · 重型（战列）"],
	["fire_capital", "开火 · 旗舰级"],
	["hit_shield", "命中 · 护盾"],
	["hit_armor", "命中 · 装甲"],
	["hit_structure", "命中 · 结构"],
	["hit_light", "命中 · 轻擦"],
	["miss", "未命中（空放）"],
	["boom", "击毁爆炸"],
]

var audio: EveAudio = null
var _log: Label = null
var _vol: HSlider = null


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		print("✗ 本台子必须非 headless（要出声）")
		get_tree().quit()
		return
	audio = AUDIO.new()
	add_child(audio)
	# 只在本次运行打开（不改默认值）
	audio.sfx_enabled = true
	_build_ui()
	_report_bank()


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.05, 0.06)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.offset_left = 28
	scroll.offset_top = 18
	scroll.offset_right = -28
	scroll.offset_bottom = -18
	add_child(scroll)

	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(900, 0)
	col.add_theme_constant_override("separation", 6)
	scroll.add_child(col)

	var title := Label.new()
	title.text = "战斗音效试听台 · 打击感改造批次 1"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.78, 0.94, 0.98))
	col.add_child(title)

	var tip := Label.new()
	tip.text = ("本次运行已临时打开 sfx（不写存档、不改默认值）。"
			+ "先逐个听，再点最下面的「实战密度齐射」。")
	tip.add_theme_color_override("font_color", Color(0.55, 0.72, 0.78))
	col.add_child(tip)

	col.add_child(_spacer(10))

	for it in ITEMS:
		col.add_child(_item_row(String(it[0]), String(it[1])))

	col.add_child(_spacer(14))

	var salvo := Button.new()
	salvo.text = "▶ 实战密度齐射（6 发开火 + 3 次命中 + 1 次击毁）"
	salvo.custom_minimum_size = Vector2(0, 40)
	salvo.pressed.connect(_play_salvo)
	col.add_child(salvo)

	var loop := Button.new()
	loop.text = "▶ 连续 4 轮齐射（约 4 秒，测「会不会吵」）"
	loop.custom_minimum_size = Vector2(0, 34)
	loop.pressed.connect(_play_salvo_loop)
	col.add_child(loop)

	col.add_child(_spacer(12))

	var vrow := HBoxContainer.new()
	var vlab := Label.new()
	vlab.text = "音效音量"
	vlab.custom_minimum_size = Vector2(90, 0)
	vlab.add_theme_color_override("font_color", Color(0.55, 0.72, 0.78))
	vrow.add_child(vlab)
	_vol = HSlider.new()
	_vol.min_value = -40.0
	_vol.max_value = 0.0
	_vol.step = 0.5
	_vol.value = -8.9
	_vol.custom_minimum_size = Vector2(320, 20)
	_vol.value_changed.connect(func(v: float) -> void:
		audio.set_volume(&"sfx", v)
		_note("sfx 总线 = %.1f dB（默认 -8.9）" % v))
	vrow.add_child(_vol)
	col.add_child(vrow)

	_log = Label.new()
	_log.text = "就绪。"
	_log.add_theme_color_override("font_color", Color(0.85, 0.68, 0.28))
	col.add_child(_log)


func _item_row(key: String, label: String) -> Control:
	var row := HBoxContainer.new()
	var btn := Button.new()
	btn.text = "▶  " + label
	btn.custom_minimum_size = Vector2(420, 34)
	btn.pressed.connect(func() -> void: _play(key))
	row.add_child(btn)

	var info := Label.new()
	var list: Array = audio.get("_sfx_bank").get(key, [])
	if list.is_empty():
		info.text = "⛔ 音源缺失"
		info.add_theme_color_override("font_color", Color(0.82, 0.32, 0.28))
	else:
		var st: AudioStream = list[0]
		var secs := 0.0
		if st is AudioStreamOggVorbis:
			secs = (st as AudioStreamOggVorbis).get_length()
		info.text = "%d 个变体 · 约 %.2f s" % [list.size(), secs]
		info.add_theme_color_override("font_color", Color(0.45, 0.60, 0.66))
	row.add_child(info)
	return row


func _spacer(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c


func _play(key: String) -> void:
	var ok: bool = audio.call("_play_from", audio.get("_sfx_bank"), key,
			audio.get("_sfx_players"), 1.0, 1.0, false)
	_note(("✔ 播放 %s" if ok else "✗ 没有可播的 %s（音源缺失）") % key)


func _play_salvo() -> void:
	await _one_salvo()
	_note("一轮齐射播完（这是 BOSS 节点 6v6 的典型密度）")


func _play_salvo_loop() -> void:
	for i in 4:
		await _one_salvo()
	_note("4 轮齐射播完 —— 如果你在这里想调小音量，那就是默认音量偏高")


## 一轮齐射：与真实战斗的**事件顺序**一致（先开火，再命中，最后炸）
##
## ⚠️ 间隔 0.07s 取自实测：6v6 下单帧特效峰值 10、活跃窗口约 0.4s
##    ⇒ 平均到每 70ms 就有一次开火事件。
func _one_salvo() -> void:
	for i in 6:
		_play("fire" if i % 2 == 0 else "fire_light")
		await get_tree().create_timer(0.07).timeout
	_play("hit_shield")
	await get_tree().create_timer(0.07).timeout
	_play("hit_armor")
	await get_tree().create_timer(0.07).timeout
	_play("hit_structure")
	await get_tree().create_timer(0.07).timeout
	_play("boom")


func _note(s: String) -> void:
	if _log != null:
		_log.text = s
	print("  " + s)


## 启动时把「银行里到底有什么」打出来，方便直接看数据而不是靠听。
func _report_bank() -> void:
	var bank: Dictionary = audio.get("_sfx_bank")
	var keys := bank.keys()
	keys.sort()
	print("══════════════════════════════════════════════")
	print("  音源银行 sfx：%d 组" % keys.size())
	for k in keys:
		var list: Array = bank[k]
		var secs := 0.0
		if not list.is_empty() and list[0] is AudioStreamOggVorbis:
			secs = (list[0] as AudioStreamOggVorbis).get_length()
		print("    %-16s %2d 变体 · %.2f s" % [String(k), list.size(), secs])
	print("══════════════════════════════════════════════")
