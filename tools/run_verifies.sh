#!/usr/bin/env bash
# =============================================================================
#  统一运行全部无头验收。
#
#  用法：
#     tools/run_verifies.sh                          # 引擎路径：GODOT_BIN → 本机配置 → PATH
#     GODOT_BIN=/path/to/godot tools/run_verifies.sh
#     tools/run_verifies.sh /path/to/godot /path/to/project
#
#  环境变量：
#     GODOT_BIN    Godot 可执行文件（Windows 上用 console 版，否则看不到输出）
#     QUIT_AFTER   单套验收的帧数上限，默认 9000
#     LOG_DIR      日志目录，默认 ${TMPDIR:-/tmp}/eve_verify_logs
#
#  本机引擎路径也可以写进 tools/pipeline/paths.local.json 的 `godot_bin`
#  （该文件未入库；仓库里不写死任何机器路径）。
#
#  退出码：0 = 全部通过；1 = 至少一套失败。
#
#  判定规则（任一不满足即失败）：
#     1. 进程退出码为 0；
#     2. 输出中没有 `SCRIPT ERROR` / `Parse Error` / `Failed to load script`；
#     3. 输出中出现完成标记（`RESULT passed=` / `结果：` / `VERIFY_DONE` 等），
#        防止脚本中途退出被当成通过；
#     4. 输出中的失败计数（`failed=N` / `N 项失败` / `失败项 N`）为 0。
# =============================================================================
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# 从本机配置读引擎路径（`tools/pipeline/paths.local.json`，未入库）。
# ★ 2026-10-12 集成 PR#3 时补：PR 把「默认引擎路径」去掉了（仓库里不该写死任何机器路径），
#   但那样本机 `bash tools/run_verifies.sh` 就必须先设 GODOT_BIN 才能跑。
#   这里让 runner 也认同一份本机配置 ⇒ 仓库保持机器无关，本机依然开箱可用。
local_cfg_godot() {
  local f="${SCRIPT_DIR}/pipeline/paths.local.json"
  [ -f "${f}" ] || return 1
  sed -n 's/.*"godot_bin"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "${f}" | head -1
}

find_godot() {
  local c
  for c in "${GODOT_BIN:-}" "$(local_cfg_godot)" godot godot4 \
           Godot_v4.7.2-stable_win64_console.exe \
           Godot_v4.7.2-stable_linux.x86_64; do
    [ -z "${c}" ] && continue
    if [ -x "${c}" ] || command -v "${c}" >/dev/null 2>&1; then
      echo "${c}"
      return 0
    fi
  done
  return 1
}

GODOT="${1:-$(find_godot)}" || true
if [ -z "${GODOT}" ]; then
  echo "找不到 Godot 可执行文件：请设置 GODOT_BIN、传入第一个参数，或写进 tools/pipeline/paths.local.json 的 godot_bin。" >&2
  exit 2
fi
PROJ="${2:-$(cd "${SCRIPT_DIR}/.." && pwd)}"
QUIT_AFTER="${QUIT_AFTER:-9000}"

# 验收套件：数据源、主流程、UI、卡牌、存档、审查修复项。
# 只收有通过/失败判定的脚本（它们都会输出完成标记）。诊断型脚本
# （verify_battle / verify_background / verify_camera 与 probe_*）只输出数据供人查看，不放进来。
SUITE=(
  verify_i18n
  verify_data_source
  verify_ship_table
  verify_ship_assets
  verify_run
  verify_run_save
  verify_review_fixes
  verify_menu
  verify_codex
  verify_ui_scale
  verify_ui_metrics
  verify_resolution
  verify_mobile_layout
  verify_window
  verify_ddz
  verify_ddz_net
  verify_net_config
  verify_ddz_room
  verify_ddz_online_ui
  verify_intro
  verify_audio
)

# 完成标记，命中任意一条即视为脚本已跑完。
MARKER='RESULT passed=|结果：|VERIFY_DONE|全部通过|表结构无问题'

LOG_DIR="${LOG_DIR:-${TMPDIR:-/tmp}/eve_verify_logs}"
mkdir -p "${LOG_DIR}"

fail=0
for t in "${SUITE[@]}"; do
  out="${LOG_DIR}/${t}.log"
  "${GODOT}" --headless --path "${PROJ}" --quit-after "${QUIT_AFTER}" \
      "res://tools/${t}.tscn" >"${out}" 2>&1
  code=$?

  # 2. 脚本错误
  if grep -qE "SCRIPT ERROR|Parse Error|Failed to load script" "${out}"; then
    echo "✗ ${t}：出现脚本错误"
    grep -m3 -E "SCRIPT ERROR|Parse Error|Failed to load script" "${out}" | sed 's/^/    /'
    fail=1
    continue
  fi
  # 3. 完成标记
  if ! grep -qE "${MARKER}" "${out}"; then
    echo "✗ ${t}：没有完成标记（进程退出码 ${code}）—— 可能没跑完"
    tail -5 "${out}" | sed 's/^/    /'
    fail=1
    continue
  fi
  # 4. 失败计数：取输出中最后一个计数（完成标记行在最后，过程行不算）
  fnum="$(grep -oE 'failed=[0-9]+|失败项[：: ]*[0-9]+|[0-9]+[ ]*项失败' "${out}" \
          | grep -oE '[0-9]+' | tail -1)"
  if [ -n "${fnum}" ] && [ "${fnum}" -gt 0 ]; then
    echo "✗ ${t}：输出判据 failed=${fnum}（退出码 ${code}）"
    grep -E 'failed=[0-9]+|失败项|项失败' "${out}" | tail -3 | sed 's/^/    /'
    # 打印前 10 条失败断言，方便直接在 CI 日志里定位。
    grep -m10 -E '\[FAIL\]|✗ ' "${out}" | sed 's/^/    /'
    echo "    （完整输出：${out}）"
    fail=1
    continue
  fi
  # 1. 退出码
  if [ "${code}" -ne 0 ]; then
    echo "✗ ${t}：退出码 ${code}"
    tail -5 "${out}" | sed 's/^/    /'
    fail=1
    continue
  fi
  # 汇总行
  summary="$(grep -E "${MARKER}" "${out}" | tail -1 | sed 's/^[[:space:]]*//')"
  echo "✓ ${t}：${summary}"
done

echo "───────────────────────────────────────────────"
if [ "${fail}" -eq 0 ]; then
  echo "全部通过 ✅"
else
  echo "有失败项 ❌"
fi
exit "${fail}"
