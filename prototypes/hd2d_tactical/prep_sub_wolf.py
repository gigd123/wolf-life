"""次成年灰狼（1～2 歲）的 HD-2D 素材處理（2026-11-25，試玩回報 Bug #1）。

來源：arts/sub_wolf_2026-11-25/sub_<姿勢>.jpg（綠底，照成狼的圖出的同一隻年輕的狼）。
處理照 prep_wolf.py：綠色色鍵去背、只留最大的一塊；毛色偏黃褐 → 照成狼第二輪走路那張的色盤調色（冷灰）；
縮成 32／48、外面補一圈深色外框。寬幾格照成狼走路（1.35 格）換算（同樣的畫布），遊戲裡再乘年齡的縮放（wolf_display_scale）。
輸出 assets/hdwolf_sub_<成狼的姿勢名>_32／48.png；HD2DBoard.hd_wolf_texture 在 1～2 歲時優先用這套，沒有的姿勢用成狼的。
還沒交的：走路第二格 sub_walk_b、咬住 sub_hold（現在那張要重出，交了再把 "hold": "hold" 加回 POSES）（docs/art-request-hd2d-2026-11-06.md）。

用法：python3.12 -I prototypes/hd2d_tactical/prep_sub_wolf.py
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import prep_grizzly as pg  # noqa: E402
import prep_wolf as pw  # noqa: E402

SUB = os.path.join(pg.ROOT, "arts", "sub_wolf_2026-11-25")
# 交圖的檔名 → 成狼的姿勢名（hdwolf_<名>）
POSES = {"stand": "stand", "walk": "walk", "walk_b": "walk_b", "stalk": "stalk", "pounce": "lunge", "hurt": "hurt", "submit": "submit"}


def main():
    ref = pg.cut(os.path.join(pg.SRC, "wolf_r2_walk.jpg"), "green")
    for src_name, pose in POSES.items():
        p = os.path.join(SUB, "sub_%s.jpg" % src_name)
        if not os.path.exists(p):
            print("缺", src_name)
            continue
        c = pw.match_palette(pg.cut(p, "green"), ref)
        cells = pw.WALK_CELLS * c.width / ref.width
        for d in pg.DENSITIES:
            out = pw.outline(pg.shrink(c, round(cells * d)))
            out.save(os.path.join(pg.OUT, "hdwolf_sub_%s_%d.png" % (pose, d)))
            print(pose, d, out.size, "寬 %.2f 格" % cells)


if __name__ == "__main__":
    main()
