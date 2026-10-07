extends Node
## 验证 30 艘 away 的新 spec 是否真让 bow 朝 −Z
##
## 跑法：
##   "C:/godot/Godot_v4.7.1-stable_win64_console.exe" --headless \
##     --path "F:/evezzq/eve自走棋918" --quit-after 5000 \
##     res://tools/probe_verify_r20.gd

const YAW := preload("res://scripts/data/eve_ship_yaw.gd")
const MODEL_YAW_FIX := -PI / 2.0
const ENEMY_DIR := Vector3(0.0, 0.0, -1.0)

## 30 艘新 spec（按 r20 提案）
const PROPOSED := {
	&"typhoon":     "-X,+Y,-Z",
	&"condor":      "-X,+Y,-Z",
	&"executioner": "-X,+Y,-Z",
	&"raven":       "-X,+Y,-Z",
	&"apocalypse":  "-X,+Y,-Z",
	&"omen":        "-X,+Y,-Z",
	&"dragoon":     "-X,+Y,-Z",
	&"coercer":     "-X,+Y,-Z",
	&"stabber":     "-X,+Y,-Z",
	&"thrasher":    "-X,+Y,-Z",
	&"abaddon":     "-X,+Y,-Z",
	&"rokh":        "-X,+Y,-Z",
	&"osprey":      "-X,+Y,-Z",
	&"cormorant":   "-X,+Y,-Z",
	&"hurricane":   "-X,+Y,-Z",
	&"brutix":      "-X,+Y,-Z",
	&"maelstrom":   "-X,+Y,-Z",
	&"rifter":      "-X,+Y,-Z",
	&"punisher":    "-X,+Y,-Z",
	&"moa":         "-X,+Y,-Z",
	&"rupture":     "-X,+Y,-Z",
	&"drake":       "-X,+Y,-Z",
	&"thorax":      "-X,+Y,-Z",
	&"caracal":     "-X,+Y,-Z",
	&"maller":      "-X,+Y,-Z",
	&"incursus":    "-X,+Y,-Z",
	&"prophecy":    "-X,+Y,-Z",
	&"exequror":    "-X,+Y,-Z",
	&"kestrel":     "+Z,-X,-Y",
	&"slasher":     "+Z,-X,-Y",
}


func _ready() -> void:
	print("[R20] ════ 30 艘新 spec 朝敌验证 ═══")
	var n_ok := 0
	var n_bad := 0
	for id in PROPOSED.keys():
		var spec: String = PROPOSED[id]
		var M := _spec_to_basis(spec)
		var bow := Basis.from_euler(Vector3(0.0, MODEL_YAW_FIX, 0.0)) * M * Vector3(1.0, 0.0, 0.0)
		var dot := bow.dot(ENEMY_DIR)
		var ok := dot > 0.9
		print("[R20]  %-13s spec=%-12s  bow=%s  dot(−Z)=%+.4f  %s" % [
			String(id), spec, _vec(bow), dot, ("✅" if ok else "❌")])
		if ok:
			n_ok += 1
		else:
			n_bad += 1
	print("[R20] ── 验证：%d 通过 / %d 失败 ──" % [n_ok, n_bad])

	# 专门为 kestrel/slasher 反解
	print("")
	print("[R20] ════ kestrel/slasher 反解（24 个右手系 spec 候选） ═══")
	for id in [&"kestrel", &"slasher"]:
		print("[R20] ▶ %s" % String(id))
		var shown := 0
		for spec in _enumerate_basis_specs():
			var M := _spec_to_basis(spec)
			if absf(M.determinant() - 1.0) > 0.001:
				continue
			var bow := Basis.from_euler(Vector3(0.0, MODEL_YAW_FIX, 0.0)) * M * Vector3(1.0, 0.0, 0.0)
			var dot := bow.dot(ENEMY_DIR)
			if dot > 0.9 and absf(bow.y) < 0.1:
				print("[R20]   ✅  spec=%-12s  bow=%s  dot=%+.3f  det=%+.3f" % [
					spec, _vec(bow), dot, M.determinant()])
				shown += 1
		print("[R20]   候选数 = %d" % shown)

	# 同时验：spec 必须是合法旋转（det=+1，第三行 = 1×2）
	for id in PROPOSED.keys():
		var spec: String = PROPOSED[id]
		var M := _spec_to_basis(spec)
		var det := M.determinant()
		var row3 := M.z.cross(M.x)   # YAW.axis_remap 用「rows = Basis 的列」，第 3 行 (Z) 应等于 1×2
		var err := (row3 - M.y).length()
		print("[R20]  %-13s det=%+.3f  row3_err=%+.3f  M.x=%s  M.y=%s  M.z=%s" % [
			String(id), det, err, _vec(M.x), _vec(M.y), _vec(M.z)])

	get_tree().quit(0)


func _spec_to_basis(spec: String) -> Basis:
	var parts := spec.split(",")
	var rows: Array[Vector3] = []
	for p in parts:
		var s := String(p).strip_edges()
		var sign := 1.0 if s[0] == "+" else -1.0
		var v := Vector3.ZERO
		match s[1].to_upper():
			"X": v.x = sign
			"Y": v.y = sign
			"Z": v.z = sign
		rows.append(v)
	return Basis(
		Vector3(rows[0].x, rows[1].x, rows[2].x),
		Vector3(rows[0].y, rows[1].y, rows[2].y),
		Vector3(rows[0].z, rows[1].z, rows[2].z))


func _vec(v: Vector3) -> String:
	return "(%+.3f, %+.3f, %+.3f)" % [v.x, v.y, v.z]


## 枚举 24 个右手系 spec 字符串（3! × 2^3 = 48，过滤掉 24 个 det=−1）
func _enumerate_basis_specs() -> Array[String]:
	var out: Array[String] = []
	var ax := ["X", "Y", "Z"]
	for perm in [
		[0, 1, 2], [0, 2, 1], [1, 0, 2], [1, 2, 0], [2, 0, 1], [2, 1, 0]
	]:
		for s0 in ["+", "-"]:
			for s1 in ["+", "-"]:
				for s2 in ["+", "-"]:
					var spec := "%s%s,%s%s,%s%s" % [
						s0, ax[perm[0]], s1, ax[perm[1]], s2, ax[perm[2]]]
					out.append(spec)
	return out
