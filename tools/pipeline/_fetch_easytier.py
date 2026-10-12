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

# ★★ 解出后每个文件的 SHA256（2026-10-12 实测值）。
#    ⛔ 只看「文件在不在 / 多大」是不够的（2026-10-12 联网专项审查 N08）：
#      中断解包、缓存损坏、换版本后遗留的旧文件都会让「检查通过」与实际可执行状态不一致
#      —— 实测把全部文件做成零字节，老的 check() 仍返回 0。
#    ⇒ 换内核版本时必须连同这里一起更新（本文件顶部 VERSION 附近有清单）。
WANT_SHA256 = {
    "easytier-core.exe": "da7eb2d24b5416f3d3407636949e964a0750e3f9dc53a828cb6799a57ead445d",
    "Packet.dll": "c7c03a87eac7243ccbe331554624b18803010b740e311fc8cfddb573096eacac",
    "wintun.dll": "e5da8447dc2c320edc0fc52fa01885c103de8c118481f683643cacc3220dafce",
    "WinDivert64.sys": "8da085332782708d8767bcace5327a6ec7283c17cfb85e40b03cd2323a90ddc2",
    "easytier-cli.exe": "d8783e851e944b44a9b71b39fd02f227ec0a2a82b3165c55ead5dd32dcde53a1",
    # Android 那份（Magisk 包里的 easytier-core，AArch64）
    "android-arm64/easytier-core": "7bd504e87cad52edacb9ea84ece7397d0afb911101de623a3dfc4a4dbd9e6bb6",
}
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


def verify_one(path: str, key: str) -> tuple[bool, str]:
    """按 `WANT_SHA256[key]` 校验单个文件。返回 `(ok, 说明)`。"""
    want = WANT_SHA256.get(key)
    if not os.path.exists(path):
        return False, "缺失"
    if os.path.getsize(path) == 0:
        return False, "零字节"
    got = sha256_file(path)
    if want and got != want:
        return False, "SHA256 不符（%s… != %s…）" % (got[:12], want[:12])
    return True, ""


def present() -> list[str]:
    """**已通过哈希校验**的 Windows 内核文件（⛔ 不是「文件存在」）。"""
    return [n for n in WANT if verify_one(os.path.join(DEST, n), n)[0]]


def android_ready() -> bool:
    """Android 内核就位：源文件哈希正确，**且 jniLibs 那份与它逐字节一致**。"""
    ok_core, _ = verify_one(ANDROID_CORE, "android-arm64/easytier-core")
    if not ok_core or not os.path.exists(JNI_SO):
        return False
    return sha256_file(JNI_SO) == sha256_file(ANDROID_CORE)


def check(verbose: bool = True) -> int:
    ok = True
    if verbose:
        print("目标目录：%s" % DEST)
    for n in WANT:
        good, why = verify_one(os.path.join(DEST, n), n)
        if good:
            if verbose:
                print("  ✓ %-20s %10d 字节  SHA256 校验通过" % (n, os.path.getsize(os.path.join(DEST, n))))
        else:
            print("  ✗ %-20s %s" % (n, why))
            ok = False
    for label, p, key in (("android-arm64/easytier-core", ANDROID_CORE, "android-arm64/easytier-core"),
                          ("jniLibs/arm64-v8a/libetcore.so", JNI_SO, "android-arm64/easytier-core")):
        good, why = verify_one(p, key)
        if good:
            if verbose:
                print("  ✓ %-28s %10d 字节  SHA256 校验通过" % (label, os.path.getsize(p)))
        else:
            print("  ✗ %-28s %s（安卓联机需要）" % (label, why))
            ok = False
    # jniLibs 那份必须与源文件一致（否则「换了内核但装的是旧的」）
    if os.path.exists(ANDROID_CORE) and os.path.exists(JNI_SO) and not android_ready():
        print("  ✗ jniLibs 里的 libetcore.so 与 android-arm64/easytier-core 不一致 ⇒ 重跑 --force")
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
    # ★ 解出后**逐个按哈希校验**：解包中断/磁盘损坏都必须在这里暴露，而不是等到玩家点建房
    bad = [n for n in WANT if not verify_one(os.path.join(DEST, n), n)[0]]
    if bad:
        print("✗ 解出的文件校验不通过：%s ⇒ 请重跑 --force" % ", ".join(bad))
        return False
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
    if not android_ready():
        print("✗ Android 内核校验不通过（源文件哈希不符 或 jniLibs 副本不一致）⇒ 请重跑 --force")
        return False
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
