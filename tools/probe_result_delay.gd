extends Node

## 结算弹窗延迟出图探针（**非无头**）—— 2026-10-01 用户要求「击毁后一秒弹出」
##
## 跑法：
##   "C:/godot/Godot_v4.7.1-stable_win64_console.exe" \
##     --path "F:/evezzq/eve自走棋918" --quit-after 4000 \
##     res://tools/probe_result_delay.tscn
##
## 产物在 `user://result_delay/`
##
## ══════════════════════════════════════════════════════════════════
##  这个探针要证明的那一件事
## ══════════════════════════════════════════════════════════════════
##  延迟 1 秒的**唯一目的**是让玩家看见最后一艘敌舰的击毁爆炸。
##  ⇒ 所以判据不是「1 秒后弹了」（verify_run 已经在无头里验过），
##     而是**打完那一刻画面上真的有东西可看**：开火线 + 爆炸。
##
##  三张图构成一组证据链：
##    ① 击毁瞬间（t = 0）—— 最后那一下开火线还在、爆炸刚起
##    ② 延迟中（t ≈ 0.5）—— 爆炸在扩散，**结算页还没盖上来**
##    ③ 延迟到点（t ≈ 1.1）—— 结算页上台
##
##  ⚠️ 如果 ② 里结算页已经盖住了画面，说明延迟没生效（这正是改造前的行为）。
## ══════════════════════════════════════════════════════════════════

const BATTLE_SCENE := preload("res://scenes/battle_scene.tscn")
const BATTLE_SCRIPT := preload("res://scripts/eve_battle_scene.gd")

const SHOT_DIR := "user://result_delay"


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SHOT_DIR)
	if DisplayServer.get_name() == "headless":
		print("✗ 本探针必须非 headless")
		get_tree().quit()
		return
	print("=".repeat(64))
	print("结算弹窗延迟出图探针 —— 1920×1080")
	print("=".repeat(64))

	var scene: Variant = BATTLE_SCENE.instantiate()
	add_child(scene)
	await _frames(90)

	var run = scene.get("run")
	run.set("coin", 999)
	for id in ["punisher", "incursus", "slasher"]:
		run.get("bench").append({"ship_key": StringName(id), "star": 1, "cost": 1})
	run.emit_signal("changed")
	await _frames(5)
	for i in 3:
		run.call("deploy_from_bench", 0, 7, i)
	run.emit_signal("changed")
	await _frames(5)
	scene.call("start_battle")
	await _frames(60)
	print("  开战 · 快进到战斗结束前一刻")

	# ⚠️ 快进到**刚好打完**：多快进一秒就会整段错过要拍的窗口。
	#    做法：小步快进，每步检查 sim.finished。
	var sim = scene.get("sim")
	if sim == null:
		print("  ✗ 没有模拟器")
		get_tree().quit()
		return
	var guard := 0
	while not bool(sim.get("finished")) and guard < 400:
		scene.call("debug_fast_forward_battle", 0.5)
		await _frames(1)
		guard += 1
	print("  战斗结束：elapsed=%.1fs（快进 %d 步）" % [float(sim.get("elapsed")), guard])

	# ① 击毁瞬间
	await _shot("01_击毁瞬间")
	# ② 延迟中：等约 0.5 秒（真实帧）
	await _wait_seconds(0.5)
	var hud = scene.get("hud")
	print("  t≈0.5s · 结算页在台上？%s（应为 false）" % str(hud.call("result_is_open")))
	await _shot("02_延迟中_爆炸扩散")
	# ③ 延迟到点
	await _wait_seconds(0.8)
	print("  t≈1.3s · 结算页在台上？%s（应为 true）" % str(hud.call("result_is_open")))
	await _shot("03_结算页上台")

	print("完成。产物在 user://result_delay/")
	get_tree().quit()


## 等**真实**秒数（按帧累加 `delta`）。
##
## ⚠️ 不能用 `create_timer` —— 它按 `process` 走，而我们要等的正是
##    `_process` 里那一秒。这里逐帧等、逐帧判，把「等了多少秒」打出来，
##    让用户看到探针确实在延迟窗口里截的图。
func _wait_seconds(sec: float) -> void:
	var t := 0.0
	while t < sec:
		var d := await _next_delta()
		t += d


func _next_delta() -> float:
	var d := get_process_delta_time()
	await get_tree().process_frame
	return d


func _shot(name: String) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var vp := get_viewport()
	var img := vp.get_texture().get_image()
	if img == null:
		print("  ✗ %s：取图失败" % name)
		return
	var path := SHOT_DIR + "/" + name + ".png"
	img.save_png(path)
	print("  ✔ %s → %s" % [name, path])


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().process_frame
