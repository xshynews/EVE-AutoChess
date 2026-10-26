extends Node3D

## EVE 自走棋 —— 战斗打击特效层（阶段 D）
##
## ══════════════════════════════════════════════════════════════════
##  它解决什么
## ══════════════════════════════════════════════════════════════════
##  阶段 A~C 打通的是「数字对不对」；这个文件的职责是让玩家**看得见**那些数字。
##  在此之前，`EveBattleSimulator.shot_fired` 每帧都在发，但没有任何东西听它 ——
##  战斗在玩家眼里就是「几艘船在飘，偶尔有一艘不见了」。
##
##  三类反馈（对应 sim 的三个信号语义）：
##    · 开火线   ★ 2026-10-01 改版：**黄色长短不一的细线**，
##              一次开火亮一条，两端分别连着开火方与被打击方。
##    · 命中爆点 打中的位置闪一小团光
##    · 击毁爆炸 船体位置一大团橙红扩散 + 短暂的强光
##
## ── 为什么不用 GPUParticles3D ─────────────────────────────────────
##  粒子系统要预热、要材质、要 process_material，无头环境下
##  （`--headless` 没有 GPU）行为与实机不一致，验收会拿不到稳定判据。
##  这里全部用 **QuadMesh + 自绘材质** 手推生命周期：
##  每帧改 alpha / scale，到寿命就 queue_free。
##  好处是**任何环境都能跑**，而且「当前活跃特效数」是个可直接断言的整数
##  （`active_count()`）—— 验收不必去数像素。
##
## ── 为什么挂在 Node3D 而不是 Control ──────────────────────────────
##  开火线与爆点都在世界空间里，会随相机远近自然缩放。
##  伤害**数字**则必须固定在屏幕空间（跟着船缩放的话，推近时会糊满屏），
##  那一层在 HUD 里（eve_damage_feed.gd），刻意分家。

## 命中爆点存活时间
##
## ★ 2026-10-17 打击感改造：0.28 → **0.16**。
##   「疼」来自「短、亮、干脆」而不是「大、久」。旧版 0.28 秒 + 外扩 1.8 倍，
##   实际读起来是一块慢慢变大的色板（实测占中央区 4~9%），而不是一次打击。
const HIT_LIFE := 0.16
## 护盾涟漪存活时间
##
## ⚠️ 比命中爆点长一点：护盾是「一层壳被点亮」，扩散要看得见；
##    和爆点同寿命会觉得只是闪了一下、没读出「这层还在扛」。
const SHIELD_LIFE := 0.32
## 击毁爆炸存活时间
const BOOM_LIFE := 0.62

## ══════════════════════════════════════════════════════════════════
##  ★ 特效尺寸（2026-10-17，打击感改造的核心改动）
## ══════════════════════════════════════════════════════════════════
##  口径：**世界单位**。实测换算 —— 2.6 世界单位的舰船在实战取景下 ≈ 121 px
##  （`probe_impact` 逐艘投影实测），即 **1 世界单位 ≈ 46 px**。
##
##  旧版命中爆点 base 0.9~2.2、再乘 1.8 倍外扩 ⇒ 1.6~4.0 世界单位
##  ⇒ 屏幕上 74~184 px 的**实心方块**，比整艘船还大 —— 这就是「一块板盖住船」。
##  新版按「屏幕 7~17 px 的星芒」反解：0.16~0.37 世界单位。
##
##  ⚠️ 这不是「调小一点」的审美微调，而是**量纲修正**：
##     特效尺寸必须相对舰船（0.06~0.14 × 船长），不能是绝对像素拍出来的数。
##  ⛔ 改这几个值必须重跑 `probe_impact` 出对照图，别只改数字。
const HIT_SIZE_BASE := 0.16
const HIT_SIZE_PER_TIER := 0.035
## 击毁：白热核 + 冲击波环。环可以是船的 0.5 倍宽（爆炸本来就该比船大一点）。
const BOOM_CORE_SIZE := 0.42
const BOOM_RING_SIZE := 1.25
## 护盾：真球壳，直径略小于舰船长（2.6），包住船体中心即可。
const SHIELD_DIAMETER := 2.05

