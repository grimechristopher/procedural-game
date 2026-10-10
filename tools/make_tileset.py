"""Draws the 16x16 pixel-art tileset atlas used by the GridMap blocks.

Run from the repo root:  python3 tools/make_tileset.py
Writes assets/tileset.png. The tile order must match GridWorld.Tex.
"""
import random

from PIL import Image

T = 16
COLS, ROWS = 4, 3
rng = random.Random(7)

GRASS = [(52, 116, 60), (62, 132, 66), (74, 148, 72), (44, 102, 54)]
GRASS_HI = (104, 170, 80)
DIRT = [(122, 82, 52), (138, 94, 60), (106, 70, 44), (150, 104, 66)]
PEBBLE = (172, 140, 104)
PATH = [(176, 142, 92), (164, 130, 84), (188, 154, 104), (152, 120, 78)]
PATH_DARK = (150, 116, 74)
STONE = [(136, 138, 150), (150, 152, 164), (122, 124, 138)]
STONE_LINE = (88, 90, 104)
WOOD = [(160, 104, 60), (172, 116, 68), (148, 94, 54)]
WOOD_LINE = (96, 60, 34)
FLOWERS = [(240, 220, 90), (236, 120, 140), (240, 240, 240)]


def noise(px, ox, oy, palette, weights=None):
    for y in range(T):
        for x in range(T):
            px[ox + x, oy + y] = rng.choices(palette, weights)[0]


def speckle(px, ox, oy, color, count, rows=range(T)):
    rows = list(rows)
    for _ in range(count):
        px[ox + rng.randrange(T), oy + rng.choice(rows)] = color


def grass(px, ox, oy):
    noise(px, ox, oy, GRASS, [3, 4, 2, 2])
    # Little two-pixel blades.
    for _ in range(10):
        x, y = rng.randrange(T), rng.randrange(1, T)
        px[ox + x, oy + y] = GRASS_HI
        px[ox + x, oy + y - 1] = GRASS[2]


def dirt(px, ox, oy, rows=range(T)):
    for y in rows:
        for x in range(T):
            px[ox + x, oy + y] = rng.choices(DIRT, [4, 3, 2, 1])[0]
    speckle(px, ox, oy, PEBBLE, 5, rows)


def grass_side(px, ox, oy):
    dirt(px, ox, oy)
    for x in range(T):
        depth = 3 + rng.choice([0, 0, 1, 1, 2])
        for y in range(depth):
            px[ox + x, oy + y] = rng.choice(GRASS)
        px[ox + x, oy] = GRASS_HI if rng.random() < 0.4 else GRASS[2]


def path(px, ox, oy):
    noise(px, ox, oy, PATH, [4, 3, 2, 1])
    speckle(px, ox, oy, PATH_DARK, 8)
    speckle(px, ox, oy, PEBBLE, 4)


def flowers(px, ox, oy):
    grass(px, ox, oy)
    for _ in range(4):
        x, y = rng.randrange(1, T - 1), rng.randrange(1, T - 1)
        c = rng.choice(FLOWERS)
        px[ox + x, oy + y] = c
        px[ox + x + 1, oy + y] = c
        px[ox + x, oy + y + 1] = c


def stone(px, ox, oy):
    noise(px, ox, oy, STONE, [3, 2, 2])
    # Brick courses, offset every other row.
    for y in range(0, T, 4):
        for x in range(T):
            px[ox + x, oy + y] = STONE_LINE
        for x in range((y // 4 % 2) * 4, T, 8):
            for dy in range(4):
                px[ox + x, oy + y + dy] = STONE_LINE


def planks(px, ox, oy):
    for y in range(T):
        shade = rng.choice(WOOD)
        for x in range(T):
            px[ox + x, oy + y] = shade if rng.random() < 0.8 else rng.choice(WOOD)
    for y in range(0, T, 4):
        for x in range(T):
            px[ox + x, oy + y] = WOOD_LINE
        px[ox + rng.randrange(T), oy + y + 2] = WOOD_LINE


SOIL = [(140, 98, 62), (128, 88, 54), (152, 108, 70)]
SOIL_FURROW = (96, 64, 40)
WET = [(74, 50, 36), (66, 44, 32), (82, 56, 40)]
WET_FURROW = (44, 30, 22)


def tilled(px, ox, oy, palette=SOIL, furrow=SOIL_FURROW):
    noise(px, ox, oy, palette, [3, 2, 2])
    # Furrows across the plot, with a lighter lip above each.
    for y in (3, 7, 11, 15):
        for x in range(T):
            px[ox + x, oy + y] = furrow
            if y > 0 and rng.random() < 0.6:
                px[ox + x, oy + y - 1] = palette[2]
    # Square border so neighbouring plots read as separate.
    for i in range(T):
        for x, y in ((i, 0), (0, i)):
            px[ox + x, oy + y] = furrow


def tilled_wet(px, ox, oy):
    tilled(px, ox, oy, WET, WET_FURROW)


# Order matches GridWorld.Tex.
TILES = [grass, grass_side, lambda p, x, y: dirt(p, x, y), path, flowers, stone, planks, tilled, tilled_wet]

img = Image.new("RGB", (T * COLS, T * ROWS), (255, 0, 255))
px = img.load()
for i, draw in enumerate(TILES):
    draw(px, (i % COLS) * T, (i // COLS) * T)
img.save("assets/tileset.png")
print("wrote assets/tileset.png")
