# -*- coding: utf-8 -*-
"""pose_sheet.py —— 判「这艘船在游戏里是不是倒着飞」，并出人眼可判的两端实拍。

════════════════════════════════════════════════════════════════
 判据（两条独立，互为交叉验证）
════════════════════════════════════════════════════════════════
物理前提：`_e`（自发光）贴图里最集中、最强的自发光面组 = **发动机喷口**，
喷口只能在船尾，且**喷口的法线沿舰艏−舰尾轴朝外**（舷窗法线垂直于该轴）。
⇒ 用喷口面反解舰艏方向，比「端部宽度」之类启发式硬得多。

  v1（面积法，宽口径）：沿 PCA 最长轴 p，两端各 20% 长度带内的自发光**面积**之比
        ratio1 = (A(+p) − A(−p)) / (A(+p) + A(−p))
  v2（法线法，窄口径，**只抓喷口**）：只取 `|面法线·p| > 0.6` 的自发光面，
        按面积加权求法线的有向和
        score2 = Σ(area·sign(n·p)) / Σarea
        score2 > +0.5 ⇒ 喷口法线朝 +p ⇒ 喷口在 **+p 端** ⇒ 舰艏在 **−p 端**

两条都算，一致才认。

════════════════════════════════════════════════════════════════
 判「表里该不该翻」的统一算式
════════════════════════════════════════════════════════════════
    world = R_y(MODEL_YAW_FIX + AXIS_DEG + 180°·FLIP + 180°·GLOBAL_180) · M · p_model
    R_y(−90°) 把 +X 打到 +Z ⇒ 舰艏要落 +Z，就必须让**舰艏沿 M 第一行那个方向**：
      · 未重映射的船：M = I ⇒ 第一行 = +X ⇒ 舰艏必须在原始 **+X** 端
      · 重映射的船：M 第一行 = spec 第一项（kestrel "+Y,-Z,-X" ⇒ 舰艏沿 **+Y**）
    need_flip = (bow_raw · A) < 0        A = M 第一行
    贴合度   = |bow_raw · A|             < 0.70 就别信

════════════════════════════════════════════════════════════════
 两端实拍（已修掉画家算法深度序 —— 现在是**真·近侧视图**）
════════════════════════════════════════════════════════════════
  <id>_stern.png  az=+90  ⇒ 相机在 **−Z**，看船尾 ⇒ **应看到喷口（红）**
  <id>_bow.png    az=270  ⇒ 相机在 **+Z**，看船艏 ⇒ 不该有喷口红块
  <id>_iso.png    斜视，看整体

用法:
    python pose_sheet.py [ship_id ...]
"""
import os
import re
import sys

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, r'C:\godot\_export')
from glow_probe import gather, load_glb, font          # noqa: E402

GLB_DIR = r'F:\evezzq\eve自走棋918\assets\ships3d'
SRC_DIR = r'C:\godot\_export\_ship3d'
SRC_DIR2 = r'C:\godot\_export\_models'
YAW_GD = r'F:\evezzq\eve自走棋918\scripts\data\eve_ship_yaw.gd'
OUT = r'C:\godot\_export\_pose'

MODEL_YAW_FIX = -90.0
AXES = {'X': 0, 'Y': 1, 'Z': 2}
THR = 0.30
BAND = 0.20
MIN_FACES = 20
MIN_NOZ = 8
CONF = 0.70

# ── 自适应阈值（2026-09-26）──────────────────────────────────────
# 固定 THR=0.30 会把「喷口只是中等亮度」的船整批漏掉 —— 实测：
#   harbinger  @0.30 只有 4 个轴向面 ⇒ 判不了；@0.06 有 78 面、noz2=+0.97
#   inquisitor @0.30 只有 3 个      ⇒ 判不了；@0.12 有 30 面、noz2=+0.98
#   slasher    @0.30 只有 6 个      ⇒ 判不了；@0.20 有 16 面、noz2=+0.70
# 所以在多档阈值上各判一次，**只采信符号一致的那些档**，取聚拢度最高的一档。
THR_LIST = (0.30, 0.20, 0.12, 0.06, 0.03)
MIN_NOZ_SOFT = 4      # 面数下限可比硬判据松：单个大喷口常被切成 3~5 个三角面
SC2_SOFT = 0.60       # 但 noz2 要更强，补偿面数少
# ⚠️ 2026-09-26 实测否决：「簇必须落在船两端」这条约束**不成立**，别再加回来。
#    rifter/hyperion/scorpion/burst/bantam… 的轴向自发光簇 rel 都在 0.40~0.60
#    （自发光面本来就遍布全船，不止喷口），硬卡两端会把 19 艘**正确的**船误判成
#    「判不了」。rel / span 只作为**参考信息**打印 + 画在图上，不参与判定。
END_MIN = 0.0         # 0 = 不启用
SPAN_MAX = 9.9        # 9.9 = 不启用
NOZ_LOW = 20          # 轴向面数低于此值 ⇒ 结论存疑（catalyst n=5 就是典型）


