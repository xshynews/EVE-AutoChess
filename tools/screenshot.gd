extends Node

## 截图工具 —— 在真实（非无头）渲染下跑若干帧，然后保存一张 PNG
## 用途：验证 3D 星空竞技场 + 漂浮窗口 HUD 的实际观感
##
## 用法：
##   godot_console.exe --path <工程> --quit-after N res://tools/screenshot.tscn

const SCENE_PATH := "res://scenes/battle_scene.tscn"
const OUT_PATH := "user://battle_shot.png"

var _battle: Node = null
var _frame := 0
var _warmup := 90   ## 先跑 90 帧让战斗推进到交火状态


func _ready() -> void:
	var packed: PackedScene = load(SCENE_PATH)
	_battle = packed.instantiate()
	add_child(_battle)


func _process(_dt: float) -> void:
	_frame += 1
	if _frame < _warmup:
		return
	_dump_diag()
	# 再等一帧让渲染管线完成
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img == null:
		push_error("截图失败：拿不到 viewport 图像")
		get_tree().quit(1)
		return
	var err := img.save_png(OUT_PATH)
	if err != OK:
		push_error("保存 PNG 失败，错误码 %d" % err)
		get_tree().quit(1)
		return
	print("[截图已保存] ", ProjectSettings.globalize_path(OUT_PATH))
	get_tree().quit(0)


## 把取景相关的运行时数值打进日志，方便对照截图定量校准构图
func _dump_diag() -> void:
	var arena = _battle.get("arena")
	if arena == null:
		print("[DIAG] arena 为空")
		return
	var cam: Camera3D = arena.get("camera")
	var min_v := Vector3(INF, INF, INF)
	var max_v := Vector3(-INF, -INF, -INF)
	var any := false
	for node in arena.get("_ship_nodes").values():
		if not is_instance_valid(node) or not node.visible:
			continue
		any = true
		min_v = min_v.min(node.position)
		max_v = max_v.max(node.position)
	print("[DIAG] 存活可视节点=%d" % arena.get("_ship_nodes").size())
	if any:
		print("[DIAG] 包围盒 x=[%.2f, %.2f] z=[%.2f, %.2f]" % [min_v.x, max_v.x, min_v.z, max_v.z])
		print("[DIAG] 跨度 x=%.2f z=%.2f" % [max_v.x - min_v.x, max_v.z - min_v.z])
	print("[DIAG] 相机 pos=%s dist=%.2f" % [
		cam.position, cam.position.length() if cam else -1.0])
	print("[DIAG] 部署带 own=%.0f enemy=%.0f" % [
		arena.get("deploy_own_z"), arena.get("deploy_enemy_z")])
