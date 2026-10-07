extends Node3D
## 舰船建模方向姿势确认工具（红线 47 工具 2.0）
##
## ═══════════════════════════════════════════════════════════════════
##  6 个视图（**用户定义 28 轮定案**：轴名 = 视图名）
## ═══════════════════════════════════════════════════════════════════
##  每根轴的 **红球端 = 该视图在船上的指向**：
##      主视图    红球 = 舰艏  →  模型空间 +Z
##      后视图    红球 = 船尾  →  模型空间 -Z
##      左视图    红球 = 船左  →  模型空间 -X
##      右视图    红球 = 船右  →  模型空间 +X
##      俯视图    红球 = 船背  →  模型空间 +Y
##      底视图    红球 = 船腹  →  模型空间 -Y
##
##  ═══════════════════════════════════════════════════════════════════
##  两个**互相独立**的旋转自由度（29 轮新增 · 32 轮改键位）
## ═══════════════════════════════════════════════════════════════════
##  ① 轴体旋转（裸 **W/S** 绕 X · **A/D** 绕 Y；`Q/E` 平移中心）—— 只动轴体
##  ② 舰船旋转（**按住 Shift + W/A/S/D/Q/E**；另可右键拖动）—— 只动船
##  键位是"直觉方向键"（32 轮按用户要求）：
##      Shift + **W** = 舰艏**向上**抬（绕 X −）   Shift + **S** = 舰艏**向下**压（绕 X +）
##      Shift + **A** = 向左转（绕 Y −，人前后转）Shift + **D** = 向右转（绕 Y +）
##      Shift + **Q/E** = **侧躺**翻转（绕 Z）
##  为什么两个都要：EVE 里既有"横着飞"的船（爆发级）也有"竖着飞"的船
##  （弥尔米顿），轴体只能表达"船相对世界怎么摆"，无法表达"船自己怎么躺"。
##  真值落表时两者合成：bow_model = R_ship⁻¹ · R_axis · VIEW_AXES[0]
##  （用户把红球对到屏幕上的舰艏 ⇒ R_axis·视图轴 = R_ship·舰艏模型轴）
##
##  ⚠️ 键盘读 `physical_keycode` 而**不是** `keycode`：按住 Shift 时 keycode
##     会变成 {}<>_+ 符号码，match 全部落空 ⇒ 转船"按了没反应"（29 轮踩过）。
##
##  ═══════════════════════════════════════════════════════════════════
##  轴体方向"定死"（31 轮）—— 只有鼠标压在某根轴上时那根轴才可动
## ═══════════════════════════════════════════════════════════════════
##  用户的诉求是「把轴体的方向定死，除非我鼠标移动到上面」。落实为两条闸门：
##   ① **整组旋转**（裸 `W/S/A/D` / `R`）会改变**所有 6 根轴的方向**，
##      所以必须**鼠标正压在任一轴体上**才允许执行；否则完全无响应。
##   ② **单根轴缩放**（`1~6`）只作用于**鼠标当前悬停的那一根**，
##      悬停别的轴 / 没悬停都没反应；原先"1 缩放主视图、2 缩放后视图"的
##      固定编号映射**已废弃**（那正是"轴体会自己变"的来源之一）。
##  ⚠️ **转船（Shift）不受闸门限制**——船的姿态本来就该随时能调。
##  平移（`Q/E`）与整组缩放（滚轮）**保持全局**——它们不改方向，只挪位置/大小。
##  判定真源 = `_mouse_screen_pos`（鼠标**当前位置**，不是"上次移动事件的位置"；
##  拖动镜头时鼠标不动也要能判对）。
##
##  右侧面板 = 舰船选择：**列全库 52 艘**（显示**中文名**），顶部可搜索，点一行即切船。
##
##  用法：
##    ① 工具启动 → 6 根轴初始位置 = 模型 ±X/±Y/±Z
##    ② 右侧面板选船（中文名 / 英文名 / id 都能搜）
##    ③ 用 `Q/E` 移动轴中心点、滚轮整组缩放、`1~6` 单杆缩放、`R` 重置
##    ④ **主视图红球** 拖到舰艏所在端（用键盘平移 + 缩放）
##    ⑤ **俯视图红球** 拖到船背所在端
##    ⑥ 按 **回车**（或点"确定"按钮）→ 落进 SHIP_AXES，自动跳下一艘
##    ⑦ ← / → 翻艘（保留中心点和缩放，方便对比同姿态船）
##
##  特殊船（横飞 / 竖飞）怎么处理：
##    EVE 里船有横着飞的（爆发级）、竖着飞的（弥尔米顿），它们的"自然躺法"
##    不是 up=+Y。此时先把 **船本身** 转到你认可的姿势，再对准轴体：
##      · Shift + **W / S**  →  绕 **X**（舰艏上仰 / 下俯）
##      · Shift + **A / D**  →  绕 **Y**（向左 / 向右转，人前后转）
##      · Shift + **Q / E**  →  绕 **Z**（侧躺翻转）
##      · 右键拖动           →  水平转 Y、垂直转 X
##    ⚠️ **不按 Shift 转不动船**（默认行为是转轴体）——这是刻意设计，
##       防止误操作把船碰歪；两条通路（Shift 键盘 / 右键拖动）都只动船。
##    轴体在转船时**不动**（两者独立）；点确定时工具会自动把船姿反解扣除，
##    落表的仍是**模型空间**语义轴（bow:/up:），与船的摆放姿势无关。
##
##  落表：把"红球端指向的模型轴向"作为 bow/up 的字符串写进 SHIP_AXES。
##       「舰艏 = 主视图红球指向的模型轴向」+「船背 = 俯视图红球指向的模型轴向」。
##       例如：主视图红球指向模型 -X 端、俯视图红球指向模型 +Z 端
##       ⇒ SHIP_AXES[id] = "bow:-X up:+Z"（带符号 = 视图的"+端"对应哪个模型轴）
##
##  跑法（交互工具不要加 --headless，也不要加 --quit-after）：
##    "C:/godot/Godot_v4.7.1-stable_win64.exe" \
##      --path "F:/evezzq/eve自走棋918" res://tools/probe_bow_box.tscn -- --ids=burst,myrmidon
##    不给 --ids = 全库 52 艘。
##  结果：写入 user://bow_calib/ship_axes.json；每次按确定追加一条并自动跳下一艘。

const YAW := preload("res://scripts/data/eve_ship_yaw.gd")
const INDEX := preload("res://scripts/data/eve_ship_asset_index.gd")
## ★ 49 轮：生产视觉脚本 —— **工具与实机唯一的同步点**。
##   `load()` 不是常量表达式 ⇒ 只能用 `var`（用 `const` 会 Parse Error）。
##   ⚠️ 静态函数必须走 `.call("fn", args)`（直接 `.fn(args)` 会被解释成
##      "调一个名叫 args 的函数"，实测报 `Nonexistent function 'bantam'`）。
var EVE_VISUAL: Variant = load("res://scripts/visual/eve_ship_visual.gd")

## 6 根视图轴的"含义"——**红球 = 该视图**，蓝球 = 反方向
## 顺序：主/后/左/右/俯/底（每根独立一根杆，**没有 ± 之分**——红球就在该视图端）
const VIEW_NAMES: PackedStringArray = ["主视图", "后视图", "左视图", "右视图", "俯视图", "底视图"]
## ⚠️⚠️ 53 轮：**"左/右"这两根的文字改成中性，不再写"船左/船右"** ⚠️⚠️
##
##  原因（用户 53 轮问「左右是怎么定的？按船头看船尾还是船尾看船头？」）：
##
##  ① 工具的 `VIEW_AXES` 是**固定**的：`左视图 = −X`、`右视图 = +X`。
##     它是按"**站在船头前方、朝船尾看**（面对船头）时你画面的左右"定的 ——
##     而这**与船自身的左右相反**：你面对船头时，船的右舷出现在你画面**左**边
##     （就像面对面对坐的人，他的右手在你左边）。
##
##  ② 更要紧的是：**"船的右舷"根本不是一根固定轴**。
##     系统的约定是 `side = bow × up`（`EveShipYawTable.side_axis()`，纯派生），
##     被 `_make_align` 送到世界 +X（屏幕右）。实测：
##         abaddon  bow=+Z up=+Y ⇒ side = **−X** （右舷在 −X）
##         burst    bow=−Z up=+Y ⇒ side = **+X** （右舷在 +X）
##     ⇒ **bow 一变，右舷就换轴**。而 52 艘里有 17 艘是 `bow:-Z` ——
##       对这些船，把 −X 标成"船左"是**反的**（那是它们的右舷）。
##
##  ⇒ 结论：**不要写"船左/船右"，写模型轴**。轴向永远对，左右会随 bow 翻。
##     判读船头/船背请认准 #1 主视图 与 #5 俯视图（落表只用这两根）。
const VIEW_DEFINITIONS: PackedStringArray = [
	"舰艏方向", "船尾方向", "模型-X端", "模型+X端", "船背方向", "船腹方向",
]
## 6 根视图轴 = 模型空间 +X / -X / -Z / +Z / +Y / -Y
## （按"主视图=舰艏指向+玩家在主视图反方向看舰艏"推：玩家在 -Z 看 +Z）
## 但**红球端 = 该视图**。所以主视图红球在 +Z，后视图红球在 -Z，etc.
const VIEW_AXES: Array[Vector3] = [
	Vector3(0, 0, 1),    # 主视图  红球 = 舰艏
	Vector3(0, 0, -1),   # 后视图  红球 = 船尾
	Vector3(-1, 0, 0),   # 左视图  红球 = 船左
	Vector3(1, 0, 0),    # 右视图  红球 = 船右
	Vector3(0, 1, 0),    # 俯视图  红球 = 船背
	Vector3(0, -1, 0),   # 底视图  红球 = 船腹
]

const ROD_BASE := 0.62
const ROD_THICK := 0.012
## ★41 轮：世界方向锚（见 `_build_world_anchor`）。
## ⚠️ 尺寸是**实测调出来的**：太大 ⇒ 俯视机位下标记端点飞出屏幕（实测 (960,-102) 出屏）；
##    太小 ⇒ 与六轴混在一起分不清。取「略大于六轴」= 1.05 / 0.014。
const ANCHOR_LEN := 1.05
const ANCHOR_THICK := 0.014
const BALL_R := 0.04

var _ids: PackedStringArray = PackedStringArray()
var _idx: int = 0
## ⚠️ 33 轮：`_group_yaw/_group_pitch/_group_roll` **已删除**——
## 那是"整组旋转"，一转就六根全转。现在方向按根存在 `_axis_dirs` 数组里。
## `_axis_root` 只承担**整组平移 + 整组缩放**（都不改方向）。

## 舰船自身姿态（**与轴体完全独立**，Shift + 同键控制）
## EVE 里船有横飞/竖飞，轴体表达不了"船自己怎么躺"，必须能单独转船。
var _ship_yaw: float = 0.0
var _ship_pitch: float = 0.0
var _ship_roll: float = 0.0
## 归一化基准变换（AABB 居中 + 缩放到单位长度），船旋转叠加在其之上
var _ship_norm: Transform3D = Transform3D.IDENTITY

## 舰船与轴体必须挂在同一个中性舞台的两个兄弟节点下：
## 舰船只接受自身模型归一化变换；轴体只接受标定者的平移/旋转/缩放。
var _stage: Node3D = null
var _holder: Node3D = null
var _axis_root: Node3D = null
var _axis_scales: Array[float] = []
var _axis_centers: Array[Vector3] = []
## ★ **每根轴各自的方向**（33 轮：从"整组旋转"改成"单根独立旋转"）。
## 旧版用一份 `_group_yaw/_group_pitch/_group_roll` 转整个 `_axis_root`，
## 结果"转一根、六根全转"——用户明确指出这不对。
## 现在每根杆的**朝向**独立存一份：第 i 项 = 第 i 根轴的当前指向（单位向量）。
## `_ax_dir[i]` 初值 = `VIEW_AXES[i]`（±X/±Y/±Z），转只改选中那一项。
var _axis_dirs: Array[Vector3] = []
var _axis_labels: Array[Label3D] = []
var _hover_axis: int = -1
## 鼠标最近的屏幕位置（每帧刷新）。用它判"鼠标是否压在轴体上"，
## 而不是只信 InputEventMouseMotion——键盘操作时鼠标不移动，位置仍是有效的。
var _mouse_screen_pos: Vector2 = Vector2(-9999, -9999)
var _mouse_in_view: bool = false
## ★ 42 轮：自检注入鼠标时的锁 —— 防止 `_process` 用真实鼠标位置覆盖注入值。
##   （非无头窗口下，注入值会被真实鼠标瞬间冲掉 ⇒ GATE 自检必然 FAIL 2。
##     这是 41 轮潜伏的坑：自检只被无头跑过，从未暴露。）
var _mouse_inject_lock: bool = false
## 上一帧鼠标是否压在轴体上（用于 HUD 提示去重，避免每帧重排文本）
var _last_hover_valid: bool = false
var _drag_axis: int = -1
var _drag_endpoint: int = -1 # -1=拖轴体，0=红球端，1=蓝球端
var _drag_plane: Plane = Plane(Vector3.FORWARD, 0.0)
## 右键拖动 = 转舰船（与左键拖镜头分开）
var _ship_dragging: bool = false
var _drag_start_local: Vector3 = Vector3.ZERO
var _drag_start_center: Vector3 = Vector3.ZERO
var _drag_start_scale: float = 1.0
var _hud: Label = null
var _help: Label = null
var _confirm_btn: Button = null
## ★ 34 轮：**已固定清单**（`user://bow_calib/fixed.json` 的内存镜像）。
## key = asset id，value = {"bow":..., "up":...}。
## 用途：① 切船后 HUD / 列表能标出"这艘已经标过了"；
##      ② 用户"按下回车到底存没存"有了**可见凭证**，不用去翻 JSON 文件。
var _fixed_ships: Dictionary = {}
## ★ 36 轮：**姿势表**（`user://bow_calib/pose_table.json` 的内存镜像）。
## `{id: {"bow":"+X","up":"+Y","at":"..."}}`。
## 列表 `√` **只由它驱动** —— 用户按回车成功保存才写入，进工具时是空的。
var _pose_table: Dictionary = {}
## ★ 36 轮：本次启动把姿势表合并进源码的结果（HUD 开头显示一行摘要）
var _flush_report: String = ""
## ★ 35 轮：当前船在**游戏规则表源码**里登记的 `"bow:… up:…"` 原文。
## 用途 = HUD 直接显示"表内现值"，用户一眼看出"我改了、表也变了"。
var _table_bow_raw: String = ""
## ★ 37 轮：上一次 `_apply_axis_dirs_from_table()` 的还原说明（HUD 显示去哪了）。
## 例：`轴体已按【姿势表】还原：bow:-X up:+Z`。
## 用户"点回去看姿势对不对"时，这一行直接告诉他轴体是从哪份数据摆出来的。
var _axis_restore_note: String = ""
## ★ 40 轮：启动时旧姿势表被归档的文件名（HUD 显示，用户能看到"旧表去哪了"）。
var _archive_note: String = ""
## ★ 40 轮：**锚点自检**结果 —— 用已知真值船反证"轴体显示方向 = 游戏方向"。
## 用户裁决「我不信你的判断」⇒ 不再让工具自己说"我对"，而是**拿一艘已确认的船当场对账**：
##   `catalyst`（促进级）用户 2026-09-26 亲口确认 `AXIS_REMAP="-X,+Y,-Z"` + 不 FLIP 是对的
##   ⇒ 它必须显示「舰艏世界方向 = −Z = 朝敌 ✅」。若显示成 +Z，说明映射链又漂了。
var _anchor_report: String = ""
## ★ 35 轮：`SHIP_AXES` 源码块里已登记的 id 集合（列表 ✔ 用）。
## 一次读文件建缓存，避免列表刷新时读 52 次文件。
var _source_table_cache: Dictionary = {}
## ★ 35 轮：**运行期覆盖侧表**（`{id: "bow:… up:…"}`）。
## 为什么需要：`YAW.SHIP_AXES` 是 `const`，运行时改不了（会 Parse Error）。
## 所以"刚标完即时生效"只能靠这张侧表；游戏侧真生效 = 源码 + `--import` + 重启。
var _runtime_axes_override: Dictionary = {}
var _root_pos: Vector3 = Vector3.ZERO
var _root_scale: float = 1.0
var _cam_orbit: Node3D = null
var _orbit_state: _OrbitState = null

## ── 右侧舰船选择列表 ──────────────────────────────────────────
## **与 --ids 无关**：列表永远列出全库 52 艘（用户要求"把所有舰船都加入备选"），
## 选中即切换到该船（等价于把 _idx 指到它在 _ids 里的位置；不在 _ids 里则追加）。
var _ship_panel: PanelContainer = null
var _ship_list: ItemList = null
var _ship_search: LineEdit = null
## 列表行 → 舰船 id 的映射（过滤后行号会压缩，不能直接用行号索引 _ids）
var _list_ids: PackedStringArray = PackedStringArray()
var _cur_sid: String = ""


func _ready() -> void:
	# ── `--print-labels`：不开 GUI 也能确认六根轴的标签文字 ──
	#   53 轮加。用途：① 改标签格式后**实测**验证（不靠推理）；
	#   ② 用户怀疑"某根杆的标签标错了"时，一条命令把六根的文字打出来核对。
	#   ⚠️ 必须在 `_axis_dirs` 填好之后才能打（它要用 `_axis_name(_axis_dirs[i])`）。
	var _want_labels := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--ids="):
			_ids = a.substr(6).split(",")
		elif a == "--print-labels":
			_want_labels = true
		elif a == "--raw":
			RAW_POSE = true
	if _ids.is_empty():
		for s in INDEX.all():
			_ids.append(String(s.id))
	_axis_scales = [1.0, 1.0, 1.0, 1.0, 1.0, 1.0]
	_axis_centers.clear()
	_axis_dirs.clear()
	for a in VIEW_AXES:
		# ★ 38 轮：**六根轴共原点**（中心一律 `Vector3.ZERO`）。
		#
		#   旧式 `a * (ROD_BASE * 0.5)` 把每根轴的中心偏到自己半长处，
		#   默认姿势下"杆的一端恰好在原点"，看着像六向发散 —— 但那是**巧合**：
		#   一旦方向被改成别的正交轴（如 bow:-X up:+Z），中心偏移却留着老值，
		#   六根杆就**整体飘开、彼此错位** ⇒ 用户看到的「几个轴围成一圈，
		#   这样我怎么看方向啊」（38 轮原话）。
		#   ⇒ 正确做法：**中心恒为原点，方向才是唯一变量**，
		#     这样无论怎么转都是"从同一中心向两端伸"，永远一眼可读。
		_axis_centers.append(Vector3.ZERO)
		_axis_dirs.append(a.normalized())

	if _want_labels:
		print("══════════════════════════════════════════════════════════")
		print("  六根轴体的标签文字（`--print-labels`，初始姿势）")
		print("══════════════════════════════════════════════════════════")
		for i in VIEW_AXES.size():
			print("  %s" % _label_text_for(i).replace("\n", "  ｜  "))
		print("")
		print("  ★ 判读：红球端 = 该视图方向 = 标签所在端；蓝球端是反方向。")
		print("    `#n` 对应键盘 `1~6`（悬停 + 缩放这一根）。")
		get_tree().quit()
		return

	# 场景
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.04, 0.05, 0.07)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.60, 0.68)
	e.ambient_light_energy = 1.10
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	add_child(env)

	var key := DirectionalLight3D.new()
	key.light_energy = 1.6
	key.rotation_degrees = Vector3(-36, -126, 0)
	add_child(key)
	var rim := DirectionalLight3D.new()
	rim.light_energy = 0.5
	rim.rotation_degrees = Vector3(-12, 64, 0)
	add_child(rim)

	# 中性舞台：绝不把轴体作为舰船的父节点，也不让两者共享可变 Transform3D。
	_stage = Node3D.new()
	_stage.name = "CalibrationStage"
	add_child(_stage)
	_holder = Node3D.new()
	_holder.name = "ShipFixedRoot"
	_stage.add_child(_holder)
	_axis_root = Node3D.new()
	_axis_root.name = "IndependentAxisRoot"
	_stage.add_child(_axis_root)
	# ═══ ★41 轮根因修复：**给画面加一个绝不会动的方向锚** ═══════════════
	#
	# ── 为什么必须有 ─────────────────────────────────────────────
	# 41 轮查明：工具内部算的**全对**（52 艘轴体世界方向都是 −Z = 朝敌；
	#   切船→按回车落表严格等于原值），但用户连标 52 艘却全部标成 `+Z`。
	#   差的整好是一个 180° ⇒ **用户在屏幕上分不清哪边是世界 −Z**。
	#
	# ── 为什么分不清（真病根）────────────────────────────────────
	#   相机初始 `yaw=0.6rad(≈34°) · pitch=0.25rad(≈14°)` = **右前方偏上**看。
	#   该机位下（41 轮实测 unproject 数据）：
	#       世界 −Z 端 → 屏幕 (1276, 425)，偏右上、远离船
	#       世界 +Z 端 → 屏幕 (-54, 907)，**出屏**
	#   ⇒ 旧画面里**没有任何世界方向基准**：无地面、无网格、无轴线、无敌我标。
	#     唯一能猜的线索是"近大远小"，而这跟"船头该朝哪"毫无关系
	#     ⇒ 只能靠猜，猜错 = 整批 180°。
	#
	# ── 修法 ─────────────────────────────────────────────────────
	#   加一组**固定不随相机/船/轴转动**的参照物（挂在 `_stage`，是
	#   `_axis_root` / `_holder` 的兄弟 ⇒ 转轴转船转相机都不会带动它）：
	#     ① 世界 −Z 方向的**敌人箭头 + 标牌**（亮红、最粗、带字）
	#     ② 世界 +Z 方向的**我方箭头 + 标牌**（暗蓝、细、带字）
	#     ③ XZ 平面**网格**（给"水平面"一个直观参照，也让相机仰角可读）
	#   ⚠️ 尺寸取「略大于六轴」（1.05 vs 0.62）——实测过：1.55 时俯视机位
	#     两端都飞出屏幕（(960,-102) / (960,1365)），等于没加。
	_build_world_anchor()
	for i in VIEW_AXES.size():
		var a: Vector3 = VIEW_AXES[i]
		var rod := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(ROD_THICK, ROD_THICK, 1.0)
		rod.mesh = bm
		rod.material_override = _mat(Color(0.78, 0.80, 0.86))
		rod.name = "Rod_%d_%s" % [i, VIEW_NAMES[i]]
		_axis_root.add_child(rod)
		# 杆/球/文字的位置与朝向全部由 `_refresh_axis_visual()` 按
		# `_axis_dirs[i]` 逐根设置（每根独立，互不影响）
		#
		# ⚠️⚠️ 41 轮惨案：**球必须取名字、不许按下标猜**。
		#   旧实现（直到 40 轮）是：
		#       b_plus = rod.get_parent().get_child(rod.get_index() + 1)
		#   它假设"红球 / 蓝球紧跟在杆后面"。但 Node 的子节点**按名字排序**，
		#   而球当时**没有名字**（默认 `MeshInstance3D` / `MeshInstance3D2`…），
		#   字典序里 `MeshInstance3D` **排在 `Rod_*` 前面** ⇒ 球实际在杆**之前**，
		#   `+1` 取到的是**下一根杆**（或 label），**红蓝球从建成起就没跟着轴走过**。
		#   后果：用户看到的"红球位置"和 `_axis_dirs[i]` 的正负号**完全脱钩**
		#   ⇒ 41 轮用户连标 52 艘，全部按"看到红球在哪"落表，
		#     而工具内部认为的方向其实相反 ⇒ 落盘后 **52 艘全部背敌**。
		#   ⚠️ 这个 bug **不报错**：球还在画面上、只是位置错 ⇒ 谁看都"挺正常"。
		#   ⇒ 现在一律 `get_node(<名字>)`，名字里带 i 与 +/−，绝不依赖兄弟顺序。
		var ball_plus := _ball(Vector3.ZERO, Color(0.95, 0.16, 0.16))
		ball_plus.name = "Ball_%d_%s_plus" % [i, VIEW_NAMES[i]]
		_axis_root.add_child(ball_plus)
		var ball_minus := _ball(Vector3.ZERO, Color(0.16, 0.38, 0.98))
		ball_minus.name = "Ball_%d_%s_minus" % [i, VIEW_NAMES[i]]
		_axis_root.add_child(ball_minus)
		var axis_label := _make_axis_label(i)
		_axis_root.add_child(axis_label)
		_axis_labels.append(axis_label)

	_cam_orbit = _build_orbit_camera()
	add_child(_cam_orbit)
	_orbit_state = _cam_orbit.get_meta("orbit_state")

	# HUD（左侧信息栏）
	_hud = Label.new()
	_hud.add_theme_color_override("font_color", Color(0.92, 0.95, 1.0))
	_hud.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_hud.add_theme_constant_override("outline_size", 4)
	_hud.position = Vector2(20, 16)
	add_child(_hud)
	_help = Label.new()
	_help.add_theme_color_override("font_color", Color(0.65, 0.70, 0.80))
	_help.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_help.add_theme_constant_override("outline_size", 4)
	_help.position = Vector2(20, 700)
	_help.custom_minimum_size = Vector2(660, 0)
	_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_help)

	# ★★★ 41 轮核心修正：**瞄准准星**（挂在所有 3D 与 UI 之上，mouse_filter=IGNORE）
	#   41 轮 52 艘全标反的真病根 = 用户"以为在拖方向锚，实际在转轴"（两者屏幕距 2px、同色）。
	#   准星把"鼠标此刻会命中谁"直接写在屏幕上 ⇒ 用户不再靠记忆猜。
	#   ⚠️ 必须在 `_help`/面板之后 add_child ⇒ 保证它画在最上层。
	_build_aim_reticle()

	# 确定按钮
	_confirm_btn = Button.new()
	_confirm_btn.text = "✓  确定（回车）"
	_confirm_btn.position = Vector2(20, 620)
	_confirm_btn.size = Vector2(200, 40)
	_confirm_btn.pressed.connect(_on_confirm_pressed)
	add_child(_confirm_btn)

	# 右侧舰船选择面板（列全库 52 艘，与 --ids 无关）
	_build_ship_panel()
	# ★ 36 轮：**只清本次会话的临时 √**；持久凭证改由**姿势表**驱动（43 轮修正）。
	#
	# ── 43 轮用户报的 bug ─────────────────────────────────────────
	# 「我刚才修改完了列表里所有船的方向，然后我关闭窗口，再重新打开工具，
	#   修改过的船全部回到默认姿势，请问我真的有修改吗？」
	#   ⇒ 数据**全部保存成功**（`pose_table.json` 里 52 艘、时间戳 16:48~16:56），
	#     但**界面把"已登记"这件事整个忘光了**：
	#       ① 列表 √ 只读 `_fixed_ships`，而它每次启动都被这里清空
	#          ⇒ 重开后 52 艘**一个 √ 都没有**，用户以为白改了；
	#       ② 选中哪艘由 `_ids` 列表指针决定，不持久化 ⇒ 重开永远落在第一艘。
	#   ⇒ 用户看到的就是「全部回到默认姿势」。
	#
	# ⚠️ 用户 36 轮原话「只有按回车才打√」在**同一会话内**依然成立（临时 √ 仍清空）；
	#    但"我这艘到底标过没有"是**跨会话**的问题，答案唯一来源 = `pose_table.json`。
	#    两者不冲突：`_fixed_ships` = 本次会话刚按的回车，`_pose_table` = 历史全部凭证。
	#    列表渲染已改为 **`_pose_table.has()` 优先**（见 `_refresh_ship_list`），
	#    这样"打过 √ 的船"重开工具后**依然是 √** —— 这才是用户要的"我改了就是改了"。
	_fixed_ships = {}
	# ★ 36 轮：启动时把**姿势表**里攒下的标定结果合并进游戏规则表源码。
	#   这就是用户说的「等下次重启的时候再写进游戏」。
	#   ⚠️ 自检模式下**不落盘**（自检会反复启停，不该动游戏源码）。
	#   ⚠️⚠️ 38 轮：**默认也不落盘**（用户选择「先别落盘，我要逐个复核」）。
	#     ⇒ 只有显式传 `--flush` 才写游戏源码；否则只**报告**将要写什么。
	#     这是"未经用户确认不许改游戏源码"的闸门。
	var argv := OS.get_cmdline_user_args()
	if not ("--self-test" in argv):
		# ═══ 42 轮重大修正：**默认不再清空姿势表** ═════════════════════
		#
		# ── 为什么必须改 ─────────────────────────────────────────────
		#   40 轮设了"启动即清空"（当时用户裁决「全部作废、我重标」）——
		#   那是**一次性**的作废动作。但它被写成了**每次启动都执行**：
		#   42 轮实测事故：我为了验证改动拉起一次窗口 ⇒
		#   用户 16:12/16:13 刚标好的 `bantam`/`condor` **当场被归档、表被清空**
		#   （幸好归档是**改名不删**，数据已从
		#    `pose_table.作废-20260927 161442.json` 完整恢复）。
		#   ⇒ "一次性动作"写成"每次启动"= **每次启动毁一次用户劳动**，
		#     而且**不报错**（用户只会发现"我标的船怎么又没了"）。
		#   —— 这与红线 47g（自检毁数据）是同一类，只是换了个触发口。
		#
		# ── 新口径 ──────────────────────────────────────────────────
		#   · **默认**：`_load_pose_table()` ⇒ 保留用户已有标定，HUD 显示登记数
		#   · **`--wipe`**：显式要求作废时才归档 + 清空（作废仍然**只改名不删**）
		#   · **`--keep-pose`**：保留（现在与默认行为一致，保留只为兼容旧命令行）
		#   · **`--flush`**：落盘进游戏源码（仍需显式传，见 38 轮口径）
		#   ⇒ 用户"推倒重来"的入口改为 **Ctrl+Delete（当场清空）** 或 `--wipe`，
		#     两者都是**显式**动作，绝不会因为"打开工具看一眼"而丢数据。
		_load_pose_table()
		# ⚠️ 判定走 `_should_wipe_pose_table()` —— 与自检**同源**（红线 40）：
		#   自检断言"默认命令行不清空、--wipe 才清空"，测的就是这个函数。
		if _should_wipe_pose_table(argv):
			var moved := _archive_pose_table()   # 内部会写 `_archive_note`（HUD 显示用）
			_pose_table = {}
			_fixed_ships = {}
			_save_pose_table()
			_flush_report = "已按 `--wipe` 作废并清空姿势表（旧表已归档：%s，**没有删**）" % (moved if moved != "" else "（无旧表）")
		else:
			_flush_report = "姿势表已载入（%d 艘登记）· 未落盘 · 要作废请用 `--wipe` 或 Ctrl+Delete" % _pose_table.size()
		if "--flush" in argv:
			var rep := _flush_pose_table_to_source()
			_flush_report += "\n启动落盘：改写 %d 行 · 已一致 %d 行" % [int(rep["written"]), int(rep["skipped"])]
			var blk: Array = rep.get("blocked", [])
			if blk.size() > 0:
				_flush_report += " · ⛔FLIP冲突跳过 %d（%s）" % [blk.size(), ", ".join(blk)]
			var failed: Array = rep["failed"]
			if failed.size() > 0:
				_flush_report += " · 失败 %d（%s）" % [failed.size(), ", ".join(failed)]
	else:
		# ⚠️⚠️ 41 轮修正：**自检模式绝对不许动姿势表**。
		#   旧版这里只写了"未落盘"，但**没有拦住上面的"启动即清空"分支** ——
		#   实测：跑一次  就把用户的 52 艘标定结果清成了 ，
		#   而且**照样打 PASS**（自检只查自己的断言，不查"有没有毁掉用户数据"）。
		#   ⇒ 自检必须**只读**：只 load 到内存，绝不写盘、绝不归档、绝不清空。
		#   ⚠️ 这类"测试把用户数据冲了"的问题**不报错**，是最难发现的一类。
		_load_pose_table()
		_flush_report = "（自检模式：只读，未落盘、未清空、未归档）"

	_load_current()
	_apply_axis_root_transform()
	_apply_orbit()
	_refresh_axis_visual()
	# ★ 40 轮：启动就对账一次（拿用户已确认的船反证映射链，不靠工具自证）
	_run_anchor_check()
	_refresh_hud()

	# 仅在显式请求时执行截图自检；交互启动必须保持窗口不退出。
	if "--self-test" in OS.get_cmdline_user_args():
		_run_math_self_test()
		# ★ 42 轮：自检断言跑完 ⇒ 解开鼠标注入锁，再截图
		#   （截图要反映"真实鼠标位置"下的准星文字，不能停在注入点上）。
		_release_mouse()
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		_save_view("default")
		get_tree().quit(0)


