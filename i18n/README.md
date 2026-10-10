# i18n —— 文案与翻译

> ## ⏸⏸ 冻结中（2026-10-11 用户定调：**英文版现在时机不成熟，先不做**）
>
> **这一整块暂停推进。** 基础设施已经铺好、UI 面也迁了一部分，但**不再继续**，
> 并且**不对外提供英文**——玩家切过去只会看到"一半英文一半中文"的半成品。
>
> 冻结范围（⛔ 别再往里加东西，除非用户明确解冻）：
> - ⛔ 不再迁移新的 UI 面中文（`eve_run_state` / `eve_trait_table` 效果文本 /
>   开场剧情 / 事件表 / 背景库 `display_name` … 全部停在这里）。
> - ⛔ 不再往 `strings.csv` 加新 key；⛔ 不再跑 `add_i18n_*_rows.py`。
> - ⛔ **不交付英文**：默认 locale 恒 `zh_CN`；设置窗**不建**「语言」行 ——
>   开关是 `EveText.LANGUAGE_ENABLED`（当前 `false`，**唯一真源**）。
>   ⚠️ 隐藏不只是"不画这一行"：`apply_saved()` 还会**忽略存档里已存的语言**并强制 `zh_CN`，
>   否则之前手滑切过 English 的玩家一进游戏仍是半成品英文。
> - ✅ 已迁的部分**保留不动**：它们不改变中文版任何行为（默认 locale = zh_CN ⇒
>   取词原样返回中文，逐字不变），回滚反而会引入风险。
> - ✅ `verify_i18n` 继续跑（它同时是"中文逐字不变"的护栏）；
>   它里面有**三条冻结期断言**（开关仍是 false / 语言行不存在 / 存档语言被忽略）。
>
> **解冻时怎么接**：
> 1. 先补**英文文案本身**（现在 CSV 里大量 en 列是占位/直译，还没过审）；
> 2. 再迁剩下的面（顺序建议：羁绊效果文本 → 事件/节点表 → 开场剧情 → 提示文案）；
> 3. 全程用 `tools/pipeline/scan_ui_cn_left.py` 看剩余量；
> 4. 最后 **`EveText.LANGUAGE_ENABLED` 改成 `true`** —— 「语言」行会自己回来，
>    代码一直在、没删。⛔ 同时把 `verify_i18n` 的 ③ 段改回正向判据
>    （行要存在 / 存档语言要生效）。
>
> 冻结时的存量：`strings.csv` 465 行 · `verify_i18n` 77 条 ·
> 已迁面 = 术语 70 + 主菜单 97 + 设置窗 43 + 结算页 33 + 商店 23 + 档案窗 21 + 牌桌 90 + 战斗面 59。
>
> ### 📢 给 fork / 二次开发的同学（**这不是半成品坑，是有意冻结**）
> 如果你 clone 下来发现「有套 i18n 却切不了英文 / 一半界面能翻一半不能」——**这是故意的**，
> 不是我们没做完就丢给你。原因与现状都写在上面：中文是唯一交付语言，
> 英文的**文案本身还没过审**，提前开放只会让所有人看到中英混杂。
> 想自己加语言，按上面「解冻时怎么接」四步走即可；只翻一个常量就能先看到界面上的入口。
> 也欢迎直接 PR —— 英文文案（CSV 的 `en` 列）是最容易、也最需要母语者帮忙的部分。

> ★ 2026-10-10 立项：用户定调「**以后肯定要出英文版 —— EVE 欧服玩家很多**」。
> ⏸ 2026-10-11 用户按下：**先不做**。立项背景仍成立，只是时机未到。

## 一句话
**玩家可见文案的唯一真相源 = `i18n/strings.csv`；代码里一律经 `EveText.t()` 取词。**

