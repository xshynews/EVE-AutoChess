extends Node

## 开场剧情自检（无头）
##
## 跑法：
##   "C:/godot/Godot_v4.7.1-stable_win64_console.exe" --headless \
##     --path "F:/evezzq/eve自走棋918" --quit-after 900 \
##     res://tools/verify_intro.tscn
##
## ── 本文件里**刻意造错就必挂**的反向注入检查（没有这些等于没牙齿）──────
##   ① 片头段（0 ~ 2.6s）UI 层必须**整层不可见** —— 改回"只藏框不藏带子"就挂
##   ② 背景视频层必须 `MOUSE_FILTER_IGNORE` —— 让它 STOP（吃掉点击）就挂
##   ③ 三个按钮必须 `MOUSE_FILTER_STOP` 且能发出信号 —— 只是"画上去"就挂
##   ④ 暂停后时间真源 `_t` 必须**一动不动** —— 只是把按钮变灰就挂
##   ⑤ 「上一步」必须把 `_t` 拉回上一句的 t0（而不是只清一下画面）—— 糊弄就挂
##   ⑥ 信标收起态四片叶仰角必须 ≈ −90°、展开态 ≈ −25.3° —— 铰链轴选错/符号反了就挂
##   ⑦ 「首次 / 非首次」的判定必须**随进度存档翻转** —— 写死成两句话就挂
##   ⑧ 「下一步」两段行为必须都在：没显示完 ⇒ 只补全（时间不动）；显示完 ⇒ 真跳下一句
##   ⑨ 「跳过对话」必须真的跳到末段 —— 又顺手把人送出开场就挂
##
## ⚠️ 关键不变量禁用 assert（release 会剥离）⇒ 一律 push_warning + 计数。
## ⚠️ 本文件会**动玩家的进度存档** ⇒ 开头存快照、结尾原样写回（工程铁律）。

const INTRO_SCENE := preload("res://scenes/intro_scene.tscn")
const SCRIPT := preload("res://scripts/data/eve_intro_script.gd")
const PROGRESS := preload("res://scripts/core/eve_progress_store.gd")
## user:// 迁移（主菜单 `_ready` 会随启动调一次）—— 验收里必须关掉写盘
const EveUserDir := preload("res://scripts/core/eve_user_dir.gd")
const MENU_SCENE := preload("res://scenes/main_menu.tscn")

const MENU_PATH := "res://scenes/main_menu.tscn"
const BATTLE_SCENE := "res://scenes/battle_scene.tscn"

## 与 EveCynoBeacon.LEAF_ELEV 同值 —— 展开后叶片应有的仰角
const LEAF_ELEV_OPEN := -25.3
const MENU_INTRO := "res://scenes/intro_scene.tscn"
const MENU_BATTLE := "res://scenes/battle_scene.tscn"

var _pass: int = 0
var _fail: int = 0
var _intro: Variant = null
var _overlay: Variant = null
var _beacon: Variant = null
var _saved: Dictionary = {}


func _ok(cond: bool, what: String) -> void:
	if cond:
		_pass += 1
		print("PASS  %s" % what)
	else:
		_fail += 1
		push_warning("[verify_intro] FAIL  %s" % what)
		print("FAIL  %s" % what)


func _ready() -> void:

	# ⛔ 验收**不许**去搬玩家的真实存档目录（下面会实例化主菜单，它的 `_ready` 会调迁移）
	EveUserDir.persist = false

	print("=".repeat(62))
	print("开场剧情自检")
	print("=".repeat(62))

	# ── 存档快照（结尾原样写回，验收不许改玩家数据）──
	_saved = PROGRESS.load_all()

	_phase_scene_and_layers()
	await _phase_intro_clean()
	await _phase_dialogue()
	await _phase_buttons()
	await _phase_beacon()
	_phase_progress()
	await _check_menu_wiring()

	# ── 还原存档 ──
	PROGRESS.save_all(_saved)
	print("[存档] 已还原到自检前的状态：intro_seen = %s" % str(_saved["intro_seen"]))

	print("=".repeat(62))
	print("结果：%d 项通过 · %d 项失败" % [_pass, _fail])
	if _fail > 0:
		print("⚠️ 有失败项 —— 见上面的 FAIL 行")
	print("=".repeat(62))
	if _intro != null and is_instance_valid(_intro):
		_intro.queue_free()
	await get_tree().process_frame
	get_tree().quit(1 if _fail > 0 else 0)


