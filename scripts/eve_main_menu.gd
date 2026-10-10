extends Control


## ★ 字号缩放（2026-10-07）：⛔ 别直接调 `add_theme_font_size_override`，
## 一律走 `FONT.fs(node, 设计字号)` —— 它同时记住设计字号（供改滑块时就地重算）。
## ⚠️ 子类（`extends eve_window.gd` 的那 9 个）靠**继承**拿到这个常量，
##    它们自己再写一个会撞名（基类已有同名成员 ⇒ 子类编译失败，本工程踩过）。
const FONT := preload("res://scripts/ui/eve_font.gd")
## EVE 自走棋 —— 主界面（启动后的第一个页面）
##
## ══════════════════════════════════════════════════════════════════
##  术语与它在整局里的位置
## ══════════════════════════════════════════════════════════════════
##
##     MainMenu（本文件）  ──「开始」──→  battle_scene.tscn（一局）
##            ↑                                    │
##            └────── 设置窗「返回主界面」──────────┘
##
##  这个页面叫**主界面 / 大厅（Main Menu / Lobby）**，不叫启动页
##  （Splash 是只显示 logo 的几秒过渡）、也不叫引导页（Onboarding 只在首次出现、
##  教操作）。「模式选择」本来就属于主界面这一层 —— 本页面把模式与难度合并进来了。
##
## ── 为什么是「左列模式按钮 + 右侧并列竖长条」────────────────────
##  用户明确要求：不要"大块大方框里放图"，要干净的左列选项 + 右侧内容；
##  难度分级要能放"三个甚至更多" ⇒ 一难一条竖长条，并列排。
##  定稿见 `C:\godot\_export\ui_mainmenu\`（HTML 高保真稿 + 出图）。
##
## ── 为什么背景是一张贴图而不是 3D 天空盒 ────────────────────────
##  菜单相机不动、也不缩放，所以用**离线烘好的 1920x1080** 最省也最准：
##  那张图是从 EVE 立方体星云**直接投出的针孔视角**（不经过等距柱状，
##  见 skill eve-nebula-skybox 第 5 节），星点层按用户实机截图统计量拟合。
##  ⚠️ 星点**不能**烘进游戏天空盒：局内相机 zoom 会变（DEFAULT_ZOOM=3.32），
##     zoom 改的是 FOV ⇒ 天空盒整体放大 ⇒ 1px 星点会跟着变大。
##     菜单没有这个问题（FOV 固定），所以这里烘进图里是安全的。
##
## ── 三层结构 ────────────────────────────────────────────────────
##  ① 底图 TextureRect（铺满，1:1 不缩放）
##  ② 品牌 + 系统项
##  ③ 左列模式按钮（3 个）+ 右侧难度长条（数量由难度表决定）
##
## ⚠️ 配色一律取自 EveWindow 的常量口径，禁止另起一套。
## ⚠️ 难度数据全部来自 EveCampaignTiers.ROWS —— 本文件不许写死难度。
##    加一档难度 = 在表里加一条记录，本文件的条数与位置会自动跟上。

const TIERS := preload("res://scripts/data/eve_campaign_tiers.gd")
const BTN_THEME := preload("res://scripts/ui/eve_button_theme.gd")
const MENU_BG := preload("res://assets/backgrounds/caldari-c07-menu-1920x1080.png")
## 平台 UI 缩放档（主菜单只用它的 `apply_scene_default`）
const UI_SCALE_SCRIPT := preload("res://scripts/ui/eve_ui_scale.gd")
## ★ 非 16:9 分辨率下的**内容居中偏移**（见 EveLayout 顶注）。
const LAYOUT := preload("res://scripts/ui/eve_layout.gd")
## ★ 窗口分辨率档（2026-10-07）。⚠️ 只在桌面端生效，见 `EveResolution.is_enabled()`。
const RESOLUTION := preload("res://scripts/ui/eve_resolution.gd")
## ★ user:// 目录迁移（2026-10-07 项目名去掉「918」的收尾，见该文件顶注）
const USER_DIR := preload("res://scripts/core/eve_user_dir.gd")

## 一局场景（「开始」按钮的去处）
const BATTLE_SCENE := "res://scenes/battle_scene.tscn"
## ★ 2026-10-06 棋牌室（斗地主先行）。独立场景，与自走棋零耦合。
## 方案见 `docs/棋牌室-执行方案.md`。
const CARD_ROOM_MODE_ID := "cardroom"
## 斗地主牌局场景（观战模式：三个 AI 自动打）。P2 起从棋牌室卡片进入。
const DOUDIZHU_SCENE := "res://scenes/doudizhu.tscn"
## 开场剧情场景（**只在第一次玩时**经过它，见 `_on_start_pressed`）
const INTRO_SCENE := "res://scenes/intro_scene.tscn"
## 「第一次玩」的判据：第 1 模式（任务关卡）的第 1 难度（守卫边境）
const FIRST_MODE_ID := "campaign"
const FIRST_TIER_ID := "guard_border"
const PROGRESS := preload("res://scripts/core/eve_progress_store.gd")
## ★ 2026-10-10 主界面 BGM。菜单原本**没有音频宿主**（见 `_build_sys` 里那条
##    「菜单上没有这个宿主」的说明）⇒ 要出声必须自己起一个只做
##    「总线音量 + 一条 BGM」的实例，与牌桌（ddz_table）同一套做法。
const AUDIO_SCRIPT := preload("res://scripts/core/eve_audio.gd")
## 设置存档（读音量初值 —— 让玩家在设置窗里调的音乐音量**在主界面照样生效**）
const STORE := preload("res://scripts/core/eve_settings_store.gd")
## ★ 2026-10-10 i18n：文案取词入口（见 eve_text.gd 顶注）。
const T := preload("res://scripts/core/eve_text.gd")
## 对局存档（`user://run.cfg`）—— 「继续上局」入口靠它判断有没有档。
const RUN_STORE := preload("res://scripts/core/eve_run_store.gd")
## ★ 2026-10-10 主界面「设置」窗 —— 与战场 / 牌桌**共用同一个类**，只是换档案。
##   用 `PROFILE_MENU`（音频 + 分辨率；⛔ 无字号、无返回主界面，理由见该类顶注）。
const SETTINGS_SCRIPT := preload("res://scripts/ui/panels/eve_settings.gd")
## 设置窗宽度（设计空间像素）。高度由窗自己按内容反推，⛔ 别在这里定。
const SETTINGS_W := 320.0

## ★ 2026-10-10 版权声明。它不是"游戏模式"，但对玩家来说就是**左边按钮列表最下面**
##   的一项，而且要和模式按钮**共用同一套选中样式与键盘导航** ⇒ 作为伪模式挂在
##   `_modes` 末尾（`credits = true`）。⛔ 不放进 EXTRA_MODES：那里是"可玩模式"的数据。
##
## ⚠️ 它是 `_modes` 里唯一 `cards` 为空的项 ⇒ 所有"按卡片下标"的路径都要先
##    `_is_credits()` 挡一下，否则左右键的 `% 0` 与开始的 `cards[0]` 会越界报错。
const CREDITS_MODE_ID := "credits"
## 版权声明大方框（右侧，正好占满难度卡片那块地方：3 列 × 964 宽 / 470 高）。
const CREDITS_W := 964.0
const CREDITS_H := 470.0

