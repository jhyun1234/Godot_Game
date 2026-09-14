#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""tools/palette.py — KayKit 던전 팔레트 사본 (제안서 #17, 질감 A).

`assets/kaykit/dungeon/dungeon_texture.png` 는 그림이 아니라 8x4 색 패치 팔레트다.
패치마다 위→아래 그라디언트 하나. 벽은 (0,0)·(1,0) 두 칸, 바닥은 (5,0) 한 칸만 쓴다.
원본은 그대로 두고, 아래 표의 패치만 다시 칠해 `assets/generated/palette/` 에 사본을 쓴다.
실행 중에 `scripts/Atmosphere.gd` 가 던전 재질의 텍스처를 이 사본으로 갈아 끼운다.

    python tools/palette.py            사본 생성
    python tools/palette.py --dump     원본 32 패치 색을 출력 (표를 고칠 때)

색 방향은 "젖은 검은 돌" (사용자 결정 2026-09-08). 갱목·밧줄은 갈색을 남긴다 —
전부 검게 하면 대비가 없어져 오히려 가짜처럼 보인다.
"""
import os
import sys

from PIL import Image

# Windows 콘솔은 cp949 라 한글 출력이 깨진다. utf-8 로 고정 (qc.py 와 같다).
for _st in (sys.stdout, sys.stderr):
    if hasattr(_st, "reconfigure"):
        _st.reconfigure(encoding="utf-8", errors="replace")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "assets", "kaykit", "dungeon", "dungeon_texture.png")
DST = os.path.join(ROOT, "assets", "generated", "palette", "dungeon_texture.png")
COLS, ROWS = 8, 4

# (열, 행): (위 색, 아래 색). 원본 값은 주석. 표에 없는 패치는 원본 그대로.
RECOLOR = {
    (1, 0): ("353c44", "14181c"),  # 벽 몸통      aab8be -> 596064  밝은 회색 돌 -> 젖은 청흑 석탄
                                   #   4a5054/23272a 는 누런 램프 아래 갈색으로 읽혔다(09-08)
    (0, 0): ("1e2429", "0d1013"),  # 벽 굽도리    596064 -> 3c4246  아랫단은 더 검게
    (5, 0): ("3f3b37", "201d1a"),  # 바닥         a8a29d -> 6d605c  진흙 바닥
    (2, 0): ("5a4636", "2e221a"),  # 나무(밝음)   c8855f -> 9b5a45  썩은 갱목
    (4, 0): ("4a3527", "261a12"),  # 나무(어둠)   b27052 -> 7d3d2c
    (7, 0): ("4a423a", "2b2622"),  # 가죽·밧줄    837265 -> 534741  톤 맞춤
}


def hex_rgb(h):
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def dump(im):
    cw, ch = im.width // COLS, im.height // ROWS
    for r in range(ROWS):
        cells = []
        for c in range(COLS):
            top = im.getpixel((c * cw + cw // 2, r * ch + 8))[:3]
            bot = im.getpixel((c * cw + cw // 2, r * ch + ch - 8))[:3]
            cells.append("(%d,%d) %02x%02x%02x/%02x%02x%02x" % ((c, r) + top + bot))
        print("  ".join(cells))


def recolor(im):
    out = im.copy()
    px = out.load()
    cw, ch = im.width // COLS, im.height // ROWS
    for (c, r), (top_hex, bot_hex) in RECOLOR.items():
        top, bot = hex_rgb(top_hex), hex_rgb(bot_hex)
        for y in range(r * ch, (r + 1) * ch):
            t = (y - r * ch) / float(ch - 1)
            col = tuple(int(round(top[i] + (bot[i] - top[i]) * t)) for i in range(3))
            for x in range(c * cw, (c + 1) * cw):
                a = px[x, y][3] if len(px[x, y]) == 4 else 255
                px[x, y] = col + (a,)
    return out


def main(argv):
    im = Image.open(SRC).convert("RGBA")
    if "--dump" in argv:
        dump(im)
        return 0
    if not RECOLOR:
        print("FAIL 재색 표가 비어 있다")
        return 1
    out = recolor(im)
    os.makedirs(os.path.dirname(DST), exist_ok=True)
    out.save(DST)
    print("ok 팔레트 사본 %s (패치 %d칸)" % (os.path.relpath(DST, ROOT), len(RECOLOR)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
