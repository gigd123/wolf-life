"""主視覺場景圖（Gemini）→ 遊戲用的像素背景：面積平均縮到 320×180（和遊戲現有的地形背景同尺寸，畫面上放大 2 倍），
再收斂成 128 色調色盤（不抖動），去掉 JPG 雜訊與 AI 圖裡大小不一的方塊。
用法：python3 process_scene.py  → assets/art/art_test/scene/bg_<名稱>.png
"""
import os
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "..", "assets", "art", "art_test", "scene")
SIZE = (320, 180)
COLORS = 128
SCENES = {"forest": "bg_forest.jpg", "meadow": "bg_meadow.png", "winter": "bg_winter.png",
          "forest_summer": "bg_forest_summer.jpg", "forest_snowy": "bg_forest_snowy.jpg", "forest_winter": "bg_forest_winter.jpg"}


def main():
    os.makedirs(OUT, exist_ok=True)
    for key, fn in SCENES.items():
        im = Image.open(os.path.join(HERE, "source", fn)).convert("RGB")
        small = im.resize(SIZE, Image.BOX)
        q = small.quantize(colors=COLORS, method=Image.Quantize.MEDIANCUT, kmeans=3, dither=Image.Dither.NONE).convert("RGB")
        q.save(os.path.join(OUT, f"bg_{key}.png"))
        q.resize((SIZE[0] * 4, SIZE[1] * 4), Image.NEAREST).save(os.path.join(HERE, f"preview_bg_{key}.png"))
        print(key, q.size)


if __name__ == "__main__":
    main()
