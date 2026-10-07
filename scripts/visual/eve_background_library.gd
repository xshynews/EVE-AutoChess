extends RefCounted
class_name EveBackgroundLibrary

## EVE 自走棋 —— 可替换背景库
##
## 设计目标：把「背景」从场景代码里彻底剥离成一个【数据条目】。
##   换背景 = 改一个 id / 丢一个文件进 assets/backgrounds/，不改任何场景逻辑。
##
## ── 【重要更正】只保留一种投影模式：天空盒 ──────────────────────────
##
## 用户指出参考程序「做了个天空盒，然后在天空盒上做了个星空贴图」——
## 这是对的。补抽 combat-webgl-renderer.js 的 vertex 段后确认：
## 它是「全屏三角 + 逐像素球面反投影」，即天空盒（详见 EveBackground 文件头）。
##
## 所以本库原来的 MODE_BILLBOARD（平面背景板）已被【移除】。
## 它是「误判参考程序为平面贴图」这个错误前提的产物，连带催生了
## highlight_compress / zoom / zoom_center 三个补偿字段 —— 也一并删掉。
##
## 现在只剩：
##   MODE_EQUIRECT  等距柱状全景 → 天空盒（唯一正确选择）
##   MODE_NONE      纯色兜底
##
## ⚠️ 非 2:1 的图（比如 16:9 的概念图）不应该丢进这里当背景。
##    正确做法是先转成等距柱状投影，否则贴到球上会被拉伸变形
##    （「糊在天花板上的一张画」）。

enum Mode {
	MODE_EQUIRECT,   ## 全景天空盒（必须是 2:1 等距柱状图）
	MODE_NONE,       ## 纯色（关掉贴图，只留底色）
}

## 单条背景记录
##
## 字段全部是「给场景读的」纯数据，不含任何节点引用 ——
## 这样它既能在编辑器里 @export，也能从 JSON 外部加载。
class Entry extends RefCounted:
	var id: String = ""              ## 唯一标识（存档 / 配置里用这个）
	var display_name: String = ""    ## 中文显示名（调试面板 / 设置界面用）
	var path: String = ""            ## res:// 路径
	var mode: int = Mode.MODE_EQUIRECT
	var intensity: float = 1.0       ## 亮度倍率（参考程序默认 0.86）
	var tint: Color = Color.WHITE    ## 叠加色调（乘算）
	## 天球赤道倾角（度）—— 对应参考程序 shader 里那个硬编码 3×3 矩阵。
	##
	## 0 表示「用 EveBackground.SKY_PITCH_BIAS_DEG 的默认值」。
	## 每条背景如果来自不同星系，这个值应当不同（EVE 每个星系有自己的天球朝向）。
	var sky_pitch_bias: float = 0.0
	## 高光安全阀：0 = 不压缩（与参考程序完全等价）。
	##
	## ⚠️ 这是【例外路径】，不是默认。只在素材本身有接近纯白的过曝区、
	##    且压强度也救不回来时才开一点点（0.2~0.5）。
	##    正常情况下保持 0 —— 参考程序就是 0。
	var highlight_compress: float = 0.0
	var note: String = ""            ## 备注 / 版权说明 / 踩坑记录

	func is_valid() -> bool:
		return id != "" and (mode == Mode.MODE_NONE or ResourceLoader.exists(path))

	func describe() -> String:
		var modes := ["天空盒", "纯色"]
		var m: String = modes[mode] if mode >= 0 and mode < modes.size() else "?"
		return "%s [%s] %s" % [display_name, m, path]


