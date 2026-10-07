extends RefCounted
class_name EveShipYawTable

## EVE 自走棋 —— 舰船 3D 模型「朝向修正表」（逐艘人工标定）
##
## ══════════════════════════════════════════════════════════════════
##  它替掉的是什么
## ══════════════════════════════════════════════════════════════════
##  `eve_ship_visual.gd` 原来只有一个**全船共用**的常量：
##
##      const MODEL_YAW_FIX := -PI / 2.0
##
##  它的前提是「所有 glb 的长轴在 +X，且舰艏朝 +X」。实测**两层都不成立**：
##
##    ① 长轴歪 —— condor / raven / tristan 的 XZ 主轴不在 X 上
##       （PCA 实测 +88.6° / +75.7° / −52.4°）
##       ⇒ 它们在棋盘上**斜着飞**，而尺寸、血条、位置全都正常，不看图发现不了。
##
##    ② 舰艏在主轴哪一端因船而异 —— PCA 主方向是**轴**不是**有向向量**，
##       数学上就说不出舰艏在哪头 ⇒ 这 180° **只能人眼标定**。
##
##  ⚠️⚠️ **2026-09-26 重要更正**：下面这套「20 保持 / 25 翻转 / 7 待定」的名单**已作废** ——
##  因为**那张总览图上的「前方 →」箭头是画反的**（实测世界 +Z 投在屏幕**左侧**而不是右侧，
##  见 `tools/probe_cam_axis.tscn`）。于是「图上船头朝右 = 本表给对了」这个判据从根上不成立，
##  按它逐格判出来的 `FLIP` 名单落成了**真值的补集**（24 条里判得動的 21 条有 20 条是错的）。
##  现行 `FLIP` 是 2026-09-26 用 `_e` 自发光贴图判据**重建**的 —— 见该 const 处的长注释。
##
## ── 口径（必须与出图口径一致）────────────────────────────────────
##     总偏航 = MODEL_YAW_FIX(−90°) + AXIS_DEG[id] + (180° if id ∈ FLIP)
##
##  逐步口径仍与 `tools/probe_ship_yaw_sheet.gd --apply=table` 同源。
##
## ⚠️ 改完这里**必须重跑总览图复核**，别只对着数字想。
## ⚠️ 但**别再拿那张老总览图上的箭头当判据** —— 箭头方向已确认是反的。
##    现行判据是**物理**的：`_e` 自发光贴图里「法线平行于舰艏轴」的面聚在哪端 ⇒ 那端是船尾。
##    工具 `C:\godot\_export\pose_sheet.py`（全库）· `multi_e_test.py` · `proof_pair.py`。
##    ⚠️「端部宽度分布」与「轮廓 IoU」两条自动路仍不可用（前者把磨难级判成同向、
##    后者 margin 落进噪声），过程见 `.workbuddy/memory/REF_3D模型朝向标定.md`。

## ── 主轴补偿：XZ 主轴相对 +X 的实测偏角（度）────────────────────
##
## 数值来自 tools/probe_ship_yaw_audit.tscn（PCA 实测，可复现）。
## **全部 52 艘都收**，零阈值 —— 连 0.01° 级的尾数也不丢。
##
## ⚠️ 为什么连 1~8° 的「小」偏角也要收（而不是只收那 3 艘超过 12° 的）：
##    出图口径（probe --align=z）对**每一艘**都做了这一步，
##    所以工程侧漏掉哪艘，那艘就会在棋盘上**持续歪着**。
##    实测差距不小：burst −7.85° / kestrel −4.81° / incursus +4.45° / omen +4.15°
##    —— 用户正是拿那张「已补偿」的图做的判定，工程侧必须同源。
##
## ⚠️ 为什么阈值取 0（第一版只收 19 艘，被差分验证打回来了）：
##    丢掉 |θ|<0.5° 的尾数后，改前/改后差分里非翻转船仍有 **0.8~1.4%** 的像素差。
##    先验证「渲染确定性」：同参数重复渲染同一批 → 差异 **0 像素**（不是噪声），
##    所以那 1% 只能是 θ 残差。⇒ 阈值降到 0，差分随之归零，
##    表与出图**逐像素同源**。这是个可验证的强结论，值得多这 30 行。
##
## ⚠️ 这一层是**纯几何**，与「哪端是舰艏」无关，
##    所以对 PENDING 那几艘也照常生效 —— 它们斜着飞同样要修。
##
## ══════════════════════════════════════════════════════════════════
##  ⚠️⚠️ 2026-09-26 复核：PCA 给的大多数值**不是模型的歪斜，是形状噪声**
## ══════════════════════════════════════════════════════════════════
##  起因：用户逐艘复核时指出「爆发级舰艏略歪」「小鹰级应逆时针转 90°」——
##  这两艘恰好是 PCA 表里 +88.64° / −7.85° 两个极值。于是重新问了一遍：
##  **「模型真的歪吗？」**
##
##  用两条**互相独立**、且都**不经过 PCA** 的判据全库重测：
##    ① `C:\godot\_export\nozzle_axis.py` —— **有向**喷口法线反解真轴方位。
##       取 `_e` 自发光且法线沿轴的面，求有向面积加权和 `v = Σ w·NR`（**不翻符号**）。
##       喷口朝外 ⇒ `v ≈ −A′`（A′ = 真舰艏轴）⇒ 它在 (A, 侧向) 平面内的方位角
##       与 180° 的差就是 A′ 相对 A 的偏角 δ，**δ 就是该船的 AXIS_DEG**。
##    ② `C:\godot\_export\sym_audit.py` —— 俯视**实心轮廓**与其左右镜像的 IoU
##       最大时的旋转角（与自发光、与 PCA 都无关）。从面积加权质心起算，扫到 0.02°。
##
##  **两条判据在对照组上逐度一致**（rifter / hyperion / apocalypse / abaddon 等
##  轮廓对称度 > 0.95 的船，两条都给出 |δ| < 0.05°）⇒ 判据可信。
##
##  结论：**47 / 52 艘的 δ 算出来是精确的 `+0.00`**（不是「接近零」—— 喷口面组
##  左右对称，垂直分量完全抵消，只剩 < 0.005° 的浮点噪声）。
##  也就是说**模型舰艏轴本来就是精确对齐的**，PCA 那批 1~8° 的值是在**制造**
##  它本要修的歪斜（PCA 会被翼展、不对称装甲板、近正方投影带偏 —— 见上面两条缺陷）。
##
##  ⇒ 本次把 **|旧值| > 1.0° 的 12 艘**归零（行尾注原值），保留其余的尾数：
##   bantam / burst / coercer / condor / dragoon / executioner /
##   incursus / omen / raven / scorpion / tempest / typhoon
##  其中
##    · `incursus` 取 +0.55（喷口法线直测值；轮廓镜像说 +4.27，细长船有 90° 歧义 ⇒ 信前者）
##    · `condor` / `burst` 与用户判读**同向**（逆时针 90° / 顺时针一点）⇒ 互证
##    · `raven` **用户尚未复核**（在总览图第 4 页）：旧值 +75.69 让乌鸦级一直**横躺着**
##      （俯视图里船身横置），两条判据都说应 ≈ 0 ⇒ 已归零。
##
##  ⚠️ **没动的两个例外，各有一条明确理由**：
##    · `corax`（+1.55）：两判据差 1.65°，且 `_e` 只有 8 个面 ⇒ 证据不足，且用户已判「对」；
##    · `myrmidon`（**2026-09-26 三轮：+10.41 → +0.02**）：旧值是在**错的残差平面**上量的
##      —— 当时它的 `AXIS_REMAP` 是 `+X,+Z,-Y`（船背指到 +Z ⇒ 船是侧躺的），
##      残差平面 = 模型 X-Y 面；改成 `+X,+Y,+Z` 之后平面变成模型 X-Z 面
##      ⇒ `probe_ship_yaw_audit` 回读 **θ = +0.02°、退化度 0.022**（PCA 可信）✓
##      ⚠️ 但它的**翻转**（180°）是独立的另一件事，已按用户判读进 FLIP。
##    · `catalyst`（**2026-09-26 三轮：+0.06 → −1.63**）：同上 —— AXIS_REMAP 由
##      `-X,+Y,-Z` 改为 `-X,+Z,+Y` ⇒ 回读 **θ = −1.63°、退化度 0.046**（PCA 可信）✓
##
##  验收口径不变：改完必须重跑总览图，别只对着数字想。
const AXIS_DEG := {
	&"abaddon": 0.00,
	&"algos": 0.00,
	&"apocalypse": 0.00,
	&"maller": 0.00,
	&"armageddon": 0.00,
	&"augoror": 0.00,
	&"bantam": 0.00,
	&"brutix": 0.00,
	&"burst": 0.00,
	&"caracal": 0.00,
	&"catalyst": 0.00,
	&"coercer": 0.00,
	&"condor": 0.00,
	&"corax": 0.00,
	&"cormorant": 0.00,
	&"cyclone": 0.00,
	&"dominix": 0.00,
	&"dragoon": 0.00,
	&"drake": 0.00,
	&"executioner": 0.00,
	&"exequror": 0.00,
	&"ferox": 0.00,
	&"harbinger": 0.00,
	&"hurricane": 0.00,
	&"hyperion": 0.00,
	&"incursus": 0.00,
	&"inquisitor": 0.00,
	&"kestrel": 0.00,
	&"maelstrom": 0.00,
	&"megathron": 0.00,
	&"moa": 0.00,
	&"myrmidon": 0.00,
	&"navitas": 0.00,
	&"omen": 0.00,
	&"osprey": 0.00,
	&"prophecy": 0.00,
	&"punisher": 0.00,
	&"raven": 0.00,
	&"rifter": 0.00,
	&"rokh": 0.00,
	&"rupture": 0.00,
	&"scorpion": 0.00,
	&"scythe": 0.00,
	&"slasher": 0.00,
	&"stabber": 0.00,
	&"talwar": 0.00,
	&"tempest": 0.00,
	&"thorax": 0.00,
	&"thrasher": 0.00,
	&"tristan": 0.00,
	&"typhoon": 0.00,
	&"vexor": 0.00,
}


