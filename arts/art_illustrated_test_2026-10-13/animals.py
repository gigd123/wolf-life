"""插畫版其他動物的骨架設定（座標都是 cut/<動物>.png 的原尺寸）。格式同 rig.WOLF_ILLUS。"""
import rig

# 黑狼：和灰狼同一個底（身體、頭、尾巴的座標相同），近側前腿是走路時抬起的姿勢。毛色深，切腿的亮度門檻調低。
WOLF_BLACK = dict(rig.WOLF_ILLUS)
WOLF_BLACK.update(
    bones=[b for b in rig.WOLF_ILLUS["bones"] if not b[0].startswith(("nf_", "ff_"))] + [
        ("nf_upper", "chest", (630, 330), (615, 420)),
        ("nf_lower", "nf_upper", (615, 420), (640, 560)),
        ("nf_paw", "nf_lower", (640, 560), (680, 615)),
        ("ff_upper", "chest", (740, 330), (800, 440)),
        ("ff_lower", "ff_upper", (800, 440), (792, 520)),
        ("ff_paw", "ff_lower", (792, 520), (770, 592)),
    ],
    limits={
        "nh": [(108, 470), (150, 412), (250, 364), (338, 364), (338, 420), (270, 470), (222, 520), (222, 648), (80, 648), (96, 540)],
        "fh": [(300, 372), (458, 372), (450, 470), (500, 560), (500, 648), (360, 648), (284, 520), (296, 440)],
        "nf": [(560, 364), (700, 364), (705, 560), (732, 648), (590, 648), (572, 480)],
        "ff": [(702, 364), (846, 364), (846, 624), (738, 624), (744, 470), (706, 420)],
    },
    seeds={"nh": [(160, 560), (250, 430)], "fh": [(370, 480), (420, 590)], "nf": [(620, 480), (670, 620)], "ff": [(800, 470), (785, 560)]},
    lum_t=0.13,
    claw_y=570,
)

# 灰熊：四肢粗、遠側前腿往前跨，尾巴很短（尾巴骨只影響臀部後緣一小塊）。
GRIZZLY = dict(
    bones=[
        ("hips", None, (220, 250), (600, 230)),
        ("chest", "hips", (600, 230), (880, 220)),
        ("head", "chest", (880, 180), (1135, 285)),
        ("jaw", "head", (1030, 306), (1110, 320)),
        ("tail1", "hips", (95, 200), (75, 240)),
        ("tail2", "tail1", (75, 240), (62, 262)),
        ("nh_thigh", "hips", (170, 300), (150, 470)),
        ("nh_shin", "nh_thigh", (150, 470), (110, 580)),
        ("nh_foot", "nh_shin", (110, 580), (150, 650)),
        ("fh_thigh", "hips", (360, 380), (360, 500)),
        ("fh_shin", "fh_thigh", (360, 500), (380, 590)),
        ("fh_foot", "fh_shin", (380, 590), (460, 630)),
        ("nf_upper", "chest", (650, 330), (660, 480)),
        ("nf_lower", "nf_upper", (660, 480), (670, 600)),
        ("nf_paw", "nf_lower", (670, 600), (740, 650)),
        ("ff_upper", "chest", (800, 380), (870, 500)),
        ("ff_lower", "ff_upper", (870, 500), (930, 580)),
        ("ff_paw", "ff_lower", (930, 580), (1000, 630)),
    ],
    jaw=[(1028, 302), (1060, 312), (1100, 316), (1120, 310), (1112, 326), (1080, 335), (1048, 331), (1030, 318)],
    mouth=[(1031, 304), (1060, 314), (1100, 318), (1116, 313), (1108, 324), (1080, 332), (1050, 328), (1033, 317)],
    teeth=[(1082, 315, 6, 10), (1097, 315, 6, 10)],
    limits={
        "nh": [(20, 420), (120, 380), (262, 380), (270, 440), (204, 560), (204, 684), (16, 684)],
        "fh": [(266, 400), (462, 400), (452, 560), (512, 600), (512, 684), (290, 684), (280, 520)],
        "nf": [(548, 380), (752, 380), (752, 560), (795, 600), (795, 684), (568, 684), (556, 520)],
        "ff": [(754, 400), (890, 380), (952, 520), (1044, 590), (1044, 684), (900, 684), (842, 560), (754, 560)],
    },
    seeds={"nh": [(100, 600), (190, 470)], "fh": [(350, 550), (400, 620)], "nf": [(650, 520), (700, 640)], "ff": [(850, 520), (980, 620)]},
    lum_t=0.06,
    hole_y=460,
    claw_y=600,
    head_x=(860, 930),
    tail_x=100,
    stretch_center=(560, 650),
)

