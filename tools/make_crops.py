"""Draws the 16x16 crop and item sprite sheet used by the farming system.

Run from the repo root:  python3 tools/make_crops.py
Writes assets/crops.png. Rows match Crops.ALL[...].row; columns are
  0 seeds in soil, 1-4 growth stages, 5 ready to harvest,
  6 harvested item icon, 7 seed packet icon.
The last row holds tool icons and the dead crop (see Crops.ICONS).
"""
import random

from PIL import Image, ImageDraw

T = 16
COLS, ROWS = 8, 7
rng = random.Random(3)

LEAF = [(58, 140, 52), (78, 166, 64), (44, 112, 44)]
STEM = (60, 120, 46)
SEED = (120, 92, 52)
STAKE = (150, 110, 64)


def put(px, ox, oy, x, y, c):
    if 0 <= x < T and 0 <= y < T:
        px[ox + x, oy + y] = c + (255,)


def leaf_tuft(px, ox, oy, size, top):
    """A bushy tuft of leaves rising from the bottom centre to row `top`."""
    for y in range(top, T - 1):
        spread = max(1, int(size * (y - top + 2) / (T - top)))
        for x in range(8 - spread, 8 + spread):
            if rng.random() < 0.75:
                put(px, ox, oy, x, y, rng.choice(LEAF))
    put(px, ox, oy, 7, T - 1, STEM)
    put(px, ox, oy, 8, T - 1, STEM)


def seeds(px, ox, oy):
    for x, y in ((5, 14), (8, 13), (10, 14), (7, 15)):
        put(px, ox, oy, x, y, SEED)


def sprout(px, ox, oy):
    for y in range(11, 16):
        put(px, ox, oy, 8, y, STEM)
    for x, y in ((6, 11), (7, 12), (9, 11), (10, 10), (6, 10)):
        put(px, ox, oy, x, y, LEAF[1])


def blob(px, ox, oy, cx, cy, r, colors, outline=None):
    for y in range(cy - r, cy + r + 1):
        for x in range(cx - r, cx + r + 1):
            d = (x - cx) ** 2 + (y - cy) ** 2
            if d <= r * r + r:
                edge = d > (r - 1) ** 2 + (r - 1) and outline
                put(px, ox, oy, x, y, outline if edge else rng.choice(colors))


def stake(px, ox, oy, top):
    for y in range(top, T):
        put(px, ox, oy, 12, y, STAKE)
        put(px, ox, oy, 3, y, STAKE)
    for x in range(3, 13):
        put(px, ox, oy, x, top + 1, STAKE)


# Each crop: how its growth stages look, what it looks like ready, and its item.
def parsnip_ready(px, ox, oy):
    leaf_tuft(px, ox, oy, 5, 3)
    blob(px, ox, oy, 8, 13, 2, [(236, 222, 170), (220, 204, 150)])