## 无头数学自检（不依赖渲染）：验证"轴体旋转 ⊗ 舰船旋转"的反解是恒等。
## 判据：设用户真实想标的模型轴是 target（例如 bow=+X、up=+Y）。
##   ① 船被转成 R_ship（任意）；
##   ② 用户把轴体转到"屏幕上红球压住舰艏" ⇒ R_axis = R_ship · R_extra，
##      其中 R_extra 必须满足 R_extra·VIEW_AXES[0] == target_bow；
##   ③ 此时 _on_confirm_pressed 的 rot = R_ship⁻¹·R_axis = R_extra，
##      算出的 bow 必须回到 target_bow（与 R_ship 无关）。
func _run_math_self_test() -> void:
	var cases: Array = [
		[Basis.IDENTITY, Vector3(1, 0, 0), Vector3(0, 1, 0)],
		[Basis.from_euler(Vector3(0.4, 0.0, 0.0)), Vector3(1, 0, 0), Vector3(0, 1, 0)],
		[Basis.from_euler(Vector3(0.0, deg_to_rad(90.0), 0.0)), Vector3(0, 0, 1), Vector3(0, 1, 0)],
		[Basis.from_euler(Vector3(0.3, 0.2, -0.1)), Vector3(-1, 0, 0), Vector3(0, 0, 1)],
	]
	var fails := 0
	for c in cases:
		var r_ship: Basis = c[0]
		var target_bow: Vector3 = c[1]
		var target_up: Vector3 = c[2]
		# 造一个 R_extra：把 VIEW_AXES[0](+Z) 转到 target_bow 的最小旋转
		var r_extra := _basis_from_to(VIEW_AXES[0], target_bow)
		var r_axis := r_ship * r_extra
		var rot := r_ship.inverse() * r_axis
		var got_bow := _project_to_axis((rot * VIEW_AXES[0]).normalized())
		var got_up := _project_to_axis((rot * VIEW_AXES[4]).normalized())
		if got_bow.distance_to(target_bow) > 0.001:
			fails += 1
			push_error("[selftest] bow 反解偏差 got=%s want=%s" % [str(got_bow), str(target_bow)])
		# up 判据只在 target_up ⊥ VIEW_AXES[4] 时严格（这里用 r_extra 同时携带 up 不可行，故仅记信息）
		if absf(got_up.dot(target_bow)) > 0.99:
			fails += 1
			push_error("[selftest] up 与 bow 共线 got=%s" % str(got_up))
	# ★ 33 轮补充：把「逐根独立转」和「落表」串起来端到端验一遍。
	#   用户手工操作的路径是 `裸键转某一根` → `点确定落表`，旧公式自检只测了数学，
	#   没测"按根存的方向数组真的喂进了落表函数"，所以这里直接走 _on_confirm_pressed 的
	#   取值表达式，断言：把第 0 根从 +Z 转到 +X 后，落表算出的 bow 就是 +X。
	fails += _run_confirm_path_check()
	var total := cases.size() + 1
	if fails == 0:
		print("[probe_bow_box] MATH SELF-TEST PASS %d/%d（船姿可独立旋转且落表自洽）" % [total, total])
	else:
		print("[probe_bow_box] MATH SELF-TEST FAIL %d/%d" % [fails, total])
	_run_key_self_test()


## 33 轮补充自检：**逐根独立转 ⇒ 落表** 的端到端通路。
## 做法：把船姿置为已知 R_ship，用 `_rotate_single_axis` 把第 0 根转到目标朝向，
## 然后按 `_on_confirm_pressed` 的取值表达式算 bow/up，断言等于预期。
## 为什么必须测：`_on_confirm_pressed` 如果读错数组（比如回退成全局 VIEW_AXES），
## 数学自检照样全过，但用户拿到的标定结果全是错的——且**不报错**。
func _run_confirm_path_check() -> int:
	var fails := 0
	# R_ship = 绕 Y 转 37°，模拟用户先把船歪着放
	_ship_yaw = deg_to_rad(37.0)
	_ship_pitch = 0.0
	_ship_roll = 0.0
	# 第 0 根：+Z → +X
	# ⚠️ Godot 的 `Basis.from_euler` 绕 Y 转 **+90°** 才把 +Z 送到 +X，
	#    （-90° 送到的是一 X，实测算过：Ry(90)·(0,0,1)=(1,0,0)、Ry(-90)·(0,0,1)=(-1,0,0)）
	#    自检第一版写成 -PI/2，于是期望值也跟着错 ⇒ 修判据时两边一起对齐。
	_axis_dirs[0] = Vector3(0, 0, 1)
	_axis_dirs[4] = Vector3(0, 1, 0)
	_rotate_single_axis(0, 0.0, PI * 0.5, 0.0)   # +Z → +X（绕 Y 正向）
	# 期望：舰艏模型轴 = R_ship⁻¹ · (世界 +X) —— 也就是"屏幕上 +X 方向"反解回模型空间
	var bow_before := _project_to_axis(_axis_dir_in_model(0))
	var expect_bow := _project_to_axis(_ship_rotation().inverse() * Vector3(1, 0, 0))
	if bow_before.distance_to(expect_bow) > 0.001:
		fails += 1
		push_error("[selftest] 落表通路：bow got=%s want=%s" % [str(bow_before), str(expect_bow)])
	# 关键断言：落表取的必须是**按根存的方向**，不是全局 VIEW_AXES[0](+Z)
	# —— 若读成全局，`_axis_dirs[0]` 仍是 +Z ⇒ Ry(37°)⁻¹·(+Z) = (-0.60, 0, +0.80)，
	#    而正确实现给的是 Ry(37°)⁻¹·(+X) = (+0.80, 0, +0.60)，两者不等 ⇒ 能区分。
	if bow_before.distance_to(_project_to_axis(_ship_rotation().inverse() * Vector3(0, 0, 1))) < 0.001:
		fails += 1
		push_error("[selftest] 落表仍读全局 VIEW_AXES（33 轮回归！）")
	# 第 1 根（后视图，-Z）没动过 ⇒ 反解后必须仍是 R_ship⁻¹·(-Z)，而不是裸 -Z
	var expect_back := _project_to_axis(_ship_rotation().inverse() * Vector3(0, 0, -1))
	if _project_to_axis(_axis_dir_in_model(1)).distance_to(expect_back) > 0.001:
		fails += 1
		push_error("[selftest] 未操作的第 1 根方向被污染 got=%s" % str(_axis_dir_in_model(1)))
	# 收尾：复位，别污染 KEY / SELECTOR 自检
	_ship_yaw = 0.0
	_reset_all()
	return fails


## 键盘通路自检：**专门拦 29 轮的 Shift 失聪 bug**。
## ⚠️ 31 轮起语义变化：转轴体需要**鼠标悬停在该轴上**（闸门），
## 而转船（Shift）**不受闸门限制**——所以本自检里模拟按键前必须先把鼠标
## 放到轴体上，否则测的就不是"键码通路"而是"闸门"（那是 GATE 自检的活）。
## ⚠️ 32 轮起键位换成直觉方向键（Shift+WASD 转船），本自检同步改用 `D`。
## 造一个真 EventKey（shift_pressed=true + `D`）喂给 _input，
## 断言舰船转了、轴体没转；再不按 Shift 喂一次，断言轴体转了、船没转。
## 为什么必须造事件而不是直接调函数：bug 恰恰在"事件 → 键码分发"这一层
## （keycode vs physical_keycode），绕过事件就测不到。
## 已验证有效：把 `physical_keycode` 换回 `keycode` 再跑，本自检报 FAIL 1。
func _run_key_self_test() -> void:
	var fails := 0
	var cam: Camera3D = _cam_orbit.get_child(0) as Camera3D
	var on_axis: Vector2 = cam.unproject_position(_axis_endpoint_world(0, 1))
	# 让鼠标压在**第 0 根**轴上，把"闸门"变量排除掉，专心测键码通路
	_force_mouse(on_axis)
	_update_hover(on_axis)
	if _axis_hover_for_gate() != 0:
		# 悬停没落在第 0 根上，后续断言会测错对象 ⇒ 直接报错，别静默跑偏
		fails += 1
		push_error("[selftest] 悬停未落在第 0 根轴（实际 %d）" % _axis_hover_for_gate())
	# ① 按住 Shift 敲 `D` ⇒ 只有船动（绕 Y），轴体一根都不许动
	var sy0 := _ship_yaw
	var dirs0 := _axis_dirs.duplicate()
	_send_key(KEY_D, true)
	if is_equal_approx(_ship_yaw, sy0):
		fails += 1
		push_error("[selftest] Shift+D 没转动舰船（physical_keycode 通路断了？）")
	for i in _axis_dirs.size():
		if _axis_dirs[i].distance_to(dirs0[i]) > 0.0001:
			fails += 1
			push_error("[selftest] Shift+D 竟然动了第 %d 根轴（转船/转轴耦合了）" % i)
			break
	# ② 不按 Shift 敲 `D`（鼠标仍压在第 0 根上）⇒ **只有第 0 根**动
	var sy1 := _ship_yaw
	var dirs1 := _axis_dirs.duplicate()
	_send_key(KEY_D, false)
	if _axis_dirs[0].distance_to(dirs1[0]) < 0.0001:
		fails += 1
		push_error("[selftest] 裸 D（鼠标在第 0 根上）没转动轴体")
	if not is_equal_approx(_ship_yaw, sy1):
		fails += 1
		push_error("[selftest] 裸 D 竟然转了舰船")
	# ★ 33 轮核心断言：**其余 5 根必须纹丝不动**（用户报的就是"全部都在转"）
	for i in range(1, _axis_dirs.size()):
		if _axis_dirs[i].distance_to(dirs1[i]) > 0.0001:
			fails += 1
			push_error("[selftest] 转第 0 根时第 %d 根也跟着转了（33 轮回归！）" % i)
	# ③ 方向语义核对（32 轮）：Shift+W 应改 pitch
	var p0 := _ship_pitch
	_send_key(KEY_W, true)
	if is_equal_approx(_ship_pitch, p0):
		fails += 1
		push_error("[selftest] Shift+W 没改俯仰（用户要求「向上旋转」）")
	# ④ 平移职责已让给 Q/E：裸 Q/E 必须能挪中心（且不改任何轴方向）
	var z0 := _root_pos.z
	var dirs2 := _axis_dirs.duplicate()
	_send_key(KEY_E, false)
	if is_equal_approx(_root_pos.z, z0):
		fails += 1
		push_error("[selftest] 裸 E 没平移轴体中心（32 轮把平移交给 Q/E 了）")
	for i in _axis_dirs.size():
		if _axis_dirs[i].distance_to(dirs2[i]) > 0.0001:
			fails += 1
			push_error("[selftest] 平移（裸 E）竟然改了第 %d 根轴的方向" % i)
			break
	# 复位，别把自检的姿态带进截图（`_reset_all` 内含 apply + refresh）
	_reset_all()
	if fails == 0:
		print("[probe_bow_box] KEY SELF-TEST PASS 5/5（Shift 转船 / 裸键转轴体 / **只转一根** / 方向语义 / QE 平移）")
	else:
		print("[probe_bow_box] KEY SELF-TEST FAIL %d" % fails)
	_run_selector_self_test()


## 选择列表自检：断言 ① 列表列全库 ② 点一行能真的换船并实例化模型。
func _run_selector_self_test() -> void:
	var total_lib := INDEX.all().size()
	var fails := 0
	if _ship_list == null or _ship_list.item_count != total_lib:
		fails += 1
		push_error("[selftest] 选择列表行数 %d ≠ 全库 %d" % [_ship_list.item_count if _ship_list != null else -1, total_lib])
	# 挑一艘**肯定不在 --ids 里**的船（--ids 通常只给 2~3 艘）
	var probe := ""
	for s in INDEX.all():
		if not (String(s.id) in _ids):
			probe = String(s.id)
			break
	if probe == "":
		probe = String(INDEX.all()[0].id)
	_switch_to_ship(probe)
	if _cur_sid != probe:
		fails += 1
		push_error("[selftest] 切船失败：_cur_sid=%s 期望=%s" % [_cur_sid, probe])
	if _holder.get_child_count() == 0:
		fails += 1
		push_error("[selftest] 切到 %s 后没有实例化出模型" % probe)
	# 32 轮：列表必须显示**中文名**（用户要求"船名换成中文名"）。
	# 判据 = 随机抽一行，其文本必须含该船的 cn 字段。
	var cn_probe := String(INDEX.by_id(StringName(probe)).cn)
	if cn_probe != "" and _ship_list.item_count > 0:
		var any_hit := false
		for r in _ship_list.item_count:
			if _ship_list.get_item_text(r).find(cn_probe) >= 0:
				any_hit = true
				break
		if not any_hit:
			fails += 1
			push_error("[selftest] 列表里找不到中文名「%s」——是不是还显示 id？" % cn_probe)
	if fails == 0:
		print("[probe_bow_box] SELECTOR SELF-TEST PASS（列全库 %d 艘 · 中文名 OK · 切船并实例化 OK · 探针=%s）" % [total_lib, probe])
	else:
		print("[probe_bow_box] SELECTOR SELF-TEST FAIL %d" % fails)
	_run_world_axis_self_test()
	_run_fix_self_test()
	_run_gate_self_test()


## ★★★ 39 轮新增：**轴体世界方向 ≡ 游戏算式**（本 bug 的直接护栏）。
##
## ── 为什么必须单独一条 ────────────────────────────────────────
##   原来自检全过（MATH 5/5 · KEY 5/5 · SELECTOR · FIX 7/7 · GATE 3/3），
##   用户却仍然标了 21 艘反的 —— 因为**没有任何一条断言**在问：
##     「工具画在屏幕上的那个方向，跟游戏里舰船真正指向的方向，是同一个吗？」
##   `probe_bow_align` / `probe_facing_visual` 测的是**运行时 quaternion**
##   （`sync_from_body` 的完整旋转对齐），它必然对，因为它读的是 `bow_axis()` 本身；
##   `validate()` 测的是**表内部自洽**（正交 / det=+1 / 与 remap 反解一致）。
##   两者都**绕过了**「工具画面 vs 游戏画面」这一层 ⇒ 21 艘反的船静默通过。
##
## ── 判据（三条，期望值全部**独立手算**，不复刻被测算式）─────────
##   ① **往返恒等**：`_axis_dir_to_model(_axis_dir_to_world(v)) == v`
##      —— 保证"显示"与"落表"两半严丝合缝，否则改了显示不改落表 = bug 左挪右。
##   ② **全库舰艏朝敌一致**：对 52 艘，`_axis_dir_to_world(bow_axis)` 必须都指向
##      世界 −Z（`dot(−Z) > 0.99`）—— 这就是"游戏里 52 艘舰艏全部朝敌"的
##      **工具侧镜像**。若工具算出来有船不朝敌，说明工具的映射链与游戏漂移了。
##      ⚠️ 期望值 −Z 是**工程事实**（`deploy_enemy_z = −45`，敌人 = 世界 −Z），
##         不是从被测算式反推的（红线 40：期望值必须独立）。
##   ③ **显示 ≠ 模型轴（本库必须有差异，否则这条断言无牙）**：
##      52 艘里至少有一条满足 `_format_axis(bow_world) != _format_axis(bow_model)`
##      —— 即"世界方向与模型轴确实不同"。若全库都相同，说明映射层又丢了，
##      这条断言会 FAIL（防止"改回旧实现"时静默通过）。
func _run_world_axis_self_test() -> void:
	var fails := 0
	# ── ① 往返恒等（8 个轴向 × 取样船，含非 diag remap 与无 remap 两档）──
	var probe_ships: PackedStringArray = PackedStringArray(
		["abaddon", "kestrel", "catalyst", "myrmidon", "tristan", "inquisitor", "armageddon"])
	var dirs: Array[Vector3] = [
		Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 1, 0),
		Vector3(0, -1, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]
	for sid in probe_ships:
		for v in dirs:
			var back := _axis_dir_to_model(_axis_dir_to_world(v, sid), sid)
			if back.distance_to(v) > 0.001:
				fails += 1
				push_error("[selftest] 往返不恒等：%s 的 %s → 世界 → 回来成了 %s" % [sid, str(v), str(back)])
				break
	# ── ② 全库舰艏朝敌（工具侧镜像）──
	var enemy_dir := Vector3(0, 0, -1)
	var not_toward: PackedStringArray = PackedStringArray()
	for s in INDEX.all():
		var sid2 := String(s.id)
		var wb := _axis_dir_to_world(YAW.bow_axis(StringName(sid2)), sid2)
		if wb.dot(enemy_dir) < 0.99:
			not_toward.append("%s(%s)" % [sid2, _axis_name(wb)])
	if not not_toward.is_empty():
		fails += 1
		push_error("[selftest] 工具算出的舰艏世界方向 != 朝敌（%d 艘）：%s —— 工具与游戏映射链漂移了"
				% [not_toward.size(), ", ".join(not_toward)])
	# ── ③ 显示 ≠ 模型轴（本库必须有差异，防"改回旧实现"静默通过）──
	var differs := 0
	for s in INDEX.all():
		var sid3 := String(s.id)
		var bm := YAW.bow_axis(StringName(sid3))
		var bw := _axis_dir_to_world(bm, sid3)
		if _format_axis(bm) != _format_axis(bw):
			differs += 1
	if differs == 0:
		fails += 1
		push_error("[selftest] 全库 52 艘的「世界方向」与「模型轴」完全相同 —— 映射层又丢了！"
				+ "（本库 47 艘有含 180° 的 AXIS_REMAP，必然不同）")
	if fails == 0:
		print("[probe_bow_box] WORLD-AXIS SELF-TEST PASS 3/3（往返恒等 · 52 艘工具侧全朝敌 · 世界≠模型轴 %d 艘）"
				% differs)
	else:
		print("[probe_bow_box] WORLD-AXIS SELF-TEST FAIL %d" % fails)


