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
