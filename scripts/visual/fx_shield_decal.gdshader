// 蛋形护盾 · 曲面贴花片（与 Blender v3 对齐）
//
// 与旧版的区别：
//   旧版：整颗椭球壳 + 世界空间投影算 UV，靠 shader 裁出小圆点。
//         曲率大时 UV 被拉伸，尺寸/形状失控。
//   新版：贴花是一块真实投影到椭球面的网格（见 shield_decal_test.gd），
//         每个顶点都在壳面上，UV 由网格给出。shader 只负责采样图集与上色，
//         不再做任何世界空间反投影。曲面大弯的地方靠网格顶点自然贴合。
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, fog_disabled, shadows_disabled;

uniform sampler2D atlas : source_color, filter_linear, repeat_disable;
uniform int frame : hint_range(0, 63) = 0;
uniform int atlas_size = 8;

uniform float intensity = 6.0;
// 贴花片边缘软过渡，避免方形网格边露出来
uniform float edge_softness = 0.18;
// 视角衰减：让曲面明暗参与成像，边缘偏暗、正对处最亮
uniform float facing_power = 0.85;

uniform vec4 color_deep : source_color = vec4(0.00, 0.00, 0.00, 1.0);
uniform vec4 color_mid : source_color = vec4(0.05, 0.30, 1.00, 1.0);
uniform vec4 color_high : source_color = vec4(0.32, 0.70, 1.00, 1.0);
uniform vec4 color_core : source_color = vec4(0.94, 0.99, 1.00, 1.0);
uniform bool debug_solid = false;

void fragment() {
	int col = frame % atlas_size;
	int row = frame / atlas_size;
	vec2 auv = (UV + vec2(float(col), float(row))) / float(atlas_size);
	vec4 tex = texture(atlas, auv);

	// 圆形遮罩：贴花片本身是方网格，这里收成圆
	float r = length(UV - vec2(0.5)) * 2.0;
	float mask = 1.0 - smoothstep(1.0 - edge_softness, 1.0, r);

	float a = tex.a * mask;

	// 法线在这里随壳面弯曲变化 → 贴花自身读出曲率
	// NORMAL/VIEW 的坐标系约定在不同渲染后端会有差异，取绝对值避免整片被乘成 0。
	float facing = clamp(abs(dot(normalize(NORMAL), normalize(VIEW))), 0.0, 1.0);
	float shaped = clamp(pow(facing, facing_power), 0.0, 1.0);

	vec3 rgb = mix(color_deep.rgb, color_mid.rgb, smoothstep(0.10, 0.62, a));
	rgb = mix(rgb, color_high.rgb, smoothstep(0.62, 0.88, a));
	rgb = mix(rgb, color_core.rgb, smoothstep(0.92, 0.99, a));

	float alpha = clamp(a * shaped, 0.0, 1.0);
	if (debug_solid) {
		// 调试：忽略图集，直接画曲面片本身，用来确认几何与遮挡关系
		ALBEDO = vec3(1.0, 0.15, 0.15) * mask * 2.0;
		ALPHA = mask;
	} else {
		// blend_add 里最终是 ALBEDO*ALPHA 再相加。若 ALBEDO 再乘一次 alpha，
		// 等于 alpha²，贴花会被压得几乎看不见。这里 ALBEDO 只保留色带与
		// 轻度增益，透明度交给 ALPHA。
		float boost = 0.55 + 0.9 * a;
		ALBEDO = rgb * mask * shaped * intensity * boost;
		ALPHA = clamp(mask * shaped, 0.0, 1.0);
	}
}
