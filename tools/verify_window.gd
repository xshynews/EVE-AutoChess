extends Node
## 浮窗「收起 / 展开 / 布局记忆」自检（★ 2026-10-07）
##
## ⚠️ 为什么单独一套：`EveWindow` 是所有浮窗的基类（11 扇窗），
##    它的三类 bug —— **收起被 HUD 刷新顶掉 / 拖动结果被抹掉 / 尺寸记不住** ——
##    全都是「不报错的静默错」，只靠跑一遍没崩永远查不出来。

const W := preload("res://scripts/ui/eve_window.gd")
const LAYOUT_STORE := preload("res://scripts/ui/eve_window_store.gd")

const HEADER_H := 26.0

var _pass := 0
var _fail := 0


func _ok(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
		print("  ✓ " + msg)
	else:
		_fail += 1
		print("  ✗ " + msg)


func _ready() -> void:
	LAYOUT_STORE.persist = false          # ⛔ 别写盘污染玩家的真实窗口布局
	print("═══ 浮窗收起 / 布局记忆 自检 ═══")
	_t_basic()
	_t_refresh_not_undo()
	_t_click_channels()
	_t_height_sync()
	_t_persist()
	_t_closable()
	print("═══ RESULT passed=%d failed=%d ═══" % [_pass, _fail])
	# ★ 2026-10-10（审查 R07）：失败 ⇒ 非零退出码
	get_tree().quit(1 if _fail > 0 else 0)


func _mk_win(title: String, persist := false) -> Control:
	var host := Control.new()
	host.size = Vector2(1920, 1080)
	add_child(host)
	var w: Control = W.new()
	w.set("window_title", title)
	w.set("persist_layout", persist)
	host.add_child(w)
	return w


## 同上，但能**在 `add_child` 之前**设好 `closable` / `collapsible`。
## ⚠️ 必须提前设：`_build()`（在 `_ready`）读它们决定建不建按钮 —— 建完再改没用。
func _mk_win_cfg(title: String, closable: bool, collapsible: bool = true) -> Control:
	var host := Control.new()
	host.size = Vector2(1920, 1080)
	add_child(host)
	var w: Control = W.new()
	w.set("window_title", title)
	w.set("persist_layout", false)
	w.set("closable", closable)
	w.set("collapsible", collapsible)
	host.add_child(w)
	return w


# ---------------------------------------------------------------- 关闭按钮
## 标题栏 ✕（在折叠按钮右边）：默认不建 / 开了就在最右 / **点下去真的发信号**。
## ⚠️ 红线 9：新面板必须验「点下去有反应」—— 不能只断言按钮存在。
func _t_closable() -> void:
	print("[6] 关闭按钮（closable）")
	var w0 := _mk_win("无关闭")
	_ok(not bool(w0.get("closable")), "默认 `closable == false`（常驻面板不该挂假 ✕）")
	_ok(w0.get("_close_btn") == null, "★ 默认不建 ✕ —— 避免「看着能点、点了没反应」")

	var w := _mk_win_cfg("有关闭", true)
	var cb: Control = w.get("_close_btn")
	var hdr: Control = w.get("header")
	var col: Control = w.get("_collapse_btn")
	_ok(cb != null, "★ `closable=true` ⇒ 建出 ✕（%s）" % (cb.name if cb != null else "—"))
	_ok(hdr != null and cb != null and cb.get_index() == hdr.get_child_count() - 1,
			"★ ✕ 在标题栏**最右端**（下标 %d / 共 %d）"
			% [(cb.get_index() if cb != null else -1), (hdr.get_child_count() if hdr != null else -1)])
	_ok(col != null and cb != null and cb.get_index() == col.get_index() + 1,
			"★★ ✕ 紧跟在折叠按钮**右边**（✕ %d / 折叠 %d）"
			% [(cb.get_index() if cb != null else -1), (col.get_index() if col != null else -1)])
	# 点下去真的发信号（不是假按钮）
	var fired := [false]
	w.connect("close_requested", func() -> void: fired[0] = true)
	if cb != null:
		_click(cb)
	_ok(fired[0], "★★ 点 ✕ ⇒ 发出 close_requested（按钮真的接上了）")

	# 没有折叠按钮时 ✕ 仍居最右（两者相互独立）
	var w2 := _mk_win_cfg("无折叠有关闭", true, false)
	var cb2: Control = w2.get("_close_btn")
	var hdr2: Control = w2.get("header")
	_ok(w2.get("_collapse_btn") == null, "collapsible=false ⇒ 不建折叠按钮")
	_ok(cb2 != null and hdr2 != null and cb2.get_index() == hdr2.get_child_count() - 1,
			"★ 无折叠按钮时 ✕ 仍在最右")


# ---------------------------------------------------------------- 基本
func _t_basic() -> void:
	print("[1] 基本：默认可收起 / 收起只剩标题栏 / 再切回来")
	var w := _mk_win("窗A")
	_ok(bool(w.get("collapsible")), "默认 `collapsible == true`（所有浮窗都能收）")
	w.call("set_window_rect", 100.0, 120.0, 300.0, 220.0)
	_ok(absf(w.size.x - 300.0) < 0.5 and absf(w.size.y - 220.0) < 0.5,
			"设置矩形生效（%.0f×%.0f）" % [w.size.x, w.size.y])
	_ok(w.position == Vector2(100, 120), "位置生效（%s）" % str(w.position))

	w.call("toggle_collapse")
	_ok(bool(w.call("is_collapsed")), "★ 切一次 ⇒ 收起")
	# ⚠️ 用 <= 而不是 ==：Godot 会按 （含 1px 边框）
	#    把高度夹上去，实测 27 而不是 26。断言留 3px 余量。
	_ok(w.size.y <= HEADER_H + 3.0, "★ 收起后只剩标题栏高（%.0f ≈ %.0f）" % [w.size.y, HEADER_H])
	_ok(absf(w.size.x - 300.0) < 0.5, "★ 收起只压高度，宽度不变（%.0f）" % w.size.x)
	var cm: Control = w.get("_content_margin")
	_ok(cm != null and not cm.visible, "★ 收起后内容区隐藏")
	var grip: Control = w.get("_grip")
	_ok(grip != null and not grip.visible, "★ 收起后缩放把手隐藏（收起来还让拉大小很怪）")

	w.call("toggle_collapse")
	_ok(not bool(w.call("is_collapsed")), "再切一次 ⇒ 展开")
	_ok(absf(w.size.y - 220.0) < 0.5, "★ 展开后高度回到 220（实际 %.0f）" % w.size.y)
	_ok(cm.visible, "展开后内容区回来")


# ---------------------------------------------------------------- ★★ 集成：HUD 刷新
func _t_refresh_not_undo() -> void:
	print("[2] ★★ HUD 反复 set_window_rect 不能顶掉收起 / 拖动")
	var w := _mk_win("窗B")
	w.call("set_window_rect", 40.0, 40.0, 260.0, 200.0)
	w.call("toggle_collapse")
	# 模拟 HUD 每次刷新都来一遍（`eve_hud_root.gd` 里有十处调用）
	for _i in 3:
		w.call("set_window_rect", 40.0, 40.0, 260.0, 200.0)
	_ok(bool(w.call("is_collapsed")),
			"★★ 收起后 HUD 刷新 3 次 ⇒ **仍然收起**（不弹开）")
	_ok(w.size.y <= HEADER_H + 3.0,
			"★★ 刷新后仍是收起的（高 %.0f）" % w.size.y)

	# 拖动/缩放的结果也不能被刷新抹掉
	w.call("toggle_collapse")
	w.position = Vector2(500.0, 300.0)
	w.size = Vector2(320.0, 260.0)
	w.call("_note_user_rect")
	w.call("set_window_rect", 40.0, 40.0, 260.0, 200.0)
	_ok(w.position == Vector2(500, 300),
			"★★ 玩家拖到的位置不被设计稿覆盖（实际 %s）" % str(w.position))
	_ok(absf(w.size.x - 320.0) < 0.5 and absf(w.size.y - 260.0) < 0.5,
			"★★ 玩家拉成的尺寸不被覆盖（%.0f×%.0f）" % [w.size.x, w.size.y])

	w.call("reset_layout")
	_ok(w.position == Vector2(40, 40) and absf(w.size.y - 200.0) < 0.5,
			"★ `reset_layout()` 恢复设计稿位置（%s / %.0f）" % [str(w.position), w.size.y])


# ---------------------------------------------------------------- ★ 走真实输入通道
func _t_click_channels() -> void:
	print("[3] ★ 走真实点击通道：收起按钮 / 双击标题栏")
	var w := _mk_win("窗C")
	w.call("set_window_rect", 60.0, 60.0, 280.0, 200.0)

	# ① 点标题栏右侧的收起按钮
	var btn: Control = w.get("_collapse_btn")
	_ok(btn != null, "标题栏里确实建了收起按钮")
	if btn != null:
		_click(btn)
		_ok(bool(w.call("is_collapsed")), "★ 点收起按钮 ⇒ 收起（走 gui_input）")
		_click(btn)
		_ok(not bool(w.call("is_collapsed")), "★ 再点一次 ⇒ 展开")

	# ② 双击标题栏
	var hdr: Control = w.get("_header_panel")
	_ok(hdr != null, "有标题栏面板")
	if hdr != null:
		_dbl_click(hdr)
		_ok(bool(w.call("is_collapsed")), "★ 双击标题栏 ⇒ 收起（EVE 习惯）")
		_dbl_click(hdr)
		_ok(not bool(w.call("is_collapsed")), "★ 再双击 ⇒ 展开")


# ---------------------------------------------------------------- ★ 档案窗那个真 bug
func _t_height_sync() -> void:
	print("[4] ★ `set_window_height()` 之后不能被 set_window_rect 改回去")
	var w := _mk_win("窗D")
	w.call("set_window_rect", 80.0, 80.0, 172.0, 128.0)
	w.call("set_window_height", 320.0)          # 档案窗「展开」
	_ok(absf(w.size.y - 320.0) < 0.5, "展开到 320（实际 %.0f）" % w.size.y)
	w.call("set_window_rect", 80.0, 80.0, 172.0, 128.0)   # HUD 刷新
	_ok(absf(w.size.y - 320.0) < 0.5,
			"★★ HUD 刷新后**仍是 320**（实际 %.0f）—— 修前会被改回 128" % w.size.y)
	w.call("set_window_height", 128.0)
	_ok(absf(w.size.y - 128.0) < 0.5, "再收回 128（实际 %.0f）" % w.size.y)


# ---------------------------------------------------------------- 布局记忆
func _t_persist() -> void:
	print("[5] 布局记忆：拖动/缩放/收起态 都要记下来")
	# ⚠️⚠️ 2026-10-10（同 verify_run 的窗高假失败，一个病根）：
	#   本节要**真的写盘**才能验证"记不住"这个病，但 `clear_all()` 会把玩家
	#   真实的 `user://window_layout.cfg` **整个清掉**（游戏里的浮窗位置就没了）。
	#    ⇒ 先存原始字节，结束时**原样写回**；验收不该改变玩家的存档。
	var snap := _read_raw(LAYOUT_STORE.PATH)
	LAYOUT_STORE.persist = true
	LAYOUT_STORE.clear_all()
	var a := _mk_win("记忆窗", true)
	a.call("set_window_rect", 200.0, 150.0, 300.0, 220.0)
	# 模拟「拖动后松手」（松手分支不依赖鼠标位置，可安全喂事件）
	a.position = Vector2(640.0, 360.0)
	a.size = Vector2(360.0, 280.0)
	_press(a.get("_header_panel"), true)
	_press(a.get("_header_panel"), false)
	var rec := LAYOUT_STORE.load_window("记忆窗")
	_ok(not rec.is_empty(), "★ 松手后写下了布局记录")
	_ok(absf(float(rec.get("x", 0.0)) - 640.0) < 0.5
			and absf(float(rec.get("w", 0.0)) - 360.0) < 0.5,
			"★ 记录的位置/尺寸对（%s）" % str(rec))

	# 新起一扇同名窗 ⇒ 应该自动恢复到记录的位置
	var b := _mk_win("记忆窗", true)
	_ok(b.position == Vector2(640, 360),
			"★★ 新窗自动恢复上次位置（实际 %s）" % str(b.position))
	_ok(absf(b.size.x - 360.0) < 0.5 and absf(b.size.y - 280.0) < 0.5,
			"★★ 新窗自动恢复上次尺寸（%.0f×%.0f）" % [b.size.x, b.size.y])

	# 收起态也要记住
	b.call("toggle_collapse")
	var c := _mk_win("记忆窗", true)
	_ok(bool(c.call("is_collapsed")), "★★ 收起态也被记住（新窗进来就是收起的）")

	# ★ 收起态下再拖动 ⇒ ⛔ 不能把「标题栏高」当成玩家要的高度存下来
	c.position = Vector2(700.0, 400.0)
	_press(c.get("_header_panel"), true)
	_press(c.get("_header_panel"), false)
	LAYOUT_STORE.clear_all()
	c.call("reset_layout")            # ⚠️ 它会把收起态清成展开 ⇒ 下面要重新收起
	c.call("set_window_rect", 100.0, 100.0, 300.0, 240.0)
	c.call("toggle_collapse")
	c.position = Vector2(700.0, 400.0)
	c.call("_note_user_rect")
	var ur: Rect2 = c.get("_user_rect")
	_ok(ur.size.y > HEADER_H + 1.0,
			"★★ 收起态下拖动，记下的是**展开态高度**（%.0f，不是 %.0f）"
			% [ur.size.y, HEADER_H])

	# 关掉 persist ⇒ 不写盘
	LAYOUT_STORE.clear_all()
	var d := _mk_win("不写盘窗", false)
	d.call("set_window_rect", 10.0, 10.0, 200.0, 160.0)
	d.call("toggle_collapse")
	_ok(LAYOUT_STORE.load_window("不写盘窗").is_empty(),
			"★ `persist_layout = false` ⇒ 不写盘（验收/特殊窗用）")
	LAYOUT_STORE.persist = false
	_restore_raw(LAYOUT_STORE.PATH, snap)      # ★ 原样写回玩家存档
	# ★ 隔离自证：跑完这一节，玩家的档必须**一字节都没变**（防以后又改回来）
	_ok(_read_raw(LAYOUT_STORE.PATH) == snap,
			"★ 自检未污染玩家的窗口布局档（原样写回）")


# ---------------------------------------------------------------- 存档隔离辅助
func _read_raw(p: String) -> PackedByteArray:
	if not FileAccess.file_exists(p):
		return PackedByteArray()
	var f := FileAccess.open(p, FileAccess.READ)
	return f.get_buffer(f.get_length()) if f != null else PackedByteArray()


func _restore_raw(p: String, b: PackedByteArray) -> void:
	if b.is_empty():
		# 原本就没有这个文件 ⇒ 还原成"没有"，别留一个空档
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
		return
	var f := FileAccess.open(p, FileAccess.WRITE)
	if f != null:
		f.store_buffer(b)


# ---------------------------------------------------------------- 输入辅助
func _click(c: Control) -> void:
	_press(c, true)
	_press(c, false)


func _press(c: Control, down: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = down
	ev.position = c.size * 0.5
	c.gui_input.emit(ev)


func _dbl_click(c: Control) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.double_click = true
	ev.position = c.size * 0.5
	c.gui_input.emit(ev)
