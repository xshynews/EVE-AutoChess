extends Node3D

## 52 艘 3D 舰船「朝向总览」渲染台（非 headless）
##
## ══════════════════════════════════════════════════════════════════
##  它要回答的问题
## ══════════════════════════════════════════════════════════════════
##  用户：「磨难级的朝向是不对的，那肯定有其他舰船是不对的」。
##
##  probe_ship_yaw_audit 已查清**长轴**那一层（52 艘里只有 3 艘歪：
##  condor / raven / tristan）。但 PCA 主方向是**轴**不是有向向量，
##  它说不出「哪一头是舰艏」—— 那 180° 只能人眼看。
##
## ── 两种渲染口径（由 --align 选）────────────────────────────────
##  ① `--align=z`（默认，= 当前实装口径）
##     把 PCA 主轴转到 +Z（船头朝向约定），相机架在 +X 侧
##     ⇒ **+Z 在画面里恒指向【左侧】**。规则：「每艘船的船头都该朝左」。
##     ⚠️ 这里原本写的是「右侧」——那是**纸面推导，从未实测**，是错的。
##        2026-09-23 由 tools/probe_cam_axis.tscn 实拍定案：红球放 +Z 端，
##        它的屏幕 x̄ 在画布最左（30.7 / 420）。方向标反会直接误导朝向标定。
##  ② `--align=x`（= 官方观感口径，用来和官方立绘并排比对）
##     把 PCA 主轴转到 +X，相机用 CAM_DIR 默认值（当年为对齐官方
##     render 观感调出来的 3/4 斜视）⇒ 出图与 assets/ships/<id>.png
##     的机位接近，**可以直接并排看「船头方向是否一致」**。
##
## ── 关键设计 ────────────────────────────────────────────────────
##  · **正交相机**：构图完全可控，不会「近船大远船小」。
##  · **XZ 平面 PCA 主方向对齐**（不是 AABB 长轴）：
##    ⚠️ 踩过坑。按「AABB 最大维」对齐时，水平面里斜放的船 AABB 被撑成
##       近正方形，「哪一维最大」变成随机判定（实测 condor 76×28×76）。
##  · **长轴归一化**到 1.0 世界单位 + 相机 size 1.30 ⇒ 每艘占同样画幅宽度。
##  · **独立 World3D**：不受主场景光照/天空盒干扰，52 张同一套光照。
##
## ── 跑法（⚠️ 不要加 --headless，headless 下拿不到 SubViewport 纹理）──
##   "C:/godot/Godot_v4.7.1-stable_win64_console.exe" \
##     --path "F:/evezzq/eve自走棋918" --quit-after 4000 \
##     res://tools/probe_ship_yaw_sheet.tscn
##
##   可选参数（写在 `--` 之后）：
##     --dir=yaw_pair          输出目录名（默认 yaw_sheet）
##     --size=260              单图边长（默认 220）
##     --cam=0.48,0.37,0.80    相机方位
##     --align=x|z             主轴对齐口径（默认 z）
##     --ids=rifter,raven      只渲这几艘
##     --both                  同时输出 +180° 版（文件名后缀 _a / _b）
##     --apply=table           **按工程实际算式**渲（MODEL_YAW_FIX + EveShipYawTable），
##                             用来取证「eve_ship_visual 的逐艘修正确实生效」——
##                             此口径下 52 艘除 PENDING 那 7 艘外都应朝【左】。
##                             （此时 --align / --both 自动失效：表里已含这两层语义）
##
## 输出：`user://<dir>/<序号>_<id>.png` + `user://<dir>/map.txt`

const INDEX := preload("res://scripts/data/eve_ship_asset_index.gd")

const SIZE := 220
const OUT_DIR := "user://yaw_sheet"

## 相机方位（未归一化）。默认在 +X 侧 ⇒ 画面里 +Z（船头）指向【左侧】
## （实拍确认，见 probe_cam_axis；别凭直觉改回「右侧」）。
const CAM_DIR := Vector3(1.0, 0.78, 0.22)

## 官方观感机位：当年为对齐 `assets/ships/*.png` 的视角调出来的值。
const CAM_DIR_OFFICIAL := Vector3(0.48, 0.37, 0.80)

