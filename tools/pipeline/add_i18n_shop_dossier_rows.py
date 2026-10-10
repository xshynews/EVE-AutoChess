# ⏸⏸ 冻结（2026-10-11 用户定调：英文版现在时机不成熟，先不做）。
# ⛔ 解冻前不要跑这个脚本 —— 它往 i18n/strings.csv 追加 key，属于「继续做英文版」。
#    解冻顺序：先补英文文案本身 → 再迁剩余 UI 面 → 最后开放设置窗「语言」行。
#    详见 i18n/README.md 顶部。
# -*- coding: utf-8 -*-
"""一次性：把商店 + 舰船档案（i18n 第 3 步 UI 面）的文案追加进 i18n/strings.csv。

⛔ 幂等：已存在的 key 跳过（绝不覆盖手写行）。
⚠️ 商店 / 档案窗的短标签（盾/甲/护盾/装甲…）**不进术语段**（`SHIP.` / `DEFENSE.` 那套是
   EVE 官方名词，由 `gen_i18n_terms.py` 生成）；这些是 UI 排版用的短写，独立成 key。
"""
import csv
import io
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CSV_PATH = os.path.join(ROOT, "i18n", "strings.csv")

ROWS = [
    # ── 商店：窗壳 / 经济区 ──────────────────────────────────────
    ("SHOP_TITLE", "Shop", "商店"),
    ("SHOP_COIN_UNIT", "Credits", "星币"),
    ("SHOP_REFRESH", "↻ Reroll %d", "↻ 刷新 %d"),
    ("SHOP_LEVELUP", "▲ Level Up %d", "▲ 加速等级 %d"),
    ("SHOP_LOCK", "✦ Lock Roster", "✦ 锁定加速列表"),
    ("SHOP_LOCKED", "✦ Roster Locked", "✦ 已锁定加速列表"),
    # ── 商店：货架卡 ─────────────────────────────────────────────
    ("SHOP_BOUGHT", "Purchased", "已买走"),
    ("SHOP_SALVAGE", "Refit %s", "修复 %s"),
    ("SHOP_CARD_STAT", "%s · %s\nATK %d　%s %d", "%s · %s\n攻 %d　%s %d"),
    ("SHOP_DEF_SHIELD", "SH", "盾"),
    ("SHOP_DEF_ARMOR", "AR", "甲"),
    # ── 商店：打捞框 ─────────────────────────────────────────────
    ("SHOP_SALVAGE_HEAD", "To Salvage", "待打捞"),
    ("SHOP_SALVAGE_HINT", "Pick wrecks\non the battle result",
     "打捞请在\n战斗结算页选"),
    ("SHOP_SALVAGE_HEAD_N", "To Salvage %d", "待打捞 %d"),
    ("SHOP_WRECK_STAT", "Strike %d · %s %d", "打击 %d · %s %d"),
    ("SHOP_WRECK_BOOSTED", "Boosted", "强化"),
    ("SHOP_WRECK_DEFENSE", "Defense", "防御"),
    ("SHOP_WRECK_ORDER", "Order −%d ◆", "下单 −%d ◆"),
    ("SHOP_NEXT_NODE", "Arrives next node", "下节点到账"),
    ("SHOP_REPAIRING", "Refitting", "修复中"),
    ("SHOP_NEXT_NODE_SLOT", "Arrives next node\nreplaces 1 cargo slot",
     "下节点到账\n顶掉 1 个货位"),
    # ── 商店：底部 ───────────────────────────────────────────────
    ("SHOP_BENCH", "Bench %d / %d", "备战席 %d / %d"),
    ("SHOP_SELL_HINT", "Drag here to sell · ◆ refunded", "拖到此处出售 · 返还 ◆"),
    # ── 舰船档案：窗壳 / 空态 ────────────────────────────────────
    ("DOSSIER_TITLE", "Ship Dossier", "舰船档案"),
    ("DOSSIER_EMPTY_H", "Select a ship", "点击舰船查看"),
    ("DOSSIER_EMPTY_P", "Battlefield / Bench / Shop card\nclick any one of them",
     "战场 / 备战席 / 商店卡\n任一处点选即可"),
    ("DOSSIER_NONE", "None Selected", "未选中"),
    # ── 舰船档案：三层血 ─────────────────────────────────────────
    ("DOSSIER_HP_SHIELD", "Shield", "护盾"),
    ("DOSSIER_HP_ARMOR", "Armor", "装甲"),
    ("DOSSIER_HP_HULL", "Hull", "结构"),
    # ── 舰船档案：六格属性 ───────────────────────────────────────
    ("DOSSIER_ATTR_ATTACK", "Attack", "攻击"),
    ("DOSSIER_ATTR_INTERVAL", "Interval", "攻击间隔"),
    ("DOSSIER_ATTR_RANGE", "Range", "射程"),
    ("DOSSIER_ATTR_SPEED", "Speed", "移速"),
    ("DOSSIER_ATTR_SIG", "Signature", "信号半径"),
    ("DOSSIER_ATTR_CLASS", "Class", "吨位"),
    ("DOSSIER_RANGE", "%d cells", "%d 格"),
    ("DOSSIER_SPEED", "%.2f cells/s", "%.2f 格/s"),
    # ── 舰船档案：元信息 / 定位 / 羁绊 ───────────────────────────
    ("DOSSIER_ROLE_NONE", "Role　—", "定位　—"),
    ("DOSSIER_META", "%s · %s · %d cost", "%s · %s · %d 费"),
    ("DOSSIER_ROLE", "Role　%s%s", "定位　%s%s"),
    ("DOSSIER_LOGI", "(Logistics)", "（后勤）"),
    ("DOSSIER_TRAIT_ACTIVE", "Active", "已生效"),
    ("DOSSIER_TRAIT_AWAY", "%d tier(s) short", "差 %d 档"),
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
