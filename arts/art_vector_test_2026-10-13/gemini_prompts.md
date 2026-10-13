# 插畫風比較場景：Gemini 提示詞範本

測試地圖（`vector_test`）用的素材：玩家灰狼、黑狼、灰熊、馬鹿（母鹿、公鹿）、雪兔，加上兩張背景（林緣草地、林內）。
動物圖之後會由 Claude 切成部件（頭、身體、四條腿、尾巴），在 Godot 做骨架動畫，所以構圖要求比一般插畫嚴格。

## 使用方式

1. **每次都附上風格參考圖**：把之前 Gemini 產的那張灰狼（走路、林間小徑）一起上傳，提示詞開頭已經寫了「match the art style of the attached image」。這是讓每張圖風格一致最有效的方法。
2. 一次只產一種動物、一個姿勢。每種多產 2～4 張，挑最好的一張。
3. 產出後先自己檢查下面的「驗收清單」，不合格就請 Gemini 修正（例如「make it an exact side view」「separate the legs more」），或重產。
4. 原圖傳給 Claude，不用自己去背或裁切。

## 共用風格段（每段提示詞都已經包含）

```
Match the art style of the attached image: stylized 2D game illustration, clean bold dark outlines,
cel-shaded with layered fur clumps, semi-realistic animal proportions, muted natural colors,
soft light from the upper left.
```

## 動物共用的構圖要求（每段動物提示詞都已經包含）

```
Exact side view (profile), facing right, full body completely inside the frame with margin on all sides.
Standing pose with all four legs visible and clearly separated (near legs and far legs not overlapping),
tail fully visible and not overlapping the legs. Mouth closed.
Plain flat pure white background, no ground, no shadow, no scenery, no text, no watermark, no border.
```

驗收清單：
- 正側面、朝右（不是 3/4 側面，看得到的只有一隻眼睛）。
- 整隻都在畫面內，四周有留白；沒有地面、影子、背景。
- 四條腿都看得到而且分開，尾巴沒有和腿疊在一起。
- 風格和參考圖一樣（外框線粗細、毛撮畫法、配色的飽和度）。
- 沒有多出來的腿、腳趾或奇怪的身體結構（AI 常出錯，要特別看）。

---

## 1. 玩家灰狼（成年）

```
Match the art style of the attached image: stylized 2D game illustration, clean bold dark outlines,
cel-shaded with layered fur clumps, semi-realistic animal proportions, muted natural colors,
soft light from the upper left.

Subject: an adult North American gray wolf. Grizzled gray and tan coat with a darker saddle on the back,
cream-white cheeks, throat and chest, pale cream lower legs, amber eyes, thick neck ruff, deep chest,
bushy tail with a dark tip. Balanced natural proportions, head not oversized, short blunt muzzle.

Exact side view (profile), facing right, full body completely inside the frame with margin on all sides.
Standing pose with all four legs visible and clearly separated (near legs and far legs not overlapping),
tail fully visible and not overlapping the legs. Mouth closed.
Plain flat pure white background, no ground, no shadow, no scenery, no text, no watermark, no border.
```

## 2. 黑狼

```
Match the art style of the attached image: stylized 2D game illustration, clean bold dark outlines,
cel-shaded with layered fur clumps, semi-realistic animal proportions, muted natural colors,
soft light from the upper left.

Subject: an adult black-phase gray wolf, the same body shape as a gray wolf. Black coat with subtle
charcoal-gray fur clumps and a few silver hairs on the muzzle and chest, yellow eyes, thick neck ruff,
bushy black tail. Balanced natural proportions, head not oversized, short blunt muzzle.

Exact side view (profile), facing right, full body completely inside the frame with margin on all sides.
Standing pose with all four legs visible and clearly separated (near legs and far legs not overlapping),
tail fully visible and not overlapping the legs. Mouth closed.
Plain flat pure white background, no ground, no shadow, no scenery, no text, no watermark, no border.
```

## 3. 灰熊

```
Match the art style of the attached image: stylized 2D game illustration, clean bold dark outlines,
cel-shaded with layered fur clumps, semi-realistic animal proportions, muted natural colors,
soft light from the upper left.

Subject: an adult grizzly bear walking on all fours. Brown coat with silver-tipped (grizzled) fur on the
back and shoulders, darker legs, a shoulder hump, dished face, small rounded ears, long pale claws.
Heavy, rounded hindquarters that look slightly larger than the shoulder hump. Massive and heavy.

Exact side view (profile), facing right, full body completely inside the frame with margin on all sides.
Standing pose with all four legs visible and clearly separated (near legs and far legs not overlapping).
Mouth closed.
Plain flat pure white background, no ground, no shadow, no scenery, no text, no watermark, no border.
```

## 4. 馬鹿（母鹿）

