extends "res://scripts/ui/eve_window.gd"
## 斗地主 · 联机对战面板（**自包含**：建房 / 加入 / 权限说明 / 房主确认 / 房间码）。
##
## 配套设计：作者本地文档《联机方案-内置EasyTier-工程设计-2026-10-12》（未入库）
##
## ★ 为什么单独一个面板、而不是塞进 `ddz_table.gd`：牌桌已经 1800+ 行（自绘 + 驱动），
##   联机这一摊（内核权限 / 房间码 / 等待 / 确认）与牌局渲染无关，混在一起两边都难改。
##   本面板只做三件事：**驱动 `ddz_room`**、**显示状态**、**把开始/结束告诉牌桌**。
##
## ★ 三条产品规则（都来自实测与用户决定）：
##   ① 权限**只在这一刻申请**：点「创建房间」→ 先弹**说明卡**（不是系统弹窗）→
##      玩家点「继续」才真正去起内核（房主需要一次管理员权限；加入者**零权限**）。
##   ② 拒绝 / 起不来 ⇒ **不静默失败**：给一句人话原因，并提供「改用局域网」的降级路。
##   ③ 房主确认加入：8 位房间码 + 房主点「允许」。
##
## ⚠️ i18n：文案走 `T.t("KEY", "中文")` 而**不往 strings.csv 加行** ——
##    `T.t()` 对未登记的 key 会回落调用点给的中文源文（`verify_i18n` 有断言钉住这条），
##    所以在「英文冻结」期间新增界面不必动 CSV。

signal panel_closed
signal match_started              ## 对局开始 ⇒ 牌桌切到联机渲染
signal match_ended                ## 房间关闭 / 失败 ⇒ 牌桌回本地模式

const ROOM := preload("res://scripts/net/ddz_room.gd")
const RC := preload("res://scripts/net/eve_room_code.gd")
const N := preload("res://scripts/net/ddz_net.gd")
const STORE := preload("res://scripts/core/eve_settings_store.gd")
const T := preload("res://scripts/core/eve_text.gd")
const BTN := preload("res://scripts/ui/eve_button_theme.gd")
## ⚠️ 平台判据（`is_mobile()`）走它 —— 工程唯一真源
const UI_SCALE := preload("res://scripts/ui/eve_ui_scale.gd")

enum Phase { CHOOSE, PERMISSION, HOSTING, JOINING, CONNECTING, PLAYING, FAILED }

const PANEL_W := 400.0
const PANEL_H := 360.0
## 面板放大倍数 —— **按平台**（⛔ 两个数只差倍数，**两端都居中**）。
##
## ★ 2026-10-18 用户：「安卓端…联机页面太小了…放大两倍看看」→ 认可 2 倍之后又补：
##   「这个只适用于安卓端，PC 端改成居中微微放大 1.2 倍就行」。
## ⚠️ 平台判据走 `EveUiScale.is_mobile()`（工程**唯一真源**，
##    定义见 `scripts/ui/eve_ui_scale.gd`），⛔ 别在这里另写 `OS.has_feature("mobile")` ——
##    那样日后判据一改（例如加"平板算桌面"）这里会悄悄不一致。
## ⚠️ 用节点 `scale` 而不是把 `PANEL_W/H` 乘倍数：后者只放大**外壳**，里面的字号 /
##    行高 / 按钮都还是原尺寸（800×720 的窗里塞 13px 字 = 一片空荡）。
const SCALE_MOBILE := 2.0
const SCALE_DESKTOP := 1.2


## 本机该用哪个倍数。
func panel_scale() -> float:
	return SCALE_MOBILE if UI_SCALE.is_mobile() else SCALE_DESKTOP
## 昵称默认值（存档里没有时用）
const DEFAULT_NAME := "舰长"

## `ddz_room` 实例。★ 牌桌拿它读视图、发命令 ⇒ 房间活着的时候本面板可以隐藏。
var room = null
var phase := Phase.CHOOSE
## 记住「玩家选了哪条路」，失败重试时用
var _want_host := false

