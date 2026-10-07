extends Node

## 棋盘朝向 / 舰船尺寸 —— 视觉实验探针（一次性）
##
## ══════════════════════════════════════════════════════════════════
##  它回答两个问题（用户 2026-09-20 提出）
## ══════════════════════════════════════════════════════════════════
##   Q1「棋盘歪着很奇怪，能不能正着？硬要歪，能不能从左下歪到右上？」
##      → 歪的根源 = 相机 DEFAULT_YAW = -0.58 rad(≈-33.2°)，而棋盘是
##        【世界轴对齐】的矩形。两者差 33° → 格子投影成菱形。
##      → 本探针把若干候选 yaw 逐个拍下来，并且**用投影坐标定量描述**
##        「近端横边」的倾斜方向（dy 的符号），不靠肉眼判断方向
##        —— 方向类判断在无头环境里不会报错，只会静默反掉。
##
##   Q2「舰船在棋盘上太小了，放大三倍看看，最小两倍」
##      → 舰船视觉倍率 = EveShipVisual.VISUAL_EXAGGERATION(1.20)。
##      → 本探针在运行时把每艘船的 hull/label 缩放乘上候选倍率，
##        同一机位出图，直接看哪档合适。
##
## ── 跑法（⚠️ 要看像素，不要加 --headless）─────────────────────────
##   "C:/godot/Godot_v4.7.1-stable_win64_console.exe" \
##     --path "F:/evezzq/eve自走棋918" --quit-after 1200 res://tools/probe_view.tscn
##
## 产物：user://view_<名字>.png  +  user://view_report.txt

const SCENE_PATH := "res://scenes/battle_scene.tscn"

## ── 机位候选（yaw，弧度）──
##
##   0.0    = 相机在 +z 正后方，正对棋盘 → 横平竖直（云顶之弈那种）
##  -0.58   = 现状（EVE 默认机位，相机偏西南上方）
##  +0.58   = 镜像（相机偏东南上方）
##  0.30   = 小角度（"稍微歪一点"的折中）
const YAWS := [
	{"name": "yaw_000", "yaw": 0.0, "note": "正对棋盘（横平竖直）"},
	{"name": "yaw_m058", "yaw": -0.58, "note": "现状：EVE 默认机位 -33.2°"},
	{"name": "yaw_p058", "yaw": 0.58, "note": "镜像：+33.2°"},
]

## ── 舰船倍率候选（相对当前 VISUAL_EXAGGERATION=1.20）──
const SHIP_MULS := [
	{"name": "ship_1x", "mul": 1.0, "note": "现状 1.20"},
	{"name": "ship_2x", "mul": 2.0, "note": "两倍 2.40"},
	{"name": "ship_3x", "mul": 3.0, "note": "三倍 3.60"},
]

var _battle: Node = null
var _arena: Variant = null
var _cam: Camera3D = null
var _lines: Array[String] = []
var _ship_base: Dictionary = {}      # id -> {"hull": Vector3, "label": Vector3}


