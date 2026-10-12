extends Node
## 斗地主 · 联机**牌桌适配层**自检（不需要网络、不需要内核）。
##
## 用法：`godot --headless --path <工程> --quit-after 9000 res://tools/verify_ddz_online_ui.tscn`
##
## ★ 为什么要单开一套：`verify_ddz_room` 只证明「协议对」；而**牌桌怎么显示联机局面**
##   是另一条容易错的路径 —— 它读的是「按座位裁剪的快照」，而单机版读的是完整局面。
##   这里把快照**直接喂**给牌桌，钉住四件事：
##     ① 我的手牌 = 快照给我的那一份；
##     ② 别人的手牌**只有长度**（全是占位 -1），⛔ 绝不出现别人的真牌；
##     ③ 座位方位随「我是谁」旋转（我在哪，哪就在屏幕正下方）；
##     ④ 座位名优先用玩家昵称。
##
## ⚠️ 这一套**不碰内核**（`skip_tunnel` 都不开）—— 只构造一个「已开局」的房间对象。

const ROOM := preload("res://scripts/net/ddz_room.gd")
const NET := preload("res://scripts/net/ddz_net.gd")
const G := preload("res://scripts/card/ddz/ddz_game.gd")
const TABLE := "res://scenes/doudizhu.tscn"

var _pass := 0
var _fail := 0


func _ok(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("  [FAIL] %s" % msg)


func _ready() -> void:
	print("═══ 斗地主联机牌桌适配层自检 ═══")
	await _run()
	print("═══ RESULT passed=%d failed=%d ═══" % [_pass, _fail])
	if _fail > 0:
		print("⚠️ 有失败项")
	get_tree().quit(1 if _fail > 0 else 0)


## 造一份「我的座位 = seat」的裁剪快照。
## ⚠️ 刻意让别人的手牌用 `-1` 之外的**真牌 id** 出现在断言里，
##   这样一旦适配层把别人的牌搬进来，断言就会红。
func _make_view(seat: int, mine: Array) -> Dictionary:
	var counts := [17, 17, 17]
	counts[seat] = mine.size()
	return {
		"seat": seat,
		"phase": int(G.Phase.PLAY),
		"turn": seat,
		"landlord": seat,
		"base_score": 3,
		"pass_streak": 0,
		"passed": [false, false, false],
		"bombs": 0,
		"spring": false,
		"winner": -1,
		"multiplier": 1,
		"counts": counts,
		"your_hand": mine.duplicate(),
		"last_play": {"seat": (seat + 1) % 3, "cards": [5, 6],
				"info": {"type": 0, "rank": 0, "len": 2}},
		"played": [5, 6],
		"bottom": [0, 1, 2],
		"log": ["x"],
		"seats": [{"name": "我", "online": true, "ai": false},
				{"name": "北京A", "online": true, "ai": false},
				{"name": "杭州B", "online": true, "ai": false}],
	}


func _run() -> void:
	var table: Control = load(TABLE).instantiate()
	add_child(table)
	await get_tree().process_frame
	await get_tree().process_frame

	# ── 造一个「对局中、我是座位 2」的房间（不连网、不起内核）──
	var room = ROOM.new()
	room.skip_tunnel = true
	room.net = NET.new()
	room.net.client_setup(2, "杭州B")
	table._room = room
	table._online.phase = table._online.Phase.PLAYING

	# 座位 2 的 17 张（用真牌 id 0~16，好认）
	var mine: Array = []
	for i in 17:
		mine.append(i)
	var v := _make_view(2, mine)
	table._apply_online_view(v)

	# ① 我是谁 / 我的手牌
	_ok(table._my_seat() == 2, "★ `_my_seat()` 跟着房主分配的座位走（得到 %d）" % table._my_seat())
	_ok(str(table.game.hand_of(2)) == str(mine), "我的手牌 = 快照给我的那一份")
	_ok(table.game.hand_of(2).size() == 17, "我的手牌 17 张")
	_ok(table.game.is_over() == false, "局面未结束")

	# ② 别人的手牌**只有长度**（全是占位）-1
	var others_ok := true
	var leaked: Array = []
	for s in [0, 1]:
		var h: Array = table.game.hand_of(s)
		if h.size() != 17:
			others_ok = false
		for c in h:
			if int(c) != -1:
				leaked.append(int(c))
	_ok(others_ok, "别人的手牌**长度正确**（17）—— 界面靠它画张数")
	_ok(leaked.is_empty(), "★★ 别人的手牌里**没有一张真牌**（全是占位 -1）")

	# ③ 方位旋转：我在哪，哪就在屏幕正下方
	_ok(table._dir_of(2) == table.DIR_DOWN, "★ 我（座位 2）画在**正下方**")
	_ok(table._dir_of(0) == table.DIR_RIGHT, "我的下家（座位 0）画在**右**")
	_ok(table._dir_of(1) == table.DIR_LEFT, "我的上家（座位 1）画在**左**")

	# ④ 座位名：用玩家昵称，而不是「你/下家/上家」
	_ok(table._seat_name(2).begins_with("杭州B"),
			"★ 座位名用玩家昵称（得到「%s」）" % table._seat_name(2))
	_ok(table._seat_name(0).begins_with("我"),
			"座位 0 用昵称（得到「%s」）" % table._seat_name(0))

	# ⑤ 出牌托盘：从快照的 last_play 填（联机不跑 `_do_play`）
	_ok(str(table._shown[(2 + 1) % 3]) == str([5, 6]), "出牌托盘由快照的 last_play 填出")
	_ok(table._passed == [false, false, false], "「不要」标记来自快照的 passed")

	# ⑥ 回合判断：轮到我就该给按钮
	_ok(table._is_human_turn(), "★ 快照说轮到我 ⇒ `_is_human_turn()` 为真")

	# ⑥b ★ 联机**不摆「托管」按钮** —— 它只改本地 `_auto`，房主不知情 ⇒ 牌局会卡住
	var has_auto := false
	for b in table._buttons():
		if String(b["id"]) == "auto":
			has_auto = true
	_ok(not has_auto, "★ 联机模式不出现「托管」按钮（本地托管会让房主那边的牌局卡住）")

	# ⑦ 占位期（还没收到快照）**不该**给任何操作
	table._online_view = {}
	var blank := G.new()
	table.game = blank
	_ok(not table._is_human_turn(), "★ 还没收到快照 ⇒ 不给操作（免得闪出一排点了没用的按钮）")

	# ⑧ 回到单机：一切复原（离线路径不受影响）
	table._leave_online()
	_ok(table._my_seat() == table.HUMAN_SEAT, "退出联机 ⇒ 座位回落到单机（HUMAN_SEAT）")
	_ok(table._dir_of(1) == table.DIR_RIGHT, "退出联机 ⇒ 方位映射回到单机口径")

	room.queue_free()
	table.queue_free()
	await get_tree().process_frame
