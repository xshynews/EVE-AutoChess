extends Node
## 启动引导（autoload）。在任何场景加载之前执行一次。
##
## 目前只负责语言：`TranslationServer` 的初始 locale 是操作系统语言，
## 必须在第一次取词之前改成游戏设定的语言，否则英文系统上会取到 CSV 的 en 列
## （例如舰船中文名显示成英文、羁绊数值不生效）。
##
## autoload 早于主场景实例化，所以无论从哪个场景启动（主菜单、验收场景）都会先执行这里。
## 只依赖 `EveText`，不要在这里引用其他游戏脚本，以免提前触发它们的静态初始化。

const T := preload("res://scripts/core/eve_text.gd")
## 安卓线 · 设备指标采集（只读，不改布局）。桌面端不会写。
const DI := preload("res://scripts/mobile/eve_device_info.gd")


func _init() -> void:
	T.apply_saved()


## ★ 2026-10-18：真机指标回传。
##   等两帧再采集 —— `_init()` 时根窗口还没完成尺寸/缩放初始化，那时读到的
##   `viewport_logical` 是默认值，不是真机实际值（会误导后续布局）。
func _ready() -> void:
	if not OS.has_feature("mobile"):
		return
	await get_tree().process_frame
	await get_tree().process_frame
	DI.write_report(get_tree())
