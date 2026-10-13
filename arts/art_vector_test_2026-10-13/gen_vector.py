"""向量風格比較場景：用程式組 SVG，再用 cairosvg 轉成 PNG。
扁平色塊＋少量漸層、平滑曲線；動物由部件（身體、頭、四肢、尾巴）組成，之後的動作用部件旋轉。
用法：python3 gen_vector.py preview   → 輸出試作圖到這個資料夾
"""
import math, sys, os, random, re
import cairosvg

HERE = os.path.dirname(os.path.abspath(__file__))


def svg(w, h, body, defs=""):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" '
            f'viewBox="0 0 {w} {h}"><defs>{defs}</defs>{body}</svg>')


def path(d, fill, extra=""):
    return f'<path d="{d}" fill="{fill}" {extra}/>'


def limb(pts, widths, fill):
    """一段段的腿：每段一條圓頭粗線，寬度逐段變細。"""
    out = []
    for (a, b), w in zip(zip(pts, pts[1:]), widths):
        out.append(f'<line x1="{a[0]}" y1="{a[1]}" x2="{b[0]}" y2="{b[1]}" stroke="{fill}" '
                   f'stroke-width="{w}" stroke-linecap="round"/>')
    for p, w in zip(pts[1:-1], widths[1:]):
        out.append(f'<circle cx="{p[0]}" cy="{p[1]}" r="{w/2}" fill="{fill}"/>')
    return "".join(out)


def paw(x, y, fill, w=12):
    return f'<ellipse cx="{x + 3}" cy="{y - 2}" rx="{w/2 + 1}" ry="3.5" fill="{fill}"/>'


def rot(deg, cx, cy, inner):
    return f'<g transform="rotate({deg} {cx} {cy})">{inner}</g>'


# ---------------- 形狀工具：平滑輪廓＋毛邊 ----------------
def _norm(dx, dy):
    l = math.hypot(dx, dy) or 1.0
    return dx / l, dy / l


def outline(spec, sweep=(-0.5, 0.35)):
    """spec：點 (x, y) 與毛邊標記 ("fur", 深度, 撮數) 的序列，順時針描（畫面座標 y 向下）。
    一般的邊用 Catmull-Rom 曲線；標記之後那一條邊改成一撮撮的毛，往外側、順著 sweep 方向翹。"""
    pts, fur = [], {}
    for e in spec:
        if isinstance(e, tuple) and e and e[0] == "fur":
            fur[len(pts) - 1] = e[1:]
        else:
            pts.append(e)
    n = len(pts)
    d = [f"M{pts[0][0]:.1f} {pts[0][1]:.1f}"]
    for i in range(n):
        a, b = pts[i], pts[(i + 1) % n]
        if i in fur:
            depth, count = fur[i]
            tx, ty = _norm(b[0] - a[0], b[1] - a[1])
            ox, oy = ty, -tx          # 順時針描時的外側
            for k in range(count):
                p0 = (a[0] + (b[0] - a[0]) * k / count, a[1] + (b[1] - a[1]) * k / count)
                p1 = (a[0] + (b[0] - a[0]) * (k + 1) / count, a[1] + (b[1] - a[1]) * (k + 1) / count)
                dep = depth * (0.75 + 0.5 * ((k * 7919) % 5) / 4)
                tip = (p1[0] + (ox + sweep[0]) * dep, p1[1] + (oy + sweep[1]) * dep)
                c1 = (p0[0] + (tip[0] - p0[0]) * 0.55 + ox * dep * 0.25, p0[1] + (tip[1] - p0[1]) * 0.55 + oy * dep * 0.25)
                c2 = ((tip[0] + p1[0]) / 2 - ox * dep * 0.1, (tip[1] + p1[1]) / 2 - oy * dep * 0.1)
                d.append(f"Q{c1[0]:.1f} {c1[1]:.1f} {tip[0]:.1f} {tip[1]:.1f} Q{c2[0]:.1f} {c2[1]:.1f} {p1[0]:.1f} {p1[1]:.1f}")
        else:
            p0, p3 = pts[(i - 1) % n], pts[(i + 2) % n]
            c1 = (a[0] + (b[0] - p0[0]) / 6, a[1] + (b[1] - p0[1]) / 6)
            c2 = (b[0] - (p3[0] - a[0]) / 6, b[1] - (p3[1] - a[1]) / 6)
            d.append(f"C{c1[0]:.1f} {c1[1]:.1f} {c2[0]:.1f} {c2[1]:.1f} {b[0]:.1f} {b[1]:.1f}")
    return " ".join(d) + " Z"