var _name_edit: LineEdit = null
var _avatar_rect: TextureRect = null
var _avatar_bytes: PackedByteArray = PackedByteArray()
var _avatar_dialog: FileDialog = null
var _choose_row: HBoxContainer = null
var _perm_lbl: Label = null
var _perm_row: HBoxContainer = null
var _join_row: HBoxContainer = null
var _code_edit: LineEdit = null
var _code_lbl: Label = null
var _code_row: HBoxContainer = null
var _players_lbl: Label = null
var _start_row: HBoxContainer = null
var _approve_lbl: Label = null
var _approve_row: HBoxContainer = null
var _status_lbl: Label = null
var _fail_row: HBoxContainer = null
var _close_row: HBoxContainer = null
var _btn_start: Button = null
var _btn_close: Button = null


func _ready() -> void:
	window_title = T.t("DDZ_ON_TITLE", "联机对战  ONLINE")
	layout_key = "ddz_online"
	# ★★ 必须**在 `super()` 之前**置位：✕ 是在标题栏建立时按 `closable` 决定画不画的。
	#    没有 ✕ 的后果（2026-10-12 用户实测报障「不能点返回」）：牌桌在面板可见时
	#    **吞掉全部输入**，而 CHOOSE 阶段又没有「离开房间」⇒ 玩家卡死在面板里。
	closable = true
	super()
	# ✕ 与牌桌的「← 返回」走同一条路（见 `hide_panel()`）
	close_requested.connect(hide_panel)
	# ⚠️⚠️ `EveWindow` **不会**自动调 `_build_contents()`（设置窗是自己调的）——
	#   漏了这一步的表现是「窗框和标题都在、内容一片空」，而且**不报错**（实测踩过）。
	_build_contents()
	_load_saved_avatar()
	_refresh()
	visible = false
	# ⚠️ `_build()` 跑完宽度还没定，量高度会拿到垃圾值 ⇒ 等两帧（与设置窗同一套路）
	await get_tree().process_frame
	await get_tree().process_frame
	_fit_height()


# ══════════════════════════════════════════════════════════ 构建

