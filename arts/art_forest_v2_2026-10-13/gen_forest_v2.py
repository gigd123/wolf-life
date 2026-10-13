#!/usr/bin/env python3
# 森林美術第 2 版（2026-10-13，依使用者提供的參考圖改畫，照山地、草原、苔原第 2 版的做法）：
# 層層的針葉林牆（遠的偏藍淡、近的深綠）、點綴金黃與淺綠的闊葉樹（白楊）、高大的松樹、溪流與水塘、倒木、長苔的地面。
# 東部：山區流下的溪谷（遠方雪山、林坡、溪流與石頭）；北部：深林與倒映樹影的小水塘；
# 南部：圓林坡、開闊草地、有蘆葦的水塘、孤立的高松；西部：老林的大樹、斜倒的倒木、苔蘚。
# 冬季：積雪、樹上有雪、水面結冰；燒過：灰黃煙霾的天空、焦黑的枯樹幹、灰燼地面。
# 沿用 arts/art_mountain_2026-10-13/gen_mountain_v2.py 的工具函式。
# 產生：區域背景 640×360（一般、冬季、燒過）4 區、地形背景 320×180（溪流、密林、林緣、空地、倒木區，各三版）、區域小圖。
# 用法：在專案根目錄 python3 arts/art_forest_v2_2026-10-13/gen_forest_v2.py
import math, random, sys
from PIL import Image, ImageDraw
sys.path.insert(0, 'arts/art_mountain_2026-10-13')
import gen_mountain_v2 as gm

ARCH = 'arts/art_forest_v2_2026-10-13/'


class FPal(gm.Pal):
    def __init__(self, mode):
        super().__init__(mode == 'winter')
        self.mode = mode
        self.burned = mode == 'burned'
        if self.burned:
            self.sky_top = (138, 128, 116); self.sky_bot = (196, 178, 150)
            self.far = (128, 120, 112); self.far_shade = (110, 102, 96)
        elif not self.winter:
            self.sky_top = (96, 146, 204); self.sky_bot = (184, 214, 232)
            self.far = (138, 156, 182); self.far_shade = (114, 132, 160)
        # 針葉樹：深、中、亮（燒過是焦黑）
        self.tree = [(26, 56, 42), (40, 82, 56), (70, 116, 74)] if not self.burned else [(30, 26, 24), (44, 38, 34), (60, 52, 46)]
        self.haze = gm.lerp(self.sky_bot, self.far, 0.5)
        self.grass = [(84, 132, 62), (90, 138, 66), (80, 126, 58)] if mode == 'normal' else \
            ([(232, 236, 242), (226, 232, 240), (236, 240, 246)] if self.winter else [(70, 64, 58), (84, 76, 68), (58, 54, 50)])
        self.grass_hi = (150, 190, 96) if mode == 'normal' else ((250, 252, 255) if self.winter else (110, 100, 88))
        self.grass_lo = (58, 96, 46) if mode == 'normal' else ((196, 206, 222) if self.winter else (40, 36, 34))
        self.moss = (92, 136, 60) if mode == 'normal' else ((228, 234, 242) if self.winter else (66, 60, 54))
        self.aspen = [[(196, 160, 52), (226, 196, 76), (168, 128, 40)], [(136, 168, 70), (166, 196, 92), (110, 140, 58)],
                      [(196, 108, 46), (222, 142, 62), (160, 84, 40)]]
        self.water = (70, 110, 120) if mode == 'normal' else ((190, 210, 226) if self.winter else (70, 74, 76))
        self.water_hi = (150, 196, 206) if mode == 'normal' else ((236, 244, 250) if self.winter else (110, 112, 112))
        self.log = [(96, 70, 48), (120, 90, 62), (74, 54, 38)] if not self.burned else [(36, 32, 30), (52, 46, 42), (26, 24, 22)]


def tree(d, x, base, hgt, pal, rnd, far=0.0):
    """針葉樹；far（0～1）越大越偏霧色（遠的林子）。燒過時是焦黑的枯樹幹。"""
    if pal.burned:
        snag(d, x, base, hgt, pal, rnd)
        return
    if far > 0:
        save = pal.tree
        pal.tree = [gm.lerp(c, pal.haze, far) for c in save]
        gm.conifer(d, x, base, hgt, pal, rnd, snow=pal.winter)
        pal.tree = save
    else:
        gm.conifer(d, x, base, hgt, pal, rnd, snow=pal.winter)


