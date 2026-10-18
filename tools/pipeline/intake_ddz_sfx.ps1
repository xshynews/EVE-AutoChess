# ══════════════════════════════════════════════════════════════════
#  斗地主牌桌音效 —— 候选池 → 正式音库（一次性 / 可重跑）
# ══════════════════════════════════════════════════════════════════
#  ⛔ 为什么是 PowerShell 不是 .py：本机**没有装 Python**（pipeline 里其它脚本
#     都跑不了），而 ffmpeg 工程自带 ⇒ 用 pwsh + ffmpeg 才能落地执行。
#  ⚠️ 编码器：ogg = Vorbis（⛔ 不是 Opus —— Godot 的 .ogg 只认 Ogg Vorbis）。
#
#  用法：
#     pwsh -File tools/pipeline/intake_ddz_sfx.ps1            # 真跑
#     pwsh -File tools/pipeline/intake_ddz_sfx.ps1 -DryRun    # 只打印映射不写文件
#
#  命名：`<逻辑名>_01.ogg` —— `EveAudio._scan_dir()` 按「去掉末尾 _NN」还原逻辑名。
#  ⚠️ 逻辑名一律 ddz_ 前缀：与战斗音（fire/hit/boom）分属两个语义世界，
#     将来整体替换（见下表「来源」列的 ⚠UNO）时一眼能找齐。
#
#  ★ 两批映射，同一个循环里跑（重跑 = 幂等覆盖）：
#     ① `$MAP`  18 行 —— 发牌 / 叫抢 / 牌型 / 胜负（2026-10-17 试听台拍板，手写）
#     ② `$MAP2` 28 行 —— **报牌音**：单张 15 条 + 对子 13 条。
#        ⛔ 这一批**不手抄**：脚本自己遍历源目录、按**文件名**查点数表推导逻辑名；
#        认不出的名字 / 缺的点数一律**直接报错退出**（见下面「第二批」整段）。
# ══════════════════════════════════════════════════════════════════
param(
	[string]$FFMPEG = "C:\godot\_export\ffmpeg\bin\ffmpeg.exe",
	[switch]$DryRun
)

$ErrorActionPreference = "Stop"
$ROOT = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$SRC = Join-Path $ROOT "assets\audio_candidates"
$DST = Join-Path $ROOT "assets\audio\sfx"

