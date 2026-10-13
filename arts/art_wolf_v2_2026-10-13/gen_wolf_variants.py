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
    # 狼的體型：胸深、頸部有厚鬃毛、頭大口鼻寬、腿粗、尾巴蓬鬆直垂（和郊狼的細瘦區分）
    frame=(48, 32), ground=30, split=27, file='wolf',
    body=[(9, 19), (11, 15), (17, 13), (26, 13), (31, 11), (36, 12), (38, 17), (37, 22), (30, 23), (18, 22), (11, 21)],
    neck=[(28, 13), (34, 6), (39, 13), (36, 22)],
    head=[(34, 8), (37, 5), (41, 5), (43, 7), (47, 9), (49, 10), (49, 12), (45, 13), (40, 14), (36, 13)],
    jaw=[(44, 12), (48, 12), (47, 14), (44, 13)],
    ears=[[(36, 6), (37, 1), (40, 5)], [(39, 5), (41, 0), (42, 6)]],
    eye=(41, 7), nose=(49, 10),
    legs=[('far', (32, 20), 4, 3, 1), ('far', (15, 20), 5, 3, -1), ('near', (34, 20), 4, 4, 1), ('near', (13, 20), 6, 4, -1)],
    paw=2, tail=[(10, 16), (6, 19), (5, 23), (5, 27)], tail_w=6, tail_tip=3)


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


def variant(colors, belly, back, patches, **extra):
    sp = dict(BASE)
    sp.update(colors=colors, belly=belly, back=back, patches=patches, grizzle=True, **extra)
    return shift(sp, -2)


# 臉頰與喉部的淡色（跟著頭）、眉上的深色（跟著頭）
CHEEK = [(36, 10), (41, 12), (42, 14), (38, 18), (34, 16)]
BROW = [(38, 6), (42, 6), (42, 7), (38, 7)]

VARIANTS = {
    'A': variant({BODY: (150, 126, 96), HEAD: (138, 118, 92), EAR: (96, 84, 72), LEG: (222, 206, 176), FARLEG: (176, 160, 134),
                  PAW: (232, 220, 196), MUZZLE: (230, 218, 192), TAIL: (112, 104, 96), TAILTIP: (32, 30, 30)},
                 belly=(226, 212, 182), back=(90, 84, 78),
                 patches=[((226, 214, 188), CHEEK, True), ((70, 62, 56), BROW, True),
                          ((170, 150, 116), [(18, 16), (24, 15), (25, 21), (19, 22)], False)]),
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
                 patches=[((238, 224, 196), [(34, 11), (40, 13), (42, 16), (39, 22), (34, 22), (31, 16)], True),
                          ((84, 72, 64), BROW, True)]),
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
