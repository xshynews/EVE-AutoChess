extends Node

## ★ 舰船「体型刻度」验证探针（2026-09-28）
##
## ══════════════════════════════════════════════════════════════════
##  为什么必须单独做一个
## ══════════════════════════════════════════════════════════════════
##  · `probe_fleet_view53` **不能**用来比大小，两个原因：
##      ① 它**没设 `ship.ship_class`** ⇒ `EveShip.new()` 默认 FRIGATE
##         ⇒ 52 艘全按「护卫」缩放 ⇒ 大小差被抹平；
##      ② 正交视野 `CAM_SIZE=1.45`，而船长是 2.1~4.4 世界单位
##         ⇒ 船**整体溢出画幅**，量到的 bbox 一堆是全画幅（无法比较）。
##  · 本探针两件事都做对：**显式给吨位档** + **取景装得下**。
##
## ══════════════════════════════════════════════════════════════════
##  它输出什么
## ══════════════════════════════════════════════════════════════════
##  ① **世界空间船长**：遍历每艘船的所有 `MeshInstance3D`，把 `mesh.get_aabb()`
##     的 8 个角经 `global_transform`（含 hull_root.scale × model.scale 连乘）
##     送进世界空间，取最大轴向跨度 —— **由引擎算，探针不写一个乘号**（红线 40）。
##  ② 按吨位档汇总：`基准 / 实际 min~max / 档内比值` + **相邻档是否重叠**。
##  ③ 非 headless 时额外渲一张 **5 列（吨位）× 最多 12 行** 的对照图
##     （侧视、舰艏朝画面右），列头标吨位名与等级。
##
##  跑法：
##    "C:/godot/Godot_v4.7.1-stable_win64_console.exe" --headless \
##      --path "<工程>" --quit-after 12000 res://tools/probe_ship_size.tscn
##    （去掉 --headless 则额外出图）

const SHIP_SCRIPT := preload("res://scripts/visual/eve_ship_visual.gd")
const INDEX := preload("res://scripts/data/eve_ship_asset_index.gd")
const MODEL := preload("res://scripts/visual/eve_ship_model.gd")
const VISUAL := preload("res://scripts/visual/eve_ship_visual.gd")

const OUT_PNG := "user://ship_size_ladder.png"

const COL_GAP := 6.0          ## 列间距（世界单位，沿 Z；船最长 4.42 ⇒ 不会串列）
const ROW_GAP := 1.70         ## 行间距（世界单位，沿 Y）
const ROW_TOP := 1.5          ## 首行下移量（给列头 Label 留空，别压在一起）
const MAX_ROWS := 12
const CAM_H := 23.5           ## 正交纵向尺寸（装得下 12 行 + 船宽 + 列头）
## 列 → Z：屏幕右 = 世界 −Z ⇒ 要让 **护卫在最左**，护卫取最大 Z。
const COL_Z0 := 24.0

var _tiers: Array = []        ## 吨位档枚举顺序（运行时初始化，避免 const 跨类引用）
var _cols: Dictionary = {}    ## cls -> [ {id, real, vis, L} ]