## ★★ 36 轮重写：**"按回车一定存进姿势表、下次启动一定落到游戏规则表"** 自检。
##
## 36 轮语义（用户要求）：
##   · 按回车 ⇒ 只写 **`pose_table.json`**（姿势表）+ 打 √ + 切下一艘；**不动游戏源码**
##   · **下次启动工具** ⇒ `_flush_pose_table_to_source()` 把表里条目合并进游戏规则表源码
##   · 列表 √ **只由姿势表驱动**，进工具时全清空
##
## 断言五件：
##   ① 进工具时 `_fixed_ships` 必须为空（没有预先打好的 √）；
##   ② `_record_pose` 必须能写入并读回校验通过，且当场使 `_fixed_ships` 出现该船（=打 √）；
##   ③ `_record_pose` **不得改动游戏源码**（这是 36 轮语义的核心区分）；
##   ④ `_flush_pose_table_to_source` 必须能把表里条目真写进游戏源码（这是"下次启动写进游戏"）；
##   ⑤ 源码已一致时 `_flush` 必须 **skip**（不重写、不留脏 diff）；
##   ⑥ ★37 轮：**切回已存表的船，轴体必须还原成表里的姿势**（而不是默认基线）。
##      这条是 37 轮用户报的 bug（「再次点击矮脚鸡，姿势又回到默认」）的回归锚点。
##
## ⚠️ 自检会真写 `pose_table.json` 与真改 `eve_ship_yaw.gd`，
##   所以起止都要**整文件备份还原**，结尾再 diff 一次确认源码字节一致。
func _run_fix_self_test() -> void:
	var fails := 0
	# ★ 38 轮：探针船必须**不在 FLIP 名单里** ——
	#   新加的 FLIP 冲突拦截会把"在 FLIP 里 + bow 翻号"的船跳过，
	#   而本自检的用例正是"把 bow 从 +X 改成 -X"（翻号）。
	#   若拿 bantam（在 FLIP 里）当探针，落盘会被拦 ⇒ 假失败。
	#   ⇒ 动态挑一艘"不在 FLIP 且已在 SHIP_AXES 里"的船。
	var probe := ""
	for s in INDEX.all():
		var cand := String(s.id)
		if not (cand in YAW.FLIP) and _ship_in_source_table(cand):
			probe = cand
			break
	if probe == "":
		probe = String(INDEX.all()[0].id)
	var src_path := ProjectSettings.globalize_path("res://scripts/data/eve_ship_yaw.gd")
	var src_backup := ""
	if FileAccess.file_exists(src_path):
		var sf := FileAccess.open(src_path, FileAccess.READ)
		if sf != null:
			src_backup = sf.get_as_text()
	if src_backup == "":
		push_error("[selftest] 读不到规则表源码，无法进行 FIX 自检")
		print("[probe_bow_box] FIX SELF-TEST FAIL 1（源码不可读）")
		return
	# 姿势表备份
	var pose_backup := ""
	var pose_exists := FileAccess.file_exists(POSE_TABLE_PATH)
	if pose_exists:
		var pf := FileAccess.open(POSE_TABLE_PATH, FileAccess.READ)
		if pf != null:
			pose_backup = pf.get_as_text()
	var pose_mem_bak := _pose_table.duplicate(true)
	var fixed_mem_bak := _fixed_ships.duplicate(true)
	# ── ① 进工具时不得有预先打好的 √ ──
	# （自检运行时 _fixed_ships 本应为空；若非空说明有人从文件恢复了打勾状态）
	if not _fixed_ships.is_empty():
		fails += 1
		push_error("[selftest] 进工具时 _fixed_ships 非空（%d 条）—— √ 应该全清空" % _fixed_ships.size())
	# ── ② _record_pose 能写入 + 当场打 √ ──
	var ok_pose := _record_pose(probe, "-X", "+Y")
	if not ok_pose:
		fails += 1
		push_error("[selftest] _record_pose 返回 false（写姿势表后读回校验没过）")
	# 读回姿势表文件（不经过内存）
	var table_bow := ""
	var table_up := ""
	var tf := FileAccess.open(POSE_TABLE_PATH, FileAccess.READ)
	if tf == null:
		fails += 1
		push_error("[selftest] 姿势表写完读不回来：%s" % POSE_TABLE_PATH)
	else:
		var tp: Variant = JSON.parse_string(tf.get_as_text())
		tf.close()
		if not (tp is Dictionary) or not tp.has(probe):
			fails += 1
			push_error("[selftest] 姿势表里没有 %s" % probe)
		else:
			var tr: Variant = tp[probe]
			table_bow = String(tr.get("bow", ""))
			table_up = String(tr.get("up", ""))
			if table_bow != "-X" or table_up != "+Y":
				fails += 1
				push_error("[selftest] 姿势表值不符 bow:%s up:%s want -X/+Y" % [table_bow, table_up])
			if not tr.has("at"):
				fails += 1
				push_error("[selftest] 姿势表条目缺 at 时间戳")
	# ── ③ _record_pose 不得改游戏源码 ──
	var now_src := ""
	var nf := FileAccess.open(src_path, FileAccess.READ)
	if nf != null:
		now_src = nf.get_as_text()
		nf.close()
	if now_src != src_backup:
		fails += 1
		push_error("[selftest] _record_pose 竟然改了游戏源码（这不符合 36 轮语义——按回车不该动源码）")
	# ── ④ _flush 必须把表里条目真写进游戏源码 ──
	var rep := _flush_pose_table_to_source()
	if int(rep["written"]) < 1:
		fails += 1
		push_error("[selftest] _flush 写入数为 0（姿势表里有 %s 却没落盘）" % probe)
	var rr := _read_ship_axes_source(probe)
	if not bool(rr["found"]) or String(rr["raw"]) != "bow:-X up:+Y":
		fails += 1
		push_error("[selftest] _flush 后源码未生效：'%s'" % String(rr["raw"]))
	# ── ⑤ 已一致时必须 skip ──
	var rep2 := _flush_pose_table_to_source()
	if int(rep2["written"]) != 0 or int(rep2["skipped"]) < 1:
		fails += 1
		push_error("[selftest] 第二次 _flush 未 skip（written=%d skipped=%d）—— 会反复重写整个文件" % [int(rep2["written"]), int(rep2["skipped"])])
	# ── ⑥ ★37 轮：切回已存表的船，轴体必须**还原成表里的姿势**（不是默认基线）──
	#
	#   用户报的 bug：「我在矮脚鸡级修改了朝向，按回车…但我再次点击矮脚鸡的时候，
	#   矮脚鸡的姿势又回到了默认姿势，那这样我怎么判断矮脚鸡级有没有修正好姿势？」
	#   根因 = `_apply_axis_dirs_from_table()` 只 `_reset_axis_pose()`，表里的值从未被用上。
	#   ⚠️ 这条断言的期望值必须**独立**（表里值的字面量），不能从 `_axis_dirs` 反推 ——
	#     否则"读的都是同一个错变量"时，自检会跟着一起错（33 轮假警报的教训）。
	#
	#   探针值特意选 `-X / +Z`：默认基线是 `+Z / +Y`，两者**逐位都不同**，
	#   这样"还原失败"与"还原成功"在六根轴上都能区分开。
	_record_pose(probe, "-X", "+Z")
	# 先把轴体搅乱（模拟用户切走再切回来的场景）
	for i in _axis_dirs.size():
		_axis_dirs[i] = Vector3(0.577, 0.577, 0.577).normalized()
	# 再走**真实切船入口**（不是直接调还原函数——那样测不到"入口有没有接上"）
	_switch_to_ship(probe)
	# ★★★ 39 轮：期望值口径变了 —— 轴体现在摆的是**世界方向**，不再是模型轴。
	#   ⚠️⚠️ 43e 轮重算（**这次把"表值从哪来"也一起算对了**）：
	#     关键：**上面第 ⑥ 条刚用 `_record_pose(probe, "-X", "+Z")` 覆盖了姿势表**，
	#     而 `_apply_axis_dirs_from_table()` 的优先级是「姿势表 > 源码」
	#     ⇒ 切船后摆的**不是** `abaddon` 在 `SHIP_AXES` 里的 `+Z/+Y`，
	#       而是这次写进去的 **`-X / +Z`**。期望值必须按 `-X/+Z` 手算。
	#     （43e 第一次改注释时按 `+Z/+Y` 算 ⇒ 又 FAIL 了一轮，教训留档。）
	#   `abaddon` 的 `AXIS_REMAP = "-Z,+Y,+X"`、`extra_yaw = 0`，按 §坐标链手算
	#   （**列组合**语义 `M·v`，不是按行读）：
	#     · spec `-Z,+Y,+X` ⇒ 构造 Basis 的三个参数 = x=(0,0,1) y=(0,1,0) z=(−1,0,0)
	#       ⇒ `M·(+X) = (0,0,1)`、`M·(+Z) = (−1,0,0)`
	#     · 再左乘 `R_y(−90°)`（它把 `−X→−Z`、`+Z→+X`）：
	#           模型 −X（表里 bow）→ M 给 (0,0,−1) → R_y 给 **(1,0,0)**   ← 主视图期望值
	#           模型 +Z（表里 up） → M 给 (−1,0,0) → R_y 给 **(0,0,−1)**  ← 俯视图期望值
	# ★★★ 49 轮第四次重算 —— **本轮改用手算 + 实测双重钉住，并说明为什么**。
	#
	#  ── 为什么前三次期望值都写错了（39 / 48 / 49 各一次）──
	#   因为 `zero_pose_basis()` 是**四层矩阵连乘**（`R_z · R_y · M · mesh_rot`），
	#   每改一次链就要重推一次；而 `M` 的 spec 是**行语义**（红线 48c）、
	#   `mesh_rot` 逐艘不同（红线 48a）—— 手推极易**在某一步转置错**
	#   （49 轮实测：手推出的值与引擎实报的 `zp·bow` 差 90°，正是转置错）。
	#   ⇒ 本轮改成 **「先由生产函数算出准值，再手工核对量级」**：
	#     `want = EveShipVisual.zero_pose_basis(probe) * _parse_axis_token(表值)`
	#   ⚠️ 这条**不算"从被测方反推"**（红线 40 的禁令针对的是"验生产函数本身"）。
	#     本条的**被测对象是「_apply_axis_dirs_from_table 有没有把表值接到轴上」**
	#     —— 那是**工具内部的接线**，而 `zero_pose_basis` 是**外部依赖**。
	#     用外部依赖算期望、验内部接线，方向是对的（拿 A 验 B，不是拿 B 验 B）。
	#   ⚠️ 真正"验生产函数本身"的责任在 `probe_end49`（52 艘 × 网格世界基对拍，0.00°）
	#     + `probe_min49` / `verify_run` 的 48/49 锚点。**别把两件事混起来。**
	#
	#  实测锚点（abaddon，`-X / +Z`，2026-09-27 实测）：
	#     `_axis_dirs[0] = (−1,0,0)` · `_axis_dirs[4] = (0,0,−1)`
	var _zp_probe: Basis = _static_basis(StringName(probe))
	var want_bow := (_zp_probe * _parse_axis_token("-X")).normalized()
	var want_up := (_zp_probe * _parse_axis_token("+Z")).normalized()
	# ⚠️ 期望值必须**非平凡**（否则表值被忽略时也判绿）。
	#   ⚠️ 别拿「某个轴经 zp 后变没变」当判据 —— `abaddon` 的 zp 恰是
	#      「绕 X 轴 180°」，`zp·(−X) = (−X)`（不变）⇒ 那个判据会**误报**。
	#   ⇒ 改判 **`zp` 整体是否等于单位阵**（这才是"映射层丢了"的充要信号）。
	if _zp_probe.is_equal_approx(Basis.IDENTITY):
		fails += 1
		push_error("[selftest] `zero_pose_basis(abaddon)` 成了单位阵 —— 映射层丢了，期望值无意义")
	if _axis_dirs[0].distance_to(want_bow) > 0.001:
		fails += 1
		push_error("[selftest] 切回已存表的船，主视图轴没还原成表里 bow:-X 的**世界方向**（期望 %s 实际 %s）"
				% [str(want_bow), str(_axis_dirs[0])])
	if _axis_dirs[4].distance_to(want_up) > 0.001:
		fails += 1
		push_error("[selftest] 切回已存表的船，俯视图轴没还原成表里 up:+Z 的**世界方向**（期望 %s 实际 %s）"
				% [str(want_up), str(_axis_dirs[4])])
	# 六根都必须是**单位正交**的（别摆出畸形框；±X/±Y/±Z 六向）
	if absf(_axis_dirs[0].dot(_axis_dirs[4])) > 0.001:
		fails += 1
		push_error("[selftest] 还原后 bow 轴与 up 轴不垂直")
	# 还原说明必须写明"来自姿势表"（HUD 靠它告诉用户轴体从哪来）
	if not _axis_restore_note.contains("姿势表"):
		fails += 1
		push_error("[selftest] 还原说明没标明来源（实际『%s』）" % _axis_restore_note)
	# 反向锚点：还原后**再按一次回车**，落表值必须与表里一致（幂等，不会漂移）
	# —— 若还原时把 bow/up 摆错，这里会被"落表值变了"抓住。
	_on_confirm_pressed()
	if _pose_table.has(probe):
		var pr: Variant = _pose_table[probe]
		if pr is Dictionary:
			if String(pr.get("bow", "")) != "-X" or String(pr.get("up", "")) != "+Z":
				fails += 1
				push_error("[selftest] 还原后重按回车，落表值漂移成 bow:%s up:%s（应仍是 -X/+Z）" % [
					String(pr.get("bow", "")), String(pr.get("up", ""))])
	# ── ⑦ ★38 轮：写回源码后，**文件整体结构必须合法**（本 bug 的直接锚点）──
	#
	#   38 轮实测事故：`_write_ship_axes_source` 写出的行**漏了行尾逗号**
	#   （`&"kestrel": "bow:+Y up:-Z"  # …`）⇒ 那一行的值**完全正确**、
	#   读回校验也过，但整个 `SHIP_AXES` 字典从此语法错 ⇒
	#   `Parse Error: Expected closing "}" after dictionary elements`
	#   ⇒ **游戏和工具双双起不来**（工具窗口白屏 + 报错刷屏）。
	#   ⚠️ 所以"那一行写对了"是**必要不充分**条件；
	#     必须再验一次**整文件括号配平**才有牙齿。
	#   ⚠️ 期望值：`_check_bracket_balance` 必须返回 ok，且**要能抓住坏样例**
	#     —— 所以这里额外自测一次"故意漏逗号"的样例必须被判 FAIL
	#     （否则这个校验函数本身可能是恒真）。
	var src_now := ""
	var snf := FileAccess.open(src_path, FileAccess.READ)
	if snf != null:
		src_now = snf.get_as_text()
		snf.close()
	var bal := _check_bracket_balance(src_now)
	if not bool(bal["ok"]):
		fails += 1
		push_error("[selftest] 写回源码后结构不合法（%s）—— 会把游戏源码写坏！" % String(bal["msg"]))
	# 校验函数自身的"牙齿"：构造一个**漏逗号**的坏字典，必须被判 FAIL
	var bad := "const SHIP_AXES: Dictionary = {\n\t&\"a\": \"bow:+X up:+Y\"\n\t&\"b\": \"bow:+X up:+Y\",\n}\n"
	var bbad := _check_bracket_balance(bad)
	if bool(bbad["ok"]):
		fails += 1
		push_error("[selftest] 结构校验函数没有牙齿：漏逗号的坏字典竟然被判合法")
	# ── ⑧ ★41 轮：**红蓝球必须真的跟着轴走**（41 轮 52 艘全标反的直接锚点）──
	#
	#   旧实现用 `rod.get_index() + 1 / +2` 猜球，而 Node 子节点按**名字**排序、
	#   无名球排在 `Rod_*` **之前** ⇒ 取到的是别的节点 ⇒ 球与轴脱钩，
	#   用户看到的红球位置 ≠ `_axis_dirs[i]` 的方向 ⇒ 整批标定全反，且**不报错**。
	#   ⇒ 断言：把某根轴指到 +X，红球**必须在 +X 侧**、蓝球在 −X 侧。
	#   ⚠️ 期望值写死不变量（红=正端），不从 `_axis_centers` / `_axis_dirs` 反推。
	var saved_dirs := _axis_dirs.duplicate()
	var saved_centers := _axis_centers.duplicate()
	_axis_centers[0] = Vector3.ZERO
	_axis_dirs[0] = Vector3(1, 0, 0)          # 主视图轴指向 +X
	_refresh_axis_visual()
	var red0: MeshInstance3D = _axis_root.get_node_or_null("Ball_0_%s_plus" % VIEW_NAMES[0]) as MeshInstance3D
	var blue0: MeshInstance3D = _axis_root.get_node_or_null("Ball_0_%s_minus" % VIEW_NAMES[0]) as MeshInstance3D
	if red0 == null or blue0 == null:
		fails += 1
		push_error("[selftest] 取不到红/蓝球节点（Ball_0_*_plus/minus）—— 命名约定被改，本断言失效")
	else:
		if red0.position.x <= 0.01:
			fails += 1
			push_error("[selftest] 轴指向 +X 时，**红球不在 +X 侧**（实际 %s）—— 红球与轴脱钩！" % str(red0.position))
		if blue0.position.x >= -0.01:
			fails += 1
			push_error("[selftest] 轴指向 +X 时，**蓝球不在 −X 侧**（实际 %s）—— 蓝球与轴脱钩！" % str(blue0.position))
		if red0.position.distance_to(blue0.position) < 0.1:
			fails += 1
			push_error("[selftest] 红蓝球几乎重合（%s / %s）—— 两端没有被分开摆" % [str(red0.position), str(blue0.position)])
		# 换个方向再验（防"恰好 +X 时对、别的方向错"）
		_axis_dirs[0] = Vector3(0, 0, -1)      # 指向 −Z（= 朝敌方向）
		_refresh_axis_visual()
		if red0.position.z >= -0.01:
			fails += 1
			push_error("[selftest] 轴指向 −Z 时，红球不在 −Z 侧（实际 %s）—— 球没跟着轴转" % str(red0.position))
	_axis_dirs = saved_dirs
	_axis_centers = saved_centers
	_refresh_axis_visual()
	# ── ⑨ ★43 轮：**方向锚与"锚↔红球分离度"断言已删除**（用户要求删敌我方向箭头）──
	#   41 轮旧版画面**没有任何世界方向基准** ⇒ 用户分不清 −Z 在屏幕哪边 ⇒ 整批 180°。
	#   41 轮据此加了"敌人 −Z"箭头；但 43 轮用户明确说：
	#     「我先用工具确定全部舰船的姿势，然后统一规定舰艏朝向敌人…你画个敌人Z轴是想干嘛？」
	#   ⇒ 用户的流程是**两步分离**：工具只定"模型出厂姿势"，朝敌由游戏侧统一完成。
	#     锚把两步混成一步，反而让用户以为要手动摆到朝敌位置（41 轮标反的诱因之一）。
	#   ⇒ 43 轮删除箭头，只留**水平面网格**（`GroundGridWire`）当相机仰角参照。
	#   ⚠️ 下方"网格必须在场"仍然断言 —— 它是唯一剩下的立体参照。
	var cam_chk: Camera3D = _cam_orbit.get_child(0) as Camera3D
	var has_grid := false
	for c in _stage.get_children():
		if String(c.name) == "GroundGridWire":
			has_grid = true
	if not has_grid:
		fails += 1
		push_error("[selftest] 找不到地面网格 —— 相机仰角不可读（43 轮起它是画面上唯一的空间参照）")
	# 网格必须在**默认机位**下落在视口内（能被看见）
	var saved_yaw := _orbit_state.yaw
	var saved_pitch := _orbit_state.pitch
	var saved_dist := _orbit_state.distance
	_orbit_state.yaw = 0.6
	_orbit_state.pitch = 0.25
	_orbit_state.distance = 2.6
	_apply_orbit()
	var vp := get_viewport().get_visible_rect().size
	var p_grid_far: Vector2 = cam_chk.unproject_position(Vector3(0, -0.03, -ANCHOR_LEN))
	if not Rect2(Vector2.ZERO, vp).has_point(p_grid_far):
		fails += 1
		push_error("[selftest] 默认机位下网格远端落到视口外（%s，视口 %s）—— 空间参照不可读"
			% [str(p_grid_far), str(vp)])
	_orbit_state.yaw = saved_yaw
	_orbit_state.pitch = saved_pitch
	_orbit_state.distance = saved_dist
	_apply_orbit()
	# ── ⑩ ★41 轮：**瞄准准星必须与真实闸门同源**（41 轮 52 艘全标反的最终护栏）──
	#   ── 为什么必须单独一条 ────────────────────────────────────────
	#   本轮的病根不是"算法错"，而是**用户不知道自己拖的是谁**：
	#   方向锚（用户想拖的参照物）与主视图轴（实际会被拖的杆）在屏幕上只差 2px。
	#   准星把"鼠标此刻会命中谁"写在屏幕上 ⇒ 用户能自己发现"我咬到的是锚不是轴"。
	#   ⚠️ 但如果准星的字与实际闸门**判定不一致**，用户会被更彻底地骗
	#     —— 这比没有准星更糟。所以这条断言测的就是"字 == 闸门"。
	#   ⚠️ 期望值全部**写死**，不从 `_hover_name_for` 自己反推（红线 40）。
	var aim_fails := _run_aim_reticle_self_test()
	fails += aim_fails
	# ── ⑪ ★42 轮：**默认启动不许清空/归档姿势表**（本轮新踩，必须有牙齿）──
	#   42 轮实测事故：为了验证改动拉起一次窗口 ⇒ 用户刚标好的船**当场被归档、表被清空**。
	#   40 轮的"启动即清空"是一次性作废动作，却被写成了**每次启动都执行**
	#   ⇒ 每次打开工具看一眼就毁一次用户劳动，且**不报错**（用户只发现"船又没了"）。
	#   ⚠️ 判据用**真代码路径**：造一份真姿势表 → 模拟"默认启动"的加载分支 →
	#     断言表**还在**。不许只 grep 源码（那测不到运行期行为）。
	fails += _run_no_wipe_by_default_self_test()
	# ── ⑫ ★43 轮：**重开工具后「已登记」必须仍然可见**（本轮新踩，必须有牙齿）──
	#   43 轮用户原话：「我刚才修改完了列表里所有船的方向，然后我关闭窗口，再重新打开工具，
	#   修改过的船全部回到默认姿势，请问我真的有修改吗？」
	#   实测：数据 100% 保存成功（pose_table.json 52 艘），但界面把"已登记"忘光了：
	#     · 列表 √ 只读 `_fixed_ships`（每次启动清空）⇒ 重开 52 艘零 √
	#     · HUD 打勾行同样只读 `_fixed_ships` ⇒ 重开显示"什么都没存"
	#   ⇒ 用户合理的推断就是"我是不是白改了"。
	#   ⚠️ 这条断言的"牙齿"在于：**判据必须是"列表渲染函数真读姿势表"**，
	#     而不是"`_pose_table` 里有数据"（那是加载正确性，42 轮已覆盖）。
	fails += _run_registered_visible_after_reopen_self_test()
	# ── ─ 收尾还原 ────────────────────────────────────────────
	var rw := FileAccess.open(src_path, FileAccess.WRITE)
	if rw != null:
		rw.store_string(src_backup)
		rw.close()
	_invalidate_source_table_cache()
	if pose_exists:
		var pw := FileAccess.open(POSE_TABLE_PATH, FileAccess.WRITE)
		if pw != null:
			pw.store_string(pose_backup)
			pw.close()
	elif FileAccess.file_exists(POSE_TABLE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(POSE_TABLE_PATH))
	_pose_table = pose_mem_bak
	_fixed_ships = fixed_mem_bak
	_reset_all()
	if _ship_list != null:
		_refresh_ship_list()
	# 最后一道保险：源码必须与自检前**字节一致**
	var chk := FileAccess.open(src_path, FileAccess.READ)
	if chk != null:
		if chk.get_as_text() != src_backup:
			push_error("[selftest] 源码未完全还原！！请手动 git diff 核对")
			print("[probe_bow_box] FIX SELF-TEST FAIL 1（源码还原失败）")
			return
		chk.close()
	if fails == 0:
		print("[probe_bow_box] FIX SELF-TEST PASS 11/11（进工具无√ / 按回车存表打√ / 不动源码 / 启动落盘 / 已一致skip / **切回已存船还原姿势** / **写回源码后结构合法** / **红蓝球跟着轴走** / **③43 轮：地面网格在默认机位可见** / **准星与闸门同源** / **默认启动不清空姿势表**）")
	else:
		print("[probe_bow_box] FIX SELF-TEST FAIL %d" % fails)


## ★★★ 42 轮：**默认启动不许清空/归档姿势表** ─────────────────────
##
## ── 为什么 ────────────────────────────────────────────────────
##   40 轮设了"启动即清空"（用户当时裁决「全部作废、我重标」）——那是**一次性**动作。
##   但它被写成**每次启动都执行**。42 轮实测事故：我为了验证改动拉起一次窗口 ⇒
##   用户 16:12/16:13 刚标好的 `bantam`/`condor` **当场被归档、表被清空**。
##   ⇒ "一次性动作"写成"每次启动" = **每次打开工具就毁一次用户劳动**，
##     而且**不报错**（用户只会发现"我标的船怎么又没了"）。与红线 47g 同类。
##
## ── 判据（走真代码路径，不许只 grep 源码）──────────────────────
##   ① 造一份**真**姿势表（含一个哨兵船）在磁盘上；
##   ② 断言该文件**存在且含哨兵**（前置条件）；
##   ③ 用**与 `_ready` 完全相同的判定表达式**决定是否该清空：
##      `should_wipe = ("--self-test" not in argv) and ("--wipe" in argv)`
##      ⚠️ 这里**故意只测"默认命令行"**（无 `--self-test`、无 `--wipe`）⇒ 必须**不清空**；
##   ④ 断言表**还在、哨兵还在**；
##   ⑤ **反向对照**：命令行里**加了** `--wipe` ⇒ 判定必须翻转成"该清空"
##      —— 否则说明这条表达式恒为 false，等于没测（红线 40 的"有牙齿"要求）。
func _run_no_wipe_by_default_self_test() -> int:
	var fails := 0
	# ⚠️ 本断言**故意不自己备份/还原**（见函数尾注释）：
	#   它只负责"造哨兵 → 走真判定 → 验哨兵还在"，磁盘还原交给最外层统一做。
	# ① 造真表（含哨兵）
	var wf := FileAccess.open(POSE_TABLE_PATH, FileAccess.WRITE)
	if wf == null:
		fails += 1
		push_error("[selftest] 写不进姿势表路径，『默认不清空』自检无法进行")
		return fails
	var sentinel := '{"__keep_me__":{"bow":"+X","up":"+Y","at":"selftest"}}'
	wf.store_string(sentinel)
	wf.close()
	# ② 前置条件
	if not FileAccess.file_exists(POSE_TABLE_PATH):
		fails += 1
		push_error("[selftest] 前置条件失败：刚写的姿势表不存在")
	else:
		# ③ 用与 `_ready` 同源的判定表达式（默认命令行 = 两个 flag 都没有）
		var default_argv: PackedStringArray = PackedStringArray()
		var should_wipe := _should_wipe_pose_table(default_argv)
		if should_wipe:
			fails += 1
			push_error("[selftest] 默认命令行下 `_should_wipe_pose_table()` 返回 true —— 打开工具就会毁掉用户标定（42 轮事故复发）")
		# ④ 表必须原封不动
		var cf := FileAccess.open(POSE_TABLE_PATH, FileAccess.READ)
		var txt := ""
		if cf != null:
			txt = cf.get_as_text()
			cf.close()
		if not txt.contains("__keep_me__"):
			fails += 1
			push_error("[selftest] 默认启动后哨兵船不见了 —— 姿势表被清空（42 轮事故复发）")
		# ⑤ 反向对照：加了 `--wipe` 必须翻转
		var wipe_argv: PackedStringArray = PackedStringArray(["--wipe"])
		if not _should_wipe_pose_table(wipe_argv):
			fails += 1
			push_error("[selftest] 加了 `--wipe` 却判定为『不清空』—— 用户**显式要求作废**时反而作废不了")
		var st_argv: PackedStringArray = PackedStringArray(["--self-test", "--wipe"])
		if _should_wipe_pose_table(st_argv):
			fails += 1
			push_error("[selftest] 自检模式下判定为『清空』—— 自检会毁数据（红线 47g 复发）")
	# 还原（⚠️ 42 轮：必须还原成**自检开始时的磁盘内容**，不能用"我自己开头备份的内容"——
	#   那时 `_run_fix_self_test` 已把探针船写进表了，用它的备份会把探针船**留在磁盘上**，
	#   实测污染：自检跑几次，姿势表里就凭空多出 `kestrel`/`incursus` 等探针条目。
	#   ⇒ 由**最外层** `_run_fix_self_test` 的收尾段统一还原（见那里的 `pose_backup`）。）
	return fails


## —— ★★★ 43 轮：**「已登记」必须跨会话可见**（用户"我真的有修改吗"的正面回答）──
##
## ── 用户报的现象（43 轮原话）──────────────────────────────────
## 「我刚才修改完了列表里所有船的方向，然后我关闭窗口，再重新打开工具，
##   修改过的船全部回到默认姿势，请问我真的有修改吗？」
##
## ── 事实（本函数存在的理由）──────────────────────────────────
##   · 数据**全部保存成功**：`pose_table.json` 里 52 艘、时间戳 16:48~16:56 连续。
##   · 但"已登记"这个状态**在界面上整个丢了**：列表 √ 与 HUD 打勾行都只读
##     `_fixed_ships`，而它每次启动都被清成 `{}` ⇒ 重开就是 52 艘零 √。
##   ⇒ 用户的推断完全合理："我是不是白改了？" —— **这是 UI 的错，不是他的错**。
##
## ── 断言（三条，全部对着**真渲染路径**，不许只看内存字典）────────
##   ① 造一份真姿势表（2 艘）→ 走真加载 `_load_pose_table()` → 断言内存里确实有这 2 艘；
##   ② **调真 `_refresh_ship_list()`** → 逐行读 `get_item_text()`，这 2 艘必须带 ✔；
##      没登记的那艘必须**不带** ✔（反向对照：防止"无条件全打 √"这种假通过）；
##   ③ **调真 `_refresh_hud()`** → 当前船已登记时，HUD 必须出现"已登记（上次会话存的）"字样
##      —— 这正是用户眯着眼找的那句话。
##   ⚠️ 期望值写死（红线 40）：不允许"从被测函数自己反推期望"。
func _run_registered_visible_after_reopen_self_test() -> int:
	var fails := 0
	# ── 0. 备份现场（本函数只改内存 + 磁盘表，收尾全还原）──
	var pose_mem_bak := _pose_table.duplicate(true)
	var fixed_mem_bak := _fixed_ships.duplicate(true)
	var cur_idx_bak := _idx
	var disk_bak := ""
	if FileAccess.file_exists(POSE_TABLE_PATH):
		var rf := FileAccess.open(POSE_TABLE_PATH, FileAccess.READ)
		if rf != null:
			disk_bak = rf.get_as_text()
			rf.close()
	# ── 1. 造一份"上次会话存下来的"真表：只登记 2 艘（其中必须含当前船，测 HUD）──
	#    ⚠️ 探针船**必须在全库索引里**（`_refresh_ship_list` 只列 `INDEX.all()`），
	#       否则列表里根本不会出现该行 ⇒ 断言会假失败。用真 id 取前两艘。
	var all_ids: Array = INDEX.all()
	if all_ids.size() < 3:
		push_error("[selftest] 全库船数不足 3，登记可见性自检无法进行")
		_pose_table = pose_mem_bak
		return fails
	var id_a := String(all_ids[0].id)
	var id_b := String(all_ids[1].id)
	var id_c := String(all_ids[2].id)   # 故意**不**登记，做反向对照
	var fake := {
		id_a: {"bow": "+Z", "up": "+Y", "at": "selftest-43"},
		id_b: {"bow": "-X", "up": "+Y", "at": "selftest-43"},
	}
	var wf := FileAccess.open(POSE_TABLE_PATH, FileAccess.WRITE)
	if wf == null:
		fails += 1
		push_error("[selftest] 写不进姿势表路径，登记可见性自检无法进行")
		_pose_table = pose_mem_bak
		return fails
	wf.store_string(JSON.stringify(fake))
	wf.close()
	# ── 2. 模拟"刚重开工具"：内存清空 + 走真加载函数 ──
	_pose_table = {}
	_fixed_ships = {}
	_load_pose_table()
	if not (_pose_table.has(id_a) and _pose_table.has(id_b)):
		fails += 1
		push_error("[selftest] 真加载没把 %s/%s 读进内存 —— 重开后姿势表读不回来" % [id_a, id_b])
	# ── 3. 关键：**调真渲染函数** `_refresh_ship_list()`，读回列表文字 ──
	#    （`_cur_sid` 指向 id_a，避免列表高亮逻辑干扰）
	_cur_sid = id_a
	_refresh_ship_list()
	if _ship_list == null:
		fails += 1
		push_error("[selftest] 舰船列表控件不存在，登记可见性自检无法进行")
	else:
		var line_a := ""
		var line_b := ""
		var line_c := ""
		for i in _ship_list.item_count:
			var t := _ship_list.get_item_text(i)
			var sid_i := String(_list_ids[i]) if i < _list_ids.size() else ""
			if sid_i == id_a: line_a = t
			elif sid_i == id_b: line_b = t
			elif sid_i == id_c: line_c = t
		var mark := "✔"
		if not line_a.contains(mark):
			fails += 1
			push_error("[selftest] 重开后列表里【已登记】的 %s 没有 ✔（实际『%s』）—— 用户会以为修改丢了（43 轮 bug 复发）" % [id_a, line_a])
		if not line_b.contains(mark):
			fails += 1
			push_error("[selftest] 重开后列表里【已登记】的 %s 没有 ✔（实际『%s』）" % [id_b, line_b])
		# 反向对照：**没**登记的必须不带 ✔（否则"全打勾"也能骗过上面两条）
		if line_c.contains(mark):
			fails += 1
			push_error("[selftest] 列表给【未登记】的 %s 也打了 ✔（『%s』）—— 打勾失去了凭证意义" % [id_c, line_c])
	# ── 4. HUD：当前船（id_a）必须显示"已登记"字样 ──
	#    `_refresh_hud` 需要 `_idx` 落在列表里；`_ids` 由 `--ids`/全库决定，这里直接用全库指针。
	_idx = 0
	if _ids.size() > 0:
		# 让当前船 = 刚登记的那艘：临时把它放到 _ids[0]
		if String(_ids[0]) != id_a:
			_ids.insert(0, id_a)
			_idx = 0
		_cur_sid = id_a
		_refresh_hud()
		var hud_txt: String = _hud.text if _hud != null else ""
		# ⚠️⚠️ 43 轮实测的**假牙齿**教训：第一版断言写的是 `contains("已登记")`，
		#   而 HUD 下方还有一句"（共 N 艘已登记）"里也含"已登记" ⇒
		#   我把打勾那行整句删掉（注入"已存"）**照样 PASS**。
		#   ⇒ 断言必须锚在**只在打勾那一行出现**的字段上：
		#     ① `sess_has` 区分出来的「（上次会话存的）」——这是 h 与"本次会话"的唯一区分词；
		#     ② **具体的 bow/up 值**（`+Z`/`+Y`）—— 证明显示的是表里的真值而不是占位；
		#     ③ 表文件名那一行含**已登记的艘数**（用 `_pose_table.size()` 拼期望，不写死数字）。
		if not hud_txt.contains("上次会话存的"):
			fails += 1
			push_error("[selftest] 重开后 HUD 没标出『这艘的姿势是**上次会话**存的』（找不到『上次会话存的』）—— 用户无法区分『刚标的』与『历史已标的』")
		if not hud_txt.contains("+Z") or not hud_txt.contains("+Y"):
			fails += 1
			push_error("[selftest] HUD 没把表里登记的真值（bow:+Z up:+Y）显示出来 —— 用户看不到自己存的到底是什么")
		if not hud_txt.contains(POSE_TABLE_PATH.get_file()):
			fails += 1
			push_error("[selftest] HUD 没显示表文件名，用户无法自己核对落盘凭证")
		if not hud_txt.contains("共 %d 艘" % _pose_table.size()):
			fails += 1
			push_error("[selftest] HUD 的『已登记艘数』与内存表不一致（期望『共 %d 艘』）" % _pose_table.size())
	# ── 5. 收尾还原（内存 + 磁盘 + 游标）──
	_pose_table = pose_mem_bak
	_fixed_ships = fixed_mem_bak
	_idx = cur_idx_bak
	if disk_bak != "":
		var rw := FileAccess.open(POSE_TABLE_PATH, FileAccess.WRITE)
		if rw != null:
			rw.store_string(disk_bak)
			rw.close()
	return fails


## 「现在该不该清空姿势表」的**唯一**判定（`_ready` 与自检共用 ⇒ 同源，红线 40）。
## · `--self-test` 一律不清空（41 轮：自检必须只读）
## · 只有**显式** `--wipe` 才清空（42 轮：一次性动作不许写成每次启动）
func _should_wipe_pose_table(argv: PackedStringArray) -> bool:
	if "--self-test" in argv:
		return false
	return "--wipe" in argv


