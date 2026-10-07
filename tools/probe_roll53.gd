extends Node

## ★ 53 轮（第三版）· **全库 52 艘「滚转前后」姿态普查**
##
## ══════════════════════════════════════════════════════════════════
##  为什么需要这个探针
## ══════════════════════════════════════════════════════════════════
##  53 轮用户看 `布阵实机_俯视.png` 后裁定：
##    「舰艏还是朝向玩家的，这不对。kestrel_SIDE.png 里面船是茶隼，
##      可以转 Z 轴，沿 X 轴转 180 度就合适了。」
##
##  而 `eve_ship_visual.gd` 第 530 行有一条**全局**开关
##      `const GLOBAL_ROLL_180 := true`   （48 轮为「舰船腹部朝上」加的）
##  作用点：
##      `zero_pose_basis = R_z(180°) · R_y(yaw) · M · mesh_rot`
##                        ^^^^^^^^^ 世界空间侧最左
##
##  ⇒ 该 180° **对每一艘船都生效**，而 48 轮的症状报告是**逐艘**的
##    （用户当时只报了部分船）。一刀切 = 把本来正确的船也翻过去。
##
## ══════════════════════════════════════════════════════════════════
##  本探针干什么
## ══════════════════════════════════════════════════════════════════
##  对每一艘船输出**两栏**世界姿态：
##    · 「含滚转」= 生产实际值 = `EveShipVisual.zero_pose_basis(id)`
##    · 「不含滚转」= `EveShipVisual.zero_pose_basis_no_roll(id)`
##  以及各自：
##    · 舰艏世界方向 `bow_w`（对敌判据：`bow_w · (0,0,−1)`）
##    · 船背世界方向 `up_w` （朝天判据：`up_w · (0,1,0)`）
##    · 横向世界方向 `side_w`
##
## ⚠️ 红线 40：**全部调生产函数**，不自己乘 `R_z` / 不手推 M。
## ⚠️ 红线 51d：本探针只**报告**，不据此否定用户标定（`pose_table.json`）。
##    它回答的是一个**新**问题：48 轮那刀 `GLOBAL_ROLL_180` 该不该全局生效。
##
##  用法：
##      Godot_v4.7.1-stable_win64_console.exe --headless \
##          --path "<工程>" --quit-after 900 \
##          res://tools/probe_roll53.tscn -- --out "<路径>"

const SIDE := preload("res://scripts/data/eve_ship_yaw.gd")

var _lines: PackedStringArray = []
var _out_path := ""


func _ready() -> void:
	var ua := OS.get_cmdline_user_args()
	for i in ua.size():
		if ua[i] == "--out" and i + 1 < ua.size():
			_out_path = ua[i + 1]

	_p("══════════════════════════════════════════════════════════════")
	_p("  53c · 全库 52 艘「滚转前后」姿态普查")
	_p("  GLOBAL_ROLL_180 = %s （轴 %s）" % [
			str(EveShipVisual.GLOBAL_ROLL_180),
			str(EveShipVisual.GLOBAL_ROLL_AXIS)])
	_p("══════════════════════════════════════════════════════════════")
	_p("")
	_p("  列说明：bow/up/side = 该姿态下**世界**方向；")
	_p("         朝敌 = bow·(0,0,−1)；朝天 = up·(0,1,0)。")
	_p("         二者都 +1.00 才是「舰艏指着敌人 + 船背朝天」。")
	_p("")

	var ids := SIDE.all_ship_ids()
	var n_bad_roll := 0
	var n_bad_noroll := 0
	var n_diff := 0
	for sid in ids:
		var r := _one(sid)
		if r["bad_roll"]:
			n_bad_roll += 1
		if r["bad_noroll"]:
			n_bad_noroll += 1
		if r["diff"]:
			n_diff += 1

	_p("")
	_p("──────────────────────────────────────────────────────────")
	_p("  合计 %d 艘" % ids.size())
	_p("    含滚转（生产现值）  不达标：%d" % n_bad_roll)
	_p("    不含滚转（回滚候选）不达标：%d" % n_bad_noroll)
	_p("    两种姿态**不同**的船：%d" % n_diff)
	_p("──────────────────────────────────────────────────────────")

	if _out_path != "":
		var f := FileAccess.open(_out_path, FileAccess.WRITE)
		if f != null:
			f.store_string("\n".join(_lines))
			f.close()
			print("[probe_roll53] 报告已写：%s" % _out_path)
		else:
			print("[probe_roll53] ⚠ 写文件失败：%s" % _out_path)

	get_tree().quit()


func _one(sid: StringName) -> Dictionary:
	# ── 两栏姿态：全部走生产函数（红线 40）──
	var zp_roll: Basis = EveShipVisual.zero_pose_basis(sid)
	var zp_noroll: Basis = EveShipVisual.zero_pose_basis_no_roll(sid)

	var b: Vector3 = SIDE.bow_axis(sid)
	var u: Vector3 = SIDE.up_axis(sid)
	var s: Vector3 = SIDE.side_axis(sid)

	var bw_r := (zp_roll * b).normalized()
	var uw_r := (zp_roll * u).normalized()
	var sw_r := (zp_roll * s).normalized()

	var bw_n := (zp_noroll * b).normalized()
	var uw_n := (zp_noroll * u).normalized()
	var sw_n := (zp_noroll * s).normalized()

	# ── 判据（阈值 0.90 ≈ 25° 容差，只用于分档统计，不做裁决）──
	var fwd := Vector3(0, 0, -1)
	var sky := Vector3(0, 1, 0)
	var dot_r := bw_r.dot(fwd)
	var upr := uw_r.dot(sky)
	var dot_n := bw_n.dot(fwd)
	var upn := uw_n.dot(sky)

	var bad_r: bool = dot_r < 0.90 or upr < 0.90
	var bad_n: bool = dot_n < 0.90 or upn < 0.90
	var diff: bool = (bw_r - bw_n).length() > 1e-3 or (uw_r - uw_n).length() > 1e-3

	var flag := ""
	if bad_r and not bad_n:
		flag = "  ← 含滚转坏 / 不含滚转好 ⇒ **该船不该吃这刀**"
	elif not bad_r and bad_n:
		flag = "  ← 不含滚转坏 / 含滚转好 ⇒ 该船需要这刀"
	elif bad_r and bad_n:
		flag = "  ← 两栏都坏 ⇒ 另有问题"
	else:
		flag = "  ← 两栏都好（该刀对本船无影响或无害）"

	_p("%-12s 含滚转 bow·敌=%+.2f up·天=%+.2f  舰艏%s 船背%s" % [
			String(sid), dot_r, upr, _v(bw_r), _v(uw_r)])
	_p("%-12s 不含滚转 bow·敌=%+.2f up·天=%+.2f  舰艏%s 船背%s%s" % [
			String(sid), dot_n, upn, _v(bw_n), _v(uw_n), flag])
	if diff:
		_p("%-12s   侧向：含滚转%s  不含滚转%s" % [String(sid), _v(sw_r), _v(sw_n)])
	_p("")
	return {"bad_roll": bad_r, "bad_noroll": bad_n, "diff": diff}


func _p(s: String) -> void:
	print(s)
	_lines.append(s)


func _v(v: Vector3) -> String:
	return "(%.2f,%+.2f,%+.2f)" % [v.x, v.y, v.z]