# ══════════════════════════════════════════════════════════════════
#  配色（口径同 scripts/ui/eve_window.gd）
# ══════════════════════════════════════════════════════════════════
const C_TEXT := Color(0.70, 0.82, 0.85)
const C_TEXT_HI := Color(0.91, 0.96, 0.97)
const C_DIM := Color(0.44, 0.55, 0.59)
const C_ACCENT := Color(0.55, 0.78, 0.82)
const C_ACCENT_HI := Color(0.84, 0.95, 0.97)
const C_GOLD := Color(0.91, 0.76, 0.35)
const C_STRIP := Color(0.039, 0.055, 0.067, 0.66)
const C_STRIP_ON := Color(0.063, 0.094, 0.110, 0.78)
const C_STRIP_LOCK := Color(0.035, 0.047, 0.055, 0.60)
const C_STRIP_LOCK_ON := Color(0.051, 0.071, 0.082, 0.72)
const C_BORDER := Color(0.42, 0.55, 0.60, 0.34)
const C_BORDER_LOCK := Color(0.42, 0.55, 0.60, 0.26)
const C_SEP := Color(0.42, 0.55, 0.60, 0.24)

# ══════════════════════════════════════════════════════════════════
#  布局（照抄定稿稿，基准 1920x1080）
#
#  ⚠️ 坐标是**绝对像素**，与 EveHudRoot 的 RECT_* 同一口径。
#     窗口是 1920x1080 + stretch canvas_items/expand（见 project.godot），
#     所以这里按设计分辨率写死即可。
# ══════════════════════════════════════════════════════════════════
const BRAND_POS := Vector2(56, 76)
const MODES_POS := Vector2(56, 296)
const MODE_W := 300.0
const MODE_H := 62.0
const MODE_GAP := 14.0
const STRIP_POS := Vector2(660, 296)
const STRIP_W := 300.0
const STRIP_H := 470.0
const STRIP_GAP := 32.0
## 棋牌室用**方框**（2 行 2 列），比难度竖条矮得多。
## ⚠️ 两套尺寸都由模式表里的 `layout` 决定，⛔ 不在卡片代码里写死 ——
##    见 `_layout_of()`。将来再加网格型模式（比如更多棋牌）直接复用。
const GRID_W := 300.0
const GRID_H := 196.0
const GRID_GAP_V := 24.0
const SYS_MARGIN_R := 120.0
const SYS_TOP := 88.0

## 难度表之外的另外两个模式：它们没有难度分级 ⇒ 各自只有一张"条"。
## 数据形状与 EveCampaignTiers.ROWS 一致，这样渲染路径只有一条。
const EXTRA_MODES: Array = [
	{
		# ★ 2026-10-06：棋牌室。**刻意排在「无尽模式」之前**（列表第 2 项）——
		#   但⛔ 绝不排在「任务关卡」之前：主入口必须仍是自走棋，
		#   免得新玩家第一眼以为这是个棋牌游戏。
		# ★ 2026-10-06 用户定：**「棋牌室」→「娱乐总汇」**。出处：EVE 里本来就有
		#   「娱乐总汇」这种供人消遣的场所；而且它顺手解决了「代币叫什么」
		#   —— ⇒ **娱乐币**。
		"id": "cardroom", "name": "娱乐总汇", "meta": "斗地主 · 可试玩", "locked": false,
		# ★ 2026-10-06 改：**不再用独立场景**（原 `card_room.tscn` 已删）。
		#   点「棋牌室」直接在主菜单右侧铺开这 4 张卡，排成 2 行 2 列
		#   （列数与卡片尺寸见 `_layout_of()`）。
		#   ⚠️ `open` 决定两件事：卡片是否压暗 + 「开始」按钮是否可点。
		#      斗地主 `open=true`（P0 阶段点了会给「制作中」提示，⛔ 不静默）；
		#      其余三个 `open=false` ⇒ 真禁用。
		"cards": [
			{
				"name": "斗地主", "code": "DOUDIZHU", "open": true,
				"desc": "一副牌，三个对手。抢地主、炸弹、王炸。",
				"stats": [["玩法", "斗地主", ""], ["对手", "电脑 · 3 人", ""],
						["状态", "开发中", ""]],
			},
			{
				"name": "川麻", "code": "SICHUAN", "open": false,
				"desc": "四川麻将 · 血战到底。缺一门、刮风下雨。",
				"stats": [["玩法", "四川麻将", ""], ["对手", "电脑 · 3 人", ""],
						["状态", "待开发", ""]],
			},
			{
				"name": "日麻", "code": "RIICHI", "open": false,
				"desc": "立直麻将。役种、宝牌、振听。",
				"stats": [["玩法", "立直麻将", ""], ["对手", "电脑 · 3 人", ""],
						["状态", "待开发", ""]],
			},
			{
				"name": "升级", "code": "SHENGJI", "open": false,
				"desc": "拖拉机 · 4 人 2 队。亮主反主、甩牌抠底。",
				"stats": [["玩法", "升级", ""], ["对手", "电脑 · 3 人", ""],
						["状态", "待开发", ""]],
			},
		],
	},
	{
		"id": "endless", "name": "无尽模式", "meta": "最高纪录　—", "locked": true,
		"cards": [{
			"name": "无尽模式", "code": "ENDLESS", "open": false,
			"desc": "没有终点。一波接一波的敌方舰队，波数越高吨位越重、编制越脏。"
					+ "撑到撑不住为止，只比谁走得更远。",
			"stats": [["对手", "电脑舰队 · 无限波次", ""], ["终点", "无 · 直到全灭", ""],
					["纪录", "—", "gold"], ["状态", "尚未开放", ""]],
		}],
	},
	{
		"id": "versus", "name": "多人对战", "meta": "即将开放", "locked": true,
		"cards": [{
			"name": "多人对战", "code": "VERSUS", "open": false,
			"desc": "与其他指挥官同场博弈，八人各自为战。对手的阵容在变化，"
					+ "没有固定解法 —— 这是留给后期的模式。",
			"stats": [["对手", "其他玩家 · 8 人", ""], ["终点", "最后存活者获胜", ""],
					["前置", "需要联网与服务器", ""], ["状态", "尚未开放", ""]],
		}],
	},
]

var _modes: Array = []
var _mode_idx: int = 0
var _pick: Dictionary = {}          ## mode_id → 选中的难度下标

var _mode_btns: Array[Button] = []
var _mode_names: Array[Label] = []
var _mode_metas: Array[Label] = []
var _mode_bars: Array[ColorRect] = []
var _mode_arrows: Array[Label] = []
var _strip_row: GridContainer = null
## 当前模式的卡片尺寸 / 列数 —— 由 `_rebuild_strips()` 每次按模式设好，
## `_make_strip()` 只读它。⛔ 别在 `_make_strip` 里直接引用 STRIP_W/H：
## 那样棋牌室会被画成 470 高的竖条。
var _card_w := STRIP_W
var _card_h := STRIP_H
var _strip_panels: Array[PanelContainer] = []
var _strip_bars: Array[ColorRect] = []
## ★ 内容居中层：除底图之外的一切都挂在它身上（非 16:9 分辨率下整体平移）。
var _content: Control = null
## ★ 主界面 BGM 宿主。
## ⚠️ 声明成 **Variant** 而不是 `Node`：`AudioStreamPlayer` 之外的成员
##    （`set_volume` / `play_music`）在 `Node` 基类上没有，写死类型会**解析失败**
##    —— 牌桌踩过同一个坑，见 `ddz_table` 的同款说明。
var _audio: Variant = null
## ★ 2026-10-10 版权声明大方框。**只建一次**，之后靠 `visible` 切换 ——
##    每次 `_refresh()` 重建会让文字闪一下，也白白丢掉旧节点的引用。
var _credits_panel: PanelContainer = null
## ★ 2026-10-10 设置窗（`eve_settings.gd` 的 `PROFILE_MENU` 档案）。
## ⚠️ 声明成 **Variant**：要调 `set_state()` / `set_window_rect()` / `move_to_front()`
##    这些 `Control` 基类上没有的成员，写成具体类型会**解析失败**（牌桌踩过同款坑）。
var _settings: Variant = null
## 右上角「设置」按钮（开 / 关同一扇窗）。
var _settings_btn: Button = null
## 「继续上局」（有对局存档时才 `visible`；见 `_build_sys`）。
var _continue_btn: Button = null