## 程序化形状 shader（无贴图：任何环境都能跑，验收不必依赖资源导入）
const FX_SHADER := preload("res://scripts/visual/fx_impact.gdshader")
const SHIELD_SHADER := preload("res://scripts/visual/fx_shield.gdshader")

## ══════════════════════════════════════════════════════════════════
##  ★ 开火线（2026-10-01 用户定案 · 第二版）
## ══════════════════════════════════════════════════════════════════
##  用户原话：「攻击还是要有点特效，先统一成如同黄色长短不一的细线，
##             亮一下等于开火一次，线两端连着开火方与被打击方。」
##
##  ── 与旧版（已废弃）的区别 ──────────────────────────────────────
##  旧版是「竖线闪屏」：`QuadMesh` 加 `BILLBOARD_ENABLED` —— billboard 绕的是
##  相机轴，所以一条斜着飞出去的弹道在屏幕上会**转成竖直**再旋转，
##  观感就是「屏幕闪了一下竖条」。用户说的「看着很别扭」就是指这个。
##
##  ⇒ 新版**不用 billboard**：把方片当成「贴在弹道上的墙面」，
##     直接以弹道方向为法线摆好，再用 `CULL_DISABLED` 保证两边都看得见。
##     这样无论相机怎么转，线都**始终躺在弹道上**（两端真的连着火方与受击方）。
##
##  ── 「长短不一」怎么来 ──────────────────────────────────────────
##  三档长度来源互相独立，避免所有线看起来一样长：
##    ① 档位（0~6）：打得越狠，线越长、越亮 —— 这条是给玩家读伤害的；
##    ② 实时距离：远处开火自然长，是真实弹道长度；
##    ③ 抖动：每发 ±18% 随机，让齐射看起来是「一片弹幕」而不是一根尺子。
##
##  ⚠️ 未命中的线**画到中段（62%）**，不画到目标身上 —— 画到目标等于
##     告诉玩家「打中了」，而伤害数字又是 0，两条信息互相打脸。
##     见 `spawn_tracer()` 的说明。
## ══════════════════════════════════════════════════════════════════
const TRACER_COLOR := Color(1.0, 0.85, 0.28)          ## 统一的亮黄
const TRACER_MISS_COLOR := Color(1.0, 0.74, 0.30, 0.45)  ## 未命中：暗一档、半透明
## 线的视觉宽度（世界单位）。
##
## ★ 2026-10-17：0.07 → **0.105**。实测 1 世界单位 ≈ 46 px（船身 121 px / 2.6 单位），
##   0.07 只有 **3 px**，而开火线是 0.15 秒就灭的瞬时元素 —— 3 px 在亮星云上等于看不见，
##   玩家实际只看到"莫名闪一下的爆点"。这是「打击感单薄」的第二大人为原因。
## ⚠️ 上限也要有：太粗会让高射速弹幕糊成一片黄墙（`MAX_FX` 也兜不住亮度堆积）。
const TRACER_WIDTH := 0.105
## 三档长度。命中时按档位取一档；未命中固定用最短那档（打空了不该有长弹道）。
const TRACER_LEN_HIT := [0.42, 0.68, 0.95]
## 未命中的长度占「开火方 → 被击方」真实距离的比例
const TRACER_MISS_FRACTION := 0.62
## 长度抖动幅度（±18%）
const TRACER_JITTER := 0.18
## 线亮起 → 灭掉的时长。用户要求「亮一下 = 开火一次」，所以刻意很短。
##
## ★ 2026-10-17：0.15 → **0.10**。理由不是"更短更帅"，而是**因果顺序**：
##   线必须比命中爆点（0.16）先消失，玩家才读得出「打出去 → 打中」；
##   两者同寿命时，画面上是"线和大方块同时出现"，打击感变成一坨。
const TRACER_FLASH := 0.10

## 线长上限（世界单位）。
##
## ⚠️ 必须有：场上追逃时两船可能相距好几十单位，一条横跨全屏的线
##    会把整个战场盖住。截断后是「一段弹道」而不是「一条分割线」。
const TRACER_MAX_LEN := 4.2
const ARTILLERY_SHADER := preload("res://scripts/visual/fx_artillery_streak.gdshader")
const ARTILLERY_FRACTION := 0.55
const ARTILLERY_MIN_LEN := 2.0
## 不截断：炮击亮痕必须从攻击船完整连接到护盾锚点。
const ARTILLERY_MAX_LEN := 1000.0
const ARTILLERY_WIDTH := 0.20
const ARTILLERY_LIFE := 0.11

