"""美術測試場景（prototypes/art_test/）用的素材：把骨架動畫輸出成 spritesheet，加一份描述檔。

輸出到 assets/art/art_test/：
  illus/<動物>_<動作>.png   插畫版（平滑縮放）
  pixel/<動物>_<動作>.png   像素版（原生解析度，最近鄰放大）
  manifest.json             {風格: {動物: {frame, foot, body_h, rel_height, actions: {動作: {sheet, frames, fps, loop}}}}}
同一隻動物的所有動作裁成同一個範圍，切換動作時位置不會跳。foot＝腳底在格子裡的 y，body_h＝靜止姿勢的高度。
用法：python3 export_game.py [illus|pixel]（不給就兩種都做）
"""
import json
import os
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
OUT = os.path.join(ROOT, "assets", "art", "art_test")
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(ROOT, "arts", "art_pixel_test_2026-10-13"))

import rig  # noqa: E402
import animals  # noqa: E402

# 播放設定：fps 與是否循環
PLAY = {"idle": (10, True), "walk": (12, True), "bite": (18, False), "hurt": (12, False), "hop": (14, True)}
# 相對灰狼的高度（和遊戲 art.json 的 display_scale 同一套比例）
REL = {"wolf_gray": 1.0, "wolf_black": 1.0, "grizzly": 1.5, "elk_cow": 2.0, "hare": 0.5}

ILLUS = [
    # (id, 去背圖名, 設定, 動作, 骨架函式)
    ("wolf_gray", "wolf_gray", rig.WOLF_ILLUS, rig.ACTIONS, None),
    ("wolf_black", "wolf_black", animals.WOLF_BLACK, rig.ACTIONS, None),
    ("grizzly", "grizzly", animals.GRIZZLY, rig.ACTIONS, None),
    ("elk_cow", "elk_cow", animals.ELK_COW, animals.PREY_ACTIONS, None),
    ("hare", "hare_summer", animals.HARE, animals.HARE_ACTIONS, animals.hare_rig),
]


def crop_all(acts, rest):
    """所有動作與靜止姿勢的聯集範圍，四周留 2 像素。"""
    box = rest.getbbox()
    for frames in acts.values():
        for f in frames:
            b = f.getbbox()
            if b:
                box = (min(box[0], b[0]), min(box[1], b[1]), max(box[2], b[2]), max(box[3], b[3]))
    W, H = rest.size
    return (max(0, box[0] - 2), max(0, box[1] - 2), min(W, box[2] + 2), min(H, box[3] + 2))


def write_animal(style, aid, acts, rest, entry_extra=None):
    os.makedirs(os.path.join(OUT, style), exist_ok=True)
    box = crop_all(acts, rest)
    rb = rest.getbbox()
    entry = {
        "frame": [box[2] - box[0], box[3] - box[1]],
        "foot": rb[3] - box[1],
        "center_x": (rb[0] + rb[2]) / 2 - box[0],
        "body_h": rb[3] - rb[1],
        "rel_height": REL[aid],
        "actions": {},
    }
    entry.update(entry_extra or {})
    for act, frames in acts.items():
        frames = [f.crop(box) for f in frames]
        path = os.path.join(OUT, style, f"{aid}_{act}.png")
        rig.save_sheet(frames, path)
        fps, loop = PLAY[act]
        entry["actions"][act] = {"sheet": f"res://assets/art/art_test/{style}/{aid}_{act}.png",
                                 "frames": len(frames), "fps": fps, "loop": loop}
    return entry


def bite_trails(acts):
    if "bite" in acts:
        n = len(acts["bite"])
        acts["bite"] = rig.add_trails(acts["bite"], [i for i in range(n) if 0.36 <= i / n <= 0.56])
    return acts


def export_illus():
    rig.SCALE = 0.35   # 遊戲裡狼最大約 180 實際像素高，0.35 倍（狼約 230 像素）已足夠
    out = {}
    for aid, name, cfg, actions, rig_fn in ILLUS:
        acts = bite_trails(rig.render_actions(name, cfg, rig.HERE, actions, rig_fn))
        rest = Image.open(os.path.join(rig.HERE, "anim", f"{name}_rest.png"))
        out[aid] = write_animal("illus", aid, acts, rest)
        print("illus", aid, out[aid]["frame"])
    return out


def export_pixel():
    import pixel_rig
    rig.SCALE = 0.5
    out = {}
    acts_hi = rig.render_actions("wolf_gray", pixel_rig.WOLF_PIXEL, pixel_rig.HERE)
    rest_hi = Image.open(os.path.join(pixel_rig.HERE, "anim", "wolf_gray_rest.png"))
    bb = rest_hi.getbbox()
    k = pixel_rig.SIZES["wolf_px64"] / (bb[3] - bb[1])
    bones = [rig.Bone(*b) for b in pixel_rig.WOLF_PIXEL["bones"]]
    rest_px, pal = pixel_rig.pixelize(rest_hi, k)
    pixel_rig.put_eye(rest_px, pixel_rig.eye_point(bones, {}, k))
    acts = {}
    for act, frames in acts_hi.items():
        fn, n = rig.ACTIONS[act]
        acts[act] = [pixel_rig.put_eye(pixel_rig.pixelize(f, k, pal)[0], pixel_rig.eye_point(bones, fn(i / n), k))
                     for i, f in enumerate(frames)]
    acts = bite_trails(acts)
    out["wolf_gray"] = write_animal("pixel", "wolf_gray", acts, rest_px)
    print("pixel wolf_gray", out["wolf_gray"]["frame"])
    return out


def main():
    which = sys.argv[1:] or ["illus", "pixel"]
    path = os.path.join(OUT, "manifest.json")
    manifest = json.load(open(path, encoding="utf-8")) if os.path.exists(path) else {}
    if "illus" in which:
        manifest["illus"] = export_illus()
    if "pixel" in which:
        manifest["pixel"] = export_pixel()
    os.makedirs(OUT, exist_ok=True)
    json.dump(manifest, open(path, "w", encoding="utf-8"), ensure_ascii=False, indent=1)


if __name__ == "__main__":
    main()
