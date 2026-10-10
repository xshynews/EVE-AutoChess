#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""48 轮：把「高度轴 != up 轴」的船的 up 改成高度轴（最薄轴）。

口径：出厂坐标系里 EVE 舰船是**平铺**的 —— 三轴 = 机身(最长) / 翼展 / 高度(最薄)。
      `SHIP_AXES` 的 up 必须是**高度轴**。
      违反不报错：up 落在宽度轴上 ⇒ 船**肚皮朝天**（48 轮用户实机现象）。

落盘方式（48 轮教训）：**只按行号逐行替换，其余字节原样**。
      禁止整段正则抓取 + 重写（两张表形态相同，非贪婪正则极易抓错块 ⇒ 曾把文件截成 1 行）。
"""
import io, os, re, sys
import numpy as np
sys.path.insert(0, r'C:/godot/_export')
from glow_probe import gather, load_glb

YAW_GD = r'F:/evezzq/eve自走棋918/scripts/data/eve_ship_yaw.gd'
GLB_DIR = r'F:/evezzq/eve自走棋918/assets/ships3d'

ROW_RE = re.compile(r'^(\t&"([a-z0-9_]+)":\s*"bow:([-+][XYZ]) up:)([-+][XYZ])(".*)$')

# 逐条确认名单：只改这两类，其余任何偏移都打印出来要求人工判读
#   ① up 落在宽度轴上（高度轴不是 Y）⇒ 必改
#   ② up 仍在 Y 轴但高度轴不是 Y  ⇒ 必改
# 例外：用户实机终审过的船（kestrel/slasher 23/24 轮）走同一条规则，结果一致


def metrics(sid, cache={}):
    if sid in cache:
        return cache[sid]
    gp = os.path.join(GLB_DIR, sid + '.glb')
    if not os.path.exists(gp):
        sys.exit('缺 glb: ' + sid)
    js, b = load_glb(gp)
    P, _, _ = gather(js, b)
    P = P.reshape(-1, 3)
    d = P.max(0) - P.min(0)
    res = ('XYZ'[int(np.argmin(d))], d)
    cache[sid] = res
    return res


def main(apply=False):
    lines = io.open(YAW_GD, encoding='utf-8').read().split('\n')
    # 定位 SHIP_AXES 块的行号区间（只用于限定搜索范围，不做任何重写）
    start = end = None
    for i, ln in enumerate(lines):
        if ln.startswith('const SHIP_AXES := {'):
            start = i
        elif start is not None and ln.startswith('}'):
            end = i
            break
    if start is None or end is None:
        sys.exit('找不到 SHIP_AXES 块')
    print('SHIP_AXES 行区间: %d..%d' % (start + 1, end + 1))

    plan = []
    for i in range(start + 1, end):
        m = ROW_RE.match(lines[i])
        if not m:
            continue
        sid, bow, up = m.group(2), m.group(3), m.group(4)
        thin, d = metrics(sid)
        if up[1] == thin:      # 符号不管，轴对就行（up 只关心「哪根轴」）
            continue
        plan.append((i, sid, bow, up, thin, d))

    if not plan:
        print('无需修改（全库 up 已都是高度轴）')
        return
    print('待改 %d 艘：' % len(plan))
    for i, sid, bow, up, thin, d in plan:
        print('  %-12s up:%s → up:%s   (高度轴 %s 尺寸 %.1f | 三轴 %.1f/%.1f/%.1f)'
              % (sid, up, '+' + thin, thin, d['XYZ'.index(thin)], d[0], d[1], d[2]))

    if not apply:
        print('\n[dry-run] 加 --apply 才写盘')
        return

    for i, sid, bow, up, thin, d in plan:
        m = ROW_RE.match(lines[i])
        lines[i] = m.group(1) + '+' + thin + m.group(5)
    io.open(YAW_GD, 'w', encoding='utf-8', newline='\n').write('\n'.join(lines))
    print('\n已落盘 %s' % YAW_GD)


if __name__ == '__main__':
    main(apply='--apply' in sys.argv)
