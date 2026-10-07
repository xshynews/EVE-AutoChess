extends Node3D
class_name EveBackground

## EVE 自走棋 —— 可替换背景渲染器（天空盒版）
##
## ══════════════════════════════════════════════════════════════════════
## 【重要更正】参考程序的背景到底是什么
## ══════════════════════════════════════════════════════════════════════
##
## 我第一版把它判成「全屏贴图 / 背景板」，那是错的 —— 用户直接指出了
## 这一点：「星装舰船配置.exe 是做了个天空盒，然后在天空盒上做了个星空
## 贴图」。回去把 combat-webgl-renderer.js 的【vertex 阶段】补抽之后，
## 原文是这样的：
##
##   const environmentVertex = `#version 300 es
##     precision highp float; out vec2 vNdc;
##     void main(){
##       vec2 position = gl_VertexID==0 ? vec2(-1.0,-1.0)
##                     : gl_VertexID==1 ? vec2( 3.0,-1.0)
##                                      : vec2(-1.0, 3.0);
##       vNdc = position;
##       gl_Position = vec4(position, 0.9999, 1.0);   // 永远在最远层
##     }`;
##
##   const environmentFragment = `#version 300 es
##     ...
##     vec3 viewRay = normalize(uForward + uRight*viewX + uUp*viewY);
##     vec3 ray = normalize(M * viewRay);              // M = 天球姿态矩阵
##     vec2 uv = vec2(atan(ray.x, ray.z)/(2.0*PI) + 0.5,    // 经度 → u
##                    0.5 - asin(clamp(ray.y,-1.0,1.0))/PI); // 纬度 → v
##     float halfTexel = .5/float(textureSize(uEnvironment,0).x);
##     uv.x = mix(halfTexel, 1.0-halfTexel, uv.x);     // 半纹素内缩，消接缝
##     vec3 color = textureLod(uEnvironment, uv, 0.0).rgb;
##     outColor = vec4(color * uIntensity, 1.0);`;
##
## ⚠️ 这是【天空盒】的标准实现，而且是 EVE 客户端的写法：
##
##   不建球壳几何体，而是「全屏三角形 + 逐像素球面反投影」。
##   数学上完全等价于一个半径无限大的球幕，但：
##     ① 省掉几何体（2 个三角形 vs 4850 个顶点）
##     ② 不吃视锥剔除 / 不需要 extra_cull_margin
##     ③ 不会有球壳在相机移动时的透视偏移
##
##   我的错误在于：【只抽了 fragment 段就下了几何结论】。
##   `gl_VertexID` 那三行是几何的全部，我没看；而
##   `atan(ray.x, ray.z)` / `asin(ray.y)` 是教科书级等距柱状映射，
##   我却把 uEnvironment 当成了一张「构图海报」。
##
##   结果就是在旧实现里加了一堆参考程序【根本没有】的补偿：
##     bg_compress（高光压缩）、bg_zoom（取景缩放）、bg_zoom_c
##   —— 全部因为错误前提「平板贴图有构图问题」。
##
## ══════════════════════════════════════════════════════════════════════
## 本文件现在的实现策略
## ══════════════════════════════════════════════════════════════════════
##
## 保留球壳几何体（SphereMesh），不用全屏三角，理由：
##   Godot 里做全屏三角要占一个 CanvasLayer 或走 CompositorEffect，
##   而 SphereMesh 的等距柱状 UV 是引擎原生支持的（实测已确认），
##   代码量小得多，视觉后果一致。
##
## ⚠️ 但实测发现两个必须显式补偿的 Godot 约定差异 —— 见下面两段。
##
## ── 差异 ①：经度起点差 180 度 ─────────────────────────────────────
##
##   实测 SphereMesh 的顶点/UV 对应关系：
##       dir=(0,0,+1) → u=0.0000
##       dir=(1,0,0)  → u=0.2500
##       dir=(0,0,-1) → u=0.5000
##       dir=(-1,0,0) → u=0.7500
##   即 u = i/radial_segments，而顶点位置是 -sin(phi)/-cos(phi)（带负号），
##   两者差 180 度。参考程序没有这个问题（它自己算 atan）。
##
##   修法：给球幕绕 Y 轴补 180 度（YAW_FIX_DEG）。
##
## ── 差异 ②：天球俯仰偏置的方向和数值 ───────────────────────────────
##
##   参考程序把「天球姿态」写成 shader 里的硬编码 3×3 矩阵 M：
##       M = [-.1392603 -.4202494 -.8966588]
##           [ .8180628  .4614205 -.3433138]
##           [ .5580142 -.7813332  .2795328]
##   实测：det = 1.0000000，M·Mᵀ = I  —— 是标准正交矩阵（天球姿态）。
##   它隐含一个绕 X 的赤道倾角 = asin(0.5580142) = 33.919 度。
##
##   ⚠️ 我在这一个参数上连错两次，都是「方向错」而不是「数值错」：
##      ① 旧代码 sky_pitch_bias = -34.0（靠试 span 值蒙出来的）
##      ② 第一次修正 -83.0（用手算反解「推」出来的）
##      两次实测都落在天底附近（-5.5° / -89.6°），而星云主体在 +34~+49°，
##      等于完全没生效。共同错误根源：都假设了「俯视相机要反向转」，
##      而球幕绕 X 正转才是把下方天球内容送到视线方向上的那个方向。
##
##   正确做法（已验证）：不猜、不反解，直接扫。
##      跑 tools/probe_sky_uv.tscn，以 20° 步长扫 [-180, +180]，
##      打印每档的采样纬度，读表取命中带内的档位。
##      实测命中档：-60°（纬度 +40.4°）与 +160°（等价，差一个整圈）。
##
##   ⚠️ 别再试图「用公式一步算出来」。因为 yaw 修正与 pitch 修正的
##      复合顺序、以及 Godot YXZ 欧拉序，会让手算的符号极易反 ——
##      这个参数的正确性只能由【采样纬度读数】背书。
##
## ══════════════════════════════════════════════════════════════════════
## 与参考程序的【等价性验证】
## ══════════════════════════════════════════════════════════════════════
##
##   两者在数学上都归约为：
##     v = 0.5 - asin(dir.y)/PI          （纬度）
##     u = atan(dir.x, dir.z)/(2PI)+0.5  （经度）
##   区别只是我们的 dir 由「球壳几何体的插值 UV」给出，
##   参考程序由「逐像素 ray 反投影」给出。视觉结果一致。
##
## ── 可替换背景（用户需求）─────────────────────────────────────────
##   MODE_EQUIRECT：2:1 等距柱状全景 → 天空盒（唯一正确选择）
##   MODE_NONE    ：纯色兜底
##
##   原来的 MODE_BILLBOARD 已被【移除】。原因：参考程序根本没有这一路，
##   而它是用户这次指出问题的直接产物 —— 错误前提催生的多余分支。
##   如果以后确实需要「用一张普通构图图当背景」，正确做法是先把它
##   转成等距柱状（或接受它在球面上的拉伸），而不是加一套平面背景板。

