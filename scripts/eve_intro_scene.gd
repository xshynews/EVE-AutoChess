extends Control
class_name EveIntroScene
## ★ 字号缩放（2026-10-07）：只动字、不动版面（见 eve_font.gd）
const FONT := preload("res://scripts/ui/eve_font.gd")

## 「守卫边境」开场 —— 视频背景 + 对话层 + 信标展开，最后进对局。
##
## ★ 三层彻底分开（这是「上一步 / 暂停 / 跳过」能真正工作的前提）：
##   ① 背景  `VideoStreamPlayer` —— `mouse_filter = IGNORE`，只播画面与声音
##   ② 对话  `EveIntroOverlay`  —— 实时绘制的 Control，三个按钮是真 Button
##   ③ 信标  `SubViewport`(3D)   —— 末句（没有视频的那一段）接上展开动画
##   ⛔ 绝不把 UI 烘进视频 —— 那样三个按钮只是画面上的方块，点不动。
##
## ★ 时间真源是**本脚本的 `_t`**，不是视频的播放位置。
##   理由：末句超出了视频长度（视频 23.104s / 时间轴到 25.6s），
##   拿视频当钟会在末段冻结；而且无头环境下视频根本不推进，
##   以它为准的话验收就全废了。视频只负责「按指令播 / 停 / 跳」。

const SCRIPT := preload("res://scripts/data/eve_intro_script.gd")
const PROGRESS := preload("res://scripts/core/eve_progress_store.gd")
const BEACON := preload("res://scripts/visual/eve_cyno_beacon.gd")
const OVERLAY := preload("res://scripts/ui/eve_intro_overlay.gd")

const BATTLE_SCENE := "res://scenes/battle_scene.tscn"

## 开场结束（看完 / 跳过）之后去哪。
## 留成变量：验收要测「跳过 ⇒ 写进度存档」，但不希望自检节点被切场景销毁
## ⇒ 自检里把它置空，就只验写盘不真跳。
var next_scene := BATTLE_SCENE

## 片头段结束 → 对话层淡入的时长（秒）。硬切会"啪"一下跳出来。
const RAMP := 0.35
const FADE_3D := 0.45               ## 视频 → 3D 的交叉淡入

## 末段的任务提示（⚠️ 最小版：完整的「任务方框 + 星币教学」还没做）
const TASK_TEXT := "守卫移动式诱导信标 · 共计 15 回合（含事件回合）"

var _lines: Array = []

var _video: VideoStreamPlayer
var _vp_cont: SubViewportContainer
var _viewport: SubViewport
var _beacon: Variant                    ## EveCynoBeacon（用 Variant 才能直接调它的 unfold）
var _overlay: EveIntroOverlay

var _t := 0.0
var _paused := false
var _line_idx := -2                  ## −2 = 还没评估过；−1 = 无当前句（片头）
var _beacon_started := false
var _prompted := false
var _done := false


func _ready() -> void:
	name = "IntroScene"
	# ★ 字号缩放：对话层与信标标注的字都在建立时定
	FONT.load_from_settings()
	# ⛔ 见 overlay 里的同一条注释：0×0 控件上必须用 and_offsets 版本才会真铺开
	if size == Vector2.ZERO:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_video()
	_build_3d()
	_build_overlay()

	_lines = SCRIPT.build()
	_overlay.bind_lines(_lines)
	_t = 0.0
	_sync_line(true)
	print("[开场] 共 %d 句 · 总长 %.2fs（其中信标段 %.2f–%.2f）"
			% [_lines.size(), SCRIPT.total(), SCRIPT.BEACON_IN, SCRIPT.PROMPT_AT])


