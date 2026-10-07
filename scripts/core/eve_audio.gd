extends Node
class_name EveAudio

## EVE 自走棋 —— 音频层（阶段 D 子项 ④）
##
## ══════════════════════════════════════════════════════════════════
##  它解决什么
## ══════════════════════════════════════════════════════════════════
##  阶段 A~D 一路做下来，战斗在玩家眼里已经完全成立：船在动、曳光在飞、
##  爆点在闪、伤害数字在飘。但它**一直是静音的**。静音的战斗有个很具体的
##  副作用：玩家感知不到「打得多狠」—— 7 档命中品质（MISS→WRECKING）在
##  视觉上只差别在爆点大小，而声音是**瞬间**传达量级的通道。
##
##  音源全部来自本机 EVE Online 客户端（`D:\EVE`）解包，
##  用 vgmstream 从 Wwise SoundBank 导出 —— 也就是**玩家在 EVE 里听到的
##  同一个音源**，不是仿制品。
##
## ── 三条总线的分工 ──────────────────────────────────────────────
##     SFX       打击反馈：开火 / 命中（按品质分档）/ 击毁爆炸
##     Ambience  阶段环境：准备倒计时 / 开战读秒 / 结算
##     Music     背景音乐：准备段 / 战斗段
##
##  分开的理由不是「看着整齐」：玩家在准备阶段会反复进出商店、翻看舰船
##  详情，那时打击音早停了而 BGM 还在响；如果只有一条总线，调音量就变成
##  「要么都吵要么都听不见」。三条独立音量是**可调旋钮清单**的落点。
##
## ── 为什么用 AudioStreamPlayer 池而不是 AudioStreamPlayer3D ───────
##  自走棋的战术视角是**俯视全局**，声音不该按相机距离衰减 ——
##  相机拉远时「听不见远处的爆炸」会让玩家漏掉战况。
##  EVE 自己的战斗音也是**全向汇报**（tactical overview 的听觉版本），
##  所以这里刻意不做 3D 衰减，只用音量 + 随机音高做「层次感」。
##
## ── 无头环境下的行为（验收必须能跑）────────────────────────────
##  `--headless` 没有音频设备，AudioServer 仍然存在且能 add_play 不报错，
##  但**不会有声音**。所以验收不验「有没有响」，只验：
##    · `play_*` 调用链有没有通（`stats()` 里的计数器）
##    · 节流有没有生效（开火 200 次 → sfx_played 远小于 200）
##  这与 `eve_battle_fx.active_count()` 是同一套验收哲学：
##  **把「发生过」变成可断言的整数**。
##
## 变更清单（阶段 D 子项 ④）：
##   - 三条总线（SFX / Ambience / Music）+ 独立音量
##   - 音效池（SFX_POOL 个 player 轮转）+ 每类节流窗口
##   - 打击反馈：开火 / 命中 7 档品质映射 / 击毁爆炸
##   - 阶段环境：倒计时滴答 / 开战 / 结算 / 节点推进
##   - 背景音乐：准备段 / 战斗段交叉淡入
##   - 音源缺失时**静默降级**（不报错、不崩，只记一次日志）

# ══════════════════════════════════════════════════════════════════
#  总线与池
# ══════════════════════════════════════════════════════════════════

const BUS_SFX := &"SFX"
const BUS_AMB := &"Ambience"
const BUS_MUSIC := &"Music"
## 总音量走引擎的 Master 总线 —— 三条分总线都 send 到它下面，
## 所以它是「一处调、三条一起变」的真实总闸，不必在三条上各乘一次系数
## （各乘一次会导致 master 与分档互相污染：调完总音量，音效/音乐的**比例**也变了）。
const BUS_MASTER := &"Master"

