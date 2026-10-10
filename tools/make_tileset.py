"""Draws the 16x16 pixel-art tileset atlas used by the GridMap blocks.

The style follows Pokemon HeartGold/SoulSilver: a small, bright palette and
ordered, hand-placed patterns (grass tufts, pebbles, paving) rather than
noise, with cliff-like block sides.

Run from the repo root:  python3 tools/make_tileset.py
Writes assets/tileset.png. The tile order must match GridWorld.Tex.
"""
from PIL import Image

T = 16
COLS, ROWS = 4, 3

GRASS = (120, 200, 88)
GRASS_DARK = (72, 152, 64)
GRASS_LIGHT = (176, 232, 128)
GRASS_EDGE = (40, 104, 48)

ROCK = (208, 168, 112)
ROCK_MID = (176, 128, 80)
ROCK_DARK = (120, 80, 48)
ROCK_LIGHT = (232, 200, 144)

SAND = (232, 208, 152)
SAND_DARK = (200, 168, 112)
SAND_LIGHT = (248, 232, 184)

STONE = (200, 200, 212)
STONE_LIGHT = (236, 236, 244)
STONE_DARK = (152, 152, 172)
GROUT = (112, 112, 136)

WOOD = (208, 144, 80)
WOOD_LIGHT = (232, 176, 104)
WOOD_DARK = (128, 80, 40)

SOIL = (176, 120, 72)
SOIL_FURROW = (120, 76, 44)
SOIL_LIGHT = (200, 148, 96)
WET = (112, 76, 52)
WET_FURROW = (72, 46, 30)
WET_LIGHT = (140, 98, 68)

FLOWER_RED = (232, 72, 72)
FLOWER_WHITE = (248, 248, 248)
FLOWER_CENTER = (248, 216, 72)

# Tuft positions, chosen so the pattern tiles seamlessly without lining up.
TUFTS = [(1, 2), (9, 1), (5, 6), (13, 7), (2, 11), (10, 12), (6, 14)]
PEBBLES = [(3, 3), (11, 5), (6, 10), (13, 13), (1, 14)]


def fill(px, ox, oy, color, rows=range(T)):
    for y in rows:
        for x in range(T):
            px[ox + x, oy + y] = color


def put(px, ox, oy, x, y, color):
    px[ox + x % T, oy + y % T] = color


def grass(px, ox, oy):
    fill(px, ox, oy, GRASS)
    for x, y in TUFTS:
        # A small "v" tuft with a highlight above its left blade.
        put(px, ox, oy, x, y, GRASS_DARK)
        put(px, ox, oy, x + 2, y, GRASS_DARK)
        put(px, ox, oy, x + 1, y + 1, GRASS_DARK)
        put(px, ox, oy, x, y - 1, GRASS_LIGHT)


def rock_face(px, ox, oy, top=0):
    """Cliff rock: rows of rounded stones, staggered, each lit from the top-left."""
    fill(px, ox, oy, ROCK_DARK, range(top, T))
    rows = [(6, [0, 8]), (5, [4, 12]), (5, [2, 10])]
    y = top
    for height, starts in rows:
        if y >= T:
            break
        for k, x0 in enumerate(starts):
            width = (starts[(k + 1) % len(starts)] - x0) % T
            for dy in range(height - 1):
                for dx in range(width - 1):
                    if y + dy >= T:
                        continue
                    edge_l, edge_r = dx == 0, dx == width - 2
                    c = ROCK
                    if dy == 0 or (edge_l and dy < height - 2):
                        c = ROCK_LIGHT
                    elif dy == height - 2 or edge_r:
                        c = ROCK_MID
                    # Round off the stone's corners.
                    if (dy == 0 or dy == height - 2) and (edge_l or edge_r):
                        c = ROCK_DARK
                    put(px, ox, oy, x0 + dx, y + dy, c)
        y += height