func _ready() -> void:
	# ★ 2026-10-10 i18n：**必须早于任何 UI 构建** —— 文案是建的时候取词的。
	T.apply_saved()
	# ★★ 第一件事：把**旧项目名**下的存档搬过来（2026-10-07 改显示名的一次性收尾）。
	#    ⚠️ 必须排在所有 `user://` 读写**之前** —— 下面 `RESOLUTION.apply_from_settings()`
	#       就要读 `settings.cfg`，晚了会读到"空设置"再用默认值覆盖回去，
	#       玩家的音量/字号/分辨率就**静默重置**了（迁移反而变成破坏）。
	#    ⚠️ 幂等：目标已存在的文件不动 ⇒ 每次启动都跑也无所谓。
	USER_DIR.migrate_legacy()
	# 防御：被 `SCRIPT.new()` 直接造出来时锚点是默认值（尺寸 0x0），
	# 底图 TextureRect 锚满父节点就等于没画 ⇒ 整张图全黑。真场景（.tscn）里
	# 锚点已经设好了，这一行不会生效。
	if size == Vector2.ZERO:
		set_anchors_preset(Control.PRESET_FULL_RECT)
	# ★ 主菜单**恒定 1.0 缩放**（2026-10-07）。
	#   ⚠️ `content_scale_factor` 是根窗口属性，跨场景不会自动复位 ——
	#      不写这一句就变成「进过一次战场 ⇒ 回主菜单也被放大」，
	#      而本菜单是按 1920×1080 死坐标 + 1:1 烘好的背景图做的（放大就散了）。
	#   ⚠️ 它不是「清掉玩家的设置」：值还在 settings.cfg 里，下次进战场照样放大。
	UI_SCALE_SCRIPT.apply_scene_default(get_window())
	# ★ 字号缩放：主菜单**恒定 100%**（2026-10-07，用户实测）。
	#   ⚠️ 为什么不是 `load_from_settings()`：主菜单是按 1920×1080 死坐标排的
	#      —— 模式按钮只有 62px 高，字一放大就顶破方框（用户实测 130% 超出）。
	#      与 `apply_scene_default` 是同一个理由：非战斗场景 = 固定版面。
	#   ⚠️ 它不是「清掉玩家的设置」：值还在 settings.cfg 里，进战场照样按档位放大。
	FONT.reset_scale()
	# ★ 分辨率：读盘并应用（桌面端才有；无头/移动端内部直接返回）。
	#   ⚠️ 必须在量 `_content` 之前 —— 窗口尺寸变了，设计空间才定得下来。
	RESOLUTION.apply_from_settings(get_window())
	# ★ 底图**先加**：它挂在根上、铺满整个窗口（含非 16:9 多出来的边）。
	#   ⚠️⚠️ 顺序不能反！Godot 里**后加的子节点画在上面** ——
	#      把 `_content` 建在 `_build_bg()` 之前的话，底图会盖住全部内容，
	#      表现是「4:3 下主菜单整屏只剩星云」（2026-10-07 出图实测踩到，
	#      而 verify_menu 那 38 条断言**全绿** —— 它不看像素）。
	_build_bg()
	# ★ 2026-10-10：主界面 BGM（见 `_build_audio` 的说明）。
	#   ⚠️ 放在建内容层之前：它只往根上挂两个 AudioStreamPlayer、与版面无关，
	#      但越早起播越不容易听出「进了菜单半秒没声」。
	_build_audio()
	# ★ 内容居中层（非 16:9 分辨率档：1920×1200 之类）。
	#   为什么是**另一层**而不是直接挪 root：底图要铺满整个窗口（含多出来的边），
	#   而品牌 / 模式 / 卡片全部按 1920×1080 死坐标排 ⇒ 内容整体平移即可。
	_content = Control.new()
	_content.name = "Content"
	_content.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_content)
	_modes = _build_mode_table()
	for m in _modes:
		_pick[String(m["id"])] = 0
	_build_brand()
	_build_sys()
	_build_version_tag()
	_build_modes()
	_build_strips()
	_build_credits_panel()
	# ★ 2026-10-10 设置窗**最后建** —— Godot 里后加的子节点画在上面，
	#   建早了会被模式按钮 / 难度卡片盖住（底图那处踩过同一个坑）。
	#   ⚠️ 它挂在 `_content` 上 ⇒ 坐标即基准区坐标，跟着内容一起居中。
	_build_settings()
	_refresh()
	_layout_content()
	resized.connect(_layout_content)


## 把内容层摆到「基准区居中」的位置。
##
## ⚠️ 判据用**根 Control 自己的 `size`**（= 设计空间），⛔ 不用 `get_window().size`：
##    无头模式下窗口尺寸是假的 (64,64)，而 Control 的 size 是引擎已经拉伸好的真值。
func _layout_content() -> void:
	if _content == null:
		return
	var base := LAYOUT.BASE
	_content.position = LAYOUT.origin_of(size)
	_content.size = base


## 主界面 BGM（**只为「一条 BGM + 总线音量」存在**，不做任何打击反馈）。
##
## ⚠️ 音量读**存档**而不是 `_audio.volumes()`：后者是刚 new 出来的实例的
##    出厂默认值，写进总线会把玩家在战场/设置窗里调好的音乐音量重置回默认
##    （总线音量是全局的）。牌桌踩过同一个坑，见 `ddz_table._build_audio()`。
func _build_audio() -> void:
	_audio = AUDIO_SCRIPT.new()
	_audio.name = "MenuAudio"
	add_child(_audio)
	var s: Dictionary = STORE.load_all()
	_audio.set_volume(&"master", float(s.get("master", 1.0)))
	_audio.set_volume(&"sfx", float(s.get("sfx", 0.60)))
	_audio.set_volume(&"amb", float(s.get("amb", 0.39)))
	_audio.set_volume(&"music", float(s.get("music", 0.32)))
	_audio.set_muted(bool(s.get("muted", false)))
	# ★ 主界面 BGM = City of Night（逻辑名 "menu"，`menu_01.ogg`，68.25s 无缝循环）。
	_audio.play_music("menu")


## ★ 2026-10-10 主界面「设置」窗（与战场 / 牌桌**共用同一个类**，换 `PROFILE_MENU` 档案）。
##
## ⚠️ `profile` 必须在 `add_child` **之前**设好 —— `_ready` 里就按它决定建哪些分区。
## ⚠️ `layout_key` 用**独立的一个**：⛔ 别与战场 / 牌桌共用存档位（三方窗尺寸不同，
##    共用一个键会让窗一进来就落在别人的坐标上）。
## ⚠️ 它挂 `_content` 上（跟着内容居中），且是 `_content` 的**最后一个**子节点
##    （在 `_build_credits_panel()` 之后建）—— Godot 里后加的画在上面。
func _build_settings() -> void:
	_settings = SETTINGS_SCRIPT.new()
	_settings.name = "MenuSettings"
	_settings.profile = SETTINGS_SCRIPT.PROFILE_MENU
	_settings.layout_key = "menu_settings"
	_content.add_child(_settings)
	_settings.visible = false
	# 音量 / 静音直接回写到菜单自己的音频宿主（它已在 `_build_audio()` 里建好）。
	_settings.volume_changed.connect(func(kind: StringName, v: float):
		if _audio != null:
			_audio.set_volume(kind, v))
	_settings.mute_toggled.connect(func(on: bool):
		if _audio != null:
			_audio.set_muted(on))
	# 分辨率变了 ⇒ 窗口尺寸变 ⇒ 内容的居中偏移变 ⇒ 把窗与内容一起重摆。
	_settings.resolution_changed.connect(func(_i: int):
		_place_settings()
		_layout_content())
	# ★ 2026-10-10：标题栏右上角的 ✕ ⇒ 关掉本窗（与 `_toggle_settings()` 的隐藏口径一致）。
	_settings.closed.connect(func() -> void: _settings.visible = false)
	_place_settings()