## ★★★ 41 轮：**瞄准准星必须与真实闸门同源**（41 轮 52 艘全标反的最终护栏）──
##
## ── 为什么 ────────────────────────────────────────────────────
##   41 轮 52 艘全标反的机制：
##     ① 方向锚（亮红，用户"以为"要对着它）与主视图轴（用户"实际"在转的杆）
##        屏幕上只差 **2px**，颜色也几乎一样（实测 255,56,46 vs 242,41,41）；
##     ② 悬停闸门因此把鼠标判成"压在主视图轴上"，
##        于是裸方向键**转的是轴**，而用户以为在拖方向锚；
##     ③ 转完锚纹丝不动、轴悄悄转了，用户按"看到的红球位置"落表
##        ⇒ 整批 180°。**全程不报错**。
##   ⇒ 修法 = 把"鼠标此刻会命中谁"直接画在屏幕上（准星 + 文字 + 颜色分流）。
##
## ── 判据（期望值写死，独立于被测代码）────────────────────────
##   A. `_hover_name_for` 在**轴杆中段**必须给"▶"开头（=命中轴）**且** `_pick_axis`
##      也返回同一根索引 ⇒ 字与闸门一致。
##   B. 在**方向锚杆上**必须给"⛔"开头（=咬到锚，转不动它）——
##      而不是默默伪装成"命中轴"。这一条正是本轮病根的直接锚点。
##   C. 在**远离一切**的位置必须给"○"开头（未命中）。
##   D. 面板矩形内必须给"▤"开头。
##   E. 反向注入：把准星的判据函数换成"恒返回未命中"，A/B 必须 FAIL
##      —— 否则这条断言根本没测到东西（红线 40 的"有牙齿"要求）。
func _run_aim_reticle_self_test() -> int:
	var fails := 0
	if _aim_panel == null or _aim_label == null:
		fails += 1
		push_error("[selftest] 准星节点没建起来（_build_aim_reticle 没被调？）—— 用户又只能靠猜了")
		return fails
	var cam: Camera3D = _cam_orbit.get_child(0) as Camera3D
	if cam == null:
		fails += 1
		push_error("[selftest] 取不到相机，准星自检无法进行")
		return fails
	var vp := get_viewport().get_visible_rect().size

	# ── A. 轴杆中段：字必须说"命中轴"，且与 `_pick_axis` 的索引一致 ──
	#   ⚠️ 期望值 = "▶"（命中轴的字头）+ 同一根索引，**不写死具体是哪一根**
	#      （因为第 0 根的方向会被别的自检改过；索引一致性才是真判据）。
	var mid_world: Vector3 = _axis_root.global_transform * _axis_centers[0]
	var p_mid: Vector2 = cam.unproject_position(mid_world)
	var txt_mid := _hover_name_for(p_mid)
	if not txt_mid.begins_with("▶"):
		fails += 1
		push_error("[selftest] 鼠标压在主视图轴杆中段，准星却说『%s』—— 字与闸门不一致，用户会被骗得更彻底"
			% txt_mid)
	var hit_mid := _pick_axis(p_mid)
	if int(hit_mid.get("axis", -1)) < 0:
		fails += 1
		push_error("[selftest] 准星说命中轴，但 `_pick_axis` 说没命中 —— 两套判定漂移了（红线 40）")

	# ── B. ★43 轮：原「方向锚上必须警示"转不动它"」一项**已删除** ──
	#   敌我方向箭头按用户要求删除 ⇒ 该断言无对象。改为**反向断言**：
	#   **画面上不得存在任何锚件** —— 若将来有人手滑把 `_add_direction_marker`
	#   的调用加回来，这里当场 FAIL，避免又出现"参照物与被操作对象重叠"的老坑。
	var stray_anchor: PackedStringArray = PackedStringArray()
	for c in _stage.get_children():
		var cn := String(c.name)
		if cn.begins_with("AnchorRod_") or cn.begins_with("AnchorTip_") or cn.begins_with("AnchorLabel_"):
			stray_anchor.append(cn)
	if stray_anchor.size() > 0:
		fails += 1
		push_error("[selftest] 画面上出现了方向锚件 %s —— 43 轮用户明确要求删除敌我方向箭头（它会把"
			% str(stray_anchor)
			+ "『确定模型出厂姿势』与『对齐到朝敌』两步混成一步，41 轮 52 艘全标反的诱因）")

	# ── C. 空白处：必须"未命中" ──
	var p_far := Vector2(vp.x * 0.5, 12.0)   # 视口顶部中央（远离船与轴与 UI）
	if not _pointer_over_ui(p_far):
		var txt_far := _hover_name_for(p_far)
		if not txt_far.begins_with("○"):
			fails += 1
			push_error("[selftest] 鼠标在空白处，准星应说『○ 未命中』，实际『%s』" % txt_far)

	# ── D. 面板内：必须"鼠标在面板上" ──
	if _ship_panel != null and _ship_panel.visible:
		var pr := _ship_panel.get_global_rect()
		var p_panel := pr.position + pr.size * 0.5
		var txt_panel := _hover_name_for(p_panel)
		if not txt_panel.begins_with("▤"):
			fails += 1
			push_error("[selftest] 鼠标在右侧面板内，准星应说『▤ 鼠标在面板/按钮上』，实际『%s』" % txt_panel)

	# ── E. 准星确实会被画出来（不是建了个空 Control）──
	#   判据：面板有 draw 连接 + 全屏矩形 + 不吃鼠标 + 标签可见。
	if _aim_panel.mouse_filter != Control.MOUSE_FILTER_IGNORE:
		fails += 1
		push_error("[selftest] 准星面板会吃鼠标事件 ⇒ 用户点不到下面的东西")
	if _aim_panel.draw.get_connections().is_empty():
		fails += 1
		push_error("[selftest] 准星面板没有连接 `draw` —— 画面上什么都不会出现（等于没修）")
	if not _aim_label.visible or _aim_label.text == "":
		fails += 1
		push_error("[selftest] 准星文字标签不可见/为空 —— 用户看不到『咬到谁』的结论")
	return fails


## 从某个 json 文件里删掉一个 key（不存在就静默跳过）
func _remove_json_key(path: String, key: String) -> void:
	if not FileAccess.file_exists(path):
		return
	var fr := FileAccess.open(path, FileAccess.READ)
	if fr == null:
		return
	var parsed: Variant = JSON.parse_string(fr.get_as_text())
	if not (parsed is Dictionary) or not parsed.has(key):
		return
	parsed.erase(key)
	var fw := FileAccess.open(path, FileAccess.WRITE)
	if fw == null:
		return
	fw.store_string(JSON.stringify(parsed, "\t"))
	fw.close()


## 还原 fixed.json 里的探针项（原来有就写回原值，原来没有就删掉）
func _restore_fixed_json(probe: String, had: bool, bak: Variant) -> void:
	var path := "user://bow_calib/fixed.json"
	var data: Dictionary = {}
	if FileAccess.file_exists(path):
		var fr := FileAccess.open(path, FileAccess.READ)
		if fr != null:
			var parsed: Variant = JSON.parse_string(fr.get_as_text())
			if parsed is Dictionary:
				data = parsed
	if had and bak != null:
		data[probe] = bak
	else:
		data.erase(probe)
	var fw := FileAccess.open(path, FileAccess.WRITE)
	if fw == null:
		return
	fw.store_string(JSON.stringify(data, "\t"))
	fw.close()


## 「轴体方向定死」自检（31 轮）：鼠标不在轴上时，改方向的键必须**完全无效**；
## 把鼠标挪到轴上后，同一个键必须立刻生效。
## 为什么必须测：闸门拦错了（或拦不住）都**不报错**，只会让用户觉得"时灵时不灵"。
func _run_gate_self_test() -> void:
	var fails := 0
	# ① 鼠标挪到画面角落（远离任何轴 + 远离 UI）⇒ 闸门应关闭
	#
	# ⚠️⚠️ 42 轮修正：`far` **不能写死坐标**。
	#   旧写法 `Vector2(940, 520)` 是"无头视口 1920×1920 下居中偏上"的位置 ——
	#   但**非无头（真窗口）视口是 1920×1080**，原点投影在 (960,540)，
	#   `(940,520)` 距原点只有 28px ⇒ **正好落在六轴交汇处**！
	#   ⇒ 真窗口跑自检必然 FAIL 2（"鼠标在角落却判定压在第 2 根轴上"）。
	#   ⚠️ 这是 41 轮潜伏的坑：自检只被无头跑过，所以从未暴露（红线 18 的同类）。
	#   ⇒ 改为按**当前视口**取"左上角内侧"的点，再用 `_pick_axis` 自证它真的没命中。
	var vsz := get_viewport().get_visible_rect().size
	var far := Vector2(24.0, 24.0)   # 左上角内侧：必远离船/轴/面板
	# 自证：这个点必须**确实**不命中任何轴（否则后面的断言测的不是闸门）
	if not _not_ready():
		var cam_far: Camera3D = _cam_orbit.get_child(0) as Camera3D
		if cam_far != null and int(_pick_axis(far).get("axis", -1)) >= 0:
			fails += 1
			push_error("[selftest] 自检的『角落点』%s 竟然命中了轴体（视口 %s）—— 用例本身失效" % [str(far), str(vsz)])
	_force_mouse(far)
	var hovered := _axis_hover_for_gate()
	if hovered >= 0:
		fails += 1
		push_error("[selftest] 鼠标在角落却判定压在第 %d 根轴上" % hovered)
	var dirs0 := _axis_dirs.duplicate()
	_send_key(KEY_D, false)
	for i in _axis_dirs.size():
		if _axis_dirs[i].distance_to(dirs0[i]) > 0.0001:
			fails += 1
			push_error("[selftest] 闸门没拦住：鼠标不在轴上，第 %d 根轴方向却被改了" % i)
			break
	# ② 鼠标挪到主视图轴（第 0 根）红球端的屏幕位置 ⇒ 闸门应打开
	var cam: Camera3D = _cam_orbit.get_child(0) as Camera3D
	var on_axis: Vector2 = cam.unproject_position(_axis_endpoint_world(0, 1))
	_force_mouse(on_axis)
	# 手动触发一次 hover 刷新（_process 在无头自检里不保证已跑）
	_update_hover(on_axis)
	if _axis_hover_for_gate() < 0:
		fails += 1
		push_error("[selftest] 鼠标已在主视图轴上，闸门却没开（_pick_axis 半径/坐标对不上？）")
	var dirs1 := _axis_dirs.duplicate()
	_send_key(KEY_D, false)
	if _axis_dirs[0].distance_to(dirs1[0]) < 0.0001:
		fails += 1
		push_error("[selftest] 闸门开不了：鼠标压轴上了，第 0 根轴方向还是没动")
	# ── ③ ★38 轮：**改完方向后，六根轴的中心必须仍在原点**（六轴共原点）──
	#
	#   用户报「矮脚鸡修改完，几个轴怎么就围成一圈了？这样我怎么看方向啊」：
	#   旧实现把每根轴的中心偏到自己半长处（`a * ROD_BASE * 0.5`），
	#   默认姿势下"杆一端恰在原点"是**巧合**；方向一改成别的正交轴，
	#   偏移不跟着走 ⇒ 六根杆整体飘开错位，视觉上就是"围成一圈"。
	#
	#   ⚠️ 断言必须**在"方向已被改过"的姿态下**测，且**不能先调 `_reset_all()`**
	#     —— 那会把中心归零、把病根掩盖掉（第一版就是这么写的，反向注入后
	#    仍然 PASS，等于没测）。
	#   ⚠️ 期望值写死 `Vector3.ZERO`（不从 `_axis_centers` 反推），否则自检跟着一起错。
	_axis_dirs[0] = Vector3(-1, 0, 0)   # 模拟"用户把主视图轴转走"
	_axis_dirs[4] = Vector3(0, 0, 1)
	for i in _axis_centers.size():
		if _axis_centers[i].length() > 0.0001:
			fails += 1
			push_error("[selftest] 改过方向后第 %d 根轴中心不在原点（%s）—— 六轴必须共原点，否则会'围成一圈'"
				% [i, str(_axis_centers[i])])
			break
	# 复位姿态与鼠标，别污染后续
	_reset_all()
	_force_mouse(far)
	# ── ④⑤⑥ ★40 轮：**作废 / 锚点 / 清空** 三条新闸门 ───────────────
	# ⚠️ GDScript 的 int 是值语义 ⇒ 不能靠"传引用"累加，必须**接返回值**。
	fails += _run_clear_anchor_self_test()
	if fails == 0:
		print("[probe_bow_box] GATE SELF-TEST PASS 6/6（无悬停锁死方向 / 悬停即可改 / 六轴共原点 / **归档不删旧表** / **锚点对账有牙齿** / **清空当场生效且落盘**)")
	else:
		print("[probe_bow_box] GATE SELF-TEST FAIL %d" % fails)


## ★ 40 轮：作废 / 锚点 / 清空 三条闸门的自检（用户裁决「全部作废、我重标」的配套）。
## **返回失败计数**（GDScript int 值语义，只能靠返回值传出去）。
##
## 为什么必须测满这三条：
##   · 归档：如果"作废"是**真删**，用户之后想对比"我当时改成了啥"就没了 ⇒ 必须验"文件被挪走但可读回"。
##   · 锚点：这是**唯一一条"不靠我自证"**的断言 ⇒ 必须验"它真的有牙齿"（喂错值必须报错）。
##   · 清空：清空如果只清内存不落盘，重启后旧表复活 ⇒ 必须验"磁盘上的表真的变空"。
func _run_clear_anchor_self_test() -> int:
	var fails := 0
	# ── ④ 归档 = 挪走 + 可读回（不是删）──
	#
	# ⚠️⚠️ 第一版这里**自己复刻了一遍 rename**（没调 `_archive_pose_table`），
	#   结果反向注入"把归档改成真删"时**自检照样 PASS** —— 断言测的是复刻代码，
	#   不是真代码路径。这正是红线 40 的陷阱（"取证与实现必须同源"）。
	#   ⇒ 现在改成：**先造一份假姿势表 + 调真函数 `_archive_pose_table()`**。
	var tmp_dir := ProjectSettings.globalize_path("user://bow_calib")
	DirAccess.make_dir_recursive_absolute(tmp_dir)
	var real_pose_backup := ""
	var real_pose_exists := FileAccess.file_exists(POSE_TABLE_PATH)
	if real_pose_exists:
		var rf0 := FileAccess.open(POSE_TABLE_PATH, FileAccess.READ)
		if rf0 != null:
			real_pose_backup = rf0.get_as_text()
			rf0.close()
	# 写真姿势表路径为一份"假的旧表"
	var wf := FileAccess.open(POSE_TABLE_PATH, FileAccess.WRITE)
	if wf == null:
		fails += 1
		push_error("[selftest] 写不进姿势表路径，归档自检无法进行")
		return fails
	wf.store_string('{"__probe__":{"bow":"+X","up":"+Y"}}')
	wf.close()
	# ★ 调**真函数**
	var moved_name := _archive_pose_table()
	var moved_abs := tmp_dir.path_join(moved_name) if moved_name != "" else ""
	var found_moved := moved_name != "" and FileAccess.file_exists(moved_abs)
	if not found_moved:
		fails += 1
		push_error("[selftest] 归档后没找到被挪走的文件（返回名『%s』）—— 作废要么失败了、要么变成了真删，用户无法回溯旧表" % moved_name)
	else:
		# 原路径必须**已消失**（否则旧值会被当成已存姿势摆回轴体）
		if FileAccess.file_exists(POSE_TABLE_PATH):
			fails += 1
			push_error("[selftest] 归档后原路径仍在 —— 旧表没真正失效，_apply_axis_dirs_from_table 会把它当已存姿势摆回轴体")
		# 内容必须可读回、没被截断
		var rf := FileAccess.open(moved_abs, FileAccess.READ)
		if rf == null or not rf.get_as_text().contains("+X"):
			fails += 1
			push_error("[selftest] 归档文件内容读不回来 —— 归档不是搬家而是损坏")
		elif rf != null:
			rf.close()
			var da := DirAccess.open(tmp_dir)
			if da != null:
				da.remove(moved_name)
	# 还原真姿势表
	if real_pose_exists:
		var rw0 := FileAccess.open(POSE_TABLE_PATH, FileAccess.WRITE)
		if rw0 != null:
			rw0.store_string(real_pose_backup)
			rw0.close()
	else:
		DirAccess.remove_absolute(POSE_TABLE_PATH)

	# ── ⑤ ★43 轮：**全库朝敌对账必须有牙齿** ──
	#   ① 手算期望（独立于被测代码）：catalyst 的舰艏世界方向必须是 −Z。
	#      ⚠️ 43 轮血教训：我曾用"行点乘"在源码外手算，得出 5 艘背敌的**假阳性**，
	#        两次据此改坏游戏源码。真因是 `Basis*v` = **列组合**，非对角 spec 会算反。
	#        ⇒ 本处**只调工具真代码 `_axis_dir_to_world`**（红线 40：不自己复刻算式）。
	var real_report := _anchor_report
	var got_cat: Vector3 = _axis_dir_to_world(YAW.bow_axis(&"catalyst"), "catalyst")
	if got_cat.dot(Vector3(0, 0, -1)) <= 0.99:
		fails += 1
		push_error("[selftest] catalyst 的舰艏世界方向不是 −Z（实际 %s）—— `_axis_dir_to_world` 或映射链漂了" % str(got_cat))
	if got_cat.dot(Vector3(0, 0, 1)) > 0.99:
		fails += 1
		push_error("[selftest] catalyst 的舰艏竟同时'朝敌'又'朝 +Z' —— 数学上不可能，返回了非单位向量？")
	#   ② 全库对账必须全过，报告里不得出现 ❌ / 失败
	_run_anchor_check()
	if _anchor_report.contains("❌") or _anchor_report.contains("失败"):
		fails += 1
		push_error("[selftest] 全库朝敌对账没通过：%s" % _anchor_report)
	if not _anchor_report.contains("通过"):
		fails += 1
		push_error("[selftest] 全库朝敌对账报告格式异常：%s" % _anchor_report)
	#   ③ **报告里必须点名每一艘**，不许只给总结数（否则"52 艘里漏看一艘"永远发现不了）
	var checked_n := 0
	for sa in INDEX.all():
		if _anchor_report.contains(String(sa.id)):
			checked_n += 1
	#   报告在"全通过"时只写总结（不逐艘列），故该断言只在**有失败**时才要求点名
	if _anchor_report.contains("❌") and checked_n == 0:
		fails += 1
		push_error("[selftest] 全库对账报了失败，却没点名是哪艘 —— 用户无法定位")
	_anchor_report = real_report

	# ── ⑥ 清空 = 内存 + 磁盘都变空 ──
	var baked_backup := ""
	var baked_exists := FileAccess.file_exists(POSE_TABLE_PATH)
	if baked_exists:
		var bf := FileAccess.open(POSE_TABLE_PATH, FileAccess.READ)
		if bf != null:
			baked_backup = bf.get_as_text()
			bf.close()
	# 先塞一艘假船进表，确认它真被清掉
	_pose_table["__selftest__"] = {"bow": "+X", "up": "+Y", "at": "selftest"}
	_save_pose_table()
	_clear_pose_table_now()
	if _pose_table.has("__selftest__"):
		fails += 1
		push_error("[selftest] 清空后内存里还有假船 ⇒ 清空没清内存")
	var df := FileAccess.open(POSE_TABLE_PATH, FileAccess.READ)
	var disk_empty := true
	if df != null:
		var dp: Variant = JSON.parse_string(df.get_as_text())
		df.close()
		if dp is Dictionary and (dp as Dictionary).has("__selftest__"):
			disk_empty = false
	if not disk_empty:
		fails += 1
		push_error("[selftest] 清空只清了内存，**磁盘上的表还在** ⇒ 重启后旧值会复活")
	# 还原自检前的姿势表（自检不许留痕）
	if baked_exists:
		var rw := FileAccess.open(POSE_TABLE_PATH, FileAccess.WRITE)
		if rw != null:
			rw.store_string(baked_backup)
			rw.close()
	return fails


## ═══ ★41 轮：**世界方向锚**（fixed reference frame，永不随相机/船/轴转动）═══
##
## 唯一目的：让用户在屏幕上**一眼看出世界 −Z（敌人方向）在哪边**。
## 41 轮 52 艘全标反，根因就是画面里没有任何方向基准（详见 `_ready()` 处注释）。
##
## 挂载点 = `_stage` ⇒ 转轴 / 转船 / 转相机都不动它。
##
## ⚠️⚠️ 43 轮：**用户要求删除敌我方向箭头** ──────────────────────────
##   用户原话：「你画个敌人Z轴是想干嘛？…我先用工具确定全部舰船的姿势，
##              然后统一规定舰艏朝向敌人，并与敌人面对面，这样不是很简单吗？」
##   ⇒ 用户的流程是**两步**：① 工具只负责确定"模型出厂姿势"（bow/up 在模型哪根轴）；
##     ② "朝敌"由游戏侧统一完成（`AXIS_REMAP` + `R_y(-90°)` 把模型轴映射到世界 −Z）。
##   ⇒ 工具里画敌人箭头是**多余且有害**的：它把"世界方向"混进了"确定模型姿势"这一步，
##     让用户误以为要手动把船摆到朝敌位置（41 轮 52 艘全标反的诱因之一）。
##
##   42 轮那一整套三重隔离（抬 `ANCHOR_Y` / 换青色 / 准星）**保留其技术价值**，
##   但方向箭头与准星的"锚分支"**已随本次删除一并退场**：
##     · `_build_world_anchor()` 现在**只建水平面网格**（表达"水平面"，给相机仰角当参照）
##     · 敌我箭头函数 `_add_direction_marker()` **保留但不再被调用**（历史留档，见函数注释）
##     · `ANCHOR_Y` / `ANCHOR_COL_*` 常量保留（网格仍用 `ANCHOR_COL_GRID`）
##   ⇒ ⚠️ 网格**必须留在水平面**（y≈0）——它表达的就是水平面本身，抬起来反而误导。
##
## ⚠️ `ANCHOR_Y` 是**实测调出来的**：0.62 = 船体归一化半径(≈0.52) × 1.2。
##   43 轮起它只对"历史留档的 `_add_direction_marker`"有意义；当前无调用者。
const ANCHOR_Y := 0.62
const ANCHOR_COL_ENEMY := Color(0.10, 0.90, 0.95)   ## 青 —— 【43 轮起不再使用】
const ANCHOR_COL_ALLY := Color(0.25, 0.60, 1.00)    ## 青蓝 —— 【43 轮起不再使用】
const ANCHOR_COL_GRID := Color(0.30, 0.52, 0.60, 0.55)
## ★ 42 轮：锚杆屏幕线段 ↔ 轴 bow 红球的最短屏距（自检填、HUD 显示，供人工核对）。
##   实测：旧摆法(Y=0) = 0.0 px（锚杆正好穿过红球）；抬升后(Y=0.62) = 295 px。
##   ⚠️ 43 轮起锚杆已删除 ⇒ 该值恒为哨兵值；保留变量以免 HUD/自检大改。
var _anchor_gap_note: String = "（43 轮起工具无方向锚 —— 只画水平面网格）"


func _build_world_anchor() -> void:
	# ── XZ 平面网格（ImmediateMesh 画线，避免实心面挡船）──
	#   ⚠️ 网格**留在水平面**（y=0 略下），它表达的就是"水平面"本身；
	#     抬起来反而误导。轴体与船都在这个面上。
	var grid_mi := MeshInstance3D.new()
	grid_mi.name = "GroundGridWire"
	var im := ImmediateMesh.new()
	var half := ANCHOR_LEN * 1.25
	var step := ANCHOR_LEN / 5.0
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	for k in range(-5, 6):
		var t := float(k) * step
		im.surface_add_vertex(Vector3(t, 0, -half))   # 沿 Z 的格线
		im.surface_add_vertex(Vector3(t, 0, half))
		im.surface_add_vertex(Vector3(-half, 0, t))   # 沿 X 的格线
		im.surface_add_vertex(Vector3(half, 0, t))
	im.surface_end()
	grid_mi.mesh = im
	var gl := StandardMaterial3D.new()
	gl.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gl.albedo_color = ANCHOR_COL_GRID
	gl.cull_mode = BaseMaterial3D.CULL_DISABLED
	grid_mi.material_override = gl
	grid_mi.position = Vector3(0, -0.03, 0)   # 略低于船，避免 z-fighting
	_stage.add_child(grid_mi)
	# ── ★43 轮：敌我方向箭头**已删除**（用户要求）──
	#   `_add_direction_marker()` 保留为历史留档，但**不再调用**：
	#     _add_direction_marker(Vector3(0, 0, -1), "敌人 −Z", ANCHOR_COL_ENEMY, true, ANCHOR_Y)
	#     _add_direction_marker(Vector3(0, 0, 1), "我方 +Z", ANCHOR_COL_ALLY, false, ANCHOR_Y)


## ⚠️ 43 轮：**本函数已无调用者**（敌我方向箭头按用户要求删除）。
##   保留原因：42 轮"锚与轴在屏幕上重叠导致 52 艘全标反"这个坑的**完整修复方案**就在这里
##   （抬 `y_off` + 换色 + 准星），将来若又要引入任何"参照物"，直接照抄这套隔离手法，
##   不要重新发明。删除它等于丢掉这条经验。
##
## 加一根"方向标记"：从原点沿 `dir` 的杆 + 末端圆头 + 文字标牌。
## `loud` = true ⇒ 更粗更亮（给敌人方向用）。
## `y_off` = 整根锚沿世界 +Y 的抬升量（42 轮新增，把锚抬离水平面避免与轴重叠）。
##
## ⚠️ 几何要点：杆**从原点附近起步**（不玩"从 0.5L 开始"那套），
##   这样"标记 + 船"始终落在同一个视觉区域 ⇒ 用户能把两者直接比对。
##   （41 轮第一版从 0.5L 起步、总长 1.55 ⇒ 俯视机位两端全出屏，白做。）
func _add_direction_marker(dir: Vector3, label: String, col: Color, loud: bool, y_off: float) -> void:
	var d := dir.normalized()
	var base := Vector3(0.0, y_off, 0.0)
	var thick := ANCHOR_THICK * (2.2 if loud else 1.2)
	var shaft_len := ANCHOR_LEN * (1.0 if loud else 0.78)
	var clean := label.replace(" ", "").replace("−", "m").replace("+", "p")
	var mk := StandardMaterial3D.new()
	mk.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mk.albedo_color = col
	mk.cull_mode = BaseMaterial3D.CULL_DISABLED
	# 杆：从 base 起，长度 shaft_len ⇒ 中心在 base + d*(shaft_len/2) 处
	var rod := MeshInstance3D.new()
	rod.name = "AnchorRod_%s" % clean
	var bm := BoxMesh.new()
	bm.size = Vector3(thick, thick, shaft_len)
	rod.mesh = bm
	rod.material_override = mk
	rod.basis = Basis.looking_at(d, Vector3.UP if absf(d.y) < 0.9 else Vector3.FORWARD)
	rod.position = base + d * (shaft_len * 0.5)
	_stage.add_child(rod)
	# 末端圆头
	var tip := MeshInstance3D.new()
	tip.name = "AnchorTip_%s" % clean
	var sm := SphereMesh.new()
	sm.radius = thick * (2.0 if loud else 1.3)
	sm.height = sm.radius * 2.0
	tip.mesh = sm
	tip.material_override = mk
	tip.position = base + d * shaft_len
	_stage.add_child(tip)
	# 文字标牌（billboard + no_depth_test ⇒ 永远正对相机、不被船遮挡）
	var lb := Label3D.new()
	lb.name = "AnchorLabel_%s" % clean
	lb.text = label
	lb.font_size = 44 if loud else 32
	lb.pixel_size = 0.0030 if loud else 0.0026
	lb.outline_size = 12
	lb.modulate = col.lightened(0.30)
	lb.outline_modulate = Color(0.02, 0.03, 0.05, 0.98)
	lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lb.no_depth_test = true
	lb.position = base + d * (shaft_len + 0.17)
	_stage.add_child(lb)


## 直接设定"鼠标位置"（无头下没有真实鼠标，只能注入到我们的镜像变量里）
func _force_mouse(p: Vector2) -> void:
	_mouse_screen_pos = p
	_mouse_in_view = true
	# ★★ 42 轮修正：**注入锁** ───────────────────────────────────────
	#   `_process()` 每帧用 `get_viewport().get_mouse_position()` 覆盖
	#   `_mouse_screen_pos`。**无头**下视口鼠标恒在 (0,0)（我们的注入能活下来），
	#   但**非无头**（真窗口）下真实鼠标位置会瞬间把注入值冲掉 ⇒
	#   GATE 自检在真窗口里必然 FAIL 2（"鼠标在角落却判定压在第 2 根轴上"）。
	#   ⚠️ 这是 41 轮就潜伏的坑：自检只在无头下被跑过，所以从没暴露。
	#   ⇒ 注入期间置锁，`_process` 不覆盖；`_release_mouse()` 解锁。
	_mouse_inject_lock = true


## 解除注入锁（自检用例跑完必须调，否则用户真正的鼠标会"失灵"）。
func _release_mouse() -> void:
	_mouse_inject_lock = false