## 运行时可改的炮击颜色。改这两项即可换整套亮痕色调。
static var artillery_core_color := Color(0.88, 0.96, 1.0, 1.0)
static var artillery_edge_color := Color(0.10, 0.38, 1.0, 1.0)

## 特效上限 —— 超过就直接丢弃最老的。
##
## ⚠️ 必须有这个上限：BOSS 节点 6v6、30Hz 开火，一秒钟能产生几百条开火线。
##    无上限的话每帧都在 add_child/queue_free 上百个节点，
##    无头验收会明显变慢，实机上则是掉帧。
const MAX_FX := 140

## 命中判定档位的显示配色。
##
## ⚠️ 开火线**不用**这张表了（2026-10-01 起统一成黄色，见 TRACER_COLOR）——
##    一次齐射里有好几档混在一起，每条线一个颜色会让整片弹幕变成彩虹，
##    玩家反而读不出「谁打了谁」。
## ⛔ 这张表仍然被 `spawn_hit()`（命中爆点）使用，**不许删**。
##    与 EveCombatCore.HitQuality 一一对应（MISS/BARELY/LIGHT/HIT/
##    PENETRATING/SMASHING/WRECKING 共 7 档），改那边必须回来改这边。
const QUALITY_COLORS: Array[Color] = [
	Color(0.44, 0.52, 0.56),   # MISS       暗灰
	Color(0.62, 0.70, 0.72),   # BARELY     浅灰
	Color(0.70, 0.82, 0.86),   # LIGHT      淡青
	Color(0.55, 0.78, 0.82),   # HIT        强调青
	Color(0.35, 0.70, 0.90),   # PENETRATING 护盾蓝
	Color(0.85, 0.68, 0.28),   # SMASHING   装甲金
	Color(0.95, 0.45, 0.30),   # WRECKING   结构橙红
]

## 已激活的特效：元素 = {"node": Node3D, "t": float, "life": float, "kind": int}
var _fx: Array[Dictionary] = []

## 米 → 世界单位（与 eve_ship_visual.METERS_PER_UNIT 同一个口径）
const METERS_PER_UNIT := 1000.0

enum Kind { TRACER, HIT, SHIELD, BOOM }


## 当前活跃特效数（验收断言用）
func active_count() -> int:
	var n := 0
	for f in _fx:
		if is_instance_valid(f["node"]):
			n += 1
	return n


# ------------------------------------------------------------------ 对外接口

## ══════════════════════════════════════════════════════════════════
##  特效总开关
## ══════════════════════════════════════════════════════════════════
##  历史：2026-10-01 用户先要求「把攻击动画（闪屏竖线）全部关闭，
##  **是关闭，不是删除**，我怕以后会用到」，于是有 `FX_ENABLED_DEFAULT = false`。
##  随后同一天 又要求「攻击还是要有点特效，先统一成黄色长短不一的细线」，
##  竖线特效因此被**重做**（见文件顶部的开火线说明），开关随之翻回 true。
##
##  ⛔ 开关本身不删：命中爆点 / 击毁爆炸 / 开火线三套的建造与生命周期逻辑
##     都在，把 `fx_enabled` 置 false 即整体静音（验收用它做双向测试）。
##  ⚠️ 做成 `var` 是为了验收能双向测（开 ⇒ active_count()>0；关 ⇒ 恒为 0）——
##     这也是**唯一**能把「特效断了」与「特效被主动关掉」区分开的办法。
const FX_ENABLED_DEFAULT := true
var fx_enabled := FX_ENABLED_DEFAULT

## 运行时可改的贴花颜色；由 shield_impact.gd 在建槽时读取。
static var shield_decal_mid_color := Color(0.05, 0.30, 1.00, 1.0)
static var shield_decal_high_color := Color(0.32, 0.70, 1.00, 1.0)


