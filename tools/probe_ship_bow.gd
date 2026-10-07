extends Node3D

## 52 艘 3D 舰船的「舰艏在哪一端」—— 纯几何客观判定探针
##
## ══════════════════════════════════════════════════════════════════
##  为什么需要它（2026-09-23）
## ══════════════════════════════════════════════════════════════════
##  目视标定会**被「基准箭头」污染**：判定图上画了「前方 →」，
##  但那个机位下世界 +Z 其实投影在屏幕【左侧】（实测，见 probe_cam_axis）。
##  用户照箭头判 → 整份名单倒挂 180°，而且**看起来完全正常**。
##
##  所以这里换一个**只吃几何、不吃任何人工标注**的判据，做独立交叉验证。
##
## ── 判据（移植自 Blender 侧 blender_project.py::orient_ship()）────
##  「船首尖、船尾宽（引擎舱）」：
##    沿最长轴分 14 段，每段量另两轴的展宽（取 max），
##    两端各取 1/3 段求平均宽度 —— **窄的那端 = 舰艏**。
##
##  ⚠️ 该判据在 Blender 侧「一直判对」，但它对**两端宽度接近的船**
##     理论上可能失效（宽体船 / 双体船）。所以本探针同时打印完整
##     宽度曲线（14 个数），两端差距小的船要单独看。
##
## ── 与游戏朝向的关系 ─────────────────────────────────────────────
##  `eve_ship_visual.gd` 的 MODEL_YAW_FIX = −π/2 把 glb 的 +X 长轴转到 +Z，
##  而 `sync_from_body` 用 `atan2(v.x, v.z)` 设 rotation.y ⇒ **局部 +Z = 前向**。
##  ⇒ **舰艏在 +X 端的船：不翻转就正确；在 −X 端的船：需要翻转 180°。**
##  ⇒ 本探针给出的 `bow_plus == false` 那批，就是**客观上需要进 FLIP 表**的。
##
## ── 跑法（headless 即可，不需要渲染）──────────────────────────────
##   "C:/godot/Godot_v4.7.1-stable_win64_console.exe" --headless \
##     --path "F:/evezzq/eve自走棋918" --quit-after 4000 \
##     res://tools/probe_ship_bow.tscn

const INDEX := preload("res://scripts/data/eve_ship_asset_index.gd")

## 沿长轴的分段数（与 orient_ship 一致）
const SEGS := 14
## 顶点降采样步长（52 艘 × 6 万顶点，全量太慢）
const STEP := 7
## 两端各取多少段求平均（2 选 1；两边都算，看是否一致）
const K_ABS := 4        ## = SEGS // 3，orient_ship 用的口径
const K_REL := 3        ## 每端 3 段（更靠端点，对锥形舰更敏感）

var _rows_out: PackedStringArray = PackedStringArray()


func _ready() -> void:
	var rows: Array = INDEX.ROWS.duplicate()
	rows.sort_custom(func(a, b): return String(a[0]) < String(b[0]))

	_rows_out.append("id\tcn\taxis\tdx\tdy\tdz\tlw\trw\tbow_plus\tlw_r\trw_r\tbow_plus_rel\tws14")
	var n_plus := 0
	var n_minus := 0
	var n_bad := 0
	var minus_ids: PackedStringArray = PackedStringArray()
	var disagree: PackedStringArray = PackedStringArray()

	for r in rows:
		var id := String(r[0])
		var cn := String(r[3])
		var res := _measure(StringName(id))
		if res.is_empty():
			_rows_out.append("%s\t%s\tNO_MODEL" % [id, cn])
			n_bad += 1
			continue
		var axis_name: String = ["X", "Y", "Z"][int(res["axis"])]
		var d: Vector3 = res["dims"]
		var lw := float(res["lw"])
		var rw := float(res["rw"])
		var bow_plus := bool(res["bow_plus"])
		var lwr := float(res["lw_rel"])
		var rwr := float(res["rw_rel"])
		var bow_plus_rel := bool(res["bow_plus_rel"])
		if not bow_plus:
			n_minus += 1
			minus_ids.append(id)
		else:
			n_plus += 1
		if bow_plus != bow_plus_rel:
			disagree.append(id)
		var ws: PackedFloat32Array = res["ws"]
		var ws_str := PackedStringArray()
		for w in ws:
			ws_str.append("%.2f" % w)
		_rows_out.append("%s\t%s\t%s\t%.2f\t%.2f\t%.2f\t%.2f\t%.2f\t%s\t%.2f\t%.2f\t%s\t%s" % [
			id, cn, axis_name, d.x, d.y, d.z, lw, rw,
			("+" if bow_plus else "-"),
			lwr, rwr, ("+" if bow_plus_rel else "-"),
			",".join(ws_str)])

	print("[BOW] ═══════════════════════════════════════════════════")
	print("[BOW] 判据：沿长轴分 %d 段量横截面展宽，窄端=舰艏（orient_ship 口径）" % SEGS)
	print("[BOW] bow_plus = 舰艏在【长轴正端】。放到游戏里：")
	print("[BOW]   bow_plus=true  → 舰艏在 +X → MODEL_YAW_FIX 后朝 +Z → 【不用翻转】")
	print("[BOW]   bow_plus=false → 舰艏在 −X → 会朝 −Z 倒飞 → 【需要翻转】")
	print("[BOW] 统计：正端 %d 艘 / 负端 %d 艘 / 缺模型 %d 艘" % [n_plus, n_minus, n_bad])
	print("[BOW] 需要翻转（bow_plus=false）%d 艘：%s" % [n_minus, ", ".join(minus_ids)])
	print("[BOW] 两种 K 口径判定不一致 %d 艘：%s" % [
		disagree.size(), ("（" + ", ".join(disagree) + "）") if disagree.size() > 0 else "无"])
	print("[BOW] 表格：")
	for line in _rows_out:
		print("[BOW] " + line)
	print("[BOW] ==== DONE ====")
	get_tree().quit(0)