# ─────────────────────────────────────────────── ① 场景与分层
func _phase_scene_and_layers() -> void:
	print("\n[1] 场景与分层（视频 / 对话 / 3D 必须是三层）")
	_ok(ResourceLoader.exists(MENU_PATH), "主界面场景存在")
	_ok(ProjectSettings.get_setting("application/run/main_scene") == MENU_PATH,
			"主场景仍是主界面（没被开场场景顶掉）")
	_ok(ResourceLoader.exists(BATTLE_SCENE), "对局场景存在")

	_intro = INTRO_SCENE.instantiate()
	add_child(_intro)
	_intro.process_mode = Node.PROCESS_MODE_DISABLED     # 先冻住，用 seek 做确定性断言

	var vid: Node = _intro.get_node_or_null("BgVideo")
	_ok(vid != null, "背景视频层存在（BgVideo）")
	if vid != null:
		_ok(vid is VideoStreamPlayer, "背景层是 VideoStreamPlayer")
		# ★ 反向注入①：视频若吃掉点击，三个按钮永远收不到事件
		_ok((vid as Control).mouse_filter == Control.MOUSE_FILTER_IGNORE,
				"★ 背景视频 mouse_filter = IGNORE（不吃点击）")
		var vs: Variant = (vid as VideoStreamPlayer).stream
		_ok(vs != null, "背景视频已加载")
		if vs != null:
			# 实测结论：Godot 4.7 的 VideoStream 只认 ogv（Ogg Theora），mp4 连 .import 都不生成
			_ok(vs.get_class() == "VideoStreamTheora",
					"★ 视频格式 = Ogg Theora（实际 %s；mp4 引擎不认）" % vs.get_class())

	var layer: Node = _intro.get_node_or_null("BeaconLayer")
	_ok(layer != null, "信标 3D 层存在（BeaconLayer）")
	if layer != null:
		_ok((layer as Control).mouse_filter == Control.MOUSE_FILTER_IGNORE,
				"信标层不吃点击")

	_overlay = _intro.overlay_ref()
	_beacon = _intro.beacon_ref()
	_ok(_overlay != null, "对话层存在")
	_ok(_beacon != null, "信标节点存在")
	_ok(_overlay.get_parent() == _intro and _overlay != vid,
			"对话层与视频层是**两个独立节点**（不是同一棵子树）")


# ─────────────────────────────────────────────── ② 片头整屏干净
func _phase_intro_clean() -> void:
	print("\n[2] 片头段整屏干净（本次改动的核心）")
	_intro.seek(0.30)
	await get_tree().process_frame
	_ok(not _overlay.visible or _overlay.modulate.a <= 0.001,
			"★ 反向注入①：t=0.30 片头中段 UI 整层不可见（a=%.2f）" % _overlay.modulate.a)
	_intro.seek(2.50)
	await get_tree().process_frame
	_ok(not _overlay.visible or _overlay.modulate.a <= 0.001,
			"★ t=2.50 片头末段仍不可见")
	_intro.seek(2.80)
	await get_tree().process_frame
	_ok(_overlay.visible and _overlay.modulate.a > 0.05 and _overlay.modulate.a < 0.95,
			"t=2.80 淡入进行中（a=%.2f，不是硬切）" % _overlay.modulate.a)
	_intro.seek(4.00)
	await get_tree().process_frame
	_ok(_overlay.visible and _overlay.modulate.a >= 0.99,
			"t=4.00 片头结束后完全可见（a=%.2f）" % _overlay.modulate.a)


# ─────────────────────────────────────────────── ③ 对话内容
func _phase_dialogue() -> void:
	print("\n[3] 对话内容按时间码驱动")
	var lines := SCRIPT.build()
	_ok(lines.size() == 13, "台词表 13 句（实际 %d）" % lines.size())
	_ok(lines.size() > 1 and not bool(lines[0]["box"]), "第 1 行是片头（无台词 ⇒ 不出框）")

	_intro.seek(3.20)
	await get_tree().process_frame
	_ok(_overlay.current_index() == 1, "t=3.20 当前是第 2 句（实际 idx=%d）" % _overlay.current_index())
	var body: Label = _overlay.get_node("DialogueBox/Body")
	var spk: Label = _overlay.get_node("DialogueBox/Speaker")
	_ok(spk.text == "玩家", "说话人是「玩家」（实际 %s）" % spk.text)
	_ok(body.text == String(lines[1]["text"]), "台词文本与表一致")

	# 逐字：同一句更早的时刻，显示的字数必须更少
	_intro.seek(2.66)
	await get_tree().process_frame
	var early: int = body.visible_characters
	_intro.seek(4.10)
	await get_tree().process_frame
	var late: int = body.visible_characters
	_ok(early < late, "★ 逐字显示生效（t=2.66 显示 %d 字 < t=4.10 显示 %d 字）" % [early, late])
	_ok(late >= String(lines[1]["text"]).length(), "到时间后整句显示完")

	_intro.seek(SCRIPT.PROMPT_AT + 0.10)
	await get_tree().process_frame
	_ok(body.text.contains("15 回合"), "末段改成任务提示（含「15 回合」）：%s" % body.text)
	_ok(spk.text == "本局任务", "任务提示的抬头是「本局任务」（实际 %s）" % spk.text)


