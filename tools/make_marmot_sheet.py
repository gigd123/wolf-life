#!/usr/bin/env python3
"""旱獺的主遊戲 spritesheet 佔位圖（Phase 2g）：把河狸的 spritesheet 換色（灰褐的毛、淡黃的腹、蓬鬆的褐色尾巴），
之後換正式素材時檔名與尺寸不變（192×64，每格 48×32，第 0 列 idle、第 1 列 move，同河狸）。

輸出：assets/art/sprites/animals/marmot_sheet.png、marmot_young_sheet.png
用法：python3 tools/make_marmot_sheet.py
"""
from PIL import Image

SRC = "assets/art/sprites/animals/"
COLORS = {
    (112, 74, 46): (128, 104, 78),   # 身體 → 灰褐
    (150, 104, 66): (184, 150, 98),  # 亮部 → 淡黃（黃腹）
    (78, 50, 30): (92, 72, 54),      # 暗部
    (56, 44, 40): (104, 80, 56),     # 河狸的扁尾 → 褐色的尾巴
    (90, 72, 64): (138, 110, 82),
    (230, 140, 40): (232, 218, 188), # 河狸的橘色門牙 → 淡色的鼻口
}


def recolor(src, dst):
    im = Image.open(SRC + src).convert("RGBA")
    px = im.load()
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, a = px[x, y]
            if a and (r, g, b) in COLORS:
                px[x, y] = COLORS[(r, g, b)] + (a,)
    im.save(SRC + dst)


recolor("beaver_sheet.png", "marmot_sheet.png")
recolor("beaver_young_sheet.png", "marmot_young_sheet.png")
print("完成")
