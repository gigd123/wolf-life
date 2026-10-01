# wolf-life 專案規則

## 資料隔離（重要）

這個專案（`wolf-life`，狼之一生養成遊戲）絕對不能使用、讀取、參考任何與使用者在**台達電（Delta）**的工作專案有關的資料或檔案，尤其是 **pcap** 封包擷取檔。

- 不要在這個專案目錄下讀取、搜尋、複製、引用任何台達電相關的原始碼、文件、資料檔或 pcap 檔案。
- 若在這台機器上其他位置發現疑似台達電工作內容（例如檔名、路徑、註解中出現 Delta、台達電或相關產品代號），不要將其內容帶入這個專案，也不要在這個專案的檔案中提及其細節。
- 這個專案應該完全獨立於使用者的工作內容，只處理遊戲設計與開發本身。

## Godot 檢查

- 修改 `.gd` / `.tscn` / `project.godot` 後，執行 `bash tools/godot_check.sh` 確認匯入、編譯、主場景啟動都沒有錯誤，再 commit。
- 雲端 session 會由 SessionStart hook（`tools/install_godot.sh`）自動安裝 Godot headless；本機請設定 `GODOT=<Godot console 執行檔路徑>`。
- 雲端沒有畫面，UI 排版與視覺效果需由使用者在本機 Godot 編輯器確認。
