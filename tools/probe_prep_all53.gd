extends Node

## ★★ 53 轮（第四版）· **全库 52 艘 · 走真实拖拽入口 `deploy_from_bench`** 的布阵姿态
##
## ══════════════════════════════════════════════════════════════════
##  为什么必须写这个（上一版探针的盲区）
## ══════════════════════════════════════════════════════════════════
##  53 轮第三版我用 `probe_prep53` 报「14/14 全对」，但用户实机仍然看到：
##      「大部分船朝向玩家，而部分特殊的船朝向则是乱七八糟」
##  ⇒ 那个探针**只测了 12 艘**（`WANT` 列表），**全库 52 艘里的绝大多数从未被测过**。
##    12 艘全对 ⇒ 我宣布"修好了"；剩下 40 艘怎么样，**没人知道**。
##
##  而且它走的是**另一条路**：直接改 `run.field` 再手动调 `_respawn_own_fleet()`，
##  绕过了 `_refresh_run_ui` 里的守卫（`_busy` / `_drag` / 签名比对）。
##  用户实际走的是 **UI 拖拽 → `_end_drag` → `run.deploy_from_bench()`**。
##
## ══════════════════════════════════════════════════════════════════
##  本探针干什么
## ══════════════════════════════════════════════════════════════════
##  ① 起真实 `battle_scene.tscn`；
##  ② 把**全库 52 艘**按 `field_limit()` 分批，每批走**真实入口**
##     `run.deploy_from_bench(index, row, col)`（拖拽唯一入口，红线 8）；
##  ③ 每批之后读**引擎渲染真值** `mesh.global_transform.basis`（红线 40）；
##  ④ 报每艘的 `bow·敌` 与 `up·天`，并**统计不合格名单**。
##
##  ⚠️ 判据必须**成对**（53 轮 §22.9 的血泪）：只测 `bow` 不够，
##     52 艘肚皮朝天时 `bow·敌` 照样 1.000 ⇒ 必须**同时**测 `up·天`。
##
##  用法：
##      Godot_v4.7.1-stable_win64_console.exe --headless \
##          --path "<工程>" --quit-after 3000 \
##          res://tools/probe_prep_all53.tscn -- --out "<路径>"

const YAW := preload("res://scripts/data/eve_ship_yaw.gd")
const INDEX := preload("res://scripts/data/eve_ship_asset_index.gd")

var _scene: Node = null
var _lines: PackedStringArray = []
var _out_path := ""
## id → [bow·敌, up·天]
var _res: Dictionary = {}


func _ready() -> void:
	var ua := OS.get_cmdline_user_args()
	for t in ua:
		if t.begins_with("--out="):
			_out_path = t.substr(6)

	var ps: PackedScene = load("res://scenes/battle_scene.tscn")
	if ps == null:
		print("✗ 载入失败")
		get_tree().quit()
		return
	_scene = ps.instantiate()
	add_child(_scene)
	await get_tree().process_frame
	await get_tree().process_frame
	_run()


func _run() -> void:
	var run: Variant = _scene.get("run")
	if run == null:
		print("✗ 拿不到 run")
		get_tree().quit()
		return

	_p("══════════════════════════════════════════════════════════════")
	_p("  53e · 全库 52 艘 · 走真实拖拽入口 deploy_from_bench() 的布阵姿态")
	_p("══════════════════════════════════════════════════════════════")
	_p("  判据（**成对**，§22.9）：bow·敌 ≥ 0.94 **且** up·天 ≥ 0.94")
	_p("")

	# 全库 id 列表
	var all_ids: Array[String] = []
	for s in INDEX.all():
		all_ids.append(String(s.id))
	all_ids.sort()

	var limit := int(run.call("field_limit"))
	_p("  field_limit = %d · 全库 %d 艘 ⇒ 分 %d 批" % [
			limit, all_ids.size(), ceili(float(all_ids.size()) / float(maxi(1, limit)))])

	var batch_i := 0
	var from := 0
	while from < all_ids.size():
		var batch: Array[String] = []
		var to := mini(from + maxi(1, limit), all_ids.size())
		for i in range(from, to):
			batch.append(all_ids[i])
		batch_i += 1
		_p("")
		_p("── 第 %d 批（%d 艘）──" % [batch_i, batch.size()])

		# 清空场上与备战席
		run.get("bench").clear()
		run.get("field").clear()
		run.emit_signal("changed")
		await get_tree().process_frame

		# 灌进备战席
		for sid in batch:
			run.get("bench").append({"ship_key": StringName(sid), "star": 1, "cost": 1})
		run.emit_signal("changed")
		await get_tree().process_frame

		# ★ 走**真实入口**逐艘部署（备战席 index 0 会被移走 ⇒ 每艘都取 index 0）
		var placed := 0
		for sid in batch:
			var bench_now: Array = run.get("bench")
			if bench_now.is_empty():
				break
			var ok: bool = _deploy_one(run, sid)
			if not ok:
				_p("    ⚠ %s 部署失败（已跳过）" % sid)
				# 失败就把它从备战席移除，避免卡住后面的
				run.get("bench").remove_at(0)
				continue
			placed += 1
		await get_tree().process_frame
		await get_tree().process_frame

		_measure(batch)
		from = to

	_report()
	if _out_path != "":
		var f := FileAccess.open(_out_path, FileAccess.WRITE)
		if f != null:
			f.store_string("\n".join(_lines))
			f.close()
			print("")
			print("[probe_prep_all53] 报告已写：%s" % _out_path)
	get_tree().quit()


