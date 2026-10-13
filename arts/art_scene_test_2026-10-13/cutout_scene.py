"""場景角色的去背：白底＋自帶的灰色影子一起去掉。
從畫面邊緣往內，經過「接近白色」或「接近影子色」的像素都算背景；動物有深色外框擋住，毛色裡的灰不會被吃掉。
用法：python3 cutout_scene.py [名稱…]   → cut/<名稱>.png
"""
import os
import sys

import numpy as np
from PIL import Image
from scipy import ndimage

HERE = os.path.dirname(os.path.abspath(__file__))
# 名稱: (原圖, 影子取樣點；None＝沒有影子)
# 白色門檻：雪兔冬毛偏藍、不會到純白，背景是純 255，所以門檻提高
WHITE_MIN = {"hare_winter": 250}
# 影子到白底的過渡色只算到這個比例（雪兔的白毛和偏白的過渡色太像）
MIX_MAX = {"hare_winter": 0.45}
# 被角和頸圍住的白底洞：面積夠大的純白區塊也當背景
FILL_HOLES = {"elk_bull"}
ITEMS = {
    "wolf_gray2": ("wolf_gray2.jpg", (300, 690)),
    "grizzly2": ("grizzly2.jpg", None),
    "elk_cow": ("elk_cow.jpg", (600, 640)),
    "elk_bull": ("elk_bull.jpg", (500, 640)),
    "hare_winter": ("hare_winter.jpg", (300, 670)),
}


def cut(name):
    fn, shadow_pt = ITEMS[name]
    im = np.asarray(Image.open(os.path.join(HERE, "source", fn)).convert("RGB")).astype(int)
    h, w = im.shape[:2]
    white = (im.min(2) > WHITE_MIN.get(name, 225)) & (im.max(2) - im.min(2) < 24)
    passable = white
    if shadow_pt is not None:
        sc = im[shadow_pt[1], shadow_pt[0]]
        near = np.sqrt(((im - sc) ** 2).sum(2)) < 30
        # 影子和白底之間的過渡色（JPG 的漸層）
        mix = np.zeros_like(near)
        for t in np.linspace(0.15, MIX_MAX.get(name, 0.85), 8):
            c = sc * (1 - t) + 252 * t
            mix |= np.sqrt(((im - c) ** 2).sum(2)) < 14
        passable = white | near | mix
    lab, _ = ndimage.label(passable)
    border = set(np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]]))) - {0}
    bg = np.isin(lab, list(border))
    if name in FILL_HOLES:
        strict = (im.min(2) >= 246) & ~bg
        lab_h, nh = ndimage.label(strict)
        if nh:
            sizes = ndimage.sum(strict, lab_h, range(1, nh + 1))
            big = [i + 1 for i, sz in enumerate(sizes) if sz >= 25]
            hole = np.isin(lab_h, big)
            bg |= ndimage.binary_dilation(hole, iterations=1) & (im.min(2) > 200)
    alpha = (~bg).astype(np.uint8) * 255
    # 去掉零碎的小點，只留最大的一塊（動物本身）
    lab2, n = ndimage.label(alpha > 0)
    if n > 1:
        sizes = ndimage.sum(alpha > 0, lab2, range(1, n + 1))
        alpha = np.where(lab2 == (np.argmax(sizes) + 1), 255, 0).astype(np.uint8)
    out = np.dstack([im.astype(np.uint8), alpha])
    ys, xs = np.nonzero(alpha)
    box = (max(0, xs.min() - 8), max(0, ys.min() - 8), min(w, xs.max() + 9), min(h, ys.max() + 9))
    Image.fromarray(out, "RGBA").crop(box).save(os.path.join(HERE, "cut", name + ".png"))
    return box


if __name__ == "__main__":
    for n in sys.argv[1:] or ITEMS:
        print(n, cut(n))