## 正交相机视野宽度（世界单位）。船的长轴归一化到 1.0，
## 所以 1.30 意味着船占画面宽度的 77%、两侧各留 11.5% 边距。
const CAM_SIZE := 1.30

## 顶点降采样步长（PCA 用）。
const PCA_STEP := 11

## 工程当前的模型朝向修正（eve_ship_visual.gd 的 MODEL_YAW_FIX）。
const MODEL_YAW_FIX := -PI / 2.0

var _size := SIZE
var _out_dir := OUT_DIR
var _cam_dir := CAM_DIR
var _align := "z"
var _apply := ""
var _both := false
var _ids: PackedStringArray = PackedStringArray()

var _vp: SubViewport = null
var _cam: Camera3D = null
var _holder: Node3D = null


func _ready() -> void:
	_parse_args()
	_build_world()
	await _run()


func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--size="):
			_size = maxi(64, int(a.substr(7)))
		elif a.begins_with("--dir="):
			_out_dir = "user://" + a.substr(6)
		elif a.begins_with("--cam="):
			var p: PackedStringArray = a.substr(6).split(",")
			if p.size() == 3:
				_cam_dir = Vector3(float(p[0]), float(p[1]), float(p[2]))
		elif a.begins_with("--align="):
			_align = a.substr(8)
		elif a.begins_with("--ids="):
			_ids = a.substr(6).split(",")
		elif a.begins_with("--apply="):
			_apply = a.substr(8)
		elif a == "--both":
			_both = true


func _build_world() -> void:
	_vp = SubViewport.new()
	_vp.size = Vector2i(_size, _size)
	_vp.transparent_bg = true
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

	# 主光从右上后方来 —— 让「船头（+Z，画面右）」是受光侧，轮廓更清楚。
	var key := DirectionalLight3D.new()
	key.light_energy = 1.7
	key.rotation_degrees = Vector3(-34, -128, 0)
	_vp.add_child(key)

	var rim := DirectionalLight3D.new()
	rim.light_energy = 0.65
	rim.rotation_degrees = Vector3(-16, 62, 0)
	_vp.add_child(rim)

	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.size = CAM_SIZE
	_cam.near = 0.01
	_cam.far = 40.0
	# ⚠️ 顺序不能颠倒：look_at 需要节点已在场景树里。
	#    否则相机没有朝向 —— 渲染出来是一张全白图，不报错也不崩。
	_vp.add_child(_cam)
	_cam.position = _cam_dir.normalized() * 8.0
	_cam.look_at(Vector3.ZERO, Vector3.UP)

	_holder = Node3D.new()
	_vp.add_child(_holder)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out_dir))

	var rows: Array = []
	for r in INDEX.ROWS:
		if _ids.size() > 0 and not _ids.has(String(r[0])):
			continue
		rows.append(r)
	rows.sort_custom(func(a, b): return String(a[0]) < String(b[0]))

	var lines: PackedStringArray = PackedStringArray()
	lines.append("idx\tid\tcn\tcost\ttheta_deg\tyaw_deg")
	var ok_n := 0
	var fail: PackedStringArray = PackedStringArray()
	print("[SHEET] align=%s  cam=%s  size=%d  out=%s  条数=%d" % [
		_align, str(_cam_dir), _size, _out_dir, rows.size()])

	for idx in rows.size():
		var r: Array = rows[idx]
		var id := StringName(r[0])
		var res := await _render_one(id, false)
		if res.is_empty():
			fail.append("%d %s" % [idx, String(id)])
			continue
		var img: Image = res["img"]
		var suffix := "_a" if _both else ""
		img.save_png("%s/%02d_%s%s.png" % [_out_dir, idx, String(id), suffix])
		if _both:
			var res2 := await _render_one(id, true)
			if not res2.is_empty():
				var img2: Image = res2["img"]
				img2.save_png("%s/%02d_%s_b.png" % [_out_dir, idx, String(id)])
		lines.append("%d\t%s\t%s\t%d\t%+.2f\t%+.2f" % [
			idx, String(id), String(r[3]), int(r[4]),
			rad_to_deg(float(res["theta"])), rad_to_deg(float(res["yaw"]))])
		ok_n += 1
		print("[SHEET] %2d %-14s %-8s θ=%+6.1f°  yaw=%+7.1f°  dims %.2f×%.2f×%.2f" % [
			idx, String(id), String(r[3]),
			rad_to_deg(float(res["theta"])), rad_to_deg(float(res["yaw"])),
			res["dims"].x, res["dims"].y, res["dims"].z])

	var f := FileAccess.open("%s/map.txt" % _out_dir, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(lines))
		f.close()

	print("[SHEET] 成功 %d / 失败 %d %s" % [
		ok_n, fail.size(), ("（" + ", ".join(fail) + "）") if fail.size() > 0 else ""])
	print("[SHEET] 输出目录 -> %s" % ProjectSettings.globalize_path(_out_dir))
	print("[SHEET] ==== DONE ====")
	get_tree().quit(0)


