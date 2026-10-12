extends RefCounted
## 联机 · 会合节点（rendezvous / 共享节点）列表 —— **纯数据**。
##
## 作用：玩家之间互不知道对方在哪，得先有个「大家都够得着的地方」交换地址，
## 之后才是 P2P 打洞；打洞失败则由它中继。
##
## ★★ 铁律（2026-10-12 实测）：**所有玩家必须去连同一份列表**。
##    两边连不同的会合节点 ⇒ **互相看不见**（实测复现）。
##    ⇒ 所以这份列表要内置进游戏，玩家不需要配，也⛔不要让他们各自填。
##
## ⚠️⚠️ 这些是**第三方公益节点**（个人/社区无偿提供）：
##    · 随时可能关站、限速、丢包 —— 所以**内置多个**，单个挂了还有别的；
##    · 曾经的官方节点 `public.easytier.cn:11010` **已于 2026-02 停服**
##      （DNS 已不存在）⇒ ⛔ 绝不能写进代码；
##    · 长期方案是自建（军团一台小机器即可，只做会合与中继，不存数据）。
##      部署配置见 `tools/server/easytier-relay/`，整体方案见 `docs/联机方案.md`。
##
## 下表由 `tools/probe_eve_relay.gd` 在 2026-10-12 实测（TCP 可达 + 延迟）得出。

## 当前内置节点（国内，按实测延迟排序）。格式同内核 `-p` 参数。
const BUILTIN: Array[String] = [
	"tcp://sh.vomiku.com:7910",        ## 上海 · 实测 54~63 ms
	"tcp://38.147.105.178:11010",      ## 实测 ~62 ms
	"tcp://boi.de5.net:11010",         ## 实测可达
	"tcp://47.92.208.217:11010",       ## 实测可达
]

## 实测日期（超过半年请重跑 `tools/probe_eve_relay.gd` 复核；节点会死）
const VERIFIED_AT := "2026-10-12"


## 内置列表（拷贝，⛔ 别让调用方改到常量本身）。
static func peers() -> Array[String]:
	var out: Array[String] = []
	out.append_array(BUILTIN)
	return out


## 内置 + 玩家自定义（设置里填的会放前面优先连）。
static func peers_with(extra: Array) -> Array[String]:
	var out: Array[String] = []
	for uri in extra:
		var u := String(uri).strip_edges()
		if is_valid(u) and not out.has(u):
			out.append(u)
	for uri in BUILTIN:
		if not out.has(uri):
			out.append(uri)
	return out


## `tcp://host:port` / `udp://host:port` 形态校验 —— 给「自定义会合节点」输入框用。
static func is_valid(uri: String) -> bool:
	var p := parse(uri)
	return not p.is_empty()


## 拆成 `{"proto":String, "host":String, "port":int}`；不合法返回空字典。
##
## ⚠️ 端口在**路径之前**（`wss://host:11012/ws`）—— 别用 rfind(":")，
##    那会把 `a.b.c/ws:11012` 这种写错顺序的串当成合法的。
static func parse(uri: String) -> Dictionary:
	var s := uri.strip_edges()
	var idx := s.find("://")
	if idx <= 0:
		return {}
	var proto := s.substr(0, idx).to_lower()
	if proto != "tcp" and proto != "udp" and proto != "ws" and proto != "wss":
		return {}
	var rest := s.substr(idx + 3)
	var colon := rest.find(":")
	if colon <= 0:
		return {}
	var host := rest.substr(0, colon)
	var tail := rest.substr(colon + 1)
	var slash := tail.find("/")
	var port_text := tail if slash < 0 else tail.substr(0, slash)
	if not port_text.is_valid_int():
		return {}
	var port := port_text.to_int()
	if not _host_ok(host) or port <= 0 or port > 65535:
		return {}
	return {"proto": proto, "host": host, "port": port}


## 主机名合法性（只允许字母/数字/`.`/`-`/`_`）——
## ⛔ 这层校验是为了挡住「顺序写错」的串（`a.b.c/ws:11012` 里的 host 会带 `/`）。
static func _host_ok(h: String) -> bool:
	if h == "":
		return false
	for ch in h.to_lower():
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") \
				or ch == "." or ch == "-" or ch == "_":
			continue
		return false
	return true