# ── 拍板结果（2026-10-17 用户试听台拍定）────────────────────────────
#   事件            逻辑名                  候选源文件                          来源
$MAP = @(
	# ★★ 发牌音（2026-10-18 用户定稿的**结构**；10-18 二次调参：停顿 0.1 → 0.4s）：
	#   0.6 秒洗牌音发一批牌 → 停 0.4 秒 → 再播一遍……共 4 段
	#   （每段发 4 张，末段 5 张 ⇒ **4-4-4-5 = 17**），最后再停 0.5 秒才进叫地主
	#   ⇒ 成品就是这条时间线本身：
	#     音 ×4 + 段间 0.4s 静音 + 收尾 0.5s 静音（合计 4.09s）
	#   ⛔ 别做成"一段 3.6 秒的连续洗牌"：那样段间没有停顿，动画也没法跟着分段
	#      （用户原话「一段发牌音要对应一段发牌动画，中间需要停顿一下」）。
	#   ⚠️ `ddz_table` 的 DEAL_SEG_SOUND / DEAL_SEG_GAP / DEAL_TAIL / DEAL_BURSTS
	#      与这里**必须一致**（音画同源），改一处就得同步另一处。
	#   ★ 停顿为什么是 0.4（不是 0.1）：0.1s 只占一段音的 17%，**眼睛抓不到**
	#     （连拍探针 `probe_ddz_deal` 实测：0.2s 采样下每行张数都在涨，看不出分段）
	#     ⇒ 用户「我并没有感受到那种段落感」。0.4s 让「一段音 + 一次停顿」凑成
	#     **整整 1 秒的节拍**（0.598 + 0.4 ≈ 1.0）⇒ 段落感立刻出来，总长 4.09s 仍在 5s 内。
	@{ ev = "发牌";        k = "ddz_deal";        f = "uno_FL_Card_Shuffle_01.wav";          src = "⚠UNO"; burst = 4; gap = 0.4; tail = 0.5 },
	# ★ 「过」：与「不要」**共用逻辑名** `ddz_pass`（n=2 ⇒ 落成 ddz_pass_02.ogg）
	#   ⇒ `EveAudio` 会随机挑一个变体，且**不与上一次重复** ⇒ 两句交替出现（用户要的趣味性）。
	@{ ev = "过";          k = "ddz_pass";        f = "ddz_001_过.wav";                      src = "自备"; n = 2 },
	@{ ev = "我抢";        k = "ddz_bid_rob";     f = "ddz_002_我抢.wav";                    src = "自备" },
	@{ ev = "选牌";        k = "ddz_pick";        f = "uno_FL_Card_Select.wav";              src = "⚠UNO" },
	@{ ev = "取消选牌";    k = "ddz_pick";        f = "uno_FL_Card_Select.wav";              src = "⚠UNO" },
	# ★ 2026-10-17 用户：「找到 FL_CARD_SELECT 这个音频文件，我觉得这个文件非常适合
	#   放进斗地主的鼠标点击声，有鼠标点击又没有规定其他声音的话，就放这个音效」
	#   ⇒ 与「选牌」同一个采样（`uno_FL_Card_Select.wav`），但落成**独立键**：
	#     ⛔ 别合并进 `ddz_pick` —— 将来换掉任一个，另一个不该跟着变。
	@{ ev = "鼠标点击";    k = "ddz_click";       f = "uno_FL_Card_Select.wav";              src = "⚠UNO" },
	@{ ev = "出牌";        k = "ddz_play";        f = "uno_FL_Card_Play_02.wav";             src = "⚠UNO" },
	@{ ev = "不要";        k = "ddz_pass";        f = "ddz_005_不要.wav";                    src = "自备" },
	@{ ev = "顺子";        k = "ddz_combo_straight";   f = "ddz_004_顺子.wav";               src = "自备" },
	@{ ev = "连对";        k = "ddz_combo_pairs";      f = "ddz_014_连对.wav";               src = "自备" },
	@{ ev = "三带一";      k = "ddz_combo_trio";       f = "ddz_008_三带一.wav";             src = "自备" },
	@{ ev = "三带二";      k = "ddz_combo_trio_pair";  f = "ddz_011_三带二.wav";             src = "自备" },
	@{ ev = "四带一";      k = "ddz_combo_quad";       f = "ddz_009_四带一.wav";             src = "自备" },
	@{ ev = "四带二";      k = "ddz_combo_quad_pair";  f = "ddz_010_四带二.wav";             src = "自备" },
	@{ ev = "王炸";        k = "ddz_rocket";      f = "ddz_012_王炸.wav";                    src = "自备" },
	@{ ev = "叫地主";      k = "ddz_bid_call";    f = "ddz_002_叫地主.wav";                  src = "自备" },
	@{ ev = "不叫";        k = "ddz_bid_nocall";  f = "ddz_001_不叫.wav";                    src = "自备" },
	@{ ev = "抢地主";      k = "ddz_bid_grab";    f = "ddz_003_抢地主.wav";                  src = "自备" },
	@{ ev = "不抢";        k = "ddz_bid_nograb";  f = "ddz_007_不抢.wav";                    src = "自备" },
	@{ ev = "非法操作/拒绝"; k = "ddz_deny";      f = "uno_Sfx_Card_Error_Warning.wav";      src = "⚠UNO" },
	@{ ev = "胜利";        k = "ddz_win";         f = "uno_Jingle_Classic_A_Match_End.wav";  src = "⚠UNO" }
)

