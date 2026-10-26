extends Node

## ★ 2026-10-25 · **相机取景量测**（用户：「默认摄影机距离舰船太远，舰船显得太小」）
##
## ══════════════════════════════════════════════════════════════════
##  它回答什么问题
## ══════════════════════════════════════════════════════════════════
##  「太远 / 太小」是主观描述 —— 改参数前必须先有可复现的数。
##
##  ⚠️⚠️ 量法用的是**船体网格投影**（④），不是像素差：
##     舰船模型的 `get_aabb()` 是**未缩放的原始网格**（condor 76 世界单位），
##     实际缩放挂在父链上（scale≈0.0275），所以要经 `global_transform` 逐角点
##     `unproject_position` 才准。
##     像素差（有船 / 无船两张图相减）在本场景**不可用**：SSAO / GI 是屏幕空间
##     效果，加减一艘船会把周围一片的光照都改掉，差集比船本身大得多。
##
##  两种构图分别量：
##    ① `frame_battlefield(false)` —— 按部署带取景（刚进一局时看到的）
##    ② `frame_battlefield(true)`  —— 按真实舰队包围盒取景（0.6s 后的稳态）
##
##  跑法（**不要加 --headless**：要读渲染结果）：
##      "$GODOT_BIN" --path "<工程>" res://tools/probe_cam_framing.tscn
##
##  同时打印「再放大 k 倍会不会切船」—— 用真实重投影算，不写近似公式。

const SCENE := "res://scenes/battle_scene.tscn"
const OWN_SHIPS: Array[String] = [
	"condor", "thrasher", "caracal", "stabber", "moa",
]
## 我方部署区中间那行（--wide 时把船摊开用）
const OWN_ROW := 8

var _scene: Node = null
var _frames := 0
var _done := false


func _ready() -> void:
	var win := get_window()
	if win != null:
		win.size = Vector2i(1920, 1080)
	var ps: PackedScene = load(SCENE)
	if ps == null:
		print("✗ 载入 battle_scene.tscn 失败")
		get_tree().quit(1)
		return
	_scene = ps.instantiate()
	add_child(_scene)
	await get_tree().process_frame
	await get_tree().process_frame
	_inject()


func _inject() -> void:
	var run: Variant = _scene.get("run")
	if run == null:
		print("✗ 拿不到 run")
		return
	run.bench.clear()
	run.field.clear()
	# `--wide` = 摊到最宽（行 8，列 2/4/6/8/10）；默认 = 让 arena 用自动阵型摆
	var wide := OS.get_cmdline_user_args().has("--wide")
	for i in OWN_SHIPS.size():
		var rec := {"ship_key": StringName(OWN_SHIPS[i]), "star": 1,
				"cell": Vector2i(OWN_ROW, 2 + i * 2) if wide else Vector2i(-1, -1)}
		run.bench.append(rec)
		run.field.append(rec.duplicate(true))
	run.changed.emit()
	_scene.call("_respawn_own_fleet")


func _process(_dt: float) -> void:
	if _done or _scene == null:
		return
	_frames += 1
	if _frames < 40:
		return
	_done = true
	await _measure()
	get_tree().quit(0)


