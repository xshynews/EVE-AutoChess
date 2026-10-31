extends Node

## 探针：**舰船抽奖窗口**的四个画面（2026-10-31）。
##
## 玩家诉求（用户原话，两次来回）：
##   「抽船事件单独做一个抽奖窗口 …… 下面会有一个许愿，让你在可能的舰船中选，
##     一星和二星舰船分开，选一个，如果真抽到了自己许愿的那个船，
##     就奖励舰船星币（二星舰船按一星计价）」
##   → 纠正：「一星二星**全部进一个池子**……二星不是单独的池子，玩家**只能选一艘**」
##
## 本探针解决的是**只有看图才能判断**的四件事：
##   ① 44 张卡摊在 1000×560 的窗里（8 列 × 6 行），有没有被裁 / 有没有溢出窗框；
##   ② 合并成一栏之后，★1（青边）/ ★2（金边）**能不能一眼分开** —— 这是这次改版
##      最容易做砸的地方：两栏变一栏，星级唯一的线索就是卡面；
##   ③ 单选许愿的选中态（金底金边）在深色卡上够不够看得出来；
##   ④ 抽完的结果卡读不读得出「抽到谁 / 命中没有 / 返了几个币」。
##
## ── 跑法 ────────────────────────────────────────────────────────────
##   "$GODOT_BIN" --path . --quit-after 900 res://tools/probe_lottery.tscn
##   ⚠️ 不要加 --headless（要看像素）
##
## 产物：outputs/lottery_1_pool.png / _2_wish.png / _3_result.png / _4_hit.png
##
## ⚠️ 走的是**真实链路**：`prep.on_event_chosen(black_market)` → 开窗 →
##    点卡片许愿 → 点「抽取」（信号 → prep.on_lottery_draw）→ 点「完成」
##    （信号 → prep.on_lottery_finished → advance）。
##    ⛔ 不要图省事直接 `run.lottery_draw()` —— 那样验不到"信号没接上"这类
##    静默断线（按钮能点、点下去什么都不发生，是这类面板最常见的病）。

const SCENE_PATH := "res://scenes/battle_scene.tscn"
const OUT_DIR := "res://outputs"

var _battle: Node = null
var _hud: Node = null
var _run: EveRunState = null
## ⚠️ 不能声明成 Node：`_prep_phase` 是 `extends RefCounted` 的纯逻辑模块
var _prep = null
var _lw: Node = null

var _frame := 0
var _done := false


func _ready() -> void:
	var win := get_window()
	if win != null:
		win.size = Vector2i(1920, 1080)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var packed: PackedScene = load(SCENE_PATH)
	_battle = packed.instantiate()
	add_child(_battle)


func _process(_dt: float) -> void:
	if _done:
		return
	_frame += 1
	match _frame:
		40: _open_lottery()
		48: _shot("lottery_1_pool")
		50: _make_wishes()
		56: _shot("lottery_2_wish")
		58: _draw()
		66: _shot("lottery_3_result")
		# 命中态（UI 渲染检查）：真实链路下"抽中许愿船"是概率事件，
		# 一次跑不一定撞上，所以这里**手工喂一条命中结果**让画面能看。
		# ⚠️ 它只验「金色命中那行字画得对不对」，不冒充真实抽取逻辑
		#    （真实逻辑由 verify_run 的 `_t_inferno_lottery` 用同种子对账）。
		68: _fake_hit_shot()
		74: _shot("lottery_4_hit")
		78: _finish_probe()


# ------------------------------------------------------------------ 流程

