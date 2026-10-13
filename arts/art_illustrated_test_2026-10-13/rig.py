"""插畫風動物的骨架動畫（預先算成影格）。

做法：把去背後的插畫依遮罩分成幾層（遠側的腿 → 身體 → 下顎 → 近側的腿），每層鋪三角網格，
每個頂點依和骨頭的距離分配權重（線性混合蒙皮），擺好姿勢後把變形的三角形逐一貼回去。
關節附近的頂點同時跟著兩根骨頭動，所以彎曲時是平順的，不會有紙片接縫。

座標都用 cut/<動物>.png 的原尺寸；SCALE 是實際運算與輸出的縮放。
用法：python3 rig.py            → 輸出灰狼的預覽 GIF 與 spritesheet 到 anim/
"""
import math
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
SCALE = 0.5
PAD = 120          # 畫布四周的空間（原尺寸像素），撲咬往前衝時不會被切掉
STRETCH_CENTER = (560, 600)  # 腳底附近，伸縮時腳不會離地太多
GRID = 14         # 網格間距（原尺寸像素）


# ---------------- 骨架 ----------------
class Bone:
    def __init__(self, name, parent, a, b):
        self.name, self.parent, self.a, self.b = name, parent, np.array(a, float), np.array(b, float)


def rot_about(p, deg):
    """繞 p 旋轉的 3x3 仿射矩陣（畫面座標 y 向下，正角度＝順時針）。"""
    t = math.radians(deg)
    c, s = math.cos(t), math.sin(t)
    px, py = p
    return np.array([[c, -s, px - c * px + s * py], [s, c, py - s * px - c * py], [0, 0, 1]])


def translate(dx, dy):
    return np.array([[1, 0, dx], [0, 1, dy], [0, 0, 1]], float)


def world_mats(bones, pose):
    """pose：{骨頭名: 角度}，另外 "root_dx"、"root_dy" 平移整隻。回傳 {骨頭名: 3x3}。"""
    mats = {}
    for b in bones:  # 骨頭依父子順序排列
        local = rot_about(b.a, pose.get(b.name, 0.0))
        if b.parent is None:
            # 壓縮與伸展：以身體中心為準縮放（root_sx 水平、root_sy 垂直）
            cx, cy = STRETCH_CENTER
            sx, sy = pose.get("root_sx", 1.0), pose.get("root_sy", 1.0)
            stretch = translate(cx, cy) @ np.diag([sx, sy, 1.0]) @ translate(-cx, -cy)
            mats[b.name] = translate(pose.get("root_dx", 0.0), pose.get("root_dy", 0.0)) @ stretch @ local
        else:
            mats[b.name] = mats[b.parent] @ local
    return mats


def seg_dist(p, a, b):
    ab = b - a
    t = np.clip(((p - a) @ ab) / (ab @ ab), 0, 1)
    return np.linalg.norm(p - (a + t[:, None] * ab), axis=1)


# ---------------- 圖層與網格 ----------------
class Layer:
    def __init__(self, name, tex, bones, weight_bones, falloff=4.0, bias=None):
        """tex：這一層的 RGBA（float、已乘 alpha）；weight_bones：這層會跟著動的骨頭。
        bias：{骨頭名: 函式(點陣列) -> 權重倍率}，用來限制某根骨頭只影響某個範圍。"""
        self.name, self.tex = name, tex
        h, w = tex.shape[:2]
        alpha = tex[..., 3]
        step = GRID * SCALE
        xs = np.arange(0, w + step, step)
        ys = np.arange(0, h + step, step)
        gx, gy = np.meshgrid(xs, ys)
        self.verts = np.stack([gx.ravel(), gy.ravel()], 1)
        nx = len(xs)
        tris = []
        # 只保留蓋到不透明像素的格子
        for j in range(len(ys) - 1):
            for i in range(len(xs) - 1):
                x0, y0 = int(xs[i]), int(ys[j])
                x1, y1 = min(w, int(xs[i + 1]) + 1), min(h, int(ys[j + 1]) + 1)
                if x0 >= w or y0 >= h or alpha[y0:y1, x0:x1].max() <= 0.01:
                    continue
                v0, v1, v2, v3 = j * nx + i, j * nx + i + 1, (j + 1) * nx + i, (j + 1) * nx + i + 1
                tris += [(v0, v1, v3), (v0, v3, v2)]
        self.tris = np.array(tris, int)
        # 權重：和骨頭（線段）的距離越近越大
        pts = self.verts / SCALE
        ws = []
        for bn in weight_bones:
            b = next(x for x in bones if x.name == bn)
            d = seg_dist(pts, b.a, b.b)
            wv = 1.0 / (d / 40.0 + 0.15) ** falloff
            if bias and bn in bias:
                wv = wv * bias[bn](pts)
            ws.append(wv)
        ws = np.array(ws)
        self.weights = ws / ws.sum(0, keepdims=True)
        self.weight_bones = weight_bones

    def deform(self, mats):
        p = np.concatenate([self.verts / SCALE, np.ones((len(self.verts), 1))], 1)
        out = np.zeros((len(p), 2))
        for k, bn in enumerate(self.weight_bones):
            out += self.weights[k][:, None] * (p @ mats[bn].T)[:, :2]
        return out * SCALE


