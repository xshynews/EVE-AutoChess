# data —— 设计侧数据源

> 这里放的是**原始数据**（设计稿快照）。游戏里真正读的是 `scripts/data/*.gd`，
> 两边的关系见下（⚠️ 目前是**人工搬运**，靠 `tools/verify_data_source.tscn` 防漂）。

## source_csv/ —— 「重启交接-2026-09-17」附件（原样留档）

| 文件 | 落地到 | 说明 |
|---|---|---|
| `01_舰船数值全表.csv` | `scripts/data/eve_ship_table.gd` | 52 艘 = 4 派系 × 13；列序与 `.gd` 的 `ROWS` **完全一致**（逐列对照） |
| `02_羁绊系统表.csv` | `scripts/data/eve_trait_table.gd` | 势力阈值 [2,4] / 武器·防御 [3,6]（`verify_run` 有一条专门钉这个） |
| `03_敌人编组表.csv` | `scripts/data/eve_enemy_comps.gd` | 10 个编组：id / 站位模板 / 艘数 / 编成 |
| `04_节点表_遥望边境.csv` | `scripts/data/eve_node_table.gd` | 15 个节点（含 4/10/14 事件节点） |
| `05_按钮与交互清单.csv` | （设计参考，未直接驱动代码） | 交互稿 |
| `06_环境与工具链.md` | （工具链说明） | 本机环境与工具链原始记录 |

## intro/

| 文件 | 落地到 | 说明 |
|---|---|---|
| `时间轴.csv` | `scripts/data/eve_intro_script.gd` | 开场剧情台词时间码（**同源**；那份还给"离线出透明视频"用） |

## ⚠️ 两条必须知道的事

1. **表是人工搬的，不是生成的。** 改数值时 CSV 与 `.gd` **两边都要改**，
   否则游戏里和设计稿会悄悄分家。
   ⇒ `tools/verify_data_source.tscn` 会**逐列对拍**（以 CSV 为真值），
     漂了立刻红。**已登记的有意分歧**（换船 / 正名）在白名单里，理由写在代码注释。

2. **`装甲/结构` 是合并列。** CSV 只有一个数（如 `90`），拆分成 `armor` / `hull`
   的规则在 `scripts/data/eve_ship_database.gd`，⛔ 别在别处再拆一遍。

## 📌 建议（尚未做）

写一个 `tools/pipeline/gen_ship_table.py`，把 `01_舰船数值全表.csv` **自动生成**
`eve_ship_table.gd`，从此只有 CSV 一处真值。做完后 `verify_data_source` 的对拍
就可以降级成"生成结果自检"，而不必再靠人工同步。
