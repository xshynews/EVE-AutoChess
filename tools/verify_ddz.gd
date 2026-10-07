extends Node
## 斗地主 · 规则内核自检（**无 UI，纯逻辑全表**）。
##
## 用法：`godot --headless --path <工程> --quit-after 4000 res://tools/verify_ddz.tscn`
##
## ⚠️ 定这个自检的理由：斗地主的**牌型判定**是最容易写错、又最难靠人眼发现的地方
##    （错一条就会放行非法牌或漏判合法牌，实机里表现为「AI 打出怪牌」）。
##    所以这里把每种牌型都摆正例 + 反例，边界全部钉住。

const R := preload("res://scripts/card/ddz/ddz_rules.gd")
const G := preload("res://scripts/card/ddz/ddz_game.gd")
const AI := preload("res://scripts/card/ddz/ddz_ai.gd")
const T := preload("res://scripts/card/ddz/ddz_table.gd")
const E := preload("res://scripts/card/ddz/ddz_eval.gd")
const COIN := preload("res://scripts/card/ddz/ddz_coin.gd")

var _pass := 0
var _fail := 0


func _ready() -> void:
	print("═══ 斗地主规则自检 ═══")
	# ⚠️ 逐步计时：这套自检里 `_t_autoplay` / `_t_ab` 要跑几百局 AI 对打，
	#    加一步慢东西就会让整套从十几秒变成几分钟（实测踩过 212 秒）。
	_run_timed("_fix_tail", _fix_tail)
	_run_timed("_t_singles", _t_singles)
	_run_timed("_t_straights", _t_straights)
	_run_timed("_t_planes", _t_planes)
	_run_timed("_t_fours", _t_fours)
	_run_timed("_t_invalid", _t_invalid)
	_run_timed("_t_beats", _t_beats)
	_run_timed("_t_deal", _t_deal)
	_run_timed("_t_autoplay", _t_autoplay)
	_run_timed("_t_table", _t_table)
	_run_timed("_t_eval", _t_eval)
	_run_timed("_t_ai_l3", _t_ai_l3)
	_run_timed("_t_ab", _t_ab)
	_run_timed("_t_layout", _t_layout)
	_run_timed("_t_deal_anim", _t_deal_anim)
	print("═══ RESULT passed=%d failed=%d ═══" % [_pass, _fail])
	if _fail > 0:
		print("⚠️ 有失败项")
	# ★ 跑完就退：所有步骤都是**同步**跑完的，⛔ 别靠 `--quit-after` 收尾 ——
	#   之前挂 30000 帧空转 ⇒ 实测整套 4 秒的活在进程里耗掉 212 秒。
	get_tree().quit()


## 跑一步并打印耗时（定位「哪一步把整套自检拖慢了」的第一入口）
func _run_timed(name: String, cb: Callable) -> void:
	var t0 := Time.get_ticks_msec()
	cb.call()
	print("  [耗时] %-12s %6d ms" % [name, Time.get_ticks_msec() - t0])