def leg_shape(joints, widths):
    """沿關節的錐形腿：每個關節給寬度，左右兩邊各偏移一半，連成平滑輪廓。"""
    n = len(joints)
    left, right = [], []
    for i, (x, y) in enumerate(joints):
        if i == 0:
            tx, ty = _norm(joints[1][0] - x, joints[1][1] - y)
        elif i == n - 1:
            tx, ty = _norm(x - joints[i - 1][0], y - joints[i - 1][1])
        else:
            ax, ay = _norm(x - joints[i - 1][0], y - joints[i - 1][1])
            bx, by = _norm(joints[i + 1][0] - x, joints[i + 1][1] - y)
            tx, ty = _norm(ax + bx, ay + by)
        w = widths[i] / 2
        left.append((x + ty * w, y - tx * w))
        right.append((x - ty * w, y + tx * w))
    return right + left[::-1]


def paw_shape(x, y, fill, r=7.5):
    """腳掌：前低後高的橢圓，加兩條趾縫。"""
    return (f'<path d="M{x-r} {y} Q{x-r} {y-6} {x-1} {y-6.5} Q{x+r+2} {y-5} {x+r+2.5} {y-0.5} Q{x+r} {y+1} {x} {y+1} Q{x-r} {y+1} {x-r} {y} Z" fill="{fill}"/>'
            f'<path d="M{x+2} {y-2.5} L{x+2.5} {y+0.5} M{x+5.5} {y-2.5} L{x+6} {y+0.5}" stroke="#00000033" stroke-width="0.9"/>')


# ---------------- 灰狼 ----------------
WOLF_PALETTES = {
    # base 主色、shade 陰影面、light 亮面、cream 臉頰與胸前、saddle 背上深色、far 遠側
    "gray": dict(base="#8f8b87", shade="#76726f", light="#a9a5a0", cream="#e8e4dd", saddle="#575352",
                 far="#64605e", nose="#222020", eye="#e2a73c", tip="#2f2c2b", ear_in="#cfc8bf"),
    "black": dict(base="#3d3c40", shade="#2f2e32", light="#4d4c51", cream="#6a686d", saddle="#232226",
                  far="#28272b", nose="#121113", eye="#e4b54a", tip="#18171a", ear_in="#5a585d"),
}


