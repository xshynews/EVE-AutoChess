extends Node3D
## ══════════════════════════════════════════════════════════════════════
## ⛔⛔ **53 轮标注：本探针的判据/出图已作废**，仅留档参考 ——
##    原因见「接手手册-2026-09-24 / 03_3D模型朝向标定.md」§16.5（对照图两硬伤）。
##    **不要**拿它的输出当下结论。
##  51 轮 · **工具 ↔ 实机 姿态对照台**（左 = 工具视角，右 = 实机视角）
## ══════════════════════════════════════════════════════════════════════
##
## ── 为什么要有这一条（用户 51 轮原话）─────────────────────────────
##   「我用工具定下舰船应该有朝向，然后你进游戏看建模，一个一个翻转建模，
##     直到翻转来和工具定下的一样了，那就以这个标准为准。如果出现参照系
##     的数据不一样，那就记下不一样，多记几个，看看是哪出了问题。」
##   ⇒ 用户要的是**两屏并排**、人眼一比就知道哪艘不一致。
##
## ── 两屏各是什么（⭐ 关键：两边都走**生产代码**，红线 40）────────
##   左屏「工具视角」：把船的 `basis` 设成 `EveShipVisual.zero_pose_basis(id)`，
##                     即**标定工具里那艘船的姿态**（工具 49 轮起就是这么摆的）。
##   右屏「实机视角」：把船按**实机挂载链**摆 —— `hull_root` + `model.basis =
##                     zero_pose_basis(id)` + `model.scale = HULL_REF_LENGTH/span`，
##                     再叠 `sync_from_body` 的静止姿态（无速度、有 aim_dir ⇒
##                     `quaternion = looking_at(aim, UP) · C`）。
##
##   ⚠️ 若两屏**一模一样** ⇒ 参照系没漂，问题在别处（表值 / 用户判读）。
##      若两屏**不一样** ⇒ 当场坐实"参照系不一致"，且差异就是病根所在。
##
## ── 视角（三组都给，非 headless 出图）─────────────────────────────
##   每组 6 视角：主 / 后 / 左 / 右 / 俯 / 底（与工具里的六视图同名同向）
##   相机在世界轴上绕目标转，**不带任何船的朝向** ⇒ 纯客观。
##   红球 = 世界 −Z（敌向）· 蓝球 = 世界 +Y（天）· 绿球 = 世界 +X
##
## 跑法（**非 headless**，要出图）：
##   "C:/godot/Godot_v4.7.1-stable_win64.exe" --path "F:/evezzq/eve自走棋918" \
##      res://tools/probe_cmp51.tscn -- --ids=algos,catalyst,kestrel
##   不给 --ids = 全库 52 艘。
##
## 输出：`user://cmp51/<id>_L.<view>.png` / `<id>_R.<view>.png` / `<id>_CMP.png`

const YAW := preload("res://scripts/data/eve_ship_yaw.gd")
const VISUAL := preload("res://scripts/visual/eve_ship_visual.gd")
const MODEL := preload("res://scripts/visual/eve_ship_model.gd")
const ASSET := preload("res://scripts/data/eve_ship_asset_index.gd")

## 与 `eve_ship_visual.HULL_REF_LENGTH` 同值（实机里船体归一化到的世界长度）。
const HULL_REF_LENGTH := 2.6

## 相机绕目标的距离（世界单位；船已被归一到 2.6）。
const CAM_DIST := 5.2

## 六个客观视角：名字 → (相机所在方向, up 参考)
##   ⚠️ 与工具六视图**同名同向**，方便逐格对照。
const VIEWS := {
	"主视图": [Vector3(0, 0, 1), Vector3(0, 1, 0)],
	"后视图": [Vector3(0, 0, -1), Vector3(0, 1, 0)],
	"左视图": [Vector3(-1, 0, 0), Vector3(0, 1, 0)],
	"右视图": [Vector3(1, 0, 0), Vector3(0, 1, 0)],
	"俯视图": [Vector3(0, 1, 0), Vector3(0, 0, -1)],
	"底视图": [Vector3(0, -1, 0), Vector3(0, 0, 1)],
}