## 短音（开火 / 命中）同时可播的条数。
##
## ⚠️ 这个数是「同时发声数」不是「总音效数」：BOSS 战 6v6、30Hz 开火时
##    每帧都有新开火，池子太小会**互相打断**（后一个 play 把前一个顶掉，
##    听起来像卡带）；太大则混成一片白噪音。
##    12 是实测下来「密集但有层次」的档位。
const SFX_POOL := 12

## 击毁爆炸单独一个池 —— 爆炸音长（0.5~2s），和短音抢池子会让开火音
## 在爆炸期间集体消失。
const BOOM_POOL := 4

## 阶段环境（倒计时 / 开战 / 结算）单独一个池，挂在 BUS_AMB 上 ——
## 不能复用 SFX 池，否则环境音会走打击总线（音量被打击旋钮接管）。
const AMB_POOL := 4

## 音乐用两个 player 做交叉淡入（A 响 B 备），不是池
const MUSIC_FADE := 1.2

# ══════════════════════════════════════════════════════════════════
#  节流窗口（秒）
# ══════════════════════════════════════════════════════════════════
#
# ⚠️ 节流是**必须**的，不是优化：30Hz × 12 艘船 = 每秒 360 次开火信号。
#    不节流的话声音层会变成一堵噪音墙，玩家反而听不出战况。
#    Windows 的取值逻辑是「人类能分辨的相邻同种声音间隔」——
#    开火比命中密（开火是连续动作，命中有品质差异需要被听见）。

const THROTTLE_FIRE := 0.045
const THROTTLE_HIT := 0.040
const THROTTLE_BOOM := 0.010

## 每个节流窗口内**允许**放几声（令牌桶容量）。
##
## ⚠️ 只有「窗口」没有「容量」会踩一个很具体的坑：战斗是固定步长推进的，
##    同一 tick 里 6 艘船同时开火 —— 它们的 `sim.elapsed` **完全相同**，
##    于是窗口节流把 6 声压成 1 声。实测 12 秒战斗 32 次开火只响 8 声，
##    听感是「零零星星放了两枪」，而画面上是六艘船在齐射。
##    容量 = 3 是「同一瞬间最多三声」：既不成噪音墙，也不把齐射吃掉。
const BURST_FIRE := 3
const BURST_HIT := 3
const BURST_BOOM := 2
## 命中品质越高，节流窗口越短 —— 重击绝不能被吞掉。
## 下标 = 品质档（EveCombatCore.HitQuality 7 档）
const THROTTLE_BY_QUALITY: Array[float] = [0.12, 0.10, 0.06, 0.045, 0.035, 0.022, 0.016]

# ══════════════════════════════════════════════════════════════════
#  音频目录
# ══════════════════════════════════════════════════════════════════

const DIR_SFX := "res://assets/audio/sfx/"
const DIR_AMB := "res://assets/audio/ambience/"
const DIR_MUS := "res://assets/audio/music/"

## 打击音表：键 = 逻辑名，值 = 该类的候选文件名（随机挑一个）。
##
## ⚠️ 候选是**列表**不是单文件：同一件事重复放同一个采样，玩家 3 秒内
##    就会听出「复读机」。EVE 原始 bank 里每类都有几十个变体，我们取几个
##    轮换，代价是 0 而收益是「听起来像真的在打」。
var _sfx_bank: Dictionary = {}
var _amb_bank: Dictionary = {}
var _mus_bank: Dictionary = {}

# ══════════════════════════════════════════════════════════════════
#  运行时状态
# ══════════════════════════════════════════════════════════════════

var _sfx_players: Array[AudioStreamPlayer] = []
var _boom_players: Array[AudioStreamPlayer] = []
var _amb_players: Array[AudioStreamPlayer] = []
var _music_a: AudioStreamPlayer
var _music_b: AudioStreamPlayer

## ⚠️ 独立 RNG：音效挑变体 / 抖音高**必须**走它，绝不能碰全局 randi()。
##    理由不是洁癖 —— 战斗 sim 的命中判定吃全局随机序列，音效一插手，
##    同一个种子跑出来的战斗结果就变了，验收会变成玄学。
##    这条由 tools/verify_audio.gd 的「随机隔离」用例守着。
var _rng := RandomNumberGenerator.new()
var _music_active: AudioStreamPlayer
var _music_idle: AudioStreamPlayer
var _music_current := ""

