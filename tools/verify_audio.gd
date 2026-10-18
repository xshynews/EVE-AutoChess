extends Node

## 验收 eve_audio.gd 的明确问题（与资产无关，全部用内存 AudioStreamWAV）。
##
## 覆盖用户的清单：
##   · 三条总线存在（SFX / Ambience / Music）
##   · 池数量正确（SFX=12 / Ambience=4 / Boom=4），且 Ambience 池挂在 BUS_AMB
##   · 音乐快速切换 + 停止：active / idle / fade 全部清掉；音乐 loop 已设
##   · 随机隔离：音频不碰全局 randi()，战斗 sim 随机序列不受影响
##   · 缺音源计数：countdown / phase 缺源时不计成功
##   · 命中音色按真实受击层优先（hit_shield/armor/structure），层未知退回品质
##
## 跑法（无头，不需要像素）：
##   "$GODOT_BIN" \
##     --headless --path . --quit-after 60 res://tools/verify_audio.tscn
##
## 退出码：0 = 全过；1 = 有断言失败（失败项逐条打进 stdout）

var _failed := 0
var _passed := 0


func _ready() -> void:
	run_all()
	# 等两帧让日志 flush 再退出（退出码 = 断言结果）
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit(1 if _failed > 0 else 0)


func _ok(name: String, cond: bool) -> void:
	if cond:
		_passed += 1
		print("PASS  %s" % name)
	else:
		_failed += 1
		print("FAIL  %s" % name)


func run_all() -> void:
	_bus_test()
	_pool_test()
	_ambience_bus_test()
	_music_stop_test()
	_music_gain_test()
	_variant_no_repeat_test()
	_random_isolation_test()
	_missing_source_count_test()
	_hit_layer_test()
	_salvo_burst_test()
	_sfx_switch_test()
	_cue_test()
	_volume_test()
	_default_level_test()
	print("")
	print("RESULT passed=%d failed=%d" % [_passed, _failed])


func _make_audio() -> EveAudio:
	var a := EveAudio.new()
	add_child(a)
	# ★ 2026-10-01：音效有总开关，**默认是关的**（用户要求"先全部关闭"）。
	#   下面这些测的是音频层**本身的机制**（节流 / 池 / 缺失计数），
	#   关着开关测等于什么都没测 ⇒ 这里显式打开。
	#   总开关自己由 `_sfx_switch_test()` 双向验。
	a.sfx_enabled = true
	return a


## 音效总开关（2026-10-01 用户要求「音效先全部关闭，是关闭不是删除」）
##
## ★ 双向：
##   ① 打开 ⇒ 开火/爆炸**真的响**（计数涨）
##   ② 关掉 ⇒ 一声不响（计数不涨）
##   ③ 关掉时**不许**走 `_note_missing()` —— 否则"关掉音效"会反过来
##      刷一屏「音源缺失」告警（守卫装在 `play_*` 入口而不是 `_play_from`，
##      就是为了这件事）。
func _sfx_switch_test() -> void:
	var a := _make_audio()
	var fs := _fake_stream()
	a._sfx_bank = {"fire": [fs], "boom": [fs]}

	a.sfx_enabled = true
	a.reset_stats()
	a.play_fire(3, false)
	a.play_boom()
	var on_n := int(a.stats().get("fire", 0)) + int(a.stats().get("boom", 0))
	var on_miss := int(a.stats().get("missing", 0))

	a.sfx_enabled = false
	a.reset_stats()
	a.play_fire(3, false)
	a.play_boom()
	a.play_phase(0)
	var off_n := int(a.stats().get("fire", 0)) + int(a.stats().get("boom", 0)) \
			+ int(a.stats().get("amb", 0))
	var off_miss := int(a.stats().get("missing", 0))

	a.sfx_enabled = true
	a.reset_stats()
	_ok("总开关打开 ⇒ 开火/爆炸真的响（%d 声）" % on_n, on_n >= 2)
	_ok("总开关打开时没有静默缺源（missing=%d）" % on_miss, on_miss == 0)
	_ok("总开关关闭 ⇒ 开火/爆炸/阶段音一声不响（%d 声）" % off_n, off_n == 0)
	_ok("★ 总开关关闭时**不误报**音源缺失（missing=%d）" % off_miss, off_miss == 0)
	a.queue_free()


