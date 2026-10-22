#!/usr/bin/env python3
"""戰術地圖的佔位圖（Phase 2c，2026-10-20 使用者選 B＋1）：程式畫的俯視小圖，之後換正式素材時檔名與尺寸不變。

輸出（每格 14×14，和戰術地圖的格子一樣大）：
- assets/art/tactical/{wolf,deer,fawn,elk,elk_bull,mule_deer,caribou,moose,moose_calf,bison,bison_calf,beaver,beaver_kit,pronghorn,pronghorn_kid,bighorn_sheep,bighorn_ram,bighorn_sheep_calf}.png：8 個方向的橫條（112×14），順序同 TacticalHunt.DIRS：
  右、右下、下、左下、左、左上、上、右上。
- assets/art/tactical/tile_{open_0..2,forest_0..1,logs_0,rock_0..1,water_0..1,shallow_0..1,deep_0..1,cliff_0..1}.png：地塊（14×14；rock 岩坡、water 河，Phase 2d；shallow 淺水、deep 深水，河狸；cliff 峭壁，大角羊）。
- arts/tactical_placeholder/：同樣的圖放大 4 倍（只給人看，程式不讀）。

用法：python3 tools/make_tactical_art.py
"""
import math
import os
import random

from PIL import Image, ImageColor, ImageDraw

CELL = 14
SS = 8  # 先畫成 8 倍大再縮小（Nearest），得到乾淨的像素邊緣
OUT = "assets/art/tactical"
OUT_4X = "arts/tactical_placeholder"
DIRS = [(1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0), (-1, -1), (0, -1), (1, -1)]

