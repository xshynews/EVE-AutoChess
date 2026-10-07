extends "res://scripts/ui/eve_window.gd"

## EVE 自走棋 —— 设置窗（阶段 D / 2026-09-28 重构）
##
## ══════════════════════════════════════════════════════════════════
##  它存在的原因：把「散落开关」收进来
## ══════════════════════════════════════════════════════════════════
##  在它出现之前，这个工程有一堆只能靠键盘快捷键碰到的开关：
##    B = 棋盘显隐 · C = 相机复位 · SPACE = 暂停 · R = 重开一局
##  它们分散在 `eve_battle_scene._unhandled_input` 里，玩家不看代码就发现不了。
##  顶条右端那个 `≡` 按钮从 V3 稿起就一直空着 —— 它就是给这个窗留的位置。
##
##  ⚠️ 快捷键【保留不动】。设置窗是「让不知道快捷键的玩家也能用」，
##     不是「取代快捷键」。两者并存，谁也不抢谁。
##
## ── 2026-09-28 重构：从「开关集散地」升级成「真设置」────────────
##  三件事：
##   ① **暂停按钮上位**（最顶、最大）—— PVE 也要能停。暂停 = 停推进 + 禁操作，
##      由 `EveHudRoot` 的全屏遮罩吃掉鼠标、主控停掉 `_process`，
##      只有空格与设置窗自己的「继续」能解开（见 eve_battle_scene.set_paused）。
##   ② **音量四条滑杆**（总 / 音效 / 环境 / 音乐）+ 静音 —— 后端是
##      `EveAudio.set_volume()`，真实存在，不是假旋钮。
##   ③ **持久化**（`EveSettingsStore` → `user://settings.cfg`）——
##      只存「玩家偏好」，不存「场上状态」（雾 / 射程环 / 棋盘会随阶段自动变，
##      存下来只会造成「上局收尾是关的 ⇒ 下局开局也是关的」这种鬼打墙）。
##
## ── 分区 ──────────────────────────────────────────────────────────
##    [暂停]  ·  音频  ·  画面  ·  战斗界面  ·  操作  ·  系统（DEBUG 折叠）
##  顺序是「按玩家会来找什么」排的：最急的是暂停，其次听感，其次画面，
##  其次场上辅助线，其次是动作，最后是调试残留。
##
## ── 交互形态：为什么用「分段按钮」而不是 CheckButton ──────────────
##  这个工程的整套视觉语言是**直角、1px 边框、不发光**（见 EveWindow 顶注）。
##  Godot 默认 CheckButton 是圆角胶囊 + 蓝色高亮，丢进来自带一整套
##  不属于这里的语言。所以开关用 EveButtonTheme 的按钮做（青底 = 开），
##  连续量（音量）用 HSlider **套同样的直角 StyleBoxFlat**。
##
## ⚠️ 每一组都是【即时生效】的：点下去立刻改后端，没有「应用」按钮。
##    设置项少到一个屏能看完时，「应用」只是多一次误操作的机会。
## ⚠️ 窗高是**按内容反推**的（`_fit_height`）—— 别手写高度：
##    写死的后果是本工程已经踩过两次的「窗底一条填不满的死白」。

signal background_changed(id: String)
signal mood_changed(mode: int)
signal fog_toggled(on: bool)
signal range_rings_toggled(on: bool)
signal board_toggled(on: bool)
signal camera_reset_requested()
signal run_restart_requested()
## 「放弃本局 · 回主界面」——离开这一局、回主菜单。由主控切场景。
## ⚠️ 目前**没有存档**，所以按钮文案必须把"放弃本局"写出来，
##    不能只写"返回主界面" —— 那会让人以为进度还在。
signal back_to_menu_requested()

## 暂停 / 继续。`on = true` 请求暂停。
##
## ⚠️ 这是**请求**不是命令：主控（`EveBattleScene.set_paused`）才是真相源，
##    它会把结果用 `set_paused()` 回写到这里（键盘空格走的是另一条路，
##    按钮必须跟着变，否则出现「场上停着、按钮写着暂停」）。
signal pause_toggled(on: bool)
## 音量改动。`kind` = &"master" / &"sfx" / &"amb" / &"music"，`v` ∈ [0,1]
signal volume_changed(kind: StringName, v: float)
## 静音开关
signal mute_toggled(on: bool)
## ★ 界面缩放档（2026-10-07）。值 = **存档原值**（0 = 自动）。
## ⚠️ 只发「玩家点了哪一个」，解析成倍数由 `EveUiScale.resolve()` 负责 ——
##    档位表只有一份，窗里不再抄第二份。
signal ui_scale_changed(saved: float)
## ★ 字号缩放变了（`1.0` = 设计字号）。值已经**由本窗应用到全树**（`FONT.reapply`），
## 这个信号是给 HUD 的：「底部两条要按新字高重新上抬」（见 `EveHudRoot.SHOP_FONT_GROW`）。
signal font_scale_changed(v: float)
## ★ 分辨率档变了（2026-10-07）。值 = **档位下标**（`EveResolution.CHOICES`）。
## ⚠️ 窗口尺寸**本窗自己就改了**（`EveResolution.apply_index`）—— 这个信号是给
##    「拿不到窗口的持有者」的：HUD 要重铺（居中偏移变了）、牌桌要重绘。
##    ⛔ 别在接收方再改一次窗口尺寸（两次改动之间会闪一帧）。
signal resolution_changed(idx: int)

