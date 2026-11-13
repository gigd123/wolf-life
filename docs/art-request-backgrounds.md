# 背景圖出圖清單（2026-11-13，使用者選方案 1：全部請 AI 畫，慢慢出）

把選單畫面的佔位背景（Claude Code 用程式畫的）全部換掉。一共 90 張：區域背景 46 張（主畫面後面的大圖）、地形背景 44 張（遭遇、選單式狩獵與戰鬥時動物後面的那張）。

**流程**：先出「基本圖」（夏天、白天），再出變化版（冬天、秋天、燒過）：把基本圖附上，貼「變化版的文案」。出好的圖直接傳給 Claude Code，檔名照下表的 id（例如 `forest_east`、`forest_east_winter`），Claude Code 負責裁成 16:9、縮成遊戲用的尺寸（區域 640×360、地形 320×180）、接進遊戲。

**優先順序**：先出森林（開局的地方）→ 苔原 → 山地 → 草原 → 牧場。每個地圖先出區域背景，再出那個地圖會用到的地形。

## 共通要求（每一段文案都已經附在裡面，不用另外貼）

- 寬 16:9 的橫向風景，側面平視（像橫向捲軸遊戲的背景），**沒有任何動物、人、文字**。
- 像素畫（pixel art），顏色略為柔和（遊戲裡會再壓暗，讓上面的文字和動物看得清楚）。
- 地平線大約在畫面高度的 55～60%，下面三分之一是平坦、開闊的地面（動物會站在中下方），不要有大石頭或樹幹擋在畫面正中下方。
- 光從左上方來；北美落磯山脈一帶的溫帶與北方森林（雲杉、松、白楊、白樺）。

## 區域背景（主畫面）

### 基本圖的文案

每段都可以直接複製。

**forest_east 森林東部**
```
A wide 16:9 side-view landscape for a 2D game background: the edge of a North American mountain forest in summer. A clear stream flows out of the forest toward the viewer, between spruce and aspen trees on both sides; in the distance, snow-capped Rocky Mountain peaks under a blue sky. Grassy open ground in the lower third with a few small stones by the stream. No animals, no people, no text. Pixel art with slightly muted colors, light from the upper left, horizon at about 55–60% of the image height, the lower third flat and open with nothing blocking the lower middle.
```

**forest_north 森林北部**
```
A wide 16:9 side-view landscape for a 2D game background: a dense, dark northern spruce forest in summer, tall trees close together, a narrow stream running through the forest floor with moss and ferns along its banks, soft light filtering between the trunks. No animals, no people, no text. Pixel art with slightly muted colors, light from the upper left, horizon at about 55–60% of the image height, the lower third flat and open forest floor with nothing blocking the lower middle.
```

**forest_south 森林南部**
```
A wide 16:9 side-view landscape for a 2D game background: the southern edge of a forest in summer, where the trees thin out into a wide sunny clearing of grass and wildflowers; a few scattered pines and aspens, a low sandy bank on one side (a fox den area), the forest wall in the background. No animals, no people, no text. Pixel art with slightly muted colors, light from the upper left, horizon at about 55–60% of the image height, the lower third flat and open with nothing blocking the lower middle.
```

**forest_west 森林西部**
```
A wide 16:9 side-view landscape for a 2D game background: a deep old-growth forest on a slope in summer, huge old spruce and fir trees, many fallen moss-covered logs lying across the ground, dim green light. No animals, no people, no text. Pixel art with slightly muted colors, light from the upper left, horizon at about 55–60% of the image height, the lower third mostly open forest floor (fallen logs at the sides, not in the lower middle).
```

**tundra_south 苔原林線**
```
A wide 16:9 side-view landscape for a 2D game background: the northern treeline in summer, where the spruce forest becomes sparse with small stunted spruces, opening to low tundra of grass, moss and dwarf shrubs stretching to the horizon under a pale wide sky. No animals, no people, no text. Pixel art with slightly muted colors, light from the upper left, horizon at about 55–60% of the image height, the lower third flat and open with nothing blocking the lower middle.
```

**tundra_central 開闊苔原**
```
A wide 16:9 side-view landscape for a 2D game background: endless flat open tundra in summer, green-brown moss and low grass, small pools of water, a few lichen-covered rocks, a huge pale sky with long clouds, nowhere to hide. No animals, no people, no text. Pixel art with slightly muted colors, light from the upper left, horizon at about 55–60% of the image height, the lower third flat and open.
```

**tundra_east 苔原河谷**
```
A wide 16:9 side-view landscape for a 2D game background: a tundra river valley in summer, a shallow river winding between thickets of low willow shrubs, muddy banks, gentle hills of tundra on both sides under a wide sky. No animals, no people, no text. Pixel art with slightly muted colors, light from the upper left, horizon at about 55–60% of the image height, the lower third flat and open with nothing blocking the lower middle.
```