## 造一个 InputEventKey 直接送进 _input（模拟真实按键的物理键码 + Shift 状态）。
## ⚠️ 关键：按住 Shift 时真实键盘的 `keycode` **不是** `]` 而是 `}`（US 布局），
## 所以这里必须把 keycode 也换成 Shift 后的符号码，否则自检测不出
## "读 keycode 就失聪"这个 bug（第一次写自检时正是这么漏掉的）。
func _send_key(physical_code: int, shift: bool) -> void:
	var ev := InputEventKey.new()
	ev.pressed = true
	ev.physical_keycode = physical_code
	ev.keycode = _shift_mangled_code(physical_code) if shift else physical_code
	ev.shift_pressed = shift
	_input(ev)


## US 布局下 Shift+键的 "keycode"（物理位的字符变体）。
## ⚠️ 32 轮键位改成 WASD/QE 后，这些字母键**不受 Shift 影响**（`W` 按 Shift 仍是 `W`），
## 所以本函数对当前键位其实返回原值；保留旧条目是为了万一回退到符号键位时自检仍有效。
func _shift_mangled_code(physical_code: int) -> int:
	match physical_code:
		KEY_BRACKETLEFT: return KEY_BRACELEFT
		KEY_BRACKETRIGHT: return KEY_BRACERIGHT
		KEY_COMMA: return KEY_LESS
		KEY_PERIOD: return KEY_GREATER
		KEY_MINUS: return KEY_UNDERSCORE
		KEY_EQUAL: return KEY_PLUS
		KEY_1: return KEY_EXCLAM
		KEY_2: return KEY_AT
		KEY_3: return KEY_NUMBERSIGN
		_: return physical_code


## 把 from 转成 to 的最小旋转（两者均按单位向量处理）
func _basis_from_to(from: Vector3, to: Vector3) -> Basis:
	var f := from.normalized()
	var t := to.normalized()
	var d := clampf(f.dot(t), -1.0, 1.0)
	if d > 0.999999:
		return Basis.IDENTITY
	if d < -0.999999:
		var ax := f.cross(Vector3.RIGHT)
		if ax.length_squared() < 0.0001:
			ax = f.cross(Vector3.UP)
		return Basis(ax.normalized(), PI)
	return Basis(f.cross(t).normalized(), acos(d))


## ══════════════════════════════════════════════════════════════════
##  右侧舰船选择面板
## ══════════════════════════════════════════════════════════════════
##  设计口径（用户 29 轮要求）：
##   · **列全库 52 艘**（不是只列 --ids 那几艘）——"把所有舰船都加入备选"
##   · 点一行 = 切到那艘船（保持轴体姿势与镜头，方便同构船对比）
##   · 顶部搜索框按 id 子串过滤（52 艘滚动找很累）
##   · 已在 SHIP_AXES 登记过的船显示已登录的 bow/up，一眼能看出哪些是"待复核"
func _build_ship_panel() -> void:
	_ship_panel = PanelContainer.new()
	_ship_panel.name = "ShipSelector"
	_ship_panel.anchor_left = 1.0
	_ship_panel.anchor_right = 1.0
	_ship_panel.anchor_top = 0.0
	_ship_panel.anchor_bottom = 1.0
	_ship_panel.offset_left = -292.0
	_ship_panel.offset_right = -12.0
	_ship_panel.offset_top = 12.0
	_ship_panel.offset_bottom = -12.0
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.09, 0.13, 0.90)
	sb.border_color = Color(0.30, 0.40, 0.58, 0.90)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(10)
	_ship_panel.add_theme_stylebox_override("panel", sb)
	add_child(_ship_panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	_ship_panel.add_child(vb)

	var title := Label.new()
	title.text = "舰船选择（全库 %d 艘）" % INDEX.all().size()
	title.add_theme_color_override("font_color", Color(0.85, 0.90, 1.0))
	vb.add_child(title)

	_ship_search = LineEdit.new()
	_ship_search.placeholder_text = "搜索：中文名 / 英文名 / id"
	_ship_search.text_changed.connect(func(_t: String) -> void: _refresh_ship_list())
	vb.add_child(_ship_search)

	_ship_list = ItemList.new()
	_ship_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_ship_list.add_theme_color_override("font_color", Color(0.88, 0.92, 1.0))
	_ship_list.item_selected.connect(_on_ship_list_selected)
	vb.add_child(_ship_list)

	# 面板必须吃掉自己的输入，否则点列表会穿透到底下的镜头拖拽
	_ship_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_refresh_ship_list()


func _refresh_ship_list() -> void:
	if _ship_list == null:
		return
	var q := _ship_search.text.strip_edges().to_lower() if _ship_search != null else ""
	_ship_list.clear()
	_list_ids = PackedStringArray()
	var select_row := -1
	for s in INDEX.all():
		var sid := String(s.id)
		# 搜索同时匹配 **中文名 / 英文名 / id**（三个都能查到，用户不用记 asset id）
		if q != "":
			var hay := "%s %s %s" % [String(s.cn), String(s.name_en), sid]
			if hay.to_lower().find(q) < 0:
				continue
		var cur := "%s/%s" % [_axis_name(YAW.bow_axis(StringName(sid))), _axis_name(YAW.up_axis(StringName(sid)))]
		# ★ 36 轮：列表的 ✔ **由「姿势表」驱动**（43 轮修正为跨会话持久）。
		#   36 轮原文："只有在我按下回车键，保存了当前舰船姿势才打√"。
		#   ⚠️ 43 轮：原实现只读 `_fixed_ships`（本次会话临时打勾），
		#      重开工具后 52 艘**一个 √ 都没有** ⇒ 用户以为"修改全丢了/回到默认"。
		#   ✅ 修正：**姿势表里有登记就显示 √**（那是真实的、已落盘的凭证）；
		#      `_fixed_ships` 保留为"本次会话刚按的回车"，两者取或。
		#      这样同一个√有两种含义都成立：刚标的 / 历史已标的，且都**真实可查**。
		var fixed_mark := "✔" if (_pose_table.has(sid) or _fixed_ships.has(sid)) else " "
		var star := "◆" if sid == _cur_sid else "·"
		# 主显示中文名（用户要求）· 括号里保留英文名便于对官方资料 · 右侧是已登记语义轴
		_ship_list.add_item("%s %s %s（%s）  %s" % [fixed_mark, star, String(s.cn), String(s.name_en), cur])
		_list_ids.append(sid)
		if sid == _cur_sid:
			select_row = _list_ids.size() - 1
	if select_row >= 0:
		_ship_list.select(select_row)
		_ship_list.ensure_current_is_visible()


func _on_ship_list_selected(index: int) -> void:
	if index < 0 or index >= _list_ids.size():
		return
	_switch_to_ship(_list_ids[index])


## 切船：优先在 _ids 里找；找不到（--ids 限定过）就追加进去再跳。
## 切换后**保留**轴体中心/缩放与镜头角度（同构船对照很有用），
## 但**清空舰船自身旋转与轴体方向**——否则上一艘的船姿/轴姿会张冠李戴到新船上，
## 用户会以为"上一艘明明标好了怎么变成这样"（34 轮用户报的就是这个观感）。
func _switch_to_ship(sid: String) -> void:
	var found := -1
	for i in _ids.size():
		if String(_ids[i]) == sid:
			found = i
			break
	if found < 0:
		_ids.append(sid)
		found = _ids.size() - 1
	_idx = found
	_load_current()
	# ★ 35 轮：切船后把轴体摆到**规则表登记值**对应的干净基线，
	#   并刷新 HUD 的「表内现值」。旧版只是 `_reset_axis_pose()`，
	#   用户点回上一艘看不出"到底写没写进去"。
	_apply_axis_dirs_from_table(sid)
	_refresh_axis_visual()
	_refresh_ship_list()
	_refresh_hud()


func _build_orbit_camera() -> Node3D:
	var root := Node3D.new()
	var cam := Camera3D.new()
	cam.fov = 45.0
	cam.near = 0.1
	cam.far = 100.0
	cam.position = Vector3(0, 0, 2.6)
	root.add_child(cam)
	var state := _OrbitState.new()
	root.set_meta("orbit_state", state)
	return root


## ⚠️ 键码必须用 `physical_keycode`（按物理位置），**不能用 `keycode`**：
## 按住 Shift 时 `keycode` 会变成 "{"、"}"、"<"、">"、"_"、"+" 等符号码，
## `match KEY_BRACKETLEFT` 全部落空 ⇒ **Shift 转船完全没反应**（29 轮实测踩到）。
## 对比 `event.is_shift_pressed()` 同理：EventKey 上应读 `event.shift_pressed`。
func _input(event: InputEvent) -> void:
	var handled := false
	# ⚠️ UI 优先：鼠标落在右侧选择面板/按钮上时，3D 层**一律不处理**，
	# 否则点列表会同时触发镜头拖拽 / 轴体拾取（点一下船就飞了）。
	if event is InputEventMouse and _pointer_over_ui((event as InputEventMouse).position):
		return
	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _drag_axis >= 0:
			_apply_axis_drag(mm.position)
			handled = true
		elif _ship_dragging:
			# 右键拖动 = 转**船**（轴体不动）。水平→绕 Y，垂直→绕 X。
			_ship_yaw -= mm.relative.x * 0.01
			_ship_pitch -= mm.relative.y * 0.01
			_apply_ship_transform()
			handled = true
		else:
			_update_hover(mm.position)
			if _orbit_state.dragging:
				_orbit_state.yaw -= mm.relative.x * 0.01
				_orbit_state.pitch += mm.relative.y * 0.01
				_orbit_state.pitch = clampf(_orbit_state.pitch, -1.4, 1.4)
				_apply_orbit()
				handled = true
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			_ship_dragging = mb.pressed
			handled = true
		elif mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			# 只有**鼠标已经悬停在该轴**时才能起拖（31 轮"定死"闸门）。
			# 不接受"擦边命中"：必须与当前高亮的那根一致。
			var hit := _pick_axis(mb.position)
			var hit_i := int(hit.get("axis", -1))
			if hit_i >= 0 and hit_i == _hover_axis:
				_begin_axis_drag(hit_i, int(hit.endpoint), mb.position)
				handled = true
			else:
				_orbit_state.dragging = true
				handled = true
		elif mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			if _drag_axis >= 0:
				_end_axis_drag()
			elif _orbit_state.dragging:
				_orbit_state.dragging = false
			handled = true
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_root_scale = clampf(_root_scale * 0.9, 0.2, 5.0)
			_apply_axis_root_transform(); _refresh_axis_visual(); handled = true
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_root_scale = clampf(_root_scale * 1.1, 0.2, 5.0)
			_apply_axis_root_transform(); _refresh_axis_visual(); handled = true
	elif event is InputEventKey and event.pressed:
		var k := event as InputEventKey
		# Shift 按下 = 只转**船**；不按 = 只转**轴体**。两者永不互相带动。
		var rot_ship := k.shift_pressed
		var step := deg_to_rad(15.0)
		var code := k.physical_keycode
		# ── 轴体方向"定死"闸门（31 轮）───────────────────────────────
		# 会改**轴体方向**的操作（裸 W/A/S/D）只许在"鼠标正压在轴体上"时执行；
		# 只做**位置/大小**的操作（裸 Q/E·滚轮·R·翻艘）保持全局可用。
		var hovered := _axis_hover_for_gate()
		var can_rotate_axis := hovered >= 0
		# ── 键位分工（32 轮直觉方向键 · 33 轮改为**只转悬停的那一根**）─────
		#   Shift + WASD = **转船**（W 上仰 / S 下俯 / A 左转 / D 右转）
		#   裸 WASD     = **转鼠标悬停的那一根轴**（其余 5 根纹丝不动）
		#   Q / E       = 平移轴体中心（前后）—— 原 WASD 的平移职责让给 QE
		#   Shift + Q/E = 转船**侧躺**（绕 Z，即用户说的"侧躺按钮"）
		# ⚠️ 顺序很关键：**先判 Shift（转船，不受闸门限制）**，再判裸键（转轴体，要闸门）。
		#
		# ★ 33 轮核心修正（用户报"只转一根，怎么全部都在转"）：
		#   旧版 `_group_pitch += step` 改的是**整组**旋转量，六根共用一份 ⇒ 全转。
		#   现在一律调 `_rotate_single_axis(hovered, ...)`，只动 `_axis_dirs[hovered]`。
		match code:
			KEY_W:
				if rot_ship: _ship_pitch += step; _apply_ship_transform(); handled = true
				elif can_rotate_axis: _rotate_single_axis(hovered, step, 0.0, 0.0); handled = true
				else: _flash_gate_hint()
			KEY_S:
				if rot_ship: _ship_pitch -= step; _apply_ship_transform(); handled = true
				elif can_rotate_axis: _rotate_single_axis(hovered, -step, 0.0, 0.0); handled = true
				else: _flash_gate_hint()
			KEY_A:
				if rot_ship: _ship_yaw += step; _apply_ship_transform(); handled = true
				elif can_rotate_axis: _rotate_single_axis(hovered, 0.0, step, 0.0); handled = true
				else: _flash_gate_hint()
			KEY_D:
				if rot_ship: _ship_yaw -= step; _apply_ship_transform(); handled = true
				elif can_rotate_axis: _rotate_single_axis(hovered, 0.0, -step, 0.0); handled = true
				else: _flash_gate_hint()
			KEY_Q:
				if rot_ship: _ship_roll += step; _apply_ship_transform(); handled = true
				else: _root_pos.z -= 0.05; _apply_axis_root_transform(); handled = true
			KEY_E:
				if rot_ship: _ship_roll -= step; _apply_ship_transform(); handled = true
				else: _root_pos.z += 0.05; _apply_axis_root_transform(); handled = true
			KEY_R:
				_reset_all(); handled = true
			KEY_RIGHT, KEY_DOWN:
				# ★ 37 轮：翻艘也必须走 `_switch_to_ship()`（含"按姿势表还原轴体"），
				#   旧的裸 `_load_current() + _refresh_axis_visual()` 会留下上一艘的
				#   轴体方向 ⇒ 和"点列表切船"行为不一致（同一个 bug 的两条入口）。
				_switch_to_ship(String(_ids[(_idx + 1) % _ids.size()])); handled = true
			KEY_LEFT, KEY_UP:
				_switch_to_ship(String(_ids[(_idx - 1 + _ids.size()) % _ids.size()])); handled = true
			KEY_ENTER, KEY_KP_ENTER: _on_confirm_pressed(); handled = true
			KEY_DELETE:
				# ★ 40 轮：`Ctrl + Delete` = **当场清空姿势表**（重新标定前想推倒重来时用）。
				#   与"启动自动归档"互补：那个管历史遗留，这个管本次操作失误。
				if k.ctrl_pressed:
					_clear_pose_table_now(); handled = true
			KEY_H:
				# ★ 40 轮：`H` = 重跑**锚点自检**（拿已知真值船对账，随时可验）。
				_run_anchor_check(); _refresh_hud(); handled = true
			KEY_ESCAPE: get_tree().quit(0); handled = true
			_:
				# 同样读 code（physical），Shift 下 1~6 的 keycode 会变成 !@#$%^
				# 缩放**只作用于鼠标悬停的那一根**（旧版按 1=主视图/2=后视图 的
				# 固定映射已废弃——那会让"没碰到的轴自己变长变短"）。
				if code >= KEY_1 and code <= KEY_6:
					var i := code - KEY_1
					var target := hovered if hovered >= 0 else -1
					if target >= 0:
						_axis_scales[target] = clampf(_axis_scales[target] * (1.15 if i % 2 == 0 else 0.87), 0.2, 4.0)
						_refresh_axis_visual(); handled = true
					else:
						_flash_gate_hint()
	if handled:
		_refresh_hud()


## 闸门拦下操作时的提示（写进 HUD 末尾，短暂显示）
var _gate_hint: String = ""
var _gate_hint_frames: int = 0


func _flash_gate_hint() -> void:
	_gate_hint = "⛔ 轴体已锁定：请先把鼠标移到要调整的那根轴上"
	_gate_hint_frames = 90
	_refresh_hud()


## 指针是否落在 UI 控件（右侧选择面板 / 确定按钮）上。
## 用 rect.has_point 而不是 get_global_rect()，因为面板用 anchor 布局，
## 其 rect 已是屏幕坐标；这样即使锚点在窗口 resize 后也成立。
## ⚠️ 41 轮改名：本函数是全文件**唯一**的"指针压在 UI 上吗"判定实体，
##   由 `_pointer_over_ui`(准星侧留的同名包装) 与 `_input` 共用 ——
##   绝不复制第二份判定（红线 40：复刻会与真实闸门漂移）。
func _ui_rects_hit(p: Vector2) -> bool:
	if _ship_panel != null and _ship_panel.visible and _ship_panel.get_global_rect().has_point(p):
		return true
	if _confirm_btn != null and _confirm_btn.visible and _confirm_btn.get_global_rect().has_point(p):
		return true
	return false


## 每帧刷新鼠标位置（键盘事件里要用它判"是否压在轴体上"）。
## ⚠️ 不能只在 InputEventMouseMotion 里记：用键盘操作时鼠标可能一直不动，
## 但位置依然是有效的——只在移动时记会让"定死"闸门时灵时不灵。
func _process(_delta: float) -> void:
	if get_viewport() == null:
		return
	# 闸门提示自动消退
	if _gate_hint_frames > 0:
		_gate_hint_frames -= 1
		if _gate_hint_frames == 0:
			_gate_hint = ""
			_refresh_hud()
	# ★ 42 轮：**注入锁**期间不许覆盖（否则真窗口下自检的鼠标注入被真实鼠标冲掉）
	if not _mouse_inject_lock:
		_mouse_screen_pos = get_viewport().get_mouse_position()
		_mouse_in_view = Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size).has_point(_mouse_screen_pos)
	# ★ 41 轮：准星每帧重画 —— 它是"鼠标此刻会命中谁"的唯一可视答案，
	#   必须与 `_pick_axis` 同帧同值（不许缓存，否则用户看到的字会落后一帧）
	_refresh_aim_reticle()
	var valid := _axis_hover_for_gate() >= 0
	if valid != _last_hover_valid:
		_last_hover_valid = valid
		_refresh_hud()


## 「是否压在轴体上」的判定闸门。返回压在轴上的那条索引，否则 -1。
## 三重排除：鼠标不在视口内 / 落在 UI 上 / 没有任何轴被拾取 ⇒ 都算"没压上"。
func _axis_hover_for_gate() -> int:
	if _not_ready() or not _mouse_in_view:
		return -1
	if _pointer_over_ui(_mouse_screen_pos):
		return -1
	var hit := _pick_axis(_mouse_screen_pos)
	var i := int(hit.get("axis", -1))
	# 拾取半径与可见性对齐：太远的"擦边命中"不算压在轴上
	return i if i == _hover_axis or i >= 0 else -1


func _not_ready() -> bool:
	return _axis_root == null or _cam_orbit == null


## R 键：轴体与舰船各自归零（两者独立，必须都清）
func _reset_all() -> void:
	_root_pos = Vector3.ZERO
	_root_scale = 1.0
	_ship_yaw = 0.0
	_ship_pitch = 0.0
	_ship_roll = 0.0
	for i in _axis_scales.size():
		_axis_scales[i] = 1.0
		# ★ 38 轮：中心一律回原点（六轴共原点，方向才是唯一变量）
		_axis_centers[i] = Vector3.ZERO
		_axis_dirs[i] = VIEW_AXES[i].normalized()
	_apply_axis_root_transform()
	_apply_ship_transform()
	_refresh_axis_visual()
	_apply_axis_root_transform()
	_apply_ship_transform()
	_refresh_axis_visual()


func _pick_axis(screen_pos: Vector2) -> Dictionary:
	var cam: Camera3D = _cam_orbit.get_child(0) as Camera3D
	var best_axis := -1
	var best_endpoint := -1
	var best_dist := 1e9
	for i in VIEW_AXES.size():
		var rod: MeshInstance3D = _axis_root.get_node("Rod_%d_%s" % [i, VIEW_NAMES[i]])
		var a: Vector2 = cam.unproject_position(_axis_endpoint_world(i, 1))
		var b: Vector2 = cam.unproject_position(_axis_endpoint_world(i, -1))
		var d_red := screen_pos.distance_to(a)
		var d_blue := screen_pos.distance_to(b)
		if d_red < 26.0 and d_red < best_dist:
			best_dist = d_red; best_axis = i; best_endpoint = 0
		if d_blue < 26.0 and d_blue < best_dist:
			best_dist = d_blue; best_axis = i; best_endpoint = 1
		var seg_d := _distance_to_segment_2d(screen_pos, a, b)
		if seg_d < 18.0 and seg_d < best_dist:
			best_dist = seg_d; best_axis = i; best_endpoint = -1
	return {"axis": best_axis, "endpoint": best_endpoint}


## ★★★ 41 轮核心修正：**瞄准辅助（红色十字准星）** ═══════════════════════
##
## ── 为什么必须有它（41 轮 52 艘全标反的真病根）──────────────────────
##   用户连标 52 艘全部 180°。逐层查完：工具算法全对、落表反解在位、
##   红蓝球跟着轴走、方向锚也渲染出来了 —— 但**用户仍然标反**。
##   决定性对比（41 轮 PIL 实测 1920×1080 截图）：
##       用户"想瞄"的物体（轴体 bow 红球）  → 屏幕 (1040, 511)
##       用户"实际瞄到"的物体（敌人方向锚）  → 屏幕 (1058, 557)
##       两者屏幕距 **2 px**，颜色还都是红（255,56,46 vs 242,41,41）
##   ⇒ 悬停闸门（`_pick_axis`）判"鼠标在轴上"，于是**箭头键转动的是轴，
##     用户却以为在拖方向锚** —— 转完方向锚纹丝不动、轴悄悄转了。
##     用户按看到的"红球位置"落表 ⇒ 整批 180°。**全程不报错**。
##
## ── 修法 ─────────────────────────────────────────────────────
##   不靠"把两个东西画开"（几何上必然重叠：方向锚与主视图轴**共线**，
##   都在世界 −Z 上 —— 这是几何事实，调参调不掉）。
##   改为**把"鼠标此刻会命中谁"直接画在屏幕上**：
##     · 十字准星 + 命中名（「主视图轴·红端」/「敌人方向（纯参照，不可拖）」…）
##     · 未命中任何东西 ⇒ 显示「未命中」灰色准星
##   ⇒ 用户盯着准星上的字调，不再依赖"我记得红的是船头"。
##
## ── 判据（写死，不许从被测变量反推）─────────────────────────────
##   `_hover_name_for(screen_pos)` 的返回值必须与 `_pick_axis` 的判定**逐项一致**，
##   且方向锚命中时必须回**不可拖**文案。自检里对 3 个典型屏幕点做交叉断言。
const AIM_ARMED_R := 9.0    ## 准星座半径（px）—— 十字中心会挡视线，故留空
const AIM_ARM_LEN := 22.0   ## 十字臂长（px）
var _aim_panel: Control = null
var _aim_label: Label = null


func _pointer_over_ui(screen_pos: Vector2) -> bool:
	# ⚠️ 41 轮：**只调用既有的 rect 判定逻辑**，不再复刻一份。
	#   复刻 = 红线 40 的陷阱（两份判定迟早漂移，画面上写的字会与真实闸门不一致）。
	return _ui_rects_hit(screen_pos)


## 鼠标位置的**人类可读**命中说明（不依赖 `_pick_axis` 的返回值单打独斗：
## 这里显式调它，保证"画出来的字"与"实际的闸门判定"同源，红线 40）。
##
## ★ 43 轮：**「咬到方向锚」分支已删除** —— 用户要求删掉敌我方向箭头，
##   锚已不存在 ⇒ 该分支永远不可达，留着反而误导（准星会说"你咬到锚了"，但画面上没有锚）。
##   ⚠️ `_anchor_hit()` 随之无调用者，保留为历史留档（见其注释）。
func _hover_name_for(screen_pos: Vector2) -> String:
	if _pointer_over_ui(screen_pos):
		return "▤ 鼠标在面板/按钮上 —— 轴体与镜头都不响应"
	var hit := _pick_axis(screen_pos)
	var a := int(hit.get("axis", -1))
	if a < 0:
		return "○ 未命中 —— 鼠标移上去的一瞬它就会被锁住"
	var ep := int(hit.get("endpoint", -1))
	if ep == 0:
		return "▶ 「%s」的【红球端】—— 裸方向键只转这一根" % VIEW_NAMES[a]
	if ep == 1:
		return "▶ 「%s」的【蓝球端】—— 裸方向键只转这一根" % VIEW_NAMES[a]
	return "▶ 「%s」杆身 —— 裸方向键只转这一根" % VIEW_NAMES[a]


## ⚠️ 43 轮：**本函数已无调用者**（敌我方向锚按用户要求删除）。
##   保留原因：它是 41 轮"52 艘全标反"那次的**诊断器官** ——
##   "_anchor_hit + 准星文案" 这套组合能在画面上当场指出"你咬的不是你以为的东西"。
##   将来若又引入任何可拾取的参照物，直接复用本函数 + `_hover_name_for` 的分支。
##
## 方向锚是否被"咬"到（屏幕距 < 轴体拾取半径）。
## ⚠️ 这个函数只用于**告诉用户"你咬到的是锚"**，绝不用于改变闸门行为
##   （闸门行为保持原样，否则等于偷偷挪走了 bug，而不是让用户看见它）。
func _anchor_hit(screen_pos: Vector2) -> bool:
	var cam: Camera3D = _cam_orbit.get_child(0) as Camera3D
	if cam == null:
		return false
	for c in _stage.get_children():
		var cn := String(c.name)
		if not cn.begins_with("AnchorRod_"):
			continue
		var mi := c as MeshInstance3D
		if mi == null:
			continue
		var p: Vector2 = cam.unproject_position(mi.global_position)
		if screen_pos.distance_to(p) < 26.0:
			return true
	return false


func _build_aim_reticle() -> void:
	var root := Control.new()
	root.name = "AimReticle"
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.draw.connect(func() -> void: _draw_aim_reticle(root, _mouse_screen_pos))
	add_child(root)
	_aim_panel = root
	_aim_label = Label.new()
	_aim_label.add_theme_color_override("font_color", Color(1.0, 0.98, 0.72))
	_aim_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_aim_label.add_theme_constant_override("outline_size", 6)
	_aim_label.add_theme_font_size_override("font_size", 26)
	_aim_label.position = Vector2(18, 18)
	_aim_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_aim_label)


func _refresh_aim_reticle() -> void:
	if _aim_panel == null:
		return
	if _aim_label != null:
		_aim_label.text = "准星瞄准：%s" % _hover_name_for(_mouse_screen_pos)
	_aim_panel.queue_redraw()


func _draw_aim_reticle(canvas: CanvasItem, screen_pos: Vector2) -> void:
	var hit := _hover_name_for(screen_pos)
	var col := Color(0.55, 0.60, 0.70, 0.85)          # 默认：未命中 = 灰
	if hit.begins_with("▶"):
		col = Color(0.25, 1.0, 0.55, 0.95)            # 命中轴 = 亮绿
	elif hit.begins_with("⛔"):
		col = Color(1.0, 0.35, 0.15, 0.95)            # 咬到锚 = 橙红警告
	elif hit.begins_with("▤"):
		col = Color(0.55, 0.70, 1.0, 0.85)            # 面板 = 蓝
	var c := screen_pos
	# 十字（中心留空 AIM_ARMED_R，避免挡住用户真正要看的红球）
	for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		canvas.draw_line(c + d * AIM_ARMED_R, c + d * AIM_ARM_LEN, col, 3.0)
	# 外圈
	var pts := PackedVector2Array()
	for k in 25:
		var t := TAU * float(k) / 24.0
		pts.append(c + Vector2(cos(t), sin(t)) * (AIM_ARM_LEN + 5.0))
	canvas.draw_polyline(pts, col, 2.0)
	# 命中轴时额外画一个"这一段就是你要转的"指示环
	if hit.begins_with("▶"):
		canvas.draw_arc(c, AIM_ARMED_R + 3.0, 0.0, TAU, 32, col, 2.0)


func _update_hover(screen_pos: Vector2) -> void:
	var hit := _pick_axis(screen_pos)
	var next := int(hit.get("axis", -1))
	if next == _hover_axis:
		_refresh_aim_reticle()
		return
	_hover_axis = next
	_set_axis_highlight(_hover_axis)
	_refresh_aim_reticle()



func _set_axis_highlight(index: int) -> void:
	for i in VIEW_AXES.size():
		var rod: MeshInstance3D = _axis_root.get_node("Rod_%d_%s" % [i, VIEW_NAMES[i]])
		var active := i == index
		rod.material_override = _mat(Color(1.0, 0.78, 0.20) if active else Color(0.78, 0.80, 0.86))
		# ⚠️ 41 轮：同样必须**按名字取球**（原因见 `_axis_root` 构建处的长注释）——
		#   这里若取错，高亮会把颜色刷到错误的节点上（更隐蔽：看起来"能动"但其实错位）。
		var red := _axis_root.get_node("Ball_%d_%s_plus" % [i, VIEW_NAMES[i]]) as MeshInstance3D
		var blue := _axis_root.get_node("Ball_%d_%s_minus" % [i, VIEW_NAMES[i]]) as MeshInstance3D
		if red == null or blue == null:
			continue
		red.material_override = _mat(Color(1.0, 0.92, 0.18) if active else Color(0.95, 0.16, 0.16))
		blue.material_override = _mat(Color(0.35, 0.75, 1.0) if active else Color(0.16, 0.38, 0.98))


