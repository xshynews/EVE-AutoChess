extends Node

## ★ 53 轮 · **布阵阶段实机朝向**验收（红线 54 的判据）
##
## ══════════════════════════════════════════════════════════════════
##  这个探针判什么
## ══════════════════════════════════════════════════════════════════
##  用户裁决（53 轮）：「初始状态（= 我把舰船摆到战斗区的时候）一律朝正前方，
##  正前方 = 世界 −Z」。
##
##  本探针**走真实生产链路**：
##      起 `battle_scene.tscn` → 等 `begin_prep` 跑完（布阵态就位）
##      → 读**引擎渲染出来**的 `mesh.global_transform.basis`
##      → 算 `舰艏(世界) · (0,0,−1)`，要求 ≈ **+1.000**
##
##  ⚠️ 红线 40：**必须读引擎连乘的结果**（`mesh.global_transform`），
##     不许自己拿 `SHIP_AXES` / `zero_pose_basis` 复刻算式 —— 复刻必然漂移。
##     期望值侧则独立取 `EveShipYawTable.bow_axis(id)`（表的真值），
##     两边来源不同，才叫"对拍"。
##
##  ⚠️ 红线 42：敌人恒在世界 **−Z**（`deploy_enemy_z = −45`）。
##
##  用法：
##      Godot_v4.7.1-stable_win64_console.exe --headless \
##          --path "<工程>" --quit-after 2400 \
##          res://tools/probe_prep53.tscn

const OUT_DIR := "user://prep53"

## 强塞的我方 8 艘（覆盖 52 艘里的各种结构：R_y(180°) 主流 / R_x(90°) 三艘 /
## 120° 斜轴两艘 / 以及 24~28 轮翻过案的几艘）—— 让"逐艘各异"这类问题无处藏。
const WANT: Array[String] = [
	"abaddon", "kestrel", "algos", "catalyst",
	"myrmidon", "tristan", "slasher", "burst",
	"maller", "inquisitor", "raven", "thorax",
]

var _scene: Node = null
var _frames := 0
var _ready_done := false
var _settled := false
var _rows: Array = []


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	print("══════════════════════════════════════════════════════════════")
	print("  53 轮 · 布阵阶段实机朝向验收（应全员朝世界 −Z）")
	print("══════════════════════════════════════════════════════════════")

	var ps: PackedScene = load("res://scenes/battle_scene.tscn")
	if ps == null:
		print("✗ 载入 battle_scene.tscn 失败")
		get_tree().quit()
		return
	_scene = ps.instantiate()
	add_child(_scene)


## 强塞我方舰队 —— 与 `probe_fight52` 同款注入法（改 run.bench/field + 重建）。
##
## ⚠️ 必须在**布阵阶段**做（`_respawn_own_fleet` 只允许 PREP，见
##    `_on_run_changed` 的守卫 `run.phase == Phase.PREP`）。
##    本探针**不调 start_battle** ⇒ 停在布阵态，正是要测的状态。
func _inject_fleet() -> void:
	var run: Node = _scene.get("run")
	if run == null:
		print("✗ 拿不到 run")
		return
	run.coin = 999999
	run.bench.clear()
	run.field.clear()
	for k in WANT:
		run.bench.append({"ship_key": StringName(k), "star": 1, "cell": Vector2i(-1, -1)})
		run.field.append(run.bench[run.bench.size() - 1].duplicate(true))
	run.changed.emit()
	_scene.call("_respawn_own_fleet")


func _process(_delta: float) -> void:
	_frames += 1
	if _settled:
		return
	# ① 等主场景 ready（`_ready` 里跑 begin_prep / _place_fleet / spawn）
	if not _ready_done:
		if _frames < 50:
			return
		_ready_done = true
		_inject_fleet()
		return
	# ② 注入后等视觉节点 world transform 被引擎连乘出来
	if _frames < 120:
		return
	_settled = true
	_measure()
	_write_report()
	# ⚠️ 不能在这里 `await` —— `_process` 每帧都会被调，await 之后会继续往下走。
	#    截图 + 退出交给独立协程，本函数立刻返回。
	_finish()


## 收尾协程：调机位 → 等收敛 → 截图 → 退出。
func _finish() -> void:
	await _shoot()
	get_tree().quit()


