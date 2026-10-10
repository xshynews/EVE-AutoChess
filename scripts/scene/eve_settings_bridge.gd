extends RefCounted

## 设置窗桥接器 —— HUD 设置窗的每条请求落到具体子系统的**唯一落点**。
##
## ══════════════════════════════════════════════════════════════════
##  为什么单独一个文件（而不是继续留在 eve_battle_scene.gd）
## ══════════════════════════════════════════════════════════════════
##  「设置意图 → 子系统调用」是一个内聚职责：天空盒 / 显示模式 / 雾 / 棋盘 走
##  `arena`，音量 / 静音 走 `audio`，加币 走 `run`，偏好持久化 走 `EveSettingsStore`。
##  主控（2139 行的状态机）本来只需要知道「有人要改设置」，不必知道每一条怎么落地。
##
## ⚠️ 这里所有 handler 的共同约定：**改的是子系统的真实状态**，改完**不**回头去刷
##    设置窗的按钮 —— 窗里的按钮就是玩家刚点的那个，它自己已经切好皮肤了。
##    回刷会引入「谁是真相源」的歧义。唯一例外 = `sync_ui()`（键盘改的，窗不知道）。
##
## ⚠️ **本模块不含暂停**：`set_paused()` 与 `_paused` 留在主控 ——
##    那是红线级的「唯一写入口」，且验收脚本直接读 `_battle.get("_paused")`。
##    这里只通过 `_pause` 回调转调。
##
## ⚠️ 依赖是**显式注入**的（两阶段，见 `setup()` / `bind_run()`）：
##    · `arena` / `hud` / `audio` / `deploy` 在主控 `_ready` 早段就绪 ⇒ 阶段一注入；
##    · `run` 建得更晚（且只有「加币」用它）⇒ 阶段二 `bind_run()` 补。
##    · `restart / 回主界面 / 暂停 / 刷 UI / 读暂停态` 是主控自己的动作 ⇒ Callable。

const SETTINGS_STORE := preload("res://scripts/core/eve_settings_store.gd")
const UI_SCALE_SCRIPT := preload("res://scripts/ui/eve_ui_scale.gd")
const RESOLUTION := preload("res://scripts/ui/eve_resolution.gd")
const FONT := preload("res://scripts/ui/eve_font.gd")

var _arena: EveBattleArena = null
var _hud: EveHudRoot = null
var _audio: EveAudio = null
var _deploy = null
var _run: EveRunState = null

var _is_paused: Callable = Callable()
var _pause: Callable = Callable()
var _restart: Callable = Callable()
var _back_to_menu: Callable = Callable()
var _refresh_ui: Callable = Callable()


## 阶段一：`arena` / `hud` / `audio` 一建好就能接（此时 `run` 还没建）。
func setup(p_arena: EveBattleArena, p_hud: EveHudRoot, p_audio: EveAudio, p_deploy,
		p_is_paused: Callable, p_pause: Callable, p_restart: Callable,
		p_back_to_menu: Callable, p_refresh_ui: Callable) -> void:
	_arena = p_arena
	_hud = p_hud
	_audio = p_audio
	_deploy = p_deploy
	_is_paused = p_is_paused
	_pause = p_pause
	_restart = p_restart
	_back_to_menu = p_back_to_menu
	_refresh_ui = p_refresh_ui


## 阶段二：`run` 建好之后补上（只有「加币」按钮用它）。
func bind_run(p_run: EveRunState) -> void:
	_run = p_run


# ══════════════════════════════════════════════════════════════════
#  打开 / 关闭
# ══════════════════════════════════════════════════════════════════

## 打开设置窗（顶条 ≡）。必须先把**当前真实状态**回写进窗里。
func open() -> void:
	if _hud.settings_is_open():
		# 再点一次 = 收起。这比强制玩家去找关闭按钮友好。
		_hud.hide_settings()
		return
	# ⚠️ 打开时必须回写**全部**真实状态（含音量与暂停态）——
	#    否则玩家看到的开关与实际不符，点一下反而改成了他不想要的那个。
	var vols := _audio.volumes()
	_hud.show_settings({
		"background": _arena.current_background_id(),
		"mood": int(_arena.render_mood),
		"fog": bool(_arena.enable_space_fog),
		"rings": _arena.range_layer != null and _arena.range_layer.visible,
		"board": _arena.board != null and _arena.board.visible,
		"paused": bool(_is_paused.call()),
		# ⚠️ 现读存档而不是缓存字段：玩家在窗里改完就写盘了，
		#    缓存一份必然会和盘上漂移（表现 = 重开窗高亮跑位）。
		"ui_scale": float(SETTINGS_STORE.load_all().get("ui_scale", 0.0)),
		# ⚠️ 分辨率传**解析后的档位下标**（不是存档里的 key）——
		#    存档空串是「自动」，窗里要亮的是"实际生效的那一档"。
		"resolution_index": RESOLUTION.current_index(),
		# ⚠️ 字号传**当前生效值**（`FONT.scale`）而不是存档原值：存档里 0.0
		#    是「没设过」，真正生效的是平台出厂默认（桌面 1.10 / 移动 1.20）
		#    —— 传原值会让滑杆停在 0 位上（显示成 0%，玩家一看就懵）。
		"font_scale": FONT.scale,
		"muted": bool(vols.get("muted", false)),
		"volumes": vols,
	})


# ══════════════════════════════════════════════════════════════════
#  画面 / 场地
# ══════════════════════════════════════════════════════════════════