## 节流：键 -> 最近几次播放的时间戳（令牌桶，见 `_throttle`）
var _recent: Dictionary = {}

## 可断言的计数器（验收用）
var _count := {
	"fire": 0, "hit": 0, "boom": 0, "amb": 0, "music": 0, "missing": 0,
	"fire_throttled": 0, "hit_throttled": 0, "boom_throttled": 0,
}

## 总音量（0~1）。1.0 = 不额外衰减，分档音量原样生效。
var volume_master := 1.0

## 音量（0~1），外部可调。
##
## ⚠️ 这**不是**线性增益 —— `_set_bus_vol` 里走的是平方曲线（`gain = lin²`），
##    所以「降一半响度」= 这里乘 `1/√2 ≈ 0.707`，**不是乘 0.5**。
##    乘 0.5 会变成 −12 dB（听感上只剩四分之一），过头了。
##    当前这组 = 原始 `0.85 / 0.55 / 0.45` 统一 −6 dB（各乘 1/√2，比例不变）：
##      sfx   0.60 → 20·log10(0.60²) = −8.9 dB（原 −2.8 dB）
##      amb   0.39 → −16.4 dB（原 −10.4 dB）
##      music 0.32 → −19.8 dB（原 −13.9 dB）
##    要再整体挪一档就三个数一起乘同一个系数（保持 sfx : amb : music 的配比）。
var volume_sfx := 0.60
var volume_amb := 0.39
var volume_music := 0.32

## 全局静音开关（设置窗用）
var muted := false

## 音源缺失计数 —— 只记一次，避免刷屏
var _missing_reported := {}


# ══════════════════════════════════════════════════════════════════
#  生命周期
# ══════════════════════════════════════════════════════════════════

## ══════════════════════════════════════════════════════════════
##  音效总开关（2026-10-01 用户要求）
## ══════════════════════════════════════════════════════════════
##  用户原话：「音效和攻击的动画都不是认真做的，所以看着听着很别扭，
##             先全部关闭吧，**是关闭，不是删除**，我怕以后会用到。」
##
##  ⛔ 这是**开关**不是删除：音源银行、总线、节流、「缺源计数」逻辑**全部保留**，
##     把 `sfx_enabled` 置 true 即完整恢复。以后做「设置窗里的音效开关」
##     直接把这一项挂上去就行。
##
##  只管 **sfx + amb**（开火 / 命中 / 爆炸 / 阶段 / 滴答 / 读秒 / 结算 / 节点推进）；
##  ⛔ **不碰 music** —— BGM 是从 EVE 客户端正经解出来的素材，用户没抱怨过。
##
##  ⚠️ 为什么是 `var` 而不是 `const`：验收要能**双向测** ——
##     打开时断言「播了、计数 +1」，关掉时断言「一声没响、计数不变」。
const SFX_ENABLED_DEFAULT := false
var sfx_enabled := SFX_ENABLED_DEFAULT


## 音效是否被总开关挡住。每个公开的 play_* 第一行都要过这一关。
##
## ⛔ **不要把它塞进 `_play_from()`** —— 那会让 `_play_from` 返回 false，
##    调用方随即走 `_note_missing()`，于是「关掉音效」反而刷一屏「音源缺失」告警。
func sfx_off() -> bool:
	return not sfx_enabled


func _ready() -> void:
	_ensure_buses()
	_build_banks()
	_build_players()
	_apply_volumes()


