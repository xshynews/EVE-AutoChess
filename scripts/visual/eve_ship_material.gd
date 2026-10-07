extends RefCounted
class_name EveShipMaterial

## EVE 自走棋 —— 舰船外壳材质「还原」
##
## ═══════════════════════════════════════════════════════════════════════════
## 解决的问题：glb 里的材质是**退化的**
## ═══════════════════════════════════════════════════════════════════════════
##
## Blender 侧的金属度/粗糙度是「`_s` 分区图 → ColorRamp / MapRange」的**节点图**，
## 而 glTF 只能表达常量 + 一张贴图，中间节点全丢。实测导入结果：
##
##     metallic_tex  = `_s` 图，取 BLUE  通道，因子 1.0
##     roughness_tex = `_s` 图，取 GREEN 通道，因子 1.0
##     ⇒ 引擎里实际是 `metallic = spec 原值` = 0.345 / 0.682 / 0.780
##
## 而正确值是 **0 / 0.80 / 0.95**。两个看得见的后果：
##   ① 白甲板被当成 34.5% 金属 → 发银灰（EVE 的白甲板是哑光漆）
##   ② 金饰只有 78% 金属度 → 该被光擦亮的地方是哑的
## 粗糙度同理整体偏大（0.345/0.682/0.780 vs 应为 0.332/0.480/0.523）。
##
## 本类把每个表面的材质换成 `ship_hull.gdshader` —— 那条 ramp 的引擎侧复现。
## 顺带把法线强度 1.25（Blender Normal Map 节点的 Strength）也带上。
##
## ═══════════════════════════════════════════════════════════════════════════
## 两条硬闸（防止"修材质"反而把船修坏）
## ═══════════════════════════════════════════════════════════════════════════
##
## 1. **没有 `_s` 图就一个字都不改**。
##    shader 里 spec_tex 的缺省值是白（hint_default_white）= 1.0，
##    ramp(1.0) = 0.97 ⇒ 整船饱和成全金属。缺图时保留原来的 StandardMaterial3D
##    —— 那个虽然金属度偏，但至少不会变成一面镜子。
##
## 2. **只换材质，不动几何、不动节点结构**。
##    用 `set_surface_override_material`（覆盖）而不是改导入资源本身：
##    改导入资源会污染共享的 .scn，一艘船改坏＝52 艘一起坏。
##
## ═══════════════════════════════════════════════════════════════════════════
## 主键 = ship id（与立绘 EveShipArt / 模型 EveShipModel 同一个键）
## ═══════════════════════════════════════════════════════════════════════════
##
## 缓存键 = `<ship_id>/<surface>`。同一艘船的第 i 个面共用一个 ShaderMaterial，
## 11 艘同型船浮在场上也只有 1 份 —— 不会每实例编译一次着色器。
##
## 自检：`tools/probe_ship_material.tscn`（绑定 + ramp 数值双验）

const SHADER_PATH := "res://scripts/visual/ship_hull.gdshader"

## 与 Blender 侧 `blender_project.py` 的常数逐一对齐
const NORMAL_STRENGTH := 1.25       # Normal Map 节点 Strength
const R_WHITE := 0.62               # 白甲板粗糙度上限
const R_GOLD := 0.18                # 金饰粗糙度下限

## ── 船壳提亮（2026-09-21，唯一一处**有意偏离** Blender 配方的地方）──────
##
## 动机与实测见 ship_hull.gdshader 顶部的「舰船亮度补偿」整段。
## 一句话：船体 63~87% 金属 ⇒ 镜面 F0 = ALBEDO ⇒ 深色 albedo = 深色镜子，
## 靠灯光最多只能把 p50 从 32 抬到 47，而背景是 130。
##
## `albedo_lift` 用伽马曲线：**暗部抬得多、亮部抬得少**（白漆不爆）。
## 取值由 `tools/probe_ship_bright.tscn` 的同机位扫描定（见那边的候选表）。
##
## 实测（备战席 5 艘 · 同帧同机位 · 船体掩膜内 p50，背景 p50 = 130）：
##   恒等 1.0 → 32.7（船/背景 0.25）· 1.4 → 51.7 · 1.8 → 67.8
##   2.2 → 80.7 · 2.6 → 90.5 · **线性增益 1.6 只有 39.9**（形状不对，已弃）
## 2.2 是「细节全部可读、又还没洗成灰白」的那一档：
##   1.0 的船在亮星云前就是一团没有细节的剪影；2.6 起开始失去舰船质感。
## 1.0 = 恒等 = 忠实的旧行为（shader 里有快路径，逐位等于原实现）。
const ALBEDO_LIFT := 2.2
const ALBEDO_GAIN := 1.0