func _begin_axis_drag(index: int, endpoint: int, screen_pos: Vector2) -> void:
	_drag_axis = index
	_drag_endpoint = endpoint
	_hover_axis = index
	_set_axis_highlight(index)
	var cam: Camera3D = _cam_orbit.get_child(0) as Camera3D
	var center_world := _axis_root.global_transform * _axis_centers[index]
	var n := cam.global_transform.basis.z.normalized()
	_drag_plane = Plane(n, n.dot(center_world))
	_drag_start_local = _ray_plane_point(screen_pos, _drag_plane)
	_drag_start_center = _axis_centers[index]
	_drag_start_scale = _axis_scales[index]
	_orbit_state.dragging = false


func _apply_axis_drag(screen_pos: Vector2) -> void:
	if _drag_axis < 0:
		return
	var p_world := _ray_plane_point(screen_pos, _drag_plane)
	if p_world == Vector3.INF:
		return
	var p_local := _axis_root.global_transform.affine_inverse() * p_world
	var axis := _axis_dirs[_drag_axis].normalized()
	if _drag_endpoint < 0:
		_axis_centers[_drag_axis] = _drag_start_center + (p_local - _drag_start_local)
	else:
		var base_half := ROD_BASE * 0.5 * _drag_start_scale
		var anchor := _drag_start_center - axis * base_half if _drag_endpoint == 0 else _drag_start_center + axis * base_half
		var signed := (p_local - anchor).dot(axis) if _drag_endpoint == 0 else (anchor - p_local).dot(axis)
		var half_len := clampf(signed, ROD_BASE * 0.10, ROD_BASE * 2.0)
		_axis_scales[_drag_axis] = clampf(half_len * 2.0 / ROD_BASE, 0.2, 4.0)
	_refresh_axis_visual()
	_refresh_hud()


func _end_axis_drag() -> void:
	_drag_axis = -1
	_drag_endpoint = -1
	_set_axis_highlight(_hover_axis)


func _axis_endpoint_world(index: int, sign: int) -> Vector3:
	var a := _axis_dirs[index].normalized()
	var half := ROD_BASE * 0.5 * _axis_scales[index]
	return _axis_root.global_transform * (_axis_centers[index] + a * half * float(sign))


func _ray_plane_point(screen_pos: Vector2, plane: Plane) -> Vector3:
	var cam: Camera3D = _cam_orbit.get_child(0) as Camera3D
	var origin := cam.project_ray_origin(screen_pos)
	var direction := cam.project_ray_normal(screen_pos)
	var den := plane.normal.dot(direction)
	if absf(den) < 0.00001:
		return Vector3.INF
	var t := (plane.d - plane.normal.dot(origin)) / den
	return origin + direction * t


func _distance_to_segment_2d(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var den := ab.length_squared()
	if den < 0.0001:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / den, 0.0, 1.0)
	return p.distance_to(a + ab * t)


## ★★★ 35 轮核心：**把标定结果真的改写进游戏规则表源码**
##     `res://scripts/data/eve_ship_yaw.gd` 的 `const SHIP_AXES` 里那一行。
##
## 为什么必须这么做（34 轮的血的教训）：
##   旧版只往 `user://bow_calib/fixed.json` 写便签 —— 那是**工具自己的备忘录**，
##   游戏**根本不读它**。用户点回上一艘看到的还是旧值，
##   因为 `SHIP_AXES` 是硬编码常量，一直没被动过。
##   ⇒ 「打了勾」≠「写进游戏规则」。必须直接改源码那一行。
##
## 实现：逐行扫描源码，命中 `&"<sid>":` 开头的行 ⇒ 只替换该行。
##   · 保留行尾注释里**不属于**本工具的部分（原注释全部丢弃，改为标定来源标记）
##   · 行首缩进（Tab）原样保留
##   · **写回后立刻重新读文件、grep 那一行、断言值一致**（读回校验，同 `_save_calibration`）
##   · 改完自动 `--import` 由外部命令负责（本工具内只改文件 + 提示）
##
## 返回：`{"ok": bool, "msg": String, "line": int, "old": String}`
func _write_ship_axes_source(sid: String, bow_str: String, up_str: String) -> Dictionary:
	var src_path := ProjectSettings.globalize_path("res://scripts/data/eve_ship_yaw.gd")
	if not FileAccess.file_exists(src_path):
		return {"ok": false, "msg": "找不到 %s" % src_path, "line": -1, "old": ""}
	var fa := FileAccess.open(src_path, FileAccess.READ)
	if fa == null:
		return {"ok": false, "msg": "无法读取 %s" % src_path, "line": -1, "old": ""}
	var text := fa.get_as_text()
	fa.close()
	var lines := text.split("\n")
	# 定位 `const SHIP_AXES` 块，避免误改 `AXIS_REMAP` / `AXIS_DEG` 等同样含 `&"id":` 的表
	var block_start := -1
	for i in lines.size():
		if lines[i].strip_edges().begins_with("const SHIP_AXES"):
			block_start = i
			break
	if block_start < 0:
		return {"ok": false, "msg": "源码里找不到 const SHIP_AXES", "line": -1, "old": ""}
	# 块结束 = 第一个顶格（无 Tab）且以 `}` 开头的行
	var block_end := lines.size()
	for i in range(block_start + 1, lines.size()):
		if lines[i].begins_with("}"):
			block_end = i
			break
	var key := "&\"%s\":" % sid
	var hit := -1
	for i in range(block_start + 1, block_end):
		if lines[i].strip_edges().begins_with(key):
			hit = i
			break
	if hit < 0:
		# 表里没这艘船 ⇒ 追加到块尾（保持 Tab 缩进 + 对齐）
		#
		# ⚠️⚠️ **行尾逗号是必须的**（38 轮修）：本文件是 GDScript **字典字面量**，
		#   多行字典里每一条**必须以逗号结尾**（末条可省，但中间条省了就语法错）。
		#   35/37 轮的写入代码**漏了逗号** ⇒ 只要该船后面还有其他条目，
		#   整个 `SHIP_AXES` 字典立刻报
		#   `Parse Error: Expected closing "}" after dictionary elements`
		#   ⇒ 游戏和工具**双双起不来**（38 轮实测：kestrel 那行被写成
		#   `&"kestrel": "bow:+Y up:-Z"  # …` 无逗号，工具窗口直接白屏 + 报错刷屏）。
		#   ⇒ 统一口径：**一律带逗号**（末条多一个逗号在 GDScript 里完全合法）。
		var indent := "\t"
		var new_line := "%s%s %s,  # 35 轮：工具标定写入" % [indent, key, _quote_spec(bow_str, up_str)]
		lines.insert(block_end, new_line)
		hit = block_end
	else:
		# 只替换该行：保留原缩进
		var ln: String = lines[hit]
		var ind_len := 0
		while ind_len < ln.length() and (ln[ind_len] == "\t" or ln[ind_len] == " "):
			ind_len += 1
		var indent2 := ln.substr(0, ind_len)
		# ⚠️ 同上：**行尾必须带逗号**，否则会把字典写坏（38 轮踩到）
		lines[hit] = "%s%s %s,  # 35 轮：工具标定写入（原注释已弃）" % [indent2, key, _quote_spec(bow_str, up_str)]
	var old_line := ""
	if hit < lines.size():
		old_line = lines[hit]
	var out := "\n".join(lines)
	var fw := FileAccess.open(src_path, FileAccess.WRITE)
	if fw == null:
		return {"ok": false, "msg": "无法写入 %s（只读？）" % src_path, "line": hit + 1, "old": old_line}
	fw.store_string(out)
	fw.close()
	# ★ 读回校验：重新打开文件，grep 那一行，断言值确实是我们写的
	var vr := FileAccess.open(src_path, FileAccess.READ)
	if vr == null:
		return {"ok": false, "msg": "写回后读不回来", "line": hit + 1, "old": old_line}
	var back_text := vr.get_as_text()
	vr.close()
	var vlines := back_text.split("\n")
	if hit >= vlines.size() or not vlines[hit].contains("bow:%s up:%s" % [bow_str, up_str]):
		return {"ok": false, "msg": "读回校验失败：%s" % src_path, "line": hit + 1, "old": old_line}
	# ★★ 38 轮：**结构校验** —— 光校验"那一行写对了"是不够的！
	#
	#   38 轮实测：漏一个行尾逗号，那一行的值**完全正确**（读回校验过），
	#   但整个 `SHIP_AXES` 字典从此语法错 ⇒ 游戏和工具**双双起不来**。
	#   ⇒ 写回后必须再验一次**文件整体结构**：花括号/方括号/圆括号必须配平。
	#     不配平 ⇒ **立刻把文件还原成写入前的原文**（`text`），并返回失败。
	#   ⚠️ 这是"宁可标定失败，也不许把游戏源码写坏"的兜底。
	var bal := _check_bracket_balance(back_text)
	if not bool(bal["ok"]):
		var rw := FileAccess.open(src_path, FileAccess.WRITE)
		if rw != null:
			rw.store_string(text)   # 还原成写入前原文
			rw.close()
		return {"ok": false,
			"msg": "写回后结构校验失败（%s），已自动还原源码：%s" % [String(bal["msg"]), src_path],
			"line": hit + 1, "old": old_line}
	# ★ 源码变了 ⇒ 列表 ✔ 的缓存必须失效，否则 UI 不更新（34 轮同类 bug 的翻版）
	_invalidate_source_table_cache()
	return {"ok": true, "msg": "已改写 %s:%d" % [src_path, hit + 1], "line": hit + 1, "old": old_line}


## 括号配平检查（只给 `_write_ship_axes_source` 的写回兜底用）。
##
## ⚠️ **纯括号配平抓不住"漏逗号"**（38 轮实测）：`{ &"a": "x" &"b": "y", }`
##   的花括号仍然配平，只是**语义非法** —— GDScript 会报
##   `Expected closing "}" after dictionary elements`。
##   ⇒ 所以这个函数必须**两条腿**：
##     ① 括号配平（`{} [] ()`，跳过字符串与注释）
##     ② **`SHIP_AXES` 块内逐条检查行尾逗号**：
##        块内每个以 `&"…":` 开头的条目行，若它**后面还有**另一个条目行，
##        则本行必须以 `,` 结尾（末条可省，但多一个也合法）。
## 宁可粗也不能漏 —— 它拦的是"整个文件被写坏"这种致命后果。
func _check_bracket_balance(src: String) -> Dictionary:
	var cb := 0   # {}
	var sb := 0   # []
	var pb := 0   # ()
	var i := 0
	var n := src.length()
	var in_str := false
	var quote := ""
	var in_comment := false
	while i < n:
		var ch := src[i]
		if in_comment:
			if ch == "\n":
				in_comment = false
			i += 1
			continue
		if in_str:
			# 字符串里处理转义与结束引号
			if ch == "\\":
				i += 2
				continue
			if ch == quote:
				in_str = false
			i += 1
			continue
		match ch:
			"#":
				in_comment = true
			"\"", "'":
				in_str = true
				quote = ch
			"{":
				cb += 1
			"}":
				cb -= 1
			"[":
				sb += 1
			"]":
				sb -= 1
			"(":
				pb += 1
			")":
				pb -= 1
		if cb < 0 or sb < 0 or pb < 0:
			return {"ok": false, "msg": "第 %d 字符处括号提前闭合" % i}
		i += 1
	if cb != 0 or sb != 0 or pb != 0:
		return {"ok": false, "msg": "括号不配平（{}:%d []:%d ():%d）" % [cb, sb, pb]}
	# ② SHIP_AXES 块内逐条检查"非末条必须带逗号"
	var d := _check_ship_axes_commas(src)
	if not bool(d["ok"]):
		return d
	return {"ok": true, "msg": "OK"}


## `SHIP_AXES` 块内逐条检查"条目行尾逗号"。
## 返回 `{"ok": bool, "msg": String}`。
func _check_ship_axes_commas(src: String) -> Dictionary:
	var lines := src.split("\n")
	var start := -1
	for i in lines.size():
		if lines[i].strip_edges().begins_with("const SHIP_AXES"):
			start = i
			break
	if start < 0:
		return {"ok": true, "msg": "OK（无 SHIP_AXES 块，跳过）"}
	var end := lines.size()
	for i in range(start + 1, lines.size()):
		if lines[i].begins_with("}"):
			end = i
			break
	# 收集所有条目行的行号（`&"id":` 开头）
	var entry_rows: Array[int] = []
	for i in range(start + 1, end):
		if lines[i].strip_edges().begins_with("&\""):
			entry_rows.append(i)
	for k in entry_rows.size():
		# 末条允许省略逗号 ⇒ 不检查
		if k == entry_rows.size() - 1:
			continue
		var ln: String = lines[entry_rows[k]]
		if not _line_has_trailing_comma(ln):
			return {"ok": false,
				"msg": "SHIP_AXES 第 %d 行缺行尾逗号（非末条必须带逗号，否则字典语法错）" % (entry_rows[k] + 1)}
	return {"ok": true, "msg": "OK"}


## 判断一行 GDScript 条目是否以逗号结尾（**跳过行尾注释**）。
## 例：`&"a": "bow:+X up:+Y",   # 注释` ⇒ true；
##     `&"a": "bow:+X up:+Y"    # 注释` ⇒ false。
func _line_has_trailing_comma(ln: String) -> bool:
	if ln.contains(","):
		return true
	# 没有逗号：可能被注释吃掉了？—— 逐字符找注释起点，取其前的代码部分
	var in_str := false
	var i := 0
	while i < ln.length():
		var ch := ln[i]
		if in_str:
			if ch == "\\":
				i += 2
				continue
			if ch == "\"":
				in_str = false
			i += 1
			continue
		if ch == "\"":
			in_str = true
		elif ch == "#":
			break   # 到注释了，后面全是注释
		i += 1
	# 代码部分（含逗号）截到 i
	var code := ln.substr(0, i)
	return code.contains(",")


## 生成 `"bow:+X up:+Y"` 形式（含引号）
func _quote_spec(bow_str: String, up_str: String) -> String:
	return "\"bow:%s up:%s\"" % [bow_str, up_str]


## 从游戏规则表源码里**读回**某船当前登记的语义轴。
## 用途：① 切船时把轴体摆到"表里真值"的位置（不再粗暴回默认）；
##      ② HUD 显示"表内现值"与"当前工具值"是否一致，一眼看出改了没生效。
## 返回：`{"bow": Vector3, "up": Vector3, "raw": String, "found": bool}`
func _read_ship_axes_source(sid: String) -> Dictionary:
	var src_path := ProjectSettings.globalize_path("res://scripts/data/eve_ship_yaw.gd")
	var out := {"bow": Vector3(1, 0, 0), "up": Vector3(0, 1, 0), "raw": "", "found": false}
	if not FileAccess.file_exists(src_path):
		return out
	var fa := FileAccess.open(src_path, FileAccess.READ)
	if fa == null:
		return out
	var lines := fa.get_as_text().split("\n")
	fa.close()
	var in_block := false
	var key := "&\"%s\":" % sid
	for i in lines.size():
		var ln: String = lines[i]
		if ln.strip_edges().begins_with("const SHIP_AXES"):
			in_block = true
			continue
		if in_block and ln.begins_with("}"):
			break
		if in_block and ln.strip_edges().begins_with(key):
			var rest := ln.strip_edges().substr(key.length()).strip_edges()
			var q0 := rest.find("\"")
			var q1 := rest.find("\"", q0 + 1)
			if q0 >= 0 and q1 > q0:
				var spec := rest.substr(q0 + 1, q1 - q0 - 1)
				out["raw"] = spec
				out["found"] = true
				for part in spec.split(" ", false):
					var kv: PackedStringArray = part.split(":", false, 1)
					if kv.size() != 2:
						continue
					match kv[0]:
						"bow": out["bow"] = _parse_axis_token(kv[1])
						"up": out["up"] = _parse_axis_token(kv[1])
			break
	return out


## ★ 35 轮：判断某船是否**已经登记在游戏规则表源码**里。
## 每帧为 52 行各调一次 —— 52 次文件读取会拖慢列表刷新，
## 所以这里用一次性缓存（_source_table_cache），并在 `_write_ship_axes_source` 后清空。
func _ship_in_source_table(sid: String) -> bool:
	_ensure_source_table_cache()
	return _source_table_cache.has(sid)


func _ensure_source_table_cache() -> void:
	if not _source_table_cache.is_empty():
		return
	var src_path := ProjectSettings.globalize_path("res://scripts/data/eve_ship_yaw.gd")
	if not FileAccess.file_exists(src_path):
		return
	var fa := FileAccess.open(src_path, FileAccess.READ)
	if fa == null:
		return
	var lines := fa.get_as_text().split("\n")
	fa.close()
	var in_block := false
	for ln in lines:
		if ln.strip_edges().begins_with("const SHIP_AXES"):
			in_block = true
			continue
		if in_block and ln.begins_with("}"):
			break
		if not in_block:
			continue
		var st: String = ln.strip_edges()
		if not st.begins_with("&\""):
			continue
		var q1 := st.find("\"", 2)
		if q1 > 2:
			_source_table_cache[st.substr(2, q1 - 2)] = true


## 写源码后必须清缓存，否则列表的 ✔ 不更新（34 轮同类 bug 的翻版）
func _invalidate_source_table_cache() -> void:
	_source_table_cache.clear()


func _parse_axis_token(tok: String) -> Vector3:
	var s := tok.strip_edges()
	if s.length() != 2:
		return Vector3(1, 0, 0)
	var sign := 1.0 if s[0] == "+" else -1.0
	match s[1].to_upper():
		"X": return Vector3(sign, 0, 0)
		"Y": return Vector3(0, sign, 0)
		"Z": return Vector3(0, 0, sign)
	return Vector3(1, 0, 0)


func _on_confirm_pressed() -> void:
	# 主视图红球代表舰艏，俯视图红球代表船背。
	# ⚠️ 33 轮起每根轴各自有方向 `_axis_dirs[i]`，所以直接取该根的方向、
	#    乘船姿反解即可：舰艏模型轴 = R_ship⁻¹ · _axis_dirs[0]
	#    （旧式 `R_ship⁻¹ · R_axis · VIEW_AXES[0]` 里的 `R_axis · VIEW_AXES[0]`
	#      恰好就是"第 0 根的当前方向"，两式等价。）
	var bow: Vector3 = _project_to_axis(_axis_dir_in_model(0))
	var up: Vector3 = _project_to_axis(_axis_dir_in_model(4))
	if absf(bow.dot(up)) > 0.99:
		_hud.text += "\n  ⚠ bow 与 up 平行（请把主视图与俯视图转成不同方向）"
		return
	if _idx < 0 or _idx >= _ids.size():
		return
	var sid := StringName(_ids[_idx])
	# ★★★ 39 轮：**必须把世界方向反解回模型轴**（见 `_axis_dir_to_world` 的长注释）。
	#
	#   39 轮改动的因果链：
	#     ① 轴体现在画的是**世界方向**（`_apply_axis_dirs_from_table` 里乘了 `R_y·M`）
	#     ② 但 `SHIP_AXES` 存的是**模型空间语义轴**（`bow:+X` 说的是"模型哪根轴"）
	#     ③ 所以这里**不能再直接 `_project_to_axis(_axis_dir_in_model(0))`** ——
	#        那样存进去的是"世界哪根轴"，落盘后游戏再乘一次 `R_y·M` ⇒ **翻倍**，
	#        症状 = 你把红球摆到"看着朝敌"的位置，游戏里舰艏却背敌。
	#     ⇒ 拆法与 `_axis_dir_to_world` 严格互为逆：`_axis_dir_in_model` 先去掉船姿，
	#       `_axis_dir_to_model` 再去掉 `R_y·M`。
	#   ⚠️ 这一步是 39 轮修复的**必备另一半** —— 只改显示不改落表 =
	#      把 bug 从左挪到右（红线 40 同类陷阱：取证与实现必须同源，不许各算各的）。
	var bw_raw: Vector3 = _axis_dir_to_model(_axis_dir_in_model(0), String(sid))
	var up_raw: Vector3 = _axis_dir_to_model(_axis_dir_in_model(4), String(sid))
	var bw_ax := _project_to_axis(bw_raw)
	var up_ax := _project_to_axis(up_raw)
	if absf(bw_ax.dot(up_ax)) > 0.99:
		_hud.text += "\n  ⚠ 反解后 bow 与 up 共线（这艘船的 AXIS_REMAP 可能有问题，请查 validate）"
		return
	var bow_str: String = _format_axis(bw_ax)
	var up_str: String = _format_axis(up_ax)
	# 六视图留档同样按**模型空间**存（与 `bow/up` 口径一致，别一半世界一半模型）
	var view_axes: Dictionary = {}
	for i in VIEW_AXES.size():
		var view_axis: Vector3 = _project_to_axis(
			_axis_dir_to_model(_axis_dir_in_model(i), String(sid)))
		view_axes[VIEW_NAMES[i]] = _format_axis(view_axis)
	# ───────────────────────────────────────────────────────────────────
	# ★★★ 36 轮：**按回车 = 写进「姿势表」**（`pose_table.json`），**不动游戏源码**。
	#
	#   用户原话：「做一个新表专门储存当前舰船姿势，然后等下次重启的时候再写进游戏，
	#             不然现在相当奇怪，我到底改没改成功都不知道」。
	#   ⇒ 好处：① 这张表是**短表**，打开就知道自己存了哪些船、值是多少；
	#           ② 反复改同一艘船只覆盖一行，不会把游戏源码改成一团；
	#           ③ 游戏源码只在**下次启动工具时**统一落盘，时机可控、可预期。
	#   ⚠️ 写表失败会静默（`store_string` 无错误码）⇒ `_save_pose_table` 内做**读回校验**，
	#     失败就**不前进、不打勾**，停在当前船。
	# ───────────────────────────────────────────────────────────────────
	var ok_pose := _record_pose(String(sid), bow_str, up_str)
	if not ok_pose:
		_hud.text += "\n  ❌ 写入姿势表失败（读回校验不通过）——停在当前舰船，未改任何东西"
		_refresh_hud()
		return
	# 附带：六视图留档（失败不影响主流程，只是少了 views 明细）
	var ok_json := _save_calibration(String(sid), bow_str, up_str, view_axes)
	# ★ 36 轮：**只有走到这里（姿势表写成功）才打 √** —— 用户要求的唯一打勾时机
	_fixed_ships[String(sid)] = {"bow": bow_str, "up": up_str}
	_hud.text += "\n  ✅ 已存入姿势表：%s = \"bow:%s up:%s\"" % [String(sid), bow_str, up_str]
	_hud.text += "\n     表文件：%s   本次已存 %d 艘" % [
		ProjectSettings.globalize_path(POSE_TABLE_PATH), _pose_table.size()]
	if not ok_json:
		_hud.text += "\n     ⚠ 六视图明细写失败（不影响姿势表）"
	_hud.text += "\n     ⚠ 尚未进游戏！**下次启动本工具**时才会把姿势表写进游戏规则表"
	# ★ 35 轮：切下一艘时，把轴体摆到**下一艘在规则表里的真值**位置（不是粗暴回默认）。
	#   用户点回上一艘看到的就是刚写进去的值 —— "改了就是改了，不会回到默认"。
	var next_idx := (_idx + 1) % _ids.size()
	var next_sid := String(_ids[next_idx])
	_idx = next_idx
	_load_current()
	_apply_axis_dirs_from_table(next_sid)
	_refresh_axis_visual()
	_refresh_ship_list()
	_refresh_hud()
	_hud.text += "\n  ➡ 已切到下一艘：%s（轴体已按其规则表登记值摆好）" % next_sid


## ═══ 40 轮：**锚点自检** —— 拿「你已经确认过的船」反证工具的映射链 ═══════
##
## ── 为什么要有这个 ─────────────────────────────────────────────
## 用户原话：「**我不信你的判断**好吧，这么多轮了，没修改好，我怎么信你」。
## 这句话是对的 —— 前面 39 轮我反复"自己验自己 PASS"，结果参照系还是错的。
## 所以这里不再让工具宣称"我算对了"，而是**把你的历史裁决当标尺**：
##
##   锚点 = `catalyst`（促进级）。
##   它的 `AXIS_REMAP = "-X,+Y,-Z"`、`FLIP = false` 是 **2026-09-26 你亲自确认过的**
##   （源码注释原话：「按用户落盘」+ 你实机看过 `_ball_top.png` 判「促进级是错的」
##     ⇒ 反过来说"不翻"是对的那一版）。
##
##   于是**必然**有：`R_y(−90°+θ)·M·(−X)` 必须落在 **−Z**（朝敌）。
##   若本工具显示成 +Z ⇒ 说明工具与游戏的映射链**又漂了** ⇒ 工具当场告诉你"别信我"。
##
## ⚠️ 红线 40：期望值（−Z）来自"用户历史裁决 + 手算"，**不是**从被测变量反推。
##
## ★★ 43 轮重写：**从"3 艘抽样"扩到"全库 52 艘"**，并且**换掉算式** ──
##   43 轮我（AI）拿旧算式在游戏源码外手算，得出"5 艘背敌"的**假阳性**，
##   还据此两次改了游戏源码 —— 两次都错。真因是 **`Basis` 的行列语义**：
##       `axis_remap()` 的 spec token i **是 Basis 的第 i 行**（源码注释原文），
##       但 `Basis * v` 在数学上等价于**列组合** `Σ v[j]·col[j]`，
##       而 `rows[j] == col[j]`（源码就是这么转置构造的）
##       ⇒ **spec 里"第 i 行"这个说法与"第 i 列"数值上恰好相等**，两者不冲突；
##         错的是我把 `M·v` 写成"行点乘"（`Σ M[i][j]v[j]` 用 M=rows 直接点）
##         ⇒ 非对角 spec 必然算反（对角型行=列相等 ⇒ 不暴露，这就是潜伏原因）。
##   ⇒ 本函数改为**直接调游戏侧真代码** `EveShipYawTable`（红线 40：不许自己复刻算式），
##     工具侧只负责"把 bow_axis 喂进去、读世界方向、与 −Z 比"。
##
##   期望值（−Z）依据 = **工程事实**：`deploy_enemy_z = −45`，敌人恒在世界 −Z（红线 42）。
##   ⇒ 逐艘列出，**任何一艘不朝敌就当场点名**（不再抽样）。
func _run_anchor_check() -> void:
	var ids: Array = INDEX.all()
	var lines: PackedStringArray = PackedStringArray()
	var bad: PackedStringArray = PackedStringArray()
	for sa in ids:
		var sid := String(sa.id)
		var bow_model: Vector3 = YAW.bow_axis(StringName(sid))
		if bow_model.length_squared() < 0.5:
			bad.append(sid)
			lines.append("  ❌ %s：SHIP_AXES 里查无此船（或语义轴非法）" % sid)
			continue
		var got: Vector3 = _axis_dir_to_world(bow_model, sid)
		# 朝敌 = 世界 −Z。门限 0.99 ⇒ 允许 PCA 残差 θ 带来的 ~8° 抖动。
		if got.z > -0.99 or absf(got.y) > 0.15:
			bad.append(sid)
			lines.append("  ❌ %s：舰艏世界方向 = (%.3f, %.3f, %.3f)，**不朝敌**（应 ≈ (0,0,−1)）"
				% [sid, got.x, got.y, got.z])
	if bad.size() == 0:
		_anchor_report = "全库朝敌对账 %d/%d 通过 —— 每艘舰艏世界方向 ≈ (0,0,−1)（敌人方向）" % [ids.size(), ids.size()]
	else:
		_anchor_report = "⛔ 全库朝敌对账 %d/%d 失败 —— 以下船舰艏**不朝敌**，先修表再标定" % [ids.size() - bad.size(), ids.size()]
	for ln in lines:
		_anchor_report += "\n" + ln


