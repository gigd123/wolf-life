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
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
SCALE = 0.5
PAD = 60          # 畫布四周的空間（原尺寸像素），撲咬往前衝時不會被切掉
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
            mats[b.name] = translate(pose.get("root_dx", 0.0), pose.get("root_dy", 0.0)) @ local
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


def wolf_rig(name="wolf_gray"):
    img = Image.open(os.path.join(HERE, "cut", name + ".png")).convert("RGBA")
    W0, H0 = img.size
    os.makedirs(os.path.join(HERE, "anim"), exist_ok=True)

    bones = [
        Bone("hips", None, (330, 262), (560, 250)),
        Bone("chest", "hips", (560, 250), (790, 225)),
        Bone("head", "chest", (800, 220), (1040, 230)),
        Bone("jaw", "head", (948, 240), (1035, 256)),
        Bone("tail1", "hips", (238, 236), (140, 322)),
        Bone("tail2", "tail1", (140, 322), (30, 440)),
        Bone("nh_thigh", "hips", (262, 300), (302, 396)),
        Bone("nh_shin", "nh_thigh", (302, 396), (140, 462)),
        Bone("nh_foot", "nh_shin", (140, 462), (165, 615)),
        Bone("fh_thigh", "hips", (395, 330), (395, 420)),
        Bone("fh_shin", "fh_thigh", (395, 420), (320, 502)),
        Bone("fh_foot", "fh_shin", (320, 502), (440, 600)),
        Bone("nf_upper", "chest", (630, 330), (612, 410)),
        Bone("nf_lower", "nf_upper", (612, 410), (622, 556)),
        Bone("nf_paw", "nf_lower", (622, 556), (675, 615)),
        Bone("ff_upper", "chest", (716, 330), (715, 410)),
        Bone("ff_lower", "ff_upper", (715, 410), (706, 556)),
        Bone("ff_paw", "ff_lower", (706, 556), (765, 600)),
    ]

    # 遮罩（原尺寸座標）
    polys = {
        "nh": [(92, 436), (160, 402), (250, 384), (334, 384), (334, 420), (262, 468), (208, 500), (215, 648), (88, 648)],
        "fh": [(300, 392), (458, 392), (444, 470), (414, 520), (486, 560), (494, 648), (370, 648), (288, 520), (300, 450)],
        "nf": [(566, 384), (672, 384), (668, 500), (690, 560), (722, 585), (728, 648), (588, 648), (588, 480)],
        "ff": [(672, 384), (792, 384), (772, 500), (822, 648), (728, 648), (722, 585), (700, 560), (672, 500)],
        "jaw": [(940, 238), (1000, 242), (1046, 238), (1042, 258), (1012, 268), (972, 270), (944, 258)],
    }

    def mask_of(poly):
        m = Image.new("L", (W0, H0), 0)
        ImageDraw.Draw(m).polygon(poly, fill=255)
        return m

    src = np.asarray(img).astype(float) / 255.0

    def tex_from(mask_img, base=None):
        m = np.asarray(mask_img.resize((int(W0 * SCALE), int(H0 * SCALE)), Image.BILINEAR)).astype(float)[..., None] / 255
        b = base if base is not None else small
        t = b.copy()
        t[..., 3:4] *= m
        t[..., :3] *= t[..., 3:4]
        return t

    small = np.asarray(img.resize((int(W0 * SCALE), int(H0 * SCALE)), Image.LANCZOS)).astype(float) / 255.0

    # 腿：從腿裡的種子點往外長，碰到黑色外框就停（限制在 limits 的範圍內），再往外擴幾像素把自己的外框收進來。
    # 這樣切線會沿著原圖的線條走，不會把另一條腿的外框切進來。
    limits = {
        "nh": [(108, 470), (150, 412), (250, 364), (338, 364), (338, 420), (270, 470), (222, 520), (222, 648), (80, 648), (96, 540)],
        "fh": [(300, 372), (458, 372), (450, 470), (500, 560), (500, 648), (360, 648), (284, 520), (296, 440)],
        "nf": [(562, 364), (674, 364), (676, 420), (700, 540), (750, 600), (750, 648), (580, 648), (580, 470)],
        "ff": [(676, 364), (796, 364), (790, 470), (830, 600), (830, 648), (700, 648), (690, 540), (678, 420)],
    }
    seeds = {"nh": [(170, 540), (240, 420)], "fh": [(370, 470), (420, 590)], "nf": [(630, 480), (650, 610)], "ff": [(735, 470), (770, 590)]}
    leg_masks = {k: seg_leg(src, mask_of(limits[k]), seeds[k]) for k in limits}
    # 腿和身體在腹部重疊一段：身體只挖掉 y ≥ 398 的部分，腿層往上到 364，接縫不會露白
    yy = np.arange(H0)[:, None]
    body_hole = np.zeros((H0, W0), bool)
    from scipy import ndimage
    for m in leg_masks.values():
        body_hole |= ndimage.binary_dilation(m, iterations=4) & (yy >= 398)
    body_mask = Image.fromarray(np.where(body_hole, 0, 255).astype(np.uint8))
    leg_masks = {k: Image.fromarray((m * 255).astype(np.uint8)) for k, m in leg_masks.items()}
    dbg = np.asarray(img).copy()
    for k, col in zip(leg_masks, [(255, 0, 0), (0, 160, 255), (0, 200, 0), (255, 160, 0)]):
        m = np.asarray(leg_masks[k]) > 0
        dbg[m, :3] = (dbg[m, :3] * 0.4 + np.array(col) * 0.6).astype(np.uint8)
    Image.fromarray(dbg).save(os.path.join(HERE, "anim", name + "_masks.png"))

    # 身體層：下顎的位置換成嘴裡的深色，下顎張開時才看得到
    body_img = img.copy()
    d = ImageDraw.Draw(body_img)
    d.polygon([(944, 240), (1040, 240), (1030, 252), (990, 258), (950, 254)], fill=(70, 22, 24, 255))
    for x in (1010, 1024):
        d.polygon([(x, 240), (x + 6, 240), (x + 3, 250)], fill=(240, 236, 226, 255))
    body_small = np.asarray(body_img.resize(small.shape[1::-1], Image.LANCZOS)).astype(float) / 255.0

    head_only = lambda p: np.clip((p[:, 0] - 770) / 40, 0, 1)
    not_head = lambda p: np.clip((830 - p[:, 0]) / 60, 0.02, 1)
    tail_only = lambda p: np.clip((262 - p[:, 0]) / 30, 0, 1)

    layers = [
        Layer("fh", tex_from(leg_masks["fh"]), bones, ["hips", "fh_thigh", "fh_shin", "fh_foot"]),
        Layer("ff", tex_from(leg_masks["ff"]), bones, ["chest", "ff_upper", "ff_lower", "ff_paw"]),
        Layer("body", tex_from(body_mask, body_small), bones, ["hips", "chest", "head", "tail1", "tail2"],
              bias={"head": head_only, "chest": not_head, "tail1": tail_only, "tail2": tail_only}),
        Layer("jaw", tex_from(mask_of(polys["jaw"])), bones, ["jaw"]),
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


def pose_bite(t):
    """撲咬：先往後蓄力、再往前撲、張嘴咬、收回。"""
    if t < 0.3:          # 蓄力：重心後移、頭壓低
        k = t / 0.3
        return {"root_dx": -14 * k, "root_dy": 6 * k, "hips": 2 * k, "head": 10 * k, "chest": 3 * k,
                "nh_thigh": -6 * k, "fh_thigh": -6 * k, "nh_shin": 10 * k, "fh_shin": 10 * k,
                "nf_upper": 8 * k, "ff_upper": 8 * k, "nf_lower": -8 * k, "ff_lower": -8 * k, "tail1": -6 * k}
    if t < 0.6:          # 撲出：前身抬起前伸、嘴張開
        k = (t - 0.3) / 0.3
        e = math.sin(k * math.pi / 2)
        return {"root_dx": -14 + 70 * e, "root_dy": 6 - 16 * e, "hips": 2 - 8 * e, "chest": 3 - 6 * e,
                "head": 10 - 18 * e, "jaw": 34 * e,
                "nh_thigh": -6 + 22 * e, "fh_thigh": -6 + 22 * e, "nh_shin": 10 - 16 * e, "fh_shin": 10 - 16 * e,
                "nh_foot": 20 * e, "fh_foot": 20 * e,
                "nf_upper": 8 - 48 * e, "ff_upper": 8 - 40 * e, "nf_lower": -8 + 30 * e, "ff_lower": -8 + 26 * e,
                "nf_paw": 20 * e, "ff_paw": 20 * e, "tail1": -6 - 8 * e, "tail2": -10 * e}
    k = (t - 0.6) / 0.4  # 咬合後落地收回
    e = 1 - (1 - k) ** 2
    b = pose_bite(0.5999)
    out = {key: v * (1 - e) for key, v in b.items()}
    out["jaw"] = 34 * max(0.0, 1 - k * 3)
    return out


def pose_hurt(t):
    """受傷：被撞得往後一縮、頭往上甩、尾巴夾起，再恢復。"""
    k = math.sin(min(1.0, t / 0.35) * math.pi / 2) if t < 0.35 else 1 - (t - 0.35) / 0.65
    k = max(0.0, k)
    return {"root_dx": -22 * k, "root_dy": 4 * k, "hips": 4 * k, "chest": -6 * k, "head": -16 * k, "jaw": 10 * k,
            "nf_upper": -14 * k, "ff_upper": -10 * k, "nf_lower": 6 * k, "nh_thigh": 8 * k, "fh_thigh": 8 * k,
            "tail1": 14 * k, "tail2": 18 * k}


ACTIONS = {"idle": (pose_idle, 12), "walk": (pose_walk, 12), "bite": (pose_bite, 10), "hurt": (pose_hurt, 8)}


def tint(im, rgb, amount):
    if amount <= 0:
        return im
    a = im.split()[3]
    flat = Image.new("RGBA", im.size, rgb + (255,))
    mixed = Image.blend(im.convert("RGBA"), flat, amount)
    mixed.putalpha(a)
    return mixed


def main(name="wolf_gray"):
    out_dir = os.path.join(HERE, "anim")
    os.makedirs(out_dir, exist_ok=True)
    bones, layers, size0 = wolf_rig(name)
    rest = render(bones, layers, size0, {})
    rest.save(os.path.join(out_dir, f"{name}_rest.png"))
    for act, (fn, n) in ACTIONS.items():
        frames = []
        for i in range(n):
            t = i / n
            im = render(bones, layers, size0, fn(t))
            if act == "hurt":
                im = tint(im, (200, 40, 30), 0.35 * max(0.0, 1 - t * 3))
            frames.append(im)
        w, h = frames[0].size
        sheet = Image.new("RGBA", (w * n, h))
        for i, f in enumerate(frames):
            sheet.paste(f, (i * w, 0))
        sheet.save(os.path.join(out_dir, f"{name}_{act}.png"))
        print(act, n, "frames", (w, h))


if __name__ == "__main__":
    main()
