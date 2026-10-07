extends Node
## ══════════════════════════════════════════════════════════════════
##  红线 46 **验收**：舰艏 ≡ 前进方向 ≡ 速度方向（全库 52 艘 × 4 个航向）
## ══════════════════════════════════════════════════════════════════
##
##  这是「船头必须朝着前进方向」这条要求的**唯一**可复现验收口。
##  它不看你我怎么说，只看一个数：`bow_world · velocity.normalized()`。
##
## ── 为什么必须造真的视觉节点来测 ──────────────────────────────────
##  红线 40：取证探针**必须调真代码**（或对拍）。本探针走的是
##  `eve_ship_visual.gd` 的**同一条路**：
##      `new()` → `set("ship")` → `_build_hull_model()` → `sync_from_body()`
##  与 `probe_ship_views.gd::_build_via_game()` 同源（那一处已证明这条路
##  能读到「工程里真的是这个朝向」）。自己复刻一遍算式的话，
##  一旦工程侧改了**它照出来的数仍然是对的** ⇒ 探针失去取证价值。
##
## ── 判据 ──────────────────────────────────────────────────────────
##    · `bow · v̂ ≥ 0.999`  ⇒ 舰艏严格等于前进方向（收敛后应当**精确**为 1）
##    · `up · (0,1,0) ≥ 0.999` ⇒ 船没有侧翻/倒扣
##  两个都过才算过。**少一个都说明姿态矩阵被污染了。**
##
## ⚠️⚠️ **53 轮修正：`up` 判据恢复成 `up · UP ≥ +0.999`（背朝 +Y）**。
##  48 轮曾把期望翻成 `≤ −0.999`，理由是「用户报肚皮朝天 ⇒ 生产侧加全局滚转
##  `R_z(180°)` ⇒ 几何背轴自然指向 −Y」。53 轮用 `tools/probe_roll53.tscn`
##  做了「含滚转 / 不含滚转」两栏全库普查（**全部调生产函数**）：
##
##      合计 52 艘
##        含滚转（true）      不达标：52   ← 52/52 船背朝 −Y
##        不含滚转（false）    不达标： 0   ← 52/52 舰艏朝敌 + 船背朝天
##
##  ⇒ 那刀 `GLOBAL_ROLL_180` **本身就是病**（把 52 艘本来正确的姿态全翻过去），
##    已改回 `false`。因此本探针的 `up` 期望也必须回到 `+0.999`。
##  ⚠️ 两者必须同步：改 `GLOBAL_ROLL_180` 而不改本判据 ⇒ 全库 52 艘假红。
##  ⚠️ `bow` 判据（`dot ≥ 0.999`）两轮都成立 —— 滚转是绕机身长轴的，
##     本来就不该动舰艏方位（红线 37）。
##
## ── 为什么要用 slerp 迭代很多帧 ────────────────────────────────────
##  朝向是**平滑跟随**的（FACING_LERP = 0.12），单帧只走 12%。
##  判「稳态是否严格相等」必须等它收敛：迭代 N 次后残差 ≈ 0.88^N。
##  150 次 ⇒ 残差 ~1e-9，远低于打印精度。
##  ⚠️ 只看 1 帧会误判成"船头没对上" —— 那只是**还没转过去**。
##
##  跑法：
##    "C:/godot/Godot_v4.7.1-stable_win64_console.exe" --headless \
##      --path "F:/evezzq/eve自走棋918" --quit-after 9000 \
##      res://tools/probe_bow_align.tscn
##  产物：user://bow_align_report.txt

const SHIP_SCRIPT := preload("res://scripts/visual/eve_ship_visual.gd")
const YAW := preload("res://scripts/data/eve_ship_yaw.gd")
const INDEX := preload("res://scripts/data/eve_ship_asset_index.gd")

## 四个航向（含一个斜向，专抓"只对齐了轴向特例"的假通过）
const DIRS: Array[Vector3] = [
	Vector3(0.0, 0.0, -1.0),   # 朝敌
	Vector3(0.0, 0.0, 1.0),    # 背敌（撤退）
	Vector3(1.0, 0.0, 0.0),    # 朝右
	Vector3(0.6, 0.0, -0.8),   # 斜向（非 90° 倍数，最能抓错）
]
const DIR_NAMES: Array[String] = ["朝敌-Z", "背敌+Z", "朝右+X", "斜向"]

## ⚠️⚠️ **53 轮：收敛帧数必须按闸门上限算，不能拍一个数** ⚠️⚠️
##  本探针用**固定 `delta = 1/60`** 调 `sync_from_body`，而生产里有**角速度闸门**
##  `facing_max_step_deg(1/60) = 90/60 = 1.5°`（2 的存在见生产注释：
##  `Quaternion.angle_to` 是半角，53 轮已乘 2 修正）。
##  ⇒ 最坏航向要转 **180°**（朝敌 → 背敌）⇒ 至少 `180 / 1.5 = 120` 帧。
##  旧的 `150` 是**卡着临界**的：一开始就不够稳（能过是余量凑的）。
##  53 轮把闸门修正成真实角度后，放行量减半 ⇒ 需要 **240 帧**。
##  取 **400** 留足余量（收敛是几何级的，多跑只是多花几十毫秒）。
##  ⚠️ 别用"跑到收敛为止"的 while：本函数是纯数学迭代，不依赖渲染帧，
##     帧数可预测就够了 —— 变量更少，读数更好解释。
const SETTLE_FRAMES := 400

