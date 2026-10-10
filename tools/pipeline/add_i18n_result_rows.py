# ⏸⏸ 冻结（2026-10-11 用户定调：英文版现在时机不成熟，先不做）。
# ⛔ 解冻前不要跑这个脚本 —— 它往 i18n/strings.csv 追加 key，属于「继续做英文版」。
#    解冻顺序：先补英文文案本身 → 再迁剩余 UI 面 → 最后开放设置窗「语言」行。
#    详见 i18n/README.md 顶部。
# -*- coding: utf-8 -*-
"""一次性：把结算页（i18n 第 3 步 UI 面）的文案追加进 i18n/strings.csv。

⛔ 幂等：已存在的 key 跳过（绝不覆盖手写行）。
"""
import csv
import io
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CSV_PATH = os.path.join(ROOT, "i18n", "strings.csv")

ROWS = [
    ("RESULT_TITLE", "Node Report", "节点结算"),
    ("RESULT_WIN", "Interception Successful", "拦截成功"),
    ("RESULT_LOSE", "Interception Failed", "拦截失败"),
    ("RESULT_SUB", "Node 1 / 15 · Skirmish", "节点 1 / 15 · 遭遇战"),
    ("RESULT_SUB_FMT", "Node %d / 15 · %s%s", "节点 %d / 15 · %s%s"),
    ("RESULT_STAGE_SKIRMISH", "Skirmish", "遭遇战"),
    # ── 战绩 / 收益 ─────────────────────────────────────────────
    ("RESULT_KILL", "Destroyed", "击毁"),
    ("RESULT_SHIPS_0", "0 ships", "0 艘"),
    ("RESULT_SHIPS_N", "%d ships", "%d 艘"),
    ("RESULT_ALIVE", "Own Surviving", "我方存活"),
    ("RESULT_XP", "XP", "经验"),
    ("RESULT_WRECK", "Wrecks", "残骸"),
    ("RESULT_WRECK_N", "%d awaiting salvage", "%d 艘待打捞"),
    ("RESULT_NONE", "None", "无"),
    # ── 两个动作按钮 ────────────────────────────────────────────
    ("RESULT_END", "End Run", "结束本局"),
    ("RESULT_NEXT", "Continue · Next Node", "继续 · 下一节点"),
    ("RESULT_AGAIN", "↻ Play Again", "↻ 再来一局"),
    # ── 打捞区 ──────────────────────────────────────────────────
    ("RESULT_SALVAGE_TITLE", "Salvage Wrecks", "打捞 残骸"),
    ("RESULT_SALVAGE_HINT", "Ordering pays at once · delivered next node",
     "下单即付款 · 下节点到账占位"),
    ("RESULT_SALVAGE_CLOSE_TIP", "Collapse the salvage area (wrecks are kept)",
     "收起打捞区（残骸仍保留）"),
    ("RESULT_SALVAGE_ROW", "Node %d · %s ★%d", "节点 %d · %s ★%d"),
    ("RESULT_SALVAGE_BTN", "Salvage", "打捞"),
    ("RESULT_SALVAGE_WARN", "⚠ Deciding later forfeits them (%d ships)",
     "⚠ 不决定就作废（%d 艘）"),
    ("RESULT_SALVAGE_EMPTY", "No wrecks yet — destroyed ships show up here",
     "暂无残骸 —— 舰船被击毁后会出现在这里"),
    ("RESULT_SALVAGE_QUEUE", "Repair queue (arrives next round): %s",
     "修复队列（下回合到账）：%s"),
    ("RESULT_COIN", "Holding %d credits", "持有 %d 星币"),
    # ── 零选二次确认 ────────────────────────────────────────────
    ("RESULT_SALVAGE_ASK_TITLE", "Give Up Salvage", "放弃打捞"),
    ("RESULT_SALVAGE_ASK_OK", "Give Up", "确定放弃"),
    ("RESULT_SALVAGE_ASK_CANCEL", "Back to Choosing", "回去再选"),
    # ── 结局页 ──────────────────────────────────────────────────
    ("RESULT_ENDING_CLEARED", "The Frontier Is Cleared", "遥望边境已肃清"),
    ("RESULT_ENDING_BEACON", "Beacon at Zero · Withdraw", "信标归零 · 撤离"),
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
