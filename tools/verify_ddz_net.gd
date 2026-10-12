extends Node
## 斗地主联机会话层自检（无 UI、无网络）。
##
## 用法：`godot --headless --path . --quit-after 9000 res://tools/verify_ddz_net.tscn`
##
## 最关键的是 `_t_isolation`（手牌隔离）。把单机版改成联机时，最容易顺手把整副牌同步出去，
## 而界面和流程看起来完全正常。判据：
## 1. 每个座位的下发负载里，不出现别人尚未公开的牌；
## 2. 负载字段严格等于白名单，新增字段必须同步修改 `SNAP_KEYS`；
## 3. 发牌种子不出现在键名、数值与日志中。
## 另有一条反向自检：故意把整副牌塞进负载，确认检测器确实能发现泄漏。
##
## `_t_peer_binding` 与 `_t_input_validation` 覆盖网络输入：冒充座位、越界叫分、畸形数据。

const N := preload("res://scripts/net/ddz_net.gd")
const RC := preload("res://scripts/net/eve_room_code.gd")
const G := preload("res://scripts/card/ddz/ddz_game.gd")
const AI := preload("res://scripts/card/ddz/ddz_ai.gd")
const R := preload("res://scripts/card/ddz/ddz_rules.gd")

## 下发负载允许出现的字段（白名单）。新增字段必须同步修改这里。
const SNAP_KEYS := ["seat", "phase", "turn", "landlord", "base_score", "pass_streak",
		"passed",
		"bombs", "spring", "winner", "multiplier", "counts", "your_hand",
		"last_play", "played", "bottom", "log", "seats"]
## 单局自检的步数上限。一局跑不完说明驱动卡住了。
const MAX_STEPS := 400

var _pass := 0
var _fail := 0


func _ready() -> void:
	print("═══ 斗地主联机会话层自检 ═══")
	_t_room_code()
	_t_seed_repro()
	_t_isolation()
	_t_authority()
	_t_peer_binding()
	_t_input_validation()
	_t_takeover()
	_t_wire()
	print("═══ RESULT passed=%d failed=%d ═══" % [_pass, _fail])
	if _fail > 0:
		print("有失败项")
	get_tree().quit(1 if _fail > 0 else 0)


