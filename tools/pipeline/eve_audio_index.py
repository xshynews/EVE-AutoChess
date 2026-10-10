# -*- coding: utf-8 -*-
"""解析 EVE resfileindex.txt，建立音频资源的 原始路径 -> 哈希文件 映射。"""
import sys, os, json

IDX = r"D:\EVE\SharedCache\serenity\resfileindex.txt"
RES = r"D:\EVE\SharedCache\ResFiles"
OUT = r"C:\godot\_export"

audio = []
total = 0
with open(IDX, "r", encoding="utf-8", errors="replace") as f:
    for line in f:
        total += 1
        line = line.strip()
        if not line:
            continue
        parts = [p.strip() for p in line.split(",")]
        if len(parts) < 5:
            continue
        orig = parts[0]
        hashpath = parts[1].replace("\\", "/")
        if "/audio/" not in orig:
            continue
        audio.append({
            "orig": orig,
            "hashpath": hashpath,
            "md5": parts[2],
            "size": int(parts[3]) if parts[3].isdigit() else 0,
            "csize": int(parts[4]) if parts[4].isdigit() else 0,
        })

with open(os.path.join(OUT, "_eve_audio_manifest.json"), "w", encoding="utf-8") as f:
    json.dump(audio, f, ensure_ascii=False, indent=0)

# 统计
import collections
ext = collections.Counter()
tree = collections.Counter()
for a in audio:
    e = os.path.splitext(a["orig"])[1].lower()
    ext[e] += 1
    # res:/audio/media/xxx.wem -> audiomedia
    rel = a["orig"].replace("res:/audio/", "")
    tree[rel.split("/")[0]] += 1

lines = []
lines.append("index_total_lines=%d" % total)
lines.append("audio_entries=%d" % len(audio))
lines.append("--- ext ---")
for k, v in ext.most_common():
    lines.append("  %s = %d" % (k, v))
lines.append("--- tree ---")
for k, v in tree.most_common():
    lines.append("  %s = %d" % (k, v))

# 抽查哈希文件是否真的存在
lines.append("--- sample existence check ---")
for a in audio[:5] + audio[-5:]:
    hp = os.path.join(RES, a["hashpath"])
    lines.append("  %s -> %s exists=%s" % (a["orig"], a["hashpath"], os.path.exists(hp)))

with open(os.path.join(OUT, "_eve_manifest_report.txt"), "w", encoding="utf-8") as f:
    f.write("\n".join(lines))
print("OK", len(audio))