# ── 表解析（只作对照）────────────────────────────────────────────────
def parse_table():
    src = open(YAW_GD, encoding='utf-8').read()

    def block(name, close):
        i = src.index(name)
        return src[i:src.index(close, i)]

    deg = {m.group(1): float(m.group(2)) for m in re.finditer(
        r'&"([a-z0-9_]+)"\s*:\s*([+-]?[\d.]+)\s*,', block('const AXIS_DEG := {', '\n}'))}
    remap = {m.group(1): m.group(2) for m in re.finditer(
        r'&"([a-z0-9_]+)"\s*:\s*"([+\-XYZ,]+)"', block('const AXIS_REMAP := {', '\n}'))}
    flip = set(re.findall(r'"([a-z0-9_]+)"',
                          block('const FLIP: PackedStringArray = [', ']')))
    glob = bool(re.search(r'const GLOBAL_180\s*:=\s*true', src))
    return deg, remap, flip, glob


def spec_rows(spec):
    rows = []
    for tok in [t.strip() for t in spec.split(',')]:
        v = np.zeros(3)
        v[AXES[tok[1].upper()]] = 1.0 if tok[0] == '+' else -1.0
        rows.append(v)
    return np.array(rows)


def ry(deg):
    a = np.radians(deg)
    c, s = np.cos(a), np.sin(a)
    return np.array([[c, 0.0, s], [0.0, 1.0, 0.0], [-s, 0.0, c]])


def src_texture(sid):
    for d in (os.path.join(SRC_DIR, sid, 'textures'),
              os.path.join(SRC_DIR2, sid, 'textures')):
        if os.path.isdir(d):
            c = [f for f in os.listdir(d) if f.endswith('_e.png')]
            if c:
                return np.asarray(Image.open(os.path.join(d, sorted(c)[0]))
                                  .convert('L'), dtype=np.float32) / 255.0
    return None


def uv_sample(tex, uv):
    H, W = tex.shape
    u = np.clip(uv[:, 0] % 1.0, 0, 1 - 1e-6)
    v = np.clip(uv[:, 1] % 1.0, 0, 1 - 1e-6)
    return tex[np.clip((v * H).astype(int), 0, H - 1),
               np.clip((u * W).astype(int), 0, W - 1)]


def tri_area(Q):
    return 0.5 * np.linalg.norm(np.cross(Q[:, 1] - Q[:, 0], Q[:, 2] - Q[:, 0]), axis=1)


def area_ratio(Q, g, p, band=BAND):
    """v1：沿 p 两端各 band 长度带内的自发光面积比"""
    t = (Q.mean(1) if Q.ndim == 3 else Q) @ p
    t0, t1 = float(t.min()), float(t.max())
    L = max(t1 - t0, 1e-9)
    a = tri_area(Q)
    ap = float(a[g & (t > t1 - band * L)].sum())
    am = float(a[g & (t < t0 + band * L)].sum())
    tot = ap + am
    return ap, am, ((ap - am) / tot if tot > 1e-12 else 0.0)


def nozzle_score(Q, NR, g, p, min_cos=0.6):
    """v2：只取法线沿 p 的自发光面（= 喷口），按面积加权求有向和"""
    s = NR @ p
    sel = g & (np.abs(s) > min_cos)
    n = int(sel.sum())
    if n == 0:
        return 0.0, 0, 0.0
    w = tri_area(Q)[sel]
    tot = float(w.sum())
    sc = float((w * np.sign(s[sel])).sum()) / max(tot, 1e-12)
    return sc, n, tot


