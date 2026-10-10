# -*- coding: utf-8 -*-
"""sym_audit.py —— 用「镜像对称」独立测每艘船的**偏斜**（既不靠自发光，也不靠表）。

════════════════════════════════════════════════════════════════
 物理前提
════════════════════════════════════════════════════════════════
舰船关于自己的**中纵剖面**（同时含「上下轴」与「舰艏轴」的那个竖直面）镜像对称。
⇒ 把船按表的姿态摆好、**俯视投影成实心轮廓**，再问：
   「把轮廓转多少度，它关于竖直中线的镜像重合度最高？」
   那个角就是船的**横向轴**偏角 φ。

   横向轴必须落在世界 ±X 上（中纵剖面该是 x=0 平面）⇒ φ≠0 就是**歪的**。

⚠️ 为什么用**实心轮廓**而不是「三角形重心的点云直方图」（第一版）：
   点云分布会被机翼薄板 / 内部非对称件（天线、炮塔）带偏，细条船更糟 ——
   实测 catalyst 的点云版给出假的 −87°，而它的俯视轮廓明明是正的正条。
   实心轮廓由船的外壳决定 ⇒ 对内部不对称免疫，且**在图像上转一下**就等于
   「绕世界 Y 转一下」（俯视投影下两者等价）⇒ 又快又能扫到 0.02°。

⚠️ 这个量**与「舰艏在哪端」无关**（横向轴反向 180° 是同一个平面）
   ⇒ 它与 `FLIP` 名单**解耦**：本脚本只回答「歪不歪、歪多少」，不回答「该不该翻」。

⚠️ 它也和 `_e` 自发光判据、PCA 主轴**完全独立**（第三条证据链）。
   PCA 会被翼展带偏（kestrel 翼展 172 > 机身 81.6），本方法不会。

口径（符号要记牢）：
    Δ > 0 ⇒ 应把船**顺时针**转（俯视图里 +X 在屏幕右、+Z 在屏幕上）
    需要的新 AXIS_DEG ≈ 旧的 AXIS_DEG + Δ

用法:
    python sym_audit.py [ship_id ...]        不给参数 = 全 52 艘
    python sym_audit.py --img <id>           额外落盘「俯视轮廓 + 最佳对称轴」对照图
"""
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, r'C:\godot\_export')
from glow_probe import gather, load_glb                                  # noqa: E402
from pose_sheet import (parse_table, spec_rows, ry, tri_area, dom_axis,   # noqa: E402
                        GLB_DIR, MODEL_YAW_FIX, font)
from review_sheet import parse_index                                     # noqa: E402

W = 460                # 轮廓画布宽
COARSE = 0.50          # 粗扫步长（度）
FINE = 0.02            # 精扫步长（度）
GOOD = 1.20            # |Δ| ≤ 此值 ⇒ 判「正」（1.2° 是肉眼看不出的量级）
OUT = r'C:\godot\_export\_sym'


def footprint(Q):
    """俯视实心轮廓（白 = 船）。屏幕右 = 世界 +X，屏幕上 = 世界 +Z。"""
    x, z = Q[:, :, 0], Q[:, :, 2]
    x0, x1 = float(x.min()), float(x.max())
    z0, z1 = float(z.min()), float(z.max())
    pad = 0.06 * max(x1 - x0, z1 - z0)
    span = max(x1 - x0, z1 - z0) + 2 * pad
    sc = W / span
    H = max(64, int(round((z1 - z0) + 2 * pad) * sc))
    ox = W * 0.5 - (x0 + x1) * 0.5 * sc
    oy = H * 0.5 + (z0 + z1) * 0.5 * sc          # 屏幕 y 向下 ⇒ 取负
    img = Image.new('L', (W, H), 0)
    dr = ImageDraw.Draw(img)
    for i in range(len(Q)):
        dr.polygon([(ox + x[i, k] * sc, oy - z[i, k] * sc) for k in range(3)], fill=255)
    return img


def iou(img_rot):
    A = np.asarray(img_rot, dtype=np.uint8) > 127
    B = A[:, ::-1]
    u = int(np.logical_or(A, B).sum())
    return float(np.logical_and(A, B).sum() / u) if u else 0.0


def sym_angle(mask, lo=0.0, hi=180.0, step=COARSE):
    """扫出使「轮廓 ≅ 自身左右镜像」的旋转角（PIL 的 rotate 正方向 = 逆时针 = +φ）。"""
    c = (mask.width * 0.5, mask.height * 0.5)
    best, ba = -1.0, 0.0
    for d in np.arange(lo, hi, step):
        s = iou(mask.rotate(float(d), center=c, resample=Image.NEAREST,
                            fillcolor=0))
        if s > best:
            best, ba = s, float(d)
    return ba, best


