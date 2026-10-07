extends Node

## ★ 53 轮（第四版）· **开打瞬间「首帧姿态跳变」定位**
##
## ══════════════════════════════════════════════════════════════════
##  现象
## ══════════════════════════════════════════════════════════════════
##  `probe_handoff53` 用逐帧真实 dt 口径统计后：
##      超闸门帧数 ≈ 0.7% ~ 1.25%，**全部集中在 `algos` 一艘**
##      最严重一帧 3.0°（该帧 cap=0.38°）
##
##  注意 `cap` 已经是**生产函数** `facing_max_step_deg(dt)` 的值
##  （含 `maxf(delta, 1/240)` 下限 ⇒ 最小 0.375°）。
##  ⇒ 3.0° 是 cap 的 **8 倍**，说明闸门**没有生效**或被绕过。
##
## ══════════════════════════════════════════════════════════════════
##  本探针干什么
## ══════════════════════════════════════════════════════════════════
##  在**布阵 → 开打切换的那几帧**里，对每艘船**逐帧同时记三样**：
##    ① `node.quaternion`（视觉根节点的朝向，`sync_from_body` 写的）
##    ② `model.basis`（几何体自己的姿态 = `zero_pose_basis`，构造时写死）
##    ③ `mesh.global_transform.basis`（**引擎渲染实际用的**，含全部父子链）
##  并算出**每一样**的逐帧角增量。
##
##  ⇒ 三者中哪一样在跳，就锁定了跳变发生在哪一层：
##    · ① 跳 ⇒ `_facing_quat` 的闸门没生效（`sync_from_body`）或被 `snap` 覆盖
##    · ② 跳 ⇒ 几何体姿态在运行中被重写（不该发生）
##    · ③ 跳而 ①② 不跳 ⇒ **父子链里有别的东西在动**（父节点 / `hull_root`）
##
## ⚠️ 红线 40：全部读**引擎真值**（`global_transform` / `quaternion`），
##    不自己乘矩阵复刻。
##
##  用法：
##      Godot_v4.7.1-stable_win64_console.exe --headless \
##          --path "<工程>" --quit-after 1400 \
##          res://tools/probe_jump53.tscn

const YAW := preload("res://scripts/data/eve_ship_yaw.gd")

const WANT: Array[String] = [
	"abaddon", "kestrel", "algos", "catalyst",
	"myrmidon", "tristan", "slasher", "burst",
]

var _scene: Node = null
var _frames := 0
var _phase := 0
## id → { ① node.quat, ② model.basis, ③ mesh.global.basis }
var _prev: Dictionary = {}
var _worst: Dictionary = {}       # id → [layer, deg]
var _rows: Array[String] = []
var _log: Array[String] = []
var _armed := false


func _ready() -> void:
	print("══════════════════════════════════════════════════════════════")
	print("  53d · 开打瞬间首帧姿态跳变定位（逐帧三层次角增量）")
	print("══════════════════════════════════════════════════════════════")
	var ps: PackedScene = load("res://scenes/battle_scene.tscn")
	if ps == null:
		print("✗ 载入失败")
		get_tree().quit()
		return
	_scene = ps.instantiate()
	add_child(_scene)


func _process(_delta: float) -> void:
	_frames += 1
	match _phase:
		0:
			if _frames >= 50:
				_inject()
				_phase = 1
		1:
			if _frames >= 120:
				print("")
				print("── 布阵态基线（第 120 帧）──")
				_dump("prep")
				_scene.call("start_battle")
				_armed = true
				_phase = 2
		2:
			if _armed:
				_sample(_frames - 120)
				if _frames - 120 >= 6:
					_armed = false
					_finish()
		3:
			pass


func _inject() -> void:
	var run: Variant = _scene.get("run")
	if run == null:
		print("✗ 拿不到 run")
		return
	run.set("coin", 999999)
	var bench: Array = run.get("bench")
	var field: Array = run.get("field")
	bench.clear()
	field.clear()
	for s in WANT:
		field.append({"ship_key": StringName(s), "star": 1, "cost": 1})
	run.emit_signal("changed")
	_scene.call("_respawn_own_fleet")


