# AI 操作游戏 —— 本地桥使用说明（2026-10-26）

让外部 AI（DSH 里的我 / 任何能连 TCP 的脚本）**像玩家一样**从开机画面起操作这一局：
看状态 → 决策 → 下手 → 截图核对，循环。

## 1. 启动

```powershell
# 从主菜单开机（AI 自己点进一局）
& 'C:\godot\Godot_v4.7.2-stable_win64_console.exe' --path 'F:\evezzq\eve自走棋918'
```

启动后控制台会打印：

```
[AI桥] 已监听 127.0.0.1:9081 · JSON 行协议 · 命令见 scripts/core/eve_ai_api.gd
```

## 2. 协议

`127.0.0.1:9081`，**一行一个 JSON**（`\n` 分隔），一问一答。

```jsonc
// 请求
{"id": 1, "cmd": "state"}
{"id": 2, "cmd": "start", "args": {"difficulty_index": 1}}
{"id": 3, "cmd": "deploy", "args": {"bench": 0, "row": 7, "col": 2}}

// 成功
{"id": 1, "ok": true, "data": { ... }}

// 失败（一定有 error 或 data.reason，不会只有 ok:false）
{"id": 2, "ok": false, "data": {"ok": false, "reason": "只能放在我方部署区（棋盘下 4 行）"}}
```

## 3. 命令按场景分三张表

桥会先看当前是哪个场景（`ai_kind()`），再把命令送到对应表。
**主菜单 / 片头 / 战斗**各自一套，跨场景发错命令会收到一份可用命令清单。

### 通用（任何场景）

| cmd | args | 作用 |
| --- | --- | --- |
| `ping` | — | 探活 |
| `info` | — | 游戏/引擎版本 + 当前场景种类 |
| `state` | — | **当前场景的快照**（各场景自己造） |
| `screenshot` | `name` | 抓一帧存 `user://ai_shots/<name>.png`，返回绝对路径 |
| `wait` | `seconds` | 等若干秒后回一帧快照（≤30） |
| `quit` | — | 退出游戏 |

### 主菜单（`scene: "menu"`）

| cmd | args | 作用 |
| --- | --- | --- |
| `start` | `difficulty_index` / `difficulty_id` | 开始一局（可先指定难度） |
| `continue` | — | 继续上一局（恢复存档，不进片头） |
| `select_mode` | `index` | 选左侧模式（父项 = 展开/收起） |
| `select_difficulty` | `index` | 选右侧难度卡（不开局） |
| `settings` | `on` | 设置窗开 / 关 |
| `replay_intro` | — | 回看片头 |
| `quit_game` | — | 退出 |
| `restart` | — | 语义统一为「开一局新的」 |
| `pause` | — | 语义统一为设置窗开关 |

快照字段：`modes` / `mode_index` / `content_id` / `difficulties` / `difficulty_index` /
`has_run` / `settings_open` / `toast`。

### 开场剧情（`scene: "intro"`）

| cmd | args | 作用 |
| --- | --- | --- |
| `next` | — | 下一句 |
| `skip_talk` | — | 跳过当前对白（不结束整段） |
| `finish` | — | **整段结束 ⇒ 进战斗**（AI 不用干等 40 秒） |
| `pause` | `on` | 暂停 / 继续 |
| `seek` | `t` | 拖到第 t 秒 |

### 战斗（`scene: "battle"`）

