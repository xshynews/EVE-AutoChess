# -*- coding: utf-8 -*-
"""multi_e_test.py —— 多套 `_e` 的船：逐张试，取「喷口最聚拢」的那套。

原理：多材质船的源目录里有多张 `_e`（同一 UV 图集的不同材质 set）。
     正确的那套会在**同一端聚出一簇法线平行于舰艏轴的自发光面**（= 发动机喷口）；
     不相干的那套只会给出散乱 / 抵消的结果。
     判据：coherence = |score2| × sqrt(n_noz)，最大者胜。

用法: python multi_e_test.py
"""
import os
import sys

import numpy as np

sys.path.insert(0, r'C:\godot\_export')
from PIL import Image                                          # noqa: E402
from glow_probe import gather, load_glb                        # noqa: E402
from pose_sheet import (parse_table, spec_rows, uv_sample,     # noqa: E402
                        area_ratio, nozzle_score, GLB_DIR, SRC_DIR, SRC_DIR2)

MULTI = ['maelstrom', 'omen', 'scythe', 'stabber', 'thorax']


def cand_list(sid):
    out = []
    for d in (os.path.join(SRC_DIR, sid, 'textures'),
              os.path.join(SRC_DIR2, sid, 'textures')):
        if os.path.isdir(d):
            for f in sorted(os.listdir(d)):
                if f.endswith('_e.png'):
                    out.append(os.path.join(d, f))
    return out


def load_e(path):
    return np.asarray(Image.open(path).convert('L'), dtype=np.float32) / 255.0


def main():
    deg, remap, flip, glob = parse_table()
    for sid in MULTI:
        gp = os.path.join(GLB_DIR, sid + '.glb')
        js, bin_ = load_glb(gp)
        P, NR, UVC = gather(js, bin_)
        M = spec_rows(remap[sid]) if sid in remap else np.eye(3)
        A = M[0]
        print('=' * 78)
        print('[%s] A(舰艏轴)=%s' % (sid, A))
        best = None
        for p in cand_list(sid):
            tex = load_e(p)
            g = uv_sample(tex, UVC) >= 0.30
            ng = int(g.sum())
            _, _, r1 = area_ratio(P, g, A)
            sc2, nnz, _ = nozzle_score(P, NR, g, A)
            coh = abs(sc2) * (nnz ** 0.5)
            mark = ''
            if best is None or coh > best[0]:
                best = (coh, os.path.basename(p), sc2, nnz, r1)
                mark = ''
            print('   %-28s 面=%4d  ratio1=%+0.2f  noz2=%+0.2f (n=%3d)  coherence=%6.1f'
                  % (os.path.basename(p), ng, r1, sc2, nnz, coh))
        if best:
            print('   ⇒ 最聚拢：%s  noz2=%+0.2f n=%d ⇒ 舰艏在 %s'
                  % (best[1], best[2], best[3],
                     '−A（需要翻 180°）' if best[2] > 0 else '+A（保持）'))


if __name__ == '__main__':
    main()
