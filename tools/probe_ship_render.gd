extends Node3D

## 立绘「统一机位」自渲染可行性验证台（非 headless）
##
## ══════════════════════════════════════════════════════════════════
##  它要回答的问题
## ══════════════════════════════════════════════════════════════════
##  用户要「备战席的船用 2D 立绘」，但实测官方 render 图**不能直接用**：
##  它的机位是固定的，而 52 艘船的**模型自身朝向各不相同**，
##  于是输出视角有的正视、有的侧视（实测横构图 bbox ≈439×294、
##  竖构图 ≈336×439，各占一半）。旋转一张「正视」位图 90° 变不成「侧视」
##  —— 这是**位图无法修复**的，只能重新渲染。
##
##  好消息：工程里已经有 52 个可用的 3D 模型（assets/ships3d/<id>.glb）。
##  只要**先把模型的长轴转到统一方向、再从一个固定机位拍**，
##  出来的 52 张立绘就天然朝向一致、构图一致。
##
## ── 关键设计 ────────────────────────────────────────────────────
##  · **正交相机**（不是透视）：构图完全可控，不会「近船大远船小」。
##  · **XZ 平面 PCA 主方向对齐**（不是 AABB 长轴！）：
##    ⚠️ 这是踩过坑才改的。第一版按「AABB 最大维」对齐，结果一批船仍是斜的 ——
##       因为很多船在水平面里是**斜放**的，AABB 被撑成近正方形，
##       「哪一维最大」变成随机判定。实测：condor 76×28×76、raven 778×222×746、
##       condor 的 x 与 z 几乎相等 ⇒ 45° 斜放 ⇒ 长轴判定无意义。
##       PCA（对顶点做协方差、取主特征向量）直接给出**真实主方向**，
##       对斜放船也成立。
##  · **长轴归一化**：缩放到长轴 = 1.0 世界单位，相机 size 设 1.30 ⇒
##    每艘船占同样的画面宽度，大小不一致的问题也消失。
##  · **独立 World3D**（own_world_3d）：不受主场景光照/天空盒干扰，
##    保证 52 张是在同一套光照下拍的。
##
## ⚠️ 本轮**不做船头/船尾判定**：主方向对齐只保证「横着」，
##    不保证「头都朝右」。剩下的 180° 分歧要靠人眼标定
##    （见 tools/probe_ship_art.tscn 的网格图，报序号即可）。
##
## ── 跑法（⚠️ 不要加 --headless，headless 下取不到 SubViewport 纹理）──
##   "C:/godot/Godot_v4.7.1-stable_win64_console.exe" \
##     --path "F:/evezzq/eve自走棋918" --quit-after 900 \
##     res://tools/probe_ship_render.tscn

const INDEX_SCRIPT := preload("res://scripts/data/eve_ship_asset_index.gd")

const SIZE := 220
const COLS := 8
const ROWS := 7
const OUT_SHEET := "user://ship_render_sheet.png"

## 正交相机视野宽度（世界单位）。船的长轴被归一化到 1.0，
## 所以 1.30 意味着船占画面宽度的 77%、两侧各留 11.5% 边距。
const CAM_SIZE := 1.30

## 相机方位：从**右前上方**看。长轴沿 +X ⇒ 画面里看到的是「船头朝右的侧视偏前」。
## 数值 = 未归一的方位向量，仰角约 21°、偏航约 31°（对齐官方 render 的观感）。
const CAM_DIR := Vector3(0.48, 0.37, 0.80)

## 顶点降采样步长（PCA 用）。52 艘全量顶点太慢，隔 11 个取一个足够定方向。
const PCA_STEP := 11

var _vp: SubViewport = null
var _cam: Camera3D = null
var _holder: Node3D = null


func _ready() -> void:
	_build_world()
	await _run()


func _build_world() -> void:
	_vp = SubViewport.new()
	_vp.size = Vector2i(SIZE, SIZE)
	_vp.transparent_bg = true
	# 独立世界：52 张必须在同一套光照下拍，不能吃主场景的天空盒/IBL
	_vp.own_world_3d = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp)

	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0, 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.52, 0.59, 0.68)
	env.ambient_light_energy = 1.25
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	we.environment = env
	_vp.add_child(we)

	var key := DirectionalLight3D.new()
	key.light_energy = 1.7
	key.rotation_degrees = Vector3(-34, -142, 0)
	_vp.add_child(key)

	var rim := DirectionalLight3D.new()
	rim.light_energy = 0.65
	rim.rotation_degrees = Vector3(-16, 58, 0)
	_vp.add_child(rim)

	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	# ⚠️ size 对正交相机是【视野高度】（keep_aspect 默认 KEEP_HEIGHT）；
	#    画布是 1:1，所以宽高同为 CAM_SIZE。
	_cam.size = CAM_SIZE
	_cam.near = 0.01
	_cam.far = 40.0
	# ⚠️ 顺序不能颠倒：`look_at` 需要节点**已在场景树里**
	#    （否则报 "Node not inside tree. Use look_at_from_position() instead."
	#     并且**相机没有朝向** —— 渲染出来是一张全白图，不报错也不崩）。
	_vp.add_child(_cam)
	_cam.position = CAM_DIR.normalized() * 8.0
	_cam.look_at(Vector3.ZERO, Vector3.UP)

	_holder = Node3D.new()
	_vp.add_child(_holder)


