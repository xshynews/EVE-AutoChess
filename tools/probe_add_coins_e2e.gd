extends Node
## 端到端：跑主场景，模拟点 +100/300/999，验是否真闪退
##
## 跑法：
##   "C:/godot/Godot_v4.7.1-stable_win64_console.exe" --headless \
##     --path "F:/evezzq/eve自走棋918" --quit-after 8000 \
##     res://tools/probe_add_coins_e2e.tscn

const BATTLE_SCENE := preload("res://scripts/eve_battle_scene.gd")
const SETTINGS_SCRIPT := preload("res://scripts/ui/panels/eve_settings.gd")
const SHIP_DB := preload("res://scripts/core/eve_ship_database.gd")

var _battle: Node = null
var _hud: Node = null
var _run: Node = null
var _settings_window: Node = null
var _crashed: bool = false


func _ready() -> void:
	print("[E2E] ═══ 加币按钮端到端测试 ═══")

	# 1. 加载主场景
	var packed: PackedScene = load("res://scenes/battle_scene.tscn")
	_battle = packed.instantiate()
	add_child(_battle)
	for _i in 30:
		await get_tree().process_frame
	print("[E2E] 主场景 _ready 完毕")

	# 2. 拿 hud / run / settings
	_hud = _battle.get("hud")
	_run = _battle.get("run")
	_settings_window = _hud.get("settings_window")
	if _settings_window == null:
		print("[E2E] ❌ 拿不到 settings_window")
		get_tree().quit(1)
		return

	# 3. 开设置窗
	_settings_window.visible = true
	for _i in 3:
		await get_tree().process_frame
	print("[E2E] 设置窗已打开")

	# 4. 记录加币前
	var before: int = int(_run.coin)
	print("[E2E] 加币前 run.coin = %d" % before)

	# 5. 模拟点 +100（直接 emit signal，不靠鼠标）
	_settings_window.add_coins_requested.emit(100)
	for _i in 3:
		await get_tree().process_frame
	if _crashed:
		print("[E2E] ❌ 点 +100 后崩溃")
		return
	var after_100: int = int(_run.coin)
	print("[E2E] 加 +100 后 run.coin = %d (期望 %d)" % [after_100, before + 100])
	if after_100 != before + 100:
		print("[E2E] ❌ 加币失败")
		return

	# 6. 再点 +300
	_settings_window.add_coins_requested.emit(300)
	for _i in 3:
		await get_tree().process_frame
	if _crashed:
		print("[E2E] ❌ 点 +300 后崩溃")
		return
	var after_300: int = int(_run.coin)
	print("[E2E] 加 +300 后 run.coin = %d (期望 %d)" % [after_300, after_100 + 300])
	if after_300 != after_100 + 300:
		print("[E2E] ❌ 加币失败")
		return

	# 7. 再点 +999
	_settings_window.add_coins_requested.emit(999)
	for _i in 3:
		await get_tree().process_frame
	if _crashed:
		print("[E2E] ❌ 点 +999 后崩溃")
		return
	var after_999: int = int(_run.coin)
	print("[E2E] 加 +999 后 run.coin = %d (期望 %d)" % [after_999, after_300 + 999])
	if after_999 != after_300 + 999:
		print("[E2E] ❌ 加币失败")
		return

	# 8. 验 hud.refresh() 也能调（通用刷接口）
	var before_refresh: int = int(_run.coin)
	_hud.call("refresh")
	for _i in 3:
		await get_tree().process_frame
	if _crashed:
		print("[E2E] ❌ hud.refresh() 后崩溃")
		return
	var after_refresh: int = int(_run.coin)
	print("[E2E] hud.refresh() 后 run.coin = %d (期望 %d, 不应变化)" % [after_refresh, before_refresh])
	if after_refresh != before_refresh:
		print("[E2E] ❌ hud.refresh() 副作用异常")
		return

	# 9. 检查日志里有没有 "[DEBUG] 星币 +..."
	# 日志在 _hud 的 log_root 里
	print("[E2E] ✅ 三档加币全过 + hud.refresh() 也通，无崩溃")
	get_tree().quit(0)