var _lines: Array[String] = []


func _ready() -> void:
	var worst_dot := 1.0
	var worst_up := 1.0
	var worst_id := ""
	var n_bad := 0

	_lines.append("══════════════════════════════════════════════════════════════════")
	_lines.append("  红线 46 验收：舰艏 ≡ 速度方向（52 艘 × 4 航向，slerp 收敛后）")
	_lines.append("══════════════════════════════════════════════════════════════════")
	_lines.append("")
	_lines.append("  %-13s %8s %8s %8s %8s  %8s %8s %8s %8s  %s" % [
		"id", "朝敌", "背敌", "朝右", "斜向", "上·UP", "上·UP", "上·UP", "上·UP", "判定"])

	for ship in INDEX.all():
		var sid := StringName(ship.id)
		var r := _test(sid)
		if r.is_empty():
			_lines.append("  %-13s  —— 无模型（走占位体路径，本探针不覆盖）" % String(sid))
			continue
		var dots: Array = r["dots"]
		var ups: Array = r["ups"]
		var ok := true
		for i in DIRS.size():
			# ⚠️ 53 轮：up 期望值恢复 +1（`GLOBAL_ROLL_180` 已改回 false）—— 详见文件头
			if float(dots[i]) < 0.999 or float(ups[i]) < 0.999:
				ok = false
			worst_dot = minf(worst_dot, float(dots[i]))
			worst_up = minf(worst_up, float(ups[i]))
			if float(dots[i]) < worst_dot or worst_id == "":
				pass
		if not ok:
			n_bad += 1
			worst_id = String(sid)
		_lines.append("  %-13s %8.4f %8.4f %8.4f %8.4f  %8.4f %8.4f %8.4f %8.4f  %s" % [
			String(sid),
			float(dots[0]), float(dots[1]), float(dots[2]), float(dots[3]),
			float(ups[0]), float(ups[1]), float(ups[2]), float(ups[3]),
			("✅" if ok else "❌")])

	_lines.append("")
	_lines.append("── 汇总 ──")
	_lines.append("  不达标：%d 艘（%s）" % [n_bad, worst_id if n_bad > 0 else "无"])
	_lines.append("  全库最差 bow·v̂ = %.6f   （1.0 = 舰艏与前进方向**严格同向**）" % worst_dot)
	_lines.append("  全库最差 up·UP = %.6f   （53 轮口径：**+1.0** = 几何背轴朝天 = 全局滚转已关闭）" % worst_up)
	_lines.append("  ⚠️ 若这条变负 ⇒ `GLOBAL_ROLL_180` 被改回 true 了（52 艘全肚皮朝天）")
	_lines.append("")
	_lines.append(n_bad == 0)

	var f := FileAccess.open("user://bow_align_report.txt", FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(_lines))
		f.close()
		print("[BOW-ALIGN] 报告已写 user://bow_align_report.txt")
	for s in _lines:
		print(s)
	get_tree().quit(0)


func _test(sid: StringName) -> Dictionary:
	var vis: Variant = SHIP_SCRIPT.new()
	var sh := EveShip.new()
	sh.ship_key = sid
	vis.set("ship", sh)
	var hr := Node3D.new()
	hr.name = "Hull"
	vis.set("hull_root", hr)
	vis.add_child(hr)

	var model := EveShipModel.instantiate(sid)
	if model == null:
		vis.free()
		return {}
	vis.call("_build_hull_model", model)

	# 模型空间的舰艏 / 船背 —— **从标定表读**，不在探针里复刻
	var mb := model.basis.orthonormalized()   # ⚠️ 含缩放，必须正交化（红线 41）
	var local_bow := (mb * YAW.bow_axis(sid)).normalized()
	var local_up := (mb * YAW.up_axis(sid)).normalized()

	var dots: Array = []
	var ups: Array = []
	for d in DIRS:
		var body := EveDestinyMotion.Body.new()
		body.position = Vector3.ZERO
		body.velocity = d * 100.0   # 100 m/s，远大于 MOVE_EPS(1)
		for _i in SETTLE_FRAMES:
			# ⚠️ 传 alive=false：跳过 _update_bars（那需要真实的 max_hp 字典），
			#    而 quaternion 在那之前就已经写好了 ⇒ 不影响本探针测的东西。
			vis.call("sync_from_body", body, false)
		var q: Quaternion = vis.get("quaternion")
		dots.append((q * local_bow).normalized().dot(d.normalized()))
		ups.append((q * local_up).normalized().dot(Vector3.UP))

	vis.free()
	return {"dots": dots, "ups": ups}
