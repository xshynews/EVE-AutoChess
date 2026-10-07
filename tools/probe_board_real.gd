extends Node

## 棋盘取景【实机标定探针】（非 headless）
##
## ══════════════════════════════════════════════════════════════════
##  为什么不能用 headless 版（probe_board_fit）
## ══════════════════════════════════════════════════════════════════
##  headless 下 viewport 是 **1920×1920**（实测），而实机窗口是 1080×608。
##  两者的宽高比不同 ⇒ 「同样的世界高度对应多少像素」这件事在两处**不一样**，
##  所以在 headless 里标定出来的 y 会偏。本探针在**真实窗口**下量。
##
##  它做三件事：
##    ① 打印真实 viewport 尺寸 + HUD 设计坐标与实际像素的比例；
##    ② 把相机硬设到布阵档（yaw=BOARD_VIEW_YAW / pitch=BOARD_VIEW_PITCH），
##       投影棋盘四角，同时给出【设计坐标】与【实际像素】两套数；
##    ③ 落一张截图，供人眼复核。
##
## ── 跑法（⚠️ 不要加 --headless）──────────────────────────────────
##   "C:/godot/Godot_v4.7.1-stable_win64_console.exe" \
##     --path "F:/evezzq/eve自走棋918" --quit-after 600 \
##     res://tools/probe_board_real.tscn

const SCENE_PATH := "res://scenes/battle_scene.tscn"
const ARENA_SCRIPT := preload("res://scripts/scene/eve_battle_arena.gd")
const ORBIT_SCRIPT := preload("res://scripts/scene/eve_orbit_camera.gd")
const HUD_SCRIPT := preload("res://scripts/ui/eve_hud_root.gd")

const DESIGN := Vector2(1920.0, 1080.0)
const OUT_SHOT := "user://bench_real.png"

var _battle: Node = null
var _frame := 0
var _shot_done := false


func _ready() -> void:
	_battle = load(SCENE_PATH).instantiate()
	add_child(_battle)


func _process(_delta: float) -> void:
	_frame += 1
	if _frame == 4:
		var arena = _battle.get("arena")
		if arena != null:
			arena.call("show_board_for_deploy")
	if _frame < 20:
		return
	if not _shot_done:
		_measure()
		_shot_done = true
		_shot()


func _measure() -> void:
	var arena = _battle.get("arena")
	var board = arena.get("board")
	var cam = arena.get("orion_cam")
	var cam3d: Camera3D = arena.get("camera")
	if arena == null or board == null or cam == null or cam3d == null:
		print("[REAL] 缺对象")
		return

	var vp := Vector2.ZERO
	if cam3d.get_viewport() != null:
		vp = cam3d.get_viewport().get_visible_rect().size
	var hud_w = _battle.get("hud")
	var hud_size := Vector2.ZERO
	if hud_w != null and hud_w is Control:
		hud_size = (hud_w as Control).size
	var sx := vp.x / DESIGN.x
	var sy := vp.y / DESIGN.y

	print("[REAL] viewport=%s  HUD.size=%s  scale=(%.4f, %.4f)" % [
		str(vp), str(hud_size), sx, sy])
	print("[REAL] RECT_BENCH=%s  RECT_SHOP=%s" % [
		str(HUD_SCRIPT.RECT_BENCH), str(HUD_SCRIPT.RECT_SHOP)])
	print("[REAL] 格带顶(实际像素)=%.1f  格带底=%.1f  商店顶=%.1f" % [
		HUD_SCRIPT.RECT_BENCH.position.y * sy,
		(HUD_SCRIPT.RECT_BENCH.position.y + HUD_SCRIPT.RECT_BENCH.size.y) * sy,
		HUD_SCRIPT.RECT_SHOP.position.y * sy])

	var half: float = float(board.get("half"))
	var bp: Vector3 = board.get("position")
	var u2m: float = float(arena.get("world_unit_in_meters"))

	# ── 按当前常量单点校验 ──
	arena.set("board_view_zoom", float(ARENA_SCRIPT.BOARD_VIEW_ZOOM))
	arena.set("_board_frame_mode", 0)
	cam.set("yaw", float(ARENA_SCRIPT.BOARD_VIEW_YAW))
	cam.set("pitch", float(ARENA_SCRIPT.BOARD_VIEW_PITCH))
	# ⚠️ 必须用**当前**默认 zoom（2026-09-28 起 = 1.616074，不再是 1.0），
	#    否则量到的棋盘尺寸是假的（相机视距 = max_range*1.52/zoom）。
	cam.set("zoom", float(ORBIT_SCRIPT.DEFAULT_ZOOM))
	arena.call("_apply_board_framing_now")

	var mn_y := 1e9
	var mx_y := -1e9
	var mn_x := 1e9
	var mx_x := -1e9
	for cz in [-half, half]:
		for cx in [-half, half]:
			var sp: Vector2 = arena.call("world_to_screen",
					(bp + Vector3(cx, 0.0, cz)) * u2m)
			mn_x = minf(mn_x, sp.x)
			mx_x = maxf(mx_x, sp.x)
			mn_y = minf(mn_y, sp.y)
			mx_y = maxf(mx_y, sp.y)

	var bt: float = HUD_SCRIPT.RECT_BENCH.position.y
	var bb: float = bt + HUD_SCRIPT.RECT_BENCH.size.y
	var bl: float = HUD_SCRIPT.RECT_BENCH.position.x
	var br2: float = bl + HUD_SCRIPT.RECT_BENCH.size.x
	print("[REAL] ── 单点校验（当前常量）──")
	print("[REAL] 棋盘  x[%.0f,%.0f] 宽%.0f  y[%.0f,%.0f] 高%.0f  单格%.1f" % [
		mn_x, mx_x, mx_x - mn_x, mn_y, mx_y, mx_y - mn_y, (mx_x - mn_x) / 11.0])
	print("[REAL] 格带  x[%.0f,%.0f] 宽%.0f  y[%.0f,%.0f] 高%.0f  单格%.1f" % [
		bl, br2, br2 - bl, bt, bb, bb - bt, (br2 - bl) / 8.0])
	print("[REAL] ▶ 棋盘下沿 %.0f vs 格带顶 %.0f → 差 %+.0f（0 = 贴合）" % [mx_y, bt, mx_y - bt])
	print("[REAL] ▶ 宽度差：格带 %.0f − 棋盘 %.0f = %+.0f" % [br2 - bl, mx_x - mn_x, (br2 - bl) - (mx_x - mn_x)])
	print("[REAL] ▶ 棋盘上沿 %.0f（顶条底 46 → %s）" % [
		mn_y, "不撞" if mn_y > 46.0 else "撞了!"])
	print("[REAL] ▶ 棋盘横向居中余量：左 %.0f / 右 %.0f" % [
		mn_x, 1920.0 - mx_x])

	print("[REAL] ==== DONE ====")


func _shot() -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(OUT_SHOT)
	print("[REAL] 截图 -> %s" % ProjectSettings.globalize_path(OUT_SHOT))
