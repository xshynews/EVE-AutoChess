# -*- coding: utf-8 -*-
r"""
=======================================================================
 由 eve_ship_build.py 的产物直接生成一个「打开就能用」的 Blender 工程
=======================================================================

用法::

    blender --background --python blender_project.py -- <项目目录> [<输出目录>]

输入：<项目目录> 里要有 eve_ship_build.py 产出的 `ship.json` + `<Name>.obj` + `textures/`。

产出：
    <项目目录>/<Name>.blend        自包含（贴图已 pack，换机可开）
    <输出目录>/_proj_hero|side|top|rear.png
    <输出目录>/_tt_frames/f_0001..N.png      （转台序列，交给外部 ffmpeg 编码）

-------------------------------------------------------------------------
 为什么是这套材质（照抄，别改，这是对着 CCP 官方渲染定标出来的）
-------------------------------------------------------------------------
  * `_d` 漫反射  → Base Color（官方白甲 + 金饰已经画在图里，别再叠派系色）
  * `_n` 法线    → Normal Map，Strength 1.25
        1024² 的图承载了卷草纹 / 板缝 / 喷口全部细节，低模的立体感全靠它
  * `_s` 高光图  → **它是材质分区图，不是渐进高光**（这条最容易搞错）
        实测三档离散值：≈0.35 白装甲板 → 哑光、metallic 0
                       ≈0.68 深色结构 → metallic 0.80
                       ≈0.78 金色饰件 → metallic 0.95
        配方：roughness = 1 − spec（收敛到 [0.18, 0.62]），metallic = ramp(spec)
        ⚠️ 全局拉金属度是错的 —— 那会把白甲板渲成银灰。
  * 官方那种「暗古铜底 + 金色雕花被光擦亮」的观感 =
        **暗环境（bg≈0.014）+ 金属反射**，不是纹理里画的黑。
        拿亮环境平光渲会渲成平涂金，这是本管线里最容易白干一天的坑。

-------------------------------------------------------------------------
 ⚠️ Blender 5.2.2 实测的三个坑（都写在注释里了，别重踩）
-------------------------------------------------------------------------
 1. `render.image_settings.file_format` 实例枚举里**没有 FFMPEG**
    （RNA 里列了，赋值直接报 enum not found）→ 这个构建编不出视频。
    所以这里只渲 PNG 序列，编码交给外部 ffmpeg（见 SKILL.md 的命令）。
 2. `scene.collection.objects.unlink(o)` 对 OBJ 导入的物体会报「不在集合里」
    → 用 move_to() 遍历所有集合再挂。
 3. 转台的关键帧插值要兼容新版 slotted action：
    `action.fcurves` 之外还要兜 `action.layers[*].strips[*].channelbags[*].fcurves`。
"""
import bpy
import json
import math
import mathutils
import os
import sys

argv = sys.argv
argv = argv[argv.index("--") + 1:] if "--" in argv else []
PROJ = argv[0] if argv else os.getcwd()
OUT = argv[1] if len(argv) > 1 else PROJ

# ── 出图参数（对着官方立绘定的，改之前先看 SKILL.md 的说明）────────────────
BG = (0.014, 0.016, 0.020)      # 暗环境；亮环境 = 平涂金
EXPOSURE = -0.25
R_WHITE = 0.62                  # 白甲板的粗糙度（上限）
R_GOLD = 0.18                   # 金饰的粗糙度（下限）
LENS = 52.0
TURNTABLE_FRAMES = 120          # .blend 里那套转台动画的长度 —— 恒定，不受下方参数影响
RES = (1400, 900)