var _ids: PackedStringArray = PackedStringArray()
var _slot_l: Node3D = null   ## 左：工具视角
var _slot_r: Node3D = null   ## 右：实机视角
var _cur_label := ""

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute("user://cmp51")
	_ids = _parse_ids()
	print("[51 轮·对照台] 共 %d 艘：%s" % [_ids.size(), ", ".join(_ids)])

	_env_setup()
	_slot_l = Node3D.new()
	_slot_l.name = "SlotTool"
	add_child(_slot_l)
	_slot_r = Node3D.new()
	_slot_r.name = "SlotReal"
	_slot_r.position = Vector3(CAM_DIST * 3.0, 0, 0)   # 两个并排放，便于一屏同拍
	add_child(_slot_r)

	await _shoot_each()
	get_tree().quit(0)


func _parse_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--ids="):
			for s in a.substr(6).split(",", false):
				out.append(s.strip_edges())
	if out.is_empty():
		for s in ASSET.all():
			out.append(String(s.id))
	return out


## 天空盒 + 环境光 —— 与实机场景同源（红线 40：观感口径别自己对）。
func _env_setup() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var mat := ProceduralSkyMaterial.new()
	sky.sky_material = mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 1.0
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	we.environment = env
	add_child(we)

	# 世界锚球：红 = −Z（敌向）· 蓝 = +Y（天）· 绿 = +X
	_world_ball(Vector3(0, 0, -1) * (CAM_DIST * 1.15), Color(1, 0.15, 0.15), "TO_ENEMY(-Z)")
	_world_ball(Vector3(0, 1, 0) * (CAM_DIST * 1.15), Color(0.25, 0.55, 1), "UP(+Y)")
	_world_ball(Vector3(1, 0, 0) * (CAM_DIST * 1.15), Color(0.3, 1, 0.35), "+X")


func _world_ball(pos: Vector3, col: Color, txt: String) -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.10
	sm.height = 0.20
	mi.mesh = sm
	mi.position = pos
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = 2.0
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = m
	add_child(mi)
	var lb := Label3D.new()
	lb.text = txt
	lb.position = pos
	lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lb.no_depth_test = true
	lb.font_size = 48
	lb.pixel_size = 0.002
	lb.modulate = col
	add_child(lb)


## ══ 摆船：左（工具视角） ═════════════════════════════════════════════
## 与 `probe_bow_box._load_current()` **同一个式子**：
##     holder.basis = R_ship · zero_pose_basis(id) · scale
## 用户不按 Shift 时 `R_ship = I` ⇒ 工具里的船姿 = `zero_pose_basis(id)`。
func _build_tool_side(id: StringName) -> void:
	_clear(_slot_l)
	var model := MODEL.instantiate(id)
	if model == null:
		return
	var aabb := _aabb_of(model)
	if aabb.size.length() < 1e-4:
		model.queue_free()
		return
	var long_len := maxf(aabb.size.x, maxf(aabb.size.y, maxf(aabb.size.z, 1e-4)))
	var sc := 1.0 / long_len
	_slot_l.add_child(model)
	# ⚠️ 与工具同序：先 basis（含 zp）再 scale；origin 是 AABB 居中
	model.basis = VISUAL.zero_pose_basis(id) * Basis.IDENTITY.scaled(Vector3.ONE * sc)
	model.position = -(sc * aabb.get_center())
	model.name = "TOOL_%s" % String(id)


## ══ 摆船：右（实机视角） ═════════════════════════════════════════════
## 严格照 `eve_ship_visual._build_hull_model()` 的挂载链：
##   hull_root (Identity)
##     └─ model  [basis = zero_pose_basis(id), scale = HULL_REF_LENGTH/span_m]
## 再叠静止姿态（有目标、无速度）：节点 quaternion = looking_at(aim,UP) · C
##   ⚠️ 这里 aim 取「朝敌」= 世界 −Z —— 与实机战斗里舰艏朝敌一致（红线 42）。
func _build_real_side(id: StringName) -> void:
	_clear(_slot_r)
	var model := MODEL.instantiate(id)
	if model == null:
		return
	var span_m := MODEL.max_dim_m(id)
	if span_m <= 0.001:
		model.queue_free()
		return
	var s := HULL_REF_LENGTH / span_m
	model.basis = VISUAL.zero_pose_basis(id)
	model.scale = Vector3.ONE * s
	model.name = "REAL_%s" % String(id)

	# 静止姿态：把 C 烘进 hull_root（= 实机里 ship 节点那一层）
	#   C 必须用 no_roll 烘焙（红线 48b 的契约），与生产同源
	var geo := VISUAL.zero_pose_basis_no_roll(id).orthonormalized()
	var bow_l := YAW.bow_axis(id)
	var up_l := YAW.up_axis(id)
	var c := _make_align(geo * bow_l, geo * up_l)
	var aim := Vector3(0, 0, -1)   # 朝敌（红线 42）
	var node_q := Basis.looking_at(aim, Vector3.UP) * c

	var hull_root := Node3D.new()
	hull_root.name = "hull_root"
	hull_root.basis = node_q.orthonormalized()
	hull_root.add_child(model)
	_slot_r.add_child(hull_root)