# 動物的形狀：面向右（+x），座標以 14 格為單位、中心 (7, 7)。每個部件 (種類, 顏色, 參數)
#   ellipse: (cx, cy, rx, ry)；poly: [(x, y), ...]
WOLF = [
    ("ellipse", "#7c7c7c", (1.9, 7, 1.9, 0.75)),          # 尾巴
    ("ellipse", "#a3a3a3", (6.0, 7, 4.0, 2.7)),           # 身體
    ("ellipse", "#727272", (5.8, 7, 3.2, 1.0)),           # 背上的深色
    ("ellipse", "#b4b4b4", (10.3, 7, 2.1, 2.0)),          # 頭
    ("ellipse", "#c8c8c8", (12.4, 7, 1.0, 0.75)),         # 口鼻
    ("poly", "#6a6a6a", [(9.6, 5.6), (10.6, 4.6), (10.9, 5.8)]),  # 耳朵
    ("poly", "#6a6a6a", [(9.6, 8.4), (10.6, 9.4), (10.9, 8.2)]),
]
DEER = [
    ("ellipse", "#9b6534", (6.6, 7, 4.3, 2.1)),           # 身體
    ("ellipse", "#f2ead8", (2.5, 7, 1.0, 1.1)),           # 白色的臀部
    ("ellipse", "#8a5a2e", (10.6, 7, 1.3, 0.9)),          # 脖子
    ("ellipse", "#a8723f", (12.0, 7, 1.3, 1.0)),          # 頭
    ("poly", "#6e4524", [(11.3, 5.9), (11.0, 4.6), (12.0, 5.7)]),  # 耳朵
    ("poly", "#6e4524", [(11.3, 8.1), (11.0, 9.4), (12.0, 8.3)]),
]
FAWN = [
    ("ellipse", "#c08a4e", (6.8, 7, 3.2, 1.6)),
    ("ellipse", "#f2ead8", (3.8, 7, 0.7, 0.8)),
    ("ellipse", "#c99559", (10.0, 7, 1.1, 0.9)),
    ("ellipse", "#f6f0e2", (6.0, 6.3, 0.45, 0.45)),       # 白點
    ("ellipse", "#f6f0e2", (7.6, 7.6, 0.45, 0.45)),
    ("ellipse", "#f6f0e2", (5.2, 7.7, 0.45, 0.45)),
    ("poly", "#8a5a2e", [(9.6, 6.2), (9.3, 5.0), (10.2, 6.0)]),
    ("poly", "#8a5a2e", [(9.6, 7.8), (9.3, 9.0), (10.2, 8.0)]),
]
MULE_DEER = [  # 騾鹿（Phase 2d 第 3 步）：灰褐色、大耳朵、白臀加黑尾尖
    ("ellipse", "#8a7a68", (6.6, 7, 4.3, 2.1)),           # 灰褐的身體
    ("ellipse", "#f2ead8", (2.5, 7, 1.1, 1.2)),           # 白色的臀部
    ("ellipse", "#1e1a16", (1.5, 7, 0.5, 0.45)),          # 黑尾尖
    ("ellipse", "#7a6a58", (10.6, 7, 1.3, 0.9)),          # 脖子
    ("ellipse", "#958571", (12.0, 7, 1.3, 1.0)),          # 頭
    ("poly", "#5c4e40", [(11.2, 5.9), (10.4, 3.6), (12.2, 5.5)]),  # 大耳朵
    ("poly", "#5c4e40", [(11.2, 8.1), (10.4, 10.4), (12.2, 8.5)]),
]
CARIBOU = [  # 馴鹿（Phase 2d 第 4 步）：褐色身體、淺色脖子與臀部、往前彎的角
    ("ellipse", "#7a5a3c", (6.4, 7, 4.3, 2.2)),           # 身體
    ("ellipse", "#e8e0cc", (2.3, 7, 1.0, 1.2)),           # 淺色臀部
    ("ellipse", "#ddd3bc", (10.4, 7, 1.5, 1.2)),          # 淺色脖子
    ("ellipse", "#8e7050", (12.1, 7, 1.2, 0.95)),         # 頭
    ("poly", "#cbb894", [(11.4, 6.2), (10.6, 3.6), (12.6, 4.4), (11.8, 5.0), (12.2, 6.0)]),   # 角
    ("poly", "#cbb894", [(11.4, 7.8), (10.6, 10.4), (12.6, 9.6), (11.8, 9.0), (12.2, 8.0)]),
]
ELK = [
    ("ellipse", "#c39a62", (6.2, 7, 4.8, 2.5)),           # 淺色的身體
    ("ellipse", "#ede0bc", (1.7, 7, 1.0, 1.3)),           # 淺色的臀部
    ("ellipse", "#5a3a22", (10.6, 7, 1.8, 1.4)),          # 深色的脖子（鬃毛）
    ("ellipse", "#6b4a2c", (12.3, 7, 1.3, 1.0)),          # 頭
]


ELK_BULL = ELK + [  # 公馬鹿（Phase 2f）：馬鹿加一對往後彎的大角
    ("poly", "#e2d2a8", [(11.6, 6.0), (9.4, 2.6), (8.0, 2.2), (9.8, 3.4), (11.0, 5.6)]),
    ("poly", "#e2d2a8", [(11.6, 8.0), (9.4, 11.4), (8.0, 11.8), (9.8, 10.6), (11.0, 8.4)]),
]