## 把设置窗摆在设计空间**居中偏上**。
##
## ⚠️ 它挂在 `_content` 上 ⇒ 坐标即「基准区」坐标，⛔ 不用再补居中偏移
##    （`_content` 自己已经被 `_layout_content()` 挪到居中位置了）。
## ⚠️ 高度**不由这里定**：`EveSettingsWindow._fit_height()` 会按内容反推并接管。
func _place_settings() -> void:
	if _settings == null:
		return
	var base := LAYOUT.BASE
	_settings.set_window_rect((base.x - SETTINGS_W) * 0.5, 70.0, SETTINGS_W, 480.0)


## 右上角「设置」：开 / 关同一扇窗（再点一次收起 —— 与牌桌同一个交互）。
##
## ⚠️ 打开时回写**全部真实状态**：窗里显示的必须就是实际值，否则玩家看到的
##    开关与实际不符，点一下反而改成了他不想要的那个。
func _toggle_settings() -> void:
	if _settings == null:
		return
	if _settings.visible:
		_settings.visible = false
		return
	_place_settings()
	var vols: Dictionary = _audio.volumes() if _audio != null else {}
	_settings.set_state({
		"resolution_index": RESOLUTION.current_index(),
		"ui_scale": float(STORE.load_all().get("ui_scale", 0.0)),
		"muted": bool(vols.get("muted", false)),
		"volumes": vols,
	})
	_settings.visible = true
	_settings.move_to_front()


## 模式表 = 任务关卡（难度来自表）+ 两个无分级的模式
func _build_mode_table() -> Array:
	var first: Dictionary = TIERS.ROWS[0]
	var meta := T.t("MODE_CAMPAIGN_META", "%d 回合 · 共 %d 个难度") \
			% [int(first["rounds"]), TIERS.ROWS.size()]
	var out: Array = []
	out.append({"id": "campaign", "name": "任务关卡", "meta": meta, "locked": false,
			"cards": TIERS.ROWS})
	for m in EXTRA_MODES:
		out.append(m)
	# ★ 2026-10-10：版权声明（伪模式，见 CREDITS_MODE_ID 的注释）。
	#   **必须最后追加** —— 用户要求它落在左边按钮的最下方。
	out.append({
		"id": CREDITS_MODE_ID, "name": "版权声明", "meta": "致谢 · 开源许可",
		"locked": false, "credits": true, "cards": [],
	})
	return out


func _cards_of(idx: int) -> Array:
	return _modes[idx]["cards"]


# ------------------------------------------------------------ 文案取词（i18n）
#
# ★★ 设计口径：**数据表里仍是中文源文** —— `EveCampaignTiers.ROWS` 与
#    `EXTRA_MODES` 都保持 `const`（⛔ 别为了塞 `T.t()` 把它们改成函数：
#    const 初始化器里调不了函数，改成函数又会牵动 `verify_menu` 的读法）。
#    中文在这里既是**兜底**也是**活文档**；**渲染时**才过一遍 `T.t()`。
#    ⇒ 加语言不用改数据表，改数据表也不用碰 i18n。
# ⚠️ 默认 locale = zh_CN ⇒ 取词原样返回中文 ⇒ 既有行为/断言/截图逐字不变。

## ★ 下面四个都是 `static` —— 不碰任何实例状态，**自检可以静态调用**
##   （`verify_i18n` 的 ⑤ 就是静态跑的，⛔ 别改成实例方法）。

## 模式名 / 副标题（按模式 **id** 取 key：`MODE_CAMPAIGN_NAME` …）。
## ⚠️ `field` 一律 `to_upper()` —— 调用点写的是小写 `"name"`，不转就拼出
##    `MODE_CAMPAIGN_name` 这种对不上 CSV 的 key（英文**静默回落中文**，10-10 踩到）。
static func _mode_key(m: Dictionary, field: String) -> String:
	return "MODE_%s_%s" % [String(m["id"]).to_upper(), field.to_upper()]


static func _mode_txt(m: Dictionary, field: String) -> String:
	return T.t(_mode_key(m, field), String(m[field]))


## 卡片的 key 前缀：任务关卡用 `id`（`guard_border`…），娱乐总汇的卡用 `code`
## （`DOUDIZHU`…）—— 两边都取 ASCII 稳定标识，⛔ 别用中文当 key。
static func _card_key(card: Dictionary) -> String:
	var id := String(card.get("id", ""))
	if id == "":
		id = String(card.get("code", ""))
	return id.to_upper()


static func _card_txt(card: Dictionary, field: String) -> String:
	return T.t("CARD_%s_%s" % [_card_key(card), field.to_upper()],
			String(card.get(field, "")))


## `stats` 行的**键与值**取词表（中文源文 → key）。
## ⛔ 只用于显示；⛔ 别拿这些中文去分支（工程红线：逻辑只认 id）。
## ⚠️ 表里的中文必须与 CSV 的 `zh_CN` 列**逐字一致**（`verify_i18n` 会对拍）。
## ⚠️ 没登记进这张表的取值 ⇒ 原样返回中文（英文版会露中文，但不会崩、不会空）。
const STAT_KEYS: Dictionary = {
	"玩法": &"CARD_K_PLAY",
	"对手": &"CARD_K_OPP",
	"状态": &"CARD_K_STATUS",
	"终点": &"CARD_K_END",
	"纪录": &"CARD_K_RECORD",
	"前置": &"CARD_K_REQ",
	"回合数": &"CARD_K_ROUNDS",
	"解锁": &"CARD_K_UNLOCK",
	# ── 值 ──────────────────────────────────────────────────────
	"电脑 · 3 人": &"CARD_V_CPU3",
	"电脑舰队 · 4 派系": &"CARD_V_FLEET4",
	"电脑舰队 · 成建制": &"CARD_V_FLEET_FORMAL",
	"电脑舰队 · 无限波次": &"CARD_V_FLEET_WAVES",
	"其他玩家 · 8 人": &"CARD_V_PLAYERS8",
	"待定": &"CARD_V_TBD",
	"可进入": &"CARD_V_OPEN",
	"开发中": &"CARD_V_WIP",
	"尚未开放": &"CARD_V_CLOSED",
	"默认开放": &"CARD_V_UNLOCK_DEFAULT",
	"无 · 直到全灭": &"CARD_V_NO_END",
	"最后存活者获胜": &"CARD_V_LAST_ALIVE",
	"需要联网与服务器": &"CARD_V_NEED_NET",
	"斗地主": &"CARD_V_PLAY_DDZ",
	"四川麻将": &"CARD_V_PLAY_SICHUAN",
	"立直麻将": &"CARD_V_PLAY_RIICHI",
	"升级": &"CARD_V_PLAY_SHENGJI",
	"15 回合": &"CARD_V_ROUNDS15",
	"25 回合": &"CARD_V_ROUNDS25",
	"通关第 1 难度": &"CARD_V_UNLOCK_T1",
	"通关第 2 难度": &"CARD_V_UNLOCK_T2",
}


static func _stat_txt(s: String) -> String:
	var k := String(STAT_KEYS.get(s, ""))
	return T.t(k, s) if k != "" else s


# ------------------------------------------------------------------ 构建

