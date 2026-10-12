# `_manifest/` —— 3D 构建流水线的清单与结果

这一目录是**流水线的输入/记录**，随仓库开源，目的是让其他开发者**能复现**舰船 3D 资产的构建：

| 文件 | 是什么 | 谁产生 / 谁消费 |
| --- | --- | --- |
| `_ship_manifest.json` | 52 艘船 id → typeID → 模型名 的清单（构建的输入） | 由 `fetch_official.py` + `01_舰船数值全表.csv` 得来；`_build_all_ships.py` / `_gen_ship_index.py` 读它 |
| `_build_result.json` | 逐艘的构建结果（面数、包围盒、贴图清单） | `_build_all_ships.py` 写；`_gen_ship_index.py` 读 |
| `_typeids.json` | 舰船名 → ESI typeID 的缓存 | `fetch_official.py` 写 |

> ⚠️ 这些文件原先只存在于作者本机的 `C:\godot\_export\`，别人克隆后无法重建模型
> （= 假开源）。2026-10-12 起随仓库提供，路径由 `tools/pipeline/_paths.py` 解析
> （`SHIP_MANIFEST` / `build_result_json()`），可用环境变量覆盖。

## ✅ 口径已于 2026-10-12 对齐（原先的 3 处偏差已消除）

历史上本清单比仓库里的 `eve_ship_asset_index.gd` 旧 3 处，现已按「**运行时为准**」
（谁被引用得更多：`eve_ship_table.gd` + 资产索引 + `assets/` 才有模型与立绘）对齐：

| 舰船 | 对齐结果 | 依据 |
| --- | --- | --- |
| `executioner` | 刽子手级 | ESI typeID 589 官方中文名 |
| `arbitrator` → **`maller`** | 暴君级（typeID 624） | 原 `arbitrator` 已下线；游戏里有 `maller.glb` + `maller.png` |
| `cyclone` / `hurricane` | 飓风级 / 暴风级 | ESI 16231 / 24702 官方中文名 |

同时 `data/source_csv/01_舰船数值全表.csv` 也改到了同一口径，
`tools/verify_data_source.gd` 里那两条「有意分歧」白名单随之清空。

> 现在 `python tools/pipeline/_gen_ship_index.py` 的输出与仓库里的
> `eve_ship_asset_index.gd` **逐字节一致**（可重复生成，已实测幂等）。

