# 素材規格

《狼之一生》目前使用佔位素材。換正式素材時，維持相同的檔名、尺寸與格式，程式就不需要修改。

## 共通規則

- 基準解析度 640×360，視窗以整數倍放大（1920×1080 為 3 倍），`project.godot` 的縮放模式為 `canvas_items`。
- 像素圖一律用 PNG，透明背景（背景圖除外）。
- 貼圖過濾必須是 **Nearest**，否則放大後會模糊。目前沒有設定專案預設值，由使用貼圖的節點各自設定：`texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST`。新增顯示像素圖的節點時記得一起設定。
- 時段光線（清晨、黃昏、深夜）由程式調色，暴雨由粒子效果處理，不需要另外的圖。

## 檔名規則

- 全部小寫英文，單字以底線分隔。
- 類別前綴：`wolf_`（灰狼動作）、`bg_`（背景）、`clue_`（線索圖示）、`bgm_`（背景音樂）、`sfx_`（音效）；動物直接用物種名稱，例如 `deer_doe`、`fox`。
- 每張像素圖都有兩種倍率：`_1x.png` 是原始像素尺寸，`_4x.png` 是 4 倍放大的預覽或高解析度版本。程式以 `_1x` 為準。

## 目前使用中的素材

| 檔案 | 尺寸 | 用途 |
| --- | --- | --- |
| `sprites/wolf_spritesheet.png` | 192×96，4 欄 × 3 列，每格 48×32 | 灰狼動畫。第 1 列是待機（主畫面頭像、一生回顧）；第 2、3 列目前沒有使用 |
| `audio/bgm_meadow_loop.wav` | 44.1 kHz、單聲道、16 bit，約 23 秒 | 背景音樂，循環播放 |
| `audio/sfx_bite.wav` | 同上，約 0.8 秒 | 撲咬 |
| `audio/sfx_wolf_howl.wav` | 同上，約 5.4 秒 | 狼嚎（進入遊戲時播放） |
| `audio/sfx_level_up.wav` | 同上，約 1.7 秒 | 素質成長 |

區域地圖圖塊、獵物與灰熊的遭遇圖、狀態圖示（受傷、中毒、飢餓）目前由 `scripts/core/PixelArt.gd` 以程式即時生成，沒有圖檔。

## Phase 1.5 佔位素材

規格位置是 `assets/art/phase1.5/`。目前檔案還在專案根目錄的 `arts/phase1.5_art/`，會在美術接入的步驟搬過來。以下尺寸都是 `_1x`。

| 類別 | 檔案 | 尺寸 |
| --- | --- | --- |
| 灰狼動作 | `wolf_stalk`（伏低潛近）、`wolf_pounce`（撲擊）、`wolf_eat`（進食）、`wolf_sleep`（睡覺） | 58×20、55×34、52×23、51×18 |
| 陌生灰狼 | `wolf_stranger` | 46×28 |
| 灰熊（遠距） | `bear_distant` | 43×24 |
| 白尾鹿 | `deer_buck`（公鹿）、`deer_doe`（母鹿）、`deer_fawn`（幼鹿） | 51×61、51×52、31×32 |
| 小型獵物 | `hare`（野兔）、`fox`（狐狸） | 18×18、44×24 |
| 背景 | `bg_stream_valley`、`bg_deep_forest`、`bg_forest_edge_meadow`、`bg_fallen_log_slope` | 320×180，下方約三分之一是地面 |
| 線索圖示 | `clue_track`（足跡）、`clue_scent`（氣味）、`clue_sound`（聲音）、`clue_sight`（目擊）、`clue_claw`（爪痕）、`clue_unknown`（未知） | 16×16 |
| 風向圖示 | `wind` | 16×16 |

背景檔名依地形命名，和區域的對應寫在資料檔，不改檔名：

| 區域 | 背景 |
| --- | --- |
| 森林東部 `forest_east` | `bg_stream_valley` |
| 森林北部 `forest_north` | `bg_deep_forest` |
| 森林南部 `forest_south` | `bg_forest_edge_meadow` |
| 森林西部 `forest_west` | `bg_fallen_log_slope` |

## 尺寸參考

- 小型動物 16～24 px，狼與鹿 32～48 px（狼一格約 48×32；伏低、睡覺等姿勢會比較扁），灰熊 48～64 px。
- 背景 320×180，放大 2 倍填滿 640×360 的畫面。
- 圖示 16×16。

## 另一套素材

`arts/files/` 裡有另一套素材：640×360 的森林背景（含冬季北部）與 `wolf_assets/` 分層素材。這套和 Phase 1.5 佔位素材擇一使用，由使用者比較後決定；決定前先用 Phase 1.5 那套。