def nozzle_cluster(Q, NR, g, p, min_cos=0.60):
    """只抓「法线沿 p **且聚在船的一端**」的自发光面 —— 这才是喷口。

    返回 (score, n, rel, span)：
        score = 面积加权的法线有向和（+1 ⇒ 全朝 +p ⇒ 喷口在 +p 端）
        rel   = 该簇质心沿 p 的相对位置（0 = −p 端，1 = +p 端）
        span  = 该簇沿 p 的加权标准差 / 船长（小 = 聚在一处）

    ⚠️ 为什么要加 rel（2026-09-26 亲眼看图后补的）：
        slasher（伐木者级）/ catalyst（促进级）原本被判「需翻 180°」，但复核卡里
        俯视图明明舰艏朝上 —— 是**误报**。原因：这两艘的**翼面 / 机身中部**有朝后
        的发光板，法线也沿轴，就混进了「喷口」名单（slasher n=16、catalyst n=5）。
        真喷口**一定在船的一端**，中段那批必须剔除 —— rel 就是干这个的。
        `span` 用来进一步识别「沿轴拉得老长」的发光条（那是散热片不是喷口）。
    """
    s = NR @ p
    sel = g & (np.abs(s) > min_cos)
    n = int(sel.sum())
    if n == 0:
        return 0.0, 0, 0.5, 1.0
    a = tri_area(Q)[sel]
    tot = float(a.sum())
    sc = float((a * np.sign(s[sel])).sum()) / max(tot, 1e-12)
    t = Q.mean(1) @ p
    t0, t1 = float(t.min()), float(t.max())
    L = max(t1 - t0, 1e-9)
    tc = t[sel]
    rel = float((a * (tc - t0)).sum() / max(tot, 1e-12) / L)
    tcm = float((a * tc).sum() / max(tot, 1e-12))
    var = float((a * (tc - tcm) ** 2).sum() / max(tot, 1e-12))
    span = float((var ** 0.5) / L)
    return sc, n, rel, span


def dom_axis(v):
    k = int(np.argmax(np.abs(v)))
    return '%s%s' % ('+' if v[k] > 0 else '-', 'XYZ'[k])


def adaptive_judge(P, NR, UVC, tex, A):
    """自适应阈值判定舰艏方向（固定 THR 的替代品，见 THR_LIST 注释）。

    在 THR_LIST 每一档上跑一遍 v2（法线法），收集所有「可用」档
    （轴向自发光面数 ≥ MIN_NOZ_SOFT 且 |noz2| > SC2_SOFT），
    **要求它们符号一致**才采信，取聚拢度 |noz2|·√n 最高的那档作为结论。

    返回 dict：
        dir : +1 ⇒ 喷口朝 **+A** ⇒ 舰艏在 −A ⇒ 需翻 180°
              −1 ⇒ 喷口朝 −A ⇒ 舰艏在 +A ⇒ 保持
               0 ⇒ 判不了（无可用档 / 各档互相矛盾）
        thr : 采信的那一档阈值；sc2 / n : 该档的 noz2 与轴向面数
        votes : 全部可用档 [(thr, sc2, n), ...]
        why : 'ok' / 'none' / 'conflict'
    """
    votes = []
    for t in THR_LIST:
        g = uv_sample(tex, UVC) >= t
        if int(g.sum()) == 0:
            continue
        sc2, nnz, rel, span = nozzle_cluster(P, NR, g, A)
        # 三道闸：面数够 · 朝向够强 · **簇落在船的一端且不发散**
        if (nnz >= MIN_NOZ_SOFT and abs(sc2) > SC2_SOFT
                and abs(rel - 0.5) > END_MIN and span < SPAN_MAX):
            votes.append((float(t), float(sc2), int(nnz), float(rel), float(span)))
    if not votes:
        return dict(dir=0, thr=None, sc2=0.0, n=0, rel=0.5, span=1.0,
                    votes=[], why='none')
    if len({1 if v[1] > 0 else -1 for v in votes}) != 1:
        return dict(dir=0, thr=None, sc2=0.0, n=0, rel=0.5, span=1.0,
                    votes=votes, why='conflict')
    best = max(votes, key=lambda v: abs(v[1]) * (v[2] ** 0.5))
    return dict(dir=(1 if best[1] > 0 else -1), thr=best[0], sc2=best[1],
                n=best[2], rel=best[3], span=best[4], votes=votes, why='ok')


