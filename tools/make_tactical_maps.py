#!/usr/bin/env python3
"""戰術地圖：每種地形 2～3 張（Phase 2c 第 4 步，SPEC「每種地形手工做 2～3 張」）。

每張 40×16 格，字元：. 開闊、f 密林（樹叢、柳叢、林子）、l 倒木（或岩堆）、r 岩坡（碎石坡、岩壁；騾鹿在上面不減速，Phase 2d）、
w 河（馴鹿涉水不減速，Phase 2d 第 4 步）、s 淺水、d 深水（河狸的水塘，2026-10-22：淺水河狸稍快、狼稍慢；深水河狸很快、狼很慢，河狸進了深水就潛走）、
c 峭壁（大角羊的峽谷，2026-10-22：大角羊在上面很穩、一上去就算逃掉，狼幾乎上不去）、
b 洞口（旱獺，Phase 2g：旱獺一鑽進去就算逃掉；狼可以站在上面擋住）。
用簡單的形狀「畫」出來，寫進 data/tactical_hunt.json 的 maps（{id: {name, family, map}}）；
狼與鹿的起始位置、鹿的目的地由 TacticalHunt.setup_from_game 每場隨機挑。

地形 → 地圖族（GameState.TACTICAL_TERRAIN_FAMILY）：
  open（空地、草原、高山草甸、苔原、丘陵）、edge（林緣、樹線）、dense（密林）、stream（溪、河、柳叢）、logs（倒木）、
  slope（岩石、碎石、崖邊；Phase 2d 第 3 步）、tundra（開闊苔原、冰磧丘）、river（柳叢河谷，有河；Phase 2d 第 4 步）、
  pond（水塘：深水外圍一圈淺水；河狸一律用這一族，species.family）、cliff（峽谷：峭壁、碎石坡、草地；大角羊）、talus（岩坡草甸：碎石與岩塊、2～3 個洞口；旱獺，Phase 2g）。

用法：python3 tools/make_tactical_maps.py（會改寫 tactical_hunt.json 的 maps 一項，其他不動）
"""
import json
import math
import random
import re

W, H = 40, 16


def blank(ch="."):
    return [[ch] * W for _ in range(H)]


def put(g, x, y, ch):
    if 0 <= x < W and 0 <= y < H:
        g[y][x] = ch


def blob(g, cx, cy, rx, ry, ch="f", rough=0.0, seed=0):
    rnd = random.Random(seed)
    for y in range(H):
        for x in range(W):
            d = ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2
            if d <= 1.0 + (rnd.random() - 0.5) * rough:
                g[y][x] = ch


def line(g, x0, y0, x1, y1, ch="l"):
    n = max(abs(x1 - x0), abs(y1 - y0))
    for i in range(n + 1):
        put(g, round(x0 + (x1 - x0) * i / n), round(y0 + (y1 - y0) * i / n), ch)


def edge_left(g, depth, wobble, seed, ch="f"):
    rnd = random.Random(seed)
    for y in range(H):
        d = depth + rnd.randint(-wobble, wobble)
        for x in range(d):
            g[y][x] = ch


def edge_top(g, depth, wobble, seed, ch="f"):
    rnd = random.Random(seed)
    for x in range(W):
        d = depth + rnd.randint(-wobble, wobble)
        for y in range(d):
            g[y][x] = ch


def band(g, pts, width, ch="f"):
    """沿折線畫一條帶子（溪邊的柳叢）"""
    for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
        n = max(abs(x1 - x0), abs(y1 - y0))
        for i in range(n + 1):
            cx = x0 + (x1 - x0) * i / n
            cy = y0 + (y1 - y0) * i / n
            for dy in range(-width, width + 1):
                put(g, round(cx), round(cy + dy), ch)