## ══════════════════════════════════════════════════════════════════
##  场景档案：**同一扇设置窗，两套内容**
## ══════════════════════════════════════════════════════════════════
##
## 2026-10-07 用户：「我发现斗地主页面没有基本的设置，看看能不能把守卫边境的设置搬过去」。
##
## ⚠️ 「搬过去」不能是**整扇照搬** —— 战场的「暂停 / 空间雾 / 射程环 / 棋盘 /
##    相机复位 / 重开一局」在牌桌上**没有对应物**，照搬过去就是一排
##    「看着能点、点了没反应」的死按钮（工程红线 9，本文件顶注也写过同一条）。
## ⇒ 按场景**条件构建**：
##    · `battle`（守卫边境 / 战场）：完整设置，一字不改
##    · `lounge`（娱乐总汇 / 牌桌）：音频 · 显示 · 界面 · 返回主界面
##
## ⚠️ 是「**不构建**」而不是「灰掉/禁用」：禁用态会在正式版里留下一排
##    永远点不动的按钮，比没有更糟（同一个理由见「系统 DEBUG」那一段）。
const PROFILE_BATTLE := "battle"
const PROFILE_LOUNGE := "lounge"

## 本窗的档案。**建 UI 之前**设好（`_build_contents` 读它决定建哪些分区）。
var profile := PROFILE_BATTLE


func _is_battle() -> bool:
	return profile == PROFILE_BATTLE

## ⚠️ DEBUG-ONLY: 调试期加币按钮，发布时**必须删除**。
##   加 300 星币让玩家在不动现有结构的前提下快速测试经济路径
##   （买经验、超频、刷新、打捞都更顺）。
##   删的时候一并删：① 本 signal ② 本组按钮构建块 ③ eve_hud_root 里的 connect
##   ④ eve_battle_scene 里的 handler（如果加了）⑤ `add_coins_requested` 的所有 grep 引用。
signal add_coins_requested(amount: int)
signal closed()

## 当前天空盒候选（与 EveBattleArena 的 background_id 导出枚举同源）。
##
## ⚠️ 这里只列 4 个有代表性的，不是全部 —— 设置窗是「换一张看看」，
##    不是素材浏览器。真正的全表在 eve_background_library.gd。
##    加新背景时**优先改这里**（而不是在别处再抄一份列表）。
const BACKGROUNDS: Array = [
	{"id": "caldari_c07", "name": "加达里 C07"},
	{"id": "caldari_c02", "name": "加达里 C02"},
	{"id": "gallente_g03", "name": "盖伦特 G03"},
	{"id": "amarr_a03", "name": "艾玛 A03"},
]

const MOODS: Array = [
	{"v": 0, "name": "通透"},
	{"v": 1, "name": "氛围"},
]

## 设置持久化。
##
## ⚠️ 用 `preload` 而不是直接写类名：全局 class_name 要等 `.godot` 重新扫描
##    才注册得上，而 preload 是**显式依赖**，任何时候都能解析 ——
##    少一层「必须记得跑 --import」的隐性前提。
const STORE := preload("res://scripts/core/eve_settings_store.gd")
## UI 缩放档的取值域与解析（唯一真相源）
const UI_SCALE_SCRIPT := preload("res://scripts/ui/eve_ui_scale.gd")
## ★ 窗口分辨率档（唯一真相源）。⚠️ 只在**桌面端**生效。
const RESOLUTION_SCRIPT := preload("res://scripts/ui/eve_resolution.gd")

## 音量的四档 —— 顺序 = 窗里的顺序，键 = `EveAudio.set_volume` 的 kind。
##
## ⚠️ 「总音量」走 Master 总线（三条分总线都是它的下游），
##    所以它不是「三条的平均值」而是一个真正的上游总闸。
const VOLUME_KINDS: Array = [
	{"k": &"master", "name": "总音量"},
	{"k": &"sfx", "name": "音效"},
	{"k": &"amb", "name": "环境"},
	{"k": &"music", "name": "音乐"},
]

## 单选组的按钮引用 —— 每项 = {"btns": Array[Button], "apply": Callable(index)}
var _groups: Array[Dictionary] = []
var _bg_btns: Array[Button] = []
var _mood_btns: Array[Button] = []
## 缩放档按钮（**只有移动端才建** ⇒ 桌面端这里是空的，别当成 bug）
var _scale_btns: Array[Button] = []
## 分辨率档按钮（**只有桌面端才建** ⇒ 移动端这里是空的，别当成 bug）
var _res_btns: Array[Button] = []
## 本窗认为的缩放档（存档原值，0 = 自动）
var _cur_ui_scale := 0.0
## 二态开关（雾 / 射程环 / 棋盘 / 静音）—— 值存在这里，刷新时按值上皮肤
var _toggles: Dictionary = {}
## 音量滑杆 —— key = kind，值 = {"slider": HSlider, "num": Label}
var _sliders: Dictionary = {}

var _cur_bg: String = "caldari_c07"
var _cur_mood: int = 0
## 「字号」滑杆行（{"row","slider","num"}）—— 桌面端也有，所以不是空字典
var _font_slider: Dictionary = {}
## 本窗认为的暂停态。只在 `set_paused()` 里被改（主控回写）。
var _paused := false

var _pause_btn: Button = null
## DEBUG 区（默认收起）—— 常驻显示的话，一个正式设置窗里挂着加币按钮很出戏
var _dbg_box: VBoxContainer = null
var _dbg_btn: Button = null


