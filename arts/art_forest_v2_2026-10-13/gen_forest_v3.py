#!/usr/bin/env python3
# 森林美術第 3 版（2026-10-13，使用者看過第 2 版後的方向：以「人在森林裡面看出去」為主，只有一區是林中空地；
# 參考圖是像素畫的林內場景與闊葉林）：
# 層次分明的林內：頂部濃密的樹冠、遠處淡而帶霧的樹幹、近處粗大深色的樹幹與樹根、蕨類與灌木叢、林子深處透出的光。
# 樹冠由許多小葉團疊成不規則的大團塊（每團暗、中、亮三層），不再是單顆圓球。
# 四版：一般（春夏的綠）、秋季（闊葉樹變金黃、橘、紅，針葉樹仍是綠的，地上有落葉）、冬季（闊葉樹落葉剩枝條、積雪）、燒過（焦黑的樹幹、灰燼、煙霾）。
# 西部：老林（粗大的闊葉老樹、倒木、小徑）；北部：深林（雲杉樹幹、苔蘚、小水塘）；東部：溪谷（兩側是樹、中間看到遠山、溪流）；
# 南部：林中空地（四周針闊混合的林牆、草地、水塘）。
# 產生：區域背景 640×360（一般、秋季、冬季、燒過）4 區、地形背景 320×180（溪流、密林、林緣、空地、倒木區，各四版）、區域小圖。
# 用法：在專案根目錄 python3 arts/art_forest_v2_2026-10-13/gen_forest_v3.py
import math, random, sys
from PIL import Image, ImageDraw
sys.path.insert(0, 'arts/art_mountain_2026-10-13')
import gen_mountain_v2 as gm
import gen_forest_v2 as v2

ARCH = 'arts/art_forest_v2_2026-10-13/'
SUF = {'normal': '', 'autumn': '_autumn', 'winter': '_winter', 'burned': '_burned'}

LEAF_GREEN = [(34, 70, 40), (52, 102, 50), (88, 142, 64), (140, 186, 92)]
LEAF_DEEP = [(26, 54, 34), (40, 82, 44), (66, 116, 56), (110, 156, 80)]
CONIFER = [(22, 46, 36), (34, 66, 48), (54, 92, 62), (86, 124, 80)]
AUTUMN = [[(140, 96, 28), (198, 146, 38), (234, 192, 70), (250, 226, 132)],   # 金黃
          [(140, 60, 28), (198, 94, 40), (230, 138, 58), (246, 184, 100)],     # 橘
          [(110, 34, 30), (170, 48, 36), (212, 78, 50), (238, 128, 88)]]       # 紅


class P:
    def __init__(self, mode):
        self.mode = mode
        self.winter = mode == 'winter'
        self.burned = mode == 'burned'
        self.autumn = mode == 'autumn'
        self.glow = {'normal': (184, 214, 160), 'autumn': (232, 210, 150), 'winter': (214, 222, 232), 'burned': (176, 156, 132)}[mode]
        self.deep = {'normal': (40, 70, 52), 'autumn': (70, 66, 46), 'winter': (110, 124, 140), 'burned': (60, 52, 46)}[mode]
        self.trunk = [(44, 32, 26), (64, 46, 36), (96, 72, 54)] if not self.burned else [(22, 20, 20), (34, 30, 28), (48, 42, 38)]
        self.ground = {'normal': [(72, 118, 52), (76, 124, 55), (68, 112, 50)], 'autumn': [(120, 110, 52), (136, 100, 48), (104, 104, 50)],
                       'winter': [(228, 234, 242), (218, 226, 238), (236, 240, 246)], 'burned': [(66, 60, 56), (78, 72, 66), (56, 52, 48)]}[mode]
        self.ground_hi = {'normal': (132, 178, 84), 'autumn': (214, 150, 60), 'winter': (250, 252, 255), 'burned': (100, 92, 84)}[mode]
        self.path = {'normal': (150, 120, 82), 'autumn': (160, 124, 82), 'winter': (206, 210, 220), 'burned': (90, 82, 76)}[mode]
        self.snow = (240, 244, 250)
        self.water = (60, 98, 104) if mode in ('normal', 'autumn') else ((190, 210, 226) if self.winter else (66, 70, 72))
        self.water_hi = (140, 186, 196) if mode in ('normal', 'autumn') else ((236, 244, 250) if self.winter else (104, 108, 108))
        self.rock = [(116, 118, 116), (132, 134, 130), (100, 102, 100)]

    def leaves(self, rnd, kind='broad'):
        """這棵樹的葉色（4 層：暗、中、亮、高光）。冬季與燒過的闊葉樹沒有葉子（回傳 None）。"""
        if kind == 'conifer':
            return None if self.burned else CONIFER
        if self.winter or self.burned:
            return None
        if self.autumn:
            return rnd.choice(AUTUMN + [LEAF_GREEN])  # 秋季：多數變色，偶爾還綠
        return rnd.choice([LEAF_GREEN, LEAF_DEEP])


