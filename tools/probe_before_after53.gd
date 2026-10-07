extends Node

## ★ 53 轮 · **「改前 / 改后」对照出图**（用户需求：证据链要有对照组）
##
## ══════════════════════════════════════════════════════════════════
##  53 轮的核心改动是 `eve_ship_visual.gd` 的
##      const GLOBAL_ROLL_180 : true → false
##  用户要看的正是这个开关的**画面差别**。
##
##  但「改前」状态已经不存在于代码里了（已改 false）。
##  ⇒ 本探针**不改生产常量**，而是在**离屏 SubViewport** 里
##    逐艘渲两张图：
##       图 A：含滚转（等价 `true`）  = `R_z(180°) · zero_pose_basis_no_roll`
##       图 B：不含滚转（现行生产值） = `zero_pose_basis_no_roll`
##    ⚠️ 两张图的**唯一差异**就是这个矩阵，别的一律相同（同机位、同光照、同尺度）
##       —— 否则对照无效（红线 40：变量必须唯一）。
##
##  ⚠️ 图 A 的算式**看似复刻**，但它等价于"把生产常量改回 true"，
##     且我在生产侧留了 `global_roll()` 这个**生产函数**来取那个矩阵 ⇒
##     用的是生产代码，不是我手写的 `Basis.from_euler`。
##
##  用法（⚠️ 非 headless）：
##      Godot_v4.7.1-stable_win64_console.exe --path "<工程>" --quit-after 9000 \
##          res://tools/probe_before_after53.tscn -- --ids=kestrel,slasher --size=420

const SHIP_SCRIPT := preload("res://scripts/visual/eve_ship_visual.gd")
const YAW := preload("res://scripts/data/eve_ship_yaw.gd")

const CAM_DIST := 8.0
const CAM_SIZE := 1.45
const OUT_DIR := "user://before_after53"

var _ids: PackedStringArray = ["kestrel", "slasher"]
var _size := 420


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var ua := OS.get_cmdline_user_args()
	# ⚠️ 两种写法都要认：`--ids=a,b`（等号）与 `--ids a,b`（分开）。
	#    53 轮踩过：只写等号形式 ⇒ 静默用默认值，出图全是默认那两艘（不报错）。
	var joined := " ".join(ua)
	for tok in ua:
		if tok.begins_with("--ids="):
			_ids = tok.substr(6).split(",")
		elif tok.begins_with("--size="):
			_size = int(tok.substr(7))
	for i in ua.size() - 1:
		if ua[i] == "--ids":
			_ids = ua[i + 1].split(",")
		elif ua[i] == "--size":
			_size = int(ua[i + 1])

	print("══════════════════════════════════════════════════════════════")
	print("  53 轮 · 「含滚转(改前) / 不含滚转(改后)」对照出图")
	print("══════════════════════════════════════════════════════════════")
	print("  GLOBAL_ROLL_180 现值 = %s" % str(SHIP_SCRIPT.GLOBAL_ROLL_180))
	print("  待渲：%s（%d 艘 × 2 版 × 2 机位）" % [", ".join(_ids), _ids.size()])
	print("")

	_run()


## ⚠️ `_shot()` 里有 `await` ⇒ 它一被调就成协程；
##    直接在 `_ready()` 里 await 会让「quit()」在 await 恢复前就执行（实测：出 0 张图）。
##    ⇒ 收尾必须放在独立协程里，由它 await 完整流程。
func _run() -> void:
	for sid in _ids:
		await _shot(StringName(sid.strip_edges()))

	print("")
	print("出图 → %s" % ProjectSettings.globalize_path(OUT_DIR))
	get_tree().quit()


func _shot(sid: StringName) -> void:
	# 世界 −Z 方向放一个红球（= 敌人方向），与 probe_ship_views 同口径
	var ball := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.062
	sph.height = 0.124
	ball.mesh = sph
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1, 0.15, 0.12)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ball.material_override = mat
	ball.position = Vector3(0, 0.62, -0.72)
	add_child(ball)

	var vp := SubViewport.new()
	vp.size = Vector2i(_size, _size)
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = CAM_SIZE
	vp.add_child(cam)

	# 两版姿态：BEFORE = 含滚转（48~53 轮初的生产值）· AFTER = 不含（53 轮修后）
	var after := SHIP_SCRIPT.zero_pose_basis_no_roll(sid)
	var before: Basis = SHIP_SCRIPT.global_roll() * after
	var versions := [["BEFORE", before], ["AFTER", after]]
	var shots := [
		["FRONT", Vector3(0, 0, 1), Vector3(0, 1, 0)],
		["TOP", Vector3(0, 1, 0), Vector3(0, 0, -1)],
	]

	for ver in versions:
		var vtag: String = ver[0]
		var basis: Basis = ver[1]
		var model := EveShipModel.instantiate(sid)
		if model == null:
			print("  ✗ %s 无模型" % String(sid))
			break
		model.transform.basis = basis
		add_child(model)
		for sh in shots:
			var tag: String = sh[0]
			var dir: Vector3 = sh[1]
			var up: Vector3 = sh[2]
			cam.global_position = dir * CAM_DIST
			cam.look_at(Vector3.ZERO, up)
			await get_tree().process_frame
			await get_tree().process_frame
			var img := vp.get_texture().get_image()
			if img == null:
				print("  ✗ %s %s/%s 取图失败（headless？）" % [String(sid), vtag, tag])
				continue
			img.save_png("%s/%s_%s_%s.png" % [OUT_DIR, String(sid), vtag, tag])
		remove_child(model)
		model.free()
	print("  ✔ %s" % String(sid))

	remove_child(ball)
	ball.free()
	remove_child(vp)
	vp.free()