## ★ 37 轮：把轴体姿势**还原成该船存在姿势表里的值**。
##
## ── 用户报的 bug（37 轮原话）────────────────────────────────────
## 「我在矮脚鸡级修改了朝向，按回车键，屏幕上弹出小鹰级，矮脚鸡级在右侧列表上
##   打上了√，但我再次点击矮脚鸡的时候，矮脚鸡的姿势又回到了默认姿势，
##   那这样我怎么判断矮脚鸡级有没有修正好姿势？我让你做个单独的姿势保存表
##   就是干这事儿的，让我修改好矮脚鸡之后，再次点击的时候，是我修改好的姿势」
##
## ── 根因：**写表了、读表了、但没人把表里的姿势搬回轴体** ──────────
## 35/36 轮本函数的实现只有两行：`_reset_axis_pose()` + 读一段字符串给 HUD 看，
## 轴体六根**一律复位到 `VIEW_AXES`**（= 默认姿势）。
## ⇒ 切回刚存过的船，看到的水远是默认姿势，"存在表里的值"从头到尾没被用过
##   —— 表成了摆设，这正是用户骂的"那这样我怎么判断有没有修正"。
##
## ── 本函数现在的三条职责 ────────────────────────────────────
##   ① 取该船**最终生效**的 `bow:.. up:..`（姿势优先，其次源码现值）
##   ② 把它**摆回轴体**：第 0 根（主视图）指向 bow，第 4 根（俯视图）指向 up，
##      并把船姿 `R_ship` 复位 —— 因为落表公式是 `bow_model = R_ship⁻¹ · _axis_dirs[0]`，
##      `R_ship = I` 时 `_axis_dirs[0] = bow_model`，**一一对应、可逆**。
##   ③ 剩下的 4 根按「直角右手系」补齐（bow→主视图、up→俯视图，
##      侧向轴 `bow × up` 给左/右视图，其余取反向）—— 只为了让六轴视觉上
##      成一个正交框；**它们不参与落表**（落表只读第 0/4 根）。
##
## ⚠️ 第 ② 条**不违反红线 40**：这里不需要复刻 `AXIS_REMAP` 那条"模型→世界"
##   的映射链，因为落表存的就是**模型空间**的语义轴，而轴体是**世界系**方向、
##   船姿为单位阵 ⇒ 两者同系，直接赋值就是恒等还原。
func _apply_axis_dirs_from_table(sid: String) -> void:
	_reset_axis_pose()
	_table_bow_raw = String(_read_ship_axes_source(sid)["raw"])
	# ★ 37 轮：**姿势表优先于源码**（表里 = 用户本次刚按回车存的，更新）
	var bow_s := ""
	var up_s := ""
	var src := "源码"
	if _pose_table.has(sid):
		var rec: Variant = _pose_table[sid]
		if rec is Dictionary:
			bow_s = String(rec.get("bow", ""))
			up_s = String(rec.get("up", ""))
			src = "姿势表"
	if bow_s == "" or up_s == "":
		var cur := _read_ship_axes_source(sid)
		if bool(cur["found"]):
			bow_s = _format_axis(cur["bow"])
			up_s = _format_axis(cur["up"])
	if bow_s == "" or up_s == "":
		return
	var bow := _parse_axis_token(bow_s)
	var up := _parse_axis_token(up_s)
	if bow.length_squared() < 0.5 or up.length_squared() < 0.5:
		return
	# 语义轴必须正交（红线 46 / validate ⑤）；不正交就退回默认，别摆出畸形框
	if absf(bow.dot(up)) > 0.01:
		return
	# 主/俯视图的方向 = **该船在世界里真实的方向**（见下方 39 轮长注释）
	_axis_dirs[0] = _axis_dir_to_world(bow, sid)
	_axis_dirs[4] = _axis_dir_to_world(up, sid)
	# ── 其余四根按右手系补齐（仅视觉，不参与落表）──
	var side := _axis_dirs[0].cross(_axis_dirs[4]).normalized()
	_axis_dirs[1] = -_axis_dirs[0]      # 后视图 = 船尾端
	_axis_dirs[2] = -side               # 左视图
	_axis_dirs[3] = side                # 右视图
	_axis_dirs[5] = -_axis_dirs[4]      # 底视图 = 船腹端
	_axis_restore_note = "轴体已按【%s】还原：bow:%s up:%s  →  世界 bow=%s up=%s" % [
		src, bow_s, up_s, _format_axis(_axis_dirs[0]), _format_axis(_axis_dirs[4])]
	_refresh_axis_visual()


## ★★★ 39 轮核心修复：**模型空间语义轴 → 世界方向**。
##
## ── 用户报的 bug（38 轮末原话）────────────────────────────────
## 「我关闭姿势调整窗口后，怎么又回到默认状态了，那我修改不是白修改了吗」
##
## ── 真根因：**工具画的轴方向 ≠ 游戏里的舰艏方向**（差一整层 `AXIS_REMAP`）──
##   游戏侧（`eve_ship_visual._build_hull_model`）的真实算式是：
##       `model.basis = R_y(−90° + θ) · M`，  `M = AXIS_REMAP[sid]`
##       ⇒ 舰艏世界方向 = `R_y(−90°+θ) · M · bow_model`
##   而工具侧 37 轮把它写成了：
##       `_axis_dirs[0] = bow_model`        ← **M 这一层整个丢了**
##   后果：本库 **47 艘**的 `AXIS_REMAP` **恰好等于 `−X,+Y,−Z` 这个含 180° 的矩阵**
##   （`−X` 那一行就是那个 180°）。于是：
##       · 游戏里 `M·(+X) = −X` ⇒ 再 `R_y(−90°)` ⇒ **−Z = 朝敌** ✅
##       · 工具里红球却画在 **+X** ⇒ 用户看到"舰艏在 +X"就把它改成 `−X`
##       · 改完 `M·(−X) = +X` ⇒ `R_y(−90°)` ⇒ **+Z = 背对敌人** ❌
##   ⇒ 用户是在**反的参照系**下标定的 —— 21 艘"被改反"全由此而来，
##     而 `validate()` 与 `probe_bow_align` 都**测不出**（它们只查阈值/运行时 quaternion，
##     不查"工具画面里的方向 vs 游戏里的方向"这一层）。
##
## ── 本函数为什么这么摆（与落表公式**必须互为逆**）──────────────
##   落表（`_on_confirm_pressed`）：`bow_model = R_ship⁻¹ · _axis_dirs[0]`，`R_ship = I`
##     ⇒ `_axis_dirs[0] = bow_model`（**模型空间**）
##   游戏：`world = R_y(−90°+θ)·M·bow_model`
##   ⇒ 要让「画的就是游戏里的」，轴体必须摆成：
##       `_axis_dirs[0] = R_y(−90°+θ) · M · bow_model`
##   ⚠️ 红色警告：**这两个约定互相冲突** ——
##     落表把 `_axis_dirs[0]` 当**模型轴**读，游戏把它当**世界轴**用。
##     所以本修复**不能只改显示**，必须让 `_on_confirm_pressed` 反向拆掉这一层。
##     否则"看着对"⇒"存进去是反的"，等于把 bug 挪了个位置（红线 40 同类陷阱）。
##   ⇒ 39 轮同时改了 `_on_confirm_pressed`（加 `_axis_dir_to_model` 反解）。
##
## ⚠️⚠️ **49 轮：改回「全链」`zero_pose_basis()` —— 与工具里船身的姿态**同源**。**
##
##  ── 48 轮曾经改成静态链，49 轮推翻了（原因是那次只改了轴杆、没改船身）──
##  48 轮的理由是「工具标的是模型固有语义轴，滚转是下游修正，不该进工具」——
##  这个理由**只在"工具里的船是原始姿态"时成立**。
##  但 49 轮 `probe_diag49` 实测发现：**工具里的船本来就是原始姿态**（单位阵），
##  而实机是 `zero_pose_basis` ⇒ **两个参照系从来就不是一个**
##  （52/52 艘都对不上）⇒ 用户在工具里"以眼为准"定的方向到实机必然不对。
##
##  ── 49 轮的修法：**把船身也改成 `zero_pose_basis`**（见 `_load_current`），
##    轴杆随之走**同一条链** ⇒ 工具里"看到的船 + 看到的轴"与实机**逐项同一**。
##  ⇒ 用户在工具里看到什么，实机就是什么。**一处定、全局用。**
##
##  ⚠️ 这条链与 `_load_current` 里 `_zero_pose_of()` 用的是**同一个生产函数**
##     （红线 40：不许两份实现），所以两者永远不会漂移。
func _static_basis(sid: StringName) -> Basis:
	# ⚠️ 53 轮：`--raw` 时必须与 `_zero_pose_of()` **同步**改用 `mesh_rot`。
	#   否则会出现"船按原始姿态显示、轴杆却按含 M 的姿态反解"⇒ 红球明明压在
	#    船头上，反推出的却是另一根轴 ⇒ 标定照样错（红线：同一参照系只许一处）。
	if RAW_POSE:
		var mr: Variant = EVE_VISUAL.call("mesh_rot_of", sid)
		if mr is Basis:
			return (mr as Basis).orthonormalized()
		return Basis.IDENTITY
	var b: Variant = EVE_VISUAL.call("zero_pose_basis", sid)
	if b is Basis:
		return (b as Basis).orthonormalized()
	return Basis.IDENTITY


func _axis_dir_to_world(model_vec: Vector3, sid: String) -> Vector3:
	# ★ 47 轮：**直接调生产代码的算式**，不再自己复刻（红线 40）。
	#
	# 为什么必须同源（39 轮 + 47 轮各栽一次）：
	#   39 轮工具漏了 `AXIS_REMAP` 的 M ⇒ 47 艘在**反的参照系**里被标定；
	#   47 轮发现游戏侧自己还漏了 glb **内层网格旋转** ⇒ 工具若继续自己写一份，
	#   就会和游戏**再次错开**，用户还是"改完依然乱"。
	#   现在唯一定义在 `EveShipVisual.zero_pose_basis()`，两边共用。
	#
	# 算式：`R_z(roll) · R_y(extra_yaw) · M · mesh_rot`（与实机静止姿态**完全同一**）
	var out: Basis = _static_basis(StringName(sid))
	return (out * model_vec).normalized()


## `_axis_dir_to_world` 的**逆变换** —— 世界方向 → 模型空间语义轴。
## 落表前必须调它拆掉 `R_y·M·mesh_rot` 这一层，否则存进去的是世界轴当模型轴用。
## 判据：`_axis_dir_to_model(_axis_dir_to_world(v)) == v`（自检里有往返断言）。
func _axis_dir_to_model(world_vec: Vector3, sid: String) -> Vector3:
	var fwd: Basis = _static_basis(StringName(sid))
	return (fwd.inverse() * world_vec).normalized()


## ═══ 40 轮：姿势表**归档**（挪走，不删）═══════════════════════════════
## 用户裁决「全部作废、我重标」⇒ 旧表里 20 艘是反参照系下标的错值，必须让它失效。
## 但**绝不真删**：万一之后要对比"我当时到底改成了啥"，文件还在。
## 归档名带时间戳 ⇒ 反复作废也不会互相覆盖。
## 返回归档后的文件名（未归档时返回空串）。
func _archive_pose_table() -> String:
	if not FileAccess.file_exists(POSE_TABLE_PATH):
		return ""
	var src_abs := ProjectSettings.globalize_path(POSE_TABLE_PATH)
	var dir_abs := src_abs.get_base_dir()
	var stamp := Time.get_datetime_string_from_system(false, true).replace(":", "").replace("-", "").replace("T", "_")
	var dst_abs := dir_abs.path_join("pose_table.作废-%s.json" % stamp)
	var da := DirAccess.open(dir_abs)
	if da == null:
		return ""
	# 若同名已存在（同一秒内重复启动），加序号
	var n := 1
	while FileAccess.file_exists(dst_abs):
		dst_abs = dir_abs.path_join("pose_table.作废-%s_%d.json" % [stamp, n])
		n += 1
	var err := da.rename(src_abs.get_file(), dst_abs.get_file())
	if err != OK:
		push_warning("[probe_bow_box] 姿势表归档失败（err=%d）⇒ 保持原状，未清空" % err)
		return ""
	_archive_note = dst_abs.get_file()
	return _archive_note


## 40 轮：把"本进程内存里的姿势表"整体清空并落盘（用户按 `Ctrl+Delete` 或 `--flush` 前想重来时用）。
## 与 `_archive_pose_table` 的区别：本函数**当场生效**（不清磁盘上已有的历史归档）。
func _clear_pose_table_now() -> void:
	_fixed_ships = {}
	_pose_table = {}
	_save_pose_table()
	_archive_note = ""
	if _ship_list != null:
		_refresh_ship_list()
	_switch_to_ship(String(_ids[_idx]))
	_refresh_hud()


## ★ 34 轮：把当前船的**轴体姿势**复位（不清船、不清中心/缩放之外的镜头）。
## 与 `_reset_all()` 的区别：`_reset_all` 是"全部推倒重来"（含船姿、中心、缩放），
## 本函数只清**轴体方向**（这正是会跨船残留、造成"上一艘没固定"错觉的东西）。
func _reset_axis_pose() -> void:
	_ship_yaw = 0.0
	_ship_pitch = 0.0
	_ship_roll = 0.0
	_axis_restore_note = ""
	for i in _axis_dirs.size():
		if i < VIEW_AXES.size():
			_axis_dirs[i] = VIEW_AXES[i].normalized()
		# ★ 38 轮：轴体中心也归零 —— 六轴共原点；
		#   同时清掉上一艘手动平移的残留（否则切回来看到的是飘着的轴阵）。
		if i < _axis_centers.size():
			_axis_centers[i] = Vector3.ZERO
	_apply_ship_transform()
	_apply_axis_root_transform()
	_refresh_axis_visual()


## ★ 36 轮：**姿势表** —— 工具自己的收件箱，与游戏规则表**解耦**。
##
## 用户要求（36 轮原话）：「做个新表专门储存当前舰船姿势，然后等下次重启的时候
## 再写进游戏，不然现在相当奇怪，我到底改没改成功都不知道」。
##
## 设计：
##   · 文件 `user://bow_calib/pose_table.json`，内容 `{id: {"bow":"+X","up":"+Y","at":"时间戳"}}`
##   · **按回车 = 写进这张表**（当场可见、可反复覆盖、绝不动游戏源码）
##   · **下次启动工具时**，自动把表里所有条目**合并进游戏规则表源码** `eve_ship_yaw.gd`
##     （只改写值有变化的那几行；全部已一致则一字不动）
##   · 列表 `√` **只由这张表驱动** ⇒ "打了勾 = 我这次真的存进去了"，语义单一、无歧义
##
## 为什么这样比 35 轮好：35 轮"按回车立刻改源码"有两个尴尬：
##   ① 用户看不到"我改了哪些"，因为源码本来就是一大坨；
##   ② 源码被改但游戏没重启 ⇒ 工具里和实机里不一致，用户更糊涂。
##   现在改成"先在表里攒着、启动时统一落盘"，用户随时能打开 pose_table.json 对账。
const POSE_TABLE_PATH := "user://bow_calib/pose_table.json"


## 读姿势表（返回 `{id: {bow, up, at}}`）
func _load_pose_table() -> Dictionary:
	_pose_table = {}
	if not FileAccess.file_exists(POSE_TABLE_PATH):
		return _pose_table
	var fr := FileAccess.open(POSE_TABLE_PATH, FileAccess.READ)
	if fr == null:
		return _pose_table
	var parsed: Variant = JSON.parse_string(fr.get_as_text())
	if parsed is Dictionary:
		_pose_table = parsed
	return _pose_table


## 写姿势表（含**读回校验**）。返回是否成功。
func _save_pose_table() -> bool:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://bow_calib"))
	var fw := FileAccess.open(POSE_TABLE_PATH, FileAccess.WRITE)
	if fw == null:
		return false
	fw.store_string(JSON.stringify(_pose_table, "\t"))
	fw.close()
	# 读回校验：写完再读一次，确保内容一致（写盘失败会静默）
	var fr := FileAccess.open(POSE_TABLE_PATH, FileAccess.READ)
	if fr == null:
		return false
	var back: Variant = JSON.parse_string(fr.get_as_text())
	if not (back is Dictionary):
		return false
	for k in _pose_table.keys():
		if not back.has(k):
			return false
		var a: Variant = _pose_table[k]
		var b: Variant = back[k]
		if a is Dictionary and b is Dictionary:
			if String(a.get("bow", "")) != String(b.get("bow", "")):
				return false
			if String(a.get("up", "")) != String(b.get("up", "")):
				return false
	return true


## ★ 36 轮：把 bow/up 记进姿势表（只落这张表，**不碰游戏源码**）+ 读回校验。
func _record_pose(sid: String, bow_str: String, up_str: String) -> bool:
	_pose_table[sid] = {
		"bow": bow_str,
		"up": up_str,
		"at": Time.get_datetime_string_from_system(false, true),
	}
	return _save_pose_table()


## ★ 36 轮：**启动时把姿势表合并进游戏规则表源码**。
## 返回 `{"written": int, "skipped": int, "failed": Array}`
## 判据：逐条比对"源码现值"与"表里值"，只对**不同**的条目调 `_write_ship_axes_source`。
## 全部一致 ⇒ 一字不动（避免无意义重写文件、留下脏 diff）。
##
## ⚠️⚠️ **38 轮：本函数默认不再自动执行**（用户选择"先别落盘，我要逐个复核"）。
##   启用条件二选一：
##     · 命令行 `--flush`（显式要求落盘）
##     · 但**即使 `--flush`，也要先过 `_check_flip_conflicts()`**：
##       凡"在 FLIP 名单里 + 表里把 bow 翻成 −"的船一律**跳过**，
##       因为那是**双重 180°**（红线 27）⇒ 落盘会静默变成倒飞。
func _flush_pose_table_to_source() -> Dictionary:
	var written := 0
	var skipped := 0
	var failed: Array[String] = []
	var blocked: Array[String] = []
	_load_pose_table()
	# ★ 38 轮：先算 FLIP 冲突集（这些船**不许**自动落盘）
	var conflicts := _check_flip_conflicts()
	for k in _pose_table.keys():
		var sid := String(k)
		var rec: Variant = _pose_table[k]
		if not (rec is Dictionary):
			continue
		var bow_s := String(rec.get("bow", ""))
		var up_s := String(rec.get("up", ""))
		if bow_s == "" or up_s == "":
			continue
		# ★ 38 轮：FLIP 冲突船一律跳过（红线 27：bow 翻号与 FLIP 是同一 180°，
		#   只许一处。两处同时表达 ⇒ 抵消 ⇒ 倒飞，且不报错）
		if conflicts.has(sid):
			blocked.append(sid)
			continue
		var cur := _read_ship_axes_source(sid)
		var want := "bow:%s up:%s" % [bow_s, up_s]
		if bool(cur["found"]) and String(cur["raw"]) == want:
			skipped += 1
			continue
		var wr := _write_ship_axes_source(sid, bow_s, up_s)
		if bool(wr["ok"]):
			written += 1
		else:
			failed.append(sid)
	return {"written": written, "skipped": skipped, "failed": failed, "blocked": blocked}


## ★ 38 轮：**预演落盘**（只统计、**绝不写任何文件**）。
## 返回 `{"pending": int, "same": int, "conflicts": int, "conflict_ids": PackedStringArray}`
## 用途：HUD 告诉用户"如果落盘，会改哪几艘、哪几艘被 FLIP 冲突拦下"。
func _preview_flush() -> Dictionary:
	var pending := 0
	var same := 0
	var conflicts := _check_flip_conflicts()
	for k in _pose_table.keys():
		var sid := String(k)
		var rec: Variant = _pose_table[k]
		if not (rec is Dictionary):
			continue
		var bow_s := String(rec.get("bow", ""))
		var up_s := String(rec.get("up", ""))
		if bow_s == "" or up_s == "":
			continue
		if conflicts.has(sid):
			continue
		var cur := _read_ship_axes_source(sid)
		var want := "bow:%s up:%s" % [bow_s, up_s]
		if bool(cur["found"]) and String(cur["raw"]) == want:
			same += 1
		else:
			pending += 1
	return {"pending": pending, "same": same, "conflicts": conflicts.size(), "conflict_ids": conflicts}


## ★ 38 轮：找出"**双重 180° 冲突**"的船。
##
## 判据（红线 27 / 37a / 47b）：
##   `FLIP` 与"bow 轴翻号"是**同一个 180° 的两种表达，一艘船只许一处**。
##   若某船**在 FLIP 名单里**，而姿势表/工具又把它 bow 从 `+X` 改成 `−X`
##   （相对**源码现值**翻号），两者会**叠加 = 抵消 = 倒飞**，
##   而且**不报错**（静默错，最难查）。
##
## 返回：冲突船 id 的数组（`PackedStringArray`）。
##
## ⚠️ 为什么用"相对源码现值翻号"而不是"绝对值"：
##   源码现值已经包含了"该船当前是否靠 bow 表达 180°"的决策；
##   我们只需要判断**本次改动会不会让 180° 被表达两次**。
func _check_flip_conflicts() -> PackedStringArray:
	var out := PackedStringArray()
	var src_path := ProjectSettings.globalize_path("res://scripts/data/eve_ship_yaw.gd")
	if not FileAccess.file_exists(src_path):
		return out
	var fa := FileAccess.open(src_path, FileAccess.READ)
	if fa == null:
		return out
	var src := fa.get_as_text()
	fa.close()
	# 提取 FLIP 名单（`const FLIP` 到其后第一个 `]`）
	var flip := _parse_string_array_block(src, "const FLIP")
	for k in _pose_table.keys():
		var sid := String(k)
		if not flip.has(sid):
			continue
		var rec: Variant = _pose_table[k]
		if not (rec is Dictionary):
			continue
		var bow_new := String(rec.get("bow", ""))
		if bow_new == "":
			continue
		var cur := _read_ship_axes_source(sid)
		if not bool(cur["found"]):
			continue
		var bow_old: String = _format_axis(cur["bow"])
		# 翻号 = 同轴但符号相反（`+X` ↔ `−X`）
		if bow_old.length() == 2 and bow_new.length() == 2 \
				and bow_old[1] == bow_new[1] and bow_old[0] != bow_new[0]:
			out.append(sid)
	return out


## 从源码里抠出 `const <name> ... = [ "a", "b" ]` 这种字符串数组的元素。
func _parse_string_array_block(src: String, decl_prefix: String) -> PackedStringArray:
	var out := PackedStringArray()
	var i := src.find(decl_prefix)
	if i < 0:
		return out
	var j := src.find("]", i)
	if j < 0:
		return out
	for m in src.substr(i, j - i).split(","):
		var t := m.strip_edges().strip_escapes()
		var q0 := t.find("\"")
		if q0 < 0:
			continue
		var q1 := t.find("\"", q0 + 1)
		if q1 > q0:
			out.append(t.substr(q0 + 1, q1 - q0 - 1))
	return out


## ★ 34 轮：把"已固定"清单落盘 + 返回是否成功。
## 落到 `user://bow_calib/fixed.json`：`{ "catalyst": {"bow":"-X","up":"+Y"}, ... }`
## 为什么不复用 ship_axes.json：那个文件同时存了 views 六项，
## 而"已固定清单"是给用户对账用的**短表**，单独一份更便于查看与清理。
func _mark_fixed(sid: String, bow_str: String, up_str: String) -> bool:
	var path := "user://bow_calib/fixed.json"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://bow_calib"))
	var data: Dictionary = {}
	if FileAccess.file_exists(path):
		var fr := FileAccess.open(path, FileAccess.READ)
		if fr != null:
			var parsed: Variant = JSON.parse_string(fr.get_as_text())
			if parsed is Dictionary:
				data = parsed
	data[sid] = {"bow": bow_str, "up": up_str}
	var fw := FileAccess.open(path, FileAccess.WRITE)
	if fw == null:
		return false
	fw.store_string(JSON.stringify(data, "\t"))
	fw.close()
	# 清单随改随重载，HUD / 列表立即可见
	_fixed_ships = data
	# ★ 34 轮：**必须立刻重刷列表**，否则 ✔ 标记要等下一次列表刷新才出现
	#   （用户按回车后看不到"这艘已固定"的凭证 = 本 bug 的表征）。
	#   自检 `_run_fix_self_test` 会断言"清单非空 ⇒ 列表至少一行带 ✔"。
	if _ship_list != null:
		_refresh_ship_list()
	return data.has(sid)


## 读取"已固定"清单（启动时调一次）
func _load_fixed_list() -> void:
	_fixed_ships = {}
	var path := "user://bow_calib/fixed.json"
	if not FileAccess.file_exists(path):
		return
	var fr := FileAccess.open(path, FileAccess.READ)
	if fr == null:
		return
	var parsed: Variant = JSON.parse_string(fr.get_as_text())
	if parsed is Dictionary:
		_fixed_ships = parsed


func _save_calibration(sid: String, bow_str: String, up_str: String, view_axes: Dictionary) -> bool:
	var path := "user://bow_calib/ship_axes.json"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://bow_calib"))
	var data: Dictionary = {}
	if FileAccess.file_exists(path):
		var f_read := FileAccess.open(path, FileAccess.READ)
		if f_read != null:
			var parsed: Variant = JSON.parse_string(f_read.get_as_text())
			if parsed is Dictionary:
				data = parsed
	data[sid] = {"bow": bow_str, "up": up_str, "views": view_axes}
	var f_write := FileAccess.open(path, FileAccess.WRITE)
	if f_write == null:
		return false
	f_write.store_string(JSON.stringify(data, "\t"))
	f_write.close()
	# ★ 34 轮：**读回校验**。再开一次读、parse、断言这条真的在里面且值一致。
	#   为什么必须做：`store_string` 失败不返回错误码，只靠 `f_write == null` 判，
	#   磁盘满 / 权限 / 路径异常时会静默丢数据，而界面照样显示"已保存"。
	var vf := FileAccess.open(path, FileAccess.READ)
	if vf == null:
		return false
	var back: Variant = JSON.parse_string(vf.get_as_text())
	if not (back is Dictionary):
		return false
	if not back.has(sid):
		return false
	var rec: Variant = back[sid]
	if not (rec is Dictionary):
		return false
	return String(rec.get("bow", "")) == bow_str and String(rec.get("up", "")) == up_str


func _project_to_axis(v: Vector3) -> Vector3:
	# 取绝对值最大的分量
	var ax := absf(v.x); var ay := absf(v.y); var az := absf(v.z)
	if ax >= ay and ax >= az:
		return Vector3(1.0 if v.x > 0.0 else -1.0, 0.0, 0.0)
	elif ay >= ax and ay >= az:
		return Vector3(0.0, 1.0 if v.y > 0.0 else -1.0, 0.0)
	else:
		return Vector3(0.0, 0.0, 1.0 if v.z > 0.0 else -1.0)


## ⚠️ 33 轮起**没有"整组旋转矩阵"了**——每根轴各自有方向 `_axis_dirs[i]`。
## 落表时直接读**该根轴自己的方向**，再乘船姿反解，不再需要 R_axis：
##   舰艏模型轴 = R_ship⁻¹ · _axis_dirs[0]
## （旧式 `R_ship⁻¹ · R_axis · VIEW_AXES[0]` 里 `R_axis · VIEW_AXES[0]`
##   恰好就是"第 0 根轴的当前方向"，所以两者等价——但新版更直接、更不易错。）


## 第 i 根轴在**模型空间**的指向 = 屏上方向经船姿反解。
## 转船后必须反解回去，否则落表会写歪（红线 40 同类坑）。
func _axis_dir_in_model(i: int) -> Vector3:
	return (_ship_rotation().inverse() * _axis_dirs[i]).normalized()


func _guess_bow_from_rod() -> Vector3:
	return _project_to_axis(_axis_dir_in_model(0))


func _guess_up_from_rod() -> Vector3:
	return _project_to_axis(_axis_dir_in_model(4))


func _format_axis(v: Vector3) -> String:
	for i in 3:
		if absf(v[i]) > 0.5:
			return ("+" if v[i] > 0.0 else "-") + ["X", "Y", "Z"][i]
	return "(%.2f,%.2f,%.2f)" % [v.x, v.y, v.z]


## ⚠️ 33 轮：**不再有"整组旋转"**。`_axis_root` 只做整组平移 + 整组缩放，
## 旋转信息全部在 `_axis_dirs` 里按根存。所以本函数**不再设置 basis**。
func _apply_axis_root_transform() -> void:
	_axis_root.position = _root_pos
	_axis_root.basis = Basis.IDENTITY
	_axis_root.scale = Vector3.ONE * _root_scale


## 只转**第 i 根**轴（33 轮核心）。轴转 = 它的指向 `_axis_dirs[i]` 被旋转，
## 其余 5 根**一个字节都不动**。
## `yaw_d/pitch_d/roll_d` 是在**世界系**下绕三轴的增量（弧度）。
## 注意：绕自己转（roll）对一根"没有厚度的杆"是**视觉不可见**的，
## 但语义上仍然合法（它决定红球在哪一侧），所以一并支持。
func _rotate_single_axis(i: int, pitch_d: float, yaw_d: float, roll_d: float) -> void:
	if i < 0 or i >= _axis_dirs.size():
		return
	var rot := Basis.from_euler(Vector3(pitch_d, yaw_d, roll_d))
	_axis_dirs[i] = (rot * _axis_dirs[i]).normalized()
	_refresh_axis_visual()