# ─────────────────────────────────────────────── ④ 按钮真的能点
func _phase_buttons() -> void:
	print("\n[4] 上一步 / 下一步 / 暂停 / 跳过对话 —— 必须真能点、真起作用")
	# 先回到对话中段 —— 上一阶段结尾停在末段（任务提示态），
	# 那时主按钮写的是「▶ 进入边境」，直接断文案会假失败
	_intro.seek(8.00)
	await get_tree().process_frame
	var row: Node = _overlay.get_node("Buttons")
	var prev: Button = _overlay.button("Prev")
	var nxt: Button = _overlay.button("Next")
	var pause: Button = _overlay.button("Pause")
	var skip: Button = _overlay.button("Skip")
	_ok(prev != null and nxt != null and pause != null and skip != null,
			"四个按钮都建出来了（Prev/Next/Pause/Skip）")
	_ok(skip != null and skip.text == "跳过对话",
			"「跳过」已改名「跳过对话」（实际 %s）" % ("" if skip == null else skip.text))
	for b in [prev, nxt, pause, skip]:
		if b == null:
			continue
		_ok(b.mouse_filter == Control.MOUSE_FILTER_STOP,
				"★ 反向注入③：按钮「%s」mouse_filter = STOP（能收鼠标）" % b.text)
		_ok(b.disabled == false, "按钮「%s」初始可点" % b.text)
		_ok(b.pressed.get_connections().size() > 0,
				"按钮「%s」pressed 已接线（不是画上去的死方块）" % b.text)
	_ok(row != null, "按钮行存在")

	# ── 暂停：点按钮 → 时间真源冻住 ──
	_intro.seek(9.00)
	await get_tree().process_frame
	_intro.process_mode = Node.PROCESS_MODE_INHERIT
	await get_tree().process_frame
	await get_tree().process_frame
	var t_run: float = _intro.elapsed()
	_ok(t_run > 9.0, "恢复处理后有推进（t=%.3f）" % t_run)
	pause.pressed.emit()
	await get_tree().process_frame
	_ok(_overlay.is_paused(), "点「暂停」后进入暂停态")
	_ok(pause.text == "继续", "暂停按钮文案变成「继续」（实际 %s）" % pause.text)
	var t_a: float = _intro.elapsed()
	await get_tree().process_frame
	await get_tree().process_frame
	var t_b: float = _intro.elapsed()
	_ok(absf(t_b - t_a) < 1e-6, "★ 反向注入④：暂停期间时间真源一动不动（%.5f → %.5f）" % [t_a, t_b])
	pause.pressed.emit()
	await get_tree().process_frame
	_ok(not _overlay.is_paused(), "再点一次恢复运行")
	_ok(pause.text == "暂停", "按钮文案变回「暂停」")

	# ── 上一步：必须把时间真源拉回上一句的 t0 ──
	var lines := SCRIPT.build()
	# ⚠️ 先把处理冻住再点「上一步」：否则 `_process` 会在这一帧里把 `_t`
	#    往前推一点（实测 0.035s = 一帧），断言会变成"差一帧"的假失败。
	_intro.process_mode = Node.PROCESS_MODE_DISABLED
	_intro.seek(float(lines[6]["t0"]) + 0.60)     # 停在第 7 句中间
	await get_tree().process_frame
	_ok(_overlay.current_index() == 6, "先站到第 7 句（实际 idx=%d）" % _overlay.current_index())
	var want := float(lines[5]["t0"])
	prev.pressed.emit()
	await get_tree().process_frame
	_ok(absf(_intro.elapsed() - want) < 1e-3,
			"★ 反向注入⑤：点「上一步」回到上一句 t0=%.3f（实际 %.3f）" % [want, _intro.elapsed()])
	_ok(_overlay.current_index() == 5, "上一步后当前句 = 第 6 句（实际 idx=%d）" % _overlay.current_index())

	# ── 下一步：两段行为都要在 ──
	var n_before := float(lines[3]["t0"]) + 0.10
	_intro.seek(n_before)
	await get_tree().process_frame
	_ok(not _overlay.revealed_all(), "先停在第 4 句刚开始（词还没打完）")
	var t_before: float = _intro.elapsed()        # ⚠️ `_intro` 是 Variant ⇒ 必须显式标类型
	nxt.pressed.emit()
	await get_tree().process_frame
	_ok(_overlay.revealed_all(), "★ 反向注入⑧-a：点「下一步」先把当前句补全")
	_ok(absf(_intro.elapsed() - t_before) < 1e-4,
			"补全那一下**不跳时间**（%.3f → %.3f）" % [t_before, _intro.elapsed()])
	nxt.pressed.emit()
	await get_tree().process_frame
	_ok(_overlay.current_index() == 4,
			"★ 反向注入⑧-b：再点「下一步」才真进下一句（实际 idx=%d）" % _overlay.current_index())

	# ── 跳过对话：必须到末段，不许直接退对局 ──
	_intro.next_scene = ""                       # 保险：万一它真想切场景也不会把自检干掉
	_intro.seek(5.00)
	await get_tree().process_frame
	_ok(_overlay.current_index() == 2, "先停在对话中段（实际 idx=%d）" % _overlay.current_index())
	skip.pressed.emit()
	await get_tree().process_frame
	_ok(_intro.elapsed() >= SCRIPT.BEACON_IN - 1e-3,
			"★ 反向注入⑨：「跳过对话」跳到末段 t=%.2f（实际 %.2f）"
			% [SCRIPT.BEACON_IN, _intro.elapsed()])
	_ok(_intro.elapsed() < SCRIPT.PROMPT_AT,
			"跳过对话**没跳过头**到任务提示（%.2f < %.2f）" % [_intro.elapsed(), SCRIPT.PROMPT_AT])

	# ── 末段：上一步/下一步/暂停收起，主按钮变「进入边境」 ──
	_intro.seek(SCRIPT.PROMPT_AT + 0.10)
	await get_tree().process_frame
	_ok(not prev.visible and not nxt.visible and not pause.visible,
			"末段收起「上一步 / 下一步 / 暂停」")
	_ok(skip.visible and skip.text.contains("进入边境"),
			"末段主按钮变成「进入边境」（实际 %s）" % skip.text)
	_ok(skip.pressed.get_connections().size() > 0, "「进入边境」已接线")