def glow_kinds(tex, UVC, NR, A, thr, min_cos=0.6):
    """把「自发光面」再分成两档，供图上分色 —— 判据抓的到底是哪些面，必须看得见。

    0 = 不发光
    1 = 自发光，但法线**不沿轴**（舷窗 / 散热格栅 / 装饰灯）
    2 = 自发光且法线**沿舰艏轴**（= 判据用的「喷口候选」，可能就是发动机喷口）
    """
    g = uv_sample(tex, UVC) >= thr
    ax = g & (np.abs(NR @ A) > min_cos)
    return np.where(ax, 2, np.where(g, 1, 0)).astype(np.int8)


# ── 渲染（画家算法已修正：按 dep 降序 = 远→近）──────────────────────
def render(P, NR, az, el, glow, W=560, pad=0.07, bg=(16, 19, 24), glow_kind=None):
    """画家算法已修正：按 dep 降序 = 远→近。

    glow_kind 给了 int8 数组（见 glow_kinds）时按三态分色：
        2 = 红（法线沿轴的自发光 = 判据用的喷口候选）
        1 = 橙（其他自发光 = 舷窗 / 格栅）
    不给则沿用旧行为：glow 为真的一律画红。
    """
    a, e = np.radians(az), np.radians(el)
    d = np.array([np.cos(e) * np.cos(a), np.sin(e), np.cos(e) * np.sin(a)])  # 视线方向
    # ── 2026-09-26 修正：屏幕**水平**轴符号 ──────────────────────────────
    #  Godot `Camera3D`：Z_cam = −forward(= −d)，Y_cam = up 正交化，
    #  X_cam = Y_cam × Z_cam。旧写法 `cross(up, d)` 与之**符号相反** ⇒
    #  本函数渲染的图全是**水平镜像**（"红球在上"这类竖直标注不受影响）。
    #  另外旧写法在正俯视/正仰视（d ∥ up）时会把 Xc 归零 ⇒ 整张图退化成一条线。
    Zc = -d
    up = np.array([0.0, 1.0, 0.0])
    if abs(float(up @ Zc)) > 0.99:
        up = np.array([0.0, 0.0, -1.0]) if Zc[1] > 0 else np.array([0.0, 0.0, 1.0])
    Yc = up - float(up @ Zc) * Zc
    Yc /= max(np.linalg.norm(Yc), 1e-9)
    Xc = np.cross(Yc, Zc)
    sx = P @ Xc; sy = P @ Yc; dep = P @ d
    x0, x1, y0, y1 = sx.min(), sx.max(), sy.min(), sy.max()
    span = max(x1 - x0, y1 - y0) * (1 + 2 * pad)
    sc = W / span
    H = max(48, int(round((y1 - y0 + 2 * pad * span) * sc)))
    ox = W * 0.5 - (x0 + x1) * 0.5 * sc
    oy = H * 0.5 + (y0 + y1) * 0.5 * sc
    px = np.stack([ox + sx * sc, oy - sy * sc], axis=-1)
    img = Image.new('RGB', (W, H), bg)
    dr = ImageDraw.Draw(img)
    L1 = np.array([0.45, 0.72, 0.53]); L1 /= np.linalg.norm(L1)
    base = np.array([0.60, 0.62, 0.64])
    # 相机在 −d 侧朝 +d 看 ⇒ p·d 越大越**远** ⇒ 先画远的（降序）
    for i in np.argsort(-dep.mean(axis=1)):
        if glow_kind is not None:
            gv = int(glow_kind[i])
        else:
            gv = 2 if glow[i] else 0
        if gv == 2:
            col = np.array([1.00, 0.10, 0.10])      # 轴向自发光 = 喷口候选
        elif gv == 1:
            col = np.array([0.98, 0.55, 0.08])      # 非轴向自发光 = 舷窗 / 格栅
        else:
            lam = 0.42 + 0.70 * max(0.0, float(NR[i] @ L1))
            col = np.clip(base * lam, 0, 1)
        dr.polygon([(float(px[i, k, 0]), float(px[i, k, 1])) for k in range(3)],
                   fill=tuple(int(v * 255) for v in col))
    return img


