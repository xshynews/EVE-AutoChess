# ⏸⏸ 冻结（2026-10-11 用户定调：英文版现在时机不成熟，先不做）。
# ⛔ 解冻前不要跑这个脚本 —— 它往 i18n/strings.csv 追加 key，属于「继续做英文版」。
#    解冻顺序：先补英文文案本身 → 再迁剩余 UI 面 → 最后开放设置窗「语言」行。
#    详见 i18n/README.md 顶部。
#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""生成 `i18n/strings.csv` 的**术语段**（舰船 / 吨位 / 势力 / 武器 / 防御 / 定位）。

════════════════════════════════════════════════════════════════════
 为什么要生成而不是手写
════════════════════════════════════════════════════════════════════
用户 2026-10-10 定调：「舰船、羁绊一定要遵循 EVE 官方的翻译，意译是绝对不行的」。

官方名的**权威出处已经在仓库里**，人再抄一遍必然出错（历史上就抄错过一次：
源 CSV 把 Cyclone / Hurricane 的中文名对调了 —— 而 EVE 官方恰恰是
`Cyclone = 飓风级` / `Hurricane = 暴风级`，与字面意思相反）：

  · 英文名  ← `scripts/data/eve_ship_asset_index.gd` 的 `name_en`
              （机生成：ESI `/universe/ids/` 拿 typeID → 官方英文名）
  · 中文名  ← `scripts/data/eve_ship_table.gd` 的 ROWS 第 2 列
              （设计侧权威表，`verify_data_source` 已与交接 CSV 逐列对拍）

所以术语段一律**从这两张表生成**，脚本可反复重跑。

════════════════════════════════════════════════════════════════════
 用法 / 规矩
════════════════════════════════════════════════════════════════════
    python tools/pipeline/gen_i18n_terms.py            # 写回 i18n/strings.csv

· **只覆盖术语行**（`SHIP.*` / `CLASS.*` / `FACTION.*` / `WEAPON.*` /
  `DEFENSE.*` / `ROLE.*`）。其余行（`SETTINGS_*` / `WINDOW_CLOSE` /
  `TRAITGROUP.*` …）原样保留、顺序不变 —— 那些是手写文案，翻译归翻译。
· ⛔ **别手改术语行**（改了会在下次生成时被覆盖，且 `verify_i18n` 会红）。
  要改名 ⇒ 改上面那两张表 ⇒ 重跑本脚本。
· 改完必须**重导**（Godot 把 CSV 导成 `.translation`）：
      Godot_v4.7.2-stable_win64_console.exe --headless --path . --import
  ⚠️ 若新键取不到，删掉 `i18n/strings.*.translation` 与
     `.godot/imported/strings.csv-*.md5` 再导（实测踩过）。