def sample_bilinear(tex, x, y):
    h, w = tex.shape[:2]
    x = np.clip(x, 0, w - 1.001)
    y = np.clip(y, 0, h - 1.001)
    x0, y0 = np.floor(x).astype(int), np.floor(y).astype(int)
    fx, fy = (x - x0)[:, None], (y - y0)[:, None]
    c00, c10 = tex[y0, x0], tex[y0, x0 + 1]
    c01, c11 = tex[y0 + 1, x0], tex[y0 + 1, x0 + 1]
    return (c00 * (1 - fx) + c10 * fx) * (1 - fy) + (c01 * (1 - fx) + c11 * fx) * fy


def raster(layer, dst, out_shape, offset):
    """把變形後的網格畫到一張新的圖層緩衝（重疊處直接覆寫）。"""
    H, W = out_shape
    buf = np.zeros((H, W, 4))
    src = layer.verts
    for t in layer.tris:
        d = dst[t] + offset
        s = src[t]
        x0, y0 = np.floor(d.min(0)).astype(int)
        x1, y1 = np.ceil(d.max(0)).astype(int)
        x0, y0, x1, y1 = max(x0, 0), max(y0, 0), min(x1, W - 1), min(y1, H - 1)
        if x1 < x0 or y1 < y0:
            continue
        m = np.array([[d[1, 0] - d[0, 0], d[2, 0] - d[0, 0]], [d[1, 1] - d[0, 1], d[2, 1] - d[0, 1]]])
        det = np.linalg.det(m)
        if abs(det) < 1e-6:
            continue
        inv = np.linalg.inv(m)
        gx, gy = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
        rel = np.stack([gx.ravel() - d[0, 0], gy.ravel() - d[0, 1]])
        uv = inv @ rel
        u, v = uv
        inside = (u >= -0.02) & (v >= -0.02) & (u + v <= 1.02)
        if not inside.any():
            continue
        u, v = u[inside], v[inside]
        sx = s[0, 0] + u * (s[1, 0] - s[0, 0]) + v * (s[2, 0] - s[0, 0])
        sy = s[0, 1] + u * (s[1, 1] - s[0, 1]) + v * (s[2, 1] - s[0, 1])
        col = sample_bilinear(layer.tex, sx, sy)
        px = (gx.ravel()[inside] - 0.5).astype(int)
        py = (gy.ravel()[inside] - 0.5).astype(int)
        buf[py, px] = col
    return buf


def over(dst, src):
    a = src[..., 3:4]
    return src + dst * (1 - a)


# ---------------- 灰狼 ----------------
def seg_leg(src, limit_img, seeds, lum_t=0.26, grow=5, claw_y=575):
    from scipy import ndimage
    lim = np.asarray(limit_img) > 0
    alpha = src[..., 3] > 0.5
    lum = src[..., :3].mean(2)
    passable = lim & alpha & (lum > lum_t)
    lab, _ = ndimage.label(passable)
    ids = {lab[y, x] for x, y in seeds if lab[y, x] > 0}
    region = np.isin(lab, list(ids))
    region = ndimage.binary_closing(region, iterations=3)
    region = ndimage.binary_fill_holes(region)
    region = ndimage.binary_dilation(region, iterations=grow) & lim & (src[..., 3] > 0.02)
    # 爪子是黑的，長不過去：腳掌附近（y ≥ claw_y）離腳 14 像素內的深色像素也收進來
    near = ndimage.binary_dilation(region, iterations=14)
    yy = np.arange(src.shape[0])[:, None]
    region |= near & lim & (yy >= claw_y) & (src[..., 3] > 0.02)
    return region