## ── 需要先做模型轴重映射的船（rotate_y 修不了「上轴不在 Y」的滚转）──────
##
## 格式："世界X←模型A, 世界Y←模型B, 世界Z←模型C"
## 例如 "+X,-Z,+Y" 表示：
##   模型 +X 方向 → 世界 +X（舰艏）
##   模型 −Z 方向 → 世界 +Y（舰背朝上）
##   模型 +Y 方向 → 世界 +Z
## 由交互式标定台 `ship_orient_fix.html` 逐艘点出；未登记的船返回单位阵。
##
## ⚠️ 2026-09-23：7 艘 PENDING 全部由用户在交互式标定台里点【舰艏】+【船背】定出。
##    spec 语义 = **M 的三行逐行照抄**：世界X←舰艏 / 世界Y←船背 / 世界Z←侧向。
##    （第三轴 = 舰艏 × 船背，由 det=+1 唯一确定，所以三行不能随便写 ——
##      写入前 `probe_ship_yaw_audit` 会用叉积自洽校验，不一致会当场报错。）
##
## ✅ 2026-09-26 `_e` 自发光判据**独立复核**：`condor` / `kestrel` / `raven` / `tristan`
##    这 4 艘的第一行（= 舰艏轴）**全部正确**，其中
##      · kestrel：75 个喷口面、noz2 = −1.00 ⇒ 喷口在 −Y ⇒ 舰艏 +Y ✓
##      · tristan：65 个喷口面、noz2 = −0.96 ⇒ 喷口在 −Y ⇒ 舰艏 +Y ✓
##      · condor ：120 个喷口面、noz2 = −1.00 ⇒ 舰艏 +X ✓
##      · raven  ：ratio1 = −1.00 ⇒ 舰艏 +X ✓
##    ⚠️ kestrel / tristan 这条还与用户当年「格 6（−Y 端）看得到喷口」的读数**互相印证**
##     —— 说明标定台那套协议是对的，错的只有按箭头判的 FLIP。
##
## ❌ 唯一错的是 `myrmidon`：原 `"-X,+Z,+Y"` 声称舰艏在模型 −X，
##    但 `_e` 判据说喷口在 −X（9 个喷口面、noz2 = +0.72，与它 bbox「最长轴 = X」一致）
##    ⇒ 舰艏其实在 **+X**，第一行要翻过来。第三轴随之变为 舰艏×船背 = (+X)×(+Z) = −Y。
##    ⚠️ 改完 M **必须**重算 AXIS_DEG —— 已实测（`probe_ship_yaw_audit` 回读）：
##       `myrmidon +X,+Z,-Y  新θ=+10.41  退化度 0.153  L=647.5 H=138.4 W=414.1  θ=10.41`
##       **θ 与旧值一致**，因为新旧 spec 的差异是「舰艏轴与侧向轴同时反向」= 绕世界 Y 轴 180°，
##       而残差所在的那个平面（模型 X-Y 面）**没变** ⇒ AXIS_DEG 不需要动。
##       （对照：同一次回读里 `kestrel -84.75 / tristan +28.21` 因退化度 ≥0.5 判「PCA不可信」⇒ 按规则置 0；
##        `slasher` 报 CONFLICT 舰艏轴≠长轴 ⇒ 置 0；`catalyst +0.06` 正常。三者与表内现值都吻合。）
##
## ⚠️ 登记本表**必须同时更新 AXIS_DEG**：那条残差是在「舰艏轴×侧向轴」平面上量的，
##    换了 M 就等于换了这个平面，旧数字（那是在模型 XZ 平面上量的）立刻失效。
##    量法见 `tools/probe_ship_yaw_audit.gd::_report_remapped()`（同源，不是另一套）。
## ⚠️⚠️ 2026-09-26 第三轮：`catalyst` / `myrmidon` **两艘的"船背"那一行都指错了轴**
##
## 症状（两艘一样）：**船在世界坐标里是"侧躺"的** —— 俯视看到的是"高的那一面"，
## 正侧看到的是"船顶面"。用户原话：「下面一排从左往右第三幅图，**如果是俯视图，
## 那标注就是正确的**」—— 这正是"躺着"的典型症状（机位语义被滚转 90° 抵消）。
## 注意这**不是** 180° 问题、也**不是** yaw 问题：正面朝向的四个候选全否就是因为这个。
##
## 定案证据（三条独立，互相印证）：
##  ① `sym_test2.py` 全库镜像对称检验：52 艘里 **50 艘**都是「横向=Z / 长=X / 上=Y」，
##     只有 `catalyst`（横向=Y、上=Z）与 `slasher`（横向=X、上=Z）离群。
##  ② `_ship3d/<id>/ship.json` 的 `dims_raw` × 实测 glb 尺寸 ⇒ 反解**导出置换**：
##     44 艘走主流 `ZYX`（glb = 源z, 源y, 源x），由这批已确认正确的船确立
##     **「源 y 的正方向 = 上」**；而 `catalyst` 走 `XZY`、`myrmidon` 走 `YZX`。
##       · catalyst  XZY ⇒ glb (284.1, 88.6, 73.0) ⇒ glb Z = +源y ⇒ **上轴 = glb Z** ✓ 与①吻合
##       · myrmidon  YZX ⇒ glb (601.3, 310.6, 138.4) ⇒ **长X / 上Y / 宽Z = 主流姿态** ✓ 与①吻合
##     （⚠️ `ship.json` 里 `axes_raw` 的 `y_height` / `z_length` 只是**按名字硬贴的标签**，
##       不可信 —— abaddon 标 y_height=385 是高度、myrmidon 标 y_height=601 是长轴。）
##  ③ 用户连续两轮的口述（"躺着的船，正侧看起来像俯视"）。
##
## 修正原则：**只动「船背」「侧向」两行，第一行（= 舰艏轴）一个字不碰**
##   ⇒ 180° 语义与前一轮完全一致，`FLIP` 名单不受影响、`verify_run` 锚点不用改。
##   ⚠️ 但残差平面（= 舰艏轴 × 侧向轴）**两艘都变了**（catalyst: XZ→XY · myrmidon: XY→XZ）
##      ⇒ `AXIS_DEG` 已按 `probe_ship_yaw_audit.gd::_report_remapped()` 重算，见那段注释。
##
## ⚠️⚠️ 2026-09-26 **第七轮：`myrmidon` 的「舰艏」那一行也搬了位置**（前六轮都只动第二三行）
##
## 用户口径（本轮原话）：「**弥尔米顿是垂着飞的，在 EVE 游戏里是竖着飞的**」
##   ⇒ 舰艏轴 **不朝世界 X（水平）**，而是**朝世界 Y（竖直）**。
##   ⇒ 这是**第一行**的改动，180° 与别的船无关（`myrmidon` 已不在 `FLIP` 里，见下）。
##
## 定位过程（三个候选互相排斥，只有第三个同时满足全部）：
##   · 起点：离线 6 机位正交渲染（`C:\godot\_export\_rot8.py`，长轴竖直 × 绕长轴 4 个 roll）
##     与用户 6 张实机图逐列比 ⇒ 只有 **roll 90°/270°** 能让「俯视/仰视」列的翼展变竖向
##     （roll 0/180 时翼展在画面里横摊，与实机不符）⇒ 先把 roll 收窄到两个。
##   · 再用「**模型 −X 端（喷口端）涂红 / +X 端（舰艏）涂绿**」取舍（`_rollc.py`）：
##       roll 90° 的俯视格 = 绿上红下 ✗  ·  roll 270° 的俯视格 = **红上绿下** ✓
##     用户俯视图的标注正是「引擎口在上、舰艏在下」⇒ **roll 270°**。
##
## 反解（`spec_rows` 的语义 = 第 i 个 token 是 M 的第 i 行）：
##   目标姿态 `T = R_y(270°)·R_z(90°)`，而游戏里 `T = R_y(MODEL_YAW_FIX + θ)·M`
##   （`MODEL_YAW_FIX = −90°`，且 `R_y(−90°) ≡ R_y(270°)`）
##   ⇒ `M = R_y(+90°)·R_y(270°)·R_z(90°) = R_z(90°) = [[0,−1,0],[1,0,0],[0,0,1]]`
##   ⇒ 逐行读出 spec = **`"-Y,+X,+Z"`**
##      世界 X ← 模型 −Y · 世界 Y ← 模型 **+X**（舰艏）· 世界 Z ← 模型 +Z
##
## 净效果：模型 +X（舰艏）→ 世界 **+Y** ⇒ 游戏里舰艏朝节点局部 **+Y**
##         （`sync_from_body` 只约束局部 +Z = 速度方向；局部 +Y 经 `R_y` 不变）
##         ⇒ **船在太空里是"立着"飞的**，与 EVE 里一致。
##
## ⚠️ 副作用一：`AXIS_DEG` 的物理含义变了 —— 它加在 `yaw` 上、即绕**世界 Y**；
##   以前长轴是水平的，绕 Y 是 yaw 残差；现在长轴**就是世界 Y** ⇒ 绕 Y = **绕长轴（roll）**。
##   旧的 `+0.02°` 是在旧平面（水平）量的，语义不再对应 ⇒ **置 `0.0`**（量级上本来也≈0）。
## ⚠️ 副作用二：`C:\godot\_export\_ba4.py` 的 `axis_index()` 假设「spec 第一行 = 舰艏轴」，
##   这条假设只在「舰艏朝世界 +X」时成立。本船现在舰艏在 **第二行** ⇒ 用 `_ba4.py`
##   核它时必须先改那个函数，否则会把「模型 −Y」当成舰艏（结论正好错 90°）。
##
## ⚠️⚠️ **第八轮（同日 18:05，用户裁决）**：第七轮的 `+Z` 在俯视/仰视上**上下是反的**。
##   · 用户原话：「下面一排的上下是颠倒的」·「roll90° 俯视图和仰视图是对的」。
##   · ⇒ 把第三行 `+Z` 改成 `−Z`：spec 由 `"-Y,+X,+Z"` 变为 **`"+Y,+X,-Z"`**。
##   · 几何含义：`M = R_y(180°)·R_z(90°)` ⇒ `T = R_y(+90°)·R_z(90°)`，即**绕长轴的 90° 版**
##     （第七轮那版是 270°）。两版只差**绕长轴 180°**，所以只在俯视/仰视里表现为上下翻转。
##   · 舰艏仍是模型 +X、仍朝世界 +Y（「竖着飞」这条没变）；`AXIS_DEG` 仍为 0。
##   ⚠️ 上一轮我写下的判据「正确的一行必须是红在上、绿在下」**是错的** —— 那是把
##     `_rollc.py` 的两端上色读反了方向。真正的判据 = 用户实机俯视图的形态：
##     **上端「窄短」（引擎口）、下端「窄长」（舰艏）**，即俯视图必须"上窄下宽"。
##
## ⚠️⚠️⚠️ **第十二轮（同日 18:59，用户看**游戏实机图**后裁决，本轮定案）**：用户原话
##   「**这是游戏实机图，那它的朝向应该朝向敌人，也就是转 180 度，现在这个朝向是错的**」
##
##   · 背景：第九轮把舰艏定成**朝下**，依据是「用户 6 张图里俯/仰两格不动、后视图翻 180°」。
##     但那是在**离线六视图**上判的 —— 用户看到**游戏真实画面**后立刻发现：舰艏（细长尖段）
##     指着自己这边、引擎段指着敌人，**整艘船是倒着站的**。
##   · **敌我方向 = 工程内事实，不是推测**：`eve_battle_arena.gd` 的
##     `deploy_enemy_z = −45.0`（我方 `deploy_own_z = +45`）⇒ **敌人方向 = 世界 −Z**；
##     相机在我方背后朝 −Z 看 ⇒ **画面向上 = 敌人方向**。
##   · ⇒ 「朝向敌人」在画面上 = **舰艏朝上（世界 +Y）**。第九轮的 `+Y,-X,+Z` 给的是舰艏 →
##     世界 **−Y**（朝下）⇒ 反了，正是用户看到的画面。
##   · 合法的 180° 只有两条（都必须保持长轴竖直、都把舰艏翻到世界 +Y）：
##       ① `R_z(180°)` ⇒ `−Y,+X,+Z` —— 可见的侧面不变（仍看 `+Z` 一侧），但**船背翻到 −X**
##          ⇒ 相机在 +X 侧，于是**看到的是船肚子**
##       ② `R_x(180°)` ⇒ **`+Y,+X,-Z`** —— **船背仍朝 +X（相机侧）**，只把舰艏与第三行翻过来
##   · **定案取 ②**，三条独立理由：
##       ⑴ 船背（模型 +Y，glb 的"上"）**必须仍朝向相机** —— 这是全库所有船的视觉语言
##          （正常船 `模型 +Y → 世界 +Y`，相机在上方 ⇒ 永远看船背）。① 会让这艘船肚皮朝人。
##       ⑵ 实拍取证（`_pose3.py`：原图 / ① / ② 三张实机图的船体特写并排 + 「原图绕屏心转 180°」参照）：
##          ② 与原图是**同一面**（都能看到舷侧那些棱角装甲），只是上下颠倒 + 左右镜像；
##          ① 露出的是**平滑圆钝的另一面**（船腹）。
##       ⑶ 用户说的是「转 180 度」= **画面口径**。船体左右近似镜像对称 ⇒ 保持船背可见时
##          「上下颠倒 + 左右镜像」**合起来就是画面内 180°**，与 ② 等价；而 ① 等于把船
##          **翻成肚皮朝人**，那不是「转 180°」而是「绕长轴再滚 180°」。
##     ⚠️ 若用户仍说「左右反了」，把第三行 `-Z` 改 `+Z`（即 ① 的兄弟版 `+Y,-X,+Z` 里那条
##       保持 `+Y` 的写法）—— 但他要的若是"另一面"，就直接改第三行符号，一行事。
##
## ⚠️⚠️⚠️ **第十三轮（同日 19:30，用户当面纠正 ⇒ 最终定案）**：spec 由 `"+Y,+X,-Z"`
##   （`R_x(180°)`）改为 **`"-Y,+X,+Z"`（`R_z(180°)`）**。
##
## 用户原话：「你改错了 …… 我说的转 180 度，**不是整个船身上下颠倒**，而是**相当于人前后转
##   一样**，朝向改变一下而已 …… 现在你这么上下一颠倒，我们前面做的 6 视图完全不一样了，成白做的了」
##
## · 病根：**「转 180°」有两个截然不同的轴，第十二轮我选错了轴。**
##     · `R_x(180°)` = 绕**水平轴**翻跟头 ⇒ 舰艏 −Y→+Y，**同时把「侧向」那一轴也翻掉**
##       ⇒ 六视图整组换面 ⇒ 用户看到的就是"上下颠倒" ✗
##     · `R_z(180°)` = 绕**竖直轴**原地转身（人转身）⇒ 舰艏同样 −Y→+Y，
##       但「侧向」那一轴**保持 +Z 不动** ⇒ 六视图只在"舰艏上下"这一维变化 ✓
##   ⚠️ 两者都合法、**都满足「舰艏朝世界 +Y（朝敌人）」那条锚点** ⇒ 锚点分不出对错，
##      只有用户看画面能分。**别再拿锚点当"这次一定对"的理由。**
##
## · 三条独立证据都指向 `R_z(180°)`：
##     ⑴ 用户描述的就是 `R_z`：人站着转身 ⇒ **头仍朝上**（长轴不动）、只换"面朝哪边"；
##        而 `R_x` 是翻跟头、人才会头脚颠倒 —— 与他投诉的现象逐字吻合。
##     ⑵ 「6 视图不能变」这条约束**只有 `R_z` 满足**：它不动世界 Z 轴，而俯/仰机位的
##        画面竖直轴正是世界 ∓Z（机位表见第九轮注释）⇒ **俯/仰两格原封不动**；
##        `R_x` 会把世界 Z 也翻掉 ⇒ 俯/仰跟着换面 ⇒ 六视图"完全不一样"。
##     ⑶ 与第九轮（用户认可的六视图基准 `"+Y,-X,+Z"`）逐项比：`R_z` 版只差**第一行**
##        （舰艏轴）符号；`R_x` 版还要再翻第三行。⇒ **改动面最小的那个**才是用户要的。
##
## · 反解：`M_new = R_z(180°)·M_第九轮` ⇒ 逐行读出 **`"-Y,+X,+Z"`**。
##   等价校验（按用户字面口径）：`M_new = R_y(180°)·M_第十二轮` —— 从当前状态**绕竖直轴**
##   转 180°，正是"人前后转"。
##
## · 净效果（探针 `probe_ship_in_scene` 实读，2026-09-26 19:33）：
##     模型 +X（舰艏）→ 世界 **(0,+1,0) = +Y**  ⇒ 朝上 = 朝敌人（与第十二轮一致，没退步）
##     模型 +Y（船背）→ 世界 **−X**          ⇒ 背离相机 ⇒ 玩家看到船的**另一面**（这就是"转身"）
##     模型 +Z（侧向）→ 世界 **+Z**          ⇒ **没动** —— 正是六视图保住的那一维
##
## · ⚠️ 与第十二轮注释里「① 会露出船肚子」那条结论的关系：那条是**几何事实、没错**，
##   但它把"换面"记成了缺点 —— 而"人转身"本来就必然换面。**用户要的就是这个**。
##   ⇒ 后门仍然有效：若用户说"我要看的是正面不是背面"，改第三行符号（`+Z`↔`-Z`）即可，一行事。
##
## ⚠️ **第九轮（同日 18:12）已被本轮推翻**，原文保留备查：用户原话
##   「**正视图、左视图、右视图、后视图的渲染图逆时针旋转 180° 就是正确的了**」
##   （即：四侧视格上下颠倒，俯/仰两格不动）。
##
##   几何上这是**唯一解**，可以严格证明 —— 六个机位的「画面竖直轴」（`pose_sheet.render`
##   的 `Yc`，见 `_r180.py` 的标定）：
##       正/左/右/后（相机在 ∓Z / ∓X）⇒ 画面竖直 = 世界 **+Y**
##       俯/仰（相机在 ∓Y）        ⇒ 画面竖直 = 世界 **∓Z**
##   ⇒ 「四侧视翻 180°」要求翻世界 Y；「俯/仰不动」要求**不翻**世界 Z；
##     而绕主轴的 180° 里只有 `R_x`(翻Y,Z) / `R_y`(翻X,Z) / `R_z`(翻X,Y) 三个
##     ⇒ **同时满足两条的只有 `R_z(180°)`**。
##
##   量化取证（`_pick.py`：用户实机图可靠掩膜 × 四候选，面内转角固定 0° 不算自由度）：
##       spec        正视图  俯视图  仰视图  后视图   平均
##       现行 +Y,+X,-Z  0.30   **0.81**  **0.53**   0.29   0.421
##       绕X  -Y,-X,-Z  0.26    0.53✗    0.46✗    0.67   0.403
##       绕Y  -Y,+X,+Z  0.30    0.53✗    0.46✗    0.29   0.361
##      ★绕Z  +Y,-X,+Z  0.26   **0.81**✓ **0.53**✓ **0.67**✓ **0.460**
##     （俯/仰两格的用户掩膜干净可信；正/左/右三格的掩膜被截断/含 UI 块，分数只作参考。
##       `_um.py` 出掩膜、`_um_grid.png` 可目视复核阈值。）
##
##   · 物理旁证：用户 `正视图`/`后视图` 里**引擎（青光喷口簇）都在画面上端**
##     ⇒ 舰艏必须朝世界 **−Y**（下）。改前舰艏朝 +Y ⇒ 引擎在下 = 与实机相反 ✓ 与用户判断一致。
##   · 反解：`T_new = R_z(180°)·T_old`，而 `R_y(90°)·R_z(180°)·R_y(−90°) = R_x(180°)`
##     ⇒ `M_new = R_x(180°)·M_old`（`M_old = "+Y,+X,-Z"`）⇒ 逐行读出 **`"+Y,-X,+Z"`**。
##   · ⚠️ 这条**只翻世界 Y 与 X**（世界 Z 不动）⇒ 俯/仰机位的画面竖直轴（∓Z）天然不变，
##     正是用户要的「俯/仰不动」。**别再回到绕 X 那一版** —— 它会把俯/仰也翻掉。
##   · ⚠️ 关于左/右视图：`R_z(180°)` 在左/右机位给出的是**纯上下翻转**（不是 180° 全转）。
##     严守 180° 全转得选绕 X，但那会翻掉俯/仰 —— 两者不可兼得（见上表）。
##     用户的左/右实机图本身是**斜构图**（相机有 roll），故其"180°"不在本工程的轴对齐系里。
##
## ⚠️⚠️⚠️ **第十四轮（同日 19:44，用户当面纠正 ⇒ 现行定案）**：基准换成**用户认可的参考姿态**，
##   180° 改走**机身纵轴（模型 X = 舰艏轴）** ⇒ spec `"+Y,-X,+Z"` → **`"-Y,-X,-Z"`**。
##
## 用户原话：「你就不能以这个图的第一张图做参考？**硬是要以已经上下颠倒的做参考**？给我以
##   这个图中的船做参考，**再像人前后转一样翻转**」（第一张图 = `_inscene_myrmidon.png`
##   = **第九轮那版**的实机画面 = 用户自己游戏里正在看的姿态）。
##
## · 病根（前两轮同一个错）：**「转 180°」有三个轴，我两次都挑了垂直于舰艏的那个** ⇒
##   两轮都把**舰艏翻了个头**，那才是用户看到的"上下颠倒"。规律是纯代数的 ——
##   180° 旋转 = **翻转「除旋转轴以外」那两个 token 的符号**：
##       · 翻 {X,Z} token ⇒ 180° 绕**模型 Y（船背轴）** ⇒ 第十二轮 `"+Y,+X,-Z"` ✗ 舰艏 −Y→+Y
##       · 翻 {X,Y} token ⇒ 180° 绕**模型 Z（侧向轴）** ⇒ 第十三轮 `"-Y,+X,+Z"` ✗ 舰艏 −Y→+Y
##       · 翻 {Y,Z} token ⇒ 180° 绕**模型 X（舰艏轴）** ⇒ **本轮 `"-Y,-X,-Z"`** ✓ 舰艏不动
##   用户那三句（「不是整个船身上下颠倒」·「相当于人前后转」·「朝向改变一下而已」）
##   **只对第三种成立** —— 人转身时头仍朝上，换掉的只是"面朝哪边"。
##
## · 基准 = 第九轮 `"+Y,-X,+Z"`（**不是**第十二轮）：依据是用户已两次背书的实拍图
##     `_ba9_myrmidon.png`「下面一排也是对的」＋ `_ends9_myrmidon.png`「这个图是对的」，
##   且第十一轮已按该图写入 Godot ⇒ 用户 18:55 那张实机图就是该姿态。
##   ⚠️ 第十三轮是**从第十二轮推的**（`M = R_y(180°)·M_十二轮`）—— 基准就错，结果自然错。
##
## · 净效果（探针 `probe_ship_in_scene` 实读，19:5x）：
##     模型 +X（舰艏）→ 世界 **−Y**  ⇒ **与参考图同一端朝下，一个字没动**（"不翻跟头"）
##     模型 +Y（船背）→ 世界 **−X**  ⇒ 由 +X 翻过来 ⇒ 玩家看到的是**另一侧船身**
##     模型 +Z（侧向）→ 世界 **−Z**  ⇒ 同样翻过来 ⇒ 两轴一起翻才是真·自转
##
## · ⚠️ **不能只翻第三行**：只翻第三行 = `det = −1` 的**反射**（镜像船），`validate()` 第 ④ 条
##   会当场拦下 —— 而"看另一面"**必须**是真旋转 ⇒ 「船背」那行得跟着一起翻。
## · ⚠️ 这 180° 等价于 `yaw += 180°`（本船长轴 = 世界 Y ⇒ yaw 就是**绕长轴滚转**），
##   但 `validate()` 限制 `|AXIS_DEG| < 90°` ⇒ 只能写在 `AXIS_REMAP` 里
##   （与「一艘船的 180° 只许在一处表达」一致）。
## · ⚠️ **代价要记牢**：舰艏方向**没有**变 ⇒ 仍朝世界 −Y（画面上 = 背离敌人）。
##   用户本轮口径明确：「人前后转」优先 —— 对竖直姿态的船，"朝敌人"与"不翻跟头"
##   **不可兼得**（要换端就必须翻跟头）；前两轮都已按"朝敌人"试过并被否。
##
## ══════════════════════════════════════════════════════════════════
## ★★ 47 轮（2026-09-27）：**整张表按新空间重算，上面那段"竖直轴/不翻跟头"的
##    历史口径连同它推出的 52 条取值**全部作废**（留档在 `/tmp/yaw_before_47.gd`）
## ══════════════════════════════════════════════════════════════════
##
## ── 为什么必须整张重算（用户 47 轮原话）──────────────────────────
##   「我实机确认了，舰艏没有指向敌人，而且**每艘船的舰艏指向都很不一样，很乱**。
##     前面我用工具修复过，怎么回事儿」
##   ⇒ 关键词是「**逐艘各异**」：统一的偏角早就被历轮探针排除了，只有
##     **每艘差得不一样**才会呈现出这种"乱"。
##
## ── 真因：`AXIS_REMAP` 写错了**空间**（红线 48）──────────────────
##   官方 glb 的结构**从来不是**「根节点 = 几何体」：
##       <id>.glb → 根 Node3D(basis = 单位阵)      ← 我们一直当它 `model` 写 M/yaw
##                    └─ MeshInstance3D(**自带旋转**) ← 几何体真身，**逐艘不同**
##   实测分布（`tools/probe_innerrot47.tscn` 全库普查）：
##       `R_y(180°)` 30 艘 · `R_x(90°)` catalyst/kestrel/slasher 3 艘
##       · 120° 斜轴 myrmidon/tristan 2 艘 …
##   而 `SHIP_AXES`（`bow:+Z up:+Y`）描述的是**网格空间**的轴 ——
##   两者差着那一层 ⇒ 每艘偏的量都不同 ⇒ **正是用户看到的"逐艘各异的乱"**。
##
## ── 修法（两处，缺一不可）────────────────────────────────────────
##   ① 代码侧：`eve_ship_visual._bake_mesh_rotation()` 把内层网格旋转**提升到根**，
##      于是算式收敛成唯一真相源：
##          `zero_pose_basis(id) = R_y(extra_yaw) · M · mesh_rot`
##      （`MODEL_YAW_FIX(−90°)` 已删除并吸收进 M 表 —— 红线 27：同一自由度只许一处）
##   ② 数据侧：**本表 52 条全部按新空间重算**（就是本轮所做的事）
##
## ── 重算口径（不是手推，是**穷举**）──────────────────────────────
##   工具：`tools/probe_remap47.tscn`（源 `tools/probe_remap47.gd`）
##   对每艘船穷举全部 48 个合法 spec，判据**三条同时成立**：
##       `M·mesh_rot·bow = −Z`（朝敌，红线 42：敌在世界 −Z）
##       `M·mesh_rot·up  = +Y`（船背朝天）
##       `M·mesh_rot·side = +X`（★这条必须有，否则左右镜像也是解 ⇒ 解不唯一）
##   解析走**生产函数** `parse_axis_remap()`（红线 40 同源，不自己复刻一份）。
##   结果：**52 艘全部唯一命中、零失败、零歧义**。
##   产出留档：`user://bow_calib/remap47.txt`；落盘脚本 `C:\godot\_export\_apply_remap47.py`
##
## ── 为什么旧表"看起来也对"却全错（红线 40 第 7 次现形）──────────
##   旧探针算的是 `v.quaternion · (model.basis · bow_local)` —— 这两个值
##   **正是 `_bow_align` 的构造输入** ⇒ 必然得 1.000（拿被测方验被测方）。
##   换成引擎自己连乘的 `mesh.global_transform.basis` 后，**未修主代码**时
##   读数掉到 **0.000**（舰艏与敌向垂直）—— 与用户 45 轮描述逐字吻合。
##
## ── 取值规律（供后人 sanity check）──────────────────────────────
##   · 主流 46 艘 = **`"+Z,-Y,+X"`**（模型 +Z→前方 / +Y→上方 / +X→侧向）
##   · 滚转船 `algos` `"+Z,+X,+Y"` · `catalyst` `"+Z,+X,+Y"`
##   · 长轴非 X 的 4 艘：`kestrel`/`slasher` `"-X,+Z,+Y"` ·
##     `myrmidon` `"+Z,+Y,-X"` · `tristan` `"-X,+Y,-Z"` · `inquisitor` `"-Z,-Y,-X"`
##   ⚠️ 与 `SHIP_AXES` 是**两张表**：那张说"模型里哪根轴是舰艏"，这张说"搬到世界哪边"。
##      改这张必须重跑 `probe_remap47`，**不许手推** —— 非 diag 型 spec 的行列语义
##      差一个转置，手推错一次就是整艘倒飞且**不报错**（23 轮 kestrel 实测翻过车）。
const AXIS_REMAP := {
	&"abaddon": "+Z,+Y,-X",
	&"algos": "-Z,+Y,+X",
	&"apocalypse": "+Z,+Y,-X",
	&"armageddon": "-Z,+Y,+X",
	&"augoror": "-Z,+Y,+X",
	&"bantam": "+Z,+Y,-X",
	&"brutix": "+Z,+Y,-X",
	&"burst": "-Z,+Y,+X",
	&"caracal": "+Z,+Y,-X",
	&"catalyst": "-X,-Z,-Y",
	&"coercer": "+Z,+Y,-X",
	&"condor": "+Z,+Y,-X",
	&"corax": "-Z,+Y,+X",
	&"cormorant": "+Z,+Y,-X",
	&"cyclone": "-Z,+Y,+X",
	&"dominix": "-Z,+Y,+X",
	&"dragoon": "+Z,+Y,-X",
	&"drake": "+Z,+Y,-X",
	&"executioner": "+Z,+Y,-X",
	&"exequror": "+Z,+Y,-X",
	&"ferox": "-Z,+Y,+X",
	&"harbinger": "-Z,+Y,+X",
	&"hurricane": "+Z,+Y,-X",
	&"hyperion": "-Z,+Y,+X",
	&"incursus": "+Z,+Y,-X",
	&"inquisitor": "-Z,+Y,+X",
	&"kestrel": "-X,-Z,-Y",
	&"maelstrom": "+Z,+Y,-X",
	&"maller": "+Z,+Y,-X",
	&"megathron": "-Z,+Y,+X",
	&"moa": "+Z,+Y,-X",
	&"myrmidon": "+Z,-X,-Y",
	&"navitas": "-Z,+Y,+X",
	&"omen": "+Z,+Y,-X",
	&"osprey": "-Z,+Y,+X",
	&"prophecy": "+Z,+Y,-X",
	&"punisher": "+Z,+Y,-X",
	&"raven": "+Z,+Y,-X",
	&"rifter": "+Z,+Y,-X",
	&"rokh": "+Z,+Y,-X",
	&"rupture": "+Z,+Y,-X",
	&"scorpion": "-Z,+Y,+X",
	&"scythe": "-Z,+Y,+X",
	&"slasher": "-X,-Z,-Y",
	&"stabber": "+Z,+Y,-X",
	&"talwar": "-Z,+Y,+X",
	&"tempest": "-Z,+Y,+X",
	&"thorax": "+Z,+Y,-X",
	&"thrasher": "+Z,+Y,-X",
	&"tristan": "+Z,-X,-Y",
	&"typhoon": "+Z,+Y,-X",
	&"vexor": "-Z,+Y,+X",
}