## 从备战席找 `sid` 并走真实入口部署到己方区第一个空格
func _deploy_one(run: Variant, sid: String) -> bool:
	var bench: Array = run.get("bench")
	var idx := -1
	for i in bench.size():
		if String(bench[i].get("ship_key", &"")) == sid:
			idx = i
			break
	if idx < 0:
		return false

	# 己方区行范围：从 `own_zone_row0()` 到 ROWS-1；列取 0..COLS-1
	var board: Variant = _scene.get("arena").get("board")
	var r0 := 0
	var rows := 11
	var cols := 8
	if board != null:
		r0 = int(board.call("own_zone_row0"))
		rows = int(board.get("ROWS"))
		cols = int(board.get("COLS"))

	for r in range(r0, rows):
		for c in cols:
			var res: Dictionary = run.call("deploy_from_bench", idx, r, c)
			if bool(res.get("ok", false)):
				return true
	return false


func _measure(batch: Array[String]) -> void:
	var arena: Node = _scene.get("arena")
	if arena == null:
		return
	# ⚠️ 布阵阶段 `sim.ships` 是空的 —— 我方舰队挂在场景的 `_own_ships` 上
	#    （`sim` 只在 `start_battle()` 之后才有内容）。本探针跑的是布阵态。
	var own: Array = _scene.get("_own_ships")
	if own.is_empty():
		_p("    ⚠ _own_ships 为空")
		return
	for ship in own:
		var sid := String(ship.ship_key)
		if not batch.has(sid):
			continue
		var vis: Node3D = arena.get_ship_visual(ship.id)
		if vis == null:
			_p("    %-12s —— 无视觉节点" % sid)
			continue
		var m := _first_mesh(vis)
		if m == null:
			_p("    %-12s —— 无网格" % sid)
			continue
		# ★ 引擎渲染真值（红线 40：不自己乘矩阵）
		var gb := m.global_transform.basis.orthonormalized()
		var bow := (gb * YAW.bow_axis(StringName(sid))).normalized()
		var up := (gb * YAW.up_axis(StringName(sid))).normalized()
		var d_bow := bow.dot(Vector3(0, 0, -1))
		var d_up := up.dot(Vector3(0, 1, 0))
		_res[sid] = [d_bow, d_up]
		var bad := "  ← ✗ 不合格"
		if d_bow >= 0.94 and d_up >= 0.94:
			bad = ""
		_p("    %-12s bow·敌=%+.3f  up·天=%+.3f  舰艏%s%s" % [
				sid, d_bow, d_up, _v(bow), bad])
		# ★ 56 轮：**与表无关**的原始轴向 —— 用来判「姿态到底跟着哪个字段动」。
		#   若只翻 `SHIP_AXES.bow` 而这三行不变 ⇒ 说明实机姿态不读 `bow` 字段。
		_p("       RAW 模型+Z端→%s  模型-Z端→%s  模型+Y端→%s" % [
				_v((gb * Vector3(0, 0, 1)).normalized()),
				_v((gb * Vector3(0, 0, -1)).normalized()),
				_v((gb * Vector3(0, 1, 0)).normalized())])
		# ★★ 代码自定锚（`_build_placeholder_hull` 注释：**占位体舰艏 = hull_root 局部 +Z**）
		#    ⇒ `hull_root` 局部 +Z 的**世界方向**就是「舰艏指向」，`·敌` 应为 +1。
		#    这条**不经过 `SHIP_AXES`**，是真正能判"船朝哪"的判据。
		var hr: Variant = vis.get("hull_root")
		if hr is Node3D:
			var nose := ((hr as Node3D).global_transform.basis.orthonormalized()
					* Vector3(0, 0, 1)).normalized()
			_p("       舰艏(代码定义 hull_root+Z)→%s  ·敌=%+.3f" % [
					_v(nose), nose.dot(Vector3(0, 0, -1))])


func _report() -> void:
	var bad_bow: Array[String] = []
	var bad_up: Array[String] = []
	var bad_both: Array[String] = []
	var ok_n := 0
	for k in _res.keys():
		var r: Array = _res[k]
		var db := float(r[0])
		var du := float(r[1])
		var fb := db < 0.94
		var fu := du < 0.94
		if fb and fu:
			bad_both.append(k)
		elif fb:
			bad_bow.append(k)
		elif fu:
			bad_up.append(k)
		else:
			ok_n += 1

	_p("")
	_p("══════════════════════════════════════════════════════════════")
	_p("  合计实测 %d 艘" % _res.size())
	_p("    ✅ 合格（bow 朝敌 + up 朝天）：%d" % ok_n)
	_p("    ✗  舰艏不朝敌：%d 艘" % bad_bow.size())
	if not bad_bow.is_empty():
		_p("       %s" % ", ".join(bad_bow))
	_p("    ✗  船背不朝天（肚皮朝天/侧躺）：%d 艘" % bad_up.size())
	if not bad_up.is_empty():
		_p("       %s" % ", ".join(bad_up))
	_p("    ✗  两项都不合格：%d 艘" % bad_both.size())
	if not bad_both.is_empty():
		_p("       %s" % ", ".join(bad_both))
	_p("══════════════════════════════════════════════════════════════")


func _p(s: String) -> void:
	print(s)
	_lines.append(s)


func _first_mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n as MeshInstance3D
	for c in n.get_children():
		var got := _first_mesh(c)
		if got != null:
			return got
	return null


func _v(v: Vector3) -> String:
	return "(%.2f,%+.2f,%+.2f)" % [v.x, v.y, v.z]
