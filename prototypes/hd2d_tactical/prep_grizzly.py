"""灰熊的 HD-2D 素材處理（2026-11-06）。

來源：Gemini 出的圖（arts/hd2d_2026-11-06/）。第二輪的綠底 4 張是同一隻熊，當正式的基準：
r2_stand（站）、r2_walk_a（走路，前腳抬起）、r2_walk_b（走路，另一步）、r2_swipe（揮掌、張嘴吼）；
低頭吃還沒有綠底版，先用第一輪的 r1_eat（棋盤格背景），把顏色調成和第二輪一樣。

處理（使用者 2026-11-06：Gemini 改不好的地方能改就直接改）：
1. 去背：綠底用色鍵＋去掉綠色溢色；棋盤格用從邊緣灌水的方式；只留最大的一塊（去掉雜點、揮動線）。
2. 鼻子：第二輪是粉紅鼻子，把鼻頭那一區的粉紅像素換成深黑褐色（嘴裡的紅色不動）。
3. 顏色：整批乘上同一組 RGB 倍率，讓平均毛色接近第一輪的第 4 張（深一點、偏暖棕）；r1_eat 另外調到和第二輪一樣。
4. 縮成 32 與 48 兩套（一格 32／48 像素；熊寬約 2.3 格，揮掌含伸出的前掌約 2.45 格、低頭吃約 2.0 格），四周留 1 像素空白。

用法：python3.12 -I prototypes/hd2d_tactical/prep_grizzly.py
"""
import os
from collections import deque

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SRC = os.path.join(ROOT, "arts", "hd2d_2026-11-06")
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "assets")

# 名稱 → (來源檔, 背景種類, 寬幾格)；寬幾格是照「熊的身體和走路那張一樣大」目測換算（揮掌含伸出的前掌、低頭吃的身體比較短）
FRAMES = {
    "grizzly_stand": ("r2_stand.jpg", "green", 2.3),
    "grizzly_walk": ("r2_walk_a.jpg", "green", 2.3),
    "grizzly_walk_b": ("r2_walk_b.jpg", "green", 2.3),
    "grizzly_swipe": ("r2_swipe.webp", "green", 2.45),
    "grizzly_eat": ("r1_eat.jpg", "checker", 2.0),
}
DENSITIES = (32, 48)


def largest_blob(alpha, w, h):
    lab = [0] * (w * h)
    best, best_n, cur = 0, 0, 0
    for i in range(w * h):
        if not alpha[i] or lab[i]:
            continue
        cur += 1
        n = 0
        q = deque([i])
        lab[i] = cur
        while q:
            j = q.popleft()
            n += 1
            x, y = j % w, j // w
            for k in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
                if 0 <= k[0] < w and 0 <= k[1] < h:
                    kk = k[1] * w + k[0]
                    if alpha[kk] and not lab[kk]:
                        lab[kk] = cur
                        q.append(kk)
        if n > best_n:
            best, best_n = cur, n
    return [lab[i] == best for i in range(w * h)]


def cut(path, kind):
    im = Image.open(path).convert("RGB")
    w, h = im.size
    px = im.load()
    alpha = [True] * (w * h)
    if kind == "green":
        for y in range(h):
            for x in range(w):
                r, g, b = px[x, y]
                if g > 110 and g > r * 1.3 and g > b * 1.3:
                    alpha[y * w + x] = False
    else:
        bg = [False] * (w * h)

        def isbg(c):
            r, g, b = c
            return max(r, g, b) - min(r, g, b) < 22 and min(r, g, b) > 150

        q = deque([(x, 0) for x in range(w)] + [(x, h - 1) for x in range(w)] + [(0, y) for y in range(h)] + [(w - 1, y) for y in range(h)])
        while q:
            x, y = q.popleft()
            if x < 0 or y < 0 or x >= w or y >= h or bg[y * w + x] or not isbg(px[x, y]):
                continue
            bg[y * w + x] = True
            q.extend([(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)])
        alpha = [not v for v in bg]
    keep = largest_blob(alpha, w, h)
    out = Image.new("RGBA", (w, h))
    o = out.load()
    for y in range(h):
        for x in range(w):
            if keep[y * w + x]:
                r, g, b = px[x, y]
                if kind == "green" and g > max(r, b):
                    g = max(r, b)  # 綠色溢色
                o[x, y] = (r, g, b, 255)
    return out.crop(out.getbbox())


