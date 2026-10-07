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

const W := 1920
const H := 1080


func _ready() -> void:
	await _shot_list()
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


func _shot(tag: String, info: Dictionary, stage: String) -> void:
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