def parsnip_item(px, ox, oy):
    for i in range(9):
        w = max(1, 3 - i // 3)
        for x in range(8 - w, 8 + w):
            put(px, ox, oy, x, 5 + i, rng.choice([(236, 222, 170), (220, 204, 150)]))
    for x, y in ((6, 2), (7, 3), (8, 2), (9, 3), (10, 2), (8, 4)):
        put(px, ox, oy, x, y, LEAF[1])


def potato_ready(px, ox, oy):
    leaf_tuft(px, ox, oy, 6, 4)
    for cx in (5, 11):
        blob(px, ox, oy, cx, 14, 1, [(176, 130, 80), (160, 116, 70)])


def potato_item(px, ox, oy):
    blob(px, ox, oy, 8, 9, 5, [(186, 140, 88), (170, 124, 76)], (110, 76, 44))
    for x, y in ((6, 7), (10, 10), (8, 12)):
        put(px, ox, oy, x, y, (120, 86, 52))


def cauliflower_ready(px, ox, oy):
    leaf_tuft(px, ox, oy, 7, 4)
    blob(px, ox, oy, 8, 9, 3, [(244, 240, 226), (230, 226, 210)], (200, 196, 180))


def cauliflower_item(px, ox, oy):
    blob(px, ox, oy, 8, 7, 5, [(244, 240, 226), (230, 226, 210)], (200, 196, 180))
    for x in range(3, 13):
        put(px, ox, oy, x, 12 + (x % 2), LEAF[0])


def bean_growth(px, ox, oy, stage):
    stake(px, ox, oy, 1)
    top = 14 - stage * 3
    for y in range(top, T):
        put(px, ox, oy, 7 + (y % 2), y, STEM)
        if rng.random() < 0.7:
            put(px, ox, oy, 6 + 3 * (y % 2), y, rng.choice(LEAF))


def bean_ready(px, ox, oy):
    bean_growth(px, ox, oy, 4)
    for x, y in ((5, 5), (10, 7), (6, 10), (10, 11)):
        for d in range(3):
            put(px, ox, oy, x, y + d, (120, 196, 70))


def bean_item(px, ox, oy):
    for i in range(10):
        put(px, ox, oy, 4 + i, 12 - i, (110, 186, 64))
        put(px, ox, oy, 5 + i, 12 - i, (90, 160, 52))


def melon_ready(px, ox, oy):
    leaf_tuft(px, ox, oy, 7, 6)
    blob(px, ox, oy, 8, 11, 4, [(110, 170, 70), (90, 150, 56)], (60, 110, 40))


def melon_item(px, ox, oy):
    blob(px, ox, oy, 8, 9, 6, [(110, 170, 70)], (60, 110, 40))
    for x in (5, 8, 11):
        for y in range(4, 15):
            if (x - 8) ** 2 + (y - 9) ** 2 < 30:
                put(px, ox, oy, x, y, (70, 126, 46))


def tomato_growth(px, ox, oy, stage):
    stake(px, ox, oy, 2)
    leaf_tuft(px, ox, oy, 2 + stage, 14 - stage * 3)


def tomato_ready(px, ox, oy):
    tomato_growth(px, ox, oy, 4)
    for cx, cy in ((5, 6), (10, 8), (7, 11)):
        blob(px, ox, oy, cx, cy, 1, [(220, 52, 40), (200, 40, 32)])


def tomato_item(px, ox, oy):
    blob(px, ox, oy, 8, 9, 5, [(222, 56, 42), (204, 44, 34)], (150, 30, 24))
    for x, y in ((7, 3), (8, 4), (9, 3), (8, 3)):
        put(px, ox, oy, x, y, LEAF[2])


def generic_growth(px, ox, oy, stage):
    if stage == 1:
        sprout(px, ox, oy)
    else:
        leaf_tuft(px, ox, oy, 2 + stage, 15 - stage * 3)


CROPS = [
    # (growth stage drawer, ready drawer, item drawer, packet colour)
    (generic_growth, parsnip_ready, parsnip_item, (236, 222, 170)),
    (generic_growth, potato_ready, potato_item, (176, 130, 80)),
    (generic_growth, cauliflower_ready, cauliflower_item, (240, 236, 220)),
    (lambda p, x, y, s: sprout(p, x, y) if s == 1 else bean_growth(p, x, y, s), bean_ready, bean_item, (110, 186, 64)),
    (generic_growth, melon_ready, melon_item, (110, 170, 70)),
    (lambda p, x, y, s: sprout(p, x, y) if s == 1 else tomato_growth(p, x, y, s), tomato_ready, tomato_item, (220, 52, 40)),
]


def packet(px, ox, oy, color):
    for y in range(2, 15):
        for x in range(3, 13):
            put(px, ox, oy, x, y, (226, 206, 160) if y > 4 else (196, 170, 120))
    blob(px, ox, oy, 8, 9, 3, [color], tuple(max(0, c - 50) for c in color))
    for x in range(3, 13):
        put(px, ox, oy, x, 2, (150, 120, 80))
        put(px, ox, oy, x, 14, (150, 120, 80))


def hoe(px, ox, oy):
    for i in range(11):
        put(px, ox, oy, 3 + i, 14 - i, (150, 104, 60))
    for x, y in ((10, 2), (11, 2), (12, 2), (13, 2), (13, 3), (13, 4), (12, 3)):
        put(px, ox, oy, x, y, (150, 156, 170))


def can(px, ox, oy):
    for y in range(6, 14):
        for x in range(4, 11):
            put(px, ox, oy, x, y, (110, 140, 190) if x > 4 else (80, 106, 150))
    for i in range(5):
        put(px, ox, oy, 11 + i // 2 * 1, 8 - i // 2, (80, 106, 150))
        put(px, ox, oy, 11 + i, 9 - i, (80, 106, 150))
    for x in range(5, 10):
        put(px, ox, oy, x, 4, (60, 80, 120))
    put(px, ox, oy, 4, 5, (60, 80, 120))
    put(px, ox, oy, 10, 5, (60, 80, 120))


def dead(px, ox, oy):
    for y in range(6, 16):
        put(px, ox, oy, 8 + (y % 3 == 0), y, (120, 96, 60))
    for x, y in ((5, 8), (6, 9), (10, 7), (11, 8), (6, 12), (10, 11)):
        put(px, ox, oy, x, y, (140, 112, 70))


img = Image.new("RGBA", (T * COLS, T * ROWS), (0, 0, 0, 0))
px = img.load()
for row, (growth, ready, item, color) in enumerate(CROPS):
    oy = row * T
    seeds(px, 0, oy)
    for stage in range(1, 5):
        growth(px, stage * T, oy, stage)
    ready(px, 5 * T, oy)
    item(px, 6 * T, oy)
    packet(px, 7 * T, oy, color)
oy = len(CROPS) * T
for col, draw in enumerate([hoe, can, dead]):
    draw(px, col * T, oy)
img.save("assets/crops.png")
print("wrote assets/crops.png")