func _measure() -> void:
	var arena: Variant = _scene.get("arena")
	if arena == null:
		print("✗ 拿不到 arena")
		return
	var cam: Camera3D = arena.get("camera")
	var orbit: Node = arena.get("orion_cam")
	var layer: Node = arena.get("ships_layer")
	var vp := get_viewport().get_visible_rect().size
	print("══════════════════════════════════════════════════════════════")
	print("  相机取景量测（视口 %d×%d · fov %.1f°）" % [int(vp.x), int(vp.y), cam.fov])
	print("══════════════════════════════════════════════════════════════")
	print("  舰船数 = %d" % layer.get_child_count())

	# ── ① 开局构图（玩家进入一局时看到的）──
	arena.call("frame_battlefield", false)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	await _snap("① 开局（按部署带取景）", cam, orbit, layer, vp)
	_save("user://cam_open.png")

	# ── ② 跟随构图（取景收敛到真实舰队）──
	arena.call("frame_battlefield", true)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	await _snap("② 跟随舰队", cam, orbit, layer, vp)
	_save("user://cam_follow.png")

	# ── ④ 全船「船体」投影（排除护盾壳 / 锚点 / 尾迹，只留船体网格）──
	#    判据：raw AABB 最大那个 = 船体（condor 76 单位，缩放 0.0275 后约 2 单位）
	print("  ── ④ 船体投影（当前构图）──────────────────────────────")
	var hull := Rect2()
	var hull_first := true
	for n in layer.get_children():
		if not (n is Node3D):
			continue
		var best: MeshInstance3D = null
		var best_vol := 0.0
		for m in _meshes(n):
			var mi := m as MeshInstance3D
			if not mi.is_visible_in_tree():
				continue
			var ab: AABB = mi.get_aabb()
			var vol := ab.size.x * ab.size.y * ab.size.z
			if vol > best_vol:
				best_vol = vol
				best = mi
		if best == null:
			continue
		var box := _mesh_box(best, cam)
		hull = box if hull_first else hull.merge(box)
		hull_first = false
		print("    %-10s %-12s 屏幕 x %4d..%4d  y %4d..%4d  ⇒ %.0f×%.0f px"
				% [String(n.name), String(best.name),
					int(box.position.x), int(box.position.x + box.size.x),
					int(box.position.y), int(box.position.y + box.size.y),
					box.size.x, box.size.y])
	print("    舰队船体外接框：x %.0f..%.0f  y %.0f..%.0f  ⇒ %.0f×%.0f（屏宽 %.0f%% / 屏高 %.0f%%）"
			% [hull.position.x, hull.position.x + hull.size.x,
				hull.position.y, hull.position.y + hull.size.y,
				hull.size.x, hull.size.y,
				hull.size.x / vp.x * 100.0, hull.size.y / vp.y * 100.0])
	print("    备战席顶边 y=760 ⇒ 最下面的船%s"
			% ("压在备战席上（差 %d px）" % int(hull.position.y + hull.size.y - 760.0)
				if hull.position.y + hull.size.y > 760.0 else "在备战席之上"))

	# ── ③ 再放大 k 倍会不会切船（在 ② 的基础上，真实重投影）──
	var d0 := float(orbit.call("get_distance"))
	print("  ── ③ 推近扫描（视距 × 倍率）────────────────────────────")
	print("     倍率   视距    舰队屏幕框 y        x              判定")
	for k in [1.0, 1.2, 1.33, 1.5, 2.0]:
		_set_distance(orbit, d0 / float(k))
		await get_tree().process_frame
		var bb := _project_all(layer, cam)
		var fits := Rect2(Vector2.ZERO, vp).encloses(bb)
		var clear_hud := bb.position.y + bb.size.y <= 760.0
		print("     %.2f  %6.2f   y %4d..%4d   x %4d..%4d   %s%s"
				% [k, d0 / float(k),
					int(bb.position.y), int(bb.position.y + bb.size.y),
					int(bb.position.x), int(bb.position.x + bb.size.x),
					"✔ 全在屏内" if fits else "✘ 出画",
					"  / 浮在备战席上" if clear_hud else "  / 压住备战席"])
	_set_distance(orbit, d0)


## 拍一帧有船 / 一帧无船，差集 = 舰队真实像素。
func _snap(tag: String, cam: Camera3D, orbit: Node, layer: Node, vp: Vector2) -> void:
	print("  ── %s ──────────────────────────────" % tag)
	print("     zoom=%.4f  max_range=%.2f  视距=%.2f  pitch=%.3f"
			% [float(orbit.get("zoom")), float(orbit.call("get_max_range")),
				float(orbit.call("get_distance")), float(orbit.get("pitch"))])
	var with_ships: Image = get_viewport().get_texture().get_image()
	var hidden: Array = []
	for n in layer.get_children():
		if (n is Node3D) and (n as Node3D).visible:
			(n as Node3D).visible = false
			hidden.append(n)
	await RenderingServer.frame_post_draw
	var empty: Image = get_viewport().get_texture().get_image()
	for n in hidden:
		(n as Node3D).visible = true
	var ts := with_ships.get_width() / maxf(1.0, vp.x)
	var box := _diff_box(with_ships, empty)
	if box.size.x <= 0:
		print("     ⚠ 没有差异像素")
		return
	var x0 := box.position.x / ts
	var x1 := (box.position.x + box.size.x) / ts
	var y0 := box.position.y / ts
	var y1 := (box.position.y + box.size.y) / ts
	print("     舰队像素框：x %.0f..%.0f  y %.0f..%.0f  ⇒ %.0f×%.0f px（屏宽 %.0f%% / 屏高 %.0f%%）"
			% [x0, x1, y0, y1, x1 - x0, y1 - y0,
				(x1 - x0) / vp.x * 100.0, (y1 - y0) / vp.y * 100.0])
	# 逐船：一艘一艘单独显示，各自与空图相减
	print("     逐船：")
	for n in layer.get_children():
		if not (n is Node3D):
			continue
		for o in layer.get_children():
			(o as Node3D).visible = (o == n)
		await RenderingServer.frame_post_draw
		var solo: Image = get_viewport().get_texture().get_image()
		var b := _diff_box(solo, empty)
		for o in layer.get_children():
			(o as Node3D).visible = true
		if b.size.x <= 0:
			print("       %-16s （无差异像素）" % String(n.name))
			continue
		print("       %-16s x %.0f..%.0f  y %.0f..%.0f  ⇒ %.0f×%.0f px"
				% [String(n.name), b.position.x / ts, (b.position.x + b.size.x) / ts,
					b.position.y / ts, (b.position.y + b.size.y) / ts,
					b.size.x / ts, b.size.y / ts])