def fog(c, glow, k):
    return gm.lerp(c, glow, k)


def foliage(d, cx, cy, rx, ry, cols, rnd, density=1.0, haze=0.0, glow=None, snow=False):
    """不規則的樹冠：許多小葉團疊在一起，每團暗（偏下）、中、亮（偏左上）三層，再點高光。haze 越大越偏霧色（遠的）。"""
    if glow is not None and haze > 0:
        cols = [fog(c, glow, haze) for c in cols]
    dark, mid, light, hi = cols
    n = max(4, int(rx * ry / 18 * density))
    blobs = []
    for _ in range(n):
        a = rnd.uniform(0, 6.283); r = math.sqrt(rnd.random())
        x = int(cx + math.cos(a) * rx * r); y = int(cy + math.sin(a) * ry * r)
        rr = rnd.randint(3, max(4, min(rx, ry) // 3))
        blobs.append((x, y, rr))
    for x, y, rr in blobs:
        d.ellipse([x - rr, y - rr + 2, x + rr, y + rr + 2], fill=dark)
    for x, y, rr in blobs:
        d.ellipse([x - rr + 1, y - rr, x + rr - 1, y + rr - 1], fill=mid)
    for x, y, rr in blobs:
        if (x - cx) / max(1, rx) + (y - cy) / max(1, ry) < 0.2 and rr > 2:
            d.ellipse([x - rr + 1, y - rr, x + rr // 3, y - rr // 3], fill=light)
    for x, y, rr in blobs[: n // 4]:
        if (y - cy) < 0:
            d.point((x - rr // 2, y - rr + 1), fill=hi)
    if snow:
        for x, y, rr in blobs:
            if (y - cy) < ry * 0.2:
                d.line([x - rr + 2, y - rr, x + rr - 2, y - rr], fill=(240, 244, 250))


def trunk(d, x, base, top, wb, wt, cols, rnd, roots=True, bark=True):
    """樹幹：上窄下寬，右側暗、左側亮，直向樹皮紋，底部樹根往外伸。"""
    dark, mid, light = cols
    d.polygon([(x - wb // 2, base), (x - wt // 2, top), (x + wt // 2, top), (x + wb // 2, base)], fill=mid)
    d.polygon([(x + wb // 6, base), (x + wt // 6, top), (x + wt // 2, top), (x + wb // 2, base)], fill=dark)
    d.line([(x - wb // 2 + 1, base), (x - wt // 2 + 1, top)], fill=light)
    if bark:
        for _ in range(max(2, wb // 3)):
            bx = x + rnd.randint(-wb // 3, wb // 3)
            y0 = rnd.randint(top, base - 4)
            d.line([bx, y0, bx, min(base, y0 + rnd.randint(4, 14))], fill=dark)
    if roots:
        for side in (-1, 1):
            for k in range(2):
                rx = x + side * (wb // 2 + rnd.randint(2, 4 + wb // 3))
                d.polygon([(x + side * (wb // 2 - 2), base - 6 - k * 3), (rx, base + 1), (x + side * (wb // 4), base + 1)], fill=mid if k else dark)


def broad_tree(d, x, base, hgt, wb, p, rnd, haze=0.0, crown=1.0):
    """闊葉樹：樹幹、往上分岔的枝條、樹冠由幾團不規則的葉團組成；冬季只剩枝條（樹梢有雪），燒過是焦黑枯枝。"""
    tcols = [fog(c, p.glow, haze) for c in p.trunk]
    top = base - int(hgt * 0.55)
    trunk(d, x, base, top, wb, max(2, wb // 2), tcols, rnd, roots=haze < 0.3, bark=haze < 0.5)
    leaves = p.leaves(rnd)
    branches = []
    for i in range(rnd.randint(3, 5)):
        side = rnd.choice([-1, 1])
        sx, sy = x, top + rnd.randint(0, int(hgt * 0.15))
        ex = x + side * rnd.randint(int(hgt * 0.12), int(hgt * 0.32))
        ey = base - hgt + rnd.randint(0, int(hgt * 0.25))
        d.line([sx, sy, (sx + ex) // 2, (sy + ey) // 2 + 2, ex, ey], fill=tcols[1], width=max(1, wb // 4))
        branches.append((ex, ey))
    if leaves is None:  # 冬季、燒過：細枝
        for ex, ey in branches:
            for _ in range(3):
                d.line([ex, ey, ex + rnd.randint(-8, 8), ey - rnd.randint(4, 12)], fill=tcols[0])
            if p.winter:
                d.line([ex - 2, ey, ex + 2, ey], fill=p.snow)
        return
    cr = int(hgt * 0.3 * crown)
    for ex, ey in branches:
        foliage(d, ex, ey, cr, int(cr * 0.75), leaves, rnd, haze=haze, glow=p.glow)
    foliage(d, x, base - hgt + cr // 2, int(cr * 1.2), int(cr * 0.8), leaves, rnd, haze=haze, glow=p.glow)


def spruce_trunk(d, x, base, hgt, w, p, rnd, haze=0.0):
    """林內的雲杉：直挺的深色樹幹，下段有枯枝，上段是一層層下垂的枝葉。"""
    tcols = [fog(c, p.glow, haze) for c in p.trunk]
    trunk(d, x, base, base - hgt, w, max(2, w // 2), tcols, rnd, roots=haze < 0.3, bark=haze < 0.4)
    for i in range(hgt // 10):
        y = base - hgt // 3 - i * 6
        if y < base - hgt:
            break
        d.line([x, y, x + rnd.choice([-1, 1]) * rnd.randint(3, 6), y + 2], fill=tcols[0])
    if p.burned:
        return
    cols = [fog(c, p.glow, haze) for c in CONIFER]
    for i in range(hgt // 7):
        y = base - hgt + i * 6
        # 枝葉往下漸寬，但有上限（粗樹幹不會畫出橫跨畫面的大三角）
        hw = min(3 + i * (2 + w // 8), 8 + w * 2)
        if y > base - hgt // 2:
            break
        d.polygon([(x, y - 3), (x - hw, y + 4), (x + hw, y + 4)], fill=cols[0])
        d.polygon([(x, y - 3), (x - hw, y + 4), (x, y + 3)], fill=cols[1])
        if p.winter:
            d.line([x - hw + 1, y + 3, x - 1, y - 2], fill=p.snow)


def canopy_band(d, w, y, p, rnd, kind='broad'):
    """頂部濃密的樹冠（林內往上看）。冬季的闊葉林是交錯的枝條，燒過沒有。"""
    if p.burned:
        return
    if kind == 'conifer':
        cols = CONIFER if not p.winter else [gm.lerp(c, (220, 228, 238), 0.3) for c in CONIFER]
        for x in range(-30, w + 30, 26):
            foliage(d, x + rnd.randint(-6, 6), y + rnd.randint(-4, 8), 34, 26, cols, rnd, snow=p.winter)
        return
    if p.winter:
        for _ in range(w // 3):
            x = rnd.randint(0, w); yy = rnd.randint(0, y + 20)
            d.line([x, yy, x + rnd.randint(-20, 20), yy + rnd.randint(4, 18)], fill=gm.lerp(p.trunk[1], p.glow, 0.3))
        return
    for x in range(-30, w + 30, 28):
        leaves = p.leaves(rnd) if p.autumn else rnd.choice([LEAF_GREEN, LEAF_DEEP])
        foliage(d, x + rnd.randint(-6, 6), y + rnd.randint(-4, 10), 36, 28, leaves, rnd)


def backdrop(px, w, h, p, cx, cy):
    """林子深處的光：以 (cx, cy) 為中心往外變暗（抖動混色）。"""
    for y in range(h):
        for x in range(w):
            dist = math.hypot((x - cx) / (w * 0.55), (y - cy) / (h * 0.6))
            t = min(1.0, dist) + (gm.BAYER[y % 4][x % 4] - 7.5) / 90.0
            px[x, y] = gm.lerp(p.glow, p.deep, max(0.0, min(1.0, t)))


def light_shafts(px, w, h, p, rnd, n):
    if p.burned:
        return
    for _ in range(n):
        x0 = rnd.randint(w // 5, w * 4 // 5); wid = rnd.randint(10, 22)
        for y in range(0, int(h * 0.7)):
            for k in range(wid):
                x = x0 + k + y // 3
                if 0 <= x < w and (x + y) % 3 != 0:
                    px[x, y] = gm.lerp(px[x, y], p.glow, 0.12)


def forest_floor(px, d, w, h, y0, p, rnd, path=None):
    """林地：草與苔蘚（秋季有落葉、冬季雪、燒過灰燼），可選一條往深處的小徑。"""
    n = gm.Noise(rnd, 24)
    for y in range(y0, h):
        for x in range(w):
            c = p.ground[min(len(p.ground) - 1, int(n.at(x, y) * len(p.ground)))]
            r = rnd.random()
            if r < 0.07:
                c = p.ground_hi
            elif r < 0.12:
                c = gm.mul(c, 0.82)
            if p.autumn and r > 0.95:
                c = rnd.choice([(214, 140, 50), (190, 70, 40), (230, 190, 70)])  # 落葉
            px[x, y] = c
    if path:
        (x0, y0p), (x1, y1p), wid0, wid1 = path
        for y in range(min(y0p, y1p), h):
            t = (y - y0p) / max(1, (y1p - y0p))
            cx = x0 + (x1 - x0) * t + 6 * math.sin(y / 14)
            hw = wid0 + (wid1 - wid0) * t
            for x in range(int(cx - hw), int(cx + hw)):
                if 0 <= x < w and rnd.random() > 0.08:
                    px[x, y] = gm.mul(p.path, 0.92 + 0.12 * rnd.random())


def ferns(d, w, y0, y1, p, rnd, n):
    """蕨類與灌木叢：一叢叢扇形的葉，越近越大。冬季是積雪的矮叢，燒過是焦黑的殘株。"""
    for _ in range(n):
        y = rnd.randint(y0, y1); t = (y - y0) / max(1, y1 - y0)
        x = rnd.randint(-10, w + 10)
        size = int(5 + t * 16)
        if p.burned:
            for k in range(3):
                d.line([x, y, x + rnd.randint(-size // 2, size // 2), y - rnd.randint(2, size // 2)], fill=(34, 30, 28))
            continue
        if p.winter:
            d.ellipse([x - size, y - size // 2, x + size, y + 2], fill=(214, 222, 234))
            d.ellipse([x - size + 2, y - size // 2, x + size // 2, y - 1], fill=p.snow)
            continue
        cols = rnd.choice([LEAF_GREEN, LEAF_DEEP]) if not p.autumn else rnd.choice([LEAF_GREEN, AUTUMN[0], AUTUMN[1]])
        for k in range(7):
            ang = math.pi * (1.1 + k * 0.13)
            ex = x + int(math.cos(ang) * size * 1.2); ey = y + int(math.sin(ang) * size)
            d.line([x, y, (x + ex) // 2, (y + ey) // 2 - 2, ex, ey], fill=cols[0], width=3)
            d.line([x, y - 1, (x + ex) // 2, (y + ey) // 2 - 3, ex, ey - 1], fill=cols[1 + k % 2], width=1)


def tree_wall(d, w, base, p, rnd, haze=0.3):
    """林中空地四周的林牆：針葉與闊葉混合，針葉是深綠的三角、闊葉是不規則的葉團（秋季變色）。底部先墊林下陰影。"""
    shade = fog(CONIFER[0], p.glow, haze) if not p.burned else (52, 46, 42)
    if p.winter:
        shade = gm.lerp(shade, (200, 210, 224), 0.35)
    d.rectangle([0, base - 18, w, base + 4], fill=shade)
    for x in range(-20, w + 20, 14):
        if rnd.random() < 0.55:
            hgt = rnd.randint(46, 74)
            pal = v2.FPal('burned' if p.burned else ('winter' if p.winter else 'normal'))
            pal.tree = [fog(c, p.glow, haze) for c in CONIFER[:3]] if not p.burned else pal.tree
            v2.tree(d, x + rnd.randint(-4, 4), base + rnd.randint(-4, 4), hgt, pal, rnd)
        else:
            broad_tree(d, x + rnd.randint(-4, 4), base + rnd.randint(-2, 4), rnd.randint(40, 62), 4, p, rnd, haze=haze, crown=1.1)


def region(name, mode):
    w, h = 640, 360
    rnd = random.Random(name + 'v3')
    p = P(mode)
    im, px, d = gm.new(w, h)
    if name == 'forest_west':
        # 老林：深處透光、遠樹幹、中景闊葉樹、頂部樹冠、近處粗大老樹與樹根、蕨類、倒木、小徑
        backdrop(px, w, h, p, w // 2, h * 0.45)
        for _ in range(16):
            broad_tree(d, rnd.randint(0, w), rnd.randint(230, 250), rnd.randint(150, 210), rnd.randint(5, 9), p, rnd, haze=0.65)
        for _ in range(8):
            broad_tree(d, rnd.randint(0, w), rnd.randint(250, 268), rnd.randint(190, 250), rnd.randint(10, 16), p, rnd, haze=0.35)
        light_shafts(px, w, h, p, rnd, 3)
        forest_floor(px, d, w, h, 262, p, rnd, path=((330, 262), (300, 360), 8, 46))
        canopy_band(d, w, 10, p, rnd)
        v2_pal = v2.FPal('burned' if p.burned else ('winter' if p.winter else 'normal'))
        for x, y, ln, sl in [(400, 300, 150, 0.08), (40, 318, 160, -0.06)]:
            v2.log(d, x, y, ln, sl, v2_pal, 10 + (y - 262) // 6)
        ferns(d, w, 262, 352, p, rnd, 40)
        for x, wb in [(60, 40), (590, 46)]:
            broad_tree(d, x, 366, 360, wb, p, rnd, crown=0.8)
    elif name == 'forest_north':
        # 深林：冷色的霧、一排排雲杉樹幹、頂部針葉樹冠、苔蘚地面、隱藏的小水塘
        p.glow = {'normal': (156, 190, 176), 'autumn': (180, 190, 160), 'winter': (206, 216, 230), 'burned': (170, 150, 128)}[mode]
        p.deep = {'normal': (24, 48, 44), 'autumn': (40, 54, 44), 'winter': (96, 112, 132), 'burned': (52, 46, 42)}[mode]
        backdrop(px, w, h, p, w * 0.45, h * 0.5)
        for _ in range(40):
            spruce_trunk(d, rnd.randint(0, w), rnd.randint(236, 252), rnd.randint(160, 230), rnd.randint(3, 6), p, rnd, haze=0.7)
        for _ in range(14):
            spruce_trunk(d, rnd.randint(0, w), rnd.randint(252, 268), rnd.randint(220, 280), rnd.randint(8, 13), p, rnd, haze=0.35)
        light_shafts(px, w, h, p, rnd, 2)
        forest_floor(px, d, w, h, 264, p, rnd)
        pool = [(200, 300), (270, 288), (400, 288), (470, 300), (430, 322), (250, 324)]
        d.polygon(pool, fill=p.water)
        d.polygon([(214, 296), (270, 290), (400, 290), (460, 300), (440, 304), (220, 302)], fill=gm.mul(p.water, 0.7))
        for _ in range(40):
            x = rnd.randint(220, 450); y = rnd.randint(300, 320)
            d.line([x, y, x + rnd.randint(2, 6), y], fill=p.water_hi)
        canopy_band(d, w, 6, p, rnd, kind='conifer')
        ferns(d, w, 270, 352, p, rnd, 26)
        for x, wb in [(40, 30), (610, 34)]:
            spruce_trunk(d, x, 366, 380, wb, p, rnd)
    elif name == 'forest_east':
        # 溪谷：兩側是樹，中間的開口看到遠山與天空，溪流從深處流到前景
        gm.sky(px, w, h, h, v2.FPal('burned' if p.burned else ('winter' if p.winter else 'normal')))
        mp = v2.FPal('burned' if p.burned else ('winter' if p.winter else 'normal'))
        gm.peaks(d, rnd, 210, [(320, 120, 130), (420, 90, 110)], mp, snow_frac=0.4)
        tree_wall(d, w, 214, p, rnd, haze=0.45)
        forest_floor(px, d, w, h, 216, p, rnd)
        pts = [(330, 216), (318, 250), (346, 286), (300, 330), (270, 360)]
        for i in range(-10, 11):
            d.line([(x + i * (1 + (y - 216) // 60), y) for x, y in pts], fill=p.water)
        for _ in range(80):
            i = rnd.randint(0, len(pts) - 2); t = rnd.random()
            x = int(pts[i][0] + (pts[i + 1][0] - pts[i][0]) * t) + rnd.randint(-8, 8)
            y = int(pts[i][1] + (pts[i + 1][1] - pts[i][1]) * t)
            d.line([x, y, x + rnd.randint(2, 5), y], fill=p.water_hi)
        for _ in range(14):
            y = rnd.randint(240, 352); s = 2 + (y - 220) // 20
            gm.boulder(px, w, h, rnd.randint(220, 420), y, s + rnd.randint(1, 4), s, rnd.choice(p.rock), rnd,
                       moss=(92, 136, 60) if mode in ('normal', 'autumn') else None, snow=p.snow if p.winter else None)
        # 兩側的林子（近、大）
        for x in [10, 80, 150, 500, 570, 630]:
            broad_tree(d, x + rnd.randint(-10, 10), 300 + rnd.randint(0, 40), rnd.randint(260, 330), rnd.randint(12, 24), p, rnd, haze=0.1)
        for x in [120, 540]:
            spruce_trunk(d, x, 330, 300, 12, p, rnd)
        canopy_band(d, w // 4, 4, p, rnd)
        ferns(d, w, 280, 352, p, rnd, 30)
    elif name == 'forest_south':
        # 林中空地：四周針闊混合的林牆（秋季變色）、開闊草地、有蘆葦的水塘，近處幾棵樹框住畫面
        mp = v2.FPal('burned' if p.burned else ('winter' if p.winter else 'normal'))
        gm.sky(px, w, h, h, mp); gm.clouds(d, w, rnd, 3, (20, 70))
        tree_wall(d, w, 196, p, rnd, haze=0.4)
        tree_wall(d, w, 214, p, rnd, haze=0.15)
        forest_floor(px, d, w, h, 216, p, rnd)
        pond = [(250, 276), (360, 266), (470, 272), (480, 292), (360, 304), (260, 298)]
        d.polygon(pond, fill=p.water)
        for _ in range(50):
            x = rnd.randint(270, 470); y = rnd.randint(272, 300)
            d.line([x, y, x + rnd.randint(2, 6), y], fill=p.water_hi)
        if not p.burned:
            reed = [(110, 140, 64), (136, 160, 76)] if not p.winter else [(170, 156, 120), (150, 138, 108)]
            for _ in range(80):
                x = rnd.randint(240, 490); y = rnd.choice([rnd.randint(268, 278), rnd.randint(296, 306)])
                d.line([x, y, x + rnd.randint(-1, 1), y - rnd.randint(4, 10)], fill=rnd.choice(reed))
        for x, wb, hg in [(30, 26, 330), (610, 30, 340)]:
            broad_tree(d, x, 372, hg, wb, p, rnd, crown=0.9)
        ferns(d, w, 300, 356, p, rnd, 16)
    return im


def terrain(name, mode):
    w, h = 320, 180
    rnd = random.Random('t3' + name)
    p = P(mode)
    im, px, d = gm.new(w, h)
    if name in ('dense_forest', 'fallen_logs'):
        backdrop(px, w, h, p, w // 2, h * 0.45)
        for _ in range(12):
            if name == 'dense_forest':
                spruce_trunk(d, rnd.randint(0, w), rnd.randint(118, 128), rnd.randint(90, 120), rnd.randint(3, 5), p, rnd, haze=0.6)
            else:
                broad_tree(d, rnd.randint(0, w), rnd.randint(118, 128), rnd.randint(80, 110), rnd.randint(3, 6), p, rnd, haze=0.6)
        forest_floor(px, d, w, h, 128, p, rnd)
        canopy_band(d, w, 2, p, rnd, kind='conifer' if name == 'dense_forest' else 'broad')
        if name == 'fallen_logs':
            vp = v2.FPal('burned' if p.burned else ('winter' if p.winter else 'normal'))
            for x, y, ln, sl in [(20, 146, 120, 0.08), (160, 160, 130, -0.06)]:
                v2.log(d, x, y, ln, sl, vp, 8 + (y - 128) // 5)
        ferns(d, w, 132, 176, p, rnd, 14)
        for x in (12, 306):
            (spruce_trunk if name == 'dense_forest' else lambda d_, x_, b_, h_, w_, p_, r_: broad_tree(d_, x_, b_, h_, w_, p_, r_))(
                d, x, 184, 190, 16, p, rnd)
    elif name == 'stream':
        backdrop(px, w, h, p, w // 2, h * 0.45)
        for _ in range(10):
            broad_tree(d, rnd.randint(0, w), rnd.randint(110, 120), rnd.randint(80, 100), 4, p, rnd, haze=0.55)
        forest_floor(px, d, w, h, 118, p, rnd)
        pts = [(160, 118), (150, 140), (174, 160), (140, 180)]
        for i in range(-7, 8):
            d.line([(x + i, y) for x, y in pts], fill=p.water)
        for _ in range(30):
            d.point((rnd.randint(136, 186), rnd.randint(120, 178)), fill=p.water_hi)
        canopy_band(d, w, 0, p, rnd)
        ferns(d, w, 124, 176, p, rnd, 12)
    elif name in ('forest_edge', 'clearing'):
        mp = v2.FPal('burned' if p.burned else ('winter' if p.winter else 'normal'))
        gm.sky(px, w, h, h, mp); gm.clouds(d, w, rnd, 2, (8, 30))
        tree_wall(d, w, 100 if name == 'forest_edge' else 92, p, rnd, haze=0.35)
        if name == 'forest_edge':
            tree_wall(d, w, 112, p, rnd, haze=0.1)
        forest_floor(px, d, w, h, 112 if name == 'forest_edge' else 96, p, rnd)
        ferns(d, w, 130, 176, p, rnd, 6)
    return im


def save(im, path, arch):
    im.save(path)
    im.save(ARCH + arch + '_1x.png')
    im.resize((im.width * 4, im.height * 4), Image.NEAREST).save(ARCH + arch + '_4x.png')


if __name__ == '__main__':
    only = sys.argv[1:] or None
    for r in ['forest_west', 'forest_north', 'forest_east', 'forest_south']:
        if only and r not in only and 'all' not in only:
            continue
        for mode in ('normal', 'autumn', 'winter', 'burned'):
            im = region(r, mode)
            save(im, gm.OUT_REG + r + SUF[mode] + '.png', r + SUF[mode])
            if mode == 'normal':
                save(im.resize((18, 18), Image.BOX), gm.OUT_ICON + 'region_tile_' + r + '.png', 'region_tile_' + r)
    if not only or 'all' in only or 'terrain' in only:
        for t in ['stream', 'dense_forest', 'forest_edge', 'clearing', 'fallen_logs']:
            for mode in ('normal', 'autumn', 'winter', 'burned'):
                save(terrain(t, mode), gm.OUT_TER + t + SUF[mode] + '.png', t + SUF[mode])
    print('done')
