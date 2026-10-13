#!/usr/bin/env python3
# 郊狼、美洲獅、灰熊、黑熊、加拿大猞猁重畫（2026-10-13，使用者提供參考圖）：照和灰狼（約 46×30 像素）的真實比例畫，
# 狩獵與戰鬥畫面用固定像素倍率顯示，所以像素大小就是相對體型（郊狼、猞猁較小，美洲獅、黑熊和狼差不多，灰熊明顯大）。
# 每種動物用多邊形定義輪廓（身體、頭含楔形口鼻與下顎、耳朵、尾巴），腿是上粗下細的兩段；
# 動作（走路、撲咬、受傷、威嚇、熊的揮掌）只移動前半身與腿。上色：材質底色、上亮下暗、淡色的腹部與喉部、
# 毛紋（郊狼與灰熊背上的淡色毛尖、猞猁的斑點）、深色外框。
# 產生：spritesheet（idle、move 各 4 格；熊多一列 attack 揮掌 4 格）與單張姿勢（bite 撲咬、hurt 受傷，美洲獅多 threaten），
# 檔名沿用原本的，存到 assets/art/sprites/animals/，_1x／_4x 存到這個資料夾。
# 用法：在專案根目錄 python3 arts/art_predators_v2_2026-10-13/gen_predators.py
from PIL import Image, ImageDraw

OUT = 'assets/art/sprites/animals/'
ARCH = 'arts/art_predators_v2_2026-10-13/'

FARLEG, TAIL, BODY, HEAD, EAR, LEG, TUFT, TAILTIP, PAW, MUZZLE = range(1, 11)

