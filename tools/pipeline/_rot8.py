# -*- coding: utf-8 -*-
"""_rot8.py —— 「长轴竖直」前提下的 8 种正交变体（舰艏朝上/朝下 × 绕长轴 4 个 roll）。

用户口径（2026-09-26 第七轮）：弥尔米顿在 EVE 里是「竖着飞」（长轴竖直），
上一版 `_v6.py` 第 3 行只把长轴立起来、没有绕长轴转 ⇒ 俯视/仰视里翼展是横向摊开的，
与用户实机图（竖向）差 90°。本表把这一自由度穷举。

行 = 姿态变体，列 = 与 `_v6.py` 完全相同的 6 个机位。
用法: python _rot8.py myrmidon
"""
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, r'C:\godot\_export')
from glow_probe import gather, load_glb, font                          # noqa: E402
from pose_sheet import GLB_DIR, render                                 # noqa: E402

OUT = r'C:\godot\_export'
CLIP = r'C:\Users\Administrator\.workbuddy\clipboard-images'
IMG_W = 460
CELL = 330
HDR = 66
ROWLAB = 26

USER6 = [
    ('正视图', 'clipboard-2026-09-26T08-58-52-231Z-1d2a769f.png'),
    ('后视图', 'clipboard-2026-09-26T08-58-52-240Z-9d9ae866.png'),
    ('左视图', 'clipboard-2026-09-26T08-58-52-233Z-3e37cad6.png'),
    ('右视图', 'clipboard-2026-09-26T08-58-52-236Z-1ae5abd8.png'),
    ('俯视图', 'clipboard-2026-09-26T08-58-52-238Z-fcb6d867.png'),
    ('仰视图', 'clipboard-2026-09-26T08-58-52-239Z-a8abc257.png'),
]
VIEWS = [
    ('cam+X', 180.0, 0.0),
    ('cam-X', 0.0, 0.0),
    ('cam-Z', 90.0, 0.0),
    ('cam+Z', 270.0, 0.0),
    ('cam+Y', 180.0, -90.0),
    ('cam-Y', 180.0, 90.0),
]


def rx(a):
    c, s = np.cos(np.radians(a)), np.sin(np.radians(a))
    return np.array([[1.0, 0.0, 0.0], [0.0, c, -s], [0.0, s, c]])


def ry(a):
    c, s = np.cos(np.radians(a)), np.sin(np.radians(a))
    return np.array([[c, 0.0, s], [0.0, 1.0, 0.0], [-s, 0.0, c]])


def rz(a):
    c, s = np.cos(np.radians(a)), np.sin(np.radians(a))
    return np.array([[c, -s, 0.0], [s, c, 0.0], [0.0, 0.0, 1.0]])


def variant(P, NR, down, roll):
    """先把模型长轴(X)搬到世界 ±Y，再绕世界 Y 转 roll 度。"""
    R0 = rz(-90.0) if down else rz(90.0)          # X -> ∓Y
    R = ry(roll) @ R0
    return P @ R.T, NR @ R.T


def fit(im, box):
    k = min(box / im.width, box / im.height)
    return im.resize((max(1, round(im.width * k)), max(1, round(im.height * k))),
                     Image.LANCZOS)


def main():
    sid = sys.argv[1] if len(sys.argv) > 1 else 'myrmidon'
    js, bin_ = load_glb(os.path.join(GLB_DIR, sid + '.glb'))
    P, NR, _ = gather(js, bin_)
    zero = np.zeros(len(P), bool)

    rows = []
    for down in (False, True):
        for roll in (0.0, 90.0, 180.0, 270.0):
            rows.append((down, roll))

    cols = len(VIEWS)
    row_h = CELL + ROWLAB
    sheet = Image.new('RGB', (cols * CELL, HDR + (1 + len(rows)) * row_h + 10),
                      (8, 10, 12))
    dr = ImageDraw.Draw(sheet)
    dr.text((8, 6), '%s · 长轴竖直 8 变体：你的 EVE 图 vs 绕长轴 4 个 roll × 舰艏上/下'
            % sid, font=font(22), fill=(255, 236, 130))
    dr.text((8, 34), '第 1 行 = 你的实机图；下列每格共用完全相同的 6 个机位。'
            '重点看「俯视图 / 仰视图」两列里翼展是竖还是横',
            font=font(15), fill=(150, 205, 255))
    for c, (lab, _) in enumerate(USER6):
        dr.text((c * CELL + 8, HDR - 22), lab, font=font(19), fill=(255, 236, 130))

    box = CELL - 12
    for c in range(cols):
        y0 = HDR
        dr.rectangle([c * CELL + 2, y0 + ROWLAB, (c + 1) * CELL - 4, y0 + ROWLAB + CELL],
                     outline=(46, 56, 72))
        im = Image.open(os.path.join(CLIP, USER6[c][1])).convert('RGB')
        im = fit(im, box)
        sheet.paste(im, (c * CELL + (CELL - 4 - im.width) // 2 + 1,
                         y0 + ROWLAB + (CELL - im.height) // 2))

    for r, (down, roll) in enumerate(rows):
        y0 = HDR + (r + 1) * row_h
        dr.text((8, y0 + 5), '舰艏朝%s · roll %d°' % ('下' if down else '上', int(roll)),
                font=font(18), fill=(190, 205, 225))
        for c in range(cols):
            dr.rectangle([c * CELL + 2, y0 + ROWLAB, (c + 1) * CELL - 4, y0 + ROWLAB + CELL],
                         outline=(46, 56, 72))
        Pv, NRv = variant(P, NR, down, roll)
        for c in range(cols):
            _, az, el = VIEWS[c]
            im = render(Pv, NRv, az, el, zero, W=IMG_W).convert('RGB')
            im = fit(im, box)
            sheet.paste(im, (c * CELL + (CELL - 4 - im.width) // 2 + 1,
                             y0 + ROWLAB + (CELL - im.height) // 2))

    p = os.path.join(OUT, '_rot8_%s.png' % sid)
    sheet.save(p)
    print('[ROT8] -> %s (%dx%d)' % (p, sheet.width, sheet.height))


if __name__ == '__main__':
    main()
