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
#  ⚠️ 四条判据（只靠退出码是不够的，2026-10-10 审查 R07；计数判据 B-R01，2026-10-11）：
#     ① 退出码非 0 ⇒ 失败（**除非**是下面已知的引擎收尾异常）；
#     ② 输出里出现 `SCRIPT ERROR` / `Parse Error` ⇒ 失败；
#     ③ 输出里**必须**出现完成标记（`RESULT passed=` / `结果：` / `VERIFY_DONE`）
#        —— 防"脚本没跑完就退出"被当成通过。
#     ④ 输出里的**失败计数**（`failed=N` / `N 项失败` / `失败项 N`）> 0 ⇒ 失败。
#        ★ 这是最终判据：verify_run 引擎收尾 SIGSEGV 会把 quit(1) 吞成 139，
#          退出码在这一套上完全不可信 —— 断言失败与否只能看数字。
#
#  ⚠️ 已知例外：`verify_run` 在**引擎收尾**时 SIGSEGV（退出码 139，结果其实完整）。
#     对它只认 ②③④ 三条，且 139 例外**要求**输出里能解析出失败计数（解析不出 = 判失败）
#     —— 这是长期已知问题，见 MEMORY「工程口径」。
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
  # ④ 失败计数（B-R01：139 会吞掉 quit(1)，数字才是最终判据）
  #    取输出里**最后一个**计数（完成标记行就是最后一行，中间过程行不算数）
  fnum="$(grep -oE 'failed=[0-9]+|失败项[：: ]*[0-9]+|[0-9]+[ ]*项失败' "${out}" \
          | grep -oE '[0-9]+' | tail -1)"
  if [ -n "${fnum}" ] && [ "${fnum}" -gt 0 ]; then
    echo "✗ ${t}：输出判据 failed=${fnum}（退出码 ${code}）"
    grep -E 'failed=[0-9]+|失败项|项失败' "${out}" | tail -3 | sed 's/^/    /'
    # ★ 2026-10-12：直接把**失败的断言**打出来 —— 否则在 CI 日志里只看到一个数字，
    #   还得去翻 runner 临时目录里的 per-suite log。最多 10 条，够定位。
    grep -m10 -E '\[FAIL\]|✗ ' "${out}" | sed 's/^/    /'
    echo "    （完整输出：${out}）"
    fail=1
    continue
  fi
  # ① 退出码（verify_run 的 139 例外：必须能解析出失败计数且为 0 才放行）
  if [ "${code}" -ne 0 ]; then
    if [ "${t}" = "verify_run" ] && [ "${code}" -eq 139 ] && [ -n "${fnum}" ]; then
      echo "⚠ ${t}：退出码 139（引擎收尾 SIGSEGV，已知）—— 按失败计数判（failed=${fnum}）"
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
