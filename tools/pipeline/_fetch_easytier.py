#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""抓取内置联机内核（EasyTier）—— **版本与哈希钉死**。

为什么不让二进制进 git（2026-10-12 用户定）：
  · 24 MB 的第三方可执行文件会让仓库永久膨胀，且二进制没法 review；
  · 走「构建时下载 + SHA256 校验」既可复现，也留得下审计痕迹。

产物：
  Windows：
    <工程>/addons/easytier/bin/easytier-core.exe   ← 必需
    <工程>/addons/easytier/bin/wintun.dll          ← 仅房主（TUN 模式）需要
    <工程>/addons/easytier/bin/easytier-cli.exe    ← 排障用（游戏运行时不依赖）
  Android（2026-10-12 加）：
    <工程>/addons/easytier/bin/android-arm64/easytier-core      ← 内核原始文件（留着可复现）
    <工程>/android/build/src/main/jniLibs/arm64-v8a/libetcore.so ← 进 APK 的那份（必须叫 lib*.so）

  ⚠️ Android 内核的唯一来源是 **Easytier-Magisk 包**：官方没有单独的 Android CLI 发行版
     （官方 APK 是 Kotlin + VpnService + `libapp_lib.so`，不是可复用的命令行内核）。
     它是个 AArch64 的普通 ELF 可执行文件，本身不需要 root（Magisk 只是拿它做开机服务）。

用法：
    python tools/pipeline/_fetch_easytier.py            # 缺什么下什么
    python tools/pipeline/_fetch_easytier.py --force    # 全部重下
    python tools/pipeline/_fetch_easytier.py --check    # 只校验现有文件

⚠️ 换版本时必须同时改：本文件的 VERSION/SHA256_ZIP/MAGISK_SHA256、
   `scripts/net/eve_tunnel.gd` 的 `VERSION`、以及技术声明里的版本号（多处同号）。
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

# ── Android ───────────────────────────────────────────────────────────────
MAGISK_ASSET = "Easytier-Magisk-v%s.zip" % VERSION
MAGISK_URL = "https://github.com/EasyTier/EasyTier/releases/download/v%s/%s" % (VERSION, MAGISK_ASSET)
MAGISK_SHA256 = "39a6b4fa21d9fdc83d3b38c90562f610c0986ecc089c4026c3be22a0ab27c5e5"
MAGISK_MEMBER = "easytier-core"                     # 包里的 AArch64 可执行文件
ANDROID_DEST = os.path.join(DEST, "android-arm64")
ANDROID_CORE = os.path.join(ANDROID_DEST, "easytier-core")
# 进 APK 的位置：必须是 jniLibs 下的 `lib*.so`，且构建时开启 extractNativeLibs
# （⇒ 会被解压到原生库目录，而那是 Android 10+ **唯一**允许 exec 的位置）
JNI_DIR = os.path.join(ROOT, "android", "build", "src", "main", "jniLibs", "arm64-v8a")
JNI_SO = os.path.join(JNI_DIR, "libetcore.so")


def sha256_file(path: str) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def present() -> list[str]:
    return [n for n in WANT if os.path.exists(os.path.join(DEST, n))]


def android_ready() -> bool:
    return os.path.exists(ANDROID_CORE) and os.path.exists(JNI_SO)


def check() -> int:
    print("目标目录：%s" % DEST)
    ok = True
    for n in WANT:
        p = os.path.join(DEST, n)
        if os.path.exists(p):
            print("  ✓ %-20s %10d 字节" % (n, os.path.getsize(p)))
        else:
            print("  ✗ %-20s 缺失" % n)
            ok = False
    for label, p in (("android-arm64/easytier-core", ANDROID_CORE),
                     ("jniLibs/arm64-v8a/libetcore.so", JNI_SO)):
        if os.path.exists(p):
            print("  ✓ %-28s %10d 字节" % (label, os.path.getsize(p)))
        else:
            print("  ✗ %-28s 缺失（安卓联机需要）" % label)
            ok = False
    return 0 if ok else 1