## 建三条总线（幂等 —— 已经存在就不重复建）。
##
## ⚠️ 用 `AudioServer.add_bus` 而不是在 `default_bus_layout.tres` 里配：
##    后者需要额外资源文件，而本工程**没有**该文件（一直是单总线默认布局）。
##    代码建总线还有一个好处：三条总线的父子关系（都挂在 Master 下）
##    在这里一眼可见，不必去翻二进制布局文件。
func _ensure_buses() -> void:
	for b in [BUS_SFX, BUS_AMB, BUS_MUSIC]:
		var idx := AudioServer.get_bus_index(b)
		if idx < 0:
			AudioServer.add_bus()
			idx = AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, b)
			AudioServer.set_bus_send(idx, &"Master")


## 装载音源清单。
##
## ⚠️ 目录可能**不存在**（音源尚未解包 / 用户删了 assets/audio）。
##    这里必须静默降级 —— 阶段 D 的验收脚本要能在没有音频资产的
##    持续集成环境里跑通。缺音源 = 不播，不是崩。
func _build_banks() -> void:
	_sfx_bank = _scan_dir(DIR_SFX)
	_amb_bank = _scan_dir(DIR_AMB)
	_mus_bank = _scan_dir(DIR_MUS)


## 扫一个目录，返回 {逻辑名: [AudioStream, ...]}。
##
## 命名约定：`<逻辑名>_<序号>.ogg` —— 例如 `fire_01.ogg` / `hit_03.ogg`。
## 逻辑名取第一个下划线之前的部分，序号只用来区分变体。
func _scan_dir(dir_path: String) -> Dictionary:
	var out: Dictionary = {}
	var d := DirAccess.open(dir_path)
	if d == null:
		_missing_reported[dir_path] = true
		return out
	d.list_dir_begin()
	var fn := d.get_next()
	while fn != "":
		if not d.current_is_dir() and fn.get_extension().to_lower() == "ogg":
			var base := fn.get_basename()
			# 逻辑名 = 去掉末尾的 _NN 变体号
			var logical := base
			var us := base.rfind("_")
			if us > 0:
				var tail := base.substr(us + 1)
				if tail.is_valid_int():
					logical = base.substr(0, us)
			var stream := _load_stream(dir_path + fn)
			if stream != null:
				if not out.has(logical):
					out[logical] = []
				out[logical].append(stream)
		fn = d.get_next()
	d.list_dir_end()
	return out


func _load_stream(path: String) -> AudioStream:
	if not ResourceLoader.exists(path):
		return null
	var r := ResourceLoader.load(path)
	if r is AudioStream:
		return r as AudioStream
	return null


## 建 player 池。
func _build_players() -> void:
	for i in SFX_POOL:
		var p := AudioStreamPlayer.new()
		p.bus = BUS_SFX
		p.name = "Sfx%d" % i
		add_child(p)
		_sfx_players.append(p)
	for i in BOOM_POOL:
		var p := AudioStreamPlayer.new()
		p.bus = BUS_SFX
		p.name = "Boom%d" % i
		add_child(p)
		_boom_players.append(p)
	# ⚠️ 环境音单独一池并挂 BUS_AMB：挂到 SFX 池上会被打击音量旋钮接管，
	#    玩家在准备阶段调低打击音就听不见倒计时了。
	for i in AMB_POOL:
		var p := AudioStreamPlayer.new()
		p.bus = BUS_AMB
		p.name = "Amb%d" % i
		add_child(p)
		_amb_players.append(p)

	_music_a = AudioStreamPlayer.new()
	_music_a.bus = BUS_MUSIC
	_music_a.name = "MusicA"
	add_child(_music_a)
	_music_b = AudioStreamPlayer.new()
	_music_b.bus = BUS_MUSIC
	_music_b.name = "MusicB"
	add_child(_music_b)
	_music_active = _music_a
	_music_idle = _music_b