## ── 语义轴（**模型空间**）—— 新船标定的唯一入口，全库强制登记 ─────────
##
## ⚠️⚠️ `bow` / `up` 是**唯一需要人工标定的两个"有向"量**，其余全部派生。
##    spec 写法：`"bow:+X up:+Y"`（顺序无关，值只能是 `±X / ±Y / ±Z`）
##      · `bow` = 舰艏方向（**引擎喷口的反方向**：喷口在船尾，舰艏在另一端）
##      · `up`  = 船背方向（朝天的那一面）
##      · 侧向 `side = bow × up`，由代码派生，不许人工填
##
## ⚠️ **必须全库 52 艘逐艘登记**（`validate()` 第 ⑥ 条拦漏填）。
##    这就是「以后加稀奇古怪的船怎么办」的答案：漏填 ⇒ `verify_run` 直接 FAIL，
##    不可能再出现"这艘船没标过，于是静默落回某个默认值"的情况
##    （22 轮之前 `BOW_AXIS` 就是稀疏表 + 默认 +X ⇒ 51 艘从未被真正标定过）。
##
## ⚠️⚠️ 这张表是 2026-09-26 第二十二轮**新加**的，起因是一场持续 14 轮的混乱：
##  `AXIS_REMAP` 的 spec 字符串**从来没有一个统一的语义** ——
##    · ✅ **23 轮实测定案**：`axis_remap()` 的实现是**行语义** ——
##        **第 i 个 token = Basis 的第 i 行**（M·v 的第 i 分量 = token_i · v）。
##        对 diag 型 spec（30+ 艘主流船）"行"与"列"两套读法**恰好等价**，
##        所以 22 轮前问题一直没暴露；**非 diag 型两套差一个转置 = 完全相反**。
##        （22 轮注释曾写"列语义"，是错的 —— kestrel 实测翻车后才定案，别改回去。）
##    · 而文件里多处注释、`FLIP` 判据用的 A、以及 `validate()` 里的 `bow` 变量
##      用的是相反的一套：**第 i 个 token = 世界 i 轴 ← 模型哪个轴**
##  对 diag 型 spec（`-X,+Y,-Z` 这种，30+ 艘主流船）两套读法**恰好等价**，
##  所以问题一直没暴露；对非 diag 型（myrmidon / tristan / catalyst / algos …）
##  两套读法**相差一个转置 = 完全相反的姿态** ⇒ 那批船怎么改都改不对。
##
##  ⇒ 与其继续猜 spec 的语义，不如**把真正要人工定的那一个量单独拎出来**：
##      「这艘船的模型空间里，**舰艏朝哪根轴**」。
##  剩下的（上轴、侧向）由 spec 唯一确定，不需要人再判一次。
##
## 口径：
##   · **默认值 `+X`** —— glb 由 Blender 的 `orient_ship` 把**长轴对齐到 +X**，
##     对绝大多数船"长轴 = 舰艏轴"成立 ⇒ 不登记的船自动落回旧行为。
##   · 登记值必须是 6 个轴向之一：`±X / ±Y / ±Z`。
##   · ⚠️ **一根模型轴上只能有一个语义**：舰艏轴与船背轴**不得共线**。
##     `validate()` 第 ⑤ 条会拦 —— myrmidon / tristan 的老 spec 正是共线的，
##     那意味着"模型 X 既是舰艏方向又是船背方向"，几何上不可能，
##     表现出来的症状是**舰艏竖直朝下、单 yaw 永远转不动**（第 21 轮的死锁）。
##
## 判据来源（与 FLIP 同源，都是 `_e` 自发光喷口法线）：
##   喷口法线沿「舰艏−舰尾」轴朝外 ⇒ 自发光面聚在**船尾**那一端。
##   · `tristan`：65 个喷口面、noz2 = −0.96 ⇒ 喷口在 −Y ⇒ **舰艏 = +Y** ✓
##   · `kestrel`：75 个喷口面、noz2 = −1.00 ⇒ 喷口在 −Y ⇒ **舰艏 = +Y**
##     ✅ 23 轮收案：用户判 6 宫格标定图确认舰艏在 +Y（红球侧），已登记 `SHIP_AXES`
##     并重算 spec 为 `-Y,+Z,-X`（船背 = +Z，与官方渲染俯视特征吻合）。
##     ⚠️ 2023 旧标定台点的"船背 = −Z"**作废** —— 那套机位正是"箭头画反"同源，
##     且当时的注释自己就存疑（"导弹管朝上 ⇒ 背应在 +Z"）。实机若肚皮朝天再翻回。
##   · `myrmidon`：`_e` 判据说舰艏 = **+X**（第三轮注释：喷口在 −X）
##     ⇒ 用默认值 +X，不动。
##
## ═══ ★★★ 50 轮（2026-09-27）：**一次失败的反解，与一条被证伪的判据** ═══
##
## ── 用户实机诉求 ────────────────────────────────────────────────
##    「实机的问题是，舰船的舰艏不朝向敌人……就是这几艘特殊船」
##    正确；且裁定「**以我工具里定的为准**」·「**得看外观，不能机械推**」·
##    「**先落盘，实机再看**」。
##
## ── ★ 本轮做错的事（留档，别再犯）──────────────────────────────
##   我用「`mesh.get_aabb()` 最长边 = 舰艏轴」当判据普查 52 艘，
##   发现 5 艘（algos/catalyst/kestrel/slasher/tristan）与表差 90°，
##   据此**反解并落盘**了新的 spec（`-Z,-Y,-X` 等）—— **然后 `verify_run` 报 8 项失败**。
##
##   ⚠️ **根因：判据本身错** —— `AABB` 最长边**只在"细长机身"的船上等于舰艏轴**。
##   实测这 5 艘的 AABB 全是**扁平宽板**：
##       kestrel  (99.7, 78.6, 25.0)   ← 长/宽 = 1.27
##       slasher  (172.3, 81.6, 35.9)  ← 长/宽 = 2.11
##       catalyst (284.1, 88.6, 73.0)  ← 长/宽 = 3.21
##   对这类船，"最长边"是**翼展 / 板长**，**根本不是舰艏轴**
##   （kestrel 是茶隼级 —— 四翼展开的护卫舰，翼展本来就接近机身长）。
##   ⇒ 用户 23 轮对 kestrel 的裁定（`bow:+Y`）**在几何上完全可能成立**。
##   ⇒ **已把这次改的 10 处全部回滚**（`AXIS_REMAP` × 5 + `SHIP_AXES` × 5）。
##
## ── 教训（红线 50a/50c 的修正版）──────────────────────────────
##   · **「几何代用判据」必须先证明它在目标族群上成立，再拿来判对错。**
##     `AABB` 最长边对"细长机身"成立、对"扁平宽板"不成立 ——
##     用它判 52 艘 = 拿一个**只在部分船上成立**的判据去否定用户的手工标定。
##   · **判据被证伪时，要回滚它带来的改动**，不能只关掉判据（否则表已经被污染了）。
##   · 自动判「舰艏轴」的可靠判据**尚未找到**；已知候选：
##     `_e` 自发光贴图喷口分布（24 轮用过，判据 = 喷口聚在船尾那一端）。
##     ⇒ 在找到之前，**`SHIP_AXES` 只由用户 6 宫格 / 实机裁定**（红线 33）。
##
## ── 本轮**确实拿到**的产出 ────────────────────────────────────
##   · `tools/probe_geom50` —— AABB 几何口径（**不碰任何表**，说真话的那个）
##   · `tools/probe_tabgeom50` —— 表↔几何逐艘对账
##   · `tools/probe_shot50` —— 实机三视图出图（供用户判端）
##   · `tools/probe_solve50` —— **用生产算式**枚举反解（不手推）
##   · 红线 50a：**校验与实现共用同一张表时，表错 ⇒ 全绿 + 实机全乱**
##     （「机器验过 ≠ 实机对」第 8 例，污染在**输入**不在**算式**）
const SHIP_AXES := {
	&"abaddon": "bow:-Z up:-Y",
	&"algos": "bow:-Z up:-Y",
	&"apocalypse": "bow:-Z up:-Y",
	&"armageddon": "bow:-Z up:-Y",
	&"augoror": "bow:-Z up:-Y",
	&"bantam": "bow:-Z up:-Y",
	&"brutix": "bow:-Z up:-Y",
	&"burst": "bow:-Z up:-Y",
	&"caracal": "bow:-Z up:-Y",
	&"catalyst": "bow:-Z up:-Y",
	&"coercer": "bow:-Z up:-Y",
	&"condor": "bow:-Z up:-Y",
	&"corax": "bow:-Z up:-Y",
	&"cormorant": "bow:-Z up:-Y",
	&"cyclone": "bow:-Z up:-Y",
	&"dominix": "bow:-Z up:-Y",
	&"dragoon": "bow:-Z up:-Y",
	&"drake": "bow:-Z up:-Y",
	&"executioner": "bow:-Z up:-Y",
	&"exequror": "bow:-Z up:-Y",
	&"ferox": "bow:-Z up:-Y",
	&"harbinger": "bow:-Z up:-Y",
	&"hurricane": "bow:-Z up:-Y",
	&"hyperion": "bow:-Z up:-Y",
	&"incursus": "bow:-Z up:-Y",
	&"inquisitor": "bow:-Z up:-Y",
	&"kestrel": "bow:-Z up:-Y",
	&"maelstrom": "bow:-Z up:-Y",
	&"maller": "bow:-Z up:-Y",
	&"megathron": "bow:-Z up:-Y",
	&"moa": "bow:-Z up:-Y",
	&"myrmidon": "bow:-Z up:-Y",
	&"navitas": "bow:-Z up:-Y",
	&"omen": "bow:-Z up:-Y",
	&"osprey": "bow:-Z up:-Y",
	&"prophecy": "bow:-Z up:-Y",
	&"punisher": "bow:-Z up:-Y",
	&"raven": "bow:-Z up:-Y",
	&"rifter": "bow:-Z up:-Y",
	&"rokh": "bow:-Z up:-Y",
	&"rupture": "bow:-Z up:-Y",
	&"scorpion": "bow:-Z up:-Y",
	&"scythe": "bow:-Z up:-Y",
	&"slasher": "bow:-Z up:-Y",
	&"stabber": "bow:-Z up:-Y",
	&"talwar": "bow:-Z up:-Y",
	&"tempest": "bow:-Z up:-Y",
	&"thorax": "bow:-Z up:-Y",
	&"thrasher": "bow:-Z up:-Y",
	&"tristan": "bow:-Z up:-Y",
	&"typhoon": "bow:-Z up:-Y",
	&"vexor": "bow:-Z up:-Y",
}


