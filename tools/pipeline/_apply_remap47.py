#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""47 轮：把 probe_remap47 重算出的 52 条 spec 落盘进 eve_ship_yaw.gd 的 AXIS_REMAP。

口径（红线 40）：不解析、不推导，只做**字符串搬运** ——
  · 源 = remap47.txt（由 `tools/probe_remap47.tscn` 穷举 48 个 spec 得到）
  · 靶 = eve_ship_yaw.gd 里 `const AXIS_REMAP := {` ... `}` 之间的 52 行
  · 逐行按 id 配对：源里有、靶里也有的才替换；任一侧多/少 ⇒ 直接报错退出（不猜）。
"""
import io
import re
import sys

SRC = r"C:\Users\Administrator\AppData\Roaming\Godot\app_userdata\EVE自走棋918\bow_calib\remap47.txt"
DST = r"F:\evezzq\eve自走棋918\scripts\data\eve_ship_yaw.gd"

# ── 读源：只取 `&"id": "spec",` 形态的行 ────────────────────────────
pat = re.compile(r'^\s*&"([a-z0-9_]+)":\s*"([-+][XYZ](?:,[-+][XYZ]){2})",\s*$')
new = {}
with io.open(SRC, encoding="utf-8") as f:
    for ln in f:
        m = pat.match(ln)
        if m:
            new[m.group(1)] = m.group(2)
if not new:
    sys.exit("源文件没解析出任何 spec（先跑 tools/probe_remap47.tscn）")
print("源 spec 条数 = %d" % len(new))

# ── 读靶 + 替换 ────────────────────────────────────────────────────
with io.open(DST, encoding="utf-8") as f:
    lines = f.readlines()

start = None
for i, ln in enumerate(lines):
    if ln.startswith("const AXIS_REMAP := {"):
        start = i
        break
if start is None:
    sys.exit("靶文件里没找到 `const AXIS_REMAP := {`")

end = None
for j in range(start + 1, len(lines)):
    if lines[j].startswith("}"):
        end = j
        break
if end is None:
    sys.exit("靶文件里 AXIS_REMAP 块没有收尾的 `}`")

hits = 0
seen = []
for k in range(start + 1, end):
    m = pat.match(lines[k])
    if not m:
        continue          # 不是 spec 行（注释 / 空行）⇒ 原样留着
    sid = m.group(1)
    seen.append(sid)
    if sid not in new:
        sys.exit("靶里有、源里没有的 id：%s —— 不猜，请重跑 probe_remap47" % sid)
    old_spec = m.group(2)
    new_spec = new[sid]
    if old_spec != new_spec:
        hits += 1
    lines[k] = '\t&"%s": "%s",\n' % (sid, new_spec)

missing = sorted(set(new) - set(seen))
if missing:
    sys.exit("源里有、靶里没有的 id：%s" % ", ".join(missing))
if len(seen) != len(new):
    sys.exit("条数不符：靶 %d / 源 %d" % (len(seen), len(new)))

with io.open(DST, "w", encoding="utf-8", newline="\n") as f:
    f.writelines(lines)
print("落盘完成：AXIS_REMAP 行 %d~%d，共 %d 条，其中 **改动 %d 条**"
      % (start + 2, end, len(seen), hits))
