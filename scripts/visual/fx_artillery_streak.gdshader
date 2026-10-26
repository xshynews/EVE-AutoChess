// 炮击攻击特效：沿弹道的长条亮痕（头亮尾淡）
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, fog_disabled, shadows_disabled;

uniform vec4 core : source_color = vec4(0.88, 0.96, 1.0, 1.0);
uniform vec4 edge : source_color = vec4(0.10, 0.38, 1.0, 1.0);
uniform float intensity = 1.0;

void fragment() {
	float y = clamp(UV.y, 0.0, 1.0);
	float across = abs(UV.x - 0.5) * 2.0;
	float body = 1.0 - smoothstep(0.10, 1.0, across);
	float head = smoothstep(0.50, 1.0, y);
	float tail = smoothstep(0.0, 0.38, y);
	float a = body * tail * (0.22 + 0.78 * head) * intensity;
	vec3 c = mix(edge.rgb, core.rgb, head);
	ALBEDO = c;
	ALPHA = clamp(a, 0.0, 1.0);
}
