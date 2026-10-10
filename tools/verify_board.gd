extends Node

## 棋盘验收 —— 显示 11×11 棋盘并截图
##
## 跑法（⚠️ 不要加 --headless，否则拿不到像素）：
##   "C:/godot/Godot_v4.7.1-stable_win64_console.exe" --path "F:/evezzq/eve自走棋918" \
##     --quit-after 400 res://tools/verify_board.tscn
##
## 产物：user://board_shot.png
##   另存一张关掉 HUD 的 user://board_only.png，方便单看棋盘几何

const SCENE_PATH := "res://scenes/battle_scene.tscn"
const OUT_WITH_HUD := "user://board_shot.png"
const OUT_ONLY := "user://board_only.png"
const OUT_WINDOWS := "user://window_shot.png"

var _battle: Node = null
var _arena: Node = null
var _frame := 0
var _stage := 0


func _ready() -> void:
	var packed: PackedScene = load(SCENE_PATH)
	_battle = packed.instantiate()
	add_child(_battle)


func _process(_dt: float) -> void:
	_frame += 1

	# 60 帧：等战斗场景把舰队摆好
	if _frame == 60:
		_arena = _battle.get("arena")
		if _arena == null:
			push_error("拿不到 arena")
			get_tree().quit(1)
			return
		_arena.call("set_board_visible", true)
		print("[棋盘] 显示；half=%.1f 格边长=%.1f"
				% [_arena.get("board").get("half"), _arena.get("board").get("cell")])
		return

	# 90 帧：高亮一格（我方部署区中间）
	if _frame == 90:
		var board = _arena.get("board")
		board.call("highlight", 9, 4)
		print("[棋盘] 高亮 r9 c4（我方部署区）")
		return

	# 105 帧：把相机的实际朝向与四角投影打出来，用于校验取景
	if _frame == 105:
		_dump_camera()
		return

	# 120 帧：连 HUD 一起截
	if _frame == 120:
		await _shot(OUT_WITH_HUD)
		return

	# 150 帧：关掉 HUD，只留棋盘
	if _frame == 150:
		var hud = _battle.get("hud")
		if hud != null:
			hud.visible = false
		return

	# 180 帧：截纯棋盘（先打一遍相机状态 —— 与第 105 帧对比即可看出相机是否在漂）
	if _frame == 180:
		_dump_camera()
		await _shot(OUT_ONLY)
		return

	# 210 帧：把左侧两个窗口拖到画面中央、并改尺寸 —— 验证「可拖动 / 可缩放」
	if _frame == 210:
		_verify_windows()
		return

	# 240 帧：把窗口拖出屏幕 —— 验证「会被 clamp 回视口内」
	if _frame == 240:
		_verify_clamp()
		return

	# 270 帧：截窗口操作后的状态
	if _frame == 270:
		var hud = _battle.get("hud")
		if hud != null:
			hud.visible = true
		var board = _arena.get("board")
		if board != null:
			board.visible = false
		return

	# 300 帧：截图退出
	if _frame == 300:
		await _shot(OUT_WINDOWS)
		get_tree().quit(0)


## 拖动 + 缩放：直接把两个窗口摆到画面中央，并改成一个明显不同的大小
func _verify_windows() -> void:
	var hud = _battle.get("hud")
	if hud == null:
		print("[窗口] 拿不到 hud")
		return
	var syn = hud.get("synergy_window")
	var eq = hud.get("equipment_window")
	syn.call("set_window_rect", 660.0, 300.0, 300.0, 400.0)
	eq.call("set_window_rect", 990.0, 300.0, 260.0, 180.0)
	print("[窗口] 羁绊窗 -> pos=%s size=%s" % [syn.get("position"), syn.get("size")])
	print("[窗口] 装备窗 -> pos=%s size=%s" % [eq.get("position"), eq.get("size")])


## 把窗口设到视口外，看 _clamp_into_viewport 是否把它拉回来
func _verify_clamp() -> void:
	var hud = _battle.get("hud")
	var log_w = hud.get("log_window")
	log_w.set("position", Vector2(4800.0, 2200.0))     # 远在屏幕外
	log_w.call("_clamp_into_viewport")
	var p: Vector2 = log_w.get("position")
	# clamp 口径：横向至少保留 MIN_VISIBLE(60)px 可见 -> x<=1920-60=1860
	#           纵向保证标题栏不跑出屏幕      -> y<=1080-HEADER_H(26)=1054
	print("[窗口] 日志窗拖到 (4800,2200) 后实际落点 = %s（应被拉回 x<=1860 y<=1054）" % p)
	# 再把它挪到一个能看见的位置，方便截图确认缩放柄画出来了
	log_w.call("set_window_rect", 1340.0, 300.0, 320.0, 260.0)


func _shot(path: String) -> void:
	# ⚠️ headless 下不渲染，`frame_post_draw` 永远不会发出 ⇒ 不跳过就挂死到超时。
	#    无头时只跑流程与诊断输出，不截图。
	if DisplayServer.get_name() == "headless":
		print("[截图跳过] headless：", path)
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img == null:
		push_error("截图失败")
		return
	var err := img.save_png(path)
	if err != OK:
		push_error("保存失败 %d" % err)
		return
	print("[截图已保存] ", ProjectSettings.globalize_path(path))


## 把相机的实际状态与棋盘四角的屏幕投影打出来。
## 用途：判断「棋盘在画面里偏了」到底是取景问题还是几何问题。
func _dump_camera() -> void:
	var cam: Camera3D = _arena.get("camera")
	var oc = _arena.get("orion_cam")
	var board = _arena.get("board")
	if cam == null or oc == null or board == null:
		print("[诊断] 拿不到相机 / 轨道控制器 / 棋盘")
		return
	print("[诊断] cam.pos=%s rot_deg=%s" % [cam.position, cam.rotation_degrees])
	print("[诊断] focus=%s yaw=%.3f pitch=%.3f zoom=%.3f dist=%.2f max_range=%.2f" % [
		oc.get("focus"), float(oc.get("yaw")), float(oc.get("pitch")),
		float(oc.get("zoom")), float(oc.call("distance")),
		float(oc.get("max_range"))])
	print("[诊断] board.visible=%s half=%.1f cell=%.1f" % [
		board.get("visible"), float(board.get("half")), float(board.get("cell"))])
	var h: float = float(board.get("half"))
	for label in ["ZERO", "远左", "远右", "近右", "近左"]:
		var p := Vector3.ZERO
		match label:
			"远左": p = Vector3(-h, 0, -h)
			"远右": p = Vector3(h, 0, -h)
			"近右": p = Vector3(h, 0, h)
			"近左": p = Vector3(-h, 0, h)
		print("   %s %s -> screen %s" % [label, p, cam.unproject_position(p)])
	# 四角投影的重心 —— 应当非常接近画面中心 (960, 540)
	var pts: Array[Vector2] = []
	for p in [Vector3(-h, 0, -h), Vector3(h, 0, -h), Vector3(h, 0, h), Vector3(-h, 0, h)]:
		pts.append(cam.unproject_position(p))
	var c := (pts[0] + pts[1] + pts[2] + pts[3]) * 0.25
	print("[诊断] 四角投影重心 = %s （画面中心应为 960,540）" % c)
