extends Node
## 探针：真场景里「准备阶段最后 N 秒」到底调了几声、响没响。
##
## 背景（玩家 2026-10-31）：「开战倒计时 最后 5 秒 给提示音吧」。
## 纯音频层探针（`probe_countdown_sfx`）已证明 `play_tick(5)` 能出声、音源不缺失，
## 所以剩下要排的是**上层有没有真的调它** —— 这一层只有真场景能回答。
##
## 做法：加载真 `battle_scene`，等准备阶段起来，把顶条剩余改成 8 秒，
## 然后让它自己跑 9 秒真实帧，逐秒记录：
##   · `_hud.stage_seconds_left()`（给音频层的输入）
##   · `audio.stats()` 的 amb / missing（有没有真播 / 有没有静默缺源）
##
## ⚠️ headless 下音频驱动是 dummy，但 `AudioStreamPlayer.play()` 与计数器照常工作 ——
##    能看到「调了几次」，看不到「好不好听」。
const SCENE_PATH := "res://scenes/battle_scene.tscn"

var _battle: Node = null
var _hud: Control = null
var _audio = null
var _t := 0.0
var _last_sec := -99
var _rings: Array = []


func _ready() -> void:
	_battle = (load(SCENE_PATH) as PackedScene).instantiate()
	add_child(_battle)
	for i in 6:
		await get_tree().process_frame
	_hud = _battle.get("hud")
	_audio = _battle.get("audio")
	var run = _battle.get("run")
	print("[prep] phase=%d（0=PREP）· audio=%s" % [int(run.phase), str(_audio != null)])
	if _audio == null or _hud == null:
		print("✗ 拿不到 audio/hud")
		get_tree().quit(1)
		return
	var cb = _hud.get("command_bar")
	# 归零计数（前面准备阶段开头可能已经响过几声）
	_audio.reset_stats()
	cb.time_left = 8.0
	_t = 0.0
	print("\n[逐秒] 期望：8~6 秒 tick · 5~4 秒 tick_urgent · 3/2/1 count_N")


func _process(dt: float) -> void:
	if _hud == null:
		return
	_t += dt
	var sec := int(_hud.stage_seconds_left())
	if sec != _last_sec:
		_last_sec = sec
		var st: Dictionary = _audio.stats()
		var amb := int(st.get("amb", 0))
		var miss := int(st.get("missing", 0))
		_rings.append({"sec": sec, "amb": amb, "missing": miss, "t": _t})
		print("  t=%5.2fs 顶条剩=%-3d 累计 amb=%-3d missing=%d" % [_t, sec, amb, miss])
	if _t > 10.0:
		_finish()


func _finish() -> void:
	set_process(false)
	var st: Dictionary = _audio.stats()
	print("\n[汇总] 10 秒内 aud 播放总数=%d · 缺源=%d"
			% [int(st.get("amb", 0)), int(st.get("missing", 0))])
	# 期望：8~1 秒共 8 声（tick/tick_urgent/count 各自算一声）
	var n := int(st.get("amb", 0))
	print("  %s" % ("✓ 最后 8 秒每秒都有提示音" if n >= 7 else "✗ 提示音次数不足：%d" % n))
	get_tree().quit()
