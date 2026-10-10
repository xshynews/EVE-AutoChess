# -*- coding: utf-8 -*-
"""吨位几何符号 —— 超采样预烘贴图（2026-09-23 按用户口径重建）。

用户规则（原话）：
  「护卫和驱逐是对的，其他是错的，巡洋是上面是三角形下面是一个长方形，
    且以三角形最长边为长方形的长；战巡为巡洋舰符号标识下面再加一横；
    战列舰是巡洋舰标识下面改三角形。」

实测（13 图鉴页 + 用户新截图，两个来源**逐位一致**）：
  护卫舰 10x5   apex → 45° 三角 → 底边即底线（三角闭合，无间隙）
  驱逐舰 10x7   同护卫 + 空 1 行 + 独立横线
  巡洋舰 10x9   屋顶三角(4 行) + 竖直侧边(4 行) + 底边
  战巡   10x11  同巡洋 + 空 1 行 + 独立横线
  战列舰 10x12  同巡洋屋顶 + 侧边延长 + 底部改成**向上尖的 Λ**（凹口）

⚠️ 五个符号共用同一个屋顶（顶点与屋檐顶点完全同位），只在下半部分逐级生长 ——
   所以「画布宽 10」是常量，「高」随吨位变（0.52 → 1.22 倍宽）。

⚠️ 是**描边**不是实心块面（旧版读成「拱形实心」是错的）：
   笔画宽 LW = 1.4 设计单位（实测官方 1.0~1.4px @ 宽 10px）。

为什么走「预烘纹理」而不是 Godot 侧 draw_polyline：
  project.godot 没开 msaa_2d，而 Godot 4 的 2D 绘制没有 antialiased 参数
  ⇒ 硬锯齿。开 msaa_2d 是全局改动（HUD 大量 1px 像素对齐边框会一起糊掉）。
  所以这里「离线 16x 超采样 + 盒式降采样」烘成小图，边缘覆盖率预先算好。

输出：`assets/ui/tier/tier_1..5.png`（白 + alpha，运行时 modulate 上色）
      每张纹理 = **符号自身包围盒**（不留白），宽固定 24px，高度随吨位。

⚠️ 为什么是 24px = **显示宽度（12px）的 2 倍**，而不是更大的 48px：
   双线性在 **2:1** 下是**精确的 2x2 盒平均**（采样点落在纹素正中间，四个纹素权重各 1/4）；
   到 **4:1** 就退化成「跳采样」—— 只混相邻 2 个纹素，0/3/4/7 号纹素根本没被读到
   ⇒ 细线掉墨 + 斜边摩尔纹。实测（`tools/probe_tier_icon` 隔离探针，12px 显示）：

      方案               tier_2（最细的线）保留率
      48px + mip 链             56%     ← 改前的现状
      48px + 仅 LINEAR          85%
      48px + NEAREST            85%
      24px + 仅 LINEAR         ~95%     ← 本口径（关 mip）

   ⇒ **纹理尺寸必须 = 显示尺寸的整数倍，且这个倍数要 ≤ 2。**
     改 TIER_SIZE 就离开这个关系，细线会变淡（不是不能改，是要同时改这里重烘）。
"""
import os
import numpy as np
from PIL import Image, ImageDraw, ImageFont

OUT_DIR = r"F:\evezzq\eve自走棋918\assets\ui\tier"
PREV_DIR = r"C:\godot\_export\_tier_icons"
SS = 16                      # 超采样倍率
W_PX = 24                    # 输出纹理宽（= 符号外框宽 = 显示宽 12px 的 2 倍，见头注释）

