"""像素風灰狼試作：Gemini 像素圖 → 去背（cut/）→ 骨架動畫（沿用插畫風的 rig.py，在高解析原圖上變形）
→ 每格縮回原生解析度、套統一調色盤、補 1 像素外框 → spritesheet 與比較圖。
用法：python3 pixel_rig.py
"""
import os
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "art_illustrated_test_2026-10-13"))
import rig  # noqa: E402

# cut/wolf_gray.png（976×694）的座標
WOLF_PIXEL = dict(
    bones=[
        ("hips", None, (300, 250), (560, 225)),
        ("chest", "hips", (560, 225), (740, 190)),
        ("head", "chest", (750, 170), (960, 235)),
        ("jaw", "head", (858, 256), (940, 262)),
        ("tail1", "hips", (215, 240), (115, 370)),
        ("tail2", "tail1", (115, 370), (30, 490)),
        ("nh_thigh", "hips", (250, 300), (245, 420)),
        ("nh_shin", "nh_thigh", (245, 420), (150, 525)),
        ("nh_foot", "nh_shin", (150, 525), (175, 665)),
        ("fh_thigh", "hips", (385, 330), (365, 440)),
        ("fh_shin", "fh_thigh", (365, 440), (340, 560)),
        ("fh_foot", "fh_shin", (340, 560), (420, 650)),
        ("nf_upper", "chest", (620, 320), (610, 450)),
        ("nf_lower", "nf_upper", (610, 450), (640, 620)),
        ("nf_paw", "nf_lower", (640, 620), (690, 675)),
        ("ff_upper", "chest", (705, 320), (705, 450)),
        ("ff_lower", "ff_upper", (705, 450), (715, 615)),
        ("ff_paw", "ff_lower", (715, 615), (760, 660)),
    ],
    jaw=[(852, 252), (890, 257), (935, 252), (950, 258), (932, 276), (900, 287), (870, 284), (855, 271)],
    mouth=[(855, 254), (890, 259), (933, 255), (945, 259), (930, 274), (900, 284), (872, 281), (858, 270)],
    teeth=[(906, 257, 7, 12), (922, 256, 7, 12)],
    limits={
        "nh": [(112, 560), (130, 470), (190, 400), (250, 370), (330, 380), (330, 440), (260, 480), (218, 540), (226, 694), (100, 694)],
        "fh": [(296, 400), (452, 400), (446, 520), (470, 600), (470, 694), (330, 694), (290, 560)],
        "nf": [(556, 400), (655, 400), (655, 600), (668, 632), (705, 645), (712, 694), (580, 694), (566, 520)],
        "ff": [(658, 400), (782, 400), (772, 520), (785, 600), (785, 694), (700, 694), (700, 655), (660, 630)],
    },
    seeds={"nh": [(170, 600), (225, 455)], "fh": [(345, 480), (400, 640)], "nf": [(600, 480), (640, 600)], "ff": [(720, 480), (745, 640)]},
    hole_y=440,
    claw_y=630,
    head_x=(735, 795),
    tail_x=232,
    stretch_center=(500, 680),
)
# 眼睛原本約 12×6，縮到原生解析度會被周圍的深色吃掉；改成每格依頭骨算出眼睛的位置，直接點上琥珀色
EYE_POS = (861, 160)
EYE_RGB = (222, 160, 70)

# 原生解析度：狼本體（不含四周留白）的高度，輸出兩種尺寸比較。目前遊戲的灰狼本體約 27 像素高（48×32 格）。
SIZES = {"wolf_px46": 46, "wolf_px64": 64}
PALETTE_COLORS = 32


def eye_point(bones, pose, k):
    """眼睛在原生解析度影格裡的位置（跟著頭骨移動）。"""
    mats = rig.world_mats(bones, pose)
    p = mats["head"] @ np.array([EYE_POS[0], EYE_POS[1], 1.0])
    return int((p[0] + rig.PAD) * rig.SCALE * k), int((p[1] + rig.PAD) * rig.SCALE * k)


def put_eye(im, xy):
    x, y = xy
    if 0 <= x < im.width and 0 <= y < im.height and im.getpixel((x, y))[3]:
        im.putpixel((x, y), EYE_RGB + (255,))
    return im


def pixelize(frame, k, pal_img=None):
    """高解析影格 → 原生解析度：面積平均縮小、alpha 二值化、套調色盤、補外框。"""
    w, h = max(1, round(frame.width * k)), max(1, round(frame.height * k))
    a = np.asarray(frame).astype(float) / 255
    pm = a.copy()
    pm[..., :3] *= pm[..., 3:4]
    small = Image.fromarray((pm * 255).astype(np.uint8), "RGBA").resize((w, h), Image.BOX)
    s = np.asarray(small).astype(float) / 255
    alpha = s[..., 3] > 0.45
    rgb = np.where(s[..., 3:4] > 1e-3, s[..., :3] / np.maximum(s[..., 3:4], 1e-3), 0)
    rgb_img = Image.fromarray((np.clip(rgb, 0, 1) * 255).astype(np.uint8), "RGB")
    if pal_img is None:
        # 調色盤：從靜止姿勢取 31 色，最後一格固定放眼睛的琥珀色
        pal_img = rgb_img.quantize(colors=PALETTE_COLORS - 1, method=Image.Quantize.MEDIANCUT)
        pal = pal_img.getpalette()[: (PALETTE_COLORS - 1) * 3] + list(EYE_RGB)
        pal_img.putpalette(pal + [0] * (768 - len(pal)))
    q = np.asarray(rgb_img.quantize(palette=pal_img, dither=Image.Dither.NONE).convert("RGB")).copy()
    # 外框：不透明、但上下左右有透明鄰居的像素改成最深的顏色
    pad = np.pad(alpha, 1)
    edge = alpha & ~(pad[:-2, 1:-1] & pad[2:, 1:-1] & pad[1:-1, :-2] & pad[1:-1, 2:])
    pal = np.array(pal_img.getpalette()[: PALETTE_COLORS * 3]).reshape(-1, 3)
    darkest = pal[pal.sum(1).argmin()]
    q[edge] = darkest
    out = np.dstack([q, np.where(alpha, 255, 0)]).astype(np.uint8)
    return Image.fromarray(out, "RGBA"), pal_img


def main():
    acts = rig.render_actions("wolf_gray", WOLF_PIXEL, HERE)
    rest = Image.open(os.path.join(HERE, "anim", "wolf_gray_rest.png"))
    bb = rest.getbbox()
    for prefix, body_h in SIZES.items():
        k = body_h / (bb[3] - bb[1])
        bones = [rig.Bone(*b) for b in WOLF_PIXEL["bones"]]
        rest_px, pal_img = pixelize(rest, k)
        put_eye(rest_px, eye_point(bones, {}, k)).save(os.path.join(HERE, "anim", f"{prefix}_rest.png"))
        for act, frames in acts.items():
            fn, n = rig.ACTIONS[act]
            px = [put_eye(pixelize(f, k, pal_img)[0], eye_point(bones, fn(i / n), k)) for i, f in enumerate(frames)]
            if act == "bite":
                px = rig.add_trails(px, [i for i in range(len(px)) if 0.36 <= i / len(px) <= 0.56])
            rig.save_sheet(px, os.path.join(HERE, "anim", f"{prefix}_{act}.png"))
        print(prefix, px[0].size)


if __name__ == "__main__":
    main()