## 语义轴**待人工复核**的船 —— 只给报告 / 工具看，**不参与计算、不报错**。
##
## 登记在这里 = 「这张表的取值有疑问，实机若发现它侧飞 / 倒飞，先怀疑这几艘」。
## 复核方式：`tools/probe_bow_calib.tscn --ship=<id>` 渲 6 宫格标定图，人工点选后改表。
const AXES_REVIEW: PackedStringArray = []   # 23 轮：kestrel 已由用户判图收案（bow:+Y up:+Z）

## 语义轴解析缓存（id → `{bow, up}`）。标定表是 const ⇒ 缓存安全。
static var _axes_cache: Dictionary = {}

## ★ 47 轮：`mesh_rot` 的**注入点**（Callable，缺省 = 恒返回单位阵）。
##
## 为什么需要它：`mesh_rot`（glb 内层网格自带旋转，逐艘不同）住在**视觉层**
## （`eve_ship_visual.mesh_rot_of()`），而本文件是纯静态数据表、不许反向依赖节点类。
## 但 ⑧⑨ 两条校验**必须**知道它（否则算的是「根节点空间」而 `SHIP_AXES` 说的是
## 「网格空间」，落差 = 全库 52 艘假失败）。
##   ⇒ 由入口（`eve_ship_visual._ready` / 探针 / `verify_run`）注入一次，
##     与 `SHIP_AXES` 同级地视为"船的几何事实"。
## ⚠️ 未注入时退化为单位阵 —— 那会让 ⑧⑨ 退回旧口径（**会报假失败，不会漏报**），
##    所以入口必须注入；`verify_run` 有一条锚点专门拦它。
static var _mesh_rot_cb: Callable = Callable()