# ------------------------------------------------------------------ 常量

## 球幕半径。取 12000 —— 远大于战场（几十单位）又小于相机 far 上限（20000）。
##
## ⚠️ 不要为了「省得改 far」把半径设小。
##    半径一旦接近相机 far，球壳会被视锥裁掉一角，画面边缘出现硬边。
const SKY_RADIUS := 12_000.0

## 经度起点修正（度）—— 补偿 Godot SphereMesh 的 UV 与顶点差 180 度的问题
## 详见文件头「差异 ①」
const YAW_FIX_DEG := 180.0

## 天球俯仰偏置（度）—— 让【画面中央】拍到等距柱状图里的星云带
##
## ⚠️ 这个参数我连错四次。前三次是【方向/符号】错、不是数值错：
##     ① -34°（靠试 span 值蒙出来的）    → 落空
##     ② -83°（手算反解「推」出来的）    → 落空（正视天底）
##     ③ -60°（用简化向量扫描出来的）    → 落空（向量漏了 x 分量）
##   共同根因：都假设了「俯视相机要反向转」，而球幕绕 X 正转才是把
##   下方天球内容送到视线方向上的那个方向；且视线【不是】YZ 平面内的
##   向量 —— 轨道相机用 look_at，其 up 由 up×(target-pos) 解出，
##   相机绕 Y 到 -33° 时 basis 被额外多转约 43°，
##   真机朝向是 (0.412, -0.659, -0.629)，带 x 分量。
##
##   第四次错在【纬度换算系数】，隐蔽得多，值得单独记：
##     sample_center_latitude 报的纬度写成了 (0.5 - v) * 360，
##     而正确是 (0.5 - v) * 180（推导见该函数注释）——【正好差一倍】。
##     于是「报告纬度」与「贴图纬度带」分属两种单位：
##     报告 +40° 看着命中带 +34~+49，真实机位其实只有 +20°，低了 20°。
##     症状只是「画面偏暗」，极难往「单位错了」上想。
##
## ✅ 现在的正确几何关系（相机默认机位固定，由 eve_orbit_camera.gd 决定）：
##        球幕局部 dir.y = 0.911 · sin(bias − 46.33°)
##        采样纬度      = asin(dir.y) · 180/π
##    由它解析反解，一步到位，不必再跑扫描：
##        caldari c16 星云带 +34~+49（中心 +40） → bias ≈ +91°
##        nebula_duo  星云带 +17.5（重拼版）      → bias ≈ +66°（贴到带中心）
##                    实用取 +40 → 中心采样 −5.8°，画面上暗尘埃带与亮带兼得
##    可达纬度上限约 ±64°（再往外没有更多天区可转）。
##
## ⚠️ 只有换了默认机位（DEFAULT_PITCH / DEFAULT_YAW）时，上式才要重推。
##    换贴图只需按「新图星云带纬度」重代一次。
##
## 工具：tools/probe_sky_uv.tscn（可为任意目标纬度求 bias）
##       tools/verify_background.tscn 第 6 项（不看纬度数字，直接量贴图像素，
##       是这套坐标记账的独立校验 —— 上述第四次错误就是它抓出来的）
const SKY_PITCH_BIAS_DEG := 91.0