| cmd | args | 作用 |
| --- | --- | --- |
| `buy` | `index` | 买商店第 index 张卡（0~4） |
| `refresh` | — | 刷商店（2 ◆） |
| `levelup` | — | 买经验（4 ◆） |
| `shop_lock` | `on` | 锁/解锁商店 |
| `deploy` | `bench,row,col` | 备战席上场 |
| `move` | `field,row,col` | 场上换位 |
| `recall` | `field` | 撤回备战席 |
| `sell` | `source,index` | 出售（`bench` / `field`） |
| `stance` | `ship_id,stance` | 姿态 0~4（接近/保持/环绕/风筝/手动） |
| `start_battle` | — | 开战（客户端别名 `fight`） |
| `pause` | `on` | 暂停/继续 |
| `restart` | — | 重开一局 |
| `back_to_menu` | — | 回主菜单（别名 `menu`） |
| `fast_forward` | `seconds` | 快进战斗（调试） |
| `event_choose` | `id` | 事件节点四选一 |
| `event_ship` | `index` | 事件节点选船 |
| `result_next` / `result_end` | — | 结算页两个出口 |
| `salvage` | `index` | 打捞第 index 艘残骸 |
| `salvage_zero` | — | 放弃剩余残骸并推进 |
| `dialog_confirm` / `dialog_cancel` | — | 应答确认框（见下） |
| `camera` | `yaw,pitch,zoom,focus` | 相机（角度为度） |
| `frame` | `mode` | 取景：`battle` / `board` / `own` |
| `colors` | `artillery_core,artillery_edge,decal_mid,decal_high` | 运行时改特效配色 |
| `shell` / `markers` | `on` | 护盾壳 / 锚点调试小球可见性 |

#### 确认框（2026-10-26 补，踩过的坑）

残骸没捞完就点「继续」会弹「放弃打捞」二次确认。**弹着的时候其它指令全部石沉大海**
—— AI 看起来就是「卡在 RESOLVE 反复点继续不动」。

快照里的 `dialog` 字段：

```jsonc
{ "salvage_ask_open": true, "any_open": true }
```

处理顺序：**先看 `dialog.any_open`，再按 phase 分派**。

#### 战斗快照

| 字段 | 含义 |
| --- | --- |
| `phase` / `phase_name` | 0=PREP 1=BATTLE 2=RESOLVE 3=ENDING |
| `paused` | 是否暂停 |
| `node` | 节点号/总数/类型/时限 |
| `economy` | 星币 / 等级 / 经验 / 信标 / 利息 / 收入 / 战败预览 |
| `board` | 棋盘几何：11×11，**我方部署区 = 行 7~10**，隔离区 4~6，敌区 0~3 |
| `shop.offers` | 5 张卡（已瘦身：主键/费用/星级/阵营/职能/武器/防御/羁绊/攻击/三层HP/射程） |
| `bench` / `field` | 备战席 / 上场（含格子） |
| `synergies` | 当前羁绊 |
| `own` / `enemy` | 敌我全部船：id/键名/星级/存活/姿态/三层 HP/位置(米)/伤害/击杀 |
| `battle` | elapsed / tick / finished / winner_team / damage_multiplier |
| `timer_left` | 阶段顶条剩余秒数 |
| `ui` | 结算页 / 事件页 / 设置窗是否打开 |
| `dialog` | 确认框是否开着（**弹着时先应答它**） |
| `event` | 事件节点：四选一/选船两个子状态 + 可选项 |
| `salvage` | 残骸打捞信息 |

## 4. 命令行客户端

```powershell
$node = "C:\Users\Administrator\.dsh\dsh-runtimes\dsh-primary-runtime\dependencies\node\bin\node.exe"
$c = "$node 'F:\evezzq\eve自走棋918\tools\ai_client.mjs'"

# 从主菜单开局（AI 全程自己点）
& $c select_mode 2          # 任务关卡
& $c select_difficulty 1    # 普通
& $c start
& $c finish                 # 若进了片头，直接跳过
& $c buy 0
& $c deploy 0 7 5
& $c fight                  # 开战
& $c wait 12
& $c shot battle

& $c colors '{"artillery_core":[1,0.95,0.72,1],"artillery_edge":[1,0.34,0.08,1]}'
```

别名：`fight`→start_battle、`menu`→back_to_menu、`next`→result_next、
`shot`→screenshot、`ff`→fast_forward、`lock`→shop_lock。
⚠️ `start` **不**做别名 —— 它在主菜单是「开始一局」，战斗里开战请用 `fight`。

## 5. 实测：AI 全自主打完一整个任务关卡

```
node tools/ai_autoplay.mjs --nodes 15 --difficulty 0 --shots --verbose
```