## 具名音效（牌桌 / UI，2026-10-17 入库）—— `play_cue()`
##
## ★ 为什么专门测它：`play_cue` 的**唯一失败模式**是「键名写错」——
##   写错了不报错、不崩溃，只是那个事件**永久哑掉**；牌型音尤其隐蔽
##   （只有真出那种牌时才听得出来）。所以除了验机制，还要把牌桌真正用到的
##   键名**逐个对着磁盘上的音库点名**（前 3 条）。
func _cue_test() -> void:
	var a := _make_audio()
	# ① 牌桌实际会调的键名，必须在真音库里真的存在（防拼错 / 防漏改文件名）
	var wanted := ["ddz_deal", "ddz_pick", "ddz_play", "ddz_pass", "ddz_deny",
			"ddz_bid_call", "ddz_bid_nocall", "ddz_bid_grab", "ddz_bid_nograb",
			"ddz_bid_rob", "ddz_click", "ddz_combo_straight", "ddz_combo_pairs",
			"ddz_combo_trio", "ddz_combo_trio_pair", "ddz_combo_quad",
			"ddz_combo_quad_pair", "ddz_rocket", "ddz_win"]
	# ★ 2026-10-17 第二批「报牌音」（源 `F:\evezzq\音频\牌`，28 条）：
	#   单张 3~17（含 小王 16 / 大王 17）+ 对子 3~15（王各一张 ⇒ **没有对王**）。
	#   ⚠️ 区间必须与 `ddz_table._combo_cue()` 的 hi 参数一致 —— 两边一改一漏，
	#      这条断言就会去点一个牌桌根本不会用的键名（假绿）。
	#   ⛔ 这里也是**唯一**能查出「键名拼错」的地方：拼错时 `play_cue` 只是安静地
	#      记一次 missing，那个点数就**永久哑音**（要真出到那张牌才听得出）。
	for r in range(3, 18):
		wanted.append("ddz_card_%d" % r)
	for r in range(3, 16):
		wanted.append("ddz_pair_%d" % r)
	var miss: Array[String] = []
	for k: String in wanted:
		if not a._sfx_bank.has(k) and not a._amb_bank.has(k):
			miss.append(k)
	_ok("牌桌 %d 个键名全部有音源（缺：%s）" % [wanted.size(),
			("无" if miss.is_empty() else str(miss))],
			miss.is_empty())
	# ② 「炸弹 / 失败」是**复用现成音源**（不在 ddz_ 前缀里）⇒ 单列两条
	_ok("炸弹键 boom 在 sfx 库", a._sfx_bank.has("boom"))
	_ok("失败键 resolve 在 ambience 库", a._amb_bank.has("resolve"))
	# ③ 真键 ⇒ 真的响（cue 计数涨，且不误报缺源）
	a.reset_stats()
	a.play_cue("ddz_play")
	_ok("play_cue 真的响（cue +1）", int(a.stats().get("cue", 0)) == 1)
	_ok("真键不误报缺源（missing=0）", int(a.stats().get("missing", 0)) == 0)
	# ④ **跨库回退**：键只在 ambience 里也要能响（「失败」用的 `resolve` 正是这种）
	a.reset_stats()
	a.play_cue("resolve")
	_ok("sfx 库没有、ambience 有 ⇒ 也能响（cue +1）", int(a.stats().get("cue", 0)) == 1)
	_ok("跨库回退不误报缺源", int(a.stats().get("missing", 0)) == 0)
	# ⑤ 拼错的键 ⇒ 记一次 missing（**这是哑音唯一能被发现的线索**）
	a.reset_stats()
	a.play_cue("ddz_typo_nonexistent")
	_ok("拼错的键记一次缺源（missing=1）", int(a.stats().get("missing", 0)) == 1)
	_ok("拼错的键不涨 cue", int(a.stats().get("cue", 0)) == 0)
	# ⑥ 总开关关掉 ⇒ 不响，且**不许**刷 missing（与战斗音同一条守卫）
	a.sfx_enabled = false
	a.reset_stats()
	a.play_cue("ddz_play")
	_ok("总开关关闭 ⇒ cue 不响", int(a.stats().get("cue", 0)) == 0)
	_ok("总开关关闭 ⇒ 不误报缺源", int(a.stats().get("missing", 0)) == 0)
	a.queue_free()