## 球幕在渲染队列里的优先级 —— 必须是【最先画的那个】
##
## ⚠️ 这不是性能调优，是正确性修复（2026-09-20 实测定位）。
##
## ── 为什么球幕会跑去和棋盘抢排序位 ──────────────────────────────
##   下面 BG_SKY_SHADER 的 fragment 里有一句 `ALPHA = 1.0;`。
##   只要 shader 给 ALPHA 赋过值，Godot 就把这个材质判成【透明】——
##   于是半径 12000 的球幕进的不是「背景」队列，而是【透明队列】。
##
##   透明队列是【按到相机的距离从远到近】排序的，球幕的 AABB 中心
##   在竞技场原点附近（≈ 相机距离 180），而棋盘 AABB 中心在
##   global z = -11.1（相机在 +z 侧 → 棋盘更远）。
##   两个距离只差几十个单位 → 球幕排在棋盘【后面】画 →
##   球幕把整块棋盘刷成了星云。
##
## ── 症状为什么极具迷惑性 ────────────────────────────────────────
##    11×11 网格线、三区底色全部消失，唯独 6×6 的落点高亮格还在。
##    看起来像「大的不画、小的画」，很容易误判成几何或材质问题
##    （实测排查时确实先怀疑了 MeshInstance3D / AABB / 顶点数据）。
##    真实原因是 z 差：高亮格在 z = +6.9，比球幕中心【更近】，
##    排序上反而活了下来。
##
##    佐证：把棋盘材质换成【不透明】就立刻出现（不透明队列不参与
##    这个排序）；在只有纯色底的干净场景里也正常（没有球幕）。
##
## ── 为什么用 render_priority 而不是「删掉 ALPHA = 1.0」 ──────────
##    删掉 ALPHA 会让球幕改走不透明队列 / 深度预通道，那是另一条
##    渲染路径；而本项目的背景亮度是按现在这条路径调好的
##    （见 _build_environment 的「通透参数组」，以及 verify_background
##    对亮度的独立校验），不该顺带改掉。压低排序优先级是同一路径内
##    最小的一刀。
const SKY_RENDER_PRIORITY := -128

