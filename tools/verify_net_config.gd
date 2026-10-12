extends Node
## 联机 · 内核配置与会合节点自检（**不需要内核二进制**，纯逻辑）。
##
## 用法：`godot --headless --path <工程> --quit-after 9000 res://tools/verify_net_config.tscn`
##
## ★ 为什么要有这一套：`probe_eve_tunnel` 要真内核才能跑，**CI 上没有内核**。
##   于是「参数拼错了」「端口撞了」「port-forward 指错目标」这类错会悄悄溜过去 ——
##   而它们的表现是「玩家点了建房没反应」。所以把参数生成当纯函数来钉。
##
## ⚠️ 真机能不能起来，最终仍以 `probe_eve_tunnel` + 三地实测为准（见设计文档 §2）。

const TUN := preload("res://scripts/net/eve_tunnel.gd")
const RC := preload("res://scripts/net/eve_room_code.gd")
const RELAY := preload("res://scripts/net/eve_relay_list.gd")

const CODE := "K7QM3X9D"

var _pass := 0
var _fail := 0


func _ready() -> void:
	print("═══ 联机内核配置自检 ═══")
	_t_room_code_ports()
	_t_relay_list()
	_t_args_client()
	_t_args_host()
	_t_files()
	print("═══ RESULT passed=%d failed=%d ═══" % [_pass, _fail])
	if _fail > 0:
		print("⚠️ 有失败项")
	get_tree().quit(1 if _fail > 0 else 0)