func _ready() -> void:
	var packed: PackedScene = load(SCENE_PATH)
	_battle = packed.instantiate()
	add_child(_battle)

	# 等场景完全就绪（HUD 布局 + 舰队 spawn + 棋盘 configure）
	for _i in 40:
		await get_tree().process_frame

	_arena = _battle.get("arena")
	_cam = _arena.get("camera")
	if _arena == null or _cam == null:
		_line("!! arena / camera 取不到，实验中止")
		_flush()
		get_tree().quit(1)
		return

	_line("═" .repeat(70))
	_line("默认机位：yaw=%.3f  pitch=%.3f  zoom=%.2f  相机距离=%.1f" % [
		float(_arena.orion_cam.get("yaw")), float(_arena.orion_cam.get("pitch")),
		float(_arena.orion_cam.get("zoom")), float(_arena.orion_cam.call("get_distance"))])
	_line("视口 = %s" % str(get_viewport().get_visible_rect().size))
	_line("棋盘 half=%.1f cell=%.2f  position=%s" % [
		float(_arena.board.half), float(_arena.board.cell), str(_arena.board.position)])
	_line("")

	# ── 组 A：机位扫描（取景整块棋盘）──
	_arena.board.set_board_visible(true)
	for item in YAWS:
		_arena.frame_board()
		_apply_yaw(float(item["yaw"]))
		await _settle()
		_probe_geometry("%s（%s）" % [item["name"], item["note"]])
		await _shot(item["name"])

	# ── 组 B：舰船倍率（取景我方部署区 —— 玩家拖拽时实际看到的取景）──
	_apply_yaw(0.0)
	_cache_ship_scales()
	_line("")
	_line("═".repeat(70))
	_line("组 B：舰船倍率（机位固定 yaw=0，取景 = 我方部署区 frame_own_zone）")
	for item in SHIP_MULS:
		_arena.frame_own_zone()
		_apply_yaw(0.0)
		_apply_ship_mul(float(item["mul"]))
		await _settle()
		_probe_ships("%s（%s）" % [item["name"], item["note"]])
		await _shot(item["name"])

	# ── 组 C：正对机位下，棋盘 + 我方区取景的实际观感（给用户看的成品参照）──
	_line("")
	_line("═".repeat(70))
	_apply_ship_mul(3.0)
	_arena.frame_own_zone()
	_apply_yaw(0.0)
	await _settle()
	await _shot("final_own_zone")

	_flush()
	get_tree().quit(0)


# ------------------------------------------------------------------ 操作

func _apply_yaw(y: float) -> void:
	_arena.orion_cam.set("yaw", y)
	_arena.orion_cam.call("apply_to_camera")


func _cache_ship_scales() -> void:
	var nodes: Dictionary = _arena.get("_ship_nodes")
	for id in nodes:
		var v: Variant = nodes[id]
		if v == null or v.hull_root == null:
			continue
		_ship_base[id] = {
			"hull": v.hull_root.scale,
			"label": v.label_root.scale if v.label_root != null else Vector3.ONE,
		}
	_line("缓存了 %d 艘船的基准缩放" % _ship_base.size())


func _apply_ship_mul(mul: float) -> void:
	var nodes: Dictionary = _arena.get("_ship_nodes")
	var n := 0
	for id in nodes:
		if not _ship_base.has(id):
			continue
		var v: Variant = nodes[id]
		if v == null or v.hull_root == null:
			continue
		var b: Dictionary = _ship_base[id]
		v.hull_root.scale = (b["hull"] as Vector3) * mul
		if v.label_root != null:
			v.label_root.scale = (b["label"] as Vector3) * mul
		n += 1
	_line("  已把 %d 艘船的缩放乘上 %.1f" % [n, mul])


func _settle() -> void:
	for _i in 4:
		await get_tree().process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "user://view_%s.png" % name
	img.save_png(path)
	_line("  截图 → %s" % path)


# ------------------------------------------------------------------ 定量诊断

