extends Node

## 舰船亮度候选方案对比探针（2026-09-21）
##
## ══════════════════════════════════════════════════════════════════
##  这一轮要量什么（口径来自 REF_HUD 第十节 + 2026-09-20 的遗留待办）
## ══════════════════════════════════════════════════════════════════
##  上一轮修「船太暗」把**近黑像素占比 66.6% → 0.0%**，但用户回执是
##  「好多了，但还是不够亮」。结论：**消灭近黑 ≠ 观感够亮**。
##
##  所以要量的不是「船有多亮」（绝对分位），而是
##    **船体掩膜内的 p50 / p75 与星云背景亮度的比值** —— 相对对比。
##  比值 < 1 = 船比背景还暗 ⇒ 无论绝对亮度多少，看上去都是「糊在背景里」。
##
## ── 手法（三条硬约束，第一次踩过的坑都在这）──────────────────────
##  ① **同一次运行、同一机位、同一批船**，唯一变量 = 光照方案。
##     跨进程比会因为取帧时刻不同（倒计时读数、日志淡入、商店卡面 3D
##     缩略图）而不可比 —— 上次交付图就踩了，星币 5 vs 0 根本不是同一状态。
##  ② **同一套掩膜**。改亮之后「可见像素」会变多，直接对可见像素取分位
##     等于比两个不同分布。做法：隐藏可见球幕出「隔离图」，
##     **掩膜 = 全部方案隔离图的并集**，再在掩膜内统计。
##  ③ **HUD 整层隐藏**，否则窗口边框/文字会混进掩膜。
##
## ── 跑法（⚠️ 要看像素，不要加 --headless）───────────────────────
##   "C:/godot/Godot_v4.7.1-stable_win64_console.exe" \
##     --path "F:/evezzq/eve自走棋918" --quit-after 4000 res://tools/probe_ship_bright.tscn
##
##  产物：user://sbright_<id>_real.png（球幕可见）
##        user://sbright_<id>_iso.png （球幕隐藏 · 供建掩膜）
##        user://sbright_report.txt
##
##  然后跑 `python C:/godot/_export/ww2ogg_py/ship_bright.py` 出统计。

const SCENE_PATH := "res://scenes/battle_scene.tscn"

## 候选方案表。语义见 eve_battle_arena.gd / ship_hull.gdshader 的常量注释：
##   amb  = IBL_AMBIENT_ENERGY（天空盒环境光能量）
##   sun  = SUN_ENERGY（主平行光）
##   head = HEADLIGHT_ENERGY（挂相机下的头灯）
##   sky  = PanoramaSkyMaterial.energy_multiplier（只喂 PBR，不影响看得见的星云）
##   lift = ship_hull.gdshader 的 albedo_lift（伽马提亮船壳，暗部抬得多）
##
## 第一轮只挪一档发现 **amb 0.50→1.00 像素零变化**，故第二轮改成敏感度扫描：
##   amb 0→4 完全无效 / head·sky 是主力 / 但**全部拉爆也只到 p50=47**（背景 130）。
## 于是第三轮加入材质侧 albedo 提亮，并测它与灯光的组合。
const MODES: Array = [
	{"id": "cur",        "amb": 0.50, "sun": 0.95, "head": 0.40, "sky": 0.86, "lift": 1.0, "gain": 1.0},
	{"id": "lift140",    "amb": 0.50, "sun": 0.95, "head": 0.40, "sky": 0.86, "lift": 1.4, "gain": 1.0},
	{"id": "lift180",    "amb": 0.50, "sun": 0.95, "head": 0.40, "sky": 0.86, "lift": 1.8, "gain": 1.0},
	{"id": "lift220",    "amb": 0.50, "sun": 0.95, "head": 0.40, "sky": 0.86, "lift": 2.2, "gain": 1.0},
	{"id": "lift260",    "amb": 0.50, "sun": 0.95, "head": 0.40, "sky": 0.86, "lift": 2.6, "gain": 1.0},
	{"id": "gain160",    "amb": 0.50, "sun": 0.95, "head": 0.40, "sky": 0.86, "lift": 1.0, "gain": 1.6},
	{"id": "l180_h080",  "amb": 0.50, "sun": 0.95, "head": 0.80, "sky": 0.86, "lift": 1.8, "gain": 1.0},
	{"id": "l180_s120",  "amb": 0.50, "sun": 0.95, "head": 0.40, "sky": 1.20, "lift": 1.8, "gain": 1.0},
	{"id": "l180_h080s120", "amb": 0.50, "sun": 0.95, "head": 0.80, "sky": 1.20, "lift": 1.8, "gain": 1.0},
	{"id": "l220_h080s120", "amb": 0.50, "sun": 0.95, "head": 0.80, "sky": 1.20, "lift": 2.2, "gain": 1.0},
]