# ── ① 背景视频 ───────────────────────────────────────────
func _build_video() -> void:
	_video = VideoStreamPlayer.new()
	_video.name = "BgVideo"
	_video.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_video.expand = true
	_video.mouse_filter = Control.MOUSE_FILTER_IGNORE      # ★ 不吃事件，点击才轮得到 UI
	# ⛔ `autoplay` 默认是 **false** —— 不打开它，视频永远停在第一帧（等于全黑）。
	#    这个坑很隐蔽：Node 建出来了、stream 也载到了、就是不出画面。
	_video.autoplay = true
	_video.stream = load(SCRIPT.VIDEO)
	if _video.stream == null:
		push_warning("[开场] 载不到背景视频 %s —— 只有空格子（Ogg Theora 才认）" % SCRIPT.VIDEO)
	add_child(_video)
	if _video.stream != null:
		_video.play()          # `autoplay` 之外再显式叫一次，两种触发都不落空


# ── ③ 信标 3D 层（先隐藏，末段才淡入）────────────────────
func _build_3d() -> void:
	_vp_cont = SubViewportContainer.new()
	_vp_cont.name = "BeaconLayer"
	_vp_cont.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_vp_cont.stretch = true
	_vp_cont.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vp_cont.modulate = Color(1, 1, 1, 0)                  # 初始全透明
	add_child(_vp_cont)

	_viewport = SubViewport.new()
	_viewport.name = "BeaconViewport"
	_viewport.size = Vector2i(1920, 1080)
	_viewport.transparent_bg = false
	_viewport.own_world_3d = true                          # 自带 Environment 必须独立世界
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp_cont.add_child(_viewport)

	_beacon = BEACON.new()
	_viewport.add_child(_beacon)

	var cam := Camera3D.new()
	cam.name = "Cam"
	cam.fov = 32.0
	cam.near = 1.0
	cam.far = 4000.0
	var d := 292.0                                          # 由展开后半展 82 m 反算
	var az := deg_to_rad(38.0)
	var el := deg_to_rad(32.0)
	var look := Vector3(0, 6.0, 0)
	_viewport.add_child(cam)                                # ⚠️ 必须先入树，look_at 才可用
	# ⛔ 不能先 look_at 再 add_child —— 会报 "Node not inside tree"
	cam.look_at_from_position(
			look + Vector3(sin(az) * cos(el), sin(el), cos(az) * cos(el)) * d,
			look, Vector3.UP)


# ── ② 对话层 ─────────────────────────────────────────────
func _build_overlay() -> void:
	_overlay = OVERLAY.new()
	add_child(_overlay)
	_overlay.prev_pressed.connect(_on_prev)
	_overlay.next_pressed.connect(_on_next)
	_overlay.pause_toggled.connect(_on_pause)
	_overlay.skip_pressed.connect(_on_skip_talk)
	_overlay.line_skipped.connect(_on_line_skipped)


# ── 主循环 ───────────────────────────────────────────────
func _process(delta: float) -> void:
	if _done:
		return
	if not _paused:
		_t += delta
	_update_video()
	_sync_line(false)
	_update_beacon()
	_update_ramp()


## 视频：到点播 / 到点停。末段超出视频长度 ⇒ 停在最后一帧，后面交给 3D。
func _update_video() -> void:
	if _video.stream == null:
		return
	if _t >= SCRIPT.VIDEO_LEN and not _video.paused:
		_video.paused = true
		_video.modulate.a = 0.0          # 视频让位给信标（末句没有视频）


## 按 `_t` 找当前句；变了就换。片头段（没有台词）⇒ 整层不显示。
## ⛔ 末段的任务提示**不归这里管** —— 一旦 `_prompted` 就必须早退，
##    否则 `show_line(-1)` 会把刚写好的任务文字和对话框一起藏掉
##    （踩过：信标展开完成、按钮出来了，任务文字却是空的）。
func _sync_line(force: bool) -> void:
	if _prompted:
		return
	var idx := -1
	for i in range(_lines.size()):
		var L: Dictionary = _lines[i]
		if _t >= float(L["t0"]) and _t < float(L["t1"]):
			idx = i
			break
	# 末段：超出最后一句 ⇒ 停在最后一句上（不再往下掉）
	if idx < 0 and _t >= float(_lines[-1]["t1"]) and _t < SCRIPT.PROMPT_AT:
		idx = _lines.size() - 1
	if idx != _line_idx or force:
		_line_idx = idx
		_overlay.show_line(idx)
	if idx >= 0:
		var L2: Dictionary = _lines[idx]
		_overlay.set_reveal(int(maxf(0.0, _t - float(L2["t0"])) * float(L2["cps"])))


