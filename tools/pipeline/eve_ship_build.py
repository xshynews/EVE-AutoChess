# -*- coding: utf-8 -*-
r"""
=======================================================================
 EVE 舰船 3D 资产获取流水线  ——  从 typeID 到可用的 OBJ + 官方贴图
=======================================================================

一条命令跑完「官方 3D 模型 + 官方贴图」的全部获取与转换：

    python eve_ship_build.py --id 597 -o ./out/punisher

产出（都在 -o 目录下）：:

    <ModelName>.obj        Blender 原生 Z-up、UV 已 V 翻转、1 世界单位 = 1 米
    <ModelName>.mtl        引用下面贴图的材质
    textures/*.png|jpg     官方漫反射 / 高光(材质分区) / 法线 / 自发光
    ship.json              清单：名字、typeID、节点路径、面数、包围盒尺寸、贴图清单
    _report.json           本次运行的结构化报告（给自动化/回归用）

--------------------------------------------------------------- 原理
数据源 https://gamemodels3d.com/games/eveonline/vehicles/<typeID>
（站点自己带 Three.js 预览器，能看到就能下；不需要登录，直接抓原始资产）

页面源码里三个 JS 常量决定一切，**逐个正则抓出来，不要猜路径**：
    path      : "/games/eveonline/data/current/"         → 资源根
    modelName : "Punisher"                               → 模型名
    scheme    : {"visual":{"ship":{"visual":                  ← 节点路径
                  "amarr/597/visual/default/ship"}}}          （方案/皮肤见下）

资源文件 = <根> + <节点路径> + ".model" / ".material"，
两者都是 **压缩过的 JSON**（zlib / raw-deflate / gzip 三种都可能，要都试）。

--------------------------------------------------------------- 三条铁律
写 OBJ / 进 Blender 时**必须**遵守，每条都是实测踩出来的：

① UV 要 V 翻转
   源是 three.js，纹理 flipY = false（V 原点在上）；OBJ/Blender 的 V 原点在下。
   不翻转 → 贴图上下颠倒（表现为「白甲板跑到船底」）。
   注意 .material 里若引用了 specularMap，同一规则也适用于它。

② 源坐标的 Y 是**舰船高度轴**，不是深度
   实测惩罚者级：X = 36.6 横梁 / Y = 27.4 高 / Z = 65.5 长轴。
   直接按 (x, y, z) 写 OBJ，进 Blender（Z-up）会**侧滚 90°**。
   正确写 (x, z, −y) → Z 朝上、长轴落在 Y，再由 Blender 侧统一转向。
   （glTF 因为本来就是 Y-up，导入 Blender 会自动纠正 —— 所以走 GLB 不用管这条。）

③ `_s` 高光图是**材质分区图**，不是渐进高光
   三档离散值：≈0.35 白装甲板（哑光、metallic 0）
               ≈0.68 深色结构（metallic 0.80）
               ≈0.78 金色饰件（metallic 0.95）
   配方：roughness = 1 − spec，metallic = ramp(spec)。
   ⚠️ 全局拉金属度会把白甲板渲成银灰。官方那种「暗古铜 + 金色雕花」是
      **暗环境下的金属反射**，不是纹理里画的黑 —— 拿亮环境平光渲就是平涂金。

--------------------------------------------------------------- 皮肤/方案
站点支持多皮肤：节点路径里的 `visual/default/` 就是皮肤名。
站点 JS 的规则是 `path.replace("visual/", "visual/default/")` ——
即默认皮肤为 default。换皮肤就替换这一段。

--------------------------------------------------------------- 用法
    --id N            车辆 typeID（必填）
    -o DIR            输出目录（必填）
    --skin NAME       皮肤，默认 default
    --node PATH       直接指定节点路径（跳过页面解析，排障用）
    --no-tex          只下模型，不下贴图
    --quiet
"""
import argparse
import json
import os
import re
import ssl
import sys
import time
import urllib.error
import urllib.request
import zlib

