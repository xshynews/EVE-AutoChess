# Android 构建模板（不入库，两步装回）

这个目录里**只有构建期需要的东西**，`android/build/`（207 MB）⛔ 不提交进仓库。

## 为什么需要它

安卓联机要把 EasyTier 的内核**打进 APK 的原生库目录**：

- Android 10+ 禁止在应用数据目录 `exec()` 文件；
- APK 原生库目录 `/data/app/<pkg>/lib/arm64/` 是**唯一**允许执行的位置；
- 而 AGP 只会把 `jniLibs` 下的 `lib*.so` 放进那里 ⇒ 内核必须改名 `libetcore.so` 并由 gradle 构建打包。

⇒ 所以安卓导出必须开 `gradle_build`，也就必须装构建模板。

## 装回步骤（新克隆 / 模板被覆盖后）

前提：Android SDK + JDK 17 已配好（Godot「编辑器设置 → 导出 → Android」里的两个路径）。
本机现状：SDK 在 `%LOCALAPPDATA%\Android\Sdk`，JDK 在 `C:/AndroidTools/jdk-17.0.20.1+1`。
需要的 SDK 组件（模板要求）：`build-tools;36.1.0`、`platforms;android-36`。
⛔ **不需要 NDK** —— 本项目没有要编译的原生代码（见下面第 3 步的补丁说明）。

```bash
# 1) 安装构建模板：Godot 编辑器 → 项目 → 安装 Android 构建模板
#    （等价于把 export_templates/4.7.2.stable/android_source.zip 解到 android/build/）

# 2) 取内核（Windows + Android 两个平台一起），并把 Android 内核装进 jniLibs
python tools/pipeline/_fetch_easytier.py

# 3) 【必须】给模板打补丁 —— 模板会覆盖 build.gradle，所以每次重装模板后都要跑
python tools/pipeline/_android_patch.py          # 幂等，可反复跑；--check 只看不改
```

第 3 步补了四件事（细节见 `tools/pipeline/_android_patch.py` 顶部注释）：

| 补丁 | 不加会怎样 |
|---|---|
| `jniLibs.srcDirs` 加回 `src/main/jniLibs` | 模板把源目录写死成 `libs/release` ⇒ 我们的 `libetcore.so` **被静默忽略**，APK 里根本没有 |
| 无条件 `keepDebugSymbols += '**/*.so'` | AGP 会调 NDK 的 `llvm-strip` 剥离符号 ⇒ 没装 NDK 就报错 |
| 注释掉 `ndkVersion`（本机无 NDK 时） | AGP 配置阶段可能直接报 `No version of NDK matched ...` |
| 写对 `android/.build_version` | 值必须**精确等于**导出模板目录名（如 `4.7.2.stable`，⛔ 不是 `4.7.2.stable.official`），且位置在 **`android/`** 而不是 `android/build/`；错一个字导出就被拒：`Android build template is outdated ... Requested version: …` |

## 与导出预设的配合（已配好，别手改）

- `export_presets.cfg` → Android 预设：`gradle_build/use_gradle_build=true`
- `gradle_build/compress_native_libraries=true` ⇒ `extractNativeLibs=true`
  ⛔ 这项必须是 true：它决定 `.so` 会不会被**解压到原生库目录**。设成 false 时库里只有 mmap 的压缩包内数据，**没法 exec**。
- `permissions/internet=true` ⇒ 否则安卓端任何 socket 都建不了
- `architectures/arm64-v8a=true` ⇒ 与我们准备的 AArch64 内核一致

## 验证（不用真机也能验一半）

导出 APK 后看它里面有没有内核：

```bash
python -c "import zipfile;z=zipfile.ZipFile('EVE自走棋正式版V0.14.1.apk');print([n for n in z.namelist() if 'etcore' in n])"
# 期望输出 ['lib/arm64-v8a/libetcore.so']
```

真机侧要验的（只能在设备上做）：
1. `/proc/self/maps` 能否反解出原生库目录（`eve_tunnel.gd` 的 `parse_native_lib_dir`）；
2. 该目录下的 `libetcore.so` 能否被 `OS.create_process` 执行（部分厂商 ROM 更严）；
3. 加入房间后能否与 Windows 房主互通。