# ── 设计几何（单位 = 外框宽的 1/10；y 向下，0 = 顶点笔画的外上沿）──
OUT_W = 10.0                 # 外框宽（常量，5 个吨位共用）
LW = float(os.environ.get("TIER_LW", "1.1"))   # 笔画宽（可用 TIER_LW 覆盖以做对比）
#   ⚠️ 1.1 = 官方实测笔画比例（1px @ 外框宽 10px → 0.10~0.11）。
#      取值扫描（tier_fidelity.py 的 IoU）：1.0→0.864 · 1.1→0.789 · 1.2→0.766 · 1.4→0.729。
#      **不要为了「看得清」把它调粗** —— 12px 显示下 1.1 已给到 1.32 设备像素；
#      再粗就变成「描边压过形状」，且与官方比例脱钩（旧版 1.7~2.6 就是这么废掉的）。
HW = (OUT_W - LW) * 0.5      # 中心线半宽 = 4.3
TOP = LW * 0.5               # 顶点中心线 y = 0.7
RH = HW * (4.0 / 4.5)        # 屋顶高（官方实测 4/4.5 的斜率）= 3.822
CORNER = TOP + RH            # 屋檐顶点中心线 y = 4.522
CX = OUT_W * 0.5             # 中轴 x = 5.0

# 每吨位：轮廓中心线路径（闭合）+ 独立横线 y + 说明
SYMS = {
    1: dict(tag="护卫舰",     drop=None, extra=[],          note="三角（底边即底线）"),
    2: dict(tag="驱逐舰",     drop=None, extra=[2.0],       note="三角 + 独立横线（间隔 1 行）"),
    3: dict(tag="巡洋舰",     drop=4.0,  extra=[],          note="屋顶三角 + 竖直侧边 + 底边"),
    4: dict(tag="战列巡洋舰", drop=4.0,  extra=[6.0],       note="巡洋 + 独立横线"),
    5: dict(tag="战列舰",     drop=7.0,  extra=[], lam=3.0, note="屋顶 + 侧边 + 底部 Λ 凹口"),
}


def outline(cost):
    """中心线路径（闭合，首点 = 顶点）。"""
    L, R = CX - HW, CX + HW
    apex, lc, rc = (CX, TOP), (L, CORNER), (R, CORNER)
    s = SYMS[cost]
    if s["drop"] is None:
        return [apex, lc, rc]
    if "lam" in s:
        # 侧边下探到 CORNER+drop，底部改成向上尖的 Λ（顶点在 CORNER+lam）
        return [apex, lc, (L, CORNER + s["drop"]), (CX, CORNER + s["lam"]),
                (R, CORNER + s["drop"]), rc]
    return [apex, lc, (L, CORNER + s["drop"]), (R, CORNER + s["drop"]), rc]


def outer_h(cost):
    """外框高（设计单位）。"""
    s = SYMS[cost]
    if s["extra"]:
        return CORNER + max(s["extra"]) + LW * 0.5
    if s["drop"] is None:
        return CORNER + LW * 0.5
    return CORNER + s["drop"] + LW * 0.5


def render(cost):
    """渲染成 W_PX 宽的白 + alpha 贴图（16x 超采样 → 盒式降采样）。"""
    h_units = outer_h(cost)
    unit = W_PX * SS / OUT_W                 # 超采样画布上 1 设计单位 = 多少像素
    cw, ch = int(round(OUT_W * unit)), int(round(h_units * unit))
    im = Image.new("L", (cw, ch), 0)
    dr = ImageDraw.Draw(im)
    wpx = max(1, int(round(LW * unit)))

    def P(x, y):
        return (x * unit, y * unit)

    pts = [P(*p) for p in outline(cost)]
    dr.line(pts + [pts[0]], fill=255, width=wpx, joint="curve")

    # 独立横线：**贯穿整个外框宽**（0 → OUT_W）。
    # ⚠️ 别 inset 半笔画（原来写成 LW*0.5 → OUT_W-LW*0.5）—— 两端各缺 0.55 设计单位，
    #    缩到 10px 尺度二值化后是 `.########.`，而官方位图是满宽 `##########`。
    for dy in SYMS[cost]["extra"]:
        y = CORNER + dy
        dr.line([P(0.0, y), P(OUT_W, y)], fill=255, width=wpx)

    # 圆头补顶点：joint="curve" 只处理折点，端点用圆补一下（等腰尖角）
    a = P(CX, TOP)
    r = wpx * 0.5
    dr.ellipse([a[0] - r, a[1] - r, a[0] + r, a[1] + r], fill=255)

    h_px = max(2, int(round(W_PX * h_units / OUT_W)))
    small = im.resize((W_PX, h_px), Image.BOX)
    return small