func _build_contents() -> void:
	content.add_theme_constant_override("separation", 7)

	# ── 昵称（军团里的人得互相认得出来）──
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 6)
	name_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_row.add_child(_lab(T.t("DDZ_ON_NAME", "昵称"), C_TEXT_DIM, 13, 64))
	_name_edit = _edit(10)
	_name_edit.text = String(STORE.load_all().get("ddz_name", DEFAULT_NAME))
	_name_edit.text_submitted.connect(func(_s: String): _save_name())
	name_row.add_child(_name_edit)
	content.add_child(name_row)

	# ── 头像（进房时同步给好友；空 = 用牌桌几何占位）──
	var av_row := HBoxContainer.new()
	av_row.add_theme_constant_override("separation", 6)
	av_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	av_row.add_child(_lab(T.t("DDZ_ON_AVATAR", "头像"), C_TEXT_DIM, 13, 64))
	_avatar_rect = TextureRect.new()
	_avatar_rect.custom_minimum_size = Vector2(56.0, 56.0)
	_avatar_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	_avatar_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	av_row.add_child(_avatar_rect)
	av_row.add_child(_btn(T.t("DDZ_ON_PICK", "选择图片…"), func(): _on_pick_avatar(), true))
	av_row.add_child(_btn(T.t("DDZ_ON_CLEAR", "清除"), func(): _clear_avatar()))
	content.add_child(av_row)

	# 文件选择器（桌面/安卓统一走它；安卓走系统选择器，需真机验证）
	_avatar_dialog = FileDialog.new()
	_avatar_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_avatar_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_avatar_dialog.add_filter("*.png,*.jpg,*.jpeg,*.webp", T.t("DDZ_ON_IMG_FILTER", "图片(*.png,*.jpg,*.webp)"))
	_avatar_dialog.file_selected.connect(_on_avatar_file_selected)
	add_child(_avatar_dialog)

	# ── ① 选择 ──
	_choose_row = _mk_row()
	_choose_row.add_child(_btn(T.t("DDZ_ON_CREATE", "创建房间"), func(): _on_create(true)))
	_choose_row.add_child(_btn(T.t("DDZ_ON_JOIN", "加入房间"), func(): _on_create(false)))
	content.add_child(_choose_row)

	# ── ② 权限说明卡（**点创建房间之后才出现**）──
	_perm_lbl = _lab("", C_TEXT, 13, 0)
	_perm_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_perm_lbl.custom_minimum_size = Vector2(PANEL_W - 40.0, 0)
	content.add_child(_perm_lbl)
	_perm_row = _mk_row()
	_perm_row.add_child(_btn(T.t("DDZ_ON_CONTINUE", "继续（需要一次管理员权限）"),
			func(): _begin_host(false), true))
	_perm_row.add_child(_btn(T.t("DDZ_ON_CANCEL", "取消"), func(): _set_phase(Phase.CHOOSE)))
	content.add_child(_perm_row)

	# ── ③ 加入：8 位房间码 ──
	_join_row = _mk_row()
	_code_edit = _edit(8)
	_code_edit.placeholder_text = T.t("DDZ_ON_CODE_HINT", "输入 8 位房间码")
	_code_edit.text_changed.connect(func(s: String):
		var norm := RC.normalize(s)
		if norm != s:
			_code_edit.text = norm
			_code_edit.caret_column = norm.length())
	_code_edit.text_submitted.connect(func(_s: String): _begin_join(false))
	_join_row.add_child(_code_edit)
	_join_row.add_child(_btn(T.t("DDZ_ON_DO_JOIN", "加入"), func(): _begin_join(false), true))
	content.add_child(_join_row)

	# ── ④ 房主：房间码 + 玩家 + 开始 ──
	_code_lbl = _lab("", C_GOLD, 20, 0)
	content.add_child(_code_lbl)
	_code_row = _mk_row()
	_code_row.add_child(_btn(T.t("DDZ_ON_COPY", "复制房间码"), func(): _copy_code()))
	content.add_child(_code_row)
	_players_lbl = _lab("", C_TEXT, 13, 0)
	_players_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_players_lbl.custom_minimum_size = Vector2(PANEL_W - 40.0, 0)
	content.add_child(_players_lbl)
	_start_row = _mk_row()
	_btn_start = _btn(T.t("DDZ_ON_START", "开始对局"), func(): _begin_match(), true)
	_start_row.add_child(_btn_start)
	content.add_child(_start_row)

	# ── ⑤ 房主确认加入 ──
	_approve_lbl = _lab("", C_GOLD, 13, 0)
	content.add_child(_approve_lbl)
	_approve_row = _mk_row()
	content.add_child(_approve_row)

	# ── ⑥ 状态 / 失败 ──
	_status_lbl = _lab("", C_TEXT_DIM, 12, 0)
	_status_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_lbl.custom_minimum_size = Vector2(PANEL_W - 40.0, 0)
	content.add_child(_status_lbl)
	_fail_row = _mk_row()
	_fail_row.add_child(_btn(T.t("DDZ_ON_RETRY", "重试"), func(): _retry()))
	_fail_row.add_child(_btn(T.t("DDZ_ON_LAN", "改用局域网"),
			func(): _fallback_lan()))
	content.add_child(_fail_row)

	_close_row = _mk_row()
	_btn_close = _btn(T.t("DDZ_ON_DISMISS", "解散房间"), func(): _dismiss())
	_close_row.add_child(_btn_close)
	content.add_child(_close_row)


# ══════════════════════════════════════════════════════════ 对外

## 打开面板（牌桌点「联机对战」时调）。
func open_panel() -> void:
	visible = true
	if phase == Phase.PLAYING:
		phase = Phase.CHOOSE
	_set_phase(phase)


## 打完了/想继续时把面板叫回来看看房间还在不在。
func room_alive() -> bool:
	return room != null and room.state != ROOM.State.IDLE \
			and room.state != ROOM.State.FAILED


# ══════════════════════════════════════════════════════════ 流程

func _on_create(as_host: bool) -> void:
	_want_host = as_host
	_save_name()
	if as_host:
		_set_phase(Phase.PERMISSION)
		_perm_lbl.text = T.t("DDZ_ON_PERM_TEXT",
			"创建房间需要让你的电脑「被好友连上」。\n\n"
			+ "· 将要申请一次管理员权限，用来创建一张虚拟网卡（仅本次游戏期间存在）；\n"
			+ "· 首次还会安装一个虚拟网卡驱动；\n"
			+ "· 不会改系统代理、不写系统服务、不常驻后台。\n\n"
			+ "拒绝也没关系：会改用局域网模式（同一 Wi-Fi 仍可一起玩）。")
	else:
		_set_phase(Phase.JOINING)


