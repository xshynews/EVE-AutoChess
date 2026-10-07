extends Node

## ★★★ 53 轮（第四版）· **全库 52 艘「实机布阵姿态」总览出图** ★★★
##
## ══════════════════════════════════════════════════════════════════
##  为什么必须做这个
## ══════════════════════════════════════════════════════════════════
##  53 轮前三版我一直在**猜**：改代码、跑探针、报"全绿" —— 而用户实机
##  一次比一次更明确地说"还是错的"。
##
##  根因已由表头红线 50a 自己写明：
##      **「校验与实现共用同一张表时，表错 ⇒ 全绿 + 实机全乱」**
##      （污染在**输入**不在**算式**）
##  我所有判据都读 `SHIP_AXES`（`bow_axis()` / `up_axis()`），
##  而**这张表本身就是被怀疑的对象** ⇒ 判据永远自我印证，永远"全绿"。
##
##  ⇒ **不再猜。让用户的眼睛当唯一真值**（红线 33：外观真值只有实机图）。
##
## ══════════════════════════════════════════════════════════════════
##  本探针干什么
## ══════════════════════════════════════════════════════════════════
##  对全库 52 艘逐艘：
##    ① **走生产代码**摆出「布阵实机姿态」
##       （`EveShipVisual.setup()` + `snap_facing(body with aim_dir=−Z)`，红线 40）；
##    ② 在离屏 SubViewport 里以**统一机位**渲两格：**侧视**（看舰艏朝哪）
##       与**俯视**（看是否侧躺/肚皮朝天）；
##    ③ 每格标船名 + 一根**红球**指出世界 −Z（敌人方向）。
##
##  ⚠️ 姿态**零复刻**：全部由 `setup()` / `snap_facing()` 给出，
##     探针只负责取景与出图，不碰任何一个旋转量。
##
##  用法（⚠️ **必须非 headless**）：
##      Godot_v4.7.1-stable_win64_console.exe --path "<工程>" --quit-after 60000 \
##          res://tools/probe_fleet_view53.tscn -- --size=260

const YAW := preload("res://scripts/data/eve_ship_yaw.gd")
const SHIP_SCRIPT := preload("res://scripts/visual/eve_ship_visual.gd")
const INDEX := preload("res://scripts/data/eve_ship_asset_index.gd")

const OUT_DIR := "user://fleet_view53"
const CAM_DIST := 8.0
const CAM_SIZE := 1.45
## 红球（敌人方向 −Z）位置。
## ★ 53 轮修正：放 y=0 时 12/104 张被船挡住（armageddon/inquisitor/moa 等
##   大船在 SIDE/TOP 机位下盖住了球）——用户要靠红球判读，被挡 = 白渲。
##   ⇒ 抬到 y=0.42（高于多数船顶）+ 加大半径 ⇒ 永远浮在船顶靠 −Z 一侧，
##     SIDE 机位画面右（相机 forward=−X ⇒ right=−Z）、TOP 机位画面上。
## ⚠️ 53 轮：抬到 y=0 时 12/104 张被大船挡住（armageddon/inquisitor/moa 等）
##   ⇒ 抬到 y=0.36（高于多数船顶）。
## ⚠️⚠️ **但 z 不能太大**：正交视野 `CAM_SIZE=1.45` ⇒ 画面半宽只有 **0.725**。
##   53 轮踩过：把 z 加到 −0.85 后红球**整体飞出画面**（程序检测：104/156 张
##   无红球），比被挡更糟。⇒ **球心 + 半径必须落在 0.725 内**。
##   现取 z=−0.60、r=0.08 ⇒ 最远边缘 0.68 < 0.725 ✓
const BALL_Y := 0.50
const BALL_Z := -0.60
const BALL_R := 0.08

var _size := 260


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var ua := OS.get_cmdline_user_args()
	for t in ua:
		if t.begins_with("--size="):
			_size = int(t.substr(7))

	print("══════════════════════════════════════════════════════════════")
	print("  53f · 全库 52 艘「实机布阵姿态」总览出图（供用户目视裁定）")
	print("══════════════════════════════════════════════════════════════")
	if DisplayServer.get_name() == "headless":
		print("✗ 本探针必须非 headless（dummy 后端取不到纹理）")
		get_tree().quit()
		return
	_run()


