extends Node
## 联机对战 · 顶条规则自检（撤开战键 / 最后 10 秒中央倒计时 / 信标排隔断）。
##
## 用法：`godot --headless --path . --quit-after 9000 res://tools/verify_versus_countdown.tscn`
##
## ★ 为什么单开一套：这条规则曾经**只在 1 人类 + AI 那条建局路径里实现**，
##   从联机大厅进局（`_setup_versus_by_slots`）漏掉 ⇒ 玩家又看见开战键。
##   这里把**两条路径都跑一遍**，钉住「谁建局都一样」。

const BATTLE_SCENE := "res://scenes/battle_scene.tscn"
const CD := preload("res://scripts/ui/eve_round_countdown.gd")
const MS := preload("res://scripts/core/eve_match_state.gd")
const MP := preload("res://scripts/core/eve_match_player.gd")
const RUN_STORE := preload("res://scripts/core/eve_run_store.gd")

## 用户 2026-10-28 逐回合定案（键 = 回合标签，值 = RoundKind 整数）。
##   PVE=0 PVP=1 CAROUSEL=2 BOSS=3
## ⚠️ 这张表就是**设计真源**：改回合节奏必须同步改这里，否则自检会红。
const WANT_KINDS := {
	"1-1": 0, "1-2": 0, "1-3": 0,
	"2-1": 2, "2-2": 1, "2-3": 0, "2-4": 0, "2-5": 1, "2-6": 0, "2-7": 3,
	"3-1": 2, "3-2": 1, "3-3": 0, "3-4": 0, "3-5": 1, "3-6": 1, "3-7": 3,
}

var _pass := 0
var _fail := 0


