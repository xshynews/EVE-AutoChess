# -*- coding: utf-8 -*-
"""设计数据表 → Godot 数据文件：**舰船表**（`scripts/data/eve_ship_table.gd`）。

## 它解决什么

`data/README.md` 一直挂着这条待办：设计表（`data/source_csv/01_舰船数值全表.csv`）
与代码里的 `eve_ship_table.gd` **必须人工保持同步** —— 改一个数要改两处，
漏一处就静默漂移（2026-10-12 实际踩到：`executioner` 中文名、`arbitrator`/`maller`
两处口径不一致，靠 `verify_data_source` 的白名单才没红）。

## 两个模式（默认**只读**，⛔ 不写盘）

    python _gen_ship_table.py             # 校验：逐行逐列比 CSV 与 .gd，不一致 ⇒ 退出码 1
    python _gen_ship_table.py --write     # 生成：把 ROWS 行块按 CSV 重写（语义不变）

⚠️ `--write` 会**重排行内空白**（统一成生成器自己的对齐格式，两列宽固定），
   语义一个字节都不变；但它**默认拒绝**覆盖「行块里有手工注释」的文件
   （防误删解释性注释），确实要覆盖就再加 `--force`。

## 列口径

CSV 表头（14 列，第一列带 BOM）：
`船ID, 中文名, 势力, 武器, 防御, 费用, 定位, 护盾, 装甲/结构, 攻击, 射程, 移速, 攻击间隔, 后勤`
与 `eve_ship_table.gd` 的 `COLUMNS` 一一对应（顺序、类型都一致）。
"""
import argparse
import io
import os
import re
import sys
import unicodedata

from _paths import ROOT

CSV = os.path.join(ROOT, "data", "source_csv", "01_舰船数值全表.csv")
GD = os.path.join(ROOT, "scripts", "data", "eve_ship_table.gd")

## 列类型：s=字符串 i=整数 f=浮点 b=布尔（与 verify_data_source 的映射表同口径）
COLS = [
    ("船ID", "s"), ("中文名", "s"), ("势力", "s"), ("武器", "s"), ("防御", "s"),
    ("费用", "i"), ("定位", "s"), ("护盾", "i"), ("装甲/结构", "i"), ("攻击", "i"),
    ("射程", "i"), ("移速", "f"), ("攻击间隔", "i"), ("后勤", "b"),
]

## 吨位（= 费用档）中文名 —— 与 `eve_ship_table.gd` 的 `CLASS_NAMES_BY_COST` 同口径
CLASS_CN = {1: "护卫舰", 2: "驱逐舰", 3: "巡洋舰", 4: "战列巡洋舰", 5: "战列舰"}

MARK_HEAD = "const ROWS: Array = ["
MARK_END = "\n]"


def disp_w(s):
    """显示宽度（CJK 算 2 列）—— 对齐用。"""
    return sum(2 if unicodedata.east_asian_width(c) in "WF" else 1 for c in s)


def pad(s, width):
    return s + " " * max(0, width - disp_w(s))


def read_csv():
    rows = []
    with io.open(CSV, encoding="utf-8-sig") as f:
        lines = [l.rstrip("\n") for l in f if l.strip()]
    head = lines[0].split(",")
    if head[:2] != ["船ID", "中文名"]:
        raise SystemExit("✗ CSV 表头不对：%s" % head[:3])
    for ln in lines[1:]:
        c = ln.split(",")
        if len(c) < 14:
            raise SystemExit("✗ CSV 行不足 14 列：%s" % ln)
        rows.append(c[:14])
    return rows


def to_typed(cells):
    out = []
    for v, (_, t) in zip(cells, COLS):
        v = v.strip()
        if t == "i":
            out.append(int(float(v)))
        elif t == "f":
            out.append(round(float(v), 2))
        elif t == "b":
            out.append(v.lower() in ("true", "1", "是"))
        else:
            out.append(v)
    return out