MOOSE = [  # 駝鹿（Phase 2f 第 2 步）：深褐的大身體、隆起的肩、長臉、往兩側張開的掌狀角
    ("ellipse", "#3e2a1c", (6.0, 7, 5.0, 2.8)),           # 身體
    ("ellipse", "#2e1e14", (8.2, 7, 1.8, 2.2)),           # 隆起的肩
    ("ellipse", "#4a3424", (10.6, 7, 1.4, 1.2)),          # 脖子
    ("ellipse", "#5a4030", (12.4, 7, 1.6, 0.9)),          # 長臉
    ("poly", "#b8a27a", [(11.2, 6.0), (10.2, 3.0), (12.4, 2.8), (12.0, 4.4), (11.8, 5.8)]),   # 掌狀角
    ("poly", "#b8a27a", [(11.2, 8.0), (10.2, 11.0), (12.4, 11.2), (12.0, 9.6), (11.8, 8.2)]),
]
MOOSE_CALF = [  # 小駝鹿：紅褐色、沒有斑點、長腿（俯視看不到）、長臉
    ("ellipse", "#8a4a26", (6.6, 7, 3.4, 1.8)),
    ("ellipse", "#7a4020", (9.8, 7, 1.0, 0.9)),
    ("ellipse", "#9a5832", (11.2, 7, 1.2, 0.75)),
    ("poly", "#5a2e16", [(10.2, 6.2), (9.8, 4.9), (10.8, 6.0)]),
    ("poly", "#5a2e16", [(10.2, 7.8), (9.8, 9.1), (10.8, 8.0)]),
]

BISON = [  # 野牛（Phase 2f 第 3 步）：深褐、後半身短毛淺一點、前半身大駝峰與蓬毛、低垂的大頭、短彎角
    ("ellipse", "#5a3e26", (5.2, 7, 4.2, 2.6)),           # 後半身
    ("ellipse", "#2e1e12", (8.4, 7, 2.6, 3.2)),           # 駝峰與前半身的蓬毛
    ("ellipse", "#24180e", (11.4, 7, 1.6, 1.8)),          # 大頭
    ("poly", "#d8d0bc", [(11.6, 5.4), (11.0, 4.0), (12.4, 4.6)]),  # 短彎角
    ("poly", "#d8d0bc", [(11.6, 8.6), (11.0, 10.0), (12.4, 9.4)]),
]
BISON_CALF = [  # 小野牛：橘褐色（俗稱 red dog）、還沒有駝峰
    ("ellipse", "#c0743a", (6.6, 7, 3.4, 1.9)),
    ("ellipse", "#b0662e", (9.6, 7, 1.2, 1.3)),
    ("ellipse", "#c88048", (11.0, 7, 1.1, 0.9)),
]

BEAVER = [  # 河狸（2026-10-22）：圓滾的褐色身體、扁平的黑色大尾巴
    ("ellipse", "#2e2620", (3.6, 7, 1.8, 1.4)),           # 扁平的尾巴
    ("ellipse", "#7a4e2c", (7.4, 7, 3.0, 2.3)),           # 身體
    ("ellipse", "#6a4224", (10.6, 7, 1.4, 1.3)),          # 頭
    ("ellipse", "#3a2a1c", (11.8, 7, 0.5, 0.5)),          # 鼻子
]
BEAVER_KIT = [  # 小河狸：小一號
    ("ellipse", "#2e2620", (4.6, 7, 1.2, 1.0)),
    ("ellipse", "#8a5a34", (7.6, 7, 2.2, 1.7)),
    ("ellipse", "#7a4e2c", (10.0, 7, 1.1, 1.0)),
]

PRONGHORN = [  # 叉角羚（2026-10-22）：黃褐的背、白色的腹側與臀部、黑色的短角
    ("ellipse", "#f2ead8", (6.4, 7, 4.0, 2.0)),           # 白色的腹側（從上面看是外圍）
    ("ellipse", "#c08a4a", (6.6, 7, 3.6, 1.3)),           # 黃褐的背
    ("ellipse", "#f6f0e2", (2.6, 7, 1.0, 1.2)),           # 白色的臀部
    ("ellipse", "#b07a3e", (10.4, 7, 1.0, 0.8)),          # 脖子
    ("ellipse", "#c89254", (11.8, 7, 1.2, 0.85)),         # 頭
    ("poly", "#1e1a16", [(11.6, 6.2), (11.2, 4.8), (12.0, 5.9)]),  # 黑色的角
    ("poly", "#1e1a16", [(11.6, 7.8), (11.2, 9.2), (12.0, 8.1)]),
]
PRONGHORN_KID = [  # 小叉角羚：淡灰褐、縮成一團
    ("ellipse", "#c8b08a", (7.0, 7, 2.8, 1.6)),
    ("ellipse", "#b8a07a", (9.6, 7, 1.0, 0.8)),
    ("poly", "#8a7458", [(9.4, 6.2), (9.1, 5.1), (9.9, 6.0)]),
    ("poly", "#8a7458", [(9.4, 7.8), (9.1, 8.9), (9.9, 8.0)]),
]