func _begin_host(skip_tunnel: bool) -> void:
	_ensure_room()
	room.skip_tunnel = skip_tunnel
	_set_status(T.t("DDZ_ON_STARTING", "正在启动联机内核…"))
	if not room.create_room(_player_name(), Time.get_ticks_msec(), 0, _avatar_bytes):
		return                       # 失败时 room 会发 failed ⇒ 已切到 FAILED
	_set_phase(Phase.HOSTING)


func _begin_join(skip_tunnel: bool) -> void:
	var code := RC.normalize(_code_edit.text)
	if not RC.is_valid(code):
		_set_status(T.t("DDZ_ON_BAD_CODE", "房间码是 8 位（字母数字，去掉 0/O/1/I）"))
		_code_edit.grab_focus()
		return
	_ensure_room()
	room.skip_tunnel = skip_tunnel
	_set_status(T.t("DDZ_ON_STARTING", "正在启动联机内核…"))
	if not room.join_room(code, _player_name(), Time.get_ticks_msec(), _avatar_bytes):
		return
	_set_phase(Phase.CONNECTING)


## 失败后原路重试（保持「刚才是建房还是加入」）。
func _retry() -> void:
	if _want_host:
		_begin_host(room != null and room.skip_tunnel)
	else:
		_begin_join(room != null and room.skip_tunnel)


## 降级：不走内置内核，直接用 ENet 连（同一局域网 / 已知 IP）。
func _fallback_lan() -> void:
	_set_status(T.t("DDZ_ON_LAN_NOTE",
			"已切到局域网模式：同一 Wi-Fi 下可以直接连；跨网络则需要对方能直连的地址。"))
	if _want_host:
		_begin_host(true)
	else:
		_begin_join(true)


func _begin_match() -> void:
	if room == null:
		return
	# ⚠️ 种子的来源：房主给一个真随机的（客户端拿不到它 ⇒ 无法重算牌局）
	var seed_val := int(Time.get_unix_time_from_system() * 1000.0) & 0x7FFFFFFF
	if not room.start_game(seed_val):
		_set_status(T.t("DDZ_ON_START_FAIL", "开不了局（可能人不够）"))
		return
	_set_phase(Phase.PLAYING)
	visible = false
	match_started.emit()


func _dismiss() -> void:
	_close_room()
	_set_phase(Phase.CHOOSE)
	visible = false
	panel_closed.emit()


## 收起面板。★ 标题栏 ✕ 与牌桌的「← 返回」都走这里（两个入口一条路）。
##
## ⛔ 对局进行中**只收面板、不拆房间**：牌局在房主手里，点一下 ✕ 就把房间拆了
##    等于误伤整桌人。要真离开请用面板上的「离开房间」。
func hide_panel() -> void:
	if room != null and phase == Phase.PLAYING:
		visible = false
		return
	_dismiss()


func _close_room() -> void:
	if room != null:
		room.close()
		room.queue_free()
		room = null
	match_ended.emit()


# ══════════════════════════════════════════════════════════ 房间接线

func _ensure_room() -> void:
	if room != null:
		return
	room = ROOM.new()
	room.name = "DdzRoom"
	add_child(room)
	room.state_changed.connect(_on_room_state)
	room.join_requested.connect(_on_join_requested)
	room.failed.connect(_on_room_failed)
	room.log_line.connect(func(t: String): _set_status(t))


func _on_room_state() -> void:
	if room == null:
		return
	if room.state == ROOM.State.PLAYING and phase != Phase.PLAYING:
		# 房主开局 / 加入者被放行 —— 两种都从这里进对局
		if not room.is_host:
			_set_phase(Phase.PLAYING)
			visible = false
			match_started.emit()
	_refresh()


## 有人请求加入 —— 房主确认（产品规则 ③）。
func _on_join_requested(peer_id: int, player_name: String) -> void:
	_approve_lbl.text = T.t("DDZ_ON_REQ", "%s 请求加入：") % player_name
	for c in _approve_row.get_children():
		c.queue_free()
	_approve_row.add_child(_btn(T.t("DDZ_ON_ALLOW", "允许"), func():
		if room != null:
			room.approve(peer_id)
		_approve_lbl.text = ""
		_refresh(), true))
	_approve_row.add_child(_btn(T.t("DDZ_ON_DENY", "拒绝"), func():
		if room != null:
			room.decline(peer_id)
		_approve_lbl.text = ""
		_refresh()))
	_refresh()


