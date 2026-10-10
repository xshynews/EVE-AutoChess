extends Node

## 「对局存档」端到端自检（审查 2#2）—— 无头跑，退出码 = 有无失败。
##
## ══════════════════════════════════════════════════════════════════
##  判什么（走**真实生产链路**，不 mock）
## ══════════════════════════════════════════════════════════════════
##   ① 起 `battle_scene.tscn` → `begin_prep()` 结束 ⇒ **写出对局存档**；
##   ② 再起一次并把 `resume_requested` 置位 ⇒ run **恢复到存档那一局**
##      （节点号 / 星币 / 信条与存档一致，**不是**被 `start_run()` 顶掉）；
##   ③ `RUN_STORE.clear()` ⇒ 档消失（「没有可继续的对局」）。
##
## ⚠️ 全程快照 + 原样还原玩家的 `user://run.cfg`（自检不许污染存档）。
## ⚠️ `session_active` 必须显式置位 —— 那正是"真实会话"的闸门；
##    不自检就写盘、又不还原，是工程里踩过的老坑。
##
## 用法：
##   Godot_v4.7.2-stable_win64_console.exe --headless \
##     --path "<工程>" --quit-after 6000 res://tools/verify_run_save.tscn

const SCENE_PATH := "res://scenes/battle_scene.tscn"
const RUN_STORE := preload("res://scripts/core/eve_run_store.gd")

var _pass := 0
var _fail := 0
var _phase := 0
var _frames := 0
var _scene: Node = null
var _snap := PackedByteArray()
var _coin0 := -1
var _node0 := -1


func _ready() -> void:
	_snap = _read_raw(RUN_STORE.PATH)
	RUN_STORE.persist = true
	RUN_STORE.session_active = true
	RUN_STORE.resume_requested = false
	RUN_STORE.clear()
	print("═══ verify_run_save（对局存档 E2E）═══")
	_instantiate()


func _process(_dt: float) -> void:
	_frames += 1
	if _frames < 8:
		return
	_frames = 0
	match _phase:
		0:
			_step_after_fresh_start()
		1:
			_step_resume()
		_:
			_finish()
	_phase += 1


func _instantiate() -> void:
	var ps: PackedScene = load(SCENE_PATH)
	if ps == null:
		_ok(false, "载入 battle_scene.tscn")
		return
	_scene = ps.instantiate()
	add_child(_scene)


func _free_scene() -> void:
	if _scene != null and is_instance_valid(_scene):
		_scene.queue_free()
	_scene = null


func _step_after_fresh_start() -> void:
	_ok(RUN_STORE.has_run(), "★ 新开局后写出对局存档（user://run.cfg）")
	var d := RUN_STORE.load_run()
	_node0 = int(d.get("node_index", -1))
	_coin0 = int(d.get("coin", -1))
	_ok(_node0 == 1, "★ 存档里节点 = 1（实际 %d）" % _node0)
	_ok(_coin0 >= 0, "★ 存档里星币可读（%d）" % _coin0)
	# ② 换成"继续上一局"
	_free_scene()
	RUN_STORE.resume_requested = true
	_instantiate()


func _step_resume() -> void:
	var r = _scene.get("run") if _scene != null else null
	if r == null:
		_ok(false, "继续上局：拿得到 run")
		return
	_ok(int(r.node_index) == _node0 and int(r.coin) == _coin0,
			"★ 继续上局恢复到存档那一局（节点 %d、星币 %d）—— 未被 start_run 顶掉"
			% [int(r.node_index), int(r.coin)])
	# ③ 删档
	RUN_STORE.clear()
	_ok(not RUN_STORE.has_run(), "★ clear() 后「没有可继续的对局」")
	_free_scene()


func _finish() -> void:
	RUN_STORE.session_active = false
	RUN_STORE.resume_requested = false
	_restore_raw(RUN_STORE.PATH, _snap)      # ★ 原样还原玩家存档
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


func _read_raw(p: String) -> PackedByteArray:
	if not FileAccess.file_exists(p):
		return PackedByteArray()
	var f := FileAccess.open(p, FileAccess.READ)
	return f.get_buffer(f.get_length()) if f != null else PackedByteArray()


func _restore_raw(p: String, b: PackedByteArray) -> void:
	if b.is_empty():
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
		return
	var f := FileAccess.open(p, FileAccess.WRITE)
	if f != null:
		f.store_buffer(b)
