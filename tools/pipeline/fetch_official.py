# -*- coding: utf-8 -*-
"""从 EVE 官方图片 CDN 拉取全 50 艘舰船的 1024 渲染图。
流程：ESI /universe/ids/ 批量解析 typeid -> images.evetech.net 下载。
"""
import json, os, time, urllib.request, urllib.error

SRC = r"C:\godot\_export\_52ships.txt"
OUT = r"C:\godot\_export\_official_all"
UA = "EVEChess-art-probe (non-commercial fan project)"
HDR = {"User-Agent": UA}

os.makedirs(OUT, exist_ok=True)

names, keys = [], {}
for line in open(SRC, encoding="utf-8").read().splitlines()[1:]:
    line = line.strip()
    if not line:
        continue
    parts = line.split()
    if len(parts) >= 2:
        en = parts[0].capitalize()
        names.append(en)
        keys[en.lower()] = parts[1]

log = []
log.append("待查 %d 艘" % len(names))

# ---- 1) 批量解析 typeid
idmap = {}
for i in range(0, len(names), 25):
    batch = names[i:i + 25]
    try:
        data = json.dumps(batch).encode()
        req = urllib.request.Request(
            "https://esi.evetech.net/latest/universe/ids/?datasource=tranquility",
            data=data, headers={**HDR, "Content-Type": "application/json"}, method="POST")
        with urllib.request.urlopen(req, timeout=45) as r:
            res = json.loads(r.read().decode())
        for t in res.get("inventory_types", []):
            idmap[t["name"].lower()] = t["id"]
        log.append("批次 %d-%d 解析出 %d 个 id" % (i, i + len(batch), len(res.get("inventory_types", []))))
    except Exception as e:
        log.append("批次 %d 失败: %s" % (i, e))
    time.sleep(0.6)

log.append("共解析 %d 个 typeid" % len(idmap))

# ---- 2) 下载
ok, fail = [], []
for en in names:
    tid = idmap.get(en.lower())
    if not tid:
        fail.append("%s(无typeid)" % en)
        continue
    dst = os.path.join(OUT, "%s.png" % en.lower())
    if os.path.exists(dst) and os.path.getsize(dst) > 5000:
        ok.append(en)
        continue
    try:
        req = urllib.request.Request(
            "https://images.evetech.net/types/%d/render?size=1024" % tid, headers=HDR)
        with urllib.request.urlopen(req, timeout=45) as r:
            b = r.read()
        open(dst, "wb").write(b)
        ok.append(en)
        log.append("  OK %-14s id=%-7d %7dB" % (en, tid, len(b)))
    except Exception as e:
        fail.append("%s(%s)" % (en, e))
        log.append("  FAIL %-14s %s" % (en, e))
    time.sleep(0.25)

log.append("成功 %d / 失败 %d" % (len(ok), len(fail)))
if fail:
    log.append("失败清单: " + ", ".join(fail))

json.dump({"typeid": {k: v for k, v in idmap.items()}, "key": keys},
          open(r"C:\godot\_export\_official_all\_typeids.json", "w", encoding="utf-8"),
          ensure_ascii=False, indent=1)
open(r"C:\godot\_export\_fetch_official.txt", "w", encoding="utf-8").write("\n".join(log))
print("OK %d/%d" % (len(ok), len(names)))
