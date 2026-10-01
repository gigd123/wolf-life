#!/usr/bin/env bash
# 執行 tools/sim/ 的模擬腳本（headless，不開視窗）。
# 用法：bash tools/run_sim.sh <腳本名稱> [DAYS] [RUNS]
#   bash tools/run_sim.sh balance_sim 20 60
#   bash tools/run_sim.sh hunt_outcomes
# 可用環境變數 GODOT 指定執行檔（同 tools/godot_check.sh）。
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

NAME="${1:-}"
if [ -z "$NAME" ] || [ ! -f "tools/sim/$NAME.gd" ]; then
  echo "用法：bash tools/run_sim.sh <腳本名稱> [DAYS] [RUNS]" >&2
  echo "可用的腳本：" >&2
  ls tools/sim/*.gd | xargs -n1 basename | sed 's/\.gd$//; s/^/  /' >&2
  exit 2
fi

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

"$GODOT_BIN" --headless --path . --import >/dev/null 2>&1
# 過濾掉音效驅動、資源洩漏等與模擬無關的訊息
DAYS="${2:-}" RUNS="${3:-}" "$GODOT_BIN" --headless --path . -s "res://tools/sim/$NAME.gd" 2>&1 \
  | grep -vE '^Godot Engine|^$|ALSA|audio|^ +at: |WARNING|leaked|resources still in use|ERR_CANT_OPEN'
