extends Node
## 结算页实机出图 —— ★ 打捞区（2026-10-04 改版：按钮在**下方**，逐艘点）
##
## 出两张，对应用户给的两张参考图：
##   ① `salvage_list.png`   —— 有残骸：逐艘一个「打捞」按钮 + 顶部红字警告
##   ② `salvage_empty.png`  —— 打捞完：暂无残骸 + 修复队列 + 持有星币 + 关闭
##
## 直接实例化 `EveResult` 面板喂数据，不走整局：残骸状态不好稳定复现。
const RESULT_SCRIPT := preload("res://scripts/ui/panels/eve_result.gd")
const RUNSTATE_SCRIPT := preload("res://scripts/core/eve_run_state.gd")
const SHIP_DB := preload("res://scripts/core/eve_ship_database.gd")
const UI := preload("res://scripts/ui/eve_ui_scale.gd")
const LAYOUT := preload("res://scripts/ui/eve_layout.gd")
const HUD := preload("res://scripts/ui/eve_hud_root.gd")
const FONT := preload("res://scripts/ui/eve_font.gd")

const W := 1920
const H := 1080


func _ready() -> void:
	# ★ 2026-10-25 手机档量窗探针（MuMu 实机「打捞列表看不见」的诊断）：
	#   `-- --measure` ⇒ 按真机窗口尺寸 + 手机档跑一次，打印几何数字。
	if "--measure" in OS.get_cmdline_user_args():
		await _measure_mobile()
		get_tree().quit()
		return
	await _shot_list()
	# ★ 2026-10-13：「放弃打捞」确认框换成 EVE 窗口语言版（EveConfirmDialog）后的出图
	await _shot_ask()
	await _shot_empty()
	get_tree().quit()


## 造一份「本回合击毁 3 艘（敌我都有）」的真残骸数据。
func _make_info(coin: int) -> Dictionary:
	var st = RUNSTATE_SCRIPT.new()
	st.node_index = 7
	st.coin = coin
	var ships: Array = [
		SHIP_DB.by_id("bantam"),      # 我方 1 费（盾抗后勤）
		SHIP_DB.by_id("osprey"),      # 我方 3 费
		SHIP_DB.by_id("dominix"),     # 敌方 4 费
		SHIP_DB.by_id("hurricane"),   # 敌方 3 费
	]
	# 标阵营：我方 0 / 敌方 1（定价靠它：×0.5 vs ×1.0）
	var teams: Array = [0, 0, 1, 1]
	var srcs: Array = []
	for i in ships.size():
		var d: Dictionary = ships[i]
		srcs.append({
			"star": 1,
			"atk_base": float(d.get("attack", 10.0)),
			"def_base": float(d.get("armor_struct", 1.0)),
			"shot": float(d.get("attack", 10.0)),
			"m": 1.0, "team": teams[i],
		})
	# 造 4 个 EveShip 才能带 team —— 这里直接用带 team 的最小对象
	var objs: Array = []
	for i in ships.size():
		var sh = SHIP_DB.instantiate_by_id(String((ships[i] as Dictionary).get("ship_key", "")), int(teams[i]), 7000 + i)
		objs.append(sh)
	st.resolve_battle(0, objs, srcs, 1.0)
	st.coin = coin
	return st.salvage_info()


## 手机档几何量测（**非无头**；窗口尺寸按 MuMu 常见 1024×600）。
##
## 要回答的问题：结算页在手机档（倍率 1.35、字号按屏高比例）里
##   ① 窗口实际多高、和设计矩形差多少；
##   ② 打捞列表有几行、落在窗口内的什么位置（**看不见**是「行没建」还是「行在窗下」）。
func _measure_mobile() -> void:
	UI.force_mobile = true
	# 真机移动档字号 120%（探针默认不会走 `load_from_settings`，必须显式设）
	FONT.scale = FONT.MOBILE_DEFAULT
	var win := get_window()
	win.content_scale_factor = UI.MOBILE
	# MuMu 常见几档都量一遍：设计空间高度不同 ⇒ 字号档 / 窗高算式都会变。
	for sz in [Vector2i(1024, 600), Vector2i(1280, 720), Vector2i(1600, 900),
			Vector2i(1920, 1080), Vector2i(2560, 1440)]:
		win.size = sz
		await get_tree().process_frame
		await get_tree().process_frame
		await _measure_one(win)


