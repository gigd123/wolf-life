"""主視覺場景圖（Gemini）→ 遊戲用的像素背景：面積平均縮到 640×360（和畫面的邏輯尺寸 1:1；原本縮到 320×180 太糊），
再收斂成 256 色調色盤（不抖動），去掉 JPG 雜訊與 AI 圖裡大小不一的方塊。
用法：python3 process_scene.py  → assets/art/art_test/scene/bg_<名稱>.png
"""
import os
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "..", "assets", "art", "art_test", "scene")
SIZE = (640, 360)
COLORS = 256
# 只用 Gemini 的圖（DeeVid 免費版有浮水印，原圖留在 source/ 但不輸出）
SCENES = {"forest_summer": "bg_forest_summer.jpg", "forest_snowy": "bg_forest_snowy.jpg", "forest_winter": "bg_forest_winter.jpg"}


def main():
    os.makedirs(OUT, exist_ok=True)
    for key, fn in SCENES.items():
        im = Image.open(os.path.join(HERE, "source", fn)).convert("RGB")
        small = im.resize(SIZE, Image.BOX)
        q = small.quantize(colors=COLORS, method=Image.Quantize.MEDIANCUT, kmeans=3, dither=Image.Dither.NONE).convert("RGB")
        q.save(os.path.join(OUT, f"bg_{key}.png"))
        q.resize((SIZE[0] * 2, SIZE[1] * 2), Image.NEAREST).save(os.path.join(HERE, f"preview_bg_{key}.png"))
        print(key, q.size)


if __name__ == "__main__":
    main()