## 布阵实机截图 —— 出图给用户肉眼确认「一排船头朝敌人」。
##
## ⚠️ 两条硬要求（踩过）：
##   ① **必须非 headless**（headless 下 viewport 是 1920×1920 且不渲染 3D）
##   ② 相机**必须调到能看全我方部署带**——默认战斗机位离得太远，
##      在这个尺度下船只有几个像素。这里用 `frame_own_zone()`（我方 4 行取景）
##      再加一点俯角，是我们真正想让人看到的那一帧。
func _shoot() -> void:
	# ⚠️ **无头下不截图**：headless 用的是 dummy 渲染后端，viewport 拿不到
	#    纹理（实测报 `Parameter "t" is null` 并触发段错误）。
	#    这不是错误，是 headless 的固有行为 ⇒ 静默跳过，别让它污染验收输出。
	if DisplayServer.get_name() == "headless":
		return
	var arena: Node = _scene.get("arena")
	if arena == null:
		return
	# 让相机稳定到"看全我方部署区"的机位
	arena.call("frame_own_zone")
	for _i in 90:
		await get_tree().process_frame
	var vp := get_viewport()
	if vp == null:
		return
	var img := vp.get_texture().get_image()
	if img == null:
		print("✗ 截图失败（viewport 无图像）—— 是否跑在 headless？")
		return
	var path := OUT_DIR + "/prep_overview.png"
	img.save_png(path)
	print("")
	print("截图 → %s（实际路径见 user:// 展开）" % path)
	# 也拷一份到工程外便于取用
	var abs_src := ProjectSettings.globalize_path(path)
	print("绝对路径：%s" % abs_src)


func _measure() -> void:
	var arena: Node = _scene.get("arena")
	if arena == null:
		print("✗ 拿不到 arena")
		return
	var own: Array = _scene.get("_own_ships")
	var enemy: Array = _scene.get("_enemy_ships")
	if own == null or enemy == null:
		print("✗ 拿不到舰队")
		return

	print("我方 %d 艘 · 敌方 %d 艘　（布阵阶段，未开打）" % [own.size(), enemy.size()])
	print("")
	print("%-14s %-6s %-26s %-11s %-11s" % [
			"ship_id", "team", "舰艏(世界,引擎渲染)", "vs −Z", "判定"])
	print("──────────────────────────────────────────────────────────────")

	var bad: Array = []
	var checked := 0

	for pair in [[own, 0], [enemy, 1]]:
		var fleet: Array = pair[0]
		var team: int = pair[1]
		for ship in fleet:
			var vis: Node3D = arena.get_ship_visual(ship.id)
			if vis == null:
				continue
			var mesh: MeshInstance3D = _first_mesh(vis)
			if mesh == null:
				continue
			var tb: Basis = mesh.global_transform.basis.orthonormalized()
			# 舰艏 = 该船在**表里登记的**舰艏轴，经引擎连乘后的世界方向。
			var bow_local: Vector3 = EveShipYawTable.bow_axis(ship.ship_key)
			var bow_world: Vector3 = (tb * bow_local).normalized()

			# 期望方向：己方 → −Z，敌方 → +Z（各自朝对面）
			var want := Vector3(0.0, 0.0, -1.0) if team == 0 else Vector3(0.0, 0.0, 1.0)
			var dotv := bow_world.dot(want)
			var ok := dotv > 0.94     # 20° 容差（与 meshrot53 同一把尺）
			checked += 1
			if not ok:
				bad.append("%s(team%d %.1f°)" % [
						String(ship.ship_key), team,
						rad_to_deg(acos(clampf(dotv, -1.0, 1.0)))])

			print("%-14s %-6d %-26s %-11.3f %-11s" % [
					String(ship.ship_key), team,
					"(%.2f,%.2f,%.2f)" % [bow_world.x, bow_world.y, bow_world.z],
					dotv, "✓" if ok else "✗"])

			_rows.append({
				"id": String(ship.ship_key), "team": team,
				"bow": bow_world, "dot": dotv, "ok": ok,
			})

	print("──────────────────────────────────────────────────────────────")
	print("舰艏朝对面：%d / %d" % [checked - bad.size(), checked])
	if bad.is_empty():
		print("★ 全部正确 —— 布阵阶段全员朝敌方 ✔")
	else:
		print("✗ 不达标：%s" % ", ".join(bad))


func _first_mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n as MeshInstance3D
	for c in n.get_children():
		var got := _first_mesh(c)
		if got != null:
			return got
	return null


func _write_report() -> void:
	var lines := PackedStringArray()
	lines.append("53 轮 · 布阵阶段实机朝向")
	for r in _rows:
		lines.append("%s team=%d dot=%.4f ok=%s" % [
				r["id"], r["team"], r["dot"], r["ok"]])
	var f := FileAccess.open(OUT_DIR + "/report.txt", FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(lines))
		f.close()
