extends Node3D

## 舰艏轴 **标定台** —— 新船入库的第一步（红线 47）
##
## ══════════════════════════════════════════════════════════════════
##  它回答的问题
## ══════════════════════════════════════════════════════════════════
##  「这艘新船，模型空间的 **哪根轴是舰艏**？船背朝哪？」
##
##  一张图 6 格 = 3 根模型轴（X / Y / Z）× 2 个互相垂直的侧视机位。
##  每格 **红球 = 该轴 + 端、蓝球 = − 端**，中间一根灰杆连起来。
##  人对着图找「尖的那一头（舰艏）/ 钝的那一头（引擎喷口在船尾）」，
##  一次就能把 `SHIP_AXES` 里 bow 的**轴和正负**都定死。
##
## ⚠️ **为什么不给自动判据**：
##    「端部宽度分布」与「`_e` 自发光喷口」这两条路都**实测不可用** ——
##    两端都有轴向发光面时会**假一致**（红线 32 / FLIP 表头注释）。
##    所以本工具只负责**把 6 个候选摆到人眼前**，判的人是人，写进 `SHIP_AXES`。
##    自动判据要是哪天可靠了，也**只能**输出候选 + 置信度，不许自动写表。
##
## ── 跑法（⚠️ 不要加 --headless：headless 下取不到 SubViewport 纹理）──
##   "C:/godot/Godot_v4.7.1-stable_win64_console.exe" \
##     --path "F:/evezzq/eve自走棋918" --quit-after 60000 \
##     res://tools/probe_bow_calib.tscn -- --ids=myrmidon,kestrel --size=360
##
##   `--ids=a,b,c`（不给 = 全库 52 艘）· `--size=360`（单格边长）
##   输出 `user://bow_calib/<id>_axes.png`（2 行 × 3 列拼图）+ `report.txt`
##
## ── 格子图例（**固定顺序，看图时照这个对**）──
##   第 1 行：X 轴·视角① | Y 轴·视角① | Z 轴·视角①
##   第 2 行：X 轴·视角② | Y 轴·视角② | Z 轴·视角②
##
##   · 每格 **画面右 = 该轴 + 方向**（红球那侧）· 画面上 = 该轴的某个正交方向
##   · 视角 ①② 是绕该轴互转 90° 的两个侧视机位 ⇒ 一根轴两个视角都看，
##     避免「恰好从这个方向看过去两端重叠」导致的漏判。
##
## ⚠️ 渲的是**模型原始姿态**（不加 MODEL_YAW_FIX / AXIS_REMAP）——
##    要标定的本来就是「模型空间」的语义轴，跟它在世界里怎么摆无关。

const SIZE := 360
const OUT_DIR := "user://bow_calib"
const CAM_DIST := 8.0
## 正交视野高度（世界单位）。船长归一化到 1.0，球在 ±0.62 ⇒ 1.55 留边。
const CAM_SIZE := 1.55
const BALL_R := 0.05
const BALL_D := 0.62

const AXES: Array[Vector3] = [Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)]
const AXIS_NAMES: PackedStringArray = ["X", "Y", "Z"]

var _ids: PackedStringArray = PackedStringArray()
var _size := SIZE

var _vp: SubViewport = null
var _cam: Camera3D = null
var _holder: Node3D = null
var _marks: Node3D = null
var _lines: PackedStringArray = PackedStringArray()


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--ids="):
			_ids = a.substr(6).split(",")
		elif a.begins_with("--size="):
			_size = maxi(140, int(a.substr(7)))
	if _ids.is_empty():
		for s in EveShipAssetIndex.all():
			_ids.append(String(s.id))
	_build()
	await _run()


func _build() -> void:
	_vp = SubViewport.new()
	_vp.size = Vector2i(_size, _size)
	_vp.transparent_bg = false
	_vp.own_world_3d = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp)

	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.031, 0.043, 0.055)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.58, 0.63, 0.70)
	env.ambient_light_energy = 1.35
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	we.environment = env
	_vp.add_child(we)

	var key := DirectionalLight3D.new()
	key.light_energy = 1.8
	key.rotation_degrees = Vector3(-36, -126, 0)
	_vp.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.light_energy = 0.7
	rim.rotation_degrees = Vector3(-14, 58, 0)
	_vp.add_child(rim)

	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.size = CAM_SIZE
	_cam.near = 0.01
	_cam.far = 40.0
	_vp.add_child(_cam)

	_holder = Node3D.new()
	_vp.add_child(_holder)
	_marks = Node3D.new()
	_vp.add_child(_marks)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_lines.append("══════ 舰艏轴标定台（红线 47）══════")
	_lines.append("图例：第1行 = X① Y① Z① · 第2行 = X② Y② Z② · 每格 画面右 = 该轴 + 方向（红球）")
	_lines.append("")
	_lines.append("  id            长轴(AABB)   SHIP_AXES        复核")
	for id in _ids:
		await _one(StringName(id))
	_lines.append("")
	_lines.append("出图目录：%s" % ProjectSettings.globalize_path(OUT_DIR))
	var f := FileAccess.open("%s/report.txt" % OUT_DIR, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(_lines))
		f.close()
	for l in _lines:
		print("[CALIB] %s" % l)
	print("[CALIB] ==== DONE ====")
	get_tree().quit(0)