BIGHORN_EWE = [  # 母大角羊（2026-10-22）：灰褐的身體、白色的臀部、短而細的角
    ("ellipse", "#8a7462", (6.4, 7, 4.0, 2.2)),
    ("ellipse", "#f0e8d8", (2.6, 7, 1.1, 1.3)),
    ("ellipse", "#7c6654", (10.4, 7, 1.2, 1.0)),
    ("ellipse", "#958070", (11.8, 7, 1.2, 0.95)),
    ("poly", "#cfc2a6", [(11.4, 6.1), (10.6, 5.0), (11.8, 5.8)]),
    ("poly", "#cfc2a6", [(11.4, 7.9), (10.6, 9.0), (11.8, 8.2)]),
]
BIGHORN_RAM = BIGHORN_EWE[:4] + [  # 公大角羊：兩側往後捲的大角
    ("poly", "#d8cba8", [(11.8, 6.0), (10.4, 3.6), (8.8, 3.8), (9.0, 5.2), (10.4, 5.0), (11.2, 6.2)]),
    ("poly", "#d8cba8", [(11.8, 8.0), (10.4, 10.4), (8.8, 10.2), (9.0, 8.8), (10.4, 9.0), (11.2, 7.8)]),
]
BIGHORN_LAMB = [  # 小羊：淡灰褐、白臀
    ("ellipse", "#a8947e", (6.8, 7, 3.0, 1.6)),
    ("ellipse", "#f0e8d8", (4.0, 7, 0.8, 0.9)),
    ("ellipse", "#b09c86", (9.8, 7, 1.0, 0.85)),
]


def _rot(x, y, ang):
    dx, dy = x - 7.0, y - 7.0
    c, s = math.cos(ang), math.sin(ang)
    return 7.0 + dx * c - dy * s, 7.0 + dx * s + dy * c


def _draw_shape(draw, parts, ang, ox):
    for kind, color, p in parts:
        if kind == "ellipse":
            cx, cy, rx, ry = p
            pts = []
            for i in range(24):
                t = 2 * math.pi * i / 24
                pts.append(_rot(cx + rx * math.cos(t), cy + ry * math.sin(t), ang))
        else:
            pts = [_rot(x, y, ang) for x, y in p]
        draw.polygon([((x + ox) * SS, y * SS) for x, y in pts], fill=color)


def make_sprite(name, parts, outline):
    big = Image.new("RGBA", (CELL * 8 * SS, CELL * SS), (0, 0, 0, 0))
    draw = ImageDraw.Draw(big)
    for i, (dx, dy) in enumerate(DIRS):
        _draw_shape(draw, parts, math.atan2(dy, dx), i * CELL)
    img = big.resize((CELL * 8, CELL), Image.NEAREST)
    _save(name, _outline(img, outline))


# 1 像素的深色外框（不跨到相鄰的方向格）：和草地、密林分得開
def _outline(img, color):
    out = img.copy()
    rgb = ImageColor.getrgb(color) + (255,)
    w, h = img.size
    for y in range(h):
        for x in range(w):
            if img.getpixel((x, y))[3] > 0:
                continue
            for dx, dy in [(1, 0), (-1, 0), (0, 1), (0, -1)]:
                nx, ny = x + dx, y + dy
                if 0 <= nx < w and 0 <= ny < h and nx // CELL == x // CELL and img.getpixel((nx, ny))[3] > 0:
                    out.putpixel((x, y), rgb)
                    break
    return out


