#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""抓取内置联机内核（EasyTier）—— **版本与哈希钉死**。

为什么不让二进制进 git（2026-10-12 用户定）：
  · 24 MB 的第三方可执行文件会让仓库永久膨胀，且二进制没法 review；
  · 走「构建时下载 + SHA256 校验」既可复现，也留得下审计痕迹。

产物：
  <工程>/addons/easytier/bin/easytier-core.exe   ← 必需
  <工程>/addons/easytier/bin/wintun.dll          ← 仅房主（TUN 模式）需要
  <工程>/addons/easytier/bin/easytier-cli.exe    ← 排障用（游戏运行时不依赖）

用法：
    python tools/pipeline/_fetch_easytier.py            # 下载并校验
    python tools/pipeline/_fetch_easytier.py --force    # 已有也重下
    python tools/pipeline/_fetch_easytier.py --check    # 只校验现有文件

⚠️ 换版本时必须同时改：本文件的 VERSION/SHA256_ZIP、`scripts/net/eve_tunnel.gd`
   的 `VERSION`、以及技术声明里的版本号（三处同号）。
⚠️ 许可：EasyTier 为 **LGPL-3.0**。以「独立可执行文件、进程方式调用、不做链接」
   方式分发 ⇒ 需随包附 LGPL-3.0 全文 + 上游地址 + 版本号 + 可替换说明。
   详见 `addons/easytier/LICENSE-EasyTier.txt` 与 README「技术声明」。
"""
from __future__ import annotations

import argparse
import hashlib
import io
import os
import shutil
import sys
import urllib.request
import zipfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _paths import ROOT  # noqa: E402

VERSION = "2.6.4"
ASSET = "easytier-windows-x86_64-v%s.zip" % VERSION
URL = "https://github.com/EasyTier/EasyTier/releases/download/v%s/%s" % (VERSION, ASSET)
# 2026-10-12 实测下载所得；⛔ 换版本必须同步换哈希，否则本脚本会拒绝安装
SHA256_ZIP = "27af91e270e554709b048bd32327fefd2dfce5062ae1e8701af7550c6f525f84"
# ⚠️ Packet.dll 是**加载期硬依赖**（缺了内核 100ms 静默退出，实测）；
#    wintun.dll 仅房主 TUN 需要；WinDivert64.sys 体积很小，一并带上以防内核对它有运行时依赖。
#    ⛔ 不带 easytier-web*.exe（那是它的 Web 面板，与游戏无关）
WANT = ("easytier-core.exe", "Packet.dll", "wintun.dll", "WinDivert64.sys", "easytier-cli.exe")
DEST = os.path.join(ROOT, "addons", "easytier", "bin")


def sha256_file(path: str) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def present() -> list[str]:
    return [n for n in WANT if os.path.exists(os.path.join(DEST, n))]


def check() -> int:
    have = present()
    print("目标目录：%s" % DEST)
    for n in WANT:
        p = os.path.join(DEST, n)
        if os.path.exists(p):
            print("  ✓ %-20s %10d 字节" % (n, os.path.getsize(p)))
        else:
            print("  ✗ %-20s 缺失" % n)
    return 0 if len(have) == len(WANT) else 1


def fetch(force: bool) -> int:
    os.makedirs(DEST, exist_ok=True)
    if not force and len(present()) == len(WANT):
        print("已就位，跳过下载（要重下加 --force）")
        return check()
    zip_path = os.path.join(DEST, ASSET)
    print("下载 %s" % URL)
    req = urllib.request.Request(URL, headers={"User-Agent": "eve-autochess-fetch"})
    with urllib.request.urlopen(req, timeout=180) as r, io.open(zip_path, "wb") as f:
        shutil.copyfileobj(r, f)
    got = sha256_file(zip_path)
    if got != SHA256_ZIP:
        os.remove(zip_path)
        print("✗ SHA256 不匹配！\n  期望 %s\n  实际 %s" % (SHA256_ZIP, got))
        print("  ⇒ 已删除下载文件。若确认要升级内核，请更新脚本里的 VERSION/SHA256_ZIP。")
        return 1
    print("✓ SHA256 校验通过")
    with zipfile.ZipFile(zip_path) as z:
        for n in z.namelist():
            base = os.path.basename(n)
            if base in WANT:
                with z.open(n) as src, io.open(os.path.join(DEST, base), "wb") as out:
                    shutil.copyfileobj(src, out)
                print("  解出 %s" % base)
    os.remove(zip_path)
    return check()


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--force", action="store_true", help="已存在也重新下载")
    ap.add_argument("--check", action="store_true", help="只校验，不下载")
    a = ap.parse_args()
    return check() if a.check else fetch(a.force)


if __name__ == "__main__":
    raise SystemExit(main())
