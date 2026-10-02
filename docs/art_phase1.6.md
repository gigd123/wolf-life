# Phase 1.6 美術清單

`art_phase1.6_placeholders.zip` 解壓後是 `assets/art/` 的目錄結構，直接合併進 repo 即可（不會覆蓋任何現有檔案）。這些都是**佔位素材**：圖示是手繪像素，其他由現有素材調色或變形而來。正式素材之後照同樣的檔名與尺寸替換，程式不用改。

所有素材都遵守 `assets/README.md` 的規則：PNG、透明背景（背景圖除外）、1x 尺寸、顯示時用 Nearest 過濾。

## 一、這次已製作的佔位素材

### 第 1 步：轉變與回饋提示

| 檔案 | 尺寸 | 用途 |
| --- | --- | --- |
| `icons/stat_speed.png` | 16×16 | 速度（雙箭頭） |
| `icons/stat_strength.png` | 16×16 | 力量（犬齒） |
| `icons/stat_skill.png` | 16×16 | 技巧（鉤爪） |
| `icons/stat_perception.png` | 16×16 | 感知（狼眼） |
| `icons/stat_health.png` | 16×16 | 血量上限（愛心） |
| `icons/stat_stamina.png` | 16×16 | 體力（閃電） |
| `icons/cost_turns.png` | 16×16 | 代價列：多花回合（沙漏） |
| `icons/cost_injury_risk.png` | 16×16 | 代價列：受傷風險（警告三角） |
| `icons/tendency_stealth.png` | 16×16 | 潛伏型（草叢） |
| `icons/tendency_pursuit.png` | 16×16 | 追獵型（箭頭） |
| `icons/tendency_assault.png` | 16×16 | 強攻型（張開的顎） |
| `icons/tendency_cautious.png` | 16×16 | 謹慎型（盾牌） |
| `backgrounds/seasons/season_{spring,summer,autumn,winter}.png` | 640×360 | 季節卡片背景，由區域背景調色；秋季的針葉樹也被染成褐色，正式版要修正 |

傾向圖示的檔名沿用 `data/tendency.json` 的 id：stealth、pursuit、assault、cautious。

### 第 2 步：潛力與生命階段轉變

| 檔案 | 尺寸 | 用途 |
| --- | --- | --- |
| `sprites/wolf/wolf_adult_sheet.png` | 192×128 | 成年狼，格式同 `wolf_sheet.png`（4 欄 × 4 列，每格 48×32）；毛色略深略暖，體型放大由程式處理 |
| `sprites/wolf/wolf_adult_{stalk,pounce,eat,sleep}.png` | 同原檔 | 成年狼的單張姿勢 |
| `sprites/wolf/wolf_elder_sheet.png` | 192×128 | 老年狼：毛色變淡、口鼻泛白 |
| `sprites/wolf/wolf_elder_{stalk,pounce,eat,sleep}.png` | 同原檔 | 老年狼的單張姿勢 |

現有的 `wolf_sheet.png` 與單張姿勢繼續作為次成年期使用。

### 第 3 步：戰鬥模式

| 檔案 | 用途 | 佔位做法 |
| --- | --- | --- |
| `sprites/wolf/wolf_threaten.png` | 威嚇 | 潛近姿勢＋豎起的頸毛、露出的牙 |
| `sprites/wolf/wolf_bite.png` | 撲咬 | 暫用撲擊姿勢 |
| `sprites/wolf/wolf_dodge.png` | 閃避 | 走路動畫的一格向後傾斜 |
| `sprites/wolf/wolf_hurt.png` | 受傷 | 待機姿勢加紅色調 |
| `sprites/wolf/wolf_submit.png` | 示弱 | 倒下動畫的伏低那一格 |

灰熊的戰鬥沿用現有 `bear_adult_sheet.png` 的攻擊列，這次不另外製作。

### 第 4 步：陌生灰狼

