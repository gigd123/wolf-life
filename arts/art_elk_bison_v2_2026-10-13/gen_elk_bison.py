#!/usr/bin/env python3
# 馬鹿、美洲野牛重畫（2026-10-13，使用者提供參考圖），沿用 arts/art_predators_v2_2026-10-13/gen_predators.py 的繪製器，
# 照和灰狼（約 46×30 像素）的真實比例畫：母鹿約狼的 2 倍高、公鹿含鹿角約 2.6 倍、野牛約 2 倍高 3 倍長。
# 馬鹿：紅褐色身體、深棕色的脖子鬃毛與腿、淡色臀斑、公鹿往後展開的分叉大角；小鹿帶白斑。
# 野牛：很高的肩峰、低垂的大頭、深色的頭與前身（鬃毛、鬍鬚、前腿）、肩上淺褐色披毛、較窄的後半身、短的上彎角、尾端一撮毛；
# 小野牛橘紅色、沒有肩峰。
# 用法：在專案根目錄 python3 arts/art_elk_bison_v2_2026-10-13/gen_elk_bison.py [--preview]
import sys
sys.path.insert(0, 'arts/art_predators_v2_2026-10-13')
import gen_predators as gp
from gen_predators import (BODY, HEAD, EAR, LEG, FARLEG, PAW, MUZZLE, TAIL, TAILTIP, ANTLER, ANTLER_TIP, HORN)
from PIL import Image

OUT = 'assets/art/sprites/animals/'
ARCH = 'arts/art_elk_bison_v2_2026-10-13/'

ELK_COLORS = {BODY: (178, 120, 72), HEAD: (100, 64, 42), EAR: (120, 80, 54), LEG: (94, 62, 42), FARLEG: (72, 48, 34),
              PAW: (40, 30, 26), MUZZLE: (58, 42, 34), TAIL: (214, 186, 136), TAILTIP: (200, 170, 120),
              ANTLER: (150, 120, 88), ANTLER_TIP: (230, 218, 194)}

ELK_BULL = dict(
    frame=(96, 84), ground=82, split=60, file='elk_bull',
    body=[(28, 44), (29, 38), (38, 35), (52, 35), (62, 34), (68, 36), (72, 44), (71, 53), (64, 58), (44, 59), (32, 58), (28, 52)],
    neck=[(56, 38), (70, 20), (80, 24), (72, 52)],
    head=[(71, 20), (75, 16), (80, 16), (84, 20), (88, 25), (88, 29), (84, 30), (79, 27), (74, 26), (71, 24)],
    jaw=[(83, 27), (87, 28), (86, 30), (83, 29)],
    ears=[[(74, 19), (68, 15), (72, 18)]],
    eye=(79, 20), nose=(88, 26), muzzle_x=86,
    legs=[('far', (64, 55), 6, 3, 1), ('far', (35, 55), 7, 3, -2), ('near', (67, 55), 6, 3, 1), ('near', (32, 55), 8, 3, -2)],
    paw=2, tail=[(29, 40), (27, 44)], tail_w=3, tail_tip=2,
    colors=ELK_COLORS,
    belly=(96, 64, 44), belly_frac=0.84, back=(188, 132, 82),
    # 臀斑（淡色）、脖子下垂的深色鬃毛
    patches=[((216, 188, 138), [(28, 39), (33, 36), (35, 45), (31, 53), (28, 50)], False),
             ((80, 52, 36), [(64, 40), (72, 26), (78, 30), (74, 52), (66, 56)], True)],
    # 鹿角：兩支主枝往後上方展開，每支 3 個往上的分叉
    antlers=[[(76, 16), (72, 8), (66, 3), (58, 1)], [(74, 12), (80, 6)], [(70, 6), (73, 0)], [(64, 3), (63, 0)],
             [(79, 16), (76, 8), (70, 3), (63, 1)], [(77, 12), (83, 7)], [(74, 6), (77, 0)]],
    antler_w=2)


def scaled(sp, k, frame, ground, file, drop=()):
    """把一種的座標縮放（母鹿、小鹿）。"""
    out = dict(sp)
    fx = lambda p: (round(p[0] * k), round(ground - (sp['ground'] - p[1]) * k))
    for key in ('body', 'neck', 'head', 'jaw', 'tail'):
        if out.get(key):
            out[key] = [fx(p) for p in sp[key]]
    out['ears'] = [[fx(p) for p in e] for e in sp['ears']]
    out['eye'] = fx(sp['eye']); out['nose'] = fx(sp['nose'])
    out['muzzle_x'] = fx((sp['muzzle_x'], 0))[0]
    out['legs'] = [(s_, fx(a), max(2, round(wt * k)), max(2, round(wb * k)), b) for s_, a, wt, wb, b in sp['legs']]
    out['patches'] = [(c, [fx(p) for p in pts], h) for c, pts, h in sp.get('patches', [])]
    for key in ('antlers', 'horns'):
        if sp.get(key):
            out[key] = [[fx(p) for p in line] for line in sp[key]]
    out['split'] = round(sp['split'] * k)
    out['frame'] = frame; out['ground'] = ground; out['file'] = file
    for key in drop:
        out.pop(key, None)
    return out