func _fake_stream() -> AudioStream:
	# 内存里的极短静音 WAV，足以让 get_length() 返回非 0（不依赖任何资产文件）。
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_8_BITS
	s.mix_rate = 11025
	s.stereo = false
	var data := PackedByteArray()
	data.resize(1024)
	s.data = data
	return s


func _bus_test() -> void:
	var a := _make_audio()
	_ok("bus SFX exists", AudioServer.get_bus_index(EveAudio.BUS_SFX) >= 0)
	_ok("bus Ambience exists", AudioServer.get_bus_index(EveAudio.BUS_AMB) >= 0)
	_ok("bus Music exists", AudioServer.get_bus_index(EveAudio.BUS_MUSIC) >= 0)
	a.queue_free()


func _pool_test() -> void:
	var a := _make_audio()
	_ok("sfx pool == 12", a._sfx_players.size() == 12)
	_ok("amb pool == 4", a._amb_players.size() == 4)
	_ok("boom pool == 4", a._boom_players.size() == 4)
	var on_amb := true
	for p in a._amb_players:
		if p.bus != EveAudio.BUS_AMB:
			on_amb = false
	_ok("ambience players on BUS_AMB", on_amb)
	a.queue_free()


func _ambience_bus_test() -> void:
	var a := _make_audio()
	var fs := _fake_stream()
	# amb 银行有音源、sfx 银行故意留空：若 ambience 误用 sfx 池会选不到 player。
	a._amb_bank = {"phase_prep": [fs]}
	a._sfx_bank = {}
	var before: int = a.stats()["amb"]
	a.play_phase(0)
	_ok("play_phase counts when played", a.stats()["amb"] == before + 1)
	# 真用到了 amb 池（而非 sfx 池）：被挑中的 player 在 _amb_players 里且挂在 BUS_AMB
	var used_amb := false
	for p in a._amb_players:
		if p.stream == fs and p.bus == EveAudio.BUS_AMB:
			used_amb = true
	_ok("play_phase used BUS_AMB pool", used_amb)
	# 反向：amb 银行空时不应计数（缺音源不算成功）
	a._amb_bank = {}
	var b2: int = a.stats()["amb"]
	a.play_phase(0)
	_ok("play_phase no count when missing", a.stats()["amb"] == b2)
	a.queue_free()


func _music_stop_test() -> void:
	var a := _make_audio()
	var fs := _fake_stream()
	a._mus_bank = {"prep": [fs], "battle": [fs]}
	a.play_music("prep")
	_ok("music_current == prep", a.stats()["music_current"] == "prep")
	# 切曲时 idle 流应已设 loop（否则一局响一遍就静音）
	# ⚠️ 属性名不统一：Ogg/MP3 是 `loop`，WAV 是 `loop_mode`，两边都认。
	var mst: AudioStream = a._music_idle.stream
	_ok("music loop set on idle stream",
			mst != null and (mst.get("loop") == true or mst.get("loop_mode") == 1))
	a.play_music("battle")
	_ok("music_current == battle", a.stats()["music_current"] == "battle")
	# 快速切到停：active + idle + fade 全部清掉
	a.play_music("")
	_ok("music stopped (current empty)", a.stats()["music_current"] == "")
	_ok("music fade cleared (old bug left idle/fade playing)",
			a._music_fading == false)
	# 让 _process 跑几帧，确认没有任何 player 还在播、不崩溃
	for i in 5:
		a._process(0.1)
	_ok("no music player playing after stop",
			not a._music_a.playing and not a._music_b.playing)
	a.queue_free()


