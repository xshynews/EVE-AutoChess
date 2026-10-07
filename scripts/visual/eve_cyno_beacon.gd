extends Node3D
class_name EveCynoBeacon

## 移动式诱导信标（Mobile Cynosural Beacon）
##
## 资产与实测数据全部来自 EVE 客户端取出的模型 `pcd01_t1.gr2`
## （graphicID 24934，见 `C:\godot\_export\_cyno_deploy\移动式诱导信标_资源清单.md`）。
##
## ──★ 两条必须记住的（都吃过亏）─────────────────────────
## 1. **模型空间 +Y 朝下** ⇒ 塔身用 R_x(180°) 立正。
##    ⚠️ 不翻正的后果**不是"转 180°"那么明显** —— 叶片看着会"朝上翘"，
##    很容易误判成"叶形算错了"然后跑去改叶形。**先判轴向，再判形状。**
## 2. **展开的四片叶不是实体几何**，是"全息件"，原始数据在 `effects/` 的
##    **发射点集**里（`pcd01_mesh_03c`，去重后每簇只有 6 个点）。
##    ⛔ 别拿 `pcd01_mesh_03b`（角点集）当外形 —— 那会做成 46×38 m 的"大帆"，
##       比真叶宽 3.4 倍（离线渲染与官方图标并排一比就知道是假的）。
##
## ── 实测的塔身剖面（**模型空间**，已按 R_x(180) 换算成"立正后"的 Y）──
##   y +40..+52   半径  8.5→10.0   ← **塔尖**（最细，在上）
##   y  +8..+40   半径 14.6→23.6   ← 上半身；**最宽处 r 23.6 在 y +8..+16**
##   y  −8..+8    半径 ~19.0
##   y −24..−8    半径  4.8        ← **细腰**（塔身在这里收成一根 3.7 半径的柱）
##   y −52..−24   半径 14.3→20.3   ← **下半身**（最下的头）
## 叶片铰链挂在最宽处（r 28.4 / y +14.3），向外**下**张开到 r 70.8 / y −5.9。
##
## 全部尺寸单位 = 米。塔身高 103 m，展开后叶尖半径 70.8 m。

const MESH_PATH := "res://assets/beacon/cyno_beacon.obj"

# ── 实测常数（改这里 = 改信标外形；别在函数里写魔法数）──────
const ROOT_R := 28.4          ## 叶根径向距离
const ROOT_Y := 14.2          ## 叶根高度（立正后）
const ROOT_W := 11.07         ## 叶根切向宽度
const TIP_R := 70.8           ## 叶尖径向距离
const TIP_Y := -5.8           ## 叶尖高度（立正后）
const TIP_W := 4.68           ## 叶尖切向宽度
const LEAF_ELEV := -25.3      ## 展开后叶片仰角（向外**下**）
const FOLD_ANGLE := -64.7     ## 收起：绕铰链轴转过这么多 ⇒ 叶片竖直朝下贴塔身
const FOLD_SLIDE := 7.0       ## 收起：径向内滑（贴紧塔身）

const RING_OUT_R := 4.35      ## 环外半径（实测整体 8.7 × 11.0 × 8.7）
const RING_TUBE := 0.26
const RING_COUNT := 3
const RING_SPAN := 11.0
const RING_Y := -41.5         ## 环的中心高度（实测在塔的**下端**）

## 顶端等离子柱 —— ⛔ 这一根**不在几何里**（模型没有），官方图标里它是特效。
## 位置取塔尖之上：塔尖 y +52.6，柱从 +48 起往上。
const BEAM_R := 3.2
const BEAM_H := 34.0
const BEAM_BOTTOM := 48.0

var _leaves: Array[Node3D] = []
var _leaf_meshes: Array[MeshInstance3D] = []
var _rings: Array[MeshInstance3D] = []
var _beam: MeshInstance3D
var _progress := 0.0
var _tw: Tween = null

var _mat_leaf: StandardMaterial3D
var _mat_ring: StandardMaterial3D
var _mat_beam: StandardMaterial3D


func _ready() -> void:
	name = "CynoBeacon"
	_build_materials()
	_build_body()
	_build_leaves()
	_build_rings()
	_build_beam()
	_build_env()
	set_progress(0.0)