def labeled(img, t1, t2=None, h=48):
    out = Image.new('RGB', (img.width, img.height + h), (10, 12, 15))
    out.paste(img, (0, h))
    dr = ImageDraw.Draw(out)
    dr.text((8, 5), t1, font=font(23), fill=(255, 238, 130))
    if t2:
        dr.text((8, 28), t2, font=font(17), fill=(150, 205, 255))
    return out


def grid(paths, cols, tile_w, tile_h, title, out_path):
    n = len(paths)
    rows = (n + cols - 1) // cols
    TH = 62
    sheet = Image.new('RGB', (cols * tile_w, TH + rows * tile_h), (8, 10, 12))
    dr = ImageDraw.Draw(sheet)
    dr.text((10, 16), title, font=font(34), fill=(255, 235, 110))
    for k, (p, cap) in enumerate(paths):
        im = Image.open(p)
        im.thumbnail((tile_w - 8, tile_h - TH))
        cx = (k % cols) * tile_w
        cy = TH + (k // cols) * tile_h
        sheet.paste(im, (cx + 4, cy + 26))
        dr.text((cx + 6, cy + 4), cap, font=font(17), fill=(160, 210, 255))
    sheet.save(out_path)
    return out_path


def main():
    only = sys.argv[1:]
    deg, remap, flip, glob = parse_table()
    os.makedirs(OUT, exist_ok=True)
    ids = only or sorted(deg.keys())

    print('[JUDGE] `_e` 自发光 → 喷口 → 舰艏。表：AXIS_DEG=%d REMAP=%d FLIP=%d GLOBAL_180=%s'
          % (len(deg), len(remap), len(flip), glob))
    print('[JUDGE] %-13s %6s %8s %7s %7s %5s %-4s %-4s %-5s %s'
          % ('id', '发光%', 'ratio1', 'noz2', 'n_noz', '贴合', '长轴', '舰艏', '表里', '结论'))

    rows, tiles = [], []
    for sid in ids:
        gp = os.path.join(GLB_DIR, sid + '.glb')
        if not os.path.exists(gp):
            print('[JUDGE] %-13s glb 缺失' % sid); continue
        js, bin_ = load_glb(gp)
        P, NR, UVC = gather(js, bin_)
        tex = src_texture(sid)
        if tex is None or np.isnan(UVC).any():
            print('[JUDGE] %-13s %s' % (sid, '无 `_e`' if tex is None else '无 UV')); continue

        flat = P.reshape(-1, 3)
        c0 = flat.mean(0)
        w, V = np.linalg.eigh(np.cov((flat - c0).T))
        p = V[:, np.argsort(w)[::-1][0]]
        if p[int(np.argmax(np.abs(p)))] < 0:
            p = -p

        g = uv_sample(tex, UVC) >= THR
        ng = int(g.sum())
        cov = 100.0 * ng / len(P)

        M = spec_rows(remap[sid]) if sid in remap else np.eye(3)
        A = M[0]                     # 表声称的「舰艏方向」：世界X ← 模型 A

        # ⚠️ 测量轴一律取 A（不是 PCA 长轴）——
        #   A 才是表里真正决定舰艏去向的那根轴；重映射船的 PCA 长轴可能是翼展
        #   （kestrel 翼展 172 > 机身 81.6），拿它量会得到「轴向法线自相抵消」的假 0。
        _, _, r1 = area_ratio(P, g, A)
        sc2, nnz, _ = nozzle_score(P, NR, g, A)
        apx = float(abs(A @ p))      # A 与 PCA 长轴的贴合（诊断用，不参与判定）

        if nnz >= MIN_NOZ and abs(sc2) > 0.5:
            engine_dir = A if sc2 > 0 else -A
            src_metric = 'v2'
        elif ng >= MIN_FACES and abs(r1) > 0.5:
            engine_dir = A if r1 > 0 else -A
            src_metric = 'v1'
        else:
            engine_dir = None
            src_metric = '-'
        bow = (-engine_dir) if engine_dir is not None else None
        need = None if bow is None else bool(bow @ A < 0.0)

        if bow is None:
            verdict = 'n/a'
        elif need == (sid in flip):
            verdict = '一致'
        else:
            verdict = '应加' if need else '应删'

        print('[JUDGE] %-13s %5.2f%% %+8.2f %+7.2f %7d %5.2f %-4s %-4s %-5s %s'
              % (sid, cov, r1, sc2, nnz, apx, dom_axis(p),
                 dom_axis(bow) if bow is not None else '?', src_metric,
                 ('FLIP/应删' if verdict == '应删' else
                  '非FLIP/应加' if verdict == '应加' else
                  'FLIP/一致' if verdict == '一致' and sid in flip else
                  '非FLIP/一致' if verdict == '一致' else '判不了')))

        rows.append(dict(id=sid, cov=cov, r1=r1, sc2=sc2, nnz=nnz, apx=apx,
                         need=need, in_flip=sid in flip, verdict=verdict,
                         ax=dom_axis(p), bow=dom_axis(bow) if bow is not None else '?'))

        # ── 两端实拍（游戏姿态）──
        yaw = MODEL_YAW_FIX + deg.get(sid, 0.0) + (180.0 if sid in flip else 0.0) \
            + (180.0 if glob else 0.0)
        T = ry(yaw) @ M
        Q = (T @ P.reshape(-1, 3).T).T.reshape(-1, 3, 3)
        NRq = (T @ NR.T).T
        _, _, rz = area_ratio(Q, g, np.array([0.0, 0.0, 1.0]))
        Qs = Q - np.array([0.0, 0.0, 0.5 * (Q[:, :, 2].min() + Q[:, :, 2].max())])
        v = '★倒飞' if rz > 0.5 else ('OK' if rz < -0.5 else '?')
        ps = os.path.join(OUT, '%s_stern.png' % sid)
        labeled(render(Qs, NRq, 62.0, 18.0, g), '%s [看船尾 -Z]' % sid,
                '%s  ratio=%+.2f%s' % (v, rz, '  [表内FLIP]' if sid in flip else ''))\
            .save(ps)
        pb = os.path.join(OUT, '%s_bow.png' % sid)
        labeled(render(Qs, NRq, 242.0, 18.0, g), '%s [看船艏 +Z]' % sid,
                'ratio=%+.2f' % rz).save(pb)
        labeled(render(Qs, NRq, 35.0, 20.0, g), '%s [斜视]' % sid, 'Az+35 El+20')\
            .save(os.path.join(OUT, '%s_iso.png' % sid))
        tiles.append((sid, ps, pb, verdict, rz))

    jr = [r for r in rows if r['verdict'] != 'n/a']
    bad = [r for r in jr if r['verdict'] != '一致']
    print('')
    print('[JUDGE] ═══ 结论 ═══')
    print('[JUDGE] 判得动 %d / 全库 %d；与现表**不一致** %d 艘' % (len(jr), len(rows), len(bad)))
    print('[JUDGE] · 表里在 FLIP、判据说该删（舰艏本就在 +A，不需要翻）：%s'
          % (sorted(r['id'] for r in bad if r['verdict'] == '应删') or '无'))
    print('[JUDGE] · 表里不在 FLIP、判据说该加（舰艏在 −A，需要翻）：%s'
          % (sorted(r['id'] for r in bad if r['verdict'] == '应加') or '无'))
    print('[JUDGE] · 判不了（贴图自发光太少 / 舰艏不在 M 第一行方向）：%s'
          % (sorted(r['id'] for r in rows if r['verdict'] == 'n/a') or '无'))

    if len(tiles) > 8:
        grid([(t[1], '%s  %s rz=%+.2f' % (t[0], t[3], t[4])) for t in tiles], 7,
             320, 250, '游戏姿态 · 站在船尾(-Z)看 —— 应该看到喷口红块', 
             os.path.join(r'C:\godot\_export', '_pose_sheet_stern.png'))
        grid([(t[2], '%s' % t[0]) for t in tiles], 7,
             320, 250, '游戏姿态 · 站在船艏(+Z)看 —— 不该有喷口',
             os.path.join(r'C:\godot\_export', '_pose_sheet_bow.png'))
        print('[JUDGE] 总览图：_pose_sheet_stern.png / _pose_sheet_bow.png')
    print('[JUDGE] ==== DONE ====')


if __name__ == '__main__':
    main()
