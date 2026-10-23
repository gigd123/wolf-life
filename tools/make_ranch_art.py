#!/usr/bin/env python3
"""牧場的佔位圖（Phase 4a 第 6 步）：之後換正式素材時檔名與尺寸不變。

- 區域背景 640×360（含冬季）：放牧地（草原平原調綠＋柵欄＋遠處的穀倉）、屋舍與畜欄（穀倉、冒炊煙的木屋、畜欄）、
  牧場邊緣（河岸林帶＋遠處一排柵欄樁）
- 地圖小格 18×18：同上縮小的意思
- 家畜 spritesheet：牛（小野牛的圖換成赫里福德牛的紅褐色、白臉；一歲牛、成牛放大）、羊（大角羊母羊換成米白羊毛）
- 殘骸：牛（馬鹿殘骸換色）、羊（大角羊殘骸換色）
- 遭遇的圖 112×56：巡查（騎馬的人沿柵欄走）、追獵（騎馬的人＋獵犬）、被狗追上（三隻獵犬）；獵犬是郊狼換色
- 線索圖示 16×16：柵欄、牛的蹄印、馬蹄鐵、斧頭、槍聲

用法：python3 tools/make_ranch_art.py
"""
from PIL import Image, ImageDraw, ImageOps

A = "assets/art/"
ANIM = A + "sprites/animals/"
BG = A + "backgrounds/regions/"
ICON = A + "icons/"
EV = A + "events/"

POST = (96, 70, 44)
POST_D = (66, 48, 30)
RAIL = (128, 96, 62)
BARN = (150, 52, 42)
BARN_D = (112, 38, 32)
ROOF = (70, 44, 40)
TRIM = (226, 220, 206)
LOG = (122, 92, 62)
LOG_D = (92, 68, 46)
SMOKE = (200, 200, 204)


