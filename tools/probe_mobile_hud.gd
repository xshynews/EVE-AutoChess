extends Node

## 手机专用布局出图探针（2026-10-13 二修四项）
##
## ══════════════════════════════════════════════════════════════════
##  为什么需要它
## ══════════════════════════════════════════════════════════════════
##  手机档布局跑在**安卓真机**上，开发机是 Windows ⇒ 看不见。
##  本探针用 `force_mobile_layout` 在桌面机上强制进手机档，
##  把评审稿的四项修订逐态拍下来：
##    ① mobile_hud       默认战场态（左栏 242 · 构成 240 / 装备 300 · 档案隐藏）
##    ② mobile_settings  设置窗横向栏目（视频 / 音频 / 界面 / 游戏）
##    ③ mobile_dossier   点中舰船 ⇒ 档案亮起、日志让位
##
## ── 跑法 ─────────────────────────────────────────────────────────
##   "$GODOT_BIN" --path . --quit-after 600 res://tools/probe_mobile_hud.tscn
##
##  ⚠️ **不能加 `--headless`**：截图要真渲染。
##  图落在 user://mobile_hud*.png（1920×1080 = 手机横屏同款比例）。

const SCENE_PATH := "res://scenes/battle_scene.tscn"
const SHIP_DB := preload("res://scripts/core/eve_ship_database.gd")

var _battle: Node = null
var _frame := 0


func _ready() -> void:
	var packed: PackedScene = load(SCENE_PATH)
	_battle = packed.instantiate()
	add_child(_battle)


func _process(_dt: float) -> void:
	_frame += 1
	match _frame:
		30:
			_battle.call("begin_prep")
		40:
			# ★ 强制进手机专用布局（与 verify_ui_scale 第 8 段同款手法）
			var hud = _battle.get("hud")
			hud.set("force_mobile_layout", true)
			hud.call("apply_ui_profile", 1.35)
		80:
			_shot("mobile_hud")
		82:
			# 顶条 ≡ 的真实通路：信号 → 桥接器 open() → show_settings()
			_battle.get("hud").emit_signal("settings_requested")
		100:
			_shot("mobile_settings")          # 视频（默认栏目）
		102:
			_click_tab(1)                     # 音频
		104:
			_shot("mobile_settings_audio")
		106:
			_click_tab(3)                     # 游戏
		108:
			_shot("mobile_settings_game")
		110:
			var hud2 = _battle.get("hud")
			hud2.call("hide_settings")
			# 点中一艘船 ⇒ 档案亮起
			var sh = SHIP_DB.instantiate_by_id("bantam", 0, 91001)
			hud2.call("show_ship", sh)
		130:
			_shot("mobile_dossier")
		132:
			get_tree().quit(0)


## 点设置窗的第 i 个栏目按钮（真实 pressed 通道，⛔ 不直接改 `_cur_tab`）。
func _click_tab(i: int) -> void:
	var sw = _battle.get("hud").get("settings_window")
	var btns: Array = sw.get("_tab_btns")
	if i < 0 or i >= btns.size():
		print("[probe] 没有第 %d 个栏目按钮（共 %d）" % [i, btns.size()])
		return
	(btns[i]["btn"] as Button).pressed.emit()


## 截图（同步版：`_process` 里拿到的是上一帧已渲染的纹理，评审够用）。
func _shot(tag: String) -> void:
	var tex := get_viewport().get_texture()
	if tex == null:
		print("[probe] 拿不到视口纹理：%s" % tag)
		return
	var img := tex.get_image()
	if img == null:
		print("[probe] 截图失败：%s" % tag)
		return
	img.save_png("user://%s.png" % tag)
	print("[probe] %s.png 已保存 → %s" % [tag, ProjectSettings.globalize_path("user://%s.png" % tag)])
