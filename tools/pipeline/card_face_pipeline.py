# -*- coding: utf-8 -*-
"""斗地主牌面批处理管线（固化路线 · 角标归一化）
────────────────────────────────────────────────────────────
输入：F:\\EVE自走棋\\牌面\\牌面\\*.png   （54 张 = 13 点数 × 4 花色 + 大小王）
输出：F:\\evezzq\\eve自走棋918\\assets\\cards\\card_<id>.png  （512×717，alpha 圆角）

处理（对齐已确认的 v4 观感）：
  ① 逐张检测左上角「点数+花色」墨迹 → 抠成纯色 mask →
     一次性缩放到 v4 规范尺寸（角标块高 ≈ 23.6% 画布高）→ 贴回规范位置；
     右下角 = 同一 mark 的 180° 镜像（源图 BR 角标先擦除）。
  ② 中文题字**不动**（本版题字不糊；且 76px 手牌下本来不可读，重排需逐张取字，收益低）。
  ③ 统一缩放到 512×717 + 10% alpha 圆角（与 v4 一致）。
  ④ 大小王（无角标）只做 ③。

顺序（质量优先）：**在源分辨率下检测 + 擦除**，再一次性缩到画布、贴标。
用法：
  python card_face_pipeline.py pilot   # 只跑 PILOT 名单，出 QC（结果图 + 检测框）
  python card_face_pipeline.py all     # 全量 → 写入游戏 assets/cards
"""
import os
import sys
import glob
from PIL import Image, ImageDraw, ImageFilter, ImageEnhance, ImageStat

SRC = r"F:\EVE自走棋\牌面\牌面"
OUT = r"F:\evezzq\eve自走棋918\assets\cards"
QC = r"C:\godot\_export\gen\qc"

PILOT = ["梅花2_游戏版.png", "方片2_游戏版.png", "黑桃A_游戏版.png", "黑桃3_游戏版.png",
         "方片3_游戏版.png", "梅花7_游戏版.png", "小王_游戏版.png", "大王_游戏版.png"]
## ★ 大小王：角标不是"单字+花色"，而是**左上竖排 JOKER 字样** ⇒ 单独的目标尺寸
##   （见 TARGET_BLOCK_H_JOKER）与更大的行合并容差（字母之间有间隙）。
JOKERS = ("小王_游戏版.png", "大王_游戏版.png")
MERGE_GAP_JOKER = 26       # 竖排字母间的行间隙容差（普通角标用 3）
## ★ 改从**镜像侧**取角标的卡（**当前为空**）。
## 曾对方片3 试用（其 TL 侧「3」有小缺口），但镜像侧检测框会多含一个元素
## ⇒ 抠出来**重复一个菱形**，反而更糟 ⇒ 弃用。方片3 保留 TL 侧（缺口很小，手牌尺寸不可见）。
## ★ 角标「重建」表（**当前为空**，留作备用）。曾试用「底卡+花色供体」重建方片3，
## 但与擦除流程叠加会出**双花色**，且「倒置源图取另一侧」这一通用规律已能解决（见 process_one）。
## ⛔ 不用生图模型修（整张重画 ⇒ 舰船换样 + 带水印，踩过两次）。
MARK_REBUILD = {}

CANVAS = (512, 717)
BLOCK_TOP = 0.028          # 角标块顶边（归一 H）
BLOCK_LEFT = 0.043         # 角标块左边（归一 W）
TARGET_BLOCK_H = 0.24      # ★ 2026-10-08 用户实机反馈「还得加粗加大」但 0.30 成角上糊块 ⇒ 0.236 → 0.16 又太小看不清
                           #   0.24 = 源图角标 0.109H 放大到 1.10x（172px），清楚且不糊
