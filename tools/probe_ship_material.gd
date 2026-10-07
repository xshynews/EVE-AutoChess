extends Node

## 探针 —— 舰船材质「还原」的双重验证
##
## ═══════════════════════════════════════════════════════════════════════
## 验证哪两件事
## ═══════════════════════════════════════════════════════════════════════
## ① **绑定层**：glb 导入后的材质真的被换成了 ship_hull.gdshader，
##    且 albedo / normal / spec 三张图都非空（换漏一张就会画出怪船）。
## ② **数值层**：着色器里那条 ramp 算出来的值，和 Python 从 `_s` 图独立算出的
##    值是否一致。探针 `#include` 的是**线上同一个** ship_hull_ramp.gdshaderinc，
##    所以这一条等价于「线上跑的那段代码是对的」。
##
## ═══════════════════════════════════════════════════════════════════════
## 为什么要用 8 条色带（而不是直接读像素）
## ═══════════════════════════════════════════════════════════════════════
## 屏幕上量到的亮度 ≠ 着色器算出的值：中间还隔着 HDR 2D / 帧缓冲编码。
## 所以前 4 条带渲染**已知常数**（0.20 / 0.50 / 0.80 / 0.95）当标尺，
## 后 4 条才是待测值；Python 用前 4 条拟合出「真值 ↔ 屏幕值」的映射再反解。
##
## 顺带把「`_s` 有没有被 sRGB 解码」再验一次（带5 = 已知均值 0.6434）——
## 这条如果翻车，金饰的金属度会从 0.95 塌到 0.45，而画面上只是"金有点脏"。
##
## 用法（**必须开窗口**，headless 没有 GPU 上下文，渲出来是空的）：
##   godot_console.exe --path <工程> --quit-after 300 res://tools/probe_ship_material.tscn

const SHIP := &"punisher"
const S_FILE := "res://assets/ships3d/punisher_af3_t1_s.jpg"
const OUT := "user://probe_ship_material.png"

const REF_MEAN := 0.6434      ## Python 侧实测 `_s` 全图均值
const CAL := [0.20, 0.50, 0.80, 0.95]

var _node: Node3D = null


func _ready() -> void:
	_verify_binding()
	_build_bands()


## ① 绑定层
func _verify_binding() -> void:
	_node = EveShipModel.instantiate(SHIP)
	if _node == null:
		push_error("[材质探针] 拿不到模型 —— 资产没装？")
		return
	add_child(_node)

	print("══════ ① 绑定层 ══════")
	print("  模型 %s 已被材质还原：%s" % [SHIP, str(EveShipMaterial.is_upgraded(_node))])
	var st := EveShipMaterial.last_stats
	print("  网格=%d 表面=%d 已换=%d 缺图跳过=%d 非BaseMaterial3D=%d 自发光=%d" % [
			int(st.get("meshes", -1)), int(st.get("surfaces", -1)),
			int(st.get("swapped", -1)), int(st.get("no_spec", -1)),
			int(st.get("not_base", -1)), int(st.get("has_emissive", -1))])
	print("  材质缓存条数 = %d" % EveShipMaterial.cache_size())

	var meshes: Array[MeshInstance3D] = []
	_collect(_node, meshes)
	for mi in meshes:
		var mesh: Mesh = mi.mesh
		if mesh == null:
			continue
		for i in mesh.get_surface_count():
			var m: Material = mi.get_active_material(i)
			print("  [%s #%d] %s" % [mi.name, i, m.get_class()])
			var sm := m as ShaderMaterial
			if sm == null:
				print("      ⚠️ 不是 ShaderMaterial —— 没换上")
				continue
			print("      shader = %s" % (sm.shader.resource_path if sm.shader else "<null>"))
			for p in ["albedo_tex", "normal_tex", "spec_tex"]:
				print("      %-12s = %s" % [p, _tex(sm.get_shader_parameter(p))])
			print("      normal_strength=%.2f  r_white=%.2f  r_gold=%.2f  gain=%.2f bias=%.2f" % [
					sm.get_shader_parameter("normal_strength"),
					sm.get_shader_parameter("r_white"),
					sm.get_shader_parameter("r_gold"),
					sm.get_shader_parameter("spec_gain"),
					sm.get_shader_parameter("spec_bias")])


func _collect(n: Node, out: Array[MeshInstance3D]) -> void:
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		_collect(c, out)


func _tex(t) -> String:
	if t == null:
		return "<null>  ⚠️"
	var tex := t as Texture2D
	if tex == null:
		return "<不是 Texture2D>"
	return "%dx%d %s" % [tex.get_width(), tex.get_height(), tex.get_class()]


## ② 数值层：8 条色带
func _build_bands() -> void:
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;
render_mode unshaded;

#include "res://scripts/visual/ship_hull_ramp.gdshaderinc"

uniform sampler2D spec_tex : hint_default_white;

void fragment() {
	int idx = int(floor(UV.x * 8.0));
	vec2 t = vec2(clamp(fract(UV.x * 8.0), 0.001, 0.999), UV.y);
	float spec = texture(spec_tex, t).r;
	vec3 col;
	if (idx == 0)       col = vec3(0.20);
	else if (idx == 1)  col = vec3(0.50);
	else if (idx == 2)  col = vec3(0.80);
	else if (idx == 3)  col = vec3(0.95);
	else if (idx == 4)  col = vec3(spec);
	else if (idx == 5)  col = vec3(0.6434);
	else if (idx == 6)  col = vec3(eve_metal_ramp(spec));
	else                col = vec3(eve_roughness(spec, 0.62, 0.18));
	COLOR = vec4(col, 1.0);
}
"""
	if sh.get_code().is_empty():
		push_error("[材质探针] 着色器编译失败（看上面的报错）")

	var mat := ShaderMaterial.new()
	mat.shader = sh
	# 用工程里独立的那份 `_s.jpg`（不依赖 glb 内嵌），确保测的是同一张图
	var tex: Texture2D = load(S_FILE)
	if tex == null:
		push_error("[材质探针] 载不到 %s" % S_FILE)
	mat.set_shader_parameter("spec_tex", tex)
	print("══════ ② 数值层 ══════")
	print("  色带 0-3 = 常数标尺 %s" % str(CAL))
	print("  色带 4 = `_s` 原始  预期均值 %.4f" % REF_MEAN)
	print("  色带 5 = 常数 %.4f（编码参照）" % REF_MEAN)
	print("  色带 6 = eve_metal_ramp(spec)")
	print("  色带 7 = eve_roughness(spec, 0.62, 0.18)")
	print("  spec 图 = %s" % _tex(tex))

	var rect := ColorRect.new()
	rect.material = mat
	rect.anchor_right = 1.0
	rect.anchor_bottom = 1.0
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rect)

	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img == null:
		push_error("[材质探针] 拿不到 viewport 图像（是不是 headless 跑的？）")
		get_tree().quit(1)
		return
	img.save_png(OUT)
	print("[材质探针] 已存 ", ProjectSettings.globalize_path(OUT), "  ", img.get_size())
	get_tree().quit(0)
