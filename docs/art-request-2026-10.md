# 美術需求（2026-10-08 整理）

> **狀態：2026-10-08 已交付（`arts/art_2026-10-08/`），29 張都已合併進 `assets/art/` 並接上 `data/art.json`。**

1.7 本身不需要新圖；這份整理 1.6、1.7 試玩時提到或發現可以補的圖，一次出。規則同 `assets/README.md`：PNG、1x 尺寸（另附 `_4x` 可選）、像素風、透明背景（背景圖除外）、顯示時用 Nearest 過濾。檔名都是 `assets/art/` 底下的路徑。

程式都已經接好（2026-10-08）：檔案放進去、在 `data/art.json` 加一行對應就會用到；沒有圖時照舊（沿用目前的圖或文字），不會壞掉。各項要加的 `art.json` 鍵寫在「接法」欄。

## 一、使用者提過的

### 1. 大火後的焦黑地形（QA-72，優先）

大火後區域背景已經是焦黑的，但探索、狩獵、遭遇畫面的地形背景還是綠的。參考現有的地形圖與 `backgrounds/regions/forest_*_burned.png` 的色調：燒黑的樹幹、灰燼、地面焦黑，零星殘火或煙可有可無。

| 檔案 | 尺寸 | 內容 | 接法（`art.json` → `terrain_backgrounds`） |
| --- | --- | --- | --- |
| `backgrounds/terrain/stream_burned.png` | 320×180 | 溪谷，兩岸燒黑 | `"stream@burned"` |
| `backgrounds/terrain/dense_forest_burned.png` | 320×180 | 深林，只剩焦黑的樹幹 | `"dense_forest@burned"` |
| `backgrounds/terrain/forest_edge_burned.png` | 320×180 | 林緣草地，草燒光 | `"forest_edge@burned"`、`"clearing@burned"`（空地共用） |
| `backgrounds/terrain/fallen_logs_burned.png` | 320×180 | 倒木區，倒木燒焦 | `"fallen_logs@burned"` |

燃燒中與焦黑期（約 12 天）用這組，之後的「新綠」期回到一般的圖。

### 2. 成年狼的外貌更明顯（2026-10-08 試玩清單備註）

「成年跟次成年看不太出差異，成年跟老年有明顯差異。」成年應該體型更大、胸口更厚、毛色更深更有層次。另外成年、老年目前**沒有戰鬥姿勢**，戰鬥時會用回次成年的圖，這次一起補。

替換（同檔名、同尺寸，直接覆蓋）：

| 檔案 | 尺寸 | 內容 |
| --- | --- | --- |
| `sprites/wolf/wolf_adult_sheet.png` | 192×128（每格 48×32，4 列：待機、走路、嚎叫、趴下，各 4 格） | 成年狼，和次成年明顯不同 |
| `sprites/wolf/wolf_adult_{stalk,pounce,eat,sleep}.png` | 同現有檔案 | 同上的成年版 |

新增（接法：`art.json` → `wolf.stages.adult.poses` 與 `wolf.stages.elder.poses` 各加 5 個鍵，鍵名就是姿勢名）：

| 檔案 | 尺寸 | 內容 |
| --- | --- | --- |
| `sprites/wolf/wolf_adult_{threaten,bite,dodge,hurt,submit}.png` | 約 55×34（參考 `wolf_bite.png` 等次成年版） | 成年狼的威嚇、撲咬、閃避、受傷、示弱 |
| `sprites/wolf/wolf_elder_{threaten,bite,dodge,hurt,submit}.png` | 同上 | 老年狼（口鼻、背部灰白）的同樣五個姿勢 |

### 3. 「體力不支」狀態圖示（1.7）

| 檔案 | 尺寸 | 內容 | 接法（`art.json` → `icons`） |
| --- | --- | --- | --- |
| `icons/status_exhausted.png` | 16×16 | 體力耗盡，例如垂頭吐舌喘氣的狼頭、或空掉的閃電（體力圖示 `stat_stamina.png` 是閃電） | `"status.exhausted"` |

有圖之後，頂部的紅字「體力不支」換成圖示（滑鼠提示不變）。

## 二、試玩時發現、建議一起補的

### 4. 森林的冬季背景

森林只有北部有冬季區域背景，東部、南部、西部冬天主畫面還是綠草地；森林的四種地形也都沒有冬季版（苔原的地形都有）。

| 檔案 | 尺寸 | 接法 |
| --- | --- | --- |
| `backgrounds/regions/forest_{east,south,west}_winter.png` | 640×360 | `region_backgrounds` 加 `"forest_east@winter"` 等（參考 `forest_north_winter.png`） |
| `backgrounds/terrain/{stream,dense_forest,forest_edge,fallen_logs}_winter.png` | 320×180 | `terrain_backgrounds` 加 `"stream@winter"` 等；溪流結冰、林地積雪 |

### 5. 圍攻狼獾的事件圖（可選）

`events/wolverine_mobbed.png` 目前 150×20，在事件畫面上很小（試玩清單當時的備註「看要不要放大」）。建議重畫成和其他事件圖接近的大小，例如 112×56（同 `blizzard_sign.png`）：兩隻淺色苔原狼左右包夾中間的深色狼獾。同檔名覆蓋即可。

### 6. 空地的地形（可選，低）

「空地」目前和林緣草地共用 `forest_edge.png`。要區分的話加 `backgrounds/terrain/clearing.png`（320×180，林中的一片開闊草地），`terrain_backgrounds` 的 `"clearing"` 改指到它。

## 數量

| 項目 | 張數 |
| --- | --- |
| 1. 焦黑地形 | 4 |
| 2. 成年狼外貌（替換 5、新增 10） | 15 |
| 3. 體力不支圖示 | 1 |
| 4. 森林冬季（區域 3、地形 4） | 7 |
| 5. 圍攻狼獾（可選） | 1 |
| 6. 空地（可選） | 1 |
| 合計 | 29（必要 27） |

交付方式同之前：放進 `arts/`（附 `_1x`／`_4x` 與預覽圖），或直接照上面的路徑放進 `assets/art/`。Claude Code 收到後會接上 `art.json`、確認尺寸並截圖檢查。
