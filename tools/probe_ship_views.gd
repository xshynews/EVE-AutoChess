extends Node3D

## 舰船「六视图 + 世界轴标」**工程内**取证台（非 headless）
##
## ══════════════════════════════════════════════════════════════════
##  它回答的问题
## ══════════════════════════════════════════════════════════════════
##  「离线渲染图改对了 —— 但**游戏里**真的是这样吗？」
##
##  本探针用**工程自己的模型**（`EveShipModel.instantiate`）与**工程自己的
##  朝向算式**（与 `scripts/visual/eve_ship_visual.gd::_build_hull_model()`
##  逐字一致，含 `EveShipYawTable.axis_remap()` 那个 M），渲出 6 个机位，
##  并把「世界 +Z = 游戏里的【前进方向】」以**红球**画进同一张图。
##
##  ⚠️ 为什么不复用 `probe_ship_axis.gd`：
##     它只算绕世界 Y 的 `yaw`（`MODEL_YAW_FIX + extra_yaw`），**漏乘了
##     `AXIS_REMAP` 的 M** ⇒ 对 7 艘重映射船（myrmidon / catalyst / kestrel …）
##     渲出来是「完全没修过」的姿态 = **取证假阴性**（不报错，只是图骗人）。
##
## ── 机位定义（与离线对照图的唯一真源 `C:\godot\_export\views6.py` 同名同序）──
##      正视图 = 相机在 +Z   · 左视图 = 相机在 −X   · 右视图 = 相机在 +X
##      俯视图 = 相机在 +Y   · 仰视图 = 相机在 −Y   · 后视图 = 相机在 −Z
##  ⚠️ 俯 / 仰两格的 `up` **不能给 (0,1,0)** —— 与视线平行 ⇒ `look_at` 退化
##     （船会被转到一个随机姿态，**不报错**）。
##     这两格的 up 按「画面上 = 世界 ∓Z」反解（与 `pose_sheet.render` 同口径）：
##       俯视（相机在 +Y）画面上 = 世界 −Z ⇒ up = (0, 0, −1)
##       仰视（相机在 −Y）画面上 = 世界 +Z ⇒ up = (0, 0, +1)
##
## ── 跑法（⚠️ 不要加 --headless：headless 下取不到 SubViewport 纹理）──
##   "C:/godot/Godot_v4.7.1-stable_win64_console.exe" \
##     --path "F:/evezzq/eve自走棋918" --quit-after 6000 \
##     res://tools/probe_ship_views.tscn -- --ids=myrmidon --size=420
##
##   `--ids=a,b,c`（默认 myrmidon）· `--size=420`（单图边长）
##   输出 `user://ship_views/<id>_<序号>_<英文机位>.png`（ASCII 名，中文标签在拼图侧加）

const INDEX := preload("res://scripts/data/eve_ship_asset_index.gd")
const SHIP_SCRIPT := preload("res://scripts/visual/eve_ship_visual.gd")

const SIZE := 420
const OUT_DIR := "user://ship_views"
## 与 eve_ship_visual.gd 的 MODEL_YAW_FIX 必须一致（那是工程常量，别在这里改）
const MODEL_YAW_FIX := -PI / 2.0
const CAM_DIST := 8.0
## 正交视野高度（世界单位）。船长归一化到 1.0 ⇒ 1.45 表示船占 69% 画幅。
const CAM_SIZE := 1.45
## 轴标：红球 = 世界 +Z（游戏【前进方向】）· 蓝球 = 世界 −Z（后方）
const BALL_Y := 0.62
const BALL_Z := 0.72
const BALL_R := 0.062

## [文件后缀, 中文名, 相机位置(单位向量), up 提示]
const VIEWS := [
	["zheng", "正视图", Vector3(0, 0, 1), Vector3(0, 1, 0)],
	["zuo", "左视图", Vector3(-1, 0, 0), Vector3(0, 1, 0)],
	["you", "右视图", Vector3(1, 0, 0), Vector3(0, 1, 0)],
	["fu", "俯视图", Vector3(0, 1, 0), Vector3(0, 0, -1)],
	["yang", "仰视图", Vector3(0, -1, 0), Vector3(0, 0, 1)],
	["hou", "后视图", Vector3(0, 0, -1), Vector3(0, 1, 0)],
]

var _ids: PackedStringArray = PackedStringArray(["myrmidon"])
var _size := SIZE

