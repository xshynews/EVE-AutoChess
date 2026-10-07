extends Node

## ★★ 53 轮（第七版）· **工具 vs 实机 · 几何体朝向对拍**
##
## ══════════════════════════════════════════════════════════════════
##  它要证明什么
## ══════════════════════════════════════════════════════════════════
##  用户：「全部不对，给我按照工具的 XYZ 轴调整整个项目」。
##
##  怀疑：工具里船的几何体朝向 = `holder.basis × 子网格mesh_rot`，
##        而实机（烘焙后）= `R_y·M·mesh_rot`
##        ⇒ 若 holder 也带 mesh_rot，就**乘了两次** ⇒ 系统性偏差 = mesh_rot。
##
##  ⇒ 本探针把**两条路径各跑一遍**，读引擎真值 `mesh.global_transform.basis`
##    （红线 40：不自己乘矩阵），逐艘比对：
##      A = 实机路径   `EveShipVisual.setup()` + `snap_facing(aim=−Z)`
##      B = 工具路径   `EveShipModel.instantiate()` + holder.basis(=修正后)
##    并额外给出「修正前」的 C 作对照（holder 带 mesh_rot 的旧行为）。
##
##  A 与 B 应**逐列相同**（差角 ≈ 0）。若 B≠A ⇒ 工具显示的船就不是实机的船。
##
##  用法：
##      Godot_v4.7.1-stable_win64_console.exe --headless \
##          --path "<工程>" --quit-after 9000 \
##          res://tools/probe_toolvsgame53.tscn

const YAW := preload("res://scripts/data/eve_ship_yaw.gd")
const SHIP_SCRIPT := preload("res://scripts/visual/eve_ship_visual.gd")
const INDEX := preload("res://scripts/data/eve_ship_asset_index.gd")


func _ready() -> void:
	print("══════════════════════════════════════════════════════════════")
	print("  53i · 工具 vs 实机 · 几何体朝向对拍（引擎真值，零复刻）")
	print("══════════════════════════════════════════════════════════════")
	print("")
	print("  %-12s %10s %10s %10s  %s" % ["id", "A实机", "B工具(修)", "C工具(旧)", "判定"])

	var ids: Array[String] = []
	for s in INDEX.all():
		ids.append(String(s.id))
	ids.sort()

	var n_ab := 0        # A 与 B 一致
	var n_c := 0         # A 与 C 一致（旧行为对）
	for sid in ids:
		var a := _game_basis(StringName(sid))
		var b := await _tool_basis(StringName(sid), false)  # 修正后（holder 不带 mesh_rot）
		var c := await _tool_basis(StringName(sid), true)   # 旧行为（holder 带 mesh_rot）
		if not _ok or not _ok_b or not _ok_c:
			print("  %-12s —— 缺模型" % sid)
			_ok = true
			continue
		var d_ab := _max_col_deg(a, b)
		var d_ac := _max_col_deg(a, c)
		if d_ab < 0.5:
			n_ab += 1
		if d_ac < 0.5:
			n_c += 1
		print("  %-12s %10s %10s %10s  %s" % [
				sid, "A", "Δ%.1f°" % d_ab, "Δ%.1f°" % d_ac,
				("B✅" if d_ab < 0.5 else "B✗") + (" C✅" if d_ac < 0.5 else "")])

	print("")
	print("──────────────────────────────────────────────────────────")
	print("  A(实机) 与 B(工具·RAW: holder=mesh_rot) 一致：%d / %d" % [n_ab, ids.size()])
	print("  A(实机) 与 C(工具·正常: holder=zero_pose) 一致：%d / %d" % [n_c, ids.size()])
	if n_c == ids.size():
		print("  ★ **正常模式下工具显示的船 = 实机的船（逐像素一致）**")
		print("    ⇒ holder 必须直接用 `zero_pose_basis`，不能去掉 mesh_rot。")
		print("    ⇒ RAW 模式(B) 与 A 差 mesh_rot⁻¹ 是**预期内**（那就是原始姿态）。")
	else:
		print("  ⚠ 正常模式下工具与实机不一致 —— 需继续查")
	print("──────────────────────────────────────────────────────────")
	get_tree().quit()


## A：实机路径（`setup` + `snap_facing`），读引擎真值
func _game_basis(sid: StringName) -> Basis:
	var sh := EveShip.new()
	sh.ship_key = sid
	sh.id = 1
	sh.body = EveDestinyMotion.Body.new(1)
	sh.body.position = Vector3.ZERO
	sh.body.aim_dir = Vector3(0, 0, -1)
	sh.body.velocity = Vector3.ZERO

	var vis: Variant = SHIP_SCRIPT.new()
	vis.set("ship", sh)
	var hr := Node3D.new()
	hr.name = "Hull"
	vis.set("hull_root", hr)
	vis.add_child(hr)
	vis.call("setup", sh)
	vis.call("snap_facing", sh.body, true)

	var m := _first_mesh(vis as Node)
	if m == null:
		_ok = false
		(vis as Node).free()
		return Basis()
	var out := m.global_transform.basis.orthonormalized()
	(vis as Node).free()
	return out


## B/C：工具路径。`old=true` 模拟修正前（holder 也带 mesh_rot）
func _tool_basis(sid: StringName, old: bool) -> Basis:
	# old=true → 正常模式(holder=zero_pose)；old=false → RAW(holder=mesh_rot)
	var model := EveShipModel.instantiate(sid)
	if model == null:
		if old:
			_ok_c = false
		else:
			_ok_b = false
		return Basis()
	var holder := Node3D.new()
	holder.add_child(model)
	add_child(holder)

	var zp: Basis = SHIP_SCRIPT.zero_pose_basis(sid)
	var mr: Basis = SHIP_SCRIPT.mesh_rot_of(sid).orthonormalized()
	# 修正后：zero_pose 去掉一次 mesh_rot（交给子网格）
	# 旧行为：直接用 zero_pose（子网格再乘一次 ⇒ 两次）
	holder.basis = (zp if old else mr).orthonormalized()

	# ⚠️ 必须等一帧让 global_transform 更新
	await get_tree().process_frame
	var m := _first_mesh(holder)
	var out := Basis()
	if m != null:
		out = m.global_transform.basis.orthonormalized()
	else:
		if old:
			_ok_c = false
		else:
			_ok_b = false
	remove_child(holder)
	holder.free()
	return out


## 用四元数夹角比整个旋转（`Basis` 没有 `get_column()`，红线：别猜 API）
## ⚠️ `Quaternion.get_angle()` 返回的是**半角** ⇒ 实际旋转角要 ×2（红线 53g）。
func _max_col_deg(a: Basis, b: Basis) -> float:
	var qa := a.get_rotation_quaternion()
	var qb := b.get_rotation_quaternion()
	var d := rad_to_deg(qa.angle_to(qb)) * 2.0
	# ⚠️ 四元数 `q` 与 `−q` 表示**同一旋转** ⇒ `angle_to` 会给 π（×2 = 360°）。
	#    不归一化的话会把"完全一致"误判成 360° 不一致（53 轮踩过）。
	return minf(d, 360.0 - d)


## `_game_basis` / `_tool_basis` 取不到网格时置 false（Basis 没有 is_empty）
var _ok := true
var _ok_b := true
var _ok_c := true


func _first_mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n as MeshInstance3D
	for c in n.get_children():
		var got := _first_mesh(c)
		if got != null:
			return got
	return null
