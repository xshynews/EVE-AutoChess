extends Node

## 探针：**准备阶段点击我方舰船，档案会不会跟着换？**
##
## 玩家反馈：「准备阶段点击舰船，舰船档案不会显示，只会显示战斗中最后点的那一个，
##   而不是点击选中的那个」。
##
## 本探针只做一件事：用**真实鼠标事件**（motion → press → release，中途不移动）
## 点战场上的第 2 艘我方舰船，然后看 `hud.get_selected_ship()` 与档案窗的 `ship`
## 有没有变成它。
##
## ⚠️ 必须非 headless：要走真实的 GUI 仲裁 + 3D 反投影。
## 用法：
##     "$GODOT_BIN" --path . res://tools/probe_prep_select.tscn
##
## 三个断言的对照设计（缺一个就会得出错误结论）：
##   A 准备阶段·点船（不移动）     ← 玩家报的那一下
##   B 准备阶段·直接调 _unhandled_input ← 若 A 失败 B 成功 ⇒ 是 GUI 挡的（另一个 bug）
##   C 战斗阶段·点船（不移动）     ← 已知能用的路径，用来证明探针手法本身有效

const SCENE_PATH := "res://scenes/battle_scene.tscn"

var _battle: Node = null
var _hud: Control = null
var _dos: Control = null
var _frame := 0
var _target: EveShip = null
var _fail := 0


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		print("✗ 必须非 headless")
		get_tree().quit(1)
		return
	_battle = (load(SCENE_PATH) as PackedScene).instantiate()
	add_child(_battle)


func _process(_dt: float) -> void:
	_frame += 1
	match _frame:
		40:
			_battle.call("begin_prep")
		50:
			_setup_fleet()
		60:
			_hud = _battle.get("hud")
			_dos = _hud.get("dossier_window") if _hud != null else null
		90:
			_probe_prep()
		110:
			_probe_prep_direct()
		130:
			_probe_bench()
		150:
			_probe_real_drag()
		170:
			_battle.call("start_battle")
		230:
			_probe_battle()
		260:
			print("\n=== 结论：%s ===" % ("全部符合预期" if _fail == 0
					else "%d 项不符合预期" % _fail))
			get_tree().quit(0 if _fail == 0 else 3)


# ------------------------------------------------------------------ 造舰队

## 开局是空场（`field` 里一条都没有），必须先买 + 上场，否则探针无从点起。
##
## ⚠️ 走**真实链路**（`_on_shop_buy` → `deploy_from_bench`），不往内部数组里硬塞：
##    硬塞绕过了 `changed` 信号，`_respawn_own_fleet` 不会跑，3D 舰队依然是空的。
func _setup_fleet() -> void:
	var run = _battle.get("run")
	if run == null:
		print("✗ run 缺失")
		return
	run.set("coin", 99)
	for i in 3:
		_battle.call("_on_shop_buy", i)
	var bench: Array = run.call("bench_entries")
	# ⚠️ 商店抽的三张可能同型号（实测抽到过两张「检察官级」）⇒ 名字一样就看不出
	#    档案到底换没换。这里把三条 entry 改写成三个**确定的、互不相同**的型号，
	#    让输出一眼能读。改的是 `bench` 里的字典（引用），后面 deploy 走真实链路。
	var keys := [&"punisher", &"kestrel", &"rifter"]
	for i in mini(bench.size(), keys.size()):
		(bench[i] as Dictionary)["ship_key"] = keys[i]
		(bench[i] as Dictionary)["star"] = 1
	print("[setup] 买完 bench=%d 艘，改写为 %s" % [bench.size(), str(keys)])
	var cells := [Vector2i(8, 4), Vector2i(9, 6)]
	# ⚠️ 每次都用 index 0：`deploy_from_bench()` 会把该条**从 bench 摘掉**，
	#    后面的条目整体前移 ⇒ 连调 (0)(1)(2) 会错位（实测第 3 次报「这一格是空的」）。
	for i in cells.size():
		var c: Vector2i = cells[i]
		var r: Dictionary = run.call("deploy_from_bench", 0, c.x, c.y)
		print("[setup] 上场 bench[0] → 第 %d 行第 %d 列 : ok=%s %s"
				% [c.x + 1, c.y + 1, str(r.get("ok")), str(r.get("reason"))])
	_battle.call("_refresh_run_ui")
	print("[setup] 场上 %d 艘 · 备战席还剩 %d 艘（留给用例 D / E）"
			% [(_battle.get("_own_ships") as Array).size(),
			(run.call("bench_entries") as Array).size()])


