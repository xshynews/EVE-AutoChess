# -*- coding: utf-8 -*-
"""给 i18n 流水线脚本顶部打「⏸ 英文版冻结」标记（幂等）。

用户 2026-10-11 定调：英文版现在时机不成熟，先不做 ⇒ 这些脚本暂停使用。
"""
import io
import os

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")

BANNER = (
    "# ⏸⏸ 冻结（2026-10-11 用户定调：英文版现在时机不成熟，先不做）。\n"
    "# ⛔ 解冻前不要跑这个脚本 —— 它往 i18n/strings.csv 追加 key，属于「继续做英文版」。\n"
    "#    解冻顺序：先补英文文案本身 → 再迁剩余 UI 面 → 最后开放设置窗「语言」行。\n"
    "#    详见 i18n/README.md 顶部。\n"
)

TARGETS = [
    "tools/pipeline/add_i18n_menu_rows.py",
    "tools/pipeline/add_i18n_settings_rows.py",
    "tools/pipeline/add_i18n_result_rows.py",
    "tools/pipeline/add_i18n_shop_dossier_rows.py",
    "tools/pipeline/add_i18n_ddz_rows.py",
    "tools/pipeline/add_i18n_battle_rows.py",
    "tools/pipeline/scan_ui_cn_left.py",
    "tools/pipeline/scan_ui_cn.py",
    "tools/pipeline/gen_i18n_terms.py",
]

for rel in TARGETS:
    p = os.path.normpath(os.path.join(ROOT, rel))
    if not os.path.exists(p):
        print("SKIP (missing):", rel)
        continue
    s = io.open(p, encoding="utf-8").read()
    if "⏸⏸ 冻结" in s[:400]:
        print("ALREADY:", rel)
        continue
    io.open(p, "w", encoding="utf-8", newline="").write(BANNER + s)
    print("OK:", rel)
