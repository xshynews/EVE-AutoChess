extends Node
## ══════════════════════════════════════════════════════════════════════
##  47 轮 · **全库 AXIS_REMAP 重算器**
## ══════════════════════════════════════════════════════════════════════
##
## ── 为什么必须重算 ═══════════════════════════════════════════════════
##  `AXIS_REMAP`（M）是 39~44 轮在「**没有 mesh_rot**」的旧空间里标定的：
##  那时游戏算式是 `world = R_y(yaw) · M · bow_model`，
##  现在变成 `world = R_y(yaw) · M · mesh_rot · bow_model`（47 轮修正）。
##  ⇒ M 的**底座**变了 ⇒ 旧的 M 全部失效（工具自检 52/52 抓到了）。
##
## ── 重算口径 ════════════════════════════════════════════════════════
##  目标（红线 42/46）：零姿态下舰艏必须落 **−Z**（朝敌）、船背落 **+Y**。
##  已知（人工真值）：`SHIP_AXES[id]` 给出**网格空间**的 bow/up 轴。
##
##  求 M，使得：
##      `R_y(MODEL_YAW_FIX + extra) · M · mesh_rot · bow  = −Z`
##      `R_y(MODEL_YAW_FIX + extra) · M · mesh_rot · up   = +Y`
##
##  ⚠️ `MODEL_YAW_FIX = −90°` 是**旧的全局常量**，它本身就是为了"把长轴 +X
##     转到 +Z"而设的。47 轮之后 mesh_rot 已经把这层信息显式化了 ⇒
##     `MODEL_YAW_FIX` 应当**归零**，否则等于把同一件事表达两次
##     （红线 27：同一自由度只许一处 —— 这里正是同一个坑）。
##
##  所以重算的目标式（干净形式）：
##      `M · mesh_rot · bow = −Z`  且  `M · mesh_rot · up = +Y`
##  解：`M = Basis(−Z, +Y, +X) · (mesh_rot · [bow, up, side])⁻¹`
##      其中 [bow, up, side] 是把三个模型轴排成列。
##
##  产出 → `user://bow_calib/remap47.txt`，格式 = GDScript 表项，便于人工粘贴。
##
## 跑法：
##   `--headless --path <工程> --quit-after 400 res://tools/probe_remap47.tscn`
const YAW := preload("res://scripts/data/eve_ship_yaw.gd")

## 枚举用的 6 个轴向 token。
const AXT := ["+X", "-X", "+Y", "-Y", "+Z", "-Z"]

## ⚠️ 47 轮：**不再硬写 id 列表**（红线 1：禁"第几行/第几个文件"式取法，
##    也禁把清单复制成第二份真相源）。直接问表要全库主键。
static func all_ids() -> Array:
	var out: Array = []
	var keys := YAW.AXIS_REMAP.keys()
	for k in keys:
		out.append(String(k))
	out.sort()
	return out

func _ready() -> void:
	print("═══ 47 轮 · AXIS_REMAP 重算（mesh_rot 提升后）═══")
	# 标准基：舰艏→−Z · 船背→+Y · 侧向→+X
	var TARGET := Basis(
			Vector3(0, 0, -1),   # 列0 = 目标 bow 方向
			Vector3(0, 1, 0),    # 列1 = 目标 up 方向
			Vector3(1, 0, 0))    # 列2 = 目标 side 方向
	var lines: Array[String] = []
	var n := 0
	var missing: Array[String] = []
	for id in all_ids():
		var sid := StringName(id)
		var mr: Basis = EveShipVisual.mesh_rot_of(sid)
		var bow: Vector3 = YAW.bow_axis(sid)
		var up: Vector3 = YAW.up_axis(sid)
		# 用**同一个模型实例**判定是否能加载，避免缓存与真实不符
		var probe := EveShipModel.instantiate(sid, false)
		if probe == null:
			missing.append(id)
			continue
		probe.free()
		# ★★ 47 轮最终方案：**穷举 48 个 spec，选端到端真的把 bow 送到 −Z 的**。
		#
		# 为什么不靠公式：推导"要取行还是取列"连续错了 4 次（44 轮同款），
		# 每次都表现为**不报错的倒飞**。但判据本身极硬：
		#     `R_y(extra)·parse(spec)·mesh_rot·bow == −Z`
		# ⇒ 直接枚举，让 Godot 自己选。48 候选 × 52 艘，本地毫秒级，**零推导风险**。
		#
		# ⚠️⚠️ 48 轮：**第三种列加 `-up`**。
		#   起因：用户实机报「船全部肚皮朝天」⇒ 查到 `SHIP_AXES` 里 19 艘的 `up`
		#   落在了**宽度轴**上（出厂坐标系里最薄的那根轴才是高度轴）。
		#   改完 up 之后，**只翻 up 符号**的候选必须也在备选里 ——
		#   因为「保持舰艏不动、把船翻正」在几何上正是 `bow 不变 / up 翻号`。
		#   ⚠️ 但**不能只加 `-up` 就完事**：判据里 `side = bow × up` 会跟着翻，
		#     第三行符号自由 ⇒ 仍要按三条判据一起筛（下面 `_solve_spec` 已含 side）。
		#   ⚠️ **不许直接把 `AXIS_REMAP` 整体换成 `-up` 版**：那样会把已经正确的船
		#     （up 本就在高度轴上、且只有 2 个候选）也一起翻 ⇒ 那批反而变肚皮朝天。
		#     ⇒ 只对**需要翻**的船（由 `SHIP_AXES` 的高度轴判定）翻。
		var solved := _solve_spec(mr, bow, up, YAW.extra_yaw(sid))
		var hits: Array = solved["hits"]
		var spec: String = String(solved["spec"])
		if spec == "":
			print("  ✗ %-12s 48 个 spec 全不命中（几何退化？）" % id)
			continue
		if hits.size() > 1:
			print("  ⚠️ %-12s 命中不唯一 %d 个：%s" % [id, hits.size(), ", ".join(hits)])
		lines.append("\t&\"%s\": \"%s\"," % [id, spec])
		var m_back := _parse_via_production(spec)
		var chk := Basis.from_euler(Vector3(0, YAW.extra_yaw(sid), 0)) * m_back * mr
		var got: Vector3 = (chk * bow).normalized()
		var up_got: Vector3 = (chk * up).normalized()
		print("  %-12s %-14s bow=%s up=%s ✔"
				% [id, spec, _v3(got), _v3(up_got)])
		n += 1
	print("── 共 %d 艘 ──" % n)
	var f := FileAccess.open("user://bow_calib/remap47.txt", FileAccess.WRITE)
	if f != null:
		f.store_line("# 47 轮 AXIS_REMAP 重算结果（mesh_rot 提升后）")
		f.store_line("# 口径：M·mesh_rot·bow = −Z · M·mesh_rot·up = +Y")
		for l in lines:
			f.store_line(l)
		f.close()
		print("已写出：%s" % ProjectSettings.globalize_path("user://bow_calib/remap47.txt"))
	if missing.size() > 0:
		print("⚠️ 载入失败 %d 艘：%s" % [missing.size(), ", ".join(missing)])
	get_tree().quit(0)


