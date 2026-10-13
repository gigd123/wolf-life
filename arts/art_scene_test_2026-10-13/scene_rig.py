"""主視覺場景版的角色：Gemini 的像素狼（cut/）→ 骨架動畫（共用 art_illustrated_test 的 rig.py）
→ 縮到場景比例（本體 30 像素）、套調色盤、補外框、眼睛跟著頭骨 → assets/art/art_test/scene/ 與 manifest["scene"]。
用法：python3 scene_rig.py [check]   （check：只輸出切腿的遮罩圖）
"""
import json
import os
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "arts", "art_illustrated_test_2026-10-13"))
sys.path.insert(0, os.path.join(ROOT, "arts", "art_pixel_test_2026-10-13"))
import rig  # noqa: E402
import pixel_rig  # noqa: E402
import export_game  # noqa: E402

BODY_PX = 30

WOLF_GRAY = dict(
    bones=[
        ("hips", None, (260, 250), (560, 240)),
        ("chest", "hips", (560, 240), (800, 180)),
        ("head", "chest", (820, 150), (1050, 225)),
        ("jaw", "head", (930, 240), (1040, 250)),
        ("tail1", "hips", (210, 215), (110, 330)),
        ("tail2", "tail1", (110, 330), (20, 440)),
        ("nh_thigh", "hips", (240, 320), (200, 440)),
        ("nh_shin", "nh_thigh", (200, 440), (150, 520)),
        ("nh_foot", "nh_shin", (150, 520), (165, 615)),
        ("fh_thigh", "hips", (380, 360), (370, 450)),
        ("fh_shin", "fh_thigh", (370, 450), (330, 510)),
        ("fh_foot", "fh_shin", (330, 510), (420, 590)),
        ("nf_upper", "chest", (610, 360), (610, 460)),
        ("nf_lower", "nf_upper", (610, 460), (640, 580)),
        ("nf_paw", "nf_lower", (640, 580), (680, 625)),
        ("ff_upper", "chest", (700, 360), (710, 460)),
        ("ff_lower", "ff_upper", (710, 460), (720, 570)),
        ("ff_paw", "ff_lower", (720, 570), (770, 605)),
    ],
    jaw=[(930, 240), (980, 245), (1035, 240), (1050, 236), (1040, 255), (1000, 268), (960, 265), (935, 255)],
    mouth=[(934, 242), (980, 247), (1033, 242), (1045, 239), (1036, 253), (1000, 264), (962, 262), (938, 254)],
    teeth=[],
    limits={
        "nh": [(100, 450), (160, 400), (250, 330), (330, 330), (330, 400), (250, 460), (205, 520), (210, 650), (95, 650)],
        "fh": [(300, 380), (450, 380), (440, 470), (480, 560), (480, 650), (320, 650), (290, 520)],
        "nf": [(570, 370), (668, 370), (668, 560), (690, 600), (705, 650), (580, 650), (575, 520)],
        "ff": [(668, 370), (790, 370), (770, 520), (815, 580), (815, 650), (705, 650), (690, 600), (672, 560)],
    },
    seeds={"nh": [(150, 560), (240, 400)], "fh": [(360, 480), (420, 590)], "nf": [(620, 480), (650, 610)], "ff": [(720, 480), (760, 600)]},
    lum_t=0.2,
    hole_y=400,
    claw_y=590,
    head_x=(790, 850),
    tail_x=230,
    stretch_center=(500, 630),
    eye=(952, 158),
)