func _ready() -> void:
	window_title = "设置"
	density = Density.COMPACT
	# ★ 高度由内容反推（见 `_fit_height`）⇒ 允许它高过设计稿的 480，
	#   摆位时由基类把它上移进屏（否则底部会被切掉）。
	fit_in_viewport = true
	super._ready()
	_build_contents()
	set_paused(false)
	#
	# ⚠️ 窗高按内容反推，但**必须等布局稳定**才量得准 ——
	#    `_build_contents()` 刚跑完时窗口宽度还是 0（hud 的 `set_window_rect`
	#    在 `add_child` 之后才执行），而带 autowrap / 自动换行的控件的最小高度
	#    **取决于当时拿到的宽度**：0 宽 ⇒ 折成几十行 ⇒ 量出 800+px ⇒
	#    窗被撑到 919px、底部留 390px 空白（用户 2026-09-29 实测报的就是这个）。
	#    等两帧：第一帧宽度就位、第二帧各控件的 minimum size 缓存刷新完。
	await get_tree().process_frame
	await get_tree().process_frame
	_fit_height()


func _build_contents() -> void:
	content.add_theme_constant_override("separation", 7)

	# ── ⓪ 暂停（最顶、最大）—— **只有战场有** ──
	#
	# ⚠️ 放在第一行的理由：它是设置窗里**唯一一个会被急用的东西** ——
	#    玩家来点它的时候往往正手忙脚乱（战斗打崩了、想截图、想看清楚），
	#    埋在分区里等于没有。40px 高（常规按钮 22）是为了让它在
	#    一堆小控件里一眼可辨，而不是靠颜色去抢注意力。
	#
	# ⚠️ 牌桌档案里**不建**：牌桌是纯 2D、没有战斗在跑，暂停没有对应物
	#    （见顶注的 `PROFILE_*` 与红线 9）。
	if _is_battle():
		_pause_btn = Button.new()
		_pause_btn.custom_minimum_size = Vector2(0, 40)
		_pause_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_pause_btn.pressed.connect(func(): pause_toggled.emit(not _paused))
		content.add_child(_pause_btn)
		content.add_child(make_divider())

	# ── ① 音频（**两个档案都有**）──
	content.add_child(make_group_header("音频  AUDIO"))
	for item in VOLUME_KINDS:
		var kind: StringName = item["k"]
		var made := _build_slider_row(String(item["name"]), 1.0,
				func(v: float): _pick_volume(kind, v))
		_sliders[kind] = made
		content.add_child(made["row"])

	var mute_row := HBoxContainer.new()
	mute_row.add_theme_constant_override("separation", 5)
	mute_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mute_row.add_child(_make_toggle("mute", "静音", func(on: bool):
		STORE.save_one("muted", on)
		mute_toggled.emit(on)))
	content.add_child(mute_row)
	content.add_child(make_divider())

	# ── ② 显示（窗口分辨率 / 界面缩放）—— **两个档案都有**，内容随平台变 ──
	for r in _build_display_rows():
		content.add_child(r)

	# ── ③ 界面（字号）—— **两个档案都有** ──
	#
	#  ★★ 字号缩放（**独立于界面缩放**：只动字、版面一点不动）。
	#  · 界面缩放：整幅画布一起放大（字号与版面同步）——代价是设计空间被压缩
	#    （设计高 = 1080÷倍数），所以底部两条要改贴底。
	#  · 字号缩放：只动字 —— 适合「整体比例看着正好、就是字小」。
	#  ⇒ 两者相乘，可细调；详见 `EveFont` 顶注。
	#
	# ⚠️ 上限定 1.30 不是随手取的：顶条 40px / 商店 158px / 棋带 140px 都是
	#    设计稿写死的高度，1.30 之内它们还塞得下（实测见日志），再大就该用界面缩放。
	# ⚠️ 桌面端**也有**这一行 —— 它跟界面缩放不同，桌面同样有意义
	#    （窗口大小是玩家自己拖的，字号未必跟着舒服）。
	content.add_child(make_group_header("界面  INTERFACE"))
	_font_slider = _build_slider_row("字号", FONT.scale,
			func(v: float): _pick_font_scale(v),
			FONT.MIN_SCALE, FONT.MAX_SCALE, FONT.STEP)
	content.add_child(_font_slider["row"])
	content.add_child(make_divider())

	# ── ④ 画面（天空盒 / 氛围）—— **只有战场有** ──
	#    ⚠️ 牌桌没有 3D 场景可换：它的背景是 `ddz_table` 自己画的，
	#       由牌桌档案的「牌桌美化」项管，⛔ 别把天空盒搬过去（那是死按钮）。
	if _is_battle():
		content.add_child(make_group_header("画面  RENDER"))
		# ⚠️ 天空盒用 2×2 而不是一行 4 个：窗宽 320 时一行 4 个每个只有 ~70px，
		#    「加达里 C07」这种 7 字标签会被压成省略号（改窗宽就会复现）。
		var bg := _build_choice_block(BACKGROUNDS, "name", 2,
				func(i: int): _pick_background(i))
		var bg_btns: Array = bg["btns"]
		for b in bg_btns:
			_bg_btns.append(b as Button)
		var bg_rows: Array = bg["rows"]
		for r in bg_rows:
			content.add_child(r)

		var mood := _build_choice_block(MOODS, "name", 2, func(i: int): _pick_mood(i))
		var mood_btns: Array = mood["btns"]
		for b in mood_btns:
			_mood_btns.append(b as Button)
		var mood_rows: Array = mood["rows"]
		for r in mood_rows:
			content.add_child(r)
		content.add_child(make_divider())

		# ── ⑤ 战斗界面（空间雾 / 射程环 / 棋盘）—— **只有战场有** ──
		content.add_child(make_group_header("战斗界面  BATTLE UI"))
		var toggles := HBoxContainer.new()
		toggles.add_theme_constant_override("separation", 5)
		toggles.mouse_filter = Control.MOUSE_FILTER_IGNORE
		toggles.add_child(_make_toggle("fog", "空间雾", func(on: bool):
			fog_toggled.emit(on)))
		toggles.add_child(_make_toggle("rings", "射程环", func(on: bool):
			range_rings_toggled.emit(on)))
		toggles.add_child(_make_toggle("board", "棋盘", func(on: bool):
			board_toggled.emit(on)))
		content.add_child(toggles)
		content.add_child(make_divider())

	# ── ⑥ 操作（不是开关，是「做一件事」）—— **两个档案都有** ──
	content.add_child(make_group_header("操作  ACTION"))
	if _is_battle():
		var acts := HBoxContainer.new()
		acts.add_theme_constant_override("separation", 5)
		acts.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var cam_btn := _mk_btn("相机复位")
		cam_btn.pressed.connect(func(): camera_reset_requested.emit())
		acts.add_child(cam_btn)
		var restart_btn := _mk_btn("重开一局")
		EveButtonTheme.apply(restart_btn, "hud_warn")
		restart_btn.pressed.connect(func(): run_restart_requested.emit())
		acts.add_child(restart_btn)
		content.add_child(acts)

	# 返回主界面单独一行：它是"离开这一局"，与上面两个"局内动作"不同级。
	# ⚠️ **两个档案都要**（牌桌上这是唯一的"离开"入口），只是文案不同：
	#    战场**没有存档**，所以必须把"放弃本局"写出来，不能只写"返回主界面"
	#    —— 那会让人以为进度还在（本文件顶注也写过这条）。
	var back_row := HBoxContainer.new()
	back_row.add_theme_constant_override("separation", 5)
	back_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var menu_btn := _mk_btn("放弃本局 · 回主界面" if _is_battle() else "返回主界面")
	menu_btn.pressed.connect(func(): back_to_menu_requested.emit())
	back_row.add_child(menu_btn)
	content.add_child(back_row)

	# ── ⑦ 系统（DEBUG 默认折叠）—— **只有战场有** ──────────────
	#
	# ★★ 2026-10-06 发布版：**DEBUG 区整块不创建**（用户：「什么 debug 功能都不需要」）。
	#
	#   原代码自己就写着「调试期加币按钮，发布时**必须删除**」。这里不删代码，
	#   改用**内建 feature tag** 条件化：导出 release 模板时 OS.has_feature("release")
	#   为真 ⇒ 整块跳过；编辑器里调试跑（F5）是 debug ⇒ 加币按钮照旧可用。
	#   ⇒ 满足「正式版没有调试功能」，又不用每次发布前手动删代码再改回来。
	#
	#   ⚠️ 判据用内建 tag，⛔ 不新增 custom_features —— 自己加的 tag 忘了配 preset 时
	#   会**静默失效**（按钮照样出现在正式版里）；"release" 由构建类型决定，不可能忘。
	#   ⚠️ `_set_debug_open()` 里已有 null 守卫（两个字段判 null），所以正式版
	#   字段留空不会在别处炸。
	#   ⚠️ 加币是**战场经济**的调试手段（星币）⇒ 牌桌档案里同样不该出现。
	if _is_battle() and not OS.has_feature("release"):
		content.add_child(make_divider())
		content.add_child(make_group_header("系统  SYSTEM"))
		# 三个常见经济档位的快速加币按钮：
		#   100 = 买 1 次超频 + 1 次经验档
		#   300 = 日常调试（刷新 / 加速 / 打捞都够用 1~2 次）
		#   999 = "把整局买穿"（验全档品质 / 满级后超频链）
		_dbg_btn = Button.new()
		_dbg_btn.custom_minimum_size = Vector2(0, 20)
		_dbg_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_dbg_btn.pressed.connect(func():
			_set_debug_open(_dbg_box == null or not _dbg_box.visible))
		content.add_child(_dbg_btn)

		_dbg_box = VBoxContainer.new()
		_dbg_box.add_theme_constant_override("separation", 5)
		_dbg_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var dbg := HBoxContainer.new()
		dbg.add_theme_constant_override("separation", 5)
		dbg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for amt in [100, 300, 999]:
			var b := _mk_btn("+%d 星币" % amt)
			b.pressed.connect(func(a = amt): add_coins_requested.emit(a))
			dbg.add_child(b)
		_dbg_box.add_child(dbg)
		content.add_child(_dbg_box)
		# ⚠️ 传 false：此刻窗口宽度还是 0，反推高度会拿到垃圾值（见 _set_debug_open 的说明）
		_set_debug_open(false, false)

	# 快捷键备忘 —— 设置窗的一大价值就是「让隐藏操作变得可发现」
	#
	# ⚠️ **不许开 autowrap**（`AUTOWRAP_OFF`）：开了之后这行的「最小高度」取决于
	#    当时拿到的宽度 —— 窗口宽度还是 0 的那一帧（刚 new 出来、还没 set_window_rect）
	#    会按「一个字一行」折出 800+ px 的最小高度，`_fit_height()` 于是把窗撑到 919px，
	#    底部留下 390px 空白（用户 2026-09-29 实测）。这一行本来就放得下，不需要折行。
	# ⚠️ 牌桌档案里那串战场快捷键（空格 / C / B / R）**一个都不存在** ⇒
	#    换成一句只说显示的话，⛔ 别把战场的说明写进牌桌（那是一页骗人的话）。
	var hint := Label.new()
	hint.text = "快捷键  空格 暂停/继续 · C 相机复位 · B 棋盘 · R 重开" if _is_battle() \
			else "分辨率与字号即时生效；牌桌不参与「界面缩放」"
	hint.add_theme_color_override("font_color", C_TEXT_FAINT)
	FONT.fs(hint, 9)
	hint.autowrap_mode = TextServer.AUTOWRAP_OFF
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(hint)


