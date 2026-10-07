extends Node

## 棋盘取景【标定探针】
##
## ══════════════════════════════════════════════════════════════════
##  它回答什么
## ══════════════════════════════════════════════════════════════════
##  备战席改版后，屏幕纵向被切成三段：
##      棋盘区 50..760 → 备战格带 760..900 → 商店 908..1066
##  所以棋盘必须**整盘落进 y ∈ [50, 760]**（高 710px）。
##
##  但「BOARD_VIEW_ZOOM 取多少才能得到 710px」**算不出来**：
##  投影含透视（近端格比远端格大），正交近似会差 2~3 倍
##  （实测 zoom=2.0 时棋盘宽 2946px，正交估算只有约 1400px）。
##  所以只能扫。
##
## ── 跑法 ─────────────────────────────────────────────────────────
##   "C:/godot/Godot_v4.7.1-stable_win64_console.exe" \
##     --headless --path "F:/evezzq/eve自走棋918" --quit-after 900 \
##     res://tools/probe_board_fit.tscn
##
##  纯数值输出 → 可以 --headless。

const SCENE_PATH := "res://scenes/battle_scene.tscn"
const BOARD_SCRIPT := preload("res://scripts/scene/eve_board.gd")
const ARENA_SCRIPT := preload("res://scripts/scene/eve_battle_arena.gd")
const ORBIT_SCRIPT := preload("res://scripts/scene/eve_orbit_camera.gd")

const DESIGN := Vector2(1920.0, 1080.0)
## 棋盘区允许的纵向范围（与 EveHudRoot 的备战格带/RECT_SHOP 对齐）
const BAND_TOP := 50.0
const BAND_BOTTOM := 760.0

var _battle: Node = null
var _frame := 0


func _ready() -> void:
	_battle = load(SCENE_PATH).instantiate()
	add_child(_battle)


func _process(_delta: float) -> void:
	_frame += 1
	if _frame < 30:
		return
	_scan()
	get_tree().quit()