ELK_COW = scaled(ELK_BULL, 0.88, (88, 64), 62, 'elk_cow', drop=('antlers',))
ELK_COW['colors'] = {**ELK_COLORS, HEAD: (124, 82, 54)}
ELK_COW['patches'] = [ELK_COW['patches'][0], ((108, 72, 48), ELK_COW['patches'][1][1], True)]
ELK_CALF = scaled(ELK_BULL, 0.56, (56, 44), 42, 'elk_calf', drop=('antlers',))
ELK_CALF['colors'] = {**ELK_COLORS, BODY: (176, 124, 78), HEAD: (150, 104, 66)}
ELK_CALF['patches'] = [ELK_CALF['patches'][0]]
ELK_CALF.update(spots=(236, 226, 206), many_spots=True, spot_area=(19, 38, 19, 28), spot_count=14)

BISON = dict(
    frame=(104, 64), ground=62, split=56, file='bison',
    body=[(18, 41), (20, 31), (28, 27), (40, 25), (50, 18), (57, 9), (66, 6), (74, 10), (80, 18), (84, 28), (84, 40), (78, 48),
          (64, 50), (40, 49), (24, 48), (19, 46)],
    neck=[(76, 16), (82, 20), (84, 40), (78, 44)],
    head=[(78, 22), (86, 22), (92, 28), (96, 34), (98, 40), (96, 45), (90, 47), (84, 46), (80, 40), (78, 30)],
    jaw=[(92, 43), (97, 43), (96, 45), (92, 45)],
    ears=[[(85, 27), (81, 28), (84, 30)]],
    eye=(90, 31), nose=(98, 40), muzzle_x=96,
    legs=[('far', (70, 47), 6, 4, 0), ('far', (30, 45), 6, 4, -1), ('near', (75, 47), 8, 5, 0), ('near', (26, 45), 7, 4, -1)],
    paw=2, tail=[(19, 34), (16, 40), (16, 47)], tail_w=2, tail_tip=3,
    colors={BODY: (112, 76, 50), HEAD: (46, 34, 28), EAR: (52, 38, 30), LEG: (54, 40, 32), FARLEG: (40, 30, 24),
            PAW: (30, 24, 20), MUZZLE: (74, 66, 62), TAIL: (100, 70, 46), TAILTIP: (40, 30, 24), HORN: (222, 212, 192)},
    back=(126, 86, 56), grizzle=True,
    # 肩上的淺褐色披毛、前身的深色鬃毛、下巴的鬍鬚
    patches=[((172, 114, 64), [(42, 25), (50, 18), (57, 9), (66, 6), (74, 10), (77, 18), (72, 30), (60, 36), (48, 33)], False),
             ((62, 44, 34), [(74, 10), (80, 18), (84, 28), (84, 42), (78, 48), (70, 47), (71, 32), (76, 22)], False),
             ((44, 32, 26), [(84, 44), (91, 46), (89, 55), (84, 52)], True)],
    horns=[[(86, 25), (87, 20), (90, 18)]])

BISON_CALF = dict(
    frame=(56, 40), ground=38, split=30, file='bison_calf',
    body=[(12, 26), (13, 20), (18, 17), (28, 17), (35, 17), (39, 20), (40, 26), (36, 29), (20, 29), (13, 28)],
    neck=[(34, 18), (40, 16), (41, 25), (37, 27)],
    head=[(38, 18), (43, 17), (47, 21), (50, 26), (49, 29), (45, 30), (40, 26)],
    jaw=[(46, 28), (49, 28), (49, 29), (46, 29)],
    ears=[[(42, 19), (39, 20), (41, 21)]],
    eye=(44, 21), nose=(50, 26), muzzle_x=48,
    legs=[('far', (34, 27), 4, 3, 0), ('far', (17, 27), 4, 3, -1), ('near', (36, 27), 4, 3, 0), ('near', (15, 27), 5, 3, -1)],
    paw=2, tail=[(13, 21), (11, 26)], tail_w=2, tail_tip=2,
    colors={BODY: (184, 112, 60), HEAD: (170, 102, 56), EAR: (150, 90, 50), LEG: (160, 96, 52), FARLEG: (130, 78, 42),
            PAW: (60, 40, 30), MUZZLE: (110, 70, 46), TAIL: (170, 104, 58), TAILTIP: (90, 58, 38)},
    back=(196, 124, 70))

