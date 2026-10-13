#!/usr/bin/env python3
# 灰狼重畫的正式版（2026-10-13）：使用者選定玩家用 H、其他狼可用 G 或 H（gen_wolf_variants.py 的候選）。
# 玩家：次成年（H 縮小約 12%、毛色偏淡褐）、成年（H）、老年（H、毛色偏灰白、口鼻與臉白）。
# 黑狼（H 體型、黑色帶灰）、苔原狼（G 體型、米白色）、挑戰者（G 體型、灰褐偏棕）。
# 產生：spritesheet（idle、walk、howl、down 各 4 格，48×32）與單張姿勢（stalk、pounce、eat、sleep、threaten、bite、dodge、hurt、submit），
# 苔原狼另有兩隻並排的 pair；檔名沿用原本的。戰鬥動畫另外用 gen_combat_wolf.py、gen_combat_opponents.py 重拆。
# 用法：在專案根目錄 python3 arts/art_wolf_v2_2026-10-13/gen_wolves.py [--write]（不加 --write 只出預覽）
import sys
sys.path.insert(0, 'arts/art_predators_v2_2026-10-13')
sys.path.insert(0, 'arts/art_wolf_v2_2026-10-13')
import gen_predators as gp
import gen_wolf_variants as wv
from gen_predators import BODY, HEAD, EAR, LEG, FARLEG, PAW, MUZZLE, TAIL, TAILTIP
from PIL import Image, ImageDraw

OUT = 'assets/art/sprites/wolf/'
ARCH = 'arts/art_wolf_v2_2026-10-13/'
H = wv.VARIANTS['H']
G = wv.VARIANTS['G']


def recolor(sp, colors=None, belly=None, back=None, patch_colors=None, **extra):
    out = dict(sp)
    if colors:
        out['colors'] = {**sp['colors'], **colors}
    if belly:
        out['belly'] = belly
    if back:
        out['back'] = back
    if patch_colors:
        out['patches'] = [(patch_colors[i] if i < len(patch_colors) and patch_colors[i] else c, pts, h)
                          for i, (c, pts, h) in enumerate(sp['patches'])]
    out.update(extra)
    return out


def scaled(sp, k):
    """以腳底中央為基準縮放（次成年的體型）。"""
    g = sp['ground']; cx = 24
    f = lambda p: (round(cx + (p[0] - cx) * k), round(g - (g - p[1]) * k))
    out = dict(sp)
    for key in ('body', 'neck', 'head', 'jaw', 'tail'):
        out[key] = [f(p) for p in sp[key]]
    out['ears'] = [[f(p) for p in e] for e in sp['ears']]
    out['eye'] = f(sp['eye']); out['nose'] = f(sp['nose'])
    out['legs'] = [(s_, f(a), max(2, round(wt * k)), max(2, round(wb * k)), b) for s_, a, wt, wb, b in sp['legs']]
    out['patches'] = [(c, [f(p) for p in pts], h) for c, pts, h in sp['patches']]
    out['split'] = f((sp['split'], 0))[0]
    out['tail_w'] = max(3, round(sp['tail_w'] * k))
    return out


# H 的色塊順序：頸毛、臉頰、眉
SUBADULT = recolor(scaled(H, 0.88), colors={BODY: (132, 120, 108), HEAD: (156, 146, 134), LEG: (196, 186, 170), TAIL: (116, 106, 98)},
                   back=(98, 90, 84), patch_colors=[(170, 160, 148), None, None])
ADULT = H
ELDER = recolor(H, colors={BODY: (142, 138, 134), HEAD: (182, 178, 172), EAR: (112, 108, 106), LEG: (212, 208, 202),
                           MUZZLE: (232, 230, 226), TAIL: (128, 124, 120), TAILTIP: (90, 88, 86)},
                belly=(214, 210, 204), back=(108, 106, 106), patch_colors=[(196, 192, 186), (234, 232, 228), (110, 108, 106)])
BLACK = recolor(H, colors={BODY: (54, 52, 56), HEAD: (62, 60, 64), EAR: (40, 38, 42), LEG: (58, 56, 60), FARLEG: (40, 38, 42),
                           PAW: (70, 68, 72), MUZZLE: (92, 90, 94), TAIL: (46, 44, 48), TAILTIP: (28, 26, 30)},
                belly=(76, 74, 78), back=(34, 32, 36), patch_colors=[(70, 68, 72), (96, 94, 98), (30, 28, 32)])
# G 的色塊順序：臉頰
TUNDRA = recolor(G, colors={BODY: (226, 222, 212), HEAD: (232, 228, 220), EAR: (184, 178, 170), LEG: (230, 226, 218),
                            FARLEG: (190, 186, 178), PAW: (240, 238, 232), MUZZLE: (242, 240, 236), TAIL: (220, 216, 208),
                            TAILTIP: (168, 162, 154)},
                 belly=(242, 240, 234), back=(202, 198, 190), patch_colors=[(244, 242, 238)])
CHALLENGER = recolor(G, colors={BODY: (156, 128, 100), HEAD: (164, 138, 108), EAR: (120, 98, 76), LEG: (156, 128, 100),
                                FARLEG: (100, 82, 64), PAW: (210, 196, 172), MUZZLE: (226, 214, 192), TAIL: (146, 120, 94),
                                TAILTIP: (96, 78, 62)},
                     belly=(222, 206, 178), back=(126, 102, 80), patch_colors=[(226, 214, 194)])