## 注入 `mesh_rot` 提供者（`func(id: StringName) -> Basis`）。
static func set_mesh_rot_provider(cb: Callable) -> void:
	_mesh_rot_cb = cb


## 取某艘船的 `mesh_rot` —— 未注入时返回单位阵（并把这件事说清楚，不静默）。
static func mesh_rot_for(ship_id: StringName) -> Basis:
	if not _mesh_rot_cb.is_valid():
		return Basis.IDENTITY
	return _mesh_rot_cb.call(ship_id) as Basis


## ── 需额外转 180° 的船（模型舰艏在主轴 −X 端）──────────────────
##
## ⚠️⚠️ 2026-09-26 **整份名单已重建** —— 上一版（24 条）是错的。
##
## ── 上一版怎么错的（根因已由用户确认，闭案）────────────────────────
##  用户 2026-09-23 是按 `yaw_sheet.png`（52 艘总览图）**逐格判**的，
##  判据 = 图上画的「前方 →」箭头 + 「船头朝右的算对」。
##  而那支箭头**画反了**：它要表达的是「世界 +Z 投影在屏幕右侧」，
##  实测 +Z 投在**左侧**（`tools/probe_cam_axis.tscn`：+Z 端红球屏幕 x̄ = 30.7 / 画布 420）。
##  ⇒ 用户看到「船头朝右」的其实是船头朝左 ⇒ 名单落成了**真值的补集**。
##
## ── 本版依据：`_e` 自发光贴图（**物理判据**，与那一套协议无关）──────
##  源资产 `C:\godot\_export\_ship3d\<id>\textures\*_e.png` 里，
##  **发动机喷口是最强、最集中的一组自发光面，且喷口法线沿「舰艏−舰尾」轴朝外**
##  （舷窗法线垂直于该轴）⇒ 只在两端找「法线平行于舰艏轴」的自发光面，
##  它们聚在哪一端，哪一端就是**船尾**。
##
##  口径：`noz2` = 只取 `|法线·A| > 0.6` 的面，按面积加权求法线有向和
##        （`A` = `AXIS_REMAP` 第一行；未重映射船 `A = +X`）。
##        `noz2 > +0.5` ⇒ 喷口朝 +A ⇒ **舰艏在 −A ⇒ 要翻**。
##        辅判据 `ratio1` = 两端各 20% 长度带内自发光**面积**之比。
##  52 艘判完：判得动 44 · 与旧表不一致 **36**。
##  工具：`C:\godot\_export\pose_sheet.py`（全库）· `multi_e_test.py`（多套 `_e` 的 5 艘逐张试）
##        · `proof_pair.py`（「现在 vs 修正后」同机位并排实拍）。
##  证据全文：`F:\evezzq\接手手册-2026-09-24\09_朝向问题盘点-2026-09-26.md`。
##
## ⚠️ 别再走「端部宽度分布」猜哪端是舰艏：那条路早已实测不可用。
## ⚠️ 更别改成「整组翻转」：见下面 GLOBAL_180 处的说明。
##
## ── 旧名单（2026-09-23 版，**已作废，留档备查**）────────────────────
##   abaddon apocalypse bantam brutix caracal coercer dragoon drake executioner
##   exequror hurricane incursus maelstrom moa omen prophecy punisher rifter
##   rokh rupture stabber thorax thrasher typhoon
##   ⇒ 其中 **21 条**（除 bantam / omen / thorax）被判「舰艏本就在 +X，不需要翻」。
##
## ⚠️ 2026-09-23：`arbitrator`（主宰级）已被用户换掉 —— 原话「我要留的是暴君，
##    不是主宰」，改成 `maller`（暴君级 / typeID 624，资产为本次新造）。
##    ⇒ arbitrator 已从本名单**删除**（它已不在 52 艘名册里，留着就是个哑 id）。
##    Maller **不进 FLIP**（已复核：`_e` 判据说它舰艏在 +X ✓）；
##    它的主轴残差 θ = −0.45° 只在 AXIS_DEG 里。
const FLIP: PackedStringArray = []

