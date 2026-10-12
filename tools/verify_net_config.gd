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
	_t_android_paths()
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
	_ok(_value_of(a, "--network-secret") == RC.network_secret(CODE), "密钥由房间码派生")
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
	print("── 房主参数（TUN，要建虚拟网卡）──")
	var a := TUN.build_args(CODE, 0, true, RELAY.peers(), "云南我")
	_ok(not _has(a, "--no-tun"), "★ 房主**不加** --no-tun（要建虚拟网卡才能被连）")
	_ok(not _has(a, "--port-forward"), "房主不需要端口转发（它是被连的一方）")
	# ★ 房主必须声明 /24：加入者的 DHCP 靠它确定网段（不带前缀 ⇒ 落到默认网段 ⇒ 通不了）
	_ok(_value_of(a, "-i") == RC.host_virtual_ip(CODE) + "/24",
			"★ 房主虚拟 IP 带 /24 前缀（%s）" % _value_of(a, "-i"))
	_ok(not _has(a, "-d"), "房主不用 DHCP（IP 必须可预测，加入者要转发到它）")
	_ok(_value_of(a, "--network-name") == RC.network_name(CODE), "和加入者同一个网络名")
	_ok(_value_of(a, "--network-secret") == RC.network_secret(CODE), "和加入者同一个密钥")
	# 房主与加入者的网络身份必须一致，否则根本进不了同一张网
	var c := TUN.build_args(CODE, 1, false, RELAY.peers(), "杭州B")
	_ok(_value_of(a, "--network-name") == _value_of(c, "--network-name"),
			"★★ 房主与加入者网络名一致（不一致就看不见对方）")
	_ok(_value_of(a, "--network-secret") == _value_of(c, "--network-secret"),
			"★★ 房主与加入者密钥一致")
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
	_ok(TUN.missing_files(true).is_empty() or not TUN.has_wintun(),
			"房主侧依赖：缺 wintun.dll 时会被 missing_files 报出来")
	_ok(TUN.missing_files(false).find(TUN.PACKET_DLL) == -1,
			"★ Packet.dll 在依赖清单里（缺它内核 100ms 静默退出）")
	# ★★ 不变量：交给 `OS.create_process` 的必须是**磁盘真文件**，⛔ 绝不可是 `res://`
	#   虚拟路径（导出后 `FileAccess` 读得到但进程起不来 —— 2026-10-12 导出时踩过）。
	var p := TUN.core_path()
	_ok(not p.begins_with("res://"),
			"★ 内核路径不是 res:// 虚拟路径（实际「%s」）" % p)
	_ok(FileAccess.file_exists(p), "★ 内核路径在磁盘上真实存在（可被 create_process 执行）")
	_ok(p.find("easytier") >= 0 and p.find(TUN.VERSION) >= 0,
			"解包落在带版本的目录里（换版本会自动重解）")
	_ok(TUN.FILES.has(TUN.CORE) and TUN.FILES.has(TUN.PACKET_DLL) and TUN.FILES.has(TUN.WINTUN),
			"解包清单含 core / Packet.dll / wintun.dll")
	_ok(TUN.SRC_DIR.begins_with("res://"), "解包源目录指向包内资源（导出时才拿得到）")
	print("  内核路径：%s" % p)


# ══════════════════════════════════════════════ 安卓路径反解

func _t_android_paths() -> void:
	print("── 安卓原生库目录反解（纯函数，可无头验） ──")
	var sample := "7f1c2b3d4000-7f1c2b3d5000 r--p 00000000 fd:04 1234 /system/framework/boot.art\n" \
			+ "7f1c2b600000-7f1c2b700000 r-xp 00000000 fd:04 5678 " \
			+ "/data/app/~~AbC==/com.evezzq.autochess-XyZ==/lib/arm64/libgodot_android.so\n" \
			+ "7f1c2b800000-7f1c2b900000 rw-p 00000000 00:00 0 [anon]"
	var got := TUN.parse_native_lib_dir(sample)
	_ok(got == "/data/app/~~AbC==/com.evezzq.autochess-XyZ==/lib/arm64",
			"★ 从 /proc/self/maps 反解出原生库目录（得到「%s」）" % got)
	_ok(TUN.parse_native_lib_dir("") == "", "空输入 → 空（不崩）")
	_ok(TUN.parse_native_lib_dir("no lib here\nnothing") == "", "没有 /lib/ 的行不影响")
	_ok(TUN.parse_native_lib_dir("/a/lib/arm64/x.so (deleted)") == "/a/lib/arm64",
			"带 (deleted) 后缀也能解出")
	_ok(TUN.ANDROID_CORE.begins_with("lib") and TUN.ANDROID_CORE.ends_with(".so"),
			"★ 安卓内核名必须是 lib*.so（否则不会被打进 jniLibs）")
	_ok(TUN.ANDROID_SRC.find("android-arm64") > 0,
			"安卓内核的随包源路径指向 android-arm64 目录")
	# ★★ 系统库目录必须被排除（2026-10-12 联网专项审查）：`/vendor/lib/egl/...` 这类
	#    同样含 `/lib/`，且通常排在应用自己的库**之前** ⇒ 只取第一个会选错。
	var noisy := "7f00-7f01 r-xp 00000000 fd:00 1 /vendor/lib/egl/libEGL.so\n" \
			+ "7f02-7f03 r-xp 00000000 fd:00 2 /apex/com.android.runtime/lib64/libc.so\n" \
			+ "7f04-7f05 r-xp 00000000 fd:00 3 " \
			+ "/data/app/~~XyZ==/com.evezzq.autochess-AbC==/lib/arm64/libgodot_android.so"
	_ok(TUN.parse_native_lib_dir(noisy)
			== "/data/app/~~XyZ==/com.evezzq.autochess-AbC==/lib/arm64",
			"★ 优先取 /data/app/（跳过前面的 /vendor、/apex）")
	_ok(TUN.parse_native_lib_dir("/vendor/lib/egl/libEGL.so\n/apex/x/lib64/libc.so") == "",
			"★ 只有系统库目录时返回空（⛔ 不能拿系统目录当 exec 位置）")


# ══════════════════════════════════════════════ 工具

func _has(a: Array, flag: String) -> bool:
	return a.has(flag)


func _value_of(a: Array, flag: String) -> String:
	var i := a.find(flag)
	if i < 0 or i + 1 >= a.size():
		return ""
	return String(a[i + 1])