# 插畫風灰狼的設定（cut/wolf_gray.png 的座標）。別的圖照同樣的格式給一份。
WOLF_ILLUS = dict(
    bones=[
        ("hips", None, (330, 262), (560, 250)),
        ("chest", "hips", (560, 250), (790, 225)),
        ("head", "chest", (800, 220), (1040, 230)),
        ("jaw", "head", (948, 240), (1035, 256)),
        ("tail1", "hips", (238, 236), (140, 322)),
        ("tail2", "tail1", (140, 322), (30, 440)),
        ("nh_thigh", "hips", (262, 300), (302, 396)),
        ("nh_shin", "nh_thigh", (302, 396), (140, 462)),
        ("nh_foot", "nh_shin", (140, 462), (165, 615)),
        ("fh_thigh", "hips", (395, 330), (395, 420)),
        ("fh_shin", "fh_thigh", (395, 420), (320, 502)),
        ("fh_foot", "fh_shin", (320, 502), (440, 600)),
        ("nf_upper", "chest", (630, 330), (612, 410)),
        ("nf_lower", "nf_upper", (612, 410), (622, 556)),
        ("nf_paw", "nf_lower", (622, 556), (675, 615)),
        ("ff_upper", "chest", (716, 330), (715, 410)),
        ("ff_lower", "ff_upper", (715, 410), (706, 556)),
        ("ff_paw", "ff_lower", (706, 556), (765, 600)),
    ],
    # 下顎（張嘴時轉動的部分）與嘴裡的深色（只填在下顎原本的位置，閉嘴時完全被蓋住）、上排犬齒
    jaw=[(944, 240), (975, 247), (1005, 251), (1035, 249), (1048, 245), (1042, 258), (1010, 270), (985, 270), (958, 263), (944, 254)],
    mouth=[(946, 242), (975, 248), (1005, 252), (1035, 250), (1044, 247), (1038, 257), (1010, 267), (986, 267), (960, 261), (946, 253)],
    teeth=[(1012, 249, 6, 10), (1026, 249, 6, 10)],
    # 腿：從種子點往外長，碰到黑色外框就停（限制在 limits 範圍內），再往外擴幾像素把自己的外框收進來
    limits={
        "nh": [(108, 470), (150, 412), (250, 364), (338, 364), (338, 420), (270, 470), (222, 520), (222, 648), (80, 648), (96, 540)],
        "fh": [(300, 372), (458, 372), (450, 470), (500, 560), (500, 648), (360, 648), (284, 520), (296, 440)],
        "nf": [(562, 364), (674, 364), (676, 420), (700, 540), (750, 600), (750, 648), (580, 648), (580, 470)],
        "ff": [(676, 364), (796, 364), (790, 470), (830, 600), (830, 648), (700, 648), (690, 540), (678, 420)],
    },
    seeds={"nh": [(170, 540), (240, 420)], "fh": [(370, 470), (420, 590)], "nf": [(630, 480), (650, 610)], "ff": [(735, 470), (770, 590)]},
    hole_y=398,          # 身體只挖掉這條線以下的腿，腿層往上到 limits 的頂端，兩者重疊不露縫
    claw_y=575,          # 爪子（深色）從這裡往下收進腿
    head_x=(770, 830),   # 頭骨只影響 x > 770；胸骨在 x > 830 幾乎不影響
    tail_x=262,          # 尾巴骨只影響 x < 262
    stretch_center=(560, 600),
)


