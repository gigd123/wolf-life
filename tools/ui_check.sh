#!/usr/bin/env bash
# UI 檢查：xvfb 下實際開遊戲隨機遊玩，找原始翻譯鍵、沒替換的佔位、超出 640×360 的元件，並截圖（說明見 tools/ui_check.gd）。
# 用法：bash tools/ui_check.sh [種子] [每個巢穴的步數]；截圖在 $UI_CHECK_OUT（預設 /tmp/ui_check/）。約 5～10 分鐘。
# 有問題時回傳 1。
set -u
cd "$(dirname "$0")/.."
G="${GODOT:-$(ls $HOME/.cache/godot/*/godot 2>/dev/null | tail -1)}"
export UI_CHECK_SEED="${1:-7}" UI_CHECK_STEPS="${2:-400}" UI_CHECK_OUT="${UI_CHECK_OUT:-/tmp/ui_check/}"
rm -rf "$UI_CHECK_OUT"
BEFORE=$(ls playtest_logs 2>/dev/null)
LOG=$(mktemp)
xvfb-run -a -s "-screen 0 1920x1080x24" "$G" --path . --rendering-driver opengl3 -s tools/ui_check.gd > "$LOG" 2>&1
# 狼死亡時遊戲會存試玩紀錄；測試產生的紀錄不留
for f in $(ls playtest_logs 2>/dev/null); do echo "$BEFORE" | grep -qx "$f" || rm -f "playtest_logs/$f"; done
grep -E 'SCRIPT ERROR' -A2 "$LOG"
grep -E '^(ISSUE|UI 檢查)' "$LOG"
grep -q '^ISSUE ' "$LOG" && exit 1 || exit 0