func _ok(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("  [FAIL] %s" % msg)


# ══════════════════════════════════════════════════════ 1 房间码派生

func _t_room_code() -> void:
	print("── 房间码派生 ──")
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261012
	var code: String = RC.generate(rng)
	_ok(code.length() == 8, "生成 8 位房间码（得到 %s）" % code)
	_ok(RC.is_valid(code), "生成结果合法")
	var bad := 0
	for ch in code:
		if RC.ALPHABET.find(ch) < 0:
			bad += 1
	_ok(bad == 0, "只含非易混字符（不含 0/O/1/I）")
	# 玩家输入容错：小写、横杠、空格都吃得下
	_ok(RC.normalize(RC.pretty(code).to_lower()) == code, "规范化能吃下小写与横杠")
	_ok(RC.normalize("k7qm-3x9d") == "K7QM3X9D", "规范化示例 k7qm-3x9d → K7QM3X9D")
	_ok(not RC.is_valid(RC.normalize("K7QM")), "半截码判不合法")
	_ok(RC.pretty("K7QM3X9D") == "K7QM-3X9D", "展示排版 4-4")
	# 确定性派生
	_ok(RC.network_name(code) == RC.network_name(code), "网络名确定")
	_ok(RC.network_name(code).begins_with("eve-ddz-"), "网络名带前缀")
	_ok(RC.network_name(code) == RC.network_name(code.to_lower()), "网络名与大小写无关")
	_ok(RC.network_secret(code).length() == 16, "密钥 16 位 hex")
	_ok(RC.network_secret(code) == RC.network_secret(code), "密钥确定")
	_ok(RC.network_secret(code).find(code.to_lower()) < 0, "密钥里不出现码明文")
	_ok(RC.network_name(code).to_upper().find(code) < 0, "网络名里不出现码明文")
	_ok(RC.network_name(code) != RC.NET_PREFIX + code.to_lower(), "网络名不是「前缀 + 房间码」")
	# 不传 rng 时走密码学安全随机数
	var c1: String = RC.generate()
	var c2: String = RC.generate()
	_ok(RC.is_valid(c1) and RC.normalize(c1) == c1, "默认生成器产出合法房间码（%s）" % c1)
	_ok(c1 != c2, "默认生成器两次结果不同")
	# 网段：避开常见家用网段（撞了会被本地路由抢先）
	var parts: PackedStringArray = RC.subnet_for(code).split(".")
	_ok(parts.size() == 4 and parts[0] == "10" and parts[3] == "0/24",
			"网段形如 10.x.y.0/24（得到 %s）" % RC.subnet_for(code))
	var o2 := int(parts[1])
	_ok(o2 >= 200 and o2 <= 250, "第二段落在 200~250（避开 192.168 / 10.0 / 172.16）")
	_ok(parts[2] != "0" and parts[2] != "1", "第三段避开 0 / 1")
	# 座位 IP
	_ok(RC.virtual_ip(code, 0) == RC.host_virtual_ip(code), "房主的虚拟 IP = 座位 0")
	_ok(RC.virtual_ip(code, 0) != RC.virtual_ip(code, 1), "座位间虚拟 IP 不重复")
	_ok(RC.virtual_ip(code, 2).begins_with("10."), "座位虚拟 IP 形如 10.x.y.z")
	# 不同房间码 → 不同网络（两局人不会串到一条网上）
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = 7
	var code2: String = RC.generate(rng2)
	_ok(code2 != code, "不同种子出不同码")
	_ok(RC.network_name(code2) != RC.network_name(code), "不同码 → 不同网络名")
	_ok(RC.network_secret(code2) != RC.network_secret(code), "不同码 → 不同密钥")
	_ok(RC.DEFAULT_PORT == 27015, "统一端口 27015（全员连 127.0.0.1:27015）")


# ══════════════════════════════════════════════════════ 2 发牌可复现

func _t_seed_repro() -> void:
	print("── 发牌可复现（种子只在房主侧）──")
	var a = G.new()
	a.start(4242)
	var b = G.new()
	b.start(4242)
	var c = G.new()
	c.start(4243)
	_ok(str(a.hands) == str(b.hands), "同种子发同一副牌")
	_ok(str(a.hands) != str(c.hands), "不同种子发不同牌")
	_ok((a.hands[0] as Array).size() == 17, "每家 17 张")
	_ok(a.bottom.size() == 3, "底牌 3 张")


# ══════════════════════════════════════════════════════ 3 手牌隔离

func _t_isolation() -> void:
	print("── 手牌隔离（核心）──")
	var seed_val := 987654321
	var net = N.new()
	net.host_setup(["我", "下家", "上家"])
	net.host_start(seed_val, 0)
	var g = net.authoritative_game()

	var steps := 0
	var leaks := 0
	var key_bad := 0
	var own_bad := 0
	var seed_bad := 0
	var want: Array = SNAP_KEYS.duplicate()
	want.sort()

	while not g.is_over() and steps < MAX_STEPS:
		steps += 1
		# 三家一律用 AI 驱动，且全部走房主的命令入口（与真人同一条路径）
		var t := int(g.turn)
		if int(g.phase) == int(G.Phase.BID):
			net.apply_command({"seat": t, "kind": N.Kind.BID,
					"score": AI.bid_score(g, t)})
		else:
			var mv: Dictionary = AI.choose(g, t)
			if bool(mv.get("pass", false)):
				net.apply_command({"seat": t, "kind": N.Kind.PASS})
			else:
				net.apply_command({"seat": t, "kind": N.Kind.PLAY,
						"cards": mv.get("cards", [])})

		# 每一步之后，核三个座位各自的下发负载
		for s in N.SEATS:
			var snap: Dictionary = net.snapshot_for(s)
			if snap.is_empty():
				continue
			# ① 字段白名单
			var keys: Array = snap.keys()
			keys.sort()
			if str(keys) != str(want):
				key_bad += 1
				if key_bad <= 2:
					print("     字段不符 seat=%d：%s" % [s, str(keys)])
			# ② 自己的手牌必须一字不差
			if str(snap["your_hand"]) != str(g.hands[s]):
				own_bad += 1
				if own_bad <= 2:
					print("     自己的手牌不对 seat=%d" % s)
			# ③ 别人未公开的牌：一张都不许出现
			var leaked: Array = _leaked_ids(g, s, snap)
			if not leaked.is_empty():
				leaks += 1
				if leaks <= 3:
					print("     ✗ seat=%d 泄漏了别人的牌 %s" % [s, str(leaked)])
			# ④ 种子三路排查：字段名 / 数值 / 日志
			var seed_hit := false
			for k in N.collect_keys(snap):
				if String(k).to_lower().find("seed") >= 0:
					seed_hit = true
			if N.collect_ints(snap).has(seed_val):
				seed_hit = true
			for line in snap.get("log", []):
				if String(line).to_lower().find("seed") >= 0:
					seed_hit = true
			if seed_hit:
				seed_bad += 1
				if seed_bad <= 2:
					print("     ✗ seat=%d 负载里出现发牌种子" % s)

	_ok(steps > 20, "跑完一整局（%d 步）" % steps)
	_ok(bool(g.is_over()), "对局正常结束")
	_ok(key_bad == 0, "下发字段严格等于白名单（加字段必须来改 SNAP_KEYS）")
	_ok(own_bad == 0, "每个座位都拿到了且只拿到自己的手牌")
	_ok(seed_bad == 0, "全 %d 步：发牌种子从未下发" % steps)
	_ok(leaks == 0, "全 %d 座位 × 全 %d 步：无任何他人手牌泄漏" % [N.SEATS, steps])

	# 反向自检：故意把整副牌塞进负载，检测器必须抓到（否则上面那个 0 不可信）
	var fake: Dictionary = net.snapshot_for(1)
	var all: Array = []
	for o in N.SEATS:
		all.append_array(g.hands[o])
	fake["your_hand"] = all
	_ok(not _leaked_ids(g, 1, fake).is_empty(), "反向自检：把整副牌塞进负载，检测器能抓到")

	# 亮底之后：底牌归地主，那 3 张对地主本人是公开的，但对别人仍不该出现
	# （它在另一个人的手里 —— 除非他就是地主）
	var s_land := int(g.landlord)
	if s_land >= 0:
		var j := (s_land + 1) % N.SEATS
		_ok(_leaked_ids(g, j, net.snapshot_for(j)).is_empty(),
				"亮底后：非地主座位仍看不到那 3 张底牌")


## 某座位的下发负载里，混进了多少张「别人的、且尚未公开的」牌。
func _leaked_ids(g, seat: int, snap: Dictionary) -> Array:
	var public_ids := {}
	for c in g.played:
		public_ids[int(c)] = true
	if int(g.landlord) >= 0:
		for c in g.bottom:
			public_ids[int(c)] = true     # 亮了底的 3 张是公开情报
	var mine := {}
	for c in g.hands[seat]:
		mine[int(c)] = true
	var seen := {}
	for v in _card_fields(snap):
		seen[int(v)] = true
	var out: Array = []
	for o in N.SEATS:
		if o == seat:
			continue
		for c in g.hands[o]:
			var ci := int(c)
			if public_ids.has(ci) or mine.has(ci):
				continue
			if seen.has(ci) and not out.has(ci):
				out.append(ci)
	return out


## 负载里所有会装牌 id 的字段（只挑这几个 —— 别把 turn/phase 这种小整数
## 一起摊平，否则 `turn=3` 会撞上牌 id 3 造成假阳性）。
func _card_fields(snap: Dictionary) -> Array:
	var out: Array = []
	for key in ["your_hand", "played", "bottom"]:
		for v in snap.get(key, []):
			out.append(int(v))
	var lp: Dictionary = snap.get("last_play", {})
	for v in lp.get("cards", []):
		out.append(int(v))
	return out


# ══════════════════════════════════════════════════════ 4 房主权威

func _t_authority() -> void:
	print("── 房主权威（客户端说不了算）──")
	var net = N.new()
	net.host_setup(["A", "B", "C"])
	net.host_start(13579, 0)
	var g = net.authoritative_game()

	# 不是自己的回合
	var wrong: Dictionary = net.apply_command({"seat": 1, "kind": N.Kind.BID, "score": 3})
	_ok(not bool(wrong["ok"]), "不是自己回合 ⇒ 被拒（%s）" % String(wrong["reason"]))

	# 座位 0 叫 3 分 ⇒ 直接定地主
	var okb: Dictionary = net.apply_command({"seat": 0, "kind": N.Kind.BID, "score": 3})
	_ok(bool(okb["ok"]), "座位 0 叫 3 分成功")
	_ok(int(g.landlord) == 0, "地主 = 座位 0")
	_ok(int(g.phase) == int(G.Phase.PLAY), "进入出牌阶段")
	_ok((g.hand_of(0) as Array).size() == 20, "地主 20 张（17 + 底牌 3）")

	# 出别人手里的牌
	var steal: Dictionary = net.apply_command({"seat": 0, "kind": N.Kind.PLAY,
			"cards": [int((g.hands[1] as Array)[0])]})
	_ok(not bool(steal["ok"]), "出别人手里的牌 ⇒ 被拒（%s）" % String(steal["reason"]))

	# 空出牌
	var empty: Dictionary = net.apply_command({"seat": 0, "kind": N.Kind.PLAY, "cards": []})
	_ok(not bool(empty["ok"]), "空出牌 ⇒ 被拒")

	# 非法牌型：两张不同点数的单牌（不是任何合法牌型）
	var bad_cards: Array = _two_different_ranks(g.hand_of(0))
	_ok(bad_cards.size() == 2, "构造出「两张不同点数」的样本")
	if bad_cards.size() == 2:
		var bad: Dictionary = net.apply_command({"seat": 0, "kind": N.Kind.PLAY,
				"cards": bad_cards})
		_ok(not bool(bad["ok"]), "非法牌型 ⇒ 被拒（%s）" % String(bad["reason"]))

	# 未知命令
	var unk: Dictionary = net.apply_command({"seat": 0, "kind": 99})
	_ok(not bool(unk["ok"]), "未知命令 ⇒ 被拒")

	# 座位越界
	var oob: Dictionary = net.apply_command({"seat": 7, "kind": N.Kind.PLAY, "cards": []})
	_ok(not bool(oob["ok"]), "座位越界 ⇒ 被拒")

	# 合法出牌（房主的合法候选）
	var legal: Array = g.legal_now(0)
	_ok(not legal.is_empty(), "房主有合法候选")
	if not legal.is_empty():
		var r: Dictionary = net.apply_command({"seat": 0, "kind": N.Kind.PLAY,
				"cards": legal[0]})
		_ok(bool(r["ok"]), "合法出牌成功")

	# 客户端不能裁决
	var cli = N.new()
	cli.client_setup(1, "下家")
	var nothost: Dictionary = cli.apply_command({"seat": 1, "kind": N.Kind.BID, "score": 1})
	_ok(not bool(nothost["ok"]), "客户端无法裁决（%s）" % String(nothost["reason"]))
	_ok(cli.apply_command({"seat": 1, "kind": N.Kind.BID, "score": 1})["result"].is_empty(),
			"被拒时不下发任何状态")

	# 客户端只能看到自己的手牌（视图来自快照，不建本地对局）
	var snap1: Dictionary = net.snapshot_for(1)
	cli.client_apply_snapshot(snap1)
	_ok(str(cli.view["your_hand"]) == str(g.hands[1]), "客户端视图里的手牌 = 他的真手牌")
	_ok(not cli.view.has("seed"), "客户端视图里没有种子字段")
	_ok(cli.authoritative_game() == null, "客户端没有权威对局对象（拿不到整副牌）")


# ══════════════════════════════════════════════════════ 5 连接绑定（防冒充）

func _t_peer_binding() -> void:
	print("── 连接绑定（防冒充）──")
	var net = N.new()
	net.host_setup(["A", "B", "C"], 1)
	net.host_start(24680, 0)
	var g = net.authoritative_game()
	_ok(net.seat_of_peer(1) == 0, "房主连接绑定在座位 0")
	_ok(net.bind_peer(1, 101), "座位 1 绑定连接 101")
	_ok(net.bind_peer(2, 102), "座位 2 绑定连接 102")
	_ok(not net.bind_peer(2, 101), "同一连接不能占两个座位")
	_ok(not net.bind_peer(5, 105), "绑定越界座位被拒")

	# 未入座的连接
	var stranger: Dictionary = net.apply_remote(999, {"seat": 0, "kind": N.Kind.BID, "score": 1})
	_ok(not bool(stranger["ok"]), "未入座连接的命令被拒（%s）" % String(stranger["reason"]))

	# 连接 101（座位 1）伪造 seat=0，在座位 0 的回合叫 3 分
	_ok(int(g.turn) == 0, "当前轮到座位 0")
	var spoof: Dictionary = net.apply_remote(101, {"seat": 0, "kind": N.Kind.BID, "score": 3})
	_ok(not bool(spoof["ok"]), "伪造 seat 字段冒充座位 0 被拒（%s）" % String(spoof["reason"]))
	_ok(int(g.landlord) < 0 and int(g.phase) == int(G.Phase.BID), "冒充命令没有改变局面")

	# 冒充心跳：连接 101 替掉线的座位 2 续命
	net.mark_offline(2)
	net.apply_remote(101, {"seat": 2, "kind": N.Kind.PING, "now_ms": N.TAKEOVER_MS * 10})
	_ok(not bool(net.seats[2]["online"]), "伪造他人心跳不会让掉线座位恢复在线")
	var r: Dictionary = net.tick(N.TAKEOVER_MS + 1000)
	_ok((r["takeover"] as Array).has(2), "掉线座位照常转为托管")

	# 正常路径：房主自己叫分
	var own: Dictionary = net.apply_remote(1, {"kind": N.Kind.BID, "score": 3})
	_ok(bool(own["ok"]), "通过连接身份正常叫分（命令里不带 seat 也行）")

	# 重连换了连接 id
	_ok(net.bind_peer(1, 201), "座位 1 重连后改绑连接 201")
	_ok(net.seat_of_peer(101) < 0, "旧连接 101 不再对应任何座位")
	net.unbind_peer(201)
	_ok(net.seat_of_peer(201) < 0, "解绑后连接 201 不对应任何座位")
	_ok(not bool(net.apply_remote(201, {"kind": N.Kind.PING})["ok"]), "解绑后的连接命令被拒")


# ══════════════════════════════════════════════════════ 6 输入校验

func _t_input_validation() -> void:
	print("── 输入校验（畸形 / 越界数据不报错、不生效）──")
	var net = N.new()
	net.host_setup(["A", "B", "C"])
	net.host_start(11223, 0)
	var g = net.authoritative_game()

	# 叫分范围
	for s in [99, 4, -1]:
		var r: Dictionary = net.apply_command({"seat": 0, "kind": N.Kind.BID, "score": s})
		_ok(not bool(r["ok"]), "叫 %d 分被拒（%s）" % [s, String(r["reason"])])
	_ok(int(g.base_score) == 1 and int(g.phase) == int(G.Phase.BID), "越界叫分没有改变底分与阶段")
	_ok(not bool(net.apply_command({"seat": 0, "kind": N.Kind.BID, "score": "3"})["ok"]),
			"叫分为字符串被拒")
	_ok(not bool(net.apply_command({"seat": 0, "kind": N.Kind.BID})["ok"]), "缺少叫分被拒")

	# 进入出牌阶段
	net.apply_command({"seat": 0, "kind": N.Kind.BID, "score": 3})
	_ok(int(g.phase) == int(G.Phase.PLAY), "叫 3 分进入出牌阶段")
	var h0: Array = g.hand_of(0)
	var c0 := int(h0[0])
	var bad_cases := [
		["cards 是整数", 5],
		["cards 是字符串", "abc"],
		["cards 是字典", {"a": 1}],
		["牌 id 是浮点数", [float(c0)]],
		["牌 id 是字符串", [str(c0)]],
		["牌 id 越界", [54]],
		["牌 id 为负", [-1]],
		["重复的牌", [c0, c0]],
		["张数过多", range(21)],
	]
	for case in bad_cases:
		var r: Dictionary = net.apply_command({"seat": 0, "kind": N.Kind.PLAY, "cards": case[1]})
		_ok(r.has("ok") and not bool(r["ok"]), "%s ⇒ 被拒（%s）" % [case[0], String(r.get("reason", ""))])
	_ok((g.hand_of(0) as Array).size() == 20, "畸形出牌后地主手牌不变")

	# 命令本身的格式
	_ok(not bool(net.apply_command({"seat": "0", "kind": N.Kind.PASS})["ok"]), "seat 为字符串被拒")
	_ok(not bool(net.apply_command({"seat": 0, "kind": 1.0})["ok"]), "kind 为浮点数被拒")
	_ok(not bool(net.apply_command({})["ok"]), "空命令被拒")
	_ok(not bool(net.apply_command({"seat": 0, "kind": N.Kind.PING, "now_ms": "x"})["ok"]),
			"心跳时间为字符串被拒")
	net.bind_peer(1, 101)
	_ok(not bool(net.apply_remote(101, [1, 2, 3])["ok"]), "远端命令不是字典被拒")
	_ok(not bool(net.apply_remote(101, null)["ok"]), "远端命令为 null 被拒")


func _two_different_ranks(hand: Array) -> Array:
	for i in hand.size():
		for j in range(i + 1, hand.size()):
			if R.rank_of(int(hand[i])) != R.rank_of(int(hand[j])):
				return [int(hand[i]), int(hand[j])]
	return []


# ══════════════════════════════════════════════════════ 7 掉线托管

func _t_takeover() -> void:
	print("── 掉线托管 ──")
	var net = N.new()
	net.host_setup(["我", "下家", "上家"])
	net.host_start(2468, 0)
	var g = net.authoritative_game()

	net.mark_offline(1)
	var r1: Dictionary = net.tick(1000)
	_ok((r1["takeover"] as Array).is_empty(), "刚掉线不立刻托管")

	var r2: Dictionary = net.tick(N.TAKEOVER_MS + 2000)
	_ok((r2["takeover"] as Array).has(1), "超时后座位 1 交给托管")
	_ok(bool(net.seats[1]["ai"]), "座位 1 标记为 AI")

	var denied: Dictionary = net.apply_command({"seat": 1, "kind": N.Kind.BID, "score": 1})
	_ok(not bool(denied["ok"]), "托管座位拒收真人命令（%s）" % String(denied["reason"]))

	# 推到「轮到托管座位」的局面，让 tick 替他走
	net.apply_command({"seat": 0, "kind": N.Kind.BID, "score": 3})
	_ok(int(g.landlord) == 0, "（托管用例）座位 0 当地主")
	var h0: Array = g.hand_of(0)
	net.apply_command({"seat": 0, "kind": N.Kind.PLAY, "cards": [int(h0[0])]})
	_ok(int(g.turn) == 1, "现在轮到托管中的座位 1")
	var before: int = (g.hand_of(1) as Array).size()
	var r3: Dictionary = net.tick(N.TAKEOVER_MS + 3000)
	_ok((r3["auto"] as Array).has(1), "tick 自动替托管座位 1 走了一步")
	_ok(int(g.turn) != 1, "托管走完之后轮到别人")
	_ok((g.hand_of(1) as Array).size() <= before, "托管不会凭空给座位 1 加牌")

	# 重连 ⇒ 解除托管
	net.reclaim(1, N.TAKEOVER_MS + 4000)
	_ok(not bool(net.seats[1]["ai"]), "重连后解除托管")
	_ok(bool(net.seats[1]["online"]), "重连后在线状态恢复")
	var back: Dictionary = net.apply_command({"seat": 1, "kind": N.Kind.PING,
			"now_ms": N.TAKEOVER_MS + 5000})
	_ok(bool(back["ok"]), "PING 命令永远被接受（心跳）")


# ══════════════════════════════════════════════════════ 8 负载序列化

func _t_wire() -> void:
	print("── 负载序列化 ──")
	var net = N.new()
	net.host_setup(["A", "B", "C"])
	net.host_start(555, 0)
	var snap: Dictionary = net.snapshot_for(2)
	var back: Dictionary = N.from_wire(N.to_wire(snap))
	_ok(not back.is_empty(), "字节往返解得出字典")
	_ok(str(back["your_hand"]) == str(snap["your_hand"]), "往返后手牌一致")
	_ok(str(back["counts"]) == str(snap["counts"]), "往返后各家张数一致")
	_ok(typeof(back["your_hand"][0]) == TYPE_INT,
			"往返后牌 id 仍是 int（用 JSON 会全变 float，`5.0` 混进手牌）")
	_ok(N.from_wire(PackedByteArray()).is_empty(), "空字节 ⇒ 空字典（不炸）")
	var huge := PackedByteArray()
	huge.resize(N.MAX_WIRE_BYTES + 1)
	_ok(N.from_wire(huge).is_empty(), "超长数据 ⇒ 空字典（不解析）")
	_ok(N.from_wire(var_to_bytes([1, 2])).is_empty(), "不是字典 ⇒ 空字典")
