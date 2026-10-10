"""Draws the 16x16 pixel-art tileset atlas used by the GridMap blocks.

The style follows the concept art in documentation/concept: a muted
natural palette (olive grass, grey rock, brown dirt), with HGSS-style
ordered, hand-placed patterns (grass tufts, pebbles, paving) rather than
noise, and cliff-like block sides.

Run from the repo root:  python3 tools/make_tileset.py
Writes assets/tileset.png. The tile order must match GridWorld.Tex.
"""
from PIL import Image

T = 16
COLS, ROWS = 4, 7

GRASS = (118, 150, 74)
GRASS_DARK = (84, 116, 58)
GRASS_LIGHT = (150, 178, 96)
GRASS_EDGE = (56, 82, 44)

# Cliffs are warm earth, as in HGSS and BW.
ROCK = (184, 128, 78)
ROCK_MID = (150, 100, 60)
ROCK_DARK = (102, 66, 42)
ROCK_LIGHT = (214, 164, 108)

SAND = (170, 138, 96)
SAND_DARK = (138, 108, 72)
SAND_LIGHT = (194, 164, 120)

STONE = (172, 164, 150)
STONE_LIGHT = (204, 196, 180)
STONE_DARK = (138, 130, 118)
GROUT = (96, 90, 82)

WOOD = (138, 96, 60)
WOOD_LIGHT = (164, 118, 76)
WOOD_DARK = (80, 54, 34)

SOIL = (176, 120, 72)
SOIL_FURROW = (120, 76, 44)
SOIL_LIGHT = (200, 148, 96)
WET = (112, 76, 52)
WET_FURROW = (72, 46, 30)
WET_LIGHT = (140, 98, 68)

THATCH = (196, 156, 84)
THATCH_DARK = (148, 110, 56)
THATCH_LIGHT = (226, 192, 118)
SHINGLE = (128, 78, 58)
SHINGLE_DARK = (86, 50, 38)
SHINGLE_LIGHT = (162, 104, 76)
PLASTER = (226, 218, 196)
PLASTER_DARK = (204, 194, 170)
BEAM = (96, 64, 42)
BEAM_DARK = (70, 46, 30)
GLASS = (240, 202, 104)
GLASS_LIGHT = (252, 232, 160)
DOOR = (124, 84, 50)
DOOR_DARK = (84, 56, 34)
BRASS = (230, 190, 90)
FIELD = (150, 146, 138)
FIELD_LIGHT = (178, 174, 166)
FIELD_DARK = (112, 108, 102)
MORTAR = (86, 82, 76)
EMBER = [(120, 30, 20), (200, 60, 24), (244, 128, 40), (252, 210, 90)]

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
    """Cliff rock as HGSS draws it: horizontal strata, each a lit ridge
    shading down into a dark seam, with the seams wavering a pixel up and
    down so they don't read as brick courses."""
    wave = [0, 0, 1, 1, 1, 0, 0, 0, -1, -1, 0, 0, 1, 0, 0, -1]
    for x in range(T):
        for y in range(top, T):
            k = (y - wave[x]) % 4
            c = [ROCK_LIGHT, ROCK, ROCK_MID, ROCK_DARK][k]
            put(px, ox, oy, x, y, c)
    # A few vertical cracks breaking the ridges.
    for x, y0 in [(3, 1), (11, 6), (7, 10), (14, 13)]:
        for y in range(y0, min(y0 + 2, T)):
            if y >= top:
                put(px, ox, oy, x, y, ROCK_DARK)


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


