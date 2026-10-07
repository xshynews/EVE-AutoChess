extends Node

## 「写入 godot」的终极验收：**把船放进真实战场，用游戏自己的相机拍**（非 headless）
##
## ══════════════════════════════════════════════════════════════════
##  与 `probe_ship_views` 的分工
## ══════════════════════════════════════════════════════════════════
##   · `probe_ship_views`：**独立 SubViewport**（无天空盒 / 无棋盘 / 无 HUD），
##     出 6 个正交机位，用来和用户的 EVE 实机图逐格比对。
##   · **本探针**：加载 `scenes/battle_scene.tscn`，用 `EveShip.create()` 造船
##     → `arena.spawn_ship_visual()`（**真正的游戏运行路径**）→ 用**游戏自己的相机**拍。
##     看到的画面 = 玩家在游戏里看到的样子（含天空盒 / 棋盘 / HUD）。
##
## ── 跑法（⚠️ 不要加 --headless：headless 下取不到纹理）──
##   "C:/godot/Godot_v4.7.1-stable_win64_console.exe" --path "F:/evezzq/eve自走棋918" \
##     --quit-after 900 res://tools/probe_ship_in_scene.tscn -- --ids=myrmidon
##
##   输出 `user://ship_in_scene.png`

const SCENE_PATH := "res://scenes/battle_scene.tscn"
const OUT_SHOT := "user://ship_in_scene.png"

const F_SHOW_BOARD := 4
const F_PLACE := 14
const F_SHOT := 24

var _battle: Node = null
var _frame := 0
var _ids: PackedStringArray = PackedStringArray(["myrmidon"])
var _stage := 0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--ids="):
			_ids = a.substr(6).split(",")
	_battle = load(SCENE_PATH).instantiate()
	add_child(_battle)


func _process(_d: float) -> void:
	_frame += 1
	if _frame == F_SHOW_BOARD:
		var arena = _battle.get("arena")
		if arena != null:
			arena.call("show_board_for_deploy")
	elif _frame == F_PLACE:
		_place()
	elif _frame == F_SHOT:
		_shot()


func _place() -> void:
	var arena = _battle.get("arena")
	if arena == null:
		print("[SCENE] 缺 arena")
		return
	var dz := 0.0
	var v = arena.get("deploy_own_z")
	if v != null:
		dz = float(v)
	print("[SCENE] deploy_own_z = %.1f m" % dz)
	for i in _ids.size():
		var sid := StringName(_ids[i])
		var ship: EveShip = EveShip.create(9000 + i, String(sid),
				EveShip.Faction.AMARR, EveShip.Class.CRUISER, 0, 3)
		ship.ship_key = sid
		var off := (float(i) - float(_ids.size() - 1) * 0.5) * 140.0
		ship.body.position = Vector3(off, 0.0, dz)
		var vis: Node3D = arena.call("spawn_ship_visual", ship)
		var model: Node3D = null
		if vis != null:
			var hr: Node = vis.get("hull_root")
			if hr != null:
				model = hr.get_node_or_null("Model_%s" % String(sid))
		if model != null:
			var mb := model.basis.orthonormalized()
			print("[SCENE] %s 放到 %s · 舰艏(模型+X)→世界(%+.2f,%+.2f,%+.2f)"
					% [String(sid), str(ship.body.position), mb.x.x, mb.x.y, mb.x.z])
		else:
			print("[SCENE] %s 已放置，但没找到 Model_%s 节点" % [String(sid), String(sid)])
	_aim(dz)


## 把轨道相机推到船前。
##
## ⚠️ `EveOrbitCamera` 的 `yaw` / `pitch` / `zoom` / `focus` / `max_range`
##    都是 **public var** ⇒ 可以直接设（不用走输入）。但它的 `_target_*`
##    可能是动画中的目标值 ⇒ 一并置 `NAN` 掐掉动画，否则下一帧被拉回去。
## ⚠️ `focus` 的单位是**世界单位**（= 米 / `METERS_PER_UNIT`），不是米。
func _aim(dz_m: float) -> void:
	var arena = _battle.get("arena")
	if arena == null:
		return
	var tgt := Vector3(0.0, 0.0, dz_m / 1000.0)
	# ⚠️ 光停 `orion_cam` 不够 —— **arena 自己每帧也在调** `orion_cam.apply_to_camera()`，
	#    所以手摆的机位会被它重新盖掉（实测：相机又退回了全景）。
	#    这里直接把 arena 的每帧逻辑停掉（只停逻辑，不影响渲染）。
	if arena is Node:
		(arena as Node).set_process(false)
		(arena as Node).set_physics_process(false)
		print("[SCENE] 已停用 arena 的每帧逻辑")
	var cam = arena.get("orion_cam")
	if cam != null and cam is Node:
		# ⚠️ 必须**停掉轨道相机自己的 `_process`** —— 它每帧都会按自己的
		#    `yaw/pitch/zoom/focus` 重新 `apply_to_camera()`，
		#    不停的话下面手摆的机位**下一帧就被抹掉**（不报错，只是图没变）。
		(cam as Node).process_mode = Node.PROCESS_MODE_DISABLED
		print("[SCENE] 已停用 orion_cam 的每帧覆盖")
	var c3d: Camera3D = arena.get("camera")
	if c3d == null:
		print("[SCENE] 没找到 arena.camera")
		return
	# 船长归一化后 ≈ 2.6~4 世界单位 ⇒ 机位摆在约 9 单位外，整艘都能进画面。
	c3d.global_position = tgt + Vector3(2.6, 2.1, 7.6)
	c3d.look_at(tgt + Vector3(0.0, 0.0, 0.0), Vector3.UP)
	print("[SCENE] 相机手动摆位 %s → 目标 %s" % [str(c3d.global_position), str(tgt)])


func _shot() -> void:
	var vp := get_viewport()
	if vp == null:
		print("[SCENE] 无 viewport")
		get_tree().quit(0)
		return
	var img := vp.get_texture().get_image()
	if img == null:
		print("[SCENE] 取不到纹理")
		get_tree().quit(0)
		return
	img.save_png(OUT_SHOT)
	print("[SCENE] 截图 -> %s" % ProjectSettings.globalize_path(OUT_SHOT))
	print("[SCENE] ==== DONE ====")
	get_tree().quit(0)
