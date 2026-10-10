extends Control
## ★ 字号缩放（2026-10-07）：自绘文字的字号也要过它（`FONT.s(设计字号)`）。
const FONT := preload("res://scripts/ui/eve_font.gd")
## 斗地主 · 牌桌（**你打座位 0，两个 AI 打另外两家**）。
##
## ★ 2026-10-06 第二版：从「观战」改成「能自己打」。
##   用户原话：「先做2，我能自己打了才能知道问题在哪，AI 到底有啥问题，
##   现在 3 个 AI 自己打，太快，我都不知道发生了啥」。
##
## ## 这一版解决三件事
## ##   ① **你能操作**：点手牌选牌 / 出牌 / 不要 / 提示 / 叫分 / 托管
## ##   ② **看得懂**：右侧「对局记录」逐条写清谁做了什么；桌面保留每一家出的牌；
## ##      「不要」也画出来（原来过牌什么都不留，玩家分不清「过了」和「还没出」）
## ##   ③ **节奏你控**：AI 只在**你不动的时候**才走一步（每步 0.9 秒），
## ##      轮到你就**一直等** —— 不再有「一眨眼十几手过去」
##
## ## ⛔ 三条不许破的
## ##   ① 按钮的「画」和「点」必须**同一个来源**（都走 `_buttons()`）。
## ##      绘制里另写一套坐标 = 「看着能点、点了没反应」（工程红线 9，踩过）。
## ##   ② 被拒的操作**必须给理由**（`_toast`），⛔ 不许静默 return。
## ##      「点不动」和「点了告诉你为什么不行」对玩家是两件事。
## ##   ③ 牌面**默认全代码画**（`_draw_*`）：零包体增量、风格与工程一致。
## ##      ★ 2026-10-07 起开一个**按牌 id 的贴图白名单**（`CARD_FACES`）：
## ##      AI 生成的整张牌面（舰船立绘 + 派系徽记 + 角标）代码画不出来，
## ##      命中白名单的牌整张画贴图。花色仍 ⛔ 不用 ♠♥♦♣ 字符 —— 某些字体会把它们
## ##      渲染成彩色 emoji（红线 3），代码画的牌花色一律几何形状。

const R := preload("res://scripts/card/ddz/ddz_rules.gd")
const G := preload("res://scripts/card/ddz/ddz_game.gd")
const AI := preload("res://scripts/card/ddz/ddz_ai.gd")
const COIN := preload("res://scripts/card/ddz/ddz_coin.gd")
## 平台 UI 缩放档 —— 牌桌**不缩放**（它的版面是按 1920×1080 排的），
## 但必须把根窗口的缩放**归位**，见 `_ready()`。
const UI_SCALE_SCRIPT := preload("res://scripts/ui/eve_ui_scale.gd")
## ★ 非 16:9 分辨率下的**内容居中偏移**（见 `EveLayout` 顶注）。
const LAYOUT := preload("res://scripts/ui/eve_layout.gd")
## ★ 窗口分辨率档（2026-10-07）。⚠️ 只在桌面端生效。
const RESOLUTION := preload("res://scripts/ui/eve_resolution.gd")
## ★ 设置窗（**与战场共用同一个类**，只是换 `profile`）——
## 2026-10-07 用户：「斗地主页面没有基本的设置，把守卫边境的设置搬过去」。
const SETTINGS_SCRIPT := preload("res://scripts/ui/panels/eve_settings.gd")
## ★ 音频层。牌桌本来没有音频，但设置窗有音量四条 ——
## ⛔ 没有后端就是「拖了没反应」的死旋钮（红线 9）⇒ 起一个只做总线音量 + BGM 的实例。
const AUDIO_SCRIPT := preload("res://scripts/core/eve_audio.gd")
## 设置存档（读音量 / 字号 / 分辨率的初值）
const STORE := preload("res://scripts/core/eve_settings_store.gd")
## ★ 2026-10-10 i18n：文案取词入口（见 eve_text.gd 顶注）。
const T := preload("res://scripts/core/eve_text.gd")

## ★ 牌面贴图白名单（2026-10-07 起；2026-10-08 全量 54 张）。键 = **牌 id**
## （唯一真相源；id 除以 4 的余数：0=黑桃 1=红桃 2=方块 3=梅花；rank=3+id/4
## ⇒ id 0~51 普通牌、52=小王 53=大王）。值 = 整张牌面贴图（自带角标 / 立绘 / 派系名，
## 角标已由 10-08 管线归一放大、圆角已烘 alpha）。
## 生成链：F:\EVE自走棋\牌面\牌面 → tools/pipeline/card_face_pipeline.py
## ⛔ 别按「点数」当键 —— 同一点数有 4 张花色。
const CARD_FACES := {
	0: preload("res://assets/cards/card_0.png"),
	1: preload("res://assets/cards/card_1.png"),
	2: preload("res://assets/cards/card_2.png"),
	3: preload("res://assets/cards/card_3.png"),
	4: preload("res://assets/cards/card_4.png"),
	5: preload("res://assets/cards/card_5.png"),
	6: preload("res://assets/cards/card_6.png"),
	7: preload("res://assets/cards/card_7.png"),
	8: preload("res://assets/cards/card_8.png"),
	9: preload("res://assets/cards/card_9.png"),
	10: preload("res://assets/cards/card_10.png"),
	11: preload("res://assets/cards/card_11.png"),
	12: preload("res://assets/cards/card_12.png"),
	13: preload("res://assets/cards/card_13.png"),
	14: preload("res://assets/cards/card_14.png"),
	15: preload("res://assets/cards/card_15.png"),
	16: preload("res://assets/cards/card_16.png"),
	17: preload("res://assets/cards/card_17.png"),
	18: preload("res://assets/cards/card_18.png"),
	19: preload("res://assets/cards/card_19.png"),
	20: preload("res://assets/cards/card_20.png"),
	21: preload("res://assets/cards/card_21.png"),
	22: preload("res://assets/cards/card_22.png"),
	23: preload("res://assets/cards/card_23.png"),
	24: preload("res://assets/cards/card_24.png"),
	25: preload("res://assets/cards/card_25.png"),
	26: preload("res://assets/cards/card_26.png"),
	27: preload("res://assets/cards/card_27.png"),
	28: preload("res://assets/cards/card_28.png"),
	29: preload("res://assets/cards/card_29.png"),
	30: preload("res://assets/cards/card_30.png"),
	31: preload("res://assets/cards/card_31.png"),
	32: preload("res://assets/cards/card_32.png"),
	33: preload("res://assets/cards/card_33.png"),
	34: preload("res://assets/cards/card_34.png"),
	35: preload("res://assets/cards/card_35.png"),
	36: preload("res://assets/cards/card_36.png"),
	37: preload("res://assets/cards/card_37.png"),
	38: preload("res://assets/cards/card_38.png"),
	39: preload("res://assets/cards/card_39.png"),
	40: preload("res://assets/cards/card_40.png"),
	41: preload("res://assets/cards/card_41.png"),
	42: preload("res://assets/cards/card_42.png"),
	43: preload("res://assets/cards/card_43.png"),
	44: preload("res://assets/cards/card_44.png"),
	45: preload("res://assets/cards/card_45.png"),
	46: preload("res://assets/cards/card_46.png"),
	47: preload("res://assets/cards/card_47.png"),
	48: preload("res://assets/cards/card_48.png"),
	49: preload("res://assets/cards/card_49.png"),
	50: preload("res://assets/cards/card_50.png"),
	51: preload("res://assets/cards/card_51.png"),
	52: preload("res://assets/cards/card_52.png"),
	53: preload("res://assets/cards/card_53.png"),
}

## 牌桌内容的**基准区** = 设计稿坐标系的尺寸。
##
## ⚠️⚠️ 界面上的几何**一律用它**，⛔ 不用 `size`：
##    非 16:9 的分辨率档会让设计空间比基准大（1920×1200 之类），
##    用 `size` 算的话牌桌会被"拉长"、圆心与半径全都不对。
##    正确做法 = 几何锚在基准区 + `_draw` 整体平移居中（见 `_ui_origin`）。
const BASE := Vector2(1920.0, 1080.0)
## ⚠️ 这里**没有** preload  —— 牌桌不显示记牌器了（用户 2026-10-06），
##   所以牌桌侧不再需要它。AI 侧（ddz_ai.gd）照旧用，记牌是 AI 强度的一部分。

const MAIN_MENU := "res://scenes/main_menu.tscn"

## 玩家打的座位。⛔ 只改这里 —— `HUMAN_SEAT` 是唯一真相源，
## 别在别处再写死一个 0（那就会两处不一致，而且不报错）。
const HUMAN_SEAT := 0

## AI 每步之间的间隔（秒）。原来 0.55 秒一手，用户反馈「太快，看不清」⇒ 放慢。
const STEP_SECONDS := 0.9
## 提示条显示多久
const TOAST_SECONDS := 2.6

## 尺寸。★ 手牌 52×74 → **76×108**：资料结论「手牌尺寸调大 ⇒ 沉浸感更强」。
const HAND_CARD_W := 76.0
const HAND_CARD_H := 108.0
const HAND_OVERLAP := 46.0      ## 手牌叠放间距（< 牌宽就是叠着）
const PLAY_CARD_W := 60.0       ## 出牌区的牌小一号（桌面上的牌不该跟手牌抢大小）
const PLAY_CARD_H := 84.0
const PLAY_OVERLAP := 34.0
const PLAY_ROW_MAX := 470.0     ## 出牌行的最大宽度（超出就自动收紧叠放）
## ★★ 2026-10-06 **圆桌制**（用户定）：四方位 = **下(你) · 左(上家) · 右(下家) · 上(底牌)**。
##   ⚠️ 上下家是**出牌顺序**派生的：座位 1 在你**之后**出牌 ⇒ **下家**；
##      座位 2 在你**之前**出牌 ⇒ **上家**。
##   ⚠️⚠️ 2026-10-07 **又对调了一次**（用户：「有玩家反馈说是上下家是逆时针的」）：
##      斗地主是**逆时针**轮转 ⇒ 你（下）出完轮到**右边**那家 ⇒ **下家在右、上家在左**。
##      （10-06 那版是「下家在左」，方向反了；`SEAT_DIR` 是唯一改点。）
const TABLE_CX := 0.500         ## 圆心 x（屏宽比例）
## ⚠️ 圆心 y 是**出图调的**：0.395 时整体偏上、下半屏空 → 用户 2026-10-07
##   「总体布局有点太靠上了，下部分留空太多」⇒ 下移到 0.435（同时纵半径 0.258→0.248
##   给下方的玩家块腾位置，否则「你」的出牌区会压到它）。
const TABLE_CY := 0.435         ## 圆心 y（屏高比例）
const TABLE_RX := 0.318         ## 横半径（屏宽比例）
const TABLE_RY := 0.248         ## 纵半径（屏高比例）
const DIR_DOWN := 0
const DIR_LEFT := 1
const DIR_RIGHT := 2
const DIR_UP := 3
## 座位 → 方位。⛔ 这是**语义**（谁在你上/下家），不是画面坐标，别按视觉写死。
## ⚠️ 2026-10-07 对调（逆时针轮转）：下家（座位 1）在**右**、上家（座位 2）在**左**。
const SEAT_DIR := [DIR_DOWN, DIR_RIGHT, DIR_LEFT]
const PLAY_OUT := 0.62          ## 出牌/亮牌离圆心的距离（比例）
const NEW_HL_SEC := 3.2         ## 「新到的底牌」抬起高亮的时长（秒）
const NEW_LIFT := 16.0          ## 新底牌额外的抬起量
const COIN_UNIT := 10           ## 娱乐币单位：1 倍 = 10 娱乐币
const FLOAT_SEC := 2.8          ## 结算飘字的时长（秒）

## ★ 2026-10-07 发牌流程（用户：「进游戏之后不能直接开始，还需要点击一下开始游戏」
##   + 「要有个发牌的动画，让手牌一张一张的出现」）。
##   形态照欢乐斗地主录像 8~14s：**牌从桌面中央一张张飞向落位**，手牌从左往右长出来。
##   ⚠️ 时长是**从录像量化出来的**（逐帧统计手牌区亮像素的增量）⇒ 正片约 3.0s 发完 17 张。
const DEAL_SEC := 2.8            ## 发牌动画总时长（17 张 ⇒ 每张 ≈0.165s，与录像同档）
const DEAL_FACE := 17            ## 每人张数。⚠️ 写死是**故意的**：这是斗地主规则，不是可配参数
const DEAL_BOTTOM_LEAD := 0.30   ## 底牌提前这么久出现（最后 3 张一并落到顶部）
## ★ 2026-10-06 加头像位：236×92 → 264×104。
##   依据（欢乐斗地主实机截图）：每个座位是「一张人物立绘 + 名牌 + 金币」，
##   有"人"的存在感 —— 我们原来只有一块空面板。
const SEAT_W := 264.0           ## 座位面板（资料：面板必须紧凑，不超屏 1/4）
const SEAT_H := 104.0
const AVATAR := 60.0            ## 头像边长（★ 预留位，见 `set_avatar()`）
const AVATAR_R := 10.0          ## 头像圆角
const LIFT := 22.0              ## 选中的手牌上移
const HOVER_LIFT := 9.0         ## 悬停上移（即时反馈）
const HAND_BOTTOM_GAP := 152.0  ## 手牌底边离屏底（下面留给「已选」行 + 操作栏 + 提示条）