func _build_bg() -> void:
	var t := TextureRect.new()
	t.name = "MenuBg"
	t.texture = MENU_BG
	t.set_anchors_preset(Control.PRESET_FULL_RECT)
	# ★ 铺满，但**保持比例**（2026-10-07 改）：底图是 1920×1080 的定稿。
	#   16:9 下 KEEP_ASPECT_COVERED == 铺满（行为不变）；非 16:9 的档
	#   （1920×1200 之类）下它按比例放大到盖满，多余的部分裁掉 ——
	#   ⛔ 绝不用 STRETCH_SCALE：那会把星点与星云整体拉变形。
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(t)


func _build_brand() -> void:
	var box := VBoxContainer.new()
	box.name = "Brand"
	box.position = BRAND_POS
	box.add_theme_constant_override("separation", 8)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h := _label(T.t("MENU_BRAND", "EVE 自走棋"), 26, C_TEXT_HI)
	h.add_theme_constant_override("letter_spacing", 0)
	var s := _label("NEW EDEN AUTO CHESS", 9, Color(0.69, 0.80, 0.84, 0.80))
	box.add_child(h)
	box.add_child(s)
	_content.add_child(box)


func _build_sys() -> void:
	var box := VBoxContainer.new()
	box.name = "Sys"
	box.alignment = BoxContainer.ALIGNMENT_END
	box.add_theme_constant_override("separation", 10)
	box.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	# ⚠️ 宽度要够放**四**个按钮（继续上局 / 设置 / 回看片头 / 退出游戏，
	#    各 84 + 三道 18 间隔 = 390）⇒ 留 400。原来 220 只够两个。
	#    「继续上局」无档时 `visible=false`（HBox 会把它从布局里摘掉），
	#    所以三个按钮时也不会留空。
	box.offset_left = -(SYS_MARGIN_R + 400.0)
	box.offset_right = -SYS_MARGIN_R
	box.offset_top = SYS_TOP
	box.offset_bottom = SYS_TOP + 70.0

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 18)
	# ★ 2026-10-10（审查 2#2）：「继续上局」—— 有对局存档时才可见。
	#
	#   ⚠️ **始终建出来**、只切 `visible`：① 无档时 HBox 自动把它摘出布局，
	#     不会留空；② 节点结构恒定 ⇒ 任何"数按钮"的验收不受存档影响。
	#   ⛔ 不做成"没档时也显示但点了没反应"（红线 9）。
	var cont_btn := Button.new()
	cont_btn.name = "ContinueRunBtn"
	cont_btn.text = T.t("MENU_CONTINUE", "继续上局")
	BTN_THEME.apply(cont_btn, "hud_main")
	FONT.fs(cont_btn, 12)
	cont_btn.custom_minimum_size = Vector2(84, 26)
	cont_btn.size_flags_horizontal = Control.SIZE_SHRINK_END
	cont_btn.visible = RUN_STORE.has_run()
	cont_btn.pressed.connect(_on_continue_run)
	row.add_child(cont_btn)
	_continue_btn = cont_btn
	# ★ 2026-10-10 补上「设置」（用户要求：主界面右上角要有设置，主要设置都放进去）。
	#   此前缺它的唯一理由是「菜单没有音频宿主 ⇒ 音量滑杆是死旋钮」（红线 9）；
	#   `_build_audio()` 之后菜单**已经有** `_audio` 宿主了 ⇒ 那个理由不再成立。
	#   ⚠️ 用 `PROFILE_MENU` 档案：音频 + 分辨率；⛔ 无字号（菜单恒定 100%）、
	#      无「返回主界面」（我们就在主界面）。
	var set_btn := Button.new()
	set_btn.name = "SettingsBtn"
	set_btn.text = T.t("MENU_SETTINGS", "设置")
	BTN_THEME.apply(set_btn, "plain")
	FONT.fs(set_btn, 12)
	set_btn.custom_minimum_size = Vector2(84, 26)
	set_btn.size_flags_horizontal = Control.SIZE_SHRINK_END
	set_btn.pressed.connect(_toggle_settings)
	row.add_child(set_btn)
	_settings_btn = set_btn
	#
	# 「回看片头」：开场剧情**默认只在第一次玩时出现**（存 progress.cfg），
	# 所以必须留一个显式的回看入口 —— **跳过不可以是不可逆的**。
	var replay_btn := Button.new()
	replay_btn.name = "ReplayIntroBtn"
	replay_btn.text = T.t("MENU_REPLAY_INTRO", "回看片头")
	BTN_THEME.apply(replay_btn, "plain")
	FONT.fs(replay_btn, 12)
	replay_btn.custom_minimum_size = Vector2(84, 26)
	replay_btn.size_flags_horizontal = Control.SIZE_SHRINK_END
	replay_btn.pressed.connect(_on_replay_intro)
	row.add_child(replay_btn)

	var quit_btn := Button.new()
	quit_btn.name = "QuitBtn"
	quit_btn.text = T.t("MENU_QUIT", "退出游戏")
	BTN_THEME.apply(quit_btn, "plain")
	FONT.fs(quit_btn, 12)
	quit_btn.custom_minimum_size = Vector2(84, 26)
	quit_btn.size_flags_horizontal = Control.SIZE_SHRINK_END
	quit_btn.pressed.connect(_on_quit)
	row.add_child(quit_btn)
	box.add_child(row)

	# ⚠️ 版本号**不再放这里**（2026-10-10 用户要求）：移到主界面**右下角**，
	#    见 `_build_version_tag()`。以后导出只改 `application/config/version`，
	#    右下角自动跟着变（永久管线，见 MEMORY「导出」章）。
	_content.add_child(box)


## ★ 2026-10-10 主界面**右下角**版本号（显示 `V<application/config/version>`）。
##
## ⚠️ 版本号**只读 `application/config/version`**（`project.godot` 的 `config/version`）
##    —— ⛔ 这里不许另写死一个数字。导出流程只改那一处，右下角就自动更新
##    （**永久管线**：导出改版本 ⇒ 右下角版本号默认跟着变）。
## ⚠️ 锚在 `_content` 上（=`LAYOUT.BASE` 1920×1080）⇒ 非 16:9 下跟着内容一起居中，
##    始终贴在基准区右下角。
## ⚠️ 用 `set_anchors_and_offsets_preset`（⛔ 不是 `set_anchors_preset`）：后者会
##    **保持 0×0 的当前矩形**、量不出正确位置（见 MEMORY §10 的同类坑）。
func _build_version_tag() -> void:
	var ver := str(ProjectSettings.get_setting("application/config/version", "0.0.0"))
	# ⚠️ **不加暗底**（用户 2026-10-10 明确要求）⇒ 必须用**深色字**：底图右下角是
	#    亮星云（实测 RGB≈160,180,192），浅色字根本读不出来；深色字对比度 ≈ 6:1。
	var tag := _label(T.t("MENU_VERSION", "当前版本 V%s") % ver, 11, Color(0.12, 0.16, 0.19, 0.92))
	tag.name = "VersionTag"
	tag.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	tag.offset_left = -170.0
	tag.offset_right = -56.0
	tag.offset_top = -50.0
	tag.offset_bottom = -26.0
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_content.add_child(tag)


## 当前选中的是不是「版权声明」这一项。
func _is_credits() -> bool:
	return String(_modes[_mode_idx]["id"]) == CREDITS_MODE_ID


