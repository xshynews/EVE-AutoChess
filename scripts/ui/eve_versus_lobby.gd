extends Control

## 联机对战 · 房间（魔兽3 那种座位表）。
##
## 用户口径（2026-10-27）：「一个人创建了房间…连不上人就可以添加电脑 AI 对手」
## ⇒ 人机 = 补空位，不是独立玩法。
##
## 视觉：沿用主菜单那套 —— 同一张底图 + 暗化蒙版 + 描边卡片 +
##       C_ACCENT 标题 / C_DIM 说明 / C_GOLD 标示电脑位。
## ⛔ 别再退回「一团黑的 ColorRect 底」：那和整体风格是割裂的。

const TR := preload("res://scripts/net/eve_versus_transport.gd")
const NET := preload("res://scripts/net/eve_versus_net.gd")
const RUN_STORE := preload("res://scripts/core/eve_run_store.gd")
const BATTLE_SCENE := "res://scenes/battle_scene.tscn"
const MENU_SCENE := "res://scenes/main_menu.tscn"
const MENU_BG := preload("res://assets/backgrounds/caldari-c07-menu-1920x1080.png")
const TUNNEL := preload("res://scripts/net/eve_tunnel.gd")
const RELAYS := preload("res://scripts/net/eve_relay_list.gd")
const RC := preload("res://scripts/net/eve_room_code.gd")
## ★ 2026-10-28 零门槛：中继地址**内置**，玩家不填、不勾、不看 IP。
const NETCFG := preload("res://scripts/net/eve_net_config.gd")

const C_TEXT := Color(0.70, 0.82, 0.85)
const C_TEXT_HI := Color(0.91, 0.96, 0.97)
const C_DIM := Color(0.44, 0.55, 0.59)
const C_ACCENT := Color(0.55, 0.78, 0.82)
const C_ACCENT_HI := Color(0.84, 0.95, 0.97)
const C_GOLD := Color(0.91, 0.76, 0.35)
const C_CARD := Color(0.045, 0.062, 0.078, 0.92)
const C_BORDER := Color(0.42, 0.55, 0.60, 0.34)
const C_SEP := Color(0.42, 0.55, 0.60, 0.24)

const PORT := 37015
const MAX_SEATS := 4

var tr = null
var net = null
var is_host := false
var ready_to_go := false
var _joined_sent := false
## --autostart <秒>：到点自动点「开始对战」（无头/自动化验收用）
var _autostart_at := -1
var _autostart_sec := 0
## 跨网隧道（EasyTier）。null = 没开。
var _tunnel = null
var _tunnel_mode := false
var _code := ""
var _lan_only: CheckBox = null
## 隧道就绪后要立刻进战场（加入方不等房主的开始信号 ——
## 隧道里没有房间通道，双方直接进战场用 ENet 重新握手）。
var _pending_battle := false
var _tunnel_up := false
var _my_seat := 0

## slots[i] = {"kind": "human"|"ai"|"empty", "name": String, "peer": int}
var slots: Array = []

var _status: Label = null
var _addr: LineEdit = null
var _slot_box: VBoxContainer = null
var _start_btn: Button = null
## 房间码行（跨网建房时显形）：大字号码 + 一键复制。
## ★ 2026-10-28 用户：「联机界面需要一个复制房间码的快捷方式，方便大家分享房间码」。
var _code_row: HBoxContainer = null
var _code_lbl: Label = null
var _copy_btn: Button = null
## ★ 2026-10-28 中转模式：手机也能建房（不需要 TUN）。两端都连一台公网 UDP 中继。
##   ⚠️ 2026-10-28 二改（用户：「只装一次，联网尽量没有门槛」）：
##      取消勾选框 ⇒ **默认就走中继**，地址取 `EveNetConfig`（内置/上次保存）。
##      玩家界面上唯一的输入 = 房间码。
var _relay_addr: LineEdit = null
var _relay_mode := false


func _ready() -> void:
	net = NET.new()
	tr = TR.new()
	add_child(tr)
	tr.set_process(false)
	net.attach_transport(tr)
	_init_slots()
	_build_ui()
	_parse_args()


func _init_slots() -> void:
	slots = []
	for i in MAX_SEATS:
		slots.append({"kind": "empty", "name": "空位", "peer": -1})
	slots[0] = {"kind": "human", "name": "你", "peer": 1}


