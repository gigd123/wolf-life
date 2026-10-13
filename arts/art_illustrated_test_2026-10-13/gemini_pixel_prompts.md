# 像素風比較：Gemini 提示詞範本

用途：和插畫風（`gemini_prompts.md`）對照，看「Gemini 畫的像素圖＋骨架動畫」在遊戲裡的效果。
先只產**灰狼一張**做試作；確認路線後再產其他動物（黑狼、灰熊、馬鹿、雪兔）與背景。

## 使用方式

1. **每次都附上風格參考圖**：上傳那張 Gemini 產的像素灰狼（雪夜森林、走路的那張）。提示詞開頭已經寫了「match the pixel art style of the attached image」。
2. 一次只產一種動物、一個姿勢，多產 2～4 張挑最好的。
3. 產出後對照下面的「驗收清單」；不合格就請 Gemini 修正，或重產。
4. 原圖直接傳給 Claude。去背、對齊像素格、縮回原生解析度、統一調色盤都由 Claude 處理。

## 共用風格段（每段提示詞都已經包含）

```
Match the pixel art style of the attached image: detailed pixel art, crisp hard-edged square pixels,
every pixel the same size on one strict grid, no anti-aliasing, no blur, no gradients, no smooth shading.
Limited palette of about 32 colors. Fur drawn with clustered pixels and light dithering,
dark 1-pixel outline around the animal, soft light from the upper left.
```

## 動物共用的構圖要求（每段動物提示詞都已經包含）

```
Exact side view (profile), facing right, full body completely inside the frame with margin on all sides.
Standing pose with all four legs visible and clearly separated (near legs and far legs not overlapping),
tail fully visible and not overlapping the legs. Mouth closed.
Plain flat pure white background, no ground, no shadow, no snow, no scenery, no text, no watermark, no border.
```

驗收清單：
- **像素方塊大小一致**：放大看，每個方塊一樣大、排得整齊，沒有忽大忽小、沒有歪斜的方塊（AI 常出現的問題）。
- 邊緣是硬邊，沒有模糊、沒有漸層的光暈。
- 正側面、朝右，只看得到一隻眼睛。
- 整隻都在畫面內，純白背景，沒有地面、影子、雪。
- 四條腿分開、尾巴沒壓到腿。
- 沒有多出來的腿、腳趾或奇怪的身體結構。

---

## 1. 玩家灰狼（試作只要這張）

```
Match the pixel art style of the attached image: detailed pixel art, crisp hard-edged square pixels,
every pixel the same size on one strict grid, no anti-aliasing, no blur, no gradients, no smooth shading.
Limited palette of about 32 colors. Fur drawn with clustered pixels and light dithering,
dark 1-pixel outline around the animal, soft light from the upper left.

Subject: the same adult North American gray wolf as in the attached image. Grizzled gray and tan coat
with a darker saddle on the back, cream-white cheeks, throat and chest, pale cream lower legs,
amber eyes, thick neck ruff, deep chest, bushy tail with a dark tip. Balanced natural proportions,
head not oversized, short blunt muzzle.

Exact side view (profile), facing right, full body completely inside the frame with margin on all sides.
Standing pose with all four legs visible and clearly separated (near legs and far legs not overlapping),
tail fully visible and not overlapping the legs. Mouth closed.
Plain flat pure white background, no ground, no shadow, no snow, no scenery, no text, no watermark, no border.
```

## 2～6. 其他動物（確認路線後再產）

把灰狼那段的 `Subject:` 換成下面這幾段，其他不變（第一行的參考圖仍附像素灰狼）。

**黑狼**
```
Subject: an adult black-phase gray wolf with the same body shape as the gray wolf in the attached image.
Black coat with subtle charcoal-gray fur clusters and a few silver hairs on the muzzle and chest,
yellow eyes, thick neck ruff, bushy black tail.
```

**灰熊**（姿勢那一行的 `tail fully visible...` 可以留著，熊尾巴很短不影響）
```
Subject: an adult grizzly bear standing on all fours. Brown coat with silver-tipped (grizzled) fur on
the back and shoulders, darker legs, a shoulder hump, dished face, small rounded ears, long pale claws.
Heavy, rounded hindquarters slightly larger than the shoulder hump. Massive and heavy.
```

**馬鹿母鹿**
```
Subject: an adult female elk (wapiti cow), no antlers. Tan-brown body, dark chocolate-brown neck mane
and legs, pale cream rump patch, short tail, long slender legs, alert ears.
```

**馬鹿公鹿**（把 `full body completely inside the frame` 改成 `full body and the whole antlers completely inside the frame`）
```
Subject: an adult bull elk (wapiti) with large branching antlers sweeping backwards (six points per side).
Tan-brown body, thick dark chocolate-brown shaggy neck mane, dark legs, pale cream rump patch, powerful build.
```

**雪兔**（夏毛、冬毛各產一張）
```
Subject: a snowshoe hare in its [SUMMER: brown coat with white feet and belly /
WINTER: all-white coat with black ear tips]. Large hind feet, long ears upright, sitting alert on all four feet.
```
（雪兔冬毛是白的，白底會不好去背；這張的背景改成 `Plain flat pure light-gray (#c8c8c8) background`。）

---

## 背景（選做）

像素試作可以先放在遊戲現有的背景上比較，不一定要新背景。想要 Gemini 的像素背景時用這段：

```
Match the pixel art style of the attached image: detailed pixel art, crisp hard-edged square pixels,
every pixel the same size on one strict grid, no anti-aliasing, no blur, limited palette.

[場景描述，例如：A forest edge meadow in the North American Rocky Mountains in summer daylight:
tall grass and a few wildflowers in the foreground, a dark wall of spruce forest in the middle distance,
snow-capped mountains and a blue sky with soft clouds far away. Large tree trunks frame the left and right edges.]

The lower third of the image is open, fairly flat ground with nothing in the middle (animals will be placed there).
No animals, no people, no text, no watermark. 16:9 wide format.
```

---

## 備註

- AI 產的像素圖通常不是真的對齊格子；Claude 會偵測方塊大小（參考圖約 6×6）、縮回原生解析度、統一調色盤，再做骨架動畫（在高解析的原圖上變形後再縮回像素格，避免旋轉後的碎點）。
- 放進遊戲前，請確認 Gemini 輸出的使用條款允許用在遊戲。
