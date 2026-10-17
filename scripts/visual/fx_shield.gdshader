// 护盾壳被点亮（2026-10-17 打击感改造·批次 1）
//
// ══════════════════════════════════════════════════════════════════
//  为什么护盾要单独一个 shader
// ══════════════════════════════════════════════════════════════════
//  旧版把护盾命中做成「一张蓝色的 billboard 方片」，读起来是：
//    「这里被贴了一块蓝色板」而不是「这艘船的盾还在扛」。
//
//  护盾的物理读法只有一种：**包住船体的壳，边缘亮、正面透**。
//  所以这里用真球（SphereMesh）+ 菲涅尔（fresnel）：
//    · 视线越接近切向（球面边缘）越亮 ⇒ 读起来是"一层壳"；
//    · 正对镜头的部分几乎全透 ⇒ 不遮船；
//    · 加色混合 ⇒ 在亮星云上也是"发光"，不是"贴片"。
//
//  ⚠️ 球必须 `cull_disabled`：玩家可能从任何一侧看，剔一面会出现"半个壳"。
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, fog_disabled;

// 生命周期进度 0..1
uniform float progress : hint_range(0.0, 1.0) = 0.0;
// 护盾色（青蓝，与血条同一套语义色）
uniform vec4 tint : source_color = vec4(0.38, 0.74, 1.0, 1.0);
// 边缘光强
uniform float rim_energy = 2.6;

void fragment() {
	// 菲涅尔：1 = 正对镜头，0 = 切向
	float facing = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float rim = pow(1.0 - facing, 3.0);
	// 壳本身有一点点弥散（不是纯边缘），否则小尺寸下会"看不见"
	float body = 0.05;
	// 时间包络：被点亮的一瞬间最亮，随后整层退掉
	float env = (1.0 - progress) * (1.0 - progress * 0.35);
	float a = (rim * rim_energy + body) * env;

	ALBEDO = tint.rgb * a;
	ALPHA = clamp(a, 0.0, 1.0);
}