一个启发式机器人（只走 AI 桥，不碰内部 API）从主菜单开局，**45 秒内打完 15 个节点**：

- 每节点：买船 → 上场 → 开战 → 快进 → 打捞 → 下一节点
- 事件节点 ×3：武器调校 / 结构加固（都要先选船）/ 紧急维修
- 确认框 ×7：残骸捞不起时「放弃并继续」
- 终态：节点 15、信标 94/100、等级 5、上场 7 艘
- 截图 `user://ai_shots/auto_node1..15.png`

```
menu → select_mode 2 → select_difficulty 1 → start
  → buy 0 → deploy 0 7 5 → fight → wait 12
```

- 难度真的传进去了：普通档敌方装甲 61.95（简单档 59）
- 开战后 `phase=BATTLE`、`elapsed=12.6s`、`damage_multiplier=1`
- 片头链路：`menu → replay_intro`（`scene:intro`，13 句）`→ finish` → 回战斗 PREP
- 截图 2048×1152 正常落盘
- `colors` 改色前后两张图差异像素 3.40% ⇒ 运行时调色已生效

## 6. 三条实现红线

1. **不另造第二份真相源**：AI 的每个动作都走玩家点击的同一条代码路径
   （HUD 信号 → 场景 handler → `EveRunState`）。规则只在 RunState 里判一次，
   AI 没有任何绕过判定的后门。
2. **拒绝必须有理由**：所有失败都带 `reason`，AI 才知道下一步该改什么。
3. **响应要瘦**：船表行有 50+ 字段，`_slim()` 会把它压成十几个决策相关项，
   否则一次 `state` 就能吃掉几十 KB 上下文。

## 7. 文件

| 文件 | 职责 |
| --- | --- |
| `scripts/core/eve_ai_bridge.gd` | autoload，TCP 9081 + 行协议 + 帧预算 |
| `scripts/core/eve_ai_api.gd` | 按场景路由 + 战斗快照 + 瘦身 + 截图 |
| `scripts/eve_main_menu.gd`（末尾） | 主菜单操作面：开始/继续/选模式/选难度/设置/片头 |
| `scripts/eve_intro_scene.gd`（末尾） | 片头操作面：下一句/跳过/整段结束/拖时间 |
| `scripts/eve_battle_scene.gd`（末尾） | 战斗操作面：买卖/布阵/流程/相机/调色 |
| `tools/ai_client.mjs` | Node 命令行客户端 |

## 8. 已知边界

- 单帧最多处理 8 条命令（`MAX_CMD_PER_FRAME`），AI 批量刷指令时不会卡死主线程。
- `stance` 直接写 `ship.stance`：HUD 的 `stance_changed` 信号**至今没有发射方**
  （UI 没接），所以没有「玩家路径」可委托。
- 斗地主 / 棋牌室 / 联机对战还没有操作面（`start` 会走到它们的 WIP 提示）。
- 截图是**整帧**，不做裁剪/标注；要局部细节让 AI 自己裁。
## 9. 难度扫荡 + 胜率报表

```powershell
$node = "C:\Users\Administrator\.dsh\dsh-runtimes\dsh-primary-runtime\dependencies\node\bin\node.exe"

# 四个难度各打 1 轮，打完一轮回主菜单换下一个
& $node 'F:\evezzq\eve自走棋918\tools\ai_sweep.mjs' --rounds 1 --verbose

# 只打某一个难度，打 3 轮
& $node 'F:\evezzq\eve自走棋918\tools\ai_sweep.mjs' --difficulty hard --rounds 3
```

| 参数 | 含义 |
| --- | --- |
| `--rounds N` | 每个难度打几轮（默认 1） |
| `--difficulty X` | 只打某个难度（id / 中文名 / 下标） |
| `--nodes N` | 节点上限（默认 15） |
| `--verbose` | 打印每一手买/上场/打捞 |
| `--no-shots` | 不截图 |

产物（**相对脚本自身**，不受 cwd 影响）：

- `tools/ai_runs/runs.csv` —— 逐局原始记录
- `tools/ai_runs/report.md` —— 按难度汇总的胜率报表