func _project_size(mi: MeshInstance3D, cam: Camera3D) -> Vector2:
	var out := Rect2()
	var started := false
	var aabb: AABB = mi.get_aabb()
	for i in 8:
		var p: Vector2 = cam.unproject_position(mi.global_transform * aabb.get_endpoint(i))
		if not started:
			out = Rect2(p, Vector2.ZERO)
			started = true
		else:
			out = out.expand(p)
	return out.size


func _mesh_box(mi: MeshInstance3D, cam: Camera3D) -> Rect2:
	var out := Rect2()
	var started := false
	var aabb: AABB = mi.get_aabb()
	for i in 8:
		var p: Vector2 = cam.unproject_position(mi.global_transform * aabb.get_endpoint(i))
		if not started:
			out = Rect2(p, Vector2.ZERO)
			started = true
		else:
			out = out.expand(p)
	return out


## 锚点截图（去出图看构图是否真的「船变大且没切」）。
func _save(path: String) -> void:
	var img: Image = get_viewport().get_texture().get_image()
	if img == null:
		return
	img.save_png(path)
	print("     截图 → %s" % path)


## 两张图的差异外接框（步长 2 采样，够用且快 4 倍）。
##
## ⚠️ 这个数在**用了屏幕空间效果（SSAO/GI）的场景里只能当粗略参考**：
##    加减一艘船会改变周围一片的光照，差集比船本身大。判「切没切」要看截图。
func _diff_box(a: Image, b: Image) -> Rect2i:
	var out := Rect2i()
	var first := true
	for y in range(0, a.get_height(), 2):
		for x in range(0, a.get_width(), 2):
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			if absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b) > 0.06:
				if first:
					out = Rect2i(x, y, 1, 1)
					first = false
				else:
					out = out.expand(Vector2i(x, y))
	return out


## 改视距：`distance = max_range * 1.52 / zoom` ⇒ 反解 max_range。
func _set_distance(orbit: Node, want: float) -> void:
	var zoom := float(orbit.get("zoom"))
	orbit.call("set_max_range", maxf(20.0, want * zoom / 1.52))


## 全部舰船的网格角点投影外接框（判「会不会切」用；尺寸仍以像素差为准）。
func _project_all(layer: Node, cam: Camera3D) -> Rect2:
	var out := Rect2()
	var started := false
	for n in layer.get_children():
		if not (n is Node3D) or not (n as Node3D).visible:
			continue
		for m in _meshes(n):
			var mi := m as MeshInstance3D
			if not mi.is_visible_in_tree():
				continue
			var aabb: AABB = mi.get_aabb()
			for i in 8:
				var p: Vector2 = cam.unproject_position(mi.global_transform * aabb.get_endpoint(i))
				if not started:
					out = Rect2(p, Vector2.ZERO)
					started = true
				else:
					out = out.expand(p)
	return out


func _meshes(root: Node) -> Array:
	var out: Array = []
	for c in root.get_children():
		var nm := String(c.name)
		if nm.begins_with("Bars") or nm.begins_with("Labels"):
			continue
		if c is MeshInstance3D:
			out.append(c)
		out.append_array(_meshes(c))
	return out
