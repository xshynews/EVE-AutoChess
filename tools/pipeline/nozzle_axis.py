# -*- coding: utf-8 -*-
"""nozzle_axis.py —— 用**有向**喷口法线反解「模型舰艏轴的真实偏角 δ」。

════════════════════════════════════════════════════════════════
 它替掉的是一段同义反复
════════════════════════════════════════════════════════════════
`axis_nozzle.py` 里写过：

        sgn = np.sign(NR[sel] @ A)
        nbar = (w[:,None] * sgn[:,None] * NR[sel]).sum(0)

那个 `sgn` 会把**所有面强制翻到 +A 侧** ⇒ `nbar ≈ +A` 恒成立 ⇒ 它打印的
「轴向方位」恒等于 `−yaw`、「应补Δ」恒等于 `−AXIS_DEG`。
它看起来「45 艘都与 −AXIS_DEG 吻合到 0.05°」不是因为发现了什么，
而是因为它**恒等式**。⇒ 该模块整体作废，判据以本模块为准。

════════════════════════════════════════════════════════════════
 本模块的口径
════════════════════════════════════════════════════════════════
取 `_e` 自发光且 `|NR·A| > MIN_COS` 的面（A = AXIS_REMAP 第一行 = 舰艏轴），
求**有向**面积加权和 `v = Σ w·NR`（不翻符号）。发动机喷口朝外 ⇒ `v ≈ −A′`，
其中 A′ 是**真实的**舰艏轴。把 v 在 (A, 侧向) 平面内分解：

        va = v·A,  vb = v·M[2]
        ang = atan2(vb, va)          # v 相对 A 的方位角，理想 = 180°
        δ  = reduce180(ang − 180)    # ⇒ 真实舰艏轴 = A 绕 up 转 δ

要让舰艏落到世界 +Z（游戏前方），需要 `AXIS_DEG = δ`（**绝对量**，与旧值无关）。

⚠️ 前提：喷口面**集中在一端**。否则 v 被两端抵消。
   用 `conc = |v| / Σw` 度量集中度，`conc < MIN_CONC(<0.2)` 的结果不可信。
⚠️ 它依赖 `A` 只用来**选面**（|NR·A|>0.6），A 差几十度内都还能选对；
   但 A 差 90° 就会选错面 ⇒ 与 PCA / 轮廓镜像都**独立**，三条互为对照。
⚠️ 符号约定以对照组为准（rifter / punisher / hyperion / apocalypse 必须给 |δ|<0.3°）。

用法: python nozzle_axis.py [ship_id ...]
"""
import os
import sys

import numpy as np

sys.path.insert(0, r'C:\godot\_export')
from glow_probe import gather, load_glb                              # noqa: E402
from pose_sheet import (parse_table, spec_rows, tri_area, uv_sample,  # noqa: E402
                        GLB_DIR, THR_LIST)
from review_sheet import parse_index, best_e                         # noqa: E402

MIN_F = 4          # 喷口面数下限
MIN_COS = 0.60     # 只取法线沿轴的自发光面
MIN_CONC = 0.20    # 集中度下限


def reduce180(d):
    d = (d + 90.0) % 180.0 - 90.0
    return 90.0 if abs(d + 90.0) < 1e-9 else d


def solve(sid, P, NR, UVC, M):
    A = M[0]
    b = M[2]
    tex, note = best_e(sid, P, NR, UVC, A)
    if tex is None:
        return None
    g = uv_sample(tex, UVC)
    w_all = tri_area(P)
    best = None
    for thr in THR_LIST:
        sel = (g >= thr) & (np.abs(NR @ A) > MIN_COS)
        n = int(sel.sum())
        if n < MIN_F:
            continue
        w = w_all[sel]
        v = (w[:, None] * NR[sel]).sum(0)
        sw = float(w.sum())
        ln = float(np.linalg.norm(v))
        if ln < 1e-9 or sw <= 0:
            continue
        conc = ln / sw
        u = v / ln
        va, vb = float(u @ A), float(u @ b)
        ang = float(np.degrees(np.arctan2(vb, va)))
        d = reduce180(ang - 180.0)
        if best is None or conc > best['conc']:
            best = dict(thr=thr, n=n, conc=conc, ang=ang, d=d, note=note)
    return best


def main():
    want = set(sys.argv[1:])
    deg, remap, flip, glob = parse_table()
    ships = [s for s in parse_index() if (not want or s['id'] in want)]
    print('[NAX] 轴偏 δ = 用有向喷口法线反解的真实舰艏轴偏角；'
          '「应改」= 它认为 AXIS_DEG 该是几（绝对量）')
    print('[NAX] %-13s %-9s %8s %5s %5s %9s %7s %9s %8s  %s'
          % ('id', '中文', '表值', '面数', '档', '轴偏δ', '集中度', '应改', '差', '结论'))

    rows = []
    for s in ships:
        sid = s['id']
        gp = os.path.join(GLB_DIR, sid + '.glb')
        if not os.path.exists(gp):
            continue
        js, bin_ = load_glb(gp)
        P, NR, UVC = gather(js, bin_)
        M = spec_rows(remap[sid]) if sid in remap else np.eye(3)
        r = solve(sid, P, NR, UVC, M)
        old = deg.get(sid, 0.0)
        if r is None:
            print('[NAX] %-13s %-9s 无可用判据' % (sid, s['cn']))
            continue
        weak = ' ⚠弱(集中度低)' if r['conc'] < MIN_CONC else ''
        dlt = r['d'] - old
        tag = ('⚠ 差 %+.2f' % dlt) if abs(dlt) > 1.2 else 'ok'
        rows.append((sid, s['cn'], old, r['d'], dlt, r['conc']))
        print('[NAX] %-13s %-9s %+8.2f %5d %5.2f %+9.2f %7.3f %+9.2f %+7.2f  %s%s'
              % (sid, s['cn'], old, r['n'], r['thr'], r['d'], r['conc'],
                 r['d'], dlt, tag, weak))
    print('')
    bad = [r for r in rows if abs(r[4]) > 1.2]
    print('[NAX] ═══ 与表值差 >1.2° 的 %d 艘 ═══' % len(bad))
    for sid, cn, old, new, dlt, conc in bad:
        print('[NAX]    %-13s %-9s %+7.2f → %+7.2f  (差 %+6.2f, 集中度 %.3f)'
              % (sid, cn, old, new, dlt, conc))
    print('[NAX] ==== DONE ====')


if __name__ == '__main__':
    main()
