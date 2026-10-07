extends Node

## 棋盘朝向 A/B 严格对照（一次性）
##
## ══════════════════════════════════════════════════════════════════
##  为什么要单独做一个：verify_run 那两张图【不公平】
## ══════════════════════════════════════════════════════════════════
##  它两次运行之间商店是随机的 → 买到的船不同 → 舰队射程中位数不同
##  → compute_deploy_z 给的部署带不同 → frame_battlefield 的取景距离不同。
##  结果「改前」那张镜头离得极近、棋盘占满屏幕，
##  于是画面里同时混进了【角度】和【距离】两个变量，不能用来说明问题。
##
##  本探针把变量锁死：**同一帧、同一取景（frame_own_zone）、同一批船、
##  舰船同为布阵态（3 倍）**，唯一的差别就是 yaw。
##
## 跑法：
##   "C:/godot/Godot_v4.7.1-stable_win64_console.exe" \
##     --path "F:/evezzq/eve自走棋918" --quit-after 600 res://tools/probe_ab.tscn

const SCENE_PATH := "res://scenes/battle_scene.tscn"

const CASES := [
	{"name": "ab_before", "yaw": -0.58, "note": "改前：EVE 默认机位 -0.58"},
	{"name": "ab_after", "yaw": 0.0, "note": "改后：BOARD_VIEW_YAW = 0"},
]

var _battle: Node = null
var _arena: Variant = null
var _cam: Camera3D = null
var _lines: Array[String] = []


func _ready() -> void:
	var packed: PackedScene = load(SCENE_PATH)
	_battle = packed.instantiate()
	add_child(_battle)
	for _i in 45:
		await get_tree().process_frame

	_arena = _battle.get("arena")
	_cam = _arena.get("camera")
	# 锁定变量：棋盘显形 + 舰船布阵态（放大）——两次拍完全一致
	_arena.board.set_board_visible(true)
	_arena.set_ships_board_mode(true)

	for item in CASES:
		# 每次重设取景：frame_own_zone 只吃棋盘尺寸，与 yaw 无关 → 取景恒等
		_arena.frame_own_zone()
		_arena.orion_cam.set("yaw", float(item["yaw"]))
		_arena.orion_cam.call("apply_to_camera")
		for _i in 4:
			await get_tree().process_frame
		_report(String(item["name"]), String(item["note"]))
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(
				"user://%s.png" % String(item["name"]))

	var f := FileAccess.open("user://ab_report.txt", FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(_lines))
		f.close()
	get_tree().quit(0)


func _report(name: String, note: String) -> void:
	var b: Variant = _arena.board
	var h: float = float(b.half)
	var nl := _proj(b, Vector3(-h, 0.0, h))
	var nr := _proj(b, Vector3(h, 0.0, h))
	var fl := _proj(b, Vector3(-h, 0.0, -h))
	var fr := _proj(b, Vector3(h, 0.0, -h))
	var c0 := _proj(b, Vector3(0.0, 0.0, 0.0))
	var c1 := _proj(b, Vector3(float(b.cell), 0.0, 0.0))
	var c2 := _proj(b, Vector3(0.0, 0.0, float(b.cell)))
	# 单位方格的「歪斜度」：格子的横边相对屏幕水平的夹角就是可读性的量化指标
	var skew := rad_to_deg(atan2((c1 - c0).y, (c1 - c0).x))
	var s := "%s  (%s)  相机距离=%.1f" % [name, note, float(_arena.orion_cam.call("get_distance"))]
	s += "\n   近左%s 近右%s 远左%s 远右%s" % [_v(nl), _v(nr), _v(fl), _v(fr)]
	s += "\n   一整格: 横 %.1f px x 纵 %.1f px   宽高比 %.2f" % [
		(c1 - c0).length(), (c2 - c0).length(),
		(c1 - c0).length() / maxf(1.0, (c2 - c0).length())]
	s += "\n   格子横边相对屏幕水平夹角 = %+.1f°  → %s" % [
		skew, "倾斜（菱形感）" if absf(skew) > 5.0 else "接近水平（矩形感）"]
	_lines.append(s)
	print(s)


func _proj(board: Variant, local: Vector3) -> Vector2:
	var w: Vector3 = board.to_global(local) if board.is_inside_tree() else local
	return _cam.unproject_position(w)


func _v(v: Vector2) -> String:
	return "(%.0f,%.0f)" % [v.x, v.y]
