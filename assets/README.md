# 素材規格

《狼之一生》目前使用佔位素材。換正式素材時，維持相同的檔名、尺寸與格式，或只改 `data/art.json` 的路徑，程式就不需要修改。

## 共通規則

- 基準解析度 640×360，視窗以整數倍放大（1920×1080 為 3 倍），`project.godot` 的縮放模式為 `canvas_items`。
- 像素圖一律用 PNG，透明背景（背景圖除外）。
- 貼圖過濾必須是 **Nearest**，否則放大後會模糊。目前沒有設定專案預設值，由使用貼圖的節點各自設定：`texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST`。新增顯示像素圖的節點時記得一起設定。
- 時段光線（清晨、黃昏、深夜）由程式調色（`data/art.json` 的 `period_tint`），暴雨由粒子效果處理，不需要另外的圖。

## 原始檔與使用中的檔案

- `arts/`：美術交付的原始檔，保留不動（含 `_4x` 版本與預覽圖）。
  - `arts/files/wolf_assets/`：主要的一套（動物動畫、區域背景、圖示）。
  - `arts/phase1.5_art/`：2026-10-01 補充的一套（雄鹿／母鹿、遠距灰熊、陌生灰狼、灰狼動作、地形背景、線索圖示）。
- `assets/art/`：程式實際讀取的檔案，只放 1x，依用途分類並改成好懂的檔名。對應關係寫在 `data/art.json`，程式透過 `scripts/ui/ArtLibrary.gd` 讀取；找不到圖時會退回 `PixelArt.gd` 程式生成的佔位圖。

## assets/art/ 目錄

| 路徑 | 內容 | 來源 | 尺寸 |
| --- | --- | --- | --- |
| `backgrounds/regions/forest_{east,north,south,west}.png` | 主畫面的區域背景 | `wolf_assets/backgrounds/*_640x360` | 640×360 |
| `backgrounds/regions/forest_north_winter.png` | 北部冬季背景 | 同上 | 640×360 |
| `backgrounds/terrain/{stream,dense_forest,forest_edge,fallen_logs}.png` | 狩獵、遭遇畫面依地形的背景（空地共用林緣） | `phase1.5_art/bg_*_1x`（溪谷、深林、林緣草地、倒木坡） | 320×180，放大 2 倍 |
| `sprites/wolf/wolf_sheet.png` | 主角灰狼：4 欄 × 4 列，列 = 待機、走路、嚎叫、倒下 | `wolf_assets/sprites/wolf_spritesheet_4rows` | 192×128，每格 48×32 |
| `sprites/wolf/wolf_{stalk,pounce,eat,sleep}.png` | 灰狼單張姿勢：潛近、撲擊、進食、睡覺 | `phase1.5_art/wolf_*_1x` | 58×20、55×34、52×23、51×18 |
| `sprites/wolf/wolf_stranger.png` | 陌生灰狼 | `phase1.5_art/wolf_stranger_1x` | 46×28 |
| `sprites/animals/{deer_fawn,hare_adult,hare_young,fox_adult,fox_kit}_sheet.png` | 動物動畫：4 欄 × 2 列，列 = 待機、跑動 | `wolf_assets/sprites/*` | 192×64，每格 48×32 |
| `sprites/animals/{bear_adult,bear_cub}_sheet.png` | 灰熊：4 欄 × 3 列，列 = 待機、走路、攻擊 | `wolf_assets/sprites/*` | 192×96，每格 48×32 |
| `sprites/animals/deer_buck.png`、`deer_doe.png` | 白尾鹿雄鹿、母鹿 | `phase1.5_art/*_1x` | 51×61、51×52 |
| `sprites/animals/bear_distant.png` | 遠距目擊的灰熊 | `phase1.5_art/bear_distant_1x` | 43×24 |
| `icons/status_{injury,poison,hunger}.png` | 狀態圖示 | `wolf_assets/icons` | 16×16 |
| `icons/{berry,mushroom,honeycomb,den_marker}.png` | 採集物、巢穴標記 | `wolf_assets/icons` | 16×16 |
| `icons/clue_{claw,scent,sight,sound,track,unknown}.png`、`wind.png` | 線索與風向圖示 | `phase1.5_art/*_1x` | 16×16 |

## Phase 1.6 佔位素材

2026-10-02 加入 45 個 1.6 佔位素材，原始壓縮檔在 `arts/phase1.6_art.zip`，預覽圖 `arts/phase1.6_art_preview.png`，清單與用途見 `docs/art_phase1.6.md`。依 1.6 各步驟需要再寫進 `data/art.json`。第 1 步的項目已接上（`art.json` 的 `icons` 鍵 `stat.*`、`cost.*`、`tendency.*`，與 `season_backgrounds`）。

