"""戰術地圖的環境物件（2026-11-08，ChatGPT 出圖，arts/props_2026-11-08/）。

樹、灌木、石頭等：綠色背景去背、縮成和松樹（pine_dark，一格 48 像素時高 140）同樣的尺度，
輸出 assets/<名稱>_32.png、_48.png，給 HD2DBoard 的 trees／tree_mix／border 用（和 pine_dark 同樣用法）。
葉子是黃綠色，prep_grizzly.cut 的「偏綠就去掉」會把葉子一起挖掉 → 這裡只去掉接近純綠背景的顏色。

用法：python3.12 -I prototypes/hd2d_tactical/prep_props.py
"""
import os
import sys
from collections import deque

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import prep_grizzly as pg  # noqa: E402
from PIL import Image  # noqa: E402

SRC = os.path.join(pg.ROOT, "arts", "props_2026-11-08")
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "assets")
# 名稱 → (檔名, 一格 48 像素時的高度)。松樹高 140（約 2.9 格）
PROPS = {
    "birch": ("birch.png", 150),
    # 灌木（約 1.4 寬高比）：tree_mix 裡和樹一起輪替；密林格子的樹縮成 0.45 → 約 0.8 格寬，外圍 1 倍 → 約 1.7 格寬
    "shrub": ("shrub.jpg", 60),
    "shrub_winter": ("shrub_winter.jpg", 60),
    # 秋天的灌木（autumn_swap）、另一種形狀的灌木（增加變化，夏天和原本的輪替）
    "shrub_autumn": ("shrub_autumn.jpg", 60),
    "shrub_b": ("shrub_b.jpg", 60),
    # 大石頭（約 1.45 寬高比）：放在岩坡（r）上，trees.r 的 scale 0.8 → 約 0.9 格寬
    "boulder": ("boulder.jpg", 36),
    "boulder_winter": ("boulder_winter.jpg", 36),
    # 倒木（含樹枝約 2.3 寬高比）：取代程式畫的圓柱（logs），trees.l 1 倍 → 約 1.2 格寬
    "log": ("log.jpg", 25),
    "log_winter": ("log_winter.jpg", 25),
    # 枯樹（樹枝張開，寬高比約 0.7）：比松樹矮一點；冬天也用同一張
    "dead_tree": ("dead_tree.jpg", 120),
    # 夏天的雲杉（取代參考圖裁出來、枝葉邊緣有白點的深色松樹）：高度和松樹一樣
    "spruce": ("spruce.jpg", 140),
    # 秋天的白樺（秋天時 tree_mix 的 birch 換成這張，autumn_swap）
    "birch_autumn": ("birch_autumn.jpg", 115),  # 樹冠比夏天的寬，高度調低一點免得太大
    # 牧場：小木屋（約 3 格寬，地圖上緣外面）、乾草堆（約 1.1 格寬，開闊地點綴）
    "cabin": ("cabin.jpg", 80),
    "haystack": ("haystack.jpg", 28),
    # 小石堆（寬高比約 1.25）：開闊地（.）少量點綴，1 倍約半格寬
    "stones": ("stones.jpg", 20),
    "stones_winter": ("stones_winter.jpg", 20),
    # 蘆葦（寬高比約 0.7）：水邊的平地（near_props），約一格高、0.7 格寬
    "reeds": ("reeds.jpg", 46),
    "reeds_winter": ("reeds_winter.jpg", 46),
    # 草原的高草叢（寬高比約 1.9）：草原、苔原的樹種輪替裡用（fixed_scale 約一格寬）
    "tallgrass": ("tallgrass.jpg", 28),
    "tallgrass_winter": ("tallgrass_winter.jpg", 28),
    # 牧場的木柵欄（寬高比約 1.9）：牧場地圖的外圍（edge_props）一格一段
    # 草原密林格子的高草（潛伏用）：同一張圖放大（高 44、約 1.6 格寬），放在格子前緣，蓋住站在同一格的狼的下半身
    "tallgrass_cover": ("tallgrass.jpg", 44),
    "tallgrass_cover_winter": ("tallgrass_winter.jpg", 44),
    "fence": ("fence.jpg", 26),
    # 洞穴入口（寬高比約 1.9）：地形 b（狩獵的躲藏處）約 1.3 格寬
    "cave": ("cave.jpg", 34),
    "cave_winter": ("cave_winter.jpg", 34),  # 2026-11-12 冬天版（頂上積雪、冰柱）
}
# 顏色調整（飽和度倍率, 亮度倍率）：ChatGPT 的葉子是鮮黃綠色，在深色松樹旁邊太跳 → 稍微降飽和、調暗
TONE = {"birch": (0.8, 0.9), "birch_autumn": (0.85, 0.9)}