const C_BG := Color(0.043, 0.059, 0.072)
# ⚠️ 原来的实心桌面填充（以及它的桌沿色）**已删除** —— 用户 2026-10-07：
#   「删除掉中间的色块，只保留一圈一圈的细线」。⛔ 别再把它加回来。
const C_RING := Color(0.45, 0.72, 0.76, 0.34)  ## 距离环（⚠️ 出图调的：0.20 太淡，压在亮星云上会糊）
const RING_N := 5                               ## 等差环数
const RING_KM := 20                             ## 每圈多少 km（等差数列，纯 EVE 风味）
## ★ 半透明桌面填充（用户 2026-10-07：「把中间填色改成半透明的，透明度 50%」）。
##   50% ⇒ 星空与星云**透过来**，桌面像一块玻璃板：仍能"落桌"，但不盖掉背景。
##   ⚠️ 透明度是**用户指定的 50%**，⛔ 别自己改（要改先问）。
const C_TABLE_FILL := Color(0.10, 0.14, 0.17, 0.50)
const C_TRAY := Color(0.055, 0.075, 0.090)     ## 出牌托盘（比桌面还暗 ⇒ 牌浮起来）
const C_TRAY_EDGE := Color(0.15, 0.24, 0.28)
const C_BAR := Color(0.055, 0.075, 0.090)      ## 顶部记分条
const C_PANEL := Color(0.075, 0.102, 0.122)
const C_PANEL_EDGE := Color(0.20, 0.36, 0.40)
const C_TEXT := Color(0.70, 0.82, 0.85)
const C_DIM := Color(0.44, 0.55, 0.59)
const C_FAINT := Color(0.30, 0.38, 0.42)
const C_HI := Color(0.91, 0.96, 0.97)
const C_GOLD := Color(0.91, 0.76, 0.35)
const C_ACCENT := Color(0.55, 0.78, 0.82)
const C_PRIMARY := Color(0.55, 0.78, 0.82)     ## 主按钮填充（出牌）
const C_CARD := Color(0.93, 0.94, 0.91)
const C_CARD_EDGE := Color(0.66, 0.70, 0.70)
const C_RED := Color(0.78, 0.20, 0.20)
const C_BLACK := Color(0.12, 0.13, 0.15)
const C_BACK := Color(0.14, 0.22, 0.28)
const C_BACK_EDGE := Color(0.30, 0.46, 0.52)
const C_BTN := Color(0.13, 0.20, 0.24)         ## 次按钮底
const C_BTN_HOT := Color(0.20, 0.32, 0.37)     ## 次按钮 hover
const C_BTN_OFF := Color(0.10, 0.13, 0.15)     ## 禁用底
const C_WARN := Color(0.90, 0.45, 0.38)        ## 提示条 / 非法牌型

# ══════════════════════════════════════════════════════════════════
#  ★★ 棋牌室礼装 —— **整块可替换**（为「军团礼装」留的槽）
# ══════════════════════════════════════════════════════════════════
#
# 为什么单独圈一块：这不是"随手美化"。用户视频原话 ——
#   「进一步就想到以后可以加强和军团的合作，做点军团独有的外观出来，
#     比如主界面、舰船皮肤、**棋盘**等等。军团礼装这套系统还是值得好好研究研究的」
# ⇒ 棋牌室的装饰 = **军团礼装的第一批落地点**。
#   所以这里把「背景贴图 + 舱壁/桌面配色 + 装饰语言」全集中在这一段：
#   将来做军团礼装 = **换这一段**，⛔ 不动绘制函数。
#
# 概念：**棋牌室 = 舰长室**。也不是我编的 —— 最初观众的原话就是
#   「我们只是想要**舰长室**，小游戏来个斗地主 麻将」。
# ⇒ 窗外是太空（舷窗），用的是**主菜单同一张背景** ⇒ 从主菜单走进来，
#   窗外是同一片天，空间上是连贯的。
#
# ⛔ 风格纪律（用户视频原话）：「既得是 EVE 又是自走棋才对」「总体上不是那种
#   繁复绚丽的」⇒ 全部低对比、细线、青灰金属感；⛔ 不引入照片级新素材
#   （零包体增量，且这两张图本来就在包里）。
## ★ 背景素材（2026-10-06 做了 5 张对照表 `_shots/bg_candidates.png` 之后定的）：
##   `caldari-c02-nebula` = 深蓝底 + 一团远红外核，均值亮度 33/255 ⇒ 最像「深空」。
##   ⛔ 别换 c07-nebula(117) / c07-menu(126) —— 太亮，压暗后就是一片灰雾；
##      amarr(62) 偏暖金、gallente(31) 发绿糊 —— 五张都试过。
##   ⚠️ 该纹理 **4096×2048 且没开 mipmap** ⇒ ⛔ 绝不能整图缩放（会出锯齿）。
##      做法：只取 **w×h 的 1:1 一块**，零缩放。
const BG_SPACE := preload("res://assets/backgrounds/caldari-c02-nebula-4096.png")
const BG_STARS := preload("res://assets/backgrounds/stars_layer_1920x1080.png")
## ★ 取样原点（已挑过）：把星云那团亮核推到**右下角**（牌桌之外的可见区），
##   让「远处有团发光星云」成为背景的一部分 —— 而不是正好被牌桌盖掉。
##   ⚠️ 改这里等于换构图，改完**必须出图看一眼**。
const BG_SPACE_OFFSET := Vector2(700.0, 200.0)

const C_HULL := Color(0.026, 0.036, 0.047)      ## 舱壁（只在四周结构带上露出来）
const C_HULL_SEAM := Color(0.10, 0.15, 0.18)    ## 舱壁横向接缝
const C_FRAME := Color(0.24, 0.41, 0.46)        ## 结构线 / 窗框（EVE 青灰）
const C_GLASS := Color(0.40, 0.66, 0.72)        ## 玻璃反光 / 固定件
const C_SPACE_DIM := Color(0.009, 0.016, 0.028, 0.68)  ## 深空压暗（⛔ 不压暗就是一片灰雾；0.62 是出图调出来的）
const C_GRID := Color(0.22, 0.40, 0.44, 0.13)   ## 桌面细网格

var game = null
var _seed := 0
var _timer := 0.0
var _shown: Array = [{}, {}, {}]      ## 每家最近出的牌（牌 id 数组；{} = 没出）
var _passed := [false, false, false]  ## 这家最近是不是「不要」
var _status := ""
var _feed: Array[String] = []         ## 对局记录（人读的，越往下越新）
var _sel: Array[int] = []             ## 玩家已选中的牌 id
var _hint_i := -1                     ## 「提示」的循环游标
var _auto := false                    ## 托管：把你的座位也交给 AI
var _toast := ""
var _toast_t := 0.0
var _t := 0.0                                 ## 累计时间（回合脉冲动画用）
var _drag_sel := false                        ## 左键按住「划过即选 / 划过即取」进行中
var _drag_mode := 1                           ## 本次拖选方向：1=选上 / -1=取下（按下第一张牌时定下）
var _drag_p := Vector2.ZERO                   ## 拖选的上一个采样点（沿路径补采样用）
var _hover_i := -1                            ## 鼠标悬停的手牌下标（-1 = 没有）
## ★ 头像贴图（每座一张）。`null` ⇒ 画几何占位剪影；有贴图 ⇒ 直接画立绘。
##   接口 `set_avatar()` —— 以后拿到素材一行接上，⛔ 不用改任何布局代码。
var _avatars: Array = [null, null, null]
## 各家的叫分记录（资料惯例：行动文本**持久留在出牌区**，不自动消失）
var _bid_text: Array[String] = ["", "", ""]
## ★ 结算飘字：[{ "seat": int, "text": String, "col": Color, "t": float }]
var _floaters: Array = []
var _settled := false           ## ⚠️ 结算**只算一次**的闸（`_process` 每帧都跑）
var _my_delta := 0              ## 本局玩家的娱乐币增减
var _new_ids: Array = []        ## 刚加入手牌的底牌（抬起高亮用）
var _new_t := 0.0

## ★ 2026-10-07：进牌桌**不自动开局**。`_started == false` 就是「空桌」态。
var _started := false
## 发牌动画进行中。此期间：**不出叫分按钮、AI 一步都不许走、手牌逐张出现**。
## ⚠️ 它是**表现层**的闸，不是规则层的 —— `game` 里的牌早就 17 张齐了（见 `_start_game`）。
var _dealing := false
var _deal_t := 0.0               ## 发牌动画已进行的秒数
## ★ 2026-10-07 音频层（主要为设置窗的音量滑杆提供后端 + 一条 BGM）
## ⚠️ 声明成 **Variant** 而不是 `Node`：类型化的 `Node` 上写 `.volumes()` 会
##    **解析失败**（基类没有这个成员），而它其实是个 `EveAudio`（本工程踩过）。
var _audio: Variant = null
## ★ 2026-10-07 设置窗（`eve_settings.gd` 的 `PROFILE_LOUNGE` 档案）。
## ⚠️ 同样用 Variant：要调 `set_state()` / `set_window_rect()` 这些
##    `Control` 基类没有的成员。
var _settings: Variant = null


func _ready() -> void:
	# ★ 2026-10-10 i18n：**必须早于任何 UI 构建** —— 文案是建的时候取词的。
	T.apply_saved()
	# ★ 2026-10-09：牌面贴图 512×717 要画到 76×108（约 6.7 倍缩小），
	#   贴图无 mipmap + 节点默认 LINEAR 过滤 ⇒ 缩小采样必然出锯齿。
	#   这里开 mipmap 过滤，配合 assets/cards/card_*.png.import 的
	#   mipmaps/generate=true 才能让缩小后的角标与圆角平滑。
	#   注意：没有 mipmap 的贴图（如背景星云）Godot 会自动退回 LINEAR，无副作用。
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	# ★ 牌桌恒定 1.0 缩放：`content_scale_factor` 是根窗口属性，
	#   从战场退出来还留着放大值 ⇒ 牌桌版面会散（见 EveUiScale 的说明）。
	UI_SCALE_SCRIPT.apply_scene_default(get_window())
	# ★ 分辨率：读盘并应用（桌面端才有；无头/移动端内部返回）。
	#   ⚠️ 在量 `_ui_origin()` 之前 —— 窗口尺寸变了，居中偏移才算得对。
	RESOLUTION.apply_from_settings(get_window())
	# ★ 字号缩放：牌面与记录都是自绘（`FONT.s` 现读），但 UI 控件要建立时定
	FONT.load_from_settings()
	COIN.load_it()          ## 娱乐币（方案 A：纯记分；字段已按 B/C 留好）
	_build_audio()
	_build_settings()
	# ★ 2026-10-07：进牌桌**不自动开局**（用户：「不能直接开始，还需要点击一下开始游戏」）。
	#   ⇒ 这里只清状态、**不建局**：`game == null` 就是「还没开始」的唯一判据。
	_reset_state()
	_refresh_status()


## 音频层（**只为设置窗的四条音量 + 一条 BGM 存在**）。
##
## ⚠️ 总线音量是**全局**的（写在 AudioServer 上），所以这里设的值
##    下次进战场照样生效 —— 这正是「通用设置」该有的语义。
## ⚠️ 只调 `set_volume/set_muted/play_music`，⛔ 不碰任何 `play_*` 音效
##    （牌桌没有打击反馈，乱播只会出怪声）。
func _build_audio() -> void:
	_audio = AUDIO_SCRIPT.new()
	_audio.name = "LoungeAudio"
	add_child(_audio)
	# ⚠️ 必须显式标注 `: Dictionary` —— `_audio` 是 Variant，`volumes()` 的返回值
	#    也推不出类型，用 `:=` 会直接**解析失败**。
	# ⚠️ 音量必须读**存档**（`settings.cfg`），⛔ 不能读 `_audio.volumes()` ——
	#    后者是「刚 new 出来的实例的出厂默认值」，写进总线等于把玩家在战场 /
	#    设置窗里调好的音量**重置回默认**（总线音量是全局的，见 EveAudio._set_bus_vol）。
	#    表现是「在战场把音乐调到 80%，一进牌桌又变回 32%」且**不报错**（2026-10-10 修）。
	var s: Dictionary = STORE.load_all()
	_audio.set_volume(&"master", float(s.get("master", 1.0)))
	_audio.set_volume(&"sfx", float(s.get("sfx", 0.60)))
	_audio.set_volume(&"amb", float(s.get("amb", 0.39)))
	_audio.set_volume(&"music", float(s.get("music", 0.32)))
	_audio.set_muted(bool(s.get("muted", false)))
	# ★ 2026-10-10：牌桌 BGM 换成 Lantern（逻辑名 "ddz"，`ddz_01.ogg`，71.5s 无缝循环）。
	#    它同时让设置窗的音乐滑杆**听得出效果**（⛔ 否则就是一排死旋钮）。
	_audio.play_music("ddz")


