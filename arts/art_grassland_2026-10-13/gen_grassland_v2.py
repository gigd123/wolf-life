#!/usr/bin/env python3
# 草原美術第 2 版（2026-10-13，依使用者提供的參考圖改畫，照山地第 2 版的做法）：
# 金黃帶綠的長草（一根根草葉，近處高、遠處細，帶暖色亮點）、高而開闊的天空與蓬鬆的積雲、
# 遠方低緩起伏的丘陵、地平線上的孤樹、淡淡的遠山。時段的暖光由遊戲用程式調色，這裡畫白天的基本色。
# 沿用 gen_mountain_v2.py 的天空、石頭、水的工具函式。
# 產生：區域背景 640×360（含冬季版）4 張、地形背景 320×180（草原、草丘、大河，含冬季版）、區域小圖 18×18。
# 用法：在專案根目錄 python3 arts/art_grassland_2026-10-13/gen_grassland_v2.py
import math, random, sys
from PIL import Image, ImageDraw
sys.path.insert(0, 'arts/art_mountain_2026-10-13')
import gen_mountain_v2 as gm

ARCH = 'arts/art_grassland_2026-10-13/'


class GPal(gm.Pal):
    def __init__(self, winter):
        super().__init__(winter)
        self.sky_top = (92, 136, 196) if not winter else (128, 148, 176)
        self.sky_bot = (196, 214, 226) if not winter else (218, 224, 232)
        self.far = (146, 156, 168) if not winter else (170, 178, 194)
        self.far_shade = (126, 136, 152) if not winter else (150, 160, 180)
        # 草：金黃帶綠（遠的偏綠灰、近的偏金）
        self.grass_far = [(150, 158, 104), (160, 162, 108), (142, 150, 100)] if not winter else [(224, 228, 236), (214, 220, 230)]
        self.grass_mid = [(176, 166, 96), (164, 160, 92), (188, 172, 100)] if not winter else [(232, 234, 240), (220, 226, 234)]
        self.blade = [(196, 176, 98), (214, 190, 108), (170, 156, 86), (150, 150, 84), (226, 204, 124)] if not winter else \
            [(150, 138, 108), (170, 156, 120), (128, 118, 96)]
        self.blade_hi = (240, 220, 150) if not winter else (250, 252, 255)
        self.blade_lo = (118, 112, 66) if not winter else (196, 206, 222)
        self.hill = [(150, 158, 104), (166, 164, 104), (136, 146, 96)] if not winter else [(220, 226, 236), (206, 214, 228), (232, 234, 240)]
        self.tree = [(54, 80, 52), (72, 104, 62), (98, 130, 74)] if not winter else [(92, 84, 78), (110, 100, 92), (130, 120, 110)]
        self.water = (78, 124, 168) if not winter else (188, 210, 228)
        self.water_hi = (168, 204, 228) if not winter else (238, 244, 250)
        self.sand = (206, 190, 150) if not winter else (226, 230, 238)