## 片头段整屏干净；片头结束 → 按 RAMP 淡入
func _update_ramp() -> void:
	var intro_end := 0.0
	for L in _lines:
		if not bool(L["box"]):
			intro_end = float(L["t1"])
			break
	var a := 1.0
	if _t < intro_end:
		a = 0.0
	elif _t < intro_end + RAMP:
		a = (_t - intro_end) / RAMP
	_overlay.set_ui_on(a > 0.001)
	_overlay.modulate = Color(1, 1, 1, a)


## 末段：3D 淡入 → 展开 → 出「▶ 进入边境」
func _update_beacon() -> void:
	if _t >= SCRIPT.BEACON_IN:
		var k := clampf((_t - SCRIPT.BEACON_IN) / FADE_3D, 0.0, 1.0)
		_vp_cont.modulate = Color(1, 1, 1, k)
	if not _beacon_started and _t >= SCRIPT.BEACON_UNFOLD:
		_beacon_started = true
		_beacon.unfold(SCRIPT.UNFOLD_DUR)
		print("[开场] 信标展开开始（t=%.2f，时长 %.2fs）" % [_t, SCRIPT.UNFOLD_DUR])
	if not _prompted and _t >= SCRIPT.PROMPT_AT:
		_prompted = true
		_overlay.show_task(TASK_TEXT)
		_overlay.set_prompt(true)
		print("[开场] 展开完成 → 等待「进入边境」")


# ── 按钮 ─────────────────────────────────────────────────

## 上一步：回到**上一句**开头。**视频一起回退** —— 时间轴是按视频排的，
## 只退文字会让音画错位。
## ⚠️ 语义只做一件事：**退到上一句**。曾经写成"刚切过来就再退一句、
##    否则重启本句"，那让同一个按钮有两种行为 —— 玩家没法预期（自检抓到）。
func _on_prev() -> void:
	if _done or _paused:
		return
	var idx := _line_idx
	if idx < 0:
		return
	var target_idx := maxi(idx - 1, 0)
	var t0 := float(_lines[target_idx]["t0"])
	print("[开场] 上一步 → 第 %d 句（t=%.2f）" % [target_idx + 1, t0])
	_t = t0
	_beacon_started = false
	_prompted = false
	_overlay.set_prompt(false)
	_beacon.stop_unfold()                    # ★ 先掐掉动画，否则它下一帧就把进度写回去
	_beacon.set_progress(0.0)
	_vp_cont.modulate = Color(1, 1, 1, 0)
	if _video.stream != null:
		_video.modulate.a = 1.0
		_video.paused = false
		_video.stream_position = clampf(t0, 0.0, SCRIPT.VIDEO_LEN - 0.05)
	_sync_line(true)


func _on_pause(on: bool) -> void:
	if _done:
		return
	_paused = on
	_overlay.set_paused(on)
	if _video.stream != null and not (_t >= SCRIPT.VIDEO_LEN):
		_video.paused = on or _t >= SCRIPT.VIDEO_LEN
	print("[开场] %s（t=%.2f）" % ["暂停" if on else "继续", _t])


func _on_line_skipped() -> void:
	_overlay.reveal_all()


