// 命中火焰 · 翻页图集（UE 火焰包解包出的 8×8 / 64 帧）
//
// 颜色完全由 alpha 驱动，不取贴图颜色 —— 原图是橙色，
// 想要蓝色只要改三个色标，未来换紫/绿同理。
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, fog_disabled;

uniform sampler2D atlas : source_color, filter_linear_mipmap;
uniform int frame : hint_range(0, 63) = 0;
uniform int atlas_size = 8;
uniform float brightness = 3.0;
uniform float alpha_gain = 1.0;

uniform vec4 color_deep : source_color = vec4(0.00, 0.02, 0.22, 1.0);
uniform vec4 color_mid : source_color = vec4(0.02, 0.22, 0.95, 1.0);
uniform vec4 color_high : source_color = vec4(0.22, 0.62, 1.0, 1.0);
uniform vec4 color_core : source_color = vec4(0.85, 0.96, 1.0, 1.0);

// 不做全屏 billboard：三张交叉片各自固定朝向（脚本里按命中法线摆好），
// 和 Blender 里的做法一致 —— 任何机位都有体积，又不会在某角度塌成一条线。


void fragment() {
	int n = atlas_size;
	int col = frame % n;
	int row = frame / n;
	vec2 uv = (UV + vec2(float(col), float(row))) / float(n);
	vec4 tex = texture(atlas, uv);

	float a = tex.a * alpha_gain;
	vec3 fire_rgb = mix(color_deep.rgb, color_mid.rgb, smoothstep(0.10, 0.62, a));
	fire_rgb = mix(fire_rgb, color_high.rgb, smoothstep(0.62, 0.88, a));
	fire_rgb = mix(fire_rgb, color_core.rgb, smoothstep(0.92, 0.99, a));

	ALBEDO = fire_rgb * brightness * a;
	ALPHA = a;
}
