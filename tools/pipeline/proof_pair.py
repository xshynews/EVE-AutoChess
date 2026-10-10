# -*- coding: utf-8 -*-
"""proof_pair.py —— 「现在的游戏姿态」vs「按 `_e` 判据修正后的姿态」并排对照。

同一机位（前上右 3/4，az=237 el=-22 ⇒ 相机在 +Z/+X/+Y 侧看**舰艏**）。
        · 左格（现在）   ：如果这艘船是**对的**，你应该看到船头
        · 右格（修正后） ：如果判据是对的，这一格才是船头
两格里哪一格是船头，用户一眼就能认（长叉 / 引擎喷口 / 官方立绘记忆）。

红块 = `_e` 自发光面（发动机喷口就在里面）。
"""
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, r'C:\godot\_export')
from glow_probe import gather, load_glb, font                      # noqa: E402
from pose_sheet import (parse_table, spec_rows, ry, src_texture,   # noqa: E402
                        uv_sample, render, OUT, GLB_DIR, THR)

SHIPS = sys.argv[1:] or ['rifter', 'punisher', 'executioner',
                         'hyperion', 'typhoon', 'megathron']
RES = r'C:\godot\_export\_proof.png'


def pose(P, NR, yaw, M):
    T = ry(yaw) @ M
    Q = (T @ P.reshape(-1, 3).T).T.reshape(-1, 3, 3)
    return Q - np.array([0.0, 0.0, 0.5 * (Q[:, :, 2].min() + Q[:, :, 2].max())]), \
        (T @ NR.T).T


def main():
    deg, remap, flip, glob = parse_table()
    TW, TH = 540, 330
    HEAD = 76
    sheet = Image.new('RGB', (2 * TW + 24, HEAD + len(SHIPS) * (TH + 30)), (8, 10, 12))
    dr = ImageDraw.Draw(sheet)
    dr.text((14, 8), '左 = 现在游戏里的姿态（已按 `_e` 喷口判据修正）    右 = 在它之上再翻 180°（错的那版）',
            font=font(28), fill=(255, 235, 110))
    dr.text((14, 44), '同一机位（前上右 3/4 看舰艏）。红 = `_e` 自发光面 = 发动机喷口。'
                      '⇒ 喷口只该出现在**右**格（那是船尾转向镜头的姿态）。',
            font=font(20), fill=(150, 205, 255))

    for k, sid in enumerate(SHIPS):
        gp = os.path.join(GLB_DIR, sid + '.glb')
        js, bin_ = load_glb(gp)
        P, NR, UVC = gather(js, bin_)
        tex = src_texture(sid)
        g = uv_sample(tex, UVC) >= THR
        M = spec_rows(remap[sid]) if sid in remap else np.eye(3)
        yaw = -90.0 + deg.get(sid, 0.0) + (180.0 if sid in flip else 0.0) \
            + (180.0 if glob else 0.0)

        cells = [('现在（yaw=%.1f°）' % yaw, yaw),
                 ('再翻 180°（yaw=%.1f°）' % (yaw + 180.0), yaw + 180.0)]
        y = HEAD + k * (TH + 30)
        dr.text((14, y + 2), '%s   %s' % (sid, '表内 FLIP' if sid in flip else '不在 FLIP'),
                font=font(21), fill=(255, 238, 130))
        for c, (cap, yy) in enumerate(cells):
            Qs, NRq = pose(P, NR, yy, M)
            im = render(Qs, NRq, 237.0, -22.0, g, W=TW - 16)
            im.thumbnail((TW - 16, TH - 34))
            x = 12 + c * (TW + 12)
            sheet.paste(im, (x + 8, y + 28))
            dr.text((x + 8, y + 28 + max(im.height, 1) + 2), cap,
                    font=font(18), fill=(160, 210, 255))
    sheet.save(RES)
    print('[PROOF] -> %s  %dx%d' % (RES, sheet.width, sheet.height))


if __name__ == '__main__':
    main()