func _measure_one(win: Window) -> void:
	var d := LAYOUT.design_space(win)
	var rw: Variant = RESULT_SCRIPT.new()
	add_child(rw)
	await get_tree().process_frame
	var tbl: Dictionary = HUD.mobile_rects(d, 0.0, false)
	var rect: Rect2 = tbl.get("result", Rect2())
	rw.call("set_window_rect", rect.position.x, rect.position.y, rect.size.x, rect.size.y)
	rw.call("show_result", {
		"won": true, "damage": 0, "beacon": 88, "beacon_before": 88,
		"beacon_max": 100, "destroyed": 3, "alive": 1, "total": 2,
		"xp": 2, "wreck": true, "wreck_count": 3, "wreck_name": "",
		"node": 1, "stage": "拦截成功", "ending": "", "reason": "敌方全灭",
	})
	rw.call("refresh_salvage", _make_info(23), false)
	var c0: Control = rw.get("content")
	print("[measure]   刷新后立刻：窗高 %.1f · content 最小 %s"
			% [(rw as Control).size.y, str(c0.get_combined_minimum_size())])
	for i in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw

	var c: Control = rw.get("content")
	var sec: Control = rw.get("_salvage_section")
	var lst: Control = rw.get("_salvage_list")
	var host: Control = rw.get("_content_host")
	var sec_r := Rect2(sec.global_position - host.global_position, sec.size)
	print("[measure] 窗口 %s · 设计空间 %s · 设计矩形 %s" % [str(win.size), str(d),
			str(rect)])
	print("[measure]   窗 size = %s · pos = %s" % [str((rw as Control).size),
			str((rw as Control).position)])
	print("[measure]   host = %s · content 最小 %s · 实际 %s" % [
			str(host.size), str(c.get_combined_minimum_size()), str(c.size)])
	print("[measure]   打捞区 visible=%s · 最小高 %.0f · 宿主内矩形 %s · 列表 %d 行 %s"
			% [str(sec.visible), sec.get_combined_minimum_size().y, str(sec_r),
				lst.get_child_count(), str(lst.size)])
	print("[measure]   ★ 打捞区底部在宿主内？%s（底 %.1f / 宿主 %.1f）"
			% ["是" if sec_r.end.y <= host.size.y + 0.5 else "否",
				sec_r.end.y, host.size.y])
	var img: Image = win.get_texture().get_image()
	if img != null:
		img.save_png("user://result_mobile_measure_%dx%d.png" % [win.size.x, win.size.y])
	rw.queue_free()


func _shot_list() -> void:
	var info := _make_info(23)
	await _shot("salvage_list", info, "节点 7 · 遭遇战")


## 打捞完两艘后的形态：先下单再截图。
func _shot_empty() -> void:
	var st = RUNSTATE_SCRIPT.new()
	st.node_index = 7
	st.coin = 23
	var ships: Array = [SHIP_DB.by_id("bantam"), SHIP_DB.by_id("dominix")]
	var teams: Array = [0, 1]
	var srcs: Array = []
	for i in ships.size():
		var d: Dictionary = ships[i]
		srcs.append({"star": 1, "atk_base": float(d.get("attack", 10.0)),
			"def_base": float(d.get("armor_struct", 1.0)),
			"shot": float(d.get("attack", 10.0)), "m": 1.0, "team": teams[i]})
	var objs: Array = []
	for i in ships.size():
		objs.append(SHIP_DB.instantiate_by_id(
			String((ships[i] as Dictionary).get("ship_key", "")), int(teams[i]), 7100 + i))
	st.resolve_battle(0, objs, srcs, 1.0)
	st.coin = 23
	st.salvage_order([0, 1])          # 两艘都打捞掉
	await _shot("salvage_empty", st.salvage_info(), "节点 7 · 遭遇战")


## 打捞确认框（2026-10-13 新版）：结算页 + 居中模态框同框。
func _shot_ask() -> void:
	var info := _make_info(23)
	await _shot("salvage_ask", info, "节点 7 · 遭遇战", true)


func _shot(tag: String, info: Dictionary, stage: String, open_ask: bool = false) -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(W, H)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)

	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.06, 0.085)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vp.add_child(bg)

	var rw: Variant = RESULT_SCRIPT.new()
	vp.add_child(rw)
	await get_tree().process_frame
	await get_tree().process_frame
	rw.call("set_window_rect", 700.0, 250.0, 520.0, 420.0)
	rw.call("show_result", {
		"won": true, "damage": 0, "beacon": 88, "beacon_before": 88,
		"beacon_max": 100, "destroyed": 4, "alive": 3, "total": 4,
		"xp": 2, "wreck": int(info.get("total", 0)) > 0,
		"wreck_count": int(info.get("total", 0)),
		"wreck_name": String(info.get("name", "")),
		"node": 7, "stage": stage, "ending": "", "reason": "敌方全灭",
	})
	# ★ 打捞数据**单独推**（与主控 `_popup_result()` 同一姿势）
	rw.refresh_salvage(info, false)
	rw.visible = true
	await get_tree().process_frame
	await get_tree().process_frame
	if open_ask:
		# 与主控 `_maybe_confirm_leftover_wrecks()` 同一入口（3 艘未打捞）
		rw.call("ask_abandon_salvage", 3)
		await get_tree().process_frame
		await get_tree().process_frame
	await RenderingServer.frame_post_draw

	var img := vp.get_texture().get_image()
	if img == null:
		print("[probe] 截图失败：%s" % tag)
	else:
		img.save_png("user://%s.png" % tag)
		var sec: Control = rw.get("_salvage_section")
		var rows: int = (rw.get("_salvage_list") as Node).get_child_count()
		print("[probe] %s.png  结算页整体高=%.0f · 打捞区高=%.0f · 列表行数=%d"
			% [tag, (rw as Control).size.y,
			sec.get_combined_minimum_size().y, rows])
	vp.queue_free()