def thatch(px, ox, oy):
    """Layered straw: bands with dark undersides and diagonal strands."""
    for y in range(T):
        band = y % 4
        for x in range(T):
            c = THATCH_DARK if band == 3 else (THATCH_LIGHT if band == 0 and (x + y) % 3 == 0 else THATCH)
            if band in (1, 2) and (x + y // 4) % 4 == 0:
                c = THATCH_DARK
            put(px, ox, oy, x, y, c)


def shingle(px, ox, oy):
    """Wooden shingles in staggered rows, each with a dark lower edge."""
    for y in range(T):
        row, r = divmod(y, 4)
        for x in range(T):
            c = SHINGLE_LIGHT if r == 0 else (SHINGLE_DARK if r == 3 else SHINGLE)
            if (x + row * 2) % 4 == 0 and r < 3:
                c = SHINGLE_DARK
            put(px, ox, oy, x, y, c)


def plaster(px, ox, oy):
    """Plaster between timber beams: a post on the left, a beam on top."""
    fill(px, ox, oy, PLASTER)
    for x, y in ((5, 6), (11, 10), (8, 13), (13, 4)):
        put(px, ox, oy, x, y, PLASTER_DARK)
    for i in range(T):
        put(px, ox, oy, 0, i, BEAM)
        put(px, ox, oy, 1, i, BEAM_DARK)
        put(px, ox, oy, i, 0, BEAM)
        put(px, ox, oy, i, 1, BEAM_DARK)


def window(px, ox, oy):
    """A warmly lit window: wooden frame, four panes."""
    fill(px, ox, oy, BEAM)
    for y in range(2, 14):
        for x in range(2, 14):
            c = GLASS_LIGHT if (x < 5 and y < 6) else GLASS
            if x in (7, 8) or y in (7, 8):
                c = BEAM_DARK
            put(px, ox, oy, x, y, c)
    for x in range(T):
        put(px, ox, oy, x, 15, BEAM_DARK)


def door_planks(px, ox, oy):
    for y in range(T):
        for x in range(T):
            put(px, ox, oy, x, y, DOOR_DARK if x % 4 == 3 else DOOR)
    for y in range(T):
        put(px, ox, oy, 0, y, BEAM_DARK)
        put(px, ox, oy, 15, y, BEAM_DARK)


def door_top(px, ox, oy):
    door_planks(px, ox, oy)
    for x in range(T):
        put(px, ox, oy, x, 0, BEAM_DARK)
        put(px, ox, oy, x, 1, BEAM)
    for x in range(2, 14):
        put(px, ox, oy, x, 6, BEAM)  # cross brace


def door_bottom(px, ox, oy):
    door_planks(px, ox, oy)
    for x in range(2, 14):
        put(px, ox, oy, x, 9, BEAM)
    put(px, ox, oy, 12, 2, BRASS)
    put(px, ox, oy, 12, 3, BRASS)


def fieldstone(px, ox, oy):
    """Irregular rounded stones set in dark mortar."""
    fill(px, ox, oy, MORTAR)
    stones = [(0, 0, 6, 4), (7, 0, 15, 3), (0, 5, 4, 9), (5, 5, 11, 8), (12, 4, 15, 9),
              (0, 10, 7, 15), (8, 9, 15, 14)]
    for x0, y0, x1, y1 in stones:
        for y in range(y0, y1):
            for x in range(x0, x1):
                c = FIELD
                if y == y0 or x == x0:
                    c = FIELD_LIGHT
                if y == y1 - 1 or x == x1 - 1:
                    c = FIELD_DARK
                put(px, ox, oy, x, y, c)


def embers(px, ox, oy):
    """Glowing forge coals."""
    for y in range(T):
        for x in range(T):
            put(px, ox, oy, x, y, EMBER[((x * 7 + y * 3) % 9) // 3 + (1 if (x + y) % 5 == 0 else 0)])


def earth_side(px, ox, oy):
    """The earth face of cliffs on gentle ground. Those are half a block
    tall, showing only the top 8 rows, so those rows make a whole face on
    their own: lit earth carrying on down from the band on the cliff's top,
    darker toward the foot. The bottom rows carry on for taller faces."""
    bands = [ROCK, ROCK, ROCK_LIGHT, ROCK, ROCK, ROCK, ROCK_MID, ROCK_DARK,
             ROCK, ROCK_LIGHT, ROCK, ROCK, ROCK_MID, ROCK, ROCK_MID, ROCK_DARK]
    for y, c in enumerate(bands):
        fill(px, ox, oy, c, [y])
    # Short vertical streaks of shade, staggered.
    for x, y0, length in [(1, 3, 2), (5, 4, 2), (9, 3, 3), (12, 4, 2), (3, 10, 3), (10, 9, 4), (14, 11, 2)]:
        for y in range(y0, y0 + length):
            put(px, ox, oy, x, y, ROCK_MID)
    # Pebbles with a lit top.
    for x, y in [(6, 4), (13, 2), (7, 12), (1, 13)]:
        put(px, ox, oy, x, y, ROCK_LIGHT)
        put(px, ox, oy, x + 1, y, ROCK_LIGHT)
        put(px, ox, oy, x, y + 1, ROCK_DARK)
        put(px, ox, oy, x + 1, y + 1, ROCK_DARK)


# --- Cliff-top autotile pieces ---------------------------------------------
# The band along a cliff's top edge comes in three pieces, each drawn for the
# south-east quarter of a cell (columns and rows 8-15 of its tile; the rest
# is grass): an EDGE where the south side drops away, an OUTER corner where
# the south and east sides both do, and an INNER corner where only the
# south-east diagonal does. The game mirrors and flips them for the other
# quarters. Across 8 px from the cell's centre: grass, a 2 px fringe, then
# 3 px of rock or earth, its outermost row lit where it meets the face.
# Edge pieces also run the band across the whole tile width, for diagonal
# cliffs.

def _band_color(depth, rim, at_edge):
    """depth: px out from the grass. rim: the rock or earth ramp (base,
    shade, highlight). at_edge: on the cell's outer edge, where the face
    below begins."""
    if depth < 1:
        return GRASS_DARK
    if depth < 2:
        return GRASS_EDGE
    if at_edge:
        return rim[2]
    return rim[0] if depth < 3 else rim[1]


def _cliff_piece(px, ox, oy, kind, rim):
    fill(px, ox, oy, GRASS)
    for y in range(8, T):
        for x in range(0 if kind == "edge" else 8, T):
            lx, ly = x - 8 + 0.5, y - 8 + 0.5
            if kind == "edge":
                depth = ly - 3
                # A wavy fringe.
                if int(ly) == 3 and x % 4 in (1, 2):
                    depth = -1
            elif kind == "outer":
                depth = (lx * lx + ly * ly) ** 0.5 - 3
            else:
                depth = 4.55 - ((8 - lx) ** 2 + (8 - ly) ** 2) ** 0.5
            if depth >= 0:
                at_edge = y == T - 1 or (kind != "edge" and x == T - 1)
                put(px, ox, oy, x, y, _band_color(depth, rim, at_edge))
    # Speckles in the rim.
    for x, y in [(9, 14), (13, 13), (3, 14), (11, 15)]:
        if px[ox + x, oy + y] == rim[1]:
            put(px, ox, oy, x, y, ROCK_MID if rim[0] == ROCK else ROCK_DARK)


CLIFF_RIM = [ROCK_MID, ROCK, ROCK_LIGHT]
EARTH_RIM = [ROCK, ROCK, ROCK_LIGHT]


def cliff_edge(px, ox, oy): _cliff_piece(px, ox, oy, "edge", CLIFF_RIM)
def cliff_outer(px, ox, oy): _cliff_piece(px, ox, oy, "outer", CLIFF_RIM)
def cliff_inner(px, ox, oy): _cliff_piece(px, ox, oy, "inner", CLIFF_RIM)
def earth_edge(px, ox, oy): _cliff_piece(px, ox, oy, "edge", EARTH_RIM)
def earth_outer(px, ox, oy): _cliff_piece(px, ox, oy, "outer", EARTH_RIM)
def earth_inner(px, ox, oy): _cliff_piece(px, ox, oy, "inner", EARTH_RIM)


# Order matches GridWorld.Tex.
TILES = [grass, grass_side, dirt, path, flowers, stone, planks, tilled, tilled_wet, farmland,
         thatch, shingle, plaster, window, door_top, door_bottom, fieldstone, embers,
         earth_side,
         cliff_edge, cliff_outer, cliff_inner, earth_edge, earth_outer, earth_inner]

img = Image.new("RGB", (T * COLS, T * ROWS), (255, 0, 255))
pixels = img.load()
for i, draw in enumerate(TILES):
    draw(pixels, (i % COLS) * T, (i // COLS) * T)
img.save("assets/tileset.png")
print("wrote assets/tileset.png")
