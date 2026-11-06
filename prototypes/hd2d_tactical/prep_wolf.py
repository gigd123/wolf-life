"""灰狼的 HD-2D 素材處理（2026-11-06）。

來源：Gemini 出的圖（arts/hd2d_2026-11-06/，綠底）。
第二輪（wolf_r2_*，淺灰、黑框粗）是基準：walk 走路、submit 示弱（耳朵壓平、尾巴下垂）、down 帶傷倒地（被打倒）、
threaten 豎毛露牙（示威）、stalk 壓低頭潛行、retreat 尾巴夾住的潛行（撤退、退開）、hurt 帶傷潛行（過了重傷線）、ready 豎毛壓低頭齜牙（準備咬、壓制）。
第一輪（wolf_r1_*，偏灰褐、黑框細）補第二輪沒有的：stand 站、lunge 撲咬、carry 叼著肉；毛色乘倍率調到和第二輪的走路一樣。
處理照 prep_grizzly.py：綠色色鍵去背、只留最大的一塊、縮成 32／48；縮小後外面補一圈 1 像素的深色外框（原圖的細黑框縮小後會不見）。
寬幾格：照畫布換算（每張的狼都差不多佔滿 1024 的畫布），走路寬 1.35 格。

用法：python3.12 -I prototypes/hd2d_tactical/prep_wolf.py
"""
import os
import sys

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import prep_grizzly as pg  # noqa: E402

WALK_CELLS = 1.35
R2 = ["walk", "submit", "down", "threaten", "stalk", "retreat", "hurt", "ready"]
R1 = ["stand", "lunge", "carry"]


def outline(im, col=(30, 28, 28, 255)):
    w, h = im.size
    out = Image.new("RGBA", (w + 2, h + 2))
    out.alpha_composite(im, (1, 1))
    p = out.load()
    a = [[p[x, y][3] for x in range(w + 2)] for y in range(h + 2)]
    for y in range(h + 2):
        for x in range(w + 2):
            if a[y][x] == 0 and any(0 <= x + dx < w + 2 and 0 <= y + dy < h + 2 and a[y + dy][x + dx] for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
                p[x, y] = col
    return out


def main():
    cuts = {n: pg.cut(os.path.join(pg.SRC, "wolf_r2_%s.jpg" % n), "green") for n in R2}
    r1 = {n: pg.cut(os.path.join(pg.SRC, "wolf_r1_%s.jpg" % n), "green") for n in R1}
    target = pg.mean_rgb(cuts["walk"])
    gain = [t / max(1.0, b) for t, b in zip(target, pg.mean_rgb(r1["stand"]))]
    print("第一輪毛色倍率", [round(g, 3) for g in gain])
    for n, c in r1.items():
        cuts[n] = pg.apply_gain(c, gain)
    ref = cuts["walk"].width
    for n, c in cuts.items():
        c.save(os.path.join(pg.SRC, "hdwolf_%s_src.png" % n))
        cells = WALK_CELLS * c.width / ref
        for d in pg.DENSITIES:
            out = outline(pg.shrink(c, round(cells * d)))
            out.save(os.path.join(pg.OUT, "hdwolf_%s_%d.png" % (n, d)))
            print(n, d, out.size, "寬 %.2f 格" % cells)


if __name__ == "__main__":
    main()