func _scan() -> void:
	var arena = _battle.get("arena")
	var board = arena.get("board")
	var cam = arena.get("orion_cam")
	if arena == null or board == null or cam == null:
		print("[FIT] arena/board/cam 缺失")
		return

	# ── 先做一次「相机状态全打印」诊断：focus 的投影必须落在屏幕正中，
	#    不落在正中说明有别的东西在改相机（本探针卡在这里很久）。
	var cam3d: Camera3D = arena.get("camera")
	arena.call("set_board_visible", true, 1)
	arena.set("board_view_zoom", 1.4)
	arena.set("_board_frame_mode", 1)
	cam.set("yaw", float(ARENA_SCRIPT.BOARD_VIEW_YAW))
	cam.set("pitch", float(ORBIT_SCRIPT.DEFAULT_PITCH))
	# ⚠️ 用当前默认 zoom（2026-09-28 起 1.616074）：视距 = max_range*1.52/zoom
	cam.set("zoom", float(ORBIT_SCRIPT.DEFAULT_ZOOM))
	arena.call("_apply_board_framing_now")

	var half: float = float(board.get("half"))
	var bp: Vector3 = board.get("position")
	var u2m: float = float(arena.get("world_unit_in_meters"))
	var vp_size := Vector2.ZERO
	if cam3d != null and cam3d.get_viewport() != null:
		vp_size = cam3d.get_viewport().get_visible_rect().size

	print("[DIAG] viewport=%s  cam.fov=%.2f  current=%s" % [
		str(vp_size), cam3d.fov if cam3d != null else -1.0,
		str(cam3d.current) if cam3d != null else "?"])
	print("[DIAG] cam pos=%s  basis.z(前)=%s" % [
		str(cam3d.global_position.round()) if cam3d != null else "?",
		str(cam3d.global_transform.basis.z.round()) if cam3d != null else "?"])
	print("[DIAG] orbit: yaw=%.3f pitch=%.3f zoom=%.3f max_range=%.2f dist=%.2f" % [
		float(cam.get("yaw")), float(cam.get("pitch")), float(cam.get("zoom")),
		float(cam.get("max_range")), float(cam.call("distance"))])
	print("[DIAG] orbit focus=%s   board.position=%s" % [
		str(cam.get("focus")), str(bp)])
	var fp: Vector2 = arena.call("world_to_screen", bp * u2m)
	print("[DIAG] focus 的投影=%s  （应等于 viewport 中心 %s）" % [
		str(fp.round()), str(vp_size * 0.5)])
	var origin_p: Vector2 = arena.call("world_to_screen", Vector3.ZERO)
	print("[DIAG] 世界原点的投影=%s" % str(origin_p.round()))
	print("[DIAG] board.cell=%.3f half=%.3f u2m=%.1f" % [
		float(board.get("cell")), half, u2m])

	# ── 二维扫描：俯角 × 取景倍率 ────────────────────────────────────
	#
	# ⚠️⚠️ headless 下 viewport 是 1920×**1920**（实测），而实机窗口是
	#      1920×1080。fov 是垂直的（KEEP_HEIGHT），所以：
	#        横向像素 = headless 值（宽都是 1920，不变）
	#        纵向像素 = headless 值 × (1080/1920) = ×0.5625
	#        y 实机  = 540 + (y_headless − 960) × 0.5625
	#      不做这个换算会得出「棋盘高 1229px」这种实机上不存在的数。
	const Y_SCALE := 1080.0 / 1920.0
	var ax_scale := 1.0

	# 复用上面已声明的 half / bp / u2m（⚠️ 别再声明一次，会 Parse Error）

	print("[FIT] 目标：纵向落在 [%.0f, %.0f]（高 %.0f）且横向 ≤ 1920" % [
		BAND_TOP, BAND_BOTTOM, BAND_BOTTOM - BAND_TOP])
	print("[FIT] pitch   zoom |  w_实机  h_实机 |  y_top  y_bot | 横溢出")
	print("[FIT] -------------+---------------+--------------+-------")

	for pi in [1.05]:
		for zi in [17, 18]:
			var z := float(zi) * 0.1
			for oi in range(0, 33, 2):
				var off := float(oi)
				arena.set("board_view_zoom", z)
				arena.set("_board_frame_mode", 1)
				var fr: Dictionary = arena.call("_board_framing")
				cam.call("set_range_from_half_extent", fr["half_x"], fr["half_z"])
				cam.set("yaw", float(ARENA_SCRIPT.BOARD_VIEW_YAW))
				cam.set("pitch", pi)
				# ⚠️ 用当前默认 zoom（2026-09-28 起 1.616074）：视距 = max_range*1.52/zoom
				cam.set("zoom", float(ORBIT_SCRIPT.DEFAULT_ZOOM))
				# 焦点沿 +z（往近端）偏移 —— 焦距往近端推，棋盘（在焦点远端侧）
				# 就会在画面上抬。
				var f: Vector3 = fr["focus"] + Vector3(0.0, 0.0, off)
				cam.set("focus", f)
				cam.call("apply_to_camera")

				var min_x := 1e9
				var max_x := -1e9
				var min_y := 1e9
				var max_y := -1e9
				for cz in [-half, half]:
					for cx in [-half, half]:
						var sp: Vector2 = arena.call("world_to_screen",
								(bp + Vector3(cx, 0.0, cz)) * u2m)
						min_x = minf(min_x, sp.x)
						max_x = maxf(max_x, sp.x)
						min_y = minf(min_y, sp.y)
						max_y = maxf(max_y, sp.y)
				var w_act := (max_x - min_x) * ax_scale
				var y_top := 540.0 + (min_y - 960.0) * Y_SCALE
				var y_bot := 540.0 + (max_y - 960.0) * Y_SCALE
				print("[OFF] zoom=%.1f off=%4.0f | w=%6.0f | y=%5.0f..%5.0f (h=%4.0f)" % [
					z, off, w_act, y_top, y_bot, y_bot - y_top])

	print("[FIT] ==== DONE ====")
