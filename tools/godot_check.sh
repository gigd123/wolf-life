#!/usr/bin/env bash
# Godot headless 檢查：匯入資源 → 逐一檢查 GDScript 語法 → 跑主場景幾秒看有沒有執行期錯誤。
# 用法：bash tools/godot_check.sh
# 可用環境變數 GODOT 指定執行檔（例如本機 Windows 的 Godot_v4.7.2-stable_win64_console.exe）。
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

GODOT_BIN="${GODOT:-}"
if [ -z "$GODOT_BIN" ]; then
  if command -v godot >/dev/null 2>&1; then
    GODOT_BIN="godot"
  else
    GODOT_BIN="$(ls "$HOME"/.cache/godot/*/godot 2>/dev/null | tail -n 1)"
  fi
fi
if [ -z "$GODOT_BIN" ]; then
  echo "找不到 Godot。雲端請先執行 tools/install_godot.sh，本機請設定 GODOT=<執行檔路徑>" >&2
  exit 2
fi

ERR_PATTERN='SCRIPT_CHECK_FAIL|SCRIPT ERROR|Parse Error|Compile Error|ERROR:|Failed to load script'
LOG="$(mktemp)"
fail=0

run() { "$GODOT_BIN" --headless --path . "$@" >"$LOG" 2>&1; }
report() {
  if grep -qE "$ERR_PATTERN" "$LOG"; then
    echo "  ✗ $1"
    grep -E -A2 "$ERR_PATTERN" "$LOG" | sed 's/^/    /'
    fail=1
  else
    echo "  ✓ $1"
  fi
}

echo "== 1/3 匯入資源"
run --import
report "import"

echo "== 2/3 GDScript 編譯檢查（含 autoload）"
run res://tools/ScriptCheck.tscn
code=$?
grep -E "SCRIPT_CHECK_DONE" "$LOG" | sed "s/^/  /"
if [ "$code" -ne 0 ] || ! grep -q SCRIPT_CHECK_DONE "$LOG"; then fail=1; fi
report "compile all scripts"

echo "== 3/3 主場景冒煙測試（約 5 秒）"
run --quit-after 300
report "run main scene"

rm -f "$LOG"
if [ "$fail" -ne 0 ]; then
  echo "檢查失敗" >&2
  exit 1
fi
echo "全部通過"