## 用**生产代码的解析器**把 spec 读回 Basis —— 保证与 `axis_remap()` 逐字节同源。
##
## ⚠️ 不复刻解析逻辑（红线 40）：直接调 `EveShipYawTable.parse_axis_remap()`
##    （它是 `axis_remap()` 内部用的**同一个**函数，47 轮为此专门抽出来）。
func _parse_via_production(spec: String) -> Basis:
	return YAW.parse_axis_remap(spec)


## ★ 47 轮最终方案：**穷举 48 个 spec，选端到端真的把 bow 送到 −Z 的那个**。
##
## ── 为什么不靠公式推导 ────────────────────────────────────────────
##  「该取行还是该取列」这一条**连续推错多次**（44 轮同款），每次症状都是
##  **不报错的倒飞**（船看着有朝向、数值也"像"，只是朝反）。
##  但判据本身极简单、极硬：
##
##      `R_y(extra_yaw) · parse(spec) · mesh_rot · bow == (0,0,−1)`  且
##      `R_y(extra_yaw) · parse(spec) · mesh_rot · up  == (0, 1, 0)`
##
##  ⇒ **穷举 48 个候选，让 Godot 自己选**（48 × 52 = 2496 次比对，本地毫秒级），
##    **零推导风险**。
##
## ── ⚠️ 必须**同时**约束 side（否则解不唯一）────────────────────────
##  实测：只约束 bow + up 时**每艘都命中 2 个**候选，差在**第三行符号**
##  （如 `+Z,-Y,+X` vs `-Z,-Y,+X`）。原因：`bow`/`up` 都不带 X 分量时，
##  M 的第三行**不参与**它俩的映射 ⇒ 自由。
##  但第三行决定 **side 轴（左右）** ⇒ 解错 = **整船左右镜像**
##  （红线 39：左右视图只差一个水平镜像，纯旋转换不过来）。
##  ⇒ 判据必须加第三条：`… · side == (+1, 0, 0)`。
func _solve_spec(mr: Basis, bow: Vector3, up: Vector3, extra: float) -> Dictionary:
	var ry := Basis.from_euler(Vector3(0, extra, 0))
	var side: Vector3 = bow.cross(up).normalized()
	var hits: Array[String] = []
	for i in 6:
		for j in 6:
			for k in 6:
				var sp := "%s,%s,%s" % [AXT[i], AXT[j], AXT[k]]
				var f: Basis = ry * YAW.parse_axis_remap(sp) * mr
				if (f * bow).normalized().distance_to(Vector3(0, 0, -1)) < 0.001 \
						and (f * up).normalized().distance_to(Vector3(0, 1, 0)) < 0.001 \
						and (f * side).normalized().distance_to(Vector3(1, 0, 0)) < 0.001:
					hits.append(sp)
	return {"hits": hits, "spec": (hits[0] if hits.size() > 0 else "")}


func _tok(v: Vector3) -> String:
	var ax := 0
	var best := -1.0
	for i in 3:
		var a := absf(v[i])
		if a > best:
			best = a
			ax = i
	var sign := "+" if v[ax] >= 0.0 else "-"
	return "%s%s" % [sign, "XYZ"[ax]]


func _v3(v: Vector3) -> String:
	return "(%+.2f,%+.2f,%+.2f)" % [v.x, v.y, v.z]