### 一轮实测（2026-10-26，四难度各 1 轮）

| 难度 | 局数 | 通关 | 撤离 | 胜率 | 平均节点 | 平均信标 | 平均等级 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 简单 | 1 | 1 | 0 | 91.7% | 15.0 | 100.0 | 5.0 |
| 普通 | 1 | 1 | 0 | 50.0% | 15.0 | 54.0 | 5.0 |
| 困难 | 1 | 0 | 1 | 11.1% | 11.0 | 0.0 | 5.0 |
| 炼狱 | 1 | 0 | 1 | 11.1% | 11.0 | 0.0 | 5.0 |

**总体战斗胜率 45.2%**（胜 19 / 负 23，按单节点战斗计）。
难度递增是真的：节点 1 首舰装甲 59 → 62 → 68 → 74。

### 三个实测踩出来的坑

1. **胜负被重复计数**：`sim.finished` 之后 phase 还会停留几帧，
   每轮都计就把胜率吹起来了（实测同一节点被计 3 次）。
   改成「只在 false → true 的那一帧计一次」。
2. **每轮都发 fast_forward**：sim 结束后它是空转，白占主线程。
   改成「一场战斗只快进一次，然后轮询等 phase 翻」。
3. **报表写飞了**：输出目录按 cwd 解析，从仓库根跑一次就写到
   `F:\evezzq\tools\ai_runs`。改成相对 `import.meta.url`。

另外：**通关不能无条件记**。最后一节点打输了也是「到 15」，
所以兜底判定要看最后一场战斗的胜负；能读到真 ENDING 时以它为准。
## 10. 演示模式（给人看）

```powershell
& $node 'F:\evezzq\eve自走棋918\tools\ai_sweep.mjs' --demo
& $node 'F:\evezzq\eve自走棋918\tools\ai_sweep.mjs' --demo --demo-delay 2500
```

演示模式下每一步都带序号和理由，步间停一拍（默认 1400ms，可调）：

```
01. ── 简单 · 第 1 轮 ──   ← 共 1 轮
02. 主菜单选难度 → 「简单」   ← 难度下标 0
03. 进入节点 1/15   ← 敌 2 艘 · 时限 45s
04. 买商店第 0 张：小鹰级   ← ◆1 · 剩 ◆4
05. 买商店第 1 张：伐木者级   ← ◆1 · 剩 ◆3
07. 备战席 0 上场 → 第7行第0列   ← 我方部署区 = 行 7~10 · 上限 3 艘
09. 开战   ← 上场 2 艘 · 对 2 艘
10. 快进战斗 51 秒   ← 剩余时限 45s
11. 节点 1 战斗结束：胜   ← 信标 100 · 累计 1胜0负
12. 打捞 伐木者级   ← −◆1
16. 确认「放弃打捞」并继续   ← 残骸捞不起了（◆0）
```

## 11. 通关率口径

**通关率 = 打到 15 节点的局数 / 总局数**（用户 2026-10-26 定案）。
单节点战斗胜负另列一栏，只是参考，不是 headline。

## 12. 查过的问题：困难和炼狱成绩一样

扫荡报表里两档成绩一模一样，怀疑是 bug。用
`tools/probe_difficulty_comps.tscn` 直接读数据表，结论是**设计如此**：

| | 困难 | 炼狱 |
| --- | --- | --- |
| `scale` | 1.15 | 1.25 |
| `ai_level` | 2 | 3 |
| `key_mechanic` | 无 | `armor_pierce` |
| 节点 15 编组 | `overlord_escort×9` | `boss_overlord×6` |
| 节点 1~14 编组 | **与炼狱完全相同** | **与困难完全相同** |
| `loss_curve` 末段 | 34 | 38 |

两档的 `comp_overrides` 只在**节点 15** 不同（其余 3/5/6/7/8/9/11 逐条相同）。
所以死在前中段的局，两档体验几乎一致——只有 scale 1.15/1.25
（约 +8.7% 敌方 HP）和略狠的 loss_curve 能区分。

要真区分两档，得打到节点 15 的 BOSS 关。