# 座標都是 idle 時的位置（y 往下），ground 是腳底。split：x 大於這個值的屬於前半身（動作時一起移動）。
SPECIES = {
    'coyote': dict(
        frame=(48, 32), ground=30, split=26, file='coyote',
        body=[(9, 19), (11, 16), (16, 15), (24, 15), (30, 14), (33, 16), (34, 19), (32, 22), (25, 23), (16, 23), (11, 22)],
        head=[(32, 13), (35, 9), (38, 9), (40, 11), (45, 12), (45, 14), (41, 15), (37, 16), (33, 17)],
        jaw=[(39, 14), (44, 14), (43, 16), (39, 16)],
        ears=[[(34, 10), (35, 4), (37, 9)], [(36, 9), (38, 3), (39, 9)]],
        neck=[(28, 15), (34, 10), (36, 16), (32, 20)],
        eye=(38, 11), nose=(45, 12),
        legs=[('far', (29, 20), 3, 2, 1), ('far', (16, 20), 3, 2, -1), ('near', (31, 20), 3, 2, 1), ('near', (14, 20), 4, 2, -1)],
        paw=2, tail=[(11, 17), (8, 20), (6, 24), (6, 28)], tail_w=4, tail_tip=3,
        colors={BODY: (152, 134, 112), HEAD: (160, 138, 110), EAR: (150, 106, 72), LEG: (180, 124, 76),
                FARLEG: (142, 96, 62), TAIL: (148, 130, 108), TAILTIP: (44, 38, 34), PAW: (156, 108, 68), MUZZLE: (226, 212, 188)},
        belly=(224, 210, 186), back=(118, 104, 90), grizzle=True),
    'lynx': dict(
        # 照使用者的參考圖（短尾貓的樣子）：黃褐帶灰、斑點明顯、白色胸腹、臉頰毛有黑紋、黑耳背與黑耳簇、短尾上黑下白；四肢粗壯、大掌
        frame=(48, 32), ground=30, split=25, file='lynx',
        body=[(13, 18), (15, 14), (22, 13), (29, 13), (32, 15), (33, 19), (31, 22), (24, 23), (17, 22), (13, 21)],
        head=[(31, 11), (33, 7), (37, 6), (40, 8), (41, 11), (40, 14), (37, 15), (33, 15)],
        jaw=[(37, 13), (40, 13), (39, 15), (37, 15)],
        ruff=[(31, 12), (32, 17), (35, 18), (38, 16), (36, 14)], ruff_stripes=[[(33, 14), (34, 16)]],
        neck=[(27, 14), (32, 9), (34, 15), (31, 19)],
        ears=[[(32, 8), (34, 3), (36, 7)], [(36, 7), (38, 2), (40, 7)]],
        tufts=[[(34, 3), (34, 1)], [(38, 2), (38, 0)]],
        eye=(38, 9), nose=(41, 11),
        legs=[('far', (29, 20), 4, 4, 1), ('far', (18, 20), 5, 4, -1), ('near', (31, 20), 5, 4, 1), ('near', (16, 20), 6, 4, -1)],
        paw=4, tail=[(14, 15), (11, 17), (10, 19)], tail_w=3, tail_tip=2, tail_under=(238, 232, 220),
        colors={BODY: (186, 152, 112), HEAD: (190, 158, 118), EAR: (150, 118, 88), LEG: (184, 150, 112),
                FARLEG: (150, 122, 92), TAIL: (182, 148, 108), TAILTIP: (30, 26, 24), TUFT: (30, 26, 24),
                PAW: (210, 190, 160), MUZZLE: (240, 234, 222)},
        belly=(238, 232, 220), back=(166, 134, 100), spots=(112, 82, 58), many_spots=True, legs_behind=True),
    'cougar': dict(
        frame=(72, 32), ground=30, split=40, file='cougar',
        body=[(20, 17), (23, 11), (30, 10), (40, 10), (46, 9), (51, 11), (53, 16), (50, 21), (40, 22), (30, 22), (23, 21)],
        head=[(49, 8), (52, 5), (57, 5), (59, 7), (63, 9), (63, 12), (60, 14), (55, 15), (50, 14)],
        jaw=[(58, 12), (62, 12), (61, 14), (58, 14)],
        neck=[(44, 11), (50, 7), (52, 14), (48, 19)],
        ears=[[(51, 6), (53, 2), (55, 5)]],
        eye=(57, 7), nose=(63, 9),
        legs=[('far', (46, 18), 5, 4, 1), ('far', (27, 18), 6, 4, -1), ('near', (48, 18), 6, 5, 1), ('near', (25, 18), 7, 5, -1)],
        paw=3, tail=[(21, 15), (16, 18), (11, 23), (7, 26), (3, 26), (1, 23), (2, 19)], tail_w=5, tail_tip=4,
        colors={BODY: (198, 142, 86), HEAD: (200, 146, 92), EAR: (150, 100, 62), LEG: (194, 140, 86),
                FARLEG: (160, 112, 66), TAIL: (192, 136, 82), TAILTIP: (74, 50, 36), PAW: (222, 194, 156), MUZZLE: (240, 230, 212)},
        belly=(236, 218, 182), back=(178, 124, 72), mask=(84, 60, 46)),
    'black_bear': dict(
        frame=(64, 40), ground=38, split=34, file='blackbear',
        body=[(8, 27), (9, 20), (13, 15), (20, 13), (31, 13), (40, 14), (45, 16), (48, 21), (47, 27), (42, 31), (22, 32), (12, 31)],
        head=[(44, 15), (48, 12), (52, 13), (54, 16), (59, 18), (59, 21), (54, 23), (48, 23), (45, 21)],
        jaw=[(53, 21), (58, 21), (57, 23), (53, 23)],
        ears=[[(46, 13), (47, 10), (50, 11), (49, 13)]],
        eye=(51, 16), nose=(59, 18), muzzle_x=53,
        legs=[('far', (40, 27), 6, 5, 0), ('far', (20, 27), 8, 6, 0), ('near', (43, 27), 7, 6, 0), ('near', (16, 27), 9, 6, 0)],
        paw=2, tail=None,
        colors={BODY: (42, 42, 50), HEAD: (46, 46, 54), EAR: (40, 40, 48), LEG: (38, 38, 46),
                FARLEG: (28, 28, 34), PAW: (32, 32, 38), MUZZLE: (176, 142, 104)},
        sheen=(92, 96, 114)),
    'grizzly_bear': dict(
        frame=(80, 52), ground=50, split=42, file='bear_adult',
        # 下半身（臀部、後腿）比肩峰更大：臀部頂端比肩峰高、往後更寬，肩峰降低
        body=[(7, 38), (6, 28), (9, 20), (15, 14), (24, 13), (32, 16), (39, 18), (44, 16), (48, 14), (53, 15), (58, 18), (61, 23), (62, 29), (59, 37),
              (51, 40), (30, 41), (15, 41), (9, 40)],
        head=[(57, 19), (62, 17), (66, 19), (68, 22), (70, 24), (75, 25), (76, 28), (72, 31), (65, 32), (60, 30), (57, 26)],
        jaw=[(69, 29), (75, 29), (73, 31), (69, 31)],
        ears=[[(60, 18), (61, 15), (64, 15), (64, 18)]],
        eye=(66, 23), nose=(76, 25), muzzle_x=70,
        legs=[('far', (52, 36), 8, 7, 0), ('far', (22, 36), 12, 9, 0), ('near', (56, 36), 9, 8, 0), ('near', (17, 36), 14, 9, 0)],
        paw=3, tail=None, claws=True,
        colors={BODY: (128, 96, 66), HEAD: (140, 104, 72), EAR: (104, 76, 54), LEG: (94, 68, 48),
                FARLEG: (74, 54, 38), PAW: (80, 58, 42), MUZZLE: (160, 124, 88)},
        back=(176, 144, 104), grizzle=True),
}


