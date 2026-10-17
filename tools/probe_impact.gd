extends Node
## 打击感取证探针（2026-10-17 · 接手第 0 轮）
##
## ══════════════════════════════════════════════════════════════════
##  为什么需要它
## ══════════════════════════════════════════════════════════════════
##  用户的诉求是「打起来不好看 / 没打击感」——这是一句**观感**描述，
##  工程里没有任何一条验收能覆盖它（`verify_*` 全是数值与结构断言）。
##  在动手改之前，必须先把这个观感**变成可数的量**：
##
##    ① 一帧里同时存在多少条开火线 / 爆点（`active_count()`）
##    ② 战斗区在屏幕上占多大（相机距离 → 船的实际像素尺寸）
##    ③ 命中瞬间有没有任何「屏幕级」反馈（震屏 / 顿帧 / 闪白）
##    ④ 音效是否真的在响（`sfx_enabled`）
##
##  本探针只**读数 + 出图**，不改任何生产逻辑。
##
## ── 跑法（⚠️ 不能 headless：要真渲染）────────────────────────────
##   "$GODOT_BIN" --path . --quit-after 3000 res://tools/probe_impact.tscn
##
##  产物：`user://impact/*.png`（开战后每 6 帧一张）+ 控制台读数
## ==================================================================

const INDEX := preload("res://scripts/data/eve_ship_asset_index.gd")
const SHOT_DIR := "user://impact"

## 截多少张（每 SHOT_EVERY 帧一张）
const SHOT_EVERY := 6
const SHOT_COUNT := 24

## 灌进备战席的船数（部署上限由 run 的 field_limit 决定，超了会 break）
const WANT_SHIPS := 6

var _scene: Node = null
var _frame := 0
var _battle_started := false
var _shots := 0
var _fx_max := 0
var _fx_samples: Array[int] = []
var _print_every := 6

## ★ 首次出现特效那一刻起，改成「每 2 帧一张」密集抓拍 ——
##   0.15 秒的开火线按 6 帧一截会整段漏掉（第一版就漏了，144 帧一张没抓上）。
var _burst_left := 0
var _burst_gap := 0


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SHOT_DIR)
	if DisplayServer.get_name() == "headless":
		print("✗ 本探针必须非 headless（要真渲染）")
		get_tree().quit()
		return
	var ps: PackedScene = load("res://scenes/battle_scene.tscn")
	if ps == null:
		print("✗ battle_scene.tscn 加载失败")
		get_tree().quit()
		return
	_scene = ps.instantiate()
	add_child(_scene)
	await _wait_frames(40)
	_scene.call("begin_prep")
	await _wait_frames(20)
	_inject()
	await _wait_frames(30)
	_save("00_prep.png")
	print("──────────────────────────────────────────────")
	print("  [音效] sfx_enabled = %s" % str(_audio_sfx_enabled()))
	print("──────────────────────────────────────────────")
	_scene.call("start_battle")
	_battle_started = true


func _process(_dt: float) -> void:
	if not _battle_started:
		return
	_frame += 1
	var fx := _fx()
	if fx >= 0:
		_fx_samples.append(fx)
		if fx > _fx_max:
			_fx_max = fx
	# 首次见到特效 ⇒ 进入密集抓拍（抓「命中瞬间」那一两帧）
	if fx > 0 and _burst_left == 0:
		_burst_left = 12
	if _burst_left > 0:
		_burst_gap += 1
		if _burst_gap % 2 == 0:
			_shots += 1
			_burst_left -= 1
			_save("%03d_hit_fx%d.png" % [_shots, fx])
	elif _frame % SHOT_EVERY == 0 and _shots < SHOT_COUNT:
		_shots += 1
		_save("%03d_battle.png" % _shots)
	if _frame % (SHOT_EVERY * 4) == 0:
		print("  [@%d] fx_active=%d  %s" % [_frame, fx, _cam_desc()])
	if _frame > 420:
		_report()
		get_tree().quit(0)


func _report() -> void:
	print("══════════════════════════════════════════════")
	print("  打击感取证读数")
	print("  开火/命中/爆炸 活跃峰值 = %d" % _fx_max)
	print("  活跃数样本 = %s" % str(_fx_samples))
	print("  音效开关 = %s" % str(_audio_sfx_enabled()))
	print("  相机 = %s" % _cam_desc())
	print("  截图 %d 张 → %s" % [_shots, SHOT_DIR])
	_dump_ships()
	print("══════════════════════════════════════════════")


