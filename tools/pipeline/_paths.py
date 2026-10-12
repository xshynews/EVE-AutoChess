# -*- coding: utf-8 -*-
r"""流水线公共路径解析。所有流水线脚本都从这里取路径，脚本里不要再写绝对路径。

## 配置来源（优先级从高到低）

1. 环境变量（下表第一列）；
2. 本机配置文件 `tools/pipeline/paths.local.json`（已加入 .gitignore，不会提交）。
   复制 `paths.local.example.json` 改名后按本机情况填写，只需填要改的项；
3. 仓库内默认值。

| 环境变量 | 配置文件键 | 含义 | 默认值 |
| --- | --- | --- | --- |
| `EVE_PROJECT_ROOT` | `project_root` | Godot 工程根 | 本文件上溯两级（仓库根） |
| `EVE_WORK_DIR` | `work_dir` | 流水线工作目录（中间产物） | `<仓库根>/.pipeline_work` |
| `EVE_CLIENT_DIR` | `client_dir` | EVE 客户端 SharedCache | 未设置（依赖它的脚本会报错退出） |
| `EVE_CARD_SRC` | `card_src` | 卡牌正面原图目录 | `<仓库根>/.incoming/cards` |
| `EVE_EXPORT_DIR` | `export_dir` | 发布包输出目录 | `<仓库根>/build` |
| `EVE_GODOT_BIN` | `godot_bin` | Godot 可执行文件 | 在 PATH 中查找 |
| `EVE_TEXCONV` | `texconv` | texconv.exe（DirectXTex） | `<工作目录>/_tools/texconv.exe`，再在 PATH 中查找 |
| `EVE_PYTHON` | `python` | 子进程使用的 Python | 当前解释器 |
| `EVE_GODOT_USER_NAME` | `godot_user_name` | `user://` 目录名 | 自动探测 |

运行 `python tools/pipeline/_paths.py` 可打印当前解析结果。

## 用法

    from _paths import ROOT, WORK, CLIENT, CARD_SRC, godot_bin, texconv

直接运行 `python tools/pipeline/xxx.py` 时，脚本所在目录就是 `sys.path[0]`，可以直接 import。
"""
import io
import json
import os
import shutil
import sys

# Windows 上 Python 的标准输出默认按本地代码页编码（英文系统为 cp1252），输出中文会抛
# UnicodeEncodeError。所有流水线脚本都会 import 本模块，所以在这里统一改成 UTF-8。
for _s in (sys.stdout, sys.stderr):
    try:
        _s.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass

_HERE = os.path.dirname(os.path.abspath(__file__))
LOCAL_CONFIG = os.path.join(_HERE, "paths.local.json")


def _load_local_config():
    if not os.path.exists(LOCAL_CONFIG):
        return {}
    try:
        with io.open(LOCAL_CONFIG, encoding="utf-8") as f:
            data = json.load(f)
    except (OSError, ValueError) as e:
        raise SystemExit("✗ 读取 %s 失败：%s" % (LOCAL_CONFIG, e))
    if not isinstance(data, dict):
        raise SystemExit("✗ %s 顶层必须是 JSON 对象" % LOCAL_CONFIG)
    return data


_LOCAL = _load_local_config()


def _setting(env, key, default=""):
    """按「环境变量 > 本机配置 > 默认值」取一项配置。"""
    v = os.environ.get(env) or _LOCAL.get(key) or default
    return os.path.expanduser(str(v)) if v else ""


def _first_existing(*cands):
    for c in cands:
        if c and os.path.exists(c):
            return c
    return None


# 仓库根：本文件位于 <root>/tools/pipeline/_paths.py。
ROOT = _setting("EVE_PROJECT_ROOT", "project_root", os.path.dirname(os.path.dirname(_HERE)))

# 工作目录（中间产物）。默认在仓库内，已加入 .gitignore。
WORK = _setting("EVE_WORK_DIR", "work_dir", os.path.join(ROOT, ".pipeline_work"))

# EVE 客户端缓存（音频、星云、模型等原始资源）。属于 CCP 的版权资源，不入库。
CLIENT = _setting("EVE_CLIENT_DIR", "client_dir")

# 卡牌正面原图（设计侧提供的 PNG）。默认目录已加入 .gitignore。
CARD_SRC = _setting("EVE_CARD_SRC", "card_src", os.path.join(ROOT, ".incoming", "cards"))

# 发布包输出目录。默认目录已加入 .gitignore。
EXPORT_DIR = _setting("EVE_EXPORT_DIR", "export_dir", os.path.join(ROOT, "build"))