## ── 内置背景表 ────────────────────────────────────────────────────
##
## 新增背景只需在这里加一条。想把背景完全外置的，见 load_from_json()。
static func builtin_entries() -> Array[Entry]:
	var out: Array[Entry] = []

	# 1) 官方加达里 C06 星域星云 —— 与参考程序同一张图
	#
	#    来源 res:/dx9/scene/universe/c16_cube.dds（BC6H cubemap）
	#    经「立方体贴图 → 等距柱状投影 + 透明度处理 + 离线 bloom」转换得到。
	#
	#    ⚠️ 这张图必须配天球赤道倾角一起用：
	#       它的星云主体在纬度 +34°~+49°，而战术相机俯视 41.3° 正对南半球暗区，
	#       不摆天球就完全看不到内容。
	#       实测数据见 EveBackground.SKY_PITCH_BIAS_DEG 的说明。
	var caldari := Entry.new()
	caldari.id = "caldari_c06"
	caldari.display_name = "加达里 C06 星云"
	caldari.path = "res://assets/backgrounds/caldari-c06-starfield.webp"
	caldari.mode = Mode.MODE_EQUIRECT
	# 0.86 是参考程序的默认值，直接对齐。
	caldari.intensity = 0.86
	# 用 EveBackground 的默认天球倾角（当前 = 91°，由「真机朝向 + 天球矩阵」
	# 解析反解而来，见 EveBackground.SKY_PITCH_BIAS_DEG 的说明）
	caldari.sky_pitch_bias = 0.0
	caldari.note = "官方 c16 cubemap 转等距柱状；2:1；天球倾角用默认值 91°"
	out.append(caldari)

	# 2) 双联星云 —— 用户提供的两张星云图拼接成的一张 2:1 等距柱状图
	#
	#    拼接脚本见会话工作区 _sky_stitch.py。关键认识：
	#    两张源图各是 1920x1024 / 1920x1026（比例 1.875），
	#    这【已经近似 360°x180° 的等距柱状构图本身】（两个方向的
	#    像素/度 只差 6.8%，肉眼不可见），不是「半张全天球」。
	#
	#    所以做法是【各自铺满 360°】再用周期性权重叠合 ——
	#    而不是左半右半硬拼（那要么砍掉每张 47% 内容，
	#    要么纵向拉伸 2 倍把星点变成竖椭圆）。
	#
	#    无缝靠「让两张图的固有边缘互相藏在对方的独占区里」——
	#      · 源图不是环绕贴图：每张的【左边缘】与【右边缘】本来就不连续
	#        （实测 A 差 69/255、B 差 141/255）。
	#      · 曾用「把图滚到自身最平滑的那一列」来躲这个边缘 —— 那是错的：
	#        滚动只是把硬边从 W-1|0 【搬家】到 0|1，并没有消除它，
	#        而验收又恰好只量 W-1|0 那一列，于是自己把自己骗过。
	#        症状：屏幕上一条斜直边界（经线在球面投影里本就是直线）。
	#      · 正解：A 不滚（边缘留 u=0），B 滚半个圆周（边缘到 u=180°），
	#        再用周期性权重把 u=0 交给 B 独占区、u=180° 交给 A 独占区。
	#        残差严格为 0（mask=0 时 composite 精确取另一张图）。
	#      · 验收要按【逐纬度带扫全图所有列】，不能只看环绕接缝那一列。
	#        真接缝会在整列所有行上跳变；星点只跳一两行 —— 用「高跳行数」
	#        区分两者。（实测：整列硬边 0 条，最大列均值跳变 0.0086）
	#
	#    ⚠️ 这张图后来做了「银河带」重构：星云不再糊满全天球，而是压到
	#       一条 ±45° 的环带里，两极留成纯净深空 + 星点。所以它的
	#       sky_pitch_bias 要让相机【看向环带的上边缘之外一截】——
	#       这样整圈轨道都是「上方深空 + 下方星云」的构图，
	#       不会转到某一侧撞上满屏糊云（_sky_bias_pick.py 扫过全部
	#       俯仰角 + 12 个 yaw，bias +40 时最差 yaw 评分 -2.86，
	#       +90 时 -0.26，差别很大）。
	#       解析式 0.911·sin(bias−46.33°) → bias +90° 采样纬度 +39.0°。
	var duo := Entry.new()
	duo.id = "nebula_duo"
	duo.display_name = "双联星云（拼接 + 银河带）"
	duo.path = "res://assets/backgrounds/nebula-duo-4096.png"
	duo.mode = Mode.MODE_EQUIRECT
	duo.intensity = 0.86
	duo.sky_pitch_bias = 90.0
	duo.note = "两图周期性权重无缝叠合 → 再压成 ±45° 环带 + 程序化星空；bias +90°（中心采样 +39.0°）"
	out.append(duo)

	# ══ 3~5) 官方星云（直接从本机 EVE 客户端缓存解码，2026-09-19 接入）══════
	#
	# ── EVE 官方天空盒到底是怎么做的（查证结论）───────────────────────
	#
	# CCP 的星云【不是】等距柱状图，也【不是】截图拼接，而是
	# **手工制作的立方体贴图（cubemap）**：
	#   · 美术在 3D 里生成云 → 渲染出六面 → 再逐面手工修图（修掉接缝与构图）
	#   · 发布路径  res:/dx9/scene/universe/<组名>_cube.dds
	#     = 2048×2048 × 6 面，BC6H_SF16（HDR 半浮点）
	#   · 同组另有 _cube_lowdetail(512²) / _cube_blur / _cube_refl / .black
	#   · 官方共 75 组，命名即派系：
	#       a01..a18 艾玛    c01..c19 加达里
	#       g01..g11 盖伦特  m01..m17 米玛塔尔
	#     所以「四派系色系」是官方本来就有的：a 金 / c 蓝 / g 绿 / m 琥珀。
	#
	# ⚠️ 本机 EVE 客户端（D:/EVE/SharedCache）里就有全部原始资源，
	#    直接解码出来【比任何游戏截图都清晰】：截图最多 1080p 且带 HUD 与
	#    有损压缩，官方源是每面 2048² 的 HDR。
	#    ⇒ 不需要再去游戏里截图拼接（那条路已被本方案取代）。
	#
	# ⚠️ BC6H 不能用 texture2ddecoder 解（该库 BC6 分支返回全黑），
	#    要用微软 DirectXTex 的 texconv.exe。完整流水线见会话工作区
	#    _eve_neb.py / _eve_neb_gallery.py / _eve_export_assets.py，
	#    一条命令即可产出 75 组里的任意一组。
	#
	# ⚠️ 立方体→等距柱状 有一个致命坑（踩过）：
	#    面选择表里 comp=|x| 既当 ma 用、又被误用来判正负，而 |x|>0 恒真
	#    ⇒ 面 1/3/5（-X/-Y/-Z）永远不被选中，负半球全被当成 +X/+Y/+Z 采样。
	#    症状 = 屏幕上「一块块 90° 宽的圆角方块」+ 整体发灰
	#    （最亮的 -X 面被整个丢弃）。判正负必须用【带符号分量】。
	#    验收：随机方向取样「等距柱状图 vs 直接查立方体」，误差应 <1%。
	#
	# ⚠️ sky_pitch_bias 是按【实机相机】选的，不是按全景图选的。两个坑：
	#    ① 口径必须与 tools/verify_background 第 6 项对齐，否则本地选得再好、
	#       工程里验收也报 FAIL；
	#    ② 打分必须在【统一曝光】下做 —— 用整张全景图的 p99.9 当归一化基准。
	#       若让每个局部视野各自按自身 p99.9 归一（= 每格自动曝光），
	#       那么「转到某一侧几乎全黑」也会显得挺好，完全丧失判断力（踩过）。
	#    ③ 我还踩过第三个：用「12 个方位的最差一个」当目标函数，
	#       会把星云推出视野（最差最大化 = 选一个"到处都均匀地暗"的角度）。
	#       正确做法是【默认相机视角为主指标 + 全方位不刺眼为约束】。
	#
	# 色调映射：ACES filmic（高光滚降柔和、暗部保留微弱云结构）+ γ2.2 +
	#    轻微 lift + 量化前三角抖动（深空大面积渐变不加必出色带）。
	#    实测在 4 条曲线（线性 / Reinhard+黑切 / ACES / 朴素拉伸）里 ACES 综合最好。

	# 3) 艾玛 A03 —— 三张里最稳的（默认视角 lift 2.52x / span 0.562，全向最高 0.74）
	var a03 := Entry.new()
	a03.id = "amarr_a03"
	a03.display_name = "艾玛 A03 星云"
	a03.path = "res://assets/backgrounds/amarr-a03-nebula-4096.png"
	a03.mode = Mode.MODE_EQUIRECT
	a03.intensity = 0.86
	a03.sky_pitch_bias = 9.0
	a03.note = "官方 a03_cube 2048²/面 BC6H 解码 → 等距柱状 + ACES；" \
			+ "bias +9°（中心采样 -33.6°）；默认视角 lift 2.52x / span 0.562"
	out.append(a03)

	# 4) 盖伦特 G03 —— 绿金色星云，暗调、安静
	var g03 := Entry.new()
	g03.id = "gallente_g03"
	g03.display_name = "盖伦特 G03 星云"
	g03.path = "res://assets/backgrounds/gallente-g03-nebula-4096.png"
	g03.mode = Mode.MODE_EQUIRECT
	g03.intensity = 0.86
	g03.sky_pitch_bias = 87.0
	g03.note = "官方 g03_cube 解码；bias +87°（中心采样 +36.4°）；lift 2.29x / span 0.503"
	out.append(g03)

	# 5) 加达里 C02 —— 蓝色云团 + 红色星云核，戏剧性最强
	var c02 := Entry.new()
	c02.id = "caldari_c02"
	c02.display_name = "加达里 C02 星云"
	c02.path = "res://assets/backgrounds/caldari-c02-nebula-4096.png"
	c02.mode = Mode.MODE_EQUIRECT
	c02.intensity = 0.86
	c02.sky_pitch_bias = 24.0
	c02.note = "官方 c02_cube 解码；bias +24°（中心采样 -20.3°）；lift 2.54x / span 0.488"
	out.append(c02)

	# 6) 加达里 C07 —— ★ 当前默认（2026-09-20 换上）
	#
	#    为什么换：用户反馈「天空盒还是太暗了」。量了一下确实站得住脚 ——
	#      c02 全景均值只有 37.0/255、p50 才 18（大片近黑），明暗比 25.4×；
	#      而 c07 均值 106.6、p50 102，明暗比 4.7×。**相差近 3 倍**。
	#    选 c07 而不是 c06 的理由：
	#      · 亮度 c07(106.6) > c06(93.3)；而且 c07 在【本机客户端缓存里就有】，
	#        c06 的 cube 本地缺失、要走 CDN 下。
	#      · 两者都是加达里（用户点名要加达里）。
	#
	#    ⚠️ intensity 与其它条目一致保持 0.86 —— 用户明确说「亮度不要改」。
	#       亮度的提升【全部来自换图本身】，不靠拉 intensity 补偿。
	#       所以这张比 c02 亮，是图亮的，不是参数改的。
	#
	#    bias +63° 是唯一解：按工程的解析式
	#      bias = 46.33° + asin(sin(目标纬度) / 0.911)
	#      代入本图星云带中心 +15.1° → 62.95° ≈ 63°。
	#    实测该图的纬度亮度剖面峰值在 +11°~+14°，与此吻合。
	var c07 := Entry.new()
	c07.id = "caldari_c07"
	c07.display_name = "加达里 C07 星云"
	c07.path = "res://assets/backgrounds/caldari-c07-nebula-4096.png"
	c07.mode = Mode.MODE_EQUIRECT
	c07.intensity = 0.86
	c07.sky_pitch_bias = 63.0
	c07.note = "官方 c07_cube 解码（本机缓存完好）；bias +63°（中心采样 +15.1°）；" \
			+ "全景均值 106.6 / p50 102 / 明暗比 4.7×；映射验收误差 0.63%"
	out.append(c07)

	# 7) 纯色兜底 —— 无贴图，最低开销
	var plain := Entry.new()
	plain.id = "plain_deep"
	plain.display_name = "纯深空底色"
	plain.path = ""
	plain.mode = Mode.MODE_NONE
	plain.intensity = 1.0
	plain.note = "无贴图；用于排查「背景是否本身就有问题」"
	out.append(plain)

	return out