# ─────────────────────────────────────────────── ⑤ 信标展开
func _phase_beacon() -> void:
	print("\n[5] 信标展开动画")
	_intro.seek(22.00)
	await get_tree().process_frame
	_ok(_beacon.progress() <= 0.001,
			"★ 23.30 之前信标是收起态（progress=%.3f）" % _beacon.progress())
	var elev_fold: PackedFloat32Array = _beacon.hinge_elevations()
	_ok(elev_fold.size() == 4, "四片叶都在（实际 %d）" % elev_fold.size())
	var ok_fold := true
	for e in elev_fold:
		if absf(e - (-90.0)) > 0.6:
			ok_fold = false
	_ok(ok_fold, "★ 反向注入⑥：收起态四片叶仰角都 ≈ −90°（竖直贴塔身）实测 %.1f/%.1f/%.1f/%.1f"
			% [elev_fold[0], elev_fold[1], elev_fold[2], elev_fold[3]])

	# 展开动画是靠 Tween 跑的：这里直接拨到进度 1，验终态
	_beacon.set_progress(1.0)
	await get_tree().process_frame
	var elev_open: PackedFloat32Array = _beacon.hinge_elevations()
	var ok_open := true
	for e in elev_open:
		if absf(e - LEAF_ELEV_OPEN) > 0.6:
			ok_open = false
	_ok(ok_open, "★ 展开态四片叶仰角都 ≈ %.1f°（向外下）实测 %.1f/%.1f/%.1f/%.1f"
			% [LEAF_ELEV_OPEN, elev_open[0], elev_open[1], elev_open[2], elev_open[3]])
	_ok(absf(_beacon.progress() - 1.0) < 1e-6, "展开进度可拨到 1.0")
	_ok(_beacon.is_unfolded(), "is_unfolded() 为真")
	var body_mi: Node = _beacon.get_node_or_null("Body")
	_ok(body_mi != null, "★ 塔身网格节点存在（Body）—— 载不到 OBJ 时这条会挂")
	if body_mi != null:
		var mm: Mesh = (body_mi as MeshInstance3D).mesh
		var sc := 0 if mm == null else mm.get_surface_count()
		_ok(sc > 0, "塔身网格有面（surface=%d）" % sc)
		# 立正检查：模型 +Y 朝下，必须绕 X 转 180°
		_ok(absf((body_mi as MeshInstance3D).rotation_degrees.x - 180.0) < 0.01,
				"★ 塔身已 R_x(180°) 立正（实际 %.1f°）"
				% (body_mi as MeshInstance3D).rotation_degrees.x)


