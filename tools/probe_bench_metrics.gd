extends Node

## 备战席改版【尺寸基准探针】
##
## ══════════════════════════════════════════════════════════════════
##  它回答什么
## ══════════════════════════════════════════════════════════════════
##  用户要求「备战席按棋盘比例放大」—— 但"棋盘格子屏幕上到底多少像素"
##  没有任何地方写过。它是相机取景（BOARD_VIEW_ZOOM / 距离 / pitch）的
##  函数，靠读常量算不出来，只能在**真实取景收敛之后**投影量取。
##
##  本探针把布阵取景推到收敛（同 verify_run 的手法），然后：
##    ① 投影棋盘 4 个角 → 量出「屏幕上的棋盘外接框」与「单格像素」；
##    ② 量当前备战席轨道（RECT_BENCH / RECT_SHOP 的像素矩形）；
##    ③ 按「8 格与棋盘格同宽」反算备战席应有的屏幕宽度；
##    ④ 量屏幕底部的空间预算（商店下沿 → 1080）。
##
## ── 跑法 ─────────────────────────────────────────────────────────
##   "C:/godot/Godot_v4.7.1-stable_win64_console.exe" \
##     --headless --path "F:/evezzq/eve自走棋918" --quit-after 600 \
##     res://tools/probe_bench_metrics.tscn
##
##  纯数值输出，不需要像素 → 可以 --headless。

const SCENE_PATH := "res://scenes/battle_scene.tscn"
const HUD_SCRIPT := preload("res://scripts/ui/eve_hud_root.gd")
const ARENA_SCRIPT := preload("res://scripts/scene/eve_battle_arena.gd")
const BOARD_SCRIPT := preload("res://scripts/scene/eve_board.gd")

const DESIGN := Vector2(1920.0, 1080.0)

var _battle: Node = null
var _frame := 0


func _ready() -> void:
	_battle = load(SCENE_PATH).instantiate()
	add_child(_battle)


func _process(_delta: float) -> void:
	_frame += 1
	# 布阵取景收敛需要时间（真实约 0.25s，无头下 delta=0 所以手动推）
	if _frame == 2:
		var arena = _battle.get("arena")
		arena.call("show_board_for_deploy")
	if _frame < 40:
		return
	_report()
	get_tree().quit()


