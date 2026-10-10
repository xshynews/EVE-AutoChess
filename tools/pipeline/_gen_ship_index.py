# -*- coding: utf-8 -*-
"""从 `_ship_manifest.json` + 实际建模结果，生成 Godot 侧的资产索引。

产物：`F:\\evezzq\\eve自走棋918\\scripts\\data\\eve_ship_asset_index.gd`

## 为什么要机生成而不是手写

52 行手写的 id→typeID→模型 三列，只要敲错一行、或者以后增删船时漏改一处，
就会变成用户最担心的那种错配（点惩罚者级、上来别的船），而且**引擎不会报错**。
机生成 + 生成后自检，把正确性从「人是否细心」转移到「数据是否一致」。

## 索引里每一列的意义

    id        工程主键。立绘 = assets/ships/<id>.png，模型 = assets/ships3d/<id>.glb
    typeid    EVE 官方 typeID —— "这艘船到底是哪艘"的唯一客观凭据
    name_en   官方英文名。3D 站点返回的 model_name 必须等于它
    cn/cost   人眼核对用
    dims      【排序后】的源尺寸三元组 (横梁, 高度, 长轴)，进引擎后升为 float
              —— 这是**内容级**的防错配手段：把 GLB 载进引擎量包围盒，
              与这里的期望值比对，模型被换掉就当场露馅（见 verify_ship_assets.gd）

dims 取**排序后**的三元组，是为了跟坐标系解耦：源的 (横梁,高度,长轴) 经
Blender 的 Z-up 与 glTF 的 Y-up 两次换轴后，落在引擎里的轴顺序会变，
但**三个数的大小关系不变**。比大小不变的东西，才不会被换轴 bug 骗过去。
"""
import io
import json
import os
import sys

MANIFEST = r"C:\godot\_export\_ship_manifest.json"
RESULT = r"C:\godot\_export\_ship3d\_build_result.json"
ROOT = r"C:\godot\_export\_ship3d"
OUT = r"F:\evezzq\eve自走棋918\scripts\data\eve_ship_asset_index.gd"

HEAD = '''extends RefCounted
class_name EveShipAssetIndex

## EVE 自走棋 —— 舰船资产索引（**机生成，不要手改**）
##
## 生成器：`C:\\\\godot\\\\_export\\\\_gen_ship_index.py`
## 数据链：`01_舰船数值全表.csv` → `eve_ship_table.gd`(id/中文名/势力/费用)
##         + ESI `/universe/ids/`(id → typeID) → `_ship_manifest.json`
##         + `eve_ship_build.py`(typeID → 模型) → 本文件
##
## ── 这张表存在的唯一理由 ────────────────────────────────────────
## 用户的要求：「别最后我点的惩罚者级的立绘，上去的是其他船就糟糕了」。
## 错配的根源永远是**按顺序取资源**（第 N 个文件 / 第 N 行）。本表让
## 「id → typeID → 模型文件 → 立绘文件」逐行绑死，
## 全工程只允许 `by_id(id)` 查询，**禁止任何按位置取用**。
##
## ── dims 是干什么的 ────────────────────────────────────────────
## 前四列都是"名字"，名字错了人看不出。dims 是**尺寸三元组（已排序）**：
## 把 assets/ships3d/<id>.glb 载进引擎量出包围盒，与 dims 比对，
## 数值不对就说明这个 .glb 里装的是**另一艘船** —— 这是唯一能穿透
## "文件名正确但内容错误"的检查。

## 一艘船的资产身份
class ShipAsset:
\tvar id: String
\tvar typeid: int
\tvar name_en: String
\tvar cn: String
\tvar cost: int
\tvar dims: PackedFloat32Array       ## 已排序的 (横梁, 高度, 长轴)
\tvar model: String
\tvar portrait: String

\tfunc _init(p: Dictionary) -> void:
\t\tid = String(p["id"])
\t\ttypeid = int(p["typeid"])
\t\tname_en = String(p["name_en"])
\t\tcn = String(p["cn"])
\t\tcost = int(p["cost"])
\t\tdims = p["dims"]
\t\tmodel = String(p["model"])
\t\tportrait = String(p["portrait"])


## 期望条目数 —— 与数据表的 52 行严格一致，verify 会对账
const EXPECTED_COUNT := %d

## 原始行：id / typeid / name_en / cn / cost / dims(已排序)
const ROWS: Array = [
'''

