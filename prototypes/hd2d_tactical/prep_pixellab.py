"""PixelLab 出的圖（2026-11-06，arts/pixellab_2026-11-06/；每張 256×256 是 2×2 四個版本，透明背景）。

- wolf_walk_4var.png：灰狼走路，取左上（寬高比約 1.26，最接近第二輪走路的 1.17；右上那隻 1.64 太扁）→ hdwolf_walk_b，照高度對齊第二輪的走路（兩張輪流時不會一高一矮）
- deer_buck_4var.png：白尾鹿雄鹿 4 個版本，取右上 → hd_deer_buck（1.4 格）
- deer_doe_4poses.png：白尾鹿母鹿 4 個姿勢（左上 站、右上 走、左下 低頭吃草、右下 警覺回頭）→ hd_deer_doe（1.3 格）、_walk、_graze、_alert（照站那格的比例）
- carcass_elk_4var.png：馬鹿殘骸，左上（肋骨與淺色臀部最清楚）→ hd_carcass_elk（1.6 格）；右下（傷在腹部）縮小 → hd_carcass_deer（1.2 格，白尾鹿、騾鹿共用）
處理：切出那一格、只留最大的一塊、縮成 32／48、補 1 像素深色外框（同 prep_wolf.py）。

用法：python3.12 -I prototypes/hd2d_tactical/prep_pixellab.py
"""
import os
import sys

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import prep_grizzly as pg  # noqa: E402
import prep_wolf as pw  # noqa: E402

SRC = os.path.join(pg.ROOT, "arts", "pixellab_2026-11-06")
# 名稱 → (來源, 第幾格〔0 左上、1 右上、2 左下、3 右下〕, 寬幾格)
FRAMES = {
    "hdwolf_walk_b": ("wolf_walk_4var.png", 0, "match_height:hdwolf_walk"),
    "hd_carcass_elk": ("carcass_elk_4var.png", 0, 1.6),
    "hd_carcass_deer": ("carcass_elk_4var.png", 3, 1.2),
    # 白尾鹿（2026-11-06）：PixelLab 畫得腿長脖子高，照寬 1.3／1.4 格會和馬鹿一樣高，縮成 1.1／1.2 格（約馬鹿的 0.85 高）；顏色比其他動物鮮豔，飽和度 × 0.8。雄鹿取右上（毛色比較沉，和寫實的狼、馬鹿搭）；母鹿四格是四個姿勢：站、走、低頭吃草、警覺回頭
    "hd_deer_buck": ("deer_buck_4var.png", 1, 1.2),
    # 白尾鹿母鹿 2026-11-07 改用 Gemini 的寫實版（prep_gemini_prey.py 輸出 hd_deer_doe*）；PixelLab 版改名 _old_ 保留
    "_old_hd_deer_doe": ("deer_doe_4poses.png", 0, 1.1),
    "_old_hd_deer_doe_walk": ("deer_doe_4poses.png", 1, "same_scale:_old_hd_deer_doe"),
    "_old_hd_deer_doe_graze": ("deer_doe_4poses.png", 2, "same_scale:_old_hd_deer_doe"),
    "_old_hd_deer_doe_alert": ("deer_doe_4poses.png", 3, "same_scale:_old_hd_deer_doe"),
}


def cell(path, q):
    im = Image.open(path).convert("RGBA")
    w, h = im.size
    c = im.crop(((q % 2) * w // 2, (q // 2) * h // 2, (q % 2 + 1) * w // 2, (q // 2 + 1) * h // 2))
    cw, ch = c.size
    px = c.load()
    keep = pg.largest_blob([px[i % cw, i // cw][3] > 40 for i in range(cw * ch)], cw, ch)
    out = Image.new("RGBA", (cw, ch))
    o = out.load()
    for i in range(cw * ch):
        if keep[i]:
            r, g, b, _ = px[i % cw, i // cw]
            o[i % cw, i // cw] = (r, g, b, 255)
    return out.crop(out.getbbox())


def desaturate(im, k):
    p = im.load()
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, a = p[x, y]
            if a:
                v = 0.299 * r + 0.587 * g + 0.114 * b
                p[x, y] = (int(v + (r - v) * k), int(v + (g - v) * k), int(v + (b - v) * k), a)
    return im


def main():
    for name, (f, q, cells) in FRAMES.items():
        c = cell(os.path.join(SRC, f), q)
        if name.startswith("hd_deer_"):
            c = desaturate(c, 0.8)
        for d in pg.DENSITIES:
            if isinstance(cells, str) and cells.startswith("same_scale:"):
                # 同一張圖裡的其他姿勢：照那一格的「原圖像素 → 格」比例（低頭、走路的寬度不同）
                base = FRAMES[cells.split(":")[1]]
                bc = cell(os.path.join(SRC, base[0]), base[1])
                tw = round(c.width * base[2] * d / bc.width)
            elif isinstance(cells, str):
                # 照另一張的高度（扣掉外框與底下空白的 3 像素）換算寬度
                ref = Image.open(os.path.join(pg.OUT, "%s_%d.png" % (cells.split(":")[1], d)))
                tw = round(c.width * (ref.height - 3) / c.height)
            else:
                tw = round(cells * d)
            out = pw.outline(pg.shrink(c, tw))
            out.save(os.path.join(pg.OUT, "%s_%d.png" % (name, d)))
            print(name, d, c.size, "→", out.size)


if __name__ == "__main__":
    main()