**tundra_north 遠北苔原**
```
A wide 16:9 side-view landscape for a 2D game background: the far-north arctic tundra in summer, rocky frozen ground with scattered boulders and patches of moss, a long high gravel ridge (an esker left by glaciers) running across the middle distance, cold grey-blue sky. No animals, no people, no text. Pixel art with slightly muted colors, light from the upper left, horizon at about 55–60% of the image height, the lower third flat and open with nothing blocking the lower middle.
```

**mountain_foothills 山腳林地**
```
A wide 16:9 side-view landscape for a 2D game background: Rocky Mountain foothills in summer, mixed pine and aspen woodland at the foot of the mountains, a stream coming down from the slopes, mountains rising behind. No animals, no people, no text. Pixel art with slightly muted colors, light from the upper left, horizon at about 55–60% of the image height, the lower third flat and open with nothing blocking the lower middle.
```

**mountain_meadow 高山草甸**
```
A wide 16:9 side-view landscape for a 2D game background: a high alpine meadow above the treeline in summer, open grass and small wildflowers, grey scree slopes and rocky peaks above, the last stunted trees far below at one side. No animals, no people, no text. Pixel art with slightly muted colors, light from the upper left, horizon at about 55–60% of the image height, the lower third flat and open with nothing blocking the lower middle.
```

**mountain_canyon 岩壁峽谷**
```
A wide 16:9 side-view landscape for a 2D game background: a narrow mountain canyon in summer, steep grey-brown rock walls on both sides, loose gravel and scree on the canyon floor, a strip of sky above. No animals, no people, no text. Pixel art with slightly muted colors, light from the upper left, horizon at about 55–60% of the image height, the lower third a flat gravel floor with nothing blocking the lower middle.
```

**mountain_headwaters 溪流源頭**
```
A wide 16:9 side-view landscape for a 2D game background: the headwaters high in the mountains in summer, several small clear streams joining together over rocks, willow shrubs along the water, green slopes and peaks behind. No animals, no people, no text. Pixel art with slightly muted colors, light from the upper left, horizon at about 55–60% of the image height, the lower third flat and open with nothing blocking the lower middle.
```

**grassland_hills 丘陵草地**
```
A wide 16:9 side-view landscape for a 2D game background: rolling grassy hills in summer, layer after layer of soft green-gold hills fading into the distance, low hollows between them, big blue sky. No animals, no people, no text. Pixel art with slightly muted colors, light from the upper left, horizon at about 55–60% of the image height, the lower third flat and open.
```

**grassland_plains 開闊草原**
```
A wide 16:9 side-view landscape for a 2D game background: endless open prairie in summer, tall golden-green grass waving in the wind all the way to the horizon, a huge sky with clouds, no trees and nowhere to hide. No animals, no people, no text. Pixel art with slightly muted colors, light from the upper left, horizon at about 55–60% of the image height, the lower third flat and open.
```

**grassland_riverwoods 河岸林帶**
```
A wide 16:9 side-view landscape for a 2D game background: a line of cottonwood and aspen trees along a prairie river in summer, the only woodland on the grassland, a small hidden pool among the trees, open prairie beyond. No animals, no people, no text. Pixel art with slightly muted colors, light from the upper left, horizon at about 55–60% of the image height, the lower third flat and open with nothing blocking the lower middle.
```

**grassland_river 大河**
```
A wide 16:9 side-view landscape for a 2D game background: a wide river flowing across the prairie from the mountains in summer, sandbars in the middle of the river, willow shrubs on the near bank, mountains faint on the horizon. No animals, no people, no text. Pixel art with slightly muted colors, light from the upper left, horizon at about 55–60% of the image height, the lower third a flat open riverbank with nothing blocking the lower middle.
```

**ranch_edge 牧場邊緣**
```
A wide 16:9 side-view landscape for a 2D game background: the edge of an 1880s frontier ranch in summer, seen from outside: a wooden split-rail fence in the middle distance, brush and a small creek on this side, open pasture beyond the fence, a small log cabin far away. No animals, no people, no text. Pixel art with slightly muted colors, light from the upper left, horizon at about 55–60% of the image height, the lower third flat and open with nothing blocking the lower middle.
```

**ranch_pasture 放牧地**
```
A wide 16:9 side-view landscape for a 2D game background: a big fenced pasture of an 1880s frontier ranch in summer, short grazed grass, a long wooden fence line, a haystack, hills and forest in the distance. No animals, no people, no text. Pixel art with slightly muted colors, light from the upper left, horizon at about 55–60% of the image height, the lower third flat and open.
```

