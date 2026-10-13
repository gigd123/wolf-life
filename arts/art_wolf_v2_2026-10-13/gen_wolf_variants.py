#!/usr/bin/env python3
# 灰狼重畫的候選版本（2026-10-13，使用者提供 4 張概念圖，選一版後再同步到灰狼三個生命階段、黑狼、苔原狼、挑戰者）。
# 沿用 arts/art_predators_v2_2026-10-13/gen_predators.py 的繪製器；體型和目前的灰狼一樣（48×32 格、約 46×30 像素），比例不變。
# A 歐亞灰狼（概念圖 1）、B 銀灰（概念圖 2）、C 淡褐（概念圖 3）、D 暖色風格（概念圖 4）。
# 用法：在專案根目錄 python3 arts/art_wolf_v2_2026-10-13/gen_wolf_variants.py
import sys
sys.path.insert(0, 'arts/art_predators_v2_2026-10-13')
import gen_predators as gp
from gen_predators import BODY, HEAD, EAR, LEG, FARLEG, PAW, MUZZLE, TAIL, TAILTIP
from PIL import Image, ImageDraw

ARCH = 'arts/art_wolf_v2_2026-10-13/'

BASE = dict(
    # 正常灰狼的均衡比例、厚實：胸深背寬、腿與尾巴粗、脖子粗短，頭低（頭頂約和背線同高）
    frame=(48, 32), ground=30, split=28, file='wolf',
    body=[(6, 14), (8, 9), (14, 7), (26, 7), (31, 6), (36, 8), (38, 13), (37, 19), (31, 21), (17, 21), (9, 20), (6, 18)],
    neck=[(29, 8), (36, 7), (39, 14), (36, 20)],
    head=[(35, 9), (38, 7), (41, 7), (43, 8), (46, 10), (47, 11), (46, 13), (42, 13), (38, 14), (35, 12)],
    jaw=[(42, 12), (46, 12), (45, 13), (42, 13)],
    ears=[[(37, 8), (38, 4), (40, 7)], [(39, 7), (41, 4), (42, 7)]],
    eye=(41, 9), nose=(47, 11),
    legs=[('far', (31, 18), 4, 4, 1), ('far', (13, 18), 5, 4, -1), ('near', (33, 18), 5, 4, 1), ('near', (11, 18), 6, 4, -1)],
    paw=2, tail=[(7, 11), (4, 15), (3, 20), (3, 25)], tail_w=6, tail_tip=3)


def shift(sp, dx):
    """整隻往左右移（鼻尖不能超出 48 像素寬的格子）。"""
    f = lambda p: (p[0] + dx, p[1])
    out = dict(sp)
    for key in ('body', 'neck', 'head', 'jaw', 'tail'):
        out[key] = [f(p) for p in sp[key]]
    out['ears'] = [[f(p) for p in e] for e in sp['ears']]
    out['eye'] = f(sp['eye']); out['nose'] = f(sp['nose'])
    out['legs'] = [(s_, f(a), wt, wb, b) for s_, a, wt, wb, b in sp['legs']]
    out['split'] = sp['split'] + dx
    if 'patches' in sp:
        out['patches'] = [(c, [f(p) for p in pts], h) for c, pts, h in sp['patches']]
    return out


def lower_head(sp, dy):
    """頭和脖子前端往下（頭微微低於背線、往前伸的走姿）。"""
    f = lambda p: (p[0], p[1] + dy)
    out = dict(sp)
    for key in ('head', 'jaw'):
        out[key] = [f(p) for p in sp[key]]
    out['ears'] = [[f(p) for p in e] for e in sp['ears']]
    out['eye'] = f(sp['eye']); out['nose'] = f(sp['nose'])
    nk = sp['neck']
    out['neck'] = [nk[0], f(nk[1]), f(nk[2]), nk[3]]
    out['patches'] = [(c, [f(p) for p in pts] if h else pts, h) for c, pts, h in sp.get('patches', [])]
    return out


def variant(colors, belly, back, patches, **extra):
    sp = dict(BASE)
    sp.update(colors=colors, belly=belly, back=back, patches=patches, grizzle=True, **extra)
    return sp


# 臉頰與喉部的淡色（跟著頭）、眉上的深色（跟著頭）
CHEEK = [(37, 10), (41, 11), (41, 13), (38, 16), (36, 15)]
BROW = [(39, 8), (42, 8), (42, 9), (39, 9)]

