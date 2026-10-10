# -*- coding: utf-8 -*-
"""全量抠图：EVE 官方 render 图 -> 透明底立绘（1:1 画布，512px）。
用 isnet-general-use 语义分割 + 最大连通域清理 + 边缘羽化 + 等比居中。
"""
import os, sys, time
import numpy as np
import cv2
from PIL import Image

sys.path.insert(0, r"C:\godot\_export")
from cut_models import get_mask

SRC = r"C:\godot\_export\_official_all"
DST = r"C:\godot\_export\official_cut"
CANVAS = 512
FILL = 0.92   # 船体最大边占画布比例
PAD = 0.05    # bbox 外扩

os.makedirs(DST, exist_ok=True)


def cut_one(src, dst, thr=0.5):
    pil = Image.open(src).convert("RGB")
    W, H = pil.size
    m = get_mask(pil, "isnet")                     # 0..1, HxW
    hard = (m > thr).astype(np.uint8)
    # 只保留最大连通域，去掉背景误检
    n, lab, stats, _ = cv2.connectedComponentsWithStats(hard, 8)
    if n > 1:
        idx = 1 + int(np.argmax(stats[1:, cv2.CC_STAT_AREA]))
        hard = (lab == idx).astype(np.uint8)
    # 填洞
    ff = hard.copy()
    mk = np.zeros((H + 2, W + 2), np.uint8)
    cv2.floodFill(ff, mk, (0, 0), 1)
    hard = hard | (1 - ff)
    ys, xs = np.where(hard > 0)
    if len(xs) == 0:
        return None
    x0, x1, y0, y1 = int(xs.min()), int(xs.max()), int(ys.min()), int(ys.max())
    pd = int(max(x1 - x0, y1 - y0) * PAD)
    x0 = max(0, x0 - pd); y0 = max(0, y0 - pd)
    x1 = min(W - 1, x1 + pd); y1 = min(H - 1, y1 + pd)

    rgb = np.array(pil)[y0:y1 + 1, x0:x1 + 1]
    al = m[y0:y1 + 1, x0:x1 + 1].copy()
    # 硬边外的杂散 alpha 清掉，再羽化
    al[hard[y0:y1 + 1, x0:x1 + 1] == 0] = 0
    al = cv2.GaussianBlur(al, (0, 0), 1.2)
    al = np.clip((al - 0.08) / 0.84, 0, 1)

    ch, cw = rgb.shape[:2]
    # 面积归一化：让船体 alpha 面积占画布固定比例（视觉体量统一），
    # 再用「最大边不超过 94% 画布」做上限保护（避免细长船被放大到溢出）
    TARGET = 0.22
    fg_px = float((hard > 0).sum())
    import math
    sc = math.sqrt(TARGET * CANVAS * CANVAS / max(fg_px, 1.0))
    sc = min(sc, CANVAS * 0.94 / max(ch, cw))
    nw, nh = max(1, int(round(cw * sc))), max(1, int(round(ch * sc)))
    rs = cv2.resize(rgb, (nw, nh), interpolation=cv2.INTER_AREA)
    as_ = cv2.resize(al, (nw, nh), interpolation=cv2.INTER_AREA)

    canvas = np.zeros((CANVAS, CANVAS, 4), np.uint8)
    ox, oy = (CANVAS - nw) // 2, (CANVAS - nh) // 2
    canvas[oy:oy + nh, ox:ox + nw, :3] = rs
    canvas[oy:oy + nh, ox:ox + nw, 3] = (as_ * 255).astype(np.uint8)
    Image.fromarray(canvas, "RGBA").save(dst)
    return float((hard > 0).mean()) * 100, (cw, ch)


if __name__ == "__main__":
    files = sorted(f for f in os.listdir(SRC) if f.endswith(".png"))
    log = []
    t0 = time.time()
    for f in files:
        n = f[:-4]
        d = os.path.join(DST, n + ".png")
        try:
            r = cut_one(os.path.join(SRC, f), d)
            if r is None:
                log.append("%-16s 空 mask（跳过）" % n)
            else:
                log.append("%-16s 前景 %5.1f%%  bbox %dx%d" % (n, r[0], r[1][0], r[1][1]))
        except Exception as e:
            log.append("%-16s FAIL %s" % (n, e))
        print(log[-1])
    log.append("")
    log.append("共 %d 张，用时 %.1fs" % (len(files), time.time() - t0))
    open(r"C:\godot\_export\_cut_all.txt", "w", encoding="utf-8").write("\n".join(log))
    print(log[-1])