## 文件
| 文件 | 说明 |
|---|---|
| `i18n/strings.csv` | **唯一手工维护**的翻译源。首行 `keys,en,zh_CN`，之后每行一条。<br>⚠️ 分两段：**术语段**（`SHIP.*` / `CLASS.*` / `FACTION.*` / `WEAPON.*` / `DEFENSE.*` / `ROLE.*`）= 生成；其余 = 手写。 |
| `i18n/strings.<locale>.translation` | Godot 从 CSV **自动生成**（`--import`），条目登在 `project.godot` 的 `internationalization/locale/translations`。⛔ 别手改。 |
| `scripts/core/eve_text.gd` | 取词入口（`T.t()` / `T.set_locale()` / `T.lookup()`），见其顶注。 |
| `scripts/core/eve_terms.gd` | **术语取词**（舰船 / 吨位 / 势力 / 武器 / 防御 / 定位 / 羁绊名）—— 见下方「术语段」。 |
| `tools/pipeline/gen_i18n_terms.py` | 术语段的生成器（从两张表生成，可反复重跑）。 |
| `tools/verify_i18n.{gd,tscn}` | 自检：CSV ↔ 翻译资源逐条对拍 + **术语三方对拍** + 试点接线。 |

## 术语段：舰船名 / 羁绊名**必须用 EVE 官方译名**

> ★ 2026-10-10 用户定调：「舰船、羁绊应该都可以参考 EVE 的官方翻译，或者说**一定要遵循
> EVE 官方的翻译，意译在这个时候是绝对不行的**」。

**权威出处已经在仓库里**，⛔ 不要人肉抄：

| | 来源 | 为什么可信 |
|---|---|---|
| 英文名 | `EveShipAssetIndex.ROWS` 第 3 列 `name_en` | 机生成：ESI `/universe/ids/` 拿 typeID → 官方英文名。**人改不动 ⇒ 意译无处藏身** |
| 中文名 | `EveShipTable.ROWS` 第 2 列 | 设计侧权威表，`verify_data_source` 已与交接 CSV 逐列对拍 |

规矩：
- ⛔ **别手改 `strings.csv` 的术语行** —— 改了下次生成被覆盖，且 `verify_i18n` 直接红。
  要改名 ⇒ 改上面那两张表 ⇒ 重跑生成器：
  ```bash
  python tools/pipeline/gen_i18n_terms.py    # 然后 --import 重导
  ```
- 代码里取词一律走 `EveTerms`（`TERMS.ship(...)` / `TERMS.weapon(...)` / `TERMS.trait_member(...)`），
  ⛔ 不要在别处手写 `T.t("SHIP." + key)`（漏翻会露出 key）。
- ★★ **中文仍是逻辑主键**：`EveTraitTable.EFFECTS` / `count()` / `ship_has()`、
  `EveShip.weapon_type` 全都按中文查表 ⇒ **只换显示名，不换逻辑键**。
  `verify_i18n` 专门钉了这条（en 下 `weapon_type` 必须还是「导弹」）。

**⚠️ 已发生过的事故（这条规矩的由来）**：交接的源 CSV 把 `Cyclone` / `Hurricane`
的中文名**对调**了。而 EVE 官方恰恰是 **`Cyclone = 飓风级` / `Hurricane = 暴风级`**
（与字面意思相反）—— 工程里的舰船表 + 资产索引（都带 typeID）才是对的。
证据：`eve.huijiwiki.com/wiki/Data:Invtype/24702.json`（Hurricane → `typeName_zh: 暴风级`）、
`everef.net/zh/types/16231`（Cyclone → 飓风级）。**只靠人眼永远发现不了，三方对拍一跑就红。**

**资产索引**：里面除舰船名之外的中文（`dims` / 包围盒 / 立绘 / 模型 …）属**技术描述**，
按**计算机技术用语**写；它们不进 i18n（非玩家可见，都是注释）。


## 加一条文案（三步）
> ⏸ **冻结中** —— 这一步现在不做。下面留着，解冻后照抄即可。
1. 在 `strings.csv` 里加一行：`MY_KEY,English text,中文原文` —— **两列都要填**。
   ⚠️ 只填一列 = 那一列回落中文（英文版会"露馅"）；`verify_i18n` 会逐条报出来。
2. 代码里：`const T := preload("res://scripts/core/eve_text.gd")` 然后
   `label.text = T.t(&"MY_KEY", "中文原文")` —— 第二参是**中文源文**（兜底 + 活文档，
   必须与 CSV 的 zh_CN 列逐字一致，自检会对拍）。
3. 跑 `GODOT_BIN=... bash tools/run_verifies.sh`（或单跑 `verify_i18n`）。
   ⚠️ **改完 CSV 必须让 Godot 重新导入**（编辑器里保存即触发；命令行 `--import`）。
   若发现"新加的 key 取不到"，删掉 `i18n/strings.*.translation` 与
   `.godot/imported/strings.csv-*.md5` 再 `--import`（实测踩过：改了 CSV 但没重导）。

