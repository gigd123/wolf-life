# 主視覺風格（黃昏斜角像素場景）：Gemini 提示詞範本

主視覺以 `reference/style_dusk.jpg`（黃昏、雪山、針葉林、長苔蘚的岩階與小徑、狼與駝鹿站在場景裡）為準。
用途：先產測試用的圖，套進美術測試場景（`prototypes/art_test/`）的第三種風格「場景」。

這一批要產：
- **區域場景 3 張**：林緣草地（黃昏）、林內（黃昏）、林緣草地的冬季版
- **場景角色 5 隻**：灰狼、黑狼、灰熊、母馬鹿、雪兔（夏毛）

## 使用方式

1. **每次都附上 `reference/style_dusk.jpg`**（就是你挑的第一張）當風格參考。提示詞開頭都寫了「match the art style of the attached image」。
2. 一次只產一張。每張多產 2～4 張挑最好的。
3. 對照下面的驗收清單；不合格就請 Gemini 修正（例如「remove the white border」「remove the UI thumbnails at the bottom」），或重產。
4. 原圖直接傳給 Claude。像素方塊對齊、縮回原生解析度（場景 320×180）、統一調色盤、去背都由 Claude 處理。

> 參考圖本身下方有幾格小圖、四周有白邊與格線，那是 Gemini 自己加的，正式的圖不要有。提示詞都已經寫明不要。

---

## 一、區域場景

### 共用段（每段場景提示詞都已經包含）

```
Match the art style of the attached image exactly: detailed pixel art, crisp hard-edged square pixels on one
strict grid, no anti-aliasing, no blur. High three-quarter top-down view (camera about 45 degrees above the ground),
like a diorama: dark spruce and fir trees drawn as individual sprites, mossy rock ledges and small cliffs,
stone steps and dirt paths, ferns and small wildflowers, boulders.
The scene fills the entire image edge to edge: no white border, no frame, no grid lines, no UI, no thumbnails,
no sprite sheet, no text, no watermark. No animals and no people in the scene. 16:9 wide format.
Leave a fairly flat, open patch of ground in the lower middle of the image (about the lower 40%), with nothing on it,
where animals will be placed later.
```

驗收清單：
- 和參考圖同一種風格：同樣的俯視角度、像素方塊大小、樹的畫法、黃昏的配色。
- **整張畫滿**，沒有白邊、格線、下方的小圖、文字。
- **沒有任何動物**。
- 下方中間有一塊平坦、空著的地面（之後放動物的地方）。

### 1. 林緣草地（黃昏）— 和參考圖最接近的一張

```
[共用段]

Scene: the edge of a mountain conifer forest at dusk in late summer. An orange, pink and purple sunset sky over
snow-capped mountain peaks in the background. A wall of dark spruce trees across the middle, with a few trees
framing the left and right edges. Mossy rock ledges and a winding stone-and-dirt path on one side.
In the lower middle, an open grassy meadow with small yellow and purple wildflowers.
Warm low sunlight from the right, long soft shadows, cool purple shade under the trees.
```

### 2. 林內（黃昏）

```
[共用段]

Scene: inside an old mountain spruce forest at dusk. Tall dark trunks and dense spruce trees all around, the sky
only visible as orange and purple glimpses between the treetops. Warm golden light beams slanting through the trees
from the right. A fallen mossy log, ferns, roots and boulders. In the lower middle, a small open clearing of soft
forest floor (moss, needles and dirt) where a narrow animal trail crosses.
```

### 3. 林緣草地的冬季版

**在產出第 1 張的同一個對話裡**接著說（Gemini 會照同一張圖改，構圖比較一致）：

```
Make the exact same scene in deep winter: same layout, same trees, rocks and path in the same places, same camera
angle and pixel style. Snow covers the ground and the trees, the meadow is a smooth snowfield, the path shows as a
faint trampled line. Cold dusk light: pale pink and lavender sky, blue shadows. Keep the open area in the lower middle
empty. No animals, no border, no UI, no text.
```

---

## 二、場景角色（小尺寸，放在場景裡）