## 外部改音量 / 静音的**唯一入口**。
##
## ⚠️ 直接写 `audio.volume_sfx = 0.3` 是**不会生效**的 ——
##    总线音量只在 `_set_bus_vol` 里被写进 AudioServer，改了变量没人读它，
##    于是「拖动滑块没反应」且**不报错**。设置窗要走这两个方法。
func set_volume(kind: StringName, v: float) -> void:
	match kind:
		&"master":
			volume_master = clampf(v, 0.0, 1.0)
		&"sfx":
			volume_sfx = clampf(v, 0.0, 1.0)
		&"amb":
			volume_amb = clampf(v, 0.0, 1.0)
		&"music":
			volume_music = clampf(v, 0.0, 1.0)
		_:
			push_warning("[EveAudio] 未知音量通道：%s" % kind)
			return
	_apply_volumes()


func set_muted(on: bool) -> void:
	muted = on
	_apply_volumes()


func _apply_volumes() -> void:
	# ⚠️ Master 必须**最后**写：三条分总线的 send 目标就是它，
	#    顺序反了不会报错，但同一帧内会先静音再解除，听感上是一次爆音。
	_set_bus_vol(BUS_SFX, volume_sfx)
	_set_bus_vol(BUS_AMB, volume_amb)
	_set_bus_vol(BUS_MUSIC, volume_music)
	_set_bus_vol(BUS_MASTER, volume_master)


## 当前四档音量的快照（设置窗回写 / 验收断言用）。
##
## ⚠️ 设置窗**必须**从这里读初值而不是自己写死一份 ——
##    写死的话，「音频层默认值改了而窗里没改」就会变成静默的不同步。
func volumes() -> Dictionary:
	return {
		"master": volume_master,
		"sfx": volume_sfx,
		"amb": volume_amb,
		"music": volume_music,
		"muted": muted,
	}


func _set_bus_vol(bus: StringName, v: float) -> void:
	var idx := AudioServer.get_bus_index(bus)
	if idx < 0:
		return
	var lin := 0.0 if muted else maxf(0.0, minf(1.0, v))
	# 线性音量对听感太"陡"，用平方律（感知上是等步的）
	AudioServer.set_bus_volume_db(idx, linear_to_db(lin * lin) if lin > 0.0 else -80.0)
	AudioServer.set_bus_mute(idx, muted or lin <= 0.0)


# ══════════════════════════════════════════════════════════════════
#  打击反馈（战斗 sim 的三条信号）
# ══════════════════════════════════════════════════════════════════

## 开火音。
##
## `quality` 用来选音色族：低档用轻武器、高档用重武器。
## 未命中（MISS）也响 —— 但音色不同（更闷、更短），
## 让玩家**听着**就知道这一轮是空放还是打中。
func play_fire(quality: int = 3, pitch_jitter: bool = true) -> void:
	if sfx_off():
		return
	if _throttle("fire", THROTTLE_FIRE, BURST_FIRE):
		return
	var key := _fire_key(quality)
	if not _play_from(_sfx_bank, key, _sfx_players, 0.96, 1.06, pitch_jitter):
		# 退到通用开火音（音源未解包时静默返回）
		if not _play_from(_sfx_bank, "fire", _sfx_players, 0.96, 1.06, pitch_jitter):
			return
	_count["fire"] += 1


## 命中音。`quality` = EveCombatCore.HitQuality 的 7 档。
##
## ⚠️ 节流窗口按品质分档（`THROTTLE_BY_QUALITY`）：
##    MISS 可以密集地吞，WRECKING（结构击穿）绝不能吞 ——
##    玩家最该听见的就是那一发。
func play_hit(quality: int, layer: StringName = &"") -> void:
	if sfx_off():
		return
	var q := clampi(quality, 0, THROTTLE_BY_QUALITY.size() - 1)
	if _throttle("hit", THROTTLE_BY_QUALITY[q], BURST_HIT):
		return
	var key := _hit_key(q, layer)
	if not _play_from(_sfx_bank, key, _sfx_players, 0.94, 1.08, true):
		if not _play_from(_sfx_bank, "hit", _sfx_players, 0.94, 1.08, true):
			return
	_count["hit"] += 1


