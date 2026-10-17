// 命中 / 冲击波 的程序化形状（2026-10-17 打击感改造·批次 1）
//
// ══════════════════════════════════════════════════════════════════
//  为什么是 shader 而不是贴图
// ══════════════════════════════════════════════════════════════════
//  旧版命中特效是「纯色 QuadMesh」—— 一个 0.9~3.4 世界单位的实心方块，
//  实测占中央战斗区 4~9%，会整块盖住舰船，是「廉价感」的直接来源。
//
//  换成程序化形状后：
//    · 有形状语言（星芒 / 圆环），读得出「这是命中」而不是「一块板」；
//    · 中心亮、边缘透 ⇒ 不会遮住船体轮廓；
//    · 尺寸与亮度全部由 uniform 控制，验收可断言，不依赖任何贴图资源。
//
//  ⚠️ 一律 `blend_add`（加色）：太空背景是亮的，透明混色会发灰，
//     只有加色才能让「爆点」在月面上也读得出来。
//  ⚠️ 一律 `depth_draw_never`：特效是读数不是实体，不能写深度
//     （否则后续特效会被它挡住，形成一个个方形空洞）。
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, fog_disabled;

// 形状：0 = 命中星芒 · 1 = 冲击波环
uniform int kind : hint_range(0, 1) = 0;
// 生命周期进度 0..1（由 GDScript 每帧写）
uniform float progress : hint_range(0.0, 1.0) = 0.0;
// 中心色 / 边缘色
uniform vec4 core_color : source_color = vec4(1.0, 0.92, 0.72, 1.0);
uniform vec4 edge_color : source_color = vec4(1.0, 0.58, 0.26, 1.0);
// 整体亮度（档位越高越亮）
uniform float intensity = 2.0;
// 星芒的射线数量（4 = 十字，8 = 米字）
uniform float ray_count = 4.0;

// 始终正对镜头（等价于 BaseMaterial3D 的 BILLBOARD_ENABLED）
//
// ⚠️ ShaderMaterial **不会**自动继承 billboard —— 旧版能正对镜头是因为
//    StandardMaterial3D 的 billboard_mode。换 shader 后必须手写，
//    否则命中星芒会变成"贴在弹道平面上的斜片"，机位一转就侧过来消失。
// ⚠️ 保留 MODEL_MATRIX 的缩放（第三列以前要乘 length），否则尺寸全变 1。
void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		INV_VIEW_MATRIX[0] * length(MODEL_MATRIX[0].xyz),
		INV_VIEW_MATRIX[1] * length(MODEL_MATRIX[1].xyz),
		INV_VIEW_MATRIX[2] * length(MODEL_MATRIX[2].xyz),
		MODEL_MATRIX[3]);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	// UV 0..1 → 以中心为原点的 -1..1
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	if (r > 1.0) {
		discard;
	}

	float a = 0.0;
	vec3 col = core_color.rgb;

	if (kind == 0) {
		// ── 命中：白热核心 + 十字/米字星芒 + 一圈短促外晕 ──────────
		// 核：前半程很锐，后半程迅速塌掉（"啪"一下就没了）
		float core = smoothstep(0.42, 0.0, r) * (1.0 - smoothstep(0.25, 1.0, progress));
		// 星芒：角度调制。pow 的指数越大，射线越细、越像"光针"
		float ang = atan(p.y, p.x);
		float spokes = pow(abs(cos(ang * ray_count * 0.5)), 28.0);
		// 射线长度随进度外扩，亮度随时间衰减
		float reach = 0.30 + 0.68 * progress;
		float rays = spokes * smoothstep(reach, 0.15, r) * (1.0 - progress) * 0.9;
		// 外晕：一圈很淡的圆，给"冲击"一个体量
		float halo = smoothstep(0.55, 0.0, r) * 0.25 * (1.0 - progress);
		a = core + rays + halo;
		col = mix(core_color.rgb, edge_color.rgb, clamp(r * 1.2, 0.0, 1.0));
	} else {
		// ── 冲击波：一个薄环，半径随进度从 0.15 推到 0.95 ──────────
		float radius = 0.15 + 0.80 * progress;
		float thick = 0.16 * (1.0 - progress * 0.55);
		float ring = smoothstep(thick, 0.0, abs(r - radius));
		// 环后方的余辉（薄薄一层拖尾），让扩散不是"一个孤零零的圈"
		float trail = smoothstep(radius, max(radius - 0.22, 0.0), r) * 0.18;
		a = (ring + trail) * (1.0 - progress * 0.75);
		col = mix(core_color.rgb, edge_color.rgb, progress);
	}

	a = clamp(a, 0.0, 1.0) * intensity;
	// 加色混合：亮度就是"能量"，不用 alpha 做淡出
	ALBEDO = col * a;
	ALPHA = clamp(a, 0.0, 1.0);
}