## 设置窗（**与战场共用同一个类**，只是换 `profile`）。
##
## ⚠️ `profile = PROFILE_LOUNGE` 必须在 `add_child` **之前**设 ——
##    `_ready` 里就按它决定建哪些分区（见 `EveSettingsWindow` 顶注）。
## ⚠️ `layout_key` 换成 `lounge_settings`：⛔ 别与战场那扇共用存档位，
##    两边尺寸差很多，共用一个键会让窗一进来就落在别人的坐标上。
func _build_settings() -> void:
	_settings = SETTINGS_SCRIPT.new()
	_settings.name = "LoungeSettings"
	_settings.profile = SETTINGS_SCRIPT.PROFILE_LOUNGE
	_settings.layout_key = "lounge_settings"
	add_child(_settings)
	_settings.visible = false
	_settings.volume_changed.connect(func(kind: StringName, v: float):
		if _audio != null:
			_audio.set_volume(kind, v))
	_settings.mute_toggled.connect(func(on: bool):
		if _audio != null:
			_audio.set_muted(on))
	_settings.back_to_menu_requested.connect(func():
		get_tree().change_scene_to_file(MAIN_MENU))
	_settings.resolution_changed.connect(func(_i: int):
		_place_settings()
		queue_redraw())
	# ★ 2026-10-10：标题栏右上角的 ✕ ⇒ 关掉本窗（与 `_toggle_settings()` 的隐藏口径一致）。
	_settings.closed.connect(func() -> void: _settings.visible = false)
	_place_settings()


## 把设置窗摆到**基准区**居中偏上的位置。
##
## ⚠️ 必须加 `_ui_origin()`：设置窗是**子节点**，不受 `_draw` 的
##    `draw_set_transform` 影响 ⇒ 非 16:9 分辨率下要自己补偏移。
## ⚠️ 高度**不由这里定**：`EveSettingsWindow._fit_height()` 会按内容反推并
##    `set_window_height()` 接管（本函数只给一个初值）。
func _place_settings() -> void:
	if _settings == null:
		return
	var o := _ui_origin()
	var bw := 320.0
	_settings.set_window_rect(o.x + (BASE.x - bw) * 0.5, o.y + 70.0, bw, 480.0)


## 把一局的**表现状态**清回初始（⛔ 不碰牌局数据）。
##
## ★ 2026-10-07 从 `_new_game()` 里拆出来，因为「还没开始」这个态需要它 ——
##   进牌桌时只清状态、不建局。
func _reset_state() -> void:
	_shown = [{}, {}, {}]
	_passed = [false, false, false]
	_sel = []
	_hint_i = -1
	_toast = ""
	_toast_t = 0.0
	_bid_text = ["", "", ""]
	_hover_i = -1
	_floaters = []
	_settled = false
	_my_delta = 0
	_new_ids = []
	_new_t = 0.0
	_feed = []
	_timer = STEP_SECONDS


## 开一局。`seed_value < 0` ⇒ 用当前时间（正常玩）；
## 验收传固定 seed ⇒ 牌局可复现（查 bug 时也方便「照着一模一样的牌重放」）。
##
## `animate_deal`：是否播发牌动画。**默认 false** ⇒ 一建局手牌就是全的。
## ⚠️ 默认值故意是 false：验收脚本直接调 `_new_game(seed)` 拿到的必须是**立刻可打**的局面，
##    ⛔ 不能被发牌动画挡住（那会让每次自检都变成「要等 2.8 秒」）。
func _new_game(seed_value: int = -1, animate_deal := false) -> void:
	_seed = (int(Time.get_unix_time_from_system()) & 0xFFFF) if seed_value < 0 else seed_value
	game = G.new()
	game.start(_seed)
	_reset_state()
	# 建了局 ⇒ 就是「已开始」（验收直接调本函数时，行为与从前完全一致）
	_started = true
	_dealing = animate_deal
	_deal_t = 0.0
	_push(T.t("DDZ_LOG_NEW_GAME", "—— 新一局（seed %d）——") % _seed)
	_refresh_status()
	queue_redraw()


## 「开始游戏」：真正发牌 —— **数据层立刻发完，随后播发牌动画**。
##
## ⚠️⚠️ 顺序不能反：先把牌发好（数据层），再播动画。
##    ⛔ 绝不「边发边往手里塞牌」—— 规则层与 AI 读到半副牌会出各种怪事；
##    更要命的是将来走 P2P 时，两台机器的动画长度不可能完全一致 ⇒ 状态直接分叉。
##    ⇒ 发牌动画**只影响「画」**：由 `_deal_progress()` 决定「画到第几张」。
func _start_game(seed_value: int = -1) -> void:
	_new_game(seed_value, true)


# ══════════════════════════════════════════════════════════════════
#  驱动：只有「轮到 AI」时才自动走
# ══════════════════════════════════════════════════════════════════

func _process(delta: float) -> void:
	_t += delta
	# ★ 每帧重画：回合脉冲、悬停高亮、结算飘字都是动的。这个场景只有几十个图元，
	#   ⛔ 不值得为它做脏标记（那才是过度设计）。
	queue_redraw()
	if _toast_t > 0.0:
		_toast_t -= delta
		if _toast_t <= 0.0:
			_toast = ""
	# 结算飘字推进（⛔ 不受"轮到玩家就停"影响 —— 那时局已经结束了）
	if not _floaters.is_empty():
		var live: Array = []
		for f in _floaters:
			f["t"] = float(f["t"]) + delta
			if float(f["t"]) < FLOAT_SEC:
				live.append(f)
		_floaters = live
	if _new_t > 0.0:
		_new_t = maxf(0.0, _new_t - delta)
	# ★ 还没点「开始游戏」⇒ 空桌等着：不建局、不发牌、不摆任何操作按钮。
	if not _started or game == null:
		return
	# ★ 设置窗开着 ⇒ **一步都不推**（玩家在调设置，牌局不该在背后自己跑）。
	#   ⚠️ 与「轮到玩家就一直等」同一条思路：节奏由玩家控。
	if _settings != null and _settings.visible:
		return
	# ★★ 发牌动画进行中 ⇒ **一步都不许走**（包含 AI）。
	#    否则 AI 会在你还在看发牌的时候就把地主叫完了 —— 发牌与叫分叠在一起，很乱。
	if _dealing:
		_deal_t += delta
		if _deal_t >= DEAL_SEC:
			_dealing = false
			_deal_t = 0.0
			_refresh_status()
		return
	if game.is_over():
		# ⚠️ **只结算一次**：`_process` 每帧都跑，重复结算 = 重复加钱
		if not _settled:
			_settle()
		return
	if _is_human_turn():
		# ★★ 轮到玩家就**一直等**，不推进任何计时器 ——
		#    这是「不再一眨眼十几手过去」的关键。
		return
	_timer -= delta
	if _timer <= 0.0:
		_timer = STEP_SECONDS
		_ai_step()
		queue_redraw()


## 一局结束：算账 → 记娱乐币 → 起飘字。**只跑一次**（见 `_settled`）。
##
## ★ 公式（参考图口径）：**结算 = 底分 × 倍数 × 单位**。
##   地主赢 ⇒ 地主 +2×stake、每个农民 −stake（反过来同理）——
##   这样"地主 1 打 2"的赔率才是对的。
##
## ⚠️ 用户拍板的方案 A：**纯记分**，不设底金、不惩罚 ⇒ 余额可以为负。
##   但 B/C 要用的字段（累计下注、破产次数）已按设计留在 `ddz_coin.gd`。
## ⚠️ 只给**真人玩家**记账；两个 AI 是陪打，不落盘（它们也没有"账户"）。
func _settle() -> void:
	_settled = true
	var stake: int = maxi(1, int(game.base_score)) * int(game.multiplier()) * COIN_UNIT
	var ll: int = int(game.landlord)
	var ll_won: bool = game.landlord_won()
	for seat in 3:
		var gain: int
		if seat == ll:
			gain = (2 * stake) if ll_won else (-2 * stake)
		else:
			gain = (-stake) if ll_won else stake
		_floaters.append({"seat": seat, "text": "%+d" % gain,
				"col": C_GOLD if gain > 0 else C_WARN, "t": 0.0})
		if seat == HUMAN_SEAT:
			_my_delta = gain
			COIN.record(gain, _human_won())


func _is_human_turn() -> bool:
	# ⚠️ `_dealing` 也算「不轮到你」⇒ 叫分/出牌按钮与手牌点击在发牌期间自然全部失效。
	#    这比在每个按钮上单独加判断可靠（少一处漏判就少一个 bug）。
	if game == null or game.is_over() or _auto or _dealing:
		return false
	return int(game.turn) == HUMAN_SEAT


## 让「当前该动的那家 AI」走一步。
func _ai_step() -> void:
	var seat: int = int(game.turn)
	if int(game.phase) == int(G.Phase.BID):
		_do_bid(seat, AI.bid_score(game, seat))
		return
	var mv: Dictionary = AI.choose(game, seat)
	if mv.has("cards"):
		if not _do_play(seat, mv["cards"]):
			# AI 给了一手出不掉的牌 ⇒ 退而过；再失败就把话说明白，
			# ⛔ 不许静默空转（否则牌局会当场卡死，且没有任何线索）。
			if not _do_pass(seat):
				_status = T.t("DDZ_ERR_AI_PLAY",
						"⚠ AI 出牌失败（座位 %d）—— 见右侧记录") % seat
	else:
		if not _do_pass(seat):
			_status = T.t("DDZ_ERR_AI_PASS",
					"⚠ AI 过牌失败（座位 %d）—— 见右侧记录") % seat


## ── 三个动作（玩家与 AI **共用**，所以记录与状态只有一份口径）──

func _do_bid(seat: int, score: int) -> bool:
	var res: Dictionary = game.bid(seat, score)
	if not bool(res.get("ok", false)):
		_reject(String(res.get("reason", "")))
		return false
	var what := (T.t("DDZ_BID_PASS", "不叫") if score <= 0
			else (T.t("DDZ_BID_N", "叫 %d 分") % score))
	_push("%s %s" % [_seat_name(seat), what])
	_bid_text[seat] = what
	if int(game.phase) == int(G.Phase.PLAY):
		_shown = [{}, {}, {}]
		_passed = [false, false, false]
		# ★ 用户 2026-10-06：「叫分数那个…需要在需要叫地主的时候显示就可以，
		#   平时不需要显示的」⇒ 一进 PLAY 就把**所有叫分文本**清掉，
		#   桌面上只留出牌动作（不要 / 出牌）。
		_bid_text = ["", "", ""]
		_push(T.t("DDZ_LOG_LANDLORD", "★ 地主 = %s · 底牌 %s") % [_seat_name(int(game.landlord)),
				_cards_text(game.bottom)])
		# ★ 新到的底牌抬起高亮一会儿（用户：「新底牌抬起提示」）
		if int(game.landlord) == HUMAN_SEAT:
			_new_ids = (game.bottom as Array).duplicate()
			_new_t = NEW_HL_SEC
	_timer = STEP_SECONDS
	_refresh_status()
	return true


func _do_play(seat: int, cards: Array) -> bool:
	var res: Dictionary = game.play(seat, cards)
	if not bool(res.get("ok", false)):
		_reject(String(res.get("reason", "")))
		return false
	_shown[seat] = (cards as Array).duplicate()
	_passed[seat] = false
	_bid_text[seat] = ""        # 资料惯例：出牌阶段首次落牌 ⇒ 清掉叫分遗留文本
	_push(T.t("DDZ_LOG_PLAY", "%s 出 %s（%s）") % [_seat_name(seat),
			_cards_text(cards),
			R.type_name(int(R.classify(cards).get("type", 0)))])
	_sel = []
	_hint_i = -1
	if game.is_over():
		_push(T.t("DDZ_LOG_WIN", "★ %s 胜 —— %s") % [
				(T.t("DDZ_ROLE_LANDLORD", "地主") if game.landlord_won()
						else T.t("DDZ_ROLE_FARMER", "农民")),
				(T.t("DDZ_WIN", "你赢了") if _human_won()
						else T.t("DDZ_LOSE", "你输了"))])
	_timer = STEP_SECONDS
	_refresh_status()
	return true


func _do_pass(seat: int) -> bool:
	var res: Dictionary = game.pass_turn(seat)
	if not bool(res.get("ok", false)):
		_reject(String(res.get("reason", "")))
		return false
	_shown[seat] = {}
	_passed[seat] = true
	_push(T.t("DDZ_LOG_PASS", "%s 不要") % _seat_name(seat))
	if game.last_play.is_empty():
		# 其余两家都过 ⇒ 新的一轮。桌面必须清空，否则上一轮的牌会一直挂着，
		# 玩家会以为「这手还没结束」。
		for s in 3:
			_shown[s] = {}
			_passed[s] = false
		_push(T.t("DDZ_LOG_NEW_ROUND", "—— 新一轮，%s 先出") % _seat_name(int(game.turn)))
	_sel = []
	_hint_i = -1
	_timer = STEP_SECONDS
	_refresh_status()
	return true


func _refresh_status() -> void:
	if game == null:
		# ★「还没开始」也要有话说 —— 空桌 + 一句话告诉玩家该干什么（⛔ 别留一片死寂）
		_status = T.t("DDZ_STATUS_IDLE",
				"点「开始游戏」发牌 —— 一副牌，三个人，你打一家")
		return
	if _dealing:
		_status = T.t("DDZ_STATUS_DEALING", "发牌中…")
		return
	if game.is_over():
		_status = T.t("DDZ_STATUS_OVER", "%s 胜 · %s") % [
				(T.t("DDZ_ROLE_LANDLORD", "地主") if game.landlord_won()
						else T.t("DDZ_ROLE_FARMER", "农民")),
				(T.t("DDZ_WIN", "你赢了") if _human_won()
						else T.t("DDZ_LOSE", "你输了"))]
		return
	if int(game.phase) == int(G.Phase.BID):
		# ⚠️ 整句带 %s（⛔ 别用「前缀 + 后半句」拼接 —— 英文语序不一样，拼出来是病句）
		_status = T.t("DDZ_STATUS_BIDDING", "叫分中 —— %s") % (
					T.t("DDZ_STATUS_BID_YOU", "轮到你了（不叫 / 1~3 分）")
					if _is_human_turn()
					else T.t("DDZ_STATUS_THINKING", "%s 思考中…") % _seat_name(int(game.turn)))
		return
	var seat: int = int(game.turn)
	var n: int = (game.hand_of(seat) as Array).size()
	if seat == HUMAN_SEAT and not _auto:
		if game.last_play.is_empty() or int(game.last_play["seat"]) == HUMAN_SEAT:
			_status = T.t("DDZ_STATUS_LEAD", "轮到你了 —— 新一轮，你随意出")
		else:
			_status = T.t("DDZ_STATUS_FOLLOW", "轮到你了 —— 要压过 %s 的 %s") % [
					_seat_name(int(game.last_play["seat"])),
					_cards_text(game.last_play["cards"])]
	else:
		_status = T.t("DDZ_STATUS_THINKING_N", "%s 思考中…（还剩 %d 张）") % [_seat_name(seat), n]