## 逐艘舰船：屏幕上在哪、离相机多远、屏幕跨度多少像素。
##
## ★ 这张表是「战场取景有没有失控」的唯一硬证据 ——
##   只看截图会误判成「模型太大 / 特效太大」，其实是某艘船贴到镜头上了。
func _dump_ships() -> void:
	if _scene == null:
		return
	var arena: Variant = _scene.get("arena")
	if arena == null:
		return
	var cam3: Variant = arena.get("camera")
	if cam3 == null or not (cam3 is Camera3D):
		return
	var c: Camera3D = cam3
	# ★ 遍历整棵场景树找「带 ship 字段的 Node3D」——
	#   只查 arena._ship_nodes 会漏掉敌方（它们由 sim 的另一套节点渲染），
	#   第一次跑就是这么漏掉左下角那艘贴镜头的船的。
	var found: Array = []
	_collect_ships(self, found)
	var vp_size := get_viewport().get_visible_rect().size
	print("  舰船盘点（屏幕 %dx%d，共 %d 个 visual）：" % [
			int(vp_size.x), int(vp_size.y), found.size()])
	for n in found:
		var n3 := n as Node3D
		if n3 == null or not n3.visible:
			continue
		var sh: Variant = n3.get("ship")
		var key := "?"
		var team := -1
		if sh != null:
			key = str(sh.get("ship_key"))
			team = int(sh.get("team"))
		var wp := n3.global_position
		var sp := c.unproject_position(wp)
		var d := c.global_position.distance_to(wp)
		# 用「中心 ± 船体半长」两点投影，量真实屏幕跨度
		var half := 1.3
		var p1 := c.unproject_position(wp + Vector3(half, 0, 0))
		var p2 := c.unproject_position(wp - Vector3(half, 0, 0))
		var px := p1.distance_to(p2)
		var onscreen := sp.x >= 0 and sp.x <= vp_size.x and sp.y >= 0 and sp.y <= vp_size.y
		print("    %-12s team=%d 屏幕(%5d,%5d) %s  距相机%5.1f  跨度%4.0fpx" % [
				key, team, int(sp.x), int(sp.y), "画面内" if onscreen else "★画面外",
				d, px])


## 递归收集「带 ship 字段」的 Node3D（= EveShipVisual）
func _collect_ships(n: Node, out: Array) -> void:
	if n is Node3D and "ship" in n:
		var sh: Variant = n.get("ship")
		if sh != null:
			out.append(n)
	for c in n.get_children():
		_collect_ships(c, out)


func _fx() -> int:
	if _scene == null:
		return -1
	var arena: Variant = _scene.get("arena")
	if arena == null:
		return -1
	var battle_fx: Variant = arena.get("battle_fx")
	if battle_fx == null:
		return 0
	return int(battle_fx.call("active_count"))


## 相机距离 + 由此推出的「一艘船在 1080p 下多少像素」。
##
## 口径：1 世界单位对应屏幕高度 `2·d·tan(fov/2)`；
## 船体基准长 2.6（`HULL_REF_LENGTH`）× 战斗态放大 1.20 = 3.12 世界单位。
func _cam_desc() -> String:
	if _scene == null:
		return "?"
	var arena: Variant = _scene.get("arena")
	if arena == null:
		return "?"
	var cam3: Variant = arena.get("camera")
	if cam3 == null or not (cam3 is Camera3D):
		return "?"
	var c: Camera3D = cam3
	var focus: Variant = arena.get("_cam_focus")
	var f: Vector3 = focus if focus != null else Vector3.ZERO
	var d := c.global_position.distance_to(f)
	var half := tan(deg_to_rad(c.fov) * 0.5) * d
	var screen_h := 1080.0
	var px := 3.12 / maxf(0.001, half * 2.0) * screen_h
	return "d=%.1f 船身≈%.0fpx(1080p)" % [d, px]


func _audio_sfx_enabled() -> bool:
	if _scene == null:
		return false
	var a: Variant = _scene.get("audio")
	if a == null:
		return false
	var v: Variant = a.get("sfx_enabled")
	return bool(v) if v != null else false


## 灌船进备战席并部署（沿用 probe_live_shot 的做法）
func _inject() -> void:
	var run: Variant = _scene.get("run")
	if run == null:
		print("✗ scene 没有 run")
		return
	run.set("coin", 999999)
	var bench: Array = run.get("bench")
	bench.clear()
	var field: Array = run.get("field")
	field.clear()
	# 取 cost 最低的一批不同船，保证能部署满
	var all: Array = INDEX.all()
	var picked: Array = []
	for s in all:
		if int(s.cost) <= 1:
			picked.append(s)
		if picked.size() >= WANT_SHIPS:
			break
	for s in picked:
		bench.append({"ship_key": StringName(String(s.id)), "star": 1, "cost": int(s.cost)})
	run.emit_signal("changed")
	await _wait_frames(4)
	var deployed := 0
	for i in picked.size():
		var res: Dictionary = run.call("deploy_from_bench", 0, 7 - i / 9, i % 9)
		if bool(res.get("ok", false)):
			deployed += 1
	run.emit_signal("changed")
	print("  注入完成：备选 %d 艘 · 实际部署 %d 艘" % [picked.size(), deployed])


func _wait_frames(n: int) -> void:
	for _i in n:
		await get_tree().process_frame


func _save(name: String) -> void:
	var vp := get_viewport()
	if vp == null:
		return
	var img := vp.get_texture().get_image()
	if img == null:
		return
	img.save_png(SHOT_DIR + "/" + name)
	print("  ✔ %s" % name)
