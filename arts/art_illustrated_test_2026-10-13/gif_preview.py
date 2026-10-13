"""把 anim/ 的影格做成預覽 GIF：放在林緣草地上，依序 待機 → 走過畫面 → 撲咬 → 受傷；另一張是白底放大看細節。"""
import os
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))


def frames(name, act):
    sheet = Image.open(os.path.join(HERE, "anim", f"{name}_{act}.png"))
    h = sheet.height
    w = Image.open(os.path.join(HERE, "anim", f"{name}_rest.png")).width
    return [sheet.crop((i * w, 0, (i + 1) * w, h)) for i in range(sheet.width // w)]


def main(name="wolf_gray"):
    bg = Image.open(os.path.join(HERE, "source", "bg_meadow.jpg")).convert("RGBA").resize((960, 536), Image.LANCZOS)
    k = 0.5
    seq = []
    idle, walk, bite, hurt = (frames(name, a) for a in ("idle", "walk", "bite", "hurt"))
    x = 120.0
    for f in idle * 2:
        seq.append((f, x))
    for i in range(36):
        seq.append((walk[i % len(walk)], x))
        x += 6.5
    for f in idle:
        seq.append((f, x))
    for f in bite:
        seq.append((f, x))
    for f in idle[:6]:
        seq.append((f, x))
    for f in hurt:
        seq.append((f, x))
    for f in idle:
        seq.append((f, x))
    out = []
    for f, x in seq:
        fr = bg.copy()
        im = f.resize((int(f.width * k), int(f.height * k)), Image.LANCZOS)
        fr.alpha_composite(im, (int(x), 536 - im.height + 12))
        out.append(fr.convert("RGB").quantize(colors=255, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE))
    out[0].save(os.path.join(HERE, "anim", f"{name}_scene.gif"), save_all=True, append_images=out[1:], duration=83, loop=0)

    big = []
    for f in idle + walk * 2 + bite + idle[:4] + hurt:
        fr = Image.new("RGBA", f.size, (238, 234, 226, 255))
        fr.alpha_composite(f)
        big.append(fr.convert("RGB").quantize(colors=255, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE))
    big[0].save(os.path.join(HERE, "anim", f"{name}_actions.gif"), save_all=True, append_images=big[1:], duration=83, loop=0)


if __name__ == "__main__":
    main()
