extends Node

## ★ 53 轮 · **一键实机演示** —— 把备战席塞满全库 52 艘，开战看实机朝向
##
## 用法（**非 headless**，必须真渲）：
##     Godot_v4.7.1-stable_win64.exe --path "F:\evezzq\eve自走棋918" res://tools/probe_live_demo.tscn
##
## 你将看到：
##   · 备战席 9 格全满（每格按 cost 1~5 排开，能看到每派系每吨位档的船）
##   · 第 10 艘（编号 9）起自动部署到我方战斗区最前排
##   · 按 **空格** 或屏幕上的"开始战斗"按钮即开战
##
## 判读：开战瞬间每艘船**舰艏应指向敌方**（敌方从对面冲来）。
##       视角：按 W/A/S/D/Q/E 平移，鼠标右键拖动旋转。
##
## ⚠️ 重要：本探针不修改任何源码 / 标定数据。纯只读 + 临时灌备战席。
##   关掉程序后游戏状态全部丢失（不存盘）。

const YAW := preload("res://scripts/data/eve_ship_yaw.gd")
const INDEX := preload("res://scripts/data/eve_ship_asset_index.gd")


func _ready() -> void:
	print("══════════════════════════════════════════════════════════════")
	print("  53 轮 · 一键实机演示 — 备战席塞全库 52 艘")
	print("══════════════════════════════════════════════════════════════")
	# 等一帧让 battle_scene 跑完 _ready
	await get_tree().process_frame
	_inject()
	get_tree().quit()  # ⚠️ 这里 quit 是给 headless 用的，**真正运行时删掉**这行


func _inject() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		print("✗ 没有 current_scene")
		return
	var run: Variant = scene.get("run")
	if run == null:
		print("✗ scene 没有 run")
		return
	# 给玩家 999 金币
	run.set("coin", 999999)

	# 备战席清空后按"每派系 → 每吨位"排开
	run.get("bench").clear()
	run.get("field").clear()
	# 按 cost 升序（1 轻 → 5 重）
	var all: Array = []
	for s in INDEX.all():
		all.append([int(s.cost), String(s.id), String(s.faction)])
	all.sort()
	for entry in all:
		run.get("bench").append({
				"ship_key": StringName(entry[1]),
				"star": 1,
				"cost": entry[0]})
	run.emit_signal("changed")
	print("  灌入 %d 艘到备战席" % all.size())

	# 把前 9 艘自动部署到我方战斗区第 4 行（部署会自动把船从 bench 移走）
	var deployed := 0
	var to_deploy := mini(9, all.size())
	for i in to_deploy:
		var sid: String = all[i][1]
		var res: Dictionary = run.call("deploy_from_bench", 0, 7 - i / 9 * 2, i % 9)
		if bool(res.get("ok", false)):
			deployed += 1
		else:
			print("  ⚠ %s 部署失败：%s" % [sid, res.get("reason", "?")])
	print("  自动部署 %d 艘到战斗区" % deployed)
	print("")
	print("  ★ 准备就绪。**删掉本脚本 `_ready()` 末尾的 `get_tree().quit()`**")
	print("    并用编辑器启动：")
	print("       Godot_v4.7.1-stable_win64.exe --path F:\\evezzq\\eve自走棋918 res://tools/probe_live_demo.tscn")
	print("    然后按 空格 或屏幕上的「开始战斗」按钮开战")