# ─────────────────────────────────────────────── ⑥ 进度存档
func _phase_progress() -> void:
	print("\n[6] 首次游玩判定（进度存档）")
	var d := PROGRESS.load_all()
	_ok(d.has("intro_seen"), "存档有 intro_seen 字段")
	_ok(typeof(d["intro_seen"]) == TYPE_BOOL, "intro_seen 是 bool")
	_ok(PROGRESS.DEFAULTS["intro_seen"] == false,
			"默认值 = false（第一次玩 ⇒ 播开场）")

	# ⛔ 反向注入：写一次必须真能读回来（否则"跳过之后下次还拦人"）
	PROGRESS.save_one("intro_seen", true)
	_ok(PROGRESS.intro_seen(), "★ mark 之后读回来是 true（写盘生效）")
	PROGRESS.save_one("intro_seen", false)
	_ok(not PROGRESS.intro_seen(), "写回 false 也生效（不是只写不读）")

	# 配置文件必须与设置存档**分开**（混在一起会出"上局跳过⇒下局开头直接没"）
	_ok(PROGRESS.PATH != "user://settings.cfg",
			"进度存档与设置存档是两个文件（%s）" % PROGRESS.PATH)


# ─────────────────────────────────────────────── ⑦ 主菜单接线 + 首次判定
func _check_menu_wiring() -> void:
	print("\n[7] 主菜单接线与「首次 / 非首次」判定")
	var menu: Variant = MENU_SCENE.instantiate()
	add_child(menu)
	# 「回看片头」按钮（跳过不可以是不可逆的 ⇒ 必须有显式回看入口）
	var found := false
	for n in menu.find_children("*", "Button", true, false):
		if String((n as Button).name) == "ReplayIntroBtn":
			found = true
	_ok(found, "主界面有「回看片头」按钮（ReplayIntroBtn）")

	_ok(String(menu.INTRO_SCENE) == "res://scenes/intro_scene.tscn", "主界面知道开场场景在哪")

	# ★ 反向注入⑦：同一份代码，只翻进度存档，去的目的地必须跟着翻
	PROGRESS.save_one("intro_seen", false)
	_ok(menu.target_scene_for_start() == MENU_INTRO,
			"★ 第一次玩（intro_seen=false）⇒ 去开场（实际 %s）"
			% menu.target_scene_for_start())
	PROGRESS.save_one("intro_seen", true)
	_ok(menu.target_scene_for_start() == MENU_BATTLE,
			"★ 第二次玩（intro_seen=true）⇒ 直接进对局（实际 %s）"
			% menu.target_scene_for_start())
	PROGRESS.save_one("intro_seen", false)

	# 未开放的档位点「开始」不许进任何地方
	menu._on_mode_pressed(0)                       # 任务关卡
	menu._pick["campaign"] = 1                     # 第 2 难度（待开发）
	_ok(menu.target_scene_for_start() == "",
			"待开发难度点「开始」⇒ 哪都不去（实际 '%s'）" % menu.target_scene_for_start())
	menu._pick["campaign"] = 0

	# ★ 跳过必须写盘（否则下次开局又被拦一次）
	print("\n[8] 跳过的副作用（把 next_scene 置空，只验写盘不真切场景）")
	_intro.next_scene = ""
	PROGRESS.save_one("intro_seen", false)
	_intro._finish("自检")
	await get_tree().process_frame
	_ok(PROGRESS.intro_seen(), "★ 走到「进入边境」⇒ 进度存档写成 true（下次不再拦人）")
	_ok(bool(_intro._done), "跳过置了 finished 标志（不会被重复触发）")
	_intro.next_scene = BATTLE_SCENE
	menu.queue_free()
