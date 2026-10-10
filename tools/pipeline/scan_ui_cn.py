# ⏸⏸ 冻结（2026-10-11 用户定调：英文版现在时机不成熟，先不做）。
# ⛔ 解冻前不要跑这个脚本 —— 它往 i18n/strings.csv 追加 key，属于「继续做英文版」。
#    解冻顺序：先补英文文案本身 → 再迁剩余 UI 面 → 最后开放设置窗「语言」行。
#    详见 i18n/README.md 顶部。
#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""扫出某个 .gd 里**玩家可见的中文字符串字面量**（排除注释行）。

用法：python tools/pipeline/scan_ui_cn.py scripts/eve_main_menu.gd [more.gd ...]
"""
import io
import os
import re
import sys

CJK = re.compile(r'[\u4e00-\u9fff]')
STR = re.compile(r'"((?:[^"\\]|\\.)*)"')


def scan(path):
    hits = []
    with io.open(path, encoding="utf-8") as f:
        for i, raw in enumerate(f, 1):
            line = raw.rstrip("\n").rstrip("\r")
            st = line.strip()
            if st.startswith("#"):
                continue
            # 去掉行尾注释（粗略：`#` 前有非字符串上下文时截断）
            code = line
            if "#" in line:
                # 只处理「# 之前引号数成偶数」的情况
                idx = line.index("#")
                if line[:idx].count('"') % 2 == 0:
                    code = line[:idx]
            for m in STR.finditer(code):
                s = m.group(1)
                if CJK.search(s):
                    hits.append((i, s))
    return hits


total = 0
for p in sys.argv[1:]:
    rel = os.path.relpath(p)
    hits = scan(p)
    total += len(hits)
    print("=== %s（%d 条）===" % (rel, len(hits)))
    for i, s in hits:
        print("  %5d  %s" % (i, s))
    print("")
print("合计 %d 条" % total)