# --- 背景 ---
def fence(d, y, x0, x1, h, spacing, w=2, rail=True):
    for x in range(x0, x1, spacing):
        d.rectangle([x, y - h, x + w - 1, y], fill=POST)
        d.point((x + w - 1, y - h), fill=POST_D)
    if rail:
        for ry in (y - h + max(1, h // 4), y - h // 2):
            d.line([x0, ry, x1, ry], fill=RAIL)


def barn(d, x, y, w, h):
    # y：地面；屋身＋人字屋頂＋白邊的門
    d.rectangle([x, y - h, x + w, y], fill=BARN)
    d.rectangle([x + w * 2 // 3, y - h, x + w, y], fill=BARN_D)
    roof_h = h * 2 // 3
    d.polygon([(x - 2, y - h), (x + w // 2, y - h - roof_h), (x + w + 2, y - h)], fill=ROOF)
    dw, dh = max(2, w // 3), max(3, h * 2 // 3)
    dx = x + (w - dw) // 2
    d.rectangle([dx, y - dh, dx + dw, y], outline=TRIM)
    if dw >= 6:
        d.line([dx, y - dh, dx + dw, y], fill=TRIM)
        d.line([dx + dw, y - dh, dx, y], fill=TRIM)


def house(d, x, y, w, h, smoke=True):
    d.rectangle([x, y - h, x + w, y], fill=LOG)
    for ly in range(y - h + 2, y, 3):
        d.line([x, ly, x + w, ly], fill=LOG_D)
    d.polygon([(x - 2, y - h), (x + w // 2, y - h - h // 2), (x + w + 2, y - h)], fill=ROOF)
    cx = x + w * 3 // 4
    d.rectangle([cx, y - h - h // 2, cx + 2, y - h - 2], fill=(90, 84, 80))
    d.rectangle([x + 3, y - h + 3, x + 6, y - h + 6], fill=(220, 190, 110))
    if smoke:
        for i, (sx, sy, r) in enumerate([(1, -4, 2), (3, -9, 3), (6, -15, 4), (10, -22, 5)]):
            px, py = cx + 1 + sx, y - h - h // 2 + sy
            d.ellipse([px - r, py - r, px + r, py + r], fill=SMOKE + (150 - i * 25,))


def greener(im, top):
    px = im.load()
    for y in range(top, im.height):
        for x in range(im.width):
            r, g, b = px[x, y][:3]
            px[x, y] = (int(r * 0.6 + 70 * 0.4), int(g * 0.75 + 150 * 0.25), int(b * 0.7 + 60 * 0.3))


def bg_pasture(src, dst, winter):
    im = Image.open(BG + src).convert("RGB")
    if not winter:
        greener(im, 200)
    d = ImageDraw.Draw(im, "RGBA")
    barn(d, 470, 202, 22, 12)
    house(d, 505, 202, 12, 8, smoke=True)
    fence(d, 202, 380, 600, 3, 9, w=1)
    fence(d, 262, -4, 644, 12, 34)
    im.save(BG + dst)


def bg_yard(src, dst, winter):
    im = Image.open(BG + src).convert("RGB")
    if not winter:
        greener(im, 200)
    d = ImageDraw.Draw(im, "RGBA")
    # 地面：踩出來的泥地
    d.ellipse([90, 230, 560, 330], fill=((150, 128, 96, 120) if not winter else (210, 206, 200, 90)))
    barn(d, 120, 262, 110, 62)
    house(d, 380, 258, 70, 44, smoke=True)
    fence(d, 300, 40, 600, 20, 26, w=3)
    fence(d, 330, -4, 644, 30, 48, w=4)
    im.save(BG + dst)


def bg_edge(src, dst, winter):
    im = Image.open(BG + src).convert("RGB")
    d = ImageDraw.Draw(im, "RGBA")
    fence(d, 214, 0, 640, 5, 14, w=1)
    barn(d, 300, 212, 14, 8)
    im.save(BG + dst)


# --- 地圖小格 18×18 ---
def tile(dst, kind):
    base = Image.open(ICON + ("region_tile_grassland_riverwoods.png" if kind == "edge" else "region_tile_grassland_plains.png")).convert("RGB")
    d = ImageDraw.Draw(base)
    if kind == "pasture":
        for x in range(1, 18, 4):
            d.line([x, 11, x, 14], fill=POST)
        d.line([0, 12, 17, 12], fill=RAIL)
    elif kind == "yard":
        d.rectangle([3, 6, 10, 13], fill=BARN)
        d.polygon([(2, 6), (6, 2), (11, 6)], fill=ROOF)
        d.rectangle([12, 9, 16, 13], fill=LOG)
        d.point((15, 7), fill=SMOKE)
    else:
        for x in range(0, 18, 3):
            d.point((x, 13), fill=POST)
            d.point((x, 12), fill=POST)
    base.save(ICON + dst)


# --- 換色 ---
def recolor(src, dst, colors, scale=1.0, frame=None, new_frame=None):
    im = Image.open(src).convert("RGBA")
    px = im.load()
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, a = px[x, y]
            if a and (r, g, b) in colors:
                px[x, y] = colors[(r, g, b)] + (a,)
    if scale != 1.0 and frame:
        cols, rows = im.width // frame[0], im.height // frame[1]
        out = Image.new("RGBA", (new_frame[0] * cols, new_frame[1] * rows))
        for r in range(rows):
            for c in range(cols):
                cell = im.crop((c * frame[0], r * frame[1], (c + 1) * frame[0], (r + 1) * frame[1]))
                cell = cell.resize((round(frame[0] * scale), round(frame[1] * scale)), Image.NEAREST)
                ox = c * new_frame[0] + (new_frame[0] - cell.width) // 2
                oy = r * new_frame[1] + new_frame[1] - cell.height
                out.alpha_composite(cell, (ox, oy))
        im = out
    im.save(dst)
    return im


def calf_palette(im):
    # 小野牛的顏色依亮度對應到赫里福德牛：暗 → 深紅褐、中 → 紅褐、亮 → 白（臉、腹）
    cols = sorted({c[1][:3] for c in im.getcolors(100000) if c[1][3] > 0}, key=lambda c: sum(c))
    out = {}
    for c in cols:
        lum = sum(c) / 3
        if lum < 40:
            out[c] = c
        elif lum < 80:
            out[c] = (82, 34, 24)
        elif lum < 115:
            out[c] = (128, 54, 34)
        elif lum < 150:
            out[c] = (156, 70, 42)
        else:
            out[c] = (232, 226, 214)
    return out


def whiten_face(path, frame):
    # 牛頭在右邊：每一格最右邊的 7 列像素（不透明、不是黑邊）改成白色，像赫里福德牛的白臉
    im = Image.open(path).convert("RGBA")
    px = im.load()
    cols, rows = im.width // frame[0], im.height // frame[1]
    for r in range(rows):
        for c in range(cols):
            x0, y0 = c * frame[0], r * frame[1]
            right = -1
            for x in range(x0 + frame[0] - 1, x0 - 1, -1):
                if any(px[x, y][3] > 0 for y in range(y0, y0 + frame[1])):
                    right = x
                    break
            if right < 0:
                continue
            for x in range(right - int(frame[0] * 0.16), right + 1):
                for y in range(y0, y0 + int(frame[1] * 0.75)):
                    p = px[x, y]
                    if p[3] > 0 and sum(p[:3]) > 90:
                        px[x, y] = (232, 226, 214, p[3])
    im.save(path)


def _remove_horns(path, frame, rows):
    # 大角羊母羊頭上的短角：每一格最上面 rows 列清掉（羊的頭在這之下）
    im = Image.open(path).convert("RGBA")
    px = im.load()
    for y in range(im.height):
        if y % frame[1] < rows:
            for x in range(im.width):
                px[x, y] = (0, 0, 0, 0)
    im.save(path)


def livestock():
    calf_src = ANIM + "bison_calf_sheet.png"
    pal = calf_palette(Image.open(calf_src).convert("RGBA"))
    recolor(calf_src, ANIM + "cattle_calf_sheet.png", pal)
    recolor(calf_src, ANIM + "cattle_yearling_sheet.png", pal, 1.4, (56, 40), (80, 56))
    recolor(calf_src, ANIM + "cattle_cow_sheet.png", pal, 1.75, (56, 40), (100, 70))
    whiten_face(ANIM + "cattle_calf_sheet.png", (56, 40))
    whiten_face(ANIM + "cattle_yearling_sheet.png", (80, 56))
    whiten_face(ANIM + "cattle_cow_sheet.png", (100, 70))
    sheep = {(138, 108, 76): (226, 218, 200), (100, 76, 54): (196, 186, 166), (176, 156, 116): (226, 218, 200),
             (236, 228, 208): (240, 236, 226), (222, 212, 190): (214, 206, 188)}
    recolor(ANIM + "bighorn_ewe_sheet.png", ANIM + "sheep_sheet.png", sheep)
    _remove_horns(ANIM + "sheep_sheet.png", (48, 32), 6)
    recolor(ANIM + "carcass_elk.png", ANIM + "carcass_cattle.png", calf_palette(Image.open(ANIM + "carcass_elk.png").convert("RGBA")))
    recolor(ANIM + "carcass_bighorn.png", ANIM + "carcass_sheep.png", sheep)


# --- 獵犬、騎馬的人 ---
HOUND = {(160, 138, 110): (120, 74, 40), (180, 124, 76): (150, 96, 52), (152, 134, 112): (44, 36, 30), (184, 172, 153): (176, 120, 70),
         (118, 104, 90): (40, 32, 28), (224, 210, 186): (200, 160, 110), (74, 65, 54): (30, 24, 20), (68, 60, 52): (30, 24, 20),
         (92, 86, 76): (52, 40, 32), (90, 78, 62): (52, 40, 32)}


def hound_frame():
    im = Image.open(ANIM + "coyote_sheet.png").convert("RGBA").crop((48, 32, 96, 64))
    px = im.load()
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, a = px[x, y]
            if a and (r, g, b) in HOUND:
                px[x, y] = HOUND[(r, g, b)] + (a,)
    return im.crop(im.getbbox())


def rider(d, x, y):
    # 遠處的騎馬的人（x：馬的左端，y：地面），朝左
    horse, horse_d, man, hat = (92, 62, 40), (60, 40, 28), (70, 76, 92), (40, 34, 30)
    d.rectangle([x + 4, y - 14, x + 20, y - 8], fill=horse)
    d.rectangle([x, y - 19, x + 5, y - 13], fill=horse)
    d.point((x, y - 17), fill=horse_d)
    d.line([x + 2, y - 19, x + 3, y - 21], fill=horse_d)
    for lx in (x + 5, x + 8, x + 16, x + 19):
        d.line([lx, y - 8, lx, y], fill=horse_d)
    d.line([x + 21, y - 13, x + 23, y - 6], fill=horse_d)
    d.rectangle([x + 10, y - 23, x + 14, y - 14], fill=man)
    d.rectangle([x + 10, y - 27, x + 13, y - 24], fill=(200, 160, 130))
    d.rectangle([x + 8, y - 28, x + 15, y - 28], fill=hat)
    d.rectangle([x + 10, y - 30, x + 13, y - 29], fill=hat)
    d.line([x + 6, y - 22, x + 16, y - 22], fill=(50, 44, 40))  # 槍


def event_image(dst, riders, hounds):
    im = Image.new("RGBA", (112, 56))
    d = ImageDraw.Draw(im)
    d.rectangle([0, 46, 111, 55], fill=(124, 140, 74, 255))
    fence(d, 46, 2, 110, 8, 15, w=2)
    for rx in riders:
        # 騎馬的人和獵犬都朝右：畫在暫存圖上再左右翻轉
        tmp = Image.new("RGBA", (30, 34))
        rider(ImageDraw.Draw(tmp), 3, 33)
        im.alpha_composite(ImageOps.mirror(tmp), (rx, 50 - 33))
    hf = hound_frame()
    for hx, hy in hounds:
        im.alpha_composite(hf, (hx, hy - hf.height))
    im.save(EV + dst)


# --- 線索圖示 16×16 ---
def icons():
    def new():
        im = Image.new("RGBA", (16, 16))
        return im, ImageDraw.Draw(im)
    im, d = new()
    for x in (2, 7, 12):
        d.rectangle([x, 3, x + 1, 14], fill=POST)
    d.line([1, 6, 14, 6], fill=RAIL)
    d.line([1, 10, 14, 10], fill=RAIL)
    im.save(ICON + "clue_fence.png")
    im, d = new()
    for ox, oy in ((2, 2), (8, 8)):
        d.ellipse([ox, oy, ox + 2, oy + 4], fill=(70, 52, 40))
        d.ellipse([ox + 3, oy, ox + 5, oy + 4], fill=(70, 52, 40))
    im.save(ICON + "clue_cattle.png")
    im, d = new()
    d.arc([3, 2, 12, 13], 200, 340, fill=(150, 150, 156), width=2)
    d.arc([3, 2, 12, 13], 20, 160, fill=(150, 150, 156), width=0)
    d.line([3, 9, 3, 13], fill=(150, 150, 156), width=2)
    d.line([12, 9, 12, 13], fill=(150, 150, 156), width=2)
    for p in ((4, 6), (11, 6), (4, 10), (11, 10)):
        d.point(p, fill=(60, 60, 64))
    im.save(ICON + "clue_horseshoe.png")
    im, d = new()
    d.line([3, 14, 11, 4], fill=(120, 88, 56), width=2)
    d.polygon([(9, 2), (14, 3), (13, 8), (10, 6)], fill=(170, 172, 178))
    im.save(ICON + "clue_axe.png")
    im, d = new()
    d.line([1, 9, 9, 9], fill=(60, 52, 46), width=2)
    d.line([6, 10, 4, 13], fill=(100, 74, 50), width=2)
    for i, (x, y) in enumerate(((11, 9), (13, 6), (13, 12), (15, 9))):
        d.point((x, y), fill=(240, 200, 110))
    im.save(ICON + "clue_gunshot.png")


bg_pasture("grassland_plains.png", "ranch_pasture.png", False)
bg_pasture("grassland_plains_winter.png", "ranch_pasture_winter.png", True)
bg_yard("grassland_plains.png", "ranch_yard.png", False)
bg_yard("grassland_plains_winter.png", "ranch_yard_winter.png", True)
bg_edge("grassland_riverwoods.png", "ranch_edge.png", False)
bg_edge("grassland_riverwoods_winter.png", "ranch_edge_winter.png", True)
tile("region_tile_ranch_pasture.png", "pasture")
tile("region_tile_ranch_yard.png", "yard")
tile("region_tile_ranch_edge.png", "edge")
livestock()
event_image("ranch_patrol.png", [60], [])
event_image("ranch_hunt.png", [78], [(4, 52), (34, 54)])
event_image("ranch_dogs.png", [], [(2, 52), (36, 54), (70, 51)])
icons()
print("完成")