## 「显示 DISPLAY」分区的行（窗口分辨率 / 界面缩放）。
##
## ⚠️ 两块各自**只在对应平台**出现，而且正好互补：
##    · 窗口分辨率：**只桌面端**（手机上全屏，没有可调的余地）
##    · 界面缩放  ：**只移动端**（桌面有窗口尺寸可调，不需要整幅放大）
##   ⇒ 两个平台各看到一块，不会出现"空分区"。
##
## ⚠️ 返回 `Array[Control]`（标题 + 各行的**扁平**列表），调用方直接 add_child。
##    做成"返回行"而不是"自己 add_child"，是为了让 `_build_contents` 里的
##    分区顺序一眼可读 —— 本文件的分区顺序一直在被调整（见顶注）。
func _build_display_rows() -> Array:
	var rows: Array = []
	rows.append(make_group_header("显示  DISPLAY"))

	if RESOLUTION_SCRIPT.is_enabled():
		var items: Array = []
		for i in RESOLUTION_SCRIPT.CHOICES.size():
			items.append({"name": RESOLUTION_SCRIPT.label_of(i)})
		var blk := _build_choice_block(items, "name", 2,
				func(i: int): _pick_resolution(i))
		var btns: Array = blk["btns"]
		for b in btns:
			_res_btns.append(b as Button)
		var blk_rows: Array = blk["rows"]
		for r in blk_rows:
			rows.append(r)
		# ⚠️ 说明行必须补：`★` 是**前缀**（理由见 `EveResolution.label_of`），
		#    不解释一下玩家会以为是某种星级。
		# ⚠️ 这一行**必须短**：窗宽只有 320，「太长 + ⛔禁止 autowrap」会直接被裁掉。
		var note := Label.new()
		note.text = "★ = 推荐档（2560 × 1440）"
		note.add_theme_color_override("font_color", C_TEXT_FAINT)
		FONT.fs(note, 9)
		note.autowrap_mode = TextServer.AUTOWRAP_OFF
		note.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rows.append(note)

	if UI_SCALE_SCRIPT.is_enabled():
		var sc := _build_choice_block(UI_SCALE_SCRIPT.CHOICES, "name", 2,
				func(i: int): _pick_ui_scale(i))
		var sc_btns: Array = sc["btns"]
		for b in sc_btns:
			_scale_btns.append(b as Button)
		var sc_rows: Array = sc["rows"]
		for r in sc_rows:
			rows.append(r)

	rows.append(make_divider())
	return rows


