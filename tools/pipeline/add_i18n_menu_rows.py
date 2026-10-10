# ⏸⏸ 冻结（2026-10-11 用户定调：英文版现在时机不成熟，先不做）。
# ⛔ 解冻前不要跑这个脚本 —— 它往 i18n/strings.csv 追加 key，属于「继续做英文版」。
#    解冻顺序：先补英文文案本身 → 再迁剩余 UI 面 → 最后开放设置窗「语言」行。
#    详见 i18n/README.md 顶部。
# -*- coding: utf-8 -*-
"""一次性：把主菜单（i18n 第 3 步 UI 面）的文案追加进 i18n/strings.csv。

⛔ 幂等：已存在的 key 跳过（绝不覆盖手写行）。
"""
import csv
import io
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CSV_PATH = os.path.join(ROOT, "i18n", "strings.csv")

ROWS = [
    # ── 主菜单外壳 ────────────────────────────────────────────────
    ("MENU_BRAND", "EVE Auto Chess", "EVE 自走棋"),
    ("MENU_CONTINUE", "Continue Run", "继续上局"),
    ("MENU_SETTINGS", "Settings", "设置"),
    ("MENU_REPLAY_INTRO", "Replay Intro", "回看片头"),
    ("MENU_QUIT", "Quit", "退出游戏"),
    ("MENU_VERSION", "Version V%s", "当前版本 V%s"),
    ("MENU_MODES_CAP", "GAME MODE", "游戏模式　MODE"),
    ("MENU_START", "▶ Start %s", "▶　开始%s"),
    ("CARD_TODO", "Coming soon", "待开发"),
    # ── 模式名 / 副标题（key 按模式 id）────────────────────────────
    ("MODE_CAMPAIGN_NAME", "Campaign", "任务关卡"),
    ("MODE_CAMPAIGN_META", "%d rounds · %d difficulties", "%d 回合 · 共 %d 个难度"),
    ("MODE_CARDROOM_NAME", "Recreation Hub", "娱乐总汇"),
    ("MODE_CARDROOM_META", "Dou Dizhu · playable", "斗地主 · 可试玩"),
    ("MODE_ENDLESS_NAME", "Endless", "无尽模式"),
    ("MODE_ENDLESS_META", "Best record —", "最高纪录　—"),
    ("MODE_VERSUS_NAME", "Multiplayer", "多人对战"),
    ("MODE_VERSUS_META", "Opening soon", "即将开放"),
    ("MODE_CREDITS_NAME", "Copyright", "版权声明"),
    ("MODE_CREDITS_META", "Credits · open-source licenses", "致谢 · 开源许可"),
    # ── 任务关卡卡片（key 按 tier id）──────────────────────────────
    ("CARD_GUARD_BORDER_NAME", "Guard the Border", "守卫边境"),
    ("CARD_GUARD_BORDER_CODE", "GUARD THE BORDER · Difficulty 1", "GUARD THE BORDER · 第 1 难度"),
    ("CARD_GUARD_BORDER_DESC",
     "Difficulty 1. Fifteen consecutive rounds of skirmishes along the border line; the enemy escalates from roaming pirates to a regular fleet. Clear round 15 to finish, which unlocks Difficulty 2.",
     "第一难度。边境线上连续 15 个回合的遭遇战，敌人从游荡的海盗逐步升级为正规舰队。打完第 15 回合即通关，通关后解锁第二难度。"),
    ("CARD_FLEET_ASSEMBLY_NAME", "Fleet Assembly", "舰队集结"),
    ("CARD_FLEET_ASSEMBLY_CODE", "FLEET ASSEMBLY · Difficulty 2", "FLEET ASSEMBLY · 第 2 难度"),
    ("CARD_FLEET_ASSEMBLY_DESC",
     "Difficulty 2. Twenty-five rounds; the enemy advances in formed fleets, one tier above Difficulty 1 in both scale and strength. You must clear Difficulty 1 first — not developed yet.",
     "第二难度。25 个回合，敌人以成建制的舰队推进，规模与强度都比第一难度高一档。需先通关第一难度才解锁，目前尚未开发。"),
    ("CARD_ENDLESS_WAR_NAME", "Endless War", "无边战火"),
    ("CARD_ENDLESS_WAR_CODE", "ENDLESS WAR · Difficulty 3", "ENDLESS WAR · 第 3 难度"),
    ("CARD_ENDLESS_WAR_DESC",
     "Difficulty 3. Scale and strength rise another tier; the round count is still TBD. You must clear Difficulty 2 first — not developed yet.",
     "第三难度。规模与强度再上一档，回合配置待定。需先通关第二难度才解锁，目前尚未开发。"),
    # ── 娱乐总汇 / 另两个模式的卡片（key 按 code）───────────────────
    ("CARD_DOUDIZHU_NAME", "Dou Dizhu", "斗地主"),
    ("CARD_DOUDIZHU_DESC",
     "One deck, three opponents. Bid for the landlord, bombs, and the rocket.",
     "一副牌，三个对手。抢地主、炸弹、王炸。"),
    ("CARD_SICHUAN_NAME", "Sichuan Mahjong", "川麻"),
    ("CARD_SICHUAN_DESC",
     "Sichuan Mahjong · blood battle to the end. Missing one suit, wind and rain.",
     "四川麻将 · 血战到底。缺一门、刮风下雨。"),
    ("CARD_RIICHI_NAME", "Riichi Mahjong", "日麻"),
    ("CARD_RIICHI_DESC",
     "Riichi Mahjong. Yaku, dora, furiten.",
     "立直麻将。役种、宝牌、振听。"),
    ("CARD_SHENGJI_NAME", "Shengji", "升级"),
    ("CARD_SHENGJI_DESC",
     "Tractor · 4 players in 2 teams. Declaring and counter-declaring trump, discarding to the bottom.",
     "拖拉机 · 4 人 2 队。亮主反主、甩牌抠底。"),
    ("CARD_ENDLESS_NAME", "Endless", "无尽模式"),
    ("CARD_ENDLESS_DESC",
     "No finish line. Wave after wave of enemy fleets; the higher the wave, the heavier the tonnage and the dirtier the composition. Hold out until you cannot — the only thing that counts is how far you get.",
     "没有终点。一波接一波的敌方舰队，波数越高吨位越重、编制越脏。撑到撑不住为止，只比谁走得更远。"),
    ("CARD_VERSUS_NAME", "Multiplayer", "多人对战"),
    ("CARD_VERSUS_DESC",
     "Compete against other commanders on the same board — eight players, each for themselves. Opponent compositions keep changing and there is no fixed answer; this mode is reserved for later.",
     "与其他指挥官同场博弈，八人各自为战。对手的阵容在变化，没有固定解法 —— 这是留给后期的模式。"),
    # ── stats 行的键 ──────────────────────────────────────────────
    ("CARD_K_PLAY", "Game", "玩法"),
    ("CARD_K_OPP", "Opponents", "对手"),
    ("CARD_K_STATUS", "Status", "状态"),
    ("CARD_K_END", "End", "终点"),
    ("CARD_K_RECORD", "Record", "纪录"),
    ("CARD_K_REQ", "Requires", "前置"),
    ("CARD_K_ROUNDS", "Rounds", "回合数"),
    ("CARD_K_UNLOCK", "Unlock", "解锁"),
    # ── stats 行的值 ──────────────────────────────────────────────
    ("CARD_V_CPU3", "CPU · 3 players", "电脑 · 3 人"),
    ("CARD_V_FLEET4", "CPU fleet · 4 factions", "电脑舰队 · 4 派系"),
    ("CARD_V_FLEET_FORMAL", "CPU fleet · formed", "电脑舰队 · 成建制"),
    ("CARD_V_FLEET_WAVES", "CPU fleet · endless waves", "电脑舰队 · 无限波次"),
    ("CARD_V_PLAYERS8", "Other players · 8", "其他玩家 · 8 人"),
    ("CARD_V_TBD", "TBD", "待定"),
    ("CARD_V_OPEN", "Available", "可进入"),
    ("CARD_V_WIP", "In development", "开发中"),
    ("CARD_V_CLOSED", "Not yet open", "尚未开放"),
    ("CARD_V_UNLOCK_DEFAULT", "Open by default", "默认开放"),
    ("CARD_V_NO_END", "None · until wiped out", "无 · 直到全灭"),
    ("CARD_V_LAST_ALIVE", "Last survivor wins", "最后存活者获胜"),
    ("CARD_V_NEED_NET", "Requires network and server", "需要联网与服务器"),
    ("CARD_V_PLAY_DDZ", "Dou Dizhu", "斗地主"),
    ("CARD_V_PLAY_SICHUAN", "Sichuan Mahjong", "四川麻将"),
    ("CARD_V_PLAY_RIICHI", "Riichi Mahjong", "立直麻将"),
    ("CARD_V_PLAY_SHENGJI", "Shengji", "升级"),
    ("CARD_V_ROUNDS15", "15 rounds", "15 回合"),
    ("CARD_V_ROUNDS25", "25 rounds", "25 回合"),
    ("CARD_V_UNLOCK_T1", "Clear Difficulty 1", "通关第 1 难度"),
    ("CARD_V_UNLOCK_T2", "Clear Difficulty 2", "通关第 2 难度"),
    # ── 提示 toast ────────────────────────────────────────────────
    ("MENU_TOAST_DDZ",
     "Dou Dizhu is in development — the rules core and the AI opponents are being built. Once it opens, this button takes you straight to the table.",
     "斗地主制作中 —— 规则内核与人机对战开发中，开放后这里直接进牌局"),
    ("MENU_TOAST_MODE_WIP", "%s is still in development", "「%s」还在开发中"),
    ("MENU_TOAST_NO_RUN", "No run to continue", "没有可继续的对局"),
    # ── 版权声明 ──────────────────────────────────────────────────
    ("CREDITS_H_GAME", "The Game · GAME", "游戏本体 · GAME"),
    ("CREDITS_GAME_1",
     "The game architecture and all scripts of EVE Auto Chess (EVE-AutoChess) are created by Xingshi Huanyu and released under the GNU GPL v3.",
     "EVE 自走棋（EVE-AutoChess）的游戏架构与全部脚本由 星视寰宇 创作，以 GNU GPL v3 开源。"),
    ("CREDITS_GAME_2",
     "Source code: https://github.com/xshynews/EVE-AutoChess",
     "源码地址：https://github.com/xshynews/EVE-AutoChess"),
    ("CREDITS_GAME_3",
     "Copyright © 2026 xshynews · Derivative works must likewise be released under GPL v3.",
     "Copyright © 2026 xshynews · 衍生作品须同样以 GPL v3 开源。"),
    ("CREDITS_H_ART", "EVE Theme & Art Assets · EVE IP & ART", "EVE 题材与美术素材 · EVE IP & ART"),
    ("CREDITS_ART_1",
     "Copyright in the EVE-related IP and assets (ship models, icons, textures, etc.) belongs to Fenris Creations (the company renamed from CCP Games in May 2026; CCP originally stood for Crowd Control Productions).",
     "EVE 相关的 IP 与素材（舰船模型、图标、贴图等）著作权归 Fenris Creations 所有（该公司于 2026 年 5 月由 CCP Games 更名而来，CCP 原名 Crowd Control Productions）。"),
    ("CREDITS_ART_2",
     "This project claims no rights to these assets; the related content is not covered by GPL v3 and is used only for study, development and personal experience.",
     "本项目不持有这些素材的任何权利，相关内容不在 GPL v3 覆盖范围内，仅用于学习、开发与体验目的。"),
    ("CREDITS_H_MUSIC", "Background Music · MUSIC", "背景音乐 · MUSIC"),
    ("CREDITS_MUSIC_1",
     "Original composer of the four BGM tracks: Wuya Producer (CrowProducer).",
     "四首 BGM 原曲作者：乌鸦Producer。"),
    ("CREDITS_MUSIC_2",
     "The version used here was rearranged with AI assistance to fit the game length and to loop seamlessly; copyright in the original tracks remains with the original composer.",
     "本项目使用的版本为适配游戏时长与无缝循环经 AI 重编曲处理，原曲版权仍归原作者所有。"),
    ("CREDITS_H_LICENSE", "Open-source License · LICENSE", "开源许可 · LICENSE"),
    ("CREDITS_LICENSE_1",
     "Code: GNU GPL v3 (Copyright © 2026 xshynews).",
     "代码：GNU GPL v3（Copyright © 2026 xshynews）。"),
    ("CREDITS_LICENSE_2",
     "Art / audio assets: property of Fenris Creations and the original authors; not covered by this project's license.",
     "美术 / 音频素材：归 Fenris Creations 及原作者所有，非本项目许可证覆盖范围。"),
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
