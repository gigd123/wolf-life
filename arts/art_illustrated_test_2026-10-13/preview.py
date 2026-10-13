"""把去背後的動物照遊戲裡的相對大小（相對灰狼高度）放進兩張背景，看整體效果。"""
import os
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
REL = {"wolf_gray": 1.0, "wolf_black": 1.0, "grizzly": 1.5, "elk_cow": 2.0, "elk_bull": 2.6,
       "hare_summer": 0.5, "hare_winter": 0.5}
WOLF_H = 150


def put(bg, name, x, foot_y, flip=False):
    im = Image.open(os.path.join(HERE, "cut", name + ".png"))
    h = int(WOLF_H * REL[name])
    im = im.resize((int(im.width * h / im.height), h), Image.LANCZOS)
    if flip:
        im = im.transpose(Image.FLIP_LEFT_RIGHT)
    bg.alpha_composite(im, (int(x - im.width / 2), int(foot_y - im.height)))


meadow = Image.open(os.path.join(HERE, "source", "bg_meadow.jpg")).convert("RGBA")
put(meadow, "elk_bull", 1010, 640, flip=True)
put(meadow, "elk_cow", 760, 650, flip=True)
put(meadow, "wolf_gray", 330, 720)
put(meadow, "hare_summer", 560, 735, flip=True)
meadow.convert("RGB").save(os.path.join(HERE, "preview_meadow.png"))

forest = Image.open(os.path.join(HERE, "source", "bg_forest.jpg")).convert("RGBA")
put(forest, "grizzly", 1000, 735, flip=True)
put(forest, "wolf_black", 660, 700, flip=True)
put(forest, "wolf_gray", 330, 735)
put(forest, "hare_winter", 520, 760, flip=True)
forest.convert("RGB").save(os.path.join(HERE, "preview_forest.png"))
