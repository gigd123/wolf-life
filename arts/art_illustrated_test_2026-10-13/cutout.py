"""把 Gemini 產的動物圖（白底）去背：從畫面邊緣往內填滿「接近白色」的像素，動物有完整外框線，所以白色的雪兔身體不會被吃掉。
邊緣的半白像素依亮度給半透明，避免白邊。輸出裁到動物範圍、四周留 8 像素。
用法：python3 cutout.py
"""
import os
from collections import deque
from PIL import Image, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
# 角之間這類被線框圍住的白底洞：只對這些動物清掉（雪兔冬毛是白的，不能套用）
FILL_HOLES = {"elk_bull"}
ANIMALS = ["wolf_gray", "wolf_black", "grizzly", "elk_cow", "elk_bull", "hare_summer", "hare_winter"]


def _fill_holes(px, bg, w, h, white, min_size=150):
    """把沒和外框連通、但面積夠大的白色區塊也當成背景。"""
    seen = bytearray(w * h)
    for y0 in range(h):
        for x0 in range(w):
            i0 = y0 * w + x0
            if bg[i0] or seen[i0] or not white(px[x0, y0]):
                continue
            comp, q = [], deque([(x0, y0)])
            seen[i0] = 1
            while q:
                x, y = q.popleft()
                comp.append(y * w + x)
                for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
                    if 0 <= nx < w and 0 <= ny < h:
                        j = ny * w + nx
                        if not seen[j] and not bg[j] and white(px[nx, ny]):
                            seen[j] = 1
                            q.append((nx, ny))
            if len(comp) >= min_size:
                for j in comp:
                    bg[j] = 1


def cut(name):
    im = Image.open(os.path.join(HERE, "source", name + ".jpg")).convert("RGB")
    w, h = im.size
    px = im.load()
    white = lambda p: min(p) > 228 and max(p) - min(p) < 22
    bg = bytearray(w * h)
    q = deque()
    for x in range(w):
        q.extend([(x, 0), (x, h - 1)])
    for y in range(h):
        q.extend([(0, y), (w - 1, y)])
    while q:
        x, y = q.popleft()
        i = y * w + x
        if bg[i] or not white(px[x, y]):
            continue
        bg[i] = 1
        if x > 0: q.append((x - 1, y))
        if x < w - 1: q.append((x + 1, y))
        if y > 0: q.append((x, y - 1))
        if y < h - 1: q.append((x, y + 1))
    if name in FILL_HOLES:
        _fill_holes(px, bg, w, h, white)
    alpha = Image.frombytes("L", (w, h), bytes(0 if b else 255 for b in bg))
    # 邊緣：緊鄰背景的一圈依亮度變半透明（越白越透明）
    edge = alpha.filter(ImageFilter.MinFilter(3))
    a, e = alpha.load(), edge.load()
    for y in range(h):
        for x in range(w):
            if a[x, y] and not e[x, y]:
                lum = sum(px[x, y]) / 3
                a[x, y] = int(max(0, min(255, (250 - lum) * 255 / 120)))
    out = im.convert("RGBA")
    out.putalpha(alpha)
    box = alpha.point(lambda v: 255 if v > 16 else 0).getbbox()
    box = (max(0, box[0] - 8), max(0, box[1] - 8), min(w, box[2] + 8), min(h, box[3] + 8))
    out = out.crop(box)
    out.save(os.path.join(HERE, "cut", name + ".png"))
    return out.size


if __name__ == "__main__":
    for n in ANIMALS:
        print(n, cut(n))