# ── 可选参数（批量建模用；单艘手工跑不传，行为与以前完全一致）────────────
#   argv[2] = 转台【渲染】帧数，默认 = 120；传 0 = 只出静帧、不出转台。
#             批量 52 艘时 52 × 120 = 6240 帧纯属浪费，但 .blend 里的转台
#             动画仍然照旧建好（用户自己按空格就能渲染）。
#   argv[3] = "glb" → 额外导出 <Name>.glb（只含舰船网格、贴图内嵌），
#             这是给引擎加载用的格式；.blend 依旧照常产出。
#             用法：blender --background --python blender_project.py -- <proj> <out> 0 glb
_tt_arg = argv[2] if len(argv) > 2 else ""
try:
    TT_RENDER = int(_tt_arg) if _tt_arg != "" else TURNTABLE_FRAMES
except ValueError:
    TT_RENDER = TURNTABLE_FRAMES
EXPORT_GLB = len(argv) > 3 and argv[3].lower() == "glb"

# ── 读清单 ────────────────────────────────────────────────────────────────
man_path = os.path.join(PROJ, "ship.json")
if not os.path.exists(man_path):
    raise RuntimeError("找不到 %s —— 先跑 eve_ship_build.py" % man_path)
with open(man_path, "r", encoding="utf-8") as f:
    MAN = json.load(f)

NAME = MAN["model_name"]
OBJ = os.path.join(PROJ, MAN["obj"])
TEX = {k: (os.path.join(PROJ, v) if v else None)
       for k, v in (MAN.get("textures") or {}).items()}
BLEND = os.path.join(PROJ, "%s.blend" % NAME)
report = {"model": NAME, "typeid": MAN["typeid"], "obj": MAN["obj"],
          "blend": BLEND, "stills": {}, "frames": 0, "warnings": []}


# ── 场景工具（自包含，不依赖外部库）───────────────────────────────────────
def clear_scene():
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    for m in list(bpy.data.materials):
        try:
            bpy.data.materials.remove(m)
        except Exception:                                   # noqa: BLE001
            pass


def import_obj(path):
    for o in list(bpy.data.objects):
        if o.type == "MESH":
            bpy.data.objects.remove(o, do_unlink=True)
    before = set(bpy.data.objects)
    bpy.ops.wm.obj_import(filepath=path)
    return [o for o in bpy.data.objects if o not in before and o.type == "MESH"]


def collect_points(objs):
    pts = []
    for o in objs:
        mw = o.matrix_world
        for v in o.data.vertices:
            pts.append(mw @ v.co)
    return pts


def bbox_of(objs):
    mn = mathutils.Vector((1e18,) * 3)
    mx = mathutils.Vector((-1e18,) * 3)
    for o in objs:
        for c in o.bound_box:
            wc = o.matrix_world @ mathutils.Vector(c)
            mn = mathutils.Vector((min(mn.x, wc.x), min(mn.y, wc.y), min(mn.z, wc.z)))
            mx = mathutils.Vector((max(mx.x, wc.x), max(mx.y, wc.y), max(mx.z, wc.z)))
    return mn, mx


