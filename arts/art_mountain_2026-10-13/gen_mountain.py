#!/usr/bin/env python3
# 山地的佔位美術（Phase 2 第 1 步）：程式畫的像素背景，風格比照苔原（漸層天空、遠山剪影、分層地面、雲杉）。
# 產生：區域背景 640×360（含冬季版）、地形背景 320×180（含冬季版）、區域小圖 18×18。
# 用法：在專案根目錄 python3 arts/art_mountain_2026-10-13/gen_mountain.py
import random
from PIL import Image, ImageDraw

OUT_REG = 'assets/art/backgrounds/regions/'
OUT_TER = 'assets/art/backgrounds/terrain/'
OUT_ICON = 'assets/art/icons/'
ARCH = 'arts/art_mountain_2026-10-13/'

SKY_TOP = (92, 132, 186); SKY_BOT = (196, 206, 196)
SKY_TOP_W = (120, 140, 168); SKY_BOT_W = (214, 218, 222)
CLOUD = (238, 234, 222)
FAR = (124, 140, 170); FAR_W = (150, 160, 182)
MID = (96, 110, 120); MID_W = (130, 138, 150)
SNOW = (236, 240, 246); SNOW_SH = (200, 208, 222)
GRASS = [(108, 136, 72), (124, 150, 80), (96, 120, 64), (140, 156, 88)]
GRASS_W = [(226, 230, 236), (214, 220, 230), (236, 238, 242), (204, 212, 224)]
ROCK = [(120, 116, 110), (140, 134, 126), (100, 96, 92), (160, 152, 140)]
SPRUCE = (40, 70, 56); SPRUCE_D = (28, 52, 42)
WATER = (90, 140, 200); WATER_L = (160, 200, 240)


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def sky(d, w, h, top, bot, rnd):
    for y in range(h):
        t = y / max(1, h - 1)
        for x in range(w):
            # 2 色抖動，做出像素畫的漸層
            tt = t + (0.04 if (x + y) % 2 == 0 else 0)
            d.point((x, y), fill=lerp(top, bot, min(1, tt)))