## 全部可用 id（供设置界面 / 校验用）
static func available_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for e in builtin_entries():
		out.append(e.id)
	return out


## 按 id 取一条；找不到返回 null
static func find(id: String) -> Entry:
	for e in builtin_entries():
		if e.id == id:
			return e
	return null


## 从外部 JSON 加载 / 覆盖背景表（热更背景用，不改代码也不重编）
##
## JSON 格式：
##   { "backgrounds": [
##       { "id": "my_bg", "display_name": "我的背景",
##         "path": "res://assets/backgrounds/my_bg.png",
##         "mode": "equirect", "intensity": 0.86,
##         "tint": [0.9, 0.95, 1.0],
##         "sky_pitch_bias": -83.0, "note": "..." } ] }
##
## mode 接受 "equirect" / "none"（旧的 "billboard" 会警告并回退）。
## 返回解析成功的条目数。文件不存在时返回 0（不报错，静默降级到内置表）。
static func load_from_json(json_path: String) -> Array[Entry]:
	var out: Array[Entry] = []
	if not FileAccess.file_exists(json_path):
		return out
	var text := FileAccess.get_file_as_string(json_path)
	if text.is_empty():
		return out
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("背景表 JSON 根节点必须是对象：%s" % json_path)
		return out
	var list = parsed.get("backgrounds", [])
	if typeof(list) != TYPE_ARRAY:
		return out
	for raw in list:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var e := Entry.new()
		e.id = str(raw.get("id", ""))
		if e.id.is_empty():
			continue
		e.display_name = str(raw.get("display_name", e.id))
		e.path = str(raw.get("path", ""))
		e.mode = _parse_mode(str(raw.get("mode", "equirect")))
		e.intensity = float(raw.get("intensity", 1.0))
		e.sky_pitch_bias = float(raw.get("sky_pitch_bias", 0.0))
		e.highlight_compress = float(raw.get("highlight_compress", 0.0))
		var t = raw.get("tint", null)
		if typeof(t) == TYPE_ARRAY and t.size() >= 3:
			e.tint = Color(float(t[0]), float(t[1]), float(t[2]))
		e.note = str(raw.get("note", ""))
		out.append(e)
	return out


static func _parse_mode(s: String) -> int:
	match s.strip_edges().to_lower():
		"equirect", "sky", "sphere", "skybox":
			return Mode.MODE_EQUIRECT
		"none", "plain", "color":
			return Mode.MODE_NONE
		"billboard", "plane", "backdrop":
			# 参考程序没有这一路；留着配置项只会让「错的前提」复活
			push_warning("背景模式 'billboard' 已移除（参考程序是天空盒），回退为 equirect")
			return Mode.MODE_EQUIRECT
		_:
			push_warning("未知的背景模式 '%s'，回退为 equirect" % s)
			return Mode.MODE_EQUIRECT