func _run() -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(_size, _size)
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)

	# ★ 53 轮修正（用户：图全是黑的）：SubViewport **没有默认光照**，
	#   PBR 船体无光 = 全黑（只有自发光贴图部分可见）。
	#   ⇒ 必须显式加环境 + 平行光，否则出图毫无信息量。
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.92, 0.92, 0.95)
	env.environment = e
	vp.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.light_energy = 1.2
	vp.add_child(sun)

	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = CAM_SIZE
	vp.add_child(cam)

	var ball := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = BALL_R
	sph.height = BALL_R * 2.0
	ball.mesh = sph
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(1, 0.12, 0.1)
	bmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ball.material_override = bmat
	ball.position = Vector3(0, BALL_Y, BALL_Z)
	add_child(ball)

	var ids: Array[String] = []
	for s in INDEX.all():
		ids.append(String(s.id))
	ids.sort()

	# ⚠️ 53 轮：用户两轮反馈「什么都看不出来」⇒ ① 图太小（260px 看不清细节）
	#    ② 只有正视/俯视，**看不出船头朝哪**。加一个 45° 斜视最能判读。
	var shots := [
		["SIDE", Vector3(1, 0, 0), Vector3(0, 1, 0)],
		["TOP", Vector3(0, 1, 0), Vector3(0, 0, -1)],
		["ISO", Vector3(0.72, 0.55, 0.72).normalized(), Vector3(0, 1, 0)],
	]

	for sid in ids:
		var holder := _build(StringName(sid))
		if holder == null:
			print("  ✗ %s 无模型" % sid)
			continue
		add_child(holder)
		for sh in shots:
			cam.global_position = sh[1] * CAM_DIST
			cam.look_at(Vector3.ZERO, sh[2])
			await get_tree().process_frame
			await get_tree().process_frame
			var img := vp.get_texture().get_image()
			if img == null:
				print("  ✗ %s/%s 取图失败" % [sid, sh[0]])
				continue
			img.save_png("%s/%s_%s.png" % [OUT_DIR, sid, sh[0]])
		remove_child(holder)
		holder.free()
		print("  ✔ %s（bow=%s up=%s）" % [
				sid,
				_axes_str(StringName(sid), "bow"),
				_axes_str(StringName(sid), "up")])

	remove_child(ball)
	ball.free()
	remove_child(vp)
	vp.free()
	print("")
	print("出图 %d 张 → %s" % [ids.size() * 2, ProjectSettings.globalize_path(OUT_DIR)])
	get_tree().quit()


## ★ 用**生产代码**摆出「布阵实机姿态」：
##   `EveShipVisual.setup()` 烘焙 `_bow_align` + `snap_facing()` 写 quaternion，
##   几何体自己的 `basis` 由 `_build_hull_model()` 写成 `zero_pose_basis()`。
##  ⇒ 探针**不碰任何旋转量**（红线 40）。
func _build(sid: StringName) -> Node3D:
	var sh := EveShip.new()
	sh.ship_key = sid
	sh.id = 1
	# ⚠️ `setup()` 第 219 行会读 `ship.body.position` ⇒ **必须先给 body**，
	#    否则报 `Invalid access to property 'position' on a base object of type 'Nil'`
	#    （53 轮踩过：图能出完，但 `position` 没设 ⇒ 船不一定在取景中心）。
	sh.body = EveDestinyMotion.Body.new(1)
	sh.body.position = Vector3.ZERO
	sh.body.aim_dir = Vector3(0, 0, -1)
	sh.body.velocity = Vector3.ZERO

	var vis: Variant = SHIP_SCRIPT.new()
	vis.set("ship", sh)
	var hr := Node3D.new()
	hr.name = "Hull"
	vis.set("hull_root", hr)
	vis.add_child(hr)
	vis.call("setup", sh)

	# 布阵态：aim_dir = 世界 −Z（敌人方向，红线 42）
	vis.call("snap_facing", sh.body, true)

	# ★ 53 轮修正（用户：图上出现「保持距离」蓝字）：`setup()` 会建
	#   血条层（`_build_bars`）与**武器射程标签层**（`_build_labels`，
	#   那正是画面里满屏的「保持距离」）—— 标定图只要**几何**，信息层全关。
	vis.call("set_process", false)
	for n in vis.get_children():
		if n is Node3D and String(n.name).begins_with("Labels"):
			(n as Node3D).visible = false
		for c2 in n.get_children():
			if c2 is Node3D and String(c2.name).begins_with("Labels"):
				(c2 as Node3D).visible = false

	return vis as Node3D


func _axes_str(sid: StringName, which: String) -> String:
	var v := YAW.bow_axis(sid) if which == "bow" else YAW.up_axis(sid)
	var names := ["X", "Y", "Z"]
	var best := 0
	var bv := 0.0
	for i in 3:
		if absf(v[i]) > bv:
			bv = absf(v[i])
			best = i
	return ("+" if v[best] > 0.0 else "-") + names[best]
