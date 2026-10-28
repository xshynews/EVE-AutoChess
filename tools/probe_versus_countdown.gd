extends Node

## 临时出图探针：联机顶条（信标排）+ 最后 10 秒中央倒计时。
## 跑法：Godot --path . --quit-after 400 res://tools/probe_versus_countdown.tscn（⛔ 不能 --headless）

const SCENE_PATH := "res://scenes/battle_scene.tscn"

var _battle: Node = null
var _frame := 0
var _pc_done := false


func _ready() -> void:
	_battle = (load(SCENE_PATH) as PackedScene).instantiate()
	add_child(_battle)


func _process(_dt: float) -> void:
	_frame += 1
	match _frame:
		20:
			_battle.call("begin_prep")
		30:
			_battle.call("_setup_versus", 3)
			_battle.call("_run_ai_prep_turns")
			var hud = _battle.get("hud")
			var bar = hud.get("command_bar")
			bar.call("set_stage", 1, "准备", 30.0)
			bar.call("set_versus", "1-1", "打怪", [
				{"name": "你", "hp": 100, "is_ai": false, "alive": true},
				{"name": "铁猫", "hp": 88, "is_ai": true, "alive": true},
				{"name": "秃鹫", "hp": 72, "is_ai": true, "alive": true},
				{"name": "巨像", "hp": 54, "is_ai": true, "alive": true},
			])
			print("[probe] 顶条 %.0f×%.0f · 信标条可见=%s" % [bar.size.x, bar.size.y,
					str(bar.get("_versus_strip").visible)])
			print("[probe] 开战键可见=%s  倒计时激活=%s" % [
					str(bar.get("_start_btn").visible),
					str(hud.get("round_countdown").get("_active"))])
		40:
			_set_time(10.0)
		42:
			var hud = _battle.get("hud")
			var ov = hud.get("round_countdown")
			print("[probe] HUD %.0f×%.0f · overlay %.0f×%.0f · show_ring=%s · digits=%s · act=%s"
					% [hud.size.x, hud.size.y, ov.size.x, ov.size.y,
						str(ov.get("_show_ring")), str(ov.get("_digits")), str(ov.get("_active"))])
		44:
			_shot("versus_pc_10")
			_set_time(6.0)
		48:
			_shot("versus_pc_06")
			_set_time(3.0)
		52:
			_shot("versus_pc_03")
		56:
			var hud = _battle.get("hud")
			hud.get("command_bar").set("time_left", 0.0)
			hud.call("play_countdown_flash")
			_pc_done = true
		62:
			_shot("versus_pc_00")
		70:
			var hud = _battle.get("hud")
			hud.set("force_mobile_layout", true)
			hud.call("apply_ui_profile", 1.35)
			_set_time(10.0)
		76:
			_shot("versus_mobile_10")
			_set_time(3.0)
		80:
			_shot("versus_mobile_03")
		86:
			get_tree().quit(0)


func _set_time(sec: float) -> void:
	var hud = _battle.get("hud")
	# 探针把 30s 的准备期直接跳到最后一秒，进场横幅本该早已淡完（LIFE≈6s）；
	# 不清掉的话截图里横幅正文会正好压在这个位置上（现实里不会同时出现）。
	var bn = hud.get("entry_banner")
	if bn != null and bn.has_method("clear"):
		bn.call("clear")
	var bar = hud.get("command_bar")
	bar.set("time_left", sec)
	bar.set("phase", 0)


func _shot(tag: String) -> void:
	var tex := get_viewport().get_texture()
	if tex == null:
		print("[probe] 无纹理 %s" % tag)
		return
	var img := tex.get_image()
	img.save_png("user://%s.png" % tag)
	print("[probe] %s → %s" % [tag, ProjectSettings.globalize_path("user://%s.png" % tag)])
