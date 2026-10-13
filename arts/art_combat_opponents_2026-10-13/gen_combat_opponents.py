#!/usr/bin/env python3
# 對手的戰鬥動畫（1.9 第 4 步，動畫素材第 2～4 批＋Phase 2 的新對手）：照灰狼第 1 批的做法，
# 拆每種動物現有的 spritesheet 與姿勢圖，組成攻擊、受傷、閃避（狼類）的多格動作。照原圖的方向畫（面向右，往前是 +x）；
# 戰鬥時遊戲把對手水平翻轉，讓牠面向玩家的狼。
# 每個動作的最後一格停在該姿勢（攻擊停在打中、受傷停在受傷），在其他畫面只播一次也不會停在奇怪的格。
# 產生：<原圖檔名去掉 _sheet>_{attack,hurt,dodge}_strip.png，和原圖放在同一個資料夾；_1x／_4x 存到這個資料夾。
# 用法：在專案根目錄 python3 arts/art_combat_opponents_2026-10-13/gen_combat_opponents.py
import json, os
from PIL import Image

ARCH = 'arts/art_combat_opponents_2026-10-13/'
ANIMALS = ['grizzly_bear', 'stranger_wolf', 'tundra_wolf', 'challenger', 'wolverine', 'red_fox',
           'cougar', 'black_bear', 'coyote', 'lynx']
FPS = {'attack': 14, 'hurt': 14, 'dodge': 16}


def res(path):
    return path.replace('res://', '')


def trim(im):
    bb = im.getbbox()
    return im.crop(bb) if bb else im


def tint(im, col=(210, 70, 70), k=0.4):
    im = im.copy(); px = im.load()
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, a = px[x, y]
            if a:
                px[x, y] = (int(r + (col[0] - r) * k), int(g + (col[1] - g) * k), int(b + (col[2] - b) * k), a)
    return im


def sources(entry):
    fw, fh = entry.get('frame', [48, 32])
    sheet = Image.open(res(entry['sheet'])).convert('RGBA')
    rows = entry.get('rows', {})
    frames = int(entry.get('frames', 4))
    def row(name):
        r = rows.get(name)
        if r is None:
            return []
        return [trim(sheet.crop((c * fw, r * fh, c * fw + fw, r * fh + fh))) for c in range(frames)]
    idle = row('idle')[0]
    poses = {k: trim(Image.open(res(v)).convert('RGBA')) for k, v in entry.get('poses', {}).items()}
    return idle, row('attack'), poses


def build(entry):
    idle, attack_row, poses = sources(entry)
    atk = poses.get('attack')
    hurt = poses.get('hurt') or tint(idle)
    dodge = poses.get('dodge')
    seqs = {}
    # 攻擊：往後蓄力 → 撲出 → 打中（停在打中）
    if len(attack_row) >= 2:
        seqs['attack'] = [(idle, dict(dx=-3, sx=1.04, sy=0.9))] + [(f, dict(dx=2 * i)) for i, f in enumerate(attack_row)]
    elif atk is not None:
        seqs['attack'] = [(idle, dict(dx=-3, sx=1.04, sy=0.86)), (atk, dict(dx=2, dy=-3, rot=8)),
                          (atk, dict(dx=6, dy=-1, rot=3)), (atk, dict(dx=7))]
    else:
        seqs['attack'] = [(idle, dict(dx=-3, sx=1.04, sy=0.86)), (idle, dict(dx=3, dy=-3, rot=-8)),
                          (idle, dict(dx=7, dy=-1, rot=-4)), (idle, dict(dx=7))]
    # 受傷：受擊變紅 → 頭往後仰、往後退 → 站穩（停在受傷）
    seqs['hurt'] = [(tint(hurt, k=0.25), dict()), (idle, dict(dx=-4, dy=-3, rot=12)), (idle, dict(dx=-6, dy=-1, rot=6)),
                    (hurt, dict(dx=-4))]
    # 閃避（有閃避姿勢的狼類）：壓低 → 往後上方跳 → 落地（停在閃避）
    if dodge is not None:
        seqs['dodge'] = [(idle, dict(sx=1.04, sy=0.86)), (dodge, dict(dx=-2, dy=-4, rot=-6)), (dodge, dict(dx=-5, dy=-7)),
                         (dodge, dict(dx=-8, dy=-2, rot=4)), (dodge, dict(dx=-9))]
    return seqs


def render(seq):
    imgs = []
    for im, kw in seq:
        im2 = im
        if kw.get('sx', 1) != 1 or kw.get('sy', 1) != 1:
            im2 = im2.resize((max(1, round(im2.width * kw.get('sx', 1))), max(1, round(im2.height * kw.get('sy', 1)))), Image.NEAREST)
        if kw.get('rot'):
            im2 = trim(im2.rotate(kw['rot'], resample=Image.NEAREST, expand=True))
        imgs.append((im2, kw.get('dx', 0), kw.get('dy', 0)))
    fw = max(i.width for i, _, _ in imgs) + 20
    fh = max(i.height for i, _, _ in imgs) + 10
    base = fh - 3
    out = Image.new('RGBA', (fw * len(imgs), fh), (0, 0, 0, 0))
    for n, (im, dx, dy) in enumerate(imgs):
        x = (fw - im.width) // 2 + dx
        y = base - im.height + dy
        x = max(0, min(fw - im.width, x)); y = max(0, min(fh - im.height, y))
        out.alpha_composite(im, (n * fw + x, y))
    return out, [fw, fh], len(imgs)


if __name__ == '__main__':
    art = json.load(open('data/art.json', encoding='utf-8'))['animals']
    result = {}
    for a in ANIMALS:
        entry = art[a]['adult']
        stem = os.path.basename(res(entry['sheet'])).replace('_sheet.png', '')
        folder = os.path.dirname(res(entry['sheet']))
        result[a] = {}
        for act, seq in build(entry).items():
            im, frame, n = render(seq)
            name = f'{stem}_{act}_strip'
            im.save(f'{folder}/{name}.png')
            im.save(ARCH + name + '_1x.png')
            im.resize((im.width * 4, im.height * 4), Image.NEAREST).save(ARCH + name + '_4x.png')
            result[a][act] = {'sheet': f'res://{folder}/{name}.png', 'frame': frame, 'frames': n, 'fps': FPS[act], 'loop': False}
    json.dump(result, open(ARCH + 'strips.json', 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
    print('done', {a: list(v) for a, v in result.items()})