def wolf(pal, pose=None, scale=1.0):
    """畫布 240x160、腳底 y=164、朝右。腿長約等於胸深，胸深、腰細。pose 為部件角度（度）。"""
    p = WOLF_PALETTES[pal]
    q = dict(head=0, tail=0, fl=0, fr=0, hl=0, hr=0)
    q.update(pose or {})
    P = lambda spec, fill, sweep=(-0.5, 0.35), extra="": path(outline(spec, sweep), fill, extra)
    L = lambda joints, widths, fill: path(outline(leg_shape(joints, widths)), fill)
    g = []
    # 遠側的腿（深色）
    g.append(rot(q["fr"], 152, 88, L([(152, 86), (150, 112), (152, 148), (154, 160)], [18, 12, 8.5, 8], p["far"]) + paw_shape(156, 163, p["far"], 6.5)))
    g.append(rot(q["hr"], 82, 84, L([(80, 84), (94, 106), (74, 134), (78, 160)], [24, 14, 9, 8], p["far"]) + paw_shape(81, 163, p["far"], 6.5)))
    # 尾巴：蓬鬆下垂、兩側毛邊、尾尖深色
    tail_spec = [(62, 62), (60, 86), ("fur", 3, 4), (52, 114), ("fur", 3, 3), (42, 136), (30, 150),
                 (28, 128), ("fur", 4, 4), (34, 98), ("fur", 4, 4), (46, 72), (54, 62)]
    tail = P(tail_spec, p["shade"], (0.2, 0.4))
    tail += P([(47, 126), ("fur", 3, 2), (42, 136), (30, 150), (28, 128), ("fur", 2, 2), (30, 120)], p["tip"], (0.2, 0.4))
    tail += P([(54, 70), (56, 88), (48, 110), (44, 92)], p["light"], extra='opacity="0.5"')
    g.append(rot(q["tail"], 60, 66, tail))
    # 身體＋頸：背線平、胸深、腰收；頸背、胸前、腹下有毛邊
    body = [(58, 60), (84, 56), (112, 60), (138, 50), ("fur", 3, 8), (172, 36),
            (186, 64), ("fur", 5, 6), (176, 96), ("fur", 4, 4), (160, 102), ("fur", 3, 3), (140, 98),
            (122, 90), (108, 86), (92, 96), (72, 100), (56, 88), (52, 72)]
    g.append(P(body, p["base"], (-0.6, 0.3)))
    # 肩後的陰影面、背上的深色鞍形毛（下緣是毛邊）
    g.append(P([(138, 62), (150, 70), (154, 90), (148, 100), (138, 94), (132, 78)], p["shade"], extra='opacity="0.7"'))
    g.append(P([(60, 60), (84, 55), (112, 59), (138, 49), (166, 38), (160, 52), ("fur", 4, 5), (124, 68), ("fur", 3, 4), (86, 70), (64, 74)], p["saddle"], (-0.4, 0.5)))
    # 胸前與喉嚨的淺色毛
    g.append(P([(180, 66), (186, 66), ("fur", 5, 5), (176, 96), ("fur", 4, 3), (162, 102), (166, 88), (172, 74)], p["cream"], (-0.6, 0.3)))
    # 近側後腿：厚實的大腿，後緣是「褲腳」毛邊
    thigh = [(62, 62), (90, 66), (104, 88), (102, 108), (92, 116), ("fur", 4, 4), (66, 104), (56, 84)]
    hl = (P(thigh, p["base"], (-0.5, 0.4))
          + P([(74, 70), (92, 72), (101, 90), (96, 100), (84, 88)], p["light"], extra='opacity="0.55"')
          + L([(98, 104), (80, 134), (86, 160)], [15, 10, 8], p["base"])
          + path(outline(leg_shape([(83, 138), (87, 158)], [3.5, 3])), p["light"])
          + paw_shape(89, 163, p["base"]))
    g.append(rot(q["hl"], 84, 84, hl))
    # 近側前腿：肩胛、上臂粗、腕部細，前緣有一道亮面
    fl = (L([(162, 78), (162, 108), (164, 148), (166, 160)], [24, 14, 9.5, 9], p["base"])
          + P([(158, 70), (170, 74), (171, 90), (163, 94)], p["light"], extra='opacity="0.55"')
          + path(outline(leg_shape([(166, 116), (167, 148), (168, 158)], [4, 3.5, 3])), p["light"])
          + paw_shape(169, 163, p["base"]))
    g.append(rot(q["fl"], 162, 80, fl))
    # 頭：額頭到口鼻收細、鼻樑長；臉頰毛往後下方翹；耳朵大
    hx, hy = 178, 60
    head = (P([(166, 38), (174, 30), (188, 30), (200, 36), (206, 44), (226, 54), (234, 60), (233, 66),
               (224, 69), (210, 70), (200, 76), ("fur", 4, 4), (178, 78), (170, 64)], p["base"], (-0.7, 0.4))
            # 遠側的耳朵
            + P([(172, 36), (176, 14), (186, 34)], p["far"])
            # 口鼻與臉頰的淺色
            + P([(206, 56), (224, 60), (232, 64), (224, 69), (210, 70), (200, 76), ("fur", 5, 4), (180, 82), (184, 70), (196, 62)], p["cream"], (-0.7, 0.5))
            # 額頭到頸背的深色
            + P([(170, 34), (186, 28), (200, 36), (190, 40), (178, 46)], p["saddle"])
            # 近側的耳朵（外深內淺）
            + P([(180, 36), (188, 10), (200, 34)], p["shade"])
            + P([(185, 33), (189, 17), (195, 33)], p["ear_in"])
            # 眼睛（杏仁形）、鼻子、嘴線
            + f'<path d="M199 45 Q203 41.5 208 44 Q204 47.5 199 45 Z" fill="{p["eye"]}"/>'
            + f'<circle cx="204" cy="44.6" r="1.4" fill="{p["nose"]}"/>'
            + f'<path d="M197.5 44.2 Q203 39.5 209.5 43.6" stroke="{p["nose"]}" stroke-width="1" fill="none"/>'
            + f'<path d="M228 57 Q235 57.5 235 61.5 Q234 64.5 229 63.5 Q226 61 228 57 Z" fill="{p["nose"]}"/>'
            + f'<path d="M209 68 Q218 67.5 230 65.5" stroke="{p["nose"]}" stroke-width="1.3" fill="none" stroke-linecap="round"/>')
    g.append(f'<g transform="translate(-6 5) translate(190 56) scale(1.1) translate(-190 -56)">' + rot(q["head"], hx, hy, head) + '</g>')
    inner = "".join(g)
    return f'<g transform="scale({scale})">{inner}</g>'