def grass_side(px, ox, oy):
    rock_face(px, ox, oy, 4)
    # Grass lip hanging over the cliff, with a wavy dark edge.
    for x in range(T):
        depth = 3 + (1 if x % 4 in (1, 2) else 0)
        for y in range(depth):
            put(px, ox, oy, x, y, GRASS if y else GRASS_LIGHT)
        put(px, ox, oy, x, depth, GRASS_EDGE)
        put(px, ox, oy, x, depth + 1, ROCK_DARK)


def dirt(px, ox, oy):
    rock_face(px, ox, oy)


def path(px, ox, oy):
    fill(px, ox, oy, SAND)
    for x, y in PEBBLES:
        put(px, ox, oy, x, y, SAND_DARK)
        put(px, ox, oy, x + 1, y, SAND_DARK)
        put(px, ox, oy, x, y - 1, SAND_LIGHT)


def flowers(px, ox, oy):
    grass(px, ox, oy)
    for (cx, cy), petal in (((4, 4), FLOWER_RED), ((12, 12), FLOWER_WHITE)):
        for dx, dy in ((0, -1), (-1, 0), (1, 0), (0, 1)):
            put(px, ox, oy, cx + dx, cy + dy, petal)
        put(px, ox, oy, cx, cy, FLOWER_CENTER)
        put(px, ox, oy, cx, cy + 2, GRASS_DARK)


def stone(px, ox, oy):
    """Town paving: four bevelled slabs per tile."""
    for sx in (0, 8):
        for sy in (0, 8):
            for y in range(8):
                for x in range(8):
                    if x == 7 or y == 7:
                        c = GROUT
                    elif x == 0 or y == 0:
                        c = STONE_LIGHT
                    elif x == 6 or y == 6:
                        c = STONE_DARK
                    else:
                        c = STONE
                    put(px, ox, oy, sx + x, sy + y, c)


def planks(px, ox, oy):
    for y in range(T):
        row = y % 4
        c = WOOD_DARK if row == 3 else (WOOD_LIGHT if row == 0 else WOOD)
        for x in range(T):
            put(px, ox, oy, x, y, c)
    # Staggered plank ends and nails.
    for i, y in enumerate(range(0, T, 4)):
        end = 5 if i % 2 else 12
        for dy in range(3):
            put(px, ox, oy, end, y + dy, WOOD_DARK)
        put(px, ox, oy, end - 2, y + 1, WOOD_DARK)


def soil(px, ox, oy, base, furrow, light):
    fill(px, ox, oy, base)
    for y in (3, 7, 11, 15):
        for x in range(T):
            put(px, ox, oy, x, y, furrow)
            put(px, ox, oy, x, y - 1, light if x % 3 else base)
    for i in range(T):
        put(px, ox, oy, 0, i, furrow)


def tilled(px, ox, oy):
    soil(px, ox, oy, SOIL, SOIL_FURROW, SOIL_LIGHT)


def tilled_wet(px, ox, oy):
    soil(px, ox, oy, WET, WET_FURROW, WET_LIGHT)


def farmland(px, ox, oy):
    """Untilled soil: flat earth with a few clods."""
    fill(px, ox, oy, SOIL)
    for x, y in PEBBLES + [(8, 1), (14, 9)]:
        put(px, ox, oy, x, y, SOIL_FURROW)
        put(px, ox, oy, x + 1, y, SOIL_FURROW)
        put(px, ox, oy, x, y - 1, SOIL_LIGHT)


# Order matches GridWorld.Tex.
TILES = [grass, grass_side, dirt, path, flowers, stone, planks, tilled, tilled_wet, farmland]

img = Image.new("RGB", (T * COLS, T * ROWS), (255, 0, 255))
pixels = img.load()
for i, draw in enumerate(TILES):
    draw(pixels, (i % COLS) * T, (i // COLS) * T)
img.save("assets/tileset.png")
print("wrote assets/tileset.png")
