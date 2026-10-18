extends Node
## 安卓线 · 布局换算自检（**不需要真机**）。
##
## 钉住 `EveMobileLayout.derive()` 这条纯换算：
##   物理屏幕 + 物理安全区 + 逻辑视口  ⇒  逻辑安全区 / 内缩 / 像素比
## 以及覆盖文件的读写（L3 调参工具会用它）。
##
## ⚠️ 会临时写 `user://mobile_layout.cfg`：跑之前备份、跑完原样还原，
##    不污染用户已调好的值（与 `ddz_style_tune` 探针同一套做法）。

const ML := preload("res://scripts/mobile/eve_mobile_layout.gd")
const PATH := "user://mobile_layout.cfg"

var _pass := 0
var _fail := 0
var _had := false
var _backup := PackedByteArray()


func _ready() -> void:
	print("═══ 安卓布局换算自检 ═══")
	_backup_file()
	_run()
	_restore_file()
	print("═══ RESULT passed=%d failed=%d ═══" % [_pass, _fail])
	get_tree().quit(1 if _fail > 0 else 0)


func _ok(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("  [FAIL] %s" % msg)


func _rect_eq(a: Rect2, b: Rect2) -> bool:
	return absf(a.position.x - b.position.x) < 0.01 \
			and absf(a.position.y - b.position.y) < 0.01 \
			and absf(a.size.x - b.size.x) < 0.01 \
			and absf(a.size.y - b.size.y) < 0.01


func _run() -> void:
	ML.clear_overrides()

	# ① 真机横屏、设备报「全屏安全区」⇒ 逻辑安全区 = 整个逻辑视口
	var d1 := ML.derive(Vector2(2340, 1080), Rect2i(0, 0, 2340, 1080), Vector2(2340, 1080))
	_ok(_rect_eq(d1["safe"], Rect2(0, 0, 2340, 1080)),
			"2340×1080 全屏安全区 ⇒ 逻辑安全区就是全屏")
	_ok(is_equal_approx(float(d1["insets"]["left"]), 0.0)
			and is_equal_approx(float(d1["insets"]["right"]), 0.0),
			"全屏安全区 ⇒ 左右内缩为 0")

	# ② 左侧刘海 100×1080 ⇒ 左内缩 100、右侧 0
	var d2 := ML.derive(Vector2(2340, 1080), Rect2i(100, 0, 2240, 1080), Vector2(2340, 1080))
	_ok(_rect_eq(d2["safe"], Rect2(100, 0, 2240, 1080)), "左侧刘海 ⇒ 安全区左移 100")
	_ok(is_equal_approx(float(d2["insets"]["left"]), 100.0), "左内缩 = 100")
	_ok(is_equal_approx(float(d2["insets"]["right"]), 0.0), "右内缩 = 0")

	# ③ 战场 content_scale_factor=1.35 ⇒ 逻辑视口 1733×800
	var d3 := ML.derive(Vector2(2340, 1080), Rect2i(0, 0, 2340, 1080), Vector2(1733, 800))
	_ok(_rect_eq(d3["safe"], Rect2(0, 0, 1733, 800)),
			"factor 1.35 ⇒ 安全区按逻辑视口 1733×800 计")
	_ok(absf(d3["px_per_logical"].x - 2340.0 / 1733.0) < 0.01,
			"像素比 = 物理 / 逻辑（%.3f）" % d3["px_per_logical"].x)

	# ④ 桌面 1920×1080 恒等
	var d4 := ML.derive(Vector2(1920, 1080), Rect2i(0, 0, 1920, 1080), Vector2(1920, 1080))
	_ok(_rect_eq(d4["safe"], Rect2(0, 0, 1920, 1080)), "1920×1080 ⇒ 恒等")

	# ⑤ 设备不报安全区（size=0）⇒ 退回全屏，⛔ 不能算出 0 尺寸
	var d5 := ML.derive(Vector2(2340, 1080), Rect2i(), Vector2(2340, 1080))
	_ok(_rect_eq(d5["safe"], Rect2(0, 0, 2340, 1080)), "安全区缺失 ⇒ 退回全屏")

	# ⑥ 安全区超出视口 ⇒ 夹回视口
	var d6 := ML.derive(Vector2(100, 100), Rect2i(-50, -50, 300, 300), Vector2(100, 100))
	_ok(_rect_eq(d6["safe"], Rect2(0, 0, 100, 100)), "安全区超出视口 ⇒ 夹回")

	# ⑦ 覆盖文件：白名单键生效、未知键被忽略
	ML.save_overrides({
		"safe_override": true, "safe_left": 80.0, "safe_right": 40.0,
		"safe_top": 10.0, "safe_bottom": 20.0, "ui_scale": 1.2, "evil": 9,
	})
	var ov := ML.overrides()
	_ok(is_equal_approx(float(ov.get("ui_scale", 0.0)), 1.2), "ui_scale 覆盖生效")
	_ok(not ov.has("evil"), "白名单外键被忽略")

	var s := ML.safe_rect(null)
	_ok(_rect_eq(s, Rect2(80, 10, 1800, 1050)),
			"safe_override ⇒ 逻辑安全区 (80,10,1800,1050)（得到 %s）" % str(s))

	# ⑧ 面板矩形居中在安全区内：宽 = min(1200, 1800×0.5) = 900
	var pr := ML.panel_rect(null, 1200.0, 0.0, 0.5)
	_ok(_rect_eq(pr, Rect2(530, 10, 900, 1050)),
			"panel_rect 在安全区居中（得到 %s）" % str(pr))

	# ⑨ 清除覆盖 ⇒ 回到默认
	ML.clear_overrides()
	_ok(ML.overrides().is_empty(), "清除覆盖后为空")
	_ok(_rect_eq(ML.safe_rect(null), Rect2(0, 0, 1920, 1080)),
			"清除后回落到全屏（逻辑视口 1920×1080）")


func _backup_file() -> void:
	_had = FileAccess.file_exists(PATH)
	if _had:
		var f := FileAccess.open(PATH, FileAccess.READ)
		if f != null:
			_backup = f.get_buffer(f.get_length())
			f.close()


func _restore_file() -> void:
	if _had:
		var f := FileAccess.open(PATH, FileAccess.WRITE)
		if f != null:
			f.store_buffer(_backup)
			f.close()
	elif FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(PATH)
	ML.invalidate()
