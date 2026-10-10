#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""EVE 官方星云立方体 (BC6H cubemap) → 游戏用 2:1 等距柱状天空盒 PNG

流程（严格照 skill `eve-nebula-skybox`）：
  1. 从 resfileindex.txt 定位 <组名>_cube.dds，复制成带扩展名的 .dds
     （缓存文件【没有扩展名】，texconv 靠后缀判容器格式）
  2. texconv 解成 R32G32B32A32_FLOAT（-m 1 只留顶层 mip，否则字节偏移全错）
  3. 读 6 个面 → 等距柱状投影
  4. ACES filmic 色调映射 + γ2.2 + lift + 三角抖动
  5. 出 4096×2048 PNG，并做「随机方向 vs 直接查立方体」的映射验收

用法：
  PY eve_neb.py --cube c07 --out F:/evezzq/eve自走棋918/assets/backgrounds/caldari-c07-nebula-4096.png

★ 那个 face table 的坑（本脚本最要命的一处）：
  判正负【必须用带符号分量】，不能用 |分量|。用绝对值的话 |x|>0 恒真，
  面 1/3/5（-X/-Y/-Z）永远不被选中，负半球全被当成正半球采样。
  症状：屏幕上 90° 宽的「圆角方块」+ 整体发灰（最亮的 -X 面被整个丢弃）。
