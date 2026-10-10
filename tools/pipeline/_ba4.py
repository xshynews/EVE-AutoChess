# -*- coding: utf-8 -*-
"""_ba4.py —— 「两端上色」朝向判定卡（把歧义从肉眼读图里彻底移除）。

对某艘船渲染**当前落盘姿态**，并给模型自己的两端按 `AXIS_REMAP` 的**声明**上色：
    模型 **第 1 行那个轴的正端**（= 表里声明的**舰艏**）→ 涂 **红**
    它的负端（= 声明的**舰尾**）          → 涂 **绿**
再在世界 ±Z 放红 / 蓝球（+Z = 游戏前进方向）。

于是这张图只有两种结果，一眼可判：
    · **红端贴红球** ⇒ 声明的舰艏 = 游戏前进方向 ⇒ **姿态正确**
    · **红端贴蓝球** ⇒ 声明的舰艏朝后 ⇒ **倒飞**

用法: python _ba4.py myrmidon [改前|改后]
"""
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, r'C:\godot\_export')
import _vs_user                                                        # noqa: E402
from _pick4 import face_colors                                         # noqa: E402
from glow_probe import gather, load_glb, font                          # noqa: E402
from pose_sheet import parse_table, spec_rows, ry, GLB_DIR, MODEL_YAW_FIX  # noqa: E402

W = 620
_vs_user.W = W
OUT = r'C:\godot\_export'
RED = np.array([0.95, 0.16, 0.10], np.float32)
GRN = np.array([0.16, 0.85, 0.28], np.float32)


def sphere(c, r, n=8, m=12):
    P = []
    for i in range(n):
        t0, t1 = np.pi * i / n, np.pi * (i + 1) / n
        for j in range(m):
            p0, p1 = 2 * np.pi * j / m, 2 * np.pi * (j + 1) / m
            pts = []
            for (t, p) in ((t0, p0), (t1, p0), (t1, p1), (t0, p1)):
                pts.append(np.array([np.sin(t) * np.cos(p), np.cos(t),
                                     np.sin(t) * np.sin(p)]) * r + c)
            P.append([pts[0], pts[1], pts[2]])
            P.append([pts[0], pts[2], pts[3]])
    P = np.array(P)
    nn = np.cross(P[:, 1] - P[:, 0], P[:, 2] - P[:, 0])
    nn /= np.maximum(np.linalg.norm(nn, axis=1, keepdims=True), 1e-12)
    return P, nn


def axis_index(spec):
    """ret (axis, sign) —— spec 第一行 '±X' → 舰艏在模型该轴的正/负端。"""
    s = spec.split(',')[0].strip()
    return ('XYZ'.index(s[1].upper()), 1.0 if s[0] == '+' else -1.0)


