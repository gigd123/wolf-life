# 母大角羊的佔位圖是白尾鹿雄鹿改色的，頭上還留著分叉的鹿角（2026-10-15 試玩回報 5）。
# 公羊圖用的是同一個身體、去掉鹿角再加彎角：母羊圖裡「公羊圖是透明」的地方就是鹿角，擦掉；
# 再在頭頂畫一對母羊短短往後彎的角。
from PIL import Image
A = "assets/art/sprites/animals/"
ewe = Image.open(A + "bighorn_ewe_sheet.png").convert("RGBA")
ram = Image.open(A + "bighorn_ram_sheet.png").convert("RGBA")
DARK, HORN = (34, 28, 26, 255), (176, 156, 116, 255)
W, H = 48, 32
for fy in range(ewe.height // H):
    for fx in range(ewe.width // W):
        ox, oy = fx * W, fy * H
        top = None
        for y in range(H):
            for x in range(W):
                p = (ox + x, oy + y)
                if ewe.getpixel(p)[3] > 0 and ram.getpixel(p)[3] == 0:
                    ewe.putpixel(p, (0, 0, 0, 0))
        # 頭頂：右半邊最上面還有顏色的那一點
        for y in range(H):
            xs = [x for x in range(28, W) if ewe.getpixel((ox + x, oy + y))[3] > 0]
            if xs:
                top, tx = y, min(xs)
                break
        if top is None:
            continue
        for dx, dy, c in [(1, -1, DARK), (2, -1, HORN), (0, -2, DARK), (1, -2, HORN), (0, -3, DARK)]:
            x, y = tx + dx, top + dy
            if 0 <= y < H and ewe.getpixel((ox + x, oy + y))[3] == 0:
                ewe.putpixel((ox + x, oy + y), c)
ewe.save(A + "bighorn_ewe_sheet.png")