func _one(sid: StringName) -> void:
	var model := EveShipModel.instantiate(sid)
	if model == null:
		_lines.append("  %-13s  **建船失败**" % String(sid))
		return

	# ── 取景：等比缩放 + 居中，**旋转一个字都不碰**（标定的是模型空间）──
	var aabb := _aabb_of(model, Transform3D())
	if aabb.size.length() < 0.0001:
		_lines.append("  %-13s  **AABB 退化**" % String(sid))
		model.queue_free()
		return
	var long_len := maxf(aabb.size.x, maxf(aabb.size.y, maxf(aabb.size.z, 0.0001)))
	var sc := Basis.IDENTITY.scaled(Vector3.ONE * (1.0 / long_len))
	_holder.transform = Transform3D(sc, -(sc * aabb.get_center()))
	_holder.add_child(model)

	var sheet := Image.create(_size * 3, _size * 2, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.02, 0.02, 0.03, 1.0))
	for ai in AXES.size():
		for vi in 2:
			var img := await _shot(AXES[ai] as Vector3, vi)
			if img == null:
				continue
			# ⚠️ SubViewport 纹理读出来可能是 RGB8，与拼图 RGBA8 不同 ⇒ 必须转，
			#    否则 blit_rect 静默丢弃（报 Condition "format != p_src->format"，图全黑）
			img.convert(Image.FORMAT_RGBA8)
			sheet.blit_rect(img, Rect2i(0, 0, _size, _size), Vector2i(ai * _size, vi * _size))
	sheet.save_png("%s/%s_axes.png" % [OUT_DIR, String(sid)])

	# ── 报告：长轴（AABB 最长边）+ 现行语义轴 + 是否待复核 ──
	var longest := "X"
	var best := aabb.size.x
	for i in 3:
		if aabb.size[i] > best:
			best = aabb.size[i]
			longest = AXIS_NAMES[i]
	var cur := "%s/%s" % [
		_axis_name(EveShipYawTable.bow_axis(sid)),
		_axis_name(EveShipYawTable.up_axis(sid))]
	_lines.append("  %-13s %s(%+.2f)     bow/up=%-11s %s"
			% [String(sid), longest, best / long_len, cur,
			("⚠复核" if EveShipYawTable.needs_review(sid) else "·")])
	model.queue_free()


## 渲一格：`a` = 该格的模型轴，`view` = 0/1 两个互相垂直的侧视机位。
func _shot(a: Vector3, view: int) -> Image:
	# ── 正交基：u1 ⊥ a（用 Y 兜底；a 平行 Y 时改用 Z），u2 = a × u1 ──
	var u := Vector3(0.0, 1.0, 0.0)
	if absf(a.dot(u)) > 0.9:
		u = Vector3(0.0, 0.0, 1.0)
	u = (u - a * a.dot(u)).normalized()
	var u2 := a.cross(u).normalized()
	var up := u if view == 0 else u2

	# 屏幕右 = a、屏幕上 = up ⇒ 相机在 (a × up) 侧看向原点（红线 30 同一套轴）
	_cam.position = a.cross(up) * CAM_DIST
	_cam.look_at(Vector3.ZERO, up)
	_rebuild_marks(a)

	await RenderingServer.frame_post_draw
	var tex := _vp.get_texture()
	if tex == null:
		return null
	var img := tex.get_image()
	if img == null:
		return null
	return img


## 红球 = + 端 · 蓝球 = − 端 · 灰杆连接（挂在 `_marks`，**不进 holder**：
## holder 带归一化缩放，挂进去球会被缩成一个点）。
func _rebuild_marks(a: Vector3) -> void:
	for c in _marks.get_children():
		_marks.remove_child(c)
		c.queue_free()
	_marks.add_child(_ball(a * BALL_D, Color(0.95, 0.16, 0.16)))
	_marks.add_child(_ball(-a * BALL_D, Color(0.16, 0.38, 0.98)))
	var rod := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.02, 0.02, BALL_D * 2.0)
	rod.mesh = bm
	rod.material_override = _mat(Color(0.80, 0.82, 0.86))
	# 杆沿 a：BoxMesh 长边在局部 Z ⇒ 直接用 looking_at 构 basis
	# （⚠️ 别用 look_at：node 还没进树时会报错且不生效）
	var up_hint := Vector3.UP if absf(a.y) < 0.9 else Vector3.FORWARD
	rod.basis = Basis.looking_at(a, up_hint)
	_marks.add_child(rod)


func _ball(pos: Vector3, c: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = BALL_R
	sm.height = BALL_R * 2.0
	mi.mesh = sm
	mi.position = pos
	mi.material_override = _mat(c)
	return mi


func _mat(c: Color) -> StandardMaterial3D:
	var mt := StandardMaterial3D.new()
	mt.albedo_color = c
	mt.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return mt


func _axis_name(v: Vector3) -> String:
	for i in 3:
		if absf(v[i]) > 0.5:
			return ("+" if v[i] > 0.0 else "-") + AXIS_NAMES[i]
	return "(%.2f,%.2f,%.2f)" % [v.x, v.y, v.z]


func _aabb_of(root: Node, pre: Transform3D) -> AABB:
	var parts: Array[AABB] = []
	_collect_aabb(root, pre, parts)
	if parts.is_empty():
		return AABB()
	var a := parts[0]
	for i in range(1, parts.size()):
		a = a.merge(parts[i])
	return a


func _collect_aabb(n: Node, xf: Transform3D, out: Array[AABB]) -> void:
	var here := xf
	if n is Node3D:
		here = xf * (n as Node3D).transform
	if n is MeshInstance3D:
		var a := (n as MeshInstance3D).get_aabb()
		var mn := Vector3(1e9, 1e9, 1e9)
		var mx := Vector3(-1e9, -1e9, -1e9)
		for i in 8:
			var p := here * a.get_endpoint(i)
			mn = mn.min(p)
			mx = mx.max(p)
		out.append(AABB(mn, mx - mn))
	for c in n.get_children():
		_collect_aabb(c, here, out)
