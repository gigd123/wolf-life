"""HD-2D 測試的素材處理（2026-11-04）。

從使用者給的參考圖（arts/hd2d_test_2026-11-04/reference.jpg，AI 生成的概念圖）裁出
狼、駝鹿、樹與地面材質，清理成真正的像素圖（對齊像素格、限制顏色、去背），
做 32 與 48 兩種密度（一格幾像素）。只給 prototypes/hd2d_tactical/ 的測試用，不進正式遊戲。

用法：python3 prototypes/hd2d_tactical/prep_assets.py arts/hd2d_test_2026-11-04/reference.jpg
"""
import os
import sys
from collections import deque

from PIL import Image

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "assets")

# 參考圖裡的卡片（白底的小圖）：(名稱, 範圍)
CARDS = {
    "wolf_stand": (40, 660, 108, 729),
    "wolf_walk": (118, 660, 207, 729),
    "wolf_walk2": (216, 660, 297, 729),
    "wolf_stalk": (306, 660, 407, 729),
    "moose_stand": (1015, 618, 1148, 708),
    "moose_walk": (1153, 618, 1292, 708),
}
# 樹：只取半邊（另一半和別的樹重疊），左右鏡像成一整棵。(名稱, 範圍, 中線 x, 取哪一半)
TREES = {
    "pine_snow": ((1240, 385, 1370, 650), 1295, "right"),
    "pine_dark": ((40, 330, 180, 610), 110, "left"),
}
# 地面材質：(名稱, 範圍)。整塊縮小成像素圖後左右上下鏡像，拼起來沒有接縫。
TEXTURES = {
    "snow": (520, 440, 600, 480),
    "dirt": (1060, 500, 1130, 535),
    "grass": (1150, 350, 1250, 395),
    "rock": (680, 360, 730, 430),
    "wall": (150, 405, 310, 460),
}
# 目標大小（一格 32 或 48 像素時）：狼約一格多一點長，駝鹿約兩格
SPRITE_LEN = {"wolf": {32: 40, 48: 58}, "moose": {32: 64, 48: 92}}
TREE_H = {32: 96, 48: 140}
SRC_PIXEL = 3.5  # 場景裡一個像素約 3.5 個圖片像素（材質用）
COLORS = 24


def near_white(c, tol=38):
    return min(c) > 255 - tol


def near_bg(c, ref=(228, 228, 224), tol=26):
    return all(abs(a - b) <= tol for a, b in zip(c, ref))


def cut_card(im, box):
    """白底卡片：從邊框往內 flood fill 白色當背景，剩下的就是動物；去掉左上角的標籤字。"""
    c = im.crop(box).convert("RGBA")
    w, h = c.size
    px = c.load()
    bg = [[False] * w for _ in range(h)]
    q = deque()
    for x in range(w):
        q.append((x, 0)); q.append((x, h - 1))
    for y in range(h):
        q.append((0, y)); q.append((w - 1, y))
    while q:
        x, y = q.popleft()
        if x < 0 or y < 0 or x >= w or y >= h or bg[y][x]:
            continue
        if not near_white(px[x, y][:3]) and not (x in (0, 1, w - 1, w - 2) or y in (0, 1, h - 1, h - 2)):
            continue
        bg[y][x] = True
        q.extend(((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)))
    for y in range(h):
        for x in range(w):
            if bg[y][x] or (x < 26 and y < 14):
                px[x, y] = (0, 0, 0, 0)
    return keep_largest(c.crop(c.getbbox()))


def cut_tree(im, box, mid, side):
    c = im.crop(box).convert("RGBA")
    px = c.load()
    w, h = c.size
    for y in range(h):
        for x in range(w):
            if near_bg(px[x, y][:3]):
                px[x, y] = (0, 0, 0, 0)
    m = mid - box[0]
    half = c.crop((m, 0, w, h)) if side == "right" else c.crop((0, 0, m, h))
    mirror = half.transpose(Image.FLIP_LEFT_RIGHT)
    full = Image.new("RGBA", (half.width * 2, h), (0, 0, 0, 0))
    if side == "right":
        full.paste(mirror, (0, 0)); full.paste(half, (half.width, 0))
    else:
        full.paste(half, (0, 0)); full.paste(mirror, (half.width, 0))
    # 只留和樹幹相連的部分（去掉旁邊雜物）
    return keep_largest(full.crop(full.getbbox()))


def keep_largest(img):
    """只留最大的一塊（去掉卡片邊框的線、旁邊的雜點）。"""
    px = img.load()
    w, h = img.size
    seen = [[False] * w for _ in range(h)]
    best = []
    for sy in range(h):
        for sx in range(w):
            if seen[sy][sx] or px[sx, sy][3] == 0:
                continue
            comp = []
            q = deque([(sx, sy)])
            seen[sy][sx] = True
            while q:
                x, y = q.popleft()
                comp.append((x, y))
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < w and 0 <= ny < h and not seen[ny][nx] and px[nx, ny][3] != 0:
                        seen[ny][nx] = True
                        q.append((nx, ny))
            if len(comp) > len(best):
                best = comp
    keep = set(best)
    for y in range(h):
        for x in range(w):
            if (x, y) not in keep:
                px[x, y] = (0, 0, 0, 0)
    return img.crop(img.getbbox())


def pixelize(img, size):
    """縮小成像素圖：先平均（不留雜訊）再限制顏色；透明度二值化（像素圖不要半透明邊）。"""
    rgba = img.resize(size, Image.BOX)
    a = rgba.getchannel("A").point(lambda v: 255 if v >= 128 else 0)
    rgb = rgba.convert("RGB").quantize(colors=COLORS, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).convert("RGB")
    out = rgb.convert("RGBA")
    out.putalpha(a)
    return out