def _download(url: str, dest: str) -> bool:
    print("下载 %s" % url)
    req = urllib.request.Request(url, headers={"User-Agent": "eve-autochess-fetch"})
    try:
        with urllib.request.urlopen(req, timeout=300) as r, io.open(dest, "wb") as f:
            shutil.copyfileobj(r, f)
        return True
    except Exception as e:                                     # noqa: BLE001
        print("✗ 下载失败：%s" % e)
        if os.path.exists(dest):
            os.remove(dest)
        return False


def fetch_windows(force: bool) -> bool:
    if not force and len(present()) == len(WANT):
        print("Windows 内核已就位，跳过（要重下加 --force）")
        return True
    os.makedirs(DEST, exist_ok=True)
    zip_path = os.path.join(DEST, ASSET)
    if not _download(URL, zip_path):
        return False
    got = sha256_file(zip_path)
    if got != SHA256_ZIP:
        os.remove(zip_path)
        print("✗ SHA256 不匹配！\n  期望 %s\n  实际 %s" % (SHA256_ZIP, got))
        print("  ⇒ 已删除下载文件。若确认要升级内核，请更新脚本里的 VERSION/SHA256_ZIP。")
        return False
    print("✓ SHA256 校验通过")
    with zipfile.ZipFile(zip_path) as z:
        for n in z.namelist():
            base = os.path.basename(n)
            if base in WANT:
                with z.open(n) as src, io.open(os.path.join(DEST, base), "wb") as out:
                    shutil.copyfileobj(src, out)
                print("  解出 %s" % base)
    os.remove(zip_path)
    return True


def fetch_android(force: bool) -> bool:
    """取 Android arm64 内核，并放一份到 jniLibs（供 APK 打包）。"""
    if not force and android_ready():
        print("Android 内核已就位，跳过（要重下加 --force）")
        return True
    os.makedirs(ANDROID_DEST, exist_ok=True)
    zip_path = os.path.join(ANDROID_DEST, MAGISK_ASSET)
    if not _download(MAGISK_URL, zip_path):
        return False
    got = sha256_file(zip_path)
    if got != MAGISK_SHA256:
        os.remove(zip_path)
        print("✗ Magisk 包 SHA256 不匹配！\n  期望 %s\n  实际 %s" % (MAGISK_SHA256, got))
        print("  ⇒ 已删除下载文件。若确认要升级内核，请更新脚本里的 VERSION/MAGISK_SHA256。")
        return False
    print("✓ Magisk 包 SHA256 校验通过")
    with zipfile.ZipFile(zip_path) as z:
        if MAGISK_MEMBER not in z.namelist():
            print("✗ 包里没有 %s" % MAGISK_MEMBER)
            os.remove(zip_path)
            return False
        data = z.read(MAGISK_MEMBER)
    os.remove(zip_path)
    with io.open(ANDROID_CORE, "wb") as f:
        f.write(data)
    print("  解出 %s（%d 字节，AArch64）" % (ANDROID_CORE, len(data)))
    # 放到 jniLibs：⚠️ 名字必须是 lib*.so，否则 AGP 不会当原生库打包
    os.makedirs(JNI_DIR, exist_ok=True)
    shutil.copyfile(ANDROID_CORE, JNI_SO)
    print("  安装 %s" % JNI_SO)
    print("  ⚠️ 首次/模板重装后请再跑一次 tools/pipeline/_android_patch.py（模板会覆盖 build.gradle）")
    return True


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--force", action="store_true", help="已存在也重新下载")
    ap.add_argument("--check", action="store_true", help="只校验，不下载")
    ap.add_argument("--windows-only", action="store_true", help="只处理 Windows 内核")
    ap.add_argument("--android-only", action="store_true", help="只处理 Android 内核")
    a = ap.parse_args()
    if a.check:
        return check()
    ok = True
    if not a.android_only:
        ok = fetch_windows(a.force) and ok
    if not a.windows_only:
        ok = fetch_android(a.force) and ok
    check()
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
