#!/usr/bin/env python3
# 灰狼戰鬥動畫的第 1 批試做（1.9 第 4 步，pre-2.0-plan 的動畫素材第 1 批）：用現有的姿勢圖與 spritesheet 拆格，
# 加上壓低、旋轉、位移組成多格動作。次成年、成年、老年各用自己的原圖。
# 產生：wolf[_adult|_elder]_{bite,hurt,dodge,circle}_strip.png，每格 64×40，橫向長條；同時存 _1x／_4x 到這個資料夾。
# 用法：在專案根目錄 python3 arts/art_combat_wolf_2026-10-13/gen_combat_wolf.py
from PIL import Image

SRC = 'assets/art/sprites/wolf/'
ARCH = 'arts/art_combat_wolf_2026-10-13/'
FW, FH = 64, 40
BASE = FH - 3  # 腳的基準線


def load(prefix, name):
    return Image.open(f'{SRC}{prefix}{name}.png').convert('RGBA')


def sheet_frame(sheet, row, col):
    return sheet.crop((col * 48, row * 32, col * 48 + 48, row * 32 + 32))


def trim(im):
    bb = im.getbbox()
    return im.crop(bb) if bb else im


def place(frame, im, dx=0, dy=0, rot=0.0, sx=1.0, sy=1.0, flip=False):
    """把 im 貼進格子：水平置中、底部貼齊基準線，再位移 dx、dy（正值往右、往下）。"""
    im = trim(im)
    if flip:
        im = im.transpose(Image.FLIP_LEFT_RIGHT)
    if sx != 1.0 or sy != 1.0:
        im = im.resize((max(1, round(im.width * sx)), max(1, round(im.height * sy))), Image.NEAREST)
    if rot:
        im = trim(im.rotate(rot, resample=Image.NEAREST, expand=True))
    x = (FW - im.width) // 2 + dx
    y = BASE - im.height + dy
    frame.alpha_composite(im, (max(0, min(FW - im.width, x)), max(0, min(FH - im.height, y))))


def strip(frames):
    out = Image.new('RGBA', (FW * len(frames), FH), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        out.alpha_composite(f, (i * FW, 0))
    return out


def new():
    return Image.new('RGBA', (FW, FH), (0, 0, 0, 0))


def make(prefix):
    sheet = load(prefix, 'sheet')
    idle = sheet_frame(sheet, 0, 0)
    walk = [sheet_frame(sheet, 1, c) for c in range(4)]
    down = sheet_frame(sheet, 3, 2)
    # 撲咬、撲擊的單張比 spritesheet 的狼大一圈，縮到和待機差不多的體型
    pounce, bite = load(prefix, 'pounce'), load(prefix, 'bite')
    k = trim(idle).width / max(1, trim(bite).width - 6)
    pounce = pounce.resize((round(pounce.width * k), round(pounce.height * k)), Image.NEAREST)
    bite = bite.resize((round(bite.width * k), round(bite.height * k)), Image.NEAREST)
    dodge, hurt = load(prefix, 'dodge'), load(prefix, 'hurt')
    out = {}

    # 撲咬：蓄力壓低 → 起跳 → 張口前伸 → 咬住 → 落地（只播一次）
    seq = [(idle, dict(dx=-2, sx=1.04, sy=0.86)),
           (idle, dict(dx=-4, sx=1.08, sy=0.78)),
           (pounce, dict(dx=0, dy=-3, rot=12)),
           (bite, dict(dx=4, dy=-2, rot=3)),
           (bite, dict(dx=6, dy=0)),
           (idle, dict(dx=3, sx=1.03, sy=0.9))]
    fr = []
    for im, kw in seq:
        f = new(); place(f, im, **kw); fr.append(f)
    out['bite'] = fr

    # 被打飛：受擊的一瞬間（受傷圖，偏紅）→ 頭往後仰、身體離地往後 → 摔低 → 撐起
    seq = [(hurt, dict(dx=0)),
           (idle, dict(dx=-4, dy=-4, rot=16)),
           (idle, dict(dx=-8, dy=-3, rot=26)),
           (down, dict(dx=-10)),
           (idle, dict(dx=-8, sx=1.04, sy=0.84))]
    fr = []
    for im, kw in seq:
        f = new(); place(f, im, **kw); fr.append(f)
    out['hurt'] = fr

    # 閃避跳開：壓低 → 往後上方跳 → 弧線最高點 → 落地壓低
    seq = [(idle, dict(sx=1.04, sy=0.86)),
           (dodge, dict(dx=-2, dy=-4, rot=-6)),
           (dodge, dict(dx=-5, dy=-7)),
           (dodge, dict(dx=-8, dy=-3, rot=6)),
           (idle, dict(dx=-9, sx=1.04, sy=0.88))]
    fr = []
    for im, kw in seq:
        f = new(); place(f, im, **kw); fr.append(f)
    out['dodge'] = fr

    # 繞圈小跑（循環）：小跑起伏，中段轉身背向（左右翻轉）再轉回來
    fr = []
    for i in range(8):
        f = new()
        flip = 3 <= i <= 5
        place(f, walk[i % 4], dx=(-2 if flip else 2), dy=(-1 if i % 2 else 0), flip=flip)
        fr.append(f)
    out['circle'] = fr
    return out


def save(im, name):
    im.save(SRC + name + '.png')
    im.save(ARCH + name + '_1x.png')
    im.resize((im.width * 4, im.height * 4), Image.NEAREST).save(ARCH + name + '_4x.png')


if __name__ == '__main__':
    for prefix in ['wolf_', 'wolf_adult_', 'wolf_elder_']:
        for pose, frames in make(prefix).items():
            save(strip(frames), f'{prefix}{pose}_strip')
    print('done')
