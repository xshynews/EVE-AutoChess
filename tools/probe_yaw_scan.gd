extends Node

## 棋盘机位小角度扫描（一次性）
##
## ══════════════════════════════════════════════════════════════════
##  为什么还要扫一遍：用户说「如果硬要歪着，可不可以从左下歪到右上」
## ══════════════════════════════════════════════════════════════════
##  实测（probe_view）：yaw < 0 时近端横边的右端【更高】，
##  也就是视觉上本来就是「左下 → 右上」；yaw > 0 才是反的。
##  但 -0.58 太陡（-27.7°），方形棋盘投影成菱形，反而不像「斜着的矩形」。
##  本扫描补上中间几档，好判断「保留一点斜度」时该停在哪。
##
## 跑法：
##   "C:/godot/Godot_v4.7.1-stable_win64_console.exe" \
##     --path "F:/evezzq/eve自走棋918" --quit-after 900 res://tools/probe_yaw_scan.tscn

const SCENE_PATH := "res://scenes/battle_scene.tscn"

const CANDIDATES := [
	{"name": "s000", "yaw": 0.0, "note": "完全正对 0°"},
	{"name": "sm08", "yaw": -0.1396, "note": "-8°"},
	{"name": "sm14", "yaw": -0.2443, "note": "-14°"},
	{"name": "sm20", "yaw": -0.3491, "note": "-20°"},
	{"name": "sm28", "yaw": -0.4887, "note": "-28°（≈现状 -0.58）"},
]

var _battle: Node = null
var _arena: Variant = null
var _cam: Camera3D = null
var _lines: Array[String] = []


func _ready() -> void:
	var packed: PackedScene = load(SCENE_PATH)
	_battle = packed.instantiate()
	add_child(_battle)
	for _i in 40:
		await get_tree().process_frame

	_arena = _battle.get("arena")
	_cam = _arena.get("camera")
	_arena.board.set_board_visible(true)

	for item in CANDIDATES:
		_arena.frame_board()
		_arena.orion_cam.set("yaw", float(item["yaw"]))
		_arena.orion_cam.call("apply_to_camera")
		for _i in 3:
			await get_tree().process_frame
		_report(String(item["name"]), String(item["note"]), float(item["yaw"]))
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png("user://scan_%s.png" % String(item["name"]))
		_lines.append("  截图 → user://scan_%s.png" % String(item["name"]))

	var f := FileAccess.open("user://yaw_scan_report.txt", FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(_lines))
		f.close()
	get_tree().quit(0)


func _report(name: String, note: String, yaw: float) -> void:
	var b: Variant = _arena.board
	var h: float = float(b.half)
	var nl := _proj(b, Vector3(-h, 0.0, h))
	var nr := _proj(b, Vector3(h, 0.0, h))
	var dx := nr.x - nl.x
	var dy := nr.y - nl.y
	var c0 := _proj(b, Vector3(0.0, 0.0, 0.0))
	var c1 := _proj(b, Vector3(float(b.cell), 0.0, 0.0))
	var c2 := _proj(b, Vector3(0.0, 0.0, float(b.cell)))
	var s := "%s  yaw=%+.4f (%s)" % [name, yaw, note]
	s += "\n   横边倾斜 %+.1f°   一格 横 %.1f x 纵 %.1f px   宽高比 %.2f" % [
		rad_to_deg(atan2(dy, dx)), (c1 - c0).length(), (c2 - c0).length(),
		(c1 - c0).length() / maxf(1.0, (c2 - c0).length())]
	_lines.append(s)
	print(s)


func _proj(board: Variant, local: Vector3) -> Vector2:
	var w: Vector3 = board.to_global(local) if board.is_inside_tree() else local
	return _cam.unproject_position(w)