## ── 已从 FLIP 中**移除**的船（2026-09-26 用户人眼复核）──────────────
##   ✅ 43 轮实测确认：这 5 艘**确实已从 `FLIP` 数组移除**（数组 17 条，不含它们）。
##      本段是**文档记录**，不参与运行；43 轮一度把它误读成数组实体（见上方 43 轮说明）。
##   · `omen`（启示级）：原在本名单「无判据、按原样保留」组；用户判读「弄反了」
##     ⇒ 取消翻转。判据同向支持（noz2 = −0.86）。
##   · `thorax`（托勒克斯级）：同上组；用户判读「弄反了」⇒ 取消翻转。
##     ⚠️ 判据**反对**（noz2 = +1.00 / n = 26，判据说它现在是正的）；
##     按用户落盘。top-view 实拍里舰艏（细长锥形端）确实指向 **−Z**（倒飞），
##     与用户一致 ⇒ 判据在「多套 `_e`(6) 择优」这条路上会误报。
##   · `osprey`（鱼鹰级）：用户判读「弄反了」⇒ 取消翻转。⚠️ 判据同样**反对**
##     （noz2 = +0.85 / n = 50，判据说它现在是正的）。按用户落盘。
##   · `catalyst`（促进级）：**第三轮移除**（我第一轮误加的回退）。它走 `AXIS_REMAP`，
##     那 180° 已经在 M 的第一行里表达过了；再叠一个 FLIP 会**抵消**成倒飞。
##   · `myrmidon`（弥尔米顿 / 磨难级）：**第五轮移除**（用户 6 张 EVE 实机权威图裁决）。
##     与 `catalyst` 是**同一类病**：它也走 `AXIS_REMAP`，舰艏本就在模型 +X，
##     名单里那 180° 是多余的 ⇒ 净效果倒飞。详细证据见上方改 `FLIP` 处的注释块。
##   ⇒ 前三条是**判据与验收人唯一分歧的地方**，都记在这里备查。
##
## ★ 43 轮现行事实（对全库 52 艘逐艘手算，算式 = `R_y(−90°+θ+FLIP)·M·bow`）：
##   `FLIP` 里**没有任何一艘**同时让 `M` 表达同一个 180° ⇒ 红线 27 已满足。
##   但**有 5 艘世界朝向 = +Z（背敌）**，它们是同一批（本段所列）：
##     catalyst / myrmidon / omen / osprey / thorax
##   ⇒ 病根**不是**"两个 180° 打架"，而是**它们各自缺一次 180°**：
##     把这 5 艘的 `M` **三行翻号**（`M_new = R_y(180°)·M_old`，det 仍 +1，合法旋转）
##     即从 +Z 翻到 −Z。**该修复待用户实机确认后再落盘**（43 轮仅记录，未改）。
##   ⚠️ 这 5 艘正是 2026-09-26「判据 vs 用户」分歧最大的那批 ⇒ **别再用判据推，
##     用工具按用户目测重标**。
##   ⇒ ⚠️ 43 轮修正错误的旧表述：原文写「全库只有 catalyst 与 myrmidon 同时牵涉
##      两个 180° 自由度」—— 实测**一艘都没有**（`M` 与 `FLIP` 无重叠）。
const FLIP_REMOVED_20260926: PackedStringArray = ["omen", "thorax", "osprey", "catalyst", "myrmidon"]

## ── 待定：**已清空**（2026-09-23）────────────────────────────────
##
## 原 7 艘（catalyst / condor / kestrel / myrmidon / raven / slasher / tristan）
## 已全部由用户在交互式标定台 `ship_orient_fix.html` 里点【舰艏】+【船背】定出，
## 结论落进 `AXIS_REMAP`（轴重映射）+ `AXIS_DEG`（残差，重算过）。
##
## 渲染取证（`glb_tex.py` 六视角 + 官方立绘对照，2026-09-23）：
##   · catalyst：涡轮发动机盘在 +X 端 ⇒ 舰艏 = −X ✓
##   · tristan：三个发动机喷口朝 −Y ⇒ 舰艏 = +Y ✓；背甲朝 −X ✓
##   · kestrel：叉形舰艏两根獠牙的平分线 = +Y ✓；
##     ✅ 23 轮收案：船背实为 +Z（旧标定台点的 −Z 错了，导弹管朝上 ⇒ 背在 +Z）；
##     spec 已重算 `-Y,+Z,-X`，且**实机终审通过**（肚皮未朝天）。
##   · slasher：翼展(172) > 机身(81)，与 kestrel 同构 ⇒
##     ✅ 24 轮同款翻案：舰艏 = +Y（用户 2023 旧裁决，手册 02_未决 §65）、
##     船背 = +Z（官方渲染四翼俯视平铺）；spec `-Y,+Z,-X` 与 kestrel 同款。
##
## ⚠️ 名单保留为空是有意的：`is_pending()` 仍可被 UI 查询；
##    以后再出现判不出的船，往这里加即可（并同步写进 AXIS_REMAP）。
const PENDING: PackedStringArray = []


## 本表给出的**额外**偏航（弧度）—— 不含 MODEL_YAW_FIX。
##
## 调用方：`eve_ship_visual._build_hull_model()`
##     model.rotate_y(MODEL_YAW_FIX + EveShipYawTable.extra_yaw(ship.ship_key))
##
## 未登记的 id 返回 0.0（= 维持原来的全船统一 −90°），
## 这样加一艘新船不会因为"忘了登记"而朝错方向 —— 它只是回到旧行为。
##
## ── ⚠️ GLOBAL_180：整组 180° 的「总闸」 —— **2026-09-26 闭案，永远置 false** ──
## 2026-09-26 用户确认：当年判 `yaw_sheet.png` 用的基准**就是那支「前方 →」箭头**
## （「船头朝右的算对」），而它**画反了** ⇒ 病根定位完毕（详见上面 FLIP 处）。
##
## 但**不能**因此把它置 `true`。置 true = 给全部 52 艘各加 180°
## （等价于把 FLIP 名单换成它的补集），实测后果是修好 36 艘、同时**弄坏 8 艘**：
##   · `condor` / `kestrel` / `raven` / `tristan` —— 这 4 艘走 `AXIS_REMAP`，
##     其 M 是用户在交互式标定台上逐艘点【舰艏】+【船背】定的，而 `_e` 判据
##     **独立地证明它们是对的**（4 艘无一例外）⇒ 翻它们必错；
##   · `cormorant` / `scythe` / `vexor` / `bantam` —— 判据说这 4 艘现在也是对的。
##
## 结论：病灶不是「整组反了」，而是名单**逐条判错**（判得動的 21 条里 20 条错）
## **且漏了 15 条**。那只能重建，不能一行翻转 —— 重建已做，见上面的 FLIP。
const GLOBAL_180 := false

static func extra_yaw(ship_id: StringName) -> float:
	var rad := 0.0
	if AXIS_DEG.has(ship_id):
		rad += deg_to_rad(float(AXIS_DEG[ship_id]))
	if FLIP.has(String(ship_id)):
		rad += PI
	if GLOBAL_180:
		rad += PI
	return rad


## 返回这艘船需要先做「轴重映射」的 Basis（单位阵 = 不需要）。
##
## spec 字符串如 "+X,-Z,+Y" 表示三行：
##   世界 +X 方向 ← 模型 +X / 世界 +Y ← 模型 −Z / 世界 +Z ← 模型 +Y
## 构造 Basis 时转置成行 ⇒ 列 = 模型轴向在世界中的投影。
static func axis_remap(ship_id: StringName) -> Basis:
	if not AXIS_REMAP.has(ship_id):
		return Basis.IDENTITY
	return parse_axis_remap(String(AXIS_REMAP[ship_id]))


## 把 spec 字符串解析成 Basis —— **与 `axis_remap()` 同一份实现**（红线 40）。
##
## ⚠️ 为什么必须抽出来给外部用（47 轮）：
##  `tools/probe_remap47` 要**重算**全库 M 并写成 spec。如果它自己复刻一份解析，
##  一旦行列语义写反（44 轮踩过：纸上按"第 i 个 token = 第 i 行"建模，
##  真代码构造时转了置 ⇒ 差一个转置），就会出现「**工具写的 spec 装回游戏是错的**」
##  —— 而且不报错，只是船倒着飞。⇒ 往返自检必须调**这一个**函数。
static func parse_axis_remap(spec: String) -> Basis:
	var parts := spec.split(",")
	if parts.size() != 3:
		return Basis.IDENTITY
	var rows: Array[Vector3] = []
	for p in parts:
		var s := String(p).strip_edges()
		if s.length() != 2:
			return Basis.IDENTITY
		var sign := 1.0 if s[0] == "+" else -1.0
		var v := Vector3.ZERO
		match s[1].to_upper():
			"X": v.x = sign
			"Y": v.y = sign
			"Z": v.z = sign
			_:
				return Basis.IDENTITY
		rows.append(v)
	# rows[0..2] 是世界 X/Y/Z 在模型坐标下的表示；
	# Basis 的列是模型 X/Y/Z 在世界坐标下的表示，正好是 rows 的转置。
	return Basis(
		Vector3(rows[0].x, rows[1].x, rows[2].x),
		Vector3(rows[0].y, rows[1].y, rows[2].y),
		Vector3(rows[0].z, rows[1].z, rows[2].z)
	)


## 解析并缓存某艘船的语义轴 —— 返回 `{bow: Vector3, up: Vector3}`（模型空间）。
##
## ⚠️ 缓存是**静态**的：标定表是 const，运行期不会变，没必要每帧 parse 字符串。
static func _axes(ship_id: StringName) -> Dictionary:
	if _axes_cache.has(ship_id):
		return _axes_cache[ship_id]
	var spec: String = SHIP_AXES.get(ship_id, "")
	var bow := Vector3(1.0, 0.0, 0.0)
	var up := Vector3(0.0, 1.0, 0.0)
	for part in spec.split(" ", false):
		var kv: PackedStringArray = part.split(":", false, 1)
		if kv.size() != 2:
			continue
		match kv[0]:
			"bow": bow = _axis_vec(kv[1])
			"up": up = _axis_vec(kv[1])
			_: push_error("yaw 表：%s 语义轴里出现未知键 '%s'（只能是 bow / up）"
					% [String(ship_id), kv[0]])
	var out := {"bow": bow, "up": up}
	_axes_cache[ship_id] = out
	return out