```
Match the art style of the attached image: stylized 2D game illustration, clean bold dark outlines,
cel-shaded with layered fur clumps, semi-realistic animal proportions, muted natural colors,
soft light from the upper left.

Subject: an adult female elk (wapiti cow), no antlers. Tan-brown body, dark chocolate-brown neck mane
and legs, pale cream rump patch, short tail, long slender legs, alert ears.

Exact side view (profile), facing right, full body completely inside the frame with margin on all sides.
Standing pose with all four legs visible and clearly separated (near legs and far legs not overlapping).
Mouth closed.
Plain flat pure white background, no ground, no shadow, no scenery, no text, no watermark, no border.
```

## 5. 馬鹿（公鹿）

```
Match the art style of the attached image: stylized 2D game illustration, clean bold dark outlines,
cel-shaded with layered fur clumps, semi-realistic animal proportions, muted natural colors,
soft light from the upper left.

Subject: an adult bull elk (wapiti) with large branching antlers sweeping backwards (six points per side).
Tan-brown body, thick dark chocolate-brown shaggy neck mane, dark legs, pale cream rump patch,
powerful build.

Exact side view (profile), facing right, full body and the whole antlers completely inside the frame
with margin on all sides. Standing pose with all four legs visible and clearly separated
(near legs and far legs not overlapping). Mouth closed.
Plain flat pure white background, no ground, no shadow, no scenery, no text, no watermark, no border.
```

## 6. 雪兔（夏毛、冬毛各一張）

```
Match the art style of the attached image: stylized 2D game illustration, clean bold dark outlines,
cel-shaded with layered fur clumps, semi-realistic animal proportions, muted natural colors,
soft light from the upper left.

Subject: a snowshoe hare in its [SUMMER: brown coat with white feet and belly /
WINTER: all-white coat with black ear tips]. Large hind feet, long ears upright, sitting alert
on all four feet.

Exact side view (profile), facing right, full body completely inside the frame with margin on all sides.
Front legs and hind legs visible. Mouth closed.
Plain flat pure white background, no ground, no shadow, no scenery, no text, no watermark, no border.
```

（把 `[SUMMER … / WINTER …]` 換成其中一個，分兩次產。）

---

## 動作補充圖（第二批，動物確認後再產）

骨架動畫可以做走路、跑、撲咬、受傷，但有些姿勢的身體形狀變化太大，用部件轉不出來，另外產一張比較好看。動物確認後再產這幾張，提示詞用上面那段，只把姿勢那一行換掉：

| 圖 | 換掉姿勢那一行 |
| --- | --- |
| 灰狼、黑狼 嚎叫 | `Sitting, head raised high, muzzle pointing up, mouth open howling.` |
| 灰狼、黑狼 威嚇 | `Head low, ears back, lips pulled back showing teeth, hackles raised.`（把 `Mouth closed.` 刪掉） |
| 灰熊 站起 | `Rearing up on its hind legs, front paws raised, mouth open roaring.`（把 `Mouth closed.` 刪掉） |
| 馬鹿公鹿 反擊 | `Head lowered, antlers pointing forward, ready to charge.` |
| 灰狼 躺下睡覺 | `Lying curled up asleep, tail wrapped around the nose.` |

---

## 7. 背景：林緣草地

```
Match the art style of the attached image: stylized 2D game illustration, clean bold dark outlines,
cel-shaded, muted natural colors, soft daylight from the upper left.

A wide landscape seen from a forest edge in the North American Rocky Mountains: a sunny meadow with
tall grass and a few wildflowers in the foreground, a dark wall of spruce and pine forest in the middle
distance, snow-capped mountains and a light blue sky with soft clouds far away. A few large tree trunks
frame the left and right edges.
The lower third of the image is open, fairly flat ground with no objects in the middle (animals will be
placed there later). No animals, no people, no text, no watermark. 16:9 wide format.
```

## 8. 背景：林內

```
Match the art style of the attached image: stylized 2D game illustration, clean bold dark outlines,
cel-shaded, muted natural colors, sunlight filtering through the canopy from the upper left.

Inside an old-growth conifer forest in the North American Rocky Mountains, looking between the trees:
thick spruce and pine trunks in the foreground on both sides, a dense canopy above, misty trunks
receding into the distance, ferns, moss, and a fallen log. Soft light beams.
The lower third of the image is an open forest floor path with no objects in the middle (animals will
be placed there later). No animals, no people, no text, no watermark. 16:9 wide format.
```

（之後要季節版時，在同一張背景的對話裡請 Gemini「make the same scene in winter, covered in snow」，比從頭產一致。）

---

## 使用條款

放進遊戲前，請確認 Gemini 輸出的使用條款允許用在遊戲（尤其是之後要販售的話）。
參考圖若有圖庫浮水印，只當風格參考，不要直接上傳成素材。