**ranch_yard 屋舍與畜欄**
```
A wide 16:9 side-view landscape for a 2D game background: the yard of an 1880s frontier homestead in summer, a log cabin with a stone chimney, a small wooden barn, a corral of rough poles, a water trough, trampled dirt ground. No animals, no people, no text. Pixel art with slightly muted colors, light from the upper left, horizon at about 55–60% of the image height, the lower third flat open dirt with nothing blocking the lower middle.
```

### 變化版的文案（附上同一區的基本圖）

**冬天版**（每一區都要；檔名加 `_winter`）
```
Use the attached image as the exact reference: the same place, the same composition, trees, rocks and landforms in the same positions, the same pixel art style. Change it to deep winter: thick snow covering the ground and branches, frozen or partly frozen water, grey-white overcast sky, cold blue light. No animals, no people, no text. Wide 16:9, the lower third flat and open.
```

**秋天版**（只有森林四區；檔名加 `_autumn`）
```
Use the attached image as the exact reference: the same place, the same composition, trees, rocks and landforms in the same positions, the same pixel art style. Change it to autumn: aspen and birch leaves turned golden yellow and orange, spruces stay dark green, dry golden grass, a few fallen leaves, warm low sunlight. No animals, no people, no text. Wide 16:9, the lower third flat and open.
```

**燒過的版本**（只有森林四區；檔名加 `_burned`）
```
Use the attached image as the exact reference: the same place, the same composition and landforms, the same pixel art style. Change it to just after a forest fire: blackened tree trunks with no leaves, some still smoking, grey ash covering the ground, charred logs, a hazy brownish smoky sky. Water stays (darker). No animals, no people, no text. Wide 16:9, the lower third flat and open.
```

### 區域背景的檢查表

| 地圖 | 基本圖 | 冬天 | 秋天 | 燒過 |
| --- | --- | --- | --- | --- |
| 森林 | forest_east、forest_north、forest_south、forest_west | 4 | 4 | 4 |
| 苔原 | tundra_south、tundra_central、tundra_east、tundra_north | 4 | — | — |
| 山地 | mountain_foothills、mountain_meadow、mountain_canyon、mountain_headwaters | 4 | — | — |
| 草原 | grassland_hills、grassland_plains、grassland_riverwoods、grassland_river | 4 | — | — |
| 牧場 | ranch_edge、ranch_pasture、ranch_yard | 3 | — | — |

## 地形背景（遭遇、選單式狩獵與戰鬥）

比區域背景更「近」：站在地上看到的一小片地方，動物站在畫面中下方。共通要求同上，另外：**近景、地面佔畫面下方將近一半**。

### 基本圖的文案

**dense_forest 密林**
```
A wide 16:9 side-view close-up scene for a 2D game background: inside a dense spruce forest in summer, dark tree trunks close together in the background, moss, ferns and needles on the forest floor, dim filtered light. No animals, no people, no text. Pixel art with slightly muted colors, light from the upper left, the ground taking up nearly the lower half, open and flat in the middle so an animal can stand there.
```

**forest_edge 林緣**
```
A wide 16:9 side-view close-up scene for a 2D game background: the edge of a forest in summer, a wall of spruce and aspen on one side opening onto grass on the other, bright light on the grass. No animals, no people, no text. Pixel art with slightly muted colors, light from the upper left, the ground taking up nearly the lower half, open and flat in the middle so an animal can stand there.
```

**clearing 林間空地**
```
A wide 16:9 side-view close-up scene for a 2D game background: a sunny grassy clearing surrounded by forest in summer, wildflowers and tall grass, trees in the background. No animals, no people, no text. Pixel art with slightly muted colors, light from the upper left, the ground taking up nearly the lower half, open and flat in the middle so an animal can stand there.
```

**fallen_logs 倒木區**
```
A wide 16:9 side-view close-up scene for a 2D game background: an old forest floor with several large fallen moss-covered logs lying at different angles at the sides and back, tall old trees behind. No animals, no people, no text. Pixel art with slightly muted colors, light from the upper left, the ground taking up nearly the lower half, open and flat in the middle so an animal can stand there.
```

**stream 溪流**
```
A wide 16:9 side-view close-up scene for a 2D game background: a small clear forest stream running across the scene over pebbles, grassy banks, ferns and trees behind. No animals, no people, no text. Pixel art with slightly muted colors, light from the upper left, the ground taking up nearly the lower half, the bank in the lower middle open and flat so an animal can stand there.
```

**river 大河**
```
A wide 16:9 side-view close-up scene for a 2D game background: the bank of a wide river, flowing water across the middle distance, a gravel and sand bank in the foreground, the far shore low and grassy. No animals, no people, no text. Pixel art with slightly muted colors, light from the upper left, the ground taking up nearly the lower half, open and flat in the middle so an animal can stand there.
```

