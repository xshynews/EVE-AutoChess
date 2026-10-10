# ⏸⏸ 冻结（2026-10-11 用户定调：英文版现在时机不成熟，先不做）。
# ⛔ 解冻前不要跑这个脚本 —— 它往 i18n/strings.csv 追加 key，属于「继续做英文版」。
#    解冻顺序：先补英文文案本身 → 再迁剩余 UI 面 → 最后开放设置窗「语言」行。
#    详见 i18n/README.md 顶部。
# -*- coding: utf-8 -*-
"""一次性：把设置窗（i18n 第 3 步 UI 面）的文案追加进 i18n/strings.csv。

⛔ 幂等：已存在的 key 跳过（绝不覆盖手写行）。
"""
import csv
import io
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CSV_PATH = os.path.join(ROOT, "i18n", "strings.csv")

ROWS = [
    # ── 分区标题 ────────────────────────────────────────────────
    ("SET_GROUP_AUDIO", "Audio  AUDIO", "音频  AUDIO"),
    ("SET_GROUP_DISPLAY", "Display  DISPLAY", "显示  DISPLAY"),
    ("SET_GROUP_INTERFACE", "Interface  INTERFACE", "界面  INTERFACE"),
    ("SET_GROUP_RENDER", "Render  RENDER", "画面  RENDER"),
    ("SET_GROUP_BATTLE_UI", "Battle UI  BATTLE UI", "战斗界面  BATTLE UI"),
    ("SET_GROUP_ACTION", "Action  ACTION", "操作  ACTION"),
    ("SET_GROUP_SYSTEM", "System  SYSTEM", "系统  SYSTEM"),
    ("SET_GROUP_RESET", "Reset  RESET", "重置  RESET"),
    # ── 音量四档 ────────────────────────────────────────────────
    ("SET_VOL_MASTER", "Master", "总音量"),
    ("SET_VOL_SFX", "SFX", "音效"),
    ("SET_VOL_AMB", "Ambience", "环境"),
    ("SET_VOL_MUSIC", "Music", "音乐"),
    ("SET_MUTE", "Mute", "静音"),
    # ── 显示：语言 / 分辨率 / 界面缩放 ───────────────────────────
    ("SET_LANG", "Language LANGUAGE · %s", "语言 LANGUAGE · %s"),
    ("RES_AUTO", "Adaptive", "自适应"),
    ("SET_RES_NOTE", "★ = recommended · Adaptive = follow your screen",
     "★ = 推荐档 · 自适应 = 跟随屏幕"),
    ("SET_UISCALE_AUTO", "Auto", "自动"),
    # ── 界面：字号 ──────────────────────────────────────────────
    ("SET_FONT_SCALE", "Font size", "字号"),
    # ── 画面：天空盒 / 氛围 ─────────────────────────────────────
    ("SET_BG_CALDARI_C07", "Caldari C07", "加达里 C07"),
    ("SET_BG_CALDARI_C02", "Caldari C02", "加达里 C02"),
    ("SET_BG_GALLENTE_G03", "Gallente G03", "盖伦特 G03"),
    ("SET_BG_AMARR_A03", "Amarr A03", "艾玛 A03"),
    ("SET_MOOD_0", "Clear", "通透"),
    ("SET_MOOD_1", "Atmospheric", "氛围"),
    # ── 战斗界面三开关 ──────────────────────────────────────────
    ("SET_TOGGLE_FOG", "Space fog", "空间雾"),
    ("SET_TOGGLE_RINGS", "Range rings", "射程环"),
    ("SET_TOGGLE_BOARD", "Board grid", "棋盘"),
    ("TOGGLE_ON", "[ON]", "[开]"),
    ("TOGGLE_OFF", "[OFF]", "[关]"),
    # ── 操作 ────────────────────────────────────────────────────
    ("SET_ACT_CAMERA", "Reset camera", "相机复位"),
    ("SET_ACT_RESTART", "Restart run", "重开一局"),
    ("SET_ACT_BACK_BATTLE", "Abandon run · back to menu", "放弃本局 · 回主界面"),
    ("SET_ACT_BACK_LOUNGE", "Back to main menu", "返回主界面"),
    ("SET_PAUSE_RESUME", "▶ Resume", "▶ 继续对局"),
    ("SET_PAUSE_PAUSE", "‖ Pause", "‖ 暂停对局"),
    # ── 系统（仅 debug 构建可见）────────────────────────────────
    ("SET_DEBUG_COINS", "+%d credits", "+%d 星币"),
    # ── 重置 ────────────────────────────────────────────────────
    ("SET_RESET_DONE", "✓ Restored defaults", "✓ 已恢复默认"),
    # ── 快捷键备忘（按档案分三句）───────────────────────────────
    ("SET_HINT_BATTLE",
     "Hotkeys  Space pause/resume · C reset camera · B board · R restart",
     "快捷键  空格 暂停/继续 · C 相机复位 · B 棋盘 · R 重开"),
    ("SET_HINT_MENU_DESKTOP",
     "Volume and resolution apply instantly; the main menu is a fixed layout and keeps the font size set in battle.",
     "音量与分辨率即时生效；主界面为固定版面，字号沿用战斗设置"),
    ("SET_HINT_MENU_MOBILE",
     "Volume applies instantly; UI scale and font size take effect in battle (the main menu is a fixed layout).",
     "音量即时生效；界面缩放与字号在战斗中生效（主界面为固定版面）"),
    ("SET_HINT_LOUNGE",
     "Resolution and font size apply instantly; the card table does not use UI scaling.",
     "分辨率与字号即时生效；牌桌不参与「界面缩放」"),
    # ── 窗口通用（EveWindow 基类）───────────────────────────────
    ("WINDOW_COLLAPSE_TIP", "Collapse / expand (or double-click the title bar)",
     "收起 / 展开（也可以双击标题栏）"),
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