var _battle: Node = null
var _arena: Variant = null
var _st: Variant = null
var _hud: CanvasItem = null
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
	_hud = _battle.get("hud") as CanvasItem

	# ── 备好 5 艘在备战席上（互不相同，避免三连合成把数量搅乱）──
	_force_distinct_offers()
	for i in 5:
		_st.buy(i % 5)
	for _i in 25:
		await get_tree().process_frame

	# ⚠️ 规格 ③：HUD 整层隐藏。否则窗口边框/文字会混进「船体掩膜」。
	if _hud != null:
		_hud.visible = false

	_line("═".repeat(72))
	_line("视口 = %s" % str(get_viewport().get_visible_rect().size))
	_line("备战席 = %d 艘 · 上场 = %d 艘 · 舰船节点 %d 个"
			% [_st.bench_used(), _st.field.size(), _ship_nodes().size()])
	_line("相机距离 = %.1f   board_view_zoom = %.2f   背景 = %s"
			% [float(_arena.orion_cam.call("get_distance")),
			   float(_arena.board_view_zoom), String(_arena.background_id)])
	_line("HUD 已隐藏：%s" % str(_hud == null or _hud.visible == false))
	_line("")

	for m in MODES:
		await _case(m)
	# 收尾还原
	if _hud != null:
		_hud.visible = true
	_set_background_visible(true)
	_apply(MODES[0])
	_flush()
	get_tree().quit(0)


# ------------------------------------------------------------------ 用例

func _case(m: Dictionary) -> void:
	var id := String(m["id"])
	_apply(m)
	# 材质侧提亮：**直接改静态缓存里的 ShaderMaterial** ——
	# 同一艘船的第 i 个面共用一个实例，改一次即全场生效，不必 walk 节点树。
	#
	# ⚠️ 必须**在截图之前**调用。第一次写成了在截图之后，于是每张图用的都是
	#    上一组的参数（症状：`cur` 量出来等于常量默认值那一档，而 `lift140`
	#    量出来恰好是恒等基线）—— 参数没错、图也没错，错的是顺序，
	#    而且**不会报任何错**。
	var touched := _apply_material(float(m.get("lift", 1.0)), float(m.get("gain", 1.0)))
	for _i in 8:
		await get_tree().process_frame

	_set_background_visible(true)
	for _i in 3:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://sbright_%s_real.png" % id)

	# ② 球幕隐藏 —— 只留船（近黑底），供建掩膜
	_set_background_visible(false)
	for _i in 3:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://sbright_%s_iso.png" % id)

	_set_background_visible(true)

	# 回读**引擎里真实生效的值**（防「改了常量但没接上」这种静默失效）
	var env: Environment = _we.environment if _we != null else null
	var sky_e := -1.0
	if env != null and env.sky != null and env.sky.sky_material is PanoramaSkyMaterial:
		sky_e = (env.sky.sky_material as PanoramaSkyMaterial).energy_multiplier
	_line("%-14s amb=%.2f sun=%.2f head=%.2f sky=%.2f lift=%.2f gain=%.2f"
			% [id, m["amb"], m["sun"], m["head"], m["sky"], m["lift"], m["gain"]])
	_line("               实际生效 amb=%.2f sun=%.2f head=%.2f sky=%.2f | 材质实例 %d 个"
			% [env.ambient_light_energy if env != null else -1.0,
			   _sun.light_energy if _sun != null else -1.0,
			   _arena.camera_headlight.light_energy if _arena.camera_headlight != null else -1.0,
			   sky_e, touched])


## 把 lift / gain 推给所有已生成的船体 ShaderMaterial（共享实例）
## 返回改到的材质个数 —— 0 表示这个场景里一艘船都没走 EveShipMaterial，
## 那这轮"材质提亮"就是在测空气（必须能在报告里看出来）。
func _apply_material(lift: float, gain: float) -> int:
	var cache: Dictionary = EveShipMaterial._cache
	var n := 0
	for key in cache.keys():
		var sm = cache[key]
		if sm is ShaderMaterial:
			(sm as ShaderMaterial).set_shader_parameter("albedo_lift", lift)
			(sm as ShaderMaterial).set_shader_parameter("albedo_gain", gain)
			n += 1
	return n


# ------------------------------------------------------------------ 光照

## 只在**当前代码**的基础上改这四个数值，不另写一套建光逻辑 ——
## 这样探针量与游戏里跑的是同一条路径（否则量的是探针自己）。
func _apply(m: Dictionary) -> void:
	# 走正式入口重建 IBL Sky（与游戏里一模一样那条路径）
	_arena.set_background(String(_arena.background_id))
	if _we == null or _we.environment == null:
		return
	var env: Environment = _we.environment
	if env.sky != null and env.sky.sky_material is PanoramaSkyMaterial:
		(env.sky.sky_material as PanoramaSkyMaterial).energy_multiplier = float(m["sky"])
	env.ambient_light_energy = float(m["amb"])
	if _sun != null:
		_sun.light_energy = float(m["sun"])
	if _arena.camera_headlight != null:
		_arena.camera_headlight.light_energy = float(m["head"])


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
## （口径与 verify_run._force_offers_distinct 完全一致）
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
	var f := FileAccess.open("user://sbright_report.txt", FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(_lines))
		f.close()