def mul(c, k):
    return tuple(max(0, min(255, int(round(v * k)))) for v in c)


def pose_params(pose, phase, bear):
    """回傳 (前半身位移 fdx, fdy, 頭額外位移 hdx, hdy, 起伏 bob, 各腿腳底位移 swing[4], 抬腳 lift[4], 張口, 耳朵往後)。
    腿的順序同 SPECIES 的 legs：遠前、遠後、近前、近後。"""
    fdx = fdy = hdx = hdy = bob = 0
    swing = [0, 0, 0, 0]; lift = [0, 0, 0, 0]
    mouth = ears_back = False
    if pose == 'idle':
        bob = 1 if phase in (1, 2) else 0
        hdy = 1 if phase == 2 else 0
    elif pose == 'move':
        pat = [(-3, 3, 3, -3), (-1, 1, 1, -1), (3, -3, -3, 3), (1, -1, -1, 1)]
        swing = list(pat[phase])
        lift = [1 if phase == 3 else 0, 1 if phase == 1 else 0, 1 if phase == 1 else 0, 1 if phase == 3 else 0]
        bob = 1 if phase in (1, 3) else 0
    elif pose == 'attack':
        # 頭保持水平往前（前半身抬起時頭不再跟著仰）
        fdx, fdy, hdx, hdy = 3, -4, 2, 2
        swing = [4, -4, 7, -5]; lift = [3, 0, 5, 0]
        mouth = True
    elif pose == 'hurt':
        fdx, fdy, hdx, hdy = -1, 2, -1, 2
        swing = [-1, 1, -2, 2]
        ears_back = True
    elif pose == 'threaten':
        fdx, fdy, hdx, hdy = 1, 3, 2, 1
        swing = [1, -1, 3, -2]
        mouth = ears_back = True
    elif pose.startswith('swipe'):
        k = int(pose[-1])
        fdy = -[2, 6, 7, 3][k]; fdx = [0, 1, 3, 1][k]
        swing = [[0, 0, 1, 0], [1, 0, 3, -1], [2, 0, 9, -1], [1, 0, 4, 0]][k]
        lift = [[0, 0, 0, 0], [3, 0, 7, 0], [4, 0, 8, 0], [1, 0, 3, 0]][k]
        mouth = k in (1, 2)
    return fdx, fdy, hdx, hdy, bob, swing, lift, mouth, ears_back


