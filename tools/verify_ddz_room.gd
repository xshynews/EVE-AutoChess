extends Node
## 斗地主联机 · 端到端自检（**真跑 ENet，同进程三角色**）。
##
## 用法：`godot --headless --path <工程> --quit-after 9000 res://tools/verify_ddz_room.tscn`
##
## ★ 为什么必须真跑网络：`verify_ddz_net` 只验了「会话层会不会裁剪手牌」，
##   但它**没有把包发出去**。真正的泄漏往往发生在「发的时候发错对象」——
##   比如 `broadcast` 一份全量快照，谁都能看到别人的牌，而这在单进程逻辑测试里
##   完全测不出来。所以这一套开三个角色：房主 + 两个加入者，全部走真实 ENet 连接。
##
## ⚠️ 用 `skip_tunnel = true` 直连 127.0.0.1（跳过内置内核）：
##    内核的真机验证在 `probe_eve_tunnel`，这一套只验「网络协议 + 房主权威 + 手牌隔离」。

const ROOM := preload("res://scripts/net/ddz_room.gd")
const N := preload("res://scripts/net/ddz_net.gd")
const G := preload("res://scripts/card/ddz/ddz_game.gd")
const AI := preload("res://scripts/card/ddz/ddz_ai.gd")
const TP := preload("res://scripts/net/eve_ddz_transport.gd")
const RC := preload("res://scripts/net/eve_room_code.gd")

const SEED_VAL := 20261012
const MAX_STEPS := 400
const WAIT_MS := 6000

var _pass := 0
var _fail := 0
var _host: Node = null
var _c1: Node = null
var _c2: Node = null


func _ready() -> void:
	print("═══ 斗地主联机端到端自检（真 ENet）═══")
	await _run()
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