func _on_room_failed(reason: String) -> void:
	_set_status(reason)
	# ★★ 对局进行中失败（典型：房主掉线）⇒ 必须让牌桌**干净退出联机模式**。
	#    否则牌桌会继续渲染那份「按我的座位裁好」的旧视图，而 `_my_seat()` 已经漂回 0
	#    ⇒ 手牌行去画房主的 `-1` 占位牌 ⇒ 屏幕上一排**白色的 3**（2026-10-12 真机踩过）。
	if phase == Phase.PLAYING:
		match_ended.emit()
		# ⚠️ `match_ended` 的接收方（牌桌）会顺手把面板隐藏 ⇒ 这里要**再显出来**，
		#    否则玩家看不到失败原因、也点不到「重试」。
		visible = true
	_set_phase(Phase.FAILED)


func _copy_code() -> void:
	if room == null or room.code == "":
		return
	DisplayServer.clipboard_set(room.code)
	_set_status(T.t("DDZ_ON_COPIED",
			"房间码 %s 已复制 —— 发给好友，他点「加入房间」粘进去") % RC.pretty(room.code))


# ══════════════════════════════════════════════════════════ 显示

func _set_phase(p: Phase) -> void:
	phase = p
	_refresh()


func _refresh() -> void:
	if _choose_row == null:      # ⚙️ 建完之前不能刷（`_refresh` 会在 `_build_contents` 之前被调到）
		return
	var hosting := phase == Phase.HOSTING
	var joining := phase == Phase.JOINING
	var conn := phase == Phase.CONNECTING
	_choose_row.visible = phase == Phase.CHOOSE
	_join_row.visible = joining or conn
	_perm_lbl.visible = phase == Phase.PERMISSION
	_perm_row.visible = phase == Phase.PERMISSION
	_code_lbl.visible = hosting
	_code_row.visible = hosting
	_players_lbl.visible = hosting
	_start_row.visible = hosting
	_fail_row.visible = phase == Phase.FAILED
	_close_row.visible = phase != Phase.CHOOSE
	# ⚠️ 空 Label 也占一行 ⇒ 没人请求加入时藏起来，否则「开始对局」和状态行之间
	#    永远挂着一段莫名其妙的空白
	if _approve_lbl != null:
		_approve_lbl.visible = _approve_lbl.text != ""
		_approve_row.visible = _approve_lbl.visible
	# 「开始对局」至少要有一个好友入座（否则就是三个人陪 AI —— 那叫单机）
	if _btn_start != null and room != null:
		var n := _joined_count()
		_btn_start.disabled = n < 1
		_btn_start.text = T.t("DDZ_ON_START", "开始对局") if n >= 1 \
				else T.t("DDZ_ON_WAIT", "等好友加入…")
	if _btn_close != null:
		_btn_close.text = T.t("DDZ_ON_LEAVE", "离开房间") if not hosting \
				else T.t("DDZ_ON_DISMISS", "解散房间")
	if hosting and room != null:
		_code_lbl.text = RC.pretty(room.code)
		_players_lbl.text = _players_text()
	_fit_height()


## 已入座人数（含房主自己）。
func _joined_count() -> int:
	if room == null or room.net == null:
		return 0
	var n := 1
	for s in range(1, N.SEATS):
		if int(room.net.seats[s]["peer"]) != N.NO_PEER:
			n += 1
	return n


func _players_text() -> String:
	var lines: Array[String] = []
	for s in N.SEATS:
		var who := String(room.net.seats[s]["name"])
		var seated := int(room.net.seats[s]["peer"]) != N.NO_PEER
		if s == 0:
			seated = true
		lines.append(("· %s%s" % [who, "" if seated else T.t("DDZ_ON_EMPTY", "（空位）")]))
	lines.append(T.t("DDZ_ON_PLAYERS_FMT", "已入座 %d / %d") % [_joined_count(), N.SEATS])
	return "\n".join(lines)


func _set_status(text: String) -> void:
	if _status_lbl != null:
		_status_lbl.text = text


func _fit_height() -> void:
	if content == null:
		return
	var need: Vector2 = content.get_combined_minimum_size()
	if need.x <= 0.0:
		return
	var limit := get_viewport_rect().size.y * 0.92
	if need.y > limit:
		return
	set_window_height(HEADER_H + need.y + 6.0 + 8.0 + 2.0)


