extends RefCounted
## EVE 自走棋 —— **user:// 目录迁移**（2026-10-07 改显示名的一次性收尾）
##
## ══════════════════════════════════════════════════════════════════
##  为什么需要这个文件
## ══════════════════════════════════════════════════════════════════
##  发布前发现显示名里带了「918」—— 那三个数字在中国有特殊政治含义，
##  是绝不能碰的红线。⇒ 项目名由 `EVE自走棋918` 改成 `EVE 自走棋`。
##
##  ⚠️⚠️ 但 Godot 的 `user://` 目录**就是用项目名拼出来的**：
##       `%APPDATA%/Godot/app_userdata/<application/config/name>/`
##     改名的副作用是**老玩家的存档目录换了个名字**，游戏再也找不到它 ——
##     表现是「升级之后音量/进度/娱乐币/窗口布局全部重置」，而且**不报任何错**。
##
##  ⇒ 所以改名必须配一个迁移：把旧目录里那几个 `*.cfg` 搬过来。
##
## ── 两条边界（都很重要）──────────────────────────────────────────
##  ① **安卓不受影响**：手机上 `user://` 是应用私有目录
##     （`/data/data/<package>/files/`），与项目名无关 ⇒ 直接跳过。
##  ② **只搬白名单里的文件**，⛔ 不整个目录复制：旧目录里还躺着
##     日志、上百张探针截图、shader cache —— 复制它们既慢又没必要。
##     同目录下 godot-mcp 插件自己写的 `mcp_*.cfg` 也**不搬**
##     （那是插件的状态，让它在新目录重新生成）。
##
## ── 幂等 ────────────────────────────────────────────────────────
##  目标文件**已存在就不动**（`DirAccess.copy_absolute` 对已存在的目标返回
##  `ERR_ALREADY_EXISTS`，这里显式判掉）。所以它可以每次启动都跑，代价只是一次
##  目录存在性检查。⛔ 不需要"已迁移"标记文件 —— 那种标记一旦写坏就永久卡住。

## 旧项目名（= 改名前的 `application/config/name`）。
## ⚠️ 这里必须写死字面量：改完名之后代码里再也读不到旧名了。
const LEGACY_NAME := "EVE自走棋918"

## 要迁移的存档文件白名单。
## ⚠️ **加新存档文件时同步加到这里** —— 漏了的表现是「其他设置都搬过来了，
##    只有这一项被重置」，很容易被当成"新功能的 bug"查半天。
const FILES: Array = [
	"settings.cfg",        ## 音量 / 天空盒 / 字号 / 分辨率 / UI 缩放
	"progress.cfg",        ## 开场剧情看过没有
	"card_coin.cfg",       ## 娱乐币（方案 A：纯记分）
	"window_layout.cfg",   ## 浮窗布局记忆
]

## 验收开关：设 false 后 `migrate_legacy()` 只算不写（⛔ 别去动玩家的真实存档）。
## 惯例同 `EveWindowStore.persist` / `EveCoin.persist`。
static var persist := true


## 启动时调一次（**必须在任何 `user://` 读写之前**）。
## 返回真正搬过来的文件数（0 = 无事可做，正常情况）。
static func migrate_legacy() -> int:
	if OS.has_feature("mobile"):
		return 0                       # 见顶注 ①
	return migrate_between(_legacy_dir(), _current_dir(), persist)


## 核心逻辑 —— **只认路径**，方便用两个临时目录单测（不去碰玩家存档）。
##
## `do_write = false` ⇒ 只统计**会**搬几个（验收的"只读 pass"）。
static func migrate_between(src_dir: String, dst_dir: String, do_write := true) -> int:
	if src_dir == "" or dst_dir == "":
		return 0
	# ⚠️ 同名（= 项目名还没改、或已被改回来）⇒ 什么都不做。
	#    少了这一道，"源 == 目标"会变成自己复制自己。
	if src_dir.strip_edges().trim_suffix("/") == dst_dir.strip_edges().trim_suffix("/"):
		return 0
	if not DirAccess.dir_exists_absolute(src_dir):
		return 0
	var n := 0
	for name in FILES:
		var src := src_dir.path_join(name)
		var dst := dst_dir.path_join(name)
		if not FileAccess.file_exists(src):
			continue
		if FileAccess.file_exists(dst):
			continue                   # 幂等：目标已有 ⇒ 不覆盖（见顶注）
		n += 1
		if not do_write:
			continue
		if not DirAccess.dir_exists_absolute(dst_dir):
			DirAccess.make_dir_recursive_absolute(dst_dir)
		var err := DirAccess.copy_absolute(src, dst)
		if err != OK:
			# ⛔ 不静默：迁移失败会让玩家以为存档丢了，至少要能在日志里看到
			push_warning("[EveUserDir] 迁移失败（%s → %s）：错误码 %d" % [src, dst, err])
			n -= 1
		else:
			print("[EveUserDir] 已迁移 %s" % name)
	return n


## 当前 `user://` 的绝对路径（末尾不带 `/`）。
static func _current_dir() -> String:
	var p := ProjectSettings.globalize_path("user://")
	if p == "":
		return ""
	return p.replace("\\", "/").trim_suffix("/")


## 旧项目名对应的目录（= 当前目录的**同级兄弟**，名字换成 `LEGACY_NAME`）。
static func _legacy_dir() -> String:
	var cur := _current_dir()
	if cur == "":
		return ""
	return cur.get_base_dir().path_join(LEGACY_NAME)