# 鼻頭在圖裡的範圍（左、上、右、下，比例）：揮掌那張前掌伸到更右邊，鼻子在中間偏右
NOSE_BOX = {"grizzly_swipe": (0.70, 0.0, 0.92, 0.45)}


def fix_nose(im, box=(0.84, 0.0, 1.0, 0.65)):
    """鼻頭範圍裡的粉紅像素換成深黑褐色；嘴裡比較暗的紅色不動。"""
    w, h = im.size
    p = im.load()
    for y in range(int(h * box[1]), int(h * box[3])):
        for x in range(int(w * box[0]), int(w * box[2])):
            r, g, b, a = p[x, y]
            if a == 0:
                continue
            pink = r > 150 and g > 105 and r - g > 25 and b > g - 30 and b > 85
            if pink:
                v = (r + g + b) / 3.0
                k = 0.22 + 0.12 * (v - 150) / 105.0
                p[x, y] = (int(70 * k + 20), int(52 * k + 14), int(46 * k + 12), a)
    return im


def mean_rgb(im):
    s = [0.0, 0.0, 0.0]
    n = 0
    for r, g, b, a in im.getdata():
        if a:
            s[0] += r
            s[1] += g
            s[2] += b
            n += 1
    return [v / max(1, n) for v in s]


def apply_gain(im, gain):
    p = im.load()
    w, h = im.size
    for y in range(h):
        for x in range(w):
            r, g, b, a = p[x, y]
            if a:
                p[x, y] = (min(255, int(r * gain[0])), min(255, int(g * gain[1])), min(255, int(b * gain[2])), a)
    return im


def shrink(im, tw):
    th = round(im.height * tw / im.width)
    sm = im.resize((tw, th), Image.BOX)
    p = sm.load()
    for y in range(th):
        for x in range(tw):
            r, g, b, a = p[x, y]
            p[x, y] = (r, g, b, 255 if a > 140 else 0)
    out = Image.new("RGBA", (tw + 2, th + 1))
    out.alpha_composite(sm, (1, 0))
    return out


def main():
    cuts = {name: cut(os.path.join(SRC, f), kind) for name, (f, kind, _) in FRAMES.items()}
    for name in ("grizzly_stand", "grizzly_walk", "grizzly_walk_b", "grizzly_swipe"):
        fix_nose(cuts[name], NOSE_BOX.get(name, (0.84, 0.0, 1.0, 0.65)))
    # 目標毛色：第一輪第 4 張（r1_walk）的平均色
    target = mean_rgb(cut(os.path.join(SRC, "r1_walk.jpg"), "checker"))
    base = mean_rgb(cuts["grizzly_stand"])
    gain = [t / max(1.0, b) for t, b in zip(target, base)]
    for name in ("grizzly_stand", "grizzly_walk", "grizzly_walk_b", "grizzly_swipe"):
        apply_gain(cuts[name], gain)
    # 低頭吃：調到和調整後的第二輪一樣
    new_base = mean_rgb(cuts["grizzly_stand"])
    eat_gain = [t / max(1.0, b) for t, b in zip(new_base, mean_rgb(cuts["grizzly_eat"]))]
    apply_gain(cuts["grizzly_eat"], eat_gain)
    print("毛色倍率", [round(g, 3) for g in gain], "低頭吃", [round(g, 3) for g in eat_gain])
    for name, (_, _, cells) in FRAMES.items():
        cuts[name].save(os.path.join(SRC, name + "_src.png"))
        for d in DENSITIES:
            out = shrink(cuts[name], round(cells * d))
            out.save(os.path.join(OUT, "%s_%d.png" % (name, d)))
            print(name, d, out.size)


if __name__ == "__main__":
    main()