func _report() -> void:
	var arena = _battle.get("arena")
	var hud = _battle.get("hud")
	var cam = arena.get("orion_cam")
	var board = arena.get("board")
	if arena == null or board == null or cam == null:
		print("[METRICS] arena/board/cam 缺失，无法量测")
		return

	# ── 同 verify_run：推够步数让取景收敛到布阵档 ──
	for _i in 240:
		arena.call("_process", 1.0 / 60.0)
	for _i in 60:
		cam.call("_step", 1.0 / 60.0)

	print("[METRICS] ---- 相机实况 ----")
	print("[METRICS] fov=%.2f yaw=%.4f pitch=%.4f zoom=%.4f dist=%.2f max_range=%.2f" % [
		float(cam.get("camera").get("fov")) if cam.get("camera") != null else -1.0,
		float(cam.get("yaw")), float(cam.get("pitch")), float(cam.get("zoom")),
		float(cam.call("distance")), float(cam.call("get_max_range")),
	])

	# ── ① 投影棋盘四角 → 屏幕外接框 ──
	# 棋盘世界尺寸：cell = CELL_METERS/world_unit_in_meters，half = 5.5*cell
	var cell: float = float(board.get("cell"))
	var half: float = float(board.get("half"))
	print("[METRICS] ---- 棋盘几何 ----")
	print("[METRICS] cell(世界单位)=%.4f half=%.4f 边长=%.2f" % [cell, half, half * 2.0])

	# board.position 是它在世界里的位移；四角在 x=±half, z=±half
	var bp: Vector3 = board.get("position")
	var corners := [
		bp + Vector3(-half, 0, -half),
		bp + Vector3(half, 0, -half),
		bp + Vector3(half, 0, half),
		bp + Vector3(-half, 0, half),
	]
	var min_x := 1e9
	var max_x := -1e9
	var min_y := 1e9
	var max_y := -1e9
	for c in corners:
		var sp: Vector2 = arena.call("world_to_screen", c * float(arena.get("world_unit_in_meters")))
		print("[METRICS] corner world=%s -> screen=%s" % [str(c), str(sp.round())])
		min_x = minf(min_x, sp.x)
		max_x = maxf(max_x, sp.x)
		min_y = minf(min_y, sp.y)
		max_y = maxf(max_y, sp.y)

	var board_w := max_x - min_x
	var board_h := max_y - min_y
	print("[METRICS] ---- 棋盘屏幕外接框 ----")
	print("[METRICS] x:[%.1f, %.1f] y:[%.1f, %.1f] w=%.1f h=%.1f" % [
		min_x, max_x, min_y, max_y, board_w, board_h])
	print("[METRICS] ▶ 单格屏幕像素（横向）= %.2f px  (= w / %d)" % [
		board_w / float(BOARD_SCRIPT.COLS), BOARD_SCRIPT.COLS])
	print("[METRICS] ▶ 单格屏幕像素（纵向）= %.2f px  (= h / %d，含透视压缩)" % [
		board_h / float(BOARD_SCRIPT.ROWS), BOARD_SCRIPT.ROWS])

	# ── 最近一行（row 10）与最远一行（row 0）的实际投影高度差 = 透视强度 ──
	# ⚠️ call() 返回 Variant，不能写 `:=`（会 Parse Error: Cannot infer the type）
	var r_near: Vector2 = arena.call("world_to_screen",
			arena.call("board_cell_to_meters", BOARD_SCRIPT.ROWS - 1, 5))
	var r_far: Vector2 = arena.call("world_to_screen",
			arena.call("board_cell_to_meters", 0, 5))
	print("[METRICS] row0 屏幕y=%.1f  row10 屏幕y=%.1f  ⇒ 纵向跨度 %.1f" % [
		r_far.y, r_near.y, r_near.y - r_far.y])

	# ── ② 当前备战席 / 商店 像素矩形 ──
	print("[METRICS] ---- 当前 HUD 矩形 ----")
	print("[METRICS] RECT_BENCH=%s  (h=%.0f)" % [
		str(HUD_SCRIPT.RECT_BENCH), HUD_SCRIPT.RECT_BENCH.size.y])
	print("[METRICS] RECT_SHOP =%s  (h=%.0f · 下沿 %.0f)" % [
		str(HUD_SCRIPT.RECT_SHOP), HUD_SCRIPT.RECT_SHOP.size.y,
		HUD_SCRIPT.RECT_SHOP.position.y + HUD_SCRIPT.RECT_SHOP.size.y])
	print("[METRICS] ▶ 屏幕底部余量 = %.0f px（1080 − 商店下沿）" % [
		DESIGN.y - (HUD_SCRIPT.RECT_SHOP.position.y + HUD_SCRIPT.RECT_SHOP.size.y)])

	# ── ③ 按「备战格 = 棋盘格同宽」反算备战席应有多宽 ──
	var cell_px := board_w / float(BOARD_SCRIPT.COLS)
	var want_bench_w := cell_px * float(HUD_SCRIPT.BENCH_SLOTS)
	print("[METRICS] ---- 比例对齐推算 ----")
	print("[METRICS] ▶ 若 8 格与棋盘格同宽：备战席宽 = %.1f px（当前 %.0f px）" % [
		want_bench_w, HUD_SCRIPT.RECT_BENCH.size.x])
	print("[METRICS] ▶ 每格 %.1f px  ⇒ 比当前单格 %.1f px 大 %.2f 倍" % [
		cell_px, HUD_SCRIPT.RECT_BENCH.size.x / float(HUD_SCRIPT.BENCH_SLOTS),
		cell_px / (HUD_SCRIPT.RECT_BENCH.size.x / float(HUD_SCRIPT.BENCH_SLOTS))])

	# ── ④ 备战席格带「应有的屏幕高度」：按棋盘的纵向格高估 ──
	var row_h := (float(r_near.y) - float(r_far.y)) / float(BOARD_SCRIPT.ROWS - 1)
	print("[METRICS] ▶ 棋盘相邻行屏幕间距（近端）= %.1f px" % row_h)
	print("[METRICS] ▶ 方形格带高 ≈ %.1f px（取横向格宽 ×0.72 作视觉压缩）" % [
		cell_px * 0.72])

	print("[METRICS] ==== DONE ====")