## BGM 额外增益（鸭音）—— `set_music_gain()`（★ 2026-10-17 用户：空桌响、动手后变轻）
##
## ★ 为什么专门测它：落点是一个挂在**全局 AudioServer** 上的 `AudioEffectAmplify`，
##   不是本实例的子节点。它有两个"不报错"的失败模式：
##     ① `AudioServer.get_bus_effect()` 拿到的若是**副本**，写进去的增益只改了副本，
##        真总线上什么都没变 —— 游戏里表现为「鸭音没生效」，没有任何报错；
##     ② 效果器会被**上一个场景 / 上一个实例**留下来 —— 不归零就会把牌桌的
##        「空桌响态」带进主菜单/战场（音乐忽大忽小，也没人知道为什么）。
##   ⇒ 这里既验"写进去的量服务器真收到了"，也验两道归零 + 幂等。
func _music_gain_test() -> void:
	var a := _make_audio()
	_ok("★ Music 总线上挂到了增益效果器（鸭音的落点）", a._music_gain_fx != null)
	# ① 瞬时设置 —— 读回刻意走 `AudioServer`（**不是**读实例字段），这样才能发现"副本"坑
	a.set_music_gain(5.0, 0.0)
	_ok("★ 瞬时 +5 dB：从服务器读回 %s dB" % str(_read_bus_gain()),
			is_equal_approx(_read_bus_gain(), 5.0))
	# ② 渐变：半程应落在中间（既不是 5 也不是 0），走满精确到位
	a.set_music_gain(0.0, EveAudio.MUSIC_GAIN_FADE)
	a._process(EveAudio.MUSIC_GAIN_FADE * 0.5)
	var mid := _read_bus_gain()
	_ok("★ 淡到一半落在中间（%s dB，不是 5 也不是 0）" % str(mid), mid < 4.5 and mid > 0.5)
	a._process(EveAudio.MUSIC_GAIN_FADE)
	_ok("淡完精确落到位（%s dB）" % str(_read_bus_gain()), is_equal_approx(_read_bus_gain(), 0.0))
	# ③ 新建实例必须归零 —— 防"上一个场景的响态"泄漏
	a.set_music_gain(5.0, 0.0)
	var b := _make_audio()
	_ok("★★ 新建音频层把增益归零（服务器读回 %s dB）—— 防跨场景泄漏" % str(_read_bus_gain()),
			is_equal_approx(_read_bus_gain(), 0.0))
	# ④ 换曲必须归零 —— 别让上一首的状态跟着下一首走
	b._mus_bank = {"x": [_fake_stream()], "y": [_fake_stream()]}
	b.play_music("x")
	b.set_music_gain(5.0, 0.0)
	b.play_music("y")
	_ok("★★ 换曲把增益归零（服务器读回 %s dB）" % str(_read_bus_gain()),
			is_equal_approx(_read_bus_gain(), 0.0))
	# ⑤ 幂等：再 new 实例不许把效果器叠成两层（+5 +5 = +10，且**不报错**）
	var n_before := _count_gain_effects()
	var c := _make_audio()
	_ok("★ 效果器不重复叠加（%d → %d 个）" % [n_before, _count_gain_effects()],
			_count_gain_effects() == n_before)
	a.queue_free()
	b.queue_free()
	c.queue_free()


## 从 **AudioServer** 读回 Music 总线上的增益（⚠️ 刻意不走实例字段）。
func _read_bus_gain() -> float:
	var idx := AudioServer.get_bus_index(EveAudio.BUS_MUSIC)
	if idx < 0:
		return 999.0
	for i in AudioServer.get_bus_effect_count(idx):
		var e := AudioServer.get_bus_effect(idx, i)
		if e is AudioEffectAmplify:
			return (e as AudioEffectAmplify).volume_db
	return 999.0