# ══════════════════════════════════════════════════════════════════
#  第二批：报牌音 —— **遍历识别**（2026-10-17 下午，用户「可以直接写进游戏」）
# ══════════════════════════════════════════════════════════════════
#  源目录 `F:\evezzq\音频\牌`（28 个 wav，22050Hz 单声道）。
#  ⛔ 不手抄 28 行映射：下面三段遍历它、按**文件名**算出逻辑名。
#
#  ① 源 → 隔离区：去掉文件名开头的 `NNN_` 编号，复制成 `ddz_牌_<名>.wav`
#     ⛔ 必须去编号：源里编号**重号**（`001_三` 与 `001_大王` 都是 001），
#        拿编号当键会直接串位（「三」和「大王」互换）。
#  ② 遍历隔离区全部 `ddz_牌_*.wav` → 查下面的点数表 → 拼逻辑名：
#     `对` 开头 ⇒ 对子 `ddz_pair_<点数>`；否则 ⇒ 单张 `ddz_card_<点数>`
#  ③ 点全覆盖检查：单张 3~17、对子 3~15 **缺一条都算失败**
#     （缺的那个点数会**永久哑音**，而玩家在牌桌上根本听不出"少了一条"）
#
#  ⛔ ②③ 一旦过不去就**直接报错退出**，不猜、不跳过 ——
#     「猜一个」的后果是那张牌报错名，而那正是这批素材唯一要保证的东西。
#
#  ★ 点数 = `ddz_rules.gd` 的 rank（⛔ 不是牌面数字）：
#       3..10 就是面值 · 勾 = J = 11 · 圈儿 = Q = 12 · K = 13
#       尖 = A = **14**（⛔ 不是 1）· 二 = 2 = 15 · 小王 = 16 · 大王 = 17
#
#  ⚠️ `ddz_combo_pair`（第一批手写的通用「对」）已于 2026-10-17 删除 ——
#     被下面这 13 条**具体对子**取代（用户「该删就删」），牌桌不再调它。
$RANK_BY_NAME = [ordered]@{
	"三" = 3;  "四" = 4;  "五" = 5;  "六" = 6;  "七" = 7;  "八" = 8;
	"九" = 9;  "十" = 10; "勾" = 11; "圈儿" = 12; "K" = 13;  "尖" = 14;
	"二" = 15; "小王" = 16; "大王" = 17
}
$CARD_SRC = "F:\evezzq\音频\牌"    ## 用户自备报牌语音的落点（⛔ 在工程外）
$CARD_PFX = "ddz_牌_"

