extends Node
## 44 轮最终取证：**工具侧 vs 游戏侧**全库 52 艘逐艘对账（真代码）。
## 判据（红线 40：两侧算式独立取用，不由被测方反推）：
##   · 工具侧 = 工具的 `_axis_dir_to_world`（间接：读工具导出的 ship_axes.json 的 bow）
##   · 游戏侧 = `R_y(−90°)·M·bow_model`（本探针直接算）
##   两者必须都落 (0,0,−1)。
const YAW := preload("res://scripts/data/eve_ship_yaw.gd")
const IDX := preload("res://scripts/data/eve_ship_asset_index.gd")

func _ready() -> void:
	print("═══ 44 轮取证：工具侧 ship_axes.json vs 游戏侧算式 ═══")
	var jpath := "user://bow_calib/ship_axes.json"
	if not FileAccess.file_exists(jpath):
		print("✗ 工具导出文件不存在：%s" % jpath)
		get_tree().quit()
		return
	var fa := FileAccess.open(jpath, FileAccess.READ)
	var tbl: Variant = JSON.parse_string(fa.get_as_text())
	fa.close()
	if not (tbl is Dictionary):
		print("✗ 解析失败")
		get_tree().quit()
		return
	var n := 0
	var mismatch: PackedStringArray = PackedStringArray()
	for s in IDX.all():
		var sid := String(s.id)
		n += 1
		# 游戏侧（真代码）
		var yaw: float = -PI / 2.0 + YAW.extra_yaw(StringName(sid))
		var M: Basis = YAW.axis_remap(StringName(sid))
		var R := Basis.from_euler(Vector3(0.0, yaw, 0.0)) * M
		var bw: Vector3 = (R * YAW.bow_axis(StringName(sid))).normalized()
		# 工具侧（导出文件的 主视图 = 该船 bow 的世界方向… 实际存的是**模型轴**还是世界轴？）
		var rec: Variant = tbl.get(sid)
		var tj := "?"
		if rec is Dictionary:
			var vv: Variant = rec.get("views")
			if vv is Dictionary:
				tj = String(vv.get("主视图", "?"))
		# 判据：工具侧"主视图"字段应当 = SHIP_AXES.bow（模型轴口径），
		#       而工具**屏幕上画出来**的位置 = 游戏世界口径。两者都记录。
		print("%-14s 游戏 R·M·bow=%-22s 表内 bow=%-4s 工具主视图字段=%s"
				% [sid, str(bw.snappedf(0.001)), _fmt(YAW.bow_axis(StringName(sid))), tj])
		if bw.dot(Vector3(0, 0, -1)) < 0.99:
			mismatch.append(sid)
	print("═══ 共 %d 艘 · 游戏侧非朝敌 %d 艘 %s" % [n, mismatch.size(), ", ".join(mismatch) if mismatch.size() > 0 else ""])
	get_tree().quit()


func _fmt(v: Vector3) -> String:
	if v.x > 0.5: return "+X"
	if v.x < -0.5: return "-X"
	if v.y > 0.5: return "+Y"
	if v.y < -0.5: return "-Y"
	if v.z > 0.5: return "+Z"
	return "-Z"