## 摆到**屏幕正中**（牌桌会调它，与设置窗同一套路：子节点不受 `draw_set_transform`
## 影响 ⇒ 自己补偏移与缩放）。
##
## ★ 2026-10-18 用户：「安卓端…斗地主那个联机的页面太小了在手机上，挪到中间来，放大，
##   先放大两倍看看」⇒ 两处一起改：
##     ① 从「水平居中 + 贴顶 120px」改成**正居中**；
##     ② `PANEL_SCALE` 放大 —— ⚠️ 用节点 `scale` 而不是把 `PANEL_W/H` 直接乘 2：
##        后者只放大**外壳**，里面的字号 / 行高 / 按钮还是原尺寸
##        （800×720 的窗里塞 13px 字 = 一片空荡）；Control 的 `scale` 连
##        **内容一起**放大，输入命中判定也跟着缩放。
## ⚠️ 居中要按**可视区**算（`view_zoom`）：手机上牌桌整体有 `zoom`，可视区是
##    `1920×1080 × zoom`，只按 1920 算会让窗偏左上（`zoom > 1` 时偏差
##    `1920×(zoom-1)/2` —— 屏幕越宽偏得越多）。⛔ 但**缩放系数不乘 zoom**：
##    牌桌自己那套 zoom 是为了放大"桌面/顶栏"，窗另有 `panel_scale()`（按平台，
##    见 `SCALE_MOBILE / SCALE_DESKTOP`），两者不叠。
func place(origin: Vector2, view_zoom: float = 1.0) -> void:
	_place_origin = origin
	_place_zoom = view_zoom
	var sc := panel_scale()
	scale = Vector2(sc, sc)
	# ★★ 清掉"玩家拖过 / 存档记住"的旧矩形 —— 2026-10-18 实测踩到的坑：
	#   `EveWindow._effective_rect()` **优先**返回 `_user_rect`（玩家矩形/存档矩形），
	#   于是算好的居中位置被它**无声顶掉**（老存档里存着上一版「水平居中 + 贴顶 120px」）。
	#   ⇒ 本面板现在**始终**要居中，旧矩形一律作废（`reset_layout()` 还会清空存档）。
	#   ⚠️ 代价：这次进牌桌之前的拖动不再恢复 —— 定位改成"固定居中"之后，
	#      恢复一个旧位置本来就是反的。
	reset_layout()
	# 触发一次 `_apply_rect()`，由它完成居中（见下面的重写）
	set_window_rect(origin.x, origin.y, PANEL_W, maxf(1.0, size.y))


## ══════════════════════════════════════════════════════════════
##  **居中：挂在唯一的尺寸漏斗上**
## ══════════════════════════════════════════════════════════════
## ★★ 为什么重写 `_apply_rect()` 而不是在 `place()` / `set_window_height()` 各调一次：
##   基类里**任何**尺寸/位置变化（阶段换内容 `_fit_height()`、折叠、HUD 重铺）最后都
##    汇到 `_apply_rect()`（见它自己的注释）。挂在两个点上必漏 —— 2026-10-18 三次出图
##    实测就是这个结果：三张图**顶边一样高、只有高度在往下长**，越换阶段越偏下。
##
## ⚠️ 收起态**不居中**：那时窗变成贴边的一条标签，位置归 `dock_rect` 管。
## ⚠️ 直接写 `position`（⛔ 不再调 `set_window_rect()`）：那会再触发一次 `_apply_rect()`，
##    自我递归。`position` 就是节点的左上角，而 `scale` 的轴心默认在左上 ⇒ 直接把左上
##    角摆到「中心 − 可视尺寸的一半」即可。
func _apply_rect(r: Rect2) -> void:
	super(r)
	if _collapsed:
		return
	var view := Vector2(BASE_W, BASE_H) * _place_zoom
	var vis := Vector2(size.x, size.y) * panel_scale()
	position = Vector2(_place_origin.x + (view.x - vis.x) * 0.5,
			_place_origin.y + (view.y - vis.y) * 0.5)


## 面板落点（`place()` 记下来，供每次尺寸变化后重新居中用）。
var _place_origin := Vector2.ZERO
var _place_zoom := 1.0