# ★★ 花色归一（2026-10-08 v10，用户：「花色完全看不到是什么花色」）★★
#   实测源牌点数高 ~63px，花色高只有 19~43px（0.30~0.68 倍）；标准扑克约 0.8 倍
#   ⇒ 点数 / 花色**分组重排**：花色放大到 SUIT_RATIO × 点数高，中间夹的**装饰横线**丢弃。
SUIT_RATIO = 0.68          # 花色高 / 点数高（对齐源牌里最大的黑桃/梅花 0.68~0.70）
MARK_GAP_RATIO = 0.16      # 点数与花色之间的间隙 / 点数高
# ★ 大小王的"标志" = 左上**竖排 JOKER 字样**（不是单字）⇒ 目标块高按"字母高 ≈ 点数高"换算：
#   点数高 = 0.236 × 0.46 ≈ 0.109H，5 个字母 ⇒ 块高 ≈ 0.545H（比普通角标长得多）
TARGET_BLOCK_H_JOKER = 0.545
RADIUS_RATIO = 0.10        # 圆角 = 画布宽 × 0.10
# ★ 笔画加粗（2026-10-08 用户实机反馈「字体还得加粗加大」）：
#   ⚠️ v10 起改为**缩放到目标尺寸之后**再做膨胀 —— 在源尺度上膨胀会把小花色（梅花三瓣、
#      方块尖）糊成一坨（用户报「花色全部花掉」）。目标尺度膨胀 = 所有笔画均匀 +1px。
MARK_BOLD = 3              # 膨胀尺寸必须为奇数；目标尺度 3 ≈ +1px（5 会再次把花色糊掉）

TH_BRIGHT = 150            # 角标墨迹亮度阈
ROI_X = 0.20               # ROI 右界（归一 W，放宽；装饰由列计数阈值滤掉）
ROI_Y = 0.30               # ROI 下界（归一 H）★10-08 由 0.16 放宽：花色下半在 0.19H 附近，原值把花色切了
MIN_ROW_SPAN = 0.008       # 行墨迹最小跨度（归一 W，约 5.6px）——判「窄尖」用
NARROW_TOL = 5             # 连续多少行低于 MIN_ROW_SPAN 就判为「已离开字形」（滤花色下方装饰竖线）
MIN_COL_INK = 6            # 列最少墨迹行数：字形 10~35，装饰细线 ~3 ⇒ 阈值 6 分开

# ── 画面调性（2026-10-08 用户反馈「脏 · 不够通透」）
# 参照用户自处理版实测：均值 -14、对比 ×1.12、饱和 ×0.80（压暗背景 + 提对比 + 降饱和 = 舰船跳出来）
TONE_CONTRAST = 1.10
TONE_BRIGHT = -6.0
TONE_SAT = 0.76


# ────────────────────────── 检测 ──────────────────────────
def is_rotated(im):
    """源图是否整张旋转了 180°。
    判据：正常牌面的**徽记+派系名在左下**（墨迹多）、右上基本空白；
    旋转后正好反过来 ⇒ 左下/右上墨迹比 < 1.2 即判为歪图。
    ★ 2026-10-08 实测有 5 张源图是歪的（方片3/方片9/方片J/梅花7/黑桃4）。"""
    lum = im.convert("L")
    px = lum.load()
    W, H = lum.size

    def ink(x0, x1, y0, y1):
        c = 0
        for y in range(int(y0 * H), int(y1 * H), 2):
            for x in range(int(x0 * W), int(x1 * W), 2):
                if px[x, y] > 150:
                    c += 1
        return c

    bl = ink(0.05, 0.40, 0.60, 0.90)
    tr = ink(0.60, 0.95, 0.08, 0.38)
    return (bl + 1) / (tr + 1) < 1.2


