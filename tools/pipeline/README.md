# tools/pipeline —— 数据与美术资产生成脚本（离线，Python）

这些脚本不在游戏里运行，也不参与导出。它们记录了资产是怎么生成的：舰船表、朝向标定、
牌面、天空盒、立绘都可以用它们重新生成。

## 路径配置

脚本里没有硬编码的绝对路径，所有路径由 [`_paths.py`](./_paths.py) 解析。
优先级：环境变量 > 本机配置 `paths.local.json` > 仓库内默认值。

本机配置：把 [`paths.local.example.json`](./paths.local.example.json) 复制为
`paths.local.json`（已在 .gitignore 中），只保留需要改的项。

| 环境变量 | 配置文件键 | 用途 | 默认值 |
|---|---|---|---|
| `EVE_PROJECT_ROOT` | `project_root` | Godot 工程根 | 仓库根 |
| `EVE_WORK_DIR` | `work_dir` | 工作目录（中间产物） | `<仓库根>/.pipeline_work` |
| `EVE_CLIENT_DIR` | `client_dir` | EVE 客户端 `SharedCache` | 未设置 |
| `EVE_CARD_SRC` | `card_src` | 卡牌正面原图 | `<仓库根>/.incoming/cards` |
| `EVE_EXPORT_DIR` | `export_dir` | 发布包输出目录 | `<仓库根>/build` |
| `EVE_GODOT_BIN` | `godot_bin` | Godot 可执行文件 | 在 `PATH` 中查找 |
| `EVE_TEXCONV` | `texconv` | `texconv.exe`（DirectXTex，不入库） | `<工作目录>/_tools/texconv.exe`，再查 `PATH` |
| `EVE_PYTHON` | `python` | 子进程使用的解释器 | 当前解释器 |
| `EVE_GODOT_USER_NAME` | `godot_user_name` | `user://` 目录名 | 自动探测 |

运行 `python tools/pipeline/_paths.py` 可以打印当前解析结果。

部分脚本依赖本机 EVE 客户端（音频、星云、官方渲染图）与 `texconv.exe`。
这两类资源因版权或第三方授权不能随仓库分发，需要自备。

3D 建模的清单与核心脚本已随仓库提供：`_manifest/`（清单，含已知偏差说明）、
[`eve_ship_build.py`](./eve_ship_build.py)、[`blender_project.py`](./blender_project.py)。

## 数据表 / 索引

| 脚本 | 作用 | 输入 → 输出 |
|---|---|---|
| `_gen_ship_table.py` | **设计表 → 代码**：校验（默认）/ 生成（`--write`）舰船表 | `data/source_csv/01_舰船数值全表.csv` ↔ `scripts/data/eve_ship_table.gd` |
| `_gen_ship_index.py` | 生成 Godot 侧资产索引 | `_manifest/_ship_manifest.json` + 建模结果 → `scripts/data/eve_ship_asset_index.gd` |
| `_build_all_ships.py` | 批量建模 52 艘 | EVE 客户端资源 → `<工作目录>/_ship3d/<id>/` |
| `eve_ship_build.py` | **核心**：单个 typeID → OBJ + 官方贴图（一条命令） | gamemodels3d 官方资产 → `<out>/<Model>.obj` |
| `blender_project.py` | 用 Blender 打开构建结果做人工复核 | 上述 OBJ |
| `_paths.py` | 路径解析（环境变量 / 本机配置可覆盖） | — |

> ✅ 索引生成器**可复现**：用仓库里的清单重跑 `_gen_ship_index.py`，产物与
> `scripts/data/eve_ship_asset_index.gd` **逐字节一致**（CI 每次提交都会验这条）。

## 朝向标定（`eve_ship_yaw.gd` 的来源）

| 脚本 | 作用 |
|---|---|
| `_rot8.py` | 「长轴竖直」前提下的 8 种正交变体（舰艏朝上/下 × 绕长轴 4 个 roll） |
| `_ba4.py` | 「两端上色」朝向判定卡（把歧义从肉眼读图里移除） |
| `nozzle_axis.py` | 用**有向喷口法线**反解舰艏轴真实偏角 δ |
| `sym_audit.py` | 用**镜像对称**独立测每艘船的偏斜（不靠自发光、不靠表） |
| `pose_sheet.py` | 判「这艘船在游戏里是不是倒着飞」，出人眼可判的两端实拍 |
| `proof_pair.py` | 「现在的游戏姿态」vs「按 `_e` 判据修正后的姿态」并排对照 |
| `multi_e_test.py` | 多套 `_e` 的船：逐张试，取「喷口最聚拢」的那套 |
| `_apply_remap47.py` | 把重算出的 52 条 spec 落盘进 `eve_ship_yaw.gd` 的 `AXIS_REMAP` |
| `_apply_up48.py` | 把「高度轴 ≠ up 轴」的船的 up 改成高度轴（最薄轴） |

## 美术资产

| 脚本 | 作用 | 产出 |
|---|---|---|
| `fetch_official.py` | 从 EVE 官方图片 CDN 拉全舰船 1024 渲染图 | `assets/ships/…` |
| `cut_models.py` | 抠图库（u2net / isnet / silueta） | — |
| `off_cut_all.py` | 全量抠图：官方图 → 透明底立绘 | `assets/portraits/…` |
| `tier_icons.py` | 吨位几何符号（超采样预烘） | 吨位图标贴图 |
| `card_face_pipeline.py` | 斗地主牌面批处理（角标归一化） | `assets/cards/card_<id>.png` |
| `eve_neb.py` | 官方星云立方体（BC6H）→ 2:1 等距柱状天空盒 | `assets/backgrounds/*-4096.png` |
| `eve_audio_index.py` | 解析 `resfileindex.txt`，建音频资源映射 | 音频解包索引 |

## ⚠️ 已知缺口

- `eve_background_library.gd` 注释里提到的 `_eve_neb.py` / `_eve_neb_gallery.py` /
  `_eve_export_assets.py` **已不在磁盘上**（实际脚本是 `eve_neb.py`）。
- `assets/audio/music/*.ogg` 的解包链在**技能** `eve-audio-unpack` 里，本目录只留了索引脚本。
