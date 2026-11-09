"""Gemini 出的戰術狩獵獵物（2026-11-06 起，arts/gemini_prey_2026-11-06/；1024×1024 綠底、整隻佔滿畫布寬度）。

每種動物：站（基準，寬幾格照下表）＋其他姿勢（低頭吃草 graze、警覺抬頭 alert、跑 run）照同一個「畫布像素 → 格」比例
（Gemini 每張都畫滿畫布，所以用畫布寬度換算，不用每張的身體寬度）。
處理照 prep_grizzly.py：綠色色鍵去背、只留最大的一塊、縮成 32／48、補 1 像素深色外框（同 prep_wolf.py）。

- 騾鹿公鹿 mule_deer_buck_*：同母鹿（警覺那張是正面看著你）；吃草那張是重畫的乾淨版（第一版有草與浮著的頭，remove_grass 清得掉，留著備用）
- 騾鹿幼鹿 mule_deer_fawn_*：站寬 0.9 格
- 北美馴鹿母鹿 caribou_cow_*：站寬 1.35 格（角細短，比公鹿小）；警覺那張頭只抬高一點（之後可以重出）
- 白尾鹿幼鹿 deer_fawn_*：站寬 0.8 格（四張同一個比例；戰術物種 fawn）
- 白尾鹿雄鹿 deer_buck_*：站寬 1.4 格（取代 PixelLab 的 hd_deer_buck；同名覆蓋）
- 白尾鹿母鹿 deer_doe_*：站寬 1.15 格（取代 PixelLab 的 hd_deer_doe*；輸出同名覆蓋）；警覺是尾巴翹起、抬一隻前腳；跑是尾巴翹成白旗
- 叉角羚 pronghorn_*：站寬 1.45 格（比騾鹿略矮）；警覺是臀部白毛炸開；幼體 pronghorn_kid_* 4 個姿勢（0.85 格；跑那張身體畫得比較長 → 照身體長度指定）
- 牧場的羊 sheep_*：站寬 1.3 格（美麗諾羊，和狼差不多高、身體比較寬）
- 牧場母牛 cattle_cow_*：站寬 2.6 格（2026-11-07 放大：原本 1.75 格因為長角佔掉寬度，身體比狼還矮；現在約狼的 1.4 倍高）（德州長角牛，含角）；跑那張腳邊的沙土清掉；站定反擊第一版畫了一隻小牛趴在腳下（_cattle_cow_fight_with_calf.jpg，不用），重出的 fight＝低頭用長角對著你、刨地；小牛 cattle_calf_* 4 個姿勢（站是走路回頭看那張）
- 大角羊母羊 bighorn_ewe_*：站寬 1.15 格（短角）；小羊 bighorn_lamb_*（0.75 格）：站、警覺、跑是專屬的圖，吃草暫時用母羊那張縮小
- 大角羊公羊 bighorn_ram_*：站寬 1.4 格（含角）；跑那張腳邊的沙土不連在身上，去背時拿掉；fight＝低頭用角對著你
- 美洲野牛 bison_*：站寬 2.65 格（2026-11-07 放大到約狼的 1.6 倍高，和駝鹿同一個壓縮程度）；fight＝站定反擊（尾巴翹直、前蹄刨地；刨地的動作線不連在身上，只留最大的一塊時去掉）；小牛 bison_calf_* 4 個姿勢（1.35 格，橘紅色、沒有肩峰、沒有角；Gemini 每張都畫滿畫布，警覺那張畫得比較小 → 照身體長度指定）
- 草原的野兔 hare_*：站寬 0.6 格；警覺是原本出成「跑」的那張（耳朵往後壓、正要竄出）；跑那張附真實照片當參考才畫出整個騰空；小野兔 hare_young_* 4 個姿勢（0.42 格；警覺和站幾乎一樣，耳朵稍微高一點）
- 旱獺 marmot_*：站寬 0.7 格（含尾巴）；警覺是坐起來張望；小旱獺 marmot_young_* 4 個姿勢（0.5 格；警覺重出了一次才坐起來）
- 河狸 beaver_*：站寬 0.85 格（含尾巴）；吃草那張是坐著啃樹枝；小河狸 beaver_kit_* 4 個姿勢（0.55 格；跑那張腳邊的土屑不連在身上，去背時拿掉）
- 馬鹿公鹿 elk_bull_*：站寬 1.85 格（含角；取代風格測試的單張 hd_elk_bull）
- 馬鹿母鹿 elk_cow_*：站寬 1.6 格（取代風格測試的單張 hd_elk_cow）
- 馬鹿幼鹿 elk_calf_*：站寬 1.15 格（「站」那張是邁步的樣子，縮小後自然）
- 駝鹿母鹿 moose_cow_*：站寬 1.95 格（沒有角）；成年駝鹿每一隻開場時擲一次公或母（hd_art.moose.mixed.random）
- 駝鹿公鹿 moose_bull_*：站寬 2.1 格（含掌狀角；使用者朋友出的，png）；戰術地圖的成年駝鹿先用這張；fight＝站定準備反擊（頭壓低、鹿角朝前、背毛豎起）
- 駝鹿幼鹿 moose_calf_*：站寬 1.2 格（紅褐色、腿細長、沒有角）
- 北美馴鹿幼鹿 caribou_calf_*：站寬 0.95 格（紅褐色、沒有白點、沒有角）
- 北美馴鹿（公鹿）caribou_*：站寬 1.55 格（含角）；警覺、跑從同一張裁出來，吃草翻轉＋調色（SPECIAL）
- 騾鹿母鹿 mule_deer_doe_*：站寬 1.4 格（PixelLab 的白尾鹿腿長脖子高，1.1 格就和這隻 1.4 格差不多高；騾鹿比白尾鹿壯、略大）

用法：python3.12 -I prototypes/hd2d_tactical/prep_gemini_prey.py
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import prep_grizzly as pg  # noqa: E402
import prep_wolf as pw  # noqa: E402
from PIL import Image  # noqa: E402

SRC = os.path.join(pg.ROOT, "arts", "gemini_prey_2026-11-06")
# 動物 → (站那張身體寬幾格, [姿勢])；輸出 hd_<動物>_<姿勢>（站是 hd_<動物>）
ANIMALS = {
    "mule_deer_doe": (1.4, ["stand", "alert", "run", "graze"]),
    "mule_deer_buck": (1.4, ["stand", "alert", "run", "graze"]),
    "mule_deer_fawn": (0.9, ["stand", "alert", "run", "graze"]),
    "caribou": (1.55, ["stand", "alert", "run", "graze"]),
    "caribou_cow": (1.35, ["stand", "alert", "run", "graze"]),
    "caribou_calf": (0.95, ["stand", "alert", "run", "graze"]),
    "moose_calf": (1.2, ["stand", "alert", "run", "graze"]),
    "moose_cow": (1.95, ["stand", "alert", "run", "graze", "fight"]),
    "moose_bull": (2.1, ["stand", "alert", "run", "graze", "fight"]),
    "elk_calf": (1.15, ["stand", "alert", "run", "graze"]),
    "elk_cow": (1.6, ["stand", "alert", "run", "graze"]),
    "elk_bull": (1.85, ["stand", "alert", "run", "graze"]),
    # 白尾鹿母鹿（取代 PixelLab 的卡通風格）：站 png 960/1024、吃草與跑 1408×768（身體畫得比較大）→ 各自照身體長度指定
    "deer_doe": (1.15, ["stand", "alert", "run", "graze"]),
    "deer_buck": (1.4, ["stand", "alert", "run", "graze"]),
    "deer_fawn": (0.8, ["stand", "alert", "run", "graze"]),
    "pronghorn": (1.45, ["stand", "alert", "run", "graze"]),
    "pronghorn_kid": (0.85, ["stand", "alert", "run", "graze"]),
    "sheep": (1.3, ["stand", "alert", "run", "graze"]),
    "cattle_cow": (2.6, ["stand", "alert", "run", "graze", "fight"]),
    "cattle_calf": (1.45, ["stand", "alert", "run", "graze"]),
    "bighorn_ewe": (1.15, ["stand", "alert", "run", "graze"]),
    "bighorn_lamb": (0.75, ["stand", "alert", "run", "graze"]),
    "bighorn_ram": (1.4, ["stand", "alert", "run", "graze", "fight"]),
    "bison": (2.65, ["stand", "alert", "run", "graze", "fight"]),
    "bison_calf": (1.35, ["stand", "alert", "run", "graze"]),
    "hare": (0.6, ["stand", "alert", "run", "graze"]),
    "hare_young": (0.42, ["stand", "alert", "run", "graze"]),
    "marmot": (0.7, ["stand", "alert", "run", "graze"]),
    "marmot_young": (0.5, ["stand", "alert", "run", "graze"]),
    "beaver": (0.85, ["stand", "alert", "run", "graze"]),
    "beaver_kit": (0.55, ["stand", "alert", "run", "graze"]),
    # 駝鹿殘骸（2026-11-08 ChatGPT，躺著、肋骨露出）→ hd_carcass_moose（取代馬鹿殘骸調色的備案）
    "carcass_moose": (2.4, ["stand"]),  # 四腳伸直，身體只佔寬度約七成 → 比站姿寬一些
    # 北美馴鹿、大角羊的殘骸（2026-11-08 ChatGPT，躺著、肋骨露出）。馴鹿頭在左 → 翻轉（SPECIAL）
    "carcass_caribou": (1.9, ["stand"]),
    "carcass_bighorn": (1.6, ["stand"]),
    # 馬鹿（母）、白尾鹿（母）、野牛的殘骸（2026-11-08 ChatGPT；取代 PixelLab 與調色的暫用版）
    "carcass_elk": (2.0, ["stand"]),
    "carcass_deer": (1.5, ["stand"]),
    "carcass_bison": (2.6, ["stand"]),
    # 公馬鹿、白尾鹿雄鹿的殘骸（2026-11-08 ChatGPT 畫在同一張，SPECIAL 分別裁）：含鹿角比母的寬
    "carcass_elk_bull": (2.3, ["stand"]),
    "carcass_deer_buck": (1.6, ["stand"]),
    # 公駝鹿的殘骸（2026-11-08）：駝鹿在資料裡沒有雄性階段，先備好圖（carcass.hd 的 moose.buck），要遊戲記下性別才會用到
    "carcass_moose_bull": (2.6, ["stand"]),
    # 北美馴鹿母鹿的殘骸（2026-11-08）：鹿群多半是母鹿 → 當馴鹿的預設殘骸；原本那張（公鹿，大鹿角）改當 caribou.buck，等遊戲記下性別
    "carcass_caribou_cow": (1.7, ["stand"]),
    # 騾鹿母鹿、雄鹿的殘骸（2026-11-09 ChatGPT；原本借白尾鹿的）
    "carcass_mule_deer": (1.55, ["stand"]),
    "carcass_mule_deer_buck": (1.65, ["stand"]),
    # carcass_deer_buck_v2.jpg：白尾鹿雄鹿的另一版（旁邊多畫了一副掉落的鹿角），沒有用
}
# 特別處理的姿勢（動物_姿勢 → 設定）：file 來源檔、crop 先裁（像素，左上右下）、flip 水平翻轉（面向左的）、
# cells 直接指定寬幾格（同一張裡畫的大小不同、或畫布不是 1024 時，照身體長度目測）、match 顏色照站那張的色盤（prep_wolf.match_palette）
SPECIAL = {
    "carcass_caribou_stand": {"flip": True},
    "carcass_elk_bull_stand": {"file": "carcass_bulls_sheet.jpg", "crop": (0, 0, 1264, 500)},
    "carcass_deer_buck_stand": {"file": "carcass_bulls_sheet.jpg", "crop": (400, 395, 1264, 843)},
    # 馴鹿：Gemini 把「正面看著你」和「跑」和一副浮著的鹿角畫在同一張（左上那隻腳下還有一條黑線）→ 分別裁出來
    "caribou_alert": {"file": "caribou_sheet_alert_run.jpg", "crop": (0, 0, 590, 592), "cells": 1.45},
    "caribou_run": {"file": "caribou_sheet_alert_run.jpg", "crop": (0, 335, 1024, 1024), "cells": 1.9},
    # 低頭吃草：面向左、1408×768、毛色偏紅褐 → 翻轉、照站那張調色
    # 野兔跑：1256×848（使用者附真實照片當參考才畫對），身體畫得比較大 → 照身體長度指定
    "hare_run": {"cells": 0.78},
    # 大角羊小羊：吃草還沒有圖，先用母羊吃草那張縮小
    "bighorn_lamb_graze": {"file": "bighorn_ewe_graze.jpg", "cells": 0.8},
    "pronghorn_kid_run": {"cells": 1.1},
    "bison_calf_alert": {"cells": 1.2},
    # 小旱獺：四張畫布大小不同（警覺 1109×944、其他 1408×768），身體畫得差不多大 → 警覺照身高對齊
    "marmot_young_alert": {"cells": 0.36},
    "hare_young_run": {"cells": 0.58},
    "deer_doe_graze": {"cells": 1.2},
    "deer_doe_run": {"cells": 1.45},
    # 白尾鹿雄鹿：四張都是 1408×768，但站那張畫得比其他三張小 → 其他三張照身體長度指定
    "deer_buck_alert": {"cells": 1.5},
    "deer_buck_graze": {"cells": 1.5},
    "deer_buck_run": {"cells": 1.7},
    "caribou_graze": {"file": "caribou_graze_left.jpg", "flip": True, "cells": 1.95, "match": True},
}
# 要清掉沙土的圖（範圍比例，左上右下）：沙土是偏暖的淺褐色（紅比藍多 18 以上、亮），腿是灰白色、蹄是黑的，不受影響
CLEAN_DUST = {"bighorn_ewe_run": (0.0, 0.7, 0.4, 1.0), "cattle_cow_run": (0.0, 0.75, 1.0, 1.0)}
# 要清掉草的圖 → 範圍（左、上、右、下，比例）。吃草那張 Gemini 另外多畫了一顆浮著的鹿頭：沒連在身上，「只留最大的一塊」就去掉了
CLEAN_GRASS = {}  # 例："mule_deer_buck_graze": (0.44, 0.76, 1.0, 1.0)（第一版吃草那張，現在換成重畫的乾淨版；舊的留在 mule_deer_buck_graze_v1_grass.jpg）



def remove_grass(c, box, gmin=3, keep_min=60, gap=14, opening=4):
    """Gemini 順手畫的草（2026-11-06 騾鹿公鹿低頭吃草那張）：box（比例）裡
    1. 偏綠（綠比紅多 gmin 以上；鹿毛是暖灰色、紅 ≥ 綠）的去掉；
    2. 旁邊沒有亮色像素的深色線條（草葉的輪廓）去掉；
    3. 形態學 opening 去掉比 2×opening 細的線條（草葉；腳、蹄子很粗）；
    4. 小於 keep_min 的碎塊去掉；被草蓋住的短空隙（gap 以內）用上面的顏色補。"""
    p=c.load(); w,h=c.size
    x0,y0,x1,y1=[int(v) for v in (box[0]*w,box[1]*h,box[2]*w,box[3]*h)]
    for y in range(y0,y1):
        for x in range(x0,x1):
            r,g,b,a=p[x,y]
            if a and g>r+gmin:
                p[x,y]=(0,0,0,0)
    for it in range(4):
        rm=[]
        for y in range(y0,y1):
            for x in range(x0,x1):
                r,g,b,a=p[x,y]
                if not a or max(r,g,b)>=75: continue
                ok=False
                for dx in (-1,0,1):
                    for dy in (-1,0,1):
                        xx,yy=x+dx,y+dy
                        if 0<=xx<w and 0<=yy<h:
                            q=p[xx,yy]
                            if q[3] and max(q[:3])>=75: ok=True
                if not ok: rm.append((x,y))
        for x,y in rm: p[x,y]=(0,0,0,0)
    # 細線（草葉）：框內做形態學 opening（侵蝕 n 次再膨脹 n 次，只在原本有的像素裡），比 2n 細的線條會消失；腳、蹄子很粗不受影響
    n=opening
    mask={(x,y) for y in range(y0,y1) for x in range(x0,x1) if p[x,y][3]}
    cur=set(mask)
    for _ in range(n):
        cur={(x,y) for (x,y) in cur if all((x+dx,y+dy) in cur or not (x0<=x+dx<x1 and y0<=y+dy<y1) for dx,dy in ((1,0),(-1,0),(0,1),(0,-1)))}
    for _ in range(n):
        cur=cur|{(x+dx,y+dy) for (x,y) in cur for dx,dy in ((1,0),(-1,0),(0,1),(0,-1)) if (x+dx,y+dy) in mask}
    for xy in mask-cur:
        p[xy[0],xy[1]]=(0,0,0,0)
    # 碎塊：留下夠大的（蹄子、腳的下半截），丟掉草的殘線
    from collections import deque
    seen=[[False]*w for _ in range(h)]
    for y in range(h):
        for x in range(w):
            if seen[y][x] or not p[x,y][3]: continue
            comp=[]; q=deque([(x,y)]); seen[y][x]=True
            while q:
                cx,cy=q.popleft(); comp.append((cx,cy))
                for nx,ny in ((cx+1,cy),(cx-1,cy),(cx,cy+1),(cx,cy-1)):
                    if 0<=nx<w and 0<=ny<h and not seen[ny][nx] and p[nx,ny][3]:
                        seen[ny][nx]=True; q.append((nx,ny))
            if len(comp)<keep_min:
                for cx,cy in comp: p[cx,cy]=(0,0,0,0)
    # 被草蓋住的空隙：同一行上下 gap 像素內都有東西時，用上面的顏色補
    for x in range(x0,x1):
        y=y0
        while y<y1:
            if p[x,y][3]:
                y+=1; continue
            top=y-1
            yy=y
            while yy<y1 and not p[x,yy][3]: yy+=1
            if top>=0 and p[x,top][3] and yy<y1 and yy-y<=gap:
                for k in range(y,yy): p[x,k]=p[x,top]
            y=yy
    return c.crop(c.getbbox())


def _load(animal, pose):
    sp = SPECIAL.get("%s_%s" % (animal, pose), {})
    path = os.path.join(SRC, sp.get("file", "%s_%s.jpg" % (animal, pose)))
    if not os.path.exists(path) and os.path.exists(path[:-4] + ".png"):
        path = path[:-4] + ".png"
    if "crop" in sp or sp.get("flip"):
        im = Image.open(path).convert("RGB")
        if "crop" in sp:
            im = im.crop(sp["crop"])
        if sp.get("flip"):
            from PIL import ImageOps
            im = ImageOps.mirror(im)
        tmp = os.path.join(SRC, "_tmp.png")
        im.save(tmp)
        c = pg.cut(tmp, "green")
        os.remove(tmp)
        return c
    return pg.cut(path, "green")


def main():
    for animal, spec in ANIMALS.items():
        cells, poses = spec[0], spec[1]
        src_animal = spec[2] if len(spec) > 2 else animal
        cuts = {p: _load(src_animal, p) for p in poses}
        for p in poses:
            dbox = CLEAN_DUST.get("%s_%s" % (animal, p))
            if dbox:
                c = cuts[p]
                px = c.load()
                w, h = c.size
                for y in range(int(dbox[1] * h), int(dbox[3] * h)):
                    for x in range(int(dbox[0] * w), int(dbox[2] * w)):
                        r, g, b, a = px[x, y]
                        if a and r - b > 18 and r > 110:
                            px[x, y] = (0, 0, 0, 0)
                keep = pg.largest_blob([px[i % w, i // w][3] > 0 for i in range(w * h)], w, h)
                for i in range(w * h):
                    if not keep[i]:
                        px[i % w, i // w] = (0, 0, 0, 0)
                cuts[p] = c.crop(c.getbbox())
            box = CLEAN_GRASS.get("%s_%s" % (animal, p))
            if box:
                c = remove_grass(cuts[p], box)
                w, h = c.size
                keep = pg.largest_blob([c.getpixel((i % w, i // w))[3] > 0 for i in range(w * h)], w, h)
                px = c.load()
                for i in range(w * h):
                    if not keep[i]:
                        px[i % w, i // w] = (0, 0, 0, 0)
                cuts[p] = c.crop(c.getbbox())
        px_per_cell = cuts["stand"].width / cells
        for p, c in cuts.items():
            sp = SPECIAL.get("%s_%s" % (animal, p), {})
            if sp.get("match"):
                c = pw.match_palette(c, cuts["stand"])
            name = "hd_%s" % animal if p == "stand" else "hd_%s_%s" % (animal, p)
            for d in pg.DENSITIES:
                cw = float(sp["cells"]) if "cells" in sp else c.width / px_per_cell
                out = pw.outline(pg.shrink(c, round(cw * d)))
                out.save(os.path.join(pg.OUT, "%s_%d.png" % (name, d)))
                print(name, d, out.size)


if __name__ == "__main__":
    main()
