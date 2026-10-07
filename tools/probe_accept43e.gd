extends Node
## 44 轮验收护栏：**全库 52 艘静止姿态 = 舰艏朝敌 + 船背朝天**。
##
## ═══ 期望值来源（红线 40：期望值必须**独立**，不许从被测方反推）═══
##   · `deploy_enemy_z = −45`（我方 +45）⇒ **敌人 = 世界 −Z**（红线 42，工程事实）
##   · 相机在我方背后朝 −Z 看 ⇒ 「船背朝天」= 世界 **+Y**
##   ⇒ 期望 `zero_pose_basis(id)·bow = (0,0,−1)`、`zero_pose_basis(id)·up = (0,1,0)`
##
## ═══ 为什么必须存在（43e 的教训）═══
##   43e 把 52 艘按用户姿势表落盘后，**只有 `validate()` 自洽**是远远不够的：
##   `validate()` 查的是「表内部一致」（正交 / det=+1 / 两表交叉），
##   它**不查**「算出来的世界方向是不是朝敌」——
##   若把 SHIP_AXES 与 AXIS_REMAP 同时按同一个错口径写，validate 全绿、实机全反。
##   本条护栏直接落到**游戏真实算式**（`_build_hull_model` 里那一行）上。
##
## ⚠️⚠️ 47 轮改写（**这是一次"旧探头拖后腿"的实例**）：
##   本探头原本自带一份算式 `R_y(−90°+θ)·M·bow`，是 44 轮当时的正确口径。
##   47 轮把 `MODEL_YAW_FIX(−90°)` 删除、吸收进 M 表，并把 `mesh_rot` 提升到根节点
##   ⇒ 那份算式**同时错了两处**（多减 90°、漏乘 mesh_rot），实测 52/52 全报异常。
##   而同一个落表状态下，走生产算式的 `verify_run` 是 **384/0 全绿**。
##   ⇒ 教训：**任何"独立复刻的算式"都是一份会过期的副本**（红线 40 的镜像坑）。
##      现在这里**直接调生产函数** `EveShipVisual.zero_pose_basis()`，
##      期望值仍独立写死（`(0,0,−1)` / `(0,1,0)` 来自红 42 的工程事实）。
##
## ⚠️ 44 轮踩过的坑：本探针的**手算对照**必须用 Godot 的 `Basis` **列组合**语义
##   （`M·v = x*v.x + y*v.y + z*v.z`）。若在 Python/纸上按「行」读 spec，
##   会得到**正好相反**的结论（44 轮初判「48/52 背敌」就是这一条坑）。
##   spec 的真实语义：第 i 个 token = **Basis 构造的第 i 个参数**（= 第 i 列）。
const YAW := preload("res://scripts/data/eve_ship_yaw.gd")
const IDX := preload("res://scripts/data/eve_ship_asset_index.gd")

## 生产算式入口（`load()` + `call()`：静态函数要走 `.call(name, ...)`）。
var _ZP: Variant = load("res://scripts/visual/eve_ship_visual.gd")

func _ready() -> void:
	print("═══ 44 轮验收（真代码 · 静态链口径 · 期望 bow=(0,0,−1) up=(0,1,0)）═══")
	# ★ 47 轮：先踢一脚 provider，否则 `validate()` 的 ⑧⑨ 会退化成单位阵口径（假失败）。
	_ZP.call("mesh_rot_of", &"abaddon")
	var probs := YAW.validate()
	print("validate 问题数 = %d" % probs.size())
	for p in probs:
		print("  · " + String(p))
	var bad: PackedStringArray = PackedStringArray()
	var n := 0
	for s in IDX.all():
		n += 1
		var sid := StringName(s.id)
		# 47 轮：算式 = **生产函数**（`R_y(extra)·M·mesh_rot`，−90° 已吸收进 M）
		# ⚠️ 48 轮：改用**静态链** `zero_pose_basis_no_roll` —— 本验收守的是
		#    「用户标定有没有被正确摆出来」，全局滚转是下游统一修正
		#    （它会把 up 全体翻成 −Y，若含进来就掩盖标定本身的问题）。
		#    滚转本身由 `verify_run` 的 48 轮锚点逐艘守。
		var rm: Basis = _ZP.call("zero_pose_basis_no_roll", sid) as Basis
		var bw: Vector3 = (rm * YAW.bow_axis(sid)).normalized()
		var uw: Vector3 = (rm * YAW.up_axis(sid)).normalized()
		var db: float = bw.dot(Vector3(0, 0, -1))
		var du: float = uw.dot(Vector3(0, 1, 0))
		if db < 0.999 or du < 0.999:
			bad.append("%s(bow·朝敌=%.4f up·天=%.4f)" % [String(s.id), db, du])
	print("--- 全库 %d 艘：不合格 %d ---" % [n, bad.size()])
	for b in bad:
		print("  ✗ " + b)
	if bad.is_empty() and probs.is_empty():
		print("★★★ 44 轮验收通过：52/52 舰艏朝敌 + 船背朝天（静态链） + validate 干净 ★★★")
	else:
		print("✗✗✗ 44 轮验收未过：请见上方明细 ✗✗✗")
	get_tree().quit()