func on_background(id: String) -> void:
	if _arena.set_background(id):
		_hud.append_log({"time": 0.0, "category": &"system",
				"text": "天空盒 → %s" % id})
	else:
		# ⚠️ set_background 对不存在的 id 返回 false。静默失败的话，
		#    玩家点了一个坏条目，画面不动、也没有任何解释。
		_hud.append_log({"time": 0.0, "category": &"hint",
				"text": "天空盒 %s 加载失败（资源缺失）" % id})


func on_mood(mode: int) -> void:
	_arena.render_mood = mode
	_arena._build_environment()
	_hud.append_log({"time": 0.0, "category": &"system",
			"text": "显示模式 → %s" % ("通透" if mode == 0 else "氛围")})


func on_fog(on: bool) -> void:
	_arena.enable_space_fog = on
	_arena._build_environment()
	_hud.append_log({"time": 0.0, "category": &"system",
			"text": "空间雾 %s" % ("开" if on else "关")})


func on_board(on: bool) -> void:
	# ⚠️ 走 set_board_visible 而不是 toggle_board() ——
	#    设置窗给的是**目标状态**，toggle 给的是「翻一下」。
	#    两者在「窗里显示开、实际是关」这种不同步状态下的结果相反。
	_arena.set_board_visible(on)
	# 玩家手动开的棋盘 = 「这局棋盘归玩家管」⇒ 拖动松手时别去自动关它。
	_deploy.mark_board_manual()
	_hud.append_log({"time": 0.0, "category": &"system",
			"text": "棋盘 %s" % ("显示（11×11）" if on else "隐藏")})


func on_camera_reset() -> void:
	_arena.reset_camera()


# ══════════════════════════════════════════════════════════════════
#  局内动作
# ══════════════════════════════════════════════════════════════════

## 「放弃本局 · 回主界面」→ 切回主菜单。
## ⚠️ 主控那句 `change_scene` 由 `_back_to_menu` 回调做（RefCounted 没有树）；
##    切场景前必须先解暂停，否则主菜单进来是蒙着的。
func on_back_to_menu() -> void:
	_pause.call(false)
	_back_to_menu.call()


func on_restart() -> void:
	_hud.append_log({"time": 0.0, "category": &"system", "text": "重开一局"})
	_restart.call()


func on_pause(on: bool) -> void:
	_pause.call(on)


func on_volume(kind: StringName, v: float) -> void:
	_audio.set_volume(kind, v)


func on_mute(on: bool) -> void:
	_audio.set_muted(on)


## ⚠️ DEBUG-ONLY: 设置窗里"加币"按钮的处理器，发布时删除。
## 走 `run.coin += amt` + 调 `_refresh_run_ui()` 走标准刷路径
## （经济栏 / HUD / 商店可买性一并更新）。
## 不绕过 run_state 的 `_deny()` / `log_event` —— 调试按钮也得**走规则**，方便抓退路。
func on_add_coins(amt: int) -> void:
	if _run == null or amt <= 0:
		return
	_run.coin += amt
	_hud.append_log({"time": 0.0, "category": &"economy",
			"text": "[DEBUG] 星币 +%d（当前 %d）" % [amt, _run.coin]})
	_refresh_ui.call()


# ══════════════════════════════════════════════════════════════════
#  启动读盘 / 键盘回写
# ══════════════════════════════════════════════════════════════════

## 把 `user://settings.cfg` 里的偏好应用到这一局（音量 / 静音 / 天空盒 / 显示模式）。
##
## ⚠️ 只应用「玩家偏好」—— 雾 / 射程环 / 棋盘是**场上状态**，
##    读出来覆盖的话会出现「上局收尾时棋盘是关的 ⇒ 新一局开局也是关的」。
##    （它们因此也不进持久化表，见 EveSettingsStore 的说明。）
##
## ⚠️ 必须在 HUD 的 `_ready` 跑完之后调（`apply_ui_profile` 要 HUD 已建好），
##    同一帧内完成 ⇒ 不会闪一帧错位的布局。
func apply_saved() -> void:
	var s := SETTINGS_STORE.load_all()
	_audio.set_volume(&"master", float(s.get("master", 1.0)))
	_audio.set_volume(&"sfx", float(s.get("sfx", 0.60)))
	_audio.set_volume(&"amb", float(s.get("amb", 0.39)))
	_audio.set_volume(&"music", float(s.get("music", 0.32)))
	_audio.set_muted(bool(s.get("muted", false)))
	# ★ 平台缩放档（2026-10-07）：移动端放大 + 紧凑档；桌面端 resolve() 恒 1.0
	#   ⇒ `apply_ui_profile()` 会因为「档位没变」直接返回，一个字节都不动。
	_hud.apply_ui_profile(UI_SCALE_SCRIPT.resolve(float(s.get("ui_scale", 0.0))))
	var bid := String(s.get("background", ""))
	if not bid.is_empty():
		_arena.set_background(bid)
	_arena.render_mood = int(s.get("mood", 0))
	_arena._build_environment()


## 键盘改了会影响设置窗显示的状态时，回写窗里的按钮。
##
## ⚠️ 不这么做的话会出现「窗里写 [关]、实际棋盘是开的」——
##    玩家下一次点它，会把棋盘从「显示」切成「隐藏」，
##    而他以为自己在打开它。键盘与窗口是同一份状态的两条入口，必须同步。
func sync_ui() -> void:
	if not _hud.settings_is_open():
		return
	_hud.sync_settings_toggle("board",
			_arena.board != null and _arena.board.visible)
	_hud.sync_settings_toggle("rings",
			_arena.range_layer != null and _arena.range_layer.visible)