## 击毁爆炸。
func play_boom() -> void:
	if sfx_off():
		return
	if _throttle("boom", THROTTLE_BOOM, BURST_BOOM):
		return
	if not _play_from(_sfx_bank, "boom", _boom_players, 0.92, 1.04, true):
		return
	_count["boom"] += 1


## 品质档 -> 开火音色族。
##
## 类比 EVE 的武器谱系：低档 = 小型速射（清脆）、高档 = 大型炮（沉）。
func _fire_key(quality: int) -> String:
	var q := clampi(quality, 0, 6)
	if q <= 1:
		return "fire_light"
	if q <= 3:
		return "fire"
	if q <= 5:
		return "fire_heavy"
	return "fire_capital"


## 命中音色族。
##
## 优先按**真实受击层**选（能确定层时由场景传 layer）；
## 层未知时退回品质映射（与 EveBattleFx.QUALITY_COLORS 的口径对应）：
## MISS 暗灰 / PENETRATING 护盾蓝 / SMASHING 装甲金 / WRECKING 结构橙红。
## ⚠️ 品质≠层：品质只是兜底，真实层优先。
func _hit_key(quality: int, layer: StringName = &"") -> String:
	if layer == &"shield":
		return "hit_shield"
	if layer == &"armor":
		return "hit_armor"
	if layer == &"hull":
		return "hit_structure"
	match quality:
		0:
			return "miss"
		1, 2:
			return "hit_light"
		3:
			return "hit"
		4:
			return "hit_shield"
		5:
			return "hit_armor"
		_:
			return "hit_structure"


# ══════════════════════════════════════════════════════════════════
#  阶段环境音
# ══════════════════════════════════════════════════════════════════

## 阶段切换音。phase 用 EveRunState.Phase 的整数。
func play_phase(phase: int) -> void:
	if sfx_off():
		return
	var key := ""
	match phase:
		0:
			key = "phase_prep"
		1:
			key = "phase_battle"
		2:
			key = "phase_resolve"
		_:
			key = "phase_end"
	# 阶段音不节流 —— 一局里只会响几次，每次都该被听见
	if _play_from(_amb_bank, key, _amb_players, 0.98, 1.02, false):
		_count["amb"] += 1
	else:
		_note_missing(key)


## 准备阶段的倒计时滴答。`seconds_left` 用来分档：
## 最后 5 秒音调更高、更急（云顶同款提示）。
func play_tick(seconds_left: int) -> void:
	if sfx_off():
		return
	var key := "tick_urgent" if seconds_left <= 5 else "tick"
	if _play_from(_amb_bank, key, _amb_players, 1.0, 1.0, false):
		_count["amb"] += 1
	else:
		_note_missing(key)


## 开战读秒（3 / 2 / 1），`n` = 剩余数。
##
## ⚠️ 缺音源时**不计数**：早期实现无论播没播都 `amb += 1`，
##    验收看到「倒计时响了 3 次」其实一声没响 —— 这是静默的假通过。
func play_countdown(n: int) -> void:
	if sfx_off():
		return
	var key := "count_%d" % clampi(n, 1, 3)
	if _play_from(_amb_bank, key, _amb_players, 1.0, 1.0, false):
		_count["amb"] += 1
		return
	# 没有 count_N 就退到通用滴答；连滴答也没有才算真的缺
	if _play_from(_amb_bank, "tick", _amb_players, 1.0, 1.0, false):
		_count["amb"] += 1
		return
	_note_missing(key)


## 节点推进 / 结算
func play_resolve() -> void:
	if sfx_off():
		return
	if _play_from(_amb_bank, "resolve", _amb_players, 1.0, 1.0, false):
		_count["amb"] += 1
	else:
		_note_missing("resolve")


func play_node_advance() -> void:
	if sfx_off():
		return
	if _play_from(_amb_bank, "node", _amb_players, 1.0, 1.0, false):
		_count["amb"] += 1
	else:
		_note_missing("node")


