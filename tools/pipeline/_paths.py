# -*- coding: utf-8 -*-
r"""流水线公共路径解析 —— **全仓唯一真源**（2026-10-12 引入）。

## 为什么有这个文件

流水线脚本原先各自**硬编码作者本机的绝对路径**：

    C:\godot\_export\…                （工作目录 / 中间产物）
    F:\evezzq\eve自走棋918\…          （工程根）
    D:\EVE\SharedCache\…             （EVE 客户端缓存）
    C:\Users\Administrator\.workbuddy\…（本机解释器 / 技能脚本）

⇒ 别人克隆仓库后一个脚本都跑不起来（**假开源**）。
现在一律从这里取，并且**每一项都能用环境变量覆盖**：

| 环境变量 | 含义 | 默认值 |
| --- | --- | --- |
| `EVE_PROJECT_ROOT` | Godot 工程根 | 本文件上溯两级（= 仓库根） |
| `EVE_WORK_DIR` | 流水线工作目录（中间产物） | 旧的 `C:\\godot\\_export`（存在时）否则 `<仓库根>/.pipeline_work` |
| `EVE_CLIENT_DIR` | EVE 客户端 SharedCache | 旧的 `D:/EVE/SharedCache`（存在时）否则未设置 |
| `EVE_CARD_SRC` | 卡牌正面原图目录 | 旧的 `F:/EVE自走棋/牌面/牌面`（存在时）否则 `<仓库根>/.incoming/cards` |
| `EVE_GODOT_BIN` | Godot 可执行文件 | 依次找 `C:/godot/Godot_v4.7.2-stable_win64_console.exe`、`Godot_v4.7.2-stable_win64.exe` |
| `EVE_TEXCONV` | `texconv.exe`（DirectXTex） | 先看 `<工作目录>/_tools/texconv.exe`，再从 `PATH` 找；都没有则相关脚本报明确错误 |
| `EVE_PYTHON` | 供 subprocess 调用的解释器 | `sys.executable`（即当前跑脚本的这个） |

## 用法

脚本里**只写这一句**，别再出现任何 `C:\\…` / `F:\\…`：

    from _paths import ROOT, WORK, CLIENT, CARD_SRC, godot_bin, texconv

⚠️ 直接 `python tools/pipeline/xxx.py` 运行时，脚本所在目录就是 `sys.path[0]`，
   所以 `from _paths import …` 无需额外处理路径。

## 兼容性口径（重要）

「旧目录存在就用旧的」不是偷懒 —— 是为了**不破坏作者本机已有的中间产物**
（那些目录里有跑了几十分钟的构建结果）。别人的机器上没有这些目录，会自然落到
仓库内的默认值 ⇒ 同一个脚本在两边都能跑起来。
"""
import os
import shutil
import sys

# ★ 2026-10-12：**统一把标准输出设成 UTF-8**。
#   为什么必须在这里做：Windows 上 Python 的 stdout 默认按**本地代码页**编码
#   （英文系统 = cp1252），脚本一打中文就 `UnicodeEncodeError` 直接崩 ——
#   而中文开发机上永远是 UTF-8，**本地根本复现不出来**（CI 实测踩到）。
#   放在 `_paths`（所有流水线脚本都会 import 的第一个模块）⇒ 一处生效、全仓受益。
for _s in (sys.stdout, sys.stderr):
    try:
        _s.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass

# ── 仓库根：本文件 = <root>/tools/pipeline/_paths.py ⇒ 上溯两级 ──────────
_HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.environ.get("EVE_PROJECT_ROOT") or os.path.dirname(os.path.dirname(_HERE))

# ── 旧本机路径（仅作**兼容回退**；不存在就忽略）──────────────────────────
_LEGACY_WORK = r"C:\godot\_export"
_LEGACY_CLIENT = r"D:\EVE\SharedCache"
_LEGACY_CARD_SRC = r"F:\EVE自走棋\牌面\牌面"


def _first_existing(*cands):
    for c in cands:
        if c and os.path.exists(c):
            return c
    return None


# ── 工作目录（中间产物）。默认落在仓库内，⛔ 别提交（见 .gitignore）─────
WORK = os.environ.get("EVE_WORK_DIR") or _first_existing(
    _LEGACY_WORK, os.path.join(ROOT, ".pipeline_work")) \
    or os.path.join(ROOT, ".pipeline_work")

# ── EVE 客户端缓存（音频 / 星云 / 官方渲染图等原始资源）───────────────
CLIENT = os.environ.get("EVE_CLIENT_DIR") or _first_existing(_LEGACY_CLIENT) or ""

# ── 卡牌正面原图（设计侧给的 PNG）──────────────────────────────────
CARD_SRC = os.environ.get("EVE_CARD_SRC") or _first_existing(_LEGACY_CARD_SRC) \
    or os.path.join(ROOT, ".incoming", "cards")