static var _shader: Shader = null
static var _cache: Dictionary = {}

## 上一次 apply() 的统计，供探针/日志用
static var last_stats: Dictionary = {}


## 把子树里所有网格的材质换成船体着色器。
## 返回**换掉的表面数**；0 表示一个都没换成（缺图 / 非 BaseMaterial3D）。
static func apply(root: Node, ship_id: StringName) -> int:
	last_stats = {
		"ship": String(ship_id),
		"meshes": 0, "surfaces": 0, "swapped": 0,
		"no_spec": 0, "not_base": 0, "has_emissive": 0,
	}
	if root == null or _get_shader() == null:
		return 0
	var meshes: Array[MeshInstance3D] = []
	_collect(root, meshes)
	last_stats["meshes"] = meshes.size()
	for mi in meshes:
		var mesh: Mesh = mi.mesh
		if mesh == null:
			continue
		for i in mesh.get_surface_count():
			last_stats["surfaces"] = int(last_stats["surfaces"]) + 1
			var key := "%s/%d" % [String(ship_id), i]
			var sm: ShaderMaterial = _cache.get(key)
			if sm == null:
				sm = _make(mi.get_active_material(i), key)
				if sm == null:
					continue
				_cache[key] = sm
			mi.set_surface_override_material(i, sm)
			last_stats["swapped"] = int(last_stats["swapped"]) + 1
	return int(last_stats["swapped"])


## 一艘船到底有没有被换上——探针与回归脚本的抓手
static func is_upgraded(root: Node) -> bool:
	var meshes: Array[MeshInstance3D] = []
	_collect(root, meshes)
	for mi in meshes:
		var mesh: Mesh = mi.mesh
		if mesh == null or mesh.get_surface_count() == 0:
			continue
		return mi.get_active_material(0) is ShaderMaterial
	return false


static func clear_cache() -> void:
	_cache.clear()


static func cache_size() -> int:
	return _cache.size()


## ⚠️ 不能叫 `_shader` —— 与静态变量 `_shader` 同名会让整个类解析失败
##    （报的是「Could not resolve class EveShipMaterial」，看不出是重名）。
static func _get_shader() -> Shader:
	if _shader == null:
		_shader = load(SHADER_PATH) as Shader
	return _shader


static func _make(src: Material, key: String) -> ShaderMaterial:
	if not (src is BaseMaterial3D):
		last_stats["not_base"] = int(last_stats["not_base"]) + 1
		return null
	var b := src as BaseMaterial3D
	# glb 导入后 `_s` 落在 metallic_texture（BLUE 通道）；roughness 那份是同一张图。
	# 只认 metallic_texture 那一份，避免把两张不同的图当成同一个 spec。
	var spec: Texture2D = b.metallic_texture
	if spec == null:
		spec = b.roughness_texture
	if spec == null or b.albedo_texture == null:
		# 硬闸 1：缺图不换（见类注释）
		last_stats["no_spec"] = int(last_stats["no_spec"]) + 1
		return null

	var sm := ShaderMaterial.new()
	sm.shader = _get_shader()
	sm.resource_name = "ShipHull_%s" % key
	sm.set_shader_parameter("albedo_tex", b.albedo_texture)
	sm.set_shader_parameter("normal_tex", b.normal_texture)
	sm.set_shader_parameter("spec_tex", spec)
	sm.set_shader_parameter("normal_strength", NORMAL_STRENGTH)
	sm.set_shader_parameter("r_white", R_WHITE)
	sm.set_shader_parameter("r_gold", R_GOLD)
	# 忠实复刻：不动 spec 曲线（按派系微调时才改这两个，见 ship_hull.gdshader）
	sm.set_shader_parameter("spec_gain", 1.0)
	sm.set_shader_parameter("spec_bias", 0.0)
	# 船壳提亮（见 ALBEDO_LIFT 的说明）。两个都是恒等以外的**打光补偿**，
	# 不改 ramp 的金属度/粗糙度分区。
	sm.set_shader_parameter("albedo_lift", ALBEDO_LIFT)
	sm.set_shader_parameter("albedo_gain", ALBEDO_GAIN)

	var em: Texture2D = b.emission_texture
	var em_on := b.emission_enabled and em != null
	sm.set_shader_parameter("has_emissive", em_on)
	if em_on:
		last_stats["has_emissive"] = int(last_stats["has_emissive"]) + 1
		sm.set_shader_parameter("emissive_tex", em)
		sm.set_shader_parameter("emissive_color", b.emission)
		sm.set_shader_parameter("emissive_energy", b.emission_energy_multiplier)
	return sm


static func _collect(n: Node, out: Array[MeshInstance3D]) -> void:
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		_collect(c, out)