## 开火：在**开火方 → 被打击方**之间画一条黄色细线，亮一下就灭。
##
## ⚠️ 一条线只代表**一次开火**（用户明确要求「亮一下等于开火一次」）。
##    sim 的 `shot_fired` 每发都发一次信号，这里就每发建一个节点，
##    靠 `MAX_FX` 上限淘汰，**不做任何节流合并** —— 合并会让齐射变成一条，
##    玩家就数不出「打了几炮」了。
##
## ⚠️ 未命中的线**不画到目标身上**，只画到弹道中段 ——
##    画到目标等于告诉玩家「打中了」，而伤害数字又是 0 / miss，
##    两条信息互相打脸。短一截是「子弹从旁边飞过去了」。
func spawn_tracer(from_meters: Vector3, to_meters: Vector3, hit: bool,
		quality: int = 3) -> void:
	if not fx_enabled:
		return
	var a := from_meters / METERS_PER_UNIT
	var b := to_meters / METERS_PER_UNIT
	# ── 长度：三档来源相乘（档位 / 真实距离 / 抖动）────────────────
	# ⚠️ 先算**真实**弹道长度（未命中也要基于它），再把端点收到中段。
	var span := (b - a).length()
	if span < 0.01:
		return
	if not hit:
		b = a.lerp(b, TRACER_MISS_FRACTION)
		span *= TRACER_MISS_FRACTION
	var tier := clampi(quality, 0, 6)
	var base := float(TRACER_LEN_HIT[clampi(tier / 2, 0, TRACER_LEN_HIT.size() - 1)])
	if not hit:
		base = float(TRACER_LEN_HIT[0]) * 0.8
	# 抖动：每发独立，齐射看起来才是「弹幕」而不是一根尺子。
	var length := clampf(base * (1.0 + randf_range(-TRACER_JITTER, TRACER_JITTER)),
			0.05, TRACER_MAX_LEN)
	# ⚠️ 线的**视觉长度**可以比真实距离短（那是「弹道的一段」），
	#    但绝不能比真实距离长 —— 长了就画到目标身后去了。
	length = minf(length, span)

	var col := TRACER_COLOR
	if not hit:
		col = TRACER_MISS_COLOR
	# 档位越高越亮（0.75 → 1.0），让「打得狠」一眼看得出来。
	var energy := 1.9 + float(tier) * 0.12
	if not hit:
		energy = 1.3

	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(TRACER_WIDTH, length)
	mi.mesh = q
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = col
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = energy
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# ⛔ **不用** billboard：那正是旧版「闪屏竖线」的病根（见文件顶部说明）。
	#    这里把方片当成贴在弹道上的墙面，用 look_at 让它的**法线**沿弹道，
	#    于是线永远躺在弹道上、两端真的连着火方与受击方。
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.disable_fog = true
	# ⚠️ 线不能挡船：它是「读数」不是实体。投影也一并关掉 ——
	#    几十条线的阴影会让船体上出现莫名其妙的条纹。
	mat.no_depth_test = false
	mi.material_override = mat
	add_child(mi)
	# ── 摆位：中点定位 + 长轴指向弹道 ──────────────────────────────
	# 局部 +Y 是线的长度方向，所以要让「局部 Z」对齐弹道 ⇒ look_at 之后再
	# 绕局部 X 转 90°。这是 Godot 里把方向「贴」到两点之间最省事的写法。
	var aim := a + (b - a).normalized() * length
	mi.position = (a + aim) * 0.5
	mi.look_at(aim, Vector3.UP)
	mi.rotate_object_local(Vector3.RIGHT, PI * 0.5)
	_push(mi, TRACER_FLASH, Kind.TRACER)


## 命中爆点：目标位置上闪一小团光
##
## `layer` = 真实受击层（&"shield" / &"armor" / &"hull"），空 = 未知。
##
## ── 为什么要有 layer，而品质色不够 ────────────────────────────────
##  `QUALITY_COLORS` 是按**命中品质**（MISS~WRECKING）上的色，品质 ≠ 受击层：
##  一发「打得狠」可能砸在护盾上，一发「普通」可能已经在啃结构。
##  玩家从颜色里想读的是「现在打的是哪一层」，所以层优先、品质兜底。
##
## ── 护盾为什么单独一档 ────────────────────────────────────────────
##  护盾挨打的手感不是「炸开」，是「整层壳被点亮、扩散、收回」。
##  ⇒ 2026-10-17 起用**真球壳 + 菲涅尔**（`fx_shield.gdshader`），不再用方片。
## 运行时调色：炮击亮痕颜色。新生成的亮痕立即使用；已存在的亮痕保持当前帧。
func set_artillery_colors(core: Color, edge: Color) -> void:
	artillery_core_color = core
	artillery_edge_color = edge