## 量一艘船
func _measure(id: StringName) -> Dictionary:
	var model := EveShipModel.instantiate(id, false)
	if model == null:
		return {}
	var pts := PackedVector3Array()
	_collect(model, Transform3D(), pts)
	model.free()
	if pts.size() < 16:
		return {}

	var mn := Vector3(INF, INF, INF)
	var mx := Vector3(-INF, -INF, -INF)
	for p in pts:
		mn = mn.min(p)
		mx = mx.max(p)
	var dim := mx - mn
	if dim.length() < 1e-6:
		return {}

	# 最长轴
	var a := 0
	if dim.y > dim[a]:
		a = 1
	if dim.z > dim[a]:
		a = 2
	var vert: Array[int] = []
	for i in 3:
		if i != a:
			vert.append(i)

	# 分段 min/max
	var seg_min: Array[Vector3] = []
	var seg_max: Array[Vector3] = []
	var seg_cnt := PackedInt32Array()
	seg_cnt.resize(SEGS)
	for s in SEGS:
		seg_min.append(Vector3(INF, INF, INF))
		seg_max.append(Vector3(-INF, -INF, -INF))
	var span := maxf(dim[a], 1e-6)
	for p in pts:
		var s := int((p[a] - mn[a]) / span * float(SEGS))
		s = clampi(s, 0, SEGS - 1)
		seg_min[s] = seg_min[s].min(p)
		seg_max[s] = seg_max[s].max(p)
		seg_cnt[s] += 1

	var ws := PackedFloat32Array()
	ws.resize(SEGS)
	for s in SEGS:
		if seg_cnt[s] < 4:
			ws[s] = -1.0
			continue
		var w := 0.0
		for b in vert:
			w = maxf(w, seg_max[s][b] - seg_min[s][b])
		ws[s] = w

	var abs_res := _end_widths(ws, K_ABS)
	var rel_res := _end_widths(ws, K_REL)
	return {
		"axis": a, "dims": dim, "ws": ws,
		"lw": abs_res[0], "rw": abs_res[1], "bow_plus": abs_res[2],
		"lw_rel": rel_res[0], "rw_rel": rel_res[1], "bow_plus_rel": rel_res[2],
	}


## 取两端各 k 段的平均宽度，返回 [左均, 右均, 舰艏是否在正端]
func _end_widths(ws: PackedFloat32Array, k: int) -> Array:
	k = clampi(k, 1, SEGS / 2)
	var lw := 0.0
	var nl := 0
	for i in k:
		if ws[i] >= 0.0:
			lw += ws[i]
			nl += 1
	var rw := 0.0
	var nr := 0
	for i in range(SEGS - k, SEGS):
		if ws[i] >= 0.0:
			rw += ws[i]
			nr += 1
	if nl > 0:
		lw /= float(nl)
	if nr > 0:
		rw /= float(nr)
	return [lw, rw, rw <= lw]


func _collect(n: Node, xf: Transform3D, out: PackedVector3Array) -> void:
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
					out.append(here * vs[i])
					i += STEP
	for c in n.get_children():
		_collect(c, here, out)
