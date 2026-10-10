# ⏸⏸ 冻结（2026-10-11 用户定调：英文版现在时机不成熟，先不做）。
# ⛔ 解冻前不要跑这个脚本 —— 它往 i18n/strings.csv 追加 key，属于「继续做英文版」。
#    解冻顺序：先补英文文案本身 → 再迁剩余 UI 面 → 最后开放设置窗「语言」行。
#    详见 i18n/README.md 顶部。
# -*- coding: utf-8 -*-
"""一次性：把战斗核心面（HUD / 命令条 / 战斗日志 / prep·battle 阶段）的文案追加进
i18n/strings.csv。

⛔ 幂等：已存在的 key 跳过（绝不覆盖手写行）。
"""
import csv
import io
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CSV_PATH = os.path.join(ROOT, "i18n", "strings.csv")

ROWS = [
    # ── HUD ────────────────────────────────────────────────────
    ("HUD_TRAITS", "Traits", "羁绊"),
    ("HUD_PAUSED", "‖ Paused", "‖ 已暂停"),
    ("HUD_PAUSED_SUB", "Run frozen · controls locked", "对局已冻结 · 操作已锁定"),
    ("HUD_RESUME", "▶ Resume", "▶ 继续对局"),
    # ── 战斗日志：分类前缀（key 由 `&"economy"` 这类 ASCII id 拼出）──
    ("LOG_TITLE", "Combat Log", "战斗日志"),
    ("LOG_CAT_ECONOMY", "Report", "结算"),
    ("LOG_CAT_LOOT", "Loot", "拾取"),
    ("LOG_CAT_EQUIP", "Equip", "装备"),
    ("LOG_CAT_SALVAGE", "Salvage", "打捞"),
    ("LOG_CAT_HINT", "Hint", "提示"),
    ("LOG_CAT_BUY", "Buy", "购买"),
    ("LOG_CAT_DEPLOY", "Deploy", "部署"),
    ("LOG_CAT_SELL", "Sell", "出售"),
    ("LOG_CAT_SYSTEM", "System", "系统"),
    ("LOG_CAT_DAMAGE", "Damage", "损伤"),
    ("LOG_CAT_BREAK", "Layer Broken", "破层"),
    ("LOG_CAT_FIRE", "Fire", "射击"),
    ("LOG_CAT_REPAIR", "Logistics", "后勤"),
    # ── 命令条 ─────────────────────────────────────────────────
    ("BAR_TITLE", "Fleet Command", "舰队指挥"),
    ("BAR_STAGE_DEFAULT", "Skirmish", "遭遇战"),
    ("BAR_NODE", "Node %d", "节点 %d"),
    ("BAR_BEACON", "Beacon", "信标"),
    ("BAR_PHASE_PREP", "Prep", "准备"),
    ("BAR_PHASE_BATTLE", "Combat", "交战"),
    ("BAR_PHASE_RESOLVE", "Report", "结算"),
    ("BAR_LOSS", "Loss −%d", "战败 −%d"),
    ("BAR_START", "✦ Engage", "✦ 开战"),
    ("BAR_SETTINGS_TIP", "Settings (WIP: skybox / display mode)",
     "设置（待接入：天空盒切换 / 显示模式）"),
    # ── 准备阶段 / 事件四选一 ──────────────────────────────────
    ("PREP_TAG_FLEET", "Fleet", "舰队"),
    ("PREP_SHIP_STAT", "★%d · Class %d\nATK %d · Hull %d", "★%d · 吨位 %d\nATK %d · 结构 %d"),
    ("PREP_AUG_STAGE", "%s · Choose Augment", "%s · 选择增益"),
    ("PREP_AUG_BTN", "Choose Augment", "选择增益"),
    ("PREP_NODE_LINE", "Node %d／%d · %s · %s", "节点 %d／%d · %s · %s"),
    ("PREP_AUG_HINT", "Pick 1 of 4 augments — node %s shares this set, "
     "already taken ones cannot be picked again",
     "四条增益里选一条 —— 节点 %s 共用这一套，已获取的不能再选"),
    ("PREP_PICK_ONE", "Node %d · pick 1 of %d", "节点 %d · %d 选 1"),
    ("PREP_NO_SHIP", "No ships at all — 「%s」needs one, pick another",
     "一艘船都没有 ——「%s」要指定一艘船，先换一条"),
    ("PREP_PICK_SHIP", "Pick 1 ship — permanent for this run",
     "选 1 艘船 —— 本局永久生效"),
    ("PREP_NODE_NAME", "Node %d · %s", "节点 %d · %s"),
    ("PREP_AUG_FAIL", "This augment did not apply (already taken, or no ship "
     "picked) — pick another", "这条增益没生效（已获取过，或没选到船）—— 换一条"),
    ("PREP_RUN_OVER", "Run Over", "本局结束"),
    ("PREP_AGAIN", "↻ Play Again", "↻ 再来一局"),
    # ── 战斗阶段 ───────────────────────────────────────────────
    ("BATTLE_NO_DEPLOY", "No ships on the field — drag one from the bench",
     "场上一艘船都没有 —— 从备战席拖一艘到棋盘上"),
    ("BATTLE_NO_SHIP", "No ships at all — buy one in the shop first, then drag "
     "it from the bench to the board",
     "一艘船都没有 —— 先在商店买一艘，再从备战席拖到棋盘上"),
    ("BATTLE_ONGOING", "In Combat", "交战中"),
    ("BATTLE_STAGE", "%s · In Combat", "%s · 交战"),
    ("BATTLE_START", "Engage: %d of ours vs %d of theirs · fight until one side "
     "is wiped (damage ramps up after %ds)",
     "开战：我方 %d 艘 vs 敌方 %d 艘 · 打到一方全灭为止（%ds 后火力渐增）"),
    ("BATTLE_ESCALATE", "Damage ramping up — incoming damage grows until one "
     "side is destroyed or the timer runs out",
     "火力渐增 —— 伤害开始放大，直到一方被击毁或时限归零"),
    ("BATTLE_RESULT", "Report", "结算"),
    ("BATTLE_RESULTING", "Reporting…", "结算中…"),
    ("BATTLE_DRAW", "Draw", "平局"),
    ("BATTLE_WIN", "Interception Successful", "拦截成功"),
    ("BATTLE_LOSE", "Interception Failed", "拦截失败"),
    ("BATTLE_LOG", "%s（%s）· ours alive %d／%d · beacon −%d (%d left)",
     "%s（%s）· 我方存活 %d／%d · 信标 −%d（剩 %d）"),
    ("BATTLE_FORFEIT_NONE", "Prep time over — no ship deployed, this node is a loss",
     "准备时间结束 —— 未部署任何舰船，本节点判负"),
    ("BATTLE_FORFEIT_TIMEOUT", "Battle timer hit zero — field not cleared in "
     "time, this node is a loss", "战斗时限归零 —— 未能在时限内清场，本节点判负"),
    # ── 结束原因（`end_reason()` 的返回值 = 显示源文）─────────────
    ("BATTLE_REASON_NONE", "Not Deployed", "未部署"),
    ("BATTLE_REASON_TIMEOUT", "Time Out", "时限耗尽"),
    ("BATTLE_REASON_WIPED", "Our Fleet Wiped", "我方全灭"),
    ("BATTLE_REASON_STALEMATE", "Stalemate", "僵持收场"),
    ("BATTLE_REASON_CLEARED", "Enemy Wiped", "敌方全灭"),
]


def main():
    with io.open(CSV_PATH, encoding="utf-8-sig", newline="") as f:
        existing = list(csv.reader(f))
    have = set(r[0] for r in existing[1:] if r)
    add = [r for r in ROWS if r[0] not in have]
    skip = [r[0] for r in ROWS if r[0] in have]
    with io.open(CSV_PATH, "a", encoding="utf-8", newline="") as f:
        w = csv.writer(f, lineterminator="\n")
        for r in add:
            w.writerow(list(r))
    print("CSV=%s" % CSV_PATH)
    print("新增 %d 条，跳过（已存在）%d 条" % (len(add), len(skip)))
    for k in skip:
        print("  skip %s" % k)
    return 0


if __name__ == "__main__":
    sys.exit(main())