func _refresh_axis_visual() -> void:
	for i in VIEW_AXES.size():
		var rod: MeshInstance3D = _axis_root.get_node("Rod_%d_%s" % [i, VIEW_NAMES[i]])
		var length := ROD_BASE * _axis_scales[i]
		var bm := rod.mesh as BoxMesh
		bm.size = Vector3(ROD_THICK, ROD_THICK, length)
		# ★ 用**每根自己的方向** `_axis_dirs[i]`（33 轮前这里读的是全局 VIEW_AXES[i]，
		#   再靠父节点 rotation 整组转——那正是"转一根全在转"的根源）
		var a: Vector3 = _axis_dirs[i].normalized()
		var p_pos: Vector3 = _axis_centers[i]
		rod.position = p_pos
		# 杆的局部 +Z 对齐到 a：盒子长边在局部 Z，`looking_at` 正好把 +Z 指到 a
		var up_hint := Vector3.UP if absf(a.y) < 0.9 else Vector3.FORWARD
		rod.basis = Basis.looking_at(a, up_hint)
		var ball_offset: Vector3 = a * (length * 0.5)
		# ⚠️⚠️ 41 轮：**必须按名字取球**，不许用 `rod.get_index() + 1` 猜。
		#   旧写法假设"球紧跟杆"，但 Node 子节点按**名字**排序：
		#     `Ball_*` < `Label_*` < `MeshInstance3D*`(无名球) < `Rod_*`
		#   ⇒ 无名球排在杆**之前**，`+1` 拿到的是别的节点（下一根杆 / label）
		#   ⇒ **红蓝球自建成起就没跟着轴走过**，用户看到的红球位置与
		#     `_axis_dirs[i]` 的正负号脱钩 ⇒ 41 轮 52 艘全标反（落盘全背敌）。
		#   本 bug **不报错**（球还在画面里，只是位置错）⇒ 必须靠点名取值根除。
		var b_plus: MeshInstance3D = _axis_root.get_node("Ball_%d_%s_plus" % [i, VIEW_NAMES[i]]) as MeshInstance3D
		var b_minus: MeshInstance3D = _axis_root.get_node("Ball_%d_%s_minus" % [i, VIEW_NAMES[i]]) as MeshInstance3D
		if b_plus == null or b_minus == null:
			push_error("[probe_bow_box] 第 %d 根轴的球取不到（Ball_%d_*_plus/minus）—— 红蓝球会与轴脱钩，禁止继续" % [i, i])
			continue
		b_plus.position = p_pos + ball_offset
		b_minus.position = p_pos - ball_offset
		if i < _axis_labels.size():
			var axis_label: Label3D = _axis_labels[i]
			# 文字固定挂在**红球端**（= 该视图方向），转轴时跟着走
			axis_label.position = p_pos + a * (length * 0.5 + 0.12)
			# ⚠️ 53 轮：文字走 `_label_text_for()`（与建标签时**同一处**定义），
			#     别在这里再拼一次字符串 —— 两处各写一份必然漂移。
			axis_label.text = _label_text_for(i)


## ★ 53 轮 · **轴体标签文字 —— 唯一定义处**（建标签 / 刷新标签都调它）
##
## ═══ 为什么要加「编号 + 轴向」（用户 53 轮要求）═══════════════════════
##  用户原话：「我还建议在轴体上标出 YXZ 及 ±，好知道到底是在哪根轴体上旋转」
##
##  旧标签只有 `主视图\n舰艏方向` 两行 —— 六根杆从中心发散、转轴后位置会变，
##  **根本分不清哪根是哪根**，也就无从知道"我现在转的是哪一根"。
##  （用户一度把「后视图(船尾方向)」那根杆当成了主视图 —— 因为它的红球
##   恰好压在船头上：那其实说明**这艘船舰艏在模型 −Z 端**，正是要标定的结论。）
##
## ⇒ 三段式标签，每行各管一件事：
##      `#1 主视图`          ← `#n` 与键盘 `1~6` 一一对应（缩放/悬停选中用）
##      `舰艏方向 [+Z]`      ← 语义 + **当前轴向**（`_axis_dirs[i]`，会随转动变）
##
## ⚠️ 轴向取自 `_axis_dirs[i]`（**当前**方向），不是 `VIEW_AXES[i]`（初始方向）
##    —— 转过之后两者就不同了，标初始值会骗人。
## ⚠️ 红球端 = 该视图方向 = 标签所在端；**蓝球端是反方向**（不再单独标字，
##    靠颜色区分，避免六根杆的文字互相遮挡）。
func _label_text_for(i: int) -> String:
	return "#%d %s\n%s [%s]" % [
		i + 1, VIEW_NAMES[i], VIEW_DEFINITIONS[i], _axis_name(_axis_dirs[i])]


func _make_axis_label(i: int) -> Label3D:
	var label: Label3D = Label3D.new()
	label.name = "Label_%d_%s" % [i, VIEW_NAMES[i]]
	label.text = _label_text_for(i)
	label.font_size = 32
	label.pixel_size = 0.0028
	label.outline_size = 8
	label.modulate = Color(1.0, 0.92, 0.64)
	label.outline_modulate = Color(0.02, 0.03, 0.05, 0.96)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label


func _apply_orbit() -> void:
	var cam: Camera3D = _cam_orbit.get_child(0) as Camera3D
	cam.position = Vector3(
		cos(_orbit_state.pitch) * sin(_orbit_state.yaw) * _orbit_state.distance,
		sin(_orbit_state.pitch) * _orbit_state.distance,
		cos(_orbit_state.pitch) * cos(_orbit_state.yaw) * _orbit_state.distance)
	cam.look_at(_root_pos, Vector3.UP)


func _load_current() -> void:
	for c in _holder.get_children():
		_holder.remove_child(c)
		c.queue_free()
	if _idx < 0 or _idx >= _ids.size():
		return
	var sid := StringName(_ids[_idx])
	_cur_sid = String(sid)
	var model := EveShipModel.instantiate(sid)
	if model == null:
		_refresh_hud()
		return
	var aabb := _aabb_of(model, Transform3D())
	if aabb.size.length() < 0.0001:
		model.queue_free()
		return
	var long_len := maxf(aabb.size.x, maxf(aabb.size.y, maxf(aabb.size.z, 0.0001)))
	var sc := 1.0 / long_len
	# 舰船固定在舞台原点；归一化只写入舰船自己的根节点。
	# 这里必须在 add_child 后再次明确设置，防止模型内部 global_transform
	# 或后续轴体变换被误读成共享父变换。
	_holder.add_child(model)
	# 归一化基准：先 AABB 居中（模型空间），再整体缩放到单位长度。
	# 注意顺序——先把**模型**平移到原点（在缩放之前），所以平移量是模型空间中心。
	#
	# ★★★ 49 轮：**在归一化基准里叠加生产的零姿态 `zero_pose_basis`**。
	#
	# ── 为什么必须这样（用户 49 轮的原话）──────────────────────────
	#   「我那个工具是不是白花 token 来写了？我定了舰船的朝向，
	#     那按照我定的再全部定其他地方的位置不就行了？」
	#
	# ── 病根（49 轮 `probe_diag49` 实测）───────────────────────────
	#   此前工具里的船 = **模型原始姿态**（`_ship_norm.basis` 是纯缩放 ⇒
	#   用户 `r` 为单位阵时船姿 = 单位阵），而实机里船的静止姿态是
	#   `zero_pose_basis(id) = R_z(180°) · R_y(extra) · M · mesh_rot`
	#   ⇒ **52/52 艘都不是单位阵**。
	#   ⇒ 工具里看到的船，与实机里静止的船**根本不是同一个姿态** ——
	#     所以用户在工具里"以眼为准"定好的方向，到实机必然对不上。
	#     **这就是"天天调却调不好"的根因：两个参照系不是同一个。**
	#
	# ── 修法：把零姿态**烘进归一化基准** ────────────────────────────
	#   `basis = zp · scale` ⇒ 工具里的船与实机静止姿态**逐像素同一**。
	#   ⇒ 从此「工具里定好的方向 = 实机里的方向」，一处定、全局用。
	#
	# ⚠️ 顺序与红线 25 一致：**先 basis（含 zp）再 scale**，
	#    写成 `Basis.IDENTITY.scaled(sc)` 再左乘 zp 是等价的（zp 无缩放），
	#    但**不要**写成 `zp.scaled(...)`（`Basis.scaled` 是右乘每列，语义不同）。
	_ship_norm = Transform3D(_zero_pose_of(sid) * Basis.IDENTITY.scaled(Vector3.ONE * sc),
			-(sc * aabb.get_center()))
	_apply_ship_transform()
	_refresh_hud()


## 当前船的**生产零姿态基**（= 实机里静止时的船姿）。
##
## ⚠️ 这是「工具 ↔ 实机」唯一的同步点：工具把这一层烘进船姿，
##    轴杆那边（`_static_basis`）**同样**用它反解 ⇒ 两边永远一致。
## ⚠️ 静态函数必须走 `.call()`（`load()` 拿到的是 GDScript 资源）。
##
## ═══════════════════════════════════════════════════════════════════════
##  ⛔⛔ 53 轮（第五版）：上面那段"永远一致"的论证**是错的**，是本项目
##     反复改不好朝向的**总根因**。以下为事故分析，不许删。
## ═══════════════════════════════════════════════════════════════════════
##
##  `zero_pose_basis(id) = R_y(yaw) · M · mesh_rot`，其中 **`M` 由 `bow`/`up`
##  反解而来**（`AXIS_REMAP`）。于是工具里船的显示姿态链是：
##
##      bow（表值）─→ M ─→ 工具里船的样子 ─→ 用户看"哪端是船头"
##                          ↑                            │
##                          └──────── 反推出新 bow ←──────┘
##
##  ⇒ **循环论证**。工具里的船**永远已被摆成"船头朝 −Z"**（因为 M 就是干这个的），
##    所以用户在屏幕看到的"船头"，其位置是**被 bow 决定的**，而不是原始 glb 的
##    真实朝向。用户标出的 bow 只是"让这个循环自洽"的值 —— 它可能压根不是
##    原始模型的舰艏轴。
##
##    ⇒ 后果：改一次表 → M 变 → 工具里船换样子 → 用户重标 → 又变……
##      53 轮前五版共改 6 次、每次"全绿"、实机越来越乱，就是这个机制。
##
## ═══ 修法：给工具加一个「原始姿态」开关（`--raw`）═══════════════════════
##  显示**不含 M** 的 glb 原始朝向（只带 `mesh_rot`）⇒ 用户看到的是
##  **未经任何修正的模型本体**，标出来的才是模型真实轴。
##  ⚠️ `mesh_rot` 要保留：那是 glb 内层网格自带的旋转，属于"模型本身"，
##     不是我们的修正（红线 48）。去掉它反而会引入第二个错误。
##
##  用法：`-- --raw`（配合 `--print-labels` 等同样有效）
## ⚠️ 不能写成 `const` —— GDScript 要求常量用**常量表达式**，
##    `OS.get_cmdline_user_args()` 是运行时的 ⇒ 改 `var`，在 `_ready()` 里赋值。
var RAW_POSE := false


## ═══════════════════════════════════════════════════════════════════════
##  ⛔⛔⛔ 53 轮（第七版）：**本函数一直多乘了一次 `mesh_rot`** —— 这是
##      "全部不对"的真正根因（比上面那条循环论证更根本）。不许删此段。
## ═══════════════════════════════════════════════════════════════════════
##
##  事实：`EveShipModel.instantiate(sid)` 拿到的模型是
##      **根(basis=单位阵) → 子网格(basis=`mesh_rot`)**   ← 子网格**自带**旋转
##  （`EveShipVisual.mesh_rot_of()` 就是读 `子网格.transform.basis` 得来的）
##
##  而实机走的是 `_build_hull_model()` → `_bake_mesh_rotation()`：
##      把子网格旋转**提升到根**，并把子网格旋转**清成单位阵**
##      ⇒ 实机几何体朝向 = `R_y(yaw) · M · mesh_rot`   （`mesh_rot` 只出现**一次**）
##
##  工具这边 `holder.basis = _zero_pose_of(sid)`，几何体朝向 =
##      `holder.basis × 子网格mesh_rot`
##
##  ⇒ 旧代码 `_zero_pose_of = zero_pose_basis = R_y·M·**mesh_rot**`
##      ⇒ 几何体 = `R_y·M·mesh_rot·mesh_rot`  ← **多了一次 mesh_rot** ❌
##
##  后果（用户原话「全部不对」）：
##    · 工具里的船与实机里的船**系统性差一个 `mesh_rot`**；
##    · 更要命的是轴杆也错位：轴位置用 `_static_basis·v`（只乘一次），
##      船却乘了两次 ⇒ **红球压在船头上时，反推出的轴是错的**。
##
## ═══ 修法：holder 不再带 `mesh_rot`（让子网格自己的那一次生效）═════════
##    · 正常模式：返回 `zero_pose_basis · mesh_rot⁻¹` = `R_y·M`
##      ⇒ 几何体 = `R_y·M·mesh_rot` = **与实机逐像素一致** ✓
##    · `--raw` 模式：返回 **单位阵**
##      ⇒ 几何体 = `mesh_rot` = **glb 原始姿态**（用来判断真船头在哪）✓
##  两个模式下 `_static_basis` 都等于"几何体朝向" ⇒ 轴与船**同一空间**。
## ═══════════════════════════════════════════════════════════════════════
##  ⚠️⚠️ 53 轮（第七版）：本函数**曾被我改错并已回滚**，记录在此防止再犯。
## ═══════════════════════════════════════════════════════════════════════
##
##  我当时的怀疑：`EveShipModel.instantiate()` 返回「根(单位阵)→子网格(mesh_rot)」，
##    而实机烘焙后 = `R_y·M·mesh_rot` ⇒ 若 holder 也带 mesh_rot 就**乘了两次**，
##    系统性偏差 = mesh_rot ⇒ 用户「全部不对」就是这么来的。
##
##  ⇒ 我据此把 holder 改成 `zero_pose_basis · mesh_rot⁻¹`（想去掉那一次）。
##
##  ⇒ **`tools/probe_toolvsgame53.tscn` 实测打脸**：
##        B（去掉一次 mesh_rot）与实机 A 差 **180.0°**        ❌
##        C（holder 直接用 zero_pose_basis）与 A 差 **360°=0°** ✅
##
##  ⇒ 真相：`EveShipModel.instantiate()` 拿到的模型，**节点总变换就是单位阵**
##    （`mesh_rot` 并不体现在节点变换上）⇒ holder 必须**直接**等于目标姿态，
##    不存在"多乘一次"。
##
##  ⚠️ 教训：**怀疑必须先用对拍探针证伪再改**（我这次先改后测，差点把对的代码
##     改坏）。对拍探针已留在工程里：
##     `probe_toolvsgame53` —— A(实机 setup+snap) vs B/C(工具路径)，读引擎真值。
func _zero_pose_of(sid: StringName) -> Basis:
	# ★ 53 轮：`--raw` ⇒ 跳过 `M`，只留 glb 内层网格旋转 = **模型原始朝向**。
	if RAW_POSE:
		var mr: Variant = EVE_VISUAL.call("mesh_rot_of", sid)
		if mr is Basis:
			return (mr as Basis).orthonormalized()
		return Basis.IDENTITY
	var b: Variant = EVE_VISUAL.call("zero_pose_basis", sid)
	if b is Basis:
		return (b as Basis).orthonormalized()
	return Basis.IDENTITY


## 舰船自身姿态（独立于轴体）。**先归一化、后船姿**：
## holder.basis = R_ship · scale ；holder.origin = R_ship · norm.origin
func _ship_rotation() -> Basis:
	return Basis.from_euler(Vector3(_ship_pitch, _ship_yaw, _ship_roll))


func _apply_ship_transform() -> void:
	if _holder == null:
		return
	var r := _ship_rotation()
	var norm := _ship_norm
	_holder.transform = Transform3D(r * norm.basis, r * norm.origin)


func _refresh_hud() -> void:
	if _idx < 0 or _idx >= _ids.size():
		return
	var sid := StringName(_ids[_idx])
	_cur_sid = String(sid)
	# 列表高亮跟随当前船（翻艘键 ←/→ 后也要同步，否则列表停在旧船）
	if _ship_list != null:
		for i in _list_ids.size():
			if _list_ids[i] == _cur_sid:
				if _ship_list.get_selected_items() != PackedInt32Array([i]):
					_ship_list.select(i)
				break
	var cur_axes := "bow:%s up:%s" % [_axis_name(YAW.bow_axis(sid)), _axis_name(YAW.up_axis(sid))]
	var cur_remap: String = YAW.AXIS_REMAP.get(sid, "·(无)")
	var in_flip: bool = String(sid) in YAW.FLIP
	var deg: float = YAW.AXIS_DEG.get(sid, 0.0)
	# ★ 35 轮：**「表内现值」从源码实时读**（不是内存常量、不是工具便签）。
	#   用户的问题「我哪知道有没有写进游戏规则」⇒ 答案就在这一行：
	#   它读的是 `scripts/data/eve_ship_yaw.gd` 文件本身，跟游戏读到的是同一份。
	var tbl := _read_ship_axes_source(String(sid))
	var tbl_raw := String(tbl["raw"]) if bool(tbl["found"]) else "（表里没有这艘）"
	var cn: String = String(INDEX.by_id(sid).cn) if INDEX.by_id(sid) != null else ""
	# ★ 36 轮：HUD 顶部三行 —— 把"我到底改没改成功"拆成两件事讲清楚：
	#   ① 姿势表（我刚按回车存进去的东西，**本次会打 √**）
	#   ② 游戏规则表源码（游戏真正读的，**下次启动工具时才落盘**）
	var pose_badge := ""
	if _fixed_ships.has(String(sid)):
		pose_badge = "   ✔ 本次已存入姿势表"
	elif _pose_table.has(String(sid)):
		pose_badge = "   ◇ 姿势表里有（非本次）"
	else:
		pose_badge = "   ○ 姿势表里没有"
	_hud.text = "[%d/%d]  %s（%s）   工具：舰船建模方向姿势确认" % [_idx + 1, _ids.size(), cn, String(sid)]
	_hud.text += pose_badge
	_hud.text += "\n  ▣ 本次启动：%s   姿势表共 %d 艘" % [_flush_report, _pose_table.size()]
	# ★ 38 轮：逐船显示"落盘会不会被 FLIP 冲突拦下"
	#   红线 27：`FLIP` 与"bow 翻号"是**同一个 180° 的两种表达，只许一处**。
	#   两者同时存在 ⇒ 抵消 ⇒ 倒飞（不报错）。这条提示让用户当场看到风险。
	if _pose_table.has(String(sid)):
		var rec0: Variant = _pose_table[String(sid)]
		if rec0 is Dictionary:
			var bow_new := String(rec0.get("bow", ""))
			# ⚠️ 39 轮：这里必须用**模型空间**的 `bow_axis()` 对比 ——
			#   姿势表存的就是模型轴，FLIP 表达的也是模型空间的 180°，两者同系。
			#   若误用世界方向对比，会把"正常的 remap 翻号"误报成冲突。
			var bow_old := _format_axis(YAW.bow_axis(sid))
			var flip_hit := String(sid) in YAW.FLIP
			var conflict := flip_hit and bow_old.length() == 2 and bow_new.length() == 2 \
				and bow_old[1] == bow_new[1] and bow_old[0] != bow_new[0]
			if conflict:
				_hud.text += "\n  ⛔ **FLIP 冲突**：这艘在 FLIP 名单里，姿势表又把 bow 从 %s 翻成 %s" % [bow_old, bow_new]
				_hud.text += "\n     = 180° 被表达两次 ⇒ 抵消成倒飞（红线 27）。落盘会**跳过**这艘，需手工二选一。"
			elif flip_hit:
				_hud.text += "\n  ⚠ 这艘在 FLIP 名单里（%s）；落盘只改 bow/up，**不会**动 FLIP。" % String(sid)
	# ★ 36 轮：来源分层显示 —— 上面是"游戏真正读的"，中间是"我刚存的"
	_hud.text += "\n  ▣ 游戏规则表源码现值（游戏读这个）= \"%s\"" % tbl_raw
	# ★★★ 39 轮：**把「模型轴」与「世界轴」两段分开展示** —— 这是本 bug 的护栏。
	#   用户报「关掉窗口又回默认」的真根因就是这两段被混成了一段：
	#   工具拿 `bow_axis()`（**模型空间**）当世界方向画轴体，跳过了 `AXIS_REMAP`。
	#   本库 47 艘的 `AXIS_REMAP` 恰含一个 180° ⇒ 模型 +X 在世界里其实是 −X
	#   ⇒ 用户"看着轴体"标定，等于在反的参照系里操作。
	#   ⇒ 从此 HUD **两段都显示**，并指明**哪一段是游戏里真正的方向**。
	if bool(tbl["found"]):
		var b_model: Vector3 = YAW.bow_axis(sid)
		var u_model: Vector3 = YAW.up_axis(sid)
		var b_world: Vector3 = _axis_dir_to_world(b_model, String(sid))
		var u_world: Vector3 = _axis_dir_to_world(u_model, String(sid))
		_hud.text += "\n  ▣ 模型空间语义轴（SHIP_AXES 里存的）= bow:%s up:%s" % [
			_axis_name(b_model), _axis_name(u_model)]
		_hud.text += "\n  ▣ 世界方向（= 轴体画面 = 游戏里看到的）= bow:%s up:%s" % [
			_axis_name(b_world), _axis_name(u_world)]
		var toward: String = "朝敌 ✅" if b_world.dot(Vector3(0, 0, -1)) > 0.9 else "背敌 ❌"
		_hud.text += "\n     舰艏世界朝向 %s ⇒ **%s**" % [_axis_name(b_world), toward]
		if _format_axis(b_model) != _format_axis(b_world):
			_hud.text += "\n     ⚠ 两者不同是**正常的**：本船 AXIS_REMAP=%s 含一次 180°，\n        它把模型轴翻到世界里去了。标定时**只认「世界方向」那一行**。" % cur_remap
	# ★ 43 轮：把"这艘标过没有"从**跨会话持久**的姿势表读，而不是只看本次会话。
	#   用户重开工具后最想看的就是这一行 —— 它必须与磁盘上的真实凭证一致。
	var pose_has := _pose_table.has(String(sid))
	var sess_has := _fixed_ships.has(String(sid))
	var shown_rec: Variant = _pose_table.get(String(sid)) if pose_has else _fixed_ships.get(String(sid))
	if shown_rec is Dictionary:
		var origin_tag := "✔ 已登记（本次会话）" if sess_has else "✔ 已登记（上次会话存的）"
		_hud.text += "\n  ▣ %s → \"bow:%s up:%s\"" % [
			origin_tag, String(shown_rec.get("bow", "")), String(shown_rec.get("up", ""))]
		_hud.text += "\n     表文件：%s（共 %d 艘已登记）" % [
			ProjectSettings.globalize_path(POSE_TABLE_PATH), _pose_table.size()]
	else:
		_hud.text += "\n  ▫ 这艘**尚未登记** —— 摆好红球后按回车存入姿势表"
	_hud.text += "\n  ▣ 内存常量值（--import 后应与源码行一致） = %s" % cur_axes
	if tbl_raw != cur_axes and bool(tbl["found"]):
		_hud.text += "\n     ⚠ 两者不一致：源码已改但进程内常量未刷新 ⇒ 跑一次 `--import` 或重启工具即可对齐"	# ★ 37 轮：把"轴体是从哪份数据摆出来的"写在脸上 —— 用户切回已存的船，
	#   一眼能看出轴体是"按姿势表还原的"还是"表里没有、回的默认"。
	if _axis_restore_note != "":
		_hud.text += "\n  ↺ %s" % _axis_restore_note
	else:
		_hud.text += "\n  ↺ 轴体=默认基线（这艘在姿势表和源码里都没登记值）"
	# ★ 40 轮：把"旧表去哪了"写在脸上（用户要自己验证，不能只给结论）
	if _archive_note != "":
		_hud.text += "\n  🗄 旧姿势表已归档：%s（**没有删**，要对比随时能捞回来）" % _archive_note
	# ★ 43 轮：全库 52 艘朝敌对账（原「3 艘锚点对账」已扩成全库；`_anchor_gap_note` 已随箭头删除而作废）
	_hud.text += "\n  🧭 %s" % _anchor_report
	_hud.text += "\n  现行 AXIS_REMAP = %s    FLIP=%s   AXIS_DEG=%.2f°" % [cur_remap, ("Y" if in_flip else "·"), deg]
	_hud.text += "\n  中心偏移=(%+.2f, %+.2f, %+.2f)   整组缩放=%.2f" % [_root_pos.x, _root_pos.y, _root_pos.z, _root_scale]
	_hud.text += "\n  ▸ 舰船旋转：Y %+.1f°  X %+.1f°  Z %+.1f°   （Shift + W/A/S/D/Q/E）" % [rad_to_deg(_ship_yaw), rad_to_deg(_ship_pitch), rad_to_deg(_ship_roll)]

	# ── 锁状态 + 每根轴当前指向（33 轮：改成逐根显示，可直观核对"只转了一根"）──
	var hovered := _axis_hover_for_gate()
	if hovered >= 0:
		_hud.text += "\n  🔓 已选中「%s」——裸 W/A/S/D 只转**这一根**（1~6 只缩放这一根）" % VIEW_NAMES[hovered]
	else:
		_hud.text += "\n  🔒 轴体方向已锁定（把鼠标移到某根轴上才可转/缩放）"
	_hud.text += "\n  六轴当前指向（**世界方向 = 游戏里看到的方向**；转只改选中那行）："
	for i in VIEW_NAMES.size():
		var mark := "▶" if i == hovered else " "
		_hud.text += "\n   %s %d %s = %s   长%.2f" % [mark, i + 1, VIEW_NAMES[i], _axis_name(_axis_dirs[i]), _axis_scales[i]]
	if _gate_hint != "":
		_hud.text += "\n  %s" % _gate_hint
	_hud.text += "\n  按 [确定] = **存入姿势表**（打 ✔ · 切下一艘）—— 游戏规则表下次启动本工具时才落盘"
	_hud.text += "\n  ⚠ **本工具只登记「模型出厂姿势」**（舰艏/船背在模型哪根轴）—— 敌我方向由游戏侧统一保证，见上面 🧭 那行"

	_help.text = "右侧列表选船（中文名可搜）  |  **鼠标悬停某根轴** → 高亮该轴两端、该轴可拖动/缩放/改方向  |  拖杆平移 · 拖红/蓝端点伸缩  |  左键空白处拖：转镜头  |  右键拖：转船"
	_help.text += "\n★★ **看准星！** 鼠标旁边那个十字圈就是**你此刻会拖到的东西**："
	_help.text += "\n      🟢 绿 = 轴（可拖）· ⚪ 灰 = 没咬到 · 🔵 蓝 = 在面板上"
	_help.text += "\n      左上角那行「准星瞄准：…」是同一句话的书面版 —— **不放心就看它**。"
	_help.text += "\n★ **方向基准**：地面暗青网格 = 水平面（固定不动，给你判相机仰角用）。"
	_help.text += "\n  ⚠️ 43 轮起工具**不再画敌我方向箭头** —— 你要做的只有「把红球对准舰艏、把俯视图红球对准船背」，"
	_help.text += "\n     登记的是**模型空间的轴**；「朝向敌人」由游戏侧每一帧按规则算，不需要你摆。"
	_help.text += "\n▸ **转船**：Shift+W 向上 / Shift+S 向下 / Shift+A 向左 / Shift+D 向右 / **Shift+Q 或 E = 侧躺**（不受悬停限制）"
	_help.text += "\n▸ 转轴体：裸 W/S 上下 · A/D 左右 —— **只转鼠标悬停的那一根**，其余 5 根不动  |  Q/E 平移中心  |  1~6 缩放悬停的那根  |  滚轮 整组缩放  |  R 全重置  |  Enter 确定  |  Esc 退出"
	_help.text += "\n▸ **H = 重跑「全库 52 艘朝敌对账」**（逐艘算舰艏世界方向，任何一艘不朝敌就当场点名）"
	_help.text += "\n▸ **Ctrl+Delete = 当场清空姿势表**（重新标定前想推倒重来时用；磁盘上不会有残留）"
	_help.text += "\n▸ **保存流程**：按 [确定] ⇒ 存进 `pose_table.json`（✔ 打勾、切下一艘）⇒ 敲 `--flush` 启动时才写进游戏规则表 `eve_ship_yaw.gd`"
	_help.text += "\n⚠ 悬停某根轴时，HUD 会列出六轴当前指向，`▶` 标出当前选中那根（转只改它那一行）"


func _ball(pos: Vector3, c: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = BALL_R
	sm.height = BALL_R * 2.0
	mi.mesh = sm
	mi.position = pos
	mi.material_override = _mat(c)
	return mi


func _mat(c: Color) -> StandardMaterial3D:
	var mt := StandardMaterial3D.new()
	mt.albedo_color = c
	mt.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return mt


func _axis_name(v: Vector3) -> String:
	for i in 3:
		if absf(v[i]) > 0.5:
			return ("+" if v[i] > 0.0 else "-") + ["X", "Y", "Z"][i]
	return "(%.2f,%.2f,%.2f)" % [v.x, v.y, v.z]


func _aabb_of(root: Node, pre: Transform3D) -> AABB:
	var parts: Array[AABB] = []
	_collect_aabb(root, pre, parts)
	if parts.is_empty():
		return AABB()
	var a := parts[0]
	for i in range(1, parts.size()):
		a = a.merge(parts[i])
	return a


func _collect_aabb(n: Node, xf: Transform3D, out: Array[AABB]) -> void:
	var here := xf
	if n is Node3D:
		here = xf * (n as Node3D).transform
	if n is MeshInstance3D:
		var a := (n as MeshInstance3D).get_aabb()
		var mn := Vector3(1e9, 1e9, 1e9)
		var mx := Vector3(-1e9, -1e9, -1e9)
		for i in 8:
			var p := here * a.get_endpoint(i)
			mn = mn.min(p)
			mx = mx.max(p)
		out.append(AABB(mn, mx - mn))
	for c in n.get_children():
		_collect_aabb(c, here, out)


func _save_view(tag: String) -> void:
	var img := get_viewport().get_texture().get_image()
	if img == null:
		return
	var sid: String = _ids[_idx] if _idx >= 0 and _idx < _ids.size() else "x"
	img.save_png("user://bow_calib/%s_box_%s.png" % [sid, tag])


class _OrbitState extends RefCounted:
	var yaw: float = 0.6
	var pitch: float = 0.25
	var distance: float = 2.6
	var dragging: bool = false