def build(sid, ov):
    deg, remap, flipset, glob = parse_table()
    js, bin_ = load_glb(os.path.join(GLB_DIR, sid + '.glb'))
    P, NR, UVC = gather(js, bin_)
    cols, emis = face_colors(sid, UVC)
    spec = remap.get(sid)
    M = spec_rows(spec) if spec else np.eye(3)
    fl = (sid in flipset) if ov is None else ov
    yaw = (MODEL_YAW_FIX + deg.get(sid, 0.0)
           + (180.0 if fl else 0.0) + (180.0 if glob else 0.0))
    T = ry(yaw) @ M
    Q = (T @ P.reshape(-1, 3).T).T.reshape(-1, 3, 3)
    NRq = (T @ NR.T).T

    cols = np.array(cols, np.float32).copy()
    emis = np.array(emis, np.float32).copy()
    bow_note = '表里没有 AXIS_REMAP ⇒ 舰艏 = 模型 +X（基准态）'
    ax, sg = axis_index(spec) if spec else (0, 1.0)
    if spec:
        bow_note = 'AXIS_REMAP 第一行 = %s ⇒ 舰艏 = 模型 %s' % (
            spec.split(',')[0].strip(), spec.split(',')[0].strip())
    cen = P.mean(1)[:, ax] * sg                       # 沿舰艏-舰尾轴的**有向**坐标
    lo, hi = float(cen.min()), float(cen.max())
    tk = (hi - lo) * 0.22
    bow_m = cen > hi - tk
    stn_m = cen < lo + tk
    cols[bow_m] = RED
    cols[stn_m] = GRN
    emis[bow_m] = 0.35
    emis[stn_m] = 0.35

    # 声明轴 → 世界方向（用于打印）
    a3 = np.zeros(3)
    a3[ax] = sg
    aw = T @ a3
    print('[BA4] %s  %s' % (sid, bow_note))
    print('[BA4]   FLIP=%s yaw=%+.2f°   声明舰艏轴 → 世界 (%.2f, %.2f, %.2f)'
          % (fl, yaw, aw[0], aw[1], aw[2]))
    print('[BA4]   ⇒ 舰艏朝 %s（%s）'
          % ('+Z = 红球 = 游戏前进方向 ✓ 正确' if aw[2] > 0 else
             '−Z = 蓝球 = 游戏后退方向 ✗ 倒飞', 'aw_z=%.2f' % aw[2]))

    V = Q.reshape(-1, 3)
    c = V.mean(0)
    span = float(np.ptp(V, axis=0).max())
    lo_z, hi_z = V[:, 2].min(), V[:, 2].max()
    rad = 0.05 * span
    parts = [(Q, NRq, cols, emis)]
    for zz, col in ((hi_z + rad * 1.45, (1.0, 0.16, 0.10)),
                    (lo_z - rad * 1.45, (0.16, 0.44, 1.0))):
        sp, sn = sphere(np.array([c[0], c[1], zz]), rad)
        parts.append((sp, sn, np.tile(np.array(col, np.float32), (len(sp), 1)),
                      np.full(len(sp), 0.5, np.float32)))
    return (np.vstack([p[0] for p in parts]), np.vstack([p[1] for p in parts]),
            np.vstack([p[2] for p in parts]), np.concatenate([p[3] for p in parts]), aw)


def main():
    sid = sys.argv[1] if len(sys.argv) > 1 else 'myrmidon'
    which = sys.argv[2] if len(sys.argv) > 2 else '改后'
    ov = None if which == '改后' else True
    P, NR, C, E, aw = build(sid, ov)

    tiles = []
    for az, el, up, cap in ((90.0, 90.0, (0.0, 0.0, 1.0), '俯视（画面正上方 = +Z）'),
                            (0.0, 14.0, None, '侧视（相机在 +X 侧）')):
        im = _vs_user.render_persp(P, NR, C, E, az, el, dist_k=2.0, fov=32.0,
                                   ball=False, bg=(10, 12, 16), up_hint=up)
        im = im.resize((W, max(40, int(im.height * W / im.width))), Image.LANCZOS)
        t = Image.new('RGB', (W, im.height + 62), (8, 10, 12))
        t.paste(im, (0, 62))
        d = ImageDraw.Draw(t)
        d.text((8, 4), '%s · %s' % (sid, cap), font=font(20), fill=(215, 228, 245))
        d.text((8, 30), '红端 = 表里声明的舰艏　绿端 = 舰尾　'
                        '红球 = +Z = 游戏前进方向', font=font(16), fill=(180, 200, 225))
        tiles.append(t)

    H = max(t.height for t in tiles)
    card = Image.new('RGB', (W * 2 + 16, H + 78), (6, 8, 11))
    d = ImageDraw.Draw(card)
    d.text((12, 6), '%s —— 姿态「%s」· 两端上色判定' % (sid, which), font=font(26),
           fill=(255, 236, 120))
    d.text((12, 42), '表里声明的舰艏轴 → 世界 %s ；⇒ %s'
           % (str(np.round(aw, 2)),
              '舰艏朝红球（+Z）**正确**' if aw[2] > 0
              else '舰艏朝蓝球（−Z）**倒飞**'),
           font=font(20), fill=(130, 245, 160) if aw[2] > 0 else (255, 150, 120))
    for i, t in enumerate(tiles):
        card.paste(t, (i * (W + 16), 78))
    p = os.path.join(OUT, '_ba4_%s_%s.png' % (sid, which))
    card.save(p)
    print('[BA4] -> %s (%dx%d)' % (p, card.width, card.height))


if __name__ == '__main__':
    main()