## 版权声明大方框（右侧）。文字口径见下方各行 ——
##   · 游戏本体（架构 / 脚本 + 开源地址）→ 星视寰宇 / xshynews · GPL v3
##   · EVE 题材与美术素材             → Fenris Creations（原 CCP Games）
##   · 背景音乐                       → 乌鸦Producer · 本项目版本经 AI 重编曲
##
## ⚠️ 只建一次、之后靠 `visible` 切换（见 `_credits_panel` 的说明）。
## ⚠️ autowrap 的 Label **必须给死宽**（`CREDITS_W - 两侧留白`）——
##    宽度为 0 时它会按"一个字一行"折行，量出的最小高度大得离谱
##    （`_make_strip` 的 desc 踩过同一个坑）。
func _build_credits_panel() -> void:
	_credits_panel = PanelContainer.new()
	_credits_panel.name = "Credits"
	_credits_panel.position = STRIP_POS
	_credits_panel.size = Vector2(CREDITS_W, CREDITS_H)
	_credits_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_credits_panel.add_theme_stylebox_override("panel", _strip_style(false, true))
	_credits_panel.visible = false

	var mn := MarginContainer.new()
	mn.add_theme_constant_override("margin_left", 34)
	mn.add_theme_constant_override("margin_right", 34)
	mn.add_theme_constant_override("margin_top", 28)
	mn.add_theme_constant_override("margin_bottom", 26)
	_credits_panel.add_child(mn)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mn.add_child(col)

	# 正文可用宽度 = 面板宽 - 两侧留白（再减 2 给边框，与 desc 同口径）
	var inner := CREDITS_W - 68.0 - 2.0
	col.add_child(_label(T.t("MODE_CREDITS_NAME", "版权声明"), 20, C_TEXT_HI))
	col.add_child(_label("COPYRIGHT & CREDITS", 9, Color(0.55, 0.78, 0.82, 0.72)))
	col.add_child(_vspace(16))

	# 每条 = 小标题 + 若干正文行；正文自动折行。
	# ⚠️ `k` = i18n key 的**段名**（`CREDITS_<k>` / `CREDITS_<k>_<行号>`），
	#    中文仍是源文 ⇒ zh_CN 下逐字不变、英文走 CSV。
	var sections := [
		{
			"k": "GAME",
			"h": "游戏本体 · GAME",
			"b": [
				"EVE 自走棋（EVE-AutoChess）的游戏架构与全部脚本由 星视寰宇 创作，以 GNU GPL v3 开源。",
				"源码地址：https://github.com/xshynews/EVE-AutoChess",
				"Copyright © 2026 xshynews · 衍生作品须同样以 GPL v3 开源。",
			],
		},
		{
			"k": "ART",
			"h": "EVE 题材与美术素材 · EVE IP & ART",
			"b": [
				"EVE 相关的 IP 与素材（舰船模型、图标、贴图等）著作权归 Fenris Creations 所有"
						+ "（该公司于 2026 年 5 月由 CCP Games 更名而来，CCP 原名 Crowd Control Productions）。",
				"本项目不持有这些素材的任何权利，相关内容不在 GPL v3 覆盖范围内，"
						+ "仅用于学习、开发与体验目的。",
			],
		},
		{
			"k": "MUSIC",
			"h": "背景音乐 · MUSIC",
			"b": [
				"四首 BGM 原曲作者：乌鸦Producer。",
				"本项目使用的版本为适配游戏时长与无缝循环经 AI 重编曲处理，原曲版权仍归原作者所有。",
			],
		},
		{
			"k": "LICENSE",
			"h": "开源许可 · LICENSE",
			"b": [
				"代码：GNU GPL v3（Copyright © 2026 xshynews）。",
				"美术 / 音频素材：归 Fenris Creations 及原作者所有，非本项目许可证覆盖范围。",
			],
		},
	]
	for sec in sections:
		var sec_k := String(sec["k"])
		col.add_child(_label(T.t("CREDITS_H_%s" % sec_k, String(sec["h"])), 13, C_ACCENT))
		col.add_child(_vspace(4))
		var bl: Array = sec["b"]
		for i in bl.size():
			var line := T.t("CREDITS_%s_%d" % [sec_k, i + 1], String(bl[i]))
			var l := _label(line, 12, Color(0.81, 0.89, 0.91, 0.90))
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.custom_minimum_size = Vector2(inner, 0)
			col.add_child(l)
		col.add_child(_vspace(16))

	_content.add_child(_credits_panel)


func _build_modes() -> void:
	var cap := _label(T.t("MENU_MODES_CAP", "游戏模式　MODE"), 9, Color(0.73, 0.83, 0.87, 1.0))
	cap.position = MODES_POS - Vector2(0, 32)
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(cap)

	var col := VBoxContainer.new()
	col.name = "Modes"
	col.position = MODES_POS
	col.add_theme_constant_override("separation", int(MODE_GAP))
	_content.add_child(col)

	for i in _modes.size():
		var m: Dictionary = _modes[i]
		var b := _make_mode_row(m)
		b.pressed.connect(_on_mode_pressed.bind(i))
		col.add_child(b)
		_mode_btns.append(b)


## 某个模式的卡片区布局：「几列 + 卡片多大」。
##
## ⚠️ 由**模式 id** 决定，⛔ 不写在卡片代码里、也不散落成 if ——
##    加一种新布局只改这里一处。
##    任务关卡：3 列 × 470 高（原样，视觉不变）
##    棋牌室：  2 列 × 196 高 ⇒ 2 行 2 列的方框（用户 2026-10-06 定的形态）
func _layout_of(mode_id: String) -> Dictionary:
	if mode_id == CARD_ROOM_MODE_ID:
		return {"cols": 2, "w": GRID_W, "h": GRID_H}
	return {"cols": 3, "w": STRIP_W, "h": STRIP_H}


## 模式项 = 按钮（皮肤抄 EveButtonTheme；两行文字用子 Label，别指望 Button 自带）
func _make_mode_row(m: Dictionary) -> Button:
	var b := Button.new()
	b.name = "Mode_" + String(m["id"])
	b.custom_minimum_size = Vector2(MODE_W, MODE_H)
	b.text = ""
	b.clip_contents = true
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.tooltip_text = _mode_txt(m, "name")

	# 选中态左侧亮条。⚠️ Button 不是 Container，子节点不会被 fit ⇒ 锚点可用。
	var bar := ColorRect.new()
	bar.color = C_ACCENT
	bar.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	bar.offset_right = 3.0
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.visible = false
	b.add_child(bar)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 18.0
	box.offset_top = 12.0
	box.offset_right = -40.0
	box.offset_bottom = -12.0
	box.add_theme_constant_override("separation", 5)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var nm := _label(_mode_txt(m, "name"), 19, C_TEXT)
	var mt := _label(_mode_txt(m, "meta"), 11, C_DIM)
	box.add_child(nm)
	box.add_child(mt)
	b.add_child(box)

	var ch := _label("›", 15, C_ACCENT)
	ch.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	ch.offset_left = -34.0
	ch.offset_right = -15.0
	ch.offset_top = -10.0
	ch.offset_bottom = 10.0
	ch.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ch.visible = false
	b.add_child(ch)

	_mode_names.append(nm)
	_mode_metas.append(mt)
	_mode_bars.append(bar)
	_mode_arrows.append(ch)
	return b


func _build_strips() -> void:
	# ★ 2026-10-06：HBox → Grid。任务关卡仍是「3 列排一行」，视觉与从前一致；
	#   棋牌室用「2 列」⇒ 自然排成 2×2。⛔ 别为棋牌室另开一套控件 ——
	#   同一套卡片，只换列数与尺寸。
	_strip_row = GridContainer.new()
	_strip_row.name = "Strips"
	_strip_row.position = STRIP_POS
	_strip_row.columns = 3
	_strip_row.add_theme_constant_override("h_separation", int(STRIP_GAP))
	_strip_row.add_theme_constant_override("v_separation", int(GRID_GAP_V))
	_content.add_child(_strip_row)