def maps():
    out = {}
    # --- 開闊地 ---
    g = blank()
    blob(g, 21, 2, 3, 2, rough=0.6, seed=1)
    blob(g, 12, 13, 3, 2, rough=0.6, seed=2)
    blob(g, 1, 1, 2, 2, seed=3); blob(g, 38, 14, 2, 2, seed=4)
    out["open_1"] = {"name": "空地、兩叢灌木", "family": "open", "map": g}
    g = blank()
    for x, y in [(8, 4), (15, 11), (26, 3), (31, 12), (20, 8)]:
        blob(g, x, y, 1.3, 1.1, seed=x * 7 + y)
    out["open_2"] = {"name": "空地、零星樹叢", "family": "open", "map": g}
    g = blank()
    edge_top(g, 2, 1, 5)
    blob(g, 30, 10, 2.5, 2, rough=0.5, seed=6)
    out["open_3"] = {"name": "草原、遠處一排樹", "family": "open", "map": g}
    # --- 林緣 ---
    g = blank()
    edge_left(g, 9, 1, 11)
    blob(g, 12, 3, 2, 1.5, seed=12)
    out["edge_1"] = {"name": "林緣（樹林在一側）", "family": "edge", "map": g}
    g = blank()
    edge_top(g, 5, 1, 13)
    blob(g, 18, 6, 3, 2, rough=0.5, seed=14)  # 伸出來的一角
    out["edge_2"] = {"name": "林緣（樹林在上方，伸出一角）", "family": "edge", "map": g}
    g = blank()
    edge_left(g, 6, 1, 15)
    edge_top(g, 3, 1, 16)
    blob(g, 30, 12, 3, 2, rough=0.6, seed=17)
    out["edge_3"] = {"name": "林緣（林子轉角）", "family": "edge", "map": g}
    # --- 密林 ---
    g = blank("f")
    blob(g, 20, 8, 9, 4.5, ".", rough=0.4, seed=21)
    blob(g, 34, 8, 4, 3, ".", rough=0.4, seed=22)
    blob(g, 5, 8, 4, 3, ".", rough=0.4, seed=23)
    out["dense_1"] = {"name": "密林中的空地", "family": "dense", "map": g}
    g = blank("f")
    band(g, [(0, 4), (12, 6), (22, 11), (39, 10)], 2, ".")
    blob(g, 16, 8, 3, 2, ".", seed=24)
    out["dense_2"] = {"name": "密林中蜿蜒的林間空地", "family": "dense", "map": g}
    # --- 溪邊（柳叢沿著溪） ---
    g = blank()
    band(g, [(0, 3), (14, 6), (26, 10), (39, 13)], 1)
    blob(g, 33, 3, 2, 1.5, seed=31)
    out["stream_1"] = {"name": "溪邊（柳叢斜穿過）", "family": "stream", "map": g}
    g = blank()
    band(g, [(0, 3), (39, 4)], 1)
    band(g, [(0, 12), (39, 11)], 1)
    for x in (10, 25):  # 柳叢的缺口（淺灘）
        for y in range(H):
            if g[y][x] == "f" and (y < 6 or y > 9):
                g[y][x] = "."
    out["stream_2"] = {"name": "溪谷（兩岸柳叢）", "family": "stream", "map": g}
    # --- 倒木、岩堆 ---
    g = blank()
    line(g, 12, 2, 15, 8); line(g, 24, 9, 28, 14); line(g, 20, 3, 26, 2)
    blob(g, 37, 2, 2, 2, seed=41)
    out["logs_1"] = {"name": "倒木散在空地上", "family": "logs", "map": g}
    g = blank()
    edge_left(g, 7, 1, 42)
    for y0, x0 in [(2, 10), (6, 11), (10, 10), (13, 12)]:
        line(g, x0, y0, x0 + 5, y0 + 1)
    out["logs_2"] = {"name": "林緣的倒木堆", "family": "logs", "map": g}
    g = blank()
    for x, y in [(10, 4), (16, 11), (24, 6), (30, 12), (33, 3)]:
        blob(g, x, y, 1.6, 1.2, "l", rough=0.5, seed=x + y * 3)
    out["logs_3"] = {"name": "岩堆", "family": "logs", "map": g}
    # --- 岩坡（Phase 2d 第 3 步）：鹿在下方的草甸、岩坡在幾格外 ---
    g = blank()
    edge_top(g, 5, 1, 51, "r")
    blob(g, 30, 3, 3, 2, "r", rough=0.5, seed=52)
    blob(g, 8, 13, 1.5, 1.2, "r", seed=53)
    out["slope_1"] = {"name": "草甸與上方的碎石坡", "family": "slope", "map": g}
    g = blank()
    edge_top(g, 3, 1, 54, "r")
    for x in range(W):  # 下方的岩壁
        d = 3 + random.Random(55 + x).randint(-1, 1)
        for y in range(H - d, H):
            g[y][x] = "r"
    blob(g, 14, 8, 1.5, 1.2, "r", seed=56)
    out["slope_2"] = {"name": "峽谷（兩側岩壁）", "family": "slope", "map": g}
    g = blank()
    edge_left(g, 9, 2, 57, "r")
    blob(g, 34, 9, 4, 3, "f", rough=0.5, seed=58)
    blob(g, 24, 2, 2, 1.5, "r", seed=59)
    out["slope_3"] = {"name": "一側岩坡、一側林子", "family": "slope", "map": g}
    # --- 苔原（Phase 2d 第 4 步）：幾乎沒有掩蔽 ---
    g = blank()
    for x, y in [(9, 4), (27, 12), (33, 3)]:
        blob(g, x, y, 1.0, 0.8, seed=x * 3 + y)
    blob(g, 18, 11, 1.2, 1.0, "r", seed=61)
    out["tundra_1"] = {"name": "開闊苔原（零星矮灌叢）", "family": "tundra", "map": g}
    g = blank()
    band(g, [(0, 12), (14, 9), (26, 6), (39, 4)], 0, "r")  # 冰磧丘（一道礫石的長丘）
    blob(g, 7, 4, 1.0, 0.8, seed=62)
    blob(g, 31, 12, 1.2, 0.8, seed=63)
    out["tundra_2"] = {"name": "苔原與冰磧丘", "family": "tundra", "map": g}
    # --- 河谷（Phase 2d 第 4 步）：一條河、兩岸零星柳叢 ---
    g = blank()
    band(g, [(0, 9), (12, 10), (24, 8), (39, 9)], 1, "w")
    for x, y in [(5, 7), (16, 12), (29, 6), (35, 11)]:
        blob(g, x, y, 1.3, 0.8, seed=x + y * 5)
    out["river_1"] = {"name": "河谷（河橫過中間）", "family": "river", "map": g}
    g = blank()
    band(g, [(0, 2), (14, 5), (22, 11), (39, 14)], 1, "w")
    for x, y in [(8, 7), (26, 8), (31, 13)]:
        blob(g, x, y, 1.4, 0.9, seed=x * 7 + y)
    out["river_2"] = {"name": "河彎（斜穿過河谷）", "family": "river", "map": g}
    g = blank()
    band(g, [(0, 3), (39, 3)], 1, "w")
    for x in range(W):  # 一側的柳叢
        if random.Random(64 + x).random() < 0.5:
            g[5][x] = "f"
    blob(g, 20, 12, 2, 1.2, seed=65)
    out["river_3"] = {"name": "河在一側（岸邊柳叢）", "family": "river", "map": g}
    # --- 水塘（河狸，2026-10-22）：深水 d，外圍一圈淺水 s；岸邊柳叢 ---
    g = blank()
    blob(g, 31, 8, 7.5, 5.5, "s", rough=0.3, seed=71)
    blob(g, 32, 8, 5, 3.5, "d", rough=0.3, seed=72)
    for x, y in [(22, 3), (22, 13), (14, 8)]:
        blob(g, x, y, 1.4, 1.0, seed=x * 3 + y)
    out["pond_1"] = {"name": "水塘在一側（岸邊柳叢）", "family": "pond", "map": g}
    g = blank()
    band(g, [(0, 8), (14, 7), (26, 9), (39, 8)], 1, "s")
    blob(g, 20, 8, 5, 2.5, "s", rough=0.2, seed=73)
    blob(g, 20, 8, 3.2, 1.6, "d", rough=0.2, seed=74)
    line(g, 24, 6, 24, 10, "l")  # 河狸壩
    for x, y in [(8, 4), (31, 12), (33, 4)]:
        blob(g, x, y, 1.3, 0.9, seed=x + y * 7)
    out["pond_2"] = {"name": "溪上的河狸塘（壩後的深水）", "family": "pond", "map": g}
    g = blank()
    blob(g, 20, 1, 12, 4, "s", rough=0.3, seed=75)
    blob(g, 20, 0, 9, 2.6, "d", rough=0.3, seed=76)
    for x, y in [(6, 9), (33, 10), (18, 13)]:
        blob(g, x, y, 1.5, 1.0, seed=x * 5 + y)
    out["pond_3"] = {"name": "林間的水塘（上方的深水）", "family": "pond", "map": g}
    # --- 峽谷（大角羊，2026-10-22）：c 峭壁、r 碎石坡、. 草地 ---
    g = blank()
    for x in range(W):
        top = 2 + int(1.2 * math.sin(x / 4.0))
        for y in range(0, max(1, top)):
            g[y][x] = "c"
        for y in range(max(1, top), top + 3):
            if 0 <= y < H:
                g[y][x] = "r"
    blob(g, 30, 11, 2, 1.2, seed=81)
    out["cliff_1"] = {"name": "峭壁下的草坡", "family": "cliff", "map": g}
    g = blank()
    for x in range(W):
        for y in range(0, 2):
            g[y][x] = "c"
        for y in range(H - 2, H):
            g[y][x] = "c"
        g[2][x] = "r"
        g[H - 3][x] = "r"
    blob(g, 12, 5, 3, 1.3, "r", seed=82)
    blob(g, 28, 10, 3, 1.3, "r", seed=83)
    out["cliff_2"] = {"name": "兩側峭壁的峽谷", "family": "cliff", "map": g}
    g = blank()
    blob(g, 20, 6, 6, 3.2, "r", rough=0.3, seed=84)
    blob(g, 20, 5, 3.5, 2.0, "c", rough=0.3, seed=85)
    blob(g, 6, 12, 2, 1.2, seed=86)
    blob(g, 34, 3, 1.5, 1.0, seed=87)
    out["cliff_3"] = {"name": "草地中間的岩丘", "family": "cliff", "map": g}
    # --- 岩坡草甸（旱獺，Phase 2g）：r 碎石與岩塊（旱獺在上面快、擋住牠的視線）、b 洞口、. 草甸 ---
    g = blank()
    for x in range(W):
        top = 3 + int(1.3 * math.sin(x / 5.0 + 1.0))
        for y in range(0, top):
            g[y][x] = "r"
    for x, y in [(9, 7), (27, 9)]:
        blob(g, x, y, 1.5, 1.0, "r", seed=x * 11 + y)
    for x, y in [(6, 4), (15, 3), (31, 4)]:
        g[y][x] = "b"
    out["talus_1"] = {"name": "碎石坡腳的草甸", "family": "talus", "map": g}
    g = blank()
    for x, y, rx in [(8, 4, 2.2), (20, 10, 2.6), (32, 5, 2.0)]:
        blob(g, x, y, rx, 1.4, "r", rough=0.3, seed=x * 3 + y + 90)
    for x, y in [(10, 6), (17, 11), (33, 7)]:
        g[y][x] = "b"
    out["talus_2"] = {"name": "草甸上的岩堆", "family": "talus", "map": g}
    g = blank()
    blob(g, 2, 8, 4, 6, "r", rough=0.3, seed=91)
    blob(g, 37, 8, 4, 6, "r", rough=0.3, seed=92)
    for x, y in [(20, 4), (14, 12), (26, 11)]:
        blob(g, x, y, 1.2, 0.8, "r", seed=x + y * 5 + 93)
    for x, y in [(6, 6), (33, 11), (21, 5)]:
        g[y][x] = "b"
    out["talus_3"] = {"name": "兩片碎石坡之間的草甸", "family": "talus", "map": g}
    for k in out:
        out[k]["map"] = ["".join(r) for r in out[k]["map"]]
    return out


def main():
    p = "data/tactical_hunt.json"
    s = open(p, encoding="utf-8").read()
    m = maps()
    body = json.dumps(m, ensure_ascii=False, indent=2).replace("\n", "\n  ")
    block = '"_maps_comment": "Phase 2c 第 4 步：每種地形的地圖（tools/make_tactical_maps.py 產生）。family：open／edge／dense／stream／logs／slope／tundra／river（Phase 2d）／pond（河狸）／cliff（大角羊）／talus（旱獺）；起始位置與目的地每場隨機（TacticalHunt.setup_from_game）。",\n  "maps": ' + body
    if '"maps":' in s:
        s = re.sub(r'"_maps_comment": ".*?",\n  "maps": \{.*?\n  \}', lambda _: block, s, count=1, flags=re.S)
    else:
        k = s.rstrip().rfind("}")
        s = s[:k].rstrip() + ",\n  " + block + "\n}\n"
    json.loads(s)
    open(p, "w", encoding="utf-8").write(s)
    for k, v in m.items():
        print(k, v["name"])
        print("\n".join(v["map"]))


if __name__ == "__main__":
    main()
