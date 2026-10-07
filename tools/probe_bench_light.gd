extends Node

## 备战席舰船提亮 A/B —— 一次性探针（2026-09-20）
##
## ══════════════════════════════════════════════════════════════════
##  为什么要单独量备战席
## ══════════════════════════════════════════════════════════════════
##  流程改成「买入 → 只进备战席 → 拖到棋盘」之后，**备战席变成玩家
##  停留最久的视区**（要在上面挑船、比船）。原来的提亮验收
##  （tools/probe_v3look）只量了【布阵态 · 相机推近 ×2】的船，
##  那一档天然更亮（离镜头近、头灯打满）。
##
##  本探针把变量锁死：**同一次运行、同一机位（战场默认取景）、
##  同一批船（备战席 5 艘）、舰船同为非布阵态**，
##  唯一变量 = 光照方案：
##    · base = 改前（无 IBL · 主光 0.55 · 无头灯）
##    · ibl  = 改后（天空盒 IBL 0.50 · 主光 0.95 · 随镜头头灯 0.40）
##
##  另外各出一张「隔离图」：把可见球幕隐藏，只留 Environment 的
##  近黑底色 → 画面里除了舰船几乎全是黑，方便 Python 精确统计
##  「舰船像素」的亮度分位，不被星云干扰。
##
## ── 跑法（⚠️ 要看像素，不要加 --headless）─────────────────────────
##   "C:/godot/Godot_v4.7.1-stable_win64_console.exe" \
##     --path "F:/evezzq/eve自走棋918" --quit-after 1200 res://tools/probe_bench_light.tscn
##
## 产物：user://bheat_real_base.png / bheat_real_ibl.png
##       user://bheat_iso_base.png  / bheat_iso_ibl.png
##       user://bheat_report.txt

const SCENE_PATH := "res://scenes/battle_scene.tscn"

## 改前的主光能量（见 eve_battle_arena.SUN_ENERGY 的注释）
const SUN_ENERGY_OLD := 0.55

var _battle: Node = null
var _arena: Variant = null
var _st: Variant = null
var _sun: DirectionalLight3D = null
var _we: WorldEnvironment = null
var _lines: Array[String] = []


func _ready() -> void:
	var packed: PackedScene = load(SCENE_PATH)
	_battle = packed.instantiate()
	add_child(_battle)
	for _i in 45:
		await get_tree().process_frame

	_arena = _battle.get("arena")
	_st = _battle.get("run")
	if _arena == null or _st == null:
		_line("!! arena / run 取不到，探针中止")
		_flush()
		get_tree().quit(1)
		return

	_we = _arena.get_node_or_null("WorldEnvironment") as WorldEnvironment
	_sun = _find_sun()

	# ── 备好 5 艘在备战席上（互不相同，避免三连合成把数量搅乱）──
	_force_distinct_offers()
	for i in 5:
		_st.buy(i % 5)
	for _i in 20:
		await get_tree().process_frame

	_line("═".repeat(70))
	_line("视口 = %s" % str(get_viewport().get_visible_rect().size))
	_line("备战席 = %d 艘 · 上场 = %d 艘 · 舰船节点 %d 个"
			% [_st.bench_used(), _st.field.size(), _ship_nodes().size()])
	_line("相机距离 = %.1f   board_view_zoom = %.2f"
			% [float(_arena.orion_cam.call("get_distance")), float(_arena.board_view_zoom)])
	_line("")

	# ── 四张图：{可见球幕开/关} × {改前/改后} ──
	await _case(false, "ibl", "bheat_real_ibl")
	await _case(false, "base", "bheat_real_base")
	await _case(true, "ibl", "bheat_iso_ibl")
	await _case(true, "base", "bheat_iso_base")

	# 收尾还原
	_set_background_visible(true)
	_apply_light("ibl")
	_flush()
	get_tree().quit(0)


# ------------------------------------------------------------------ 用例

func _case(hide_bg: bool, mode: String, name: String) -> void:
	_set_background_visible(not hide_bg)
	_apply_light(mode)
	for _i in 6:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://%s.png" % name)
	_line("  截图 → user://%s.png   （球幕%s · 光照=%s）"
			% [name, "隐藏" if hide_bg else "可见", mode])


# ------------------------------------------------------------------ 光照开关

## mode = "base"（改前） / "ibl"（改后 · 当前代码）
func _apply_light(mode: String) -> void:
	if _we == null or _we.environment == null:
		return
	var env: Environment = _we.environment
	if mode == "base":
		env.sky = null
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = _arena.AMBIENT_FALLBACK
		env.ambient_light_energy = _arena.AMBIENT_FALLBACK_ENERGY
		env.reflected_light_source = Environment.REFLECTION_SOURCE_BG
		if _sun != null:
			_sun.light_energy = SUN_ENERGY_OLD
		if _arena.camera_headlight != null:
			_arena.camera_headlight.light_energy = 0.0
	else:
		# 走正式入口重建 IBL Sky（与游戏里一模一样的那条路径）
		_arena.set_background(String(_arena.background_id))
		if _sun != null:
			_sun.light_energy = _arena.SUN_ENERGY
		if _arena.camera_headlight != null:
			_arena.camera_headlight.light_energy = _arena.HEADLIGHT_ENERGY


func _set_background_visible(v: bool) -> void:
	var bg: Node = _arena.get("background")
	if bg is Node3D:
		(bg as Node3D).visible = v


func _find_sun() -> DirectionalLight3D:
	for c in _arena.get_children():
		if c is DirectionalLight3D:
			return c
	return null


# ------------------------------------------------------------------ 杂项

func _ship_nodes() -> Dictionary:
	var d = _arena.get("_ship_nodes")
	return d if d is Dictionary else {}


## 把商店 5 格换成 5 款互不相同的 1 费船
## （口径与 verify_run._force_offers_distinct 完全一致：
##   真实货架随机，偶尔会开出 3 张同名 → 触发三连合成 → 备战席数量不再是 5）
func _force_distinct_offers() -> void:
	var pool: Array = EveShipDatabase.by_cost(1)
	var arr: Array = []
	for i in EveRunState.SHOP_SLOTS:
		arr.append(pool[i % pool.size()].duplicate(true))
	_st.offers = arr
	_st.offers_changed.emit()


func _line(s: String) -> void:
	_lines.append(s)
	print(s)


func _flush() -> void:
	var f := FileAccess.open("user://bheat_report.txt", FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(_lines))
		f.close()
