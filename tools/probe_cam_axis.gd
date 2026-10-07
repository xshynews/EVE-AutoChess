extends Node3D

## 相机轴向取证 —— 回答「的  CAM_DIR=(1.0, 0.78, 0.22) 下，世界 +Z 投影到屏幕哪一侧」
##
## ══════════════════════════════════════════════════════════════════
##  为什么要问这个
## ══════════════════════════════════════════════════════════════════
##  `probe_ship_yaw_sheet.gd` 的头注释写着：
##
##      「相机架在 +X 侧 ⇒ **明显 +Z 恒指向右侧**。规则：每艘船的船头都该朝右。」
##
##  但这句话**从来没有被实测过** —— 它是纸面推导。而总览图上要画
##  「前方 →」箭头、要写「船头应朝右」，标反了会**直接误导朝向标定**。
##
##  所以这里用最笨也最硬的办法：往场景里放几个**朝向已知**的参照体，
##  渲染一张图，用眼睛看 +Z 落在屏幕哪一侧。
##
## ── 三个参照，互为交叉验证 ────────────────────────────────────────
##   ① 细锥：底面在 −Z、尖端在 +Z（用 CylinderMesh top_radius=0 绕 X 转 +90°）
##      ⇒ **尖端在屏幕哪边，+Z 就在哪边**
##   ② 细杆两端各一球：+Z 端红球、−Z 端蓝球
##   ③ 一个只朝 +Z 的箭头（ArrowMesh 没有原语，用细杆 + 锥头拼）
##
##  相机 / 光照 / 正交 size 全部**照抄** probe_ship_yaw_sheet，唯一变量就是轴向。
##
## ── 跑法（非 headless：要读 SubViewport 纹理）────────────────────
##   "C:/godot/Godot_v4.7.1-stable_win64_console.exe" \
##     --path "F:/evezzq/eve自走棋918" --quit-after 600 \
##     res://tools/probe_cam_axis.tscn

const OUT_DIR := "user://cam_axis"
const SIZE := 420

## 与 probe_ship_yaw_sheet 完全一致
const CAM_DIR := Vector3(1.0, 0.78, 0.22)
const CAM_SIZE := 1.30

var _vp: SubViewport = null
var _cam: Camera3D = null


func _ready() -> void:
	_build()
	await _run()


func _build() -> void:
	_vp = SubViewport.new()
	_vp.size = Vector2i(SIZE, SIZE)
	_vp.transparent_bg = true
	_vp.own_world_3d = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp)

	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.03, 0.04, 0.05)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.66, 0.72)
	env.ambient_light_energy = 1.5
	we.environment = env
	_vp.add_child(we)

	var key := DirectionalLight3D.new()
	key.light_energy = 1.7
	key.rotation_degrees = Vector3(-34, -128, 0)
	_vp.add_child(key)

	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.size = CAM_SIZE
	_cam.near = 0.01
	_cam.far = 40.0
	_vp.add_child(_cam)          # ⚠️ 先入树再 look_at（否则相机没朝向，渲出一张全白）
	_cam.position = CAM_DIR.normalized() * 8.0
	_cam.look_at(Vector3.ZERO, Vector3.UP)

	# ── ① 锥：尖端在 +Z ──
	var cone := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.0
	cm.bottom_radius = 0.16
	cm.height = 0.72
	cm.radial_segments = 32
	cone.mesh = cm
	cone.rotation = Vector3(PI / 2.0, 0.0, 0.0)   # +Y（锥尖）→ +Z
	cone.position = Vector3(-0.30, 0.22, 0.0)
	cone.material_override = _mat(Color(0.95, 0.74, 0.30))
	_vp.add_child(cone)

	# ── ② 杆 + 两端球：+Z 红 / −Z 蓝 ──
	var rod := MeshInstance3D.new()
	var rm := BoxMesh.new()
	rm.size = Vector3(0.05, 0.05, 1.30)
	rod.mesh = rm
	rod.position = Vector3(0.30, 0.22, 0.0)
	rod.material_override = _mat(Color(0.85, 0.85, 0.88))
	_vp.add_child(rod)
	_vp.add_child(_ball(Vector3(0.30, 0.22, 0.65), Color(0.92, 0.25, 0.25), 0.10))   # +Z
	_vp.add_child(_ball(Vector3(0.30, 0.22, -0.65), Color(0.25, 0.45, 0.95), 0.10))  # −Z

	# ── ③ 地面参考：一条沿 X 的短杆（屏幕左右方向的对照物）──
	var xrod := MeshInstance3D.new()
	var xm := BoxMesh.new()
	xm.size = Vector3(0.9, 0.03, 0.03)
	xrod.mesh = xm
	xrod.position = Vector3(0.0, -0.42, 0.0)
	xrod.material_override = _mat(Color(0.35, 0.40, 0.46))
	_vp.add_child(xrod)


func _ball(pos: Vector3, c: Color, r: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	mi.mesh = sm
	mi.position = pos
	mi.material_override = _mat(c)
	return mi


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = 0.15
	m.roughness = 0.45
	return m


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	await RenderingServer.frame_post_draw
	var tex := _vp.get_texture()
	if tex == null:
		print("[AXIS] 拿不到 SubViewport 纹理（是不是加 --headless 了？）")
		get_tree().quit(1)
		return
	var img := tex.get_image()
	img.save_png("%s/axis.png" % OUT_DIR)

	# 定量读数：把「红球」与「蓝球」在画面里的横坐标量出来。
	# 它们的 z 差 1.3（+0.65 vs −0.65），横坐标之差的正负号就是 +Z 的屏幕方向。
	var rx := _centroid(img, Color(0.92, 0.25, 0.25))
	var bx := _centroid(img, Color(0.25, 0.45, 0.95))
	print("[AXIS] 红球(+Z) 屏幕 x̄ = %.1f   蓝球(−Z) 屏幕 x̄ = %.1f   （画布宽 %d）"
			% [rx, bx, img.get_width()])
	if rx < 0.0 or bx < 0.0:
		print("[AXIS] ⚠️ 有球没找着，看 axis.png 目视判断")
	else:
		print("[AXIS] ⇒ **世界 +Z 投影到屏幕%s**" % ("右侧" if rx > bx else "左侧"))
	print("[AXIS] 输出 -> %s" % ProjectSettings.globalize_path(OUT_DIR))
	get_tree().quit(0)


## 找指定颜色的像素质心横坐标（按通道比例判定，抗光照偏移）
func _centroid(img: Image, want: Color) -> float:
	var sx := 0.0
	var n := 0
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a < 0.5:
				continue
			var d := absf(c.r - want.r) + absf(c.g - want.g) + absf(c.b - want.b)
			if d < 0.30:
				sx += float(x)
				n += 1
	if n < 8:
		return -1.0
	return sx / float(n)
