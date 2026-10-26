// 蛋形护盾 · 受击反应（Blender look-dev 的 Godot 版本）
//
// 规格来源：docs/护盾受击-实现规格.md
//   · 护盾是包住船的椭球，命中点在壳面上，离船体有距离；
//   · 命中后壳面被「点亮」并向四周推开一个亮环（世界坐标距离场）；
//   · 护盾本体只有很淡的边缘光，不遮船。
//
// 为什么用世界坐标距离而不是 UV：
//   UV 在椭球上会被拉伸，环会变成椭圆且随缩放变形；
//   世界坐标距离场在任何形状上都给出同一套环，且多艘船共用一套参数。
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, fog_disabled;

// 最多同时 4 个爆点（够表现多发命中；要更多改这里与脚本里的数组长度）
uniform int impact_count : hint_range(0, 4) = 0;
uniform vec3 impact_center[4];
uniform float impact_radius[4];
uniform float impact_amp[4];

// 壳面基础边缘光
uniform float base_rim = 0.07;
// 命中环的宽度（世界单位）
uniform float ring_width = 0.55;
// 热核半径（世界单位）
uniform float core_radius = 2.2;
uniform vec4 tint : source_color = vec4(0.35, 0.70, 1.0, 1.0);

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float facing = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float rim = pow(1.0 - facing, 3.0) * base_rim;

	float wave = 0.0;
	for (int i = 0; i < 4; i++) {
		if (i >= impact_count) {
			break;
		}
		float d = distance(world_pos, impact_center[i]);
		float ring = exp(-pow((d - impact_radius[i]) / ring_width, 2.0));
		float core = exp(-d / core_radius);
		wave += (ring + core) * impact_amp[i];
	}

	float a = clamp(rim + wave, 0.0, 1.0);
	ALBEDO = tint.rgb * a;
	ALPHA = a;
}