var _vp: SubViewport = null
var _cam: Camera3D = null
var _holder: Node3D = null
var _axis: Node3D = null


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--ids="):
			_ids = a.substr(6).split(",")
		elif a.begins_with("--size="):
			_size = maxi(140, int(a.substr(7)))
	_build()
	await _run()


func _build() -> void:
	_vp = SubViewport.new()
	_vp.size = Vector2i(_size, _size)
	# 不透明深底：拼图时直接 blit，不必处理 alpha 混合
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
	# ⚠️ 先 add_child 再设 position / look_at：不在树里时 look_at 会失败
	#    （船照出来是全白/空，且不报错）。
	_vp.add_child(_cam)

	_holder = Node3D.new()
	_vp.add_child(_holder)

	_axis = Node3D.new()
	_vp.add_child(_axis)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var n := 0
	for id in _ids:
		var sid := StringName(id)
		print("[V6] ── %s ──" % String(id))
		for i in VIEWS.size():
			if await _shot(sid, VIEWS[i], i):
				n += 1
	print("[V6] 出图 %d 张 -> %s" % [n, ProjectSettings.globalize_path(OUT_DIR)])
	print("[V6] 红球 = 世界 +Z（游戏【前进方向】）· 蓝球 = 世界 −Z（后方）")
	print("[V6] ==== DONE ====")
	get_tree().quit(0)


func _shot(sid: StringName, v: Array, idx: int) -> bool:
	# ── ① 船：**直接调游戏代码** `eve_ship_visual._build_hull_model()` ──
	#    本探针不再复刻那行算式 —— 复刻的那一份只用来**对拍**（见 _build_via_game）。
	for c in _holder.get_children():
		_holder.remove_child(c)
		c.queue_free()
	_holder.transform = Transform3D()

	var model := _build_via_game(sid)
	if model == null:
		push_warning("[V6] %s 建船失败" % String(sid))
		return false
	_holder.add_child(model)

	# ── ② 取景：只做「等比缩放 + 居中」。旋转**一个字都不碰**。 ──
	var aabb := _aabb_of(model, Transform3D())
	if aabb.size.length() < 0.0001:
		push_warning("[V6] %s 的 AABB 退化" % String(sid))
		return false
	var long_len := maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z))
	long_len = maxf(long_len, 0.0001)
	var sc := Basis.IDENTITY.scaled(Vector3.ONE * (1.0 / long_len))
	_holder.transform = Transform3D(sc, -(sc * aabb.get_center()))

	# ── ② 相机 ──
	var cam_pos: Vector3 = (v[2] as Vector3).normalized() * CAM_DIST
	_cam.position = cam_pos
	_cam.look_at(Vector3.ZERO, v[3] as Vector3)

	# ── ③ 轴标：挂在 _vp 下（不进 holder）——holder 的 basis 含船的 yaw，
	#        挂进去会把「世界 Z 轴」跟着船转掉，标定立刻失去意义。 ──
	_rebuild_axis()

	await RenderingServer.frame_post_draw
	var tex := _vp.get_texture()
	if tex == null:
		return false
	var img := tex.get_image()
	if img == null:
		return false
	img.save_png("%s/%s_%02d_%s.png" % [OUT_DIR, String(sid), idx + 1, String(v[0])])
	print("[V6]   %-8s cam@(%+.0f,%+.0f,%+.0f)  世界 +Z 在画面：%s"
			% [String(v[1]), cam_pos.x, cam_pos.y, cam_pos.z, _red_dir(img)])
	return true