# 工程内的关键文件（流水线的输入或产物）。
YAW_GD = os.path.join(ROOT, "scripts", "data", "eve_ship_yaw.gd")
SHIP_INDEX_GD = os.path.join(ROOT, "scripts", "data", "eve_ship_asset_index.gd")
GLB_DIR = os.path.join(ROOT, "assets", "ships3d")
CARDS_DIR = os.path.join(ROOT, "assets", "cards")
TIER_DIR = os.path.join(ROOT, "assets", "ui", "tier")

# 随仓库提供的清单与构建脚本（见 tools/pipeline/_manifest/）。
MANIFEST_DIR = os.path.join(_HERE, "_manifest")
SHIP_MANIFEST = os.path.join(MANIFEST_DIR, "_ship_manifest.json")
TYPEIDS_JSON = os.path.join(MANIFEST_DIR, "_typeids.json")
SHIP_BUILD_SCRIPT = os.path.join(_HERE, "eve_ship_build.py")
BLENDER_PROJECT_SCRIPT = os.path.join(_HERE, "blender_project.py")


def work(*parts):
    """工作目录下的路径，并确保目录存在（带扩展名的视为文件，只创建其父目录）。"""
    p = os.path.join(WORK, *parts)
    os.makedirs(os.path.dirname(p) if os.path.splitext(p)[1] else p, exist_ok=True)
    return p


def build_result_json():
    """3D 构建结果：优先用仓库内的清单（可复现），其次用工作目录里的。"""
    local = os.path.join(MANIFEST_DIR, "_build_result.json")
    if os.path.exists(local):
        return local
    return os.path.join(WORK, "_ship3d", "_build_result.json")


def godot_bin(console=True):
    """Godot 可执行文件。`console=True` 时优先 console 版（Windows 上无头运行才有输出）。"""
    configured = _setting("EVE_GODOT_BIN", "godot_bin")
    if configured:
        return configured
    names = ["Godot_v4.7.2-stable_win64_console.exe", "Godot_v4.7.2-stable_win64.exe"]
    if not console:
        names.reverse()
    names += ["godot", "godot4"]
    for n in names:
        w = shutil.which(n)
        if w:
            return w
    raise SystemExit(
        "✗ 找不到 Godot 可执行文件：设置环境变量 EVE_GODOT_BIN，"
        "或在 tools/pipeline/paths.local.json 里填写 godot_bin。")


def python_bin():
    """供 subprocess 调用的 Python 解释器。"""
    return _setting("EVE_PYTHON", "python") or sys.executable


def texconv():
    """texconv.exe（DirectXTex，第三方二进制，不入库）。找不到返回空字符串。"""
    configured = _setting("EVE_TEXCONV", "texconv")
    if configured and os.path.exists(configured):
        return configured
    local = os.path.join(WORK, "_tools", "texconv.exe")
    if os.path.exists(local):
        return local
    return shutil.which("texconv") or ""


def godot_user_dir(project_name=None):
    """Godot 的 `user://` 目录（Windows：`%APPDATA%/Godot/app_userdata/<工程名>`）。

    工程改过名（旧名 `EVE自走棋918`，现名 `EVE 自走棋`），未指定时两个都试。
    """
    name = _setting("EVE_GODOT_USER_NAME", "godot_user_name") or project_name
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
    """Windows 中文字体（微软雅黑粗体 / 常规）。非 Windows 或缺失时返回 (None, None)。"""
    win = os.environ.get("WINDIR", r"C:\Windows")
    d = os.path.join(win, "Fonts")
    bold = _first_existing(os.path.join(d, "msyhbd.ttc"), os.path.join(d, "msyhbd.ttf"))
    reg = _first_existing(os.path.join(d, "msyh.ttc"), os.path.join(d, "msyh.ttf"))
    return bold, reg


def report():
    """打印当前的路径解析结果，用于排查环境。"""
    rows = [
        ("本机配置", LOCAL_CONFIG if _LOCAL else "(无 paths.local.json)"),
        ("仓库根 ROOT", ROOT),
        ("工作目录 WORK", WORK),
        ("EVE 客户端 CLIENT", CLIENT or "(未设置，依赖它的脚本会报错退出)"),
        ("卡牌原图 CARD_SRC", CARD_SRC),
        ("发布目录 EXPORT_DIR", EXPORT_DIR),
        ("清单目录 MANIFEST_DIR", MANIFEST_DIR),
        ("texconv", texconv() or "(未找到，用 EVE_TEXCONV 指定或下载 DirectXTex)"),
    ]
    print("── 流水线路径解析 ──")
    for k, v in rows:
        print("  %-22s %s" % (k, v))


if __name__ == "__main__":
    report()