## 炮击攻击特效：一道沿弹道的长条亮痕，头部停在护盾锚点上。
##
## 与 spawn_tracer 的区别：曳光是「一条读数线」，这个是攻击本身 ——
## 更粗、更长、带方向感的头尾，命中那一下才成立。
func spawn_artillery(from_meters: Vector3, to_meters: Vector3, quality: int = 3) -> void:
	if not fx_enabled:
		return
	var a := from_meters / METERS_PER_UNIT
	var b := to_meters / METERS_PER_UNIT
	var span := (b - a).length()
	if span < 0.05:
		return
	var dir := (b - a) / span
	# 炮击亮痕必须完整连接攻击船与护盾，不能只画命中点附近的一截。
	# shader 自己把尾部压暗，所以整段弹道仍有攻击方向感。
	var length := clampf(span, ARTILLERY_MIN_LEN, ARTILLERY_MAX_LEN)
	length = minf(length, span)

	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(ARTILLERY_WIDTH, length)
	mi.mesh = q
	var mat := ShaderMaterial.new()
	mat.shader = ARTILLERY_SHADER
	mat.set_shader_parameter("core", artillery_core_color)
	mat.set_shader_parameter("edge", artillery_edge_color)
	mat.set_shader_parameter("intensity", 1.6 + float(clampi(quality, 0, 6)) * 0.10)
	mi.material_override = mat
	add_child(mi)

	# 头部严格停在命中点，尾部往后拉
	var tip := b
	var tail := a
	mi.position = (tail + tip) * 0.5
	mi.look_at(tip, Vector3.UP)
	mi.rotate_object_local(Vector3.RIGHT, PI * 0.5)
	_push(mi, ARTILLERY_LIFE, Kind.TRACER)
	# 命中端点补一小团白热，读起来才是打实了
	_make_burst(0, to_meters, HIT_SIZE_BASE * 1.6, HIT_LIFE,
			Color(0.92, 0.98, 1.0), Color(0.30, 0.62, 1.0), 3.2, 6.0)

func spawn_hit(pos_meters: Vector3, quality: int, layer: StringName = &"") -> void:
	if not fx_enabled:
		return
	# ★ 2026-10-21：护盾层不再画任何面积特效。
	#   用户口径：「去掉蓝色命中环，只保留贴花」。
	#   护盾受击由目标船自己的曲面贴花表现（eve_shield_impact.gd）——
	#   贴花本来就长在壳面上，等敌方开火来点亮它，不需要第二套环。
	if layer == &"shield":
		return
	var tier := clampi(quality, 0, 6)
	# 层优先、品质兜底（旧逻辑保留）：颜色要回答「打的是哪一层」
	var core := _quality_color(tier)
	var edge := core.darkened(0.25)
	if layer == &"armor":
		core = Color(1.00, 0.90, 0.62)     # 装甲：白热 → 琥珀
		edge = Color(0.95, 0.78, 0.34)
	elif layer == &"hull":
		core = Color(1.00, 0.86, 0.66)     # 结构：白热 → 橙红
		edge = Color(1.00, 0.52, 0.30)
	# 档位越高越大越亮 —— 「打得狠」必须一眼看得出来
	var size := HIT_SIZE_BASE + HIT_SIZE_PER_TIER * float(tier)
	# MISS（0）不画星芒：打空了却炸一团光，等于告诉玩家"打中了"
	if tier <= 0:
		size *= 0.55
	var energy := 2.0 + float(tier) * 0.22
	_make_burst(0, pos_meters, size, HIT_LIFE, core, edge, energy, 4.0)