def orient_ship(objs):
    """统一朝向：长轴对齐 +X、**船头（窄端）指向 +X**、**背脊朝 +Z**。

    轴向语义是【已知量】，不该按尺寸猜（上游 eve_ship_build.py 是确定性的）：
        源    x = 横梁   y = 高度   z = 长轴
        OBJ   写出 (x, z, -y)  —— 见 eve_ship_build.py 铁律②
        Blender 的 OBJ 导入器（forward=-Z / up=Y）再把它变成
              Blender X = 横梁 · Blender Y = 高度 · Blender Z = 长轴

    ⚠️ 历史坑（实测踩到的，别再犯）：
       旧版按「哪根轴最长」分支，长轴落在 Z 时走 `Rotation(pi/2, "Y")`。
       它确实把长轴搬到了 X，却把**高度留在了 Y**（Blender 里 Y 是水平轴）
       —— 成品是一艘**侧滚 90° 的船**：静帧里 el=90 的「俯视图」拍出来是
       侧视图，`el=0` 的「侧视图」拍出来是舰首正对。
       判据很隐蔽：报告里的 dims 看着完全正确（x=长轴），只有看图才发现。
       正确做法是让「长轴→+X」与「背脊→+Z」同时成立，即
       e_x→e_y · e_y→e_z · e_z→e_x，也就是**绕 (1,1,1) 转 120°**。

    头尾判据：沿长轴分 14 段量横截面展宽 —— 船首尖、船尾宽（引擎舱）。
    （该判据对「绕长轴滚 90°」不敏感：每段取的是两横向轴展宽的 max，
      交换两横向轴不改变结果，所以它一直是对的，错的只是滚转。）
    """
    pts = collect_points(objs)
    if len(pts) < 8:
        return False, "顶点太少"
    mn = mathutils.Vector((min(p[i] for p in pts) for i in range(3)))
    mx = mathutils.Vector((max(p[i] for p in pts) for i in range(3)))
    dim = mx - mn
    axis_names = "XYZ"
    a = max(range(3), key=lambda i: dim[i])
    segs = 14
    vert = [i for i in range(3) if i != a]
    ws = []
    for i in range(segs):
        lo = mn[a] + dim[a] * i / segs
        hi = mn[a] + dim[a] * (i + 1) / segs
        sel = [p for p in pts if lo <= p[a] <= hi]
        if len(sel) < 4:
            ws.append(None)
            continue
        ws.append(max(max(p[b] for p in sel) - min(p[b] for p in sel) for b in vert))
    valid = [w for w in ws if w is not None]
    if len(valid) < 6:
        head_at_pos, note = True, "段数不足，默认头在正向"
    else:
        k = max(1, len(ws) // 3)
        left = [w for w in ws[:k] if w is not None]
        right = [w for w in ws[-k:] if w is not None]
        lw = sum(left) / max(1, len(left))
        rw = sum(right) / max(1, len(right))
        head_at_pos = rw <= lw
        note = "左端宽%.4g 右端宽%.4g -> 头在%s" % (lw, rw, "+" if head_at_pos else "-")
    if a == 2:
        # 常态：长轴在 Z、背脊在 Y → 绕 (1,1,1) 转 120°，
        # (x,y,z) -> (z,x,y)，长轴落到 +X、背脊落到 +Z。
        R = mathutils.Matrix.Rotation(math.radians(120.0), 4,
                                      mathutils.Vector((1.0, 1.0, 1.0)))
    elif a == 1:
        # 旧假设（源里 Z 朝上、长轴在 Y）。当前上游不会走到这里，
        # 保留是为了上游换规则时不至于直接崩。
        R = mathutils.Matrix.Rotation(-math.pi / 2, 4, "Z")
    else:
        R = mathutils.Matrix.Identity(4)
    if a != 2:
        note += "｜⚠️ 长轴落在 %s（预期 Z）——上游写出规则可能变了，请复查" % axis_names[a]
    if not head_at_pos:
        R = mathutils.Matrix.Rotation(math.pi, 4, "Z") @ R
    for o in objs:
        o.matrix_world = R @ o.matrix_world
    bpy.context.view_layer.update()
    return True, "长轴=%s %s" % (axis_names[a], note)


def apply_material(objs, mat):
    for o in objs:
        o.data.materials.clear()
        o.data.materials.append(mat)
        try:
            o.data.shade_smooth()
        except Exception:                                   # noqa: BLE001
            pass


def setup_world_and_lights(bg_color):
    w = bpy.data.worlds.new("W")
    bpy.context.scene.world = w
    w.use_nodes = True
    nt = w.node_tree
    nt.nodes.clear()
    o = nt.nodes.new("ShaderNodeOutputWorld")
    bg = nt.nodes.new("ShaderNodeBackground")
    bg.inputs["Color"].default_value = (bg_color[0], bg_color[1], bg_color[2], 1.0)
    nt.links.new(bg.outputs["Background"], o.inputs["Surface"])

    def sun(name, energy, rot, color):
        ld = bpy.data.lights.new(name, "SUN")
        ld.energy = energy
        ld.angle = math.radians(3.0)
        ld.color = color
        ob = bpy.data.objects.new(name, ld)
        ob.rotation_euler = tuple(math.radians(v) for v in rot)
        bpy.context.scene.collection.objects.link(ob)

    # 主光硬、补光弱、轮廓光擦边 —— 这组是调出来的，别随手改
    sun("KEY", 6.2, (48, 0, 56), (1.0, 0.95, 0.87))
    sun("FILL", 1.15, (74, 0, -104), (0.58, 0.73, 1.0))
    sun("RIM", 5.6, (104, 0, -146), (0.84, 0.91, 1.0))
    sun("BOUNCE", 0.55, (-46, 0, 196), (0.70, 0.72, 0.82))
    sun("SIDE", 2.4, (62, 0, 168), (0.80, 0.86, 0.96))


def make_camera(lens):
    cd = bpy.data.cameras.new("cam")
    cd.lens = lens
    cd.clip_start = 0.05
    cd.clip_end = 1e7
    cam = bpy.data.objects.new("cam", cd)
    bpy.context.scene.collection.objects.link(cam)
    bpy.context.scene.camera = cam
    return cam


def look_at(ob, t):
    ob.rotation_euler = (t - ob.location).to_track_quat("-Z", "Y").to_euler()


def fit_camera(cam, mn, mx, dirvec, margin=1.16, iters=7):
    import bpy_extras.object_utils as ou
    sc = bpy.context.scene
    ctr = (mn + mx) * 0.5
    v = mathutils.Vector(dirvec).normalized()
    corners = [mathutils.Vector((x, y, z)) for x in (mn.x, mx.x)
               for y in (mn.y, mx.y) for z in (mn.z, mx.z)]
    dist = max(mx - mn) * 2.2
    for _ in range(iters):
        cam.location = ctr + v * dist
        look_at(cam, ctr)
        bpy.context.view_layer.update()
        xs, ys = [], []
        for c in corners:
            co = ou.world_to_camera_view(sc, cam, c)
            xs.append(co.x)
            ys.append(co.y)
        ratio = max(max(xs) - min(xs), max(ys) - min(ys))
        if ratio < 1e-6:
            break
        dist *= ratio * margin
    cam.location = ctr + v * dist
    look_at(cam, ctr)
    bpy.context.view_layer.update()
    return ctr


def setup_render(w, h, exposure, samples):
    for e in ("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE", "CYCLES"):
        try:
            bpy.context.scene.render.engine = e
            break
        except Exception:                                   # noqa: BLE001
            continue
    sc = bpy.context.scene
    sc.render.resolution_x = w
    sc.render.resolution_y = h
    sc.render.resolution_percentage = 100
    sc.render.image_settings.file_format = "PNG"
    try:
        sc.view_settings.view_transform = "Standard"   # 禁 AgX
        sc.view_settings.look = "None"
        sc.view_settings.exposure = exposure
    except Exception as e:                                  # noqa: BLE001
        report["warnings"].append("view_settings: %s" % e)
    try:
        sc.eevee.taa_render_samples = samples
    except Exception:                                       # noqa: BLE001
        pass
    return bpy.context.scene.render.engine


def elev_dir(az_deg, el_deg):
    a, e = math.radians(az_deg), math.radians(el_deg)
    return (math.cos(a) * math.cos(e), math.sin(a) * math.cos(e), math.sin(e))


def move_to(objs, coll):
    """把物体从当前所在集合摘出再挂进目标集合。

    ⚠️ 不能写 sc.collection.objects.unlink(o) —— 对 OBJ 导入的物体会报
       「不在集合 'Scene Collection' 里」（Blender 5.2 实测）。
    """
    sc = bpy.context.scene
    for o in objs:
        for c in list(bpy.data.collections) + [sc.collection]:
            try:
                if o.name in c.objects:
                    c.objects.unlink(o)
            except Exception:                               # noqa: BLE001
                pass
        coll.objects.link(o)


# ── 建模 ──────────────────────────────────────────────────────────────────
clear_scene()
sc = bpy.context.scene
sc.unit_settings.system = "METRIC"
sc.unit_settings.length_unit = "METERS"
sc.unit_settings.scale_length = 1.0

objs = import_obj(OBJ)
ok, note = orient_ship(objs)
report["orient"] = {"ok": ok, "note": note}

mn0, mx0 = bbox_of(objs)
ctr0 = (mn0 + mx0) * 0.5
for o in objs:
    o.location = o.location - ctr0
bpy.context.view_layer.update()
mn, mx = bbox_of(objs)
dim = mx - mn
report["dims_m"] = {"x": round(dim.x, 3), "y": round(dim.y, 3), "z": round(dim.z, 3)}
# ⚠️ orient_ship 会把长轴转到 X，所以这里的 x/y/z **不是**源语义的
#    长/梁/高。要源语义就看 ship.json 的 geometry.axes_raw（那份没被转过）。
report["dims_source"] = MAN.get("geometry", {}).get("axes_raw")
report["verts"] = sum(len(o.data.vertices) for o in objs)
report["faces"] = sum(len(o.data.polygons) for o in objs)

for i, o in enumerate(objs):
    o.name = NAME if i == 0 else "%s_%d" % (NAME, i)
    o.data.name = o.name + "_mesh"

# ── 材质 ──────────────────────────────────────────────────────────────────
mat_name = "M_%s" % NAME
m = bpy.data.materials.new(mat_name)
m.use_nodes = True
nt = m.node_tree
nt.nodes.clear()
out = nt.nodes.new("ShaderNodeOutputMaterial"); out.location = (1240, 0)
bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled"); bsdf.location = (900, 0)
nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])


