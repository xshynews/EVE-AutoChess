extends Node

## 备战席「购买 → 立绘上格」实机验证探针（非 headless）
##
## ══════════════════════════════════════════════════════════════════
##  它为什么存在
## ══════════════════════════════════════════════════════════════════
##  用户报告：「点击购买之后，就该让船上备战席啊，现在怎么还停留在
##  改版前的地方」。这句抱怨有两个可能，而它们在截图上看不出区别
##  （都表现为「格子里没船」），只能靠打印切开：
##    ① 名单**收到了但没画出来**（立绘资源缺 / 绘制矩形退化）；
##    ② 名单**压根没收到**（set_bench_fleet 没被调用 / 链路断了）。
##
##  ⚠️ 2026-09-23：备战席改画 2D 立绘（EveBenchRail），3D 模型层停用。
##     本探针随之改写 —— 现在量的是**格带收到的名单**与**立绘资源是否命中**，
##     不再是 holder 的世界/屏幕坐标。
##     文件名与验证意图都保留（「买完之后格子里到底有没有船」这件事没变）。
##
## ── 探针里的两条路径，别混 ────────────────────────────────────────
##   ① `_buy()`        = **真实购买**（走 _on_shop_buy）→ 验证链路端到端
##   ② `_fill_demo()`  = **直接喂 HUD**（构造多艘多星级）→ 只为了看视觉
##
## ⚠️ ② 为什么不用「run.set("bench", [...])」那种写法：
##    实测它**静默不生效** —— run.bench 原地不动、控制台一个字都不打。
##    原因是 bench 是**带类型标注**的数组，塞一个无类型 Array 进去会被拒。
##    这正是本工程反复强调的「不报错的分叉」，探针里踩一次就够了。
##
## ── 跑法（⚠️ 不要加 --headless，headless 下截图不上报）────────────
##   "C:/godot/Godot_v4.7.1-stable_win64_console.exe" \
##     --path "F:/evezzq/eve自走棋918" --quit-after 300 \
##     res://tools/probe_bench_buy.tscn

const SCENE_PATH := "res://scenes/battle_scene.tscn"
const HUD_SCRIPT := preload("res://scripts/ui/eve_hud_root.gd")
const BENCH_RAIL_SCRIPT := preload("res://scripts/ui/panels/eve_bench.gd")
const OUT_SHOT := "user://bench_buy.png"
## 备战席特写（全图看不清 150px 的格子，裁出来放大 2 倍）
const OUT_ZOOM := "user://bench_buy_zoom.png"

var _battle: Node = null
var _frame := 0
var _shot_done := false


func _ready() -> void:
	_battle = load(SCENE_PATH).instantiate()
	add_child(_battle)


func _process(_delta: float) -> void:
	_frame += 1
	if _frame == 6:
		_dump("购买前")
	if _frame == 10:
		_buy()
	if _frame == 24:
		_dump("购买后（真实链路）")
	if _frame == 26:
		_fill_demo()
	if _frame == 34:
		_dump("构造 7 艘（含多星级，末格留空）")
	if _frame == 40 and not _shot_done:
		_shot_done = true
		_shot()


## ① 真实购买一艘（端到端：商店 → run.buy → 信号 → _refresh → hud.set_bench_fleet）
func _buy() -> void:
	var run = _battle.get("run")
	if run == null:
		print("[BUY] run 缺失")
		return
	# 保证买得起（真实玩家的星币由经济系统给，这里只为了排除「买不起」这条分支）
	run.set("coin", 99)
	_battle.call("_on_shop_buy", 0)
	print("[BUY] 购买后 bench 数量=%d  内容=%s" % [_bench_n(run), str(run.get("bench"))])


## ② 直接喂 HUD：7 艘、三档星级、末格留空。
##
## 2026-09-23：**米玛塔尔 4 艘 + 其他派系 3 艘混排**。
## 混排是刻意的 —— 只喂米玛塔尔时，截图里没有亮度基准，
## 「够不够亮」无从判断（本探针踩过这个坑：全米玛塔尔那一版
## 看起来"都暗"，但其实四艘已经追平了参照）。
## drake(加达里) / tristan(盖伦特) / punisher(艾玛) 就是那三根尺子。
func _fill_demo() -> void:
	var hud = _battle.get("hud")
	if hud == null:
		return
	var keys: Array = [&"rifter", &"thrasher", &"tempest", &"rupture",
			&"drake", &"tristan", &"punisher"]
	var stars: Array = [1, 2, 3, 1, 2, 1, 3]
	var entries: Array = []
	for i in keys.size():
		entries.append({"ship_key": keys[i], "star": stars[i]})
	hud.call("set_bench_fleet", entries)
	print("[BUY] 已直接喂 HUD %d 艘（这条路径只验视觉，不验购买链路）" % keys.size())


