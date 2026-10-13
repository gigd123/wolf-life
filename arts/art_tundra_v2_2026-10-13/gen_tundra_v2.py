#!/usr/bin/env python3
# 苔原美術第 2 版（2026-10-13，依使用者提供的參考圖改畫，照山地、草原第 2 版的做法）：
# 陰天的灰藍天空、低雲與霧帶半遮的灰色遠山（山坡上一條條殘雪）；地面是苔蘚綠、紅褐、橘、赭黃交錯的低矮植被與淡灰綠的地衣，
# 散落帶地衣斑點的深色石頭、零星殘雪。林線：稀疏細長的黑雲杉；河谷：辮狀河道、礫石灘、柳叢；遠北：碎石、殘雪、沙脊；
# 開闊苔原：起伏的地面與小水塘。冬季：雪原、露出的石頭、白色的山。
# 沿用 arts/art_mountain_2026-10-13/gen_mountain_v2.py 的工具函式。
# 產生：區域背景 640×360（含冬季版）4 張、地形背景 320×180（林線、開闊苔原、河谷柳叢、岩石區、沙脊，含冬季；冰面、薄冰）、區域小圖。
# 用法：在專案根目錄 python3 arts/art_tundra_v2_2026-10-13/gen_tundra_v2.py
import math, random, sys
from PIL import Image, ImageDraw
sys.path.insert(0, 'arts/art_mountain_2026-10-13')
import gen_mountain_v2 as gm

ARCH = 'arts/art_tundra_v2_2026-10-13/'


class TPal(gm.Pal):
    def __init__(self, winter):
        super().__init__(winter)
        self.sky_top = (132, 150, 172) if not winter else (150, 160, 178)
        self.sky_bot = (210, 214, 216) if not winter else (226, 228, 232)
        self.fog = (222, 224, 226) if not winter else (234, 236, 240)
        self.far = (112, 120, 136) if not winter else (196, 204, 218)
        self.far_shade = (92, 100, 116) if not winter else (170, 180, 198)
        # 植被的色塊：苔蘚綠、紅褐、橘、赭黃、地衣（冬季是雪）
        # 依雜訊值由低到高：深苔蘚、苔蘚、地衣、苔蘚、赭黃、橘、紅褐（苔蘚與地衣占多數，紅橘點綴）
        self.veg = [(98, 108, 68), (118, 128, 78), (160, 170, 132), (128, 134, 82), (168, 146, 86), (176, 106, 60), (140, 70, 50)] if not winter else \
            [(234, 238, 244), (222, 228, 238), (244, 246, 250), (214, 222, 234)]
        self.veg_cut = [0.36, 0.46, 0.53, 0.58, 0.63, 0.68] if not winter else [0.4, 0.5, 0.6]
        self.rock = [(70, 72, 76), (84, 86, 90), (58, 60, 64)]
        self.lichen = (170, 182, 140) if not winter else (236, 240, 246)
        self.snow = (238, 242, 248)
        self.water = (92, 118, 138) if not winter else (196, 214, 228)
        self.water_hi = (170, 192, 206) if not winter else (236, 244, 250)
        self.gravel = [(150, 144, 132), (130, 124, 114), (168, 162, 150)] if not winter else [(226, 230, 238), (214, 220, 232)]
        self.spruce = [(28, 44, 40), (40, 60, 50), (58, 80, 64)]
        self.willow = [(150, 150, 70), (176, 166, 76), (122, 128, 62)] if not winter else [(150, 140, 126), (170, 160, 146), (128, 120, 108)]


def overcast(px, d, w, h, horizon, pal, rnd):
    """陰天：抖動漸層的天空，加上幾道淡淡的雲層。"""
    gm.sky(px, w, h, horizon, pal)
    for _ in range(5):
        y = rnd.randint(20, horizon - 60); x = rnd.randint(-80, w)
        cw = rnd.randint(120, 260)
        for k in range(rnd.randint(3, 6)):
            d.line([x + k * 7, y + k, x + cw - k * 9, y + k], fill=gm.lerp(pal.sky_bot, pal.fog, 0.6))