def reduce180(d):
    """归一化到 (−90, +90] —— 同一个平面的最近表示。"""
    d = (d + 90.0) % 180.0 - 90.0
    return 90.0 if abs(d + 90.0) < 1e-9 else d


def main():
    argv = sys.argv[1:]
    want_img = '--img' in argv
    only = [a for a in argv if not a.startswith('--')]
    deg, remap, flip, glob = parse_table()
    ships = parse_index()
    if only:
        ships = [s for s in ships if s['id'] in only]
    if want_img:
        os.makedirs(OUT, exist_ok=True)

    print('[SYM] 表: AXIS_DEG=%d REMAP=%d FLIP=%d GLOBAL_180=%s   判「正」阈值 |Δ|≤%.2f°'
          % (len(deg), len(remap), len(flip), glob, GOOD))
    print('[SYM] %-13s %-9s %7s %8s %8s %7s %-5s %s'
          % ('id', '中文', '现在yaw', '横向轴', 'Δ需修', '对称度', '长轴', '结论'))

    bad = []
    for s in ships:
        sid = s['id']
        gp = os.path.join(GLB_DIR, sid + '.glb')
        if not os.path.exists(gp):
            print('[SYM] %-13s glb 缺失' % sid); continue
        js, bin_ = load_glb(gp)
        P, NR, _ = gather(js, bin_)
        M = spec_rows(remap[sid]) if sid in remap else np.eye(3)
        yaw = MODEL_YAW_FIX + deg.get(sid, 0.0) \
            + (180.0 if sid in flip else 0.0) + (180.0 if glob else 0.0)

        Q = (ry(yaw) @ M @ P.reshape(-1, 3).T).T.reshape(-1, 3, 3)
        mask = footprint(Q)
        fill = float((np.asarray(mask) > 127).mean())
        a0, o0 = sym_angle(mask, 0.0, 180.0, COARSE)
        a1, o1 = sym_angle(mask, a0 - 2 * COARSE, a0 + 2 * COARSE, FINE)
        if o1 < o0:
            a1, o1 = a0, o0

        # 轮廓要转 a1 才正 ⇒ 船绕世界 Y 转 −a1 ⇒ Δ(yaw) = −a1
        dlt = reduce180(-a1)

        flat = P.reshape(-1, 3)
        wv, V = np.linalg.eigh(np.cov((flat - flat.mean(0)).T))
        p = V[:, int(np.argmax(wv))]

        # 判别可信度：轮廓填充率太低（几乎没盖住包围盒）或对称度太低都不可信
        weak = ' ⚠弱(填充%.0f%%)' % (fill * 100) if (o1 < 0.85 or fill < 0.10) else ''
        if abs(dlt) <= GOOD and not weak:
            verdict = '正'
        else:
            verdict = '歪 %.2f°（俯视图里应%s转）%s' % (
                abs(dlt), '顺' if dlt > 0 else '逆', weak)
            if abs(dlt) > GOOD:
                bad.append((sid, s['cn'], yaw, a1, dlt, o1, fill))
        print('[SYM] %-13s %-9s %7.2f %8.2f %+8.2f %7.4f %-5s %s'
              % (sid, s['cn'], yaw, a1, dlt, o1, dom_axis(p), verdict))

        if want_img:
            c = (mask.width * 0.5, mask.height * 0.5)
            rot = mask.rotate(a1, center=c, resample=Image.NEAREST, fillcolor=0)
            sheet = Image.new('RGB', (3 * W, mask.height + 54), (8, 10, 12))
            dr = ImageDraw.Draw(sheet)
            for k, (im, cap) in enumerate([(mask, '① 现在俯视轮廓'),
                                           (rot, '② 转 %.2f° 后' % a1),
                                           (rot.transpose(Image.FLIP_LEFT_RIGHT),
                                            '③ ②的左右镜像')]):
                rgb = Image.merge('RGB', (im, im, im))
                sheet.paste(rgb, (k * W, 54))
                dr.text((k * W + 8, 6), cap, font=font(20), fill=(160, 210, 255))
            dr.text((8, 30), '%s  Δ=%+.2f°  对称度=%.4f' % (sid, dlt, o1),
                    font=font(20), fill=(255, 235, 110))
            sheet.save(os.path.join(OUT, '%s.png' % sid))

    print('')
    print('[SYM] ═══ 结论 ═══')
    print('[SYM] 歪的 %d 艘 / 查了 %d 艘：' % (len(bad), len(ships)))
    for sid, cn, yaw, ax, dlt, ov, fill in bad:
        print('[SYM]    %-13s %-9s 现 yaw=%7.2f  应补 Δ=%+7.2f  对称度=%.4f 填充%.0f%%'
              % (sid, cn, yaw, dlt, ov, fill * 100))
    print('[SYM] ==== DONE ====')


if __name__ == '__main__':
    main()