## 造一艘「**游戏里真的会长成那样**」的船 —— 直接调
## `eve_ship_visual.gd::_build_hull_model()`（那是全工程**唯一**应用朝向的地方），
## 然后把模型从它的节点树里摘出来交给本探针取景。
##
## ⚠️ 为什么值得专门走这一趟：本探针原先自己复刻了那行算式。复刻得再像，
##    也只是「我以为是那样」—— 而 `_build_hull_model()` 一旦被改动
##    （比如有人在 `basis` 之后再写一次 `scale`，会把旋转**静默清掉**），
##    探针照出来的图仍然是「对的」，图就不再有取证价值。
##    走真代码 + 回读 `model.basis` 才能真正证明「工程里就是这个朝向」。
func _build_via_game(sid: StringName) -> Node3D:
	var vis: Variant = SHIP_SCRIPT.new()
	var sh := EveShip.new()
	sh.ship_key = sid
	vis.set("ship", sh)
	var hr := Node3D.new()
	hr.name = "Hull"
	vis.set("hull_root", hr)
	vis.add_child(hr)

	var model := EveShipModel.instantiate(sid)
	if model == null:
		vis.free()
		return null
	vis.call("_build_hull_model", model)

	# ── 回读「游戏代码算出来的朝向」（basis 的列 = 局部轴 → 世界）──
	# ⚠️ `Node3D.basis` 读回来**含缩放**：Godot 内部只存一个 Transform3D，
	#    而 `scale` 是它派生的（这正是红线 31「先 basis 再 scale」的成因）。
	#    本船 s ≈ 0.004 ⇒ 不做 orthonormalize 的话三列打印出来全是 0.00，
	#    会被误读成「零矩阵」。比较与打印**都必须**先正交化。
	var mb := model.basis.orthonormalized()
	var bx := mb.x
	var by := mb.y
	var bz := mb.z
	print("[V6]     游戏节点回读：模型+X→世界(%+.2f,%+.2f,%+.2f) · +Y→(%+.2f,%+.2f,%+.2f) · +Z→(%+.2f,%+.2f,%+.2f)"
			% [bx.x, bx.y, bx.z, by.x, by.y, by.z, bz.x, bz.y, bz.z])
	# ── 与**生产函数**对拍（这才是合法对照）──
	# ⚠️⚠️ 53 轮修正：这里原先写的是一份**手抄的复刻算式**
	#     `R_y(MODEL_YAW_FIX + extra_yaw) · axis_remap`，
	#     它**漏了 `mesh_rot_of(sid)`**（glb 内层网格自己的旋转）⇒ 从诞生起就恒报
	#     "不一致 ✗"。这既是红线 40 的反面教材，也会让每次跑探针都看见假警报
	#     （狼来了 ⇒ 真出问题时没人信）。
	#     ⇒ 改为直接与 `EveShipVisual.zero_pose_basis()`（生产**唯一**真相源）对拍。
	var t: Basis = SHIP_SCRIPT.zero_pose_basis(sid).orthonormalized()
	var same := (t.x - bx).length() < 1e-4 and (t.y - by).length() < 1e-4 \
			and (t.z - bz).length() < 1e-4
	print("[V6]     与生产 zero_pose_basis()：%s" % ("一致 ✓" if same else "**不一致 ✗**"))

	hr.remove_child(model)
	vis.free()
	return model


## 红球在画面里的方位自检 —— 把「世界 +Z 在哪」变成可打印的事实，不靠肉眼。
func _red_dir(src: Image) -> String:
	var im := src.duplicate() as Image
	im.resize(106, 106, Image.INTERPOLATE_NEAREST)
	var w := im.get_width()
	var h := im.get_height()
	var sx := 0.0
	var sy := 0.0
	var n := 0
	for y in h:
		for x in w:
			var c := im.get_pixel(x, y)
			if c.r > 0.30 and c.r > c.g * 1.5 and c.r > c.b * 1.5:
				sx += float(x)
				sy += float(y)
				n += 1
	if n == 0:
		return "未找到红球（可能被船挡住）"
	var vx := sx / float(n) - float(w) * 0.5
	var vy := sy / float(n) - float(h) * 0.5
	var tag := ""
	if absf(vy) > absf(vx) * 0.5:
		tag = "下" if vy > 0.0 else "上"
	if absf(vx) > absf(vy) * 0.5:
		tag = ("右" if vx > 0.0 else "左") + tag
	if tag.is_empty():
		tag = "正中"
	return "%s（%d px）" % [tag, n]


func _rebuild_axis() -> void:
	for c in _axis.get_children():
		_axis.remove_child(c)
		c.queue_free()
	_axis.add_child(_ball(Vector3(0.0, BALL_Y, BALL_Z), Color(0.95, 0.16, 0.16), BALL_R))
	_axis.add_child(_ball(Vector3(0.0, BALL_Y, -BALL_Z), Color(0.16, 0.38, 0.98), BALL_R))
	var rod := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.022, 0.022, BALL_Z * 2.0)
	rod.mesh = bm
	rod.position = Vector3(0.0, BALL_Y, 0.0)
	rod.material_override = _mat(Color(0.80, 0.82, 0.86))
	_axis.add_child(rod)


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
	var mt := StandardMaterial3D.new()
	mt.albedo_color = c
	mt.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return mt


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