# 馬鹿母鹿：長腿、深色的腿與頸鬃；近側前腿是右邊那條（蹄比較低）。
ELK_COW = dict(
    bones=[
        ("hips", None, (150, 250), (520, 235)),
        ("chest", "hips", (520, 235), (680, 165)),
        ("head", "chest", (660, 120), (895, 175)),
        ("jaw", "head", (830, 188), (892, 192)),
        ("tail1", "hips", (72, 232), (42, 270)),
        ("tail2", "tail1", (42, 270), (30, 300)),
        ("nh_thigh", "hips", (110, 300), (90, 450)),
        ("nh_shin", "nh_thigh", (90, 450), (40, 560)),
        ("nh_foot", "nh_shin", (40, 560), (50, 722)),
        ("fh_thigh", "hips", (200, 380), (170, 520)),
        ("fh_shin", "fh_thigh", (170, 520), (230, 640)),
        ("fh_foot", "fh_shin", (230, 640), (270, 710)),
        ("nf_upper", "chest", (520, 380), (500, 520)),
        ("nf_lower", "nf_upper", (500, 520), (510, 650)),
        ("nf_paw", "nf_lower", (510, 650), (540, 722)),
        ("ff_upper", "chest", (450, 400), (450, 520)),
        ("ff_lower", "ff_upper", (450, 520), (440, 650)),
        ("ff_paw", "ff_lower", (440, 650), (452, 712)),
    ],
    jaw=[(828, 186), (860, 191), (888, 191), (897, 187), (889, 201), (862, 209), (840, 206)],
    mouth=[(831, 188), (860, 193), (886, 193), (893, 190), (886, 199), (862, 206), (842, 204)],
    teeth=[],
    limits={
        "nh": [(8, 420), (80, 380), (150, 392), (152, 444), (100, 520), (86, 746), (4, 746)],
        "fh": [(152, 392), (262, 392), (262, 520), (302, 700), (302, 746), (198, 746), (140, 540), (146, 446)],
        "ff": [(406, 426), (482, 426), (482, 700), (482, 746), (398, 746), (404, 600)],
        "nf": [(482, 416), (582, 416), (562, 600), (584, 746), (498, 746), (482, 600)],
    },
    seeds={"nh": [(40, 620), (110, 450)], "fh": [(200, 560), (260, 690)], "ff": [(445, 560), (440, 700)], "nf": [(512, 560), (530, 712)]},
    lum_t=0.08,
    hole_y=445,
    claw_y=690,
    head_x=(620, 690),
    tail_x=78,
    stretch_center=(300, 720),
)


# ---------------- 雪兔：簡化骨架（身體、頭、耳朵、前腳），後腳收在身體下跟著身體動 ----------------
import math
import os

import numpy as np
from PIL import Image

HARE = dict(stretch_center=(420, 690))


def hare_rig(name="hare_summer", cfg=HARE, base=rig.HERE):
    rig.STRETCH_CENTER = cfg["stretch_center"]
    img = Image.open(os.path.join(base, "cut", name + ".png")).convert("RGBA")
    W0, H0 = img.size
    bones = [
        rig.Bone("hips", None, (120, 470), (560, 330)),
        rig.Bone("head", "hips", (600, 300), (850, 320)),
        rig.Bone("ears", "head", (630, 230), (585, 40)),
        rig.Bone("front", "hips", (560, 460), (630, 680)),
    ]
    small = np.asarray(img.resize((int(W0 * rig.SCALE), int(H0 * rig.SCALE)), Image.LANCZOS)).astype(float) / 255.0
    tex = small.copy()
    tex[..., :3] *= tex[..., 3:4]
    head_only = lambda p: np.clip((p[:, 0] - 560) / 50, 0, 1)
    ears_only = lambda p: np.clip((235 - p[:, 1]) / 25, 0, 1) * (p[:, 0] > 500)
    front_only = lambda p: np.clip((p[:, 1] - 480) / 40, 0, 1) * np.clip((p[:, 0] - 470) / 30, 0, 1)
    layer = rig.Layer("body", tex, bones, ["hips", "head", "ears", "front"],
                      bias={"head": head_only, "ears": ears_only, "front": front_only})
    return bones, [layer], (W0, H0)


def hare_idle(t):
    s = math.sin(t * 2 * math.pi)
    return {"root_sy": 1 + 0.012 * s, "head": 1.5 * s, "ears": -4 * max(0.0, math.sin(t * 4 * math.pi))}


HOP_KEYS = [
    (0.00, {}),
    (0.25, dict(root_sx=1.06, root_sy=0.9, hips=4, head=4, ears=8, front=10)),           # 蹲低蓄力
    (0.50, dict(root_dx=40, root_dy=-110, root_sx=1.14, root_sy=0.92, hips=-14, head=-6, ears=16, front=-40)),  # 騰空
    (0.78, dict(root_dx=10, root_dy=0, root_sx=1.04, root_sy=0.93, hips=8, head=4, ears=6, front=12)),  # 落地
    (1.00, {}),
]


def hare_hop(t):
    """逃跑時的一跳（原地循環）：蹲低 → 騰空 → 落地。往前移動由場景負責，遊戲裡會翻轉成往遠離狼的方向。"""
    return rig.keyframes(HOP_KEYS, t)


def hare_hurt(t):
    k = math.sin(min(1.0, t / 0.3) * math.pi / 2) if t < 0.3 else max(0.0, 1 - (t - 0.3) / 0.7)
    return {"root_dx": -30 * k, "root_sy": 1 - 0.08 * k, "hips": 6 * k, "head": -12 * k, "ears": 20 * k}


HARE_ACTIONS = {"idle": (hare_idle, 12), "hop": (hare_hop, 12), "hurt": (hare_hurt, 8)}


# 獵物（馬鹿）不咬：待機、走路（逃跑時加快播放）、受傷
def elk_walk(t):
    q = rig.pose_walk(t)
    return {k: v * 0.8 for k, v in q.items()}


PREY_ACTIONS = {"idle": (rig.pose_idle, 12), "walk": (elk_walk, 12), "hurt": (rig.pose_hurt, 8)}
