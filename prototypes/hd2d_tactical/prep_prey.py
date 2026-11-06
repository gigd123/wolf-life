"""戰術狩獵獵物的 HD-2D 素材：沿用 2026-10-13 風格測試留下的高解析度原圖（2026-11-06）。

來源（已經去背的 cut/*.png）：
- arts/art_scene_test_2026-10-13/cut/elk_cow.png、elk_bull.png：像素風的馬鹿母鹿、公鹿
- arts/art_illustrated_test_2026-10-13/cut/hare_summer.png、hare_winter.png：插畫風的雪兔夏毛、冬毛（像素風的冬毛那張肚子下留了白色背景，不用）
處理照 prep_grizzly.py：只留最大的一塊、縮成 32／48，縮小後外面補 1 像素深色外框（同 prep_wolf.py）。
寬幾格照 tactical_hunt 的 hunt_hd2d.json species（母鹿 1.6、公鹿含角 1.8、小馬鹿 1.1 用母鹿縮小、雪兔 0.55、小雪兔 0.4）。

用法：python3.12 -I prototypes/hd2d_tactical/prep_prey.py
"""
import os
import sys

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import prep_grizzly as pg  # noqa: E402
import prep_wolf as pw  # noqa: E402

A = os.path.join(pg.ROOT, "arts")
FRAMES = {
    "hd_elk_cow": ("art_scene_test_2026-10-13/cut/elk_cow.png", 1.6),
    "hd_elk_bull": ("art_scene_test_2026-10-13/cut/elk_bull.png", 1.8),
    "hd_elk_calf": ("art_scene_test_2026-10-13/cut/elk_cow.png", 1.1),
    "hd_snowhare_summer": ("art_illustrated_test_2026-10-13/cut/hare_summer.png", 0.55),
    "hd_snowhare_winter": ("art_illustrated_test_2026-10-13/cut/hare_winter.png", 0.55),
    "hd_snowhare_summer_young": ("art_illustrated_test_2026-10-13/cut/hare_summer.png", 0.4),
    "hd_snowhare_winter_young": ("art_illustrated_test_2026-10-13/cut/hare_winter.png", 0.4),
}


def load(path):
    im = Image.open(os.path.join(A, path)).convert("RGBA")
    w, h = im.size
    px = im.load()
    alpha = [px[i % w, i // w][3] > 40 for i in range(w * h)]
    keep = pg.largest_blob(alpha, w, h)
    out = Image.new("RGBA", (w, h))
    o = out.load()
    for i in range(w * h):
        if keep[i]:
            r, g, b, _ = px[i % w, i // w]
            o[i % w, i // w] = (r, g, b, 255)
    return out.crop(out.getbbox())


def main():
    for name, (src, cells) in FRAMES.items():
        c = load(src)
        for d in pg.DENSITIES:
            out = pw.outline(pg.shrink(c, max(8, round(cells * d))))
            out.save(os.path.join(pg.OUT, "%s_%d.png" % (name, d)))
            print(name, d, out.size)


if __name__ == "__main__":
    main()