def outline_dark(img):
    """邊緣的像素壓暗一點（參考圖的動物有深色邊），去背後邊緣比較乾淨。"""
    px = img.load()
    w, h = img.size
    edge = []
    for y in range(h):
        for x in range(w):
            if px[x, y][3] == 0:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if nx < 0 or ny < 0 or nx >= w or ny >= h or px[nx, ny][3] == 0:
                    edge.append((x, y)); break
    for x, y in edge:
        r, g, b, a = px[x, y]
        px[x, y] = (int(r * 0.55), int(g * 0.55), int(b * 0.6), a)
    return img


def tile_noise(size, period, seed, stretch=(1, 1)):
    """可以無縫拼接的雜訊：格點隨機值在環面上做雙線性內插。"""
    import random
    rnd = random.Random(seed)
    px, py = max(1, period * stretch[0]), max(1, period * stretch[1])
    gx, gy = max(1, size // px), max(1, size // py)
    grid = [[rnd.random() for _ in range(gx)] for _ in range(gy)]
    out = [[0.0] * size for _ in range(size)]
    for y in range(size):
        fy = y / px * 0 + y / py
        y0 = int(fy) % gy; y1 = (y0 + 1) % gy; ty = fy - int(fy)
        for x in range(size):
            fx = x / px
            x0 = int(fx) % gx; x1 = (x0 + 1) % gx; tx = fx - int(fx)
            a = grid[y0][x0] * (1 - tx) + grid[y0][x1] * tx
            b = grid[y1][x0] * (1 - tx) + grid[y1][x1] * tx
            out[y][x] = a * (1 - ty) + b * ty
    return out


def procedural(crop, size, seed, stretch=(1, 1), colors=7, no_green=False):
    """取參考圖那一塊的顏色（依出現比例），用雜訊排出新的像素材質，可以無縫拼接、不會有對稱花紋。"""
    import random
    q = crop.quantize(colors=colors, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
    pal = q.getpalette()[: colors * 3]
    counts = sorted(q.getcolors(), key=lambda c: c[1])
    if no_green:
        counts = [c for c in counts if not (pal[c[1] * 3 + 1] > pal[c[1] * 3] + 4)] or counts
    cols = [tuple(pal[i * 3: i * 3 + 3]) for _, i in counts]
    weights = [n for n, _ in counts]
    order = sorted(range(len(cols)), key=lambda i: sum(cols[i]))
    cols = [cols[i] for i in order]; weights = [weights[i] for i in order]
    total = float(sum(weights))
    cum = []
    acc = 0.0
    for w in weights:
        acc += w / total
        cum.append(acc)
    n1 = tile_noise(size, 8, seed, stretch)
    n2 = tile_noise(size, 4, seed + 1, stretch)
    n3 = tile_noise(size, 2, seed + 2, (1, 1))
    vals = []
    for y in range(size):
        for x in range(size):
            vals.append(n1[y][x] * 0.55 + n2[y][x] * 0.3 + n3[y][x] * 0.15)
    ranked = sorted(vals)
    img = Image.new("RGB", (size, size))
    px = img.load()
    for y in range(size):
        for x in range(size):
            v = vals[y * size + x]
            # 換成百分位，再照顏色出現比例決定用哪一色
            lo, hi = 0, len(ranked)
            while lo < hi:
                mid = (lo + hi) // 2
                if ranked[mid] < v:
                    lo = mid + 1
                else:
                    hi = mid
            pct = lo / len(ranked)
            k = next(i for i, c in enumerate(cum) if pct <= c + 1e-9)
            px[x, y] = cols[k]
    return img


def seamless(img):
    w, h = img.size
    out = Image.new("RGB", (w * 2, h * 2))
    out.paste(img, (0, 0))
    out.paste(img.transpose(Image.FLIP_LEFT_RIGHT), (w, 0))
    out.paste(img.transpose(Image.FLIP_TOP_BOTTOM), (0, h))
    out.paste(img.transpose(Image.ROTATE_180), (w, h))
    return out


def main(src):
    os.makedirs(OUT, exist_ok=True)
    im = Image.open(src).convert("RGB")
    for name, box in CARDS.items():
        raw = cut_card(im, box)
        kind = name.split("_")[0]
        for tile, length in SPRITE_LEN[kind].items():
            h = max(1, round(raw.height * length / raw.width))
            outline_dark(pixelize(raw, (length, h))).save(os.path.join(OUT, "%s_%d.png" % (name, tile)))
    for name, (box, mid, side) in TREES.items():
        raw = cut_tree(im, box, mid, side)
        for tile, height in TREE_H.items():
            w = max(1, round(raw.width * height / raw.height))
            pixelize(raw, (w, height)).save(os.path.join(OUT, "%s_%d.png" % (name, tile)))
    for i, (name, box) in enumerate(TEXTURES.items()):
        c = im.crop(box)
        if name == "wall":
            # 石牆保留磚塊的排列（程式排不出來），左右接縫用鏡像
            size = (max(4, round(c.width / SRC_PIXEL)), max(4, round(c.height / SRC_PIXEL)))
            small = c.resize(size, Image.BOX).quantize(colors=10, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).convert("RGB")
            seamless(small).save(os.path.join(OUT, "tex_%s.png" % name))
            continue
        stretch = (1, 2) if name == "rock" else (1, 1)
        procedural(c, 64, 7 + i * 11, stretch, 9 if name == "dirt" else 7, name == "dirt").save(os.path.join(OUT, "tex_%s.png" % name))
    print("寫到", OUT)


if __name__ == "__main__":
    main(sys.argv[1])