| 路徑 | 內容 | 1.6 步驟 |
| --- | --- | --- |
| `icons/stat_{speed,strength,skill,perception,health,stamina}.png` | 能力圖示 | 1（代價列、睡覺結算）**已接上** |
| `icons/cost_{turns,injury_risk}.png` | 代價列：多花回合、受傷風險 | 1 **已接上** |
| `icons/tendency_{stealth,pursuit,assault,cautious}.png` | 狩獵傾向圖示 | 1（頂部傾向按鈕、說明面板）**已接上** |
| `backgrounds/seasons/season_{spring,summer,autumn,winter}.png` | 季節卡片背景，640×360 | 1 **已接上** |
| `sprites/wolf/wolf_adult_*`、`wolf_elder_*` | 成年、老年狼（sheet 格式同 `wolf_sheet.png`，加單張姿勢） | 2 |
| `sprites/wolf/wolf_{threaten,bite,dodge,hurt,submit}.png` | 狼的戰鬥姿勢 | 3 |
| `sprites/wolf/wolf_stranger_sheet.png`、`wolf_stranger_*` | 陌生灰狼（黑狼）的動畫、跟蹤、撲擊與戰鬥姿勢 | 4 |
| `backgrounds/regions/forest_*_burned.png` | 燒毀後的區域背景，640×360（`art.json` 的 `forest_east@burned`） | 5 **已接上** |
| `icons/clue_smoke.png`、`icons/status_burn.png` | 煙味線索、燒傷狀態 | 5（燒傷狀態已接上；煙味線索目前沒有用到，大火徵兆是事件畫面） |

2026-10-02 再加入 41 個苔原佔位素材（第 6 步，含 1.5 遺留的獵物屍體與區域小圖），原始壓縮檔 `arts/tundra.zip`，預覽圖 `arts/tundra_preview.png`，清單同樣在 `docs/art_phase1.6.md`。6a 已接上：苔原四區的區域背景（夏、冬）、五種地形背景（夏、冬，`terrain@winter`）、八張地圖按鈕的區域小圖（`region_tile.<id>`，森林四區也一起換掉程式生成的小圖）、嚴寒圖示。動物與線索圖示在 6b、6c 接上。

| 路徑 | 內容 | 步驟 |
| --- | --- | --- |
| `backgrounds/regions/tundra_{south,central,east,north}.png`、`*_winter.png` | 苔原四區的區域背景（夏季、冬季），640×360 | 6 |
| `backgrounds/terrain/{treeline,open_tundra,river_willow,rocky,esker}.png`、`*_winter.png` | 苔原地形背景（林線、開闊苔原、河谷柳叢、岩石區、沙脊），320×180；森林的地形背景目前不分季節 | 6 |
| `sprites/animals/snowhare_{summer,winter}_sheet.png`、`caribou_sheet.png` | 雪兔（夏、冬毛色）、北美馴鹿，4 欄 × 2 列 | 6 |
| `sprites/animals/caribou_herd.png`、`moose.png`、`moose_{run,kick,hurt}.png` | 馴鹿群、駝鹿（單張，76×76） | 6 |
| `icons/clue_track_{snowhare,caribou}.png`、`clue_antler_rub.png`、`status_cold.png` | 苔原的線索與嚴寒狀態 | 6 |
| `sprites/animals/carcass_{deer,caribou,moose}.png` | 獵物屍體（進食畫面） | 白尾鹿可隨時接上；其他 6 |
| `icons/region_tile_{forest_*,tundra_*}.png` | 地圖按鈕的區域小圖，18×18（取代程式生成的小圖） | 森林可隨時接上；苔原 6 |

## 顯示方式

- 主畫面：區域背景依季節換圖、依時段調色，上面蓋一層 45% 的暗色讓文字好讀。
- 遭遇、探索畫面：動物用原始像素大小顯示（遠處的灰熊因此比較小），背景是當下的地形。
- 狩獵畫面：左邊是狼（觀察、潛近 = 潛近姿勢；追擊 = 走路動畫；撲抓、搏鬥 = 撲擊），右邊是獵物（追擊時播跑動），統一縮到 40 像素高。
- 進食畫面：狼的進食姿勢。
- 一生回顧：灰狼「倒下」那一列的最後一格。

## 尚未使用或缺少的素材

- 沒用到：`wolf_assets` 的分層背景（`*_layers/`，之後做視差可用）、`deer_adult` 動畫（雄鹿、母鹿改用 phase1.5 的單張以便區分）、`icons_sheet`。
- 缺少：雄鹿、母鹿的動畫；陌生灰狼與遠距灰熊的動畫；獵物屍體（進食畫面目前只有狼）；地圖按鈕上的區域小圖仍由程式生成。

## 檔名規則

- 全部小寫英文，單字以底線分隔。
- 動畫 spritesheet 以 `_sheet` 結尾，每格 48×32，第一列是待機。
- 換正式素材時沿用 `assets/art/` 的檔名；要改名或新增時，同步修改 `data/art.json`。
