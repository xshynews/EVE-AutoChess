extends Node3D
## 锚点布置逐档验证探针（非无头）。
##
## 直接构造船只可视节点，不走战斗流程 —— 否则战巡/战列会因为费用或槽位
## 部署不出来，验证不到 34 / 38 这两个档。
##
## 跑法：
##   "$GODOT_BIN" --path . res://tools/probe_anchor_tiers.tscn

const SHIP_VISUAL := preload("res://scripts/visual/eve_ship_visual.gd")
const SHIELD_SCRIPT := preload("res://scripts/visual/eve_shield_impact.gd")
const SHOT_DIR := "user://anchor_tiers"

var _cam: Camera3D

## [ship_key, 显示名, Class, 说明]
const FLEET := [
	["punisher", "惩罚者级", EveShip.Class.FRIGATE, "护卫"],
	["cormorant", "海燕级", EveShip.Class.DESTROYER, "驱逐"],
	["caracal", "狞獾级", EveShip.Class.CRUISER, "巡洋"],
	["hurricane", "暴风级", EveShip.Class.BATTLE_CRUISER, "战巡"],
	["raven", "乌鸦级", EveShip.Class.BATTLESHIP, "战列"],
	["myrmidon", "弥尔米顿级", EveShip.Class.BATTLE_CRUISER, "垂直船"],
]

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SHOT_DIR)
	if DisplayServer.get_name() == "headless":
		print("X 必须非 headless")
		get_tree().quit()
		return
	SHIELD_SCRIPT.debug_markers = true

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-38.0, -30.0, 0.0)
	light.light_energy = 1.1
	add_child(light)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.025, 0.04)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.12, 0.16, 0.24)
	env.ambient_light_energy = 0.6
	we.environment = env
	add_child(we)

	_cam = Camera3D.new()
	_cam.fov = 42.0
	_cam.near = 0.1
	_cam.far = 4000.0
	add_child(_cam)
	_cam.make_current()

	var n := FLEET.size()
	for i in n:
		var key: StringName = FLEET[i][0]
		var label: String = FLEET[i][1]
		var cls: int = FLEET[i][2]
		var tag: String = FLEET[i][3]
		var ship := EveShip.create(i + 1, label, 0, cls, 0, 1)
		# ⚠️ 顺序不能反：apply_stats 会用 stats["ship_key"] 覆盖 ship_key，
		#    先设 key 再 apply_stats 会被重置成空串（模型就退化成占位方块）。
		ship.apply_stats({"ship_key": String(key), "shield": 100.0, "armor": 100.0, "hull": 100.0})
		ship.ship_key = key
		# ⚠️ body.position 的单位是【米】，除以 METERS_PER_UNIT(1000) 才是世界单位。
		#    直接按世界单位摆会让所有船挤在原点。
		var gap_m := 6500.0
		ship.body.position = Vector3((float(i) - float(n - 1) * 0.5) * gap_m, 0.0, 0.0)
		var vis = SHIP_VISUAL.new()
		add_child(vis)
		vis.setup(ship)
		var fx = vis.get("_shield_fx")
		if fx == null:
			print("  X %s 没建出护盾节点" % label)
			continue
		_dump(fx, label, tag, key)

	_cam.position = Vector3(0.0, 13.0, 30.0)
	_cam.look_at(Vector3(0.0, 0.0, 0.0), Vector3.UP)
	await _frames(6)
	await _save("01_all")

	# 近景：看垂直船（弥尔米顿级）的上下分布
	_cam.position = Vector3(16.0, 5.0, 9.0)
	_cam.look_at(Vector3(16.25, 0.0, 0.0), Vector3.UP)
	await _frames(4)
	await _save("02_vertical")

	get_tree().quit()

func _dump(fx, label: String, tag: String, key) -> void:
	var bow: Vector3 = fx._bow
	var nb := 0
	var ns := 0
	var up := 0
	var down := 0
	for s in fx._slots:
		if s.dir.dot(bow) > 0.55: nb += 1
		if s.dir.dot(-bow) > 0.55: ns += 1
		if s.dir.y > 0.35: up += 1
		if s.dir.y < -0.35: down += 1
	var total: int = fx._slots.size()
	print("  %s(%s/%s)：锚点=%d 船艏=%d 引擎=%d 上=%d 下=%d" % [label, tag, key, total, nb, ns, up, down])

func _save(tag: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [SHOT_DIR, tag]
	img.save_png(path)
	print("  [SHOT] %s %dx%d" % [ProjectSettings.globalize_path(path), img.get_width(), img.get_height()])

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
