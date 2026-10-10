# EVE 自走棋 (EVE Auto-Chess)

一款以 EVE 题材为背景的**开源自走棋**（auto-battler），使用 **Godot 4** + **GDScript** 开发，支持 **Windows / Android** 双端。

- 3D 战斗、无格子布阵，52 艘舰船（4 派系 × 13 艘），吨位 1~5 档对应舰船体型档位
- 4 派系羁绊、打捞、信标、事件四选一等玩法
- 主玩法「守卫边境」PVE 流程 + 内置「娱乐总汇 · 斗地主」小游戏
- 五分区设置（分辨率 / 音频 / 界面缩放 / 字号 / 平台 UI 缩放）、非 16:9 自动居中

## 引擎与平台

| 项 | 版本 / 说明 |
|---|---|
| 引擎 | Godot **4.7.2**（导出模板需与引擎同号） |
| 语言 | GDScript |
| 桌面端 | Windows（单文件 exe） |
| 移动端 | Android（arm64-v8a） |

> 注意：本项目工程名与对外名称均为 **EVE 自走棋 / EVE-AutoChess**，与任何数字后缀无关。

## 如何运行 / 构建

1. 安装 [Godot 4.7.2](https://godotengine.org/)。
2. 用 Godot 打开本仓库根目录（`project.godot`）。
3. 编辑器内按 **F5** 直接运行；或 **项目 → 导出** 选择 Windows / Android 预设。
4. Android 导出需在 `export_presets.cfg` 填入自己的 keystore 与签名口令（仓库内已**移除**示例签名配置，避免密钥泄露）。

## 目录结构（节选）

```
scripts/        游戏逻辑（ui / core / card/ddz / data 等）
scenes/         Godot 场景（主菜单、战斗、斗地主牌桌、片头等）
assets/         美术 / 音频资源（见下方版权说明）
data/           设计侧数据源（CSV 原稿 + 开场时间轴，见 data/README.md）
tools/          无头验证与探针脚本（verify_* / probe_*）
tools/pipeline/ 离线生成脚本（舰船/朝向/牌面/天空盒，见其 README）
export_presets.cfg  导出预设（不含签名密钥）
```

## 跑验收

统一入口（读退出码，可直接给 CI 用）：

```bash
GODOT_BIN=/path/to/Godot_v4.7.2-stable_win64_console.exe tools/run_verifies.sh
```

判据不止退出码 —— 还要求**出现完成标记**、且输出里**没有** `SCRIPT ERROR`。
⚠️ `verify_run` 在引擎收尾时会 SIGSEGV（退出码 139，结果其实完整），runner 对它只认结果行。
诊断型脚本（`verify_battle` / `verify_background` / `verify_camera` / `probe_*`）只出数、
没有通过/失败语义，**不在套件里**。

## 美术资源版权说明

仓库内的舰船模型、图标、音频等游戏美术资源**提取自 EVE Echoes 客户端资源**。
EVE 相关的 IP 与素材著作权归 **Fenris Creations** 所有（该公司于 2026 年 5 月由 CCP Games 更名而来；
CCP 原名 *Crowd Control Productions*），**本开源项目不持有这些素材的任何权利**，相关内容**不**在本项目的 GNU GPL v3 许可证覆盖范围内。

- 这些资源**仅用于开发、调试与体验目的**；
- 若你分发包体，请自行确认相关素材的授权合规；
- 代码（GDScript / 配置 / 工具脚本）以 **GNU GPL v3** 许可证使用、修改与再分发（衍生作品须同样以 GPL v3 开源）。

## 许可证

- **代码**：[GNU GPL v3](./LICENSE)（Copyright © 2026 xshynews）
- **美术 / 音频资源**：归 Fenris Creations 所有，非本项目许可证覆盖范围，见上。

## 多语言（i18n）：目前**只出中文**，英文有意冻结

仓库里有一套 i18n 基建（`i18n/strings.csv` 是唯一文案真相源，代码一律经 `EveText.t()` 取词），
但**当前交付语言只有简体中文**——英文不是"做了一半丢在那"，是**有意冻结**：

- **为什么**：英文文案本身还没过审（`strings.csv` 的 `en` 列大量是占位/直译），
  UI 面也只迁了一半。这时开放语言切换，玩家只会看到中英混杂的半成品。
- **表现**：设置窗里**没有**「语言」这一行。开关是 `scripts/core/eve_text.gd` 的
  **`LANGUAGE_ENABLED = false`**（唯一真源，代码都保留着，只是被这个常量挡住）。
- **要不要紧**：不影响中文版任何行为——默认 locale 是 `zh_CN`，取词原样返回中文、逐字不变；
  `verify_i18n` 就是这条的护栏（它同时也断言"冻结期语言行不存在 / 存档语言会被忽略"）。
- **想启用 / 想加语言**：见 [`i18n/README.md`](./i18n/README.md) 顶部的解冻四步，
  **翻那一个常量**就能先看到界面入口；英文文案（`en` 列）是最欢迎 PR 的部分。

## 贡献

欢迎issue与PR。提交前请保持 `scripts/` 下 snake_case 命名、关键行为附 `verify_*` 无头验收。
