"""Gemini 出的戰術狩獵獵物（2026-11-06 起，arts/gemini_prey_2026-11-06/；1024×1024 綠底、整隻佔滿畫布寬度）。

每種動物：站（基準，寬幾格照下表）＋其他姿勢（低頭吃草 graze、警覺抬頭 alert、跑 run）照同一個「畫布像素 → 格」比例
（Gemini 每張都畫滿畫布，所以用畫布寬度換算，不用每張的身體寬度）。
處理照 prep_grizzly.py：綠色色鍵去背、只留最大的一塊、縮成 32／48、補 1 像素深色外框（同 prep_wolf.py）。

- 騾鹿母鹿 mule_deer_doe_*：站寬 1.4 格（PixelLab 的白尾鹿腿長脖子高，1.1 格就和這隻 1.4 格差不多高；騾鹿比白尾鹿壯、略大）

用法：python3.12 -I prototypes/hd2d_tactical/prep_gemini_prey.py
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import prep_grizzly as pg  # noqa: E402
import prep_wolf as pw  # noqa: E402

SRC = os.path.join(pg.ROOT, "arts", "gemini_prey_2026-11-06")
# 動物 → (站那張身體寬幾格, [姿勢])；輸出 hd_<動物>_<姿勢>（站是 hd_<動物>）
ANIMALS = {
    "mule_deer_doe": (1.4, ["stand", "alert", "run", "graze"]),
}


def main():
    for animal, (cells, poses) in ANIMALS.items():
        cuts = {p: pg.cut(os.path.join(SRC, "%s_%s.jpg" % (animal, p)), "green") for p in poses}
        px_per_cell = cuts["stand"].width / cells
        for p, c in cuts.items():
            name = "hd_%s" % animal if p == "stand" else "hd_%s_%s" % (animal, p)
            for d in pg.DENSITIES:
                out = pw.outline(pg.shrink(c, round(c.width / px_per_cell * d)))
                out.save(os.path.join(pg.OUT, "%s_%d.png" % (name, d)))
                print(name, d, out.size)


if __name__ == "__main__":
    main()
