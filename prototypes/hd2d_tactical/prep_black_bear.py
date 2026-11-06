"""黑熊的 HD-2D 素材處理（2026-11-06）。

來源：Gemini 出的圖（arts/hd2d_2026-11-06/，綠底）：
- black_bear_set3.png：三隻排在一起（左上 站、右上 走路、下 揮掌張嘴）——正式的基準（黃褐色口鼻）
- black_bear_charge.jpg：衝刺（單張）
- black_bear_eat.jpg：低頭吃（單張；嘴前的莓果是分開的小塊，只留最大的一塊時會去掉）
- black_bear_set6.jpg：六隻（風格不同：偏藍、口鼻深色）——只取用後腳站起來那一隻（最高最窄的），顏色調到和 set3 一樣
處理照 prep_grizzly.py：綠色色鍵去背、只留最大的一塊、縮成 32／48。多隻排在一起的圖先找出每一隻的範圍再分開切。
寬幾格：站、走照遊戲的黑熊 1.9 格；同一張圖裡的其他姿勢照同樣的「像素 → 格」比例（揮掌含伸出的前掌比較寬）；
衝刺、低頭吃照身體長度目測；站起來照 set6 裡站的那隻換算。

用法：python3.12 -I prototypes/hd2d_tactical/prep_black_bear.py
"""
import os
import sys
from collections import deque

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import prep_grizzly as pg  # noqa: E402

BASE_CELLS = 1.9


def blobs(path, min_px=4000):
    """綠底圖裡每一隻的範圍（左、上、右、下），由上到下、由左到右排。"""
    im = Image.open(path).convert("RGB")
    w, h = im.size
    px = im.load()
    fg = [False] * (w * h)
    for y in range(h):
        for x in range(w):
            r, g, b = px[x, y]
            fg[y * w + x] = not (g > 110 and g > r * 1.3 and g > b * 1.3)
    seen = [False] * (w * h)
    out = []
    for i in range(w * h):
        if not fg[i] or seen[i]:
            continue
        q = deque([i])
        seen[i] = True
        n, x0, y0, x1, y1 = 0, w, h, 0, 0
        while q:
            j = q.popleft()
            n += 1
            x, y = j % w, j // w
            x0, y0, x1, y1 = min(x0, x), min(y0, y), max(x1, x), max(y1, y)
            for k in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
                if 0 <= k[0] < w and 0 <= k[1] < h:
                    kk = k[1] * w + k[0]
                    if fg[kk] and not seen[kk]:
                        seen[kk] = True
                        q.append(kk)
        if n >= min_px:
            out.append((x0, y0, x1 + 1, y1 + 1))
    out.sort(key=lambda b: (round(b[1] / 150), b[0]))
    return out


def cut_box(path, box, tmp):
    m = 6
    im = Image.open(path).convert("RGB")
    b = (max(0, box[0] - m), max(0, box[1] - m), min(im.width, box[2] + m), min(im.height, box[3] + m))
    # 外圍補綠色，免得旁邊另一隻熊的邊角被切進來
    crop = Image.new("RGB", (b[2] - b[0], b[3] - b[1]), (0, 255, 0))
    crop.paste(im.crop(box), (box[0] - b[0], box[1] - b[1]))
    crop.save(tmp)
    return pg.cut(tmp, "green")


def main():
    tmp = os.path.join(pg.SRC, "_bb.png")
    src3 = os.path.join(pg.SRC, "black_bear_set3.png")
    b3 = blobs(src3)
    assert len(b3) == 3, b3
    cuts, cells = {}, {}
    names3 = ["black_bear_stand", "black_bear_walk", "black_bear_swipe"]
    px_per_cell = (b3[0][2] - b3[0][0]) / BASE_CELLS
    for name, box in zip(names3, b3):
        cuts[name] = cut_box(src3, box, tmp)
        cells[name] = cuts[name].width / px_per_cell
    cuts["black_bear_charge"] = pg.cut(os.path.join(pg.SRC, "black_bear_charge.jpg"), "green")
    cells["black_bear_charge"] = 2.3
    cuts["black_bear_eat"] = pg.cut(os.path.join(pg.SRC, "black_bear_eat.jpg"), "green")
    cells["black_bear_eat"] = 2.0
    src6 = os.path.join(pg.SRC, "black_bear_set6.jpg")
    b6 = blobs(src6)
    rear = max(b6, key=lambda b: (b[3] - b[1]) / (b[2] - b[0]))
    stand6 = min(b6, key=lambda b: (b[1], b[0]))
    cuts["black_bear_rear"] = cut_box(src6, rear, tmp)
    cells["black_bear_rear"] = BASE_CELLS * (rear[2] - rear[0]) / (stand6[2] - stand6[0])
    if os.path.exists(tmp):
        os.remove(tmp)
    # 顏色：其他幾張的平均色調到和 set3 的站一樣
    target = pg.mean_rgb(cuts["black_bear_stand"])
    for name in ("black_bear_charge", "black_bear_eat", "black_bear_rear"):
        gain = [t / max(1.0, b) for t, b in zip(target, pg.mean_rgb(cuts[name]))]
        pg.apply_gain(cuts[name], gain)
        print(name, "倍率", [round(g, 3) for g in gain])
    for name, c in cuts.items():
        c.save(os.path.join(pg.SRC, name + "_src.png"))
        for d in pg.DENSITIES:
            out = pg.shrink(c, round(cells[name] * d))
            out.save(os.path.join(pg.OUT, "%s_%d.png" % (name, d)))
            print(name, d, out.size, "寬 %.2f 格" % cells[name])


if __name__ == "__main__":
    main()