def texnode(path, non_color=False, loc=(0, 0)):
    n = nt.nodes.new("ShaderNodeTexImage")
    if path and os.path.exists(path):
        im = bpy.data.images.load(path, check_existing=True)
        if non_color:
            im.colorspace_settings.name = "Non-Color"
        n.image = im
    else:
        report["warnings"].append("缺贴图 %s" % path)
    n.location = loc
    return n


td = texnode(TEX.get("d"), False, (-1000, 460))
nt.links.new(td.outputs["Color"], bsdf.inputs["Base Color"])

if TEX.get("n"):
    tn = texnode(TEX["n"], True, (-1000, 140))
    nmn = nt.nodes.new("ShaderNodeNormalMap"); nmn.location = (-620, 140)
    nmn.inputs["Strength"].default_value = 1.25
    nt.links.new(tn.outputs["Color"], nmn.inputs["Color"])
    nt.links.new(nmn.outputs["Normal"], bsdf.inputs["Normal"])

if TEX.get("s"):
    ts = texnode(TEX["s"], True, (-1000, -240))
    inv = nt.nodes.new("ShaderNodeInvert"); inv.location = (-620, -240)
    mrn = nt.nodes.new("ShaderNodeMapRange"); mrn.location = (-340, -240)
    mrn.inputs["To Min"].default_value = R_WHITE
    mrn.inputs["To Max"].default_value = R_GOLD
    mrn.clamp = True
    nt.links.new(ts.outputs["Color"], inv.inputs["Color"])
    nt.links.new(inv.outputs["Color"], mrn.inputs["Value"])
    nt.links.new(mrn.outputs["Result"], bsdf.inputs["Roughness"])

    cr = nt.nodes.new("ShaderNodeValToRGB"); cr.location = (-340, -600)
    cr.color_ramp.interpolation = "LINEAR"
    els = cr.color_ramp.elements
    while len(els) > 1:
        els.remove(els[-1])
    els[0].position = 0.28
    els[0].color = (0.0, 0.0, 0.0, 1.0)
    for pos, v in ((0.42, 0.03), (0.58, 0.45), (0.68, 0.80), (0.78, 0.95), (1.00, 0.97)):
        e = els.new(pos)
        e.color = (v, v, v, 1.0)
    nt.links.new(ts.outputs["Color"], cr.inputs["Fac"])
    nt.links.new(cr.outputs["Color"], bsdf.inputs["Metallic"])