os.makedirs(OUT_DIR, exist_ok=True)
os.makedirs(PREV_DIR, exist_ok=True)

tiles = {}
print("吨位符号重建（描边，宽 10 设计单位，笔画 1.4）")
print("%-4s %-10s %-8s %-10s %s" % ("tier", "吨位", "外框比", "纹理", "结构"))
for c in sorted(SYMS):
    a = render(c)
    rgba = Image.merge("RGBA", (a, a, a, a))
    p = os.path.join(OUT_DIR, "tier_%d.png" % c)
    rgba.save(p)
    tiles[c] = a
    cov = np.asarray(a).astype(np.float32) / 255.0
    mid = ((cov > 0.05) & (cov < 0.95)).mean() * 100
    ink = (cov > 0.5).mean() * 100
    print("%-4d %-10s %-8s %-10s %s   (中间灰 %.1f%% / 墨量 %.1f%%)"
          % (c, SYMS[c]["tag"], "1:%.2f" % (a.height / a.width),
             "%dx%d" % (a.width, a.height), SYMS[c]["note"], mid, ink))

# ── 预览：1x 原生 / 12px 实际显示 / 24px，各放大 12 倍 ──
FB = r"C:\Windows\Fonts\msyhbd.ttc"
FR = r"C:\Windows\Fonts\msyh.ttc"
SIZES = [24, 12, 48]
ZM = 12
PAD = 18
CW = 48 * ZM + 24
ROW_H = 48 * ZM + 60
W = PAD * 2 + len(SIZES) * (CW + PAD)
H = PAD * 2 + 46 + len(SYMS) * ROW_H
cv = Image.new("RGB", (W, H), (14, 16, 20))
d2 = ImageDraw.Draw(cv)
d2.text((PAD, PAD), "吨位几何符号 · 描边重建（护卫 / 驱逐 / 巡洋 / 战巡 / 战列）",
        font=ImageFont.truetype(FB, 22), fill=(236, 236, 236))
for j, sz in enumerate(SIZES):
    lab = {48: "纹理原生 48px", 12: "备战席实际显示 12px", 24: "放大一倍 24px"}[sz]
    d2.text((PAD + j * (CW + PAD), PAD + 30), "%s（放大 %dx）" % (lab, ZM),
            font=ImageFont.truetype(FR, 15), fill=(150, 190, 220))
for i, c in enumerate(sorted(SYMS)):
    y = PAD + 46 + i * ROW_H
    for j, sz in enumerate(SIZES):
        a = tiles[c] if sz == W_PX else tiles[c].resize(
            (max(1, int(sz)), max(1, int(round(sz * tiles[c].height / tiles[c].width)))),
            Image.BOX)
        big = a.resize((a.width * ZM, a.height * ZM), Image.NEAREST)
        flat = Image.new("RGB", (48 * ZM, 48 * ZM), (14, 16, 20))
        flat.paste(Image.merge("RGB", (big, big, big)),
                   ((flat.width - big.width) // 2, (flat.height - big.height) // 2),
                   Image.merge("L", (big,)))
        cv.paste(flat, (PAD + j * (CW + PAD), y))
    d2.text((PAD + 2, y + 48 * ZM + 4),
            "tier_%d  %s   外框 1 : %.2f" % (c, SYMS[c]["tag"], outer_h(c) / OUT_W),
            font=ImageFont.truetype(FB, 18), fill=(232, 232, 232))
    d2.text((PAD + 2, y + 48 * ZM + 27),
            SYMS[c]["note"], font=ImageFont.truetype(FR, 14), fill=(148, 148, 148))

pv = os.path.join(PREV_DIR, "tier_icons_preview.png")
cv.save(pv)
print("\nsaved", pv, cv.size)