def snag(d, x, base, hgt, pal, rnd):
    """燒過的枯樹：焦黑的樹幹、幾根斷枝。"""
    dark, mid, _ = pal.tree
    d.line([x, base, x, base - hgt], fill=dark, width=max(1, hgt // 22))
    for i in range(hgt // 8):
        y = base - hgt + 4 + i * 6 + rnd.randint(0, 3)
        ln = rnd.randint(1, max(2, hgt // 10))
        d.line([x, y, x + rnd.choice([-1, 1]) * ln, y - rnd.randint(0, 2)], fill=mid)


def understory(d, w, y0, y1, pal):
    """林下陰影：林牆底部先鋪一層深色，樹幹之間才不會透出天空。"""
    col = pal.tree[0] if not pal.burned else (52, 46, 42)
    if pal.winter:
        col = gm.lerp(pal.tree[0], (200, 210, 224), 0.35)
    d.rectangle([0, y0, w, y1], fill=col)


def forest_wall(d, w, base, rnd, pal, rows, far0=0.6, far1=0.0, h0=26, h1=46, spacing=7, step=6):
    """一層層的林牆：遠的矮、淡、密，近的高、深；每層往下 step 像素。最後一層的樹幹底部先墊林下陰影。"""
    last = base + int((rows - 1) * step)
    understory(d, w, last - int(h1 * 0.35), last + 3, pal)
    for r in range(rows):
        t = r / max(1, rows - 1)
        far = far0 + (far1 - far0) * t
        hgt = int(h0 + (h1 - h0) * t)
        y = base + int(r * step)
        x = rnd.randint(-spacing, 0)
        while x < w + spacing:
            tree(d, x, y + rnd.randint(-3, 3), hgt + rnd.randint(-hgt // 4, hgt // 5), pal, rnd, far)
            x += spacing + rnd.randint(0, spacing)


def aspen(d, x, base, hgt, pal, rnd, palette=None):
    """闊葉樹（白楊）：白樹幹、成團的圓樹冠（金黃、淺綠或橘）。冬季只剩白樹幹與細枝，燒過是枯幹。"""
    if pal.burned:
        snag(d, x, base, hgt, pal, rnd)
        return
    trunk = (214, 210, 196)
    d.line([x, base, x, base - hgt], fill=trunk, width=max(1, hgt // 18))
    for i in range(0, hgt, 5):
        d.point((x, base - i), fill=(70, 66, 60))
    if pal.winter:
        for i in range(5):
            d.line([x, base - hgt + 4, x + (i - 2) * hgt // 8, base - hgt - rnd.randint(2, hgt // 4)], fill=(150, 140, 126))
        return
    dark, mid, light = palette or rnd.choice(pal.aspen)
    r = max(4, hgt // 3)
    for i in range(6):
        cx = x + rnd.randint(-r // 2, r // 2); cy = base - hgt + r // 2 + rnd.randint(0, r)
        d.ellipse([cx - r, cy - r, cx + r, cy + r * 3 // 4], fill=dark)
    for i in range(3):
        cx = x + rnd.randint(-r // 2, r // 3); cy = base - hgt + r // 2 + rnd.randint(-1, r // 2)
        d.ellipse([cx - r * 2 // 3, cy - r * 2 // 3, cx + r // 3, cy + r // 3], fill=mid)
    d.ellipse([x - r // 2, base - hgt, x, base - hgt + r // 2], fill=light)


def tall_pine(d, x, base, hgt, pal, rnd):
    """高大的松樹：細長的紅褐樹幹，樹冠集中在上面三分之一、成團（參考圖的前景大松）。"""
    if pal.burned:
        snag(d, x, base, hgt, pal, rnd)
        return
    d.line([x, base, x, base - hgt], fill=(110, 66, 46), width=max(2, hgt // 30))
    dark, mid, light = pal.tree
    for i in range(6):
        cy = base - hgt + i * hgt // 14
        hw = 3 + i * hgt // 60 + rnd.randint(0, 2)
        side = rnd.choice([-1, 1])
        d.polygon([(x, cy - 2), (x + side * hw * 2, cy + 3), (x - side * hw, cy + 4)], fill=dark)
        d.line([x, cy, x + side * hw * 2 - side, cy + 2], fill=mid)
        if pal.winter:
            d.line([x, cy - 1, x + side * hw, cy + 1], fill=pal.snow)
    d.polygon([(x, base - hgt - 6), (x - 3, base - hgt + 2), (x + 3, base - hgt + 2)], fill=dark)


def ground(px, w, h, y0, pal, rnd, horizon=None):
    """草地／雪地／灰燼：深淺交錯的底色，加亮點、暗點與小草叢。"""
    hz = horizon if horizon is not None else y0
    n = gm.Noise(rnd, 30)
    for y in range(y0, h):
        for x in range(w):
            v = n.at(x, y)
            c = pal.grass[min(len(pal.grass) - 1, int(v * len(pal.grass)))]
            r = rnd.random()
            if r < 0.07:
                c = pal.grass_hi
            elif r < 0.13:
                c = pal.grass_lo
            px[x, y] = c
    for _ in range(int(w * (h - y0) / 60)):
        y = rnd.randint(y0 + 2, h - 1); t = (y - hz) / max(1, h - hz)
        x = rnd.randint(0, w - 1)
        for k in range(1 + int(t * 4)):
            if 0 <= y - k < h:
                px[x, y - k] = pal.grass_hi if k else pal.grass_lo
    if pal.burned:  # 灰燼裡零星的焦黑與殘火
        for _ in range(int(w * (h - y0) / 300)):
            x = rnd.randint(0, w - 1); y = rnd.randint(y0, h - 1)
            px[x, y] = rnd.choice([(26, 22, 20), (26, 22, 20), (180, 90, 40)])


def flowers(px, w, h, y0, pal, rnd, n):
    if pal.mode != 'normal':
        return
    for _ in range(n):
        x = rnd.randint(0, w - 1); y = rnd.randint(y0 + 3, h - 1)
        px[x, y] = rnd.choice([(232, 202, 64), (240, 240, 230), (170, 130, 200), (220, 110, 90)])


def water_poly(d, pts, pal, rnd, reflect=None):
    d.polygon(pts, fill=pal.water)
    xs = [p[0] for p in pts]; ys = [p[1] for p in pts]
    for _ in range((max(xs) - min(xs)) // 3):
        x = rnd.randint(min(xs), max(xs)); y = rnd.randint(min(ys) + 2, max(ys) - 1)
        d.line([x, y, x + rnd.randint(2, 7), y], fill=pal.water_hi)


def reeds(d, x0, x1, y, pal, rnd, n):
    if pal.burned:
        return
    col = [(110, 140, 64), (136, 160, 76), (90, 118, 54)] if not pal.winter else [(170, 156, 120), (150, 138, 108)]
    for _ in range(n):
        x = rnd.randint(x0, x1); hgt = rnd.randint(4, 10)
        d.line([x, y, x + rnd.randint(-1, 1), y - hgt], fill=rnd.choice(col))


def log(d, x, y, length, slope, pal, th=11):
    """倒木：斜躺的樹幹（th 是粗細，近的粗），深色輪廓、上亮下暗，切口淡色年輪，上面長苔。"""
    dark, mid, light = pal.log[2], pal.log[0], pal.log[1]
    x2, y2 = x + length, y + int(length * slope)
    r = th // 2
    d.line([x, y, x2, y2], fill=(30, 22, 16), width=th)
    d.line([x, y, x2, y2], fill=dark, width=th - 2)
    d.line([x, y - r // 3, x2, y2 - r // 3], fill=mid, width=max(2, th // 2))
    d.line([x, y - r + 2, x2, y2 - r + 2], fill=light, width=max(1, th // 6))
    d.ellipse([x2 - r, y2 - r, x2 + r, y2 + r], fill=(30, 22, 16))
    d.ellipse([x2 - r + 1, y2 - r + 1, x2 + r - 1, y2 + r - 1], fill=(196, 168, 120) if not pal.burned else (60, 54, 50))
    d.ellipse([x2 - r // 2, y2 - r // 2, x2 + r // 2, y2 + r // 2], fill=(170, 140, 96) if not pal.burned else (48, 44, 40))
    if not pal.burned:
        for i in range(0, length, 4):
            d.line([x + i, y + int(i * slope) - r + 1, x + i + 2, y + int(i * slope) - r + 1], fill=pal.moss)


def region(name, mode):
    w, h = 640, 360
    rnd = random.Random(name + 'v2')
    pal = FPal(mode)
    im, px, d = gm.new(w, h)
    if name == 'forest_east':
        # 山區流下的溪谷：遠方雪山、林坡、蜿蜒的溪流與石頭、兩側高松
        gm.sky(px, w, h, h, pal); gm.clouds(d, w, rnd, 3, (20, 70))
        gm.peaks(d, rnd, 196, [(300, 130, 150), (470, 100, 130), (150, 90, 120)], pal, snow_frac=0.4)
        forest_wall(d, w, 186, rnd, pal, 4, 0.65, 0.3, 18, 28, 6, 7)
        ground(px, w, h, 212, pal, rnd, 200)
        forest_wall(d, w, 210, rnd, pal, 1, 0.2, 0.2, 30, 30, 9)
        pts = [(300, 212), (286, 240), (316, 270), (270, 310), (220, 360)]
        for i in range(14):
            d.line([(x - 7 + i, y) for x, y in pts], fill=pal.water)
        for _ in range(60):
            i = rnd.randint(0, len(pts) - 2); t = rnd.random()
            x = int(pts[i][0] + (pts[i + 1][0] - pts[i][0]) * t) + rnd.randint(-5, 5)
            y = int(pts[i][1] + (pts[i + 1][1] - pts[i][1]) * t)
            d.line([x, y, x + rnd.randint(2, 5), y], fill=pal.water_hi)
        for _ in range(16):
            y = rnd.randint(230, 350); s = 2 + (y - 220) // 22
            gm.boulder(px, w, h, rnd.randint(150, 380), y, s + rnd.randint(1, 4), s, rnd.choice(pal.rock), rnd,
                       moss=pal.moss, snow=pal.snow if pal.winter else None)
        flowers(px, w, h, 230, pal, rnd, 120)
        for x, ht in [(20, 190), (70, 150), (600, 200), (560, 140)]:
            tall_pine(d, x, 362, ht, pal, rnd)
        for x in (110, 520):
            tree(d, x, 330, 70, pal, rnd)
    elif name == 'forest_north':
        # 深林：層層的雲杉林牆，前景小水塘倒映樹影，色調偏冷
        gm.sky(px, w, h, h, pal)
        understory(d, w, 170, 246, pal)
        forest_wall(d, w, 110, rnd, pal, 9, 0.7, 0.05, 30, 80, 8, 14)
        ground(px, w, h, 238, pal, rnd, 200)
        forest_wall(d, w, 244, rnd, pal, 1, 0.0, 0.0, 70, 70, 16)
        pool = [(180, 300), (250, 286), (380, 284), (470, 296), (430, 322), (250, 326)]
        water_poly(d, pool, pal, rnd)
        if not pal.burned:  # 水面上緣倒映的林影
            d.polygon([(200, 290), (250, 288), (380, 286), (450, 296), (440, 302), (210, 300)], fill=gm.mul(pal.water, 0.72))
        reeds(d, 180, 470, 300, pal, rnd, 40)
        for x, ht in [(30, 140), (620, 150)]:
            tree(d, x, 364, ht, pal, rnd)
    elif name == 'forest_south':
        # 林緣草地：圓林坡、開闊草地、有蘆葦的水塘、孤立的高松
        gm.sky(px, w, h, h, pal); gm.clouds(d, w, rnd, 4, (20, 80))
        d.ellipse([260, 120, 560, 300], fill=gm.lerp(pal.tree[1], pal.haze, 0.25) if not pal.burned else pal.far)
        for _ in range(120):  # 圓林坡上密密的樹梢
            ang = rnd.uniform(math.pi * 1.05, math.pi * 1.95)
            rr = rnd.uniform(0.6, 1.0)
            x = int(410 + 150 * rr * math.cos(ang)); y = int(210 + 90 * rr * math.sin(ang)) + 4
            tree(d, x, y, rnd.randint(8, 14), pal, rnd, 0.35)
        forest_wall(d, w, 196, rnd, pal, 3, 0.5, 0.3, 22, 30, 7, 8)
        ground(px, w, h, 216, pal, rnd, 200)
        flowers(px, w, h, 220, pal, rnd, 300)
        pond = [(80, 286), (200, 274), (320, 280), (330, 300), (200, 312), (90, 306)]
        water_poly(d, pond, pal, rnd)
        reeds(d, 70, 340, 292, pal, rnd, 60)
        reeds(d, 60, 340, 314, pal, rnd, 60)
        for x, b, ht in [(120, 236, 70), (150, 240, 56), (500, 250, 90)]:
            tall_pine(d, x, b, ht, pal, rnd)
        aspen(d, 600, 290, 60, pal, rnd, pal.aspen[1])
    elif name == 'forest_west':
        # 最深的老林：大樹、斜倒的倒木、長苔的地面，點綴金黃的闊葉樹
        gm.sky(px, w, h, h, pal)
        understory(d, w, 160, 216, pal)
        forest_wall(d, w, 100, rnd, pal, 8, 0.6, 0.1, 34, 80, 9, 14)
        for _ in range(9):
            aspen(d, rnd.randint(0, w), rnd.randint(170, 214), rnd.randint(46, 66), pal, rnd)
        ground(px, w, h, 214, pal, rnd, 190)
        for x, y, ln, sl in [(420, 246, 120, 0.15), (60, 260, 140, 0.12), (300, 300, 180, -0.08), (120, 330, 130, -0.05)]:
            log(d, x, y, ln, sl, pal, 8 + (y - 214) // 8)
        for x, ht in [(18, 220), (560, 210), (630, 180)]:
            tree(d, x, 362, ht // 2, pal, rnd)
            if not pal.burned:
                d.line([x, 362, x, 362 - ht // 2], fill=(84, 60, 44), width=4)
        aspen(d, 250, 236, 70, pal, rnd, pal.aspen[0])
        aspen(d, 470, 230, 64, pal, rnd, pal.aspen[2])
    return im


def terrain(name, mode):
    w, h = 320, 180
    rnd = random.Random('t2' + name)
    pal = FPal(mode)
    im, px, d = gm.new(w, h)
    gm.sky(px, w, h, h, pal)
    if name == 'stream':
        forest_wall(d, w, 92, rnd, pal, 2, 0.5, 0.2, 22, 32, 6)
        ground(px, w, h, 104, pal, rnd)
        pts = [(160, 104), (150, 130), (176, 152), (140, 180)]
        for i in range(12):
            d.line([(x - 6 + i, y) for x, y in pts], fill=pal.water)
        for _ in range(30):
            d.point((rnd.randint(140, 180), rnd.randint(110, 178)), fill=pal.water_hi)
        for _ in range(8):
            y = rnd.randint(120, 175); s = 2 + (y - 110) // 18
            gm.boulder(px, w, h, rnd.randint(110, 210), y, s + 2, s, rnd.choice(pal.rock), rnd, moss=pal.moss,
                       snow=pal.snow if pal.winter else None)
    elif name == 'dense_forest':
        understory(d, w, 100, 152, pal)
        forest_wall(d, w, 50, rnd, pal, 8, 0.55, 0.0, 30, 70, 7, 13)
        ground(px, w, h, 150, pal, rnd)
        forest_wall(d, w, 160, rnd, pal, 1, 0.0, 0.0, 90, 90, 18)
    elif name == 'forest_edge':
        forest_wall(d, w, 96, rnd, pal, 3, 0.4, 0.0, 30, 56, 7)
        ground(px, w, h, 110, pal, rnd)
        flowers(px, w, h, 120, pal, rnd, 80)
        aspen(d, 260, 130, 46, pal, rnd)
    elif name == 'clearing':
        gm.clouds(d, w, rnd, 2, (10, 40))
        forest_wall(d, w, 100, rnd, pal, 2, 0.5, 0.25, 22, 30, 6)
        ground(px, w, h, 108, pal, rnd)
        flowers(px, w, h, 112, pal, rnd, 140)
    elif name == 'fallen_logs':
        forest_wall(d, w, 80, rnd, pal, 3, 0.5, 0.1, 30, 50, 8, 10)
        ground(px, w, h, 102, pal, rnd)
        for x, y, ln, sl in [(20, 140, 120, 0.1), (150, 160, 140, -0.1), (90, 172, 90, 0.04)]:
            log(d, x, y, ln, sl, pal, 6 + (y - 120) // 6)
    return im


def save(im, path, arch):
    im.save(path)
    im.save(ARCH + arch + '_1x.png')
    im.resize((im.width * 4, im.height * 4), Image.NEAREST).save(ARCH + arch + '_4x.png')


if __name__ == '__main__':
    SUF = {'normal': '', 'winter': '_winter', 'burned': '_burned'}
    for r in ['forest_east', 'forest_north', 'forest_south', 'forest_west']:
        for mode in ('normal', 'winter', 'burned'):
            im = region(r, mode)
            save(im, gm.OUT_REG + r + SUF[mode] + '.png', r + SUF[mode])
            if mode == 'normal':
                save(im.resize((18, 18), Image.BOX), gm.OUT_ICON + 'region_tile_' + r + '.png', 'region_tile_' + r)
    for t in ['stream', 'dense_forest', 'forest_edge', 'clearing', 'fallen_logs']:
        for mode in ('normal', 'winter', 'burned'):
            save(terrain(t, mode), gm.OUT_TER + t + SUF[mode] + '.png', t + SUF[mode])
    print('done')