# ① 源 → 隔离区。⚠️ 源目录不在（换机器 / 用户挪走了）⇒ 跳过，只用隔离区已有副本，
#    保证这个脚本在别处也跑得通。
if (-not $DryRun -and (Test-Path -LiteralPath $CARD_SRC)) {
	$nCopied = 0
	foreach ($cf in (Get-ChildItem -LiteralPath $CARD_SRC -File -Filter *.wav)) {
		$nm = $cf.BaseName
		if ($nm -match '^\d{3}_') { $nm = $nm.Substring(4) }
		Copy-Item -LiteralPath $cf.FullName `
				-Destination (Join-Path $SRC ($CARD_PFX + $nm + ".wav")) -Force
		$nCopied++
	}
	Write-Host ("报牌音源 → 隔离区：{0} 个（已去编号）" -f $nCopied)
} elseif (-not $DryRun) {
	Write-Warning ("报牌音源目录不在，跳过复制，只用隔离区已有副本：$CARD_SRC")
}

# ② 遍历隔离区推导逻辑名
$MAP2 = @()
$badName = @()
foreach ($cf in (Get-ChildItem -LiteralPath $SRC -File -Filter "$CARD_PFX*.wav" | Sort-Object Name)) {
	$nm = $cf.BaseName.Substring($CARD_PFX.Length)
	$isPair = $nm.StartsWith("对")
	$key = if ($isPair) { $nm.Substring(1) } else { $nm }
	if (-not $RANK_BY_NAME.Contains($key)) {
		$badName += ("{0}（名字「{1}」不在点数表里）" -f $cf.Name, $key)
		continue
	}
	$rank = [int]$RANK_BY_NAME[$key]
	if ($isPair -and $rank -gt 15) {
		$badName += ("{0}（「{1}」是王，各只有一张 ⇒ 没有对王）" -f $cf.Name, $key)
		continue
	}
	$logical = if ($isPair) { "ddz_pair_$rank" } else { "ddz_card_$rank" }
	$MAP2 += @{ ev = $nm; k = $logical; f = $cf.Name; src = "自备/牌" }
}

# ③ 全覆盖检查 + 收口
$expect = @()
foreach ($r in 3..17) { $expect += "ddz_card_$r" }
foreach ($r in 3..15) { $expect += "ddz_pair_$r" }
$haveKeys = @($MAP2 | ForEach-Object { $_.k })
$absent = @($expect | Where-Object { $haveKeys -notcontains $_ })
if ($MAP2.Count -eq 0) {
	# 隔离区里一条报牌音都没有（换机器常见）⇒ 跳过第二批，不算失败
	Write-Warning "隔离区没有报牌音（$CARD_PFX*.wav）⇒ 跳过第二批，只跑第一批"
} elseif ($badName.Count -gt 0 -or $absent.Count -gt 0) {
	Write-Host "`n✖ 报牌音识别没过，⛔ 不猜、不跳过：" -ForegroundColor Red
	foreach ($b in $badName) { Write-Host ("    认不出：{0}" -f $b) -ForegroundColor Red }
	foreach ($m in $absent) { Write-Host ("    缺音源：{0}（这个点数会永久哑音）" -f $m) -ForegroundColor Red }
	throw "报牌音识别没过 —— 改文件名 / 补文件后重跑（表在脚本里的 `$RANK_BY_NAME）"
} else {
	Write-Host ("报牌音遍历识别 OK：{0} 条（单张 {1} + 对子 {2}）" -f $MAP2.Count,
			@($MAP2 | Where-Object { $_.k.StartsWith("ddz_card_") }).Count,
			@($MAP2 | Where-Object { $_.k.StartsWith("ddz_pair_") }).Count)
}

# ── 复用已有音源（⛔ 不产新文件，只是「事件 → 现有逻辑名」）──────────
#   炸弹 → boom（assets/audio/sfx/boom_0N.ogg，随机挑一发）
#   失败 → resolve（assets/audio/ambience/resolve_0N.ogg）
#   叫分 1/2/3 → count_1/2/3（ambience；用户 2026-10-17：按钮没了，暂不接线）

if (-not (Test-Path $FFMPEG)) { throw "找不到 ffmpeg：$FFMPEG" }
if (-not (Test-Path $DST)) { throw "找不到目标音库目录：$DST" }

$done = 0; $skip = 0; $fail = 0
# ★ 两批一起跑：第一批 18 行（拍板结果，手写）、第二批（报牌音，上面遍历推导出来）。
foreach ($m in @($MAP) + @($MAP2)) {
	$in = Join-Path $SRC $m.f
	# 变体序号（默认 01）：同一个逻辑名下放多个**不同内容**的音源时用它区分
	# （例如 不要 → ddz_pass_01 / 过 → ddz_pass_02，两个都还原成逻辑名 `ddz_pass`）。
	$idx = if ($m.ContainsKey("n")) { [int]$m.n } else { 1 }
	$out = Join-Path $DST ("{0}_{1:00}.ogg" -f $m.k, $idx)
	$tag = if ($m.ContainsKey("burst")) { "  {0}段(间隙{1}s/收尾{2}s)" -f $m.burst, $m.gap, $m.tail }
		elseif ($m.ContainsKey("n")) { "  变体$idx" } else { "" }
	Write-Host ("{0,-12} {1,-22} <- {2,-38} [{3}]{4}" -f $m.ev, $m.k, $m.f, $m.src, $tag)
	if ($DryRun) { continue }
	if (-not (Test-Path $in)) { Write-Warning ("  源缺失，跳过：{0}" -f $in); $fail++; continue }
	if ($m.ContainsKey("burst")) {
		# ★ 分段结构（发牌专用，见 `$MAP` 发牌那行的注释）：
		#   `音 + gap 静音` 复制 burst 份再首尾相接，最后补 `tail - gap` 的静音。
		$burst = [int]$m.burst
		$gap = [double]$m.gap
		$tailExtra = [math]::Round([double]$m.tail - $gap, 4)
		$ins = ""
		for ($i = 0; $i -lt $burst; $i++) { $ins += "[b$i]" }
		# ⚠️ `n=${burst}` 的大括号是**必须的**：不加的话 PowerShell 会把 `$burst:v`
		#    当成「作用域 burst 里的变量 v」（`$env:PATH` 那种语法）⇒ 展开成空串，
		#    ffmpeg 收到 `concat=n==0:a=1` 就报 `Unable to parse "n" option value`（实测踩过）。
		$fc = "[0:a]apad=pad_dur=$gap,asplit=$burst$ins;" `
				+ "${ins}concat=n=${burst}:v=0:a=1,apad=pad_dur=$tailExtra[out]"
		& $FFMPEG -y -loglevel error -i $in -filter_complex $fc -map "[out]" `
				-c:a libvorbis -q:a 5 $out
	} else {
		# -q:a 5 ≈ 160kbps 立体声：短语音足够，且远小于 wav
		& $FFMPEG -y -loglevel error -i $in -c:a libvorbis -q:a 5 $out
	}
	if ($LASTEXITCODE -ne 0) { Write-Warning ("  转码失败：{0}" -f $m.f); $fail++; continue }
	$done++
}
if (-not $DryRun) {
	Write-Host ("`n转码 {0} 个 -> {1}；源缺失/失败 {2} 个" -f $done, $DST, $fail)
	Write-Host "⚠ UNO 来源的 6 个键（ddz_deal / ddz_pick / ddz_click / ddz_play / ddz_deny / ddz_win）仅限本地自用，发布前必须替换。"
}
