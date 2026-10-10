# ⏸⏸ 冻结（2026-10-11 用户定调：英文版现在时机不成熟，先不做）。
# ⛔ 解冻前不要跑这个脚本 —— 它往 i18n/strings.csv 追加 key，属于「继续做英文版」。
#    解冻顺序：先补英文文案本身 → 再迁剩余 UI 面 → 最后开放设置窗「语言」行。
#    详见 i18n/README.md 顶部。
# -*- coding: utf-8 -*-
"""一次性：把斗地主牌桌（i18n 第 3 步 UI 面）的文案追加进 i18n/strings.csv。

⛔ 幂等：已存在的 key 跳过（绝不覆盖手写行）。
"""
import csv
import io
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CSV_PATH = os.path.join(ROOT, "i18n", "strings.csv")

ROWS = [
    # ── 牌型名（唯一真源 `R.type_name()`，按 TYPE_IDS 拼 key）─────
    ("CARD_TYPE_INVALID", "Invalid", "非法"),
    ("CARD_TYPE_SINGLE", "Single", "单"),
    ("CARD_TYPE_PAIR", "Pair", "对"),
    ("CARD_TYPE_TRIPLE", "Triple", "三张"),
    ("CARD_TYPE_TRIPLE_ONE", "Triple + 1", "三带一"),
    ("CARD_TYPE_TRIPLE_TWO", "Triple + 2", "三带二"),
    ("CARD_TYPE_STRAIGHT", "Straight", "顺子"),
    ("CARD_TYPE_STRAIGHT_PAIR", "Consecutive Pairs", "连对"),
    ("CARD_TYPE_PLANE", "Plane", "飞机"),
    ("CARD_TYPE_PLANE_ONE", "Plane + Singles", "飞机带单"),
    ("CARD_TYPE_PLANE_TWO", "Plane + Pairs", "飞机带对"),
    ("CARD_TYPE_FOUR_TWO_SINGLE", "Four + Two", "四带二"),
    ("CARD_TYPE_FOUR_TWO_PAIR", "Four + Two Pairs", "四带两对"),
    ("CARD_TYPE_BOMB", "Bomb", "炸弹"),
    ("CARD_TYPE_ROCKET", "Rocket", "王炸"),
    ("CARD_TYPE_UNKNOWN", "?", "?"),
    # ── 身份 / 座位（高频复用词，各一个 key）─────────────────────
    ("DDZ_ROLE_LANDLORD", "Landlord", "地主"),
    ("DDZ_ROLE_FARMER", "Farmer", "农民"),
    ("DDZ_ROLE_TBD", "TBD", "待定"),
    ("DDZ_ROLE_NONE", "Role Unset", "身份未定"),
    ("DDZ_TBD", "Undecided", "未定"),
    ("DDZ_SEAT_0", "You", "你"),
    ("DDZ_SEAT_1", "Next", "下家"),
    ("DDZ_SEAT_2", "Previous", "上家"),
    ("DDZ_SEAT_LL", "(Landlord)", "（地主）"),
    ("DDZ_SEAT_FA", "(Farmer)", "（农民）"),
    ("DDZ_WIN", "You Win", "你赢了"),
    ("DDZ_LOSE", "You Lose", "你输了"),
    ("DDZ_PASS", "Pass", "不要"),
    ("DDZ_UNIT_CARD", "cards", "张"),
    ("DDZ_COIN", "Fun Coins %s", "娱乐币 %s"),
    ("DDZ_ALL_OUT", "All Played", "已出完"),
    # ── 顶栏 / 底牌 ─────────────────────────────────────────────
    ("DDZ_TOP_TITLE", "Dou Dizhu · Solo (you + 2 AI)", "斗地主 · 单机（你 + 两个 AI）"),
    ("DDZ_TOP_BASE", "Base ×%d    ·    Landlord %s", "底分 ×%d    ·    地主 %s"),
    ("DDZ_BOTTOM", "Bottom Cards", "底牌"),
    ("DDZ_BOTTOM_HIDDEN", "(revealed after bidding)", "（叫完才亮）"),
    # ── 手牌标题 / 提示 ─────────────────────────────────────────
    ("DDZ_HAND_DEALING", "Your hand · %d / %d cards　dealing…",
     "你的手牌 · %d / %d 张　发牌中…"),
    ("DDZ_HAND_TITLE", "Your hand · %d cards · %s%s", "你的手牌 · %d 张 · %s%s"),
    ("DDZ_NEW_BOTTOM", "　★ Bottom cards added (the 3 lifted)",
     "　★ 底牌已加入（抬起的 3 张）"),
    ("DDZ_HAND_DEAL_HINT", "Dealing — bid after the deal",
     "发牌中 —— 发完才轮到你叫地主"),
    # ── 选牌提示 ────────────────────────────────────────────────
    ("DDZ_SEL_BID", "Decide after seeing your hand: Pass / 1 / 2 / 3 "
     "(higher bid = higher base score)",
     "看完这手牌再决定：不叫 / 1 分 / 2 分 / 3 分（分数越高底分越大）"),
    ("DDZ_SEL_WAIT", "Waiting for other bids…", "等别家叫分…"),
    ("DDZ_SEL_NONE", "No cards selected — click to select (right click clears, "
     "Hint helps)", "未选牌 —— 点手牌选择（右键清空，「提示」帮你想）"),
    ("DDZ_SEL_BAD", "Selected %s — not a legal combo", "已选 %s —— 不是合法牌型"),
    ("DDZ_SEL_OK", "Selected %s（%s）", "已选 %s（%s）"),
    # ── 结算亮字 ────────────────────────────────────────────────
    ("DDZ_OVER_DELTA", "%s wins · fun coins %+d", "%s 胜 · 本局娱乐币 %+d"),
    ("DDZ_OVER_TOTAL", "Total %s · %d wins / %d games", "累计 %s · %d 胜 / %d 局"),
    # ── 日志 ────────────────────────────────────────────────────
    ("DDZ_LOG_NEW_GAME", "—— New game (seed %d) ——", "—— 新一局（seed %d）——"),
    ("DDZ_LOG_LANDLORD", "★ Landlord = %s · bottom %s", "★ 地主 = %s · 底牌 %s"),
    ("DDZ_LOG_PLAY", "%s plays %s（%s）", "%s 出 %s（%s）"),
    ("DDZ_LOG_WIN", "★ %s wins —— %s", "★ %s 胜 —— %s"),
    ("DDZ_LOG_PASS", "%s passes", "%s 不要"),
    ("DDZ_LOG_NEW_ROUND", "—— New round, %s leads", "—— 新一轮，%s 先出"),
    ("DDZ_AUTO", "Autoplay%s", "托管%s"),
    ("DDZ_AUTO_ON", "on — your seat is handed to the AI", "已开 —— 你的座位交给电脑"),
    ("DDZ_AUTO_OFF", "off", "已关"),
    # ── 状态行 ──────────────────────────────────────────────────
    ("DDZ_STATUS_IDLE", "Press Start to deal — one deck, three players, you play one",
     "点「开始游戏」发牌 —— 一副牌，三个人，你打一家"),
    ("DDZ_STATUS_DEALING", "Dealing…", "发牌中…"),
    ("DDZ_STATUS_OVER", "%s wins · %s", "%s 胜 · %s"),
    ("DDZ_STATUS_BIDDING", "Bidding —— ", "叫分中 —— "),
    ("DDZ_STATUS_BID_YOU", "your turn (pass / 1~3)", "轮到你了（不叫 / 1~3 分）"),
    ("DDZ_STATUS_THINKING", "%s thinking…", "%s 思考中…"),
    ("DDZ_STATUS_LEAD", "Your turn — new round, lead anything",
     "轮到你了 —— 新一轮，你随意出"),
    ("DDZ_STATUS_FOLLOW", "Your turn — must beat %s's %s", "轮到你了 —— 要压过 %s 的 %s"),
    ("DDZ_STATUS_THINKING_N", "%s thinking…（%d cards left）", "%s 思考中…（还剩 %d 张）"),
    ("DDZ_ERR_AI_PLAY", "⚠ AI failed to play (seat %d) — see the log on the right",
     "⚠ AI 出牌失败（座位 %d）—— 见右侧记录"),
    ("DDZ_ERR_AI_PASS", "⚠ AI failed to pass (seat %d) — see the log on the right",
     "⚠ AI 过牌失败（座位 %d）—— 见右侧记录"),
    # ── 叫分 / 按钮 ─────────────────────────────────────────────
    ("DDZ_BID_PASS", "Pass", "不叫"),
    ("DDZ_BID_N", "Bid %d", "叫 %d 分"),
    ("DDZ_BID_1", "1", "1 分"),
    ("DDZ_BID_2", "2", "2 分"),
    ("DDZ_BID_3", "3", "3 分"),
    ("DDZ_BTN_BACK", "← Back", "← 返回"),
    ("DDZ_BTN_AUTO_ON", "Autoplay: on", "托管：开"),
    ("DDZ_BTN_AUTO_OFF", "Autoplay: off", "托管：关"),
    ("DDZ_BTN_SETTINGS", "Settings", "设置"),
    ("DDZ_BTN_START", "Start Game", "开始游戏"),
    ("DDZ_BTN_AGAIN", "Play Again", "再来一局"),
    ("DDZ_BTN_PLAY", "Play", "出牌"),
    ("DDZ_BTN_HINT", "Hint", "提示"),
    ("DDZ_HINT_N", "Hint %d/%d", "提示 %d/%d"),
    # ── 拒答 toast ──────────────────────────────────────────────
    ("DDZ_TOAST_NOT_BID", "Not your bidding turn", "现在不是你的叫分回合"),
    ("DDZ_TOAST_BID_LOW", "Bid must beat the current best (now %d)",
     "叫分要高于当前最高分（现在是 %d 分）"),
    ("DDZ_TOAST_NOT_PLAY", "Not your turn to play", "还没轮到你出牌"),
    ("DDZ_TOAST_NO_SEL", "Select cards first — press Hint if unsure",
     "先点手牌选牌 —— 不知道出什么就按「提示」"),
    ("DDZ_TOAST_BAD_TYPE", "These cards are not a legal combo", "这几张凑不成合法牌型"),
    ("DDZ_TOAST_NOT_PASS", "Not your turn", "还没轮到你"),
    ("DDZ_TOAST_MUST_PLAY", "You lead this round — you cannot pass",
     "新一轮由你先出，不能不要"),
    ("DDZ_TOAST_NOT_HINT", "Not your turn to play", "现在不是你的出牌回合"),
    ("DDZ_TOAST_NO_BEAT", "Nothing can beat it — you can only pass",
     "没有能压过的牌 —— 只能「不要」"),
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