func _count_gain_effects() -> int:
	var idx := AudioServer.get_bus_index(EveAudio.BUS_MUSIC)
	if idx < 0:
		return -1
	var n := 0
	for i in AudioServer.get_bus_effect_count(idx):
		if AudioServer.get_bus_effect(idx, i) is AudioEffectAmplify:
			n += 1
	return n


## 同一键多变体 ⇒ **不与上一次重复**（用户 2026-10-18：「过和不要需要交替出现，
## 用来增加趣味性」；「避免出现连续两个"抢地主"听着很乏味」）
##
## ★ 为什么值得单测：这条规则的失败形态是"**偶尔**连着响同一个"——
##   既不会报错、也不会崩，只有长时间玩才隐约觉得单调。⇒ 只能靠断言钉住。
##   「不要 / 过」正是靠这条自动交替：两个文件放在同一个逻辑名 `ddz_pass` 下，牌桌零代码。
func _variant_no_repeat_test() -> void:
	var a := _make_audio()
	# ⚠️ 固定种子：③ 那条「5 个变体都参与轮换」是**概率性**的（纯随机下偶尔会漏掉一个
	#    而假红）⇒ 钉住种子让这条断言变成确定性事实（同 `_random_isolation_test` 的做法）。
	a._rng.seed = 20261018
	# ① 两变体 ⇒ **必然交替**（n=2 时"排除上一次"只剩一个可挑）
	a._last_variant.clear()
	var seq: Array = []
	for i in 12:
		seq.append(a._pick_variant("alt", 2))
	var ok2 := true
	for i in range(1, seq.size()):
		if seq[i] == seq[i - 1]:
			ok2 = false
	_ok("★★ 两变体必然交替（%s）" % str(seq), ok2)
	_ok("两变体都真的用上了（%s）" % str(seq), seq.has(0) and seq.has(1))
	# ② 单变体：只能一直用它（无解，但别崩、别返回-1）
	_ok("只有一个变体时稳定返回 0", a._pick_variant("solo", 1) == 0)
	# ③ 多变体（5 个）也不许与上一次重复
	a._last_variant.clear()
	var seq5: Array = []
	for i in 24:
		seq5.append(a._pick_variant("five", 5))
	var ok5 := true
	var used := {}
	for i in range(1, seq5.size()):
		if seq5[i] == seq5[i - 1]:
			ok5 = false
	for v in seq5:
		used[v] = true
	_ok("★★ 5 个变体也不与上一次重复（%s）" % str(seq5), ok5)
	_ok("5 个变体都参与轮换（用到 %d 个）" % used.size(), used.size() == 5)
	a.queue_free()


func _random_isolation_test() -> void:
	var a := _make_audio()
	var fs := _fake_stream()
	a._sfx_bank = {"fire": [fs], "hit": [fs], "tick": [fs]}
	a._mus_bank = {"prep": [fs], "battle": [fs]}
	# ── 对照组 ──────────────────────────────────────────────────────
	# 先证明「seed 后取 N 个数」这件事本身可复现。
	# ⚠️ 没有这一步，后面两条失败会分不清是「音频动了 RNG」还是
	#    「seed() 压根不可复现」—— 曾在这里误判过一次。
	seed(12345)
	var c1: Array[int] = [randi(), randi(), randi()]
	seed(12345)
	var c2: Array[int] = [randi(), randi(), randi()]
	_ok("control: seed() reproducible (test methodology)", c1 == c2)
	print("      control=%s" % str(c1))
	print("      again  =%s" % str(c2))

	# 全局 RNG 确定性基线：seed 后取 12 个值（前 6 = audio 调用前，后 6 = 之后）
	seed(12345)
	# ⚠️ 必须用普通 Array：`randi()` 返回 0..2^32-1，存进 PackedInt32Array
	#    会把 >2^31 的值截断成负数，基线就和实际值对不上（假失败）。
	var base: Array = []
	for i in 12:
		base.append(randi())
	var pre := [base[0], base[1], base[2], base[3], base[4], base[5]]
	var post_ctrl := [base[6], base[7], base[8], base[9], base[10], base[11]]
	# 实际：seed 后再取 6，调用 audio（若用全局 RNG 会打乱后续），再取 6
	seed(12345)
	var pre2 := [randi(), randi(), randi(), randi(), randi(), randi()]
	for i in 200:
		a._play_from(a._sfx_bank, "fire", a._sfx_players, 0.96, 1.06, true)
	a.play_music("prep")
	a.play_music("battle")
	var post2 := [randi(), randi(), randi(), randi(), randi(), randi()]
	print("      pre  =%s" % str(pre2))
	print("      want =%s" % str(pre))
	_ok("global RNG pre-audio untouched", pre2 == pre)
	print("      post =%s" % str(post2))
	print("      want =%s" % str(post_ctrl))
	_ok("global RNG post-audio untouched (isolated RNG)",
			post2 == post_ctrl)
	a.queue_free()