VARIANTS = {
    'A': variant({BODY: (150, 126, 96), HEAD: (138, 118, 92), EAR: (96, 84, 72), LEG: (222, 206, 176), FARLEG: (176, 160, 134),
                  PAW: (232, 220, 196), MUZZLE: (230, 218, 192), TAIL: (112, 104, 96), TAILTIP: (32, 30, 30)},
                 belly=(226, 212, 182), back=(90, 84, 78),
                 patches=[((226, 214, 188), CHEEK, True), ((70, 62, 56), BROW, True),
                          ((170, 150, 116), [(18, 13), (24, 12), (25, 18), (19, 19)], False)]),
    'B': variant({BODY: (152, 152, 150), HEAD: (144, 144, 142), EAR: (100, 100, 102), LEG: (220, 218, 212), FARLEG: (172, 170, 166),
                  PAW: (232, 230, 226), MUZZLE: (232, 230, 224), TAIL: (128, 128, 128), TAILTIP: (62, 62, 64)},
                 belly=(228, 226, 220), back=(108, 108, 110),
                 patches=[((232, 230, 226), CHEEK, True), ((96, 96, 98), BROW, True)]),
    'C': variant({BODY: (170, 148, 118), HEAD: (176, 154, 122), EAR: (130, 112, 90), LEG: (196, 176, 146), FARLEG: (156, 138, 112),
                  PAW: (214, 198, 170), MUZZLE: (226, 212, 186), TAIL: (156, 136, 108), TAILTIP: (86, 74, 62)},
                 belly=(224, 208, 180), back=(142, 120, 94),
                 patches=[((226, 212, 186), CHEEK, True)]),
    'D': variant({BODY: (186, 132, 82), HEAD: (150, 120, 96), EAR: (82, 70, 62), LEG: (196, 148, 96), FARLEG: (150, 110, 72),
                  PAW: (226, 206, 170), MUZZLE: (236, 222, 194), TAIL: (98, 84, 74), TAILTIP: (40, 34, 32)},
                 belly=(236, 220, 190), back=(94, 82, 74),
                 patches=[((238, 224, 196), [(35, 9), (40, 11), (41, 13), (38, 18), (34, 18), (32, 13)], True),
                          ((84, 72, 64), BROW, True)]),
}


# E：偏概念圖 1（對比強：深灰背鞍、褐色體側帶米黃色塊、米白四肢、白頰、耳緣深色、尾巴深色帶黑尖）
# F：偏概念圖 3（柔和：灰褐偏黃、淡色腹部與四肢、背部稍深、白頰）
SADDLE = [(18, 7), (31, 6), (36, 8), (37, 12), (30, 13), (20, 11)]
VARIANTS = {
    'E': lower_head(variant({BODY: (142, 120, 92), HEAD: (152, 126, 94), EAR: (112, 92, 72), LEG: (226, 212, 180),
                             FARLEG: (180, 164, 136), PAW: (236, 226, 204), MUZZLE: (232, 222, 200), TAIL: (104, 98, 92),
                             TAILTIP: (28, 26, 26)},
                            belly=(228, 214, 184), back=(78, 76, 74),
                            patches=[((92, 90, 90), SADDLE, False), ((200, 178, 132), [(19, 10), (22, 9), (25, 18), (21, 19)], False),
                                     ((238, 232, 220), CHEEK, True), ((70, 60, 52), BROW, True)]), 1),
    'F': lower_head(variant({BODY: (176, 154, 124), HEAD: (178, 156, 124), EAR: (120, 102, 82), LEG: (214, 198, 170),
                             FARLEG: (168, 152, 126), PAW: (226, 214, 192), MUZZLE: (232, 222, 200), TAIL: (158, 138, 110),
                             TAILTIP: (88, 74, 62)},
                            belly=(230, 218, 194), back=(146, 124, 98),
                            patches=[((154, 134, 108), SADDLE, False), ((234, 224, 204), CHEEK, True)]), 1),
}


def row(frames, label):
    W = sum(f.width + 6 for f in frames) + 6
    H = max(f.height for f in frames) + 14
    out = Image.new('RGBA', (W, H), (96, 116, 96, 255))
    x = 6
    for f in frames:
        out.alpha_composite(f, (x, H - f.height - 2)); x += f.width + 6
    ImageDraw.Draw(out).text((2, 0), label, fill=(255, 255, 255))
    return out


if __name__ == '__main__':
    rows = []
    cur = Image.open('assets/art/sprites/wolf/wolf_adult_sheet.png').convert('RGBA')
    rows.append(row([cur.crop((0, 0, 48, 32)), cur.crop((0, 32, 48, 64)), cur.crop((96, 32, 144, 64))], 'now'))
    for k, sp in VARIANTS.items():
        rows.append(row([gp.draw_frame(sp, 'idle', 0), gp.draw_frame(sp, 'move', 0), gp.draw_frame(sp, 'move', 2),
                         gp.draw_frame(sp, 'attack')], k))
    W = max(r.width for r in rows); H = sum(r.height for r in rows)
    out = Image.new('RGBA', (W, H), (96, 116, 96, 255)); y = 0
    for r in rows:
        out.alpha_composite(r, (0, y)); y += r.height
    out.resize((W * 5, H * 5), Image.NEAREST).save(ARCH + 'preview_variants.png')
    print('done')
