extends RefCounted
## 联机房间码与网络参数派生。纯逻辑，不依赖 UI 与网络。
##
## 玩家之间只交换一个房间码。虚拟网络名、网络密钥、网段、内核端口由它确定性派生，玩家不需要输入。
##
## 安全说明：
## - 房间码就是虚拟网络的密码，长度不要低于 8 位。
## - 网络名与监听端口可能被中继节点或其他人看到，所以所有派生值都来自房间码的
##   「拉伸哈希」（`_root()`），不直接对房间码做哈希，网络名里也不出现房间码明文。
## - 8 位码约 40 bit 熵。拉伸（STRETCH_ROUNDS 轮 SHA-256）让「从网络名离线穷举房间码」
##   的成本提高约 2^18 倍，但这仍然只是增加难度；真正的准入控制是房主确认加入。

## 字符集，剔除易混字符 0 O 1 I（口头报码、手抄时最容易错）。长度 32，正好 5 bit/字符。
const ALPHABET := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
const CODE_LEN := 8
## 所有玩家（含房主）统一连接本地这个端口：房主本地直连，加入者由虚拟网络内核转发到房主。
const DEFAULT_PORT := 27015
## 网络名前缀。修改前缀或下面的盐会让所有旧房间码失效。
const NET_PREFIX := "eve-ddz-"
const SALT := "eve-ddz-v2:"
## 密钥拉伸轮数。约 2^18 轮，在桌面 CPU 上约 0.1 秒，结果有缓存，每个房间码只算一次。
const STRETCH_ROUNDS := 262144
## 网段第二段取值 200~250，避开 192.168 / 172.16-31 / 10.0 等常见家用网段，
## 防止与玩家本地局域网冲突（冲突时会被本地路由抢先，表现为连不上）。
const SUBNET_MIN := 200
const SUBNET_SPAN := 51
## 虚拟网络内核的端口范围。端口按房间码与座位派生而不是写死：
## 玩家机器上可能另装了 EasyTier（默认 11010），同一台机器调试时也要同时跑房主与加入者两个实例。
const LISTEN_BASE := 21010
const RPC_BASE := 26010
const PORT_SPAN := 400

static var _root_cache: Dictionary = {}


## 规范化玩家输入：转大写，去掉所有不在字符集里的字符（允许输入空格、横杠）。
## 返回值长度不一定合法，用 `is_valid()` 判断。
static func normalize(raw: String) -> String:
	var out := ""
	for ch in raw.to_upper():
		if ALPHABET.find(ch) >= 0:
			out += ch
	return out


static func is_valid(code: String) -> bool:
	return code.length() == CODE_LEN


## 生成房间码。默认使用密码学安全随机数；传入 `rng` 时用它（仅供验收固定种子复现）。
static func generate(rng: RandomNumberGenerator = null) -> String:
	var out := ""
	if rng != null:
		for i in CODE_LEN:
			out += ALPHABET[rng.randi_range(0, ALPHABET.length() - 1)]
		return out
	# 256 是 32 的整数倍，按字节取模不会产生偏差。
	var bytes := Crypto.new().generate_random_bytes(CODE_LEN)
	for b in bytes:
		out += ALPHABET[b % ALPHABET.length()]
	return out


## 给人看的排版，例如 `K7QM-3X9D`。只用于显示，不要当作键使用。
static func pretty(code: String) -> String:
	if code.length() != CODE_LEN:
		return code
	return code.substr(0, 4) + "-" + code.substr(4, 4)


## 虚拟网络名。不含房间码明文，与大小写无关。
static func network_name(code: String) -> String:
	return NET_PREFIX + ("name:" + _root(code)).sha256_text().substr(0, 16)


## 虚拟网络的密钥（16 位十六进制）。
static func network_secret(code: String) -> String:
	return ("secret:" + _root(code)).sha256_text().substr(0, 16)


## 虚拟网段，例如 `10.231.7.0/24`。
static func subnet_for(code: String) -> String:
	return "10.%d.%d.0/24" % [_octet2(code), _octet3(code)]


## 某个座位的虚拟 IP。座位 0 是房主，其余座位依次加 1。
static func virtual_ip(code: String, seat: int) -> String:
	return "10.%d.%d.%d" % [_octet2(code), _octet3(code), seat + 1]


## 房主的虚拟 IP（加入者端口转发的目标）。
static func host_virtual_ip(code: String) -> String:
	return virtual_ip(code, 0)


## 该座位的内核监听端口（tcp/udp 共用）。
static func listen_port(code: String, seat: int) -> int:
	return _port_from("listen:%d:" % seat, code, LISTEN_BASE)


## 该座位的内核管理 RPC 端口（只监听本机，用于判断内核是否就绪）。
static func rpc_port(code: String, seat: int) -> int:
	return _port_from("rpc:%d:" % seat, code, RPC_BASE)


## 监听端口对外可见，所以也从拉伸哈希派生；否则可以用端口号低成本筛掉大部分候选房间码。
static func _port_from(tag: String, code: String, base: int) -> int:
	return base + (tag + _root(code)).sha256_text().substr(0, 4).hex_to_int() % PORT_SPAN


## 网段第二段（200~250）。
static func _octet2(code: String) -> int:
	return ("net2:" + _root(code)).sha256_text().substr(0, 2).hex_to_int() % SUBNET_SPAN + SUBNET_MIN


## 网段第三段（1~200）。同一网络里所有节点共用，与座位无关。
static func _octet3(code: String) -> int:
	return ("net3:" + _root(code)).sha256_text().substr(0, 2).hex_to_int() % 200 + 1


## 所有派生值的根：对规范化后的房间码做 STRETCH_ROUNDS 轮 SHA-256。
static func _root(code: String) -> String:
	var key := normalize(code)
	if _root_cache.has(key):
		return _root_cache[key]
	var h := SALT + key
	for i in STRETCH_ROUNDS:
		h = h.sha256_text()
	_root_cache[key] = h
	return h