"""
import argparse
import io
import os
import shutil
import subprocess
import sys
import tempfile

import numpy as np
from PIL import Image

Image.MAX_IMAGE_PIXELS = None

IDX_TQ = r"D:\EVE\SharedCache\tq\resfileindex.txt"
RES_FILES = r"D:\EVE\SharedCache\ResFiles"
TEXCONV = r"C:\godot\_export\_tools\texconv.exe"

OUT_W, OUT_H = 4096, 2048

# ── 色调映射旋钮（skill 的推荐值）────────────────────────────────
PCT_FOR_NORM = 99.9     # 按亮度 p99.9 归一 —— 各组 HDR 值域差异极大，必须按图归一
SATURATION = 1.30
GAMMA = 2.2
LIFT = 0.006
DITHER = 1.0 / 255.0    # 三角抖动幅度


# ══════════════════════════════════════════════════════════════════
# 1) 从缓存索引定位并取出 cube
# ══════════════════════════════════════════════════════════════════

def find_cube(cube: str):
    """在 resfileindex.txt 里找 <cube>_cube.dds，返回 (资源路径, 本地绝对路径)。"""
    target = cube.lower() + "_cube.dds"
    hit = None
    with io.open(IDX_TQ, "r", encoding="utf-8", errors="replace") as f:
        for line in f:
            if "/universe/" not in line:
                continue
            p = line.rstrip("\n").split(",")
            if len(p) < 5:
                continue
            if os.path.basename(p[0]).lower() == target:
                # 字段：资源路径, 缓存相对路径, 内容哈希, 压缩体积, 未压缩体积
                hit = (p[0], os.path.join(RES_FILES, p[1]))
                break
    if hit is None:
        raise SystemExit("索引里找不到 %s" % target)
    if not os.path.exists(hit[1]):
        raise SystemExit("本地缓存没有 %s（需要从 CDN 下：%s）" % (target, hit[1]))
    return hit


def decode_cube_to_float(cube: str, workdir: str) -> np.ndarray:
    """返回 (6, H, W, 3) float32，线性 HDR（未经色调映射）。"""
    res_path, local = find_cube(cube)

    # texconv 靠后缀判格式 → 必须先复制成 .dds
    src = os.path.join(workdir, cube + "_cube.dds")
    shutil.copyfile(local, src)

    outdir = os.path.join(workdir, "float")
    os.makedirs(outdir, exist_ok=True)
    cmd = [TEXCONV, "-y", "-nologo", "-m", "1",
           "-f", "R32G32B32A32_FLOAT", "-ft", "dds", "-o", outdir, src]
    # ⚠️ 中文 Windows 下 texconv 的 stdout 是 GBK，按 utf-8 解会抛 UnicodeDecodeError
    r = subprocess.run(cmd, capture_output=True)
    out_txt = r.stdout.decode("utf-8", errors="replace")
    err_txt = r.stderr.decode("utf-8", errors="replace")
    if r.returncode != 0:
        raise SystemExit("texconv 失败(%d)：\n%s\n%s" % (r.returncode, out_txt, err_txt))

    fdds = os.path.join(outdir, cube + "_cube.dds")
    if not os.path.exists(fdds):
        cands = [f for f in os.listdir(outdir) if f.lower().endswith(".dds")]
        if not cands:
            raise SystemExit("texconv 没产出文件：\n%s" % out_txt)
        fdds = os.path.join(outdir, cands[0])

    raw = open(fdds, "rb").read()
    fourcc = raw[84:88]
    hdr = 148 if fourcc == b"DX10" else 128
    print("    解码 DDS：%s  fourcc=%s  头=%d 字节  总长=%d"
          % (os.path.basename(fdds), fourcc, hdr, len(raw)))

    payload = len(raw) - hdr
    # 每面 = payload/6；由它反推面边长（float32 × RGBA = 16 字节/像素）
    per_face = payload // 6
    px = per_face // 16
    w = int(round(px ** 0.5))
    h = w
    if w * h * 16 * 6 != payload:
        raise SystemExit("面尺寸对不上：payload=%d，推得 %dx%d" % (payload, w, h))
    print("    立方体：%d² × 6 面" % w)

    arr = np.frombuffer(raw[hdr:hdr + per_face * 6], dtype=np.float32)
    arr = arr.reshape(6, h, w, 4)[..., :3]
    print("    线性 HDR 统计：min=%.4f  中位=%.4f  p99.9=%.4f  max=%.4f"
          % (arr.min(), np.median(arr), np.percentile(arr, 99.9), arr.max()))
    return arr


# ══════════════════════════════════════════════════════════════════
# 2) 立方体 → 等距柱状
# ══════════════════════════════════════════════════════════════════

def cube_to_equirect(faces: np.ndarray, ow: int, oh: int) -> np.ndarray:
    """dir → 面 + (fu,fv) → 双线性采样。返回 (oh, ow, 3) float32。

    面序（D3D）：0..5 = +X, -X, +Y, -Y, +Z, -Z
    """
    n, fh, fw, _ = faces.shape
    assert n == 6

    # 输出像素中心方向
    #
    # ⚠️ 经度起点必须用 u=0 ↔ +Z（lon = u·2π），不能写成 lon = (u−0.5)·2π。
    #    这不是风格问题：引擎侧（Godot PanoramaSky / 工程 verify_background.gd）与
    #    skill 都规定 `u = atan2(x, z) / 2π`。
    #    写成 (u−0.5) 会让【方位角整体偏 180°】—— 图看着照样是张星云，
    #    但在引擎里东西对调。本轮就是靠 validate_mapping 抓出来的：
    #    +X 方向从立方体读到 0.04725、从等距柱状读到 0.05056（正好是 −X 的值）。
    u = (np.arange(ow, dtype=np.float32) + 0.5) / ow          # [0,1)
    v = (np.arange(oh, dtype=np.float32) + 0.5) / oh
    lon = u * (2.0 * np.pi)                                    # 0..2π（u=0 → +Z）
    lat = (0.5 - v) * np.pi                                    # +π/2..-π/2
    coslat = np.cos(lat)
    # (oh, ow)
    dx = (coslat[:, None] * np.sin(lon)[None, :]).astype(np.float32)
    dy = (np.sin(lat)[:, None] * np.ones((1, ow), np.float32)).astype(np.float32)
    dz = (coslat[:, None] * np.cos(lon)[None, :]).astype(np.float32)

    ax, ay, az = np.abs(dx), np.abs(dy), np.abs(dz)

    # 主轴 —— 用 argmax 一次定完，避免写成三条互斥分支
    stack = np.stack([ax, ay, az], axis=0)
    major = np.argmax(stack, axis=0)          # 0=X 1=Y 2=Z

    # ★ 判正负用【带符号分量】，不是 |分量|
    sign = np.choose(major, [dx, dy, dz])     # 带符号
    ma = np.choose(major, [ax, ay, az])

    face = np.empty_like(major)
    sc = np.empty_like(ma)
    tc = np.empty_like(ma)

    pos = sign > 0
    # X 主轴：+X=面0 (sc=-z, tc=-y) / -X=面1 (sc=+z, tc=-y)
    mX = (major == 0)
    face[mX] = np.where(pos[mX], 0, 1)
    sc[mX] = np.where(pos[mX], -dz[mX], dz[mX])
    tc[mX] = -dy[mX]
    # Y 主轴：+Y=面2 (sc=+x, tc=+z) / -Y=面3 (sc=+x, tc=-z)
    mY = (major == 1)
    face[mY] = np.where(pos[mY], 2, 3)
    sc[mY] = dx[mY]
    tc[mY] = np.where(pos[mY], dz[mY], -dz[mY])
    # Z 主轴：+Z=面4 (sc=+x, tc=-y) / -Z=面5 (sc=-x, tc=-y)
    mZ = (major == 2)
    face[mZ] = np.where(pos[mZ], 4, 5)
    sc[mZ] = np.where(pos[mZ], dx[mZ], -dx[mZ])
    tc[mZ] = -dy[mZ]

    ma = np.maximum(ma, 1e-12)
    fu = (sc / ma + 1.0) * 0.5 * (fw - 1)
    fv = (tc / ma + 1.0) * 0.5 * (fh - 1)

    # 逐面采样（分块以免峰值内存爆掉）
    out = np.empty((oh, ow, 3), dtype=np.float32)
    x0 = np.floor(fu).astype(np.int32)
    y0 = np.floor(fv).astype(np.int32)
    tx = (fu - x0)[..., None].astype(np.float32)
    ty = (fv - y0)[..., None].astype(np.float32)
    x0c = np.clip(x0, 0, fw - 2)
    y0c = np.clip(y0, 0, fh - 2)
    x1c = x0c + 1
    y1c = y0c + 1

    for fi in range(6):
        m = (face == fi)
        if not m.any():
            raise SystemExit("面 %d 一个像素都没选中 —— 面选择表有问题！" % fi)
        rows = np.where(m.any(axis=1))[0]
        f = faces[fi]
        for r0 in range(0, rows.size, 64):
            rr = rows[r0:r0 + 64]
            mm = m[rr]
            yy = np.nonzero(mm)[0]
            xx = np.nonzero(mm)[1]
            a = f[y0c[rr][mm], x0c[rr][mm]].astype(np.float32)
            b = f[y0c[rr][mm], x1c[rr][mm]].astype(np.float32)
            c = f[y1c[rr][mm], x0c[rr][mm]].astype(np.float32)
            d = f[y1c[rr][mm], x1c[rr][mm]].astype(np.float32)
            txx = tx[rr][mm]
            tyy = ty[rr][mm]
            top = a * (1 - txx) + b * txx
            bot = c * (1 - txx) + d * txx
            out[rr[yy], xx] = top * (1 - tyy) + bot * tyy
    return out


def validate_mapping(faces: np.ndarray, eq: np.ndarray, samples: int = 200000) -> float:
    """随机方向：等距柱状（双线性回读） vs 直接查立方体，返回相对平均误差。

    ⚠️ 这是【唯一可靠】的映射验收法。
       不要用「相邻面公共边像素差」—— 那个测试在 bug 存在时照样通过
       （它只证明源数据连续，没证明映射正确）。
    """
    n, fh, fw, _ = faces.shape
    rng = np.random.default_rng(12345)
    # 均匀球面采样
    z = rng.uniform(-1, 1, samples).astype(np.float32)
    thi = rng.uniform(0, 2 * np.pi, samples).astype(np.float32)
    r = np.sqrt(np.maximum(0.0, 1 - z * z))
    dx, dy, dz = r * np.cos(thi), z, r * np.sin(thi)

    ax, ay, az = np.abs(dx), np.abs(dy), np.abs(dz)
    stack = np.stack([ax, ay, az], axis=0)
    major = np.argmax(stack, axis=0)
    sign = np.choose(major, [dx, dy, dz])
    ma = np.maximum(np.choose(major, [ax, ay, az]), 1e-12)
    pos = sign > 0
    face = np.empty_like(major)
    sc = np.empty_like(ma)
    tc = np.empty_like(ma)
    mX = (major == 0)
    face[mX] = np.where(pos[mX], 0, 1); sc[mX] = np.where(pos[mX], -dz[mX], dz[mX]); tc[mX] = -dy[mX]
    mY = (major == 1)
    face[mY] = np.where(pos[mY], 2, 3); sc[mY] = dx[mY]; tc[mY] = np.where(pos[mY], dz[mY], -dz[mY])
    mZ = (major == 2)
    face[mZ] = np.where(pos[mZ], 4, 5); sc[mZ] = np.where(pos[mZ], dx[mZ], -dx[mZ]); tc[mZ] = -dy[mZ]
    fu = (sc / ma + 1.0) * 0.5 * (fw - 1)
    fv = (tc / ma + 1.0) * 0.5 * (fh - 1)
    direct = faces[face, np.round(fv).astype(int), np.round(fu).astype(int)]

    oh, ow, _ = eq.shape
    uu = np.arctan2(dx, dz) / (2 * np.pi)
    uu = uu % 1.0
    vv = 0.5 - np.arcsin(np.clip(dy, -1, 1)) / np.pi
    px = uu * ow - 0.5
    py = vv * oh - 0.5
    x0 = np.clip(np.floor(px).astype(int), 0, ow - 1)
    x1 = (x0 + 1) % ow                       # 经度环绕
    y0 = np.clip(np.floor(py).astype(int), 0, oh - 2)
    y1 = y0 + 1
    tx = (px - np.floor(px))[:, None]
    ty = (py - np.floor(py))[:, None]
    a = eq[y0, x0]; b = eq[y0, x1]; c = eq[y1, x0]; d = eq[y1, x1]
    top = a * (1 - tx) + b * tx
    bot = c * (1 - tx) + d * tx
    got = top * (1 - ty) + bot * ty

    err = np.abs(got - direct).mean()
    scale = np.abs(direct).mean() + 1e-9
    return err / scale


# ══════════════════════════════════════════════════════════════════
# 3) 色调映射
# ══════════════════════════════════════════════════════════════════

def tonemap(rgb: np.ndarray) -> np.ndarray:
    """ACES filmic 近似 + 饱和度 + γ2.2 + lift + 三角抖动 → uint8。"""
    lum = 0.2126 * rgb[..., 0] + 0.7152 * rgb[..., 1] + 0.0722 * rgb[..., 2]
    ref = np.percentile(lum, PCT_FOR_NORM)
    print("    归一化基准 p%.1f = %.5f" % (PCT_FOR_NORM, ref))
    x = rgb / max(ref, 1e-9)
    x = np.clip(x, 0.0, None)
    # ACES 近似（Narkowicz）
    x = np.clip(x * (2.51 * x + 0.03) / (x * (2.43 * x + 0.59) + 0.14), 0.0, 1.0)
    # 饱和度：绕亮度插值
    l2 = (0.2126 * x[..., 0] + 0.7152 * x[..., 1] + 0.0722 * x[..., 2])[..., None]
    x = np.clip(l2 + (x - l2) * SATURATION, 0.0, 1.0)
    # γ2.2 + lift
    x = np.power(x, 1.0 / GAMMA) * (1.0 - LIFT) + LIFT
    # 量化前三角抖动 —— 深空大面积渐变不加必出色带
    rng = np.random.default_rng(7)
    if x.shape[0] > 4 and x.shape[1] > 4:
        d = rng.random(x.shape[:2]).astype(np.float32) - rng.random(x.shape[:2]).astype(np.float32)
        x = x + (d * DITHER)[..., None]
    return np.clip(x * 255.0 + 0.5, 0, 255).astype(np.uint8)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--cube", required=True, help="组名，如 c07（不含 _cube.dds）")
    ap.add_argument("--out", required=True, help="输出 PNG 路径")
    ap.add_argument("--size", default="%dx%d" % (OUT_W, OUT_H))
    args = ap.parse_args()
    ow, oh = (int(t) for t in args.size.lower().split("x"))

    print("=" * 70)
    print("EVE 星云立方体 → 等距柱状   组名=%s   输出=%dx%d" % (args.cube, ow, oh))
    print("=" * 70)

    workdir = tempfile.mkdtemp(prefix="eveneb_")
    print("[1] 定位并解码 cube")
    faces = decode_cube_to_float(args.cube, workdir)

    print("[2] 立方体 → 等距柱状投影")
    eq = cube_to_equirect(faces, ow, oh)

    print("[3] 映射验收（随机方向 vs 直接查立方体）")
    rel = validate_mapping(faces, eq)
    ok = rel < 0.02
    print("    相对平均误差 = %.4f%%   %s" % (rel * 100.0, "[OK]" if ok else "[FAIL]"))
    if not ok:
        print("    ⚠️ 误差过大 —— 面选择表很可能又写成了绝对值判正负")
        sys.exit(2)

    print("[4] 色调映射 (ACES + sat%.2f + γ%.1f + lift%.3f)"
          % (SATURATION, GAMMA, LIFT))
    img8 = tonemap(eq)

    os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
    Image.fromarray(img8, "RGB").save(args.out)
    g = np.asarray(Image.open(args.out).convert("L"), dtype=np.uint8).astype(np.float32)
    p = np.sort(g.ravel())
    q = lambda f: p[min(p.size - 1, int(p.size * f))]
    print("[5] 已保存 %s" % args.out)
    print("    亮度：均值 %.1f  p1=%.0f  p10=%.0f  p50=%.0f  p99=%.0f  明暗比 %.1f×"
          % (g.mean(), q(0.01), q(0.10), q(0.50), q(0.99),
             (q(0.99) + 1) / (q(0.01) + 1)))
    shutil.rmtree(workdir, ignore_errors=True)


if __name__ == "__main__":
    main()
