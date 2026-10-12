# tools/pipeline —— 数据与美术资产生成脚本（离线，Python）

> ⚠️ **这些脚本不在游戏里跑**，也不参与导出。它们是"资产是怎么来的"的留档 ——
> 没有它们，别人 clone 仓库后**没法重新生成**舰船表、朝向标定、牌面、天空盒、立绘。
>
> ✅ **2026-10-12：路径已全部外置** —— 脚本里**不再有**任何硬编码的绝对路径。
> 所有路径由 [`_paths.py`](./_paths.py) 解析，**每一项都能用环境变量覆盖**：
>
> | 环境变量 | 用途 | 默认（本机没有就落到仓库内） |
> |---|---|---|
> | `EVE_PROJECT_ROOT` | Godot 工程根 | 本文件上溯两级（= 仓库根） |
> | `EVE_WORK_DIR` | 工作目录（中间产物） | 旧 `C:\godot\_export`（存在时）否则 `<仓库根>/.pipeline_work` |
> | `EVE_CLIENT_DIR` | EVE 客户端 `SharedCache` | 旧 `D:/EVE/SharedCache`（存在时）否则未设置 |
> | `EVE_CARD_SRC` | 卡牌正面原图 | 旧 `F:/EVE自走棋/牌面/牌面`（存在时）否则 `<仓库根>/.incoming/cards` |
> | `EVE_GODOT_BIN` | Godot 可执行文件 | `C:/godot/Godot_v4.7.2-stable_win64_console.exe` 等 |
> | `EVE_TEXCONV` | `texconv.exe`（DirectXTex，**不入库**） | `<工作目录>/_tools/texconv.exe` → `PATH` |
> | `EVE_PYTHON` | 子进程用的解释器 | 当前解释器 |
>
> 先跑 `python tools/pipeline/_paths.py` 可以打印解析结果自查。
>
> ⚠️ 少数脚本依赖**本机 EVE 客户端**（音频 / 星云 / 官方渲染图）与 `texconv.exe`
> —— 这两类原始资源**不能随仓库分发**（版权 / 第三方二进制），需要自备。
>
> ⚠️ 3D 建模的清单与核心脚本已随仓库提供：`_manifest/`（清单，含**已知偏差说明**）
> + [`eve_ship_build.py`](./eve_ship_build.py) + [`blender_project.py`](./blender_project.py)。

## 数据表 / 索引

| 脚本 | 作用 | 输入 → 输出 |
|---|---|---|
| `_gen_ship_index.py` | 生成 Godot 侧资产索引 | `_manifest/_ship_manifest.json` + 建模结果 → `scripts/data/eve_ship_asset_index.gd` |
| `_build_all_ships.py` | 批量建模 52 艘 | EVE 客户端资源 → `<工作目录>/_ship3d/<id>/` |
| `eve_ship_build.py` | **核心**：单个 typeID → OBJ + 官方贴图（一条命令） | gamemodels3d 官方资产 → `<out>/<Model>.obj` |
| `blender_project.py` | 用 Blender 打开构建结果做人工复核 | 上述 OBJ |
| `_paths.py` | **路径唯一真源**（环境变量可覆盖） | — |

> ⚠️ 重新生成索引前先读 [`_manifest/README.md`](./_manifest/README.md)：清单与仓库里的
> `eve_ship_asset_index.gd` 有 **3 处已知偏差**，直接跑会把手工修正冲掉。

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
