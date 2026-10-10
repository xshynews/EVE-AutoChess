# -*- coding: utf-8 -*-
"""批量建模 52 艘舰船 —— 逐个 id 顺序建，产物落 `_ship3d\\<id>\\`。

## 防错配的两条硬约束（不要改）

1. **输出目录名 = 清单里的 id**，绝不用模型名、绝不用序号。
   `eve_ship_build.py` 自己会按模型名命名里面的 .obj/.mtl（那是它的规矩），
   但**外层目录**由本脚本控制 —— 下游一律按 `<id>/ship.json` 找资产。
2. **每个 id 单独一次子进程调用**，参数 `--id <该 id 的 typeID>` 从清单里取。
   绝不把 52 个 typeID 拼成一个列表传下去 —— 那样一旦站点少一条记录，
   后面的船会整体前移一位，正好就是用户担心的「点惩罚者级上来别的船」。

## 断点续跑

`_ship3d/<id>/ship.json` 已存在且 typeID 一致 → 跳过。
所以中断后重跑不会重复下载（惩罚者级这份已定标的基线也不会被覆盖）。

## 验收

每艘建完立刻回读 `<id>/ship.json`，把 `model_name` / `typeid` / 面数
写进结果表，并断言 `model_name.lower() == id`、`typeid == 清单里的 typeID`。
对不上就记成 FAIL —— 这是"模型与 id 绑错"的唯一防线。
"""
import io
import json
import os
import subprocess
import sys
import time

PY = r"C:\Users\Administrator\.workbuddy\binaries\python\envs\default\Scripts\python.exe"
BUILD = r"C:\Users\Administrator\.workbuddy\skills\eve-ship-3d-pipeline\scripts\eve_ship_build.py"
MANIFEST = r"C:\godot\_export\_ship_manifest.json"
ROOT = r"C:\godot\_export\_ship3d"
LOG = r"C:\godot\_export\_ship3d\_build_log.txt"


def main():
    man = json.load(io.open(MANIFEST, encoding="utf-8"))["ships"]
    only = sys.argv[1:] or None          # 可选：只跑指定 id
    os.makedirs(ROOT, exist_ok=True)

    log = []

    def say(s):
        log.append(s)
        print(s, flush=True)

    say("=== 批量建模开始 %s ===" % time.strftime("%Y-%m-%d %H:%M:%S"))
    say("清单 %d 艘" % len(man))

    results = []
    for i, m in enumerate(man):
        sid, tid = m["id"], m["typeid"]
        if only and sid not in only:
            continue
        d = os.path.join(ROOT, sid)
        sj = os.path.join(d, "ship.json")

        # ---- 断点续跑
        if os.path.exists(sj):
            try:
                old = json.load(io.open(sj, encoding="utf-8"))
                if old.get("typeid") == tid:
                    say("[%2d/%d] %-14s 已存在，跳过（%d verts）"
                        % (i + 1, len(man), sid, old.get("geometry", {}).get("verts", 0)))
                    results.append({"id": sid, "typeid": tid, "status": "skip",
                                    "model_name": old.get("model_name", "")})
                    continue
            except Exception:
                pass    # ship.json 坏了就当没建过，重跑

        t0 = time.time()
        cmd = [PY, BUILD, "--id", str(tid), "-o", d, "--quiet"]
        try:
            p = subprocess.run(cmd, capture_output=True, text=True,
                               encoding="utf-8", errors="replace", timeout=420)
            rc = p.returncode
            tail = (p.stdout or "")[-400:] + (p.stderr or "")[-400:]
        except subprocess.TimeoutExpired:
            rc, tail = -9, "TIMEOUT 420s"
        dt = time.time() - t0

        if rc != 0 or not os.path.exists(sj):
            say("[%2d/%d] %-14s FAIL rc=%s (%.0fs)" % (i + 1, len(man), sid, rc, dt))
            say("        %s" % tail.replace("\n", " | ")[-300:])
            results.append({"id": sid, "typeid": tid, "status": "fail",
                            "err": tail[-400:]})
            continue

        # ---- 回读 + 两重断言
        d2 = json.load(io.open(sj, encoding="utf-8"))
        mn = d2.get("model_name", "")
        g = d2.get("geometry", {})
        ok_name = mn.lower() == sid
        ok_tid = d2.get("typeid") == tid
        status = "ok" if (ok_name and ok_tid) else "mismatch"
        say("[%2d/%d] %-14s %-4s %-14s %5d verts %5d faces  %.0fs"
            % (i + 1, len(man), sid, status.upper(), mn,
               g.get("verts", 0), g.get("faces", 0), dt))
        if not ok_name:
            say("        !! 模型名 %r 与 id %r 不符 —— 极可能是站点数据串了" % (mn, sid))
        if not ok_tid:
            say("        !! typeID 回读 %s ≠ 清单 %s" % (d2.get("typeid"), tid))
        results.append({
            "id": sid, "typeid": tid, "status": status, "model_name": mn,
            "verts": g.get("verts", 0), "faces": g.get("faces", 0),
            "dims": g.get("dims_raw", []), "sec": round(dt, 1),
            "obj": d2.get("obj", ""),
        })

    # ---- 汇总
    cnt = {}
    for r in results:
        cnt[r["status"]] = cnt.get(r["status"], 0) + 1
    say("")
    say("=== 汇总 %s ===" % "  ".join("%s=%d" % kv for kv in sorted(cnt.items())))
    bad = [r for r in results if r["status"] in ("fail", "mismatch")]
    if bad:
        say("!! 有问题的船：")
        for r in bad:
            say("   %s [%s] %s" % (r["id"], r["status"], r.get("err", "")[:120]))

    json.dump(results, io.open(r"C:\godot\_export\_ship3d\_build_result.json", "w",
                               encoding="utf-8"), ensure_ascii=False, indent=1)
    io.open(LOG, "w", encoding="utf-8").write("\n".join(log))
    return 0 if not bad else 1


if __name__ == "__main__":
    sys.exit(main())