SETS = [('wolf_', SUBADULT, True), ('wolf_adult_', ADULT, True), ('wolf_elder_', ELDER, True),
        ('wolf_stranger_', BLACK, False), ('wolf_tundra_', TUNDRA, False), ('wolf_challenger_', CHALLENGER, False)]
PLAYER_POSES = ['stalk', 'pounce', 'eat', 'sleep', 'threaten', 'bite', 'dodge', 'hurt', 'submit']
NPC_POSES = ['stalk', 'threaten', 'bite', 'dodge', 'hurt', 'submit']
POSE_OF = {'bite': 'attack'}


def trim(im):
    bb = im.getbbox()
    return im.crop(bb) if bb else im


def sheet(sp):
    out = Image.new('RGBA', (48 * 4, 32 * 4), (0, 0, 0, 0))
    rows = [[gp.draw_frame(sp, 'idle', i) for i in range(4)], [gp.draw_frame(sp, 'move', i) for i in range(4)],
            [gp.draw_frame(sp, f'howl{i}') for i in range(4)], [gp.draw_frame(sp, f'down{i}') for i in range(4)]]
    for r, frames in enumerate(rows):
        for i, f in enumerate(frames):
            out.alpha_composite(f, (i * 48, r * 32))
    return out


def roomy(sp, dy=8, dw=8):
    """單張姿勢畫在比較大的畫布上（往上多 dy、往右多 dw），抬頭、撲擊時才不會被 48×32 切掉；畫完再裁切。"""
    f = lambda p: (p[0], p[1] + dy)
    out = dict(sp)
    for key in ('body', 'neck', 'head', 'jaw', 'tail'):
        out[key] = [f(p) for p in sp[key]]
    out['ears'] = [[f(p) for p in e] for e in sp['ears']]
    out['eye'] = f(sp['eye']); out['nose'] = f(sp['nose'])
    out['legs'] = [(s_, f(a), wt, wb, b) for s_, a, wt, wb, b in sp['legs']]
    out['patches'] = [(c, [f(p) for p in pts], h) for c, pts, h in sp['patches']]
    out['frame'] = (sp['frame'][0] + dw, sp['frame'][1] + dy)
    out['ground'] = sp['ground'] + dy
    return out


def poses(sp, names):
    big = roomy(sp)
    return {n: trim(gp.draw_frame(big, POSE_OF.get(n, n))) for n in names}


def pair(sp):
    """苔原狼兩隻並排（後面那隻稍微錯開、深一點）。"""
    back = recolor(sp, colors={k: gp.mul(v, 0.86) for k, v in sp['colors'].items()}, belly=gp.mul(sp['belly'], 0.86),
                   back=gp.mul(sp['back'], 0.86))
    out = Image.new('RGBA', (60, 34), (0, 0, 0, 0))
    out.alpha_composite(trim(gp.draw_frame(back, 'idle', 0)), (14, 2))
    a = trim(gp.draw_frame(sp, 'idle', 0))
    out.alpha_composite(a, (2, 34 - a.height))
    return out


def haze(im, col=(122, 112, 102), k=0.35):
    """遠景：顏色往霧色混一些（遠遠看到的身影）。"""
    im = im.copy(); px = im.load()
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, a = px[x, y]
            if a:
                px[x, y] = (int(r + (col[0] - r) * k), int(g + (col[1] - g) * k), int(b + (col[2] - b) * k), a)
    return im


def distant(sp):
    """黑狼的遠景：走路 4 格（每格 50×32，底部對齊）與單張，都加上霧化色調。"""
    strip = Image.new('RGBA', (50 * 4, 32), (0, 0, 0, 0))
    for i in range(4):
        f = haze(trim(gp.draw_frame(sp, 'move', i)))
        strip.alpha_composite(f, (i * 50 + (50 - f.width) // 2, 32 - f.height))
    single = haze(trim(gp.draw_frame(sp, 'idle', 0)))
    return strip, single


def save(im, name):
    im.save(OUT + name + '.png')
    im.save(ARCH + name + '_1x.png')
    im.resize((im.width * 4, im.height * 4), Image.NEAREST).save(ARCH + name + '_4x.png')


def preview(path):
    rows = []
    for prefix, sp, player in SETS:
        sh = sheet(sp)
        ps = poses(sp, PLAYER_POSES if player else NPC_POSES)
        W = sh.width + 6 + sum(p.width + 4 for p in ps.values())
        r = Image.new('RGBA', (W, max(sh.height, 40) + 10), (96, 116, 96, 255))
        r.alpha_composite(sh, (0, 10)); x = sh.width + 6
        for p in ps.values():
            r.alpha_composite(p, (x, 10 + 32 - p.height)); x += p.width + 4
        ImageDraw.Draw(r).text((2, 0), prefix, fill=(255, 255, 255))
        rows.append(r)
    W = max(r.width for r in rows); Ht = sum(r.height for r in rows)
    out = Image.new('RGBA', (W, Ht), (96, 116, 96, 255)); y = 0
    for r in rows:
        out.alpha_composite(r, (0, y)); y += r.height
    out.resize((W * 3, Ht * 3), Image.NEAREST).save(path)


if __name__ == '__main__':
    if '--write' not in sys.argv:
        preview(ARCH + 'preview_full.png')
        sys.exit(0)
    for prefix, sp, player in SETS:
        save(sheet(sp), prefix + 'sheet')
        for n, im in poses(sp, PLAYER_POSES if player else NPC_POSES).items():
            save(im, prefix + n)
    save(pair(TUNDRA), 'wolf_tundra_pair')
    strip, single = distant(BLACK)
    save(strip, 'wolf_stranger_distant_walk_strip')
    save(single, 'wolf_stranger')
    print('done')
