# 美術交付（對應 docs/art-request-2026-10.md）

29 張全部完成（含 2 張可選）。全部是 1x、照需求清單的路徑與檔名；未附 `_4x`。

佔位性質：由現有素材程式改色、變形而成（風格與現有圖一致，但不是手繪正式稿）。

## 覆蓋（同檔名、同尺寸）
- `sprites/wolf/wolf_adult_sheet.png`、`wolf_adult_{stalk,pounce,eat,sleep}.png`：成年狼重畫。毛色改為偏暖的深灰褐，背上有深色鞍狀斑、腹部與胸口米白、四腳下段淺褐；軀幹加厚 1～2 px，胸口更深。
- `events/wolverine_mobbed.png`：改為 112×56，兩隻苔原狼左右包夾狼獾，背景有雪丘與雲杉。

## 新增與 art.json 對應
| 檔案 | 鍵 |
| --- | --- |
| `backgrounds/terrain/stream_burned.png` | `terrain_backgrounds["stream@burned"]` |
| `backgrounds/terrain/dense_forest_burned.png` | `terrain_backgrounds["dense_forest@burned"]` |
| `backgrounds/terrain/forest_edge_burned.png` | `terrain_backgrounds["forest_edge@burned"]`、`["clearing@burned"]` |
| `backgrounds/terrain/fallen_logs_burned.png` | `terrain_backgrounds["fallen_logs@burned"]` |
| `sprites/wolf/wolf_adult_{threaten,bite,dodge,hurt,submit}.png` | `wolf.stages.adult.poses.<姿勢名>` |
| `sprites/wolf/wolf_elder_{threaten,bite,dodge,hurt,submit}.png` | `wolf.stages.elder.poses.<姿勢名>` |
| `icons/status_exhausted.png` | `icons["status.exhausted"]`（垂頭吐舌的狼頭） |
| `backgrounds/regions/forest_{east,south,west}_winter.png` | `region_backgrounds["forest_east@winter"]` 等 |
| `backgrounds/terrain/{stream,dense_forest,forest_edge,fallen_logs}_winter.png` | `terrain_backgrounds["stream@winter"]` 等 |
| `backgrounds/terrain/clearing.png` | `terrain_backgrounds["clearing"]` 改指到它 |

## 備註
- 成年的單張姿勢比原檔**高 2 px**（stalk 58×22、pounce 55×36、eat 52×25、sleep 51×20），是加厚軀幹的結果；原圖已經頂到邊，無法在原尺寸內做出更壯的體型。sheet 維持 192×128。顯示時請以腳底對齊。
- `forest_edge_winter.png` 也可以給 `"clearing@winter"` 共用；空地沒有另做冬季版與焦黑版。
- 戰鬥姿勢的尺寸跟著來源姿勢（威嚇約 58×24、撲咬 55×34 等），沒有統一成 55×34，請以實際尺寸對齊腳底。
- 撲咬是撲擊姿勢加上張開的紅色口部。