# ══════════════════════════════════════════════════════════════════
#  玩家输入
# ══════════════════════════════════════════════════════════════════

func _gui_input(event: InputEvent) -> void:
	# ★ 非 16:9 分辨率下内容整体平移过（见 _ui_origin）⇒ 输入要先**减掉偏移**，
	#   否则就是「看到的牌在那里、点的却是别处」。绘制与输入**用同一个偏移**
	#   就是本工程「画与点同源」那条红线在这里的落点。
	var o := _ui_origin()
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				var p := mb.position - o
				_drag_p = p
				# ★ 按住左键 = 进入「划过即选 / 划过即取」（快速多选 / 快速取消）。
				#   ⚠️ 落在顶栏按钮上时不进入拖选 —— 否则拖一下按钮会把下面的牌划选一片。
				_drag_sel = _hit_button(p) == "" and _can_pick()
				# ★ 状态检测：按下的第一张牌**当前是不是已选中**，决定这一划的方向 ——
				#   压未选中的牌 ⇒ 一路选上；压已选中的牌 ⇒ 一路取下。
				#   ⚠️ 必须在 `_on_click` 之前判：它会把落点这张 toggle 掉，判晚了拿到的
				#     就是翻转后的状态，方向刚好反掉。
				_drag_mode = 1
				if _drag_sel:
					var hid := _hand_id_at_base(p)
					if hid >= 0 and _sel.has(hid):
						_drag_mode = -1
				_on_click(p)
			else:
				_drag_sel = false
			accept_event()
		elif not mb.pressed:
			return
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			# 右键清空选择 —— 选错了不用一个个点回去
			if not _sel.is_empty():
				_sel = []
				_hint_i = -1
				queue_redraw()
			accept_event()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		var p := mm.position - o
		# 悬停高亮 = 即时反馈（资料：每个操作都要有立刻的视觉回应）
		var mi := _hand_hover_index(p)
		if mi != _hover_i:
			_hover_i = mi
			queue_redraw()
		# ★ 按住左键划过手牌 ⇒ 沿途按同一方向选上 / 取下（见 _drag_paint）。
		#   ⚠️ 用 button_mask 判「左键还按着」，而不是只认按下/抬起事件：
		#     在控件外松开左键收不到 release，只靠事件会把拖选状态卡死，
		#     之后不按键也会一直选牌。
		if mm.button_mask & MOUSE_BUTTON_MASK_LEFT:
			if _drag_sel:
				_drag_paint(_drag_p, p)
				_drag_p = p
		elif _drag_sel:
			_drag_sel = false


## 设置窗开 / 关（同一个按钮，再点一次收起 —— 与战场的 `≡` 同一种交互）。
func _toggle_settings() -> void:
	if _settings == null:
		return
	if _settings.visible:
		_settings.visible = false
		return
	_place_settings()
	var vols: Dictionary = _audio.volumes() if _audio != null else {}
	# ⚠️ 打开时回写**全部真实状态**：窗里显示的必须就是场上的实际值，
	#    否则玩家看到的开关与实际不符，点一下反而改成了他不想要的那个。
	_settings.set_state({
		"font_scale": FONT.scale,
		"resolution_index": RESOLUTION.current_index(),
		"ui_scale": float(STORE.load_all().get("ui_scale", 0.0)),
		"muted": bool(vols.get("muted", false)),
		"volumes": vols,
	})
	_settings.visible = true
	_settings.move_to_front()


func _on_click(p: Vector2) -> void:
	var bid := _hit_button(p)
	if bid != "":
		_on_button(bid)
		return
	if not _can_pick():
		return
	var my: Array = game.hand_of(HUMAN_SEAT)
	# ⚠️ 从右往左判：右边的牌画在上层，点重叠处应该选中**看得见的那张**。
	for i in range(my.size() - 1, -1, -1):
		if _hand_card_rect(i, my.size(), int(my[i])).has_point(p):
			var id := int(my[i])
			if _sel.has(id):
				_sel.erase(id)
			else:
				_sel.append(id)
			_hint_i = -1
			_toast = ""
			_toast_t = 0.0
			queue_redraw()
			return


## 现在能不能点 / 划选自己的手牌（发牌中、叫分、非自己回合、托管、已结束都不行）。
## ★ 与 _hand_hover_index() 的守卫完全一致 —— 能出悬停高亮的地方就点得中、
##   也划得中，三处共用同一个「能不能选」的判断，少一处不一致就少一个 bug。
func _can_pick() -> bool:
	return _is_human_turn() and int(game.phase) == int(G.Phase.PLAY)


## 点 p 命中的顶栏按钮 id（没有则空串）。
func _hit_button(p: Vector2) -> String:
	for b in _buttons():
		if (b["rect"] as Rect2).has_point(p):
			return String(b["id"])
	return ""


## 按住左键拖选：把光标从 a 划到 b 沿途经过的手牌按 `_drag_mode` 统一选上 / 取下。
##
## ⚠️ 沿路径补采样：快速划动时 MOUSE_MOTION 是稀疏事件，只判当前点会漏掉
##    中间那些牌，就不是「一路划过去全选中」了（而这正是本规则的用途）。
## ⚠️ 命中用**未抬起**的基准矩形（见 _hand_id_at_base）：已选中的牌会抬起
##    半截，拿抬起后的框去判，光标划到哪儿牌就从哪儿滑走 —— 与悬停抖动同坑。
## ⚠️ 一划只有一个方向（按下第一张牌时定下，见 _gui_input）：选上就只加、取下就
##    只减，**不逐张看当前状态** —— 否则来回划会来回翻转（同资源管理器多选拖选）。
func _drag_paint(a: Vector2, b: Vector2) -> void:
	if not _can_pick():
		return
	# ⚠️ 上一个采样点离得太远 ⇒ 中间不是「划过去」而是事件断档（例如光标掠过
	#    设置窗这类会吃掉鼠标的子控件）。此时只判当前点，别沿长直线补采样，
	#    否则会把中间根本没碰到的牌一并选中。
	if a.distance_to(b) > 240.0:
		a = b
	var steps := int(maxf(1.0, ceilf(a.distance_to(b) / 8.0)))
	var changed := false
	for s in range(steps + 1):
		var id := _hand_id_at_base(a.lerp(b, float(s) / float(steps)))
		if id < 0:
			continue
		if _drag_mode < 0:
			if _sel.has(id):
				_sel.erase(id)
				changed = true
		elif not _sel.has(id):
			_sel.append(id)
			changed = true
	if changed:
		_hint_i = -1
		_toast = ""
		_toast_t = 0.0
		queue_redraw()


func _on_button(id: String) -> void:
	match id:
		"back":
			get_tree().change_scene_to_file(MAIN_MENU)
			return
		"settings":
			_toggle_settings()
			return
		"auto":
			_auto = not _auto
			_sel = []
			_refresh_status()
			_push(T.t("DDZ_AUTO", "托管%s") % (T.t("DDZ_AUTO_ON", "已开 —— 你的座位交给电脑") if _auto
						else T.t("DDZ_AUTO_OFF", "已关")))
		"start", "again":
			# ★「再来一局」走同一条路 ⇒ **重发一次牌**（真实牌局每局都有发牌过程）
			_start_game()
			return
		"hint":
			_hint()
		"play":
			_try_play()
		"pass":
			_try_pass()
		_:
			if id.begins_with("bid"):
				_try_bid(int(id.substr(3)))
	queue_redraw()


func _try_bid(score: int) -> void:
	if not _is_human_turn() or int(game.phase) != int(G.Phase.BID):
		_reject(T.t("DDZ_TOAST_NOT_BID", "现在不是你的叫分回合"))
		return
	if score != 0 and score <= int(game.bid_best):
		_reject(T.t("DDZ_TOAST_BID_LOW", "叫分要高于当前最高分（现在是 %d 分）") % int(game.bid_best))
		return
	_do_bid(HUMAN_SEAT, score)


func _try_play() -> void:
	if not _is_human_turn() or int(game.phase) != int(G.Phase.PLAY):
		_reject(T.t("DDZ_TOAST_NOT_PLAY", "还没轮到你出牌"))
		return
	if _sel.is_empty():
		_reject(T.t("DDZ_TOAST_NO_SEL",
					"先点手牌选牌 —— 不知道出什么就按「提示」"))
		return
	if R.classify(_sel).is_empty():
		_reject(T.t("DDZ_TOAST_BAD_TYPE", "这几张凑不成合法牌型"))
		return
	_do_play(HUMAN_SEAT, _sel)


func _try_pass() -> void:
	if not _is_human_turn() or int(game.phase) != int(G.Phase.PLAY):
		_reject(T.t("DDZ_TOAST_NOT_PASS", "还没轮到你"))
		return
	if game.last_play.is_empty():
		# ⛔ 不能静默什么都不干：玩家必须知道「新一轮必须出牌」这条规则。
		_reject(T.t("DDZ_TOAST_MUST_PLAY", "新一轮由你先出，不能不要"))
		return
	_do_pass(HUMAN_SEAT)


## 「提示」：在**能压过上一手的候选**里循环（每按一次换一手）。
##
## ⚠️ 这不是「帮玩家作弊」，是**规则教学 + 调试工具**：
##    玩家要从这里看出「原来这几张能压」，也顺便能发现规则判错。
func _hint() -> void:
	if not _is_human_turn() or int(game.phase) != int(G.Phase.PLAY):
		_reject(T.t("DDZ_TOAST_NOT_HINT", "现在不是你的出牌回合"))
		return
	var cands: Array = game.legal_now(HUMAN_SEAT)
	if cands.is_empty():
		_reject(T.t("DDZ_TOAST_NO_BEAT", "没有能压过的牌 —— 只能「不要」"))
		return
	# 按「张数少的、点数小的」排，提示顺序更好读
	cands.sort_custom(func(a, b): return _hint_key(a) < _hint_key(b))
	_hint_i = (_hint_i + 1) % cands.size()
	_sel = []
	for c in cands[_hint_i]:
		_sel.append(int(c))
	_toast = T.t("DDZ_HINT_N", "提示 %d/%d") % [_hint_i + 1, cands.size()]
	_toast_t = TOAST_SECONDS


func _hint_key(cards: Array) -> int:
	var info := R.classify(cards)
	if info.is_empty():
		return 999999
	return int(info["rank"]) * 100 + (cards as Array).size()


func _reject(reason: String) -> void:
	_toast = reason
	_toast_t = TOAST_SECONDS
	queue_redraw()


# ══════════════════════════════════════════════════════════════════
#  按钮：**画与点唯一的来源**
# ══════════════════════════════════════════════════════════════════