## 三条硬规矩
- ⛔ **逻辑不许挂在文案上**（工程红线）：判断分支一律比 id / 枚举，不比中文字符串。
  i18n 只是**显示层**。
- ⛔ **窗口的 `layout_key` 不许回落到 `window_title`** —— 标题会被 i18n 化，
  回落到它等于「切一次语言 = 布局存档换键 = 窗口布局丢失」。
  （`eve_settings` 已按档案推导 `"<profile>_settings"`；其余窗若将来 i18n 化标题，同样要显式给键。）
- ⚠️ **`const T` 在 `EveWindow` 里必须叫 `TEXT`** —— 子类 `eve_settings.gd` 自己也声明了
  `const T`，基类/子类成员同名会让**基类**编译失败
  （`The member "T" already exists in parent class EveWindow`）。这就是工程那条红线：
  「给基类加成员前先 grep 一遍所有子类」。

## 进度（⏸ 2026-10-11 冻结在下面这一行）
- ⏸⏸ **英文版按下不做**（用户定调「现在时机不成熟」）。已迁的面保留、不再新增。
- ✅ 基础设施 + 试点（设置窗标题 / 重置按钮 / 通用 ✕ tooltip）
- ⏸ 设置窗「语言」行（简中 / English）：`_pick_language` = 立即 set_locale + 落盘 +
  **重载当前场景** —— ⏸ 2026-10-11 **已隐藏**（`EveText.LANGUAGE_ENABLED = false`），
  代码保留在 `if T.LANGUAGE_ENABLED:` 里，解冻翻常量即可，⛔ 别把它删了。
  （重载是唯一能把整屏换掉且不留中英混杂的做法。）
  ⚠️ 战场上重载前会置 `RUN_STORE.resume_requested` —— 否则 `_ready` 走 `start_run()`
  从第 1 节点重开；代价是本节点准备阶段的买/刷新会丢（存档点在 `begin_prep` 末尾）。
  ⚠️ 这一行**刻意压成单行**（标签与按钮同排）：设置窗内容真机约 900、上界是视口 92%
  （1080 屏 = 993）。实测新增约 **28px** ⇒ 窗高约 970，余量约 23px。
  ⛔ 再往里加行之前**先量**，或者先瘦身别处。
- ✅ 三个场景 `_ready` **第一句** `T.apply_saved()`（必须早于任何 UI 构建）。
- ✅ **术语段（70 条）**：52 艘舰船 + 吨位 5 + 势力 4 + 武器 4 + 防御 2 + 定位 3，
  全部**按 id 取词**；接线到 `EveShipDatabase`（`name`）/ `EveShip`
  （`faction_name()` / `class_name_cn()` / `weapon_label()` / `defense_label()` / `role_label()`）/
  `EveTierIcon.label()` / `EveTraitTable.members()[].label` + `group_label()` /
  商店卡 / 档案窗 / 舰队构成窗。见上方「术语段」。
  ⚠️ 默认 locale 是 zh_CN ⇒ 取词原样返回中文 ⇒ **既有断言与截图逐字不变**
  （`verify_run 592/0` 未动）。
- ✅ **UI 面已迁（冻结时的存量）**：主菜单 97 · 牌桌 90 · 设置窗 43 · 结算页 33 ·
  战斗面 59（HUD / 命令条 / 日志 / prep / battle）· 商店 23 · 档案窗 21。
  ⚠️ 面上残留的中文扫出来多是**数据表源文**（`EXTRA_MODES` / `BACKGROUNDS` /
  `end_reason()` 返回值），按既定口径**保留不动**（渲染时才取词）。
- ⏸ **未迁（冻结时停在这里，解冻后按此顺序继续）**：
  1. 羁绊**效果文本**（`EveTraitTable.EFFECTS` 的 `text` / `pending` —— 本作自有加成描述，非 EVE 术语）
  2. `eve_run_state` 提示文案 86 · 事件/节点表 40 · 开场剧情 32 · `battle_scene` 30 · `ddz_game` 23
  3. 背景库 `display_name` 21（「加达里 C06 星云」是**玩家可见**的）
  4. **英文文案本身**（CSV 的 en 列大多是占位/直译，**还没过审** —— 这是解冻的第一件事）
  5. `EveAudio` / 字体等本地化细节。
