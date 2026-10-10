# ⏸⏸ 冻结（2026-10-11 用户定调：英文版现在时机不成熟，先不做）。
# ⛔ 解冻前不要跑这个脚本 —— 它往 i18n/strings.csv 追加 key，属于「继续做英文版」。
#    解冻顺序：先补英文文案本身 → 再迁剩余 UI 面 → 最后开放设置窗「语言」行。
#    详见 i18n/README.md 顶部。
# -*- coding: utf-8 -*-
"""i18n 进度扫描：列出**尚未走取词**的玩家可见中文字符串。

与 `scan_ui_cn.py` 的区别：那个文件连注释一起数（所以数字只增不减），
这个文件只认「代码里的双引号字符串含中文，且该行没有 T.t( / TERMS. 取词」。

用法：
    python tools/pipeline/scan_ui_cn_left.py                 # 全工程
    python tools/pipeline/scan_ui_cn_left.py scripts/ui/...  # 指定文件
"""
import io
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CN = re.compile(r"[\u4e00-\u9fff]")
# 双引号字符串（GDScript 单引号不常用）
STR = re.compile(r'"([^"\n]*)"')
SKIP_DIRS = {".godot", "addons", ".git", "tools"}


def scan(path):
    """逐行扫。⚠️ 要处理**跨行调用**：`T.t("K",\n\t\t"中文")` 的第二行没有 `T.t(`，
    不连着算就会被误报成「未迁移」—— 用括号深度判断是否还在上一次取词里。"""
    out = []
    src = io.open(path, encoding="utf-8").read()
    depth = 0
    for i, line in enumerate(src.splitlines(), 1):
        s = line.strip()
        code = line.split("#")[0]
        if s.startswith("#"):
            continue
        if depth <= 0 and ("T.t(" in code or "TEXT.t(" in code or "TERMS." in code):
            depth = code.count("(") - code.count(")")
            if depth < 0:
                depth = 0
            continue
        if depth > 0:
            depth += code.count("(") - code.count(")")
            continue
        for m in STR.finditer(code):
            v = m.group(1)
            if CN.search(v):
                out.append((i, v))
    return out


def main():
    args = sys.argv[1:]
    if args:
        files = [os.path.join(ROOT, a) for a in args]
    else:
        files = []
        for dp, dns, fns in os.walk(ROOT):
            dns[:] = [d for d in dns if d not in SKIP_DIRS]
            for fn in fns:
                if fn.endswith(".gd"):
                    files.append(os.path.join(dp, fn))
    total = 0
    per = []
    for f in sorted(files):
        if not os.path.isfile(f):
            continue
        hits = scan(f)
        if hits:
            per.append((os.path.relpath(f, ROOT), hits))
            total += len(hits)
    for rel, hits in sorted(per, key=lambda x: -len(x[1])):
        print("=== %s（%d 条）===" % (rel, len(hits)))
        for i, v in hits[:40]:
            print("  %5d  %s" % (i, v))
        if len(hits) > 40:
            print("  … 还有 %d 条" % (len(hits) - 40))
    print("\n合计 %d 条（分布在 %d 个文件）" % (total, len(per)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