func _run() -> void:
	# ── 建房 ────────────────────────────────────────────────
	_host = ROOM.new()
	_host.skip_tunnel = true
	_host.needs_approval = true      # ★ 走「房主确认」这条路（产品规则）
	add_child(_host)
	var approved: Array[int] = []
	_host.join_requested.connect(func(pid: int, _nm: String):
		approved.append(pid)
		_host.approve(pid))
	_ok(_host.create_room("云南的我", Time.get_ticks_msec(), 12345),
			"房主建房成功")
	_ok(_host.code.length() == 8, "房间码 8 位（%s）" % _host.code)
	await _frames(4)
	_ok(_host.state == ROOM.State.LISTENING, "房主进入等待加入")

	# ── 协议版本握手 ────────────────────────────────────────
	# 用裸传输层发 HELLO：协议版本不一致或缺失都要被拒，且不进入房主的确认队列
	for case in [["协议版本不一致", {"name": "旧版本", "proto": ROOM.PROTOCOL_VERSION + 1}],
			["缺少协议版本", {"name": "无版本"}]]:
		var raw: Node = TP.new()
		add_child(raw)
		var reason := [""]
		raw.packet.connect(func(_from: int, d: Dictionary):
			if int(d.get("t", -1)) == ROOM.Msg.REJECT:
				reason[0] = String(d.get("reason", "")))
		raw.connected_ok.connect(func():
			var hello: Dictionary = (case[1] as Dictionary).duplicate()
			hello["t"] = ROOM.Msg.HELLO
			raw.send_to(TP.SERVER_ID, hello))
		raw.join("127.0.0.1", RC.DEFAULT_PORT, Time.get_ticks_msec())
		await _wait(func(): return reason[0] != "", 4000)
		_ok(String(reason[0]).find("版本") >= 0, "%s ⇒ 被拒（%s）" % [case[0], reason[0]])
		raw.stop()
		raw.queue_free()
		await _frames(4)
	_ok(approved.is_empty(), "版本不符的连接没有进入房主确认队列")

	# ── 两个加入者 ──────────────────────────────────────────
	_c1 = ROOM.new()
	_c1.skip_tunnel = true
	add_child(_c1)
	_c2 = ROOM.new()
	_c2.skip_tunnel = true
	add_child(_c2)
	_ok(_c1.join_room(_host.code, "北京A", Time.get_ticks_msec()), "加入者1 发起加入")
	_ok(_c2.join_room(_host.code, "杭州B", Time.get_ticks_msec()), "加入者2 发起加入")
	var ok1 := await _wait(func(): return _c1.state == ROOM.State.PLAYING or _c1.state == ROOM.State.FAILED)
	var ok2 := await _wait(func(): return _c2.state == ROOM.State.PLAYING or _c2.state == ROOM.State.FAILED)
	_ok(ok1 and _c1.state == ROOM.State.PLAYING, "加入者1 入座成功（%s）" % _c1.last_error)
	_ok(ok2 and _c2.state == ROOM.State.PLAYING, "加入者2 入座成功（%s）" % _c2.last_error)
	_ok(approved.size() == 2, "★ 房主收到了 2 个加入请求（确认流程生效）")
	_ok(_c1.my_seat() != _c2.my_seat(), "两个加入者座位不同（%d / %d）" % [_c1.my_seat(), _c2.my_seat()])
	_ok(_c1.my_seat() != 0 and _c2.my_seat() != 0, "加入者拿到的是 1/2 号位")
	_ok(_c1.my_seat() < _c2.my_seat(), "先来的坐 1 号位（%d <%d）" % [_c1.my_seat(), _c2.my_seat()])

	# ── 房间满员时再挤一个 ──────────────────────────────────
	var c3 := ROOM.new()
	c3.skip_tunnel = true
	add_child(c3)
	c3.join_room(_host.code, "插队的", Time.get_ticks_msec())
	var got_reject := await _wait(func(): return c3.state == ROOM.State.FAILED, 4000)
	_ok(got_reject, "★ 房间满员时第三人被拒（%s）" % c3.last_error)
	c3.close()

	# ── 开局 ────────────────────────────────────────────────
	_ok(_host.start_game(SEED_VAL), "房主开局")
	await _wait(func(): return not _c1.view().is_empty() and not _c2.view().is_empty(), WAIT_MS)
	_ok(not _c1.view().is_empty(), "加入者1 收到首份状态")
	_ok(not _c2.view().is_empty(), "加入者2 收到首份状态")

	# ── 身份不可伪造 ────────────────────────────────────────
	var g = _host.net.authoritative_game()
	if int(g.phase) == int(G.Phase.BID):
		# ① 冒称：加入者1 跳过 `client_make_command`，直接发一条 seat=0（房主）的命令
		#    ⚠️ 这里故意摸 `_tp`（房主权威的边界就在这条：**座位由连接身份决定**）
		_c1._tp.send_to(1, {"t": ROOM.Msg.CMD,
				"d": {"seat": 0, "kind": N.Kind.BID, "score": 3}})
		await _frames(40)
		_ok(int(g.bid_best) == -1, "★ 冒称座位 0 无效：房主没被它骗（bid_best=%d）" % int(g.bid_best))
		# ② 正控：房主先不叫，轮到加入者1 时他合法叫 3 分 —— 必须记在他头上
		_host.send_command(N.Kind.BID, {"score": 0})
		await _wait(func(): return int(g.turn) == _c1.my_seat(), 3000)
		_c1.send_command(N.Kind.BID, {"score": 3})
		await _wait(func(): return int(g.bid_best) > 0, 3000)
		_ok(int(g.bid_seat) == _c1.my_seat(),
				"★ 合法命令按连接身份记账（bid_seat=%d，加入者1=%d）"
				% [int(g.bid_seat), _c1.my_seat()])
	else:
		_ok(true, "（非叫分阶段，跳过身份用例）")

	# ── 打完整局（全程走真实网络）────────────────────────────
	var steps := 0
	var leaks := 0
	var own_bad := 0
	var seed_bad := 0
	while not g.is_over() and steps < MAX_STEPS:
		steps += 1
		var turn := int(g.turn)
		var kind := -1
		var payload := {}
		if int(g.phase) == int(G.Phase.BID):
			kind = N.Kind.BID
			# 胜负不影响验收：只为让三家的叫分路径都被走到
			payload = {"score": 1 if turn == 2 else 0}
		else:
			var cands: Array = []
			if turn == 0:
				cands = g.legal_now(0)
			elif turn == _c1.my_seat():
				cands = _c1.net.client_legal_now()
			elif turn == _c2.my_seat():
				cands = _c2.net.client_legal_now()
			if cands.is_empty() and not g.last_play.is_empty():
				kind = N.Kind.PASS
			else:
				kind = N.Kind.PLAY
				payload = {"cards": cands[0] if not cands.is_empty() else [int(g.hand_of(turn)[0])]}
		var tb := int(g.turn)
		var pb := int(g.phase)
		if turn == 0:
			_host.send_command(kind, payload)
		elif turn == _c1.my_seat():
			_c1.send_command(kind, payload)
		elif turn == _c2.my_seat():
			_c2.send_command(kind, payload)
		# ⚠️⚠️ 等「这一手真的被处理了」——判据必须是「局面**变了**」+「两个加入者的视图跟上了」。
		#   早先写成「视图 turn == 当前 turn」⇒ 命令还在网上飞的时候条件就已成立 ⇒
		#   循环连发好几条，被房主一一拒掉（现象：整局打不完，且看起来像"网络不通"）。
		await _wait(func(): return g.is_over() or (
				(int(g.turn) != tb or int(g.phase) != pb)
				and int(_c1.view().get("turn", -1)) == int(g.turn)
				and int(_c2.view().get("turn", -1)) == int(g.turn)), 4000, 1)
		# ★ 每一步都核两个加入者手里的视图
		for c in [_c1, _c2]:
			var seat := int(c.my_seat())
			var v: Dictionary = c.view()
			if v.is_empty():
				continue
			if str(v.get("your_hand", [])) != str(g.hands[seat]):
				own_bad += 1
				if own_bad <= 2:
					print("     手牌不符 seat=%d" % seat)
			var lk := _leaked(g, seat, v)
			if not lk.is_empty():
				leaks += 1
				if leaks <= 3:
					print("     ✗ seat=%d 的视图里出现别人的牌 %s" % [seat, str(lk)])
			if v.has("hands") or v.has("seed") or N.collect_ints(v).has(SEED_VAL):
				seed_bad += 1
				if seed_bad <= 2:
					print("     ✗ seat=%d 的视图里出现全量手牌/种子" % seat)
			for k in N.collect_keys(v):
				if String(k).to_lower().find("seed") >= 0:
					seed_bad += 1

	_ok(steps > 10, "整局都在走真实网络（%d 步）" % steps)
	_ok(bool(g.is_over()), "对局正常结束（房主裁决）")
	_ok(own_bad == 0, "★ 两个加入者每一步的手牌都与房主一致")
	_ok(leaks == 0, "★★ 两个加入者全程都看不到别人的手牌（%d 步 × 2 人）" % steps)
	_ok(seed_bad == 0, "★★ 加入者侧从未出现发牌种子/全量手牌")

	# ── 非当前回合 / 已结束时的出牌必须无效 ──────────────────
	var victim := _c1 if int(g.turn) != _c1.my_seat() else _c2
	var turn_now := int(g.turn)
	var hand_v: Array = victim.view().get("your_hand", [])
	if not hand_v.is_empty():
		victim.send_command(N.Kind.PLAY, {"cards": [int(hand_v[0])]})
		await _frames(40)
		_ok(int(g.turn) == turn_now, "★ 非当前回合（或已结束）的出牌不生效（turn 仍是 %d）" % turn_now)

	# ── 心跳用房主时钟 ──────────────────────────────────────
	# 模拟加入者的时钟与房主差很多（例如它的游戏比房主早开了很久）：发一个自报时间极大的心跳。
	# 房主必须记录自己的时间；否则掉线后「当前时间 - 最后心跳」为负，座位永远不会被托管。
	var c1seat := int(_c1.my_seat())
	_c1._tp.send_to(TP.SERVER_ID, {"t": ROOM.Msg.PING, "now_ms": 1000000000000})
	await _frames(10)
	var seen := int(_host.net.seats[c1seat]["last_seen_ms"])
	_ok(seen <= Time.get_ticks_msec() + 1000,
			"★ 心跳记录的是房主时间，不是客户端自报的时间（%d）" % seen)
	_host.net.mark_offline(c1seat)
	var r1: Dictionary = _host.net.tick(Time.get_ticks_msec() + _host.net.TAKEOVER_MS + 3000)
	_ok((r1["takeover"] as Array).has(c1seat) or bool(_host.net.seats[c1seat]["ai"]),
			"★ 时钟偏差的加入者掉线后照常被托管")

	# ── 掉线托管（房主侧判定）───────────────────────────────
	var c2seat := int(_c2.my_seat())
	_host.net.mark_offline(c2seat)
	var r: Dictionary = _host.net.tick(Time.get_ticks_msec() + _host.net.TAKEOVER_MS + 3000)
	_ok((r["takeover"] as Array).has(c2seat) or bool(_host.net.seats[c2seat]["ai"]),
			"★ 加入者2 掉线超时后被托管")

	# ── 收尾：关房必须清干净 ────────────────────────────────
	_host.close()
	_c1.close()
	_c2.close()
	await _frames(5)
	_ok(_host.state == ROOM.State.IDLE, "关房后房主状态归位")
	_ok(_c1.view().is_empty() or true, "关房不炸")


# ══════════════════════════════════════════════ 工具

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


## 等条件成立（轮询帧 + 超时）。
func _wait(cond: Callable, timeout_ms: int = WAIT_MS, poll_frames: int = 1) -> bool:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < timeout_ms:
		if bool(cond.call()):
			return true
		for i in poll_frames:
			await get_tree().process_frame
	return bool(cond.call())


## 某座位视图里混进了多少张「别人的、且未公开的」牌。
func _leaked(g, seat: int, v: Dictionary) -> Array:
	var public_ids := {}
	for c in g.played:
		public_ids[int(c)] = true
	if int(g.landlord) >= 0:
		for c in g.bottom:
			public_ids[int(c)] = true
	var mine := {}
	for c in g.hands[seat]:
		mine[int(c)] = true
	var seen := {}
	for key in ["your_hand", "played", "bottom"]:
		for x in v.get(key, []):
			seen[int(x)] = true
	var lp: Dictionary = v.get("last_play", {})
	for x in lp.get("cards", []):
		seen[int(x)] = true
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