角色要和場景**同一個像素方塊大小、同一個角度**。Gemini 會把動物畫大一點，沒關係，Claude 會照場景的比例縮回去（灰狼約 30 像素高）。

### 共用段（每段角色提示詞都已經包含）

```
Match the pixel art style of the attached image exactly, and draw the animal the way the wolf and the moose
in that image are drawn: same pixel size, same level of detail, same dusk lighting (warm light from the right,
cool shadow side), same slightly-from-above three-quarter camera angle (mostly a side view).
Crisp hard-edged square pixels on one strict grid, no anti-aliasing, no blur, dark outline.

The animal faces right. Full body completely inside the frame with margin on all sides.
Standing pose with all four legs visible and clearly separated (near legs and far legs not overlapping),
tail visible and not overlapping the legs. Mouth closed.
Plain flat pure white background, no ground, no shadow, no scenery, no grid, no UI, no text, no watermark,
only one animal in the image.
```

驗收清單：
- 和參考圖裡的狼、駝鹿是同一種畫法（方塊大小、細節程度、受光方向）。
- 朝右、略帶俯視的側面，四條腿分開、看得到。
- 純白背景，**只有一隻動物**，沒有地面、影子、格線、小圖。
- 沒有多出來的腿、奇怪的身體結構。

### 4～8. 各動物的 Subject 段（接在共用段後面）

**灰狼（玩家）**
```
Subject: an adult North American gray wolf like the wolf in the attached image: grizzled gray and tan coat,
darker saddle on the back, pale cream cheeks, throat and lower legs, amber eyes, bushy tail with a dark tip.
```

**黑狼**
```
Subject: an adult black-phase gray wolf with the same body shape and size as the wolf in the attached image:
black coat with charcoal-gray highlights where the warm light hits, yellow eyes, bushy black tail.
```

**灰熊**
```
Subject: an adult grizzly bear on all fours, clearly bigger and heavier than the wolf in the attached image:
brown coat with silver-tipped fur on the back, a shoulder hump, dished face, small round ears,
heavy rounded hindquarters, pale claws.
```

**母馬鹿**
```
Subject: an adult female elk (wapiti cow), no antlers, about as tall as the moose in the attached image but slimmer:
tan-brown body, dark chocolate-brown neck mane and legs, pale cream rump patch, long slender legs.
```

**雪兔（夏毛）**
```
Subject: a snowshoe hare in summer coat, much smaller than the wolf in the attached image:
brown coat with white feet and belly, long upright ears, large hind feet, sitting alert on all four feet.
```

---

## 免費版 Gemini 用的精簡版

免費版不太聽長段落的細節。角色改用這種短句，一次只講最重要的三件事（風格、朝右側面、白底）；
附圖除了黃昏參考圖，也可以附上**林內那張已經成功的場景**，讓它知道要畫進同一個世界。

```
Pixel art sprite of a gray wolf in the same style as the attached image. Side view, facing right, standing.
Only the wolf, on a plain white background. No ground, no scenery, no text.
```

把 `a gray wolf` 換成：
- `a black wolf`
- `a grizzly bear, much bigger than a wolf`
- `a female elk (no antlers)`
- `a brown snowshoe hare`

不合格時的追問（同一個對話裡接著說）：
- 背景不乾淨：`Make the background plain white, remove everything except the animal.`
- 不是側面：`Turn it to an exact side view facing right.`
- 太模糊、不像像素：`Make it crisp pixel art with hard square pixels, no blur.`
- 有很多隻：`Only one animal.`

場景（林緣草地、冬季）同理，用短句：

```
Pixel art scene in the same style as the attached images: a forest edge meadow at dusk, snowy mountains,
dark spruce trees, mossy rocks, an empty grassy clearing in the lower middle. Fill the whole image, no animals, no text.
```

## 之後（這一批確認後再產）

- 公馬鹿、雪兔冬毛、其他季節的場景（秋季、燒過）。
- 劇情立繪（精細的大像素圖）：用之前 `art_illustrated_test_2026-10-13/gemini_pixel_prompts.md` 的那種狼，留給事件卡片與一生回顧。

## 備註

- 放進遊戲前，請確認 Gemini 輸出的使用條款允許用在遊戲。
