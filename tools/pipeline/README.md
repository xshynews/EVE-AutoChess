# tools/pipeline —— 数据与美术资产生成脚本（离线，Python）

> ⚠️ **这些脚本不在游戏里跑**，也不参与导出。它们是"资产是怎么来的"的留档 ——
> 没有它们，别人 clone 仓库后**没法重新生成**舰船表、朝向标定、牌面、天空盒、立绘。
>
> ⚠️ 脚本里仍写着**作者本机的绝对路径**（EVE 客户端缓存、`C:/godot/_export/` 工作目录等）。
> 移植到别的机器时改脚本顶部的路径常量即可；各脚本开头都写了自己的输入/输出。

## 数据表 / 索引

| 脚本 | 作用 | 输入 → 输出 |
|---|---|---|
| `_gen_ship_index.py` | 生成 Godot 侧资产索引 | `_ship_manifest.json` + 建模结果 → `scripts/data/eve_ship_asset_index.gd` |
| `_build_all_ships.py` | 批量建模 52 艘 | EVE 客户端资源 → `_ship3d/<id>/` |

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