def cumulus(d, rnd, x, y, w, pal):
    """蓬鬆的積雲：幾個圓疊在一起，底部平、上面亮、下面帶灰。"""
    top = (246, 246, 240); shade = (214, 222, 230) if not pal.winter else (206, 212, 222)
    n = max(3, w // 14)
    for i in range(n):
        cx = x + i * w // n + rnd.randint(-3, 3)
        r = rnd.randint(w // 7, w // 4)
        d.ellipse([cx - r, y - r, cx + r, y + r // 2], fill=shade)
    for i in range(n):
        cx = x + i * w // n + rnd.randint(-2, 2)
        r = rnd.randint(w // 9, w // 5)
        d.ellipse([cx - r, y - r - 3, cx + r, y + r // 3 - 3], fill=top)
    d.rectangle([x - 4, y, x + w + 4, y + 3], fill=shade)


def far_hills(d, w, base, rnd, cols, amp=12, step=60):
    """遠方低緩起伏的丘陵：用平滑的正弦疊出來，一層比一層近、顏色一層比一層暖。"""
    for k, col in enumerate(cols):
        ph = rnd.uniform(0, 6.28); ph2 = rnd.uniform(0, 6.28)
        y0 = base + k * 6
        pts = [(0, 400)]
        for x in range(0, w + 4, 4):
            y = y0 - amp * (0.6 * math.sin(x / step + ph) + 0.4 * math.sin(x / (step * 0.45) + ph2))
            pts.append((x, int(y)))
        pts.append((w, 400))
        d.polygon(pts, fill=col)


def lone_tree(d, x, y, r, pal, rnd):
    """孤立的闊葉樹：短樹幹、圓樹冠，左上亮。冬季只剩枝幹。"""
    trunk = (74, 58, 44)
    d.line([x, y, x, y - r], fill=trunk, width=max(1, r // 4))
    if pal.winter:
        for i in range(5):
            d.line([x, y - r + 1, x + (i - 2) * r // 2, y - r - r // 2 - rnd.randint(0, r // 2)], fill=trunk)
        return
    dark, mid, light = pal.tree
    d.ellipse([x - r, y - r * 2, x + r, y - r // 2], fill=dark)
    d.ellipse([x - r + 1, y - r * 2, x + r // 3, y - r], fill=mid)
    d.ellipse([x - r // 2, y - r * 2 + 1, x, y - r - r // 3], fill=light)


def grass_field(px, w, h, y0, pal, rnd, density=1.0, top_fn=None, horizon=None, crest=False):
    """草原：每一欄從 top_fn(x)（沒給就是 y0）往下鋪草。底色依距離漸層（遠處綠灰、近處金黃，抖動混色，沒有切線），
    再畫一根根草葉：越近（越往下）草越高、越粗、越亮。horizon 是算遠近用的地平線。"""
    top_fn = top_fn or (lambda x: y0)
    hz = horizon if horizon is not None else y0
    far, near = pal.grass_far, pal.grass_mid
    for x in range(w):
        top = max(0, top_fn(x))
        for y in range(top, h):
            t = min(1.0, max(0.0, (y - hz) / max(1, h - hz)))
            cols = near if (t * 16) > gm.BAYER[y % 4][x % 4] + 2 else far
            px[x, y] = cols[(x // 3 + y // 2 + rnd.randint(0, 1)) % len(cols)]
    if crest:
        # 草丘的稜線：稜線上兩列受光變亮，稜線後方（較遠那層）幾列變暗，前後層次才分得開
        for x in range(w):
            top = top_fn(x)
            for k in range(1, 5):
                if 0 <= top - k < h:
                    px[x, top - k] = gm.mul(px[x, top - k], 0.82 + 0.03 * k)
            for k in range(2):
                if 0 <= top + k < h:
                    px[x, top + k] = gm.lerp(px[x, top + k], pal.blade_hi, 0.45 - 0.2 * k)
    n = int(w * (h - y0) * 0.09 * density)
    for _ in range(n):
        x = rnd.randint(0, w - 1)
        top = max(0, top_fn(x))
        if top >= h - 1:
            continue
        y = rnd.randint(top + 1, h - 1)
        t = min(1.0, max(0.0, (y - hz) / max(1, h - hz)))
        hgt = 1 + int(t * t * 14) + rnd.randint(0, 1 + int(t * 3))
        lean = rnd.choice([-1, 0, 0, 1]) * (1 if t > 0.3 else 0)
        col = rnd.choice(pal.blade)
        for k in range(hgt):
            yy = y - k
            xx = x + (lean * k) // max(1, hgt // 2 + 1)
            if 0 <= xx < w and top <= yy < h:
                c = col
                if k == hgt - 1 and rnd.random() < 0.6:
                    c = pal.blade_hi  # 草尖的亮點（陽光）
                elif k == 0:
                    c = pal.blade_lo
                px[xx, yy] = c


def winter_tufts(px, w, h, y0, pal, rnd):
    """冬季：雪地上露出的乾草尖。"""
    for _ in range(int(w * (h - y0) * 0.02)):
        y = rnd.randint(y0 + 2, h - 1); t = (y - y0) / max(1, h - y0)
        x = rnd.randint(0, w - 1)
        for k in range(1 + int(t * 5)):
            if 0 <= y - k < h:
                px[x, y - k] = rnd.choice(pal.blade)


def snowfield(px, w, h, y0, pal, rnd, top_fn=None):
    top_fn = top_fn or (lambda x: y0)
    for x in range(w):
        for y in range(max(0, top_fn(x)), h):
            c = pal.grass_mid[(x // 5 + y // 3) % len(pal.grass_mid)]
            if rnd.random() < 0.04:
                c = (250, 252, 255)
            px[x, y] = c
    winter_tufts(px, w, h, y0, pal, rnd)


def field(px, w, h, y0, pal, rnd, density=1.0, top_fn=None, horizon=None):
    if pal.winter:
        snowfield(px, w, h, y0, pal, rnd, top_fn)
    else:
        grass_field(px, w, h, y0, pal, rnd, density, top_fn, horizon, crest=top_fn is not None)


def wave(w, base, rnd, amp, step):
    """起伏的稜線（給 field 的 top_fn 用）。"""
    ph = rnd.uniform(0, 6.28); ph2 = rnd.uniform(0, 6.28)
    tops = [int(base - amp * (0.6 * math.sin(x / step + ph) + 0.4 * math.sin(x / (step * 0.45) + ph2))) for x in range(w)]
    return lambda x: tops[max(0, min(w - 1, x))]


def river(d, px, w, h, y, width, pal, rnd, sandbar=True):
    """大河：微微彎曲的寬水面、亮的水紋、沙洲（冬季結冰）。"""
    pts = [(x, y + int(5 * math.sin(x / 70.0))) for x in range(0, w + 8, 8)]
    for i in range(width):
        d.line([(px_, py + i) for px_, py in pts], fill=pal.water)
    # 河岸的深色邊
    d.line([(px_, py - 1) for px_, py in pts], fill=gm.mul(pal.water, 0.7))
    for _ in range(w // 5):
        x = rnd.randint(0, w); yy = y + int(5 * math.sin(x / 70.0)) + rnd.randint(2, width - 2)
        d.line([x, yy, x + rnd.randint(3, 10), yy], fill=pal.water_hi)
    if sandbar:
        sx = rnd.randint(w // 5, w // 2)
        sy = y + int(5 * math.sin(sx / 70.0)) + width // 3
        d.ellipse([sx, sy, sx + w // 5, sy + width // 3], fill=pal.sand)
        d.ellipse([sx + 4, sy + 1, sx + w // 5 - 6, sy + width // 6], fill=gm.mul(pal.sand, 1.06))


def cottonwood(d, x, y, r, pal, rnd):
    """河岸的白楊：比孤樹大、樹冠成團。"""
    trunk = (96, 82, 66)
    d.line([x, y, x, y - r], fill=trunk, width=max(2, r // 4))
    if pal.winter:
        for i in range(7):
            d.line([x, y - r + 2, x + (i - 3) * r // 3, y - r * 2 + rnd.randint(0, r // 2)], fill=trunk)
        return
    dark, mid, light = pal.tree
    for i in range(3):
        cx = x + (i - 1) * r // 2 + rnd.randint(-2, 2)
        cy = y - r - r // 2 - rnd.randint(0, r // 3)
        d.ellipse([cx - r * 2 // 3, cy - r * 2 // 3, cx + r * 2 // 3, cy + r // 2], fill=dark)
    for i in range(2):
        cx = x + (i - 1) * r // 3
        cy = y - r - r // 2 - r // 4
        d.ellipse([cx - r // 2, cy - r // 2, cx + r // 4, cy + r // 6], fill=mid)
    d.ellipse([x - r // 2, y - r * 2, x - r // 8, y - r - r // 2], fill=light)


def region(name, winter):
    w, h = 640, 360
    rnd = random.Random(name + 'v2')
    pal = GPal(winter)
    im, px, d = gm.new(w, h)
    if name == 'grassland_plains':
        # 開闊草原：地平線低、天空大、積雲、遠處幾棵孤樹與淡淡的台地
        gm.sky(px, w, h, 205, pal)
        for x, y, cw in [(60, 70, 90), (230, 52, 120), (430, 80, 100), (560, 44, 70)]:
            cumulus(d, rnd, x, y, cw, pal)
        far_hills(d, w, 198, rnd, [pal.far], amp=4, step=90)
        d.polygon([(470, 199), (490, 186), (560, 185), (580, 199)], fill=pal.far_shade)  # 遠方的台地
        far_hills(d, w, 204, rnd, [pal.hill[2]], amp=2, step=120)
        field(px, w, h, 204, pal, rnd, 1.1, horizon=204)
        for x, r in [(140, 4), (152, 3), (380, 5)]:
            lone_tree(d, x, 206, r, pal, rnd)
    elif name == 'grassland_hills':
        # 丘陵草地：一層層起伏的草丘，丘頂上的孤樹
        gm.sky(px, w, h, 200, pal)
        for x, y, cw in [(80, 60, 100), (360, 40, 130)]:
            cumulus(d, rnd, x, y, cw, pal)
        far_hills(d, w, 180, rnd, [pal.far], amp=10, step=70)
        far_hills(d, w, 200, rnd, pal.hill, amp=16, step=55)
        for x, y, r in [(120, 196, 6), (300, 190, 5), (510, 202, 7), (526, 204, 5)]:
            lone_tree(d, x, y, r, pal, rnd)
        # 中景、前景的草丘：照起伏的稜線鋪草（越近的越高）
        field(px, w, h, 214, pal, rnd, 0.8, top_fn=wave(w, 216, rnd, 8, 70), horizon=200)
        field(px, w, h, 250, pal, rnd, 1.3, top_fn=wave(w, 256, rnd, 14, 90), horizon=200)
    elif name == 'grassland_riverwoods':
        # 河岸林帶：彎曲的河、兩岸成團的白楊
        gm.sky(px, w, h, 200, pal)
        cumulus(d, rnd, 420, 56, 110, pal)
        far_hills(d, w, 196, rnd, [pal.far, pal.hill[2]], amp=6, step=80)
        field(px, w, h, 206, pal, rnd)
        for x, r in [(30, 14), (90, 18), (160, 12), (470, 16), (540, 20), (610, 14), (250, 9), (330, 8)]:
            cottonwood(d, x, 236 + rnd.randint(-6, 6), r, pal, rnd)
        pts = [(0, 300), (120, 286), (260, 296), (400, 282), (520, 292), (640, 280)]
        for i in range(16):
            d.line([(x, y + i) for x, y in pts], fill=pal.water)
        d.line([(x, y - 1) for x, y in pts], fill=gm.mul(pal.water, 0.7))
        for _ in range(70):
            x = rnd.randint(0, w); yy = rnd.randint(284, 312)
            d.line([x, yy, x + rnd.randint(3, 8), yy], fill=pal.water_hi)
        for x, r in [(60, 22), (580, 24)]:
            cottonwood(d, x, 350, r, pal, rnd)
    elif name == 'grassland_river':
        # 大河：寬闊的河面與沙洲、對岸的草地與零星的白楊
        gm.sky(px, w, h, 196, pal)
        for x, y, cw in [(100, 64, 110), (450, 50, 90)]:
            cumulus(d, rnd, x, y, cw, pal)
        far_hills(d, w, 192, rnd, [pal.far], amp=5, step=90)
        field(px, w, h, 198, pal, rnd, 0.6)
        for x, r in [(210, 6), (226, 5), (500, 7)]:
            cottonwood(d, x, 214, r, pal, rnd)
        river(d, px, w, h, 222, 76, pal, rnd)
        field(px, w, h, 304, pal, rnd, 1.3, horizon=198)
    return im


def terrain(name, winter):
    w, h = 320, 180
    rnd = random.Random('t2' + name)
    pal = GPal(winter)
    im, px, d = gm.new(w, h)
    gm.sky(px, w, h, 110, pal)
    cumulus(d, rnd, 60 + rnd.randint(0, 120), 34, 70, pal)
    if name == 'prairie':
        far_hills(d, w, 100, rnd, [pal.far], amp=2, step=60)
        field(px, w, h, 102, pal, rnd, 1.2)
        lone_tree(d, 250, 104, 3, pal, rnd)
    elif name == 'rolling_hills':
        far_hills(d, w, 92, rnd, [pal.far], amp=6, step=40)
        far_hills(d, w, 104, rnd, pal.hill, amp=10, step=34)
        lone_tree(d, 90, 100, 4, pal, rnd)
        field(px, w, h, 110, pal, rnd, 1.2, top_fn=wave(w, 120, rnd, 8, 40), horizon=100)
    elif name == 'river':
        far_hills(d, w, 96, rnd, [pal.far], amp=3, step=50)
        field(px, w, h, 98, pal, rnd, 0.6)
        river(d, px, w, h, 110, 40, pal, rnd)
        field(px, w, h, 152, pal, rnd, 1.3, horizon=98)
    return im


if __name__ == '__main__':
    for r in ['grassland_riverwoods', 'grassland_river', 'grassland_plains', 'grassland_hills']:
        for winter in (False, True):
            im = region(r, winter)
            suffix = '_winter' if winter else ''
            im.save(gm.OUT_REG + r + suffix + '.png')
            im.save(ARCH + r + suffix + '_1x.png')
            im.resize((im.width * 4, im.height * 4), Image.NEAREST).save(ARCH + r + suffix + '_4x.png')
            if not winter:
                tile = im.resize((18, 18), Image.BOX)
                tile.save(gm.OUT_ICON + 'region_tile_' + r + '.png')
                tile.save(ARCH + 'region_tile_' + r + '_1x.png')
                tile.resize((72, 72), Image.NEAREST).save(ARCH + 'region_tile_' + r + '_4x.png')
    for t in ['prairie', 'rolling_hills', 'river']:
        for winter in (False, True):
            suffix = '_winter' if winter else ''
            im = terrain(t, winter)
            im.save(gm.OUT_TER + t + suffix + '.png')
            im.save(ARCH + t + suffix + '_1x.png')
            im.resize((im.width * 4, im.height * 4), Image.NEAREST).save(ARCH + t + suffix + '_4x.png')
    print('done')