func _ready() -> void:
	_tiers = [EveShip.Class.FRIGATE, EveShip.Class.DESTROYER, EveShip.Class.CRUISER,
			EveShip.Class.BATTLE_CRUISER, EveShip.Class.BATTLESHIP]
	print("══════════════════════════════════════════════════════════════")
	print("  舰船体型刻度验证（世界空间船长 = 引擎连乘，探针零复刻）")
	print("══════════════════════════════════════════════════════════════")

	var vp := SubViewport.new()
	vp.size = Vector2i(1920, 1080)
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.905, 0.905, 0.933)
	env.environment = e
	vp.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, 30.0, 0.0)
	sun.light_energy = 1.2
	vp.add_child(sun)

	for cls in _tiers:
		_cols[cls] = []
	for a in INDEX.all():
		if a == null:
			continue
		var cls := int(EveShip.CLASS_BY_COST.get(int(a.cost), -1))
		if not _cols.has(cls):
			continue
		var sid := StringName(a.id)
		_cols[cls].append({"id": sid, "real": MODEL.max_dim_m(sid),
				"vis": _build(sid, cls), "L": 0.0})

	# 摆位：列 = 吨位档（护卫最左）；行 = 档内按真实长轴从小到大，顶端对齐
	for ci in _tiers.size():
		var cls: int = _tiers[ci]
		var col: Array = _cols[cls]
		col.sort_custom(func(x, y): return x["real"] < y["real"])
		for r in col.size():
			(col[r]["vis"] as Node3D).position = Vector3(
					0.0, -ROW_TOP - float(r) * ROW_GAP, COL_Z0 - float(ci) * COL_GAP)

	print("")
	print("%-13s %-4s %-10s %-9s %-8s %s" % ["id", "等级", "真实长轴m", "世界船长", "系数", "档内u"])
	for ci in _tiers.size():
		var cls: int = _tiers[ci]
		for en in _cols[cls]:
			var L := _world_len(en["vis"])
			en["L"] = L
			print("%-13s %-4d %-10.1f %-9.3f %-8.4f %.3f" % [
					en["id"], VISUAL.tier_level(cls), en["real"], L,
					L / (VISUAL.HULL_REF_LENGTH * VISUAL.VISUAL_EXAGGERATION),
					VISUAL.tier_slot_u(en["id"], cls)])

	print("")
	print("── 按吨位档汇总（世界船长；基准 = 10 级刻度）──")
	var allL: Array = []
	var ok := true
	for cls in _tiers:
		var ls: Array = []
		for en in _cols[cls]:
			ls.append(en["L"])
		ls.sort()
		allL += ls
		print("  %-5s 等级%2d 基准 %.3f  →  实际 %.3f ~ %.3f （档内 %.3f×）  系数 %.4f ~ %.4f" % [
				_cls_name(cls), VISUAL.tier_level(cls), VISUAL.tier_base_length(cls),
				ls[0], ls[ls.size() - 1], ls[ls.size() - 1] / maxf(ls[0], 0.0001),
				ls[0] / 3.12, ls[ls.size() - 1] / 3.12])
	print("  ── 相邻档是否重叠 ──")
	for i in range(0, 4):
		var lo: float = _min_l(_cols[_tiers[i + 1]])
		var hi: float = _max_l(_cols[_tiers[i]])
		var good := lo >= hi
		if not good:
			ok = false
		print("     %-5s 最大 %.3f  vs  %-5s 最小 %.3f   %s" % [
				_cls_name(_tiers[i]), hi, _cls_name(_tiers[i + 1]), lo,
				"✓ 不重叠" if good else "✗ 重叠 %.3f" % (hi - lo)])
	print("  全库 %.3f ~ %.3f  总比值 %.2f×   %s" % [
			allL.min(), allL.max(), allL.max() / maxf(allL.min(), 0.0001),
			"★ 档序严格 ✓" if ok else "⚠ 有重叠"])

	if DisplayServer.get_name() == "headless":
		print("")
		print("（headless：只出数值，不出图）")
		get_tree().quit()
		return

	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = CAM_H
	vp.add_child(cam)
	var zc := COL_Z0 - COL_GAP * 2.0
	var yc := -ROW_TOP - float(MAX_ROWS - 1) * ROW_GAP * 0.5
	cam.global_position = Vector3(60.0, yc, zc)
	cam.look_at(Vector3(0.0, yc, zc), Vector3(0.0, 1.0, 0.0))

	var layer := CanvasLayer.new()
	vp.add_child(layer)
	for ci in _tiers.size():
		var cls: int = _tiers[ci]
		var lb := Label.new()
		lb.text = "%s  等级%d" % [_cls_name(cls), VISUAL.tier_level(cls)]
		lb.add_theme_font_size_override("font_size", 24)
		lb.add_theme_color_override("font_color", Color(0.08, 0.10, 0.12))
		layer.add_child(lb)
		var p := cam.unproject_position(Vector3(
				0.0, yc + CAM_H * 0.5 - 1.5, COL_Z0 - float(ci) * COL_GAP))
		lb.position = p - Vector2(56.0, 20.0)

	await get_tree().process_frame
	await get_tree().process_frame
	var img := vp.get_texture().get_image()
	if img != null:
		img.save_png(OUT_PNG)
		print("")
		print("出图 → %s" % ProjectSettings.globalize_path(OUT_PNG))
	else:
		print("")
		print("✗ 取图失败")
	get_tree().quit()


## 用**生产代码**摆出一艘船（红线 40：探针不碰任何旋转 / 缩放量）
func _build(sid: StringName, cls: int) -> Node3D:
	var sh := EveShip.new()
	sh.ship_key = sid
	sh.id = 1
	sh.ship_class = cls                 ## ★ 关键：不设就会全长成「护卫」
	sh.body = EveDestinyMotion.Body.new(1)
	sh.body.position = Vector3.ZERO
	sh.body.aim_dir = Vector3(0.0, 0.0, -1.0)
	sh.body.velocity = Vector3.ZERO

	var vis: Variant = SHIP_SCRIPT.new()
	vis.set("ship", sh)
	vis.call("setup", sh)
	vis.call("snap_facing", sh.body, true)
	vis.call("set_process", false)
	# 信息层（血条 / 射程标签）全关 —— 只量几何
	for n in (vis as Node).get_children():
		if n is Node3D and String(n.name).begins_with("Labels"):
			(n as Node3D).visible = false
	add_child(vis as Node3D)
	return vis as Node3D


## 世界空间最大轴向跨度：把每个 `MeshInstance3D` 的局部 AABB 8 角经
## `global_transform`（**引擎连乘**，含 hull_root.scale × model.scale）送到世界空间。
## ⚠️ 探针**不写任何乘号**（红线 40）。
func _world_len(root: Node) -> float:
	var best := 0.0
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			if mi.mesh == null:
				continue
			var ab := mi.get_aabb()
			var xf := mi.global_transform
			var mn := Vector3(INF, INF, INF)
			var mx := Vector3(-INF, -INF, -INF)
			for i in 8:
				var p := ab.position + Vector3(
						ab.size.x * float(i & 1),
						ab.size.y * float((i >> 1) & 1),
						ab.size.z * float((i >> 2) & 1))
				var w := xf * p
				mn = mn.min(w)
				mx = mx.max(w)
			var ext := mx - mn
			best = maxf(best, maxf(ext.x, maxf(ext.y, ext.z)))
	return best


func _min_l(col: Array) -> float:
	var m := INF
	for en in col:
		m = minf(m, en["L"])
	return m


func _max_l(col: Array) -> float:
	var m := -INF
	for en in col:
		m = maxf(m, en["L"])
	return m


func _cls_name(cls: int) -> String:
	return String(EveShip.CLASS_NAMES.get(cls, "?"))