## `±X / ±Y / ±Z` → 单位向量。认不出来就报错并落回 +X（**不静默**）。
static func _axis_vec(tok: String) -> Vector3:
	match tok:
		"+X": return Vector3(1.0, 0.0, 0.0)
		"-X": return Vector3(-1.0, 0.0, 0.0)
		"+Y": return Vector3(0.0, 1.0, 0.0)
		"-Y": return Vector3(0.0, -1.0, 0.0)
		"+Z": return Vector3(0.0, 0.0, 1.0)
		"-Z": return Vector3(0.0, 0.0, -1.0)
		_:
			push_error("yaw 表：无法识别的轴向 '%s'（只能是 ±X / ±Y / ±Z）" % tok)
			return Vector3(1.0, 0.0, 0.0)


## 该船的 **舰艏轴**（模型空间单位向量）—— 人工标定，真相源 `SHIP_AXES`。
##
## ⚠️ 与 `axis_remap()` 的分工（**两者不许互相替代**）：
##     · `bow_axis()` 回答「模型里**哪根轴**是舰艏」（人工标定，本表）
##     · `axis_remap()` 回答「把那根轴**搬到世界哪个方向**」（姿态，`AXIS_REMAP`）
##    两者相乘才是舰艏的世界方向。
static func bow_axis(ship_id: StringName) -> Vector3:
	var v: Vector3 = _axes(ship_id)["bow"]
	return v


## 该船的 **船背轴**（模型空间单位向量）—— 人工标定，真相源 `SHIP_AXES`。
##
## ⚠️ 22 轮之前它是从 `AXIS_REMAP` 反解的（`M⁻¹·(0,1,0)`）。那样做的问题是：
##    「船背朝哪」明明是**模型自身的语义**，却要从一张"世界姿态表"里倒推，
##    两张表一漂移就谁也说不清哪张对。现在真相源统一到 `SHIP_AXES`，
##    `AXIS_REMAP` 只做姿态，并由 `validate()` 第 ⑧ 条**反向校验**它俩一致。
static func up_axis(ship_id: StringName) -> Vector3:
	var v: Vector3 = _axes(ship_id)["up"]
	return v


## 该船的 **侧向轴**（模型空间单位向量）—— `bow × up`，**纯派生，不许人工填**。
static func side_axis(ship_id: StringName) -> Vector3:
	var a := _axes(ship_id)
	var b: Vector3 = a["bow"]
	var u: Vector3 = a["up"]
	return b.cross(u)


## `SHIP_AXES` 里该船的**原文**（`"bow:+Z up:+Y"` 形式，找不到时返回空串）。
##
## 用途：**对账**（把源码表与工具落盘的 `pose_table.json` 逐条并排比对）。
## ⚠️ 只做展示 / 比对，**不许**拿它去解析出轴向参与计算 —— 那会绕过
##    `_axes()` 的规范化与 `validate()` 的第 ⑤⑦ 条检查（红线 40 同类陷阱）。
static func ship_axes_text(ship_id: StringName) -> String:
	var raw: Variant = SHIP_AXES.get(ship_id)
	return "" if raw == null else String(raw)


## 该船在 `SHIP_AXES` 里是否有登记（**漏登记 = 会静默走默认值**，validate 会拦）。
static func has_ship_axes(ship_id: StringName) -> bool:
	return SHIP_AXES.has(ship_id)


## 全库舰船 id 列表（`SHIP_AXES` 的键序）—— 给体检 / 探针做全库遍历用。
##
## ⚠️ 返回的是 `SHIP_AXES` 的键**快照**（`duplicate()`），调用方可以放心排序 /
##    删元素，不会污染表。**不许**拿它当"第几艘"的索引取法（红线 1）。
static func all_ship_ids() -> Array:
	return SHIP_AXES.keys()


## 该船的语义轴是否**待人工复核**（`AXES_REVIEW`）—— 只给报告 / 工具用。
static func needs_review(ship_id: StringName) -> bool:
	return AXES_REVIEW.has(String(ship_id))


## 该船的 180° 是否仍未定 —— 只给 UI / 排障用，**不参与任何计算**。
static func is_pending(ship_id: StringName) -> bool:
	return PENDING.has(String(ship_id))