def _px(img, x, y, color):
    if 0 <= x < CELL and 0 <= y < CELL:
        img.putpixel((x, y), ImageColor.getrgb(color) + (255,))


def tile_open(seed):
    rnd = random.Random(seed)
    img = Image.new("RGBA", (CELL, CELL), "#5f7a3a")
    for _ in range(22):
        _px(img, rnd.randrange(CELL), rnd.randrange(CELL), rnd.choice(["#56702f", "#6a8744", "#526b2c"]))
    for _ in range(3):  # 小草叢
        x, y = rnd.randrange(1, CELL - 1), rnd.randrange(2, CELL - 1)
        for dx, dy in [(0, 0), (-1, -1), (1, -1), (0, -2)]:
            _px(img, x + dx, y + dy, "#7a9a4c")
    return img


def tile_forest(seed):
    rnd = random.Random(seed)
    img = Image.new("RGBA", (CELL, CELL), "#253e23")
    d = ImageDraw.Draw(img)
    for _ in range(3):  # 樹冠
        cx, cy, r = rnd.randrange(2, CELL - 2), rnd.randrange(2, CELL - 2), rnd.randrange(3, 5)
        d.ellipse([cx - r, cy - r, cx + r, cy + r], fill="#2f5230")
        d.ellipse([cx - r + 1, cy - r + 1, cx, cy], fill="#3a6338")
    for _ in range(8):
        _px(img, rnd.randrange(CELL), rnd.randrange(CELL), "#1c301b")
    return img


def tile_logs(seed):
    img = tile_open(seed + 100)
    d = ImageDraw.Draw(img)
    d.line([(1, 9), (12, 4)], fill="#6b4f33", width=3)  # 倒下的樹幹
    d.line([(1, 9), (12, 4)], fill="#86643f", width=1)
    d.point([(1, 9), (12, 4)], fill="#d8c08a")             # 斷面
    d.line([(4, 12), (9, 11)], fill="#5a4129", width=2)
    return img


def tile_rock(seed):
    """岩坡（Phase 2d 第 3 步）：灰色的碎石與岩塊"""
    rnd = random.Random(seed + 300)
    img = Image.new("RGBA", (CELL, CELL), "#7d7a72")
    d = ImageDraw.Draw(img)
    for _ in range(4):
        x, y, r = rnd.randrange(1, CELL - 1), rnd.randrange(1, CELL - 1), rnd.randrange(2, 4)
        d.ellipse([x - r, y - r + 1, x + r, y + r - 1], fill=rnd.choice(["#9a968c", "#8c887e", "#a8a49a"]))
        d.line([(x - r + 1, y + r - 1), (x + r - 1, y + r - 1)], fill="#5e5b54")
    for _ in range(10):
        _px(img, rnd.randrange(CELL), rnd.randrange(CELL), rnd.choice(["#66635c", "#b2aea4"]))
    return img


def tile_water(seed):
    """河（Phase 2d 第 4 步）：藍灰的水面加幾道波紋"""
    rnd = random.Random(seed + 500)
    img = Image.new("RGBA", (CELL, CELL), "#3f6478")
    d = ImageDraw.Draw(img)
    for _ in range(3):
        x, y = rnd.randrange(0, CELL - 4), rnd.randrange(1, CELL - 1)
        d.line([(x, y), (x + 3, y)], fill="#6f95a8")
    for _ in range(8):
        _px(img, rnd.randrange(CELL), rnd.randrange(CELL), rnd.choice(["#36586b", "#4a7186"]))
    return img


def tile_shallow(seed):
    """淺水（河狸的水塘，2026-10-22）：淺藍綠、看得到底下的泥色"""
    rnd = random.Random(seed + 600)
    img = Image.new("RGBA", (CELL, CELL), "#5f8f8a")
    d = ImageDraw.Draw(img)
    for _ in range(2):
        x, y = rnd.randrange(0, CELL - 4), rnd.randrange(1, CELL - 1)
        d.line([(x, y), (x + 3, y)], fill="#8fbcb4")
    for _ in range(8):
        _px(img, rnd.randrange(CELL), rnd.randrange(CELL), rnd.choice(["#6f8f6a", "#557f7a"]))
    return img