SITE = "https://gamemodels3d.com"
GAME = "eveonline"
HDRS = {
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
                  "(KHTML, like Gecko) Chrome/126.0 Safari/537.36",
    "Accept": "*/*",
}
# 站点证书链在本机不完全可信，且只是公开静态资源 —— 关校验，别在这上面卡住。
CTX = ssl.create_default_context()
CTX.check_hostname = False
CTX.verify_mode = ssl.CERT_NONE

MAX_MODEL = 256 * 1024 * 1024
MAX_TEX = 64 * 1024 * 1024


# ─────────────────────────────────────────────────────────── HTTP
def http_get(url, referer=None, limit=MAX_MODEL, retries=3):
    """GET 一个 URL，返回 bytes。失败重试。"""
    hdrs = dict(HDRS)
    if referer:
        hdrs["Referer"] = referer
    last = None
    for i in range(retries):
        try:
            req = urllib.request.Request(url, headers=hdrs)
            with urllib.request.urlopen(req, timeout=60, context=CTX) as r:
                return r.read(limit)
        except urllib.error.HTTPError as e:
            # 4xx 是「真的没有」，重试没意义
            if 400 <= e.code < 500:
                raise
            last = e
        except Exception as e:                     # noqa: BLE001
            last = e
        time.sleep(0.6 * (i + 1))
    raise RuntimeError("%s: %s" % (url, last))


def inflate_any(data):
    """三种压缩都试一遍。站点不同资产用了不同 wbits，不能只试一种。"""
    for wbits in (15, -15, 47):
        try:
            return zlib.decompress(data, wbits)
        except Exception:                          # noqa: BLE001
            pass
    return None


def get_json(url, referer=None):
    raw = http_get(url, referer)
    plain = inflate_any(raw)
    if plain is None:
        plain = raw          # 有的资产就是没压
    return json.loads(plain.decode("utf-8"))


# ─────────────────────────────────────────────────────────── 页面解析
def parse_vehicle_page(typeid):
    """从车辆页源码里抓 path / modelName / 节点路径。

    这三个值站点是写死在页面 JS 里的（不是拼出来的），所以直接读比猜路径可靠。
    """
    url = "%s/games/%s/vehicles/%d" % (SITE, GAME, typeid)
    html = http_get(url, referer=SITE, limit=8 * 1024 * 1024).decode("utf-8", "replace")

    root = re.search(r'path\s*:\s*"([^"]+)"', html)
    name = re.search(r'modelName\s*:\s*"([^"]+)"', html)
    # ⚠️ 节点路径是 **JS 字面量**，斜杠被转义成 `\/`：
    #    scheme : {"visual":{"ship":{"visual":"amarr\/597\/visual\/default\/ship", ...}}}
    #    实践上「先按最小模式抓出字符串、再反转义」比在正则里处理转义稳妥得多 ——
    #    在正则字符类里凑 `[\\/]` 那一版实测直接匹配不到（踩过）。
    node_path = None
    for m in re.finditer(r'"visual"\s*:\s*"([^"]+)"', html):
        cand = m.group(1).replace("\\/", "/")
        if "/visual/" in cand and re.search(r"/\d+/", cand):
            node_path = cand
            break

    return {
        "page": url,
        "root": root.group(1) if root else "/games/%s/data/current/" % GAME,
        "model_name": name.group(1) if name else str(typeid),
        "node": node_path,
        "html_bytes": len(html),
    }


# ─────────────────────────────────────────────────────────── 几何
def pick_geometry(model_json):
    """.model 的 geometry 是个字典；挑顶点最多的那一件。

    多数船只有一件（键名是空串），但有些船按 LOD / 部件分多件。
    挑最大的那件 = 「精度最高的那一版」，符合我们做立绘的需求。
    """
    geo = model_json.get("geometry") or {}
    best_key, best = None, None
    best_n = -1
    for k, v in geo.items():
        if not isinstance(v, dict) or not v.get("position"):
            continue
        n = len(v["position"])
        if n > best_n:
            best_key, best, best_n = k, v, n
    if best is None:
        raise RuntimeError(".model 里没有可用的 geometry")
    return best_key, best


