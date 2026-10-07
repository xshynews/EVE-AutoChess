extends RefCounted
class_name EveSettingsStore

## EVE 自走棋 —— 设置持久化（`user://settings.cfg`）
##
## ══════════════════════════════════════════════════════════════════
##  它解决什么
## ══════════════════════════════════════════════════════════════════
##  设置窗从「开关集散地」升级成「真设置」之后，一个非常具体的落差出现了：
##  玩家把音效拉到 20%、下次开游戏又是 60%。音量这种东西**调一次就定型**，
##  每次重开都要重调的设置等于没有设置。
##
## ── 为什么只存这几项 ──────────────────────────────────────────────
##  存的是「玩家的偏好」，不是「场上的状态」：
##     ✅ 音量四档 / 静音 / 天空盒 / 显示模式 —— 玩家调完就希望一直生效
##     ❌ 空间雾 / 射程环 / 棋盘 —— 这些是**场上临时状态**，
##        棋盘还会随阶段自动显隐；把它们存下来只会造成
##        「上一局收尾时棋盘是关的 ⇒ 新一局开局棋盘也是关的」这种鬼打墙。
##
## ── 为什么用 ConfigFile 而不是 JSON ──────────────────────────────
##  ConfigFile 的 `load()` 对**不存在的文件**返回 ERR_FILE_NOT_FOUND，
##  这就是天然的「首次启动」判定，不必自己维护一个 version 字段；
##  而且它按 section/key 存，将来加分组不用改格式。
##
## ⚠️ 关键不变量**不许用 assert**（红线）：release 构建会把 assert 整段剥离。
##    读写失败一律 push_warning + 回落默认值 —— 设置读不出来只该「这局用默认值」，
##    不该让游戏起不来。

const PATH := "user://settings.cfg"
const SECTION := "game"

## 默认值表 = 唯一真相源。
##
## ⚠️ 加新设置项**先在这里加一行**：缺项回落、首次写盘、类型校验都读它，
##    在别处另写一份默认值必然会和这里漂移（本工程已经踩过多次）。
## ⚠️ 数值必须与 `EveAudio` 的初值一致 —— 设置窗没被打开过时，
##    玩家听到的就是音频层自己的默认值，两边不一致会出现
##    「窗里显示 60% 而实际是另一个值」。
const DEFAULTS := {
	"master": 1.0,
	"sfx": 0.60,
	"amb": 0.39,
	"music": 0.32,
	"muted": false,
	"background": "caldari_c07",
	"mood": 0,
	# ★ 2026-10-07 UI 缩放档。`0.0` = 「自动」（跟随平台：
	#   移动端 1.35 / 桌面 1.0）。取值域与解析见 `EveUiScale`。
	# ⚠️ 它**只在移动端生效** —— 桌面端读出来也不作数（`EveUiScale.resolve`），
	#   所以这一项进了表也不会改变 Windows 版的行为。
	"ui_scale": 0.0,
	# ★ 2026-10-07 字号缩放（**独立于界面缩放**：只动字、版面不动）。
	#   ⚠️ `0.0` = 「没设过」⇒ 跟随**平台出厂默认**（桌面 1.10 / 移动 1.20，
	#     见 `EveFont.default_scale`），⛔ 不是 1.00 也不是取值域下界。
	#     语义与上面的 `ui_scale` 完全一致：表里存 0，解析交给各自的模块。
	#   取值域 0.80~1.30 见 `EveFont`。
	"font_scale": 0.0,
	# ★ 2026-10-07 **窗口分辨率档**。存的是 `EveResolution.CHOICES` 里的
	#   **key 字符串**（如 `"2560x1440"`），⛔ 不是下标 —— 档位表增删时下标会漂移。
	#   `""`（空串）= 「自动」⇒ 按屏幕可用区挑能放下的最大档（见 `EveResolution`）。
	# ⚠️ 只在**桌面端**生效：无头与移动端一律不应用（那会把自检的视口带歪）。
	"resolution": "",
}


## 读全部设置。文件不存在 / 损坏 / 缺项 → 回落默认值（不影响开局）。
static func load_all() -> Dictionary:
	var out: Dictionary = DEFAULTS.duplicate()
	var cf := ConfigFile.new()
	var err := cf.load(PATH)
	if err != OK:
		# 首次启动就是这条路径，不是错误 —— 别报 warning 刷屏
		return out
	for k in out.keys():
		if not cf.has_section_key(SECTION, k):
			continue
		var v = cf.get_value(SECTION, k)
		# ⚠️ 类型校验：手改过的 cfg / 旧版本的字段可能类型不对。
		#    直接塞给 set_volume() 会在下游炸，这里挡一道（默认值的类型 = 期望类型）。
		if typeof(v) != typeof(out[k]):
			push_warning("[EveSettingsStore] 设置项 %s 类型不符（%d≠%d），回落默认值"
					% [k, typeof(v), typeof(out[k])])
			continue
		out[k] = v
	return out


## 全量写盘。缺的键按默认值补 —— 保证文件里永远是完整的一份。
static func save_all(d: Dictionary) -> void:
	var cf := ConfigFile.new()
	for k in DEFAULTS.keys():
		cf.set_value(SECTION, k, d.get(k, DEFAULTS[k]))
	var err := cf.save(PATH)
	if err != OK:
		push_warning("[EveSettingsStore] 写盘失败（%s）：%d" % [PATH, err])


## 改一项：读 → 改 → 全量写回。
##
## ⚠️ 不做「只写这一个键」的增量写 —— 那样一旦中途失败，
##    文件会停在「半份设置」的状态，而全量写永远留下一份完整的。
static func save_one(key: String, value: Variant) -> void:
	if not DEFAULTS.has(key):
		push_warning("[EveSettingsStore] 未知设置项：%s（未写入）" % key)
		return
	var d := load_all()
	d[key] = value
	save_all(d)
