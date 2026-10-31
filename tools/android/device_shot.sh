#!/usr/bin/env bash
# 安卓线 · 真机抓图 + 指标回传
#
# 用法：
#   bash tools/android/device_shot.sh [输出png路径]
#
# 做四件事：
#   ① 检查 adb / 设备（没设备时打印连接步骤，不静默失败）
#   ② 抓一张**真机当前画面**（不是桌面 SubViewport 模拟图）
#   ③ 打印 wm size / density / 机型 / SDK
#   ④ 回传设备指标：优先 run-as 读 user://device_metrics.txt，
#      失败则从 logcat 抓 EveDeviceInfo 摘要（release 包也能用）
#
# ⚠️ 为什么需要它：桌面探针固定 1920×1080，而真机是「约 2340×1080 + 安全区
#    + content_scale_factor」—— 两者逻辑视口不同。只看桌面图会得出错误结论。

set -uo pipefail

PKG="${PKG:-com.evezzq.autochess}"
OUT_DIR="${OUT_DIR:-outputs}"

find_adb() {
  if [ -n "${ADB:-}" ] && [ -x "${ADB}" ]; then echo "${ADB}"; return; fi
  if [ -n "${LOCALAPPDATA:-}" ]; then
    if command -v cygpath >/dev/null 2>&1; then
      local u; u="$(cygpath -u "${LOCALAPPDATA}")/Android/Sdk/platform-tools/adb.exe"
      [ -x "$u" ] && { echo "$u"; return; }
    fi
    [ -x "${LOCALAPPDATA}/Android/Sdk/platform-tools/adb.exe" ] && {
      echo "${LOCALAPPDATA}/Android/Sdk/platform-tools/adb.exe"; return; }
  fi
  # ⚠️ 2026-10-30 清理：原来这里写死了作者的 Windows 用户名
  #    （`/c/Users/Administrator/...`）。仓库要能被任何人 clone 下来就跑，
  #    ⇒ 改用 $HOME 拼（Git Bash 下即 /c/Users/<当前用户>）。
  for c in \
    "${HOME}/AppData/Local/Android/Sdk/platform-tools/adb.exe"; do
    [ -x "$c" ] && { echo "$c"; return; }
  done
  command -v adb 2>/dev/null
}

ADB="$(find_adb)"
if [ -z "${ADB}" ]; then
  echo "✗ 找不到 adb。请设置 ADB 环境变量，或把 platform-tools 加进 PATH。"
  exit 1
fi

echo "adb = ${ADB}"
echo "=== devices ==="
"${ADB}" devices

# 只认状态为 device 的条目（offline / unauthorized 不算）
READY="$("${ADB}" devices | sed '1d' | awk '$2=="device"{print $1}')"
if [ -z "${READY}" ]; then
  cat <<'EOF'

✗ 没有检测到可用的安卓设备。任选一种：

A. USB（推荐先试）
   1) 手机：设置 → 关于手机 → 连点「版本号」7 次 → 开发者选项
   2) 开发者选项 → 打开「USB 调试」
   3) 插 USB 线，手机弹窗选「允许」
   4) 再跑一次本脚本

B. 无线调试（Android 11+）
   1) 手机与电脑同一 Wi-Fi
   2) 设置 → 开发者选项 → 无线调试 →「使用配对码配对设备」
   3) 电脑执行： adb pair <手机IP>:<配对端口>   （输入手机上的 6 位码）
   4) 电脑执行： adb connect <手机IP>:<调试端口>
   5) adb devices 应出现 "<IP>:<端口>  device"

EOF
  exit 1
fi

mkdir -p "${OUT_DIR}"
STAMP="$(date +%Y%m%d-%H%M%S)"
SHOT="${1:-${OUT_DIR}/device_shot_${STAMP}.png}"

echo "=== screencap -> ${SHOT} ==="
# exec-out 是二进制安全的；个别 adb 版本会失败，退回 pull 方案。
"${ADB}" exec-out screencap -p > "${SHOT}" 2>/dev/null || true
if [ ! -s "${SHOT}" ]; then
  "${ADB}" shell screencap -p /sdcard/_eve_shot.png \
    && "${ADB}" pull /sdcard/_eve_shot.png "${SHOT}" >/dev/null \
    && "${ADB}" shell rm -f /sdcard/_eve_shot.png
fi
if [ -s "${SHOT}" ]; then
  echo "✓ 已保存：${SHOT} ($(wc -c < "${SHOT}") bytes)"
else
  echo "✗ 抓图失败（设备可能锁屏）。请解锁后重试。"
fi

echo "=== wm size ===";      "${ADB}" shell wm size
echo "=== wm density ===";   "${ADB}" shell wm density
echo "=== model ===";        "${ADB}" shell getprop ro.product.model
echo "=== sdk ===";          "${ADB}" shell getprop ro.build.version.sdk
echo "=== rotation ===";     "${ADB}" shell dumpsys input 2>/dev/null | grep -i "SurfaceOrientation" | head -1

echo "=== device_metrics.txt (run-as，需 debug APK) ==="
if "${ADB}" shell run-as "${PKG}" cat files/device_metrics.txt 2>/dev/null; then
  :
else
  echo "（run-as 不可用 —— release 包正常。下面从 logcat 取摘要）"
fi

echo "=== logcat · EveDeviceInfo ==="
"${ADB}" logcat -d 2>/dev/null | grep -a "EveDeviceInfo" | tail -5 || echo "（没有记录：先启动一次游戏）"

exit 0