WOLF_BLACK = dict(
    bones=[
        ("hips", None, (300, 260), (600, 240)),
        ("chest", "hips", (600, 240), (850, 200)),
        ("head", "chest", (860, 150), (1100, 270)),
        ("jaw", "head", (980, 290), (1080, 300)),
        ("tail1", "hips", (270, 220), (150, 380)),
        ("tail2", "tail1", (150, 380), (30, 480)),
        ("nh_thigh", "hips", (330, 360), (290, 520)),
        ("nh_shin", "nh_thigh", (290, 520), (260, 620)),
        ("nh_foot", "nh_shin", (260, 620), (290, 680)),
        ("fh_thigh", "hips", (430, 400), (400, 530)),
        ("fh_shin", "fh_thigh", (400, 530), (430, 600)),
        ("fh_foot", "fh_shin", (430, 600), (490, 625)),
        ("nf_upper", "chest", (680, 420), (690, 540)),
        ("nf_lower", "nf_upper", (690, 540), (740, 680)),
        ("nf_paw", "nf_lower", (740, 680), (790, 735)),
        ("ff_upper", "chest", (830, 420), (850, 540)),
        ("ff_lower", "ff_upper", (850, 540), (880, 650)),
        ("ff_paw", "ff_lower", (880, 650), (940, 680)),
    ],
    jaw=[(975, 290), (1030, 300), (1080, 296), (1095, 290), (1080, 312), (1030, 320), (990, 312)],
    mouth=[(979, 292), (1030, 302), (1078, 298), (1090, 293), (1077, 309), (1030, 316), (992, 309)],
    teeth=[],
    limits={
        "nh": [(205, 500), (260, 420), (375, 420), (375, 480), (325, 560), (325, 705), (205, 705)],
        "fh": [(345, 480), (472, 470), (462, 560), (512, 600), (512, 655), (380, 655), (350, 560)],
        "nf": [(620, 470), (782, 460), (782, 600), (812, 700), (812, 765), (690, 765), (640, 600)],
        "ff": [(784, 450), (905, 440), (905, 600), (965, 645), (965, 712), (830, 712), (815, 600)],
    },
    seeds={"nh": [(260, 580), (300, 470)], "fh": [(400, 560), (470, 620)], "nf": [(700, 560), (760, 720)], "ff": [(850, 540), (900, 680)]},
    lum_t=0.07,
    hole_y=480,
    claw_y=640,
    head_x=(830, 890),
    tail_x=280,
    stretch_center=(560, 720),
    eye=(970, 185),
)

WOLVES = {"wolf_gray": WOLF_GRAY, "wolf_black": WOLF_BLACK}


def eye_point(cfg, bones, pose, k):
    mats = rig.world_mats(bones, pose)
    p = mats["head"] @ np.array([cfg["eye"][0], cfg["eye"][1], 1.0])
    return int((p[0] + rig.PAD) * rig.SCALE * k), int((p[1] + rig.PAD) * rig.SCALE * k)


def export(aid, cfg, eye_rgb):
    rig.SCALE = 0.5
    acts_hi = rig.render_actions(aid, cfg, HERE)
    rest_hi = Image.open(os.path.join(HERE, "anim", f"{aid}_rest.png"))
    bb = rest_hi.getbbox()
    k = BODY_PX / (bb[3] - bb[1])
    bones = [rig.Bone(*b) for b in cfg["bones"]]
    pixel_rig.EYE_RGB = eye_rgb
    rest_px, pal = pixel_rig.pixelize(rest_hi, k)
    pixel_rig.put_eye(rest_px, eye_point(cfg, bones, {}, k))
    acts = {}
    for act, frames in acts_hi.items():
        fn, n = rig.ACTIONS[act]
        acts[act] = [pixel_rig.put_eye(pixel_rig.pixelize(f, k, pal)[0], eye_point(cfg, bones, fn(i / n), k))
                     for i, f in enumerate(frames)]
    acts = export_game.bite_trails(acts)
    return export_game.write_animal("scene", aid, acts, rest_px)


def main():
    if sys.argv[1:] == ["check"]:
        for aid, cfg in WOLVES.items():
            rig.wolf_rig(aid, cfg, HERE)
        return
    path = os.path.join(export_game.OUT, "manifest.json")
    manifest = json.load(open(path, encoding="utf-8"))
    manifest["scene"] = {}
    for aid, cfg, eye in (("wolf_gray", WOLF_GRAY, (222, 160, 70)), ("wolf_black", WOLF_BLACK, (226, 196, 80))):
        manifest["scene"][aid] = export(aid, cfg, eye)
        print(aid, manifest["scene"][aid]["frame"])
    json.dump(manifest, open(path, "w", encoding="utf-8"), ensure_ascii=False, indent=1)


if __name__ == "__main__":
    main()
