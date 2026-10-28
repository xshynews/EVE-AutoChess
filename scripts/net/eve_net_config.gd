extends RefCounted
## 联机 · 中继服务器地址（**内置 = 玩家零配置**）
##
## ══════════════════════════════════════════════════════════════════
##  玩家要做的只有一件事：装一次游戏
## ══════════════════════════════════════════════════════════════════
##  地址在这里定好、随包分发 ⇒ 玩家**看不到也填不到**任何 IP/端口，
##  双方只需要交换一个 8 位房间码。这就是「零门槛」的全部含义。
##
## ── 读取顺序（先到先用）──────────────────────────────────────────
##    1. `user://net.cfg`   —— 现场覆盖。作者在自己机器上填一次即可，
##                             ⛔ 不用重新打包；也是调试本机中继的入口。
##    2. `res://net.cfg`    —— 随包分发。导出时会被打进 APK/EXE，
##                             ⛔ 这是给「玩家」用的那份。
##    3. `BUILTIN` 常量     —— 最终兜底（为空 ⇒ 回退 EasyTier 隧道模式）。
##
## ── net.cfg 格式（ConfigFile）────────────────────────────────────
##    [relay]
##    server="xxx.natfrp.cloud:41234"
##
##   ⚠️ 端口必须**同时**是「樱花隧道的远程端口」和「中继进程监听的端口」，
##      三者不一致 ⇒ 包发出去没人接（UDP 隧道不做端口映射）。
##
## ⚠️ 服务器指的是**跑中继的那台机器**（`tools/relay/eve_relay_server.js`
##    或 `tools/relay_server.tscn`），不是玩家的机器。玩家只连它。

const CFG_SECTION := "relay"
const CFG_KEY := "server"

## ⚠️⚠️ 作者填这里：`域名:端口`（例：`abcd-1234.natfrp.cloud:41234`）。
## 留空 = 没有内置服务器 ⇒ 大厅回退到 EasyTier 隧道模式（PC 房主可用，手机不行）。
##
## ⚠️ 直连中继地址只在**作者本机**有意义（127.0.0.1）；发给玩家的包必须填公网地址。
const BUILTIN := ""

## 本机调试用的默认值（仅当什么都没配时，给作者一个能跑通的起点）。
const LOCAL_FALLBACK := "127.0.0.1:27100"

static var _cache := ""
static var _cached := false


## 当前应当使用的中继地址文本（`host:port`）。空 = 未配置。
static func relay_text() -> String:
	if _cached:
		return _cache
	_cached = true
	_cache = _read_cfg("user://net.cfg")
	if _cache == "":
		_cache = _read_cfg("res://net.cfg")
	if _cache == "":
		_cache = BUILTIN.strip_edges()
	return _cache


## 是否配好了中继（决定大厅默认走中继还是隧道）。
static func has_relay() -> bool:
	return not parse(relay_text()).is_empty()


static func host() -> String:
	return String(parse(relay_text()).get("host", ""))


static func port() -> int:
	return int(parse(relay_text()).get("port", 0))


## 拆 `host:port`。不合法返回空字典。
##
## ⚠️ 按**最后一个**冒号拆：域名里不可能有冒号，但 IPv6 字面量里有
##    （`[::1]:27100`），所以 v6 必须带方括号，拆完把方括号去掉。
static func parse(text: String) -> Dictionary:
	var s := String(text).strip_edges()
	if s == "":
		return {}
	var idx := s.rfind(":")
	if idx <= 0 or idx + 1 >= s.length():
		return {}
	var h := s.substr(0, idx).strip_edges()
	var p := s.substr(idx + 1).strip_edges()
	if h.begins_with("[") and h.ends_with("]"):
		h = h.substr(1, h.length() - 2)
	if not p.is_valid_int():
		return {}
	var port := p.to_int()
	if h == "" or port <= 0 or port > 65535:
		return {}
	return {"host": h, "port": port}


## 把地址写到 `user://net.cfg`（作者填一次，此后本机一直生效）。
## 返回是否写成功。
static func save_override(text: String) -> bool:
	var s := String(text).strip_edges()
	if parse(s).is_empty():
		return false
	var cf := ConfigFile.new()
	cf.set_value(CFG_SECTION, CFG_KEY, s)
	var ok := cf.save("user://net.cfg") == OK
	if ok:
		_cache = s
		_cached = true
	return ok


## 清缓存（验收里改完 cfg 再读时用）。
static func invalidate() -> void:
	_cache = ""
	_cached = false


static func _read_cfg(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var cf := ConfigFile.new()
	if cf.load(path) != OK:
		return ""
	return String(cf.get_value(CFG_SECTION, CFG_KEY, "")).strip_edges()