# ── 材质 ─────────────────────────────────────────────────
## ⚠️ 索引里**没有** diffuse / 法线贴图 ⇒ 不能照搬舰船那套 PBR，否则渲成一坨灰壳、
##    完全没有"信标在发光"的感觉。塔身压成深色剪影（官方图标里它就是深色的），
##    亮度交给叶 / 环 / 柱 + 环境辉光。
func _build_materials() -> void:
	_mat_leaf = StandardMaterial3D.new()
	_mat_leaf.albedo_color = Color(0.30, 0.62, 1.00, 0.62)
	_mat_leaf.emission_enabled = true
	_mat_leaf.emission = Color(0.22, 0.52, 0.98)
	_mat_leaf.emission_energy_multiplier = 2.6
	_mat_leaf.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat_leaf.cull_mode = BaseMaterial3D.CULL_DISABLED      # 薄片两面都要看得见
	_mat_leaf.roughness = 0.35

	_mat_ring = StandardMaterial3D.new()
	_mat_ring.albedo_color = Color(0.45, 0.80, 1.00, 0.85)
	_mat_ring.emission_enabled = true
	_mat_ring.emission = Color(0.32, 0.70, 1.00)
	_mat_ring.emission_energy_multiplier = 2.2

	_mat_beam = StandardMaterial3D.new()
	_mat_beam.albedo_color = Color(0.62, 0.83, 1.00, 0.42)
	_mat_beam.emission_enabled = true
	_mat_beam.emission = Color(0.42, 0.72, 1.00)
	_mat_beam.emission_energy_multiplier = 2.0
	_mat_beam.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat_beam.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat_beam.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED


# ── 塔身 ─────────────────────────────────────────────────
func _build_body() -> void:
	var mesh: Mesh = load(MESH_PATH) as Mesh
	if mesh == null:
		push_warning("[信标] 载不到 %s —— 塔身会缺席（叶/环/柱仍在）" % MESH_PATH)
		return
	var mi := MeshInstance3D.new()
	mi.name = "Body"
	mi.mesh = mesh
	mi.rotation_degrees = Vector3(180.0, 0.0, 0.0)   # ★ 立正：模型 +Y 朝下
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.30, 0.34, 0.38)
	m.metallic = 0.65
	m.roughness = 0.45
	mi.material_override = m
	add_child(mi)


# ── 四片叶 ───────────────────────────────────────────────
## 铰链 = 叶根的**切向轴**（水平、垂直于半径）⇒ 单自由度：叶片只在
## 「半径 × 竖直」平面内摆动，一个角度就够，不需要复合旋转。
func _build_leaves() -> void:
	var mesh := _leaf_mesh()
	for i in range(4):
		var az := float(i) * 90.0
		var hinge := Node3D.new()
		hinge.name = "Leaf_%d" % i
		add_child(hinge)
		var mi := MeshInstance3D.new()
		mi.name = "Blade"
		mi.mesh = mesh
		mi.material_override = _mat_leaf
		hinge.add_child(mi)
		_leaves.append(hinge)
		_leaf_meshes.append(mi)


## 叶片网格（局部：铰链在原点，+X 向外、+Y 上、+Z 切向）
## 梯形：根宽 ROOT_W（x=0）→ 梢宽 TIP_W（x=42.4, y=−20.0），叶面朝上（法向 +Y）
func _leaf_mesh() -> ArrayMesh:
	var dx := TIP_R - ROOT_R          # 42.4
	var dy := TIP_Y - ROOT_Y          # −20.0
	var h0 := ROOT_W * 0.5
	var h1 := TIP_W * 0.5
	var v := PackedVector3Array([
		Vector3(0.0, 0.0, -h0), Vector3(dx, dy, -h1), Vector3(dx, dy, h1),
		Vector3(0.0, 0.0, -h0), Vector3(dx, dy, h1), Vector3(0.0, 0.0, h0),
	])
	var n := (v[1] - v[0]).cross(v[2] - v[0]).normalized()
	var nrm := PackedVector3Array()
	for i in range(v.size()):
		nrm.append(n)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = nrm
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return am


func _build_rings() -> void:
	for i in range(RING_COUNT):
		var t := float(i) / float(maxi(RING_COUNT - 1, 1))
		var tm := TorusMesh.new()
		tm.inner_radius = RING_OUT_R - RING_TUBE
		tm.outer_radius = RING_OUT_R
		tm.rings = 40
		tm.ring_segments = 8
		var mi := MeshInstance3D.new()
		mi.name = "Ring_%d" % i
		mi.mesh = tm
		mi.material_override = _mat_ring
		mi.position = Vector3(0, RING_Y + (t - 0.5) * RING_SPAN, 0)
		mi.rotation_degrees = Vector3(0, t * 60.0, 0)
		add_child(mi)
		_rings.append(mi)


func _build_beam() -> void:
	var cm := CylinderMesh.new()
	cm.top_radius = 0.55
	cm.bottom_radius = BEAM_R
	cm.height = BEAM_H
	cm.radial_segments = 24
	cm.cap_top = false
	cm.cap_bottom = false
	_beam = MeshInstance3D.new()
	_beam.name = "Beam"
	_beam.mesh = cm
	_beam.material_override = _mat_beam
	_beam.position = Vector3(0, BEAM_BOTTOM + BEAM_H * 0.5, 0)
	add_child(_beam)