## 记一次「音源缺失」。只记一次避免刷屏，但**计数**要准 ——
## 验收靠 `stats()["missing"]` 判断「到底有没有真的播出来」。
func _note_missing(key: String) -> void:
	_count["missing"] = int(_count.get("missing", 0)) + 1
	if not _missing_reported.has(key):
		_missing_reported[key] = true
		push_warning("[EveAudio] 音源缺失（静默跳过）：%s" % key)


# ══════════════════════════════════════════════════════════════════
#  背景音乐
# ══════════════════════════════════════════════════════════════════

## 切 BGM。`which` = "prep" / "battle" / ""（停）。
##
## 交叉淡入：新曲在 idle player 上起播，两个 player 的音量在 MUSIC_FADE
## 秒内互换。**不要**直接 stop 再 play —— 那会有一个可听见的断口，
## 而准备↔战斗是每回合都发生的切换，断口会很烦。
func play_music(which: String) -> void:
	if which == _music_current:
		return
	if which == "":
		_music_current = ""
		_music_fading = false
		_music_fade_t = 0.0
		# ⚠️ 两个 player 都要停：只停 active 的话，正在淡入的 idle 会留下一首
		#    「切了歌但还在响」的幽灵 BGM，且不报错（老 bug）。
		if _music_a != null:
			_music_a.stop()
		if _music_b != null:
			_music_b.stop()
		return
	var list: Array = _mus_bank.get(which, [])
	if list.is_empty():
		_note_missing(which)
		return
	var st: AudioStream = list[_rng.randi() % list.size()]
	# BGM 必须循环：准备段可能待 40 秒，而 EVE 的曲子只有 1~3 分钟，
	# 不 loop 的话放完就静音，玩家会以为游戏卡了。
	_set_loop(st, true)
	_music_idle.stream = st
	_music_idle.volume_db = -60.0
	_music_idle.play()
	# 淡入淡出交给 _process
	_music_fading = true
	_music_fade_t = 0.0
	_music_current = which
	_count["music"] += 1


var _music_fading := false
var _music_fade_t := 0.0


func _process(delta: float) -> void:
	if not _music_fading or _music_active == null:
		return
	_music_fade_t += delta
	var k := clampf(_music_fade_t / MUSIC_FADE, 0.0, 1.0)
	# 交叉：老曲 1→0，新曲 0→1
	_music_active.volume_db = linear_to_db(maxf(0.0001, 1.0 - k))
	_music_idle.volume_db = linear_to_db(maxf(0.0001, k))
	if k >= 1.0:
		_music_fading = false
		_music_active.stop()
		var t := _music_active
		_music_active = _music_idle
		_music_idle = t


# ══════════════════════════════════════════════════════════════════
#  内部工具
# ══════════════════════════════════════════════════════════════════

## 节流用的时间基准（秒）。
##
## ⚠️ 这是**模拟器时间**，不是墙钟时间。用墙钟的后果在快进/倍速下才会暴露：
##    无头验收一次 `debug_fast_forward_battle(12.0)` 在几百毫秒墙钟内跑完
##    12 秒战斗，墙钟节流于是把 12 秒里的上百次开火**压成 1~2 声** ——
##    不报错，只是「战斗听起来像没打」。玩家开倍速时遇到的是同一个 bug。
##    由战斗场景在每次开火/击毁回调里喂 `sim.elapsed`。
var _clock := 0.0


## 喂当前（模拟）时间。`_on_shot_fired` / `_on_unit_destroyed` 里调用。
func set_clock(seconds: float) -> void:
	_clock = seconds


