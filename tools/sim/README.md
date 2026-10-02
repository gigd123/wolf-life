# 模擬腳本

雲端沒有畫面、無法實際試玩，所以 Phase 1.5 的數值與機率都先用這些腳本驗證。它們只透過 `GameState` 操作遊戲，不會修改存檔以外的任何東西（每次執行會覆寫目前的自動存檔，本機執行前請注意）。

| 腳本 | 驗證什麼 | 對應規格 |
| --- | --- | --- |
| `balance_sim` | 三種狩獵策略（只獵小型獵物／什麼都獵／以鹿為主）跑 N 天的飽食度節奏、各深度狩獵成功率、搶食次數、能力成長 | 數值壓力調整、試玩指南的「數值快測」 |
| `hunt_outcomes` | 每種獵物各狩獵 400 次的反應分布與成功率，並檢查文字是否都有翻譯 | 獵物反應、狩獵深度分級 |
| `explore_distribution` | 各區域的發現種類、來源、線索類型、新鮮度；「什麼都沒發現」不超過 15% | 探索系統 |
| `event_frequency` | 主動事件每天的次數、被驅趕、暴雨對線索的影響 | 主動事件、暴雨 |
| `combat_sim` | 三種能力的狼（次成年、成年、巔峰）× 對手（灰熊搶食／遭遇、母熊、幼熊、狐狸、陌生灰狼壯年／護地盤／7 歲）× 打法（一直撲咬、猛撲、先威嚇、瀕危也不退），統計勝、撤退、戰死、受傷、重傷與回合數 | 1.6 戰鬥模式、勝算基準、戰鬥中的死亡 |
| `growth_sim` | 七種玩法（平均、偏追獵、偏強攻、偏潛伏、偏謹慎、只吃小獵物、以鹿為主）各 RUNS 隻狼的次成年期成長與成年時的巔峰上限；`ADULT=1` 時再玩到 5 歲，看各年齡離上限多遠。機器人是 `scripts/core/AutoPlayer.gd` | 1.6 成長系統、潛力結算 |

## 執行

```
bash tools/run_sim.sh balance_sim 20 60   # 20 天 × 60 次
bash tools/run_sim.sh hunt_outcomes
bash tools/run_sim.sh explore_distribution
bash tools/run_sim.sh event_frequency
bash tools/run_sim.sh growth_sim 0 20          # 每種玩法 20 隻
bash tools/run_sim.sh combat_sim 0 400         # 每格 400 場
ADULT=1 bash tools/run_sim.sh growth_sim 0 8  # 再玩到 5 歲（較慢）
```

本機請先設定 `GODOT=<Godot console 執行檔路徑>`。數值調整後重跑，對照 `docs/progress.md` 裡的「步驟 N 後的模擬」紀錄。

## 寫新腳本時注意

- 腳本以 `-s` 單獨執行時，autoload 還沒載入就會先編譯，所以不能直接寫 `HuntSystem.Stage.DONE` 這類 class_name 引用，否則會編譯失敗。狩獵階段請用數字（`DONE = 5`、結果 `SUCCESS = 1`），或透過 `GameState` 的函式取得。
- 機器人每階段選成功率最高的選項，所以成功率會比真人玩家高，只適合看相對變化。