TAIL = ''']


static var _by_id: Dictionary = {}
static var _by_typeid: Dictionary = {}


static func _ensure() -> void:
\tif not _by_id.is_empty():
\t\treturn
\tfor r in ROWS:
\t\tvar a := ShipAsset.new({
\t\t\t"id": r[0], "typeid": r[1], "name_en": r[2], "cn": r[3], "cost": r[4],
\t\t\t"dims": PackedFloat32Array(r[5]),
\t\t\t"model": "res://assets/ships3d/%s.glb" % r[0],
\t\t\t"portrait": "res://assets/ships/%s.png" % r[0],
\t\t})
\t\t_by_id[a.id] = a
\t\t_by_typeid[a.typeid] = a


## 按 id 取资产身份。查不到时返回 null（调用方必须自己处理，别用默认值兜）。
static func by_id(ship_id: StringName) -> ShipAsset:
\t_ensure()
\treturn _by_id.get(String(ship_id))


## 按 typeID 反查（排障用：拿到一个模型文件，确认它是哪艘船）
static func by_typeid(t: int) -> ShipAsset:
\t_ensure()
\treturn _by_typeid.get(t)


static func all() -> Array:
\t_ensure()
\treturn _by_id.values()


## 索引与数据表是否对得上 —— **双向**比对，返回问题列表。
##
## 单向检查（索引里的每条都能在表里找到）不够：表里多出一艘船、
## 而索引没跟上时，那艘船在引擎里就没有模型可用，且不会报错。
## 所以两个方向都要查，任何一边多出来的都要点名。
static func cross_check_with_table() -> PackedStringArray:
\tvar problems: PackedStringArray = []
\t_ensure()
\tvar from_index := {}
\tfor a in all():
\t\tfrom_index[a.id] = true
\tvar from_table := {}
\tfor row in EveShipTable.ROWS:
\t\tfrom_table[String(row[0])] = true
\tfor id in from_table.keys():
\t\tif not from_index.has(id):
\t\t\tproblems.append("数据表有 %s，索引里没有" % id)
\tfor id in from_index.keys():
\t\tif not from_table.has(id):
\t\t\tproblems.append("索引有 %s，数据表里没有" % id)
\treturn problems


## 资产完整性自检 —— 返回问题列表，空数组表示 52 艘的关联全部成立。
##
## 检查：条数 / id 与英文名可互推 / 立绘存在且文件名 == id /
##       模型存在且文件名 == id / dims 是三个正数。
## 注意这里**不**校验模型内容 —— 那需要真载入 GLB 量包围盒，
## 由 tools/verify_ship_assets.gd 做（静态函数没法安全加载资源）。
static func audit() -> PackedStringArray:
\tvar problems: PackedStringArray = []
\t_ensure()
\tif ROWS.size() != EXPECTED_COUNT:
\t\tproblems.append("索引条数 %d ≠ 期望 %d" % [ROWS.size(), EXPECTED_COUNT])
\tfor a in all():
\t\tif a.id != a.name_en.to_lower():
\t\t\tproblems.append("%s id 与英文名 %s 不一致" % [a.id, a.name_en])
\t\tif a.portrait.get_file().get_basename() != a.id:
\t\t\tproblems.append("%s 立绘文件名 %s 与 id 不符" % [a.id, a.portrait])
\t\tif not FileAccess.file_exists(a.portrait):
\t\t\tproblems.append("%s 缺立绘 %s" % [a.id, a.portrait])
\t\tif a.model.get_file().get_basename() != a.id:
\t\t\tproblems.append("%s 模型文件名 %s 与 id 不符" % [a.id, a.model])
\t\tif not FileAccess.file_exists(a.model):
\t\t\tproblems.append("%s 缺模型 %s" % [a.id, a.model])
\t\tif a.dims.size() != 3:
\t\t\tproblems.append("%s dims 不是三元组" % a.id)
\t\telse:
\t\t\tfor v in a.dims:
\t\t\t\tif v <= 0.0:
\t\t\t\t\tproblems.append("%s dims 含非正数" % a.id)
\t\t\t\t\tbreak
\treturn problems
'''


def main():
    man = json.load(io.open(MANIFEST, encoding="utf-8"))
    ships = man["ships"]

    # 建模结果（可能还没跑完 —— 那就先出索引，verify 会报缺模型）
    built = {}
    res_path = RESULT
    if os.path.exists(res_path):
        for r in json.load(io.open(res_path, encoding="utf-8")):
            built[r["id"]] = r

    # 兜底：汇总文件是跑完才写的，中途想看表就直接读各船的 ship.json。
    # 这份 ship.json 是 eve_ship_build.py 写的，比汇总更早存在。
    def dims_of(sid):
        sj = os.path.join(ROOT, sid, "ship.json")
        if os.path.exists(sj):
            try:
                g = json.load(io.open(sj, encoding="utf-8")).get("geometry", {})
                return g.get("dims_raw") or []
            except Exception:
                return []
        return []

    lines, no_dims = [], []
    for m in sorted(ships, key=lambda x: (x["cost"], x["faction"], x["id"])):
        sid = m["id"]
        b = built.get(sid) or {}
        raw = b.get("dims") or dims_of(sid) or []
        if len(raw) == 3:
            d = sorted(round(float(x), 3) for x in raw)
            ds = "[%.2f, %.2f, %.2f]" % (d[0], d[1], d[2])
        else:
            ds = "[0.0, 0.0, 0.0]"
            no_dims.append(sid)
        # 注释只依据**实际存在的证据**：`_build_result.json` 是整批跑完才写的，
        # 拿它判"未建模"会在中途生成时给已建好的船贴上错误标签 —— 误导性注释
        # 比没有注释更糟（下一个读代码的人会信它）。
        note = ""
        if b.get("status") == "mismatch":
            note = "  # !! 建模时模型名对不上"
        elif not os.path.exists(os.path.join(ROOT, sid, "ship.json")):
            note = "  # 未建模"
        lines.append('\t["%s", %d, "%s", "%s", %d, %s],%s'
                     % (sid, m["typeid"], m["name_en"], m["cn"], m["cost"], ds, note))

    txt = HEAD % len(ships) + "\n".join(lines) + "\n" + TAIL
    with io.open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write(txt)
    print("OK 生成 %s（%d 行）" % (OUT, len(lines)))
    if no_dims:
        print("!! 以下 %d 艘还没有尺寸（未建模完成）：%s"
              % (len(no_dims), ", ".join(no_dims)))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