def far_range(d, w, base, rnd, pal, specs, streaks=True):
    """灰色遠山，山坡上一條條殘雪（往下斜的白線）。"""
    gm.peaks(d, rnd, base, specs, pal, snow_frac=0.3)
    if streaks:
        for cx, hgt, hw in specs:
            for _ in range(int(hw * 0.25)):
                x = rnd.randint(cx - hw + 10, cx - 4)
                top = base - hgt + abs(x - cx) * hgt // hw
                if top + 4 >= base - 4:
                    continue  # 太靠近山腳
                y = rnd.randint(top + 4, base - 4)
                d.line([x, y, x - rnd.randint(1, 3), y + rnd.randint(2, 5)], fill=gm.lerp(pal.far, pal.snow, 0.75))


def fog_band(px, w, y0, y1, pal, rnd):
    """低雲／霧帶：中間最濃、上下淡出（抖動混色）。"""
    for y in range(y0, y1):
        t = 1.0 - abs((y - y0) / max(1, y1 - y0) * 2 - 1)
        for x in range(w):
            k = 0.82 * t + (gm.BAYER[y % 4][x % 4] - 7.5) / 160.0
            px[x, y] = gm.lerp(px[x, y], pal.fog, max(0.0, min(1.0, k)))


def veg_ground(px, w, h, y0, pal, rnd, horizon=None, scale=1.0):
    """苔原的地面：用低頻雜訊挑植被色塊（遠處小、近處大），再加細小的亮暗點。"""
    hz = horizon if horizon is not None else y0
    n1 = gm.Noise(rnd, int(26 * scale)); n2 = gm.Noise(rnd, int(9 * scale))
    cols = pal.veg
    for y in range(y0, h):
        t = max(0.15, (y - hz) / max(1, h - hz))
        for x in range(w):
            # 透視：遠處的雜訊在水平方向壓縮
            v = n1.at(int(x / t * 0.5) % 4000, int(y / t * 1.2)) * 0.6 + n2.at(x, y) * 0.4
            # 加一點像素抖動，色塊邊緣才不會像迷彩一樣一整塊
            v += (gm.BAYER[y % 4][x % 4] - 7.5) / 60.0
            # 雜訊值集中在 0.5 附近，用分段門檻讓各色都有合理的比例（苔蘚約一半、地衣與赭黃、橘與紅褐成片點綴）
            idx = sum(1 for th in pal.veg_cut if v > th)
            c = cols[min(len(cols) - 1, idx)]
            r = rnd.random()
            if r < 0.09:
                c = gm.mul(c, 1.12)
            elif r < 0.18:
                c = gm.mul(c, 0.86)
            px[x, y] = c