## 一条难度 = 一个竖长条
func _make_strip(card: Dictionary, idx: int) -> void:
	var open := bool(card["open"])
	var p := PanelContainer.new()
	p.name = "Strip_%d" % idx
	p.custom_minimum_size = Vector2(_card_w, _card_h)
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	p.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	p.add_theme_stylebox_override("panel", _strip_style(false, open))
	p.gui_input.connect(_on_strip_input.bind(idx))

	var mn := MarginContainer.new()
	mn.add_theme_constant_override("margin_left", 22)
	mn.add_theme_constant_override("margin_right", 22)
	mn.add_theme_constant_override("margin_top", 26)
	mn.add_theme_constant_override("margin_bottom", 22)
	p.add_child(mn)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mn.add_child(col)

	var nm := _label(_card_txt(card, "name"), 23, C_TEXT_HI if open else Color(0.91, 0.96, 0.97, 0.72))
	col.add_child(nm)
	col.add_child(_vspace(10))
	col.add_child(_label(_card_txt(card, "code"), 9,
			Color(0.55, 0.78, 0.82, 0.55 if open else 0.38)))
	col.add_child(_vspace(18))

	# ⚠️ autowrap 的 Label **必须给死宽**：宽度为 0 时它会按"一个字一行"折行，
	#    量出的最小高度大得离谱（设置窗踩过，见 MEMORY 第 1 章）。
	var desc := _label(_card_txt(card, "desc"), 13,
			Color(0.81, 0.89, 0.91, 0.88) if open else Color(0.71, 0.79, 0.81, 0.62))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(_card_w - 2.0 - 44.0, 0)
	desc.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	col.add_child(desc)
	col.add_child(_vspace(22))
	col.add_child(_make_kv(card["stats"], open))

	var sp := Control.new()
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(sp)

	var sep := ColorRect.new()
	sep.color = C_SEP
	sep.custom_minimum_size = Vector2(0, 1)
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(sep)
	col.add_child(_vspace(20))

	var act := HBoxContainer.new()
	act.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var b := Button.new()
	b.name = "Start"
	# ⚠️ 按钮文案由 open **推导**，不放进难度表 ——
	#    "按钮写什么"是 UI 决策，数据表只描述"这一档开没开"。
	# ⚠️ 中英语序不同（中「▶　开始X」/ 英「▶ Start X」）⇒ 整句做成带 `%s` 的一条，
	#    ⛔ 别把「开始」和名字拼起来 —— 拼出来的英文是 "StartDou Dizhu"。
	b.text = (T.t("MENU_START", "▶　开始%s") % _card_txt(card, "name")) \
			if open else T.t("CARD_TODO", "待开发")
	b.custom_minimum_size = Vector2(0, 44)
	BTN_THEME.apply(b, "hud_main" if open else "hud")
	b.disabled = not open
	FONT.fs(b, 13)
	# ⚠️ 禁用按钮仍然 mouse_filter=STOP，会把点击吃掉 ⇒ 显式让给父面板，
	#    否则「点这条待开发长条也选中它」这个交互会失效。
	b.mouse_filter = Control.MOUSE_FILTER_STOP if open else Control.MOUSE_FILTER_IGNORE
	if open:
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		b.pressed.connect(_on_start_pressed)
	act.add_child(b)
	col.add_child(act)

	# 选中亮条 —— ⚠️ 必须垫一层普通 Control 当覆盖层：
	#    PanelContainer 是 Container，会把**每一个**子节点 fit 成自己的整块矩形，
	#    直接挂 ColorRect 的话锚点全被覆盖（eve_window 的缩放把手踩过这个坑）。
	var ov := Control.new()
	ov.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(ov)
	var bar := ColorRect.new()
	bar.color = C_ACCENT
	bar.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	bar.offset_right = 3.0
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ov.add_child(bar)
	bar.visible = false

	_strip_panels.append(p)
	_strip_bars.append(bar)
	_strip_row.add_child(p)


func _make_kv(stats: Array, open: bool) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for s in stats:
		var row := HBoxContainer.new()
		row.custom_minimum_size = Vector2(0, 24)
		row.add_theme_constant_override("separation", 6)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var k := _label(_stat_txt(String(s[0])), 11, C_DIM)
		k.custom_minimum_size = Vector2(66, 0)
		row.add_child(k)
		var tint := String(s[2]) if s.size() > 2 else ""
		var vcol := C_TEXT
		if tint == "gold":
			vcol = C_GOLD
		elif not open:
			vcol = Color(0.63, 0.71, 0.73, 0.70)
		var v := _label(_stat_txt(String(s[1])), 11, vcol)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.clip_text = true
		row.add_child(v)
		box.add_child(row)
	return box


