"""Phase 2n 第 5 步（2026-11-13）：森林大火 HD-2D 畫面的佔位圖（程式畫的像素圖，之後可以換成正式素材，檔名與尺寸維持）。

輸出到 prototypes/hd2d_tactical/assets/，每一張有 _32 與 _48 兩套（HD2DBoard 照螢幕上一格的大小切換）：
  fire_flame_a/b/c       火焰三格（輪流播放）
  fire_flame_lean_a/b/c  被風吹斜的火焰（往右倒；風往左吹時左右翻）
  fire_small_a/b         剛點燃、還很小的火
  smoke_puff_a/b         煙團（半透明，疊在格子上）
  fire_ember             火星（落下的小亮點）
  burnt_<樹>             燒焦的樹：照原本的樹圖改成焦黑、掉一些葉子（spruce、pine_dark、pine_snow、birch、birch_autumn、
                         shrub、shrub_b、shrub_autumn、dead_tree、log、reeds、tallgrass、tallgrass_cover）
用法：python3 prototypes/fire_escape/prep_fire_art.py（需要 Pillow）
"""
import math
import os
import random

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.normpath(os.path.join(HERE, "..", "hd2d_tactical", "assets"))

# 火的顏色：外緣暗紅 → 紅 → 橘 → 黃 → 中心淡黃
FIRE = [(122, 28, 18), (196, 54, 22), (240, 110, 30), (255, 178, 52), (255, 232, 140)]


def vnoise(x, y, seed):
    """平滑的值雜訊（0～1）"""
    def h(ix, iy):
        n = (ix * 374761393 + iy * 668265263 + seed * 1442695041) & 0xFFFFFFFF
        n = (n ^ (n >> 13)) * 1274126177 & 0xFFFFFFFF
        return ((n ^ (n >> 16)) & 0xFFFF) / 65535.0
    ix, iy = math.floor(x), math.floor(y)
    fx, fy = x - ix, y - iy
    fx = fx * fx * (3 - 2 * fx)
    fy = fy * fy * (3 - 2 * fy)
    a = h(ix, iy) + (h(ix + 1, iy) - h(ix, iy)) * fx
    b = h(ix, iy + 1) + (h(ix + 1, iy + 1) - h(ix, iy + 1)) * fx
    return a + (b - a) * fy


def flame(w, hgt, seed, lean=0.0, tongues=3):
    """一格火焰：底部寬、往上變尖，邊緣有幾條火舌；lean 往右倒（每往上一格偏幾格）"""
    img = Image.new("RGBA", (w, hgt), (0, 0, 0, 0))
    px = img.load()
    for y in range(hgt):
        t = 1.0 - y / (hgt - 1)  # 0 底、1 頂
        for x in range(w):
            cx = (x + 0.5) / w - 0.5 - lean * t * 0.35
            # 外形：底部寬，往上收；幾條火舌讓上緣參差
            width = 0.47 * (1.0 - t) ** 0.85
            tongue = 0.0
            for k in range(tongues):
                ph = seed * 1.7 + k * 2.1
                tongue += 0.05 * max(0.0, math.sin(cx * (9 + k * 3) + ph)) * t * (1.0 - t) * 2.0
            n = vnoise(x * 0.35, y * 0.22 + seed * 3.1, seed)
            edge = width + tongue * 0.6 + (n - 0.5) * 0.18
            d = abs(cx)
            if d > edge or t > 0.97:
                continue
            heat = (1.0 - d / max(edge, 0.001)) * (1.0 - t * 0.75) + (n - 0.5) * 0.25
            idx = 0 if heat < 0.18 else 1 if heat < 0.38 else 2 if heat < 0.58 else 3 if heat < 0.78 else 4
            r, g, b = FIRE[idx]
            px[x, y] = (r, g, b, 255)
    return img


def smoke(w, hgt, seed):
    """煙團：幾個圓疊起來，三階的透明度（像素圖不要漸層）"""
    img = Image.new("RGBA", (w, hgt), (0, 0, 0, 0))
    px = img.load()
    rnd = random.Random(seed)
    blobs = [(rnd.uniform(0.3, 0.7) * w, rnd.uniform(0.45, 0.65) * hgt, rnd.uniform(0.22, 0.34) * w) for _ in range(5)]
    for y in range(hgt):
        for x in range(w):
            v = 0.0
            for bx, by, br in blobs:
                d = math.hypot((x - bx) / br, (y - by) / (br * 0.75))
                v = max(v, 1.0 - d)
            if v <= 0.0:
                continue
            v += (vnoise(x * 0.3, y * 0.3, seed) - 0.5) * 0.3
            if v <= 0.08:
                continue
            a = 90 if v < 0.25 else 150 if v < 0.5 else 200
            shade = 168 + int(30 * (1 - y / hgt))  # 上面亮一點
            px[x, y] = (shade, shade - 4, shade - 10, a)
    return img