def read_texts(material_json):
    """从 .material 里收集所有贴图路径（去重、保序）。"""
    paths = []
    for group in (material_json.get("materials") or {}).values():
        entries = group.get("default") if isinstance(group, dict) else None
        if not isinstance(entries, list):
            continue
        for e in entries:
            if not isinstance(e, dict):
                continue
            for k in ("map", "specularMap", "normalMap", "emissiveMap",
                      "alphaMap", "bumpMap", "lightMap"):
                p = e.get(k)
                if p and p not in paths:
                    paths.append(p)
    return paths


def write_obj(path, mtl_name, obj_name, pos, uv, idx, groups, flip_v=True, z_up=True):
    """写 Blender 原生 OBJ。

    z_up:  (x, y, z) -> (x, z, -y)     见铁律②
    flip_v: v -> 1 - v                 见铁律①
    """
    nvert = len(pos) // 3
    nuv = len(uv) // 2
    with open(path, "w", encoding="utf-8", newline="\n") as w:
        w.write("# gamemodels3d - EVE Online - %s\n" % obj_name)
        w.write("# coords: %s   v_flip=%s\n"
                % ("(x, z, -y) Blender Z-up" if z_up else "(x, y, z) raw", flip_v))
        if mtl_name:
            w.write("mtllib %s\n" % mtl_name)
        w.write("o %s\n" % obj_name)
        for i in range(nvert):
            x, y, z = pos[i * 3], pos[i * 3 + 1], pos[i * 3 + 2]
            if z_up:
                w.write("v %.6f %.6f %.6f\n" % (x, z, -y))
            else:
                w.write("v %.6f %.6f %.6f\n" % (x, y, z))
        for i in range(nuv):
            u, v = uv[i * 2], uv[i * 2 + 1]
            w.write("vt %.6f %.6f\n" % (u, (1.0 - v) if flip_v else v))
        w.write("s off\n")
        has_uv = nuv == nvert
        for gi, g in enumerate(groups):
            mi = g.get("material", 0)
            w.write("g group_%d\nusemtl mat_%d\n" % (gi, mi))
            for t in range(g.get("start", 0),
                           g.get("start", 0) + g.get("count", 0), 3):
                a, b, c = idx[t] + 1, idx[t + 1] + 1, idx[t + 2] + 1
                if has_uv:
                    w.write("f %d/%d %d/%d %d/%d\n" % (a, a, b, b, c, c))
                else:
                    w.write("f %d %d %d\n" % (a, b, c))


def write_mtl(path, mat_name, tex_paths, urls_base):
    """写 MTL。map_Kd 用漫反射，map_Bump 用法线。

    ⚠️ 这里**不写** metallic/roughness —— MTL 表达不了「高光图其实是材质分区图」
       这层语义（见铁律③）。真实配方在 Blender 侧按节点图搭。
    """
    def base(p):
        return os.path.basename(p)

    # 按后缀认通道 —— 站点命名约定 _d/_s/_n/_e
    d = s = n = e = None
    for p in tex_paths:
        b = base(p).lower()
        if b.endswith("_d.png") or b.endswith("_d.jpg"):
            d = d or p
        elif b.endswith("_s.jpg") or b.endswith("_s.png"):
            s = s or p
        elif b.endswith("_n.png") or b.endswith("_n.jpg"):
            n = n or p
        elif b.endswith("_e.png") or b.endswith("_e.jpg"):
            e = e or p
    with open(path, "w", encoding="utf-8", newline="\n") as w:
        w.write("# gamemodels3d official material\n")
        w.write("# maps: d=%s s=%s n=%s e=%s\n" % (base(d) if d else "-",
                                                  base(s) if s else "-",
                                                  base(n) if n else "-",
                                                  base(e) if e else "-"))
        w.write("newmtl %s\n" % mat_name)
        w.write("Kd 1.000000 1.000000 1.000000\n")
        w.write("Ka 0.000000 0.000000 0.000000\n")
        w.write("Ks 0.300000 0.300000 0.300000\n")
        w.write("Ns 32.0\n")
        w.write("d 1.0\nillum 2\n")
        if d:
            w.write("map_Kd textures/%s\n" % base(d))
        if s:
            w.write("# specular map = 材质分区图（不是渐进高光）\n")
            w.write("map_Ks textures/%s\n" % base(s))
        if n:
            w.write("map_Bump textures/%s\n" % base(n))
    return {"d": d, "s": s, "n": n, "e": e}


