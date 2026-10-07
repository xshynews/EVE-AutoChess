extends Node
## 第二十二轮：舰艏轴（bow0）全库审计 —— 「船头必须朝前进方向」开工基线
##
## ══════════════════════════════════════════════════════════════════
##  为什么需要这张表
## ══════════════════════════════════════════════════════════════════
##  用户（2026-09-26 22轮原话）：「船头明确需要朝着前进方向 …… 多大代价都可以」。
##
##  现行 `sync_from_body` 只有一个自由度：`rotation.y`（绕世界 Y 的偏航）。
##  它**只能**把「已经在水平面里的舰艏轴」转到任意水平方向；
##  一旦某艘船的舰艏轴 **不在水平面**（bow0.y ≠ 0），
##  R_y 转**任何角度**都改不动它的 Y 分量 ⇒ **几何死锁**，
##  加 +π 也好、减 π 也好，一律无解（不报错，只是船头永远指着别处）。
##
##  ⇒ 开工第一件事：**把「谁在死锁里」量化出来**，别再靠猜。
##
## ══════════════════════════════════════════════════════════════════
##  口径（**真代码口径**，与 eve_ship_visual._build_hull_model 逐字同源）
## ══════════════════════════════════════════════════════════════════
##      base = R_y(MODEL_YAW_FIX + extra_yaw(id)) * axis_remap(id)
##      bow0 = base * (1,0,0)            # 舰艏 = 模型 +X（glb 长轴约定）
##      up0  = base * M^-1 * (0,1,0)     # 上 = spec 里映射到世界 +Y 的那根模型轴
##
##  ⚠️ `axis_remap()` 的真实语义（**以代码为准，注释里那句"世界X←模型"是错的**）：
##      返回的 Basis 的**第 i 列** = 模型 i 轴 → 世界方向 = spec 的第 i 个 token。
##      对 diag 型 spec（如 `-X,+Y,-Z`）两种读法恰好等价，所以 30+ 艘主流船没暴露问题；
##      对非 diag 型（myrmidon / tristan / catalyst / algos …）两者**相差一个转置**，
##      也就是**完全相反**的姿态 —— 这正是那批船改了 14 轮还改不对的病根。
##
## ══════════════════════════════════════════════════════════════════
##  判据
## ══════════════════════════════════════════════════════════════════
##    · `|bow0.y| > 0.01`        ⇒ 舰艏不在水平面 ⇒ **单 yaw 永远修不好**（死锁）
##    · `bow0 · (0,0,-1) < 0`    ⇒ 静止时背对敌人（敌人在世界 −Z）
##    · `up0 · (0,1,0) < 0.99`   ⇒ 船不是「背朝天」（侧躺 / 倒扣）
##
##  跑法：
##    "C:/godot/Godot_v4.7.1-stable_win64_console.exe" --headless \
##      --path "F:/evezzq/eve自走棋918" --quit-after 5000 \
##      res://tools/probe_bow_axis.tscn
##  产物：user://bow_axis_report.txt

const INDEX := preload("res://scripts/data/eve_ship_asset_index.gd")
const YAW := preload("res://scripts/data/eve_ship_yaw.gd")
## ★ 48 轮：改成直接调生产算式（红线 40：不许自己复刻）。
##   ⚠️ 本探针此前一直手写 `MODEL_YAW_FIX(−90°)·M`，而 47 轮已把
##   `MODEL_YAW_FIX` 删除并吸收进 `AXIS_REMAP` 表、也没乘 `mesh_rot`
##   ⇒ 输出长期是**错的口径**（48 轮实测：52 艘里 33 艘被误报「背敌」、
##     slasher 被误报「死锁」，全是算式漂移，不是数据问题）。
const ZPS := preload("res://scripts/visual/eve_ship_visual.gd")

const ENEMY_DIR := Vector3(0.0, 0.0, -1.0)
const WORLD_UP := Vector3(0.0, 1.0, 0.0)

var _lines: Array[String] = []