## 分段单选块：一组按钮排成若干行，点谁谁亮。
##
## 返回 {"rows": Array[HBoxContainer], "btns": Array[Button]} ——
## 调用方把 rows 塞进 content（`_bg_btns` 这类引用则单独留着刷皮肤）。
##
## ⚠️ `btns` 的顺序恒等于 `items` 的顺序（与行无关）——
##    verify_run 靠「下标 i ↔ BACKGROUNDS[i]」挑一个不同条目来验证后端，
##    一旦顺序和 items 不一致，验的就是另一张背景（静默的假通过）。
func _build_choice_block(items: Array, label_key: String, cols: int,
		on_pick: Callable) -> Dictionary:
	var rows: Array[HBoxContainer] = []
	var btns: Array[Button] = []
	for i in items.size():
		var b := _mk_btn(String(items[i][label_key]))
		b.pressed.connect(on_pick.bind(i))
		btns.append(b)
		var row_idx := i / maxi(1, cols)
		while rows.size() <= row_idx:
			rows.append(_new_row(4))
		rows[row_idx].add_child(b)
	return {"rows": rows, "btns": btns}


## 滑杆行：标签 + 直角滑杆 + 百分比。
##
## ⚠️ `min_v/max_v/step_v` 默认是**音量口径**（0~1，步进 0.01）；
##    字号那一行传 0.80~1.30 / 0.05（见 `_build_contents` 的字号行）。
##
## 返回 {"row": HBoxContainer, "slider": HSlider, "num": Label}
func _build_slider_row(label: String, value: float, on_change: Callable,
		min_v: float = 0.0, max_v: float = 1.0, step_v: float = 0.01) -> Dictionary:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.custom_minimum_size = Vector2(0, 16)

	var k := Label.new()
	k.text = label
	k.add_theme_color_override("font_color", C_TEXT_DIM)
	FONT.fs(k, 11)
	k.custom_minimum_size = Vector2(42, 0)
	k.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(k)

	var s := HSlider.new()
	s.min_value = min_v
	s.max_value = max_v
	s.step = step_v
	s.value = clampf(value, min_v, max_v)
	s.custom_minimum_size = Vector2(90, 14)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_style_slider(s)
	row.add_child(s)

	var num := Label.new()
	num.custom_minimum_size = Vector2(36, 0)
	num.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	num.add_theme_color_override("font_color", C_TEXT)
	FONT.fs(num, 11)
	num.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(num)

	s.value_changed.connect(func(v: float):
		num.text = "%d%%" % int(round(v * 100.0))
		on_change.call(v))
	num.text = "%d%%" % int(round(s.value * 100.0))
	return {"row": row, "slider": s, "num": num}


