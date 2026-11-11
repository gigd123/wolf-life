"""灰狼的 HD-2D 素材處理（2026-11-06）。

來源：Gemini 出的圖（arts/hd2d_2026-11-06/，綠底）。
第二輪（wolf_r2_*，淺灰、黑框粗）是基準：walk 走路、submit 示弱（耳朵壓平、尾巴下垂）、down 帶傷倒地（被打倒）、
threaten 豎毛露牙（示威）、stalk 壓低頭潛行、retreat 尾巴夾住的潛行（撤退、退開）、hurt 帶傷潛行（過了重傷線）、ready 豎毛壓低頭齜牙（準備咬、壓制）。
第一輪（wolf_r1_*，偏灰褐、黑框細）補第二輪沒有的：stand 站、lunge 撲咬、carry 叼著肉；照亮度的排名對應到第二輪走路那張的顏色（肉保留原色）。
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


def _lum(c):
    return 0.299 * c[0] + 0.587 * c[1] + 0.114 * c[2]


def _is_meat(c):
    r, g, b = c[:3]
    return r > 90 and r > g * 1.45 and r > b * 1.25


def match_palette(src, ref):
    import bisect
    rp = sorted([c[:3] for c in ref.getdata() if c[3]], key=_lum)
    sp = src.load()
    w, h = src.size
    vals = sorted(_lum(sp[x, y]) for y in range(h) for x in range(w) if sp[x, y][3] and not _is_meat(sp[x, y]))
    n, m = len(vals), len(rp)
    for y in range(h):
        for x in range(w):
            c = sp[x, y]
            if not c[3] or _is_meat(c):
                continue
            q = bisect.bisect_left(vals, _lum(c)) / max(1, n - 1)
            r = rp[min(m - 1, int(q * (m - 1)))]
            sp[x, y] = (r[0], r[1], r[2], 255)
    return src


def main():
    cuts = {n: pg.cut(os.path.join(pg.SRC, "wolf_r2_%s.jpg" % n), "green") for n in R2}
    r1 = {n: pg.cut(os.path.join(pg.SRC, "wolf_r1_%s.jpg" % n), "green") for n in R1}
    # 第一輪照亮度的排名對應到第二輪走路那張的顏色（色盤對應；比整張乘倍率更接近第二輪的淺灰），肉保留原色
    for n, c in r1.items():
        cuts[n] = match_palette(c, cuts["walk"])
    # 示弱 2026-11-08 換成重畫的（wolf_r3_submit.jpg：低頭、拱背、夾尾巴；原本那張站得太直），照第二輪走路的色盤調色
    r3 = os.path.join(pg.SRC, "wolf_r3_submit.jpg")
    if os.path.exists(r3):
        cuts["submit"] = match_palette(pg.cut(r3, "green"), cuts["walk"])
    # 站、撲咬、叼肉 2026-11-11 換成重畫的（wolf_r5_*.jpg，ChatGPT 照第二輪走路畫：同樣淺灰、粗框；取代第一輪調色），照第二輪走路的色盤調色
    for n in ["stand", "lunge", "carry"]:
        r5 = os.path.join(pg.SRC, "wolf_r5_%s.jpg" % n)
        if os.path.exists(r5):
            cuts[n] = match_palette(pg.cut(r5, "green"), cuts["walk"])
    ref = cuts["walk"].width
    # 咬住不放 2026-11-08（wolf_r4_hold.png，ChatGPT：壓低身子、前腳往前撐、重心在後，咬住往後拉；1536×1024 畫布不同 → 直接指定寬幾格）
    fixed_cells = {}
    r4 = os.path.join(pg.SRC, "wolf_r4_hold.png")
    if os.path.exists(r4):
        cuts["hold"] = match_palette(pg.cut(r4, "green"), cuts["walk"])
        fixed_cells["hold"] = 1.55
    for n, c in cuts.items():
        c.save(os.path.join(pg.SRC, "hdwolf_%s_src.png" % n))
        cells = fixed_cells.get(n, WALK_CELLS * c.width / ref)
        for d in pg.DENSITIES:
            out = outline(pg.shrink(c, round(cells * d)))
            out.save(os.path.join(pg.OUT, "hdwolf_%s_%d.png" % (n, d)))
            print(n, d, out.size, "寬 %.2f 格" % cells)


if __name__ == "__main__":
    main()