def ember(w):
    img = Image.new("RGBA", (w, w), (0, 0, 0, 0))
    px = img.load()
    rnd = random.Random(7)
    for _ in range(max(3, w // 6)):
        x, y = rnd.randrange(1, w - 1), rnd.randrange(1, w - 1)
        px[x, y] = (255, 214, 90, 255)
        if w >= 24:
            px[x + 1, y] = (240, 110, 30, 255)
    return img


def burnt(src, seed, drop):
    """燒焦：亮度壓低、偏暖的黑灰；drop 的比例的不透明像素拿掉（葉子燒光）；樹幹保留"""
    img = src.convert("RGBA").copy()
    px = img.load()
    w, hgt = img.size
    rnd = random.Random(seed)
    for y in range(hgt):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            lum = (0.3 * r + 0.59 * g + 0.11 * b) / 255.0
            greenish = not (r >= g and r > b)  # 不是褐色的樹幹就算葉子
            # 葉子（偏綠）比較會燒掉，越往上越多
            # 成塊燒掉（雜訊，不是一顆一顆的雜點）
            if greenish and vnoise(x * 0.22, y * 0.22, seed) < drop * (0.75 + 0.35 * (1 - y / hgt)):
                px[x, y] = (0, 0, 0, 0)
                continue
            v = int(18 + lum * 55)
            # 偶爾一點餘燼的暗紅
            if rnd.random() < 0.012:
                px[x, y] = (120, 40, 20, a)
            else:
                px[x, y] = (v + 6, v + 2, v, a)
    return img


def snag(src, seed):
    """燒焦的針葉樹：照原圖的高度畫一根焦黑的樹幹，往下斜的短枝（針葉燒光）"""
    w, hgt = src.size
    img = Image.new("RGBA", (w, hgt), (0, 0, 0, 0))
    px = img.load()
    rnd = random.Random(seed)
    top = int(hgt * 0.08)
    cx = w // 2
    col = lambda: (rnd.randint(22, 34), rnd.randint(18, 28), rnd.randint(16, 24), 255)
    for y in range(top, hgt):
        t = (y - top) / (hgt - top)  # 0 頂、1 底
        half = max(0, int(round(0.4 + t * w * 0.05)))
        for x in range(cx - half, cx + half + 1):
            px[x, y] = col()
    y = top + 4
    while y < hgt - 6:
        t = (y - top) / (hgt - top)
        ln = int(2 + t * w * 0.28 * rnd.uniform(0.4, 1.0))
        for side in (-1, 1):
            if rnd.random() < 0.25:
                continue
            for k in range(1, ln):
                xx = cx + side * k
                yy = y + k // 3
                if 0 <= xx < w and yy < hgt:
                    px[xx, yy] = col()
        y += rnd.randint(3, 6)
    for _ in range(3):
        yy = rnd.randint(top, hgt - 1)
        px[cx, yy] = (130, 42, 20, 255)
    return img


def save(img, name, px):
    img.save(os.path.join(OUT, "%s_%d.png" % (name, px)))


def main():
    for px in (32, 48):
        s = px / 32.0
        fw, fh = int(32 * s), int(44 * s)
        for i, k in enumerate("abc"):
            save(flame(fw, fh, 11 + i * 5), "fire_flame_" + k, px)
            save(flame(fw, fh, 11 + i * 5, lean=0.9), "fire_flame_lean_" + k, px)
        for i, k in enumerate("ab"):
            save(flame(int(20 * s), int(22 * s), 40 + i * 3, tongues=2), "fire_small_" + k, px)
            save(smoke(int(48 * s), int(34 * s), 60 + i * 9), "smoke_puff_" + k, px)
        save(ember(int(16 * s)), "fire_ember", px)
        for i, name in enumerate(["spruce", "pine_dark", "pine_snow", "birch", "birch_autumn", "shrub", "shrub_b", "shrub_autumn",
                                  "dead_tree", "log", "reeds", "tallgrass", "tallgrass_cover"]):
            p = os.path.join(OUT, "%s_%d.png" % (name, px))
            if not os.path.exists(p):
                continue
            drop = 0.85 if name in ("spruce", "pine_dark", "pine_snow") else 0.95 if "shrub" in name or "grass" in name or name == "reeds" else 0.7
            if name in ("spruce", "pine_dark", "pine_snow"):
                save(snag(Image.open(p), 100 + i), "burnt_" + name, px)
            else:
                save(burnt(Image.open(p), 100 + i, drop), "burnt_" + name, px)
    print("ok ->", OUT)


if __name__ == "__main__":
    main()