ALL = [ELK_BULL, ELK_COW, ELK_CALF, BISON, BISON_CALF]


def preview(path):
    wolf = Image.open('assets/art/sprites/wolf/wolf_adult_sheet.png').convert('RGBA')
    rows = [[wolf.crop((0, 0, 48, 32)), wolf.crop((0, 32, 48, 64)), wolf.crop((96, 32, 144, 64))]]
    for sp in ALL:
        rows.append([gp.draw_frame(sp, 'idle', 0), gp.draw_frame(sp, 'move', 0), gp.draw_frame(sp, 'move', 2)])
    W = max(sum(f.width + 6 for f in r) for r in rows) + 6
    H = sum(max(f.height for f in r) + 6 for r in rows) + 6
    out = Image.new('RGBA', (W, H), (96, 116, 96, 255))
    y = 6
    for r in rows:
        h = max(f.height for f in r); x = 6
        for f in r:
            out.alpha_composite(f, (x, y + h - f.height)); x += f.width + 6
        y += h + 6
    out.resize((W * 4, H * 4), Image.NEAREST).save(path)


def trim(im):
    bb = im.getbbox()
    return im.crop(bb) if bb else im


def save(im, name):
    im.save(OUT + name + '.png')
    im.save(ARCH + name + '_1x.png')
    im.resize((im.width * 4, im.height * 4), Image.NEAREST).save(ARCH + name + '_4x.png')


def herd(members, size=(114, 42)):
    """成群圖：幾隻待機圖縮小、前後錯開（遠看的一群）。members = [(種, 縮放, x, 底部 y)]，後面的先畫。"""
    out = Image.new('RGBA', size, (0, 0, 0, 0))
    for sp, k, x, by in members:
        im = trim(gp.draw_frame(sp, 'idle', 0))
        im = im.resize((max(1, round(im.width * k)), max(1, round(im.height * k))), Image.NEAREST)
        out.alpha_composite(im, (x, by - im.height))
    return out


def actions(sp):
    """反擊與受傷：馬鹿抬起前身用前蹄踢，野牛低頭衝撞。"""
    # 抬起前身時上方多留 12 像素，鹿角才不會被格子切掉
    fw, fh = sp['frame']
    tall = scaled(sp, 1.0, (fw, fh + 12), sp['ground'] + 12, sp['file'])
    tall['colors'] = sp['colors']
    attack = gp.draw_frame(tall, 'charge') if sp['file'].startswith('bison') else gp.draw_frame(tall, 'swipe2')
    return trim(attack), trim(gp.draw_frame(sp, 'hurt'))


def preview_actions(path):
    rows = [[a for a in actions(sp)] for sp in [ELK_BULL, ELK_COW, BISON]]
    rows.append([herd_elk(), herd_bison()])
    W = max(sum(f.width + 6 for f in r) for r in rows) + 6
    H = sum(max(f.height for f in r) + 6 for r in rows) + 6
    out = Image.new('RGBA', (W, H), (96, 116, 96, 255))
    y = 6
    for r in rows:
        h = max(f.height for f in r); x = 6
        for f in r:
            out.alpha_composite(f, (x, y + h - f.height)); x += f.width + 6
        y += h + 6
    out.resize((W * 4, H * 4), Image.NEAREST).save(path)


def herd_elk():
    return herd([(ELK_COW, 0.42, 4, 36), (ELK_COW, 0.42, 62, 34), (ELK_BULL, 0.42, 30, 40), (ELK_COW, 0.42, 78, 41),
                 (ELK_CALF, 0.42, 14, 42)])


def herd_bison():
    return herd([(BISON, 0.36, 2, 34), (BISON, 0.36, 66, 33), (BISON, 0.36, 34, 41), (BISON_CALF, 0.4, 84, 42)])


if __name__ == '__main__':
    if '--preview' in sys.argv:
        preview(ARCH + 'preview_basic.png')
        sys.exit(0)
    if '--preview-actions' in sys.argv:
        preview_actions(ARCH + 'preview_actions.png')
        sys.exit(0)
    for sp in ALL:
        fw, fh = sp['frame']
        sheet = Image.new('RGBA', (fw * 4, fh * 2), (0, 0, 0, 0))
        for i in range(4):
            sheet.alpha_composite(gp.draw_frame(sp, 'idle', i), (i * fw, 0))
            sheet.alpha_composite(gp.draw_frame(sp, 'move', i), (i * fw, fh))
        save(sheet, sp['file'] + '_sheet')
        if sp in (ELK_BULL, ELK_COW, BISON):
            atk, hurt = actions(sp)
            save(atk, sp['file'] + '_attack'); save(hurt, sp['file'] + '_hurt')
    save(herd_elk(), 'elk_herd')
    save(herd_bison(), 'bison_herd')
    print('done')