# ---------------- 背景：林緣草地 ----------------
def conifer(x, base, h, fill):
    w = h * 0.34
    tiers = max(5, int(h / 45))
    d = []
    for i in range(tiers):
        t0 = i / tiers
        top = base - h + h * t0 * 0.82
        bot = base - h + h * (t0 + 0.34) if i < tiers - 1 else base - h * 0.06
        hw = w * (0.32 + 0.68 * (i + 1) / tiers)
        d.append(f"M{x} {top} L{x + hw} {bot} Q{x} {bot - h*0.04} {x - hw} {bot} Z")
    trunk = f'<rect x="{x - h*0.025}" y="{base - h*0.08}" width="{h*0.05}" height="{h*0.08}" fill="{fill}"/>'
    return trunk + path(" ".join(d), fill)


def hill(y0, amp, freq, phase, fill, w=1280, h=720, steps=48):
    pts = []
    for i in range(steps + 1):
        x = w * i / steps
        y = y0 + amp * (math.sin(x * freq + phase) * 0.6 + math.sin(x * freq * 2.3 + phase * 1.7) * 0.4)
        pts.append((x, y))
    d = f"M0 {h} L" + " L".join(f"{x:.1f} {y:.1f}" for x, y in pts) + f" L{w} {h} Z"
    return path(d, fill)


