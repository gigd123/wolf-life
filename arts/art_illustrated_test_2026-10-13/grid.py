"""在去背圖上畫座標格，方便定骨頭與遮罩（輸出到 scratchpad）。用法：python3 grid.py <cut 圖> <輸出> [x0 y0 x1 y1]"""
import sys
from PIL import Image, ImageDraw
src, out = sys.argv[1], sys.argv[2]
im = Image.open(src).convert("RGBA")
bg = Image.new("RGBA", im.size, (255, 255, 255, 255))
bg.alpha_composite(im)
if len(sys.argv) > 6:
    x0, y0, x1, y1 = map(int, sys.argv[3:7])
    bg = bg.crop((x0, y0, x1, y1))
else:
    x0 = y0 = 0
d = ImageDraw.Draw(bg)
for x in range(0, bg.width, 25):
    gx = x0 + x
    d.line([(x, 0), (x, bg.height)], fill=(255, 0, 0, 200) if gx % 100 == 0 else (255, 0, 0, 55))
    if gx % 100 == 0:
        d.text((x + 2, 2), str(gx), fill=(255, 0, 0, 255))
for y in range(0, bg.height, 25):
    gy = y0 + y
    d.line([(0, y), (bg.width, y)], fill=(0, 0, 255, 200) if gy % 100 == 0 else (0, 0, 255, 55))
    if gy % 100 == 0:
        d.text((2, y + 2), str(gy), fill=(0, 0, 255, 255))
bg.convert("RGB").save(out)
