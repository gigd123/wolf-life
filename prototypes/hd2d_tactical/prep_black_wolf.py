"""黑狼的 HD-2D 素材（2026-11-08，ChatGPT，arts/hd2d_2026-11-06/blackwolf_*.jpg，1024×1024 綠底）。

站 stand、走 walk、示威 threaten（豎毛露牙）、準備撲 ready（壓低頭齜牙）、示弱 submit（壓低頭、耳朵往後，沒露牙）。
五張畫布一樣、畫的大小一樣 → 照走路那張換算：比灰狼走路（1.35 格）大一點（× 1.05）。
黑毛縮小後容易變成一團黑影 → 整體提亮 BRIGHT 倍；外框和灰狼一樣補一圈 1 像素深色（prep_wolf.outline）。
其他姿勢（撲咬、帶傷、撤退、倒地…）沒有專屬圖，戰鬥畫面用灰狼的圖調暗（combat_hd2d.json units.stranger_wolf）。

苔原狼（2026-11-08，ChatGPT，tundrawolf_*.jpg）：站、走、示威、示弱（夾尾巴、頭低於肩膀）、準備撲（重出的）、撲咬 lunge（重出準備撲時多給的一張：站著張大嘴咆哮，當咬下去那一回合用）。
白毛不提亮；大小和灰狼一樣（× 1.0）。units.tundra_wolf。

郊狼（2026-11-08，ChatGPT，coyote_*.jpg）：站、走、咬、叼肉、逃跑；約灰狼的八成長。units.coyote 的 hd2d_poses。

用法：python3.12 -I prototypes/hd2d_tactical/prep_black_wolf.py
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import prep_grizzly as pg  # noqa: E402
import prep_wolf as pw  # noqa: E402
from PIL import Image  # noqa: E402

# 前綴 → (姿勢, 比灰狼走路大幾倍, 提亮倍率)
SETS = {
    "blackwolf": (["stand", "walk", "threaten", "ready", "submit", "lunge", "retreat", "carry", "down"], 1.05, 1.3),  # 2026-11-12 補撤退、叼肉、倒地（倒地 1376×768 → CANVAS_NORM）  # 2026-11-11 補撲咬；另兩張沒用（_blackwolf_unused_crouch：像趴著戒備不像倒地、_blackwolf_unused_twisted：身體扭曲）
    "tundrawolf": (["stand", "walk", "threaten", "submit", "ready", "lunge", "retreat", "hurt", "down", "carry"], 1.0, 1.0),  # 2026-11-12 補撤退、帶傷（身上有傷口、低頭）、倒地（帶傷那張，1376×768 → CANVAS_NORM；沒傷的那張 _tundrawolf_down_unused_nowound）、叼肉
    # 郊狼（Phase 2l，ChatGPT 2026-11-08，1408×768）：約灰狼的八成長（走路約 1.08 格；體重約四成但身長約八成）
    "coyote": (["stand", "walk", "bite", "carry", "run"], 0.8, 1.0),
    # 狼獾（Phase 2l，ChatGPT 2026-11-08）：站、走、撲咬（張嘴伸爪，也當示威）、吃；含尾巴約灰狼的七成五長，矮壯
    "wolverine": (["stand", "walk", "lunge", "eat"], 0.75, 1.0),
    # 猞猁（Phase 2l，ChatGPT 2026-11-08）：站、走、揮爪、叼著雪兔跑、示威（豎毛張嘴）；約灰狼的八成長（和郊狼差不多大、腿長）
    "lynx": (["stand", "walk", "swipe", "carry", "threaten"], 0.8, 1.0),
    # 紅狐（2026-11-12，ChatGPT，站 1408×768、跑與撲 1024×1024）：站、走、跑（逃）、撲（老鼠跳）；選單畫面用。含尾巴約灰狼的六成五長
    "redfox": (["stand", "walk", "run", "pounce"], 0.65, 1.0),
}
# 每張畫布不一樣大的：照佔畫布的比例換算；值是姿勢比走路長多少（跑、撲身體拉長）
CANVAS_NORM = {"redfox": {"run": 1.1, "pounce": 1.0}, "blackwolf": {}, "tundrawolf": {}}


def main():
    for prefix, (poses, scale, bright) in SETS.items():
        cuts = {n: pg.cut(os.path.join(pg.SRC, "%s_%s.jpg" % (prefix, n)), "green") for n in poses}
        if bright != 1.0:
            for c in cuts.values():
                pg.apply_gain(c, [bright] * 3)
        ref = cuts["walk"].width
        for n, c in cuts.items():
            cells = pw.WALK_CELLS * scale * c.width / ref
            if prefix in CANVAS_NORM:
                # 畫布大小不一樣（同一隻都畫滿畫布寬度）：照佔畫布的比例換算，再乘上姿勢的伸展
                cw = Image.open(os.path.join(pg.SRC, "%s_%s.jpg" % (prefix, n))).width
                rw = Image.open(os.path.join(pg.SRC, "%s_walk.jpg" % prefix)).width
                cells = pw.WALK_CELLS * scale * (c.width / cw) / (ref / rw) * CANVAS_NORM[prefix].get(n, 1.0)
            for d in pg.DENSITIES:
                out = pw.outline(pg.shrink(c, round(cells * d)))
                out.save(os.path.join(pg.OUT, "%s_%s_%d.png" % (prefix, n, d)))
                print(prefix, n, d, out.size, "寬 %.2f 格" % cells)


if __name__ == "__main__":
    main()
