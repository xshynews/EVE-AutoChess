# -*- coding: utf-8 -*-
"""给 Godot 的 Android 构建模板打三个必要补丁（**幂等**，可反复运行）。

背景（2026-10-12，安卓内置联机内核时踩到）：

1. **jniLibs 源目录被写死**
   模板里 `sourceSets { release.jniLibs.srcDirs = ['libs/release'] }`
   —— 覆盖了 AGP 默认的 `src/main/jniLibs`。我们放进去的
   `src/main/jniLibs/arm64-v8a/libetcore.so` 会被**静默忽略**（APK 里根本没有它）。
   ⇒ 把 `src/main/jniLibs` 加回两个 buildType 的 srcDirs。

2. **.so 默认会被「剥离调试符号」**
   `keepDebugSymbols` 只在 `shouldNotStrip()`（Android Studio 或 -PdoNotStrip）时才生效，
   从 Godot 导出时**不满足** ⇒ AGP 要调 NDK 的 llvm-strip。
   本项目没有要编译的原生代码，为它下载 1.5 GB 的 NDK 不值得。
   ⇒ 无条件 `keepDebugSymbols += '**/*.so'`（顺带让 Godot 自带的 AAR 也不被剥离）。

3. **`ndkVersion` 声明**
   模板里有 `ndkVersion versions.ndkVersion`（29.0.14206865）。本机没装该版本 NDK 时，
   AGP 可能在配置阶段就报 `No version of NDK matched the requested version`。
   ⇒ 仅当本机确实没有该版本 NDK 时，才把这一行注释掉。

★ 幂等：以 `// [eve-patch]` 标记判断是否已打过；重复运行不会重复插入。
★ 何时需要重跑：在 Godot 里「安装 Android 构建模板」会覆盖 `android/build/build.gradle`。

用法：python tools/pipeline/_android_patch.py [--check]
"""
import io
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
GRADLE = os.path.join(ROOT, "android", "build", "build.gradle")
BUILD_DIR = os.path.join(ROOT, "android", "build")
VERSION_FILE = os.path.join(ROOT, "android", ".build_version")
MARK = "// [eve-patch]"

JNI_DEBUG_OLD = "debug.jniLibs.srcDirs = ['libs/debug', 'libs/debug/vulkan_validation_layers']"
JNI_DEBUG_NEW = ("debug.jniLibs.srcDirs = ['libs/debug', 'libs/debug/vulkan_validation_layers', "
                 "'src/main/jniLibs']  " + MARK)
JNI_RELEASE_OLD = "release.jniLibs.srcDirs = ['libs/release']"
JNI_RELEASE_NEW = "release.jniLibs.srcDirs = ['libs/release', 'src/main/jniLibs']  " + MARK

KEEP_BLOCK = """    packagingOptions {
        jniLibs {
            %s 预编译的 .so（含联机内核 libetcore.so）一律不剥离调试符号：
            //   AGP 默认会调 NDK 的 llvm-strip，而本项目不需要 NDK（没有要编译的原生代码）。
            keepDebugSymbols += '**/*.so'
        }
""" % MARK

NDK_LINE = "ndkVersion versions.ndkVersion"
NDK_OFF = ("    // ndkVersion versions.ndkVersion  %s 本机无此版本 NDK；本项目没有要编译的原生代码。\n"
           "    //   若将来要用 GDExtension / 自己编原生库：装上 NDK 后把这一行取消注释。\n" % MARK)

# 4) 资源合并前清掉 Godot 遗留的 `*.tmp`（见 clean_stale_tmp 的说明）。
#    写进 gradle 才不会依赖「人工记得先跑一次脚本」——导出是 Godot 自己调 gradlew 的。
TMP_GUARD = """
%s ── 资源合并前清掉 Godot 导出遗留的 `*.tmp`
//   Godot 写 res/ 资源时会留下 `<名>.<随机数>.tmp` 副本，而 AAPT2 不认 .tmp 后缀 ⇒
//   `mergeStandardReleaseResources` 直接失败（"The file name must end with .xml"）。
//   没有这个钩子，每次导出都得人工先清一遍。
tasks.configureEach { t ->
    if (t.name.startsWith("merge") && t.name.contains("Resources")) {
        t.doFirst {
            def stale = []
            fileTree(dir: projectDir, include: '**/*.tmp').visit { f -> if (!f.isDirectory()) stale << f.file }
            stale.each { it.delete() }
            if (!stale.isEmpty()) {
                logger.lifecycle("eve-patch: cleared ${stale.size()} stale .tmp file(s)")
            }
        }
    }
}
""" % MARK