func _ok(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("  [FAIL] %s" % msg)


func _ready() -> void:
	print("═══ 联机顶条 / 中央倒计时自检 ═══")
	_ok(CD.digits_for(10.0) == 10, "10.0s → 10")
	_ok(CD.digits_for(9.0001) == 10, "9.0001s → 10（向上取整，不是 9）")
	_ok(CD.digits_for(1.0) == 1, "1.0s → 1")
	_ok(CD.digits_for(0.0001) == 1, "0.0001s → 1（没归零就还在读秒）")
	_ok(CD.digits_for(0.0) == 0, "0.0s → 不显示")
	_ok(CD.digits_for(11.0) == 10, "11s 封顶 10（不会画出 11）")
	_ok(CD.band_for(10.0) == 0 and CD.band_for(6.0) == 0, "10–6s 青")
	_ok(CD.band_for(5.0) == 1 and CD.band_for(4.0) == 1, "5–4s 金")
	_ok(CD.band_for(3.0) == 2 and CD.band_for(0.5) == 2, "3–1s 红")

	await _single_ok()
	_round_table()
	_pairing_ok()
	await _path_ai()
	await _path_slots()
	await _host_authority()

	print("═══ RESULT passed=%d failed=%d ═══" % [_pass, _fail])
	if _fail > 0:
		print("⚠️ 有失败项")
	get_tree().quit(1 if _fail > 0 else 0)


## 17 回合排表 + PvP 场数 + 多人 PvE 的敌方难度档。
##
## ⚠️ 弯路的来源：`PVE_SOURCE_NODE`（逐回合指定炼狱编组）**优先级高于**
##    阶段模板 ⇒ 「配成打怪的回合」不会再是 PvP。这不是 bug，但很容易
##    让人误以为「PvP 被落下了」，所以把整张表钉死。
func _round_table() -> void:
	var room = MS.new([], 1)
	var n := 0
	var pvp := 0
	for st in range(1, MS.TOTAL_STAGES + 1):
		room.stage = st
		for rd in range(1, room.rounds_in_stage() + 1):
			room.round = rd
			var k := int(room.round_kind())
			var lbl: String = room.round_label()
			n += 1
			if k == 1:
				pvp += 1
			_ok(WANT_KINDS.has(lbl) and k == int(WANT_KINDS[lbl]),
					"回合表：%s 种类=%d（应为 %s）" % [lbl, k, str(WANT_KINDS.get(lbl, "?"))])
	_ok(n == 17, "回合表：总回合 = 17（实际 %d）" % n)
	_ok(pvp == 5, "回合表：PvP = 5 场（2-2 / 2-5 / 3-2 / 3-5 / 3-6，实际 %d）" % pvp)
	_ok(MS.TOTAL_ROUNDS == n, "回合表：TOTAL_ROUNDS 常量与实际一致")
	# 2-4 / 3-4 被 PvE 配置覆盖 ⇒ 这两处**不是**选秀（用户表就是这么定的）
	room.stage = 2
	room.round = 4
	_ok(int(room.round_kind()) == 0, "回合表：2-4 是 PvE（炼狱第 6 回合），不是选秀")


## PvP 配对规则（用户 2026-10-28）：
##   按信标血量从高到低排，**相邻两人对战** ⇒ 每个人打的是血量最接近的那个；
##   同血按座位号、奇数人时血量最低的轮空、出局者不参与、与随机种子无关。
func _pairing_ok() -> void:
	var r4 = MS.new(_mk_players([100, 88, 72, 54]), 7)
	var p: Array = r4.make_pairings()
	_ok(p.size() == 2 and p[0][0] == 0 and p[0][1] == 1, "配对：100 打 88")
	_ok(p[1][0] == 2 and p[1][1] == 3, "配对：72 打 54")
	_ok(r4.make_pairings() == p, "配对：算一次即冻结（同一回合不会换人）")

	var r3 = MS.new(_mk_players([100, 60, 20]), 7)
	var q: Array = r3.make_pairings()
	_ok(q.size() == 2, "配对：3 人 → 2 组（含 1 轮空）")
	_ok(q[0][0] == 0 and q[0][1] == 1, "配对：3 人时 100 打 60")
	_ok(q[1][1] == -1, "配对：轮空的是血量最低的那位")

	var r5 = MS.new(_mk_players([100, 0, 80]), 7)
	var s5: Array = r5.make_pairings()
	_ok(s5.size() == 1 and s5[0][0] == 0 and s5[0][1] == 2, "配对：出局者不参与")

	# 联机确定性：同样的血量表 + 不同种子，两台机器必须算出同一张表
	var a = MS.new(_mk_players([90, 90, 90, 90]), 11)
	var b = MS.new(_mk_players([90, 90, 90, 90]), 99)
	_ok(str(a.make_pairings()) == str(b.make_pairings()), "配对：与随机种子无关（两台机器同表）")
	_ok(a.make_pairings()[0][0] == 0 and a.make_pairings()[0][1] == 1, "配对：同血按座位号 0 打 1")

	# 血量变了要重排（回合推进时 reroll_pairings 必须被调）
	var r6 = MS.new(_mk_players([100, 90, 80, 70]), 7)
	var before: Array = r6.make_pairings().duplicate(true)
	r6.players[1].hp = 10      # 第二位掉到最低
	r6.reroll_pairings()
	var after: Array = r6.make_pairings()
	_ok(str(before) != str(after), "配对：血量变化后重排")
	_ok(after[1][0] == 1 or after[1][1] == 1, "配对：掉血的玩家被排到相邻的后一组")


func _mk_players(hps: Array) -> Array:
	var out: Array = []
	for i in hps.size():
		var pl = MP.new(null, "P%d" % i, false)
		pl.hp = int(hps[i])
		out.append(pl)
	return out


## PvE 敌方按炼狱档（吃羁绊 / 按阵型 / ×1.40）—— 与玩家自选难度无关
func _enemy_tier_ok(b, tag: String) -> void:
	var run = b.get("run")
	_ok(String(run.enemy_tier_override) == "inferno", "%s：敌方档覆盖 = 炼狱" % tag)
	var row: Dictionary = run.enemy_tier_row()
	_ok(bool(row.get("enemy_traits", false)), "%s：敌方吃羁绊" % tag)
	_ok(bool(row.get("enemy_formation", false)), "%s：敌方按阵型站位" % tag)
	_ok(absf(float(row.get("scale", 0.0)) - 1.40) < 0.001, "%s：敌方强度系数 ×1.40" % tag)


## 路径①：1 人类 + N AI
func _path_ai() -> void:
	var b = await _spawn()
	b.call("begin_prep")
	b.call("_setup_versus", 3)
	await get_tree().process_frame
	await _common(b, "AI 建局")
	_close(b)


## 房主权威（2026-10-28 用户：「需要房主点击开始游戏各个玩家才能开始游戏」）。
##
## ⚠️ 这条规则不能靠「两台真机」验 —— 用**单进程 + 直接注入 START 包**验：
##     · 加入方：进战场后必须干等（倒计时不动、不判负），收到 START 才开赛；
##     · 房主：等对端/宽限到点后自己开赛；
##     · 加入方：不许自己推进回合，只能跟房主的 ROUND 走。
func _host_authority() -> void:
	_reset_store("join")
	var c = await _spawn()
	await get_tree().process_frame
	await get_tree().process_frame
	var bar = c.get("hud").get("command_bar")
	_ok(bool(c.get("_vawait_start")), "加入方：进战场先等 START")
	_ok(not bool(c.get("_vstarted")), "加入方：没收到 START 就不开始")
	var t0 := float(bar.get("time_left"))
	await get_tree().create_timer(0.5).timeout
	_ok(absf(float(bar.get("time_left")) - t0) < 0.01,
			"加入方：等待期间准备倒计时不走（%.1f → %.1f）" % [t0, float(bar.get("time_left"))])
	_ok(int(c.get("run").phase) == 0, "加入方：等待期间不会被判负（仍在准备阶段）")
	# 房主 START 到达 ⇒ 开第 1 回合
	c.get("_vtr").packet.emit(1, {"kind": 4, "start": 1, "round": 0})
	await get_tree().process_frame
	await get_tree().process_frame
	_ok(bool(c.get("_vstarted")), "加入方：收到 START 即开赛")
	_ok(absf(float(bar.get("time_left")) - 30.0) < 1.5,
			"加入方：开赛后准备倒计时 = 30s（实际 %.1f）" % float(bar.get("time_left")))
	# 跟房主换回合；加入方自己不许推进
	c.call("_versus_client_follow", 2, 2)
	await get_tree().process_frame
	_ok(String(c.get("versus").round_label()) == "2-2", "加入方：跟随房主切到 2-2")
	var before := String(c.get("versus").round_label())
	c.call("_versus_advance_round")
	await get_tree().process_frame
	_ok(String(c.get("versus").round_label()) == before, "加入方：不能自己推进回合")
	_close(c)

	_reset_store("host")
	var h = await _spawn()
	await get_tree().process_frame
	_ok(bool(h.get("_vawait_start")), "房主：也要先过开赛闸门")
	_ok(not bool(h.get("_vstarted")), "房主：闸门未到点不开始")
	await get_tree().create_timer(1.8).timeout
	_ok(bool(h.get("_vstarted")), "房主：宽限到点自动开赛")
	_close(h)
	_reset_store("")


## 清掉/摆好联机建局参数（⚠️ RUN_STORE 是静态的，跨用例会串味）。
func _reset_store(role: String) -> void:
	RUN_STORE.pending_versus_role = role
	RUN_STORE.pending_versus_ai = 0
	RUN_STORE.pending_versus_tunnel = false
	RUN_STORE.pending_versus_addr = "127.0.0.1:37999"
	RUN_STORE.pending_versus_port = 37999
	RUN_STORE.pending_versus_seats = 4
	RUN_STORE.pending_versus_my_seat = 1 if role == "join" else 0
	RUN_STORE.pending_versus_slots = [
		{"kind": "human", "name": "房主"}, {"kind": "human", "name": "玩家 2"},
		{"kind": "ai", "name": "电脑 3"}, {"kind": "ai", "name": "电脑 4"},
	]


## 路径②：按座位建局（联机大厅）
func _path_slots() -> void:
	var b = await _spawn()
	var slots := [{"kind": "human"}, {"kind": "ai"}, {"kind": "ai"}, {"kind": "ai"}]
	b.call("begin_prep")
	b.call("_setup_versus_by_slots", slots, 0)
	await get_tree().process_frame
	await _common(b, "按座位建局")
	_close(b)


func _common(b, tag: String) -> void:
	var hud = b.get("hud")
	var bar = hud.get("command_bar")
	var ov = hud.get("round_countdown")
	# 信标排由主控每帧刷（`_refresh_versus_hud`）；这里显式刷一次再断言
	b.call("_refresh_versus_hud")
	await get_tree().process_frame
	_ok(bool(b.get("auto_start_on_timeout")), "%s：倒计时归零自动开战" % tag)
	_enemy_tier_ok(b, tag)
	_ok(not bool(bar.get("_start_btn").visible), "%s：开战键已撤（顶条无手动入口）" % tag)
	_ok(bool(ov.get("_active")), "%s：中央倒计时已激活" % tag)
	_ok(bool(bar.get("_versus_strip").visible), "%s：信标排独立成条" % tag)
	_ok(bool(bar.get("_versus_gap").visible), "%s：信标排与菜单之间有隔断" % tag)
	# 隔断必须真的存在（不是 0 高）—— 用户要的「隔断」就是这条空档
	_ok(bar.get("_versus_gap").custom_minimum_size.y >= 8.0, "%s：隔断 ≥ 8px" % tag)
	# 裸条被撑高（内容宿主 clip=true，不撑就会把第二排裁掉）
	_ok(bar.size.y >= 40.0 + 8.0 + 44.0 - 0.5, "%s：顶条已撑到能装下信标排（%.0f）" % [tag, bar.size.y])

	# 圆心必须真的上移过（用户：「位置有点偏下了，向上移动个 200 多 300px」）
	var cy := float((ov.call("_center") as Vector2).y)
	_ok(cy <= ov.size.y * 0.5 - 200.0, "%s：倒计时圆心上移 ≥200px（y=%.0f）" % [tag, cy])

	# 10 秒门槛：11s 不出现、10s 出现
	bar.set("phase", 0)
	bar.set("time_left", 11.0)
	await get_tree().process_frame
	_ok(not bool(ov.get("_show_ring")), "%s：11s 还不出现" % tag)
	bar.set("time_left", 9.5)
	await get_tree().process_frame
	_ok(bool(ov.get("_show_ring")) and int(ov.get("_digits")) == 10,
			"%s：9.5s 出现并显示 10" % tag)
	# 非准备阶段就算剩 5s 也不该出现（交战期没有「准备倒计时」）
	bar.set("phase", 1)
	bar.set("time_left", 5.0)
	await get_tree().process_frame
	_ok(not bool(ov.get("_show_ring")), "%s：交战阶段不显示" % tag)


## 单机路径：仍要保留开战键、不显示中央大字
func _single_ok() -> void:
	var b = await _spawn()
	b.call("begin_prep")
	await get_tree().process_frame
	var hud = b.get("hud")
	var bar = hud.get("command_bar")
	var ov = hud.get("round_countdown")
	_ok(bool(bar.get("_start_btn").visible), "单机：开战键仍在")
	_ok(not bool(ov.get("_active")), "单机：中央倒计时关闭")
	_close(b)


func _spawn() -> Node:
	var b = (load(BATTLE_SCENE) as PackedScene).instantiate()
	add_child(b)
	await get_tree().process_frame
	await get_tree().process_frame
	return b


func _close(b) -> void:
	b.queue_free()