陌生灰狼做成深色的「黑狼」，和玩家的灰狼一眼就能分辨。

| 檔案 | 用途 |
| --- | --- |
| `sprites/wolf/wolf_stranger_sheet.png` | 完整動畫（待機、走路、嚎叫、倒下），格式同 `wolf_sheet.png`；補上 1.5 缺少的陌生灰狼動畫 |
| `sprites/wolf/wolf_stranger_{stalk,pounce}.png` | 跟蹤、撲擊 |
| `sprites/wolf/wolf_stranger_{threaten,bite,dodge,hurt,submit}.png` | 戰鬥姿勢 |

現有的 `wolf_stranger.png`（單張）可以繼續用在遠距觀察。

### 第 5 步：森林大火

| 檔案 | 尺寸 | 用途 |
| --- | --- | --- |
| `backgrounds/regions/forest_{east,north,south,west}_burned.png` | 640×360 | 燒毀後的區域背景，可用 `art.json` 的 `region_backgrounds` 以 `forest_east@burned` 這類鍵對應 |
| `icons/clue_smoke.png` | 16×16 | 煙味線索 |
| `icons/status_burn.png` | 16×16 | 燒傷狀態 |

火焰與濃煙建議用粒子效果，和暴雨相同做法，不需要圖。

## 二、交給 Claude Code 時的說明

可以在第 1 步的指示後面加一段：

```
我已把 Phase 1.6 的佔位美術放進 assets/art/，清單在 docs/art_phase1.6.md。
依各步驟需要，把它們加進 data/art.json，並更新 assets/README.md 的目錄表。
```

建議把這份清單也放進 repo 的 `docs/art_phase1.6.md`，Claude Code 才找得到。

## 三、仍需要正式美術的素材

佔位素材能讓功能先動起來，但以下項目最終需要正式繪製（照 DESIGN 的流程：ChatGPT 畫概念、PixelLab 做像素圖）。依優先順序：

| 優先 | 素材 | 說明 |
| --- | --- | --- |
| 高 | 成年、老年狼 | 每個畫面都會看到；成年要表現更壯的體型，老年要有灰白口鼻與略垂的姿態 |
| 高 | 陌生灰狼 | 牠是貫穿一生的角色，值得一套有辨識度的正式造型 |
| 中 | 狼的戰鬥姿勢 | 威嚇（壓低身體、頸毛豎起、露牙）、撲咬、閃避、受傷、示弱（耳朵向後、尾巴夾起、身體伏低）；目前是由其他姿勢變形而來 |
| 中 | 四季插圖 | 正式版可以是專門繪製的季節場景，而不是區域背景調色 |
| 中 | 燒毀與再生的區域 | 燒毀後的焦黑版本，以及草木新生的版本 |
| 低 | 1.5 遺留 | 雄鹿、母鹿的動畫，遠距灰熊的動畫，獵物屍體，地圖按鈕上的區域小圖 |

這次沒有製作獵物屍體與區域小圖：前者無法從現有素材合理變形，後者要先確認地圖按鈕的實際尺寸。

## 四、第 6 步（苔原）的需求，屆時再製作

| 素材 | 數量 |
| --- | --- |
| 區域背景 | 4 區 × 夏、冬 ＝ 8 張（640×360） |
| 地形背景 | 林線、開闊苔原、河谷柳叢、岩石區、沙脊，約 5 張（320×180） |
| 地圖按鈕的區域小圖 | 4 張 |
| 雪兔 | 褐色、白色各一套（同野兔的 4 欄 × 2 列） |
| 北美馴鹿 | 待機、行走、奔跑、警戒，加上鹿群 |
| 駝鹿 | 待機、行走、奔跑、警戒、踢擊、受傷 |
| 獵物屍體 | 馴鹿、駝鹿 |
| 線索圖示 | 雪兔足跡、馴鹿足跡、駝鹿磨角痕跡 |
| 狀態圖示 | 嚴寒 |