## 击毁爆炸：白热核 + 冲击波环 + 一盏瞬时点光
##
## ★ 2026-10-17：旧版是「一个 3.4 → 6.1 世界单位的方片」，屏幕上比整艘船还大，
##   而且只有一层 —— 读起来是"黄色大方块"，没有"爆开"的过程。
##   新版拆成两层：核（极短、极亮）+ 环（稍长、向外推），
##   再保留点光让邻近舰船被照亮（那是「冲击传到别的船上」的唯一线索）。
func spawn_boom(pos_meters: Vector3) -> void:
	if not fx_enabled:
		return
	_make_burst(0, pos_meters, BOOM_CORE_SIZE, BOOM_LIFE * 0.45,
			Color(1.0, 0.98, 0.92), Color(1.0, 0.78, 0.45), 4.2, 8.0)
	_make_burst(1, pos_meters, BOOM_RING_SIZE, BOOM_LIFE,
			Color(1.0, 0.72, 0.35), Color(0.92, 0.34, 0.16), 2.4, 4.0)
	# 击毁额外加一盏瞬时点光 —— 让周围船体被照亮一瞬，
	# 「爆炸发生过」这件事才会传到邻近的船上，而不是只有一朵贴图。
	var omni := OmniLight3D.new()
	omni.light_color = Color(1.0, 0.62, 0.32)
	omni.light_energy = 3.0
	omni.omni_range = 14.0
	add_child(omni)
	omni.position = pos_meters / METERS_PER_UNIT
	_push(omni, BOOM_LIFE * 0.7, Kind.BOOM)


## 清空全部特效（重开一局 / 清场时调）
func clear() -> void:
	for f in _fx:
		var n = f["node"]
		if is_instance_valid(n):
			n.queue_free()
	_fx.clear()


# ------------------------------------------------------------------ 内部

func _quality_color(quality: int) -> Color:
	var q := clampi(quality, 0, QUALITY_COLORS.size() - 1)
	return QUALITY_COLORS[q]


## 造一片「billboard 程序化形状」闪光（星芒 / 冲击波环）。
##
## ══════════════════════════════════════════════════════════════════
##  ★ 2026-10-17 之前这里是**纯色 QuadMesh**
## ══════════════════════════════════════════════════════════════════
##  旧实现（已删）：一个 `StandardMaterial3D` + `albedo_color` + `emission`，
##  没有任何纹理 ⇒ 屏幕上就是一块**实心方块**。实测：
##    · 命中：90×85 px 的黄块
##    · 护盾：240×160 px 的蓝块，直接把舰船和背景一起盖掉
##    · 占中央战斗区 4~9%
##  这不是"参数没调好"，是**形状语言缺失**。
##
##  现在改成 `fx_impact.gdshader` 程序化绘制：
##    kind 0 = 白热核心 + 十字/米字星芒 + 短外晕
##    kind 1 = 薄冲击波环 + 拖尾
##  统一 `blend_add` + `depth_draw_never` ⇒ 亮而不遮、不写深度。
##
##  ⚠️ 每个实例都 new 一份 ShaderMaterial（不像旧版共用 StandardMaterial3D）：
##     `progress` 是 per-instance 的，共用会让所有特效同步淡出。
##     成本可接受：`MAX_FX` 上限就是为这件事定的。
func _make_burst(kind: int, pos_meters: Vector3, size: float, life: float,
		core: Color, edge: Color, energy: float, rays: float) -> void:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	mi.mesh = q
	var mat := ShaderMaterial.new()
	mat.shader = FX_SHADER
	mat.set_shader_parameter("kind", kind)
	mat.set_shader_parameter("progress", 0.0)
	mat.set_shader_parameter("core_color", core)
	mat.set_shader_parameter("edge_color", edge)
	mat.set_shader_parameter("intensity", energy)
	mat.set_shader_parameter("ray_count", rays)
	mi.material_override = mat
	mi.position = pos_meters / METERS_PER_UNIT
	add_child(mi)
	_push(mi, life, Kind.HIT if kind == 0 else Kind.BOOM, mat)