func _strip_style(on: bool, open: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	if open:
		sb.bg_color = C_STRIP_ON if on else C_STRIP
		sb.border_color = C_ACCENT if on else C_BORDER
	else:
		sb.bg_color = C_STRIP_LOCK_ON if on else C_STRIP_LOCK
		sb.border_color = Color(0.55, 0.78, 0.82, 0.45) if on else C_BORDER_LOCK
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(0)          # 工程铁律：直角
	sb.set_content_margin_all(0)
	return sb


func _label(text: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	FONT.fs(l, size)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _vspace(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


# ------------------------------------------------------------------ 刷新

func _refresh() -> void:
	for i in _modes.size():
		var m: Dictionary = _modes[i]
		_on_sel(_mode_btns[i], _mode_names[i], _mode_metas[i], _mode_bars[i],
				_mode_arrows[i], i == _mode_idx, bool(m.get("locked", false)))

	# 难度条整体重建（数量随模式变）
	for c in _strip_panels:
		c.queue_free()
	_strip_panels.clear()
	_strip_bars.clear()
	for c in _strip_row.get_children():
		c.queue_free()

	# ★ 2026-10-10 版权声明：右侧换成大方框，收掉卡片区。
	if _is_credits():
		_strip_row.visible = false
		if _credits_panel != null:
			_credits_panel.visible = true
		return
	_strip_row.visible = true
	if _credits_panel != null:
		_credits_panel.visible = false

	var cards := _cards_of(_mode_idx)
	# 先按模式定好「列数 + 卡片尺寸」，再让 `_make_strip` 去建 ——
	# 顺序不能反：`_make_strip` 读的就是这两个量。
	var grid := _layout_of(String(_modes[_mode_idx]["id"]))
	_strip_row.columns = int(grid["cols"])
	_card_w = float(grid["w"])
	_card_h = float(grid["h"])
	for i in cards.size():
		_make_strip(cards[i], i)
	var rows := int(ceil(float(cards.size()) / float(_strip_row.columns)))
	_strip_row.size = Vector2(
			_card_w * _strip_row.columns + STRIP_GAP * (_strip_row.columns - 1),
			_card_h * rows + GRID_GAP_V * (rows - 1))
	_refresh_strips()


func _refresh_strips() -> void:
	var cards := _cards_of(_mode_idx)
	var sel := int(_pick[String(_modes[_mode_idx]["id"])])
	for i in _strip_panels.size():
		var open := bool(cards[i]["open"])
		_strip_panels[i].add_theme_stylebox_override("panel", _strip_style(i == sel, open))
		_strip_bars[i].visible = i == sel


func _on_sel(b: Button, nm: Label, mt: Label, bar: ColorRect, ch: Label,
		on: bool, locked: bool) -> void:
	BTN_THEME.apply(b, "hud")
	if on:
		for st in ["normal", "hover", "pressed", "focus"]:
			var sb := b.get_theme_stylebox(st)
			if sb == null:
				continue
			var d: StyleBoxFlat = sb.duplicate()
			d.border_color = C_ACCENT if not locked else Color(0.55, 0.78, 0.82, 0.45)
			d.bg_color = Color(0.11, 0.17, 0.20, 0.92) if not locked \
					else Color(0.078, 0.11, 0.125, 0.85)
			b.add_theme_stylebox_override(st, d)
	bar.visible = on
	ch.visible = on
	nm.add_theme_color_override("font_color",
			C_TEXT_HI if on else (Color(0.55, 0.78, 0.82, 0.34) if locked else C_TEXT))
	mt.add_theme_color_override("font_color",
			Color(0.63, 0.78, 0.82, 0.90) if on else Color(0.44, 0.55, 0.59, 0.55))
	ch.add_theme_color_override("font_color",
			C_ACCENT if not locked else Color(0.55, 0.78, 0.82, 0.45))


# ------------------------------------------------------------------ 交互

func _on_mode_pressed(i: int) -> void:
	if i == _mode_idx:
		return
	_mode_idx = i
	_refresh()


func _on_strip_input(event: InputEvent, idx: int) -> void:
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		var id := String(_modes[_mode_idx]["id"])
		if int(_pick[id]) == idx:
			return
		_pick[id] = idx
		_refresh_strips()


## 「开始」——目前只有守卫边境是开放难度。
## ★ 开场剧情：**只在第一次玩时播**（`user://progress.cfg` 的 `intro_seen`）。
##   第一次 ⇒ 先进 intro_scene（看完/跳过后写盘）再进对局；之后 ⇒ 直接进对局。
##   菜单顶右有「回看片头」可以随时再看 —— 跳过不可以是不可逆的。
## ⚠️ 以后多难度都做好时，这里要按选中的难度把参数带给对局/开场场景
##    （`mode: String` / `tier_id: String`）。现在对局场景还没有这个入参，
##    所以先只做「进去」这一件事，不做假参数。
## ★ 纯函数：返回「开始」该去哪（"" = 不该去，这一档还没开放）。
##   抽出来的理由：验收要能**在不真的切场景**的前提下测「首次 / 非首次」这条分支
##   —— 自检节点本身是 current_scene，真切场景会把它一起销毁。
func target_scene_for_start() -> String:
	# ⚠️ 版权声明没有卡片（`cards` 为空）⇒ 必须先挡掉，否则下面的 `cards[sel]` 越界。
	if _is_credits():
		return ""
	var cards := _cards_of(_mode_idx)
	var sel := int(_pick[String(_modes[_mode_idx]["id"])])
	if not bool(cards[sel]["open"]):
		return ""
	var mode_id := String(_modes[_mode_idx]["id"])
	# ★ 棋牌室（2026-10-06 二次改）：**不再切独立场景**，所以这里返回 ""。
	#   ⚠️ 放在 tier_id 之前判：棋牌室的卡片没有 `id` 字段，
	#      落到下面会被当成「非首次」而错误地进 BATTLE_SCENE。
	#   ⚠️ 返回 "" 会被 `_on_start_pressed` 拦下并**给明确提示**
	#      （⛔ 不许静默 return —— 红线 9）。
	#   ▶ P2 接上牌局后改成：选中斗地主 ⇒ 返回牌局场景；否则 ""。
	if mode_id == CARD_ROOM_MODE_ID:
		# ★ 选中「斗地主」⇒ 进牌局场景；其余三张待开发 ⇒ 返回 ""（不切，
		#   由 `_on_start_pressed` 给明确提示，⛔ 不静默）。
		# ⚠️ 判据用 `code` 而不是下标 —— 卡片顺序将来可能变。
		if String(cards[sel].get("code", "")) == "DOUDIZHU":
			return DOUDIZHU_SCENE
		return ""
	var tier_id := String(cards[sel].get("id", ""))
	var first_time := (mode_id == FIRST_MODE_ID and tier_id == FIRST_TIER_ID
			and not PROGRESS.intro_seen())
	return INTRO_SCENE if first_time else BATTLE_SCENE


## 底部一行临时提示（点「开始」但目标还没做出来时用）。
## ⚠️ 存在的唯一理由是**红线 9**：别摆「看着能点、点了没反应」的东西。
var _toast: Label = null


func _show_toast(text: String) -> void:
	if _toast == null:
		_toast = Label.new()
		_toast.name = "Toast"
		FONT.fs(_toast, 14)
		_toast.add_theme_color_override("font_color", C_GOLD)
		_toast.position = Vector2(STRIP_POS.x, 852)
		_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_content.add_child(_toast)
	_toast.text = text


func _on_start_pressed() -> void:
	var cards := _cards_of(_mode_idx)
	var sel := int(_pick[String(_modes[_mode_idx]["id"])])
	var target := target_scene_for_start()
	if target == "":
		# ⚠️ 不能静默 return：玩家点了「开始」必须知道为什么没动静（红线 9）。
		if String(_modes[_mode_idx]["id"]) == CARD_ROOM_MODE_ID:
			if String(cards[sel]["code"]) == "DOUDIZHU":
				_show_toast(T.t("MENU_TOAST_DDZ",
						"斗地主制作中 —— 规则内核与人机对战开发中，开放后这里直接进牌局"))
			else:
				_show_toast(T.t("MENU_TOAST_MODE_WIP", "「%s」还在开发中")
						% _card_txt(cards[sel], "name"))
		return
	print("[主界面] 开始 %s / %s → %s%s"
			% [_modes[_mode_idx]["name"], cards[sel]["name"], target,
			   "（首次 ⇒ 先播开场）" if target == INTRO_SCENE else "（已看过开场）"])
	# ★ 2026-10-10（审查 2#2）：只有**真实会话**才允许写对局存档
	#   （40 多个 probe/自检会直接加载 battle_scene，不设闸就会覆盖玩家的一局）。
	RUN_STORE.session_active = true
	get_tree().change_scene_to_file(target)


## 「继续上局」：直接恢复上一局的存档（⛔ 不经过开场剧情）。
func _on_continue_run() -> void:
	if not RUN_STORE.has_run():
		_show_toast(T.t("MENU_TOAST_NO_RUN", "没有可继续的对局"))
		return
	print("[主界面] 继续上一局 → %s" % BATTLE_SCENE)
	RUN_STORE.session_active = true
	RUN_STORE.resume_requested = true
	get_tree().change_scene_to_file(BATTLE_SCENE)


## 菜单顶右「回看片头」：不看进度，直接进开场；**不重置** intro_seen
## （它本来就已经是 true；重置反而会让"下次开局又被拦一次"）。
func _on_replay_intro() -> void:
	print("[主界面] 回看片头 → %s" % INTRO_SCENE)
	get_tree().change_scene_to_file(INTRO_SCENE)


func _on_quit() -> void:
	print("[主界面] 退出游戏")
	get_tree().quit()


## 键盘：上下切模式、左右切难度、回车=开始
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	# ★ 2026-10-10 设置窗开着 ⇒ 菜单的键盘导航**让位**（只留 Esc 关窗）：
	#   否则玩家在窗里调设置时，背后的模式/难度还跟着上下左右键乱跳；
	#   而 Esc 原本是「退出游戏」——窗开着时直接退游会吓人，先关窗才对。
	if _settings != null and _settings.visible:
		if event.keycode == KEY_ESCAPE:
			_settings.visible = false
			get_viewport().set_input_as_handled()
		return
	var cards := _cards_of(_mode_idx)
	var id := String(_modes[_mode_idx]["id"])
	match event.keycode:
		KEY_DOWN:
			_on_mode_pressed((_mode_idx + 1) % _modes.size())
		KEY_UP:
			_on_mode_pressed((_mode_idx - 1 + _modes.size()) % _modes.size())
		KEY_RIGHT:
			# ⚠️ 版权声明没有难度可切，且 `cards.size() == 0` ⇒ `% 0` 会报除零。
			if not _is_credits():
				_pick[id] = (_pick[id] + 1) % cards.size()
				_refresh_strips()
		KEY_LEFT:
			if not _is_credits():
				_pick[id] = (_pick[id] - 1 + cards.size()) % cards.size()
				_refresh_strips()
		KEY_ENTER, KEY_KP_ENTER:
			_on_start_pressed()
		KEY_ESCAPE:
			_on_quit()
		_:
			return
	get_viewport().set_input_as_handled()