def tone(im, sat, bri):
    p = im.load()
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, a = p[x, y]
            if a:
                v = 0.299 * r + 0.587 * g + 0.114 * b
                p[x, y] = tuple(max(0, min(255, int((v + (c - v) * sat) * bri))) for c in (r, g, b)) + (a,)
    return im


def is_bg(r, g, b, bg=(3, 250, 3)):
    # 背景是純綠（白樺那張約 (3, 250, 3)），倒木那張是比較淡的綠（約 (97, 188, 67)）→ 和左上角的顏色很接近就算背景；
    # 和深色外框之間的混色（綠明顯比紅、藍多）也算。青苔是灰綠色（約 (100, 117, 85)），綠只比紅多一點，不受影響
    if sum((a - c) ** 2 for a, c in zip((r, g, b), bg)) < 50 ** 2:
        return True
    if r < 70 and b < 70 and g > 120 and g > r * 2.2 and g > b * 2.2:
        return True
    # 淡綠背景（紅 > 60）的外框混色比較亮，另外判斷；純綠背景不用（白樺深色的葉子綠是紅的 2 倍，會被挖掉）
    return bg[0] > 60 and g > 80 and g > r * 1.6 and g > b * 1.6


def key(path, min_blob=40):
    im = Image.open(path).convert("RGBA")
    w, h = im.size
    p = im.load()
    bg = p[3, 3][:3]
    for y in range(h):
        for x in range(w):
            r, g, b, a = p[x, y]
            if is_bg(r, g, b, bg):
                p[x, y] = (0, 0, 0, 0)
    # 小碎點（去背殘留）去掉；葉叢和樹幹之間可能不相連，所以不是只留最大的一塊
    seen = bytearray(w * h)
    for i in range(w * h):
        if seen[i] or not p[i % w, i // w][3]:
            continue
        comp = []
        q = deque([i])
        seen[i] = 1
        while q:
            j = q.popleft()
            comp.append(j)
            x, y = j % w, j // w
            for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
                if 0 <= nx < w and 0 <= ny < h:
                    k = ny * w + nx
                    if not seen[k] and p[nx, ny][3]:
                        seen[k] = 1
                        q.append(k)
        if len(comp) < min_blob:
            for j in comp:
                p[j % w, j // w] = (0, 0, 0, 0)
    return im.crop(im.getbbox())


# 地面材質（2026-11-08，ChatGPT 從正上方看的草地）：原圖 1024 是 512 的 2×2 重複 → 取左上 512 就能無縫拼接，
# 縮成 128（一格 32 個材質像素 → 4 格重複一次，草叢約 5 像素），顏色照舊材質（_old_tex_grass.png）的平均色調暗，限制顏色數
TEXTURES = {"grass": ("grass_top.jpg", 512, 128, 16), "snow": ("snow_top.jpg", 512, 128, 16), "dirt": ("dirt_top.jpg", 512, 128, 16), "rock": ("rock_top.jpg", 512, 128, 16), "water": ("water_top.jpg", 512, 128, 12), "ice": ("ice_top.jpg", 512, 128, 12),
            # 秋天的乾草（草原、秋天）：沒有舊材質，亮度照新的草地材質 × 1.1（乾草比綠草亮一點）、飽和度 × 0.7（原色太橘）
            "grass_autumn": ("grass_autumn_top.jpg", 512, 128, 16, "tex_grass.png", 1.1, 0.7),
            # 苔原（苔蘚、地衣、矮灌木）、森林密林的地面（針葉、苔蘚），ChatGPT 2026-11-08：704 一個循環 → 176（4 格重複一次）；亮度照草地
            "tundra": ("tundra_top.jpg", 704, 176, 16, "tex_grass.png", 1.05, 0.85),
            "forest_floor": ("forest_floor_top.jpg", 704, 176, 16, "tex_grass.png", 0.85, 0.9)}


# 只有左右重複的材質（1408×768，左右 704 一個循環、上下沒有）：取 704×704，上下接縫用下面多出來的 64 行淡入（seam_blend）
SEAM = {"tundra": 64, "forest_floor": 64}
CONTRAST = {"tundra": 0.65}


def seam_blend(src, w, h, band):
    out = src.crop((0, 0, w, h)).copy()
    a = src.load()
    o = out.load()
    for y in range(band):
        t = y / band
        for x in range(w):
            p, q = a[x, h + y], a[x, y]
            o[x, y] = tuple(int(p[k] * (1 - t) + q[k] * t) for k in range(3))
    return out


def make_texture(name, f, crop, size, colors, lum_ref="", lum_mult=1.0, sat=1.0):
    src = Image.open(os.path.join(SRC, f)).convert("RGB")
    if name in SEAM:
        im = seam_blend(src, crop, crop, SEAM[name]).resize((size, size), Image.BOX)
    else:
        im = src.crop((0, 0, crop, crop)).resize((size, size), Image.BOX)
    old = os.path.join(OUT, "_old_tex_%s.png" % name)
    if lum_ref:
        # 只調亮度（保留原本的顏色）：平均亮度 = 參考材質的 × lum_mult
        lum = lambda c: 0.299 * c[0] + 0.587 * c[1] + 0.114 * c[2]
        ref = lum(Image.open(os.path.join(OUT, lum_ref)).convert("RGB").resize((1, 1), Image.BOX).getpixel((0, 0))) * lum_mult
        k = ref / max(1.0, lum(im.resize((1, 1), Image.BOX).getpixel((0, 0))))
        im = Image.eval(im, lambda v: min(255, int(v * k)))
        if sat != 1.0:
            im = tone(im.convert("RGBA"), sat, 1.0).convert("RGB")
    elif os.path.exists(old):
        target = Image.open(old).convert("RGB").resize((1, 1), Image.BOX).getpixel((0, 0))
        base = im.resize((1, 1), Image.BOX).getpixel((0, 0))
        gain = [t / max(1, b) for t, b in zip(target, base)]
        im = Image.eval(im, lambda v: v)  # copy
        px = im.load()
        for y in range(size):
            for x in range(size):
                px[x, y] = tuple(min(255, int(c * g)) for c, g in zip(px[x, y], gain))
    # 對比降低（苔原的白色地衣太搶眼）：往平均色拉近
    if name in CONTRAST:
        k = CONTRAST[name]
        mean = im.resize((1, 1), Image.BOX).getpixel((0, 0))
        px = im.load()
        for y in range(im.height):
            for x in range(im.width):
                px[x, y] = tuple(int(mean[c] + (px[x, y][c] - mean[c]) * k) for c in range(3))
    im = im.quantize(colors=colors, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).convert("RGB")
    im.save(os.path.join(OUT, "tex_%s.png" % name))
    print("tex_" + name, im.size)


def main():
    for name, args in TEXTURES.items():
        make_texture(name, *args)
    for name, (f, h48) in PROPS.items():
        c = key(os.path.join(SRC, f))
        if name in TONE:
            c = tone(c, *TONE[name])
        for d in (32, 48):
            th = round(h48 * d / 48)
            tw = max(1, round(c.width * th / c.height))
            out = pg.shrink(c, tw)
            out.save(os.path.join(OUT, "%s_%d.png" % (name, d)))
            print(name, d, out.size)


if __name__ == "__main__":
    main()
