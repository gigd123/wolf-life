#!/usr/bin/env python3
# 山地美術第 2 版（2026-10-13，依使用者提供的概念圖改畫）：層狀的灰藍岩壁（岩層縫、垂直裂縫、亮暗面、頂上的草、底下的崩落碎石）、
# 長苔蘚的岩堆、瀑布與溪流、高大的針葉樹與野花，畫風對齊森林的正式素材（抖動漸層的天空、分層打光的樹、有亮點的草地）。
# 產生：區域背景 640×360（含冬季版）4 張、地形背景 320×180（岩壁、碎石坡、高山草甸，含冬季版）、區域小圖 18×18。
# 第 1 版（gen_mountain.py）留著：草原的產生器借用它的工具函式。
# 用法：在專案根目錄 python3 arts/art_mountain_2026-10-13/gen_mountain_v2.py
import math, random
from PIL import Image, ImageDraw

ARCH = 'arts/art_mountain_2026-10-13/'
OUT_REG = 'assets/art/backgrounds/regions/'
OUT_TER = 'assets/art/backgrounds/terrain/'
OUT_ICON = 'assets/art/icons/'

BAYER = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]


def lerp(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def mul(c, k):
    return tuple(max(0, min(255, int(round(v * k)))) for v in c)


class Pal:
    def __init__(self, winter):
        self.winter = winter
        self.sky_top = (98, 136, 186) if not winter else (124, 146, 176)
        self.sky_bot = (178, 202, 220) if not winter else (214, 222, 230)
        self.far = (128, 140, 170) if not winter else (150, 162, 186)
        self.far_shade = (104, 114, 148) if not winter else (124, 136, 166)
        self.snow = (238, 242, 248)
        self.snow_shade = (196, 208, 226)
        # 岩壁：灰藍、米灰、深灰
        self.rock = [(150, 164, 176), (172, 176, 172), (132, 146, 160), (186, 186, 176)]
        self.rock_dark = (70, 80, 96)
        self.seam = (40, 46, 58)
        self.grass = [(92, 130, 62), (106, 144, 70), (80, 116, 56)] if not winter else [(230, 234, 242), (216, 224, 236), (240, 242, 246)]
        self.grass_hi = (150, 184, 92) if not winter else (250, 252, 255)
        self.grass_lo = (64, 96, 48) if not winter else (192, 204, 222)
        self.dry = (176, 160, 104) if not winter else (226, 230, 238)  # 岩頂的乾草
        self.tree = [(34, 66, 52), (48, 88, 64), (72, 116, 80)]
        self.tree_far = (70, 102, 100) if not winter else (120, 140, 150)
        self.moss = (96, 136, 64) if not winter else (226, 232, 240)
        self.water = (70, 124, 168) if not winter else (184, 208, 226)
        self.water_hi = (170, 206, 230) if not winter else (236, 244, 250)
        self.floor = [(170, 156, 128), (156, 144, 120), (184, 170, 140)] if not winter else [(228, 232, 240), (214, 222, 234), (238, 240, 246)]


def new(w, h):
    im = Image.new('RGB', (w, h))
    return im, im.load(), ImageDraw.Draw(im)


def sky(px, w, h, y1, pal):
    """抖動漸層的天空（4×4 Bayer，8 段）。"""
    steps = 8
    for y in range(y1):
        t = y / max(1, y1 - 1) * steps
        lo = int(t)
        frac = t - lo
        c0 = lerp(pal.sky_top, pal.sky_bot, min(steps, lo) / steps)
        c1 = lerp(pal.sky_top, pal.sky_bot, min(steps, lo + 1) / steps)
        for x in range(w):
            px[x, y] = c1 if frac * 16 > BAYER[y % 4][x % 4] else c0


def clouds(d, w, rnd, n, y_range):
    for _ in range(n):
        x = rnd.randint(0, w); y = rnd.randint(*y_range); cw = rnd.randint(24, 60)
        d.rectangle([x, y, x + cw, y + 3], fill=(240, 238, 228))
        d.rectangle([x + cw // 4, y - 3, x + cw * 3 // 4, y], fill=(240, 238, 228))


def peaks(d, rnd, base, specs, pal, snow_frac=0.35, col=None, shade=None):
    """遠山：每座山左邊亮、右邊暗，山頂積雪。specs = [(中心 x, 高, 半寬)]。"""
    col = col or pal.far; shade = shade or pal.far_shade
    for cx, hgt, hw in specs:
        apex = (cx, base - hgt)
        left = [(cx - hw, base)]
        right = [(cx + hw, base)]
        # 鋸齒的山稜
        lpts, rpts = [], []
        for i in range(1, 8):
            t = i / 8
            lpts.append((int(cx - hw + hw * t + rnd.randint(-3, 3)), int(base - hgt * t + rnd.randint(-4, 4))))
            rpts.append((int(cx + hw - hw * t + rnd.randint(-3, 3)), int(base - hgt * t + rnd.randint(-4, 4))))
        outline = left + lpts + [apex] + list(reversed(rpts)) + right
        d.polygon(outline, fill=shade)
        # 亮面：山頂往下的一條斜脊
        mid = [(cx + rnd.randint(-6, 6) + int(hw * 0.15 * i / 6), base - hgt + int(hgt * i / 6)) for i in range(7)]
        d.polygon(left + lpts + [apex] + mid[1:] + [(mid[-1][0], base)], fill=col)
        # 積雪
        sy = base - hgt + int(hgt * snow_frac)
        snow_l = [p for p in lpts if p[1] <= sy]
        snow_r = [p for p in rpts if p[1] <= sy]
        if snow_l and snow_r:
            zig = []
            x0, x1 = snow_l[0][0], snow_r[0][0]
            for i in range(9):
                x = x0 + (x1 - x0) * i // 8
                zig.append((x, sy + (6 if i % 2 else -2) + rnd.randint(-2, 2)))
            d.polygon([snow_l[0]] + snow_l[1:] + [apex] + list(reversed(snow_r)) + list(reversed(zig)), fill=pal.snow_shade)
            lit = [snow_l[0]] + snow_l[1:] + [apex] + [m for m in mid if m[1] <= sy + 4]
            d.polygon(lit + [zig[min(4, len(zig) - 1)]], fill=pal.snow)


def conifer(d, x, base, hgt, pal, rnd, far=False, snow=False):
    """針葉樹：分層的三角形，左邊亮、右邊暗，像森林素材。"""
    if far:
        tiers = max(3, hgt // 6)
        for i in range(tiers):
            ty = base - hgt + i * hgt // tiers
            hw = 2 + i * hgt // (tiers * 3)
            d.polygon([(x, ty - 2), (x - hw, ty + hgt // tiers + 1), (x + hw, ty + hgt // tiers + 1)], fill=pal.tree_far)
        return
    dark, mid, light = pal.tree
    d.rectangle([x - 1, base - hgt // 8, x + 1, base], fill=(70, 52, 40))
    tiers = max(4, hgt // 7)
    for i in range(tiers):
        ty = base - hgt + i * (hgt - hgt // 8) // tiers
        th = (hgt - hgt // 8) // tiers + 3
        hw = 2 + (i + 1) * hgt // (tiers * 3)
        d.polygon([(x, ty), (x - hw, ty + th), (x + hw, ty + th)], fill=dark)
        d.polygon([(x, ty), (x - hw, ty + th), (x, ty + th)], fill=mid)
        for _ in range(max(1, hw // 3)):
            lx = x - rnd.randint(1, max(1, hw - 1)); ly = ty + th - rnd.randint(1, 2)
            d.point((lx, ly), fill=light)
        if snow:
            d.line([(x - hw + 1, ty + th - 1), (x - 1, ty + 2)], fill=pal.snow)
            d.line([(x - hw + 2, ty + th - 1), (x + hw - 2, ty + th - 1)], fill=pal.snow_shade)


def boulder(px, w, h, cx, cy, rx, ry, base, rnd, moss=None, snow=None):
    """圓滾的石頭：依法線打光（左上亮），邊緣深色，頂上可以有苔蘚或積雪。"""
    jit = [rnd.uniform(0.82, 1.08) for _ in range(12)]
    hi, lo, edge = mul(base, 1.18), mul(base, 0.72), mul(base, 0.45)
    for y in range(cy - ry - 1, cy + ry + 2):
        for x in range(cx - rx - 1, cx + rx + 2):
            if not (0 <= x < w and 0 <= y < h):
                continue
            dx, dy = (x - cx) / max(1, rx), (y - cy) / max(1, ry)
            ang = math.atan2(dy, dx)
            r = jit[int((ang + math.pi) / (2 * math.pi) * 12) % 12]
            dist = math.hypot(dx, dy)
            if dist > r or (dy > 0.75 and dist > 0.7):  # 底部平一點，坐在地上
                continue
            if dist > r - 0.18:
                c = edge
            else:
                light = -dx * 0.6 - dy * 0.8
                c = hi if light > 0.35 else (base if light > -0.25 else lo)
                if (x * 7 + y * 13) % 23 == 0:
                    c = lo
            if dy < -0.45 and dist < r - 0.1:
                if snow:
                    c = snow
                elif moss and (x + y) % 3 != 0:
                    c = moss
            px[x, y] = c


def talus(px, w, h, x0, x1, y_top, y_bot, pal, rnd, n):
    """岩壁底下崩落的碎石堆：上面小、下面大。"""
    for _ in range(n):
        y = rnd.randint(y_top, y_bot)
        t = (y - y_top) / max(1, y_bot - y_top)
        x = rnd.randint(x0, x1)
        r = int(2 + t * rnd.randint(3, 8))
        boulder(px, w, h, x, y, r + rnd.randint(0, 3), r, rnd.choice(pal.rock), rnd,
                snow=pal.snow if pal.winter and rnd.random() < 0.6 else None)


def profile(x0, x1, base, spires, rnd, rough=3):
    """岩峰的輪廓：幾座尖峰疊起來，加上隨機的階梯。spires = [(中心 x, 高, 坡度)]。回傳 top_fn。"""
    tops = {}
    walk = 0
    for x in range(x0, x1):
        if x % 3 == 0:
            walk = max(-rough, min(rough, walk + rnd.randint(-1, 1)))
        hgt = max([hh - abs(x - cx) * sl for cx, hh, sl in spires] + [0])
        tops[x] = int(base - hgt + walk + ((x // 5) % 2 if hgt > 4 else 0))
    return lambda x: tops.get(x, base)


def _hash(x, y):
    return ((x * 73856093) ^ (y * 19349663)) & 0xffff


class Noise:
    """低頻的數值雜訊（雙線性內插），讓岩壁顏色緩慢變化，不要一塊一塊跳。"""
    def __init__(self, rnd, cell=28):
        self.cell = cell
        self.g = {}
        self.rnd = rnd

    def _v(self, i, j):
        if (i, j) not in self.g:
            self.g[(i, j)] = self.rnd.random()
        return self.g[(i, j)]

    def at(self, x, y):
        c = self.cell
        i, j = x // c, y // c
        fx, fy = (x % c) / c, (y % c) / c
        fx, fy = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy)
        a = self._v(i, j) + (self._v(i + 1, j) - self._v(i, j)) * fx
        b = self._v(i, j + 1) + (self._v(i + 1, j + 1) - self._v(i, j + 1)) * fx
        return a + (b - a) * fy


def cliff_mass(px, w, h, x0, x1, top_fn, bottom, pal, rnd, shade_side='right', far=False, open_sides=('left', 'right'), ridge=None):
    """層狀岩壁（照概念圖）：一層層 18～40 像素的岩層，每層的左右邊緣參差（懸出、內縮）；
    層內用歪斜的裂縫切成大片岩面，岩面從亮的一側過渡到暗的一側；岩層縫下方有懸垂的陰影；
    整面岩壁有一側偏暗；顏色在灰藍與米灰之間緩慢變化，加上細微雜點與坑洞。頂上有乾草或積雪。"""
    tmin = min(top_fn(x) for x in range(x0, x1))
    layers = []  # (起始 y, 左緣內縮, 右緣內縮, 主要岩層縫)
    y = tmin + rnd.randint(6, 14)
    jag = 4 if far else 16
    while y < bottom:
        layers.append((y, rnd.randint(0, jag) if 'left' in open_sides else 0,
                       rnd.randint(0, jag) if 'right' in open_sides else 0, rnd.random() < 0.35,
                       rnd.uniform(-0.05, 0.05), rnd.uniform(0, 6.28)))
        y += rnd.randint(18, 40) if not far else rnd.randint(10, 20)
    noise = Noise(rnd, 22 if far else 34)
    # 每一層的裂縫：歪斜的折線，x 隨 y 漂移
    fract = []
    for i in range(len(layers) + 1):
        xs, x = [], x0 + rnd.randint(6, 30)
        while x < x1:
            # (x, 斜率, 從這層頂端往下延伸的比例：有些裂縫不貫穿整層)
            xs.append((x, rnd.uniform(-0.35, 0.35), rnd.choice([1.0, 1.0, 0.6, 0.4])))
            x += rnd.randint(22, 56) if not far else rnd.randint(14, 30)
        fract.append(xs)
    tone = {}
    span = max(1, x1 - x0)
    cool, warm = (146, 162, 178), (184, 182, 168)
    for x in range(max(0, x0), min(w, x1)):
        top = top_fn(x)
        side_t = (x - x0) / span if shade_side == 'right' else (x1 - x) / span
        side_k = 1.0 - 0.38 * max(0.0, side_t - 0.5) / 0.5
        if far:
            side_k *= 0.84
        # 岩層縫帶一點傾斜與起伏
        lys = [ly + int(sl * (x - x0) + 2.0 * math.sin(x / 23.0 + ph)) for ly, _, _, _, sl, ph in layers]
        # 岩峰：山脊右邊（暗面）整體變暗
        ridge_k = 1.0
        for y in range(max(0, top), min(bottom, h)):
            li = 0
            for j, ly in enumerate(lys):
                if y >= ly:
                    li = j + 1
            ly0 = lys[li - 1] if li > 0 else top
            ly1 = lys[li] if li < len(lys) else bottom
            ridge_k = 0.74 if ridge is not None and x > ridge(y) else 1.0
            lin, rin = (layers[li - 1][1], layers[li - 1][2]) if li > 0 else (0, 0)
            major = layers[li - 1][3] if li > 0 else False
            if x < x0 + lin or x >= x1 - rin:
                continue  # 這一層內縮，露出後面的東西
            # 岩層縫與下方懸垂的陰影
            dy = y - ly0
            if li > 0 and dy <= (1 if major else 0):
                if major:
                    px[x, y] = mul(pal.seam, side_k + 0.1)
                else:
                    px[x, y] = mul(lerp(cool, warm, noise.at(x, y)), 0.62 * side_k)
                continue
            # 這個像素屬於哪一片岩面
            xs = fract[li]
            fi = 0
            depth = y - ly0
            hl = max(1, ly1 - ly0)
            for k, (fx, sl, reach) in enumerate(xs):
                if x >= fx + int(depth * sl) and depth <= hl * reach:
                    fi = k + 1
            act = [(fx, sl) for fx, sl, reach in xs if depth <= hl * reach]
            lefts = [fx + int(depth * sl) for fx, sl in act if fx + int(depth * sl) <= x]
            rights = [fx + int(depth * sl) for fx, sl in act if fx + int(depth * sl) > x]
            lx = max(lefts) if lefts else x0 + lin
            rx = min(rights) if rights else x1 - rin
            key = (li, fi)
            if key not in tone:
                tone[key] = rnd.uniform(0.95, 1.05)
            kk = tone[key]
            c = lerp(cool, warm, noise.at(x, y))
            # 岩面的光：左亮右暗的漸層
            u = (x - lx) / max(1, rx - lx)
            k = kk * (1.12 - 0.34 * u ** 1.4)
            if x - lx < 1:
                k *= 1.12
            if rx - x <= 0:
                k *= 0.62  # 裂縫：淡的陰影線
            if li > 0 and dy <= (5 if major else 2):
                k *= (0.55 if major else 0.8) + 0.08 * dy  # 懸垂的陰影
            elif ly1 - y <= 2:
                k *= 1.08  # 下一層縫上方的亮邊
            hv = _hash(x, y)
            if hv % 41 == 0:
                k *= 0.7  # 坑洞
            k *= 0.96 + (hv % 9) * 0.01
            px[x, y] = mul(c, k * side_k * ridge_k)
        # 頂上：乾草或積雪
        cap = pal.snow if pal.winter else pal.dry
        for k2 in range(rnd.randint(2, 3)):
            if 0 <= top + k2 < h:
                px[x, top + k2] = cap if k2 < 2 else mul(cap, 0.85)
        if not pal.winter and rnd.random() < 0.3 and top - 1 >= 0:
            px[x, top - 1] = pal.grass[1]


def ground(px, w, h, y0, pal, rnd, flowers=0.0, palette=None):
    """草地：深淺交錯的橫帶，加上亮點、暗點、草叢與野花（冬季是雪地）。"""
    palette = palette or pal.grass
    band = {}
    for y in range(y0, h):
        bi = (y - y0) // (3 + (y - y0) // 20)
        if bi not in band:
            band[bi] = rnd.choice(palette)
        for x in range(w):
            c = band[bi]
            r = rnd.random()
            if r < 0.06:
                c = pal.grass_hi
            elif r < 0.11:
                c = pal.grass_lo
            px[x, y] = c
    # 草叢
    for _ in range(int(w * (h - y0) / 90)):
        x = rnd.randint(0, w - 1); y = rnd.randint(y0 + 2, h - 1)
        for k in range(rnd.randint(1, 3)):
            if 0 <= y - k < h:
                px[x, y - k] = pal.grass_hi if k == 0 else pal.grass_lo
    if flowers > 0 and not pal.winter:
        for _ in range(int(w * (h - y0) * flowers / 100)):
            x = rnd.randint(0, w - 1); y = rnd.randint(y0 + 4, h - 1)
            px[x, y] = rnd.choice([(232, 202, 64), (232, 202, 64), (240, 240, 230), (170, 130, 200)])


def floor(px, w, h, y0, pal, rnd):
    """峽谷的谷底：碎石與沙土。"""
    for y in range(y0, h):
        for x in range(w):
            c = rnd.choice(pal.floor)
            if rnd.random() < 0.05:
                c = mul(c, 0.75)
            px[x, y] = c


def water_path(d, pts, width, pal, rnd):
    for i in range(width):
        d.line([(x, y + i - width // 2) for x, y in pts], fill=pal.water)
    for _ in range(len(pts) * 3):
        i = rnd.randint(0, len(pts) - 2)
        (xa, ya), (xb, yb) = pts[i], pts[i + 1]
        t = rnd.random()
        x = int(xa + (xb - xa) * t); y = int(ya + (yb - ya) * t) + rnd.randint(-width // 2, width // 2)
        d.line([x, y, x + rnd.randint(2, 6), y], fill=pal.water_hi)


def waterfall(px, w, h, x, y0, y1, width, pal, rnd):
    for y in range(y0, y1):
        for dx in range(-width // 2, width // 2 + 1):
            xx = x + dx + int(math.sin(y * 0.2) * 1)
            if 0 <= xx < w and 0 <= y < h:
                px[xx, y] = pal.water_hi if (dx + y // 2) % 3 else pal.water
    # 水花
    for _ in range(40):
        xx = x + rnd.randint(-width - 4, width + 4); yy = y1 + rnd.randint(-3, 4)
        if 0 <= xx < w and 0 <= yy < h:
            px[xx, yy] = (245, 248, 252)


def bush(d, x, y, r, pal, rnd):
    col = (66, 108, 58) if not pal.winter else (208, 216, 228)
    hi = (104, 150, 76) if not pal.winter else (244, 246, 250)
    d.ellipse([x - r, y - r, x + r, y + r // 2], fill=col)
    d.ellipse([x - r + 1, y - r, x, y - r // 3], fill=hi)


# ---------- 區域 ----------

def region(name, winter):
    w, h = 640, 360
    rnd = random.Random(name)
    pal = Pal(winter)
    im, px, d = new(w, h)
    if name == 'mountain_foothills':
        sky(px, w, h, 220, pal); clouds(d, w, rnd, 3, (20, 70))
        peaks(d, rnd, 205, [(150, 120, 140), (360, 150, 160), (560, 110, 130)], pal)
        for x in range(0, w, 7):  # 中景的山坡森林
            conifer(d, x + rnd.randint(-3, 3), 214 + rnd.randint(-4, 4), rnd.randint(16, 26), pal, rnd, far=True)
        ground(px, w, h, 212, pal, rnd, flowers=0.3)
        # 右側長苔蘚的岩堆（概念圖 2）
        cliff_mass(px, w, h, 440, 590, profile(440, 590, 300, [(490, 62, 0.9), (540, 50, 0.7)], rnd), 300, pal, rnd)
        talus(px, w, h, 420, 620, 286, 312, pal, rnd, 28)
        for _ in range(10):
            boulder(px, w, h, rnd.randint(440, 600), rnd.randint(292, 306), rnd.randint(6, 12), rnd.randint(5, 8),
                    rnd.choice(pal.rock), rnd, moss=pal.moss, snow=pal.snow if winter else None)
        for x in (470, 560):
            bush(d, x, 236, 6, pal, rnd)
        # 溪流與石頭
        pts = [(260, 214), (230, 240), (250, 270), (200, 310), (150, 360)]
        water_path(d, pts, 10, pal, rnd)
        for _ in range(14):
            boulder(px, w, h, rnd.randint(140, 270), rnd.randint(240, 350), rnd.randint(3, 6), rnd.randint(2, 4),
                    rnd.choice(pal.rock), rnd, moss=pal.moss, snow=pal.snow if winter else None)
        for x, b, ht in [(18, 360, 150), (64, 330, 110), (330, 250, 44), (372, 254, 52), (625, 360, 140), (410, 248, 36)]:
            conifer(d, x, b, ht, pal, rnd, snow=winter)
    elif name == 'mountain_meadow':
        sky(px, w, h, 220, pal); clouds(d, w, rnd, 4, (16, 60))
        peaks(d, rnd, 215, [(110, 160, 150), (330, 190, 190), (540, 150, 150)], pal, snow_frac=0.5)
        # 中景的岩峰（概念圖 4）
        cliff_mass(px, w, h, 20, 170, profile(20, 170, 215, [(70, 52, 1.1), (110, 38, 1.0), (140, 26, 1.2)], rnd), 215, pal, rnd, far=True)
        cliff_mass(px, w, h, 460, 620, profile(460, 620, 215, [(520, 62, 1.0), (570, 44, 1.2)], rnd), 215, pal, rnd, far=True, shade_side='left')
        ground(px, w, h, 212, pal, rnd, flowers=1.6, palette=[(110, 148, 72), (124, 160, 80), (98, 136, 66)] if not winter else None)
        for _ in range(18):
            y = rnd.randint(225, 350); s = 2 + (y - 220) // 22
            boulder(px, w, h, rnd.randint(0, w), y, s + rnd.randint(1, 4), s, rnd.choice(pal.rock), rnd,
                    moss=pal.moss, snow=pal.snow if winter else None)
        for x, b, ht in [(180, 226, 26), (196, 228, 30), (430, 224, 24), (600, 300, 70)]:
            conifer(d, x, b, ht, pal, rnd, snow=winter)
    elif name == 'mountain_canyon':
        sky(px, w, h, 200, pal); clouds(d, w, rnd, 2, (14, 40))
        peaks(d, rnd, 160, [(320, 80, 120)], pal, snow_frac=0.45)
        # 後面的岩壁（遠、暗）
        cliff_mass(px, w, h, 190, 470, profile(190, 470, 280, [(260, 150, 0.4), (400, 140, 0.4)], rnd, 4), 280, pal, rnd, far=True)
        floor(px, w, h, 270, pal, rnd)
        # 左右兩面大岩壁（概念圖 1）
        cliff_mass(px, w, h, 0, 230, profile(0, 230, 330, [(40, 290, 0.25), (150, 270, 0.35)], rnd, 4), 330, pal, rnd, shade_side='right', open_sides=('right',))
        cliff_mass(px, w, h, 430, 640, profile(430, 640, 330, [(600, 262, 0.25), (500, 250, 0.4)], rnd, 4), 330, pal, rnd, shade_side='left', open_sides=('left',))
        talus(px, w, h, 150, 300, 270, 350, pal, rnd, 50)
        talus(px, w, h, 360, 500, 275, 350, pal, rnd, 50)
        for x, b, ht in [(40, 60, 34), (70, 62, 26), (590, 82, 30), (300, 282, 30), (330, 286, 24)]:
            conifer(d, x, b, ht, pal, rnd, snow=winter)
    elif name == 'mountain_headwaters':
        sky(px, w, h, 220, pal); clouds(d, w, rnd, 3, (16, 60))
        peaks(d, rnd, 200, [(110, 110, 130), (540, 120, 140)], pal)
        ground(px, w, h, 205, pal, rnd, flowers=0.4)
        # 中間的岩峰（概念圖 3）：瀑布從岩縫流下
        cliff_mass(px, w, h, 150, 510, profile(150, 510, 262, [(330, 200, 1.35), (270, 120, 1.0), (400, 130, 1.1), (300, 150, 1.2)], rnd, 4), 262, pal, rnd,
                   shade_side='left', ridge=lambda y: 330 + int((y - 62) * 0.3))
        for x, b, ht in [(236, 236, 26), (252, 226, 22), (420, 230, 24), (404, 222, 20)]:
            conifer(d, x, b, ht, pal, rnd, snow=winter)
        waterfall(px, w, h, 332, 120, 262, 7, pal, rnd)
        # 瀑布下的水潭，兩條溪流往左右流出（往森林與草原）
        d.ellipse([280, 254, 390, 290], fill=pal.water)
        d.ellipse([292, 260, 350, 272], fill=pal.water_hi)
        water_path(d, [(290, 278), (220, 300), (160, 320), (60, 360)], 9, pal, rnd)
        water_path(d, [(380, 278), (450, 305), (520, 330), (600, 360)], 9, pal, rnd)
        talus(px, w, h, 150, 510, 254, 272, pal, rnd, 70)
        talus(px, w, h, 220, 440, 250, 290, pal, rnd, 40)
        for x in range(160, 500, 26):
            if not 280 < x < 380:
                bush(d, x + rnd.randint(-6, 6), 262 + rnd.randint(0, 6), rnd.randint(4, 7), pal, rnd)
        for _ in range(12):
            boulder(px, w, h, rnd.randint(200, 460), rnd.randint(280, 330), rnd.randint(5, 10), rnd.randint(4, 7),
                    rnd.choice(pal.rock), rnd, moss=pal.moss, snow=pal.snow if winter else None)
        for x, y, r in [(250, 262, 7), (410, 262, 8), (200, 280, 6), (470, 284, 7)]:
            bush(d, x, y, r, pal, rnd)
        for x, b, ht in [(30, 330, 120), (90, 300, 80), (215, 252, 40), (452, 254, 46), (560, 300, 84), (615, 340, 120)]:
            conifer(d, x, b, ht, pal, rnd, snow=winter)
    return im


def terrain(name, winter):
    w, h = 320, 180
    rnd = random.Random('t2' + name)
    pal = Pal(winter)
    im, px, d = new(w, h)
    sky(px, w, h, 110, pal)
    if name == 'cliff':
        clouds(d, w, rnd, 1, (10, 24))
        peaks(d, rnd, 100, [(70, 60, 70)], pal)
        floor(px, w, h, 100, pal, rnd)
        cliff_mass(px, w, h, 110, 320, profile(110, 320, 160, [(250, 150, 0.35), (170, 128, 0.5)], rnd, 3), 160, pal, rnd, shade_side='left', open_sides=('left',))
        talus(px, w, h, 80, 220, 140, 176, pal, rnd, 40)
    elif name == 'scree':
        peaks(d, rnd, 96, [(80, 50, 70), (240, 60, 90)], pal)
        ground(px, w, h, 92, pal, rnd)
        # 從右上往左下的碎石坡
        d.polygon([(0, 180), (0, 150), (320, 70), (320, 180)], fill=pal.floor[1])
        for _ in range(900):
            x = rnd.randint(0, w - 1); top = int(150 - x * 0.25)
            y = rnd.randint(max(top, 0), h - 1)
            t = (y - top) / max(1, h - top)
            s = 1 + int(t * 3)
            boulder(px, w, h, x, y, s + rnd.randint(0, 1), max(1, s - 1), rnd.choice(pal.rock), rnd,
                    snow=pal.snow if winter and rnd.random() < 0.5 else None)
        for _ in range(5):
            boulder(px, w, h, rnd.randint(30, 300), rnd.randint(130, 170), rnd.randint(8, 13), rnd.randint(6, 9),
                    rnd.choice(pal.rock), rnd, moss=pal.moss, snow=pal.snow if winter else None)
    elif name == 'alpine_meadow':
        clouds(d, w, rnd, 2, (8, 30))
        peaks(d, rnd, 108, [(90, 80, 90), (240, 95, 100)], pal, snow_frac=0.5)
        ground(px, w, h, 104, pal, rnd, flowers=2.0, palette=[(110, 148, 72), (124, 160, 80), (98, 136, 66)] if not winter else None)
        for _ in range(7):
            y = rnd.randint(114, 170); s = 2 + (y - 110) // 16
            boulder(px, w, h, rnd.randint(0, w), y, s + rnd.randint(1, 3), s, rnd.choice(pal.rock), rnd,
                    moss=pal.moss, snow=pal.snow if winter else None)
        conifer(d, 290, 150, 60, pal, rnd, snow=winter)
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
                save(im.resize((18, 18), Image.BOX), OUT_ICON + 'region_tile_' + r + '.png', 'region_tile_' + r)
    for t in ['cliff', 'scree', 'alpine_meadow']:
        for winter in (False, True):
            suffix = '_winter' if winter else ''
            save(terrain(t, winter), OUT_TER + t + suffix + '.png', t + suffix)
    print('done')