def tile_deep(seed):
    """深水：深藍、少少的波紋"""
    rnd = random.Random(seed + 700)
    img = Image.new("RGBA", (CELL, CELL), "#1f3f5c")
    d = ImageDraw.Draw(img)
    for _ in range(2):
        x, y = rnd.randrange(0, CELL - 4), rnd.randrange(1, CELL - 1)
        d.line([(x, y), (x + 3, y)], fill="#3d6488")
    for _ in range(6):
        _px(img, rnd.randrange(CELL), rnd.randrange(CELL), rnd.choice(["#1a3550", "#26496a"]))
    return img


def tile_cliff(seed):
    """峭壁（大角羊的峽谷，2026-10-22）：深灰的岩壁、幾道裂縫與陰影"""
    rnd = random.Random(seed + 800)
    img = Image.new("RGBA", (CELL, CELL), "#55524c")
    d = ImageDraw.Draw(img)
    for _ in range(2):
        x = rnd.randrange(2, CELL - 2)
        d.line([(x, 0), (x + rnd.choice([-2, -1, 1, 2]), CELL - 1)], fill="#2f2d29")
    for _ in range(10):
        _px(img, rnd.randrange(CELL), rnd.randrange(CELL), rnd.choice(["#6a665e", "#45423d"]))
    return img


def _save(name, img):
    os.makedirs(OUT, exist_ok=True)
    os.makedirs(OUT_4X, exist_ok=True)
    img.save(os.path.join(OUT, name + ".png"))
    img.resize((img.width * 4, img.height * 4), Image.NEAREST).save(os.path.join(OUT_4X, name + "_4x.png"))


def main():
    make_sprite("wolf", WOLF, "#262626")
    make_sprite("deer", DEER, "#2e1a0c")
    make_sprite("fawn", FAWN, "#2e1a0c")
    make_sprite("elk", ELK, "#2e1a0c")
    make_sprite("mule_deer", MULE_DEER, "#2a221a")
    make_sprite("caribou", CARIBOU, "#2a1c10")
    make_sprite("elk_bull", ELK_BULL, "#2e1a0c")
    make_sprite("moose", MOOSE, "#140c06")
    make_sprite("moose_calf", MOOSE_CALF, "#2e1a0c")
    make_sprite("bison", BISON, "#100a04")
    make_sprite("bison_calf", BISON_CALF, "#3a1e0a")
    make_sprite("beaver", BEAVER, "#1a120c")
    make_sprite("beaver_kit", BEAVER_KIT, "#1a120c")
    make_sprite("pronghorn", PRONGHORN, "#2e1a0c")
    make_sprite("pronghorn_kid", PRONGHORN_KID, "#3a2a18")
    make_sprite("bighorn_sheep", BIGHORN_EWE, "#2a2018")
    make_sprite("bighorn_ram", BIGHORN_RAM, "#2a2018")
    make_sprite("bighorn_sheep_calf", BIGHORN_LAMB, "#3a2e22")
    for i in range(3):
        _save("tile_open_%d" % i, tile_open(i))
    for i in range(2):
        _save("tile_forest_%d" % i, tile_forest(i))
    _save("tile_logs_0", tile_logs(0))
    for i in range(2):
        _save("tile_rock_%d" % i, tile_rock(i))
    for i in range(2):
        _save("tile_water_%d" % i, tile_water(i))
    for i in range(2):
        _save("tile_shallow_%d" % i, tile_shallow(i))
        _save("tile_deep_%d" % i, tile_deep(i))
        _save("tile_cliff_%d" % i, tile_cliff(i))
    print("完成：", sorted(os.listdir(OUT)))


if __name__ == "__main__":
    main()