## 读 run.bench 的长度（Array 类型不对时返回 -1）
func _bench_n(run) -> int:
	var b = run.get("bench")
	return (b as Array).size() if b is Array else -1


func _dump(tag: String) -> void:
	var hud = _battle.get("hud")
	if hud == null:
		print("[BUY] hud 缺失")
		return
	var rail = hud.get("bench_rail")
	if rail == null:
		print("[BUY] bench_rail 缺失（HUD 侧没建出格带）")
		return

	print("[BUY] ==== %s ====" % tag)
	print("[BUY] HUD.RECT_BENCH(常量)=%s" % str(HUD_SCRIPT.RECT_BENCH))
	print("[BUY] rail.position=%s  rail.size=%s" % [
		str(rail.get("position")), str(rail.get("size"))])

	var area: Rect2 = BENCH_RAIL_SCRIPT.cell_area(HUD_SCRIPT.RECT_BENCH.size)
	var cw: float = HUD_SCRIPT.RECT_BENCH.size.x / float(HUD_SCRIPT.BENCH_SLOTS)
	print("[BUY] 格区 y=%.0f..%.0f（高 %.0f）  单格宽=%.1f  dragging=%d  hover=%d" % [
		HUD_SCRIPT.RECT_BENCH.position.y + area.position.y,
		HUD_SCRIPT.RECT_BENCH.position.y + area.position.y + area.size.y,
		area.size.y, cw,
		int(rail.get("dragging_index")), int(rail.get("hover_index"))])

	var fleet = rail.get("fleet")
	if not (fleet is Array):
		print("[BUY] ⚠️ fleet 不是 Array（实际 %s）—— set_bench_fleet 没接上" % type_string(typeof(fleet)))
		return
	var arr := fleet as Array
	print("[BUY] 名单长度=%d / 槽位=%d   （run.bench=%d）" % [
		arr.size(), HUD_SCRIPT.BENCH_SLOTS, _bench_n(_battle.get("run"))])
	for i in arr.size():
		var e = arr[i]
		if not (e is Dictionary) or (e as Dictionary).is_empty():
			print("[BUY]   槽%d  （空）" % i)
			continue
		var d := e as Dictionary
		var k := StringName(d.get("ship_key", &""))
		var tex_ok := EveShipArt.portrait(k) != null
		var bbox := EveShipArt.used_rect(k)
		# 只报「能不能放进格子」，不在这里复算绘制矩形 ——
		# 那会给 EveBenchRail 的绘制几何造出第二份真相源。
		var s := minf((cw - 4.0) / maxf(bbox.size.x, 1.0),
				area.size.y / maxf(bbox.size.y, 1.0))
		var fit := bbox.size * s
		var shape := "横" if bbox.size.x > bbox.size.y else "竖"
		print("[BUY]   槽%d  %-14s ★%d  %s构图 立绘=%-4s bbox=%.0f×%.0f  可画=%.0f×%.0f" % [
			i, String(k), int(d.get("star", 1)), shape,
			"有" if tex_ok else "**缺**",
			bbox.size.x, bbox.size.y, fit.x, fit.y])


func _shot() -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(OUT_SHOT)
	print("[BUY] 截图 -> %s" % ProjectSettings.globalize_path(OUT_SHOT))

	# 再裁一张备战席特写（150px 的格子在整屏图里看不清立绘细节）
	var vp := get_viewport().get_visible_rect().size
	var sx := vp.x / 1920.0
	var sy := vp.y / 1080.0
	var r := Rect2i(int(340.0 * sx), int(748.0 * sy), int(1240.0 * sx), int(170.0 * sy))
	if r.size.x > 8 and r.size.y > 8 and r.end.x <= img.get_width() \
			and r.end.y <= img.get_height():
		var crop := img.get_region(r)
		crop.resize(crop.get_width() * 2, crop.get_height() * 2,
				Image.INTERPOLATE_NEAREST)
		crop.save_png(OUT_ZOOM)
		print("[BUY] 特写 -> %s" % ProjectSettings.globalize_path(OUT_ZOOM))
	else:
		print("[BUY] 特写裁剪区越界，跳过：%s（图 %d×%d）" % [
			str(r), img.get_width(), img.get_height()])