## A：准备阶段，真实鼠标点第 2 艘（不移动）
func _probe_prep() -> void:
	var ships: Array = _battle.get("_own_ships")
	print("\n--- A 准备阶段·真实点击（不移动）---")
	print("我方舰队 %d 艘：%s" % [ships.size(),
			", ".join(_names(ships))])
	if ships.size() < 2:
		print("✗ 舰队不足 2 艘，无法区分「第 0 艘」")
		_fail += 1
		return
	_target = ships[1]
	var before: EveShip = _hud.call("get_selected_ship") as EveShip
	print("点击前档案 = %s" % _name_of(before))
	var p := _canvas_of(_target)
	print("目标 = %s @ 画布 %s" % [_target.ship_name, str(p)])
	_click(p)
	var after: EveShip = _hud.call("get_selected_ship") as EveShip
	print("点击后档案 = %s" % _name_of(after))
	print("档案窗 .ship = %s" % _name_of(_dos.get("ship") as EveShip))
	if after == _target:
		print("✓ A 通过")
	else:
		print("✗ A 失败：点的是 %s，档案却是 %s"
				% [_target.ship_name, _name_of(after)])
		_fail += 1


## B：归因 —— 按下那一下会不会被「拖放」拿走（修复前 = true，这就是根因）。
func _probe_prep_direct() -> void:
	print("\n--- B 归因：按下是否被拖放抢走 ---")
	if _target == null:
		print("跳过（A 没拿到目标）")
		return
	var p := _canvas_of(_target)
	var got: bool = _battle.call("_try_begin_drag", p)
	print("B _try_begin_drag(%s) = %s（true = 按下即进入拖放）" % [str(p), str(got)])
	print("B 说明：拖放为 true 时，松手事件被 `_input` 吞掉 ⇒ 修复前那条"
			+ "「松手→选中」永远走不到")
	# 清理，别把拖动态留给 C
	_battle.call("_cancel_drag", "")


## C：战斗中点击（已知能用的路径）
func _probe_battle() -> void:
	print("\n--- C 战斗阶段·真实点击（不移动）---")
	var ships: Array = _battle.get("_own_ships")
	if ships.size() < 2:
		print("跳过（舰队不足）")
		return
	var t: EveShip = ships[1]
	if not t.alive:
		print("跳过（第 2 艘已阵亡）")
		return
	_hud.call("show_ship", ships[0])
	print("重置后档案 = %s" % _name_of(_hud.call("get_selected_ship")))
	var p := _canvas_of(t)
	_click(p)
	var after: EveShip = _hud.call("get_selected_ship") as EveShip
	print("点击后档案 = %s" % _name_of(after))
	if after == t:
		print("✓ C 通过（探针手法有效）")
	else:
		print("✗ C 失败：%s → %s（探针或战场都不可靠）"
				% [t.ship_name, _name_of(after)])
		_fail += 1