# 5) 依赖仓库加国内镜像。
#    实测（2026-10-12）：本机直连 `repo.maven.apache.org` 的 TLS 握手会被干扰
#    （"Remote host terminated the handshake"）⇒ 单个 jar 拉不下来，整个构建失败。
#    镜像走的是国内 CDN，不受影响；放在 google()/mavenCentral() **之前** 优先命中。
#    ⛔ 想用原样仓库（比如在墙外）：设环境变量 EVE_NO_CN_MIRROR=1 再跑本脚本。
CN_MIRRORS = """        // %s 国内镜像优先（本机直连 Maven Central 的 TLS 握手会被干扰）
        maven { url 'https://maven.aliyun.com/repository/public' }
        maven { url 'https://maven.aliyun.com/repository/google' }
        maven { url 'https://maven.aliyun.com/repository/gradle-plugin' }
""" % MARK

GRADLE_PROPS = os.path.join(BUILD_DIR, "gradle.properties")

## 本轮**应当**写入但还没写入的补丁（供 `--check` 当发布门槛用）
_MISSING: list = []
DAEMON_OFF = """# %s 关掉 gradle daemon：
#   ① 实测（2026-10-12）daemon 会继承 gradlew 的 stdout 管道 ⇒ Godot 等不到 EOF，
#      **导出在 APK 产出后一直不退出**（实测挂了 19 分钟）⇒ 无人值守导出必须关掉它。
#   ② 不用 daemon 时，`org.gradle.jvmargs` 里的 `-D…proxyHost` 才会真正生效。
org.gradle.daemon=false
""" % MARK


def ndk_present() -> bool:
    """本机 SDK 里有没有模板要求的那个 NDK 版本。"""
    sdk = os.environ.get("ANDROID_HOME") or os.environ.get("ANDROID_SDK_ROOT")
    if not sdk:
        sdk = os.path.join(os.environ.get("LOCALAPPDATA", ""), "Android", "Sdk")
    cfg = os.path.join(ROOT, "android", "build", "config.gradle")
    want = ""
    if os.path.exists(cfg):
        m = re.search(r"ndkVersion\s*:\s*'([^']+)'", io.open(cfg, encoding="utf-8").read())
        if m:
            want = m.group(1)
    return bool(want) and os.path.isdir(os.path.join(sdk, "ndk", want))


def expected_template_version() -> str:
    """Godot 认的构建模板版本串 —— 等于 `export_templates/` 下的目录名（如 `4.7.2.stable`）。

    ★ 踩过（2026-10-12）：这个文件在 **`android/.build_version`**（不是 `android/build/` 下，
      源码里写的是 `build_dir.get_base_dir()`），值必须**精确匹配**，否则导出直接报
      「Android build template is outdated ... Requested version: X」而拒绝构建。
      （一开始我写成 `4.7.2.stable.official`，被 Godot 打回来，它报的 Requested 才是正解。）
    """
    base = os.path.join(os.environ.get("APPDATA", ""), "Godot", "export_templates")
    if not os.path.isdir(base):
        return ""
    cands = [d for d in os.listdir(base)
             if os.path.exists(os.path.join(base, d, "android_source.zip"))]
    if not cands:
        return ""
    cands.sort(key=lambda s: [int(x) if x.isdigit() else x for x in re.split(r"[.\-]", s)])
    return cands[-1]


