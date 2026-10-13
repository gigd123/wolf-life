"""像素試作的預覽：放在遊戲現有的地形背景（320×180）上，整張放大 4 倍（最近鄰），和目前的 48×32 灰狼比較。"""
import os
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..", "..")
Z = 4


def strip(prefix, act):
    sheet = Image.open(os.path.join(HERE, "anim", f"{prefix}_{act}.png"))
    w = Image.open(os.path.join(HERE, "anim", f"{prefix}_rest.png")).width
    return [sheet.crop((i * w, 0, (i + 1) * w, sheet.height)) for i in range(sheet.width // w)]


def old_walk():
    sheet = Image.open(os.path.join(ROOT, "assets/art/sprites/wolf/wolf_sheet.png"))
    return [sheet.crop((i * 48, 32, (i + 1) * 48, 64)) for i in range(sheet.width // 48)]


def foot(im):
    """影格裡最低的不透明像素列（腳底），用來對齊地面。"""
    return im.getbbox()[3]


def save(frames, name, ms=83):
    pal = [f.convert("RGB").quantize(colors=255, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE) for f in frames]
    pal[0].save(os.path.join(HERE, "anim", name), save_all=True, append_images=pal[1:], duration=ms, loop=0)


def main():
    bg = Image.open(os.path.join(ROOT, "assets/art/backgrounds/terrain/clearing.png")).convert("RGBA")
    ground = 168
    # 1) 三隻並排走路：目前 48×32、新 46、新 64（同一個像素倍率）
    ow, a, b = old_walk(), strip("wolf_px46", "walk"), strip("wolf_px64", "walk")
    frames = []
    for i in range(24):
        fr = bg.copy()
        for im, x in ((ow[(i // 3) % len(ow)], 18), (a[i % len(a)], 80), (b[i % len(b)], 186)):
            fr.alpha_composite(im, (x, ground - foot(im)))
        frames.append(fr.resize((bg.width * Z, bg.height * Z), Image.NEAREST))
    save(frames, "compare_walk.gif")
    # 2) 大的版本：待機 → 走路 → 撲咬 → 受傷
    seq = strip("wolf_px64", "idle") * 2 + strip("wolf_px64", "walk") * 2 + strip("wolf_px64", "idle")[:6] \
        + strip("wolf_px64", "bite") + strip("wolf_px64", "idle")[:6] + strip("wolf_px64", "hurt") + strip("wolf_px64", "idle")
    rest_foot = foot(Image.open(os.path.join(HERE, "anim", "wolf_px64_rest.png")))
    frames = []
    for im in seq:
        fr = bg.copy()
        fr.alpha_composite(im, (70, ground - rest_foot))
        frames.append(fr.resize((bg.width * Z, bg.height * Z), Image.NEAREST))
    save(frames, "actions_px64.gif")


if __name__ == "__main__":
    main()