apply_material(objs, m)

setup_world_and_lights(BG)
cam = make_camera(LENS)

# ── 集合整理 ──────────────────────────────────────────────────────────────
ship_col = bpy.data.collections.new("Ship")
light_col = bpy.data.collections.new("Lighting")
cam_col = bpy.data.collections.new("Camera")
for c in (ship_col, light_col, cam_col):
    sc.collection.children.link(c)
move_to(objs, ship_col)
move_to([o for o in bpy.data.objects if o.type == "LIGHT"], light_col)
move_to([cam], cam_col)

# ── 转台 ──────────────────────────────────────────────────────────────────
turn = bpy.data.objects.new("TURNTABLE", None)
turn.empty_display_size = max(dim) * 0.3
ship_col.objects.link(turn)
for o in objs:
    if o.parent is None:
        keep = o.matrix_world.copy()
        o.parent = turn
        o.matrix_world = keep

turn.rotation_euler = (0.0, 0.0, 0.0)
turn.keyframe_insert("rotation_euler", index=2, frame=1)
turn.rotation_euler = (0.0, 0.0, math.radians(360.0))
turn.keyframe_insert("rotation_euler", index=2, frame=TURNTABLE_FRAMES)
fcs = []
try:
    fcs = list(turn.animation_data.action.fcurves)