## 逐帧记三个层次
func _sample(t: int) -> void:
	var arena: Node = _scene.get("arena")
	if arena == null:
		return
	var parts := PackedStringArray()
	var sim: Variant = _scene.get("sim")
	if sim == null:
		return
	for ship in sim.ships:
		if ship.team != 0:
			continue
		var sid: StringName = ship.ship_key
		var vis: Node3D = arena.get_ship_visual(ship.id)
		if vis == null:
			continue
		var m := _first_mesh(vis)
		if m == null:
			continue

		# ① 视觉根节点
		var q1 := vis.quaternion
		# ② 几何体自身（`model` 是 mesh 的直系祖先里带 basis 的那个 —— 用 mesh 的父链回溯不可靠，
		#    改为直接读 mesh 的 **local** transform（相对其父），那正是构造时写的姿态）
		var b2 := m.transform.basis.orthonormalized()
		# ③ 引擎渲染实际用的
		var b3 := m.global_transform.basis.orthonormalized()

		var key := String(sid)
		var pq1: Quaternion = _prev.get("q1_" + key, q1)
		var pb2: Basis = _prev.get("b2_" + key, b2)
		var pb3: Basis = _prev.get("b3_" + key, b3)

		var d1 := rad_to_deg(pq1.angle_to(q1))
		var d2 := rad_to_deg(pb2.get_rotation_quaternion().angle_to(b2.get_rotation_quaternion()))
		var d3 := rad_to_deg(pb3.get_rotation_quaternion().angle_to(b3.get_rotation_quaternion()))

		_prev["q1_" + key] = q1
		_prev["b2_" + key] = b2
		_prev["b3_" + key] = b3

		var w: Array = _worst.get(key, ["", 0.0])
		for pair in [["①node", d1], ["②model", d2], ["③engine", d3]]:
			if float(pair[1]) > float(w[1]):
				w = [pair[0], float(pair[1])]
		_worst[key] = w

		if d1 > 0.05 or d2 > 0.05 or d3 > 0.05:
			_log.append("  t=%d %-10s ①node %.2f°  ②model %.2f°  ③engine %.2f°"
					% [t, key, d1, d2, d3])
		parts.append("%s[%.2f/%.2f/%.2f]" % [key, d1, d2, d3])
	print("  t=%d  " % t + " ".join(parts))


func _dump(tag: String) -> void:
	var arena: Node = _scene.get("arena")
	var sim: Variant = _scene.get("sim")
	if sim == null:
		return
	for ship in sim.ships:
		if ship.team != 0:
			continue
		var sid: StringName = ship.ship_key
		var vis: Node3D = arena.get_ship_visual(ship.id)
		if vis == null:
			continue
		var m := _first_mesh(vis)
		if m == null:
			continue
		var gb := m.global_transform.basis.orthonormalized()
		var bw := (gb * YAW.bow_axis(sid)).normalized()
		var uw := (gb * YAW.up_axis(sid)).normalized()
		print("  %-10s 舰艏%s 船背%s  bow·敌=%+.3f up·天=%+.3f" % [
				String(sid),
				_fv(bw), _fv(uw),
				bw.dot(Vector3(0, 0, -1)), uw.dot(Vector3(0, 1, 0))])


func _finish() -> void:
	print("")
	print("──────────────────────────────────────────────────────────────")
	print("  各船**最严重**的单帧跳变（跑完整轮 + 开打后 6 帧）：")
	for k in _worst.keys():
		var w: Array = _worst[k]
		print("    %-10s 最严重层次 = %-8s  %.2f°" % [k, String(w[0]), float(w[1])])
	print("")
	print("  层次含义：①node = `sync_from_body` 写的朝向 · ②model = 几何体自身姿态 ·")
	print("           ③engine = 引擎渲染实际用的（含父子链）")
	print("  ⇒ ①跳 = 闸门没生效；②跳 = 姿态被重写（不该发生）；③跳而①②不跳 = 父链在动")
	print("")
	print("══ t≥0 的逐帧记录（只有 >0.05° 的行）══")
	if _log.is_empty():
		print("  （无 —— 开打后 6 帧全船三层次增量都 < 0.05°）")
	else:
		for l in _log:
			print(l)
	get_tree().quit()


func _first_mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n as MeshInstance3D
	for c in n.get_children():
		var got := _first_mesh(c)
		if got != null:
			return got
	return null


func _fv(v: Vector3) -> String:
	return "(%.2f,%+.2f,%+.2f)" % [v.x, v.y, v.z]