def clouds(d, w, h, rnd, n=3):
    for _ in range(n):
        cx, cy = rnd.randint(0, w - 100), rnd.randint(int(h * 0.05), int(h * 0.25))
        cw = rnd.randint(int(w * 0.08), int(w * 0.2))
        d.rectangle([cx, cy, cx + cw, cy + max(3, h // 60)], fill=CLOUD)
        d.rectangle([cx + cw // 4, cy - max(2, h // 90), cx + cw * 3 // 4, cy], fill=CLOUD)


def ridge(d, w, base, amp, color, rnd, peaks=5, snow=None, jag=1.0):
    pts = [(0, base)]
    step = w / (peaks * 2)
    for i in range(peaks * 2 + 1):
        x = i * step
        y = base - (amp * rnd.uniform(0.6, 1.0) if i % 2 == 1 else amp * rnd.uniform(0.0, 0.35) * jag)
        pts.append((x, y))
    pts.append((w, base))
    poly = pts + [(w, base + 400), (0, base + 400)]
    d.polygon(poly, fill=color)
    if snow:
        for i in range(1, len(pts) - 1, 2):
            x, y = pts[i]
            if y < base - amp * 0.5:
                s = amp * 0.28
                d.polygon([(x, y), (x - s * 0.9, y + s), (x - s * 0.3, y + s * 0.8), (x + s * 0.2, y + s * 1.05), (x + s * 0.9, y + s)], fill=snow)


def bands(d, w, top, bottom, palette, rnd, stripe=4):
    y = top
    while y < bottom:
        hgt = rnd.randint(stripe, stripe * 3)
        d.rectangle([0, y, w, min(bottom, y + hgt)], fill=rnd.choice(palette))
        y += hgt
    # 草葉／碎點
    for _ in range(int(w * (bottom - top) / 40)):
        x, yy = rnd.randint(0, w), rnd.randint(top, bottom)
        d.point((x, yy), fill=rnd.choice(palette))


def spruce(d, x, y, hgt, color=SPRUCE, dark=SPRUCE_D, snow=None):
    for i in range(hgt):
        half = int((i / hgt) * hgt * 0.32) + 1
        c = dark if i % 4 == 3 else color
        d.line([x - half, y - hgt + i, x + half, y - hgt + i], fill=c)
        if snow and i % 4 == 0:
            d.line([x - half, y - hgt + i, x + half // 2, y - hgt + i], fill=snow)
    d.line([x, y, x, y + max(1, hgt // 10)], fill=(70, 50, 36))


def rocks(d, w, top, bottom, rnd, n, palette=ROCK, size=(2, 6)):
    for _ in range(n):
        x, y = rnd.randint(0, w), rnd.randint(top, bottom)
        s = rnd.randint(*size)
        d.polygon([(x - s, y), (x - s // 2, y - s), (x + s // 2, y - s), (x + s, y)], fill=rnd.choice(palette))


def cliff(d, x0, x1, top, bottom, rnd, winter=False):
    # 岩壁：鋸齒狀的頂、不規則的明暗分塊、橫向的岩棚與裂隙
    x0, x1 = int(x0), int(x1)
    tops = []
    y = top
    for x in range(x0, x1 + 1, 6):
        y = max(top - 10, min(top + 30, y + rnd.randint(-8, 8)))
        tops.append((x, y))
    def top_at(x):
        for (ax, ay), (bx, by) in zip(tops, tops[1:]):
            if ax <= x <= bx:
                return int(ay + (by - ay) * (x - ax) / max(1, bx - ax))
        return tops[-1][1]
    # 明暗分塊：每塊寬 8～22，逐欄畫到鋸齒頂為止
    x = x0
    while x < x1:
        bw = rnd.randint(8, 22)
        tone = rnd.choice([ROCK[3], ROCK[1], ROCK[0], ROCK[2]])
        for cx in range(x, min(x1, x + bw)):
            d.line([cx, top_at(cx), cx, bottom], fill=tone)
        edge = min(x1, x + bw)
        d.line([edge, top_at(edge) + 3, edge, bottom], fill=(70, 66, 62))
        x += bw
    # 岩棚
    for _ in range(int((bottom - top) / 14)):
        ly = rnd.randint(top + 10, bottom - 4)
        lx = rnd.randint(x0, x1 - 20)
        ll = rnd.randint(16, 50)
        d.line([lx, ly, min(x1, lx + ll), ly], fill=(66, 62, 58))
        d.line([lx, ly - 1, min(x1, lx + ll), ly - 1], fill=SNOW if winter else (176, 168, 156))
    # 地衣與小草
    for _ in range(int((x1 - x0) * (bottom - top) / 260)):
        d.point((rnd.randint(x0, x1), rnd.randint(top, bottom)), fill=(150, 160, 100) if not winter else SNOW)
    d.line(tops, fill=(60, 56, 52), width=2)


def stream(d, pts, width, winter=False):
    col = (200, 220, 236) if winter else WATER
    d.line(pts, fill=col, width=width)
    d.line(pts, fill=(236, 244, 250) if winter else WATER_L, width=max(1, width // 4))


def region(name, winter):
    w, h = 640, 360
    rnd = random.Random(name)
    im = Image.new('RGB', (w, h)); d = ImageDraw.Draw(im)
    sky(d, w, h, SKY_TOP_W if winter else SKY_TOP, SKY_BOT_W if winter else SKY_BOT, rnd)
    clouds(d, w, h, rnd)
    far, mid = (FAR_W, MID_W) if winter else (FAR, MID)
    grass = GRASS_W if winter else GRASS
    if name == 'mountain_foothills':
        ridge(d, w, 170, 90, far, rnd, 4, SNOW)
        ridge(d, w, 205, 40, mid, rnd, 6, SNOW if winter else None)
        bands(d, w, 205, h, grass, rnd)
        for i in range(26):
            x = rnd.randint(0, w); y = rnd.randint(215, 300)
            spruce(d, x, y, rnd.randint(30, 60), snow=SNOW if winter else None)
        for x in (12, 620, 40):
            spruce(d, x, h, rnd.randint(140, 180), snow=SNOW if winter else None)
        stream(d, [(260, h), (330, 300), (420, 262), (520, 236)], 7, winter)
    elif name == 'mountain_meadow':
        ridge(d, w, 150, 110, far, rnd, 3, SNOW)
        ridge(d, w, 190, 55, mid, rnd, 4, SNOW, jag=1.6)
        bands(d, w, 190, h, grass, rnd, 3)
        rocks(d, w, 200, h, rnd, 40)
        if not winter:
            for _ in range(160):  # 野花
                d.point((rnd.randint(0, w), rnd.randint(220, h)), fill=rnd.choice([(230, 210, 90), (200, 120, 180), (240, 240, 240)]))
        for i in range(6):
            spruce(d, rnd.randint(0, w), rnd.randint(200, 230), rnd.randint(14, 24), snow=SNOW if winter else None)
    elif name == 'mountain_canyon':
        ridge(d, w, 140, 80, far, rnd, 3, SNOW)
        bands(d, w, 230, h, [(150, 140, 120), (130, 124, 110), (170, 158, 136)] if not winter else GRASS_W, rnd, 3)
        cliff(d, 0, 200, 60, h, rnd, winter)
        cliff(d, 460, w, 80, h, rnd, winter)
        # 碎石坡
        d.polygon([(200, h), (200, 200), (300, h)], fill=ROCK[1])
        rocks(d, w, 230, h, rnd, 80, size=(2, 5))
        for i in range(5):
            spruce(d, rnd.randint(210, 450), rnd.randint(240, 280), rnd.randint(20, 34), snow=SNOW if winter else None)
    elif name == 'mountain_headwaters':
        ridge(d, w, 160, 100, far, rnd, 4, SNOW)
        ridge(d, w, 200, 45, mid, rnd, 5, SNOW if winter else None)
        bands(d, w, 200, h, grass, rnd)
        stream(d, [(0, 300), (140, 280), (300, 290), (440, 262), (640, 250)], 10, winter)
        stream(d, [(300, 290), (360, 330), (420, h)], 6, winter)
        for _ in range(30):  # 柳叢
            x, y = rnd.randint(0, w), rnd.randint(240, 320)
            c = (150, 140, 110) if winter else (110, 140, 70)
            d.ellipse([x - 6, y - 5, x + 6, y + 3], fill=c)
        for i in range(10):
            spruce(d, rnd.randint(0, w), rnd.randint(205, 235), rnd.randint(20, 40), snow=SNOW if winter else None)
    return im


def terrain(name, winter):
    w, h = 320, 180
    rnd = random.Random('t' + name)
    im = Image.new('RGB', (w, h)); d = ImageDraw.Draw(im)
    sky(d, w, h, SKY_TOP_W if winter else SKY_TOP, SKY_BOT_W if winter else SKY_BOT, rnd)
    clouds(d, w, h, rnd, 2)
    far, mid = (FAR_W, MID_W) if winter else (FAR, MID)
    grass = GRASS_W if winter else GRASS
    if name == 'alpine_meadow':
        ridge(d, w, 80, 50, far, rnd, 3, SNOW)
        bands(d, w, 95, h, grass, rnd, 2)
        rocks(d, w, 100, h, rnd, 14, size=(1, 3))
        if not winter:
            for _ in range(70):
                d.point((rnd.randint(0, w), rnd.randint(110, h)), fill=rnd.choice([(230, 210, 90), (200, 120, 180)]))
    elif name == 'scree':
        ridge(d, w, 70, 40, far, rnd, 3, SNOW)
        d.polygon([(0, h), (0, 70), (220, h)], fill=ROCK[2])
        d.polygon([(60, h), (260, 80), (w, 90), (w, h)], fill=ROCK[1])
        rocks(d, w, 85, h, rnd, 160, size=(1, 4))
        if winter:
            for _ in range(200):
                d.point((rnd.randint(0, w), rnd.randint(85, h)), fill=SNOW)
    elif name == 'cliff':
        ridge(d, w, 60, 30, far, rnd, 2, SNOW)
        bands(d, w, 150, h, grass, rnd, 2)
        cliff(d, 0, 140, 20, h, rnd, winter)
        cliff(d, 230, w, 40, h, rnd, winter)
        rocks(d, w, 150, h, rnd, 30, size=(1, 3))
    return im


def save(im, path, arch):
    im.save(path)
    im.save(ARCH + arch + '_1x.png')
    im.resize((im.width * 4, im.height * 4), Image.NEAREST).save(ARCH + arch + '_4x.png')


if __name__ == '__main__':
    for r in ['mountain_foothills', 'mountain_meadow', 'mountain_canyon', 'mountain_headwaters']:
        for winter in (False, True):
            im = region(r, winter)
            suffix = '_winter' if winter else ''
            save(im, OUT_REG + r + suffix + '.png', r + suffix)
            if not winter:
                tile = im.resize((18, 18), Image.BOX)
                save(tile, OUT_ICON + 'region_tile_' + r + '.png', 'region_tile_' + r)
    for t in ['alpine_meadow', 'scree', 'cliff']:
        for winter in (False, True):
            suffix = '_winter' if winter else ''
            save(terrain(t, winter), OUT_TER + t + suffix + '.png', t + suffix)
    print('done')