except Exception:                                           # noqa: BLE001
    pass
for layer in getattr(turn.animation_data.action, "layers", []):
    for strip in layer.strips:
        for cb in getattr(strip, "channelbags", []):
            fcs += list(cb.fcurves)
for fc in fcs:
    for kp in fc.keyframe_points:
        kp.interpolation = "LINEAR"
sc.frame_start = 1
sc.frame_end = TURNTABLE_FRAMES
sc.render.fps = 30

eng = setup_render(RES[0], RES[1], EXPOSURE, 96)
report["engine"] = eng

# ── 存工程（贴图 pack 进去，单文件自包含）─────────────────────────────────
info = bpy.data.texts.new("MODEL_INFO")
info.write(
    "%s / typeID %s\n"
    "来源: %s\n节点: %s\n"
    "网格: %d verts / %d faces\n"
    "尺寸(源语义): 长 %.2f m  梁 %.2f m  高 %.2f m\n"
    "贴图: d=%s n=%s s=%s e=%s\n"
    "材质规则: metallic = ramp(spec) 0.35->0  0.68->0.80  0.78->0.95\n"
    "          roughness = 1 - spec, 收敛到 [%.2f, %.2f]\n"
    "坐标修正: 源 Y = 高度轴 -> 已转 (x, z, -y); UV 已 V 翻转\n"
    "转台: TURNTABLE 空物体, 第 1~%d 帧绕 Z 360 度, 按空格播放\n"
    "⚠️ 本场景里长轴已转到 X，故局部 x/y/z 不等于源的长/梁/高\n"
    % (NAME, MAN["typeid"], MAN.get("page", "-"), MAN.get("node", "-"),
       report["verts"], report["faces"],
       (MAN.get("geometry", {}).get("axes_raw") or {}).get("z_length", 0.0),
       (MAN.get("geometry", {}).get("axes_raw") or {}).get("x_beam", 0.0),
       (MAN.get("geometry", {}).get("axes_raw") or {}).get("y_height", 0.0),
       os.path.basename(TEX["d"]) if TEX.get("d") else "-",
       os.path.basename(TEX["n"]) if TEX.get("n") else "-",
       os.path.basename(TEX["s"]) if TEX.get("s") else "-",
       os.path.basename(TEX["e"]) if TEX.get("e") else "-",
       R_GOLD, R_WHITE, TURNTABLE_FRAMES))