# ── 环境（自发光要有辉光才像"信标在发光"）────────────────
func _build_env() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.008, 0.014, 0.024)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.20, 0.28, 0.38)
	env.ambient_light_energy = 0.55
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_bloom = 0.12
	env.glow_hdr_threshold = 0.85
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	var we := WorldEnvironment.new()
	we.name = "Env"
	we.environment = env
	add_child(we)

	var key := DirectionalLight3D.new()
	key.name = "Key"
	key.rotation_degrees = Vector3(-32.0, 38.0, 0.0)
	key.light_energy = 0.9
	key.light_color = Color(0.86, 0.91, 1.0)
	add_child(key)

	var rim := DirectionalLight3D.new()
	rim.name = "Rim"
	rim.rotation_degrees = Vector3(12.0, -140.0, 0.0)
	rim.light_energy = 0.55
	rim.light_color = Color(0.55, 0.72, 1.0)
	add_child(rim)


# ── 展开动画 ─────────────────────────────────────────────

## 铰链位姿：**先**在局部绕 Z（切向轴）摆叶，**再**整体绕 Y 转到方位。
## `basis = R_y(az) · R_z(phi)`；Godot 的 `Transform3D.rotated()` 是在**父空间**
## 转的，直接连着调两次顺序会反 ⇒ 显式相乘。
func _hinge_transform(az_deg: float, fold01: float) -> Transform3D:
	var az := deg_to_rad(az_deg)
	var phi := deg_to_rad(FOLD_ANGLE) * fold01
	var b := Basis(Vector3.UP, az) * Basis(Vector3.BACK, phi)
	var r := ROOT_R - FOLD_SLIDE * fold01              # 收起时贴向塔身
	var dir := Vector3(sin(az), 0.0, cos(az))
	return Transform3D(b, dir * r + Vector3(0, ROOT_Y, 0))


## 0 = 完全收起（叶片竖直朝下贴塔身、环缩、柱熄灭）
## 1 = 完全展开（叶片 −25.3°、环张开、柱点燃）
## 三段时序（与离线动画对齐）：0~0.72 展叶 · 0.25~0.85 环 · 0.45~1.0 柱
func set_progress(p: float) -> void:
	_progress = clampf(p, 0.0, 1.0)
	var p_leaf := _seg(_progress, 0.00, 0.72)
	var p_ring := _seg(_progress, 0.25, 0.85)
	var p_beam := _seg(_progress, 0.45, 1.00)

	for i in range(_leaves.size()):
		_leaves[i].transform = _hinge_transform(float(i) * 90.0, 1.0 - p_leaf)

	var rs := lerpf(0.35, 1.0, p_ring)
	var ry := lerpf(0.6, 1.0, p_ring)
	for mi in _rings:
		mi.scale = Vector3(rs, ry, rs)

	_beam.visible = p_beam > 0.001
	_beam.scale = Vector3(lerpf(0.30, 1.0, p_beam), maxf(p_beam, 0.001), lerpf(0.30, 1.0, p_beam))
	_beam.position = Vector3(0, BEAM_BOTTOM + BEAM_H * 0.5 * p_beam, 0)


func _seg(x: float, a: float, b: float) -> float:
	if b <= a:
		return 1.0
	return clampf((x - a) / (b - a), 0.0, 1.0)


## 播放展开动画。`TRANS_BACK / EASE_OUT` = 带过冲（收尾"咔"一下，与离线预览一致）。
func unfold(duration: float = 1.6) -> void:
	stop_unfold()
	set_progress(0.0)
	_tw = create_tween()
	_tw.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tw.tween_method(set_progress, 0.0, 1.0, duration)


## ★ 取消正在跑的展开动画。
## ⛔ 不取消的后果很隐蔽：Tween 每帧都会写 `set_progress`，
##    外面就算手动把进度拨回 0（或拨到 1），下一帧就被动画覆盖回去 ——
##    表现出来是「按了上一步，信标还是自己在那展开」。
##    （自检里就是这么抓到的：seek 回 22s 后进度仍是 0.585。）
func stop_unfold() -> void:
	if _tw != null and _tw.is_valid():
		_tw.kill()
	_tw = null


func is_unfolded() -> bool:
	return _progress >= 0.999


func progress() -> float:
	return _progress


## 叶片自身的方向（单位向量，**局部**坐标：+X 向外、+Y 上）
## 仰角 = atan2(−20, 42.4) = **−25.25°**，这就是「向外下张开」那个角。
const LEAF_DIR_LOCAL := Vector3(0.90427, -0.42663, 0.0)

## 单片叶的真实仰角（度）。
## ⛔ 别拿铰链 basis 的 X 轴当仰角 —— 那只是**枢轴转角**（展开 0° / 收起 −64.7°），
##    真正决定"叶片朝哪"的是网格自身从根到梢的方向，两者差 25.3°。
func hinge_elevations() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for h in _leaves:
		var d: Vector3 = (h.transform.basis * LEAF_DIR_LOCAL).normalized()
		out.append(rad_to_deg(atan2(d.y, Vector2(d.x, d.z).length())))
	return out