def rocks(px, w, h, y0, pal, rnd, n, big=1.0):
    """散落的深色石頭，頂上有地衣斑點（冬季頂上積雪），越近越大。"""
    for _ in range(n):
        y = rnd.randint(y0 + 2, h - 2)
        t = (y - y0) / max(1, h - y0)
        r = max(1, int((1 + t * 7) * big * rnd.uniform(0.6, 1.3)))
        gm.boulder(px, w, h, rnd.randint(0, w - 1), y, r + rnd.randint(0, r // 2 + 1), max(1, r * 3 // 4),
                   rnd.choice(pal.rock), rnd, moss=pal.lichen, snow=pal.snow if pal.winter else None)


def snow_patches(d, w, y0, h, pal, rnd, n):
    if pal.winter:
        return
    for _ in range(n):
        y = rnd.randint(y0 + 2, h - 4); t = (y - y0) / max(1, h - y0)
        x = rnd.randint(0, w); pw = int(6 + t * 50 * rnd.uniform(0.5, 1.2)); ph = max(1, int(1 + t * 6))
        d.ellipse([x, y, x + pw, y + ph], fill=pal.snow)
        d.ellipse([x + pw // 4, y - 1, x + pw * 3 // 4, y + ph // 2], fill=(248, 250, 252))


def spruce(d, x, base, hgt, pal):
    """北方林線的黑雲杉：細長、枝條短、樹梢尖。"""
    dark, mid, light = pal.spruce
    d.line([x, base, x, base - hgt], fill=dark)
    for i in range(hgt // 3):
        y = base - hgt + 2 + i * 3
        hw = 1 + i * max(1, hgt // 12) // 3
        d.line([x - hw, y + 1, x + hw, y], fill=dark)
        d.point((x - hw, y + 1), fill=mid)
    if pal.winter:
        for i in range(0, hgt // 3, 2):
            y = base - hgt + 2 + i * 3
            d.point((x - 1, y), fill=pal.snow); d.point((x + 1, y), fill=pal.snow)


def pond(d, x, y, rw, rh, pal):
    d.ellipse([x - rw, y - rh, x + rw, y + rh], fill=gm.mul(pal.water, 0.85))
    d.ellipse([x - rw + 1, y - rh + 1, x + rw - 1, y + rh - 1], fill=pal.water)
    d.line([x - rw // 2, y - rh // 3, x + rw // 3, y - rh // 3], fill=pal.water_hi)


def braided(d, w, y0, y1, pal, rnd):
    """辮狀河道：寬的礫石灘上，幾條彎曲的水道分開又匯合。"""
    d.rectangle([0, y0, w, y1], fill=pal.gravel[0])
    for _ in range(w * (y1 - y0) // 4):
        d.point((rnd.randint(0, w), rnd.randint(y0, y1)), fill=rnd.choice(pal.gravel))
    for k in range(4):
        ph = rnd.uniform(0, 6.28); amp = rnd.randint(4, 10); yc = y0 + (y1 - y0) * (k + 1) // 5
        wid = rnd.randint(3, 7); period = rnd.randint(40, 80)
        pts = [(x, int(yc + amp * math.sin(x / period + ph))) for x in range(0, w + 8, 4)]
        for i in range(wid):
            d.line([(x, y + i) for x, y in pts], fill=pal.water)
        d.line([(x, y) for x, y in pts], fill=pal.water_hi)


def willow(d, x, y, r, pal, rnd):
    if pal.winter:
        # 冬季落葉：一叢細枝條
        for i in range(5):
            d.line([x + (i - 2), y, x + (i - 2) * 2 + rnd.randint(-1, 1), y - r - rnd.randint(0, r)], fill=pal.willow[i % 3])
        return
    a, b, c = pal.willow
    d.ellipse([x - r, y - r, x + r, y + r // 2], fill=c)
    d.ellipse([x - r + 1, y - r, x + r // 2, y], fill=a)
    d.ellipse([x - r // 2, y - r, x, y - r // 3], fill=b)


def esker(px, w, h, y, rnd, pal):
    """沙脊：一道長而低、起伏的礫石脊，脊頂亮、坡面往下變暗，底部被植被蓋住。"""
    ph = rnd.uniform(0, 6.28); ph2 = rnd.uniform(0, 6.28)
    for x in range(w):
        top = int(y - 6 - 4 * math.sin(x / 50 + ph) - 2 * math.sin(x / 17 + ph2))
        bot = y + 6 + int(2 * math.sin(x / 23 + ph2))
        for yy in range(max(0, top), min(h, bot)):
            t = (yy - top) / max(1, bot - top)
            c = gm.lerp(gm.mul(pal.gravel[-1], 1.08), gm.mul(pal.gravel[0], 0.8), t)
            if (x * 7 + yy * 13) % 11 == 0:
                c = gm.mul(c, 0.85)
            # 下半部漸漸被植被蓋住
            if t > 0.6 and rnd.random() < (t - 0.6) * 2:
                continue
            px[x, yy] = c


def region(name, winter):
    w, h = 640, 360
    rnd = random.Random(name + 'v2')
    pal = TPal(winter)
    im, px, d = gm.new(w, h)
    if name == 'tundra_south':
        # 苔原林線：遠山、霧帶、稀疏細長的黑雲杉往北漸少
        overcast(px, d, w, h, 200, pal, rnd)
        far_range(d, w, 196, rnd, pal, [(140, 90, 160), (420, 110, 190)])
        fog_band(px, w, 150, 196, pal, rnd)
        veg_ground(px, w, h, 196, pal, rnd)
        for _ in range(60):
            x = rnd.randint(0, w); y = rnd.randint(196, 250)
            spruce(d, x, y, int(10 + (y - 196) * 0.5) + rnd.randint(0, 6), pal)
        rocks(px, w, h, 196, pal, rnd, 30)
        snow_patches(d, w, 196, h, pal, rnd, 10)
        for x, y, ht in [(26, 362, 100), (604, 360, 90), (72, 344, 70)]:
            gm.conifer(d, x, y, ht, pal, rnd, snow=winter)
    elif name == 'tundra_central':
        # 開闊苔原：起伏的地面、紅橘綠交錯的植被、小水塘、遠山
        overcast(px, d, w, h, 205, pal, rnd)
        far_range(d, w, 202, rnd, pal, [(90, 70, 130), (330, 60, 150), (560, 80, 140)])
        fog_band(px, w, 168, 204, pal, rnd)
        veg_ground(px, w, h, 202, pal, rnd)
        for _ in range(7):
            y = rnd.randint(215, 330); t = (y - 202) / 158
            pond(d, rnd.randint(20, 620), y, int(6 + t * 40), int(1 + t * 6), pal)
        rocks(px, w, h, 202, pal, rnd, 26)
        snow_patches(d, w, 202, h, pal, rnd, 8)
    elif name == 'tundra_east':
        # 苔原河谷：辮狀河道與礫石灘、兩岸的柳叢
        overcast(px, d, w, h, 196, pal, rnd)
        far_range(d, w, 192, rnd, pal, [(200, 100, 170), (500, 80, 150)])
        fog_band(px, w, 140, 192, pal, rnd)
        veg_ground(px, w, h, 192, pal, rnd)
        braided(d, w, 250, 300, pal, rnd)
        for _ in range(26):
            x = rnd.randint(0, w); y = rnd.choice([rnd.randint(228, 250), rnd.randint(300, 340)])
            willow(d, x, y, int(3 + (y - 192) * 0.06) + rnd.randint(0, 3), pal, rnd)
        rocks(px, w, h, 192, pal, rnd, 18)
    elif name == 'tundra_north':
        # 遠北苔原：碎石、殘雪、沙脊，植被稀薄
        overcast(px, d, w, h, 210, pal, rnd)
        far_range(d, w, 206, rnd, pal, [(160, 70, 170), (470, 90, 200)])
        fog_band(px, w, 150, 206, pal, rnd)
        veg_ground(px, w, h, 206, pal, rnd, scale=0.7)
        esker(px, w, h, 244, rnd, pal)
        rocks(px, w, h, 206, pal, rnd, 120, big=0.8)
        snow_patches(d, w, 206, h, pal, rnd, 22)
    return im


def terrain(name, winter):
    w, h = 320, 180
    rnd = random.Random('t2' + name)
    pal = TPal(winter)
    im, px, d = gm.new(w, h)
    overcast(px, d, w, h, 104, pal, rnd)
    far_range(d, w, 100, rnd, pal, [(90, 50, 90), (250, 60, 110)])
    fog_band(px, w, 74, 100, pal, rnd)
    veg_ground(px, w, h, 100, pal, rnd, scale=0.8)
    if name == 'treeline':
        for _ in range(26):
            x = rnd.randint(0, w); y = rnd.randint(100, 150)
            spruce(d, x, y, int(8 + (y - 100) * 0.7) + rnd.randint(0, 5), pal)
        rocks(px, w, h, 100, pal, rnd, 10)
    elif name == 'open_tundra':
        pond(d, 220, 140, 30, 5, pal)
        rocks(px, w, h, 100, pal, rnd, 14)
        snow_patches(d, w, 100, h, pal, rnd, 5)
    elif name == 'river_willow':
        braided(d, w, 128, 152, pal, rnd)
        for _ in range(14):
            x = rnd.randint(0, w); y = rnd.choice([rnd.randint(112, 128), rnd.randint(152, 176)])
            willow(d, x, y, int(3 + (y - 100) * 0.08) + rnd.randint(0, 2), pal, rnd)
    elif name == 'rocky':
        rocks(px, w, h, 100, pal, rnd, 90, big=0.9)
        snow_patches(d, w, 100, h, pal, rnd, 8)
    elif name == 'esker':
        esker(px, w, h, 128, rnd, pal)
        rocks(px, w, h, 100, pal, rnd, 20, big=0.7)
    return im


def ice(thin):
    """結冰的河面（冰面捷徑、渡河用）：灰白的冰、裂紋、對岸的苔原；thin 是春季的薄冰（顏色偏深、有水窪與大裂縫）。"""
    w, h = 320, 180
    rnd = random.Random('ice' + str(thin))
    pal = TPal(True)
    im, px, d = gm.new(w, h)
    overcast(px, d, w, h, 96, pal, rnd)
    far_range(d, w, 92, rnd, pal, [(120, 50, 100), (260, 40, 90)])
    fog_band(px, w, 66, 92, pal, rnd)
    snowfield_y = 92
    for y in range(snowfield_y, 110):
        d.line([0, y, w, y], fill=pal.veg[(y // 3) % len(pal.veg)])
    base = (178, 198, 214) if not thin else (138, 162, 180)
    for y in range(110, h):
        t = (y - 110) / (h - 110)
        for x in range(w):
            c = gm.lerp(base, (214, 226, 236), 0.3 * (1 - t))
            if rnd.random() < 0.05:
                c = gm.mul(c, 1.08)
            px[x, y] = c
    for _ in range(18 if not thin else 34):
        x = rnd.randint(0, w); y = rnd.randint(112, h - 2); pts = [(x, y)]
        for _ in range(rnd.randint(2, 5)):
            x += rnd.randint(-14, 14); y += rnd.randint(-3, 6); pts.append((x, y))
        d.line(pts, fill=(236, 244, 250) if not thin else (88, 112, 132))
    if thin:
        for _ in range(6):
            x = rnd.randint(10, w - 40); y = rnd.randint(120, h - 10)
            d.ellipse([x, y, x + rnd.randint(14, 40), y + rnd.randint(2, 6)], fill=(96, 122, 144))
    return im


def save(im, path, arch):
    im.save(path)
    im.save(ARCH + arch + '_1x.png')
    im.resize((im.width * 4, im.height * 4), Image.NEAREST).save(ARCH + arch + '_4x.png')


if __name__ == '__main__':
    for r in ['tundra_south', 'tundra_central', 'tundra_east', 'tundra_north']:
        for winter in (False, True):
            im = region(r, winter)
            suffix = '_winter' if winter else ''
            save(im, gm.OUT_REG + r + suffix + '.png', r + suffix)
            if not winter:
                save(im.resize((18, 18), Image.BOX), gm.OUT_ICON + 'region_tile_' + r + '.png', 'region_tile_' + r)
    for t in ['treeline', 'open_tundra', 'river_willow', 'rocky', 'esker']:
        for winter in (False, True):
            suffix = '_winter' if winter else ''
            save(terrain(t, winter), gm.OUT_TER + t + suffix + '.png', t + suffix)
    save(ice(False), gm.OUT_TER + 'ice.png', 'ice')
    save(ice(True), gm.OUT_TER + 'ice_thin.png', 'ice_thin')
    print('done')