## 把棋盘四角投影到屏幕，并判断「近端横边」的倾斜方向。
##
## ⚠️ 屏幕坐标 y 轴【向下为正】。所以：
##      dy > 0  → 右侧更低 → 视觉上「左上 → 右下」
##      dy < 0  → 右侧更高 → 视觉上「左下 → 右上」（用户希望的这个）
func _probe_geometry(tag: String) -> void:
	var b: Variant = _arena.board
	var h: float = float(b.half)
	var nl: Vector2 = _proj(b, Vector3(-h, 0.0, h))    # 近端（我方）左
	var nr: Vector2 = _proj(b, Vector3(h, 0.0, h))     # 近端（我方）右
	var fl: Vector2 = _proj(b, Vector3(-h, 0.0, -h))   # 远端（敌方）左
	var fr: Vector2 = _proj(b, Vector3(h, 0.0, -h))    # 远端（敌方）右
	var dx := nr.x - nl.x
	var dy := nr.y - nl.y
	_line("── %s" % tag)
	_line("   近左 %s   近右 %s" % [_v2(nl), _v2(nr)])
	_line("   远左 %s   远右 %s" % [_v2(fl), _v2(fr)])
	_line("   近端横边: dx=%+.1f dy=%+.1f  角度=%+.1f°  → %s" % [
		dx, dy, rad_to_deg(atan2(dy, dx)),
		"右上抬起 = 左下→右上 ✔(用户想要)" if dy < -1.0 else
		("几乎水平 ✔" if absf(dy) <= 1.0 else "右侧下沉 = 左上→右下 ✘(现状)")])
	# 一格在屏幕上的对角线尺寸（格子可读性）
	var c0: Vector2 = _proj(b, Vector3(0.0, 0.0, 0.0))
	var c1: Vector2 = _proj(b, Vector3(float(b.cell), 0.0, 0.0))
	var c2: Vector2 = _proj(b, Vector3(0.0, 0.0, float(b.cell)))
	_line("   一格投影: 横向 %.1f px   纵深 %.1f px" % [(c1 - c0).length(), (c2 - c0).length()])


## 量几艘船在屏幕上的像素长度（取 hull 的实际 AABB）
func _probe_ships(tag: String) -> void:
	var nodes: Dictionary = _arena.get("_ship_nodes")
	var cells: Array = []
	for id in nodes:
		var v: Variant = nodes[id]
		if v == null or not v.visible or v.hull_root == null:
			continue
		var px := _screen_span(v.hull_root)
		if px > 0.0:
			cells.append(px)
	if cells.is_empty():
		_line("── %s  （场上没有可见舰船）" % tag)
		return
	cells.sort()
	var mid: float = cells[cells.size() / 2]
	_line("── %s" % tag)
	_line("   场上 %d 艘 · 屏幕船长 px: 最小 %.0f  中位 %.0f  最大 %.0f" % [
		cells.size(), cells[0], mid, cells[cells.size() - 1]])
	# 参照：一格屏幕宽度
	var b: Variant = _arena.board
	var c0: Vector2 = _proj(b, Vector3(0.0, 0.0, 0.0))
	var c1: Vector2 = _proj(b, Vector3(float(b.cell), 0.0, 0.0))
	_line("   参照：一格 = %.0f px → 中位船长 ≈ %.2f 格" % [
		(c1 - c0).length(), mid / maxf(1.0, (c1 - c0).length())])


func _proj(board: Variant, local: Vector3) -> Vector2:
	var w: Vector3 = board.to_global(local) if board.is_inside_tree() else local
	return _cam.unproject_position(w)


## 节点 AABB 在屏幕上的最长投影跨度（像素）
func _screen_span(n: Node3D) -> float:
	var vis := _first_mesh(n)
	if vis == null:
		return 0.0
	var aabb: AABB = vis.get_aabb()
	var gt: Transform3D = vis.global_transform
	var pts: Array[Vector2] = []
	for i in 8:
		var corner := aabb.position + Vector3(
			aabb.size.x * float(i & 1),
			aabb.size.y * float((i >> 1) & 1),
			aabb.size.z * float((i >> 2) & 1))
		pts.append(_cam.unproject_position(gt * corner))
	var best := 0.0
	for i in pts.size():
		for j in range(i + 1, pts.size()):
			best = maxf(best, pts[i].distance_to(pts[j]))
	return best


func _first_mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n
	for c in n.get_children():
		var m := _first_mesh(c)
		if m != null:
			return m
	return null


func _v2(v: Vector2) -> String:
	return "(%.0f,%.0f)" % [v.x, v.y]


# ------------------------------------------------------------------ 输出

func _line(s: String) -> void:
	_lines.append(s)
	print(s)


func _flush() -> void:
	var f := FileAccess.open("user://view_report.txt", FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(_lines))
		f.close()
