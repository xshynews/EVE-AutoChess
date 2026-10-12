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

## ⚠️ 已知偏差：本清单**比**仓库里的 `eve_ship_asset_index.gd` **旧 3 处**

`eve_ship_asset_index.gd`（机生成产物）后来被手工修正过几行，而本清单没有同步。
现在直接用 `_gen_ship_index.py` 重新生成，会把下面 3 处**改回旧值**：

| 舰船 id | 仓库里（`eve_ship_asset_index.gd`，含手工修正） | 本清单会生成 |
| --- | --- | --- |
| `executioner` | `"刽子手级"`（并带一段说明注释） | `"磨难级"` |
| `maller` / `arbitrator` | `["maller", 624, "Maller", "暴君级", …]` | `["arbitrator", 628, "Arbitrator", "暴君级", …]` |
| `cyclone` / `hurricane` | `cyclone=飓风级`、`hurricane=暴风级` | 两个中文名**互换** |

同时 `01_舰船数值全表.csv` 与 `scripts/data/eve_ship_table.gd` 之间也有一处不一致：

| 舰船 | 设计表 `01_舰船数值全表.csv` | 代码 `eve_ship_table.gd` |
| --- | --- | --- |
| `executioner` | 磨难级 | **刽子手级** |
| `arbitrator` / `maller` | `arbitrator`（暴君级） | **`maller`**（暴君级） |

**⇒ 在三处口径对齐之前，别直接跑 `_gen_ship_index.py` 覆盖产物**
（会把手工修正冲掉）。对齐方案需要作者拍板：以设计表为准去改代码，还是以代码为准去改设计表。