"""

import io
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CSV = os.path.join(ROOT, "i18n", "strings.csv")
SHIP_TABLE = os.path.join(ROOT, "scripts", "data", "eve_ship_table.gd")
ASSET_INDEX = os.path.join(ROOT, "scripts", "data", "eve_ship_asset_index.gd")

# ── 吨位：中文镜像 `EveShipTable.CLASS_NAMES_BY_COST`；
#           英文用 EVE 官方舰级名（Frigate … Battleship）。
#    ⚠️ 英文这几条**不是**自由翻译：就是 EVE 官方舰级命名。
CLASS_ROWS = [
    ("CLASS.1", "Frigate", "护卫舰"),
    ("CLASS.2", "Destroyer", "驱逐舰"),
    ("CLASS.3", "Cruiser", "巡洋舰"),
    ("CLASS.4", "Battlecruiser", "战列巡洋舰"),
    ("CLASS.5", "Battleship", "战列舰"),
]

# ── 势力：中文镜像 `EveShipTable.FACTION_INDEX` / `EveCombatIds.FACTION_LABEL`。
FACTION_ROWS = [
    ("FACTION.amarr", "Amarr", "艾玛"),
    ("FACTION.caldari", "Caldari", "加达里"),
    ("FACTION.gallente", "Gallente", "盖伦特"),
    ("FACTION.minmatar", "Minmatar", "米玛塔尔"),
]

# ── 武器：英文 = **EVE 官方市场分组名**（市场 → 舰船装备 → 炮台与发射器）：
#      Energy Turrets / Hybrid Turrets / Projectile Turrets / Missile Launchers。
#      中文沿用工程既有简称（EVE 中文维基「炮台」条目：能量炮台又叫激光炮）。
WEAPON_ROWS = [
    ("WEAPON.laser", "Energy Turret", "激光炮"),
    ("WEAPON.hybrid", "Hybrid Turret", "混合炮"),
    ("WEAPON.proj", "Projectile Turret", "射弹炮"),
    ("WEAPON.missile", "Missile Launcher", "导弹"),
]

# ── 防御：EVE 官方就是 Shield / Armor。
DEFENSE_ROWS = [
    ("DEFENSE.shield", "Shield", "盾抗"),
    ("DEFENSE.armor", "Armor", "甲抗"),
]

# ── 定位：后勤 = EVE 官方的 Logistics；另两条是本作的作战定位。
ROLE_ROWS = [
    ("ROLE.attack", "Attack", "攻击型"),
    ("ROLE.defense", "Defense", "防御型"),
    ("ROLE.logi", "Logistics", "后勤"),
]

GENERATED_PREFIXES = ("SHIP.", "CLASS.", "FACTION.", "WEAPON.", "DEFENSE.", "ROLE.")


def read(path):
    with io.open(path, encoding="utf-8") as f:
        return f.read()


def parse_ship_table(src):
    """`["condor",      "小鹰级",     "加达里", …]`  → [(id, 中文名), …]"""
    out = []
    for line in src.split("\n"):
        m = re.match(r'^\t\["([a-z_0-9]+)",\s*"([^"]+)",', line)
        if m:
            out.append((m.group(1), m.group(2)))
    return out


def parse_asset_index(src):
    """`["bantam", 582, "Bantam", "矮脚鸡级", 1, […]],` → {id: name_en}"""
    out = {}
    for line in src.split("\n"):
        m = re.match(r'^\t\["([a-z_0-9]+)",\s*\d+,\s*"([^"]+)",\s*"([^"]+)"', line)
        if m:
            out[m.group(1)] = m.group(2)
    return out


def main():
    ships = parse_ship_table(read(SHIP_TABLE))
    en_by_id = parse_asset_index(read(ASSET_INDEX))
    if not ships:
        sys.exit("✗ 解析不出舰船表 ROWS —— 表结构变了？")
    if not en_by_id:
        sys.exit("✗ 解析不出资产索引 ROWS —— 表结构变了？")

    missing = [sid for sid, _ in ships if sid not in en_by_id]
    assert not missing, "资产索引缺这些 id：%s" % missing

    rows = list(CLASS_ROWS) + list(FACTION_ROWS) + list(WEAPON_ROWS) \
        + list(DEFENSE_ROWS) + list(ROLE_ROWS)
    for sid, cn in ships:
        rows.append(("SHIP." + sid, en_by_id[sid], cn))

    by_key = {k: (en, cn) for k, en, cn in rows}

    # ── 读旧文件，剥掉术语行（保留手写行与其顺序）──
    keep = []
    if os.path.exists(CSV):
        with io.open(CSV, encoding="utf-8-sig") as f:
            lines = f.read().split("\n")
        for i, line in enumerate(lines):
            line = line.rstrip("\r")
            if not line.strip():
                continue
            if i == 0:
                continue                      # 表头统一重写
            key = line.split(",")[0]
            if key.startswith(GENERATED_PREFIXES):
                continue
            keep.append(line)

    out = ["keys,en,zh_CN"] + keep + ["%s,%s,%s" % (k, en, cn) for k, en, cn in rows]
    with io.open(CSV, "w", encoding="utf-8-sig", newline="") as f:
        f.write("\n".join(out) + "\n")

    print("✓ 写回 %s" % os.path.relpath(CSV, ROOT))
    print("  术语行 %d（舰船 %d / 吨位 %d / 势力 %d / 武器 %d / 防御 %d / 定位 %d）"
          % (len(rows), len(ships), len(CLASS_ROWS), len(FACTION_ROWS),
             len(WEAPON_ROWS), len(DEFENSE_ROWS), len(ROLE_ROWS)))
    print("  保留手写行 %d：%s" % (len(keep), ", ".join(r.split(",")[0] for r in keep)))
    print("  ⚠️ 记得重导：--headless --path . --import")


if __name__ == "__main__":
    main()