## 球幕着色器 —— 对照参考程序逐行等价，只多加一个「可选的高光安全阀」。
##
## 参考程序核心就一句 `color * uIntensity`。我们保持一致，
## 但保留一个 default 关闭的 compress 分支，用于处理「贴图本身
## 有接近纯白过曝区」的个别素材（不是默认路径）。
const BG_SKY_SHADER := """
shader_type spatial;
render_mode unshaded, cull_front, depth_draw_never, fog_disabled;

uniform sampler2D bg_texture : source_color, filter_linear, repeat_enable;
uniform vec4  bg_tint : source_color = vec4(1.0);
uniform float bg_compress : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	// ⚠️ 必须用内建 UV，不能自己 varying 再在 vertex() 里赋值。
	//    实测：写 `varying vec2 v_uv; void vertex(){ v_uv = UV; }` 时
	//    着色器能编译，但 v_uv 恒为 (0,0)，整张球幕采到同一个纹素 —— 表现为
	//    「背景一片糊、像单色渐变」。Godot spatial 着色器里 UV 是内建可用的。
	vec3 c = texture(bg_texture, UV).rgb;

	// 高光安全阀：默认 0.0 = 恒等，与参考程序的直出完全等价。
	// 只在素材本身有过曝白核时才开（0.2~0.5 足够）。
	if (bg_compress > 0.0) {
		float knee = 0.85;
		vec3  hi   = max(c - vec3(knee), vec3(0.0));
		vec3  lo   = min(c, vec3(knee));
		hi = sqrt(hi / max(1.0 - knee, 0.0001)) * (1.0 - knee);
		c = mix(c, lo + hi, bg_compress);
	}

	ALBEDO = c * bg_tint.rgb;
	ALPHA  = 1.0;
}
"""

# ------------------------------------------------------------------ 状态

var _entry: EveBackgroundLibrary.Entry = null
var _sky_node: MeshInstance3D = null
var _sky_material: ShaderMaterial = null
var _camera: Camera3D = null
var _shader: Shader = null

## 背景切换信号（供 HUD / 调试面板订阅）
signal background_applied(id: String, mode: int)

# ------------------------------------------------------------------ 生命周期

func _ready() -> void:
	_build_sky_node()


## 绑定相机（半径校验 + far 修正需要）
func bind_camera(cam: Camera3D) -> void:
	_camera = cam
	if _camera != null:
		_camera.far = maxf(_camera.far, SKY_RADIUS * 1.6)


# ------------------------------------------------------------------ 对外主接口

## 应用一条背景数据 —— 这是「换背景」的唯一入口
##
## 返回是否成功。失败时保持原背景不变（静默降级，不抛异常中断战斗）。
func apply_entry(entry: EveBackgroundLibrary.Entry) -> bool:
	if entry == null:
		push_warning("背景条目为空，忽略")
		return false

	# 纯色模式：交给 Environment 的 background_color
	if entry.mode == EveBackgroundLibrary.Mode.MODE_NONE:
		_hide_sky()
		_entry = entry
		background_applied.emit(entry.id, entry.mode)
		return true

	# 贴图缺失：宁可保持原样，也不要黑屏
	if not ResourceLoader.exists(entry.path):
		push_warning("背景贴图不存在：%s（保持当前背景）" % entry.path)
		return false

	var tex: Texture2D = load(entry.path)
	if tex == null:
		push_warning("背景贴图加载失败：%s" % entry.path)
		return false

	_entry = entry
	_apply_sky(tex, entry)
	background_applied.emit(entry.id, entry.mode)
	return true


## 按 id 应用（最常用）
func apply_id(id: String) -> bool:
	var e := EveBackgroundLibrary.find(id)
	if e == null:
		push_warning("未知背景 id：%s（可用：%s）"
				% [id, ", ".join(EveBackgroundLibrary.available_ids())])
		return false
	return apply_entry(e)


## 在可用背景之间循环切换（调试按键 / 演示用）
func cycle(delta: int = 1) -> String:
	var ids := EveBackgroundLibrary.available_ids()
	if ids.is_empty():
		return ""
	var cur := _entry.id if _entry != null else ""
	var idx := ids.find(cur)
	idx = (idx + delta + ids.size() * 2) % ids.size()
	apply_id(ids[idx])
	return ids[idx]


## 实时调亮度（做视觉调试时免重跑）
func set_intensity(v: float) -> void:
	if _entry == null or _sky_material == null:
		return
	_entry.intensity = clampf(v, 0.0, 3.0)
	_push_tint()


## 当前背景 id
func current_id() -> String:
	return _entry.id if _entry != null else ""


