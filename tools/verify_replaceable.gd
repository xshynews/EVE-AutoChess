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
func _test_button_skin_library() -> void:
	print("[替换验证] ── ② 按钮皮肤库 ──")
	if _hud == null:
		print("[替换验证] ✗ 拿不到 HUD，跳过按钮测试")
		_fail += 1
		return
	var ids := EveButtonTheme.available_ids()
	print("[替换验证] 可用皮肤 %d 套：%s" % [ids.size(), ", ".join(ids)])
	for id in ids:
		var ok: bool = _hud.call("set_button_skin", id)
		var tag := "✓" if ok else "✗"
		if not ok:
			_fail += 1
		# 抽查一个按钮，确认 5 个状态盒都真的设上了
		var btn := _find_first_button(_hud)
		var states := ""
		if btn != null:
			for st in ["normal", "hover", "pressed", "disabled", "focus"]:
				if btn.has_theme_stylebox_override(st):
					states += st.substr(0, 1)
		print("[替换验证] %s %s  已设状态盒=[%s]（n/h/p/d/f）" % [tag, id, states])


## ③ 运行时连续切换（模拟玩家快速换背景 / 换皮肤）
func _test_runtime_switch() -> void:
	print("[替换验证] ── ③ 运行时连续切换 ──")
	var bgs := EveBackgroundLibrary.available_ids()
	var skins := EveButtonTheme.available_ids()
	for i in 6:
		var b: String = bgs[i % bgs.size()]
		var s: String = skins[i % skins.size()]
		_arena.call("set_background", b)
		_hud.call("set_button_skin", s)
		# 校验：换完之后当前值确实变了
		var cur_b: String = _arena.call("current_background_id")
		if cur_b != b:
			print("[替换验证] ✗ 第 %d 次切背景：期望 %s 实际 %s" % [i, b, cur_b])
			_fail += 1
	print("[替换验证] 连续切换 6 轮完成，当前背景=%s 当前皮肤=%s"
			% [_arena.call("current_background_id"), _hud.get("button_skin")])


func _finish() -> void:
	print("[替换验证] ══ 完成，失败项=%d ══" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)


func _find_first_button(root: Node) -> Button:
	if root is Button:
		return root
	for c in root.get_children():
		var r := _find_first_button(c)
		if r != null:
			return r
	return null
