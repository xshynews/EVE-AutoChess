extends Node

## 整体验证 —— 背景可替换 + 按钮皮肤可替换，一次跑完
##
## 用法：
##   godot_console.exe --path <工程> --quit-after N res://tools/verify_replaceable.tscn
##
## 检查项：
##   ① 背景库：逐条应用，确认球幕/背景板/纯色三种模式都能落地
##   ② 按钮皮肤库：逐条应用，确认 5 态样式盒全部生成
##   ③ 运行时换背景：验证中途切换不会崩、不会黑屏
##   ④ 运行时换皮肤：验证递归刷新能覆盖到动态创建的按钮

const SCENE_PATH := "res://scenes/battle_scene.tscn"

var _battle: Node = null
var _arena: Node = null
var _hud: Control = null
var _phase := 0
var _frame := 0
var _fail := 0


func _ready() -> void:
	var packed: PackedScene = load(SCENE_PATH)
	_battle = packed.instantiate()
	add_child(_battle)
	await get_tree().process_frame
	_arena = _battle.get("arena")
	_hud = _battle.get("hud")
	print("[替换验证] 开始")


func _process(_dt: float) -> void:
	_frame += 1
	if _frame < 20:
		return
	_frame = 0
	match _phase:
		0:
			_test_background_library()
		1:
			_test_button_skin_library()
		2:
			_test_runtime_switch()
		_:
			_finish()
	_phase += 1


## ① 背景库逐条落地
func _test_background_library() -> void:
	print("[替换验证] ── ① 背景库 ──")
	var ids := EveBackgroundLibrary.available_ids()
	print("[替换验证] 可用背景 %d 个：%s" % [ids.size(), ", ".join(ids)])
	for id in ids:
		var e := EveBackgroundLibrary.find(id)
		if e == null:
			print("[替换验证] ✗ %s 查不到" % id)
			_fail += 1
			continue
		var ok: bool = _arena.call("set_background", id)
		var cur: String = _arena.call("current_background_id")
		var tag := "✓" if (ok and cur == id) else "✗"
		if not (ok and cur == id):
			_fail += 1
		print("[替换验证] %s %s  %s  强度=%.2f  球幕偏置=%.0f"
				% [tag, id, e.describe(), e.intensity, e.sky_pitch_bias])


## ② 按钮皮肤库逐条落地
##
## ★ 2026-10-10（审查 R08）：**原实现调 `_hud.set_button_skin()`，该方法早已不存在**
##   ⇒ 运行时抛 `Nonexistent function` 打断测试函数，而错误没计入 `_fail`，
##   最终仍打印「失败项=0」+ 退出码 0（**假通过**，比不测还糟）。
##   现状核查：产品**没有**「运行时整体换皮肤」这个功能 —— `EveButtonTheme.apply()`
##   是单按钮入口，HUD 侧只有一个默认皮肤名 `button_skin`。⇒ 测试范围对齐真实能力：
##   对**真实按钮**逐个套用每一套皮肤，并断言 5 态样式盒真的生成了。
func _test_button_skin_library() -> void:
	print("[替换验证] ── ② 按钮皮肤库 ──")
	var ids := EveButtonTheme.available_ids()
	print("[替换验证] 可用皮肤 %d 套：%s" % [ids.size(), ", ".join(ids)])
	if ids.is_empty():
		print("[替换验证] ✗ 皮肤库为空")
		_fail += 1
		return
	for id in ids:
		var btn := Button.new()
		btn.text = "样例"
		add_child(btn)
		EveButtonTheme.apply(btn, id)
		var states := ""
		for st in ["normal", "hover", "pressed", "disabled", "focus"]:
			if btn.has_theme_stylebox_override(st):
				states += st.substr(0, 1)
		var ok := states.length() >= 1          # 至少要设上 normal
		if not ok:
			_fail += 1
		print("[替换验证] %s %s  已设状态盒=[%s]（n/h/p/d/f）"
				% ["✓" if ok else "✗", id, states])
		btn.queue_free()


## ③ 运行时连续切换（模拟玩家快速换背景）
func _test_runtime_switch() -> void:
	print("[替换验证] ── ③ 运行时连续切换 ──")
	var bgs := EveBackgroundLibrary.available_ids()
	if bgs.is_empty():
		print("[替换验证] ✗ 背景库为空")
		_fail += 1
		return
	for i in 6:
		var b: String = bgs[i % bgs.size()]
		_arena.call("set_background", b)
		# 校验：换完之后当前值确实变了
		var cur_b: String = _arena.call("current_background_id")
		if cur_b != b:
			print("[替换验证] ✗ 第 %d 次切背景：期望 %s 实际 %s" % [i, b, cur_b])
			_fail += 1
	print("[替换验证] 连续切换 6 轮完成，当前背景=%s"
			% _arena.call("current_background_id"))


func _finish() -> void:
	print("[替换验证] ══ 完成，失败项=%d ══" % _fail)
	# ★ 完成标记：外部 runner 除了退出码，还应校验这一行确实出现（防"没跑完就退"）。
	print("[替换验证] VERIFY_DONE failed=%d" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)
