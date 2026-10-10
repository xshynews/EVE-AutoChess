#!/usr/bin/env bash
# =============================================================================
#  统一跑全部无头验收（审查：README 写了"无头验收"，但仓库里没有统一入口）
# =============================================================================
#
#  用法：
#     tools/run_verifies.sh                 # 用下面的默认引擎路径
#     GODOT_BIN=/path/to/godot tools/run_verifies.sh
#     tools/run_verifies.sh /path/to/godot /path/to/project
#
#  退出码：0 = 全部通过；1 = 至少一套失败（可直接给 CI 用）。
#
#  ⚠️ 三条判据（只靠退出码是不够的，2026-10-10 审查 R07）：
#     ① 退出码非 0 ⇒ 失败（**除非**是下面已知的引擎收尾异常）；
#     ② 输出里出现 `SCRIPT ERROR` / `Parse Error` ⇒ 失败；
#     ③ 输出里**必须**出现完成标记（`RESULT passed=` / `结果：` / `VERIFY_DONE`）
#        —— 防"脚本没跑完就退出"被当成通过。
#
#  ⚠️ 已知例外：`verify_run` 在**引擎收尾**时 SIGSEGV（退出码 139，结果其实完整）。
#     对它只认 ②③ 两条 —— 这是长期已知问题，见 MEMORY「工程口径」。
# =============================================================================
set -u

GODOT="${1:-${GODOT_BIN:-C:/godot/Godot_v4.7.2-stable_win64_console.exe}}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJ="${2:-$(cd "${SCRIPT_DIR}/.." && pwd)}"
QUIT_AFTER="${QUIT_AFTER:-9000}"

# 全套（覆盖：数据源 / 主流程 / UI / 卡牌 / 存档 / 审查修复项）
#
# ⚠️ 只收**有通过/失败契约**的脚本（它们都会打完成标记）。
#    诊断型脚本（`verify_battle` / `verify_background` / `verify_camera`、
#    以及 `probe_*`）是"跑一遍给人看数"，没有判定语义 ⇒ ⛔ 别放进来。
SUITE=(
  verify_i18n
  verify_data_source
  verify_ship_table
  verify_ship_assets
  verify_run
  verify_run_save
  verify_review_fixes
  verify_menu
  verify_ui_scale
  verify_resolution
  verify_window
  verify_ddz
  verify_intro
  verify_audio
)

# 完成标记（任何一条命中即视为"跑完了"）
MARKER='RESULT passed=|结果：|VERIFY_DONE|全部通过|表结构无问题'

LOG_DIR="${TMPDIR:-/tmp}/eve_verify_logs"
mkdir -p "${LOG_DIR}"

fail=0
for t in "${SUITE[@]}"; do
  out="${LOG_DIR}/${t}.log"
  "${GODOT}" --headless --path "${PROJ}" --quit-after "${QUIT_AFTER}" \
      "res://tools/${t}.tscn" >"${out}" 2>&1
  code=$?

  # ② 脚本级错误一律失败
  if grep -qE "SCRIPT ERROR|Parse Error|Failed to load script" "${out}"; then
    echo "✗ ${t}：出现脚本错误"
    grep -m3 -E "SCRIPT ERROR|Parse Error|Failed to load script" "${out}" | sed 's/^/    /'
    fail=1
    continue
  fi
  # ③ 完成标记
  if ! grep -qE "${MARKER}" "${out}"; then
    echo "✗ ${t}：**没有完成标记**（进程退出码 ${code}）—— 可能没跑完"
    tail -5 "${out}" | sed 's/^/    /'
    fail=1
    continue
  fi
  # ① 退出码（verify_run 的 139 例外）
  if [ "${code}" -ne 0 ]; then
    if [ "${t}" = "verify_run" ] && [ "${code}" -eq 139 ]; then
      echo "⚠ ${t}：退出码 139（引擎收尾 SIGSEGV，已知）—— 按结果判"
    else
      echo "✗ ${t}：退出码 ${code}"
      fail=1
      continue
    fi
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
