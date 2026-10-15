# 大角羊群拆成母羊群（含小羊）與公羊群（2026-10-15 試玩回報 5：原本的羊群圖裡有公羊，觀察母羊時看起來像公羊）。
# 用遊戲裡的 1x spritesheet 第一格合成，尺寸沿用原本的 114×42。
import sys
from PIL import Image
A = "assets/art/sprites/animals/"
def frame(name, col=0, row=0):
    im = Image.open(A + name).convert("RGBA")
    return im.crop((col * 48, row * 32, col * 48 + 48, row * 32 + 32))
def compose(parts, out):
    c = Image.new("RGBA", (114, 42), (0, 0, 0, 0))
    for im, x, y in parts:  # 先畫後面的
        c.alpha_composite(im, (x, y))
    c.save(A + out)
ewe, ewe2, lamb = frame("bighorn_ewe_sheet.png"), frame("bighorn_ewe_sheet.png", 2), frame("bighorn_lamb_sheet.png", 1)
compose([(ewe2, 52, 0), (ewe, 6, 6), (lamb, 40, 12), (ewe, 64, 10)], "bighorn_herd.png")
ram, ram2 = frame("bighorn_ram_sheet.png"), frame("bighorn_ram_sheet.png", 2)
compose([(ram2, 50, 0), (ram, 4, 8), (ram, 62, 10)], "bighorn_ram_herd.png")