## 「跳过对话」：跳过**整段对话** → 直接进末段（信标展开 + 任务提示）。
##
## ⚠️ 不要再让它直接退对局了 —— 名字改了语义就得跟着改。
##    用户原话：「我以为点跳过是跳过当前对话，原来不是哦」。
##    按钮写「跳过对话」却把人送出开场，那就是同一类谎话。
##    要离开开场，用末段的「▶ 进入边境」。
func _on_skip_talk() -> void:
	if _done:
		return
	if _prompted:
		_finish("进入边境")            # 末段时这个按钮已经写的是「▶ 进入边境」
		return
	print("[开场] 跳过对话 → 末段（t=%.2f）" % SCRIPT.BEACON_IN)
	seek(SCRIPT.BEACON_IN)


## 「下一步 ▸」：当前句没显示完 ⇒ 先补全；已显示完 ⇒ 跳下一句；最后一句 ⇒ 进末段。
func _on_next() -> void:
	if _done or _paused or _prompted:
		return
	if not _overlay.revealed_all():
		_overlay.reveal_all()
		return
	var idx := _overlay.current_index()
	if idx < 0 or idx >= _lines.size() - 1:
		_on_skip_talk()
		return
	print("[开场] 下一步 → 第 %d 句" % (idx + 2))
	seek(float(_lines[idx + 1]["t0"]))



func _finish(why: String) -> void:
	if _done:
		return
	_done = true
	print("[开场] %s → 进对局（已看过记得写盘）" % why)
	PROGRESS.mark_intro_seen()
	if next_scene != "":
		get_tree().change_scene_to_file(next_scene)


func _unhandled_input(event: InputEvent) -> void:
	if _done or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	# ⛔ 键盘必须读 physical_keycode（工程铁律）
	match event.physical_keycode:
		KEY_SPACE:
			_on_pause(not _paused)
		KEY_ENTER, KEY_KP_ENTER:
			_on_skip_talk()
		KEY_RIGHT:
			_on_next()
		KEY_LEFT, KEY_BACKSPACE:
			_on_prev()
		_:
			return
	get_viewport().set_input_as_handled()


# ── 探针 / 验收用的只读接口 ──────────────────────────────

## 跳到时间 t（探针与自检用）。
## ★ 这是个**纯粹按 t 求值的函数**：调用后画面状态只由 t 决定，与"之前播过什么"无关。
##   所以这里**不用 Tween**（Tween 是给实时播放用的），而是直接把信标进度算出来。
##   ⚠️ 必须先 `stop_unfold()` 掐掉可能在跑的动画，否则它下一帧就把进度写回去。
func seek(t: float) -> void:
	_t = t

	# 视频：跳到对应帧（不然出的是"时间轴在第 10 秒、画面还在第 1 帧"的错位图）
	if _video != null and _video.stream != null:
		_video.stream_position = clampf(t, 0.0, SCRIPT.VIDEO_LEN - 0.05)
		_video.modulate.a = 1.0 if t < SCRIPT.VIDEO_LEN else 0.0

	# 信标 3D 层
	_vp_cont.modulate = Color(1, 1, 1,
			clampf((t - SCRIPT.BEACON_IN) / FADE_3D, 0.0, 1.0))
	_beacon.stop_unfold()
	if t < SCRIPT.BEACON_UNFOLD:
		_beacon_started = false
		_beacon.set_progress(0.0)
	else:
		_beacon_started = true
		_beacon.set_progress(clampf((t - SCRIPT.BEACON_UNFOLD) / SCRIPT.UNFOLD_DUR, 0.0, 1.0))

	# 台词（`_prompted` 为真时它会早退，不会覆盖下面要写的任务提示）
	_sync_line(true)

	# 任务提示（必须放在 `_sync_line` **之后**）
	_prompted = t >= SCRIPT.PROMPT_AT
	if _prompted:
		_overlay.show_task(TASK_TEXT)
	_overlay.set_prompt(_prompted)

	_update_ramp()


func elapsed() -> float:
	return _t


func overlay_ref() -> EveIntroOverlay:
	return _overlay


func beacon_ref() -> Node:
	return _beacon