bpy.ops.wm.save_as_mainfile(filepath=BLEND)
report["blend_bytes"] = os.path.getsize(BLEND)
try:
    bpy.ops.file.pack_all()
    bpy.ops.wm.save_as_mainfile(filepath=BLEND)
    report["packed"] = True
    report["blend_bytes_packed"] = os.path.getsize(BLEND)
except Exception as e:                                      # noqa: BLE001
    report["packed"] = False
    report["pack_err"] = str(e)

# ── 静帧 ──────────────────────────────────────────────────────────────────
sc.frame_set(1)
for name, dv, mg in (("hero", elev_dir(35, 20), 1.15),
                     ("side", elev_dir(0, 8), 1.15),
                     ("top", elev_dir(90, 66), 1.10),
                     ("rear", elev_dir(200, 22), 1.15)):
    fit_camera(cam, mn, mx, dv, margin=mg)
    p = os.path.join(OUT, "_proj_%s.png" % name)
    sc.render.filepath = p
    bpy.ops.render.render(write_still=True)
    report["stills"][name] = os.path.basename(p)

# ── 转台序列（本构建无 FFMPEG，交给外部编码）──────────────────────────────
# TT_RENDER == 0 时整段跳过（批量建模用）—— 静帧已经够做验收与总览，
# 120 帧/艘 × 52 艘 = 6240 帧的渲染时间花在这里不值得。
if TT_RENDER > 0:
    sc.render.resolution_x = 1280
    sc.render.resolution_y = 720
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGB"
    try:
        sc.eevee.taa_render_samples = 32
    except Exception:                                       # noqa: BLE001
        pass
    if TT_RENDER < TURNTABLE_FRAMES:
        sc.frame_end = TT_RENDER        # 只渲染前 N 帧（动画本身仍保留全长）
    frames_dir = os.path.join(OUT, "_tt_frames")
    os.makedirs(frames_dir, exist_ok=True)
    for f in os.listdir(frames_dir):
        if f.endswith(".png"):
            os.remove(os.path.join(frames_dir, f))
    fit_camera(cam, mn, mx, elev_dir(30, 22), margin=1.28)
    sc.render.filepath = os.path.join(frames_dir, "f_")
    bpy.ops.render.render(animation=True)
    report["frames"] = len([f for f in os.listdir(frames_dir) if f.endswith(".png")])

# ── 可选：导出引擎用 GLB（只带舰船网格 + 内嵌贴图）────────────────────────
#
# ⚠️ 材质在 glTF 里会退化：Blender 侧的金属度/粗糙度是由 `_s` 材质分区图
#    经 ColorRamp 驱动的节点图，glTF **表达不了中间节点**，导出器只会把
#    能直连的贴图（基础色 / 法线 / 自发光）带过去，金属度与粗糙度退成常量。
#    → 所以 GLB 是"能看、能跑"的引擎资产，不是渲染级还原。
#      要做 1:1 的分区金属感，在引擎里用自定义着色器采样同目录的 `_s` 图
#      按 SKILL 里的 ramp(0.35→0 / 0.68→0.80 / 0.78→0.95) 复现即可。
if EXPORT_GLB:
    glb = os.path.join(OUT, "%s.glb" % NAME)
    try:
        bpy.ops.object.select_all(action="DESELECT")
        for o in objs:
            o.select_set(True)
        bpy.context.view_layer.objects.active = objs[0]
        bpy.ops.export_scene.gltf(
            filepath=glb, export_format="GLB", use_selection=True,
            export_apply=True, export_yup=True,
            export_image_format="AUTO", export_materials="EXPORT")
        report["glb"] = os.path.basename(glb)
        report["glb_bytes"] = os.path.getsize(glb)
    except Exception as e:                                  # noqa: BLE001
        report["glb_err"] = str(e)

with open(os.path.join(OUT, "_proj_report.json"), "w",
          encoding="utf-8", newline="\n") as w:
    json.dump(report, w, ensure_ascii=False, indent=1)
print("PROJ_DONE " + json.dumps(report, ensure_ascii=False))