## 当前屏幕上全部可点按钮。`_draw_buttons()` 与 `_on_click()` 都读它 ——
## ⛔ 别在绘制里另写坐标：那样「画出来的框」和「能点的框」会分家（红线 9）。
##
## ⚠️ 布局依据（BGA UX 指南 + 卡牌 UX 最佳实践）：
##   主动作「出牌」居中、更大更亮；次要动作在旁边；「返回/托管」这类
##   「随时可用但不常用」的挪到**右上角** —— 既不跟主动作抢注意力，
##   也远离手牌区（避免误触）。一共不超过 4 个按钮。
func _buttons() -> Array:
	var out: Array = []
	var w := BASE.x
	var h := BASE.y
	out.append({"id": "back", "rect": Rect2(w - 112.0, 8.0, 88.0, 28.0),
			"label": T.t("DDZ_BTN_BACK", "← 返回"), "on": true})
	out.append({"id": "auto", "rect": Rect2(w - 224.0, 8.0, 104.0, 28.0),
			"label": (T.t("DDZ_BTN_AUTO_ON", "托管：开") if _auto
						else T.t("DDZ_BTN_AUTO_OFF", "托管：关")), "on": true})
	# ★ 设置（2026-10-07）。放「随时可用但不常用」那一簇的最左（右上角），
	#   与「返回 / 托管」同一排 —— 不跟桌面的主动作抢注意力。
	#   设置窗一开，`_process` 就停推 AI（见那里的守卫）。
	out.append({"id": "settings", "rect": Rect2(w - 328.0, 8.0, 88.0, 28.0),
			"label": T.t("DDZ_BTN_SETTINGS", "设置"), "on": true})
	if game == null:
		# ★ 进牌桌**不自动开局** ⇒ 空桌正中一个大按钮（用户：「还需要点击一下开始游戏」）。
		#   位置放**桌面圆心** —— 参考录像里「开始游戏」就浮在桌面上，而不是挤在按钮栏。
		out.append({"id": "start",
				"rect": Rect2(w * 0.5 - 108.0, h * TABLE_CY - 27.0, 216.0, 54.0),
				"label": T.t("DDZ_BTN_START", "开始游戏"), "on": true, "primary": true})
		return out
	if game.is_over():
		# ⚠️ 挪到**底部操作栏**的位置：原来在 h*0.6+100 会跟正下方的**玩家块**撞上
		#    （玩家块现在就在正下、手牌正上方）。
		out.append({"id": "again", "rect": Rect2(w * 0.5 - 90.0, h - 126.0, 180.0, 46.0),
				"label": T.t("DDZ_BTN_AGAIN", "再来一局"), "on": true, "primary": true})
		return out
	var bar_y := h - 122.0
	# ★★ 发牌动画期间 **一个叫分按钮都不摆**。
	#    用户原话：「这个时候才出叫不叫地主的判断。现在那个分数按钮还在那，就很难看」
	#    —— 牌还没发完就问「叫几分」是没有依据的。
	# ⚠️ 老实说：这道闸**是冗余的** —— 下面 `_is_human_turn()` 已经把发牌期排除了
	#    （实测：删掉这三行，行为完全不变，自检照样全绿）。
	#    留着是因为「发牌期间不摆叫分」这个意图应该在**建按钮的地方**直接可读，
	#    ⛔ 别删了它、也别以为它坏了没测到 —— 真正兜底的是 `_is_human_turn()`。
	if _dealing:
		return out
	if int(game.phase) == int(G.Phase.BID):
		if _is_human_turn():
			var labels := [T.t("DDZ_BID_PASS", "不叫"),
					T.t("DDZ_BID_1", "1 分"), T.t("DDZ_BID_2", "2 分"),
					T.t("DDZ_BID_3", "3 分")]
			for i in 4:
				out.append({"id": "bid%d" % i,
						"rect": Rect2(w * 0.5 - 176.0 + i * 92.0, bar_y, 84.0, 40.0),
						"label": labels[i], "on": i == 0 or i > int(game.bid_best)})
		return out
	if _is_human_turn():
		out.append({"id": "play", "rect": Rect2(w * 0.5 - 196.0, bar_y, 140.0, 40.0),
				"label": T.t("DDZ_BTN_PLAY", "出牌"),
					"on": not _sel.is_empty(), "primary": true})
		out.append({"id": "pass", "rect": Rect2(w * 0.5 - 40.0, bar_y, 110.0, 40.0),
				"label": T.t("DDZ_PASS", "不要"),
					"on": not game.last_play.is_empty()})
		out.append({"id": "hint", "rect": Rect2(w * 0.5 + 86.0, bar_y, 110.0, 40.0),
				"label": T.t("DDZ_BTN_HINT", "提示"), "on": true})
	return out


# ══════════════════════════════════════════════════════════════════
#  绘制
# ══════════════════════════════════════════════════════════════════
#
# ★ 2026-10-06 第三版：布局 + 美化。**每条改动都有出处**（查了真实产品之后定的）：
#
#  | 改动 | 依据 |
#  |---|---|
#  | 手牌 52×74 → **76×108**（更饱满） | 欢乐斗地主新版美术方向：**手牌尺寸调大 ⇒ 沉浸感更强** |
#  | 中央加**低对比**桌面托盘（只比背景亮一点） | 同上：**牌桌用冷色系弱化体积感 ⇒ 玩家专注打牌本身** |
#  | 每家**自己前方**一个出牌托盘（⛔ 不堆中央） | 斗地主策划文档惯例：各玩家前方的框显示本轮最近一手 |
#  | 上家恒左 / 下家恒右（逆时针轮转） | 同上，与欢乐斗地主一致 |
#  | 行动文本（叫分 / 不要）**持久留在出牌区** | 同上：行动文本不自动消失；轮到该家时清空 |
#  | **最新一手**用金框高亮 | 通用卡牌 UX：用对比/层级把注意力引向「刚刚发生了什么」 |
#  | 回合用**脉冲描边**（不是静态标记） | 卡牌 UX 最佳实践：活跃座位用「细微脉冲或发光」胜过静态箭头 |
#  | 座位改**紧凑面板**（名字/角色/剩张/进度条） | 通用 UX：面板要紧凑（不超过屏 1/4），一眼看清身份与资源 |
#  | 主动作「出牌」加大加亮，次动作描边；≤4 个按钮 | BGA UX 指南：主动作居中醒目、次要在旁边、最多 4 个 |
#  | 牌面加**阴影 + 微圆角 + 中央大花色** | 卡牌 UX：可读性优先；微妙阴影/边框让牌「立起来」 |
#  | 选中的牌抬起 + 金框；**悬停**也抬起一点 | 即时反馈：每个操作都要有立刻的视觉回应 |
#
# ⚠️ 圆角只用在**卡牌和桌面**上：工程 HUD 面板的红线是「禁圆角」，
#    但牌是实体物件，圆角符合认知（资料里 3D 卡牌 = 阴影 + 圆角 + 高光）。

func _draw() -> void:
	# ★★ 2026-10-07 **两段式绘制**（分辨率是 4:3 / 16:10 的档时才看得出区别）：
	#   ① 背景（舰长室）铺满**整个设计空间** —— 多出来的边缘露的是星空与舱壁，
	#      而不是黑边（这正是选 `aspect=expand` 而不是 `keep` 的理由）；
	#   ② 其余一切锚在 **1920×1080 基准区**上，整体平移到居中位置。
	#
	#   ⚠️ 平移**只在两处**生效：这里（绘制）和 `_gui_input`（输入）。
	#      `_buttons()` / `_hand_card_rect()` 返回的**仍是基准区坐标** ⇒
	#      「画」与「点」天然同源（工程红线 9，见 `EveLayout` 顶注）。
	_draw_room(size.x, size.y)     # ★ 舰长室（铺满；⛔ 不加偏移）
	draw_set_transform(_ui_origin())
	var w := BASE.x
	var h := BASE.y

	_draw_table(w, h)          # 大圆桌（先画，牌都落在它上面）
	_draw_top_bar(w)           # 顶部记分条 + 返回/托管
	_draw_bottom_cards(w)      # 底牌（正上方）
	_draw_text(Vector2(28, 72), _status, 16, C_GOLD)   # 轮次提示：左上，最重要的一行

	if game == null:
		_draw_buttons()
	else:
		_draw_seat(1)              # 下家（右）
		_draw_seat(2)              # 上家（左）
		_draw_shown(1)
		_draw_shown(2)
		_draw_shown(0)             # 自己的出牌区最后画（在最上层）
		_draw_hand()
		_draw_me()
		_draw_buttons()
		if game.is_over():
			_draw_over(w, h)
		_draw_floaters()           # 结算飘字压在最上面（用户：要结算飘字）
		if _toast != "":
			_draw_toast(w, h)
	draw_set_transform(Vector2.ZERO)


## 内容居中偏移（非 16:9 分辨率档下不为零）。
##
## ⚠️ 判据用**自己的 `size`**（= 引擎拉伸好的设计空间），⛔ 不用 `get_window().size`：
##    无头模式下窗口尺寸是个假的 `(64,64)`，而 `size` 是真值 ——
##    自检里这张牌桌是被手动设成 1920×1080 的，因此偏移恒为 0，断言不受影响。
func _ui_origin() -> Vector2:
	return LAYOUT.origin_of(size)


## ★ 舰长室：**窗外深空 + 四周舱壁结构框**。
##
## 为什么是「整屏深空 + 舱壁边框」而不是「墙上开一扇舷窗」：
##   先做了舷窗版 —— 牌桌把窗子挡掉大半，左右只剩两块浅灰斑，看着像 bug。
##   ⇒ 改成：整屏就是窗外，舱壁只做**四周结构框**（立柱 + 顶部结构带 + 安全框角标），
##     牌桌"浮"在这片深空里。既不跟牌桌抢地方，又一眼是「室内 + 窗外」。
##
## ⛔ 全部低对比 —— 研究结论：环境要弱化 ⇒ 玩家专注打牌本身。
## ⚠️ 但「弱化」≠「看不见」：给的是**结构**（框 / 刻度 / 角标），不是花纹噪声。
func _draw_room(w: float, h: float) -> void:
	# ── 窗外深空（1:1 取样，⛔ 不缩放）──
	draw_rect(Rect2(0, 0, w, h), C_HULL)
	var sx: float = BG_SPACE_OFFSET.x
	var sy: float = BG_SPACE_OFFSET.y
	draw_texture_rect_region(BG_SPACE, Rect2(0, 0, w, h),
			Rect2(sx, sy, minf(w, 4096.0 - sx), minf(h, 2048.0 - sy)))
	draw_rect(Rect2(0, 0, w, h), C_SPACE_DIM)
	# 星点层（1920×1080 素材；非 1920 宽时会轻微缩放，星点看不出来）
	# ⚠️ 星点素材本身是**细小亮点**，铺在压暗后的星云上几乎看不见
	#    ⇒ 用 modulate > 1 提亮（出图调出来的；调低就没星星了）。
	draw_texture_rect_region(BG_STARS, Rect2(0, 0, w, h), Rect2(0, 0, 1920, 1080),
			Color(1.7, 1.7, 1.7, 1.0))

	# ── 舱壁：左右立柱（把画面「框住」）──
	var dark := Color(0.020, 0.028, 0.036, 0.96)
	draw_rect(Rect2(0, 0, 20, h), dark)
	draw_rect(Rect2(w - 20, 0, 20, h), dark)
	draw_rect(Rect2(20, 0, 1, h), Color(C_FRAME, 0.42))
	draw_rect(Rect2(w - 21, 0, 1, h), Color(C_FRAME, 0.42))
	# 立柱上的分段刻度（EVE 面板语言：用刻度代替装饰花纹）
	var ty := 104.0
	while ty < h - 60.0:
		draw_rect(Rect2(2, ty, 11, 1), Color(C_FRAME, 0.28))
		draw_rect(Rect2(w - 13, ty, 11, 1), Color(C_FRAME, 0.28))
		ty += 64.0

	# ── 舱壁：顶部结构带（紧贴顶栏下沿 ⇒ 像舱壁的上沿）──
	draw_rect(Rect2(0, 44, w, 10), Color(0.024, 0.033, 0.042, 1.0))
	draw_rect(Rect2(0, 53, w, 1), Color(C_FRAME, 0.48))

	# ── 屏幕安全框的 L 形角标（EVE HUD 通用语言：用角标代替完整边框）──
	_corner_marks(Rect2(30, 64, w - 60, h - 118), 54.0, Color(C_GLASS, 0.22), 2.0)


## ★ EVE 战术视角的**距离等差图**（用户 2026-10-07 定）。
##
## 原话：「把中间这个改成 EVE 玩家更为熟悉的战术视角下才会出现的距离等差图，
##   具体做法就是**删除掉中间的色块，只保留一圈一圈的细线**」。
##
## ★ 2026-10-07 二改（用户）：「把中间填色改成**半透明的，透明度 50%**」
##   ⇒ 环线之上再加一层 `C_TABLE_FILL`（50%），星空透过来 ⇒ 像一块玻璃桌面。
##   ⛔ 但**不再是实心**（实心那版已废）；⛔ 且填色必须画在环线**下面**。
##
## ⚠️ 几条不能忘的：
##   · 环线对比度要够（原来 0.13 的 alpha 是为"压在实心桌面上"定的，
##     直接压星空时等于看不见；现在是压在 50% 玻璃上，居中）；
##   · **距离数字是它的本体** —— 等差图没有数字，就只是"几个同心圆"。
func _draw_table(w: float, h: float) -> void:
	var c := Vector2(w * TABLE_CX, h * TABLE_CY)
	var rx := w * TABLE_RX
	var ry := h * TABLE_RY
	# ── 半透明桌面（50%）—— ⚠️ 必须在环线**之前**画，否则会把线盖灰 ──
	draw_colored_polygon(_ellipse(c, rx, ry), C_TABLE_FILL)
	# ── 一圈圈等差细线（这本身就是"桌子"）──
	for i in range(1, RING_N + 1):
		var k := float(i) / float(RING_N)
		draw_polyline(_ellipse(c, rx * k, ry * k, true), C_RING, 1.0, true)
	# 最外圈强一档 = 桌沿 / 最远参考距离
	draw_polyline(_ellipse(c, rx, ry, true), Color(C_RING.r, C_RING.g, C_RING.b, 0.62), 2.0, true)
	# ── 四方位刻度（标出"这四个方向各有一个位置"）──
	for d in 4:
		draw_line(_table_pt(d, 0.95), _table_pt(d, 1.06), Color(C_ACCENT, 0.30), 2.0)
	# ── 中央准星（战术视角的中心标记；没有填充后它也顺手标出圆心）──
	var arm := minf(rx, ry) * 0.055
	draw_line(c - Vector2(arm, 0.0), c + Vector2(arm, 0.0), Color(C_ACCENT, 0.34), 1.0)
	draw_line(c - Vector2(0.0, arm), c + Vector2(0.0, arm), Color(C_ACCENT, 0.34), 1.0)
	# ── 距离标注：沿**上方纵轴**排成一把尺（这一段是空的，不会压到牌）──
	for i in range(1, RING_N + 1):
		var k := float(i) / float(RING_N)
		var y := c.y - ry * k
		draw_line(Vector2(c.x, y), Vector2(c.x + 9.0, y),
				Color(C_RING.r, C_RING.g, C_RING.b, 0.52), 1.0)
		_draw_text(Vector2(c.x + 14.0, y + 4.0), "%d km" % (i * RING_KM), 11,
				Color(0.62, 0.78, 0.82))