## 护盾壳：真球 + 菲涅尔（包住船体、正面全透、边缘发亮）
##
## ⚠️ 用 SphereMesh 而不是 billboard：护盾的语义是「一层包住船的壳」，
##    方片永远只能在屏幕上画一个圈，读起来像冲击波，会和击毁爆炸混在一起。
func _make_shield(pos_meters: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	# 低细分就够：菲涅尔只依赖法线，16x8 在屏幕上已经看不出棱
	sm.radial_segments = 20
	sm.rings = 10
	mi.mesh = sm
	var mat := ShaderMaterial.new()
	mat.shader = SHIELD_SHADER
	mat.set_shader_parameter("progress", 0.0)
	mat.set_shader_parameter("tint", Color(0.38, 0.74, 1.00))
	mi.material_override = mat
	mi.position = pos_meters / METERS_PER_UNIT
	# 起始 scale 必须与 `_apply_envelope` 的 k=0 值一致（0.88），
	# 否则第一帧会从满尺寸"缩"一下（一帧的跳变在护盾上很明显）。
	mi.scale = Vector3.ONE * (SHIELD_DIAMETER * 0.88)
	add_child(mi)
	_push(mi, SHIELD_LIFE, Kind.SHIELD, mat)


## 登记一个特效并执行上限淘汰。
##
## ⚠️ 淘汰是「从最老的开始丢」而不是「拒绝新的」：
##    最新的那一条永远是玩家最该看到的（刚发生的打击）。
func _push(node: Node3D, life: float, kind: int, mat: Material = null) -> void:
	while _fx.size() >= MAX_FX:
		var old: Dictionary = _fx.pop_front()
		var n = old["node"]
		if is_instance_valid(n):
			n.queue_free()
	_fx.append({"node": node, "t": 0.0, "life": maxf(0.01, life), "kind": kind, "mat": mat})


func _process(delta: float) -> void:
	if _fx.is_empty():
		return
	var alive: Array[Dictionary] = []
	for f in _fx:
		var n = f["node"]
		if not is_instance_valid(n):
			continue
		f["t"] = float(f["t"]) + delta
		var k: float = float(f["t"]) / float(f["life"])
		if k >= 1.0:
			n.queue_free()
			continue
		_apply_envelope(n, f, k)
		alive.append(f)
	_fx = alive


## 生命周期包络：全部「先冲出去、再淡出」。
##
## ⚠️ 开火线**不膨胀、不缩长度** —— 它是「亮一下」，用户的原话是
##    「亮一下等于开火一次」。所以只做整体淡出（长度保持不变），
##    这样它从头到尾都躺在弹道上、两端一直连着开火方与受击方。
##    （旧版做的是「长度收缩」，那是配合 flash 曳光的读法；新版不需要。）
## ⚠️ 淡出曲线用 `fade²`：线性淡出在线很细的时候会让「灭」这一步看不出来，
##    平方收尾能做出「啪一下没了」的干脆感。
func _apply_envelope(n: Node3D, f: Dictionary, k: float) -> void:
	var fade := 1.0 - k
	var kind: int = int(f["kind"])
	if kind == Kind.TRACER:
		var mi := n as MeshInstance3D
		if mi != null and mi.material_override is StandardMaterial3D:
			var m := mi.material_override as StandardMaterial3D
			m.albedo_color.a = fade * fade
			m.emission_energy_multiplier = m.emission_energy_multiplier * 0.997 + 0.003 * fade
		elif mi != null and mi.material_override is ShaderMaterial:
			# 炮击亮痕用的是 ShaderMaterial，没有 albedo_color 可写，
			# 淡出交给 intensity
			(mi.material_override as ShaderMaterial).set_shader_parameter("intensity", fade * fade * 2.2)
		return
	if n is OmniLight3D:
		(n as OmniLight3D).light_energy = 3.0 * fade * fade
		return
	# ── shader 特效：进度写进 uniform，形状自己在新版 shader 里算 ──────
	# ⚠️ 不再用 `albedo_color.a` 淡出：ShaderMaterial 没有那个属性，
	#    写它不报错但**完全没效果**（旧代码在 shader 化后会静默失效）。
	var mat: Variant = f.get("mat")
	if mat is ShaderMaterial:
		(mat as ShaderMaterial).set_shader_parameter("progress", clampf(k, 0.0, 1.0))
	# ── 尺寸包络 ────────────────────────────────────────────────────
	# 命中：几乎不外扩（"啪"一下）。护盾：轻微外扩（壳被顶了一下）。
	# 爆炸：明显外扩（冲击波推出去）。
	var grow_k := 0.35
	if kind == Kind.SHIELD:
		grow_k = 0.28
	elif kind == Kind.BOOM:
		grow_k = 1.1
	var base_scale := 1.0
	if kind == Kind.SHIELD:
		# 球直径来自常量：球网格本身是 1 单位，scale 就是"世界直径"
		base_scale = SHIELD_DIAMETER * (0.88 + 0.22 * k)
	n.scale = Vector3.ONE * (base_scale * (1.0 + k * grow_k))
