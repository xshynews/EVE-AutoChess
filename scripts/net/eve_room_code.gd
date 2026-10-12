extends RefCounted
## 联机 · 房间码派生（**纯逻辑**，无 UI / 无网络）。
##
## 玩家之间只交换一个**房间码**，其余（虚拟网络名、网络密钥、虚拟网段、端口）
## 全部由它确定性派生 —— 玩家不需要知道也不需要输入这些。
##
## 配套：`F:\EVE自走棋\牌面\牌面\联机方案-内置EasyTier-工程设计-2026-10-12.md`
##
## ⚠️ 语义边界：房间码本身**就是**那条虚拟网络的密码。8 位随机码 + 房主确认加入
##   （2026-10-12 用户定）共同构成准入控制。⛔ 别把它降成 6 位以下。
##
## ⚠️ 这些都是「约定」不是「安全边界」：真要防人，靠的是房主确认那一步。

## 字符集：**剔除易混字符** `0 O 1 I`（口头报码、手写抄码时最容易错）。
const ALPHABET := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
const CODE_LEN := 8
## 所有玩家（含房主）统一连本地这个端口 —— 见设计文档 §3：
## 房主是本地直连、加入者由内置内核把这个端口转发进虚拟网 ⇒ 游戏侧代码只有一份。
const DEFAULT_PORT := 27015
## 网络名前缀（改名即换网，⛔ 别随手改，改了老房间码全失效）
const NET_PREFIX := "eve-ddz-"
## 密钥派生的盐（换盐 = 所有房间码失效）
const SECRET_SALT := "eve-ddz-v1:"
## 网段第二段取值范围：**避开 0/1/192.168/172.16-31** 等常见家用网段，
## 免得和玩家自己的局域网撞车（撞了会被本地路由抢先，表现为"连不上"）。
const SUBNET_MIN := 200
const SUBNET_SPAN := 51        # 200 ~ 250


## 规范化玩家输入：转大写、丢掉所有非字符集内的字符（允许他带空格/横杠）。
## 返回可能不是合法长度 —— 用 `is_valid()` 判。
static func normalize(raw: String) -> String:
	var out := ""
	for ch in raw.to_upper():
		if ALPHABET.find(ch) >= 0:
			out += ch
	return out


static func is_valid(code: String) -> bool:
	return code.length() == CODE_LEN


## 生成一个房间码。⚠️ 用调用方给的 rng（无头验收要能固定种子复现）。
static func generate(rng: RandomNumberGenerator) -> String:
	var out := ""
	for i in CODE_LEN:
		out += ALPHABET[rng.randi_range(0, ALPHABET.length() - 1)]
	return out


## 给人念的排版（`K7QM-3X9D`）。⚠️ 只为显示，⛔ 别拿它当键。
static func pretty(code: String) -> String:
	if code.length() != CODE_LEN:
		return code
	return code.substr(0, 4) + "-" + code.substr(4, 4)


static func network_name(code: String) -> String:
	return NET_PREFIX + code.to_lower()


## 虚拟网络的密钥。玩家不需要知道它 —— 由房间码派生。
static func network_secret(code: String) -> String:
	return (SECRET_SALT + code).sha256_text().substr(0, 16)


## 虚拟网段的第二段（200~250）。
static func _octet2(code: String) -> int:
	return (code + SECRET_SALT).sha256_text().substr(0, 2).hex_to_int() % SUBNET_SPAN + SUBNET_MIN


## 虚拟网段的第三段（1~200）。⚠️ 与座位无关 —— 同一条网络里所有节点共用这一段。
static func _octet3(code: String) -> int:
	return (code + "net").sha256_text().substr(0, 2).hex_to_int() % 200 + 1


## 虚拟网段字符串，如 `10.231.7.0/24`。
static func subnet_for(code: String) -> String:
	return "10.%d.%d.0/24" % [_octet2(code), _octet3(code)]


## 该座位的虚拟 IP。★ 座位 0 = 房主，其他座位依次 +1。
static func virtual_ip(code: String, seat: int) -> String:
	return "10.%d.%d.%d" % [_octet2(code), _octet3(code), seat + 1]


## 房主的虚拟 IP（加入者的端口转发目标就是它）。
static func host_virtual_ip(code: String) -> String:
	return virtual_ip(code, 0)