def ensure_build_version(check_only: bool) -> None:
    want = expected_template_version()
    if not want:
        print("⚠ 找不到导出模板目录，跳过 .build_version 检查（缺失会导致导出被拒）")
        return
    cur = ""
    if os.path.exists(VERSION_FILE):
        cur = io.open(VERSION_FILE, encoding="utf-8").read().strip()
    if cur == want:
        print("· .build_version 正确（%s）" % want)
        return
    _MISSING.append(".build_version")
    print("── .build_version 需要写为 %r（当前 %r）" % (want, cur))
    if check_only:
        print("（--check：未写盘）")
        return
    os.makedirs(os.path.dirname(VERSION_FILE), exist_ok=True)
    io.open(VERSION_FILE, "w", encoding="utf-8", newline="").write(want)
    # Godot 自己在 build 目录里也放一个空的 .gdignore（见 export_template_manager.cpp）
    gd = os.path.join(BUILD_DIR, ".gdignore")
    if os.path.isdir(BUILD_DIR) and not os.path.exists(gd):
        io.open(gd, "w").close()
    print("✓ 已写入 %s" % VERSION_FILE)


def clean_stale_tmp(check_only: bool) -> None:
    """清掉 `android/build/` 下的残留 `*.tmp`。

    ★ 踩过（2026-10-12）：Godot 写 `res/` 里的资源是**先写 `<名>.<随机数>.tmp` 再改名**；
      导出一旦被中断（比如手动取消 / 上次构建失败），这些临时文件就留在那儿，
      而 AAPT2 的资源合并**不认 `.tmp` 后缀** ⇒ 之后每次构建都卡在
      `Execution failed for task ':mergeStandardReleaseResources'`
      「The file name must end with .xml」。一次被中断的导出留下了 42 个，害我多跑两轮。
    """
    if not os.path.isdir(BUILD_DIR):
        return
    victims = []
    for root, _dirs, files in os.walk(BUILD_DIR):
        for f in files:
            if f.endswith(".tmp"):
                victims.append(os.path.join(root, f))
    if not victims:
        print("· 没有残留 .tmp")
        return
    _MISSING.append("残留 .tmp")
    print("── 发现 %d 个残留 .tmp（会让资源合并失败）" % len(victims))
    if check_only:
        print("（--check：未删除）")
        return
    n = 0
    for v in victims:
        try:
            os.remove(v)
            n += 1
        except OSError:
            pass
    print("✓ 已清理 %d 个" % n)


def ensure_gradle_props(check_only: bool) -> None:
    """gradle.properties 里必须关掉 daemon。

    ★ 踩过（2026-10-12）：daemon 会**继承** gradlew 的 stdout 管道 ⇒ Godot 读不到 EOF，
      于是「APK 早已产出、导出进程却 19 分钟不退出」——无人值守导出直接会被卡死。
      顺带一个好处：不用 daemon 时，`org.gradle.jvmargs` 里的 `-D…proxyHost` 才会真正生效
      （daemon JVM 的参数来自它自己的注册表，项目里的改动到不了它）。
    """
    if not os.path.exists(GRADLE_PROPS):
        print("⚠ 找不到 %s，跳过（模板结构可能变了）" % GRADLE_PROPS)
        return
    s = io.open(GRADLE_PROPS, encoding="utf-8").read()
    if "org.gradle.daemon=false" in s:
        print("· gradle daemon 已关闭")
        return
    _MISSING.append("org.gradle.daemon=false")
    print("── gradle.properties 需要 org.gradle.daemon=false（否则导出会在 gradle 之后一直挂着）")
    if check_only:
        print("（--check：未写盘）")
        return
    s = s.rstrip("\n") + "\n\n" + DAEMON_OFF
    io.open(GRADLE_PROPS, "w", encoding="utf-8", newline="").write(s)
    print("✓ 已写入 %s" % GRADLE_PROPS)


