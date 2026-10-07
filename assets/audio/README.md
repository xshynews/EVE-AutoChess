# assets/audio —— 音源来源与口径

音源全部来自本机 EVE Online 客户端（`D:\EVE\SharedCache\ResFiles`），
经 vgmstream 从 Wwise SoundBank 解包后压成 Ogg Vorbis。
**是玩家在 EVE 里听到的同一批音源，不是仿制品。**

## 一、可信度边界（重要）

EVE 的 SoundBank **不带「媒体 → 名字」映射**：

- STID（stream name 表）在 `essential_media` 各 bank 里是**空的**；
- 名字只以 Wwise「事件」形式存在，而事件→媒体的映射在 HIRC 里没有名字；
- 索引里列了 `res:/audio/soundbanksinfo.xml|json`，但**本机客户端没下载**
  （`ResFiles` 里查无此文件），拿不到事件→媒体表。

所以本目录采用 **银行级语义 + 银行内声学筛选**：

| 可信度 | 内容 |
| --- | --- |
| ✅ 可靠 | 每个 SoundBank 的**用途**（turrets = 炮台开火 / interface = 界面反馈 / shipeffects = 舰船效果 / 独立 .wem = 音乐） |
| ⚠️ 设计选择 | 银行**内部**按 时长 / 过零率 / 能量 分档 |

也就是说：**可以**说「开火音来自 EVE 的 turrets 音库」；
**不可以**说「hit_shield_01 就是 EVE 里护盾被打的那一声」——
护盾 / 装甲 / 结构三档是按「亮 → 暗」的音色梯度排的，属于设计选择。

## 二、文件清单

命名约定 `<逻辑名>_<序号>.ogg`（`eve_audio.gd::_scan_dir` 的解析依据）。

### sfx/（打击反馈 · 39 个 · 1.1 MB）
| 逻辑名 | 数量 | 来源 bank | 分档依据 |
| --- | --- | --- | --- |
| `fire_light` / `fire` / `fire_heavy` / `fire_capital` | 4/4/4/3 | turrets | 按时长分位四档（短 = 小炮，长 = 大炮） |
| `hit_light` / `hit` | 4/4 | effects | 短促、attack 高（一击即响） |
| `hit_shield` / `hit_armor` / `hit_structure` | 3/3/3 | effects | ⚠️ 按过零率「亮 → 暗」，**设计选择** |
| `boom` | 7 | shipeffects + effects | 最长最猛的几条 |

### ambience/（阶段环境 · 19 个 · 0.19 MB）
`tick` / `tick_urgent` / `count_1~3` / `phase_prep` / `phase_battle` /
`phase_resolve` / `phase_end` / `resolve` / `node` —— 全部来自 **interface**（界面反馈音）。

### music/（BGM · 4 个 · 14.4 MB）
来自 `essential_media` 里的独立 `.wem`（Custom Vorbis，2~23 分钟的真曲子）。
`battle_*` = RMS 最高的两首（-21.1 / -23.7 dB），
`prep_*` = 最接近 -28 dB 的两首。

⚠️ 没有取 RMS 垫底的两首（-43.9 / -46.3 dB）：那是近乎听不见的长环境声，
当 BGM 会让人以为音乐没放。

## 三、可调旋钮

全部在 `scripts/core/eve_audio.gd`：

| 旋钮 | 位置 | 说明 |
| --- | --- | --- |
| `volume_sfx` = 0.60 / `volume_amb` = 0.39 / `volume_music` = 0.32 | 通过 `set_volume()` 改 | 三条总线独立音量；**直接改变量不生效** |
| `muted` | 通过 `set_muted()` 改 | 同上 |
| `SFX_POOL` = 12 | 常量 | 短音同时发声数；太小互相打断，太大糊成噪音 |
| `BOOM_POOL` = 4 / `AMB_POOL` = 4 | 常量 | 爆炸 / 环境音独立池 |
| `THROTTLE_FIRE` = 0.045 s | 常量 | 开火节流窗口 |
| `BURST_FIRE` / `BURST_HIT` / `BURST_BOOM` = 3/3/2 | 常量 | 每窗口允许几声（齐射容量） |
| `THROTTLE_BY_QUALITY` | 常量数组 | 命中按 7 档品质分窗口，重击窗口更短 |
| `MUSIC_FADE` = 1.2 s | 常量 | BGM 交叉淡入时长 |

⚠️ **音量滑块不是线性增益**：`_set_bus_vol` 走的是平方曲线（`gain = lin²`，
见 `linear_to_db(lin * lin)`）。
所以「响度降一半」= 滑块乘 `1/√2 ≈ 0.707`，**不是乘 0.5** —— 乘 0.5 会掉 −12 dB
（听感只剩四分之一，过头了）。当前默认值就是原始 `0.85 / 0.55 / 0.45`
统一 −6 dB 的结果：

| 总线 | 滑块 | 实际增益 |
| --- | --- | --- |
| sfx | 0.60 | −8.9 dB（原 −2.8） |
| amb | 0.39 | −16.4 dB（原 −10.4） |
| music | 0.32 | −19.8 dB（原 −13.9） |

要再整体挪一档：**三个数一起乘同一个系数**，别单独动一个，否则 sfx : amb : music
的配比会变。

⚠️ `BURST_*` 不是可选优化：战斗是固定步长推进的，**同一 tick 里 6 艘船的
`sim.elapsed` 完全相同**，只有冷却窗口没有桶容量会把 6 声齐射压成 1 声
（实测 12 秒战斗 32 次开火只响 8 声）。

## 四、验收

- `res://tools/verify_audio.tscn` —— 32 条，与资产无关（用内存 WAV）
- `res://tools/verify_run.tscn` —— 328 条里含 14 条音频断言，
  守卫「静默缺源」（`missing` 计数必须为 0）与「节流真的在吞」