## 渲染一艘船：实例化 → PCA 定主方向 → 转到目标轴 → 归一化居中 → 回读像素
##
## [param flip] 为 true 时额外转 180°（用来出「另一头当船头」的对照版）。
func _render_one(id: StringName, flip: bool) -> Dictionary:
	for c in _holder.get_children():
		_holder.remove_child(c)
		c.queue_free()
	_holder.transform = Transform3D()

	var model := EveShipModel.instantiate(id, false)
	if model == null:
		push_warning("朝向总览：%s 无 3D 模型" % String(id))
		return {}
	_holder.add_child(model)

	# ① 主方向（相对 +X 的夹角）→ 按口径转到 +Z 或留在 +X
	var theta := _xz_principal_angle(model)
	var yaw := 0.0
	var rot: Basis
	if _apply == "table":
		# ── 「按工程实际算式」口径 ──
		# 完全照抄 eve_ship_visual._build_hull_model() 的朝向算式，
		# 所以这张图就是**工程此刻在游戏里会画成什么样**的取证。
		# ⚠️ 不再叠加 probe 自算的 theta —— 表里的 AXIS_DEG 就是实测 theta
		#    （叠加会变成 2× 补偿，船又斜回去）。
		# ⚠️ AXIS_REMAP 必须一并乘上：最终朝向 = R_y(yaw) ∘ M。
		#    漏了 M 的话，7 艘重映射船在这张图里呈现的是「没修过」的姿态
		#    （它们要么躺着要么侧着），而表其实已经生效 —— 纯取证假阴性。
		#    （下方打印的 θ 仍是 probe 对**原始模型**算的 PCA，只作参考；
		#      对重映射船它已无意义 —— 那不是表里登记的口径。）
		yaw = MODEL_YAW_FIX + EveShipYawTable.extra_yaw(id)
		rot = Basis.from_euler(Vector3(0.0, yaw, 0.0)) * EveShipYawTable.axis_remap(id)
	else:
		var base := theta if _align == "x" else theta + MODEL_YAW_FIX
		rot = Basis.from_euler(Vector3(0.0, base + (PI if flip else 0.0), 0.0))
	# ② 在【旋转后】的空间里量 AABB
	var aabb := _aabb_of(model, Transform3D(rot, Vector3.ZERO))
	if aabb.size.length() < 0.0001:
		push_warning("朝向总览：%s 的 AABB 退化" % String(id))
		return {}
	# ③ 主方向已对齐到目标轴 ⇒ 该轴就是主轴长度
	var long_len := aabb.size.z if _align == "z" else aabb.size.x
	if long_len < maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z)):
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
	return {"img": img, "dims": aabb.size, "theta": theta, "yaw": yaw}


## XZ 平面主方向：对顶点做 2D 协方差、取主特征向量的角度
##
## 返回「主方向与 +X 轴的夹角（弧度）」。绕 Y 旋转 +theta 即可把主方向对到 +X：
##   方向向量 (cosθ, sinθ) --绕Y转 a--> (cos(θ−a), sin(θ−a))
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


## 子树 AABB（从 [param pre] 起算，无视本节点自身的 transform）
##
## ⚠️ 必须逐级累乘 transform：glb 里网格常挂在带缩放的中间节点下，
##    只取 MeshInstance3D.transform 会漏掉父级缩放，量出来的包围盒偏小。
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
