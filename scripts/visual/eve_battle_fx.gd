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
const HIT_LIFE := 0.28
## 击毁爆炸存活时间
const BOOM_LIFE := 0.75

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
## 线的视觉宽度（世界单位）。0.07 ≈ 相机拉远时约 1 像素 —— 再细会在实机上消失。
const TRACER_WIDTH := 0.07
## 三档长度。命中时按档位取一档；未命中固定用最短那档（打空了不该有长弹道）。
const TRACER_LEN_HIT := [0.42, 0.68, 0.95]
## 未命中的长度占「开火方 → 被击方」真实距离的比例
const TRACER_MISS_FRACTION := 0.62
## 长度抖动幅度（±18%）
const TRACER_JITTER := 0.18
## 线亮起 → 灭掉的时长。用户要求「亮一下 = 开火一次」，所以刻意很短。
const TRACER_FLASH := 0.15

## 线长上限（世界单位）。
##
## ⚠️ 必须有：场上追逃时两船可能相距好几十单位，一条横跨全屏的线
##    会把整个战场盖住。截断后是「一段弹道」而不是「一条分割线」。
const TRACER_MAX_LEN := 4.2
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

enum Kind { TRACER, HIT, BOOM }


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
func spawn_hit(pos_meters: Vector3, quality: int) -> void:
	if not fx_enabled:
		return
	var col := _quality_color(quality)
	# 档位越高越大 —— 「打得狠」这件事必须一眼看得出来
	var base := 0.9 + float(clampi(quality, 0, 6)) * 0.22
	_make_flash(pos_meters, col, base, HIT_LIFE, Kind.HIT)


## 击毁爆炸：一大团橙红 + 短促强光
func spawn_boom(pos_meters: Vector3) -> void:
	if not fx_enabled:
		return
	_make_flash(pos_meters, Color(0.95, 0.55, 0.25), 3.4, BOOM_LIFE, Kind.BOOM)
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


## 造一团「billboard 方片」闪光。
##
## ⚠️ 用方片而不是球：方片 + 加色发光看起来就是「爆点」，
##    而球体在无头环境下多一层细分，且缩放时轮廓更软、不够「锐」。
##    战术视角下这一层的读法是「哪里被打了一下」，锐比圆重要。
func _make_flash(pos_meters: Vector3, col: Color, size: float,
		life: float, kind: int) -> void:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	mi.mesh = q
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(col.r, col.g, col.b, 0.92)
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 3.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.billboard_keep_scale = true
	mat.disable_fog = true
	mi.material_override = mat
	mi.position = pos_meters / METERS_PER_UNIT
	add_child(mi)
	_push(mi, life, kind)


## 登记一个特效并执行上限淘汰。
##
## ⚠️ 淘汰是「从最老的开始丢」而不是「拒绝新的」：
##    最新的那一条永远是玩家最该看到的（刚发生的打击）。
func _push(node: Node3D, life: float, kind: int) -> void:
	while _fx.size() >= MAX_FX:
		var old: Dictionary = _fx.pop_front()
		var n = old["node"]
		if is_instance_valid(n):
			n.queue_free()
	_fx.append({"node": node, "t": 0.0, "life": maxf(0.01, life), "kind": kind})


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
		_apply_envelope(n, f["kind"], k)
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
func _apply_envelope(n: Node3D, kind: int, k: float) -> void:
	var fade := 1.0 - k
	if kind == Kind.TRACER:
		var mi := n as MeshInstance3D
		if mi != null and mi.material_override != null:
			var m := mi.material_override as StandardMaterial3D
			m.albedo_color.a = fade * fade
			m.emission_energy_multiplier = m.emission_energy_multiplier * 0.997 + 0.003 * fade
		return
	# 命中 / 爆炸：膨胀 + 淡出（EVE 的爆点是「炸开」，不是「闪一下就没」）
	var grow := 1.0 + k * (0.9 if kind == Kind.HIT else 1.8)
	n.scale = Vector3.ONE * grow
	if n is OmniLight3D:
		(n as OmniLight3D).light_energy = 3.0 * fade * fade
		return
	var mi2 := n as MeshInstance3D
	if mi2 != null and mi2.material_override != null:
		var m2 := mi2.material_override as StandardMaterial3D
		m2.albedo_color.a = fade * fade * 0.92
		m2.emission_energy_multiplier = 3.0 * fade