## D：备战席的船（2D 轨道，3D 拾取永远点不中）
func _probe_bench() -> void:
	print("\n--- D 准备阶段·点备战席的船 ---")
	var run = _battle.get("run")
	var bench: Array = run.call("bench_entries")
	if bench.is_empty():
		print("跳过（备战席是空的）")
		return
	var e: Dictionary = bench[0]
	var p := _bench_slot_center(0)
	print("备战席第 1 格 = 第 %s 格 @ 画布 %s"
			% [String(e.get("ship_key", "")), str(p)])
	_click(p)
	var after: EveShip = _hud.call("get_selected_ship") as EveShip
	print("点击后档案 = %s" % _name_of(after))
	if after != null and String(after.ship_key) == String(e.get("ship_key", "")):
		print("✓ D 通过")
	else:
		print("✗ D 失败：期望 %s" % String(e.get("ship_key", "")))
		_fail += 1


## E：**回归**——真拖动必须还是拖动（别被 `TAP_SLOP` 吞成点击）。
##
## 做法：把备战席那艘拖到商店出售区松手。位移大 ⇒ 走真拖放。
## ⚠️ 这条断言的价值在于「变的是数据」：只断言「松手了」证明不了动作执行。
func _probe_real_drag() -> void:
	print("\n--- E 回归：真拖动（拖到商店出售）---")
	var run = _battle.get("run")
	var before: int = (run.call("bench_entries") as Array).size()
	if before == 0:
		print("跳过（备战席已空）")
		return
	var from := _bench_slot_center(0)
	var sell: Rect2 = _hud.call("sell_zone_rect")
	var to := sell.get_center()
	print("从 %s 拖到 %s（出售区 %s）" % [str(from), str(to), str(sell)])
	_drag_mouse(from, to)
	var after: int = (run.call("bench_entries") as Array).size()
	print("备战席 %d → %d 艘" % [before, after])
	if after == before - 1:
		print("✓ E 通过（真拖放没被吞成点击）")
	else:
		print("✗ E 失败：拖动没生效，`TAP_SLOP` 可能把拖动误判成点击了")
		_fail += 1


# ------------------------------------------------------------------ 工具

## 备战席第 i 格的屏幕中心（画布坐标）。
## ⚠️ 几何口径抄 `EveBenchRail.slot_at()`：x 按 `size.x / SLOTS` 等分。
func _bench_slot_center(i: int) -> Vector2:
	var rail: Control = _hud.get("bench_rail")
	if rail == null:
		return Vector2.ZERO
	var r := rail.get_global_rect()
	var slots := 8.0
	return r.position + Vector2(r.size.x * (float(i) + 0.5) / slots, r.size.y * 0.5)


## 真实鼠标拖动：press → 分段 motion → release
func _drag_mouse(from_canvas: Vector2, to_canvas: Vector2) -> void:
	var xf := get_viewport().get_final_transform()
	var a: Vector2 = xf * from_canvas
	var b: Vector2 = xf * to_canvas
	var mv := InputEventMouseMotion.new()
	mv.position = a
	mv.global_position = a
	get_viewport().push_input(mv)
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = a
	down.global_position = a
	get_viewport().push_input(down)
	for k in range(1, 7):
		var p := a.lerp(b, float(k) / 6.0)
		var mm := InputEventMouseMotion.new()
		mm.position = p
		mm.global_position = p
		get_viewport().push_input(mm)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = b
	up.global_position = b
	get_viewport().push_input(up)


func _canvas_of(ship: EveShip) -> Vector2:
	var arena = _battle.get("arena")
	return arena.call("world_to_screen", ship.body.position + Vector3(0, 4, 0))


## 真实鼠标：motion → press → release，**全程不动**
func _click(p_canvas: Vector2) -> void:
	var xf := get_viewport().get_final_transform()
	var p: Vector2 = xf * p_canvas
	var mv := InputEventMouseMotion.new()
	mv.position = p
	mv.global_position = p
	get_viewport().push_input(mv)
	for down in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = down
		ev.position = p
		ev.global_position = p
		get_viewport().push_input(ev)


func _names(arr: Array) -> PackedStringArray:
	var out := PackedStringArray()
	for s in arr:
		out.append(String(s.ship_name))
	return out


func _name_of(s) -> String:
	if s == null:
		return "null"
	return String(s.ship_name)