## 椭圆采样点（`closed` = 首尾闭合，供 `draw_polyline` 用）。
func _ellipse(c: Vector2, rx: float, ry: float, closed := false) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var n := 96
	var cnt := n + 1 if closed else n
	for i in cnt:
		var a := TAU * float(i) / float(n)
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	return pts


## 圆桌图上某方位的点。`dir` 用 DIR_* ；`k` = 离圆心的距离比例（1.0 = 桌沿）。
func _table_pt(dir: int, k: float) -> Vector2:
	var c := Vector2(BASE.x * TABLE_CX, BASE.y * TABLE_CY)
	match dir:
		DIR_LEFT:
			return Vector2(c.x - BASE.x * TABLE_RX * k, c.y)
		DIR_RIGHT:
			return Vector2(c.x + BASE.x * TABLE_RX * k, c.y)
		DIR_UP:
			return Vector2(c.x, c.y - BASE.y * TABLE_RY * k)
	return Vector2(c.x, c.y + BASE.y * TABLE_RY * k)


## 某座位在桌面上的方位点（出牌 / 亮牌 / 飘字都用它 —— 单一真相源）。
func _seat_pt(seat: int, k: float = PLAY_OUT) -> Vector2:
	return _table_pt(int(SEAT_DIR[seat]), k)


## 居中画一行文字（`pos` = 水平中心 + 基线）。
func _draw_center_text(pos: Vector2, text: String, px: int, col: Color) -> void:
	var tw := _font().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	_draw_text(Vector2(pos.x - tw * 0.5, pos.y), text, px, col)


## 以 `center` 为中心横排一行牌。
func _draw_card_row(cards: Array, center: Vector2, cw: float, ch: float, ov: float,
		hi: bool) -> void:
	var n := cards.size()
	var pw := cw + ov * maxf(0.0, float(n - 1))
	var x0 := center.x - pw * 0.5
	var y0 := center.y - ch * 0.5
	for i in n:
		_card_at(Vector2(x0 + i * ov, y0), int(cards[i]), cw, ch, hi)


## 四角 L 形结构标记（EVE HUD 的通用语言：用角标代替完整边框）。
func _corner_marks(r: Rect2, ln: float, col: Color, lw: float) -> void:
	var p := r.position
	var q := r.end
	draw_line(p, p + Vector2(ln, 0.0), col, lw)
	draw_line(p, p + Vector2(0.0, ln), col, lw)
	draw_line(Vector2(q.x, p.y), Vector2(q.x - ln, p.y), col, lw)
	draw_line(Vector2(q.x, p.y), Vector2(q.x, p.y + ln), col, lw)
	draw_line(Vector2(p.x, q.y), Vector2(p.x + ln, q.y), col, lw)
	draw_line(Vector2(p.x, q.y), Vector2(p.x, q.y - ln), col, lw)
	draw_line(q, q + Vector2(-ln, 0.0), col, lw)
	draw_line(q, q + Vector2(0.0, -ln), col, lw)


## 顶部记分条：全局信息放这里（BGA 的布局口诀：上下放全局信息、中央放共享动作）
func _draw_top_bar(w: float) -> void:
	draw_rect(Rect2(0, 0, w, 44), C_BAR)
	draw_rect(Rect2(0, 43, w, 1), C_PANEL_EDGE)
	_draw_text(Vector2(28, 29),
			T.t("DDZ_TOP_TITLE", "斗地主 · 单机（你 + 两个 AI）"), 17, C_HI)
	if game == null:
		return
	var ll := (T.t("DDZ_TBD", "未定") if game.landlord < 0
			else _seat_name(int(game.landlord)))
	_draw_text(Vector2(300, 29),
			T.t("DDZ_TOP_BASE", "底分 ×%d    ·    地主 %s") % [int(game.base_score), ll],
			14, C_TEXT)
	# ⛔ 这里原来有一行「记牌」提示（外面还有 2×N 王×N）。
	#   用户 2026-10-06 定：「记牌器等等附属功能，就先别出了」⇒ **整行删掉**。
	#   注意：`ddz_ai.gd` 里 AI 的记牌**照旧保留** —— 那是 AI 强度的一部分，
	#   去掉的只是"给玩家看的那个面板"。


## 底牌（顶部中央）。叫分阶段盖着 —— 叫完才亮。
func _draw_bottom_cards(w: float) -> void:
	# ⛔ 还没点「开始游戏」⇒ 底牌也不画：**桌上空空**才是「还没开始」该有的样子。
	if game == null:
		return
	# ★ 发牌动画最后 3 张才是底牌 ⇒ 手牌没发完之前它们不出现（与录像一致）。
	if _dealing and _deal_t < DEAL_SEC - DEAL_BOTTOM_LEAD:
		return
	var cw := 44.0
	var ch := 62.0
	var gap := 8.0
	var total := cw * 3.0 + gap * 2.0
	var x0 := w * 0.5 - total * 0.5
	var bidding := int(game.phase) == int(G.Phase.BID)
	_draw_text(Vector2(x0, 66),
			T.t("DDZ_BOTTOM", "底牌")
					+ (T.t("DDZ_BOTTOM_HIDDEN", "（叫完才亮）") if bidding else ""),
			12, C_DIM)
	for i in 3:
		var id: int = int((game.bottom as Array)[i])
		var pos := Vector2(x0 + i * (cw + gap), 74)
		if bidding:
			_card_back(pos, cw, ch)
		else:
			_card_at(pos, id, cw, ch, false)


## ★ 接入头像（拿到素材时调它，⛔ 不用改布局）。
##   素材请裁成**正方形**（这里按方形区域贴，不保持原比例 —— 变形比留白更难看）。
##   `tex = null` ⇒ 退回几何占位剪影。
func set_avatar(seat: int, tex: Texture2D) -> void:
	if seat < 0 or seat >= _avatars.size():
		return
	_avatars[seat] = tex
	queue_redraw()


## 头像。有贴图 ⇒ 画立绘；没有 ⇒ 画**几何占位剪影**（头 + 肩）。
##
## ⚠️ 占位故意画成"人形剪影"而不是一个问号/空框：一眼能看出**这里将来是脸**，
##    又不会假装已经有脸。⛔ 别画假头像（那比空着更容易被当成 bug）。
func _draw_avatar(pos: Vector2, sx: float, seat: int) -> void:
	_round_rect(Rect2(pos, Vector2(sx, sx)), C_BTN, AVATAR_R)
	var tex = _avatars[seat] if seat < _avatars.size() else null
	if tex is Texture2D:
		draw_texture_rect(tex as Texture2D, Rect2(pos, Vector2(sx, sx)), false)
	else:
		var col := Color(C_DIM, 0.55)
		# 头
		draw_circle(pos + Vector2(sx * 0.5, sx * 0.36), sx * 0.17, col)
		# 肩：上半圆（几何算在框内，不会被裁）
		var pts := PackedVector2Array()
		for i in 13:
			var an := PI + PI * float(i) / 12.0
			pts.append(pos + Vector2(sx * 0.5 + cos(an) * sx * 0.30,
					sx * 0.92 + sin(an) * sx * 0.30))
		draw_colored_polygon(pts, col)
	_round_rect(Rect2(pos, Vector2(sx, sx)), C_PANEL_EDGE, AVATAR_R, false, 1.0)