func _missing_source_count_test() -> void:
	var a := _make_audio()
	# countdown 缺音源（amb 银行空）时不应计数
	a._amb_bank = {}
	var before: int = a.stats()["amb"]
	a.play_countdown(3)
	a.play_countdown(2)
	a.play_countdown(1)
	_ok("countdown no count when missing", a.stats()["amb"] == before)
	# 有音源时计数
	var fs := _fake_stream()
	a._amb_bank = {
		"count_3": [fs], "count_2": [fs], "count_1": [fs], "tick": [fs],
	}
	var b2: int = a.stats()["amb"]
	a.play_countdown(3)
	a.play_countdown(2)
	a.play_countdown(1)
	_ok("countdown counts when played", a.stats()["amb"] == b2 + 3)
	a.queue_free()


func _hit_layer_test() -> void:
	# play_hit 按真实受击层选音色；层未知时退回品质映射。
	var a := _make_audio()
	_ok("hit_key shield layer", a._hit_key(3, &"shield") == "hit_shield")
	_ok("hit_key armor layer", a._hit_key(3, &"armor") == "hit_armor")
	_ok("hit_key hull layer", a._hit_key(3, &"hull") == "hit_structure")
	# 层未知（空）时退回品质映射（quality=3 → 通用 "hit"）
	_ok("hit_key falls back to quality when layer unknown",
			a._hit_key(3, &"") == "hit")
	# MISS 品质回退仍是 "miss"（场景侧 miss 不调 play_hit，但音频层要自洽）
	_ok("hit_key miss quality", a._hit_key(0, &"") == "miss")
## 音量 / 静音必须**真的写到总线**上。
##
## ⚠️ 只改 `volume_sfx` 这类成员变量是没用的（没人读它），
##    设置窗拖滑块会「看起来设了、听起来没变」，且不报错。
func _volume_test() -> void:
	var a := _make_audio()
	var idx := AudioServer.get_bus_index(EveAudio.BUS_SFX)
	a.set_volume(&"sfx", 1.0)
	var loud := AudioServer.get_bus_volume_db(idx)
	a.set_volume(&"sfx", 0.2)
	var quiet := AudioServer.get_bus_volume_db(idx)
	_ok("set_volume 真的改成总线音量（%.1f dB → %.1f dB）" % [loud, quiet],
			quiet < loud - 3.0)
	a.set_muted(true)
	_ok("set_muted(true) 真的把总线静音", AudioServer.is_bus_mute(idx))
	a.set_muted(false)
	_ok("set_muted(false) 解除静音", not AudioServer.is_bus_mute(idx))

	# ── 总音量（2026-09-28 新增，设置窗的第一条滑杆）──
	#
	# ⚠️ 它必须落在 **Master 总线**上，而不是「三条分总线各乘一次系数」：
	#    后者会让总音量与分档**互相污染** —— 玩家把总音量拉到 50% 之后，
	#    音效/音乐之间的相对配比也跟着变了（再调分档就调不回原来的手感）。
	#    所以这里同时断言两件事：Master 变了、三条分总线**一个都没动**。
	var m_idx := AudioServer.get_bus_index(EveAudio.BUS_MASTER)
	var sfx_before := AudioServer.get_bus_volume_db(idx)
	a.set_volume(&"master", 0.5)
	var master_half := AudioServer.get_bus_volume_db(m_idx)
	var sfx_after := AudioServer.get_bus_volume_db(idx)
	_ok("总音量 50%% 落到 Master 总线（%.1f dB）" % master_half, master_half < -3.0)
	_ok("调总音量不污染分档（sfx %.1f dB 不变）" % sfx_after,
			absf(sfx_after - sfx_before) < 0.001)
	a.queue_free()