## ⚠️ 2026-10-18 补：原来只有 `BASE_W`（当初只做水平居中），现在要正居中 ⇒ 高度也得有。
const BASE_H := 1080.0


# ══════════════════════════════════════════════════════════ 小工具

const BASE_W := 1920.0

func _player_name() -> String:
	var n := _name_edit.text.strip_edges()
	if n == "":
		n = DEFAULT_NAME
	_name_edit.text = n
	return n


func _save_name() -> void:
	STORE.save_one("ddz_name", _player_name())


## 头像字节落盘位置（独立二进制文件，不污染 settings.cfg）。
const AVATAR_PATH := "user://ddz_avatar.png"


## 进面板时把上次选的头像缩略图读出来。
func _load_saved_avatar() -> void:
	if not FileAccess.file_exists(AVATAR_PATH):
		return
	var f := FileAccess.open(AVATAR_PATH, FileAccess.READ)
	if f == null:
		return
	_avatar_bytes = f.get_buffer(f.get_length())
	f.close()
	if not _avatar_bytes.is_empty() and _avatar_rect != null:
		_avatar_rect.texture = ROOM.bytes_to_texture(_avatar_bytes)


## 弹出系统文件选择器。
func _on_pick_avatar() -> void:
	if _avatar_dialog != null:
		_avatar_dialog.popup_centered_ratio(0.7)


## 选中图片 ⇒ 压到最大边 96px、转 PNG 存盘，并把缩略图刷出来。
func _on_avatar_file_selected(path: String) -> void:
	var img := Image.new()
	if img.load(path) != OK:
		_set_status(T.t("DDZ_ON_AVATAR_FAIL", "读不到这张图片（可能格式不支持）"))
		return
	_avatar_bytes = _encode_avatar(img)
	if _avatar_bytes.is_empty():
		return
	var f := FileAccess.open(AVATAR_PATH, FileAccess.WRITE)
	if f != null:
		f.store_buffer(_avatar_bytes)
		f.close()
	_avatar_rect.texture = ROOM.bytes_to_texture(_avatar_bytes)
	_set_status(T.t("DDZ_ON_AVATAR_OK", "头像已更新：进房时同步给好友"))


## 清掉本地头像（进房时就不带了）。
func _clear_avatar() -> void:
	_avatar_bytes = PackedByteArray()
	if FileAccess.file_exists(AVATAR_PATH):
		DirAccess.remove_absolute(AVATAR_PATH)
	_avatar_rect.texture = null
	_set_status(T.t("DDZ_ON_AVATAR_CLEARED", "已清除本地头像"))


## 把任意图片压成「最大边 ≤ 96px」的 PNG 字节（单张远小于 64KB 的线网上限）。
func _encode_avatar(img: Image) -> PackedByteArray:
	var maxd := 96
	var w := img.get_width()
	var h := img.get_height()
	if w <= 0 or h <= 0:
		return PackedByteArray()
	var sc := mini(float(maxd) / float(w), float(maxd) / float(h))
	sc = mini(sc, 1.0)
	var nw := maxi(1, int(round(w * sc)))
	var nh := maxi(1, int(round(h * sc)))
	img.resize(nw, nh, Image.INTERPOLATE_LANCZOS)
	return img.save_png_to_buffer()


func _lab(text: String, col: Color, size: int, min_w: float) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if min_w > 0.0:
		l.custom_minimum_size.x = min_w
	return l


func _mk_row() -> HBoxContainer:
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", 6)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


func _btn(text: String, cb: Callable, primary := false) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 26)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", 13)
	b.pressed.connect(cb)
	BTN.apply(b, "hud_main" if primary else "hud")
	return b


func _edit(max_len: int) -> LineEdit:
	var e := LineEdit.new()
	e.max_length = max_len
	e.custom_minimum_size = Vector2(0, 26)
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	e.add_theme_font_size_override("font_size", 14)
	e.add_theme_color_override("font_color", C_TEXT)
	e.add_theme_color_override("font_placeholder_color", C_TEXT_FAINT)
	e.add_theme_color_override("caret_color", C_ACCENT)
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.03, 0.045, 0.055, 0.9)
	box.border_color = C_BORDER
	box.set_border_width_all(1)
	box.content_margin_left = 6.0
	box.content_margin_right = 6.0
	e.add_theme_stylebox_override("normal", box)
	e.add_theme_stylebox_override("focus", box)
	return e