**river_willow 柳叢河岸**
```
A wide 16:9 side-view close-up scene for a 2D game background: a muddy riverbank with thick clumps of low willow shrubs, shallow water behind, footprints in the mud. No animals, no people, no text. Pixel art with slightly muted colors, light from the upper left, the ground taking up nearly the lower half, open and flat in the middle so an animal can stand there.
```

**prairie 草原**
```
A wide 16:9 side-view close-up scene for a 2D game background: tall prairie grass in summer, golden-green, waving, a wide open sky above, nothing else. No animals, no people, no text. Pixel art with slightly muted colors, light from the upper left, the ground taking up nearly the lower half, a flatter patch of shorter grass in the middle so an animal can stand there.
```

**rolling_hills 草丘**
```
A wide 16:9 side-view close-up scene for a 2D game background: the slope of a grassy hill with more rolling hills behind, short grass and a few low bushes. No animals, no people, no text. Pixel art with slightly muted colors, light from the upper left, the ground taking up nearly the lower half, open and fairly flat in the middle so an animal can stand there.
```

**alpine_meadow 高山草甸**
```
A wide 16:9 side-view close-up scene for a 2D game background: a high alpine meadow, short grass and small colorful wildflowers, rocky peaks close behind. No animals, no people, no text. Pixel art with slightly muted colors, light from the upper left, the ground taking up nearly the lower half, open and flat in the middle so an animal can stand there.
```

**scree 碎石坡**
```
A wide 16:9 side-view close-up scene for a 2D game background: a mountain scree slope of loose grey broken rocks and gravel, a few tough plants, steep rocky slopes behind. No animals, no people, no text. Pixel art with slightly muted colors, light from the upper left, the ground taking up nearly the lower half, a flatter gravel patch in the middle so an animal can stand there.
```

**cliff 岩壁**
```
A wide 16:9 side-view close-up scene for a 2D game background: the foot of a tall steep rock cliff, layered grey-brown rock face filling the background, fallen rocks at its base, a gravel floor in front. No animals, no people, no text. Pixel art with slightly muted colors, light from the upper left, the ground taking up nearly the lower half, open and flat in the middle so an animal can stand there.
```

**open_tundra 開闊苔原**
```
A wide 16:9 side-view close-up scene for a 2D game background: flat open tundra, moss, lichen and low grass in green, brown and rust colors, a few small rocks, a wide pale sky. No animals, no people, no text. Pixel art with slightly muted colors, light from the upper left, the ground taking up nearly the lower half, open and flat in the middle so an animal can stand there.
```

**treeline 林線**
```
A wide 16:9 side-view close-up scene for a 2D game background: the northern treeline, a few small stunted spruce trees standing apart, low tundra plants between them, open sky. No animals, no people, no text. Pixel art with slightly muted colors, light from the upper left, the ground taking up nearly the lower half, open and flat in the middle so an animal can stand there.
```

**rocky 岩石凍原**
```
A wide 16:9 side-view close-up scene for a 2D game background: arctic rocky ground, frost-cracked stones and boulders with patches of moss and lichen, cold grey sky. No animals, no people, no text. Pixel art with slightly muted colors, light from the upper left, the ground taking up nearly the lower half, a flatter patch in the middle so an animal can stand there.
```

**esker 沙脊**
```
A wide 16:9 side-view close-up scene for a 2D game background: the side of a long high gravel and sand ridge (an esker) on the tundra, sparse low plants on the slope, wide tundra and sky behind. No animals, no people, no text. Pixel art with slightly muted colors, light from the upper left, the ground taking up nearly the lower half, open and fairly flat in the middle so an animal can stand there.
```

**ice 冰面**（冬天才有）
```
A wide 16:9 side-view close-up scene for a 2D game background: a frozen lake or river in winter, thick white-blue ice with snow drifts, snowy banks and snow-covered spruces on the far shore, grey sky. No animals, no people, no text. Pixel art with slightly muted colors, light from the upper left, the ice taking up nearly the lower half, open and flat in the middle so an animal can stand there.
```

**ice_thin 薄冰**（冬天才有；附 ice 那張）
```
Use the attached image as the exact reference: the same place, the same composition, the same pixel art style. Make the ice thin and dangerous: darker grey-green translucent ice, visible cracks, a few patches of open dark water, less snow on the ice. No animals, no people, no text. Wide 16:9, the ice in the lower half open and flat in the middle.
```

### 變化版

和區域背景一樣，用上面的「冬天版」「秋天版」「燒過的版本」文案，附上同一種地形的基本圖。

| 地形 | 冬天 | 秋天 | 燒過 |
| --- | --- | --- | --- |
| dense_forest、forest_edge、clearing、fallen_logs、stream | ✓ | ✓ | ✓ |
| alpine_meadow、cliff、esker、open_tundra、prairie、river、river_willow、rocky、rolling_hills、scree、treeline | ✓ | — | — |
| ice、ice_thin | （本身就是冬天） | — | — |