func _parse_args() -> void:
	# 先把所有参数收完再执行 —— 原来每个分支里 return，导致
	# `--host --ai 1 --autostart 12` 只处理了第一个（实测自动开始不触发）。
	var args := OS.get_cmdline_user_args()
	var want_host := false
	var join_addr := ""
	var ai_n := 0
	var forced_code := ""
	var force_lan := false
	for i in args.size():
		if args[i] == "--host":
			want_host = true
		elif args[i] == "--join" and i + 1 < args.size():
			join_addr = String(args[i + 1])
		elif args[i] == "--ai" and i + 1 < args.size():
			ai_n = int(args[i + 1])
		elif args[i] == "--autostart" and i + 1 < args.size():
			_autostart_sec = int(args[i + 1])
		elif args[i].begins_with("--code="):
			forced_code = String(args[i]).substr(7)
		elif args[i] == "--lan":
			force_lan = true
	if force_lan and _lan_only != null:
		_lan_only.button_pressed = true
	if forced_code != "":
		_addr.text = forced_code
	if want_host:
		_do_host()
	elif join_addr != "":
		_addr.text = join_addr
		_do_join()
	for k in ai_n:
		_add_ai()

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# ① 底图（和主菜单同一张，KEEP_ASPECT_COVERED 铺满）
	var bg := TextureRect.new()
	bg.texture = MENU_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	add_child(bg)
	# ② 暗化蒙版：底图本身很亮，不压暗文字读不出来
	var veil := ColorRect.new()
	veil.color = Color(0.02, 0.035, 0.05, 0.62)
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(veil)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	# ③ 卡片：描边 + 半透明深底（同主菜单卡片口径）
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(680, 0)
	card.add_theme_stylebox_override("panel", _card_box())
	center.add_child(card)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	box.custom_minimum_size = Vector2(620, 0)
	card.add_child(box)

	box.add_child(_label("联机对战 · 房间", 26, C_ACCENT_HI, HORIZONTAL_ALIGNMENT_CENTER))
	box.add_child(_label("一个人建房、等人；人不够就点空位上的「加电脑」补上，然后开始。",
		13, C_DIM, HORIZONTAL_ALIGNMENT_CENTER, true))
	box.add_child(_hair())

	# ④ 建房 / 加入
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	row.add_child(_mk_btn("创建房间", _do_host, 118))
	_addr = LineEdit.new()
	# ★ 2026-10-28 零门槛：默认**空**（不再预填 IP:端口）。
	#   建房 ⇒ 留空即随机生成房间码；加入 ⇒ 只填 8 位房间码。
	_addr.text = ""
	_addr.placeholder_text = "房间码（例如 K7QM-3X9D）"
	_addr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_addr.custom_minimum_size = Vector2(230, 34)
	_addr.add_theme_color_override("font_color", C_TEXT)
	_addr.add_theme_color_override("font_placeholder_color", C_DIM)
	_addr.add_theme_stylebox_override("normal", _edit_box(false))
	_addr.add_theme_stylebox_override("focus", _edit_box(true))
	row.add_child(_addr)
	row.add_child(_mk_btn("加入房间", _do_join, 118))

	# ④b 房间码（只有跨网建房才有）：码本身体面地显示出来，右侧一键复制。
	#     ⚠️ 建房前/局域网模式整行隐藏 —— 局域网没有房间码（填 IP:端口）。
	#     为什么要单独一行而不是只写在状态文字里：状态那一行随时会被
	#     「隧道建立中 / 有真人加入」覆盖，玩家想抄码的时候正好被冲掉。
	_code_row = HBoxContainer.new()
	_code_row.add_theme_constant_override("separation", 10)
	_code_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_code_row.visible = false
	box.add_child(_code_row)
	_code_row.add_child(_label("房间码", 13, C_DIM))
	_code_lbl = _label("", 22, C_GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	_code_lbl.custom_minimum_size = Vector2(190, 0)
	# ★ 号码本身也能点（用户 2026-10-28：「可以」）——
	#   玩家下意识会去点号码，而不是先找按钮；给一个手形光标 + 悬停变亮。
	#   ⚠️ `_label()` 默认 `mouse_filter = IGNORE`（不接任何输入），这里必须改回 STOP，
	#      否则 `gui_input` 一次都不会来。
	_code_lbl.mouse_filter = Control.MOUSE_FILTER_STOP
	_code_lbl.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_code_lbl.tooltip_text = "点击复制房间码"
	_code_lbl.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed \
				and ev.button_index == MOUSE_BUTTON_LEFT:
			_copy_code())
	_code_lbl.mouse_entered.connect(func():
		_code_lbl.add_theme_color_override("font_color", C_ACCENT_HI))
	_code_lbl.mouse_exited.connect(func():
		_code_lbl.add_theme_color_override("font_color", C_GOLD))
	_code_row.add_child(_code_lbl)
	_copy_btn = _mk_btn("复制房间码", _copy_code, 120)
	_code_row.add_child(_copy_btn)

	# 默认走中继（玩家只用房间码）；同局域网调试时才勾这个走直连 TCP。
	# ★ 2026-10-28：**已内置服务器时整行隐藏** —— 玩家不该看见任何网络选项。
	var has_builtin := NETCFG.relay_text() != ""
	_lan_only = CheckBox.new()
	_lan_only.text = "同一局域网直连（调试用，填房主 IP:端口）"
	_lan_only.visible = not has_builtin
	_lan_only.add_theme_font_size_override("font_size", 13)
	_lan_only.mouse_filter = Control.MOUSE_FILTER_STOP
	box.add_child(_lan_only)

	# ★ 2026-10-28 二改：**取消「中转模式」勾选框**。
	#   有内置地址 ⇒ 建房/加入默认就走中继，玩家不需要知道「模式」这回事；
	#   没内置地址（BUILTIN 空且没写过 net.cfg）⇒ 自动回退 EasyTier 隧道。
	#   ⚠️ 服务器这一行只为**排错/作者换服**保留：玩家不改也能正常玩。
	var relay_row := HBoxContainer.new()
	relay_row.add_theme_constant_override("separation", 8)
	relay_row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(relay_row)
	relay_row.add_child(_label("服务器", 12, C_DIM))
	_relay_addr = LineEdit.new()
	# 有内置地址 ⇒ 预填内置；没有 ⇒ 预填本机起点（作者在本机起中继即可跑通）。
	# ⚠️ 清空这一格 = 放弃中继、回退 EasyTier 隧道（只是作者的备用路径）。
	var builtin_text := NETCFG.relay_text()
	_relay_addr.text = builtin_text if builtin_text != "" else NETCFG.LOCAL_FALLBACK
	_relay_addr.custom_minimum_size = Vector2(240, 28)
	_relay_addr.add_theme_font_size_override("font_size", 12)
	_relay_addr.add_theme_color_override("font_color", C_TEXT)
	_relay_addr.add_theme_color_override("font_placeholder_color", C_DIM)
	_relay_addr.add_theme_stylebox_override("normal", _edit_box(false))
	_relay_addr.add_theme_stylebox_override("focus", _edit_box(true))
	relay_row.add_child(_relay_addr)
	relay_row.add_child(_label("内置 · 一般不用改", 11, C_DIM))
	# ★ 2026-10-28：**有内置服务器时整行隐藏**（玩家零配置，连"服务器"这回事都看不到）。
	relay_row.visible = not has_builtin

	_status = Label.new()
	_status.text = "「创建房间」→ 把房间码发给朋友；朋友填码点「加入房间」。"
	_status.add_theme_font_size_override("font_size", 14)
	_status.add_theme_color_override("font_color", C_ACCENT)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_status)

	box.add_child(_hair())
	# ⑤ 座位表
	box.add_child(_label("座位　SLOTS", 10, Color(0.73, 0.83, 0.87, 0.9)))
	_slot_box = VBoxContainer.new()
	_slot_box.add_theme_constant_override("separation", 6)
	box.add_child(_slot_box)
	box.add_child(_hair())

	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 10)
	row2.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(row2)
	_start_btn = _mk_btn("开始对战", _do_start, 140)
	row2.add_child(_start_btn)
	row2.add_child(_mk_btn("返回主菜单", _do_back, 130))
	_refresh_slots()


