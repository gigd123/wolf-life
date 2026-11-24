# 給 run_sim.sh、godot_check.sh、ui_check.sh 用 source 載入：把 user:// 指到暫存資料夾，測試不會碰到玩家的存檔、設定與試玩紀錄
# （2026-11-24：本機跑規則測試時，new_game 的自動存檔蓋掉了使用者的 save.json）。跑完刪掉；想留下來看就設 WOLF_USERDATA=<資料夾>。
if [ -n "${WOLF_USERDATA:-}" ]; then
  _WOLF_UD="$WOLF_USERDATA"
  mkdir -p "$_WOLF_UD"
else
  _WOLF_UD="$(mktemp -d)" || exit 2
  trap 'rm -rf "$_WOLF_UD"' EXIT
fi
if command -v cygpath >/dev/null 2>&1; then
  export APPDATA="$(cygpath -w "$_WOLF_UD")" # Windows
else
  export XDG_DATA_HOME="$_WOLF_UD" # Linux
fi