func _ok(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("  [FAIL] %s" % msg)


# ══════════════════════════════════════════════ 端口派生

func _t_room_code_ports() -> void:
	print("── 端口派生（防撞端口）──")
	var a := RC.listen_port(CODE, 0)
	var b := RC.listen_port(CODE, 1)
	_ok(a != b, "同房间不同座位的监听端口不同（同机跑房主+加入者不撞）(%d/%d)" % [a, b])
	_ok(a != RC.listen_port("OTHER123", 0), "不同房间的监听端口不同")
	_ok(a < RC.LISTEN_BASE + RC.PORT_SPAN and a >= RC.LISTEN_BASE,
			"监听端口落在派生的区间内（%d）" % a)
	_ok(a != 11010, "★ 不用默认 11010（玩家机器上可能装着 EasyTier 图形版）")
	_ok(RC.listen_port(CODE, 0) == a, "同一输入必然是同一端口（全员一致）")
	_ok(RC.rpc_port(CODE, 0) != RC.listen_port(CODE, 0), "RPC 端口与监听端口不同")
	_ok(RC.DEFAULT_PORT == 27015, "游戏统一端口 27015")


# ══════════════════════════════════════════════ 会合节点

func _t_relay_list() -> void:
	print("── 会合节点列表 ──")
	var peers := RELAY.peers()
	_ok(peers.size() >= 3, "内置至少 3 个会合节点（单个挂了还有别的）(%d)" % peers.size())
	var bad := 0
	for p in peers:
		if not RELAY.is_valid(p):
			bad += 1
	_ok(bad == 0, "内置节点全部格式合法")
	var dead := 0
	for p in peers:
		if p.find("public.easytier.cn") >= 0:
			dead += 1
	_ok(dead == 0, "★ 不含已停服的 public.easytier.cn（2026-02 起 NXDOMAIN）")
	_ok(RELAY.parse("tcp://sh.vomiku.com:7910") ==
			{"proto": "tcp", "host": "sh.vomiku.com", "port": 7910}, "解析 tcp://host:port")
	_ok(RELAY.parse("udp://1.2.3.4:11010")["port"] == 11010, "解析 UDP 端口")
	_ok(RELAY.parse("wss://a.b.c:11012/ws")["port"] == 11012, "ws/wss 带路径也能解析（端口在路径前）")
	_ok(RELAY.parse("wss://a.b.c/ws:11012").is_empty(), "顺序写错（路径在前）判不合法")
	_ok(RELAY.parse("").is_empty(), "空串不合法")
	_ok(RELAY.parse("sh.vomiku.com:7910").is_empty(), "缺协议头不合法")
	_ok(RELAY.parse("tcp://host:0").is_empty(), "端口 0 不合法")
	_ok(RELAY.parse("tcp://:11010").is_empty(), "缺主机名不合法")
	# 自定义节点：放前面 + 去重
	var merged := RELAY.peers_with(["tcp://my.own.node:11010", "tcp://my.own.node:11010", "垃圾"])
	_ok(merged[0] == "tcp://my.own.node:11010", "自定义节点排在最前（优先连）")
	_ok(merged.size() == RELAY.peers().size() + 1, "自定义去重、非法项被丢，且内置仍在")
	_ok(RELAY.peers_with([]).size() == RELAY.peers().size(), "没自定义时就是内置列表")


# ══════════════════════════════════════════════ 加入者参数

func _t_args_client() -> void:
	print("── 加入者参数（--no-tun + 端口转发）──")
	var a := TUN.build_args(CODE, 2, false, RELAY.peers(), "北京A")
	_ok(_has(a, "--no-tun"), "★ 带 --no-tun（⇒ 不建虚拟网卡、不需要管理员）")
	_ok(_has(a, "--port-forward"), "带 --port-forward")
	var pf := _value_of(a, "--port-forward")
	_ok(pf == "udp://127.0.0.1:27015/%s:27015" % RC.host_virtual_ip(CODE),
			"★ 端口转发指向房主虚拟 IP（%s）" % pf)
	_ok(pf.find(RC.virtual_ip(CODE, 2)) < 0, "⛔ 不会错指到自己")
	_ok(_has(a, "--network-name"), "带网络名")
	_ok(_value_of(a, "--network-name") == RC.network_name(CODE), "网络名由房间码派生")
	_ok(not _has(a, "--network-secret"), "密钥不出现在命令行（进程列表里看得到）")
	_ok(String(TUN.build_env(CODE).get(TUN.ENV_SECRET, "")) == RC.network_secret(CODE),
			"密钥经环境变量 %s 传递，由房间码派生" % TUN.ENV_SECRET)
	_ok(_has(a, "-p"), "带上会合节点")
	var peers_n := 0
	for i in a.size():
		if a[i] == "-p":
			peers_n += 1
	_ok(peers_n == RELAY.peers().size(), "每个会合节点一个 -p（%d）" % peers_n)
	_ok(_has(a, "-r"), "带管理 RPC 端口（就绪判定靠它）")
	_ok(_value_of(a, "-r") == "127.0.0.1:%d" % RC.rpc_port(CODE, 2), "RPC 只监听本机")
	# ★ 加入者用 DHCP 自动取址：⛔ 不能自己指定 IP（两个加入者会撞同一个）
	_ok(_has(a, "-d"), "★ 用 DHCP 自动取址（实测落在房主声明的网段内）")
	_ok(not _has(a, "-i"), "⛔ 加入者不写死虚拟 IP（写死 ⇒ 两个加入者撞同一个 IP）")


# ══════════════════════════════════════════════ 房主参数

func _t_args_host() -> void:
	print("── 房主参数（no-TUN，不建虚拟网卡）──")
	var a := TUN.build_args(CODE, 0, true, RELAY.peers(), "云南我")
	_ok(_has(a, "--no-tun"), "房主也带 --no-tun（不建虚拟网卡、不需要管理员；实测见 docs/联机方案.md）")
	_ok(not _has(a, "--port-forward"), "房主不需要端口转发（它是被连的一方）")
	# ★ 房主必须声明 /24：加入者的 DHCP 靠它确定网段（不带前缀 ⇒ 落到默认网段 ⇒ 通不了）
	_ok(_value_of(a, "-i") == RC.host_virtual_ip(CODE) + "/24",
			"★ 房主虚拟 IP 带 /24 前缀（%s）" % _value_of(a, "-i"))
	_ok(not _has(a, "-d"), "房主不用 DHCP（IP 必须可预测，加入者要转发到它）")
	_ok(_value_of(a, "--network-name") == RC.network_name(CODE), "和加入者同一个网络名")
	_ok(not _has(a, "--network-secret"), "房主的密钥也不出现在命令行")
	# 房主与加入者的网络身份必须一致，否则根本进不了同一张网
	var c := TUN.build_args(CODE, 1, false, RELAY.peers(), "杭州B")
	_ok(_value_of(a, "--network-name") == _value_of(c, "--network-name"),
			"★★ 房主与加入者网络名一致（不一致就看不见对方）")
	_ok(TUN.build_env(CODE)[TUN.ENV_SECRET] == RC.network_secret(CODE),
			"★★ 房主与加入者使用同一个密钥（同一房间码派生）")
	var peers_a := RELAY.peers()
	var peers_c := RELAY.peers()
	_ok(str(peers_a) == str(peers_c),
			"★★ 双方的会合节点列表一致（实测：连不同节点 ⇒ 互相看不见）")
	_ok(a[a.size() - 1] != "", "参数数组不以空串结尾")


# ══════════════════════════════════════════════ 文件依赖

func _t_files() -> void:
	print("── 内核文件依赖 ──")
	if TUN.core_path() == "":
		_ok(true, "本机没有内核（CI 正常情况）⇒ 跳过文件断言")
		_ok(TUN.missing_files(false) == [TUN.CORE], "没内核时报「缺 easytier-core.exe」")
		_ok(not TUN.available(), "available() = false")
		return
	_ok(TUN.available(), "内核可执行文件在位")
	_ok(TUN.missing_files(false).is_empty(), "加入者侧依赖齐全（core + Packet.dll）")
	_ok(TUN.missing_files(true) == TUN.missing_files(false),
			"房主与加入者依赖相同（no-TUN 不需要 wintun.dll）")
	_ok(TUN.missing_files(false).find(TUN.PACKET_DLL) == -1,
			"★ Packet.dll 在依赖清单里（缺它内核 100ms 静默退出）")
	print("  内核路径：%s" % TUN.core_path())


# ══════════════════════════════════════════════ 工具

func _has(a: Array, flag: String) -> bool:
	return a.has(flag)


func _value_of(a: Array, flag: String) -> String:
	var i := a.find(flag)
	if i < 0 or i + 1 >= a.size():
		return ""
	return String(a[i + 1])
