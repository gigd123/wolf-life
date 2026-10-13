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


# ---------------- 灰狼 ----------------
WOLF_PALETTES = {
    "gray": dict(base="#8b8379", dark="#5f5852", saddle="#4f4944", light="#d9d1c3",
                 far="#6c655e", nose="#2a2624", eye="#d9a441", tip="#3a3532"),
    "black": dict(base="#3b3a3d", dark="#2a292c", saddle="#222124", light="#5c5a5e",
                  far="#2c2b2e", nose="#141315", eye="#e0b545", tip="#1a191b"),
}


def wolf(pal, pose=None, scale=1.0):
    """畫布 240x160、腳底 y=150、朝右。pose 為部件角度。"""
    p = WOLF_PALETTES[pal]
    q = dict(head=0, tail=0, fl=0, fr=0, hl=0, hr=0, body_dy=0)
    q.update(pose or {})
    dy = q["body_dy"]
    g = []
    D = lambda d: re.sub(r"Y(-?[\d.]+)", lambda m: f"{float(m.group(1)) + dy:g}", d)
    # 遠側的腿（顏色較深）
    g.append(rot(q["fr"], 150, 96 + dy, limb([(150, 96 + dy), (148, 120 + dy), (147, 146)], [15, 9], p["far"]) + paw(147, 150, p["far"])))
    g.append(rot(q["hr"], 80, 92 + dy, path(D("M64 Y84 C66 Y70 92 Y72 96 Y88 C98 Y102 92 Y112 86 Y116 C78 Y112 64 Y102 64 Y84 Z"), p["far"])
                 + limb([(86, 112 + dy), (80, 132), (82, 146)], [12, 8], p["far"]) + paw(82, 150, p["far"])))
    # 尾巴：蓬鬆、自然下垂
    tail = path(D("M64 Y72 C52 Y76 44 Y92 44 Y114 C44 Y128 48 Y136 54 Y134 C60 Y124 60 Y108 66 Y94 C68 Y86 70 Y80 72 Y76 Z"), p["dark"])
    tail += path(D("M44 Y114 C44 Y128 48 Y136 54 Y134 C55 Y128 54 Y120 50 Y114 Z"), p["tip"])
    g.append(rot(q["tail"], 68, 74 + dy, tail))
    # 身體：前段（胸）比後段厚約 1.15 倍，腰身收起
    body = D("M72 Y66 C88 Y60 118 Y64 138 Y58 C150 Y54 166 Y54 174 Y62 C184 Y72 182 Y96 174 Y108 "
             "C166 Y116 152 Y116 144 Y112 C130 Y106 118 Y100 104 Y100 C92 Y100 80 Y104 70 Y100 "
             "C60 Y96 56 Y86 58 Y78 C60 Y70 64 Y68 72 Y66 Z")
    g.append(path(body, p["base"]))
    # 背上較深的鞍形毛
    g.append(path(D("M66 Y72 C84 Y60 118 Y66 146 Y56 C138 Y68 116 Y74 96 Y74 C84 Y74 74 Y78 66 Y72 Z"), p["saddle"]))
    # 胸前、腹部的淺色
    g.append(path(D("M120 Y102 C132 Y106 140 Y110 150 Y114 C160 Y116 170 Y112 176 Y104 C170 Y106 158 Y106 148 Y102 C138 Y100 128 Y100 120 Y102 Z"), p["light"]))
    # 近側的後腿：大腿是一塊厚實的形狀，接小腿與跗關節
    g.append(rot(q["hl"], 86, 90 + dy, path(D("M68 Y86 C70 Y70 98 Y72 102 Y90 C104 Y104 98 Y114 92 Y118 C82 Y116 68 Y104 68 Y86 Z"), p["base"])
                 + limb([(92, 114 + dy), (84, 133), (88, 146)], [13, 9], p["base"]) + paw(88, 150, p["base"])))
    # 近側的前腿：上臂粗、肘部明顯
    g.append(rot(q["fl"], 162, 96 + dy, limb([(164, 92 + dy), (160, 118 + dy), (162, 146)], [20, 11], p["base"]) + paw(162, 150, p["base"])))
    # 頭與頸：頸毛厚、頭不抬太高、口鼻鈍
    hx, hy = 172, 72 + dy
    head = (path(D("M140 Y58 C154 Y46 174 Y44 190 Y48 C200 Y50 206 Y56 214 Y60 "
                   "C222 Y63 225 Y68 222 Y73 C218 Y77 208 Y77 198 Y78 "
                   "C194 Y86 190 Y98 182 Y110 C168 Y98 154 Y76 140 Y58 Z"), p["base"])
            # 臉頰到喉嚨的淺色
            + path(D("M190 Y70 C198 Y72 210 Y74 221 Y72 C218 Y77 208 Y77 198 Y78 C194 Y86 190 Y98 182 Y110 C178 Y96 184 Y78 190 Y70 Z"), p["light"])
            # 頸背的深色毛
            + path(D("M140 Y58 C154 Y46 170 Y44 182 Y47 C168 Y52 156 Y58 148 Y66 Z"), p["saddle"])
            # 耳朵
            + path(D("M178 Y50 L183 Y32 L194 Y48 Z"), p["dark"])
            + path(D("M182 Y47 L184 Y38 L190 Y47 Z"), p["light"], 'opacity="0.55"')
            # 鼻子、眼睛、嘴線
            + f'<ellipse cx="221" cy="{66+dy}" rx="3.8" ry="3.2" fill="{p["nose"]}"/>'
            + f'<ellipse cx="199" cy="{58+dy}" rx="2.6" ry="2" fill="{p["eye"]}"/>'
            + f'<circle cx="199.6" cy="{58+dy}" r="1.1" fill="{p["nose"]}"/>'
            + f'<path d="M205 {73+dy} Q212 {75+dy} 219 {72+dy}" stroke="{p["dark"]}" stroke-width="1.2" fill="none"/>')
    g.append(rot(q["head"], hx, hy, head))
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
    pair = svg(500, 170, f'<rect width="500" height="170" fill="#e9e3d6"/>'
               f'{wolf("gray")}<g transform="translate(250 0)">{wolf("black")}</g>')
    render(pair, os.path.join(HERE, "preview_wolves.png"), 1000)
    scene = bg.replace("</svg>", f'<g transform="translate(420 432) scale(1.45)">{wolf("gray")}</g></svg>')
    render(scene, os.path.join(HERE, "preview_scene.png"))


if __name__ == "__main__":
    preview()