## 给滑杆套上本工程的皮肤（直角 / 1px 边框 / 青色已填充段）。
##
## ⚠️ 默认 HSlider 是圆角 + 蓝色高亮，和 CheckButton 一样不属于这里的语言。
## ⚠️ Godot 的滑块把手（grabber）是 **icon 不是 stylebox**，
##    所以只能用一张 5×14 的纯色小图，不能给它一个 StyleBoxFlat。
static var _grabber_tex: Texture2D = null


static func _style_slider(s: HSlider) -> void:
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.10, 0.13, 0.15, 0.92)
	track.border_color = Color(0.42, 0.55, 0.60, 0.40)
	track.set_border_width_all(1)
	track.set_corner_radius_all(0)
	track.content_margin_top = 4
	track.content_margin_bottom = 4
	s.add_theme_stylebox_override("slider", track)

	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.55, 0.78, 0.82, 0.55)
	fill.set_corner_radius_all(0)
	fill.content_margin_top = 4
	fill.content_margin_bottom = 4
	s.add_theme_stylebox_override("grabber_area", fill)
	s.add_theme_stylebox_override("grabber_area_highlight", fill)

	if _grabber_tex == null:
		var img := Image.create(5, 14, false, Image.FORMAT_RGBA8)
		img.fill(Color(0.55, 0.78, 0.82, 0.95))
		_grabber_tex = ImageTexture.create_from_image(img)
	s.add_theme_icon_override("grabber", _grabber_tex)
	s.add_theme_icon_override("grabber_highlight", _grabber_tex)
	s.add_theme_icon_override("grabber_disabled", _grabber_tex)