func _open_lottery() -> void:
	_hud = _battle.get("hud")
	_run = _battle.get("run")
	_prep = _battle.get("_prep_phase")
	_lw = _hud.get("lottery_window")
	# 直接摆到事件节点 4（本探针不跑前面 3 关的战斗）
	# ⚠️ 难度必须切到炼狱：抽奖是炼狱专属，普通档走的是旧路径（不弹窗）。
	#    这里在 `start_run()` 之后改，只为让 `difficulty_row()` 指向炼狱 ——
	#    开局星币已经在 start_run 里按旧档发过了，本探针不看那一项。
	_run.set_difficulty("inferno")
	_run.node_index = 4
	_hud.call("show_event", _run.event_options(), _run.entry_line(), "节点 4 · 事件")
	_prep.call("on_event_chosen", &"black_market")
	print("开窗：lottery_open=%s · 已取事件=%s · 窗可见=%s"
			% [str(_prep.get("lottery_open")), str(_run.event_picks),
				str(_lw.get("visible"))])
	var r: Rect2 = _lw.get_rect()
	print("  窗矩形 = %s · 视口 %s" % [str(r), str(get_viewport().get_visible_rect().size)])


func _make_wishes() -> void:
	# 池子已合并成一栏（2026-10-31 用户纠正）⇒ 只有一个 `_cards`，
	# 键是 `ship_key#star`（同名 ★1/★2 必须能分开，见 eve_lottery.gd 顶注）。
	var cards: Dictionary = _lw.get("_cards")
	if cards.is_empty():
		print("!! 池子是空的，许愿点不到（cards=%d）" % cards.size())
		return
	# 挑第一张 ★1（池子顺序：一星 32 张在前、二星 12 张在后）
	var picked := ""
	for id in cards.keys():
		if String(id).ends_with("#1"):
			picked = String(id)
			break
	if picked == "":
		print("!! 池子里没有 ★1 卡")
		return
	var parts := picked.split("#")
	# 走玩家通道（PanelContainer 的 gui_input），不是直接改字段
	_lw.call("_on_card_input", _click(), StringName(parts[0]), int(parts[1]))
	var w: Dictionary = _lw.call("current_wish")
	print("许愿 = %s ★%d · 池内卡数 %d（44 = 32 一星 + 12 二星）"
			% [String(w.get("key", "")), int(w.get("star", 0)), cards.size()])


func _draw() -> void:
	_lw.call("_on_draw_pressed")


## 手工喂一条「命中许愿」的结果（只为截图看金色那行字）。
##
## ⚠️ 它只验「金色命中那行字画得对不对」，不冒充真实抽取逻辑
##    （真实逻辑由 verify_run 的 `_t_inferno_lottery` 用同种子对账）。
func _fake_hit_shot() -> void:
	var wish: Dictionary = _lw.call("current_wish")
	var wkey: StringName = wish.get("key", &"")
	var wstar := int(wish.get("star", 1))
	var ship := EveShipDatabase.by_id(String(wkey))
	# ★ 现在一次只抽 1 艘（用户 2026-10-31 定案），假结果也只给 1 张卡 ——
	#   别让截图误导后人以为还是两艘。
	_hud.call("show_lottery_result", [
		{"ok": true, "star": wstar, "ship_key": wkey,
			"name": String(ship.get("name", "?")), "cost": int(ship.get("cost", 3)),
			"hit": true, "reward": int(ship.get("cost", 3)), "placed": "bench"},
	])


func _finish_probe() -> void:
	_done = true
	# 第二次点「抽取」= 完成 ⇒ 真实链路会走 prep.on_lottery_finished → advance
	_lw.call("_on_draw_pressed")
	print("收尾：lottery_open=%s · 节点=%d · 备战席=%d 艘 · 星币=%d"
			% [str(_prep.get("lottery_open")), _run.node_index,
				_run.bench.size(), _run.coin])
	print("  窗可见=%s（必须回到 false）" % str(_lw.get("visible")))
	print("\n产物：%s/lottery_1_pool.png · _2_wish.png · _3_result.png" % OUT_DIR)
	get_tree().quit()


# ------------------------------------------------------------------ 工具

func _click() -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	return ev


func _shot(tag: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path("%s/%s.png" % [OUT_DIR, tag]))
	print("  截图 %s（%d×%d）" % [tag, img.get_width(), img.get_height()])