## 中央视线实际采样到的贴图 UV
##
## 只报纬度是不够的 —— 横向取景同样会跑掉（u 偏了就是「星云转到画面外」）。
## 所以把 u 也如实算出来，供验证脚本直接去贴图上取像素。
##
## SphereMesh 的 u 约定（实测，见文件头「差异 ①」）：
##     u = atan2(dir.x, dir.z) / TAU      ← 比参考程序少 0.5
## 已用四个赤道方向核对：+Z→0.0 / +X→0.25 / -Z→0.5 / -X→0.75。
func sample_center_uv() -> Vector2:
	if _camera == null or _sky_node == null:
		return Vector2(0.5, 0.5)
	var fwd: Vector3 = -_camera.global_transform.basis.z
	var local := (_sky_node.global_transform.basis.inverse() * fwd).normalized()
	var v := 0.5 - asin(clampf(local.y, -1.0, 1.0)) / PI
	var u := fmod(atan2(local.x, local.z) / TAU, 1.0)
	if u < 0.0:
		u += 1.0
	return Vector2(u, v)


## 当前球幕的采样纬度（供探测脚本核验天球偏置是否生效）
##
## 返回 [纬度_度, v, 像素行]
##
## ⚠️ 这里必须【如实模拟球幕节点自身的世界变换】，不能用被简化的
##    「只乘一个绕 X 的旋转」—— 我在这上面又栽了一次，症状是：
##    探测脚本算出 -60° 命中星云带，验证脚本却算出 -121.9° 未命中。
##    原因见下。
##
## 球幕的世界变换 W（= rotation_degrees(pitch, yaw, 0)，Godot YXZ 序）：
##     W = Ry(yaw) · Rx(pitch)
## 世界视线转进球幕空间要【左乘 W⁻¹】（不是右乘，也不是乘 W）：
##     local = W⁻¹ · fwd = Rx(-pitch) · Ry(-yaw) · fwd
##
## 把 local.y 展开后，yaw 项恰好消失（Ry 不改变 y 分量）：
##     local.y = -sin(pitch)·fwd.x + cos(pitch)·fwd.y
##
## ⚠️ 关键：不能把 fwd 当成 (0, -sinθ, -cosθ) 来简化！
##    实测相机真实朝向是 (0.412, -0.659, -0.629)，带 x 分量。
##    原因是轨道相机用 look_at(focus)：其 up 向量由 up×(target-pos) 解出，
##    当相机绕 Y 旋到 -33° 附近时，这个 up 不再平行于世界 up，
##    整个相机 basis 被额外转了约 43°。
##    忽略这个 x 分量 → 纬度算出来差 80° 以上（-41 ⟷ -122）。
func sample_center_latitude() -> Array:
	if _camera == null or _sky_node == null:
		return [0.0, 0.0, 0.0]
	var fwd: Vector3 = -_camera.global_transform.basis.z
	# 球幕节点自身的世界变换的逆（不是 .transform.basis *，那方向反了）
	var local := _sky_node.global_transform.basis.inverse() * fwd
	local = local.normalized()
	var v := 0.5 - asin(clampf(local.y, -1.0, 1.0)) / PI
	# ⚠️⚠️ 换算系数是 180，不是 360。这里错过一次，代价很大：
	#
	#    v   = 0.5 - asin(y)/π        （v 值域 [0,1]，0=天顶、1=天底）
	#    ⇒ asin(y) = π·(0.5 - v)
	#    ⇒ 纬度(度) = asin(y) · 180/π = (0.5 - v) · 180
	#
	#    写成 *360 会让报出的纬度【正好是真实值的 2 倍】。
	#    后果不是「数字难看」，而是【偏置调错】：
	#      · 贴图纬度带是用另一套【正确】换算量出来的（90-180·y/h）
	#      · 于是「报告纬度」与「星云带纬度」分属两种单位，
	#        两者看似命中、实际差一倍 —— 星云根本没进画面中央。
	#      caldari c16 就是这样：偏置 70 报「+40.4° 命中带 +34~+49」，
	#      真实机位只有 +20.2°，比星云带低了 20°（画面偏暗的根因）。
	#
	#    这一次由 verify_background 第 6 项（整屏视野亮度）抓出来：
	#    它不信任任何纬度数字，直接去贴图上取像素 —— 于是 caldari 报 1.50x、
	#    nebula_duo 报 4.64x，两条与纬度无关的数字把「坐标记账」的矛盾暴露了。
	var lat := (0.5 - v) * 180.0
	return [lat, v, v * 2048.0]