## 复刻 `eve_ship_visual._make_align` 的**契约**（三轴 → −Z/+Y/+X）。
## ⚠️ 生产里那个是私有方法；这里按它在生产注释里写明的契约复建。
##    契约：返回 R 使 `R·bow_local = −Z`、`R·up_local = +Y`。
##    做法：先构造「把 (bow,up,side) 送到 (−Z,+Y,+X)」的正交基。
func _make_align(bow: Vector3, up: Vector3) -> Basis:
	var b := bow.normalized()
	var u := up.normalized()
	# 正交化 up（去 bow 分量）
	u = (u - b * u.dot(b)).normalized()
	var sd := b.cross(u).normalized()
	# 源基的列 = (bow, up, side) → 目标基的列 = (−Z, +Y, +X)
	var from := Basis(b, u, sd)
	# ⚠️ Basis 构造是**列**语义；转置得到"行 = 三个轴"再取逆
	#    ⇒ `R = T · from⁻¹` 其中 T 把 (bow,up,side) 映到 (−Z,+Y,+X)
	var t := Basis(Vector3(0, 0, -1), Vector3(0, 1, 0), Vector3(1, 0, 0))
	# from 的列是 bow/up/side ⇒ from⁻¹ 把 bow→(1,0,0) 等
	# t 的列是 −Z/+Y/+X ⇒ t·(1,0,0) = −Z ✔
	return (t * from.inverse()).orthonormalized()


func _aabb_of(n: Node) -> AABB:
	var out := AABB()
	var first := true
	for m in _meshes(n):
		var mi: MeshInstance3D = m
		var a: AABB = mi.get_aabb()
		# 用 mesh 自身节点的父链变换（这里只取 mesh 局部，够用：归一化只用尺寸）
		if first:
			out = a
			first = false
		else:
			out = out.merge(a)
	if first:
		return AABB(Vector3.ZERO, Vector3.ZERO)
	return out


func _meshes(n: Node) -> Array:
	var out: Array = []
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(_meshes(c))
	return out


func _clear(root: Node3D) -> void:
	for c in root.get_children():
		root.remove_child(c)
		c.queue_free()


## ══ 出图 ═════════════════════════════════════════════════════════════
func _shoot_each() -> void:
	var cam := Camera3D.new()
	cam.fov = 45.0
	add_child(cam)
	cam.current = true

	for id in _ids:
		var sid := StringName(id)
		await _wait(3)
		_build_tool_side(sid)
		_build_real_side(sid)
		await _wait(5)

		# 逐视角拍两屏（先拍右侧实机，再拍左侧工具，避免互相遮挡）
		#   ⚠️ 两个 slot 相距 3·CAM_DIST ⇒ 逐屏单独对焦（各自居中），
		#      出图后由外部脚本并排拼。这里直接出**同框双船**图，最省事且无拼接误差。
		for vn in VIEWS.keys():
			var d: Vector3 = VIEWS[vn][0]
			var up: Vector3 = VIEWS[vn][1]
			# 同一机位同时框住两艘（中心在两 slot 中间）
			var mid := Vector3(CAM_DIST * 1.5, 0, 0)
			cam.global_position = mid + d.normalized() * (CAM_DIST * 3.6)
			cam.look_at(mid, up)
			# 上方标注：左 = 工具视角、右 = 实机视角
			await _wait(2)
			var img := get_viewport().get_texture().get_image()
			img.save_png("user://cmp51/%s_%s.png" % [String(sid), vn])
			print("   · %s / %s" % [String(sid), vn])
		cam.queue_free()
		await _wait(1)
		cam = Camera3D.new()
		cam.fov = 45.0
		add_child(cam)
		cam.current = true

	cam.queue_free()
	print("[51 轮·对照台] 出图完毕 → user://cmp51")


func _wait(n: int) -> void:
	for _i in n:
		await get_tree().process_frame