def parse_gd_rows():
    """解析 .gd 里 `const ROWS` 的 52 行（宽松：只取 `\t[` 开头的行）。"""
    txt = io.open(GD, encoding="utf-8").read()
    i = txt.index(MARK_HEAD)
    j = txt.index(MARK_END, i)
    body = txt[i:j]
    rows = []
    for ln in body.splitlines():
        s = ln.strip()
        if not s.startswith("["):
            continue
        cells, cur, q = [], "", False
        for ch in s[1:-2]:
            if ch == '"':
                q = not q
                cur += ch
            elif ch == "," and not q:
                cells.append(cur.strip())
                cur = ""
            else:
                cur += ch
        cells.append(cur.strip())
        rows.append([c.strip('"') if c.startswith('"') else c for c in cells])
    return rows, txt, i, j


def _row_line(r):
    return ('\t[%s, %s, %s, %s, %s, %d, %s, %s, %s, %s, %s, %s, %s, %s],' % (
        pad('"%s"' % r[0], 14), pad('"%s"' % r[1], 13), pad('"%s"' % r[2], 11),
        pad('"%s"' % r[3], 9), pad('"%s"' % r[4], 7), r[5],
        pad('"%s"' % r[6], 9),
        pad("%d" % r[7], 4), pad("%d" % r[8], 4), pad("%d" % r[9], 4),
        pad("%d" % r[10], 3), pad("%.2f" % r[11], 5), pad("%d" % r[12], 3),
        "true" if r[13] else "false"))


def diff_rows(csv_rows, gd_rows):
    """逐行逐列比（类型感知）。返回差异描述列表。"""
    out = []
    if len(csv_rows) != len(gd_rows):
        out.append("行数不同：CSV %d / .gd %d" % (len(csv_rows), len(gd_rows)))
    for k, (a, b) in enumerate(zip(csv_rows, gd_rows)):
        ta = to_typed(a)
        for idx, (v0, v1) in enumerate(zip(ta, b)):
            # .gd 侧统一转成与 CSV 同类型再比
            name, t = COLS[idx]
            try:
                cv = int(float(v1)) if t == "i" else (
                    round(float(v1), 2) if t == "f" else (
                        str(v1).lower() in ("true", "1") if t == "b" else str(v1)))
            except ValueError:
                cv = v1
            if cv != v0:
                out.append("第 %d 行 %s 的「%s」：CSV=%r / .gd=%r"
                           % (k + 1, ta[0], name, v0, cv))
    return out


def build_block(rows):
    """按费用分档生成行块（含分档小标题）。"""
    lines = []
    for cost in sorted({r[5] for r in rows}):
        grp = [r for r in rows if r[5] == cost]
        lines.append("\t# %s %s cost %d（%d 艘）"
                     % ("═" * 38, CLASS_CN.get(cost, "?"), cost, len(grp)))
        lines += [_row_line(r) for r in grp]
    return "\n".join(lines)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--write", action="store_true", help="按 CSV 重写 ROWS 行块")
    ap.add_argument("--force", action="store_true", help="允许覆盖含手工注释的行块")
    a = ap.parse_args()

    csv_rows = read_csv()
    gd_rows, txt, i, j = parse_gd_rows()
    diffs = diff_rows(csv_rows, gd_rows)

    if not a.write:
        if diffs:
            print("✗ CSV 与 %s 不一致（%d 处）：" % (os.path.basename(GD), len(diffs)))
            for d in diffs[:20]:
                print("   ", d)
            print("⇒ 改设计表后请跑：python tools/pipeline/_gen_ship_table.py --write")
            return 1
        print("✓ 舰船表与设计表一致（%d 艘 · 14 列逐格比对）" % len(csv_rows))
        return 0

    # --write：装配新文件（保住头尾，替换行块）
    body = txt[i:j]
    hand = [l for l in body.splitlines()
            if l.strip().startswith("#") and "═" not in l]
    if hand and not a.force:
        print("✗ 行块里有 %d 行手工注释（例如 %r）——" % (len(hand), hand[0].strip()[:36]))
        print("  ⛔ 直接重写会丢掉它们。确认要覆盖就再加 --force。")
        return 2
    new = txt[:i] + MARK_HEAD + "\n" + build_block([to_typed(r) for r in csv_rows]) + txt[j:]
    io.open(GD, "w", encoding="utf-8", newline="\n").write(new)
    print("✓ 已按设计表重写 %s（%d 艘）" % (os.path.basename(GD), len(csv_rows)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
