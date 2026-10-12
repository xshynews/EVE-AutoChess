# -*- coding: utf-8 -*-
"""
★ 正式版导出（Windows exe + Android apk）。

⛔ 为什么不能直接用 `godot --export-release`：
   `addons/godot_mcp` 插件在**导出时也会被加载**，它会往 ProjectSettings 注入
   autoload `res://addons/godot_mcp/runtime/mcp_runtime_probe.gd`；
   而 export_presets.cfg 又把 `addons/godot_mcp/*` 排除在包外 ⇒
   导出的包一启动就报 3 条 ERROR（"Failed to instantiate an autoload"）。
   ⇒ 做法：**导出期间临时禁用该插件，导完原样还原**（开发期 MCP 完全不受影响）。

用法：
    python tools/pipeline/export_release.py            # 两个平台都导
    python tools/pipeline/export_release.py windows    # 只导 Windows
    python tools/pipeline/export_release.py android

导出目标路径**不写死** —— 从 export_presets.cfg 的 `export_path` 读（升版本只改预设）。
"""
import io
import os
import re
import subprocess
import sys

from _paths import ROOT, godot_bin

PROJ = ROOT
GODOT = godot_bin()
PRESETS = os.path.join(PROJ, "export_presets.cfg")
PROJECT = os.path.join(PROJ, "project.godot")

# MCP 插件的启用行 —— 摘掉它 ⇒ 导出时插件不加载 ⇒ 不会注入 autoload
MCP_LINE = 'enabled=PackedStringArray("res://addons/godot_mcp/plugin.cfg")'
MCP_OFF = "enabled=PackedStringArray()"

# ★ 2026-10-11（PR#2 合并后加固）：插件**启用**时，godot_mcp 还会把 autoload 条目
#   写进 project.godot（编辑器保存项目时注入）。只摘插件行挡不住它 ——
#   导出包里没有被排除的 probe 脚本 ⇒ 一启动就 "Failed to instantiate an autoload"。
#   ⇒ 导出期间把 autoload 行也临时摘掉，导完原样还原。
AUTOLOAD_LINE = 'MCPRuntimeProbe="*res://addons/godot_mcp/runtime/mcp_runtime_probe.gd"'

PLATFORMS = {"windows": "Windows", "android": "Android"}


def preset_export_path(preset_name: str) -> str:
    """从 export_presets.cfg 里取某个预设的 export_path（相对工程目录）。"""
    src = io.open(PRESETS, encoding="utf-8").read()
    blocks = src.split("[preset.")
    for b in blocks:
        if 'name="%s"' % preset_name in b:
            m = re.search(r'export_path="([^"]+)"', b)
            if m:
                return os.path.normpath(os.path.join(PROJ, m.group(1)))
    raise SystemExit("✗ export_presets.cfg 里找不到预设 %s" % preset_name)


def main() -> None:
    want = [a.lower() for a in sys.argv[1:]]
    targets = [PLATFORMS[w] for w in want] if want else list(PLATFORMS.values())

    original = io.open(PROJECT, encoding="utf-8").read()
    work = original
    if MCP_LINE in work:
        work = work.replace(MCP_LINE, MCP_OFF, 1)
    else:
        print("⚠ project.godot 里没有 MCP 启用行，跳过摘除")
    if AUTOLOAD_LINE in work:
        work = work.replace(AUTOLOAD_LINE + "\n", "", 1)
        print("── 已临时摘除 [autoload] MCPRuntimeProbe（导完还原）")
    else:
        print("⚠ project.godot 里没有 MCP autoload 条目，跳过摘除")
    # B-R02（2026-10-11 审查）：失败必须传播 —— 否则 CI / 调用方拿 0 当成功
    failed = []
    try:
        io.open(PROJECT, "w", encoding="utf-8", newline="").write(work)
        for name in targets:
            out = preset_export_path(name)
            print("── 导出 %s → %s" % (name, out))
            r = subprocess.run(
                [GODOT, "--headless", "--path", PROJ, "--export-release", name, out],
                capture_output=True, text=True, encoding="utf-8", errors="replace",
            )
            tail = [l for l in (r.stdout or "").splitlines() if l.strip()][-3:]
            for l in tail:
                print("   ", l)
            ok = r.returncode == 0 and os.path.exists(out)
            size = os.path.getsize(out) if os.path.exists(out) else 0
            print("   %s  %.1f MB" % ("✓" if ok else "✗ 失败", size / 1048576.0))
            if not ok:
                failed.append("%s(退出码 %d)" % (name, r.returncode))
                err_tail = [l for l in (r.stderr or "").splitlines() if l.strip()][-5:]
                for l in err_tail:
                    print("    [stderr]", l)
    finally:
        # ⛔ 无论成功失败都要还原 —— 否则用户下次打开编辑器 MCP 就没了
        io.open(PROJECT, "w", encoding="utf-8", newline="").write(original)
        print("── 已还原 project.godot（MCP 插件保持启用）")
    if failed:
        # ⚠️ 还原**之后**才退非零 —— 保证 project.godot 一定先写回
        raise SystemExit("✗ 导出失败：%s" % ", ".join(failed))
    print("── 全部导出成功")


if __name__ == "__main__":
    main()