func _run() -> void:
	var sheet := Image.create(COLS * SIZE, ROWS * SIZE, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.027, 0.039, 0.051, 1.0))

	var ok_n := 0
	var fail: PackedStringArray = []
	for idx in INDEX_SCRIPT.ROWS.size():
		var r = INDEX_SCRIPT.ROWS[idx]
		var id := StringName(r[0])
		var res := await _render_one(id)
		if res.is_empty():
			fail.append("%d %s" % [idx, String(id)])
			continue
		var img: Image = res["img"]
		sheet.blit_rect(img, Rect2i(0, 0, SIZE, SIZE),
				Vector2i((idx % COLS) * SIZE, (idx / COLS) * SIZE))
		ok_n += 1
		print("[RND] %2d %-14s PCA角 %+6.1f°  对齐后 dims %.2f×%.2f×%.2f  格式 %s" % [
			idx, String(id), rad_to_deg(float(res["theta"])),
			res["dims"].x, res["dims"].y, res["dims"].z, res["fmt"]])

	sheet.save_png(OUT_SHEET)
	print("[RND] 图 -> %s" % ProjectSettings.globalize_path(OUT_SHEET))
	print("[RND] 成功 %d / 失败 %d %s" % [
		ok_n, fail.size(), ("（" + ", ".join(fail) + "）") if fail.size() > 0 else ""])
	print("[RND] ==== DONE ====")


## 渲染一艘船：实例化 → PCA 定主方向 → 对齐到 +X → 缩放居中 → 回读像素
##
## 返回 {} 表示失败；否则 {"img", "dims", "theta", "fmt"}
func _render_one(id: StringName) -> Dictionary:
	for c in _holder.get_children():
		_holder.remove_child(c)
		c.queue_free()
	_holder.transform = Transform3D()

	var model := EveShipModel.instantiate(id)
	if model == null:
		push_warning("立绘渲染：%s 无 3D 模型" % String(id))
		return {}
	_holder.add_child(model)

	# ① 主方向（相对 +X 的夹角）
	var theta := _xz_principal_angle(model)
	var rot := Basis.from_euler(Vector3(0.0, theta, 0.0))
	# ② 在【旋转后】的空间里量 AABB
	var aabb := _aabb_of(model, Transform3D(rot, Vector3.ZERO))
	if aabb.size.length() < 0.0001:
		push_warning("立绘渲染：%s 的 AABB 退化" % String(id))
		return {}
	# ③ 长轴应当已是 X（PCA 保证）；若不然，退回到「最大维」兜底
	var long_len := aabb.size.x
	if long_len < maxf(aabb.size.y, aabb.size.z):
		long_len = maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z))
	long_len = maxf(long_len, 0.0001)

	var basis := rot.scaled(Vector3.ONE * (1.0 / long_len))
	var origin := -(basis * aabb.get_center())
	_holder.transform = Transform3D(basis, origin)

	await RenderingServer.frame_post_draw
	var tex := _vp.get_texture()
	if tex == null:
		return {}
	var img := tex.get_image()
	if img == null:
		return {}
	return {
		"img": img, "dims": aabb.size, "theta": theta,
		"fmt": "%s a@角%d" % [str(img.get_format()), int(img.get_pixel(0, 0).a * 255.0)],
	}


## XZ 平面主方向：对顶点做 2D 协方差、取主特征向量的角度
##
## 返回「主方向与 +X 轴的夹角（弧度）」。绕 Y 旋转 +theta 即可把主方向对到 +X：
##   方向向量 (cosθ, sinθ) --绕Y转 a--> (cos(a-θ), sin(θ-a))
##   要它等于 (1,0) ⇒ a = θ
func _xz_principal_angle(root: Node) -> float:
	var pts: PackedVector2Array = []
	_collect_xz(root, Transform3D(), pts)
	if pts.size() < 4:
		return 0.0
	var n := float(pts.size())
	var mean := Vector2.ZERO
	for p in pts:
		mean += p
	mean /= n
	var cxx := 0.0
	var czz := 0.0
	var cxz := 0.0
	for p in pts:
		var d := p - mean
		cxx += d.x * d.x
		czz += d.y * d.y
		cxz += d.x * d.y
	return 0.5 * atan2(2.0 * cxz, cxx - czz)


func _collect_xz(n: Node, xf: Transform3D, out: PackedVector2Array) -> void:
	var here := xf
	if n is Node3D:
		here = xf * (n as Node3D).transform
	if n is MeshInstance3D:
		var mesh: Mesh = (n as MeshInstance3D).mesh
		if mesh != null:
			for si in mesh.get_surface_count():
				var arrays := mesh.surface_get_arrays(si)
				if arrays.size() <= Mesh.ARRAY_VERTEX:
					continue
				var vs: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var i := 0
				while i < vs.size():
					var p := here * vs[i]
					out.append(Vector2(p.x, p.z))
					i += PCA_STEP
	for c in n.get_children():
		_collect_xz(c, here, out)


## 子树的**本地** AABB（从 [param pre] 起算，无视本节点自身的 transform）
##
## ⚠️ `pre` 用来把「旋转后的空间」当作本地空间量 AABB（传 Transform3D(rot, 0)）。
## ⚠️ 必须逐级累乘 transform：glb 里网格常挂在带缩放的中间节点下，
##    只取 `MeshInstance3D.transform` 会漏掉父级缩放，量出来的包围盒偏小。
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
