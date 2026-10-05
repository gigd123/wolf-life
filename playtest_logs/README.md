# 試玩紀錄

在 Godot 編輯器裡遊玩、狼死亡時（或除錯選單「匯出試玩紀錄」），會自動在這裡存一份 `wolf_<日期時間>.json`。
試玩後把這個資料夾的新檔案 commit、push，Claude Code 同步後就能讀，用來查戰鬥經過（`life_log.recent_combats`）、
最後看到的訊息（`life_log.recent_messages`）與一生的統計。

這個資料夾有 `.gdignore`，Godot 不會匯入裡面的檔案。