func _ok(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("  FAIL  %s" % msg)


# ------------------------------------------------------------------ 工具

## 点数数组 → 牌 id 数组。
## ⚠️ 同一个点数出现多次时要给出**不同 id**（一副牌里一个点数只有 4 张），
##    否则分类里「张数」算不对 —— 那种自检是假的。
func _ids(ranks: Array) -> Array:
	var used := {}
	var out: Array = []
	for r in ranks:
		var rr := int(r)
		if rr >= 16:
			out.append(52 if rr == 16 else 53)
			continue
		var k := int(used.get(rr, 0))
		out.append((rr - 3) * 4 + k)
		used[rr] = k + 1
	return out


func _type_of(ranks: Array) -> int:
	var d := R.classify(_ids(ranks))
	return int(d.get("type", 0))


func _rank_of(ranks: Array) -> int:
	var d := R.classify(_ids(ranks))
	return int(d.get("rank", 0))


func _len_of(ranks: Array) -> int:
	var d := R.classify(_ids(ranks))
	return int(d.get("len", 0))


func _fix_tail() -> void:
	# 顺子边界：A 是 14，2 是 15 —— 别搞反
	_ok(R.rank_of(0) == 3, "id 0 的点数是 3（实际 %d）" % R.rank_of(0))
	_ok(R.rank_of(51) == 15, "id 51 的点数是 2（实际 %d）" % R.rank_of(51))
	_ok(R.rank_of(52) == 16 and R.rank_of(53) == 17, "小王 16 / 大王 17")
	_ok(R.full_deck().size() == 54, "一副 54 张")
	_ok(R.label_of(52) == "小王" and R.label_of(53) == "大王", "王的牌面文字")


# ------------------------------------------------------------------ 基本型

func _t_singles() -> void:
	print("[1] 单 / 对 / 三 / 炸")
	_ok(_type_of([3]) == R.Type.SINGLE, "单张")
	_ok(_rank_of([15]) == 15, "单张 2 的点数 = 15")
	_ok(_type_of([7, 7]) == R.Type.PAIR, "对子")
	_ok(_type_of([9, 9, 9]) == R.Type.TRIPLE, "三张")
	_ok(_type_of([10, 10, 10, 10]) == R.Type.BOMB, "炸弹")
	_ok(_rank_of([14, 14, 14, 14]) == 14, "AAAA 是 rank14 的炸弹")
	_ok(_type_of([16, 17]) == R.Type.ROCKET, "王炸")

	# 三带一 / 三带二
	_ok(_type_of([5, 5, 5, 8]) == R.Type.TRIPLE_ONE, "三带一")
	_ok(_rank_of([5, 5, 5, 8]) == 5, "三带一的主体是那个三张（不是带的牌）")
	_ok(_type_of([5, 5, 5, 8, 8]) == R.Type.TRIPLE_TWO, "三带二")
	_ok(_type_of([5, 5, 5, 8, 9]) == R.Type.INVALID, "三带两张**不同**点数 ⇒ 非法")


# ------------------------------------------------------------------ 顺子 / 连对

func _t_straights() -> void:
	print("[2] 顺子 / 连对")
	_ok(_type_of([3, 4, 5, 6, 7]) == R.Type.STRAIGHT, "34567 顺子")
	_ok(_len_of([3, 4, 5, 6, 7]) == 5, "顺子长度 = 张数")
	_ok(_type_of([10, 11, 12, 13, 14]) == R.Type.STRAIGHT, "10JQKA 顺子（封顶 A）")
	_ok(_rank_of([10, 11, 12, 13, 14]) == 14, "该顺子的主体点数 = A（14）")
	_ok(_type_of([3, 4, 5, 6]) == R.Type.INVALID, "4 张不够成顺子（最少 5）")
	_ok(_type_of([11, 12, 13, 14, 15]) == R.Type.INVALID,
			"★ JQKA2 ⇒ 非法（2 不许进顺子）")
	_ok(_type_of([12, 13, 14, 15, 16]) == R.Type.INVALID, "★ QKA2+小王 ⇒ 非法")
	_ok(_type_of([14, 15, 16, 17]) == R.Type.INVALID, "A + 2 + 双王 ⇒ 非法")

	_ok(_type_of([4, 4, 5, 5, 6, 6]) == R.Type.STRAIGHT_PAIR, "445566 连对")
	_ok(_len_of([4, 4, 5, 5, 6, 6]) == 3, "连对长度 = **对数**")
	_ok(_type_of([4, 4, 5, 5]) == R.Type.INVALID, "2 对不够成连对（最少 3 对）")
	_ok(_type_of([13, 13, 14, 14, 15, 15]) == R.Type.INVALID,
			"★ KKAA22 ⇒ 非法（2 不许进连对）")


# ------------------------------------------------------------------ 飞机

func _t_planes() -> void:
	print("[3] 飞机（含带牌）")
	_ok(_type_of([3, 3, 3, 4, 4, 4]) == R.Type.PLANE, "333444 飞机")
	_ok(_len_of([3, 3, 3, 4, 4, 4]) == 2, "飞机长度 = **组数**")
	_ok(_rank_of([3, 3, 3, 4, 4, 4]) == 4, "主体点数 = 最高那组")
	_ok(_type_of([3, 3, 3]) == R.Type.TRIPLE, "单组三张是 TRIPLE，不是飞机")

	# 带单：4k 张
	_ok(_type_of([3, 3, 3, 4, 4, 4, 5, 6]) == R.Type.PLANE_ONE, "飞机带两单")
	_ok(_type_of([3, 3, 3, 4, 4, 4, 5, 5, 6, 6]) == R.Type.PLANE_TWO, "飞机带两对")
	_ok(_type_of([3, 3, 3, 4, 4, 4, 5, 5, 6, 7]) == R.Type.INVALID,
			"带牌不成双 ⇒ 非法（5,5,6,7 凑不出两对）")

	# 三组：3 张连续 + 不连续的要被判非法
	_ok(_type_of([3, 3, 3, 4, 4, 4, 5, 5, 5]) == R.Type.PLANE, "333444555 三组飞机")
	_ok(_type_of([3, 3, 3, 4, 4, 4, 6, 6, 6]) == R.Type.INVALID,
			"★ 3344666 断了 ⇒ 不是飞机")
	_ok(_type_of([13, 13, 13, 14, 14, 14]) == R.Type.PLANE, "KKKAAA 飞机（封顶 A）")
	_ok(_type_of([14, 14, 14, 15, 15, 15]) == R.Type.INVALID,
			"★ AAA222 ⇒ 非法（2 不许进飞机主体）")


# ------------------------------------------------------------------ 四带二

func _t_fours() -> void:
	print("[4] 四带二")
	_ok(_type_of([7, 7, 7, 7, 3, 9]) == R.Type.FOUR_TWO_SINGLE, "四带两单")
	_ok(_rank_of([7, 7, 7, 7, 3, 9]) == 7, "主体 = 那个四张")
	_ok(_type_of([7, 7, 7, 7, 3, 3, 9, 9]) == R.Type.FOUR_TWO_PAIR, "四带两对")
	_ok(_type_of([7, 7, 7, 7, 3, 3, 9, 8]) == R.Type.INVALID,
			"带牌凑不成两对 ⇒ 非法")
	# 四个二 / 四个王不算炸（王只有一张大王一张小王）
	_ok(_type_of([15, 15, 15, 15]) == R.Type.BOMB, "2222 是炸弹")


# ------------------------------------------------------------------ 非法组合

func _t_invalid() -> void:
	print("[5] 非法组合（这些必须判 {}）")
	_ok(_type_of([3, 5]) == R.Type.INVALID, "3+5 两张不同点")
	_ok(_type_of([3, 3, 5]) == R.Type.INVALID, "对 + 单")
	_ok(_type_of([3, 4, 5]) == R.Type.INVALID, "三张不同点")
	_ok(_type_of([16]) == R.Type.SINGLE, "单张小王（这个是合法的）")
	_ok(R.classify([]).is_empty(), "空数组 ⇒ {}")
	# ⚠️ 这里**故意不测「两张小王」**：它需要构造 id 52 出现两次，
	#    而一副牌里小王只有一张 —— 这种输入在真实路径下**不可达**。
	#    `classify()` 的职责是「按点数判定牌型」，不替发牌层做 id 唯一性校验
	#    （加了会让 AI 每次判型都多扫一遍，收益为零）。
	#    ⇒ 「发牌无重复」这条不变量放在 `_t_deal()` 里验才是对的位置。
	_ok(true, "（跳过：重复 id 由发牌层保证，见 _t_deal）")


# ------------------------------------------------------------------ 比较

func _t_beats() -> void:
	print("[6] 大小比较")
	var single_a := R.classify(_ids([14]))         # 单 A
	var single_3 := R.classify(_ids([3]))
	var pair_5 := R.classify(_ids([5, 5]))
	var pair_3 := R.classify(_ids([3, 3]))
	var bomb_4 := R.classify(_ids([4, 4, 4, 4]))
	var bomb_9 := R.classify(_ids([9, 9, 9, 9]))
	var rocket := R.classify(_ids([16, 17]))
	var st5 := R.classify(_ids([3, 4, 5, 6, 7]))
	var st6 := R.classify(_ids([3, 4, 5, 6, 7, 8]))
	var st5b := R.classify(_ids([4, 5, 6, 7, 8]))

	_ok(R.beats(single_a, single_3), "单 A 压单 3")
	_ok(not R.beats(single_3, single_a), "单 3 压不过单 A")
	_ok(R.beats(pair_5, pair_3), "对 5 压对 3")
	_ok(not R.beats(pair_3, pair_5), "对 3 压不过对 5")
	_ok(not R.beats(single_a, pair_3), "★ 单张压不过对子")
	_ok(not R.beats(pair_5, single_3), "★ 对子不能压单张")

	_ok(R.beats(bomb_4, single_a), "★ 炸弹压一切非炸弹（包括单 A）")
	_ok(R.beats(bomb_9, bomb_4), "大炸压小炸")
	_ok(not R.beats(bomb_4, bomb_9), "小炸压不过大炸")
	_ok(R.beats(rocket, bomb_9), "★ 王炸压炸弹")
	_ok(not R.beats(bomb_9, rocket), "炸弹压不过王炸")

	_ok(R.beats(st5b, st5), "同长顺子比最大牌")
	_ok(not R.beats(st5, st5b), "小的压不过大的")
	_ok(not R.beats(st6, st5), "★ 长度不同的顺子不能比（6 张压不过 5 张）")
	_ok(not R.beats(st5, st6), "★ 长度不同的顺子不能比（5 张压不过 6 张）")

	_ok(not R.beats({}, pair_3) and not R.beats(pair_3, {}), "空牌型永远不压")


# ------------------------------------------------------------------ 发牌

func _t_deal() -> void:
	print("[7] 发牌（同一 seed 必须发同一副牌）")
	var g = G.new()
	g.start(20261006)
	_ok((g.hands[0] as Array).size() == 17, "座位 0 拿 17 张")
	_ok((g.hands[1] as Array).size() == 17, "座位 1 拿 17 张")
	_ok((g.hands[2] as Array).size() == 17, "座位 2 拿 17 张")
	_ok((g.bottom as Array).size() == 3, "底牌 3 张")

	# ★ 一副牌 54 张必须**齐全且不重复** —— 这条只在发牌层能验
	var all: Array = []
	for s in 3:
		all.append_array(g.hands[s])
	all.append_array(g.bottom)
	all.sort()
	var uniq := {}
	for c in all:
		uniq[int(c)] = true
	_ok(all.size() == 54, "三家 + 底牌共 54 张（实际 %d）" % all.size())
	_ok(uniq.size() == 54, "★ 无重复牌（唯一 id 数 %d）" % uniq.size())
	_ok(int(all[0]) == 0 and int(all[53]) == 53, "★ 正好是 0~53 一副整牌")

	# ★ 可复现：同 seed 两局发到完全一样的牌（P2P 同步的前提）
	var g2 = G.new()
	g2.start(20261006)
	_ok(str(g.hands) == str(g2.hands) and str(g.bottom) == str(g2.bottom),
			"★ 同一 seed ⇒ 发出同一副牌（可复现）")
	var g3 = G.new()
	g3.start(20261007)
	_ok(str(g.hands) != str(g3.hands), "不同 seed ⇒ 不同的牌")


# ------------------------------------------------------------------ 自动对战

## 让 AI 互打 N 局。**这是 AI 的「能跑通」验收**：
##   不卡死、不出非法牌、每局都能分出胜负。
func _t_autoplay() -> void:
	print("[8] 自动对战 200 局（AI 互打）")
	var ll_win := 0
	var far_win := 0
	var stuck := 0
	var illegal := 0
	var events := 0
	const N := 200
	for k in N:
		var g = G.new()
		g.start(90000 + k)
		var guard := 0
		while not g.is_over() and guard < 4000:
			guard += 1
			var seat: int = int(g.turn)
			if int(g.phase) == int(G.Phase.BID):
				g.bid(seat, AI.bid_score(g, seat))
				continue
			var mv: Dictionary = AI.choose(g, seat)
			if mv.has("cards"):
				var r: Dictionary = g.play(seat, mv["cards"])
				if not bool(r.get("ok", false)):
					illegal += 1
					if illegal <= 3:
						print("    ✗ 非法出牌：%s 出 %s ⇒ %s"
								% [str(seat), str(mv["cards"]), String(r.get("reason", ""))])
					break
			else:
				var r2: Dictionary = g.pass_turn(seat)
				if not bool(r2.get("ok", false)):
					illegal += 1
					if illegal <= 3:
						print("    ✗ 非法过牌：座位 %d ⇒ %s"
								% [seat, String(r2.get("reason", ""))])
					break
		if not g.is_over():
			stuck += 1
			if stuck <= 2:
				print("    ✗ 第 %d 局跑不完（guard=%d）" % [k, guard])
		else:
			events += g.log_lines.size()
			if g.landlord_won():
				ll_win += 1
			else:
				far_win += 1
	_ok(stuck == 0, "★ %d 局全部能正常结束（卡死 %d 局）" % [N, stuck])
	_ok(illegal == 0, "★ 全程没有非法出牌（%d 次）" % illegal)
	# 胜率不该是一边倒 —— 一边倒说明 AI 有硬伤（比如农民从不配合）
	var rate := float(ll_win) / float(N)
	_ok(rate > 0.15 and rate < 0.85,
			"★ 地主胜率在合理区间（%.0f%%，200 局）" % (rate * 100.0))
	print("  地主 %d 胜 / 农民 %d 胜 · 平均每局 %.0f 条事件" % [ll_win, far_win, float(events) / N])


# ------------------------------------------------------------------ 牌桌交互

## 牌桌（**你打座位 0**）的交互自检。
##
## ⚠️⚠️ 为什么这一步必须存在：牌桌是目前**唯一「玩家直接操作」**的模块，
##    而它的三类 bug（按钮画的位置和能点的区域不一致 / 点了没反应 /
##    操作了但状态没变）**一个都不抛异常** —— 只靠「跑一遍没报错」永远查不出来。
##    ⇒ 这里一律走**真实点击通道**（构造 MouseButton 喂给 `_gui_input`），
##      ⛔ 不直接调 `_on_button("play")`：直接调就把坐标与命中判定整条绕过去了。
func _t_table() -> void:
	print("[9] 牌桌交互（你打座位 0 · 走真实点击通道）")
	var t: Control = T.new()
	add_child(t)
	# ⚠️ 必须先定尺寸再开局：所有坐标都是按 `size` 算的
	t.size = Vector2(1920, 1080)
	# 固定 seed ⇒ 牌局可复现（红了能照着同一副牌重放）
	t.call("_new_game", 20261006)
	var g = t.get("game")

	# ── ① 开局：轮到玩家叫分 ──
	_ok(int(g.turn) == 0, "开局轮到座位 0（玩家）")
	_ok(bool(t.call("_is_human_turn")), "开局是玩家的回合")
	var ids := _btn_ids(t)
	_ok(ids.has("bid0") and ids.has("bid3"), "叫分按钮齐（%s）" % str(ids))
	_ok(not ids.has("play"), "叫分阶段不摆「出牌」按钮")

	# ── ② 点「3 分」⇒ 玩家当地主 ──
	_click_btn(t, "bid3")
	_ok(int(g.phase) == int(G.Phase.PLAY), "叫 3 分后进入出牌阶段")
	_ok(int(g.landlord) == 0, "★ 玩家（座位 0）当地主")
	_ok((g.hand_of(0) as Array).size() == 20,
			"地主拿 20 张（实际 %d）" % (g.hand_of(0) as Array).size())

	# ── ③ 被拒的操作**必须给理由**，⛔ 不许静默 ──
	var h0: int = (g.hand_of(0) as Array).size()
	_click_btn(t, "pass")
	_ok((g.hand_of(0) as Array).size() == h0, "首出「不要」不改手牌")
	_ok(String(t.get("_toast")).contains("不能不要"),
			"★ 首出「不要」被拒时说明理由（实际「%s」）" % String(t.get("_toast")))
	_click_btn(t, "play")
	_ok((g.hand_of(0) as Array).size() == h0, "没选牌点「出牌」不改手牌")
	_ok(String(t.get("_toast")).contains("选牌"),
			"★ 没选牌时说明「先选牌」（实际「%s」）" % String(t.get("_toast")))

	# ── ④ 点手牌 = 选中 / 再点 = 取消 ──
	_click_card(t, 0)
	_ok((t.get("_sel") as Array).size() == 1, "点第一张手牌 ⇒ 选中 1 张")
	_click_card(t, 0)
	_ok((t.get("_sel") as Array).is_empty(), "再点同一张 ⇒ 取消选中")

	# ── ⑤ 「提示」给的牌必须**真的能出** ──
	_click_btn(t, "hint")
	var sel: Array = t.get("_sel")
	_ok(not sel.is_empty(), "★ 「提示」给出了一手牌")
	_ok(not R.classify(sel).is_empty(), "提示的那手是合法牌型")
	_ok(bool(g.last_play.is_empty() or R.beats(R.classify(sel), g.last_play["info"])),
			"★ 提示的牌**真的压得过**上一手（提示骗人 ⇒ 玩家一点出牌就被拒）")

	# ── ⑥ 出牌 ⇒ 手牌真的减少 + 记录里真的有这条 ──
	var n0: int = (g.hand_of(0) as Array).size()
	var nplay: int = sel.size()
	_click_btn(t, "play")
	var n1: int = (g.hand_of(0) as Array).size()
	_ok(n1 == n0 - nplay, "★ 出牌后手牌真的少了 %d 张（%d → %d）" % [nplay, n0, n1])
	_ok((t.get("_sel") as Array).is_empty(), "出牌后清空选中")
	var feed: Array = t.get("_feed")
	_ok(feed.size() >= 3, "对局记录有内容（%d 条）" % feed.size())
	# ⚠️ 记录里带角色后缀（「你（地主） 出 3（单）」）⇒ 只钉「开头是你 + 有『出』」，
	#    ⛔ 别钉整串 —— 那样改一下角色文案就会误红（不是 bug，是断言写太死）。
	var last_line: String = String(feed[feed.size() - 1])
	_ok(last_line.begins_with("你") and last_line.contains(" 出 "),
			"★ 最后一条记录是「你 出 …」（实际「%s」）" % last_line)
	_ok(int(g.turn) == 1, "出完轮到下家（座位 1）")

	# ── ⑦ 不是玩家的回合 ⇒ **不摆操作按钮** ──
	#    （工程红线 9：别摆「看着能点、点了没反应」的东西）
	var ids2 := _btn_ids(t)
	_ok(not ids2.has("play") and not ids2.has("pass") and not ids2.has("hint"),
			"★ 不是你的回合 ⇒ 不出牌按钮（实际 %s）" % str(ids2))
	_ok(ids2.has("back") and ids2.has("auto"), "返回 / 托管 一直在（这两个任何时候可用）")
	_click_card(t, 0)
	_ok((t.get("_sel") as Array).is_empty(), "不是你的回合点手牌不选中")

	# ── ⑧ AI 自己会走 ──
	var hand1_before: int = (g.hand_of(1) as Array).size()
	for _k in 6:
		t.call("_process", 5.0)
	var moved: bool = (g.hand_of(1) as Array).size() != hand1_before \
			or (t.get("_feed") as Array).size() > feed.size()
	_ok(moved, "★ 推进若干步后 AI 真的动过（记录 %d → %d 条）"
			% [feed.size(), (t.get("_feed") as Array).size()])

	# ── ⑨ 轮到玩家**必须停住等** —— 用户报的「太快看不清」就是这条的反面 ──
	var guard := 0
	while not bool(t.call("_is_human_turn")) and not bool(g.is_over()) and guard < 200:
		guard += 1
		t.call("_process", 5.0)
	if not bool(g.is_over()):
		_ok(bool(t.call("_is_human_turn")), "★ 循环推进后停在玩家回合（真人来得及操作）")
		var ln_before: int = (t.get("_feed") as Array).size()
		for _j in 20:
			t.call("_process", 5.0)     # 玩家一直不动 ⇒ 桌面不该有任何变化
		_ok((t.get("_feed") as Array).size() == ln_before,
				"★★ 轮到玩家后**你不动它就不推进**（记录保持 %d 条）" % ln_before)
		_ok(_btn_ids(t).has("hint"), "玩家回合里操作按钮可用")

	# ── ⑩ 收尾：把测试用的牌桌摘掉（它的 `_process` 还会继续跑）──
	t.queue_free()
	print("  牌桌交互检查完成（点击全走 _gui_input 真实通道）")


## 当前屏幕上全部按钮的 id 列表
func _btn_ids(t: Node) -> Array:
	var out: Array = []
	var btns: Array = t.call("_buttons")
	for b in btns:
		out.append(String(b["id"]))
	return out


## 走**真实点击通道**：构造一个左键按下事件喂给控件。
##
## ⚠️ 不直接调 `_on_button()` —— 「按钮画在哪」和「哪块区域能点」是两件事，
##    直接调函数会把坐标与命中判定整条绕过去，而那正是最容易错的地方。
func _click_at(t: Control, p: Vector2) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = p
	t._gui_input(ev)


## 点某个按钮的**中心**（中心由 `_buttons()` 自己算，⛔ 不另写坐标）
func _click_btn(t: Control, id: String) -> void:
	var btns: Array = t.call("_buttons")
	for b in btns:
		if String(b["id"]) == id:
			var r: Rect2 = b["rect"]
			_click_at(t, r.position + r.size * 0.5)
			return
	_ok(false, "按钮「%s」根本不存在" % id)


## 点第 i 张手牌的**中心**。矩形取自 `_hand_card_rect()` —— 与 `_draw()` 同一个来源。
func _click_card(t: Control, i: int) -> void:
	var g = t.get("game")
	var my: Array = g.hand_of(0)
	if my.is_empty():
		_ok(false, "手牌是空的，点不了第 %d 张" % i)
		return
	var r: Rect2 = t.call("_hand_card_rect", i, my.size(), int(my[i]))
	_click_at(t, r.position + r.size * 0.5)


# ══════════════════════════════════════════════════════════════════
#  评估内核（手数 / 记牌）
# ══════════════════════════════════════════════════════════════════

## `min_plays` 的**正确性 + 性能**。
##
## ⚠️ 性能断言不是洁癖：第一版我用了「枚举所有出牌」的全量 DFS，
##    实测 **361 ms/次、记忆表涨到 166 万条** —— 拿去做 AI 决策会当场卡死。
##    换成「只分支最小那张牌能进的牌组」后降到 0.16 ms。这条断言就是钉住它的。
func _t_eval() -> void:
	print("[10] 手数评估 min_plays（正确性 + 性能哨）")
	var cases := [
		[[3], 1], [[3, 3], 1], [[3, 3, 3], 1], [[3, 3, 3, 3], 1],
		[[3, 4, 5, 6, 7], 1], [[3, 3, 4, 4, 5, 5], 1],
		[[3, 3, 3, 4, 4, 4], 1], [[3, 3, 3, 4], 1], [[3, 3, 3, 4, 4], 1],
		[[16, 17], 1],
		# ⚠️ `3333 + 小王 + 大王` 是**合法的「四带两单」**（1 手）——
		#    第一次我把期望写成 2，是**我的期望错了**，DP 是对的（`classify` 也认）。
		#    ⚠️ 但 `ddz_plays._all_shapes` **不生成**四带二 ⇒ AI 永远不会这么打（不会浪费王）。
		[[16, 17, 3, 3, 3, 3], 1],
		[[3, 5, 7, 9, 11], 5],
		[[3, 4, 5, 6, 7, 9, 11, 13], 4],
		[[14, 14, 15], 2],                       # 对 A + 单 2 ⇒ 2 手
	]
	for c in cases:
		var got: int = E.min_plays(_ids(c[0]))
		_ok(got == int(c[1]), "min_plays %s = %d（期望 %d）" % [str(c[0]), got, int(c[1])])

	# ── 性能 + 记忆表体积哨 ──
	E.reset_stats()
	var t0 := Time.get_ticks_msec()
	for k in 200:
		var g = G.new()
		g.start(5000 + k)
		E.min_plays(g.hand_of(0))
	var dt := Time.get_ticks_msec() - t0
	var memo_n := int(E.stats()["memo"])
	_ok(dt < 3000, "★ 200 副起手算完 < 3 秒（实测 %d ms，平均 %.2f ms/副）" % [dt, float(dt) / 200.0])
	_ok(memo_n < 100000, "★ 记忆表条数受控（实测 %d 条）" % memo_n)
	print("  200 副 %d ms（%.2f ms/副）· 记忆表 %d 条 · 预算用尽 %d 次"
			% [dt, float(dt) / 200.0, memo_n, int(E.stats()["aborts"])])

	# ── 记牌：把外面的高牌都出掉之后，我这张就该是「没人能压」 ──
	var g2 = G.new()
	g2.start(4242)
	var cnt: Array = E.unseen_counts(g2, 0)
	_ok(int(cnt[E.IDX_BJ]) == 1, "开局外面还剩 1 张大王（实际 %d）" % int(cnt[E.IDX_BJ]))
	var my_bj := 53 if (g2.hand_of(0) as Array).has(53) else -1
	if my_bj < 0:
		# 大王不在我手里 ⇒ 记牌器要能看见它「在我不知道的地方」
		_ok(int(cnt[E.IDX_BJ]) == 1, "大王在别人手里 ⇒ 记牌器仍算作「外面剩 1 张」")
	_ok(not E.is_top([52], cnt) if int(cnt[E.IDX_BJ]) >= 1 else true,
			"外面还有大王 ⇒ 小王不是「没人能压」")
	# 把大王「打出去」之后，小王就该是无敌的
	var g3 = G.new()
	g3.start(4242)
	g3.played.append(53)
	var cnt3: Array = E.unseen_counts(g3, 0)
	if not (g3.hand_of(0) as Array).has(53):
		_ok(E.is_top([52], cnt3), "★ 大王已出 ⇒ 小王变成「没人能压」（记牌器生效）")
	else:
		_ok(true, "（大王在我手里，跳过该分支）")


# ══════════════════════════════════════════════════════════════════
#  L3 的规则（**确定性**断言：每条规则单独摆一个局面，只差那一条）
# ══════════════════════════════════════════════════════════════════

## 摆一个对局局面。`hands` = 三家的牌 id 数组。
##
## ⚠️⚠️ **夹具自检**：同一个牌 id 绝不能同时出现在两家手里 ——
##    那会让记牌器算出**负计数**，`is_top` / `min_plays` 跟着莫名其妙地错，
##    而且**一点报错都没有**（这类「夹具本身错了」的假通过最难查）。
##    ⇒ 每次摆局面都先查一遍，撞车就当场红。
func _mk(hands: Array, landlord: int, turn: int, last_seat: int, last_cards: Array):
	var seen := {}
	var dup := -1
	for h in hands:
		for c in h:
			if seen.has(int(c)):
				dup = int(c)
			seen[int(c)] = true
	for c in last_cards:
		if seen.has(int(c)):
			dup = int(c)
	if dup >= 0:
		_ok(false, "★ 夹具自检：牌 id %d 重复出现（会污染记牌器，用例必须换点数）" % dup)
	var g = G.new()
	g.start(1)
	g.hands = hands
	g.landlord = landlord
	g.phase = G.Phase.PLAY
	g.turn = turn
	g.pass_streak = 0
	if last_cards.is_empty():
		g.last_play = {}
	else:
		g.last_play = {"seat": last_seat, "cards": last_cards,
				"info": R.classify(last_cards)}
	return g


## L3 的规则 —— **每条规则单独摆一个局面，只差那一条**。
##
## ⚠️ 摆局面的两个坑（都踩过）：
##   ① 同一个点数不能出现在两家手里（id 撞车 ⇒ 记牌器负计数）⇒ 见 `_mk` 的自检；
##   ② 被「压」的那张牌**不能同时在出牌者手里**（否则他的手牌数多算一张，
##      而「对手剩几张」是残局规则的关键输入）。
func _t_ai_l3() -> void:
	print("[11] L3 规则（农民配合 / 顶牌 / 不拆牌 / 残局）")

	# ── ① 农民对队友：**便宜就跟一手**（实测推翻了「一律让牌」）──
	#    地主 0（5 张）· 农民 1 出单 5 · 农民 2 手上 [9,3,4] ⇒ 只有 9 能压，且便宜 ⇒ 跟
	var g = _mk([_ids([11, 12, 13, 14, 15]), _ids([6, 7, 10]), _ids([9, 3, 4])],
			0, 2, 1, _ids([5]))
	_ok((g.legal_now(2) as Array).size() > 0, "前置：农民 2 确实有牌能压")
	var mv: Dictionary = AI.choose(g, 2)
	var p1: Array = mv.get("cards", [])
	_ok(p1.size() == 1 and R.rank_of(int(p1[0])) == 9,
			"★ 农民对队友跟**便宜**的一手（实际 %s）" % _cards_text(p1))

	# ── ①b 但**贵就不跟**：只有 2/王 能压 ⇒ 让牌，把大牌留着 ──
	var gb = _mk([_ids([11, 12, 13, 14, 15]), _ids([6, 7, 10]), _ids([17, 3, 4])],
			0, 2, 1, _ids([5]))
	var mvb: Dictionary = AI.choose(gb, 2)
	_ok(not mvb.has("cards"), "★ 只有 2/王 能压队友 ⇒ 让牌（实际 %s）"
			% str(mvb.get("cards", [])))

	# ── ② 例外①：贵，但**压完我就只剩 1 手** ⇒ 要压 ──
	var g2 = _mk([_ids([11, 12, 13, 14]), _ids([6, 7, 10]), _ids([17, 3])],
			0, 2, 1, _ids([5]))
	var mv2: Dictionary = AI.choose(g2, 2)
	var p2: Array = mv2.get("cards", [])
	_ok(p2.size() == 1 and R.rank_of(int(p2[0])) == 17,
			"★ 压一手就能走完 ⇒ 花大王也压（例外①，实际 %s）" % _cards_text(p2))

	# ── ③ 例外②：地主只剩 2 张 + 我这张「没人能压」⇒ 抢回牌权 ──
	var g3 = _mk([_ids([11, 12]), _ids([6, 7, 10]), _ids([17, 3, 4])],
			0, 2, 1, _ids([5]))
	var mv3: Dictionary = AI.choose(g3, 2)
	var p3: Array = mv3.get("cards", [])
	_ok(p3.size() == 1 and R.rank_of(int(p3[0])) == 17,
			"★ 地主将赢 ⇒ 用大王抢回牌权（例外②，实际 %s）" % _cards_text(p3))

	# ── ④ 顶牌：我是地主下家 ⇒ 用大牌封堵，⛔ 不是甩个最小的 ──
	#    地主 0 出单 3 · 农民 1 有 [4, 9, K] ⇒ 应该出 K
	var g4 = _mk([_ids([10, 11, 12]), _ids([4, 13, 9]), _ids([5, 6, 7, 8])],
			0, 1, 0, _ids([3]))
	var mv4: Dictionary = AI.choose(g4, 1)
	var p4: Array = mv4.get("cards", [])
	_ok(p4.size() == 1 and R.rank_of(int(p4[0])) >= 13,
			"★ 地主下家要顶牌（出 K 而不是 4；实际 %s）" % _cards_text(p4))

	# ── ⑤ 不拆牌：不为出一张单去拆对子 ──
	var g5 = _mk([_ids([10, 11, 12]), _ids([8, 8, 3, 5, 7]), _ids([13, 14])],
			0, 1, -1, [])
	var mv5: Dictionary = AI.choose(g5, 1)
	var p5: Array = mv5.get("cards", [])
	var broke_pair: bool = p5.size() == 1 and R.rank_of(int(p5[0])) == 8
	_ok(not broke_pair, "★ 不拆对子出单张（实际 %s）" % _cards_text(p5))

	# ── ⑥ 残局：对手只剩 1 张时 **别出单张**（他一张就能走）──
	var g6 = _mk([_ids([6]), _ids([3, 8, 8]), _ids([13, 14])], 0, 1, -1, [])
	var mv6: Dictionary = AI.choose(g6, 1)
	var p6: Array = mv6.get("cards", [])
	_ok(p6.size() == 2, "★ 对手剩 1 张 ⇒ 不出单张（实际 %s）" % _cards_text(p6))

	# ── ⑦ 地主平时不动炸弹（对面还有 3~4 张，不急）──
	var g7 = _mk([_ids([3, 4, 5, 6]), _ids([7, 8, 11]), _ids([9, 9, 9, 9, 10])],
			2, 2, 0, _ids([13]))
	var mv7: Dictionary = AI.choose(g7, 2)
	_ok(not mv7.has("cards"), "★ 平时不动炸弹（实际 %s）" % str(mv7.get("cards", [])))

	# ── ⑧ 但对手将赢时敢炸（手上只剩炸弹 ⇒ 炸完就走完）──
	var g8 = _mk([_ids([13, 4]), _ids([5, 6, 7, 8]), _ids([9, 9, 9, 9])],
			0, 2, 0, _ids([3]))
	var mv8: Dictionary = AI.choose(g8, 2)
	_ok(mv8.has("cards"), "★ 对手只剩 2 张 ⇒ 敢动炸弹（实际 %s）"
			% str(mv8.get("cards", [])))


func _cards_text(cards: Array) -> String:
	var parts: Array[String] = []
	for c in cards:
		parts.append(R.label_of(int(c)))
	return " ".join(parts)


# ══════════════════════════════════════════════════════════════════
#  L3 vs L2 强度对拍（**同一副牌、身份互换**）
# ══════════════════════════════════════════════════════════════════

## ★ 这条是「新 AI 到底强了多少」的**唯一硬证据**。
##
## ⚠️ 别写成「全 L3 vs 全 L2」—— 那样两边三家 AI 相同，谁赢只由牌决定。
##    正确做法 = 同一副牌打两次、**身份互换**：
##      局 A：L3 当地主 + L2 当农民
##      局 B：L2 当地主 + L3 当农民
##    牌的好坏被配对消掉，剩下的差异就是 AI 的差异。
## ⚠️ 叫分两边共用 ⇒ 两局地主一定是同一家（变量控制住）。
## ⚠️ 种子固定 ⇒ **结果可复现**（不是统计抽签，红了就是真的退步了）。
func _t_ab() -> void:
	print("[12] L3 vs L2 同牌对打（身份互换）")
	E.reset_stats()
	var n := 100
	var l3 := 0
	var l2 := 0
	var ll3 := 0        # L3 当地主赢的局数
	var stuck := 0
	for k in n:
		var sv := 80000 + k
		var ra := _duel(sv, true)
		var rb := _duel(sv, false)
		if ra < 0 or rb < 0:
			stuck += 1
			continue
		ll3 += ra
		if ra == 1:
			l3 += 1
		else:
			l2 += 1
		if rb == 0:
			l3 += 1
		else:
			l2 += 1
	var tot := maxi(1, l3 + l2)
	var rate := float(l3) / float(tot)
	_ok(stuck == 0, "★ %d 副全部跑完（卡死 %d）" % [n, stuck])
	_ok(rate >= 0.54, "★★ L3 明显强于 L2：胜率 %.1f%%（阈值 54%%，%d 局）"
			% [rate * 100.0, tot])
	print("  L3 胜 %d / L2 胜 %d ⇒ **L3 %.1f%%**" % [l3, l2, rate * 100.0])
	print("  L3 当地主 %.0f%%（%d/%d）· L3 当农民 %.0f%%（%d/%d）"
			% [100.0 * ll3 / n, ll3, n, 100.0 * (l3 - ll3) / n, l3 - ll3, n])
	print("  ⏳ 遗留：地主整体胜率仍偏高（约 7 成）⇒ 农民配合还有很大提升空间")
	print("  [诊断] 对打期间 min_plays 预算用尽 %d 次 · 记忆表 %d 条"
			% [int(E.stats()["aborts"]), int(E.stats()["memo"])])


## 返回 1 = L3 队赢 · 0 = L2 队赢 · -1 = 跑不完
func _duel(seed_v: int, l3_as_landlord: bool) -> int:
	var g = G.new()
	g.start(seed_v)
	var guard := 0
	while not g.is_over() and guard < 3000:
		guard += 1
		var seat: int = int(g.turn)
		if int(g.phase) == int(G.Phase.BID):
			g.bid(seat, AI.bid_score(g, seat))
			continue
		var seat_is_l3: bool = (seat == int(g.landlord)) == l3_as_landlord
		var mv: Dictionary = AI.choose(g, seat) if seat_is_l3 else AI.choose_l2(g, seat)
		if mv.has("cards"):
			var r: Dictionary = g.play(seat, mv["cards"])
			if not bool(r.get("ok", false)):
				return -1
		else:
			var r2: Dictionary = g.pass_turn(seat)
			if not bool(r2.get("ok", false)):
				return -1
	if not g.is_over():
		return -1
	return 1 if g.landlord_won() == l3_as_landlord else 0



# ══════════════════════════════════════════════════════════════════
#  圆桌四方位 / 上下家语义 / 叫分文本 / 新底牌 / 娱乐币（2026-10-06 用户定）
# ══════════════════════════════════════════════════════════════════

## 这一步全对应用户当天的原话：
##   ·「中间这个大色块…改成大圆桌」「下方是玩家、左右分别是下家和上家
##     （也就是说，现在的上下家是反了）」
##   ·「叫分数那个…需要在需要叫地主的时候显示就可以，平时不需要显示」
##   ·「新底牌抬起提示」「结算亮字/结算飘字」
##   ·「先做 A，但字段按 B/C 设计」（娱乐币）
func _t_layout() -> void:
	print("[13] 圆桌四方位 / 上下家 / 叫分文本 / 新底牌 / 娱乐币")
	COIN.reset_for_test()
	COIN.persist = false            ## ⛔ 别污染玩家的娱乐币存档
	var t: Control = T.new()
	add_child(t)
	t.size = Vector2(1920, 1080)
	t.call("_new_game", 20261006)
	var g = t.get("game")

	# ── ① 上下家语义（用户 2026-10-06 指出"反了"；2026-10-07 又按玩家反馈对调）──
	#  ⚠️ 依据是**出牌顺序**而不是画面位置：座位 1 在你**之后**出牌 ⇒ 下家。
	#  ⚠️ 座位 → 方位是**语义**（谁在你上下家）；画面左右由 `SEAT_DIR` 决定，
	#     2026-10-07 从 [下,左,右] 对调成 [下,右,左]（斗地主**逆时针**轮转）。
	_ok(String(t.call("_seat_name", 1)).begins_with("下家"),
			"★ 座位 1 = 下家（实际「%s」）" % String(t.call("_seat_name", 1)))
	_ok(String(t.call("_seat_name", 2)).begins_with("上家"),
			"★ 座位 2 = 上家（实际「%s」）" % String(t.call("_seat_name", 2)))
	_ok(int(T.SEAT_DIR[0]) == 0 and int(T.SEAT_DIR[1]) == 2 and int(T.SEAT_DIR[2]) == 1,
			"★ 座位→方位 = [下, 右, 左]（下家在右 / 上家在左；实际 %s）" % str(T.SEAT_DIR))
	# ── 距离等差图（2026-10-07）：实心桌面已删，只剩等差环 ──
	#  ⚠️ 这一步**只能钉住参数**：环形是纯绘制，改没改对只能靠出图看
	#     （工程里那条「机器验过 ≠ 实机对」在这儿依然成立）。
	_ok(int(T.RING_N) == 5 and int(T.RING_KM) == 20,
			"★ 距离等差图 = %d 圈 × 每圈 %d km（实心色块已删）"
			% [int(T.RING_N), int(T.RING_KM)])

	# ── ② 四方位几何：下(你) / 左(上家) / 右(下家) / 上(底牌) ──
	var cx: float = 1920.0 * 0.5
	var cy: float = 1080.0 * float(T.TABLE_CY)
	var p0: Vector2 = t.call("_seat_pt", 0)
	var p1: Vector2 = t.call("_seat_pt", 1)
	var p2: Vector2 = t.call("_seat_pt", 2)
	var pu: Vector2 = t.call("_table_pt", 3, 0.62)
	_ok(p0.y > cy + 40.0 and absf(p0.x - cx) < 2.0, "★ 自己在**正下**（%s）" % str(p0))
	_ok(p1.x > cx + 40.0 and absf(p1.y - cy) < 2.0, "★ 下家（座位 1）在**正右**（%s）" % str(p1))
	_ok(p2.x < cx - 40.0 and absf(p2.y - cy) < 2.0, "★ 上家（座位 2）在**正左**（%s）" % str(p2))
	_ok(pu.y < cy - 40.0, "★ 上方是底牌位（%s）" % str(pu))

	# ── ③ 叫分文本：一进 PLAY 就全清（用户：「平时不需要显示」）──
	t.call("_do_bid", 0, 3)
	_ok(int(g.phase) == int(G.Phase.PLAY), "叫 3 分 ⇒ 直接进出牌阶段")
	var bt: Array = t.get("_bid_text")
	_ok(String(bt[0]) == "" and String(bt[1]) == "" and String(bt[2]) == "",
			"★ 进 PLAY 后叫分文本全清（实际 %s）" % str(bt))

	# ── ④ 新底牌抬起 ──
	var ni: Array = t.get("_new_ids")
	_ok(ni.size() == 3, "★ 新加入的底牌被记 3 张（实际 %d）" % ni.size())
	_ok(float(t.get("_new_t")) > 0.0, "抬起提示的计时器在跑")
	var n: int = (g.hand_of(0) as Array).size()
	var hand: Array = g.hand_of(0)
	var base_y: float = (t.call("_hand_base_rect", 0, n) as Rect2).position.y
	var lifted := 0
	for i in n:
		if ni.has(int(hand[i])):
			var r: Rect2 = t.call("_hand_card_rect", i, n, int(hand[i]))
			if base_y - r.position.y >= float(T.NEW_LIFT) - 0.5:
				lifted += 1
	_ok(lifted == 3, "★ 3 张新底牌在手牌里被抬起（实际 %d）" % lifted)

	# ── ⑤ 倍数：炸弹翻倍 / 春天翻倍 ──
	var m0: int = int(g.multiplier())
	g.bombs = 2
	_ok(int(g.multiplier()) == m0 * 4, "★ 2 个炸弹 ⇒ 倍数 ×4（实际 %d）" % int(g.multiplier()))
	g.spring = true
	_ok(int(g.multiplier()) == m0 * 8, "★ 春天再翻一倍（实际 %d）" % int(g.multiplier()))
	g.bombs = 0
	g.spring = false

	# ── ⑥ 娱乐币结算：**地主 1 打 2 的赔率** ──
	#  地主赢 ⇒ 地主 +2×stake、每个农民 −stake（反过来同理）。
	#  ⚠️ 摆成"地主就是座位 0（玩家）"⇒ `_my_delta` 正好是玩家的账。
	var stake: int = maxi(1, int(g.base_score)) * int(g.multiplier()) * int(T.COIN_UNIT)
	g.landlord = 0
	g.phase = int(G.Phase.OVER)
	g.winner = 0                    ## 地主（= 玩家）赢
	t.set("_floaters", [])
	t.set("_settled", false)
	COIN.reset_for_test()
	t.call("_settle")
	_ok((t.get("_floaters") as Array).size() == 3, "结算给三家各起一个飘字")
	_ok(int(t.get("_my_delta")) == 2 * stake,
			"★ 地主赢 ⇒ 玩家 +2×stake = %d（实际 %d）" % [2 * stake, int(t.get("_my_delta"))])
	_ok(int(COIN.coin) == 2 * stake, "★ 娱乐币入账（实际 %d）" % int(COIN.coin))
	_ok(int(COIN.games) == 1 and int(COIN.wins) == 1, "记了 1 局 1 胜")

	g.winner = 1                    ## 农民赢 ⇒ 地主赔双份
	t.set("_settled", false)
	COIN.reset_for_test()
	t.call("_settle")
	_ok(int(t.get("_my_delta")) == -2 * stake,
			"★ 农民赢 ⇒ 玩家 −2×stake = %d（实际 %d）" % [-2 * stake, int(t.get("_my_delta"))])
	_ok(int(COIN.coin) < 0,
			"★ 方案 A：余额可以为负、没有任何惩罚（实际 %d）" % int(COIN.coin))

	# ── ⑦ 娱乐币千分位（纯逻辑）──
	_ok(COIN.fmt(1234567) == "1,234,567", "千分位 1234567 → %s" % COIN.fmt(1234567))
	_ok(COIN.fmt(-60) == "-60", "负数 → %s" % COIN.fmt(-60))

	t.queue_free()



# ══════════════════════════════════════════════════════════════════
#  ★★ 发牌流程（2026-10-07 用户定案）
# ══════════════════════════════════════════════════════════════════
#
#  用户原话：「进游戏之后不能直接开始，还需要点击一下开始游戏」+
#            「要有个发牌的动画，让手牌一张一张的出现」+
#            「这个时候才出叫不叫地主的判断。现在那个分数按钮还在那，就很难看」
#
#  ⚠️ 三条里最容易漏的是「发牌期间 AI 一步都不许走」——
#     它错起来**没有任何异常**：AI 会在你看发牌的时候把地主叫完，
#     你回过神发现「牌刚发完，地主已经定了」。
#  ⚠️⚠️ 另一条是「动画只影响画」：数据层从一开始就必须是 17 张。
#     如果谁把发牌改成"边发边往手里塞牌"，规则层与 AI 会读到半副牌
#     —— 而且是**静默**的，最后表现成"AI 有时候出很怪的牌"。
func _t_deal_anim() -> void:
	print("[14] 发牌流程（开始游戏 → 发牌动画 → 才出叫分）")
	var t: Control = T.new()
	add_child(t)          # `add_child` 会**同步**触发 `_ready()` ⇒ 本步骤不需要 await
	t.size = Vector2(1920, 1080)

	# ── ① 空桌：进牌桌不能直接开始 ──
	_ok(t.get("game") == null, "★ 进牌桌**不建局**（game == null）")
	_ok(not bool(t.get("_started")), "★ 进牌桌 `_started == false`（空桌态）")
	var ids0 := _btn_ids(t)
	_ok(ids0.has("start"), "★ 空桌正中有「开始游戏」按钮（实际 %s）" % str(ids0))
	_ok(not _has_bid(ids0), "★ 空桌**没有**叫分按钮（实际 %s）" % str(ids0))
	# 空桌时桌上不该有任何牌：底牌区也不画（`_draw_bottom_cards` 对 null 直接 return）
	_ok(String(t.get("_status")).contains("开始游戏"),
			"★ 空桌状态栏提示去点开始（实际「%s」）" % String(t.get("_status")))

	# ── ② 点「开始游戏」（走真实点击通道，中心由 `_buttons()` 自己算）──
	_click_btn(t, "start")
	_ok(bool(t.get("_started")), "★ 点「开始游戏」⇒ 已开始")
	_ok(bool(t.get("_dealing")), "★ 点「开始游戏」⇒ 进入发牌动画")
	var g = t.get("game")
	_ok(g != null, "★ 点「开始游戏」才建局")
	# ★★ 数据层必须**当场就是 17 张**：动画只影响「画」
	_ok((g.hand_of(0) as Array).size() == 17,
			"★★ 动画一开始，数据层手牌**就已经是 17 张**（动画只影响画，不是边发边塞）")
	_ok((g.hand_of(1) as Array).size() == 17 and (g.hand_of(2) as Array).size() == 17,
			"★★ 两家对手的数据层也是 17 张")
	_ok((g.bottom as Array).size() == 3, "底牌 3 张（数据层）")
	_ok(float(t.call("_deal_progress")) < 1.0,
			"发牌进度从 0 起（实际 %.2f）" % float(t.call("_deal_progress")))

	# ── ③ 发牌期间：不出叫分、且**一步都不许走** ──
	var ids1 := _btn_ids(t)
	_ok(not _has_bid(ids1), "★★ 发牌期间**不摆叫分按钮**（实际 %s）" % str(ids1))
	_ok(not bool(t.call("_is_human_turn")), "发牌期间不算「轮到玩家」")
	var feed0: int = (t.get("_feed") as Array).size()
	var turn0: int = int(g.turn)
	var phase0: int = int(g.phase)
	t.call("_process", 1.0)
	_ok(bool(t.get("_dealing")), "推进 1 秒仍在发牌中（总长 %.1f s）" % float(T.DEAL_SEC))
	_ok((t.get("_feed") as Array).size() == feed0,
			"★★ 发牌期间记录条数不变 ⇒ AI 一步都没走（%d → %d）"
			% [feed0, (t.get("_feed") as Array).size()])
	_ok(int(g.turn) == turn0, "★★ 发牌期间轮次没被推进（仍座位 %d）" % int(g.turn))
	_ok(int(g.phase) == phase0, "★★ 发牌期间阶段没变（仍 %d）" % int(g.phase))
	var prog1 := float(t.call("_deal_progress"))
	_ok(prog1 > 0.0 and prog1 < 17.0, "★ 发牌进度在推进（%.1f / 17 张）" % prog1)

	# ── ★★ 手牌**逐张**出现（这是「发牌动画」唯一可断言的形态）──
	#    ⚠️⚠️ 判据必须走 `_hand_card_visible()` —— **与 `_draw()` 同一个来源**。
	#    第一版我让自检只读「进度数值」，结果把实现改成"一次全画出来"它照样全绿：
	#    「逐张出现」是**纯视觉**的，断言钉不住 ⇒ 那份自检等于没测。
	#    （同 2026-10-06 距离环那次：纯视觉改动，只能靠出图目视。）
	var c0 := _visible_hand(t)
	t.call("_process", 0.85)
	var c1 := _visible_hand(t)
	t.call("_process", 0.85)
	var c2 := _visible_hand(t)
	_ok(c0 < c1 and c1 < c2,
			"★★ 手牌**逐张**出现（可见张数 %d → %d → %d 递增）" % [c0, c1, c2])
	_ok(c0 >= 0 and c2 <= 17, "可见张数落在 0~17（%d~%d）" % [c0, c2])
	# 发牌**中途**不该是「全画出来」（否则动画等于没有）。
	# ⚠️ 用 c1 而不是 c2：c2 已经逼近动画末尾（2.70s ≈ 16.4 张）⇒ 它会等于 17，
	#    拿它判「没画满」会假红（实测踩过）。
	_ok(c1 < 17, "发牌中途还没画满 17 张（c1 = %d）" % c1)
	_ok(t.get("game") != null and (g.hand_of(0) as Array).size() == 17,
			"发牌推进过程中手牌数据仍是 17 张（只增「画出来的」，不增数据）")

	# ── ④ 发完：才出叫分 ──
	t.call("_process", float(T.DEAL_SEC) + 0.2)
	_ok(not bool(t.get("_dealing")), "★ 走满动画时长 ⇒ 发牌结束")
	_ok(absf(float(t.call("_deal_progress")) - 17.0) < 0.001,
			"★ 发牌进度到 17 张（实际 %.2f）" % float(t.call("_deal_progress")))
	t.call("_process", 0.05)
	_ok(bool(t.call("_is_human_turn")), "发完轮到玩家（座位 0 先叫）")
	var ids2 := _btn_ids(t)
	_ok(ids2.has("bid0") and ids2.has("bid3"),
			"★★ 发完**才**出现叫分按钮（实际 %s）" % str(ids2))
	_ok(String(t.get("_status")).contains("叫"),
			"状态栏切到叫分（实际「%s」）" % String(t.get("_status")))

	# ── ⑤ 「再来一局」走同一条路 ⇒ 重发一次牌 ──
	t.call("_start_game", 20261006)
	_ok(bool(t.get("_dealing")), "★ 「再来一局」同样重发一次牌（动画再走一遍）")
	_ok(not _has_bid(_btn_ids(t)), "重发期间又叫分按钮消失了")
	t.call("_process", float(T.DEAL_SEC) + 0.2)
	_ok(not bool(t.get("_dealing")), "第二次发牌也能正常结束")

	t.queue_free()
	print("  发牌流程检查完成（空桌 → 发牌 → 才出叫分）")


## 当前**画出来**的手牌张数（走 `_hand_card_visible()` —— 与 `_draw()` 同一个判据）
func _visible_hand(t: Node) -> int:
	var n: int = (t.get("game").hand_of(0) as Array).size()
	var c := 0
	for i in n:
		if bool(t.call("_hand_card_visible", i)):
			c += 1
	return c


## 这组按钮 id 里有没有叫分按钮
func _has_bid(ids: Array) -> bool:
	for i in ids:
		if String(i).begins_with("bid"):
			return true
	return false
