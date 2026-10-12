#!/usr/bin/env python3
# 草原的佔位美術（Phase 2 第 4 步）：沿用山地產生器的畫法（arts/art_mountain_2026-10-13/gen_mountain.py）。
# 產生：區域背景 640×360（含冬季版）、地形背景 320×180（草原、丘陵、大河，含冬季版）、區域小圖 18×18。
# 用法：在專案根目錄 python3 arts/art_grassland_2026-10-13/gen_grassland.py
import random, sys
from PIL import Image, ImageDraw
sys.path.insert(0, 'arts/art_mountain_2026-10-13')
import gen_mountain as gm

ARCH = 'arts/art_grassland_2026-10-13/'
PRAIRIE = [(176, 168, 96), (160, 156, 88), (190, 178, 108), (148, 150, 84)]
PRAIRIE_SUMMER = [(150, 160, 84), (166, 168, 92), (136, 150, 76), (176, 172, 100)]
COTTON = (60, 96, 52); COTTON_D = (44, 74, 40)


def cottonwood(d, x, y, r, winter):
    d.line([x, y, x, y - r], fill=(90, 70, 50), width=max(1, r // 6))
    if winter:
        for i in range(6):
            d.line([x, y - r + i * 2, x + (i - 3) * r // 4, y - r - r // 2 + i], fill=(110, 90, 70))
    else:
        d.ellipse([x - r, y - r * 2, x + r, y - r // 2], fill=COTTON)
        d.ellipse([x - r // 2, y - r * 2 + 2, x + r // 2, y - r], fill=COTTON_D)


def hills(d, w, base, rnd, palette, n=4, amp=30):
    for k in range(n):
        y0 = base + k * 18
        pts = [(0, y0 + 40)]
        for i in range(0, w + 40, 40):
            pts.append((i, y0 - rnd.randint(0, amp)))
        pts += [(w, y0 + 200), (0, y0 + 200)]
        d.polygon(pts, fill=palette[k % len(palette)])


def river(d, w, y, width, winter, rnd):
    col = (206, 222, 236) if winter else (84, 128, 176)
    hi = (236, 244, 250) if winter else (150, 190, 226)
    pts = [(x, y + int(6 * ((x // 40) % 3 - 1))) for x in range(0, w + 40, 40)]
    for i in range(width):
        d.line([(px, py + i) for px, py in pts], fill=col)
    for _ in range(w // 8):
        x = rnd.randint(0, w); yy = rnd.randint(y, y + width)
        d.line([x, yy, x + rnd.randint(3, 10), yy], fill=hi)
    # 沙洲
    sx = rnd.randint(w // 4, w // 2)
    d.ellipse([sx, y + width // 3, sx + w // 6, y + width * 2 // 3], fill=(206, 190, 150) if not winter else (226, 230, 236))


def region(name, winter):
    w, h = 640, 360
    rnd = random.Random(name)
    im = Image.new('RGB', (w, h)); d = ImageDraw.Draw(im)
    gm.sky(d, w, h, gm.SKY_TOP_W if winter else gm.SKY_TOP, gm.SKY_BOT_W if winter else (214, 206, 176), rnd)
    gm.clouds(d, w, h, rnd, 4)
    grass = gm.GRASS_W if winter else PRAIRIE
    far = gm.FAR_W if winter else (150, 156, 170)
    if name == 'grassland_riverwoods':
        gm.ridge(d, w, 190, 25, far, rnd, 3)
        gm.bands(d, w, 200, h, gm.GRASS_W if winter else PRAIRIE_SUMMER, rnd)
        river(d, w, 300, 26, winter, rnd)
        for _ in range(12):
            cottonwood(d, rnd.randint(0, w), rnd.randint(250, 300), rnd.randint(14, 26), winter)
    elif name == 'grassland_river':
        gm.ridge(d, w, 180, 20, far, rnd, 3)
        gm.bands(d, w, 190, h, grass, rnd)
        river(d, w, 230, 90, winter, rnd)
        for _ in range(5):
            cottonwood(d, rnd.randint(0, w), rnd.randint(200, 225), rnd.randint(8, 14), winter)
    elif name == 'grassland_plains':
        d.rectangle([0, 205, w, 209], fill=far)
        gm.bands(d, w, 208, h, grass, rnd, 3)
        for _ in range(500):
            d.point((rnd.randint(0, w), rnd.randint(215, h)), fill=rnd.choice(grass))
    elif name == 'grassland_hills':
        gm.ridge(d, w, 175, 30, far, rnd, 4)
        hills(d, w, 190, rnd, grass)
        gm.rocks(d, w, 240, h, rnd, 12, size=(2, 4))
    return im


def terrain(name, winter):
    w, h = 320, 180
    rnd = random.Random('t' + name)
    im = Image.new('RGB', (w, h)); d = ImageDraw.Draw(im)
    gm.sky(d, w, h, gm.SKY_TOP_W if winter else gm.SKY_TOP, gm.SKY_BOT_W if winter else (214, 206, 176), rnd)
    gm.clouds(d, w, h, rnd, 2)
    grass = gm.GRASS_W if winter else PRAIRIE
    if name == 'prairie':
        gm.bands(d, w, 100, h, grass, rnd, 2)
    elif name == 'rolling_hills':
        hills(d, w, 90, rnd, grass, 3, 20)
    elif name == 'river':
        gm.bands(d, w, 95, h, grass, rnd, 2)
        river(d, w, 120, 45, winter, rnd)
    return im


def save(im, path, arch):
    im.save(path)
    im.save(ARCH + arch + '_1x.png')
    im.resize((im.width * 4, im.height * 4), Image.NEAREST).save(ARCH + arch + '_4x.png')


if __name__ == '__main__':
    for r in ['grassland_riverwoods', 'grassland_river', 'grassland_plains', 'grassland_hills']:
        for winter in (False, True):
            im = region(r, winter)
            suffix = '_winter' if winter else ''
            save(im, gm.OUT_REG + r + suffix + '.png', r + suffix)
            if not winter:
                save(im.resize((18, 18), Image.BOX), gm.OUT_ICON + 'region_tile_' + r + '.png', 'region_tile_' + r)
    for t in ['prairie', 'rolling_hills', 'river']:
        for winter in (False, True):
            suffix = '_winter' if winter else ''
            save(terrain(t, winter), gm.OUT_TER + t + suffix + '.png', t + suffix)
    print('done')
