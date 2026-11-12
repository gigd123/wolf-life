"""渡鴉與鮭魚的 HD-2D 素材（2026-11-12，ChatGPT，arts/hd2d_2026-11-06/，綠底）：選單畫面用。

渡鴉 raven_stand（站，約 0.6 格寬）、raven_fly（飛）→ raven_circling：三隻飛的渡鴉排成在天上盤旋（大小、方向錯開），約 1.6 格寬。
黑色的鳥縮小後容易變成一團黑影 → 整體提亮 BRIGHT 倍；外框補一圈 1 像素深色（prep_wolf.outline）。
鮭魚 salmon_swim（游，約 0.6 格寬）、salmon_leap（跳，約 0.55 格寬）。

用法：python3.12 -I prototypes/hd2d_tactical/prep_birds_fish.py
"""
import os
import sys

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import prep_grizzly as pg  # noqa: E402
import prep_wolf as pw  # noqa: E402

# 名稱 → (寬幾格, 提亮倍率)
ITEMS = {
    "raven_stand": (0.6, 1.25),
    "raven_fly": (0.6, 1.25),
    "salmon_swim": (0.6, 1.0),
    "salmon_leap": (0.55, 1.0),
}
# 盤旋：三隻（相對位置 x、y 以格為單位，大小倍率，是否左右翻）
CIRCLING = [(0.0, 0.05, 1.0, False), (0.85, 0.0, 0.8, True), (0.45, 0.42, 0.65, False)]


def main():
    cuts = {}
    for name, (cells, bright) in ITEMS.items():
        c = pg.cut(os.path.join(pg.SRC, name + ".jpg"), "green")
        if bright != 1.0:
            pg.apply_gain(c, [bright] * 3)
        cuts[name] = c
        for d in pg.DENSITIES:
            out = pw.outline(pg.shrink(c, round(cells * d)))
            out.save(os.path.join(pg.OUT, "%s_%d.png" % (name, d)))
            print(name, d, out.size)
    for d in pg.DENSITIES:
        birds = []
        for (x, y, s, flip) in CIRCLING:
            b = pw.outline(pg.shrink(cuts["raven_fly"], round(ITEMS["raven_fly"][0] * s * d)))
            if flip:
                b = b.transpose(Image.FLIP_LEFT_RIGHT)
            birds.append((round(x * d), round(y * d), b))
        w = max(px + b.width for px, py, b in birds)
        h = max(py + b.height for px, py, b in birds)
        out = Image.new("RGBA", (w, h))
        for px, py, b in birds:
            out.alpha_composite(b, (px, py))
        out.save(os.path.join(pg.OUT, "raven_circling_%d.png" % d))
        print("raven_circling", d, out.size)


if __name__ == "__main__":
    main()
