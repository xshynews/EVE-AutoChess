extends Node

## 滚动交互自检 —— ★ 2026-10-31（用户：「战损多的时候 后面的船打捞不到 / 文本框也拉不动」）
##
## 这两个反馈指向同一类病：**能滚 ≠ 玩家滚得到**。用数字把三条判据钉死：
##
##   ① 滚动条够宽（≥ 10px）—— 8px 在 1080p 上压不住，症状是「手柄一样，抓不到」
##   ② 打捞列表高度**永远是整行**（行高 22）—— 给半行 = 按钮被裁一半
##   ③ 战斗日志：玩家翻上去看历史时，**新日志不能抢滚动位置**
##      （旧实现无条件 `_scroll_to_bottom()`，战斗里每 0.5 秒一条 ⇒ 拖上去就被拽回）
##
## ⚠️ 全部走真实面板实例 + 真布局（`await` 若干帧），不吃任何模拟数据。

const LOG_PANEL := preload("res://scripts/ui/panels/eve_combat_log.gd")
const RESULT_PANEL := preload("res://scripts/ui/panels/eve_result.gd")

var _pass := 0
var _fail := 0


func _ok(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
		print("  ✓ " + msg)
	else:
		_fail += 1
		print("  ✗ " + msg)


func _wait(frames: int = 3) -> void:
	for i in frames:
		await get_tree().process_frame


func _ready() -> void:
	print("═══ 滚动交互 自检 ═══")
	await _test_log_scroll()
	await _test_salvage_rows()
	print("═══ RESULT passed=%d failed=%d ═══" % [_pass, _fail])


# ---------------------------------------------------------------- 战斗日志
func _test_log_scroll() -> void:
	var w = LOG_PANEL.new()
	add_child(w)
	w.set_window_rect(0, 0, 172, 200)
	await _wait(4)

	var sc: ScrollContainer = w.get("_scroll")
	_ok(sc != null, "战斗日志有滚动区")
	if sc == null:
		w.queue_free()
		return

	_ok(sc.get_v_scroll_bar().custom_minimum_size.x >= 10.0,
			"战斗日志滚动条宽 ≥ 10px（实际 %.0f）"
					% sc.get_v_scroll_bar().custom_minimum_size.x)

	# 灌够条数，让内容明显溢出
	for i in 80:
		w.append_text("第 %d 条测试日志，内容故意长一点把宽度占满" % i)
	await _wait(6)
	var bar := sc.get_v_scroll_bar()
	_ok(bar.max_value - bar.page > 20.0,
			"80 条之后确实可滚（max−page=%.0f）" % (bar.max_value - bar.page))

	# ① 翻到顶，再来一条新日志 —— 位置不能动
	sc.scroll_vertical = 0
	await _wait(3)
	w.append_text("新来的一条（不应抢滚动位置）")
	await _wait(4)
	_ok(sc.scroll_vertical == 0,
			"玩家翻到顶部时，新日志不抢滚动位置（实际 %d）" % sc.scroll_vertical)

	# ② 回到底，再来一条 —— 应该自动跟随
	sc.scroll_vertical = int(maxf(0.0, bar.max_value - bar.page))
	await _wait(3)
	var before := sc.scroll_vertical
	w.append_text("再来一条（贴底时应当跟随）")
	await _wait(5)
	_ok(sc.scroll_vertical >= before,
			"贴底时新日志自动跟随（%d → %d）" % [before, sc.scroll_vertical])

	w.queue_free()
	await _wait(2)


# ---------------------------------------------------------------- 打捞列表
func _test_salvage_rows() -> void:
	# 12 艘残骸 = 单列 12 行（420 宽装不下两列）
	var info := _salvage_info(12)
	var w = RESULT_PANEL.new()
	add_child(w)
	await _wait(3)
	w.set_window_rect(0, 0, 420.0, 420.0)
	w.show_result({
		"won": true, "damage": 0, "beacon": 88, "beacon_before": 88,
		"beacon_max": 100, "destroyed": 12, "alive": 1, "total": 2,
		"xp": 2, "wreck": true, "wreck_count": 12, "wreck_name": "",
		"node": 7, "stage": "拦截成功", "ending": "", "reason": "敌方全灭",
	})
	w.refresh_salvage(info, false)
	w.visible = true
	await _wait(6)

	var sc: ScrollContainer = w.get("_salvage_scroll")
	var lst: GridContainer = w.get("_salvage_list")
	_ok(sc != null and lst != null, "结算页有打捞滚动区与列表")
	if sc != null and lst != null:
		var rows := int(ceil(float(lst.get_child_count())
				/ float(maxi(1, lst.columns))))
		# ⚠️ 常量走脚本本身取（`w.get("SALVAGE_ROW_H")` 拿不到 const）
		var row_h: float = float(RESULT_PANEL.SALVAGE_ROW_H)
		var h := sc.size.y
		# ① 高度必须是整行（允许 0.6px 的浮点余量）
		_ok(absf(h - roundf(h / float(row_h)) * float(row_h)) <= 0.6,
				"打捞列表高 %.0f 是整行（行高 %.0f，共 %d 行）" % [h, row_h, rows])
		# ② 内容比视口高时**必须**有可滚空间（否则后面的船真的点不到）
		var need := float(rows) * float(row_h)
		if need > h + 0.6:
			var bar := sc.get_v_scroll_bar()
			_ok(bar.max_value - bar.page > 0.0,
					"内容 (%d 行) 超出视口时留有可滚空间（可滚 %.0f）"
							% [rows, bar.max_value - bar.page])
		else:
			_ok(true, "内容 (%d 行) 全部装下，无需滚动" % rows)
		_ok(sc.get_v_scroll_bar().custom_minimum_size.x >= 10.0,
				"打捞滚动条宽 ≥ 10px")
	w.queue_free()
	await _wait(2)


## 造 n 艘残骸 —— 与 `tools/probe_result_ui.gd` 同一个姿势（走真 `resolve_battle`）。
func _salvage_info(n: int) -> Dictionary:
	var run = preload("res://scripts/core/eve_run_state.gd").new()
	run.node_index = 7
	run.coin = 60
	var db := preload("res://scripts/core/eve_ship_database.gd")
	var pool: Array[String] = ["bantam", "osprey", "dominix", "hurricane",
			"rifter", "caracal", "thorax", "rupture", "vexor", "moa",
			"slasher", "executioner"]
	var objs: Array = []
	var srcs: Array = []
	for i in n:
		var key: String = pool[i % pool.size()]
		var team := 0 if i % 2 == 0 else 1
		var d: Dictionary = db.by_id(key)
		objs.append(db.instantiate_by_id(key, team, 9000 + i))
		srcs.append({"star": 1, "atk_base": float(d.get("attack", 10.0)),
				"def_base": float(d.get("armor_struct", 1.0)),
				"shot": float(d.get("attack", 10.0)), "m": 1.0, "team": team})
	run.resolve_battle(0, objs, srcs, 1.0)
	run.coin = 60
	return run.salvage_info()