# ─────────────────────────────────────────────────────────── 主流程
def build(typeid, outdir, skin="default", node_override=None,
          want_tex=True, quiet=False):
    def log(*a):
        if not quiet:
            print(*a)
            sys.stdout.flush()

    os.makedirs(outdir, exist_ok=True)
    rep = {"typeid": typeid, "out": outdir, "steps": [], "textures": {}, "warnings": []}

    # ① 页面
    info = parse_vehicle_page(typeid)
    rep["page"] = info["page"]
    rep["root"] = info["root"]
    rep["model_name"] = info["model_name"]
    node = node_override or info["node"]
    if not node:
        raise RuntimeError("页面里找不到节点路径，也没有 --node；站点结构可能变了")
    if skin != "default":
        node = re.sub(r"/visual/[^/]+/", "/visual/%s/" % skin, node)
    rep["node"] = node
    log("[1/5] 页面解析 OK  modelName=%s  node=%s" % (info["model_name"], node))

    # ② 模型 + 材质
    referer = info["page"]
    root_url = SITE + info["root"]
    model_url = root_url + node + ".model"
    mat_url = root_url + node + ".material"
    model_json = get_json(model_url, referer)
    rep["model_url"] = model_url
    rep["model_version"] = model_json.get("version")
    log("[2/5] .model  %s  version=%s" % (model_url, model_json.get("version")))

    mat_json = None
    tex_paths = []
    try:
        mat_json = get_json(mat_url, referer)
        tex_paths = read_texts(mat_json)
        rep["material_url"] = mat_url
        log("[3/5] .material  %s  贴图 %d 张" % (mat_url, len(tex_paths)))
    except Exception as ex:                        # noqa: BLE001
        rep["warnings"].append("材质下载失败（不影响几何）: %s" % ex)
        log("[3/5] .material 失败：%s" % ex)

    # ③ 几何
    gkey, geo = pick_geometry(model_json)
    pos, uv, idx = geo["position"], geo.get("uv") or [], geo.get("index") or []
    groups = geo.get("groups") or [
        {"material": 0, "start": 0, "count": len(idx)}]
    nvert = len(pos) // 3
    nface = len(idx) // 3
    xs = [pos[i * 3] for i in range(nvert)]
    ys = [pos[i * 3 + 1] for i in range(nvert)]
    zs = [pos[i * 3 + 2] for i in range(nvert)]
    dims = [max(xs) - min(xs), max(ys) - min(ys), max(zs) - min(zs)]
    rep["geometry"] = {
        "key": gkey, "verts": nvert, "faces": nface, "groups": len(groups),
        "has_uv": len(uv) // 2 == nvert,
        "dims_raw": [round(v, 3) for v in dims],
        # 源坐标语义：Y 是高度轴（铁律②）
        "axes_raw": {"x_beam": round(dims[0], 3),
                     "y_height": round(dims[1], 3),
                     "z_length": round(dims[2], 3)},
    }
    log("[3/5] 几何  %d verts / %d faces / %d groups  UV=%s"
        % (nvert, nface, len(groups), rep["geometry"]["has_uv"]))
    log("      原始轴向  X(梁)=%.2f  Y(高)=%.2f  Z(长)=%.2f"
        % (dims[0], dims[1], dims[2]))
    if dims[1] > dims[0] and dims[1] > dims[2]:
        rep["warnings"].append("Y 不是高度轴？请人工确认轴向（铁律②的前提）")

    # ④ 贴图
    if want_tex and tex_paths:
        tdir = os.path.join(outdir, "textures")
        os.makedirs(tdir, exist_ok=True)
        for p in tex_paths:
            url = root_url + p
            fn = os.path.basename(p)
            dst = os.path.join(tdir, fn)
            try:
                blob = http_get(url, referer, limit=MAX_TEX)
                with open(dst, "wb") as w:
                    w.write(blob)
                rep["textures"][fn] = {"bytes": len(blob), "url": url}
                log("       贴图 %-24s %d 字节" % (fn, len(blob)))
            except Exception as ex:                # noqa: BLE001
                rep["warnings"].append("贴图缺失 %s: %s" % (fn, ex))
                log("       贴图 %-24s 失败 %s" % (fn, ex))

    # ⑤ 落盘
    safe = re.sub(r"[^A-Za-z0-9_]+", "_", info["model_name"]) or str(typeid)
    mtl_file = "%s.mtl" % safe
    obj_file = "%s.obj" % safe
    maps = write_mtl(os.path.join(outdir, mtl_file), "mat_0", tex_paths, root_url) \
        if tex_paths else {"d": None, "s": None, "n": None, "e": None}
    write_obj(os.path.join(outdir, obj_file), mtl_file if tex_paths else None,
              info["model_name"], pos, uv, idx, groups)
    rep["obj"] = obj_file
    rep["mtl"] = mtl_file if tex_paths else None
    rep["maps"] = {k: (os.path.basename(v) if v else None) for k, v in maps.items()}
    log("[4/5] 写出 %s / %s" % (obj_file, mtl_file))

    manifest = {
        "model_name": info["model_name"],
        "typeid": typeid,
        "game": GAME,
        "page": info["page"],
        "root": info["root"],
        "node": node,
        "skin": skin,
        "obj": obj_file,
        "mtl": rep["mtl"],
        "textures": {k: ("textures/" + v) for k, v in
                     [(k, os.path.basename(v)) for k, v in maps.items()] if v},
        "all_textures": [os.path.basename(p) for p in tex_paths],
        "geometry": rep["geometry"],
        "rules": {
            "v_flip": True,
            "axis_map": "(x, y, z) -> (x, z, -y)   源 Y = 高度轴",
            "metallic": "ramp(spec): 0.35->0  0.68->0.80  0.78->0.95",
            "roughness": "1 - spec, 收敛到 [0.18, 0.62]",
        },
    }
    with open(os.path.join(outdir, "ship.json"), "w",
              encoding="utf-8", newline="\n") as w:
        json.dump(manifest, w, ensure_ascii=False, indent=1)
    with open(os.path.join(outdir, "_report.json"), "w",
              encoding="utf-8", newline="\n") as w:
        json.dump(rep, w, ensure_ascii=False, indent=1)
    log("[5/5] ship.json / _report.json 已写")
    return rep, manifest


def main():
    ap = argparse.ArgumentParser(
        description="EVE 舰船 3D 资产流水线（gamemodels3d → OBJ + 官方贴图）")
    ap.add_argument("--id", type=int, required=True, help="车辆 typeID，如 597")
    ap.add_argument("-o", "--out", required=True, help="输出目录")
    ap.add_argument("--skin", default="default", help="皮肤名，默认 default")
    ap.add_argument("--node", default=None, help="直接指定节点路径（排障用）")
    ap.add_argument("--no-tex", action="store_true", help="只下模型不下贴图")
    ap.add_argument("--quiet", action="store_true")
    a = ap.parse_args()
    rep, _ = build(a.id, a.out, skin=a.skin, node_override=a.node,
                   want_tex=not a.no_tex, quiet=a.quiet)
    print("DONE %s" % json.dumps(
        {"obj": rep.get("obj"), "verts": rep["geometry"]["verts"],
         "faces": rep["geometry"]["faces"],
         "axes": rep["geometry"]["axes_raw"],
         "tex": len(rep["textures"]), "warn": len(rep["warnings"])},
        ensure_ascii=False))


if __name__ == "__main__":
    main()
