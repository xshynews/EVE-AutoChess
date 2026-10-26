// 蛋形护盾壳（与 Blender 版同一套：掠射亮、正对淡）
//
// 用途：开发期让护盾可见，才能判断贴花到底贴在壳面的什么位置。
// 正式效果里这层应该关掉，只留贴花。
shader_type spatial;
render_mode blend_add, unshaded, cull_back, depth_draw_never, fog_disabled, shadows_disabled;

uniform vec4 rim_color : source_color = vec4(0.26, 0.58, 1.0, 1.0);
uniform float rim_power = 2.4;
uniform float rim_strength = 0.85;
uniform float body_alpha = 0.045;

void fragment() {
	// abs：NORMAL/VIEW 的坐标系约定在不同后端不一致，取绝对值最稳
	float d = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float rim = pow(1.0 - clamp(d, 0.0, 1.0), rim_power);
	float a = body_alpha + rim * rim_strength;
	// blend_add 下最终是 ALBEDO*ALPHA，所以 ALBEDO 给纯色、ALPHA 给强度
	ALBEDO = rim_color.rgb;
	ALPHA = clamp(a, 0.0, 1.0);
}
