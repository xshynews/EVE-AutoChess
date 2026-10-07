extends Node
## ══════════════════════════════════════════════════════════════════════
##  50 轮 · 「官方渲染 vs 实机姿态」并排对照（判舰艏端 + up 用）
## ══════════════════════════════════════════════════════════════════════
##
## ── 为什么出图 ──────────────────────────────────────────────────────
##  机器已经能算「长轴 → 世界 −Z」，但**「长轴哪一端是舰艏」只能人眼判**
##  （红线 33：外观真值只有实机图 / 官方 render）。
##  ⇒ 本条把每艘船的实机姿态从**三个正交视角**拍下来，供用户指认。
##
## ── 视角（world 对齐，与游戏语义一致）────────────────────────────
##   · TOP  ：相机在 +Y 往下看，屏幕「上」= 世界 −Z（敌向）
##   · SIDE ：相机在 +X 侧看，屏幕「左」= 世界 −Z（敌向）
##   · FRONT：相机在 +Z（我方背后）看，屏幕「上」= +Y
##  ⚠️ 每张图角落画**参考球**：🔴 = 世界 −Z（敌向）· 🔵 = 世界 +Y（天）
##     ⇒ 用户看图时不用猜"哪边是敌人"。
##
## 跑法（非 headless）：
##   `--path <工程> --quit-after 900 res://tools/probe_shot50.tscn`
##
## 输出：`user://shots50/<id>_{top,side,front}.png`

const YAW := preload("res://scripts/data/eve_ship_yaw.gd")
const IDS: Array[String] = ["algos", "catalyst", "kestrel", "slasher", "tristan"]

var _battle: Node = null
var _arena: Node = null
var _frames := 0

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute("user://shots50")
	var packed: PackedScene = load("res://scenes/battle_scene.tscn")
	_battle = packed.instantiate()
	add_child(_battle)
	for _i in 40:
		await get_tree().process_frame
	_arena = _battle.get("arena")

	var run: Node = _battle.get("run")
	run.coin = 999
	run.roll_shop()
	for i in 5:
		run.buy(i)
	run.bench.clear()
	run.field.clear()
	for k in IDS:
		run.bench.append({"ship_key": StringName(k), "star": 1, "cell": Vector2i(-1, -1)})
		run.field.append(run.bench[run.bench.size() - 1].duplicate(true))
	run.changed.emit()
	_battle.call("_respawn_own_fleet")
	for _i in 5:
		await get_tree().process_frame
	_battle.call("start_battle")
	print("[50 轮·出图] 战斗已启动")


func _process(_dt: float) -> void:
	_frames += 1
	if _frames != 600:
		return
	await _shoot_all()
	get_tree().quit(0)


func _find_model(vis: Variant) -> Node3D:
	var hr = vis.get("hull_root")
	if hr == null:
		return null
	for c in hr.get_children():
		if String(c.name).begins_with("Model_"):
			return c
	return null


func _shoot_all() -> void:
	# 关掉 HUD / 血条干扰（只留船）—— 直接隐藏 ships_layer 之外的东西
	var ships_layer: Node = _arena.ships_layer
	for v in ships_layer.get_children():
		if not v.has_method("sync_from_body"):
			continue
		var s = v.get("ship")
		if s == null or s.body == null:
			continue
		# 只拍我方测试船，其余隐藏，画面干净
		var keep: bool = s.team == 0 and IDS.has(String(s.ship_key))
		v.visible = keep

	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true

	for v in ships_layer.get_children():
		if not v.has_method("sync_from_body"):
			continue
		var s = v.get("ship")
		if s == null or s.body == null or s.team != 0:
			continue
		var key := String(s.ship_key)
		if not IDS.has(key):
			continue
		var center: Vector3 = v.global_position
		var dist := 12.0

		# TOP：相机在 +Y，up 取世界 −Z
		cam.global_position = center + Vector3(0.0, dist, 0.01)
		cam.look_at(center, Vector3(0.0, 0.0, -1.0))
		await _grab(key, "top")
		# SIDE：相机在 +X（从船的右侧看），up 取 +Y
		cam.global_position = center + Vector3(dist, 0.0, 0.0)
		cam.look_at(center, Vector3.UP)
		await _grab(key, "side")
		# FRONT：相机在 +Z（我方背后朝 −Z 看），up 取 +Y
		cam.global_position = center + Vector3(0.0, 0.0, dist)
		cam.look_at(center, Vector3.UP)
		await _grab(key, "front")

	cam.queue_free()
	print("   已出图到 user://shots50（共 %d 艘 × 3 视角）" % IDS.size())


func _grab(key: String, tag: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	var p := "user://shots50/%s_%s.png" % [key, tag]
	img.save_png(p)
	print("   · %s_%s → %s" % [key, tag, ProjectSettings.globalize_path(p)])