## 自检：返回问题列表，空数组 = 表健康。
##
## 查的是三类**不会报错**的错：
##   ① 一个 id 同时在 FLIP 与 PENDING —— "翻不翻"会随查询顺序漂移
##   ② AXIS_DEG 里出现了不在 52 艘名册中的 id（拼错），或偏角越界
##   ③ FLIP / PENDING 里出现不在名册中的 id —— **哑 id 是静默失效**：
##      改船时把 `arbitrator` 换成 `maller` 却忘了删旧名，旧名单会一直"有效"却永不被查询
static func validate() -> PackedStringArray:
	var problems: PackedStringArray = []
	for id in FLIP:
		if PENDING.has(id):
			problems.append("yaw 表：%s 同时在 FLIP 与 PENDING" % id)
	for lst in [FLIP, PENDING]:
		for id in lst:
			if EveShipAssetIndex.by_id(String(id)) == null:
				problems.append("yaw 表：%s 在名单里但不在 52 艘名册中（拼错 / 已淘汰的旧 id？）" % id)
	for key in AXIS_DEG.keys():
		var s := String(key)
		if EveShipAssetIndex.by_id(s) == null:
			problems.append("yaw 表：主轴补偿里的 %s 不在 52 艘名册中（拼错 id？）" % s)
		if absf(float(AXIS_DEG[key])) >= 90.0:
			problems.append("yaw 表：%s 主轴偏角 %.2f° 越界（PCA 主轴约定在 ±90° 内）"
					% [s, float(AXIS_DEG[key])])
	if AXIS_DEG.size() != EveShipAssetIndex.EXPECTED_COUNT:
		problems.append("yaw 表：主轴补偿 %d 条 ≠ 全船 %d 艘（PCA 表应覆盖全部）"
				% [AXIS_DEG.size(), EveShipAssetIndex.EXPECTED_COUNT])

	# ── ④ AXIS_REMAP：必须是**旋转**（det=+1）且第三轴 = 舰艏×船背 ──
	#    写成反射（det=−1）会让船变成镜像船：尺寸/位置全正常，只有左右反了，
	#    不报错也不报警 ⇒ 只能在这里拦。
	for key in AXIS_REMAP.keys():
		var s := String(key)
		if EveShipAssetIndex.by_id(s) == null:
			problems.append("yaw 表：轴重映射里的 %s 不在 52 艘名册中（拼错 id？）" % s)
		var m := axis_remap(key)
		var det := m.determinant()
		if absf(det - 1.0) > 1e-6:
			problems.append("yaw 表：%s 的 AXIS_REMAP det=%.3f ≠ +1（是反射不是旋转 ⇒ 船会左右镜像）"
					% [s, det])
		var wx := m.inverse() * Vector3(1.0, 0.0, 0.0)   # 世界 +X 对应模型哪根轴
		var wy := m.inverse() * Vector3(0.0, 1.0, 0.0)
		var wz := m.inverse() * Vector3(0.0, 0.0, 1.0)
		if wx.cross(wy).distance_to(wz) > 1e-6:
			problems.append("yaw 表：%s 的 AXIS_REMAP 三行不自洽（%.2f）—— 三行必须是一次旋转"
					% [s, wx.cross(wy).distance_to(wz)])

	# ── ⑤ 舰艏轴 ⊥ 船背轴（**22 轮新增**，专治"改了 14 轮还改不对"）─────
	#    共线 = 同一根模型轴被同时当成「舰艏方向」和「船背方向」⇒ 几何上不可能。
	#    症状极其隐蔽：船的尺寸、位置、血条**全部正常**，只有舰艏竖直朝下，
	#    且**任何偏航角都转不动它**（单 yaw 改不了 Y 分量）⇒ 看起来像"这船
	#    的朝向没法修"。myrmidon / tristan 在 22 轮前正是这样（见 BOW_AXIS 注释）。
	#    ⚠️ 这条**必须全库查**（不只查有 remap 的船）—— 默认 spec 是单位阵，
	#       它也可能与某个登记过的 BOW_AXIS 撞车。
	for ship in EveShipAssetIndex.all():
		var sid := StringName(ship.id)
		var bow := bow_axis(sid)
		var up := up_axis(sid)
		if absf(bow.dot(up)) > 1e-6:
			problems.append("yaw 表：%s 的舰艏轴%s 与船背轴%s **共线**（dot=%.3f）"
					% [String(sid), _axis_name(bow), _axis_name(up), bow.dot(up)])
		if absf(bow.length() - 1.0) > 1e-6 or absf(up.length() - 1.0) > 1e-6:
			problems.append("yaw 表：%s 的舰艏/船背轴不是单位向量" % String(sid))

	# ── ⑥ 语义轴必须**逐艘登记**（新船漏填 = 直接 FAIL）─────────────────
	#    22 轮之前 `BOW_AXIS` 是「稀疏表 + 默认 +X」⇒ 51 艘其实**从未被真正标定**，
	#    只是"恰好长轴 = 舰艏轴"。新船一旦长轴 ≠ 舰艏轴就会**静默倒飞**，
	#    而且没有任何报错 ⇒ 这里改成强制全库登记，漏一艘就 FAIL。
	if SHIP_AXES.size() != EveShipAssetIndex.EXPECTED_COUNT:
		problems.append("yaw 表：语义轴 %d 条 ≠ 全船 %d 艘（**新船必须登记 bow/up**）"
				% [SHIP_AXES.size(), EveShipAssetIndex.EXPECTED_COUNT])
	for key in SHIP_AXES.keys():
		if EveShipAssetIndex.by_id(String(key)) == null:
			problems.append("yaw 表：语义轴里的 %s 不在 52 艘名册中（拼错 id？）" % String(key))
	for ship2 in EveShipAssetIndex.all():
		var sid2 := StringName(ship2.id)
		if not SHIP_AXES.has(sid2):
			problems.append("yaw 表：%s **没登记语义轴** —— 先跑 tools/probe_bow_calib 标定 bow/up"
					% String(sid2))
			continue
		# ⑦ 两根轴都必须是 ±X/±Y/±Z 之一 —— 不许填 PCA 主轴那种**斜向量**
		var a := _axes(sid2)
		var bw: Vector3 = a["bow"]
		var pu: Vector3 = a["up"]
		if not _is_axis_vec(bw):
			problems.append("yaw 表：%s 的 bow=%s 不是 ±X/±Y/±Z（斜向量会让对齐矩阵退化）"
					% [String(sid2), _axis_name(bw)])
		if not _is_axis_vec(pu):
			problems.append("yaw 表：%s 的 up=%s 不是 ±X/±Y/±Z" % [String(sid2), _axis_name(pu)])
			# ⑧ 语义表 ↔ 姿态表**交叉校验**：从 AXIS_REMAP 反解的船背轴必须一致
			#
			# ★ 47 轮修正：**必须带 `mesh_rot`**。
			#   反解口径是「M 把 `mesh_rot·up` 送到 +Y」⇒ `mesh_rot·up = M⁻¹·(+Y)`。
			#   旧写法 `up_axis_from_remap()` 直接读 `M⁻¹·(+Y)` —— 那是**根节点空间**的量，
			#   而 `SHIP_AXES` 登记的是**网格空间**的轴，两者差着 `mesh_rot` 那一层
			#   ⇒ 47 轮落表后本条对**全库 52 艘**齐刷刷报"两张表漂移"（假失败）。
			#   ⚠️ 这正是红线 48 的同一根病根：**任何跨"根↔网格"的换算都必须显式带 `mesh_rot`**。
			var up_r := up_axis_from_remap(sid2, mesh_rot_for(sid2))
			if pu.distance_to(up_r) > 1e-6:
				problems.append("yaw 表：%s 的 up=%s 与 AXIS_REMAP 反解 %s **不一致**（两张表漂移了）"
						% [String(sid2), _axis_name(pu), _axis_name(up_r)])
	# ── ⑨ **舰艏必须落到世界 YZ 平面内（否则单 yaw 转不动 ⇒ 侧向飞）** ──
	#    2026-09-27 第四十四轮新增。旧算式是 `R_y(−90°+θ)·M`，而 `R_y` **只动
	#    X/Z 两个分量**：舰艏若被 `M` 送到 ±Y，那么**任何 extra_yaw 都救不回来**
	#    （Y 分量是 R_y 的不动点）⇒ 船在太空里侧向飞 / 竖着飞，而 validate 前八条
	#    **全部通过**（det=+1、正交、两表交叉一致 —— 它们都只查表内部自洽，
	#    不查"算出来的世界方向在不在水平面内"）。
	#
	# ★ 47 轮改写（红线 40 + 48）：
	#   ① 算式换成**生产口径** `zero_pose_basis`。47 轮把 `MODEL_YAW_FIX(−90°)`
	#      删除并吸收进了 M 表 ⇒ 旧的 `R_y(−90°+θ)·M` 多减了 90°（**假失败**）。
	#   ② **必须带 `mesh_rot`**（红线 48）：`SHIP_AXES` 是网格空间的轴。
	#   ⚠️ 两条一起改才成立 —— 只改一条会得到"一半船报错"的假象。
	#
	#    ⚠️ 43e 的教训：把 SHIP_AXES 与 AXIS_REMAP 同时按同一个错口径写，
	#      前八条全绿而实机全反 ⇒ 必须再加这一条**落到世界方向**的护栏。
	#    ⚠️ 这里**只查"在不在水平面内"**，不查"朝不朝敌" —— 朝敌判据在
	#      `tools/verify_run.gd` 的 ⑤ 锚点与 `tools/probe_accept43e` 里（逐艘 52 条），
	#      两者分工：这里防"几何死锁"，那里防"方向反了"。
	for ship4 in EveShipAssetIndex.all():
		var sid4 := StringName(ship4.id)
		if not SHIP_AXES.has(sid4):
			continue   # ⑥ 已经报过"没登记"，这里不重复刷屏
		var mr4 := mesh_rot_for(sid4)
		var yaw4 := extra_yaw(sid4)
		var bow_w4 := (Basis.from_euler(Vector3(0.0, yaw4, 0.0))
				* axis_remap(sid4) * mr4 * bow_axis(sid4)).normalized()
		if absf(bow_w4.x) > 0.02 or absf(bow_w4.y) > 0.02:
			problems.append("yaw 表：%s 的舰艏落到世界 (%.2f,%.2f,%.2f) —— **不在 YZ 平面内**，"
					% [String(sid4), bow_w4.x, bow_w4.y, bow_w4.z]
					+ "单 yaw 转不到 −Z ⇒ 游戏里会**侧向飞**（SHIP_AXES 与 AXIS_REMAP 不配套）")

	# ── ⑩ **`SHIP_AXES.bow` 必须与几何机身长轴平行**（50 轮新增，红线 50c）──
	#
	# ── 为什么必须有这一条（第 ⑨ 条为什么不够）──────────────────────
	#   第 ⑨ 条只查「舰艏**在不在水平面内**」。实测（50 轮，2026-09-27）有 **5 艘**
	#   船的长轴**确实在水平面内**，但方向错了 90°（被标到横向轴上）⇒ 第 ⑨ 条
	#   **全部放行**，而实机看着是「横着飞 / 倒着飞」。
	#
	#   而且这条错误**能骗过所有探针**：表错 ⇒ `_bow_align` 用同一个错值烘 C ⇒
	#   运行时 `looking_at(f,UP)·C` 把那个**横向轴**"完美地"对到目标方向 ⇒
	#   `bow·敌向` 读出来 = +1.0000 全绿。**污染在「输入」不在「算式」**
	#   ⇒ 连"引擎连乘"口径都兜不住。**这是「机器验过 ≠ 实机对」的第 8 例。**
	#
	#   ⇒ 唯一解药 = **引入一条完全不引用本表的独立量**：几何体的 AABB 最长边。
	#     几何长轴是 glb 的客观事实，与任何表无关；`bow` 若与它垂直就是表错了。
	#
	# ── 口径 ────────────────────────────────────────────────────────
	#   与 `mesh_rot` 同款：`eve_ship_yaw.gd` 是**纯静态数据表**，不许反向依赖
	#   视觉层 / 模型层 ⇒ 几何长轴由**调用方传入**（`geo_long`，模型根空间）。
	#   调用方 = `validate()` 的两处入口（`verify_run` / `probe_tabgeom50`），
	#   它们拿到 `mesh_rot` 的同时也能拿到 AABB 最长边。
	#   ⚠️ 容差 20°：AABB 对「斜轴船」（120° 斜轴那 2 艘）有量化误差，
	#      实测合法船的最大偏差远小于此值，而真错（标到横向轴）恒为 90°。
	#
	#   ⚠️ 传 `null` / 空字典 = **调用方没有几何数据** ⇒ 本条跳过（不报假失败）。
	#      入口必须尽量传 —— `verify_run` 若不传，本条就形同虚设。
	#
	# ⚠️⚠️ **本条的判据在本轮被部分证伪，故只"报告"不"判错"** ——
	#   `mesh.get_aabb()` 最长边 **只在"细长机身"的船上等于舰艏轴**。
	#   实测反例（50 轮）：`kestrel` AABB = (99.7, 78.6, 25.0)、
	#   `catalyst` = (284.1, 88.6, 73.0)、`slasher` = (172.3, 81.6, 35.9)
	#   —— 全是**扁平宽板**（长/宽 ≈ 1.3~3.2），最长边是**翼展/板长**，
	#   **不能**当作舰艏轴。用户 23 轮对 kestrel 的裁定（舰艏 = +Y）
	#   在几何上依然可能成立。
	#   ⇒ 本条**只能当"提示"**：`bow` 与最长边差得远时提醒人工复核，
	#     **绝不**据此改表（红线 33：外观真值只有实机图 / 官方 render）。
	#   ⇒ 真正的自动化判据尚未找到，见红线 50c 的"待办"。
	#     候选：`_e` 自发光贴图喷口分布（24 轮用过，判据是"喷口聚在船尾"）。
	if false and _geo_long_provider.is_valid():
		for ship5 in EveShipAssetIndex.all():
			var sid5 := StringName(ship5.id)
			if not SHIP_AXES.has(sid5):
				continue   # ⑥ 已报过
			var geo_long := geo_long_of(sid5)
			if geo_long.length_squared() < 1e-8:
				continue   # 该船几何数据缺失，跳过（不报假失败）
			var bow5 := bow_axis(sid5)
			# 模型的 bow 是**网格空间**的；几何长轴若由调用方按**根空间**给出，
			# 调用方须自行乘 `mesh_rot` 后再传（口径统一在调用方）。
			var cos_al := absf(bow5.dot(geo_long.normalized()))
			var deg5 := rad_to_deg(acos(clampf(cos_al, -1.0, 1.0)))
			if deg5 > 20.0:
				problems.append("yaw 表：%s 的 bow=%s 与**几何机身长轴**%s 夹角 %.1f°（> 20°）"
						% [String(sid5), _axis_name(bow5),
						"(%.2f,%.2f,%.2f)" % [geo_long.x, geo_long.y, geo_long.z], deg5]
						+ " —— 舰艏轴被标到了**横向轴**上 ⇒ 实机会横着飞/倒着飞。"
						+ "跑 tools/probe_fixspec50 反解正确 spec（红线 50c）")
	return problems


## ⑩ 条（红线 50c）的入参：`{id: 几何机身长轴}`（**根空间**，已正交归一）。
##
## 为什么要"传进来"而不是在这里自己算：本文件是**纯静态数据表**，
## 不许反向依赖视觉层（`EveShipModel` 在 `scripts/visual/`）—— 与 `mesh_rot`
## 同一条约定（见 `up_axis_from_remap` 的注释）。
##
## 调用方（`verify_run` / `tools/probe_tabgeom50`）在 `validate()` **之前**注入：
##     `EveShipYawTable.set_geo_long_provider(func(id): return _geo_long_of(id))`
## 不注入 ⇒ 本条跳过（**不报假失败**，但也没护栏）。
static func set_geo_long_provider(cb: Callable) -> void:
	_geo_long_provider = cb


static func clear_geo_long_provider() -> void:
	_geo_long_provider = Callable()


static var _geo_long_provider: Callable = Callable()


## 取某船的几何长轴（根空间）。无 provider 时返回零向量（= 缺数据）。
static func geo_long_of(ship_id: StringName) -> Vector3:
	if not _geo_long_provider.is_valid():
		return Vector3.ZERO
	var v: Variant = _geo_long_provider.call(ship_id)
	if v is Vector3:
		return v
	return Vector3.ZERO


## 从姿态表反解船背轴（**只给第 ⑧ 条校验用**），
## 真相源是 `SHIP_AXES`；两者一致才说明两张表没漂移。
##
## ★ 47 轮修正（红线 48）：**必须带 `mesh_rot`**。
##   口径：`M · mesh_rot · up = +Y`（船背朝天）⇒ `mesh_rot·up = M⁻¹·(+Y)`
##        ⇒ `up = mesh_rot⁻¹ · M⁻¹ · (+Y)`。
##   旧实现漏了 `mesh_rot` 那一层（见 `eve_ship_visual.mesh_rot_of()` 的说明）——
##   `SHIP_AXES` 登记的是**网格空间**轴，`AXIS_REMAP` 映射的是**根节点空间**，
##   两者之间恒隔着一个 `mesh_rot`。
##
## ⚠️ 这里**不直接调 `EveShipVisual.mesh_rot_of()`**（那会引入「数据层依赖视觉层」
##    的反向引用，`eve_ship_yaw.gd` 是纯静态表，不许依赖节点类）⇒ 由调用方
##    （`validate()` / 探针）**传入** `mesh_rot`。语义上它属于"船的几何事实"，
##    与 `SHIP_AXES` 同级，所以放在这一层是自洽的。
static func up_axis_from_remap(ship_id: StringName, mesh_rot: Basis) -> Vector3:
	return (mesh_rot.inverse() * axis_remap(ship_id).inverse() * Vector3(0.0, 1.0, 0.0)).normalized()


## 是否是 6 个轴向之一（恰好一个分量 ±1，其余 0）。
static func _is_axis_vec(v: Vector3) -> bool:
	var n := 0
	for i in 3:
		if absf(v[i]) < 1e-6:
			continue
		if absf(absf(v[i]) - 1.0) > 1e-6:
			return false
		n += 1
	return n == 1


## 把 ±1 的轴向向量写成 "+X" / "-Y" 这种形式，只给报错信息用。
static func _axis_name(v: Vector3) -> String:
	for i in 3:
		if absf(v[i]) < 0.5:
			continue
		return ("+" if v[i] > 0.0 else "-") + ["X", "Y", "Z"][i]
	return "(%.2f,%.2f,%.2f)" % [v.x, v.y, v.z]