# ------------------------------------------------------------------ 球幕实现

func _build_sky_node() -> void:
	var sphere := SphereMesh.new()
	sphere.radius = SKY_RADIUS
	sphere.height = SKY_RADIUS * 2.0
	sphere.is_hemisphere = false
	# 段数给足，否则球壳上的 UV 是分片线性的，全景图会出现多边形折角。
	# 96x48 实测足够（球幕占屏面积大，段数低了经线会显形）。
	sphere.radial_segments = 96
	sphere.rings = 48

	_sky_material = ShaderMaterial.new()
	_sky_material.shader = _get_shader()
	# ⚠️ 不给这个值，棋盘（以及一切 AABB 中心比球幕更远的透明几何）
	#    会被球幕整个盖掉 —— 实测：相机→球幕 96.8 / 相机→棋盘 103.5，
	#    棋盘更远 → 排在球幕前面画 → 被星云刷掉。详见 SKY_RENDER_PRIORITY。
	_sky_material.render_priority = SKY_RENDER_PRIORITY

	_sky_node = MeshInstance3D.new()
	_sky_node.name = "SkyBox"
	_sky_node.mesh = sphere
	_sky_node.material_override = _sky_material
	_sky_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# 球幕在 12000 处，不能被视锥剔除
	_sky_node.extra_cull_margin = SKY_RADIUS * 0.5
	add_child(_sky_node)


func _get_shader() -> Shader:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = BG_SKY_SHADER
	return _shader


## 应用等距柱状全景 —— 天球盒的唯一实现
##
## ⚠️ 旋转次序（先 Y 后 X）很重要：
##   先绕 Y 转 YAW_FIX_DEG 修正经度起点，再绕 X 转 SKY_PITCH_BIAS_DEG
##   摆天球赤道。若反过来（先 X 后 Y），Y 旋转会把已经倾斜的赤道
##   再拧一圈，星云的纬度带位置就跑掉了。
##   Godot 的默认欧拉序是 YXZ，赋值给 rotation_degrees 时只设 y 和 x
##   即可得到「先 Y 后 X」的效果（YXZ 序里 Y 在最外层）。
func _apply_sky(tex: Texture2D, entry: EveBackgroundLibrary.Entry) -> void:
	if _sky_node == null:
		_build_sky_node()

	_sky_node.visible = true
	_sky_material.set_shader_parameter("bg_texture", tex)
	# 高光安全阀：对齐参考程序时保持 0
	_sky_material.set_shader_parameter("bg_compress", entry.highlight_compress)
	_push_tint()

	# 天球姿态：先修正经度起点，再摆赤道倾角
	var pitch_bias: float = entry.sky_pitch_bias
	if absf(pitch_bias) < 0.01:
		pitch_bias = SKY_PITCH_BIAS_DEG
	_sky_node.rotation_degrees = Vector3(pitch_bias, YAW_FIX_DEG, 0.0)

	# 球幕不写深度：由 shader 的 depth_draw_never + cull_front 保证。
	# ⚠️ 但【最先绘制】不是 shader 能保证的 —— 旧注释在这里写错了，
	#    曾据此认为「球幕一定画在别人前面」，结果棋盘被球幕整个盖掉
	#    却排查了很久。排序由 _sky_material.render_priority 负责，
	#    见 SKY_RENDER_PRIORITY。这里只做 far 兜底。
	if _camera != null:
		_camera.far = maxf(_camera.far, SKY_RADIUS * 1.6)


## 把 tint × intensity 推给 shader
##
## ⚠️ 只用 bg_tint 控亮，不碰 emission ——
##    旧实现曾经 albedo_texture + emission_texture 都给同一张图，
##    在 unshaded 下两者叠加把整张图抬高一档并截顶（亮部糊成白），
##    这正是用户当时反馈「朦朦胧胧」的主要来源之一。
##    参考程序只有一句 color * intensity，没有任何叠加项。
func _push_tint() -> void:
	if _entry == null or _sky_material == null:
		return
	_sky_material.set_shader_parameter("bg_tint", Color(
		_entry.tint.r * _entry.intensity,
		_entry.tint.g * _entry.intensity,
		_entry.tint.b * _entry.intensity,
		1.0))


func _hide_sky() -> void:
	if _sky_node != null:
		_sky_node.visible = false
