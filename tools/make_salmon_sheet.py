#!/usr/bin/env python3
"""鮭魚的主遊戲 spritesheet 佔位圖（Phase 2h 第 6 步）：遭遇畫面的鮭魚洄流線索用。
192×64，每格 48×32；第 0 列 idle（在水裡擺尾）、第 1 列 move（跳出水面）。之後換正式素材時檔名與尺寸不變。

輸出：assets/art/sprites/animals/salmon_sheet.png、arts/tactical_placeholder/salmon_sheet_4x.png
用法：python3 tools/make_salmon_sheet.py
"""
import math
import os

from PIL import Image, ImageDraw

W, H = 48, 32
SS = 8
BODY = "#b8463a"      # 洄游期的紅色身體
BACK = "#4a5a3a"      # 綠褐色的背
BELLY = "#e8c8b0"
OUT = "#2a1410"


def fish(draw, cx, cy, ang, bend):
    pts = []
    # 身體：沿著一條微彎的中線畫上下兩側
    n = 14
    upper, lower = [], []
    for i in range(n + 1):
        t = i / n
        x = -14 + 28 * t
        w = 5.5 * math.sin(math.pi * min(1.0, t * 1.15)) + 0.6
        y = bend * math.sin(t * math.pi) * (1 - t)
        upper.append((x, y - w))
        lower.append((x, y + w * 0.8))
    body = upper + lower[::-1]
    tail = [(-14, bend * 0.0), (-20, -5), (-19, 0), (-20, 5)]

    def tr(p):
        x, y = p
        c, s = math.cos(ang), math.sin(ang)
        return ((cx + x * c - y * s) * SS, (cy + x * s + y * c) * SS)
    draw.polygon([tr(p) for p in tail], fill=BODY, outline=OUT)
    draw.polygon([tr(p) for p in body], fill=BODY, outline=OUT)
    draw.polygon([tr(p) for p in upper[2:12] + [(x, y + 2.0) for x, y in upper[11:1:-1]]], fill=BACK)
    draw.polygon([tr(p) for p in lower[3:11] + [(x, y - 1.5) for x, y in lower[10:2:-1]]], fill=BELLY)
    ex, ey = tr((10.5, -1.5))
    draw.ellipse([ex - SS * 0.9, ey - SS * 0.9, ex + SS * 0.9, ey + SS * 0.9], fill="#101010")


def frame(ang, bend, cy=16, splash=False):
    big = Image.new("RGBA", (W * SS, H * SS), (0, 0, 0, 0))
    d = ImageDraw.Draw(big)
    if splash:
        for i, (x, y) in enumerate([(14, 27), (20, 29), (28, 28), (34, 27)]):
            d.ellipse([(x - 1.5) * SS, (y - 1) * SS, (x + 1.5) * SS, (y + 1) * SS], fill="#a8d0e0")
    fish(d, 24, cy, ang, bend)
    return big.resize((W, H), Image.NEAREST)


def main():
    sheet = Image.new("RGBA", (W * 4, H * 2), (0, 0, 0, 0))
    for i, b in enumerate([2.0, 0.5, -2.0, -0.5]):
        sheet.paste(frame(0.0, b, 18), (i * W, 0))
    for i, (a, cy) in enumerate([(-0.5, 20), (-0.25, 14), (0.15, 12), (0.5, 18)]):
        sheet.paste(frame(a, 1.0, cy, splash=(i in (0, 3))), (i * W, H))
    out = "assets/art/sprites/animals/salmon_sheet.png"
    sheet.save(out)
    os.makedirs("arts/tactical_placeholder", exist_ok=True)
    sheet.resize((sheet.width * 4, sheet.height * 4), Image.NEAREST).save("arts/tactical_placeholder/salmon_sheet_4x.png")
    print("完成", out)


if __name__ == "__main__":
    main()