def draw_frame(sp, pose='idle', phase=0):
    fw, fh = sp['frame']
    g = sp['ground']
    split = sp['split']
    bear = sp.get('tail') is None
    fdx, fdy, hdx, hdy, bob, swing, lift, mouth, ears_back = pose_params(pose, phase, bear)

    def tf(p, head=False):
        x, y = p
        y -= bob
        if x > split:
            # 前半身：越往前位移越多（身體會傾斜，不是整塊平移）
            t = min(1.0, (x - split) / 8.0)
            x += fdx * t; y += fdy * t
        if head:
            x += hdx; y += hdy
        return (round(x), round(y))

    m = Image.new('L', (fw, fh), 0)
    d = ImageDraw.Draw(m)

    def leg(i, kind):
        side, (ax, ay), wt, wb, bend = sp['legs'][i]
        top = tf((ax, ay))
        foot = (top[0] - (ax - tf((ax, ay))[0]) * 0 + swing[i] + (ax - top[0]) * 0, g - lift[i])
        foot = (ax + swing[i] + (fdx if ax > split else 0), g - lift[i])
        mid = ((top[0] + foot[0]) / 2 + bend, (top[1] + foot[1]) / 2)
        mat = FARLEG if side == 'far' else LEG
        d.line([top, mid], fill=mat, width=wt)
        d.line([mid, foot], fill=mat, width=wb)
        p = sp['paw']
        d.rectangle([foot[0] - wb // 2, foot[1] - 1, foot[0] - wb // 2 + wb + p - 2, foot[1]], fill=mat if side == 'far' else PAW)
        return foot

    leg(0, 'far'); leg(1, 'far')
    if sp.get('legs_behind'):
        # 近側腿也畫在身體後面，只露出身體下方那段（猞猁：腿的上段畫在身上會留下斜線）
        feet = [leg(2, 'near'), leg(3, 'near')]
    if sp.get('tail'):
        pts = [tf(p) for p in sp['tail']]
        if pose in ('idle', 'move'):
            pts = pts[:-1] + [(pts[-1][0] + [0, 1, 0, -1][phase], pts[-1][1])]
        d.line(pts, fill=TAIL, width=sp['tail_w'], joint='curve')
        # 尾尖
        tip = pts[-2:] if len(pts) > 2 else pts
        d.line(tip, fill=TAILTIP, width=sp['tail_tip'])
    d.polygon([tf(p) for p in sp['body']], fill=BODY)
    if sp.get('neck'):
        nk = sp['neck']
        d.polygon([tf(nk[0]), tf(nk[1], True), tf(nk[2], True), tf(nk[3])], fill=HEAD)
    d.polygon([tf(p, True) for p in sp['head']], fill=HEAD)
    if mouth:
        jaw = [tf((x, y + 1), True) for x, y in sp['jaw']]
        d.polygon(jaw, fill=HEAD)
    if sp.get('ruff'):
        d.polygon([tf(p, True) for p in sp['ruff']], fill=MUZZLE)
        for st in sp.get('ruff_stripes', []):
            d.line([tf(p, True) for p in st], fill=TUFT)
    for ear in sp['ears']:
        pts = [tf(p, True) for p in ear]
        if ears_back:
            pts = [(x - 1, y + 2) if k == 1 else (x, y) for k, (x, y) in enumerate(pts)]
        d.polygon(pts, fill=EAR)
    for tuft in sp.get('tufts', []):
        a, b = [tf(p, True) for p in tuft]
        if ears_back:
            a = (a[0] - 1, a[1] + 2); b = (b[0] - 2, b[1] + 3)
        d.line([a, b], fill=TUFT)
    if not sp.get('legs_behind'):
        feet = [leg(2, 'near'), leg(3, 'near')]

    # ---- 上色 ----
    out = Image.new('RGBA', (fw, fh), (0, 0, 0, 0))
    mp, op = m.load(), out.load()
    cols = sp['colors']
    # 每一欄身體的上下緣（算淡色腹部、背部顏色用）
    span = {}
    for x in range(fw):
        ys = [y for y in range(fh) if mp[x, y] == BODY]
        if ys:
            span[x] = (min(ys), max(ys))
    hspan = {}
    for x in range(fw):
        ys = [y for y in range(fh) if mp[x, y] == HEAD]
        if ys:
            hspan[x] = (min(ys), max(ys))
    spot_set = set()
    if sp.get('many_spots'):
        import random as _r
        r2 = _r.Random('spots')
        for _ in range(16):
            spot_set.add(tf((r2.randint(15, 31), r2.randint(15, 21))))
    if sp.get('spots'):
        for x, y in [(17, 16), (20, 18), (23, 15), (25, 19), (28, 16), (30, 18), (19, 14), (26, 21), (22, 20), (15, 18),
                     (31, 24), (17, 25), (30, 27), (16, 27), (29, 22), (21, 22)]:
            spot_set.add(tf((x, y)))
    eye = tf(sp['eye'], True); nose = tf(sp['nose'], True)
    muzzle_x = tf((sp.get('muzzle_x', 999), 0), True)[0]
    for x in range(fw):
        for y in range(fh):
            v = mp[x, y]
            if not v:
                continue
            c = cols.get(v, cols[BODY])
            h = (x * 7919 + y * 104729) % 97
            if v == BODY and x in span:
                top, bot = span[x]
                depth, height = y - top, max(1, bot - top)
                if 'belly' in sp and depth > height * 0.62:
                    c = sp['belly']
                elif 'back' in sp and depth <= max(1, height * 0.3):
                    c = sp['back']
                    if sp.get('grizzle') and h < 30:
                        c = mul(c, 1.22)
                if depth <= 0:
                    c = sp['sheen'] if 'sheen' in sp else mul(c, 1.14)
                elif depth >= height - 1:
                    c = mul(c, 0.82)
                if 'sheen' in sp and depth in (1, 2) and h < 40:
                    c = sp['sheen']
                if (x, y) in spot_set or ((x - 1, y) in spot_set and not sp.get('many_spots')):
                    c = sp['spots']
                elif h < 7:
                    c = mul(c, 0.86)
            elif v == HEAD and x in hspan:
                top, bot = hspan[x]
                if x >= muzzle_x:
                    c = cols[MUZZLE]
                elif 'belly' in sp and y >= bot - 1 and x > eye[0] - 3:
                    c = cols[MUZZLE]  # 下巴、喉部淡色
                if y == top:
                    c = sp['sheen'] if 'sheen' in sp else mul(c, 1.12)
                if 'mask' in sp and x in (nose[0] - 3, nose[0] - 2) and y == nose[1] + 1:
                    c = sp['mask']
            elif v in (LEG, FARLEG) and sp.get('spots') and (x * 13 + y * 5) % 9 == 0 and y < sp['ground'] - 3:
                c = mul(c, 0.78)
            elif v == TAILTIP and 'tail_under' in sp and mp[x, y + 1 if y + 1 < fh else y] == 0:
                c = sp['tail_under']
            op[x, y] = c + (255,)
    # 外框
    edge = []
    for x in range(fw):
        for y in range(fh):
            if op[x, y][3] and any(not (0 <= x + dx < fw and 0 <= y + dy < fh) or not op[x + dx, y + dy][3]
                                   for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
                edge.append((x, y))
    for x, y in edge:
        c = op[x, y]
        op[x, y] = mul(c[:3], 0.5) + (255,) if sum(c[:3]) > 180 else (14, 14, 18, 255)
    # 眼睛、鼻子、嘴、爪
    def put(p, c):
        if 0 <= p[0] < fw and 0 <= p[1] < fh:
            op[p[0], p[1]] = c
    put(eye, (220, 180, 60, 255) if sp['file'] in ('lynx', 'cougar', 'coyote') else (230, 230, 230, 255))
    put((eye[0] - 1, eye[1]), (20, 18, 18, 255))
    put(nose, (20, 18, 18, 255)); put((nose[0], nose[1] + 1), (20, 18, 18, 255))
    if mouth:
        for x, y in [tf((x, y + 1), True) for x, y in sp['jaw'][:2]]:
            put((x, y), (160, 44, 44, 255))
        jx = tf(sp['jaw'][0], True)
        for k in range(1, 4):
            put((jx[0] + k, jx[1] + 1), (160, 44, 44, 255))
    if sp.get('claws'):
        for fx, fy in feet:
            for k in (1, 3, 5):
                put((fx - sp['legs'][2][3] // 2 + sp['legs'][2][3] + sp['paw'] - 2 - k + 2, fy), (230, 222, 200, 255))
    return out


def trim(im):
    bb = im.getbbox()
    return im.crop(bb) if bb else im


def save(im, name):
    im.save(OUT + name + '.png')
    im.save(ARCH + name + '_1x.png')
    im.resize((im.width * 4, im.height * 4), Image.NEAREST).save(ARCH + name + '_4x.png')


def preview(path):
    wolf = Image.open('assets/art/sprites/wolf/wolf_adult_sheet.png').convert('RGBA')
    rows = [[wolf.crop((0, 0, 48, 32)), wolf.crop((0, 32, 48, 64)), wolf.crop((96, 32, 144, 64))]]
    for sp in SPECIES.values():
        rows.append([draw_frame(sp, 'idle', 0), draw_frame(sp, 'move', 0), draw_frame(sp, 'move', 2)])
    W = max(sum(f.width + 6 for f in r) for r in rows) + 6
    H = sum(max(f.height for f in r) + 6 for r in rows) + 6
    out = Image.new('RGBA', (W, H), (96, 116, 96, 255))
    y = 6
    for r in rows:
        h = max(f.height for f in r); x = 6
        for f in r:
            out.alpha_composite(f, (x, y + h - f.height)); x += f.width + 6
        y += h + 6
    out.resize((W * 5, H * 5), Image.NEAREST).save(path)


def preview_actions(path, keys):
    rows = []
    for k in keys:
        sp = SPECIES[k]
        if sp.get('tail') is None:
            fr = [draw_frame(sp, f'swipe{i}') for i in range(4)] + [draw_frame(sp, 'hurt')]
        else:
            fr = [draw_frame(sp, 'attack'), draw_frame(sp, 'hurt')] + ([draw_frame(sp, 'threaten')] if k == 'cougar' else [])
        rows.append(fr)
    W = max(sum(f.width + 6 for f in r) for r in rows) + 6
    H = sum(max(f.height for f in r) + 6 for r in rows) + 6
    out = Image.new('RGBA', (W, H), (96, 116, 96, 255))
    y = 6
    for r in rows:
        h = max(f.height for f in r); x = 6
        for f in r:
            out.alpha_composite(f, (x, y + h - f.height)); x += f.width + 6
        y += h + 6
    out.resize((W * 5, H * 5), Image.NEAREST).save(path)


if __name__ == '__main__':
    import sys
    if '--preview-actions' in sys.argv:
        preview_actions(ARCH + 'preview_v3_actions.png', ['coyote', 'lynx', 'cougar', 'black_bear'])
        sys.exit(0)
    if '--preview' in sys.argv:
        preview(ARCH + 'preview_v3_basic.png')
        sys.exit(0)
    for key, sp in SPECIES.items():
        fw, fh = sp['frame']
        bear = sp.get('tail') is None
        rows = [[draw_frame(sp, 'idle', i) for i in range(4)], [draw_frame(sp, 'move', i) for i in range(4)]]
        if bear:
            rows.append([draw_frame(sp, f'swipe{i}') for i in range(4)])
        sheet = Image.new('RGBA', (fw * 4, fh * len(rows)), (0, 0, 0, 0))
        for r, frames in enumerate(rows):
            for i, f in enumerate(frames):
                sheet.alpha_composite(f, (i * fw, r * fh))
        save(sheet, sp['file'] + '_sheet')
        save(trim(draw_frame(sp, 'hurt')), sp['file'] + '_hurt')
        if not bear:
            save(trim(draw_frame(sp, 'attack')), sp['file'] + '_bite')
        if key == 'cougar':
            save(trim(draw_frame(sp, 'threaten')), 'cougar_threaten')
    print('done')