func _label(text: String, size: int, col: Color, align: int = 0, wrap: bool = false) -> Label:
	var lb := Label.new()
	lb.text = text
	lb.add_theme_font_size_override("font_size", size)
	lb.add_theme_color_override("font_color", col)
	lb.horizontal_alignment = align
	if wrap:
		lb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return lb


func _card_box() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = C_CARD
	sb.border_color = C_BORDER
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 26
	sb.content_margin_right = 26
	sb.content_margin_top = 22
	sb.content_margin_bottom = 22
	return sb


func _edit_box(focus: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.03, 0.04, 0.85)
	sb.border_color = C_ACCENT if focus else C_BORDER
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	return sb


func _hair() -> Control:
	var r := ColorRect.new()
	r.color = C_SEP
	r.custom_minimum_size = Vector2(0, 1)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


func _btn_box(bg: Color, border: Color, hot: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	if hot:
		sb.bg_color = Color(0.07, 0.11, 0.13, 0.95)
	return sb


func _mk_btn(text: String, cb: Callable, w: int = 110) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(w, 32)
	b.add_theme_font_size_override("font_size", 14)
	b.add_theme_color_override("font_color", C_TEXT_HI)
	b.add_theme_color_override("font_hover_color", C_ACCENT_HI)
	b.add_theme_color_override("font_disabled_color", C_DIM)
	b.add_theme_stylebox_override("normal", _btn_box(Color(0.039, 0.055, 0.067, 0.66), C_BORDER, false))
	b.add_theme_stylebox_override("hover", _btn_box(Color(0.07, 0.11, 0.13, 0.9), C_ACCENT, true))
	b.add_theme_stylebox_override("pressed", _btn_box(Color(0.10, 0.15, 0.18, 0.95), C_ACCENT_HI, true))
	b.add_theme_stylebox_override("disabled", _btn_box(Color(0.03, 0.04, 0.05, 0.5), C_BORDER, false))
	b.pressed.connect(cb)
	return b


# ══════════════════════════════════════════════════════════ 逻辑

func _add_ai() -> void:
	if not is_host:
		return
	for i in slots.size():
		if String(slots[i]["kind"]) == "empty":
			slots[i] = {"kind": "ai", "name": "电脑 %d" % (i + 1), "peer": -1}
			_refresh_slots()
			return
	_set_status("座位已满")


func _remove_ai(idx: int) -> void:
	if not is_host or idx <= 0 or idx >= slots.size():
		return
	if String(slots[idx]["kind"]) != "ai":
		return
	slots[idx] = {"kind": "empty", "name": "空位", "peer": -1}
	_refresh_slots()


func _do_host() -> void:
	if is_host:
		return
	# ── 中转模式：不建隧道、不建虚拟网卡，只生成房间码（手机上唯一的建房方式）──
	if _relay_on():
		_relay_mode = true
		_tunnel_mode = false
		_code = RC.normalize(_addr.text.strip_edges())
		if not RC.is_valid(_code):
			_code = RC.generate()
		is_host = true
		net.host_setup(["你", "空位", "空位", "空位"], 1)
		if _autostart_sec > 0:
			_autostart_at = Time.get_ticks_msec() + _autostart_sec * 1000
		_set_status("房间已建 · 房间码 %s · 把它发给朋友，等对方进来" % RC.pretty(_code))
		_show_code_row()
		_refresh_slots()
		return
	# ── 同局域网：直连 TCP（调试用）──
	if _lan_only != null and _lan_only.button_pressed:
		var ok0: bool = tr.host_start(PORT)
		if not ok0:
			_set_status("建房失败：" + tr.last_error)
			return
		is_host = true
		_tunnel_mode = false
		net.host_setup(["你", "空位", "空位", "空位"], 1)
		if _autostart_sec > 0:
			_autostart_at = Time.get_ticks_msec() + _autostart_sec * 1000
		_set_status("局域网房间已建（端口 %d）· 对方填 <你的IP>:%d" % [PORT, PORT])
		_refresh_slots()
		return
	# ── 跨网：EasyTier 隧道。房主要建虚拟网卡 ⇒ 需要一次管理员权限 ──
	# 验收/复现用：--code=XXXX 固定房间码；否则随机生成。
	_code = RC.normalize(_addr.text.strip_edges()) if (_addr != null and RC.is_valid(RC.normalize(_addr.text.strip_edges()))) else RC.generate()
	_tunnel = TUNNEL.new()
	var ok: bool = _tunnel.start(_code, 0, true, RELAYS.peers(), "房主",
			Time.get_ticks_msec())
	if not ok:
		_set_status("建隧道失败：" + String(_tunnel.last_error))
		return
	is_host = true
	_tunnel_mode = true
	net.host_setup(["你", "空位", "空位", "空位"], 1)
	if _autostart_sec > 0:
		_autostart_at = Time.get_ticks_msec() + _autostart_sec * 1000
	_set_status("正在建隧道… 房间码：" + RC.pretty(_code) + "（首次会弹管理员授权）")
	_show_code_row()
	_refresh_slots()


func _do_join() -> void:
	if is_host:
		return
	# ── 中转模式：输入框当房间码，直接进战场（在战场里等房主的 START）──
	if _relay_on():
		var rc := RC.normalize(_addr.text.strip_edges())
		if not RC.is_valid(rc):
			_set_status("房间码不对（应是 8 位字母数字，例如 %s）" % RC.pretty(RC.generate()))
			return
		_code = rc
		_relay_mode = true
		_tunnel_mode = false
		net.client_setup(0, "玩家")
		_set_status("正在加入 %s · 等房主点开始" % RC.pretty(_code))
		_my_seat = 1
		_go_battle("join")
		return
	var raw := _addr.text.strip_edges()
	var lan := (_lan_only != null and _lan_only.button_pressed) or raw.contains(":") or raw.contains(".")
	if lan:
		var ip := raw
		var port := PORT
		var c := raw.rfind(":")
		if c > 0:
			ip = raw.substr(0, c)
			port = int(raw.substr(c + 1))
		if ip == "":
			_set_status("填房主地址，例如 192.168.1.10:%d" % PORT)
			return
		var ok2: bool = tr.join(ip, port, Time.get_ticks_msec())
		if not ok2:
			_set_status("连接失败：" + tr.last_error)
			return
		_tunnel_mode = false
		net.client_setup(0, "玩家")
		_set_status("连接中… " + ip + ":" + str(port))
		return
	# ── 跨网：把输入框当房间码 ──
	var code := RC.normalize(raw)
	if not RC.is_valid(code):
		_set_status("房间码不对（示例：%s）；同一局域网的话勾上上面那个选项再填 IP:端口" % RC.pretty(RC.generate()))
		return
	_code = code
	_tunnel = TUNNEL.new()
	var ok3: bool = _tunnel.start(_code, 1, false, RELAYS.peers(), "玩家",
			Time.get_ticks_msec())
	if not ok3:
		_set_status("加入隧道失败：" + String(_tunnel.last_error))
		return
	_tunnel_mode = true
	net.client_setup(0, "玩家")
	_set_status("正在连隧道… 房间码 " + RC.pretty(_code))


func _do_start() -> void:
	if not is_host:
		return
	# 中转模式：没有「隧道连通」这道门槛 —— 房主进战场后自己起 ENet，再等对端
	if _relay_mode:
		_my_seat = 0
		_go_battle("host")
		return
	# 隧道模式没有大厅通道（房间握手在战场里用 ENet 做），直接进战场。
	if _tunnel_mode:
		if not _tunnel_up:
			_set_status("隧道还没连通，稍等…")
			return
		_go_battle("host")
		return
	var ai_n := 0
	for s in slots:
		if String(s["kind"]) == "ai":
			ai_n += 1
	if ai_n == 0 and _human_count() <= 1:
		_set_status("至少要有一个对手：给空位加电脑，或等别人加入")
		return
	# 把座位表一起发出去：双方必须用**同一张表**建局，否则配对/血量对不上。
	net.host_broadcast_net(NET.Kind.ROUND, {"round": 0, "kind": 0, "time": 0.0,
			"start": 1, "slots": slots.duplicate(true)})
	_my_seat = 0
	_go_battle("host")


func _human_count() -> int:
	var n := 0
	for s in slots:
		if String(s["kind"]) == "human":
			n += 1
	return n


## 是否走中继。★ 2026-10-28 二改：**默认就是中继**（不再需要勾选）。
##
## 例外只有两个：
##   · 勾了「同一局域网」⇒ 走直连 TCP（作者调试用）；
##   · 地址框和内置都空（既没打包 net.cfg 也没填）⇒ 回退 EasyTier 隧道。
func _relay_on() -> bool:
	if _lan_only != null and _lan_only.button_pressed:
		return false
	return NETCFG.parse(_relay_text()).size() > 0


## 中继服务器地址文本（默认取内置；玩家一般不动）。
## ⚠️ 清空 = 明确回退 EasyTier 隧道，这里**不再**兜底回填。
func _relay_text() -> String:
	return _relay_addr.text.strip_edges() if _relay_addr != null else ""


func _go_battle(role: String) -> void:
	if ready_to_go:
		return
	ready_to_go = true
	RUN_STORE.pending_versus_role = role
	RUN_STORE.pending_versus_addr = _addr.text.strip_edges()
	RUN_STORE.pending_versus_port = PORT
	RUN_STORE.pending_versus_seats = slots.size()
	RUN_STORE.pending_versus_slots = slots.duplicate(true)
	RUN_STORE.pending_versus_ai = 0
	RUN_STORE.pending_versus_my_seat = _my_seat
	# ★ 2026-10-28 中转参数：把「中转服务器 + 房间码」带进战场。
	#   ★ 2026-10-28 二改：拆地址统一走 `EveNetConfig.parse`（支持 `[IPv6]:端口`）。
	var rpkt := NETCFG.parse(_relay_text())
	var rh := String(rpkt.get("host", "127.0.0.1"))
	var rp := int(rpkt.get("port", 27100))
	# ★ 作者改过服务器地址 ⇒ 记到 `user://net.cfg`，下次打开自动带出来（只配一次）。
	if _relay_addr != null:
		var typed := _relay_addr.text.strip_edges()
		if typed != "" and typed != NETCFG.relay_text():
			NETCFG.save_override(typed)
	RUN_STORE.pending_versus_relay = _relay_mode
	RUN_STORE.pending_versus_relay_host = rh
	RUN_STORE.pending_versus_relay_port = rp
	# 跨网标记：战场据此改用 ENet(UDP 27015) —— 隧道的 port-forward 只开这一个口子。
	RUN_STORE.pending_versus_tunnel = _tunnel_mode
	RUN_STORE.pending_versus_code = _code
	# ★ 2026-10-28 房主权威：**开赛的判定搬到了战场里**（两条路都一样）——
	#   房主等对端 ENet 连上后广播 START，加入方收到 START 才开第 1 回合；
	#   ⛔ 大厅这里不再决定「谁什么时候进战场」之外的事。
	RUN_STORE.session_active = true
	get_tree().change_scene_to_file(BATTLE_SCENE)


## ── AI 桥（截图 / 状态 / 以后外部操作都用得上）──
func ai_kind() -> String:
	return "versus_lobby"


func ai_snapshot() -> Dictionary:
	var out: Array = []
	for sl in slots:
		out.append({"kind": String(sl["kind"]), "name": String(sl["name"])})
	return {
		"scene": "versus_lobby",
		"is_host": is_host,
		"slots": out,
		"status": String(_status.text) if _status != null else "",
		"can_start": (_start_btn != null and _start_btn.visible and not _start_btn.disabled),
	}


func _do_back() -> void:
	if _tunnel != null:
		_tunnel.stop()
		_tunnel = null
	if tr != null:
		tr.stop()
	get_tree().change_scene_to_file(MENU_SCENE)


func _set_status(s: String) -> void:
	if _status != null:
		_status.text = s
	print("[room] " + s)


## 显形房间码行（跨网建房成功后调一次；局域网模式保持隐藏）。
func _show_code_row() -> void:
	if _code_row == null:
		return
	var on := is_host and _code != ""
	_code_row.visible = on
	if on and _code_lbl != null:
		_code_lbl.text = RC.pretty(_code)


## 复制房间码到系统剪贴板（好友在「加入房间」里粘贴即可）。
##
## ★ 2026-10-28 用户：「联机界面需要一个复制房间码的快捷方式，方便大家分享房间码」。
## ⚠️ 复制的是**带连字符的排版串**（`K7QM-3X9D`）：`RC.normalize()` 会剔掉
##    连字符/空格，粘进来照样能用；而带分隔的码在聊天软件里更好读、不易抄错。
func _copy_code() -> void:
	if _code == "":
		_set_status("还没有房间码：先点「创建房间」")
		return
	var text := RC.pretty(_code)
	DisplayServer.clipboard_set(text)
	_set_status("房间码 %s 已复制 —— 发给好友，他在「加入房间」里粘进去" % text)
	# 按钮上也给一次可见反馈：状态文字在卡片下方，玩家常常注意不到
	if _copy_btn == null:
		return
	var btn := _copy_btn
	btn.text = "已复制"
	await get_tree().create_timer(1.4).timeout
	if is_instance_valid(btn):
		btn.text = "复制房间码"


## Ctrl+C 快捷复制（房间码行可见时）。
##
## ⚠️ 输入框有焦点时 Ctrl+C 归 LineEdit 自己（复制地址文本），
##    事件根本走不到这里 —— 不需要自己判断焦点。
func _unhandled_key_input(e: InputEvent) -> void:
	if _code == "" or _code_row == null or not _code_row.visible:
		return
	var k := e as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	if k.ctrl_pressed and k.keycode == KEY_C:
		_copy_code()


## 座位行：左侧竖色条标示身份（你=青 / 真人=青亮 / 电脑=金 / 空位=灰）。
func _refresh_slots() -> void:
	if _slot_box == null:
		return
	for ch in _slot_box.get_children():
		ch.queue_free()
	for i in slots.size():
		var sl: Dictionary = slots[i]
		var kind := String(sl["kind"])
		var mark := C_DIM
		var tag := "空位"
		if i == 0:
			mark = C_ACCENT_HI
			tag = "你"
		elif kind == "ai":
			mark = C_GOLD
			tag = "电脑"
		elif kind == "human":
			mark = C_ACCENT
			tag = "真人"

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var bar := ColorRect.new()
		bar.color = mark
		bar.custom_minimum_size = Vector2(3, 26)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(bar)
		var no := _label("%d" % (i + 1), 13, C_DIM)
		no.custom_minimum_size = Vector2(16, 0)
		row.add_child(no)
		var nm := _label(String(sl["name"]), 15, C_TEXT_HI if kind != "empty" else C_DIM)
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(nm)
		row.add_child(_label(tag, 12, mark))
		if is_host and i > 0:
			if kind == "empty":
				row.add_child(_mk_btn("加电脑", func(): _add_ai(), 86))
			elif kind == "ai":
				row.add_child(_mk_btn("移除", func(): _remove_ai(i), 66))
		_slot_box.add_child(row)
	if _start_btn != null:
		_start_btn.visible = is_host


func _process(_d: float) -> void:
	# ── 隧道状态机（比网络通道优先，因为它是进入战场的前提）──
	if _tunnel != null:
		_tunnel.poll(Time.get_ticks_msec())
		var st := int(_tunnel.state)
		if st == 3:
			_set_status("隧道失败：" + String(_tunnel.last_error))
			_tunnel = null
			_tunnel_mode = false
		elif st == 2 and not _tunnel_up:
			_tunnel_up = true
			if is_host:
				_set_status("隧道已连通 · 房间码 %s · 点「开始对战」" % RC.pretty(_code))
			else:
				_set_status("隧道已连通 · 正在进入战场…")
				_pending_battle = true
	if _pending_battle and not ready_to_go:
		_pending_battle = false
		_go_battle("join")
	if tr == null:
		return
	tr.poll()
	tr.check_timeout(Time.get_ticks_msec())
	if is_host and _autostart_at > 0 and Time.get_ticks_msec() >= _autostart_at:
		_autostart_at = -1
		print("[room] 自动开始")
		_do_start()
	for msg in net.drain():
		var d: Dictionary = msg["d"]
		var from := int(msg["from"])
		var kind := int(d.get("kind", -1))
		if is_host:
			var r: Dictionary = net.apply_remote(from, d)
			if bool(r.get("ok", false)) and kind == NET.Kind.HELLO:
				var seat := int(r["result"].get("seat", -1))
				for i in slots.size():
					if String(slots[i]["kind"]) == "empty":
						slots[i] = {"kind": "human", "name": "玩家 %d" % (i + 1), "peer": from}
						break
				net.host_send(from, NET.Kind.WELCOME, {"seats": net.seats.duplicate(true)})
				_set_status("有真人加入（%d 号座）" % (seat + 1))
				_refresh_slots()
		else:
			if kind == NET.Kind.WELCOME:
				_set_status("已进房间 · 等房主开始")
			elif kind == NET.Kind.ROUND and int(d.get("start", 0)) == 1:
				_set_status("房主开始")
				# 客户端用房主发来的座位表建局（含自己占的是哪一位）。
				var srv_slots: Array = d.get("slots", [])
				if not srv_slots.is_empty():
					slots = srv_slots.duplicate(true)
				for i in slots.size():
					if int(slots[i].get("peer", -1)) == int(tr.my_id):
						_my_seat = i
						break
				_go_battle("join")
	if not is_host and not _joined_sent and tr.my_id != 1:
		_joined_sent = true
		net.client_join("玩家")
