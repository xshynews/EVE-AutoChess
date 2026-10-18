extends RefCounted
class_name EveDeviceInfo

## 安卓线 · 设备真相采集（**只读**：不改任何布局、不动任何存档）。
##
## ══════════════════════════════════════════════════════════════════
##  为什么需要它
## ══════════════════════════════════════════════════════════════════
##  用户的实际感受是：「截图看着是一回事儿，到手机实机看又是另一回事儿」。
##  这不是错觉，也不是某个参数写错了 —— 桌面探针跑在固定 1920×1080 的
##  Viewport 里，而真机是「约 2340×1080 + 安全区 + content_scale_factor」，
##  三者的**逻辑视口根本不是同一个东西**。
##
##  ⇒ 在改任何布局之前，先把真机的这几个数拿回来：
##      屏幕像素 / 可用区 / 安全区 / 刘海 / DPI / 缩放 / 逻辑视口 / 缩放因子
##    写进 `user://device_metrics.txt`，再用 adb 拉回电脑对照。
##
##  ★ 本文件**只采集、不判断**。哪种机型该用哪套布局，等拿到真实数据后
##    在 `EveMobileLayout`（下一步）里决定，⛔ 不要在这里写死任何 if。
##
##  ⚠️ 只在移动端写报告（桌面端跳过）：无头验收跑在桌面分支，
##    不需要也不该被这份文件干扰。

const REPORT_PATH := "user://device_metrics.txt"


## 采集当前设备的全部关键指标。纯读，不产生副作用。
static func snapshot() -> Dictionary:
	var d := {}
	d["os"] = OS.get_name()
	d["mobile"] = OS.has_feature("mobile")
	d["model"] = OS.get_model_name()
	d["engine"] = String(Engine.get_version_info().get("string", ""))
	# 物理屏幕（像素）
	d["screen_size"] = DisplayServer.screen_get_size()
	d["screen_usable"] = DisplayServer.screen_get_usable_rect()
	d["window_size"] = DisplayServer.window_get_size()
	# 安全区 / 刘海（Android 才有意义）
	d["safe_area"] = DisplayServer.get_display_safe_area()
	d["cutouts"] = DisplayServer.get_display_cutouts()
	# DPI / 缩放
	if DisplayServer.has_method("screen_get_dpi"):
		d["screen_dpi"] = DisplayServer.screen_get_dpi()
	if DisplayServer.has_method("screen_get_scale"):
		d["screen_scale"] = DisplayServer.screen_get_scale()
	return d


## 在**场景树就绪之后**调用：补上逻辑视口与缩放因子，然后写报告。
## `tree` 传 `get_tree()`；为空时静默返回（例如无头环境）。
static func write_report(tree: SceneTree) -> void:
	if tree == null or tree.root == null:
		return
	var root := tree.root
	var d := snapshot()
	# 逻辑视口：`canvas_items + expand` 下它会随屏幕比例变宽/变高。
	d["viewport_logical"] = root.get_visible_rect().size
	d["content_scale_factor"] = root.content_scale_factor
	d["content_scale_mode"] = root.content_scale_mode
	d["content_scale_aspect"] = root.content_scale_aspect
	d["content_scale_size"] = root.content_scale_size
	d["base_viewport"] = Vector2i(
			int(ProjectSettings.get_setting("display/window/size/viewport_width", 1920)),
			int(ProjectSettings.get_setting("display/window/size/viewport_height", 1080)))
	# 派生量：把「屏幕 / 逻辑视口」的比值也写出来，省得每次手算。
	var ss: Vector2i = d.get("screen_size", Vector2i.ZERO)
	var vl: Vector2 = d.get("viewport_logical", Vector2.ZERO)
	if ss.x > 0 and vl.x > 0.0:
		d["pixels_per_logical_px"] = Vector2(ss.x / vl.x, ss.y / vl.y)

	var f := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_line("# EVE 自走棋 · 设备指标（只读采集）")
	f.store_line("# 拉回电脑：bash tools/android/device_shot.sh")
	for k in d.keys():
		f.store_line("%s = %s" % [String(k), str(d[k])])
	f.close()
	# 同时打一行到 logcat，真机不接电脑也能在 `adb logcat` 里看到摘要。
	print("[EveDeviceInfo] screen=%s safe=%s logical=%s scale=%.3f factor=%.3f"
			% [str(ss), str(d.get("safe_area", Rect2i())), str(vl),
			float(d.get("screen_scale", 0.0)), float(root.content_scale_factor)])


## 把报告读成字典（给探针 / 自检用；文件不存在返回空字典）。
static func read_report() -> Dictionary:
	if not FileAccess.file_exists(REPORT_PATH):
		return {}
	var f := FileAccess.open(REPORT_PATH, FileAccess.READ)
	if f == null:
		return {}
	var out := {}
	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line == "" or line.begins_with("#"):
			continue
		var eq := line.find("=")
		if eq > 0:
			out[line.substr(0, eq).strip_edges()] = line.substr(eq + 1).strip_edges()
	f.close()
	return out