def main() -> int:
    check_only = "--check" in sys.argv
    ensure_build_version(check_only)
    clean_stale_tmp(check_only)
    ensure_gradle_props(check_only)
    if not os.path.exists(GRADLE):
        print("✗ 找不到 %s（先在 Godot 里安装 Android 构建模板）" % GRADLE)
        return 2
    s = io.open(GRADLE, encoding="utf-8").read()
    orig = s
    todo = []

    if JNI_DEBUG_NEW in s or (JNI_DEBUG_OLD not in s and "src/main/jniLibs" in s):
        print("· jniLibs(debug) 已含 src/main/jniLibs")
    elif JNI_DEBUG_OLD in s:
        todo.append("jniLibs(debug) 加回 src/main/jniLibs")
        s = s.replace(JNI_DEBUG_OLD, JNI_DEBUG_NEW, 1)
    else:
        print("⚠ 没找到 debug 的 jniLibs.srcDirs 那行，模板结构可能变了，请人工核对")

    if JNI_RELEASE_NEW in s or (JNI_RELEASE_OLD not in s and "src/main/jniLibs" in s):
        print("· jniLibs(release) 已含 src/main/jniLibs")
    elif JNI_RELEASE_OLD in s:
        todo.append("jniLibs(release) 加回 src/main/jniLibs")
        s = s.replace(JNI_RELEASE_OLD, JNI_RELEASE_NEW, 1)
    else:
        print("⚠ 没找到 release 的 jniLibs.srcDirs 那行，模板结构可能变了，请人工核对")

    if "keepDebugSymbols += '**/*.so'" in s:
        print("· 已无条件 keepDebugSymbols")
    elif "    packagingOptions {\n" in s:
        todo.append("packagingOptions 里无条件 keepDebugSymbols")
        s = s.replace("    packagingOptions {\n", KEEP_BLOCK, 1)
    else:
        print("⚠ 没找到 packagingOptions 块，请人工核对")

    if NDK_OFF.split("\n")[0].strip() in s:
        print("· ndkVersion 已注释掉")
    elif NDK_LINE in s:
        if ndk_present():
            print("· 本机有该版本 NDK ⇒ 保留 ndkVersion（走官方原样）")
        else:
            # ⚠️ 模板里 `ndkVersion` 出现**两次**（android{} 开头一次、lintOptions 后又一次）
            #    ⇒ 必须全部注释掉，否则后面那处仍然生效、AGP 照样报缺 NDK。
            n = s.count("    " + NDK_LINE + "\n")
            _MISSING.append("注释 ndkVersion")
            todo.append("注释掉 ndkVersion（本机无 NDK，共 %d 处）" % n)
            # ⛔⛔ 绝不能写 `count=0`：Python 的 `str.replace(old, new, 0)` 是
            #    「替换 0 次」＝一行都不改（2026-10-12 联网专项审查 N07，实测确认：
            #    `'a\na\n'.replace('a','X',0)` 之后仍是两个 'a'）。
            #    当时代码没生效、靠手工补救才让文件对 ⇒ 现在改为全部替换 + 后置断言。
            s = s.replace("    " + NDK_LINE + "\n", NDK_OFF)
    else:
        print("⚠ 没找到 ndkVersion 行（可能模板已变），跳过")

    if "eve-patch: cleared" in s:
        print("· .tmp 清理钩子已就位")
    else:
        _MISSING.append("gradle .tmp 钩子")
        todo.append("资源合并前清 .tmp 的 gradle 钩子")
        s = s.rstrip("\n") + "\n" + TMP_GUARD

    if MARK + " 国内镜像优先" in s:
        print("· 国内 Maven 镜像已就位")
    elif os.environ.get("EVE_NO_CN_MIRROR"):
        print("· EVE_NO_CN_MIRROR=1 ⇒ 跳过镜像补丁")
    elif "        google()\n" in s:
        _MISSING.append("aliyun 镜像")
        todo.append("依赖仓库加国内镜像（maven.aliyun.com）")
        s = s.replace("        google()\n", CN_MIRRORS + "        google()\n", 1)
    else:
        print("⚠ 没找到 repositories 里的 google() 行，跳过镜像补丁")

    # 后置断言：本轮打算禁用的有效声明必须真的消失（⛔ 别再靠「看起来打了补丁」）。
    if not ndk_present() and "    " + NDK_LINE + "\n" in s:
        print("✗ 仍有未注释的 ndkVersion 声明 ⇒ 补丁未生效，拒绝写盘")
        return 3

    if s == orig:
        print("── 构建模板补丁已是最新")
        if check_only and _MISSING:
            print("✗ --check：缺 %d 项补丁（%s）⇒ 返回非零，可作发布门槛" % (len(_MISSING), "、".join(_MISSING)))
            return 1
        return 0
    print("── 待打补丁：%s" % ("；".join(todo) if todo else "无"))
    if check_only:
        print("（--check：未写盘）")
        return 1
    io.open(GRADLE, "w", encoding="utf-8", newline="").write(s)
    print("✓ 已写入 %s" % GRADLE)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