## 节流：同一 key 在 window 秒内最多放 burst 声。返回 true = 应被吞掉。
##
## 令牌桶而不是「一刀切冷却」：桶里存最近几次播放的时间戳，
## 窗口外的自动出桶，桶满了才吞。
func _throttle(key: String, window: float, burst: int = 1) -> bool:
	# `_clock <= 0` 说明还没接过战斗时间（准备阶段 / 单元测试），退化到墙钟
	var now := _clock if _clock > 0.0 else Time.get_ticks_msec() / 1000.0
	var arr: Array = _recent.get(key, [])
	while not arr.is_empty() and now - float(arr[0]) >= window:
		arr.pop_front()
	if arr.size() >= burst:
		_count[key + "_throttled"] = int(_count.get(key + "_throttled", 0)) + 1
		return true
	arr.append(now)
	_recent[key] = arr
	return false


## 从 bank 里挑一个变体在池中轮转播放。返回 true = 播了。
##
## ⚠️ 选 player 用「最久未用优先」而不是简单轮转：
##    轮转在池满时会打断某个还没放完的音；
##    「找当前最闲的」让长音自然占住自己的 player。
func _play_from(bank: Dictionary, key: String, pool: Array[AudioStreamPlayer],
		pitch_min: float, pitch_max: float, jitter: bool) -> bool:
	var list: Array = bank.get(key, [])
	if list.is_empty():
		return false
	var p := _pick_player(pool)
	if p == null:
		return false
	# ⚠️ 独立 RNG：挑变体与音高抖动都走 _rng，不碰全局 randi()/randf_range，
	#    否则会让战斗 sim 的随机序列被音效打乱（验收用随机隔离测试守这条）。
	p.stream = list[_rng.randi() % list.size()]
	p.pitch_scale = _rng.randf_range(pitch_min, pitch_max) if jitter else 1.0
	p.play()
	return true


func _pick_player(pool: Array[AudioStreamPlayer]) -> AudioStreamPlayer:
	if pool.is_empty():
		return null
	var best: AudioStreamPlayer = null
	var best_end := -INF
	for p in pool:
		if not p.playing:
			return p
		var st := p.stream
		if st == null:
			return p
		# end = 已播位置 - 时长：越接近 0 表示剩余时间越少。
		# ⚠️ 旧实现取「剩余最长」的，会把最忙的 player 抢来打断；
		#    这里取剩余最短（end 最大）的那个，打断代价最小。
		var end := p.get_playback_position() - float(st.get_length())
		if end > best_end:
			best_end = end
			best = p
	# 全都在响 —— 挑最接近结束的那个（打断的代价最小）
	return best


## 设循环。
##
## ⚠️ 属性名不统一：`AudioStreamOggVorbis` / `AudioStreamMP3` 用 `loop`，
##    而 `AudioStreamWAV` 用 `loop_mode`。写死其中一个，在另一种流上会
##    **静默失效不报错**（BGM 放一遍就停）。两种都试一遍最稳。
func _set_loop(st: AudioStream, on: bool) -> void:
	if st == null:
		return
	if "loop" in st:
		st.set("loop", on)
	if "loop_mode" in st:
		st.set("loop_mode",
				AudioStreamWAV.LOOP_FORWARD if on else AudioStreamWAV.LOOP_DISABLED)


## 验收 / 调试用：可断言的计数器快照。
func stats() -> Dictionary:
	var d := _count.duplicate()
	d["has_sfx"] = not _sfx_bank.is_empty()
	d["has_amb"] = not _amb_bank.is_empty()
	d["has_music"] = not _mus_bank.is_empty()
	d["music_current"] = _music_current
	return d


## 验收用：重开一局时清零计数（不清音源）
func reset_stats() -> void:
	for k in _count.keys():
		_count[k] = 0
	_recent.clear()
	_clock = 0.0


## 立即停掉一切（撤离 / 重开）
func stop_all() -> void:
	for p in _sfx_players:
		if p.playing:
			p.stop()
	for p in _boom_players:
		if p.playing:
			p.stop()
	for p in _amb_players:
		if p.playing:
			p.stop()
	if _music_a != null:
		_music_a.stop()
	if _music_b != null:
		_music_b.stop()
	_music_current = ""
	_music_fading = false
