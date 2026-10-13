"""主視覺場景版的角色：Gemini 的像素狼（cut/）→ 骨架動畫（共用 art_illustrated_test 的 rig.py）
→ 縮到場景比例（本體 30 像素）、套調色盤、補外框、眼睛跟著頭骨 → assets/art/art_test/scene/ 與 manifest["scene"]。
用法：python3 scene_rig.py [check] [動物…]   （check：只輸出切腿的遮罩圖；不給動物就全部）
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

# 灰熊（DeeVid）：腿沒有外框，但腿與腿之間是背景，切腿時不看亮度（lum_t=0），只靠範圍。
# 座標是去背圖 cut/grizzly.png 的原始座標，下面統一減掉裁切的位移（裁掉右上角浮水印那一段空白）。
GRIZZLY_CROP = (180, 440, 1850, 1497)


def _shift(cfg, dx, dy):
    mv = lambda p: (p[0] - dx, p[1] - dy)
    out = dict(cfg)
    out["bones"] = [(n, par, mv(a), mv(b)) for n, par, a, b in cfg["bones"]]
    for k in ("jaw", "mouth"):
        out[k] = [mv(p) for p in cfg[k]]
    out["limits"] = {k: [mv(p) for p in v] for k, v in cfg["limits"].items()}
    out["seeds"] = {k: [mv(p) for p in v] for k, v in cfg["seeds"].items()}
    for k in ("hole_y", "claw_y"):
        out[k] = cfg[k] - dy
    out["head_x"] = (cfg["head_x"][0] - dx, cfg["head_x"][1] - dx)
    out["tail_x"] = cfg["tail_x"] - dx
    out["stretch_center"] = mv(cfg["stretch_center"])
    out["eye"] = mv(cfg["eye"])
    return out


GRIZZLY = _shift(dict(
    bones=[
        ("hips", None, (400, 800), (1000, 750)),
        ("chest", "hips", (1000, 750), (1350, 700)),
        ("head", "chest", (1400, 650), (1830, 830)),
        ("jaw", "head", (1600, 870), (1780, 880)),
        ("tail1", "hips", (230, 700), (210, 780)),
        ("tail2", "tail1", (210, 780), (205, 820)),
        ("nh_thigh", "hips", (350, 1000), (330, 1250)),
        ("nh_shin", "nh_thigh", (330, 1250), (330, 1400)),
        ("nh_foot", "nh_shin", (330, 1400), (450, 1460)),
        ("fh_thigh", "hips", (650, 1050), (640, 1250)),
        ("fh_shin", "fh_thigh", (640, 1250), (660, 1400)),
        ("fh_foot", "fh_shin", (660, 1400), (790, 1440)),
        ("nf_upper", "chest", (1000, 1050), (1000, 1250)),
        ("nf_lower", "nf_upper", (1000, 1250), (1050, 1420)),
        ("nf_paw", "nf_lower", (1050, 1420), (1180, 1470)),
        ("ff_upper", "chest", (1300, 1000), (1290, 1250)),
        ("ff_lower", "ff_upper", (1290, 1250), (1330, 1400)),
        ("ff_paw", "ff_lower", (1330, 1400), (1470, 1450)),
    ],
    jaw=[(1600, 860), (1700, 870), (1790, 860), (1810, 850), (1780, 890), (1700, 900), (1630, 895)],
    mouth=[(1604, 862), (1700, 872), (1786, 862), (1804, 854), (1776, 886), (1700, 896), (1634, 891)],
    teeth=[],
    limits={
        "nh": [(195, 1130), (500, 1130), (500, 1300), (525, 1500), (195, 1500)],
        "fh": [(500, 1150), (870, 1150), (870, 1500), (525, 1500), (500, 1300)],
        "nf": [(870, 1100), (1150, 1100), (1150, 1350), (1215, 1500), (870, 1500)],
        "ff": [(1150, 1100), (1440, 1000), (1500, 1500), (1215, 1500), (1150, 1350)],
    },
    seeds={"nh": [(330, 1300)], "fh": [(650, 1350)], "nf": [(1000, 1350)], "ff": [(1300, 1350)]},
    lum_t=0.0,
    hole_y=1150,
    claw_y=1420,
    head_x=(1300, 1380),
    tail_x=260,
    stretch_center=(850, 1480),
    eye=(1660, 730),
), GRIZZLY_CROP[0], GRIZZLY_CROP[1])

# ---- 第二批（略帶俯視、站姿；符合 HD-2D 目標條件），cutout_scene.py 去背（含自帶影子） ----
WOLF_GRAY2 = dict(
    bones=[
        ("hips", None, (190, 280), (460, 270)),
        ("chest", "hips", (460, 270), (660, 230)),
        ("head", "chest", (680, 200), (890, 235)),
        ("jaw", "head", (810, 262), (880, 262)),
        ("tail1", "hips", (160, 230), (80, 380)),
        ("tail2", "tail1", (80, 380), (30, 520)),
        ("nh_thigh", "hips", (220, 330), (180, 450)),
        ("nh_shin", "nh_thigh", (180, 450), (140, 560)),
        ("nh_foot", "nh_shin", (140, 560), (150, 680)),
        ("fh_thigh", "hips", (320, 380), (300, 480)),
        ("fh_shin", "fh_thigh", (300, 480), (290, 570)),
        ("fh_foot", "fh_shin", (290, 570), (320, 630)),
        ("nf_upper", "chest", (560, 400), (560, 500)),
        ("nf_lower", "nf_upper", (560, 500), (575, 640)),
        ("nf_paw", "nf_lower", (575, 640), (610, 690)),
        ("ff_upper", "chest", (650, 420), (640, 520)),
        ("ff_lower", "ff_upper", (640, 520), (650, 630)),
        ("ff_paw", "ff_lower", (650, 630), (690, 655)),
    ],
    jaw=[(800, 255), (840, 258), (880, 250), (892, 245), (876, 270), (840, 282), (805, 275)],
    mouth=[(804, 257), (840, 260), (878, 252), (887, 249), (873, 268), (840, 279), (808, 273)],
    teeth=[],
    limits={
        "nh": [(95, 470), (200, 330), (250, 360), (240, 480), (205, 560), (205, 712), (95, 712)],
        "fh": [(230, 400), (380, 400), (370, 520), (365, 712), (230, 712), (225, 520)],
        "nf": [(505, 430), (600, 430), (598, 620), (650, 650), (660, 712), (505, 712)],
        "ff": [(602, 430), (735, 430), (735, 700), (668, 700), (655, 640), (604, 615)],
    },
    seeds={"nh": [(150, 560), (150, 670)], "fh": [(300, 500), (320, 620)], "nf": [(560, 550), (600, 680)], "ff": [(630, 520), (690, 650)]},
    lum_t=0.2, hole_y=430, claw_y=650, head_x=(640, 700), tail_x=150,
    stretch_center=(450, 700), eye=(783, 162),
)

GRIZZLY2 = dict(
    bones=[
        ("hips", None, (100, 250), (450, 250)),
        ("chest", "hips", (450, 250), (620, 300)),
        ("head", "chest", (600, 250), (800, 420)),
        ("jaw", "head", (745, 435), (800, 445)),
        ("tail1", "hips", (60, 220), (40, 260)),
        ("tail2", "tail1", (40, 260), (30, 280)),
        ("nh_thigh", "hips", (120, 380), (70, 520)),
        ("nh_shin", "nh_thigh", (70, 520), (90, 590)),
        ("nh_foot", "nh_shin", (90, 590), (150, 630)),
        ("fh_thigh", "hips", (330, 420), (320, 500)),
        ("fh_shin", "fh_thigh", (320, 500), (360, 540)),
        ("fh_foot", "fh_shin", (360, 540), (420, 570)),
        ("nf_upper", "chest", (500, 450), (540, 560)),
        ("nf_lower", "nf_upper", (540, 560), (600, 650)),
        ("nf_paw", "nf_lower", (600, 650), (680, 700)),
        ("ff_upper", "chest", (680, 470), (730, 540)),
        ("ff_lower", "ff_upper", (730, 540), (730, 600)),
        ("ff_paw", "ff_lower", (730, 600), (760, 630)),
    ],
    jaw=[(745, 428), (790, 432), (808, 428), (800, 450), (770, 458), (748, 448)],
    mouth=[(749, 430), (790, 434), (804, 431), (797, 447), (770, 455), (751, 446)],
    teeth=[],
    limits={
        "nh": [(5, 400), (240, 420), (240, 530), (180, 660), (5, 660)],
        "fh": [(250, 440), (450, 440), (450, 600), (270, 600)],
        "nf": [(455, 470), (660, 470), (660, 580), (700, 620), (700, 734), (470, 734), (455, 600)],
        "ff": [(665, 460), (820, 460), (820, 650), (705, 650), (700, 600), (665, 570)],
    },
    seeds={"nh": [(60, 560), (130, 620)], "fh": [(330, 520), (400, 570)], "nf": [(540, 560), (640, 690)], "ff": [(720, 540), (740, 620)]},
    lum_t=0.1, hole_y=470, claw_y=600, head_x=(560, 620), tail_x=70,
    stretch_center=(420, 700), eye=(720, 330),
)

ELK_COW = dict(
    bones=[
        ("hips", None, (60, 220), (300, 240)),
        ("chest", "hips", (300, 240), (450, 230)),
        ("head", "chest", (440, 170), (625, 145)),
        ("jaw", "head", (570, 165), (615, 170)),
        ("tail1", "hips", (25, 190), (15, 230)),
        ("tail2", "tail1", (15, 230), (12, 250)),
        ("nh_thigh", "hips", (60, 300), (40, 400)),
        ("nh_shin", "nh_thigh", (40, 400), (30, 470)),
        ("nh_foot", "nh_shin", (30, 470), (40, 545)),
        ("fh_thigh", "hips", (130, 320), (130, 400)),
        ("fh_shin", "fh_thigh", (130, 400), (150, 470)),
        ("fh_foot", "fh_shin", (150, 470), (165, 515)),
        ("nf_upper", "chest", (320, 340), (325, 450)),
        ("nf_lower", "nf_upper", (325, 450), (330, 560)),
        ("nf_paw", "nf_lower", (330, 560), (345, 615)),
        ("ff_upper", "chest", (385, 330), (380, 440)),
        ("ff_lower", "ff_upper", (380, 440), (385, 540)),
        ("ff_paw", "ff_lower", (385, 540), (400, 578)),
    ],
    jaw=[(570, 160), (600, 165), (622, 160), (620, 175), (600, 182), (575, 175)],
    mouth=[(573, 162), (600, 167), (618, 163), (617, 173), (600, 179), (577, 173)],
    teeth=[],
    limits={
        "nh": [(5, 330), (95, 330), (95, 420), (80, 560), (5, 560)],
        "fh": [(96, 300), (200, 300), (200, 530), (96, 530)],
        "nf": [(295, 340), (352, 340), (352, 560), (372, 640), (295, 640)],
        "ff": [(354, 330), (440, 330), (430, 600), (374, 600), (354, 560)],
    },
    seeds={"nh": [(35, 450), (40, 540)], "fh": [(140, 420), (160, 510)], "nf": [(325, 450), (345, 610)], "ff": [(380, 440), (395, 570)]},
    lum_t=0.1, hole_y=340, claw_y=600, head_x=(430, 480), tail_x=40,
    stretch_center=(230, 620), eye=(515, 100),
)

ELK_BULL = dict(
    bones=[
        ("hips", None, (40, 280), (290, 320)),
        ("chest", "hips", (290, 320), (440, 330)),
        ("head", "chest", (440, 310), (590, 440)),
        ("jaw", "head", (550, 445), (590, 455)),
        ("tail1", "hips", (20, 240), (10, 280)),
        ("tail2", "tail1", (10, 280), (8, 300)),
        ("nh_thigh", "hips", (50, 350), (40, 450)),
        ("nh_shin", "nh_thigh", (40, 450), (30, 520)),
        ("nh_foot", "nh_shin", (30, 520), (45, 590)),
        ("fh_thigh", "hips", (130, 400), (140, 470)),
        ("fh_shin", "fh_thigh", (140, 470), (150, 530)),
        ("fh_foot", "fh_shin", (150, 530), (170, 570)),
        ("nf_upper", "chest", (300, 470), (300, 580)),
        ("nf_lower", "nf_upper", (300, 580), (305, 680)),
        ("nf_paw", "nf_lower", (305, 680), (320, 720)),
        ("ff_upper", "chest", (390, 470), (385, 560)),
        ("ff_lower", "ff_upper", (385, 560), (390, 630)),
        ("ff_paw", "ff_lower", (390, 630), (405, 665)),
    ],
    jaw=[(545, 445), (575, 448), (592, 445), (588, 462), (565, 470), (548, 460)],
    mouth=[(549, 447), (575, 450), (588, 448), (585, 459), (565, 467), (551, 458)],
    teeth=[],
    limits={
        "nh": [(5, 380), (95, 380), (95, 600), (5, 600)],
        "fh": [(96, 390), (210, 390), (210, 590), (96, 590)],
        "nf": [(260, 480), (345, 480), (345, 740), (260, 740)],
        "ff": [(346, 470), (440, 470), (440, 690), (346, 690)],
    },
    seeds={"nh": [(40, 480), (45, 580)], "fh": [(140, 460), (170, 565)], "nf": [(300, 600), (315, 715)], "ff": [(390, 560), (400, 660)]},
    lum_t=0.1, hole_y=470, claw_y=650, head_x=(430, 500), tail_x=30,
    head_poly=[(200, 20), (680, 0), (680, 480), (540, 480), (440, 360), (340, 275), (270, 250), (200, 200)],
    stretch_center=(230, 720), eye=(488, 378),
)

HARE_W = dict(
    bones=[
        ("hips", None, (80, 300), (420, 330)),
        ("chest", "hips", (420, 330), (560, 300)),
        ("head", "chest", (580, 250), (780, 300)),
        ("jaw", "head", (720, 320), (770, 330)),
        ("tail1", "hips", (60, 320), (20, 330)),
        ("tail2", "tail1", (20, 330), (5, 335)),
        ("nh_thigh", "hips", (140, 420), (100, 520)),
        ("nh_shin", "nh_thigh", (100, 520), (90, 600)),
        ("nh_foot", "nh_shin", (90, 600), (150, 680)),
        ("fh_thigh", "hips", (250, 420), (230, 520)),
        ("fh_shin", "fh_thigh", (230, 520), (270, 600)),
        ("fh_foot", "fh_shin", (270, 600), (330, 630)),
        ("nf_upper", "chest", (500, 450), (510, 550)),
        ("nf_lower", "nf_upper", (510, 550), (530, 640)),
        ("nf_paw", "nf_lower", (530, 640), (570, 690)),
        ("ff_upper", "chest", (590, 440), (590, 540)),
        ("ff_lower", "ff_upper", (590, 540), (610, 620)),
        ("ff_paw", "ff_lower", (610, 620), (645, 660)),
    ],
    jaw=[(715, 318), (745, 322), (772, 318), (768, 335), (745, 342), (720, 335)],
    mouth=[(718, 320), (745, 324), (768, 320), (765, 333), (745, 339), (722, 333)],
    teeth=[],
    limits={
        "nh": [(30, 470), (170, 440), (200, 500), (205, 717), (30, 717)],
        "fh": [(170, 430), (360, 420), (360, 660), (215, 660), (205, 500)],
        "nf": [(450, 470), (545, 480), (548, 600), (590, 640), (600, 717), (460, 717)],
        "ff": [(548, 460), (670, 460), (670, 680), (600, 680), (595, 630), (550, 600)],
    },
    seeds={"nh": [(80, 560), (120, 670)], "fh": [(240, 520), (300, 625)], "nf": [(500, 560), (550, 690)], "ff": [(600, 540), (630, 660)]},
    lum_t=0.3, hole_y=450, claw_y=670, head_x=(560, 620), tail_x=70,
    stretch_center=(350, 700), eye=(683, 236),
)

WOLVES = {"wolf_gray": WOLF_GRAY, "wolf_black": WOLF_BLACK, "grizzly": GRIZZLY,
          "wolf_gray2": WOLF_GRAY2, "grizzly2": GRIZZLY2, "elk_cow": ELK_COW, "elk_bull": ELK_BULL, "hare_winter": HARE_W}
# 本體高度：狼 30 像素，其他照相對灰狼的比例（灰熊 1.5）
BODY = {"wolf_gray": 30, "wolf_black": 30, "grizzly": 45,
        "wolf_gray2": 30, "grizzly2": 45, "elk_cow": 60, "elk_bull": 78, "hare_winter": 15}
EYES = {"wolf_gray": (222, 160, 70), "wolf_black": (226, 196, 80), "grizzly": (40, 30, 26),
        "wolf_gray2": (222, 160, 70), "grizzly2": (150, 92, 48), "elk_cow": (40, 30, 26), "elk_bull": (40, 30, 26),
        "hare_winter": (30, 24, 24)}
# 遊戲裡用的 ID（第二批取代第一批的灰狼、灰熊），以及獵物只做待機、走路、受傷
GAME_ID = {"wolf_gray2": "wolf_gray", "grizzly2": "grizzly", "hare_winter": "hare"}
PREY = {"elk_cow", "elk_bull", "hare_winter"}


def crop_grizzly():
    """去背圖右上角帶到浮水印，只保留熊的範圍。"""
    p = os.path.join(HERE, "cut", "grizzly.png")
    im = Image.open(p)
    if im.size != (GRIZZLY_CROP[2] - GRIZZLY_CROP[0], GRIZZLY_CROP[3] - GRIZZLY_CROP[1]):
        im.crop(GRIZZLY_CROP).save(p)


def eye_point(cfg, bones, pose, k):
    mats = rig.world_mats(bones, pose)
    p = mats["head"] @ np.array([cfg["eye"][0], cfg["eye"][1], 1.0])
    return int((p[0] + rig.PAD) * rig.SCALE * k), int((p[1] + rig.PAD) * rig.SCALE * k)


def export(aid, cfg, eye_rgb, body_px=BODY_PX):
    import animals
    rig.SCALE = 0.5
    # 雪兔的後腿沒有內部外框，切線是直的，所以不擺腿，整隻跳（HARE_ACTIONS）
    actions = animals.HARE_ACTIONS if aid == "hare_winter" else (animals.PREY_ACTIONS if aid in PREY else rig.ACTIONS)
    acts_hi = rig.render_actions(aid, cfg, HERE, actions)
    rest_hi = Image.open(os.path.join(HERE, "anim", f"{aid}_rest.png"))
    bb = rest_hi.getbbox()
    k = body_px / (bb[3] - bb[1])
    bones = [rig.Bone(*b) for b in cfg["bones"]]
    pixel_rig.EYE_RGB = eye_rgb
    rest_px, pal = pixel_rig.pixelize(rest_hi, k, outline="shade")
    pixel_rig.put_eye(rest_px, eye_point(cfg, bones, {}, k))
    acts = {}
    for act, frames in acts_hi.items():
        fn, n = actions[act]
        acts[act] = [pixel_rig.put_eye(pixel_rig.pixelize(f, k, pal, "shade")[0], eye_point(cfg, bones, fn(i / n), k))
                     for i, f in enumerate(frames)]
    acts = export_game.bite_trails(acts)
    gid = GAME_ID.get(aid, aid)
    export_game.REL.setdefault(gid, body_px / 30.0)
    return export_game.write_animal("scene", gid, acts, rest_px)


def main():
    crop_grizzly()
    only = [a for a in sys.argv[1:] if a != "check"]
    names = only or list(WOLVES)
    if "check" in sys.argv[1:]:
        for aid in names:
            rig.wolf_rig(aid, WOLVES[aid], HERE)
        return
    path = os.path.join(export_game.OUT, "manifest.json")
    manifest = json.load(open(path, encoding="utf-8"))
    manifest.setdefault("scene", {})
    for aid in names:
        gid = GAME_ID.get(aid, aid)
        manifest["scene"][gid] = export(aid, WOLVES[aid], EYES[aid], BODY[aid])
        print(aid, "->", gid, manifest["scene"][gid]["frame"])
    json.dump(manifest, open(path, "w", encoding="utf-8"), ensure_ascii=False, indent=1)


if __name__ == "__main__":
    main()