def wolf_rig(name="wolf_gray", cfg=WOLF_ILLUS, base=HERE):
    global STRETCH_CENTER
    STRETCH_CENTER = cfg["stretch_center"]
    img = Image.open(os.path.join(base, "cut", name + ".png")).convert("RGBA")
    W0, H0 = img.size
    os.makedirs(os.path.join(base, "anim"), exist_ok=True)
    bones = [Bone(*b) for b in cfg["bones"]]
    # 補畫：例如把眼睛放大到縮小後至少一格（像素版用）
    for x0, y0, x1, y1, col in cfg.get("paint", []):
        ImageDraw.Draw(img).rectangle([x0, y0, x1, y1], fill=col)

    def mask_of(poly):
        m = Image.new("L", (W0, H0), 0)
        ImageDraw.Draw(m).polygon(poly, fill=255)
        return m

    src = np.asarray(img).astype(float) / 255.0
    small = np.asarray(img.resize((int(W0 * SCALE), int(H0 * SCALE)), Image.LANCZOS)).astype(float) / 255.0

    def tex_from(mask_img, base_arr=None):
        m = np.asarray(mask_img.resize((int(W0 * SCALE), int(H0 * SCALE)), Image.BILINEAR)).astype(float)[..., None] / 255
        t = (base_arr if base_arr is not None else small).copy()
        t[..., 3:4] *= m
        t[..., :3] *= t[..., 3:4]
        return t

    leg_masks = {k: seg_leg(src, mask_of(cfg["limits"][k]), cfg["seeds"][k], lum_t=cfg.get("lum_t", 0.26), claw_y=cfg["claw_y"]) for k in cfg["limits"]}
    yy = np.arange(H0)[:, None]
    body_hole = np.zeros((H0, W0), bool)
    from scipy import ndimage
    for m in leg_masks.values():
        body_hole |= ndimage.binary_dilation(m, iterations=4) & (yy >= cfg["hole_y"])
    body_mask = Image.fromarray(np.where(body_hole, 0, 255).astype(np.uint8))
    leg_masks = {k: Image.fromarray((m * 255).astype(np.uint8)) for k, m in leg_masks.items()}
    dbg = np.asarray(img).copy()
    for k, col in zip(leg_masks, [(255, 0, 0), (0, 160, 255), (0, 200, 0), (255, 160, 0)]):
        m = np.asarray(leg_masks[k]) > 0
        dbg[m, :3] = (dbg[m, :3] * 0.4 + np.array(col) * 0.6).astype(np.uint8)
    Image.fromarray(dbg).save(os.path.join(base, "anim", name + "_masks.png"))

    body_img = img.copy()
    d = ImageDraw.Draw(body_img)
    d.polygon(cfg["mouth"], fill=(34, 26, 25, 255))
    for x, y, w, h in cfg["teeth"]:
        d.polygon([(x, y), (x + w, y), (x + w // 3, y + h)], fill=(236, 230, 214, 255))
    body_small = np.asarray(body_img.resize(small.shape[1::-1], Image.LANCZOS)).astype(float) / 255.0

    h0, h1 = cfg["head_x"]
    tx = cfg["tail_x"]
    head_only = lambda p: np.clip((p[:, 0] - h0) / 40, 0, 1)
    not_head = lambda p: np.clip((h1 - p[:, 0]) / 60, 0.02, 1)
    if "head_poly" in cfg:
        # 頭的範圍用多邊形指定（例如公鹿往後展開的角，x 比頸部還小）
        hm = np.asarray(mask_of(cfg["head_poly"]).filter(ImageFilter.GaussianBlur(12))).astype(float) / 255
        sample = lambda p: hm[np.clip(p[:, 1].astype(int), 0, H0 - 1), np.clip(p[:, 0].astype(int), 0, W0 - 1)]
        head_only = sample
        not_head = lambda p: np.clip(1 - sample(p), 0.02, 1)
    tail_only = lambda p: np.clip((tx - p[:, 0]) / 30, 0, 1)

    layers = [
        Layer("fh", tex_from(leg_masks["fh"]), bones, ["hips", "fh_thigh", "fh_shin", "fh_foot"]),
        Layer("ff", tex_from(leg_masks["ff"]), bones, ["chest", "ff_upper", "ff_lower", "ff_paw"]),
        Layer("body", tex_from(body_mask, body_small), bones, ["hips", "chest", "head", "tail1", "tail2"],
              bias={"head": head_only, "chest": not_head, "tail1": tail_only, "tail2": tail_only}),
        Layer("jaw", tex_from(mask_of(cfg["jaw"])), bones, ["jaw"]),
        Layer("nh", tex_from(leg_masks["nh"]), bones, ["hips", "nh_thigh", "nh_shin", "nh_foot"]),
        Layer("nf", tex_from(leg_masks["nf"]), bones, ["chest", "nf_upper", "nf_lower", "nf_paw"]),
    ]
    return bones, layers, (W0, H0)


def render(bones, layers, size0, pose):
    W0, H0 = size0
    W, H = int((W0 + PAD * 2) * SCALE), int((H0 + PAD * 2) * SCALE)
    mats = world_mats(bones, pose)
    out = np.zeros((H, W, 4))
    off = np.array([PAD * SCALE, PAD * SCALE])
    for ly in layers:
        out = over(out, raster(ly, ly.deform(mats), (H, W), off))
    rgb = np.where(out[..., 3:4] > 1e-4, out[..., :3] / np.maximum(out[..., 3:4], 1e-4), 0)
    arr = np.concatenate([rgb, out[..., 3:4]], 2)
    return Image.fromarray((np.clip(arr, 0, 1) * 255).astype(np.uint8), "RGBA")


# ---------------- 動作 ----------------
def pose_idle(t):
    """待機：呼吸（胸口起伏）、頭微微點、尾巴輕擺。t 0..1。"""
    s = math.sin(t * 2 * math.pi)
    return {"chest": -0.8 * s, "head": 1.2 * s, "tail1": 2.5 * s, "tail2": 3.0 * math.sin(t * 2 * math.pi - 0.8),
            "root_dy": 1.2 * s, "nf_upper": 0.8 * s, "ff_upper": 0.8 * s, "nh_thigh": -0.6 * s, "fh_thigh": -0.6 * s}


def pose_walk(t):
    """走路：對角步態（近後腿與遠前腿同步）。往前擺時彎膝／腕，身體上下起伏，頭與尾跟著擺。"""
    p = t * 2 * math.pi
    q = {}

    def leg(prefix_u, prefix_l, prefix_p, phase, front):
        sw = math.sin(phase)                 # >0：腿往後；<0：往前
        lift = max(0.0, -math.cos(phase))    # 往前擺（騰空）時彎曲
        if front:
            q[prefix_u] = 16 * sw
            q[prefix_l] = -4 * sw + 34 * lift
            q[prefix_p] = 28 * lift
        else:
            q[prefix_u] = 12 * sw
            q[prefix_l] = 6 * sw - 14 * lift
            q[prefix_p] = -10 * sw + 24 * lift

    leg("nh_thigh", "nh_shin", "nh_foot", p, False)
    leg("ff_upper", "ff_lower", "ff_paw", p + 0.35, True)
    leg("fh_thigh", "fh_shin", "fh_foot", p + math.pi, False)
    leg("nf_upper", "nf_lower", "nf_paw", p + math.pi + 0.35, True)
    q["root_dy"] = -3.0 * abs(math.cos(p))
    q["chest"] = 1.2 * math.sin(2 * p)
    q["head"] = -2.0 * math.sin(2 * p + 0.6)
    q["tail1"] = 4 * math.sin(p)
    q["tail2"] = 6 * math.sin(p - 0.9)
    return q


def keyframes(keys, t):
    """keys：[(時間, 姿勢), ...]；兩個關鍵影格之間用緩入緩出內插。"""
    for (t0, p0), (t1, p1) in zip(keys, keys[1:]):
        if t0 <= t <= t1:
            k = (t - t0) / (t1 - t0) if t1 > t0 else 1.0
            k = k * k * (3 - 2 * k)
            names = set(p0) | set(p1)
            dv = lambda n: 1.0 if n in ("root_sx", "root_sy") else 0.0
            return {n: p0.get(n, dv(n)) + (p1.get(n, dv(n)) - p0.get(n, dv(n))) * k for n in names}
    return dict(keys[-1][1])


def _legs(hind_t, hind_s, hind_f, front_u, front_l, front_p, far_k=0.85):
    return {"nh_thigh": hind_t, "nh_shin": hind_s, "nh_foot": hind_f,
            "fh_thigh": hind_t * far_k, "fh_shin": hind_s * far_k, "fh_foot": hind_f * far_k,
            "nf_upper": front_u, "nf_lower": front_l, "nf_paw": front_p,
            "ff_upper": front_u * far_k, "ff_lower": front_l * far_k, "ff_paw": front_p * far_k}


BITE_KEYS = [
    (0.00, {}),
    # 蓄力：重心壓低往後、頭壓低盯著前方、尾巴放低
    (0.32, dict(root_dx=-26, root_dy=16, root_sx=0.95, root_sy=1.0, hips=4, chest=7, head=10, tail1=-12, tail2=-6,
                **_legs(-12, 22, -12, 16, -24, 8))),
    # 起跳：後腿蹬直往後、前腿往前伸、前身抬高、嘴張大
    (0.44, dict(root_dx=60, root_dy=-26, root_sx=1.12, root_sy=0.94, hips=-12, chest=-10, head=-4, jaw=40, tail1=-18, tail2=-12,
                **_legs(34, -24, 34, -60, 24, 32))),
    # 咬中：衝到最前、嘴猛然合上、頭往下壓
    (0.54, dict(root_dx=104, root_dy=-4, root_sx=1.05, root_sy=0.97, hips=-6, chest=-2, head=8, jaw=2, tail1=-14, tail2=-8,
                **_legs(26, -16, 22, -30, 12, 12))),
    # 咬住甩頭
    (0.64, dict(root_dx=98, root_dy=0, hips=-4, chest=0, head=-6, jaw=0, tail1=-10, tail2=-4,
                **_legs(20, -10, 14, -20, 8, 6))),
    (0.72, dict(root_dx=100, root_dy=0, hips=-4, chest=0, head=6, jaw=0, tail1=-8,
                **_legs(18, -8, 12, -18, 6, 4))),
    (1.00, {}),
]


def pose_bite(t):
    """撲咬：壓低蓄力 → 3 格內撲出（張大嘴、四肢伸展）→ 咬中猛然合嘴、甩頭 → 收回。"""
    return keyframes(BITE_KEYS, t)


def pose_hurt(t):
    """受傷：被撞得往後一縮、頭往上甩、尾巴夾起，再恢復。"""
    k = math.sin(min(1.0, t / 0.35) * math.pi / 2) if t < 0.35 else 1 - (t - 0.35) / 0.65
    k = max(0.0, k)
    return {"root_dx": -22 * k, "root_dy": 4 * k, "hips": 4 * k, "chest": -6 * k, "head": -16 * k, "jaw": 10 * k,
            "nf_upper": -14 * k, "ff_upper": -10 * k, "nf_lower": 6 * k, "nh_thigh": 8 * k, "fh_thigh": 8 * k,
            "tail1": 14 * k, "tail2": 18 * k}


ACTIONS = {"idle": (pose_idle, 12), "walk": (pose_walk, 12), "bite": (pose_bite, 16), "hurt": (pose_hurt, 8)}


def tint(im, rgb, amount):
    if amount <= 0:
        return im
    a = im.split()[3]
    flat = Image.new("RGBA", im.size, rgb + (255,))
    mixed = Image.blend(im.convert("RGBA"), flat, amount)
    mixed.putalpha(a)
    return mixed


def add_trails(frames, idx, fades=(0.38, 0.16)):
    """撲出的那幾格，把前兩格淡淡疊在後面當殘影。"""
    out = list(frames)
    for i in idx:
        base = Image.new("RGBA", frames[i].size, (0, 0, 0, 0))
        for back, f in zip((2, 1), reversed(fades)):
            if i - back >= 0:
                g = frames[i - back].copy()
                g.putalpha(g.split()[3].point(lambda v, f=f: int(v * f)))
                base.alpha_composite(g)
        base.alpha_composite(frames[i])
        out[i] = base
    return out


def render_actions(name="wolf_gray", cfg=WOLF_ILLUS, base=HERE, actions=None, rig_fn=None):
    """回傳 {動作: [影格]}，另外存一張靜止姿勢 anim/<name>_rest.png。
    actions：{動作: (姿勢函式, 影格數)}，預設是狼的四個動作；rig_fn：自訂的骨架（例如雪兔）。"""
    actions = actions or ACTIONS
    bones, layers, size0 = (rig_fn or wolf_rig)(name, cfg, base)
    render(bones, layers, size0, {}).save(os.path.join(base, "anim", f"{name}_rest.png"))
    out = {}
    for act, (fn, n) in actions.items():
        frames = []
        for i in range(n):
            t = i / n
            im = render(bones, layers, size0, fn(t))
            if act == "hurt":
                im = tint(im, (200, 40, 30), 0.35 * max(0.0, 1 - t * 3))
            frames.append(im)
        out[act] = frames
    return out


def save_sheet(frames, path):
    w, h = frames[0].size
    sheet = Image.new("RGBA", (w * len(frames), h))
    for i, f in enumerate(frames):
        sheet.paste(f, (i * w, 0))
    sheet.save(path)


def main(name="wolf_gray"):
    acts = render_actions(name)
    acts["bite"] = add_trails(acts["bite"], [i for i in range(len(acts["bite"])) if 0.36 <= i / len(acts["bite"]) <= 0.56])
    for act, frames in acts.items():
        save_sheet(frames, os.path.join(HERE, "anim", f"{name}_{act}.png"))
        print(act, len(frames), "frames", frames[0].size)


if __name__ == "__main__":
    main()