def background_meadow(season="summer", w=1280, h=720, seed=7):
    rnd = random.Random(seed)
    sky_top, sky_bot = "#9fc3cf", "#e9e0c8"
    defs = (f'<linearGradient id="sky" x1="0" y1="0" x2="0" y2="1">'
            f'<stop offset="0" stop-color="{sky_top}"/><stop offset="1" stop-color="{sky_bot}"/></linearGradient>'
            f'<linearGradient id="mist" x1="0" y1="0" x2="0" y2="1">'
            f'<stop offset="0" stop-color="#e9e0c8" stop-opacity="0"/><stop offset="1" stop-color="#e9e0c8" stop-opacity="0.55"/></linearGradient>')
    b = [f'<rect width="{w}" height="{h}" fill="url(#sky)"/>']
    # 雲
    for cx, cy, s in [(240, 110, 1.0), (860, 80, 1.3), (1120, 150, 0.8)]:
        b.append(f'<g fill="#f6f1e4" opacity="0.85"><ellipse cx="{cx}" cy="{cy}" rx="{70*s}" ry="{18*s}"/>'
                 f'<ellipse cx="{cx-30*s}" cy="{cy-10*s}" rx="{36*s}" ry="{20*s}"/><ellipse cx="{cx+26*s}" cy="{cy-14*s}" rx="{42*s}" ry="{24*s}"/></g>')
    # 遠山（雪頂）
    peaks = [(80, 250), (260, 200), (430, 260), (620, 180), (820, 240), (1000, 190), (1200, 250)]
    d = f"M0 {360} " + " ".join(f"L{x} {y}" for x, y in peaks) + f" L{w} 330 L{w} {h} L0 {h} Z"
    b.append(path(d, "#a9b8c0"))
    full = [(0, 360)] + peaks + [(w, 330)]
    for i in range(1, len(full) - 1):
        (lx, ly), (x, y), (rx, ry) = full[i - 1], full[i], full[i + 1]
        if ly - y < 40 or ry - y < 40:
            continue
        f = 0.28
        L = (x + (lx - x) * f, y + (ly - y) * f); R = (x + (rx - x) * f, y + (ry - y) * f)
        b.append(path(f"M{x} {y} L{R[0]:.0f} {R[1]:.0f} L{(x+R[0])/2:.0f} {R[1]-6:.0f} L{x+4} {R[1]+4:.0f} "
                      f"L{(x+L[0])/2:.0f} {L[1]-4:.0f} L{L[0]:.0f} {L[1]:.0f} Z", "#eef0ec"))
    b.append(f'<rect y="200" width="{w}" height="220" fill="url(#mist)"/>')
    # 三層針葉林，越近越深
    layers = [(400, 90, "#7f998f", 26), (450, 130, "#5c7a6c", 34), (500, 180, "#3e5c4f", 44)]
    for base, th, col, step in layers:
        b.append(hill(base + 10, 10, 0.008, rnd.random() * 6, col))
        x = -10
        while x < w + 20:
            hh = th * rnd.uniform(0.7, 1.15)
            b.append(conifer(x, base + 14 + rnd.uniform(-6, 6), hh, col))
            x += step * rnd.uniform(0.55, 1.1)
    # 草地
    b.append(hill(540, 8, 0.004, 1.2, "#a3a65f"))
    b.append(hill(590, 10, 0.005, 2.5, "#8f9450"))
    b.append(hill(650, 6, 0.006, 0.4, "#7b8244"))
    # 草叢與小花
    for _ in range(140):
        x = rnd.uniform(0, w); y = rnd.uniform(560, 715)
        s = 0.6 + (y - 560) / 160
        col = rnd.choice(["#6d743c", "#b4b56c", "#5f6635"])
        b.append(path(f"M{x} {y} Q{x-4*s} {y-10*s} {x-8*s} {y-16*s} Q{x-1*s} {y-8*s} {x} {y} "
                      f"Q{x+2*s} {y-12*s} {x+3*s} {y-20*s} Q{x+5*s} {y-10*s} {x+2*s} {y} Z", col))
    for _ in range(26):
        x = rnd.uniform(0, w); y = rnd.uniform(580, 710)
        b.append(f'<circle cx="{x:.0f}" cy="{y:.0f}" r="2.4" fill="{rnd.choice(["#e8d27a", "#e6e1d2", "#b08bc0"])}"/>')
    # 岩石
    for x, y, s in [(980, 630, 1.0), (1040, 640, 0.6), (180, 660, 0.8)]:
        b.append(path(f"M{x-40*s} {y} Q{x-34*s} {y-34*s} {x} {y-38*s} Q{x+36*s} {y-36*s} {x+44*s} {y} Z", "#8b8a84"))
        b.append(path(f"M{x-6*s} {y-37*s} Q{x+30*s} {y-34*s} {x+44*s} {y} L{x+20*s} {y} Q{x+16*s} {y-20*s} {x-6*s} {y-37*s} Z", "#6e6d68"))
    # 近景框邊的大樹
    b.append(conifer(40, 760, 620, "#22382f"))
    b.append(conifer(1250, 760, 540, "#22382f"))
    return svg(w, h, "".join(b), defs)


def render(svg_text, out, width=None):
    cairosvg.svg2png(bytestring=svg_text.encode(), write_to=out, output_width=width)


def preview():
    bg = background_meadow()
    render(bg, os.path.join(HERE, "preview_meadow.png"))
    # 灰狼與黑狼的單張與擺在背景上的樣子
    pair = svg(500, 176, f'<rect width="500" height="176" fill="#e9e3d6"/>'
               f'{wolf("gray")}<g transform="translate(250 0)">{wolf("black")}</g>')
    render(pair, os.path.join(HERE, "preview_wolves.png"), 1000)
    scene = bg.replace("</svg>", f'<g transform="translate(420 432) scale(1.45)">{wolf("gray")}</g></svg>')
    render(scene, os.path.join(HERE, "preview_scene.png"))


if __name__ == "__main__":
    preview()