func _new_row(sep: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", sep)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return row


func _mk_btn(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 22)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	EveButtonTheme.apply(b, "hud")
	return b


## 二态开关按钮。
##
## ⚠️ 用 [开] / [关] 前缀在**文字**里也写出来，不只靠皮肤颜色区分 ——
##    只靠颜色的话，色觉障碍玩家读不出当前状态（而且青/暗这两档对比本来就不大）。
func _make_toggle(key: String, label: String, on_press: Callable) -> Button:
	var b := _mk_btn(label)
	_toggles[key] = {"btn": b, "label": label, "on": false}
	b.pressed.connect(func():
		var st: Dictionary = _toggles[key]
		st["on"] = not bool(st["on"])
		_refresh_toggle(key)
		on_press.call(bool(st["on"])))
	_refresh_toggle(key)
	return b


func _refresh_toggle(key: String) -> void:
	var st: Dictionary = _toggles.get(key, {})
	if st.is_empty():
		return
	var on := bool(st["on"])
	var b: Button = st["btn"]
	b.text = "%s %s" % ["[开]" if on else "[关]", String(st["label"])]
	EveButtonTheme.apply(b, "hud_main" if on else "hud")


## DEBUG 折叠。收起时那三个加币按钮连最小高度都不占（VBox 不计隐藏子节点）。
##
## ⚠️ `refit` 参数不是多余的：构建阶段（`_build_contents` 里）窗口**宽度还是 0**，
##    此时反推高度拿到的是垃圾值（而且它会被写进 custom_minimum_size，
##    把后续所有布局都带歪）。构建时传 false，等 `_ready` 里布局稳定后再统一算一次。
func _set_debug_open(open: bool, refit: bool = true) -> void:
	if _dbg_box != null:
		_dbg_box.visible = open
	if _dbg_btn != null:
		_dbg_btn.text = "%s DEBUG（发布时删除）" % ["▾" if open else "▸"]
		EveButtonTheme.apply(_dbg_btn, "hud")
	if refit:
		_fit_height()


## 按内容反推窗高。
##
## ⚠️ 手写高度的后果本工程踩过两次：窗底多出一条填不满的死白
##    （`_content_margin` 拿到 EXPAND 后，富余高度全部堆在 VBox 末尾）。
func _fit_height() -> void:
	if content == null:
		return
	var need: Vector2 = content.get_combined_minimum_size()
	# ⚠️ 宽度还没定（刚建完、还没排过序）时量出来的是垃圾值，直接放弃这一轮
	if need.x <= 0.0:
		return
	# ⚠️ 上界守卫：一个「设置窗」不可能比视口的 **85%** 还高。
	#    量出更大的值只可能是拿错了数（典型：autowrap 控件在 0 宽下折出几十行），
	#    而把它写进 custom_minimum_size 会**永久**把窗撑大 —— 宁可不改、下帧再算。
	#    ⛔ 关键不变量不许用 assert（release 会被剥离），走 push_warning。
	# ★ 2026-10-07 由 60% 放宽到 85%：加了「显示 · 分辨率」14 档（2 列 7 行）之后
	#   设置窗真的变高了（实测内容 **824px**），60% 的 648 会把**正当**的高度也拒掉 ——
	#   表现是窗停在初值、下半截被切掉，而且只报一条 warning。
	#   ⚠️ 放宽不等于失去保护：原来要防的「未布局就量」现在被两道拦住 ——
	#     ① `_ready` 里 `await process_frame` 两次才量；② 下面 `need.x <= 0` 的早退。
	var limit := get_viewport_rect().size.y * 0.85
	if need.y > limit:
		push_warning("[设置窗] 内容最小高度 %.0f 超过视口 85%%（%.0f）—— 疑似未布局就量了，本次不改窗高"
				% [need.y, limit])
		return
	set_window_height(HEADER_H + need.y + 6.0 + 8.0 + 2.0)
	# ★ 窗高由内容反推 ⇒ 可能高过设计稿的 480（加了「显示 · 分辨率」实测 **866**）。
	#    `RECT_SETTINGS` 的 y=250 是配 480 高算的 ⇒ 250+866 = 1116 顶出屏外。
	#    ⇒ 上移进屏。⚠️ 同一件事在 `EveWindow.set_window_rect()` 里也做了一遍
	#      （HUD 每次刷新都会把窗摆回设计稿坐标）—— 两边都必须有，缺一边就会
	#      "开窗时是对的、刷新一次就掉下去"。
	var ny := _fit_y_in_viewport(position.y, size.y)
	if not is_equal_approx(ny, position.y):
		position.y = ny
		_base_rect = Rect2(_base_rect.position.x, ny, _base_rect.size.x, _base_rect.size.y)


# ------------------------------------------------------------------ 对外

func _pick_background(i: int) -> void:
	if i < 0 or i >= BACKGROUNDS.size():
		return
	var id := String(BACKGROUNDS[i]["id"])
	set_background_id(id)
	STORE.save_one("background", id)
	background_changed.emit(id)


func _pick_mood(i: int) -> void:
	if i < 0 or i >= MOODS.size():
		return
	var v := int(MOODS[i]["v"])
	set_mood(v)
	STORE.save_one("mood", v)
	mood_changed.emit(v)


## 界面缩放档。与背景 / 氛围同款：**立即生效 + 立即写盘**。
##
## ⚠️ 写盘写的是**原值**（0 = 自动），⛔ 不是解析后的倍数 ——
##    否则玩家选了「自动」之后再打开窗，高亮会跳到某个具体倍数上，
##    看起来像自己变了。
func _pick_ui_scale(i: int) -> void:
	if i < 0 or i >= UI_SCALE_SCRIPT.CHOICES.size():
		return
	var v := float(UI_SCALE_SCRIPT.CHOICES[i]["v"])
	set_ui_scale(v)
	STORE.save_one("ui_scale", v)
	ui_scale_changed.emit(v)


## 字号缩放。**改完立即生效**（不用关窗）：
##   ① 改倍数 → ② 把**已经建好的**控件就地重算 → ③ 自己按新内容重推窗高。
##
## ⚠️ 重算读的是节点上记的**设计字号**（meta），⛔ 不是「再乘一次」——
##    那样每拖一格都复利叠上去，几下就把字撑爆（见 `EveFont.reapply`）。
## ⚠️ 必须 `_fit_height()`：字变了 ⇒ 本窗内容的最小高度也变了，
##    不重推的话底部会留一条死白（本工程踩过两次的老病）。
func _pick_font_scale(v: float) -> void:
	FONT.set_scale(v)
	STORE.save_one("font_scale", FONT.scale)
	FONT.reapply(get_tree().root)
	# 字变高 ⇒ 商店会长高 ⇒ 告诉 HUD 重新上抬底部两条（⛔ 不转发给主控：
	# 3D 战场跑在原生分辨率上，跟 2D 字号无关）
	font_scale_changed.emit(FONT.scale)
	_fit_height()
	if not _font_slider.is_empty():
		(_font_slider["num"] as Label).text = "%d%%" % int(round(FONT.scale * 100.0))


## 主控打开窗时回写（**只改外观，不发信号** —— 叫 reapply 会把整棵树重刷一遍，
## 开窗那一下没必要）。
func set_font_scale(v: float) -> void:
	if _font_slider.is_empty():
		return
	# ⚠️ 存 0.0 = 没设过 / 旧文件 / 手改坏了 ⇒ 回落到**本平台出厂默认**
	#    （桌面 1.10 / 移动 1.20），⛔ 不是硬写 1.00。
	var s := FONT.default_scale() if v <= 0.0 else clampf(v, FONT.MIN_SCALE, FONT.MAX_SCALE)
	(_font_slider["slider"] as HSlider).set_value_no_signal(s)
	(_font_slider["num"] as Label).text = "%d%%" % int(round(s * 100.0))


## 窗口分辨率档。**本窗自己就把窗口改了**（`EveResolution.apply_index`），
## 不再让上层各写一遍尺寸逻辑（战斗场景与牌桌都要它 ⇒ 抄两份必然漂移）。
##
## ⚠️ 写盘写的是 **key 字符串**（`"2560x1440"`），⛔ 不是下标 ——
##    档位表将来增删时下标会漂移（本工程惯例：写的"位置"先问"这列表会增删吗"）。
## ⚠️ 牌桌 / 战场收到 `resolution_changed` 后**只做重铺/重绘**，
##    ⛔ 别再改一次窗口尺寸（两次改动之间会闪一帧）。
func _pick_resolution(i: int) -> void:
	if i < 0 or i >= RESOLUTION_SCRIPT.CHOICES.size():
		return
	STORE.save_one("resolution", String(RESOLUTION_SCRIPT.CHOICES[i]["key"]))
	RESOLUTION_SCRIPT.apply_index(get_window(), i)
	resolution_changed.emit(i)


## 主控打开窗时回写高亮（**只改外观，不发信号**）。
##
## ⚠️ 桌面端 `_res_btns` 是空的（那一行根本不建）⇒ 本函数直接返回，不是漏写。
func set_resolution(idx: int) -> void:
	if _res_btns.is_empty():
		return
	if idx < 0:
		idx = RESOLUTION_SCRIPT.current_index()
	for i in _res_btns.size():
		EveButtonTheme.apply(_res_btns[i], "hud_main" if i == idx else "hud")


## 音量滑杆。改完立即写盘 —— 音量是「调一次就定型」的典型，
## 不写盘等于每次开游戏都要重调。
func _pick_volume(kind: StringName, v: float) -> void:
	STORE.save_one(String(kind), v)
	volume_changed.emit(kind, v)


## 同步当前状态（主控打开窗时调一次，保证窗里显示的就是场上的实际值）。
##
## ⚠️ 四件事各自独立，不能合并成「一个 refresh」就完事：
##    单选组刷**皮肤** · 二态开关刷皮肤 + **文字** ·
##    滑杆刷**值 + 百分比**（且不发信号，见 `set_volume`）· 暂停刷按钮文字。
func set_state(state: Dictionary) -> void:
	set_background_id(String(state.get("background", "caldari_c07")))
	set_mood(int(state.get("mood", 0)))
	_set_toggle("fog", bool(state.get("fog", false)))
	_set_toggle("rings", bool(state.get("rings", false)))
	_set_toggle("board", bool(state.get("board", false)))
	_set_toggle("mute", bool(state.get("muted", false)))
	var vols: Dictionary = state.get("volumes", {})
	for kind in _sliders.keys():
		set_volume(kind, float(vols.get(String(kind), 1.0)))
	set_paused(bool(state.get("paused", false)))
	set_ui_scale(float(state.get("ui_scale", 0.0)))
	set_font_scale(float(state.get("font_scale", 1.0)))
	# ⚠️ 缺省值给 `-1`（= 「上层没说」）⇒ `set_resolution` 自己读盘算当前档，
	#    而不是把 -1 当成"第一档"高亮（那会让玩家以为默认是 4K）。
	set_resolution(int(state.get("resolution_index", -1)))


func set_background_id(id: String) -> void:
	_cur_bg = id
	for i in _bg_btns.size():
		var on := String(BACKGROUNDS[i]["id"]) == id
		EveButtonTheme.apply(_bg_btns[i], "hud_main" if on else "hud")
	set_status(_bg_name(id))


## 回写缩放档高亮。传**存档原值**（0 = 自动）。
##
## ⚠️ 桌面端 `_scale_btns` 是空的（那一行根本不建）⇒ 本函数直接返回，
##    不是漏写。
func set_ui_scale(saved: float) -> void:
	_cur_ui_scale = saved
	if _scale_btns.is_empty():
		return
	var idx := UI_SCALE_SCRIPT.choice_index(saved)
	for i in _scale_btns.size():
		EveButtonTheme.apply(_scale_btns[i], "hud_main" if i == idx else "hud")


func set_mood(mode: int) -> void:
	_cur_mood = mode
	for i in _mood_btns.size():
		var on := int(MOODS[i]["v"]) == mode
		EveButtonTheme.apply(_mood_btns[i], "hud_main" if on else "hud")


## 只改滑杆外观，**不发信号** —— 供主控回写实际状态（避免回环）
func set_volume(kind: StringName, v: float) -> void:
	var item: Dictionary = _sliders.get(kind, {})
	if item.is_empty():
		return
	var s: HSlider = item["slider"]
	s.set_value_no_signal(clampf(v, 0.0, 1.0))
	var num: Label = item["num"]
	num.text = "%d%%" % int(round(s.value * 100.0))


## 只改按钮外观，**不发信号** —— 供主控回写实际状态（避免回环）
func _set_toggle(key: String, on: bool) -> void:
	var st: Dictionary = _toggles.get(key, {})
	if st.is_empty():
		return
	st["on"] = on
	_refresh_toggle(key)


## 主控回写暂停态（键盘空格改的，窗不知道）。
##
## ⚠️ 不回写就会出现「场上已经停了、按钮还写着『暂停对局』」——
##    玩家再点一下以为在暂停，实际是继续，而且没有任何提示。
func set_paused(on: bool) -> void:
	_paused = on
	if _pause_btn == null:
		return
	_pause_btn.text = "▶ 继续对局" if on else "‖ 暂停对局"
	# 暂停态用警示色（橙）：它表示「当前处于非正常状态」，
	# 而不是「这是一个危险操作」 —— 恢复态才是常规主操作（青）。
	EveButtonTheme.apply(_pause_btn, "hud_warn" if on else "hud_main")
	FONT.fs(_pause_btn, 14)


func is_paused() -> bool:
	return _paused


func get_toggle(key: String) -> bool:
	var st: Dictionary = _toggles.get(key, {})
	return bool(st.get("on", false))


func _bg_name(id: String) -> String:
	for b in BACKGROUNDS:
		if String(b["id"]) == id:
			return String(b["name"])
	return id