def detect_mark(im, merge_gap=3, min_x_start=0.028):
    """左上角检测「点数+花色」，返回源像素 bbox 或 None。
    策略（2026-10-08 第三次迭代）：
      1) 先按「ROI 内任意墨迹行」定 y 范围 —— 数字被拆成多段、装饰线乱入时仍稳；
      2) 在 y 范围内按列统计，取最左侧宽列段定 x 范围 —— 排除右侧竖装饰线；
      3) 若最上/最下拖着极细短线（装饰），再裁掉。
    ⚠️ 必须先跳过圆角外的白底（沿行/列找第一个暗像素 = 卡片真实边界）。"""
    W, H = im.size
    px = im.convert("L").load()
    x1 = int(ROI_X * W)
    y0b, y1b = int(0.02 * H), int(0.16 * H)   # y 范围收紧到 0.16H，刚好覆盖点数+花色，避开下方装饰

    # ★ 自适应阈值：卡面底色可能很亮（大小王是米金/红底）⇒ 用 ROI 亮度的中位数当底色，
    #   阈值 = max(150, 底色+30)。深色牌 ⇒ 仍是 150（行为不变）；米金底 ⇒ 抬到 ~200 分得开。
    vals = sorted(px[x, y] for y in range(y0b, y1b, 4) for x in range(0, x1, 4))
    bg = vals[len(vals) // 2] if vals else 40
    th = max(TH_BRIGHT, bg + 30)

    def xstart(y):                      # 该行卡片左边界（只跳**近白**=牌外留白）
        x = 0
        while x < x1 and px[x, y] > 240:
            x += 1
        return x

    # ── 1) y 范围：ROI 内第一个/最后一个有墨迹的行 ──
    y_top, y_bot = None, None
    for y in range(y0b, y1b):
        xs0 = xstart(y)
        if any(px[x, y] > th for x in range(xs0, x1)):
            if y_top is None:
                y_top = y
            y_bot = y
    if y_top is None:
        return None

    # ── 2) x 范围：在 y 范围内按列统计，取最左侧宽列段 ──
    colcnt = {}
    for x in range(x1):
        c = 0
        for y in range(y_top, y_bot + 1):
            if px[x, y] > th and x >= xstart(y):
                c += 1
        colcnt[x] = c

    cols = [x for x in range(x1) if colcnt[x] >= MIN_COL_INK]
    if not cols:
        return None
    runs, cur = [], [cols[0]]
    for x in cols[1:]:
        if x - cur[-1] <= 3:
            cur.append(x)
        else:
            runs.append(cur)
            cur = [x]
    runs.append(cur)
    run = None
    for r in runs:
        if (r[-1] + 1 - r[0]) >= 0.02 * W and r[0] >= min_x_start * W:
            run = r
            break
    if run is None:
        return None
    cx0, cx1 = run[0], run[-1] + 1

    # ── 3) 只裁掉「最顶端那一个薄段」= 装饰横线 ──
    #   ⛔ 旧写法是「while span(y) < wide(0.008W≈8.1px) 就往上爬」，会**整段跳过窄笔画字形**：
    #      黑桃 J 的竖笔只有 ~7px 宽 < 8.1 ⇒ 整根 J 被跳掉，角标只剩下半截（实机里 J 变 U，踩过）。
    #   ⇒ 改成按「有没有墨迹」分段：只有最顶端那一段**本身就够薄**（< 0.008H）才当装饰丢掉。
    def has(y):
        return any(px[x, y] > th and x >= xstart(y) for x in range(cx0, cx1))

    thin_th = int(0.008 * H)
    y = y_top
    while y <= y_bot and has(y):
        y += 1
    if (y - y_top) < thin_th and y <= y_bot:
        y_top = y
        while y_top <= y_bot and not has(y_top):
            y_top += 1

    return (cx0, y_top, cx1, y_bot + 1)


def detect_mark_br(im, merge_gap=3, min_x_start=0.028):
    """右下角角标（供擦除）：转 180° 复用左上检测，再映回。"""
    W, H = im.size
    bb = detect_mark(im.rotate(180), merge_gap=merge_gap, min_x_start=min_x_start)
    if bb is None:
        return None
    x0, y0, x1, y1 = bb
    return (W - x1, H - y1, W - x0, H - y0)


def _mirror180(box, W, H):
    x0, y0, x1, y1 = box
    return (W - x1, H - y1, W - x0, H - y0)


def _long_runs(getter, lo, hi, th, min_len):
    """在一维扫描里找「连续墨迹段」，返回 [(中心线, 起点, 终点)]（要求段长 >= min_len）。
    ⚠️ 只收**细长**结构（横线/竖线）；斜向装饰因每行段长很短而自动落选。"""
    out, cur, s = [], 0, None
    for i in range(lo, hi):
        if getter(i) > th:
            if cur == 0:
                s = i
            cur += 1
        else:
            if cur >= min_len:
                out.append((i - cur // 2, s, i - 1))
            cur = 0
    if cur >= min_len:
        out.append((hi - cur // 2, s, hi - 1))
    return out


def detect_deco(im, th=95):
    """检测左上/右下区域的**细长装饰线**（右侧横线 + 下方竖线），返回要擦的盒子。"""
    W, H = im.size
    px = im.convert("L").load()
    boxes = []

    # 横向细线：y 2%~20%，x 3%~32%，段长 >= 0.05W
    #   ⚠️ 必须**按 y 聚类后再逐组判断薄厚** —— 角标自身的横笔画也是长段，
    #      若把所有命中行合成一组，组高必然超限、整条横线被否决（踩过）。
    y0, y1 = int(0.02 * H), int(0.20 * H)
    xs0, xs1 = int(0.03 * W), int(0.42 * W)
    hits = []
    for y in range(y0, y1):
        for _c, a, b in _long_runs(lambda x: px[x, y], xs0, xs1, th, int(0.05 * W)):
            hits.append((y, a, b))
    hits.sort()
    grp, cur, last = [], [], None
    for h in hits:
        if last is not None and h[0] - last > 2:
            grp.append(cur)
            cur = []
        cur.append(h)
        last = h[0]
    if cur:
        grp.append(cur)
    for g in grp:
        gy0, gy1 = g[0][0], g[-1][0]
        if (gy1 - gy0) > 8:                       # 厚块（角标本体）跳过
            continue
        gx0 = min(h[1] for h in g)
        gx1 = max(h[2] for h in g)
        if (gx1 - gx0) < int(0.06 * W):           # 太短，不是装饰线
            continue
        # ⚠️ 检测到的是线的**边缘行**，盒必须往外扩（否则只擦掉半条线，留下线身 —— 踩过）
        boxes.append((gx0 - 4, gy0 - 12, gx1 + 12, gy1 + 12))

    # 纵向细线：x 2%~14%，y 8%~38%，段长 >= 0.10H
    vx0, vx1 = int(0.02 * W), int(0.14 * W)
    vy0, vy1 = int(0.08 * H), int(0.38 * H)
    vhits = []
    for x in range(vx0, vx1):
        for _c, a, b in _long_runs(lambda y: px[x, y], vy0, vy1, th, int(0.10 * H)):
            vhits.append((x, a, b))
    if vhits:
        vx0b, vx1b = min(h[0] for h in vhits), max(h[0] for h in vhits)
        vy0b, vy1b = min(h[1] for h in vhits), max(h[2] for h in vhits)
        if (vx1b - vx0b) <= 8:
            boxes.append((vx0b - 12, vy0b - 4, vx1b + 12, vy1b + 4))
    return boxes


def mark_erase_boxes(im, bb):
    """擦除清单（源像素）：旧角标 + 检测到的装饰细线；TL 与 BR（180° 镜像）各一份。"""
    W, H = im.size
    x0, y0, x1, y1 = bb
    tl = [(x0, y0, x1, y1)] + detect_deco(im)
    return tl + [_mirror180(b, W, H) for b in tl]


# ────────────────────────── 擦除 ──────────────────────────
def erase_ink(im, boxes, pad=26, th=95):
    """掩码 + 迭代模糊修补：把盒内墨迹擦成周围底色（无补丁边）。
    ⚠️ 阈值取 95（偏低）：装饰线偏暗（~100~160），阈值取 120 会漏掉 ⇒ 留淡痕（踩过）。"""
    for box in boxes:
        x0, y0, x1, y1 = [int(v) for v in box]
        bx = (max(0, x0 - pad), max(0, y0 - pad), min(im.width, x1 + pad), min(im.height, y1 + pad))
        region = im.crop(bx).convert("RGB")
        rel = (x0 - bx[0], y0 - bx[1], x1 - bx[0], y1 - bx[1])
        inner = region.crop(rel).convert("L").point(lambda v: 255 if v > th else 0)
        m = Image.new("L", region.size, 0)
        m.paste(inner.filter(ImageFilter.MaxFilter(11)), rel)
        # ★ 预填：掩码区先铺成「周围未掩码像素的均值」再迭代。
        #   ⛔ 直接迭代的话，亮字形的能量来不及散开 ⇒ 擦完留一块**偏亮方斑**（踩过）。
        inv = m.point(lambda v: 255 if v == 0 else 0)
        mean = ImageStat.Stat(region, inv).mean
        base = Image.new("RGB", region.size, tuple(int(v) for v in mean))
        filled = Image.composite(base, region, m)
        for _ in range(32):
            filled = Image.composite(filled.filter(ImageFilter.GaussianBlur(4)), filled, m)
        im.paste(filled, bx, m.filter(ImageFilter.GaussianBlur(2)))


# ────────────────────────── 角标重建 ──────────────────────────
def _row_groups(im, bb, th=TH_BRIGHT):
    """bbox 内按空行切墨迹组（点数 / 花色），返回 [(y0, y1)]（绝对 y）。"""
    x0, y0, x1, y1 = bb
    px = im.convert("L").load()
    groups, cur, gap = [], None, 0
    for y in range(y0, y1):
        if any(px[x, y] > th for x in range(x0, x1)):
            if cur is None:
                cur = [y, y]
            else:
                cur[1] = y
            gap = 0
        elif cur is not None:
            gap += 1
            if gap > 3:
                groups.append(cur)
                cur = None
    if cur is not None:
        groups.append(cur)
    return [(a, b + 1) for a, b in groups]


def _tight(im, box, th=TH_BRIGHT):
    """box 内墨迹的**紧包围盒**（绝对坐标）；无墨迹返回 None。"""
    x0, y0, x1, y1 = box
    px = im.convert("L").load()
    xs, ys = [], []
    for y in range(y0, y1):
        for x in range(x0, x1):
            if px[x, y] > th:
                xs.append(x)
                ys.append(y)
    if not xs:
        return None
    return (min(xs), min(ys), max(xs) + 1, max(ys) + 1)


def _mark_color(im, bb):
    """角标本体色（亮像素均值）。"""
    px = im.crop(bb).convert("RGB").load()
    w, h = bb[2] - bb[0], bb[3] - bb[1]
    acc, n = [0, 0, 0], 0
    for y in range(h):
        for x in range(w):
            c = px[x, y]
            if sum(c) / 3 > 150:
                acc = [acc[0] + c[0], acc[1] + c[1], acc[2] + c[2]]
                n += 1
    return tuple(v // n for v in acc) if n else (230, 225, 210)


def _mark_bg(im, bb):
    """角标底色（暗像素均值）。"""
    px = im.crop(bb).convert("RGB").load()
    w, h = bb[2] - bb[0], bb[3] - bb[1]
    acc, n = [0, 0, 0], 0
    for y in range(h):
        for x in range(w):
            c = px[x, y]
            if sum(c) / 3 < 100:
                acc = [acc[0] + c[0], acc[1] + c[1], acc[2] + c[2]]
                n += 1
    return tuple(v // n for v in acc) if n else (30, 32, 28)


def repair_mark(im, bb, donor_im, donor_bb, part):
    """把 donor 卡同一部位的字形搬到 im 的角标上（按**紧包围盒**对齐，其余保持 im 原样）。
    用于：源图某部位笔画缺损，或整块角标不可信 ⇒ 用干净供体重建。"""
    own = im.crop(bb).convert("RGB")
    og, dg = _row_groups(im, bb), _row_groups(donor_im, donor_bb)
    idx = 0 if part == "rank" else 1
    if len(og) <= idx or len(dg) <= idx:
        return own
    ot = _tight(im, (bb[0], og[idx][0], bb[2], og[idx][1]))
    dt = _tight(donor_im, (donor_bb[0], dg[idx][0], donor_bb[2], dg[idx][1]))
    if not ot or not dt:
        return own
    glyph = donor_im.crop(dt)
    dmask = glyph.convert("L").point(lambda v: 255 if v > TH_BRIGHT else 0)
    dmask = dmask.filter(ImageFilter.MinFilter(3)).filter(ImageFilter.MaxFilter(5))
    tw, thh = ot[2] - ot[0], ot[3] - ot[1]
    dmask = dmask.resize((tw, thh), Image.LANCZOS)
    out = own.copy()
    pos = (ot[0] - bb[0], ot[1] - bb[1])
    out.paste(Image.new("RGB", (tw, thh), _mark_bg(im, bb)), pos)      # ① 清掉本卡该部位
    out.paste(Image.new("RGB", (tw, thh), _mark_color(im, bb)), pos, dmask)  # ② 盖上供体字形
    return out


def _bin(img):
    """二值化 + 形态学开运算（去 1~2px 细斜装饰线，字形笔画不受影响）。"""
    m = img.convert("L").point(lambda v: 255 if v > TH_BRIGHT else 0)
    return m.filter(ImageFilter.MinFilter(3)).filter(ImageFilter.MaxFilter(3))


def _glyph_boxes(im, bb):
    """在角标 bbox 内按行分组，只留下**像字形**的组（够高 + 不太宽），返回紧包围盒列表。
    装饰横线（高 4~16px）与装饰竖线（又高又窄）都会被滤掉。"""
    x0, y0, x1, y1 = bb
    min_h = max(1, int(round(0.012 * im.height)))   # ≈17px：低于此高的是装饰细线
    out = []
    for ga, gb in _row_groups(im, bb):
        t = _tight(im, (x0, ga, x1, gb))
        if t is None:
            continue
        cw, chh = t[2] - t[0], t[3] - t[1]
        if chh < min_h or cw > 1.5 * chh:           # 太扁 / 太宽 = 装饰
            continue
        out.append(t)
    return out


def _compose_mark(im, bb):
    """把角标拆成「点数 / 花色」两组重排：花色放大到 SUIT_RATIO×点数高，丢掉中间装饰横线。
    返回合成后的 L 掩码（源像素尺度）或 None（分组失败 ⇒ 调用方走兜底）。
    ★ 2026-10-08 v10：源牌花色只有点数的 0.30~0.68 倍（标准扑克 ~0.8），且被装饰横线挤开
      ⇒ 不重排的话手牌尺寸下完全看不出花色（用户报「花色全部花掉」）。"""
    boxes = _glyph_boxes(im, bb)
    if len(boxes) < 2:
        return None
    rank_m = _bin(im.crop(boxes[0]))                # 第一个字形 = 点数
    suit_m = _bin(im.crop(boxes[-1]))               # 最后一个字形 = 花色
    rh = rank_m.height
    sh = max(1, int(round(SUIT_RATIO * rh)))
    sw = max(1, int(round(suit_m.width * sh / suit_m.height)))
    suit_m = suit_m.resize((sw, sh), Image.LANCZOS)
    gap = max(1, int(round(MARK_GAP_RATIO * rh)))
    W2 = max(rank_m.width, suit_m.width)
    H2 = rh + gap + sh
    comp = Image.new("L", (W2, H2), 0)
    comp.paste(rank_m, (0, 0))
    comp.paste(suit_m, (0, rh + gap))
    return comp


def mark_layer_from(im, bb, canvas, prebuilt=None, target_h=None):
    """把角标做成画布规范尺寸的 RGBA 图层（纯色 + 二值 mask）。
    [param prebuilt] 若给出（repair_mark 的产物），直接用它作为源裁剪。
    [param target_h] 目标块高（归一画布高）；默认 TARGET_BLOCK_H。"""
    CW, CH = canvas
    crop = (prebuilt if prebuilt is not None else im.crop(bb)).convert("RGB")
    # 采样本体色：只取**高亮**像素（>200）⇒ 得到干净的白/米色，不被灰边拉暗
    p = crop.load()
    acc, n = [0, 0, 0], 0
    for yy in range(crop.height):
        for xx in range(crop.width):
            c = p[xx, yy]
            if sum(c) / 3 > 200:
                acc = [acc[0] + c[0], acc[1] + c[1], acc[2] + c[2]]
                n += 1
    color = tuple(v // n for v in acc) if n else (230, 225, 210)

    mask = None
    if prebuilt is None:
        mask = _compose_mark(im, bb)                # ★ 点数+花色分组重排（v10）
    if mask is None:
        mask = _bin(crop)                           # 兜底 = 旧行为（整块角标原样抠）

    # ① 先缩到目标块高 ② 再在**目标尺度**上加粗 ③ 轻微模糊抗锯齿
    th = max(1, int(round((target_h if target_h else TARGET_BLOCK_H) * CH)))
    tw = max(1, int(round(mask.width * th / mask.height)))
    mask = mask.resize((tw, th), Image.LANCZOS)
    if MARK_BOLD > 0:
        mask = mask.filter(ImageFilter.MaxFilter(MARK_BOLD))
    mask = mask.filter(ImageFilter.GaussianBlur(0.6))
    rgba = Image.new("RGBA", mask.size, color + (0,))
    rgba.putalpha(mask)
    return rgba, color


def apply_tone(im):
    """画面调性（2026-10-08 用户反馈「脏 · 不够通透」）：
    压暗背景 + 提对比 + 降饱和 ⇒ 舰船从背景里跳出来。参数见文件头 TONE_*。
    ⚠️ 必须在 **HSV 空间只调 V / S**：直接对 RGB 做线性提对比会给暗部放大色差，
       饱和反而暴涨（实测 48→68，踩过）。"""
    h, s, v = im.convert("RGB").convert("HSV").split()
    v = v.point([max(0, min(255, int(round(TONE_CONTRAST * (i - 128) + 128 + TONE_BRIGHT))))
                 for i in range(256)])
    if TONE_SAT != 1.0:
        s = s.point([max(0, min(255, int(round(i * TONE_SAT)))) for i in range(256)])
    return Image.merge("HSV", (h, s, v)).convert("RGB")


def round_corners(im, canvas):
    CW, CH = canvas
    mask = Image.new("L", canvas, 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [0, 0, CW - 1, CH - 1], radius=int(CW * RADIUS_RATIO), fill=255)
    out = im.convert("RGBA")
    out.putalpha(mask)
    return out


def card_id(name):
    """牌名 → 牌 id（ddz_rules: rank=3+id/4, suit=id%4；黑桃0 红桃1 方块2 梅花3）
    ★ 2026-10-08 起源文件带 `_游戏版` 后缀 ⇒ 先剥掉再解析。"""
    name = name.replace("_游戏版", "")
    if name.startswith("小王"):
        return 52
    if name.startswith("大王"):
        return 53
    suit = {"黑桃": 0, "红桃": 1, "方片": 2, "方块": 2, "梅花": 3}[name[:2]]
    rk = name[2:-4]
    rank = {"J": 11, "Q": 12, "K": 13, "A": 14, "2": 15}.get(rk, int(rk) if rk.isdigit() else None)
    return (rank - 3) * 4 + suit


# ────────────────────────── 单张处理 ──────────────────────────
def process_one(path, save=False):
    name = os.path.basename(path)
    src = Image.open(path).convert("RGB")
    info = {"name": name, "mark": None, "mark_br": None, "color": None, "rotated": False,
            "W": src.width, "H": src.height}

    rotated = False
    is_joker = name in JOKERS
    # 大小王的"标志"是竖排 JOKER 字样 ⇒ 用更大的目标块高 + 更宽的行合并容差
    target_h = TARGET_BLOCK_H_JOKER if is_joker else TARGET_BLOCK_H
    merge_gap = MERGE_GAP_JOKER if is_joker else 3
    # 大小王的卡面常**贴边**（无黑边）⇒ 起点阈值放宽，否则角标被边界条件挡掉
    x_start = 0.008 if is_joker else 0.028

    # ⛔ 大小王**不做角标归一化**：源图里竖排 JOKER 字样本来就大且清晰；
    #    强行"放大重贴"会 ① 尺寸过头 ② 在米金底色上擦出可见补丁（实测）。
    #    ⇒ 只走"缩放 + 圆角"。
    if not is_joker:
        if is_rotated(src):                # ★ 源图整张倒置（实测 5 张）⇒ 先转正
            src = src.rotate(180)
            rotated = True
        info["rotated"] = rotated
        bb = detect_mark(src)
        info["mark"] = bb
        if bb:
            info["mark_br"] = detect_mark_br(src)
            # ⛔ 试过两条"修角标笔画"的路，都更糟，已弃用：
            #   ① 生图模型重画 → 舰船换样 + 水印；② 从供体卡/镜像侧搬字形 → 双花色、排列颠倒。
            #   ⇒ 源图本身的笔画缺口**不由管线伪造**（要完美请重出该源图）。
            layer, color = mark_layer_from(src, bb, CANVAS)
            info["color"] = color
            erase_ink(src, mark_erase_boxes(src, bb))

    flat = src.resize(CANVAS, Image.LANCZOS)

    if info["mark"]:
        CW, CH = CANVAS
        pos = (int(round(BLOCK_LEFT * CW)), int(round(BLOCK_TOP * CH)))
        comp = Image.new("RGBA", CANVAS, (0, 0, 0, 0))
        comp.paste(layer, pos, layer)
        br_pos = (CW - pos[0] - layer.width, CH - pos[1] - layer.height)
        comp.paste(layer.rotate(180), br_pos, layer.rotate(180))
        flat = Image.alpha_composite(flat.convert("RGBA"), comp).convert("RGB")

    rgba = round_corners(apply_tone(flat), CANVAS)
    if save:
        os.makedirs(OUT, exist_ok=True)
        rgba.save(os.path.join(OUT, "card_%d.png" % card_id(name)))
    return rgba, info


def overlay(path):
    """QC：检测框 + ROI 画在源图上。"""
    im = Image.open(path).convert("RGB")
    name = os.path.basename(path)
    dr = ImageDraw.Draw(im)
    dr.rectangle((0, 0, int(ROI_X * im.width), int(ROI_Y * im.height)), outline=(60, 200, 255), width=2)
    if name not in JOKERS:
        bb = detect_mark(im)
        if bb:
            dr.rectangle(bb, outline=(255, 60, 60), width=3)
        br = detect_mark_br(im)
        if br:
            dr.rectangle(br, outline=(255, 200, 0), width=3)
    os.makedirs(QC, exist_ok=True)
    im.save(os.path.join(QC, "qc_" + name))


if __name__ == "__main__":
    mode = sys.argv[1] if len(sys.argv) > 1 else "pilot"
    names = PILOT if mode == "pilot" else [os.path.basename(p) for p in sorted(glob.glob(os.path.join(SRC, "*.png")))]
    for n in names:
        rgba, info = process_one(os.path.join(SRC, n), save=(mode == "all"))
        m = info["mark"]
        mtxt = "x%.3f,y%.3f,x%.3f,y%.3f" % (m[0] / info["W"], m[1] / info["H"],
                                            m[2] / info["W"], m[3] / info["H"]) if m else "无"
        print("%-12s mark=[%s] color=%s" % (n, mtxt, info["color"]))
        if mode == "pilot":
            os.makedirs(QC, exist_ok=True)
            rgba.save(os.path.join(QC, "out_" + n))
    if mode == "pilot":
        for n in names:
            overlay(os.path.join(SRC, n))
        print("QC →", QC)
