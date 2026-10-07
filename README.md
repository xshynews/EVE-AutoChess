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
tools/          无头验证与探针脚本（verify_* / probe_*）
export_presets.cfg  导出预设（不含签名密钥）
```

## 美术资源版权说明

仓库内的舰船模型、图标、音频等游戏美术资源**提取自 EVE Echoes 客户端资源**。
EVE 相关的 IP 与素材著作权归 **Fenris Creations** 所有（该公司于 2026 年 5 月由 CCP Games 更名而来；
CCP 原名 *Crowd Control Productions*），**本开源项目不持有这些素材的任何权利**，相关内容**不**在本项目的 MIT 许可证覆盖范围内。

- 这些资源**仅用于开发、调试与体验目的**；
- 若你分发包体，请自行确认相关素材的授权合规；
- 代码（GDScript / 配置 / 工具脚本）以 MIT 许可证自由使用、修改与再分发。

## 许可证

- **代码**：[MIT License](./LICENSE)
- **美术 / 音频资源**：归原权利方所有，非 MIT，见上。

## 贡献

欢迎issue与PR。提交前请保持 `scripts/` 下 snake_case 命名、关键行为附 `verify_*` 无头验收。