## 默认响度守卫。
##
## ⚠️ 原始默认 `0.85 / 0.55 / 0.45` 实测偏响（sfx 有效增益只有 −2.8 dB），
##    已统一 −6 dB 到 `0.60 / 0.39 / 0.32`。
##    守卫故意写成「上限 + 配比」而**不是**「等于某几个具体数值」：
##    数值以后还要按耳朵微调（往更轻调不该被拦），
##    但**不许调回偏响那一档**，也不许把三条总线的相对配比调乱。
##    ⚠️ 注意这里量的是 `get_bus_volume_db`（平方曲线后的真实增益），
##    不是 `volume_*` 滑块值 —— 滑块 0.6 对应的是 −8.9 dB，不是 −4.4 dB。
func _default_level_test() -> void:
	var a := _make_audio()
	var sfx := AudioServer.get_bus_volume_db(AudioServer.get_bus_index(EveAudio.BUS_SFX))
	var amb := AudioServer.get_bus_volume_db(AudioServer.get_bus_index(EveAudio.BUS_AMB))
	var mus := AudioServer.get_bus_volume_db(AudioServer.get_bus_index(EveAudio.BUS_MUSIC))
	var cap := -6.0
	_ok("默认 sfx 不高于 %.0f dB（实际 %.1f dB）" % [cap, sfx], sfx <= cap)
	_ok("默认 amb 不高于 %.0f dB（实际 %.1f dB）" % [cap, amb], amb <= cap)
	_ok("默认 music 不高于 %.0f dB（实际 %.1f dB）" % [cap, mus], mus <= cap)
	_ok("默认配比未调乱（sfx > amb > music，实际 %.1f / %.1f / %.1f dB）" % [sfx, amb, mus],
			sfx > amb and amb > mus)
	a.queue_free()
##
## ⚠️ 这条守护的是一个实测踩到的坑：战斗是固定步长推进的，同一 tick 里
##    6 艘船开火的 `sim.elapsed` **完全相同**。只有「冷却窗口」没有「桶容量」
##    时，6 声被压成 1 声 —— 实测 12 秒战斗 32 次开火只响 8 声。
##    症状是「画面上六艘船在齐射，听感上零星两枪」，且**不报错**。
func _salvo_burst_test() -> void:
	var a := _make_audio()
	var fs := _fake_stream()
	a._sfx_bank = {"fire": [fs]}
	a.reset_stats()
	# 喂模拟时间：全部 6 发都在同一时刻（同一 tick）
	a.set_clock(10.0)
	for i in 6:
		a.play_fire(3)
	var n := int(a.stats()["fire"])
	_ok("同一 tick 的齐射不会被压成一声（实际 %d 声）" % n, n >= 3)
	_ok("齐射仍有上限（桶容量 BURST_FIRE=3，实际 %d）" % n, n <= 3)
	# 时间推进一个窗口后应能再放（桶会出桶）
	a.set_clock(10.1)
	a.play_fire(3)
	_ok("过了节流窗口后允许再放", int(a.stats()["fire"]) == n + 1)
	a.queue_free()