## 座位面板：**头像 + 名字 + 角色徽章 + 剩张 + 进度条**。
##
## ★ 2026-10-06 加头像位（依据：欢乐斗地主的座位是「立绘 + 名牌 + 金币」）。
## ⚠️ 面板必须小 —— 资料：4 人局在手机上也不能超过屏的 1/4。
## ⚠️ 原来那 3 张装饰牌背**删掉了**：加了头像之后面板放不下，
##    而且它跟「剩张数字 + 进度条」表达的是同一件事（冗余）。
func _draw_seat(seat: int) -> void:
	var w := BASE.x
	# ★ 座位面板贴**左右两侧、与圆心同高**（不再挤在顶角）——
	#   用户 2026-10-06：「位置也不对，需要更靠近自己的位置一些」。
	var cy := BASE.y * TABLE_CY
	var x: float = 28.0 if int(SEAT_DIR[seat]) == DIR_LEFT else w - 28.0 - SEAT_W
	var r := Rect2(x, cy - SEAT_H * 0.5, SEAT_W, SEAT_H)
	var active: bool = int(game.turn) == seat and not game.is_over()
	_round_rect(r, C_PANEL, 10.0)
	# ★ 回合指示 = 脉冲描边（资料：胜过静态箭头）
	var edge := C_ACCENT if not active else Color(C_ACCENT, 0.45 + 0.55 * _pulse())
	_round_rect(r, edge, 10.0, false, 2.0 if active else 1.0)

	_draw_avatar(Vector2(r.position.x + 12.0, r.position.y + 22.0), AVATAR, seat)

	var tx := r.position.x + 12.0 + AVATAR + 12.0        ## 文字块左沿
	var n := _seat_count(seat)
	var start := 20 if seat == int(game.landlord) else DEAL_FACE
	var name_col := C_HI if active else C_TEXT
	_draw_text(Vector2(tx, r.position.y + 34.0), _seat_name(seat), 15, name_col)
	# 角色徽章（**形状 + 文字**双重表达 ⇒ 色盲也能分辨，不靠颜色）
	var is_ll := seat == int(game.landlord)
	if game.landlord >= 0:
		var badge := Rect2(tx, r.position.y + 44.0, 52.0, 20.0)
		_round_rect(badge, C_GOLD if is_ll else C_ACCENT, 4.0)
		_draw_text(Vector2(badge.position.x + 10.0, badge.position.y + 15.0),
				(T.t("DDZ_ROLE_LANDLORD", "地主") if is_ll
						else T.t("DDZ_ROLE_FARMER", "农民")), 12, C_BG)
	else:
		# ⚠️ 叫分阶段地主还没定 ⇒ ⛔ 不能随便标一个身份（那是**没有依据的**）
		_round_rect(Rect2(tx, r.position.y + 44.0, 52.0, 20.0), C_BTN, 4.0)
		_draw_text(Vector2(tx + 10.0, r.position.y + 59.0),
				T.t("DDZ_ROLE_TBD", "待定"), 12, C_DIM)
	# ★★ 代币位（预留）：参考图里每个座位都把金币数挂在这里。
	#    等棋牌室代币定了，这一行就是 `_draw_text(..., "❖ %d" % coin, 13, C_GOLD)`。
	#    ⛔ 现在**不画假数字** —— 没有数据来源的读数比空着更糟。

	# 剩余张数（大号，右对齐；小号「张」跟在后面）
	var f := _font()
	var num_t := str(n)
	var zh_t := T.t("DDZ_UNIT_CARD", "张")
	var zh_w := f.get_string_size(zh_t, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	var num_w := f.get_string_size(num_t, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x
	var right := r.position.x + SEAT_W - 16.0
	_draw_text(Vector2(right - zh_w, r.position.y + 64.0), zh_t, 12, C_DIM)
	_draw_text(Vector2(right - zh_w - 6.0 - num_w, r.position.y + 64.0), num_t, 26, C_HI)
	# 进度条
	var bar := Rect2(r.position.x + 12.0, r.position.y + SEAT_H - 18.0, SEAT_W - 24.0, 6.0)
	_round_rect(bar, C_BTN, 3.0)
	var frac := clampf(float(n) / float(start), 0.0, 1.0)
	if frac > 0.0:
		_round_rect(Rect2(bar.position, Vector2(maxf(4.0, bar.size.x * frac), bar.size.y)),
				C_ACCENT if not is_ll else C_GOLD, 3.0)


## 玩家自己的头像块（左下角）。
##
## ★ 与参考图的「自己的头像 + 名字 + 金币」同位 —— 参考图左下角就是玩家自己。
## ★★ 这里同时是**代币显示位**的预留处（`代币` 那行注释）。
## ⛔ 不画假数字：没有数据来源的读数比空着更糟。
func _draw_me() -> void:
	var h := BASE.y
	# ★ 用户 2026-10-06：「玩家头像 ID 代币位置也不对，需要更靠近自己的位置一些，
	#   哪怕就在正上正左正右也比现在歪一大截好很多」⇒ 自己的方位是**正下**，
	#   所以这块**水平居中、就在手牌正上方**。
	# ⚠️ 上移量是出图调的：`h-390` 时手牌张数少（标题靠中间）会被这块压住一行。
	# ⚠️ 牌桌下移后这里也从 h-404 微调到 h-400（仍留 11px 给手牌标题）
	var p := Vector2(BASE.x * 0.5 - SEAT_W * 0.5, h - 400.0)
	var box := Rect2(p, Vector2(SEAT_W, SEAT_H))
	var mine: bool = _is_human_turn() and not game.is_over()
	_round_rect(box, C_PANEL, 10.0)
	var edge := C_ACCENT if not mine else Color(C_ACCENT, 0.45 + 0.55 * _pulse())
	_round_rect(box, edge, 10.0, false, 2.0 if mine else 1.0)
	_draw_avatar(Vector2(p.x + 12.0, p.y + 22.0), AVATAR, HUMAN_SEAT)
	var tx := p.x + 12.0 + AVATAR + 12.0
	_draw_text(Vector2(tx, p.y + 34.0), T.t("DDZ_SEAT_0", "你"), 15, C_HI)
	if game.landlord >= 0:
		var is_ll := int(game.landlord) == HUMAN_SEAT
		_round_rect(Rect2(tx, p.y + 44.0, 52.0, 20.0), C_GOLD if is_ll else C_ACCENT, 4.0)
		_draw_text(Vector2(tx + 10.0, p.y + 59.0), (T.t("DDZ_ROLE_LANDLORD", "地主") if is_ll
				else T.t("DDZ_ROLE_FARMER", "农民")), 12, C_BG)
	else:
		_round_rect(Rect2(tx, p.y + 44.0, 52.0, 20.0), C_BTN, 4.0)
		_draw_text(Vector2(tx + 10.0, p.y + 59.0),
				T.t("DDZ_ROLE_TBD", "待定"), 12, C_DIM)
	# ★ 娱乐币（用户 2026-10-06 定名）—— 方案 A：**纯记分**，余额可以为负
	_draw_text(Vector2(tx, p.y + 84.0),
			T.t("DDZ_COIN", "娱乐币 %s") % COIN.fmt(int(COIN.coin)), 13, C_GOLD)


## 出牌区：**各家在自己方位的桌面上摊牌**。
##
## ⛔ 不再用"托盘方框"（用户 2026-10-06：中间改成大圆桌）—— 圆桌上再摞一排方框会打架，
##   而且参考图里也没有框：牌就是落在桌面上。
## ★ 行动文本改成**大字**（用户：「对手动作大字」）：不要 / 不叫 ——
##   把「这家刚干了什么」直接写在他们自己的方位上。
## ★ 局终**亮牌**（用户：「结算亮牌」）：对手剩什么牌全摊出来，
##   玩家这才知道自己差在哪（参考图 7/8 就是这么做的）。
func _draw_shown(seat: int) -> void:
	var c := _seat_pt(seat)
	# ⚠️ 必须显式标注类型：`game` 是动态类型，``:=`` 推不出来
	var over: bool = game.is_over()
	var is_last: bool = not over and not game.last_play.is_empty() \
			and int(game.last_play["seat"]) == seat
	# 座位名（贴在该方位牌的上方）
	_draw_center_text(c + Vector2(0.0, -PLAY_CARD_H * 0.5 - 24.0), _seat_name(seat), 13,
			C_GOLD if is_last else C_DIM)
	# 行动大字
	var pass_t := T.t("DDZ_PASS", "不要")
	var note := String(_bid_text[seat])
	if note == "" and _passed[seat]:
		note = pass_t
	if note != "" and not over:
		_draw_center_text(c + Vector2(0.0, PLAY_CARD_H * 0.5 + 36.0), note, 30,
				C_GOLD if note == pass_t else C_TEXT)
	if over and seat != HUMAN_SEAT:
		_show_leftover(seat, c)
	elif (_shown[seat] is Array) and not (_shown[seat] as Array).is_empty():
		var cards: Array = _shown[seat]
		_draw_card_row(cards, c, PLAY_CARD_W, PLAY_CARD_H, _play_overlap(cards.size()),
				is_last)


## 局终亮牌：把这家**手里剩下的牌**摊在他的方位上（参考图 7/8 的做法）。
func _show_leftover(seat: int, c: Vector2) -> void:
	var left: Array = game.hand_of(seat)
	if left.is_empty():
		_draw_center_text(c, T.t("DDZ_ALL_OUT", "已出完"), 22, C_HI)
		return
	var n := left.size()
	var ov := minf(22.0, (PLAY_ROW_MAX * 0.72 - 46.0) / maxf(1.0, float(n - 1)))
	_draw_card_row(left, c, 46.0, 64.0, ov, false)


## 我的手牌（底部，最大最亮 —— 资料：手牌放大最提沉浸感）
##
## ★ 2026-10-07 发牌动画：**逐张从桌面中央飞入落位**（用户：「让手牌一张一张的出现」）。
##   ⚠️⚠️ 动画**只影响「画」** —— `game.hand_of()` 从头到尾都是 17 张。
##   ⛔ 别用「边发边往手里塞牌」来实现：规则/AI 会读到半副牌，P2P 还会两边分叉（见 `_start_game`）。
func _draw_hand() -> void:
	var my: Array = game.hand_of(HUMAN_SEAT)
	var n := my.size()
	var hp := _hand_pos(n)
	var is_ll := int(game.landlord) == HUMAN_SEAT
	# ⚠️ 叫分阶段地主还没定 ⇒ ⛔ 不能显示「农民」—— 那是一个**没有依据的身份**
	var role := (T.t("DDZ_ROLE_NONE", "身份未定") if int(game.landlord) < 0
			else (T.t("DDZ_ROLE_LANDLORD", "地主") if is_ll
				else T.t("DDZ_ROLE_FARMER", "农民")))
	# ★ 新底牌抬起期间标题也点一句 —— 否则玩家不知道那 3 张为什么跳出来
	var hint: String = T.t("DDZ_NEW_BOTTOM", "　★ 底牌已加入（抬起的 3 张）") \
			if _new_t > 0.0 and not _new_ids.is_empty() else ""
	# ⚠️ 发牌期间**必须报「已到手的张数」** —— ⛔ 不能报 17：
	#    牌还没发完却写着「17 张」，是最容易被当成 bug 的那类不一致。
	if _dealing:
		_draw_text(Vector2(hp.x, hp.y - 14.0),
				T.t("DDZ_HAND_DEALING", "你的手牌 · %d / %d 张　发牌中…") % [int(_deal_progress()), n], 14, C_HI)
	else:
		_draw_text(Vector2(hp.x, hp.y - 14.0),
				T.t("DDZ_HAND_TITLE", "你的手牌 · %d 张 · %s%s") % [n, role, hint], 14, C_HI)
	var prog := _deal_progress()
	for i in n:
		# ★ 发牌期间只画「已经到手」的（正在飞的那张由 `_deal_fly_pos` 插值到中途）
		if not _hand_card_visible(i):
			break
		var id := int(my[i])
		var r := _hand_card_rect(i, n, id)
		# ★ 新到的底牌也要金框（用户：「新底牌抬起提示」）
		var hot := _sel.has(id) or (_new_t > 0.0 and _new_ids.has(id))
		var pos: Vector2 = _deal_fly_pos(r.position, i, prog) if _dealing else r.position
		_card_at(pos, id, HAND_CARD_W, HAND_CARD_H, hot)
	# 已选牌 + 牌型判断（左对齐在手牌左端，与手牌同宽）
	# ⚠️ 发牌期间换一句话：那句「看完这手牌再决定：不叫 / 1 分…」在牌没发完时毫无意义。
	_draw_text(Vector2(hp.x, hp.y + HAND_CARD_H + 22.0),
			T.t("DDZ_HAND_DEAL_HINT", "发牌中 —— 发完才轮到你叫地主")
					if _dealing else _sel_text(),
			14, C_DIM if _dealing else _sel_color())


## 第 i 张手牌**现在该不该画**（发牌期间只有已经「到手」的那些才画）。
##
## ★★ 抽成独立函数是为了让**自检能读到与 `_draw()` 同一个判据**：
##    ⛔ 别在自检里另写一遍 `float(i) >= prog` —— 那份判据一改，
##    断言就变成在测别的东西，而「手牌是不是逐张出现」这件事**没有任何异常会提示你**。
func _hand_card_visible(i: int) -> bool:
	if not _dealing:
		return true
	return float(i) < _deal_progress()


## 发牌进度：**已经落到手上的张数**（可以是小数 —— 小数部分就是「正在飞」的那一张）。
##
## ★ 这是发牌动画与**数据层**之间唯一的接口：只读不算、不改任何状态。
##   ⇒ 将来做 P2P 时，两台机器各自播各自的动画即可，牌局状态不受影响。
func _deal_progress() -> float:
	if not _dealing:
		return float(DEAL_FACE)
	return clampf(_deal_t / DEAL_SEC, 0.0, 1.0) * float(DEAL_FACE)


## 第 i 张牌的绘制位置：进度落在 [i, i+1) 区间时，它正在从桌面中央飞到落位。
##
## ⚠️ 用 **ease-out cubic**（前快后慢）：牌「被甩出去」就是这个手感。
##   线性插值会显得像电梯 —— 真实产品里这类动画几乎都带缓动。
func _deal_fly_pos(dest: Vector2, i: int, prog: float) -> Vector2:
	var k := clampf(prog - float(i), 0.0, 1.0)
	if k >= 1.0:
		return dest
	var e := 1.0 - pow(1.0 - k, 3.0)
	# 起点 = 桌面圆心（牌堆在桌上）⇒ 与距离环圆心重合，视觉上是「从桌上发出去」
	var from := Vector2(BASE.x * TABLE_CX - HAND_CARD_W * 0.5,
			BASE.y * TABLE_CY - HAND_CARD_H * 0.5)
	return from.lerp(dest, e)


## 座位面板上显示的「剩余张数」。
##
## ⚠️ 发牌期间必须**跟着动画涨**：否则「发牌」只发生在你一家，
##    两家对手一进来就是 17 张，看起来像早就发完了。
## ★ 两家错开一点点（**下家**先、上家后）⇒ 看起来像「轮流发牌」，而不是同时变。
## ⚠️ 判据用**座位号**（座位 1 = 下家）而不是左右 —— 左右 2026-10-07 对调过
##    （见 `SEAT_DIR`），用方向判会把「下家先」这句注释悄悄变成谎话。
func _seat_count(seat: int) -> int:
	var real: int = (game.hand_of(seat) as Array).size()
	if not _dealing:
		return real
	if seat == HUMAN_SEAT:
		return mini(real, int(_deal_progress()))
	var off := 2.0 if seat == 1 else 4.0
	return mini(real, maxi(0, int(_deal_progress() + off)))


## 按钮：主（出牌）/ 次（不要、提示）/ 禁用 三态 + hover。
## ⚠️ 这里的坐标是**唯一来源** —— `_on_click()` 用的也是 `_buttons()`（红线 9）。
func _draw_buttons() -> void:
	for b in _buttons():
		var r: Rect2 = b["rect"]
		var on := bool(b["on"])
		var primary := bool(b.get("primary", false))
		var hov := r.has_point(get_local_mouse_position())
		if not on:
			_round_rect(r, C_BTN_OFF, 8.0)
			_round_rect(r, C_DIM, 8.0, false, 1.0)
		elif primary:
			_round_rect(r, C_PRIMARY if not hov else C_PRIMARY.lightened(0.14), 8.0)
		else:
			_round_rect(r, C_BTN_HOT if hov else C_BTN, 8.0)
			_round_rect(r, C_ACCENT if hov else C_PANEL_EDGE, 8.0, false, 1.0)
		var label := String(b["label"])
		var px := 17 if primary else 15
		var col := C_BG if (on and primary) else (C_HI if on else C_DIM)
		var f := _font()
		var tw := f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
		_draw_text(Vector2(r.position.x + (r.size.x - tw) * 0.5,
				r.position.y + r.size.y * 0.5 + px * 0.36), label, px, col)


## ⚠️ 对局记录**不再显示**（用户 2026-10-06：「对局记录这种东西不需要」）。
##   但 `_feed` 数据与 `_push()` **保留** —— 它是自检的判据来源
##   （`verify_ddz` 靠"最后一条记录是「你 出 …」"验真实点击通道），
##   也是排障时唯一能回看"刚刚发生了什么"的东西。⇒ 只是不画，不是不存在。


## 结算。★ 用户 2026-10-06 定：「就先改**结算亮字**和**结算飘字**」。
##   亮字 = 中央大字（玩家视角的胜负）+ 本局娱乐币 + 累计战绩。
##   亮牌在 `_draw_shown()`（对手剩余手牌摊出来）；飘字在 `_draw_floaters()`。
func _draw_over(w: float, h: float) -> void:
	var win := _human_won()
	var who := (T.t("DDZ_ROLE_LANDLORD", "地主") if game.landlord_won()
			else T.t("DDZ_ROLE_FARMER", "农民"))
	var cx := w * 0.5
	# 放圆桌偏上：中央偏下要留给「自己」的摊牌位
	var cy := h * TABLE_CY - h * TABLE_RY * 0.60
	_draw_center_text(Vector2(cx, cy),
			T.t("DDZ_WIN", "你赢了") if win else T.t("DDZ_LOSE", "你输了"), 56,
			C_GOLD if win else C_WARN)
	_draw_center_text(Vector2(cx, cy + 44.0),
			T.t("DDZ_OVER_DELTA", "%s 胜 · 本局娱乐币 %+d") % [who, _my_delta],
			20, C_TEXT)
	# 方案 A = 纯记分 ⇒ 这里只有累计，没有底金/破产（字段已按 B/C 留好）
	_draw_center_text(Vector2(cx, cy + 74.0),
			T.t("DDZ_OVER_TOTAL", "累计 %s · %d 胜 / %d 局") % [COIN.fmt(int(COIN.net)), int(COIN.wins),
						int(COIN.games)], 15, C_DIM)


## 结算飘字：每家方位上飘一个 ±N（参考图 7/8：每个座位头顶飘金币增减）。
func _draw_floaters() -> void:
	for f in _floaters:
		var k := clampf(float(f["t"]) / FLOAT_SEC, 0.0, 1.0)
		var p: Vector2 = _seat_pt(int(f["seat"])) + Vector2(0.0, -112.0 - 54.0 * k)
		_draw_center_text(p, String(f["text"]), 30, Color(f["col"], 1.0 - k * 0.85))


## 提示条（操作被拒 / 提示档位）
func _draw_toast(w: float, h: float) -> void:
	var f := _font()
	var tw := f.get_string_size(_toast, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
	var box := Rect2((w - tw) * 0.5 - 16.0, h - 46.0, tw + 32.0, 30.0)
	_round_rect(box, Color(C_WARN, 0.16), 8.0)
	_round_rect(box, Color(C_WARN, 0.55), 8.0, false, 1.0)
	_draw_text(Vector2((w - tw) * 0.5, h - 26.0), _toast, 15, C_WARN)


# ══════════════════════════════════════════════════════════════════
#  牌面（全部代码画：阴影 + 微圆角 + 中央大花色）
# ══════════════════════════════════════════════════════════════════

## 一张明牌。`hi` = 高亮（最新一手 / 已选中）
func _card_at(pos: Vector2, id: int, cw: float, ch: float, hi: bool) -> void:
	# 阴影：让牌「立起来」（资料：微妙阴影/边框能让牌面分离出来）
	_round_rect(Rect2(pos + Vector2(2.5, 2.5), Vector2(cw, ch)), Color(0, 0, 0, 0.30), cw * 0.09)
	_round_rect(Rect2(pos, Vector2(cw, ch)), C_CARD, cw * 0.09)
	# ★ 贴图牌面（白名单见 CARD_FACES 顶注）：整张覆盖，角标贴图自带。
	#   ⚠️ 画在**底色之后、描边之前** —— 选中金框要压在贴图上。
	#   贴图比例（512:717 ≈ 0.714）与牌面（76:108 ≈ 0.704）几乎一致，直接拉伸无畸变。
	var face: Texture2D = CARD_FACES.get(id)
	if face != null:
		draw_texture_rect(face, Rect2(pos, Vector2(cw, ch)), false)
	_round_rect(Rect2(pos, Vector2(cw, ch)), C_GOLD if hi else C_CARD_EDGE, cw * 0.09, false,
			2.0 if hi else 1.0)
	if face != null:
		return
	var rank := R.rank_of(id)
	# ⚠️ 大王(53) 红、小王(52) 黑 —— 与实体牌一致
	var col := C_RED if (R.suit_of(id) == 1 or R.suit_of(id) == 2 or id == 53) else C_BLACK
	var small := cw < 56.0
	# 左上角：点数 + 小花色
	_draw_text(pos + Vector2(cw * 0.11, ch * 0.22), R.label_of(id), int(cw * 0.30), col)
	_suit(pos + Vector2(cw * 0.17, ch * 0.34), R.suit_of(id), cw * 0.07, col)
	# 中央大花色（小牌就不画，免得糊成一团）
	if not small:
		if R.suit_of(id) == 4:
			# 王：画一个五角星（⛔ 不用 emoji / 不用 ♠♥♣♦ 字符，红线 3）
			_star(pos + Vector2(cw * 0.5, ch * 0.66), ch * 0.16, col)
		else:
			_suit(pos + Vector2(cw * 0.5, ch * 0.64), R.suit_of(id), ch * 0.17, col)


func _card_back(pos: Vector2, cw: float, ch: float) -> void:
	_round_rect(Rect2(pos + Vector2(2.0, 2.0), Vector2(cw, ch)), Color(0, 0, 0, 0.28), cw * 0.10)
	_round_rect(Rect2(pos, Vector2(cw, ch)), C_BACK, cw * 0.10)
	_round_rect(Rect2(pos, Vector2(cw, ch)), C_BACK_EDGE, cw * 0.10, false, 1.0)
	# 内部一个菱形纹样（几何，不依赖贴图）
	var c := pos + Vector2(cw * 0.5, ch * 0.5)
	var s := Vector2(cw * 0.20, ch * 0.22)
	draw_colored_polygon(PackedVector2Array([
			c + Vector2(0, -s.y), c + Vector2(s.x, 0),
			c + Vector2(0, s.y), c + Vector2(-s.x, 0)]), Color(C_BACK_EDGE, 0.55))


## 花色：画**几何形状**（⛔ 不用 ♠♥♦♣ 字符 —— 某些字体会渲染成彩色 emoji）
##   0=黑桃 1=红桃 2=方块 3=梅花 4=王（无花色）
func _suit(c: Vector2, suit: int, s: float, col: Color) -> void:
	match suit:
		0:  # 黑桃：尖朝上的三角 + 圆底
			draw_colored_polygon(PackedVector2Array([
					c + Vector2(0, -s), c + Vector2(-s * 0.9, s * 0.3),
					c + Vector2(s * 0.9, s * 0.3)]), col)
			draw_circle(c + Vector2(0, s * 0.35), s * 0.55, col)
		2:  # 方块：菱形
			draw_colored_polygon(PackedVector2Array([
					c + Vector2(0, -s), c + Vector2(s * 0.8, 0),
					c + Vector2(0, s), c + Vector2(-s * 0.8, 0)]), col)
		1:  # 红桃：两个圆 + 下三角
			draw_circle(c + Vector2(-s * 0.45, -s * 0.25), s * 0.5, col)
			draw_circle(c + Vector2(s * 0.45, -s * 0.25), s * 0.5, col)
			draw_colored_polygon(PackedVector2Array([
					c + Vector2(-s * 0.92, 0.0), c + Vector2(s * 0.92, 0.0),
					c + Vector2(0, s)]), col)
		3:  # 梅花：三圆 + 柄
			draw_circle(c + Vector2(0, -s * 0.45), s * 0.45, col)
			draw_circle(c + Vector2(-s * 0.5, s * 0.2), s * 0.45, col)
			draw_circle(c + Vector2(s * 0.5, s * 0.2), s * 0.45, col)
			draw_rect(Rect2(c + Vector2(-s * 0.14, s * 0.3), Vector2(s * 0.28, s * 0.7)), col)


## 五角星（王牌用）。⛔ 不用 emoji、不用 ★ 字符 —— 字符会被字体渲染成彩色符号。
func _star(c: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 10:
		var rad: float = r if i % 2 == 0 else r * 0.42
		var a := -PI * 0.5 + PI * float(i) / 5.0
		pts.append(c + Vector2(cos(a), sin(a)) * rad)
	draw_colored_polygon(pts, col)


## 圆角矩形。工程 HUD 面板一律直角，**卡牌与桌面例外**（实体物件，圆角符合认知）。
func _round_rect(r: Rect2, col: Color, rad: float, filled := true, lw := 1.0) -> void:
	if filled:
		draw_colored_polygon(_round_points(r, rad), col)
	else:
		draw_polyline(_round_points(r, rad, true), col, lw, true)


func _round_points(r: Rect2, rad: float, closed := false) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var corners := [
		[Vector2(r.position.x + r.size.x - rad, r.position.y + rad), -PI * 0.5],
		[Vector2(r.position.x + r.size.x - rad, r.position.y + r.size.y - rad), 0.0],
		[Vector2(r.position.x + rad, r.position.y + r.size.y - rad), PI * 0.5],
		[Vector2(r.position.x + rad, r.position.y + rad), PI],
	]
	for cc in corners:
		var center: Vector2 = cc[0]
		var a0: float = cc[1]
		for i in range(7):
			var a := a0 + PI * 0.5 * float(i) / 6.0
			pts.append(center + Vector2(cos(a), sin(a)) * rad)
	if closed:
		pts.append(pts[0])
	return pts


# ══════════════════════════════════════════════════════════════════
#  几何 / 文案小工具
# ══════════════════════════════════════════════════════════════════

## 手牌第一张的左上角（整把牌居中）。**基准位置**，不含抬起。
func _hand_base_rect(i: int, n: int) -> Rect2:
	var wdt := maxf(0.0, float(n - 1)) * HAND_OVERLAP + HAND_CARD_W
	var x0 := (BASE.x - wdt) * 0.5
	return Rect2(Vector2(x0 + i * HAND_OVERLAP, BASE.y - HAND_CARD_H - HAND_BOTTOM_GAP),
			Vector2(HAND_CARD_W, HAND_CARD_H))


func _hand_pos(n: int) -> Vector2:
	return _hand_base_rect(0, n).position


## 第 i 张手牌的**实际矩形**（选中 / 悬停会上移）。
## ★★ `_draw_hand()` 和 `_on_click()` 都用这个函数 —— 这就是「画的和点的同一来源」。
func _hand_card_rect(i: int, n: int, id: int) -> Rect2:
	var r := _hand_base_rect(i, n)
	if _sel.has(id):
		r.position.y -= LIFT
	elif i == _hover_i:
		r.position.y -= HOVER_LIFT
	# ★ 刚加入手牌的底牌**额外抬起**一会儿（用户：「新底牌抬起提示」）
	#   ⚠️ 这也影响命中判定 —— 与"选中的牌抬起"走同一条路，行为一致就不别扭。
	if _new_t > 0.0 and _new_ids.has(id):
		r.position.y -= NEW_LIFT
	return r


## 鼠标悬停在哪张手牌上（用**未抬起**的基准矩形判定）。
## ⚠️ 故意不用 `_hand_card_rect()`：那张被抬起后判定框也跟着动，
##    鼠标一到就「抬起→脱离→落下→再进」闪个不停（经典抖动）。
func _hand_hover_index(p: Vector2) -> int:
	if game == null or game.is_over() or not _is_human_turn():
		return -1
	if int(game.phase) != int(G.Phase.PLAY):
		return -1
	var my: Array = game.hand_of(HUMAN_SEAT)
	for i in range(my.size() - 1, -1, -1):
		if _hand_base_rect(i, my.size()).has_point(p):
			return i
	return -1


func _hand_id_at_base(p: Vector2) -> int:
	# ⚠️ 用**未抬起**的基准矩形判定：选中的牌会抬起半截，拿抬起后的框去判会让
	#    光标「划到哪儿牌就从哪儿滑走」（与 _hand_hover_index 是同一个坑）。
	#   调用方（_drag_paint）已保证 game 非空且轮到你出牌。
	var my: Array = game.hand_of(HUMAN_SEAT)
	for i in range(my.size() - 1, -1, -1):
		if _hand_base_rect(i, my.size()).has_point(p):
			return int(my[i])
	return -1


## 出牌区的叠放间距 / 总宽（牌多时自动收紧，别撑破托盘）
func _play_overlap(n: int) -> float:
	if n <= 1:
		return 0.0
	return minf(PLAY_OVERLAP, (PLAY_ROW_MAX - PLAY_CARD_W) / float(n - 1))


func _play_width(n: int) -> float:
	return PLAY_CARD_W + _play_overlap(n) * maxf(0.0, float(n - 1))


## 回合脉冲（0~1）。资料：活跃座位用「细微脉冲或发光」，胜过静态箭头。
func _pulse() -> float:
	return 0.5 + 0.5 * sin(_t * 3.4)


func _sel_text() -> String:
	# ⚠️ 叫分阶段选牌没有意义 ⇒ 换一行**指向当前该做的事**的文案
	#    （别让玩家盯着「未选牌 —— 点手牌选择」发呆，那时候点了也不算数）
	if game != null and int(game.phase) == int(G.Phase.BID):
		if _is_human_turn():
			return T.t("DDZ_SEL_BID",
					"看完这手牌再决定：不叫 / 1 分 / 2 分 / 3 分（分数越高底分越大）")
		return T.t("DDZ_SEL_WAIT", "等别家叫分…")
	if _sel.is_empty():
		return T.t("DDZ_SEL_NONE",
				"未选牌 —— 点手牌选择（右键清空，「提示」帮你想）")
	var info := R.classify(_sel)
	if info.is_empty():
		return T.t("DDZ_SEL_BAD", "已选 %s —— 不是合法牌型") % _cards_text(_sel)
	return T.t("DDZ_SEL_OK", "已选 %s（%s）") % [_cards_text(_sel),
			R.type_name(int(info["type"]))]


func _sel_color() -> Color:
	if _sel.is_empty():
		return C_DIM
	return C_TEXT if not R.classify(_sel).is_empty() else C_WARN


func _human_won() -> bool:
	if game == null or game.winner < 0:
		return false
	# 地主赢了 ⇒ 我是地主才算赢；农民赢了 ⇒ 我不是地主就算赢
	return (game.winner == int(game.landlord)) == (int(game.landlord) == HUMAN_SEAT)


func _seat_name(seat: int) -> String:
	# ⚠️ 座位 1 在**你之后**出牌 ⇒ 下家（2026-10-07 起在**右**）；座位 2 在**你之前**
	#    出牌 ⇒ 上家（在**左**）。方位由 `SEAT_DIR` 定，这里只写名字。
	#   ⛔ 上一版两个名字正好写反了（用户 2026-10-06 指出）。
	var who: String = [T.t("DDZ_SEAT_0", "你"), T.t("DDZ_SEAT_1", "下家"),
			T.t("DDZ_SEAT_2", "上家")][seat]
	if game != null and game.landlord >= 0:
		who += (T.t("DDZ_SEAT_LL", "（地主）") if seat == int(game.landlord)
				else T.t("DDZ_SEAT_FA", "（农民）"))
	return who


func _cards_text(cards: Array) -> String:
	var parts: Array[String] = []
	for c in cards:
		parts.append(R.label_of(int(c)))
	return " ".join(parts)


func _push(line: String) -> void:
	_feed.append(line)
	if _feed.size() > 80:
		_feed = _feed.slice(_feed.size() - 80)


## 字体：走与 Label **同一条**解析路径（工程没有 .ttf，全靠引擎默认字体）。
func _font() -> Font:
	var f := get_theme_default_font()
	return f if f != null else ThemeDB.fallback_font


func _draw_text(pos: Vector2, text: String, px: int, col: Color) -> void:
	draw_string(_font(), pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT.s(px), col)
