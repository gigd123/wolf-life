"""美洲獅的 HD-2D 素材處理（2026-11-06）。

來源：Gemini 出的圖（arts/hd2d_2026-11-06/）：
- cougar_sheet_checker.jpg：2×2 合在一張（灰白棋盤格背景）：左上 站、右上 走路、左下 走路（另一步）、右下 伏低（準備撲）
- cougar_sheet_green.jpg：2×2 合在一張（綠色棋盤格背景）：右下 低頭（吃）；其他和上一張重複
- cougar_pounce.jpg：撲擊（綠底，單張；像素顆粒比較粗、黑邊比較粗）
處理照 prep_grizzly.py：切成四格、去背（綠色用色鍵、灰白棋盤格用灌水）、只留最大的一塊、縮成 32／48。
美洲獅含尾巴寬約 1.8 格（狼約 1.25 格）；撲擊身體拉長約 2.1 格。

用法：python3.12 -I prototypes/hd2d_tactical/prep_cougar.py
"""
import os
import sys

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import prep_grizzly as pg  # noqa: E402

# 名稱 → (來源檔, 第幾格〔0 左上、1 右上、2 左下、3 右下；-1 整張〕, 背景種類, 寬幾格)
FRAMES = {
    "cougar_stand": ("cougar_sheet_checker.jpg", 0, "checker", 1.8),
    "cougar_walk": ("cougar_sheet_checker.jpg", 1, "checker", 1.8),
    "cougar_walk_b": ("cougar_sheet_checker.jpg", 2, "checker", 1.8),
    # 伏低：2026-11-08 換成重畫的綠底版（原本棋盤格那張尾巴和後腳之間留了白色）
    "cougar_crouch": ("cougar_crouch_v2.jpg", -1, "green", 2.0),
    "cougar_eat": ("cougar_sheet_green.jpg", 3, "green", 1.8),
    "cougar_pounce": ("cougar_pounce.jpg", -1, "green", 2.1),
}


def quadrant(path, q, tmp):
    im = Image.open(path).convert("RGB")
    if q < 0:
        return path
    w, h = im.size
    box = ((q % 2) * w // 2, (q // 2) * h // 2, (q % 2 + 1) * w // 2, (q // 2 + 1) * h // 2)
    im.crop(box).save(tmp)
    return tmp


def main():
    tmp = os.path.join(pg.SRC, "_quad.png")
    for name, (f, q, kind, cells) in FRAMES.items():
        src = quadrant(os.path.join(pg.SRC, f), q, tmp)
        c = pg.cut(src, kind)
        c.save(os.path.join(pg.SRC, name + "_src.png"))
        for d in pg.DENSITIES:
            out = pg.shrink(c, round(cells * d))
            out.save(os.path.join(pg.OUT, "%s_%d.png" % (name, d)))
            print(name, d, out.size)
    if os.path.exists(tmp):
        os.remove(tmp)


if __name__ == "__main__":
    main()