# ── 工程内的关键文件（脚本产物 / 输入）───────────────────────────────
YAW_GD = os.path.join(ROOT, "scripts", "data", "eve_ship_yaw.gd")
SHIP_INDEX_GD = os.path.join(ROOT, "scripts", "data", "eve_ship_asset_index.gd")
GLB_DIR = os.path.join(ROOT, "assets", "ships3d")
CARDS_DIR = os.path.join(ROOT, "assets", "cards")
TIER_DIR = os.path.join(ROOT, "assets", "ui", "tier")

# ── 流水线清单 / 构建脚本（已随仓库开源，见 tools/pipeline/_manifest/）──
MANIFEST_DIR = os.path.join(_HERE, "_manifest")
SHIP_MANIFEST = os.path.join(MANIFEST_DIR, "_ship_manifest.json")
TYPEIDS_JSON = os.path.join(MANIFEST_DIR, "_typeids.json")
SHIP_BUILD_SCRIPT = os.path.join(_HERE, "eve_ship_build.py")
BLENDER_PROJECT_SCRIPT = os.path.join(_HERE, "blender_project.py")


def work(*parts):
    """工作目录下的路径（自动创建目录）。"""
    p = os.path.join(WORK, *parts)
    os.makedirs(os.path.dirname(p), exist_ok=True) if os.path.splitext(p)[1] else os.makedirs(p, exist_ok=True)
    return p


def build_result_json():
    """3D 构建结果：优先用仓库内的清单（可复现），其次作者本机的工作目录。"""
    local = os.path.join(MANIFEST_DIR, "_build_result.json")
    if os.path.exists(local):
        return local
    return os.path.join(WORK, "_ship3d", "_build_result.json")


def godot_bin(console=True):
    """Godot 可执行文件。`console=True` 返回 console 版（无头跑 stdout 才回显）。"""
    env = os.environ.get("EVE_GODOT_BIN")
    if env:
        return env
    names = ["Godot_v4.7.2-stable_win64_console.exe", "Godot_v4.7.2-stable_win64.exe"] \
        if console else ["Godot_v4.7.2-stable_win64.exe", "Godot_v4.7.2-stable_win64_console.exe"]
    cands = [os.path.join(r"C:\godot", n) for n in names]
    found = _first_existing(*cands)
    if found:
        return found
    # 退一步：PATH 里找
    for n in names:
        w = shutil.which(n)
        if w:
            return w
    raise SystemExit(
        "✗ 找不到 Godot 可执行文件。设环境变量 EVE_GODOT_BIN 指向它，"
        "或把它放到 C:/godot/ 下（版本见 README）。")


def python():
    """供 subprocess 调用的 Python 解释器（默认 = 当前解释器）。"""
    return os.environ.get("EVE_PYTHON") or sys.executable


def texconv():
    """texconv.exe（DirectXTex，第三方二进制，**不入库**）。找不到返回 ""。"""
    env = os.environ.get("EVE_TEXCONV")
    if env and os.path.exists(env):
        return env
    local = os.path.join(WORK, "_tools", "texconv.exe")
    if os.path.exists(local):
        return local
    return shutil.which("texconv") or ""


def godot_user_dir(project_name=None):
    """Godot 的 `user://` 目录（Windows：`%APPDATA%/Godot/app_userdata/<工程名>`）。

    ⚠️ 工程名改过（旧 `EVE自走棋918` → 现 `EVE 自走棋`）⇒ 两种都试，
       也可以用 `EVE_GODOT_USER_NAME` 显式指定。
    """
    name = os.environ.get("EVE_GODOT_USER_NAME") or project_name
    appdata = os.environ.get("APPDATA") or os.path.expanduser("~")
    base = os.path.join(appdata, "Godot", "app_userdata")
    if name:
        return os.path.join(base, name)
    for cand in ("EVE 自走棋", "EVE自走棋918"):
        p = os.path.join(base, cand)
        if os.path.exists(p):
            return p
    return os.path.join(base, "EVE 自走棋")


def fonts():
    """Windows 中文字体（微软雅黑粗/常规）。非 Windows 或缺失时返回 (None, None)。"""
    win = os.environ.get("WINDIR", r"C:\Windows")
    d = os.path.join(win, "Fonts")
    bold = _first_existing(os.path.join(d, "msyhbd.ttc"), os.path.join(d, "msyhbd.ttf"))
    reg = _first_existing(os.path.join(d, "msyh.ttc"), os.path.join(d, "msyh.ttf"))
    return bold, reg


def report():
    """把解析结果打印出来（脚本带 `--where` 或排查环境时用）。"""
    rows = [
        ("仓库根   ROOT", ROOT),
        ("工作目录 WORK", WORK),
        ("EVE 客户端 CLIENT", CLIENT or "(未设置 ⇒ 依赖它的脚本会跳过/报错)"),
        ("卡牌原图 CARD_SRC", CARD_SRC),
        ("清单目录 MANIFEST_DIR", MANIFEST_DIR),
        ("texconv", texconv() or "(未找到 ⇒ 用 EVE_TEXCONV 指定，或下载 DirectXTex)"),
    ]
    print("── 流水线路径解析（env 可覆盖，见 _paths.py 顶注）──")
    for k, v in rows:
        print("  %-22s %s" % (k, v))


if __name__ == "__main__":
    report()