func _ready() -> void:
	var all: Array = INDEX.all()
	all.sort_custom(func(a, b): return String(a.id) < String(b.id))

	var n_dead := 0
	var n_away := 0
	var n_tilt := 0
	var rows: Array = []

	for ship in all:
		var id := StringName(ship.id)
		# ★ 48 轮：直接调生产算式（含 `R_y` + `M` + `mesh_rot`）。
		#   用**静态链**（不含 48 轮全局滚转）—— 本探针守的是「标定对不对」，
		#   滚转是下游全局修正，会把 `up` 全体翻成 −Y 而掩盖标定本身的问题。
		var base: Basis = ZPS.zero_pose_basis_no_roll(id)

		# 舰艏轴 / 船背轴 —— **都从标定表读**（唯一真相源），不许在这里硬写 (1,0,0)。
		# ⚠️ 红线 40：取证探针必须调真代码；自己复刻算式漂了以后，图**仍然看着对**。
		var bow_local: Vector3 = YAW.bow_axis(id)          # 模型空间舰艏轴（默认 +X）
		var up_local: Vector3 = YAW.up_axis(id)            # 模型空间船背轴（由 spec 反解）
		var bow0 := (base * bow_local).normalized()
		var up0 := (base * up_local).normalized()

		var vert := absf(bow0.y)
		var face := bow0.dot(ENEMY_DIR)
		# ⚠️ 28 轮：up 不再参与判定。EVE 里有横着飞/竖着飞的船（burst/myrmidon …），
		#    它们的"机背"在世界坐标里是 ±X 或 ±Z，不是 +Y。强制 up=+Y 会骗过探针
		#    （探针报 ok，但 EVE 玩家看着不对）—— 改写：up 不参与。
		var tilt := 0.0  # 保留字段兼容输出但不再失败

		var is_dead := vert > 0.01
		var is_away := face < 0.0
		# `tilt` 不再视为异常（is_tilt 恒 false）
		var is_tilt := false
		if is_dead:
			n_dead += 1
		if is_away:
			n_away += 1
		# if is_tilt:  # 28 轮改：up 不参与判定
		#     n_tilt += 1

		rows.append({
			"id": String(id),
			"spec": String(YAW.AXIS_REMAP.get(id, "·(无remap)")),
			"flip": String(id) in YAW.FLIP,
			"bow0": bow0,
			"up0": up0,
			"bow": YAW._axis_name(bow_local),
			"vert": vert,
			"face": face,
			"tilt": tilt,
			"dead": is_dead,
			"away": is_away,
			"tilted": is_tilt,
		})

	_lines.append("══════════════════════════════════════════════════════════════════")
	_lines.append("  52 艘舰艏轴审计 —— 「船头必须朝前进方向」开工基线")
	_lines.append("  bow0 = EveShipVisual.zero_pose_basis_no_roll(id) · bow_local（48 轮：真代码口径）")
	_lines.append("     = R_y(extra_yaw) · AXIS_REMAP · mesh_rot（不含 48 轮全局滚转）")
	_lines.append("  dead = |bow0.y|>0.01 ⇒ 单 yaw 几何死锁 ，必须换完整旋转对齐")
	_lines.append("══════════════════════════════════════════════════════════════════")
	_lines.append("")
	_lines.append("总计 %d 艘： 死锁 %d · 背敌 %d · 上轴不正 0（28 轮改：up 不再参与判定）" % [all.size(), n_dead, n_away])
	_lines.append("")
	_lines.append("  %-13s %-14s %-4s %-4s %-22s %8s %8s %8s  %s" % [
		"id", "AXIS_REMAP", "FLIP", "BOW", "bow0(静止舰艏)", "bow0.y", "朝敌", "上轴·UP", "状态"])
	for r in rows:
		var b: Vector3 = r["bow0"]
		var flags: Array[String] = []
		if bool(r["dead"]):
			flags.append("★死锁")
		if bool(r["away"]):
			flags.append("背敌")
		if bool(r["tilted"]):
			flags.append("侧躺")
		if flags.is_empty():
			flags.append("ok")
		_lines.append("  %-13s %-14s %-4s %-4s  (%+.3f,%+.3f,%+.3f) %8.3f %8.3f %8.3f  %s" % [
			String(r["id"]), String(r["spec"]), ("Y" if bool(r["flip"]) else "·"),
			String(r["bow"]),
			b.x, b.y, b.z, float(r["vert"]), float(r["face"]), float(r["tilt"]),
			" ".join(flags)])

	var f := FileAccess.open("user://bow_axis_report.txt", FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(_lines))
		f.close()
		print("[BOW-AXIS] 报告已写 user://bow_axis_report.txt")
	for s in _lines:
		print(s)
	get_tree().quit(0)
