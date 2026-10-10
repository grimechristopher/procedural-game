"""Draws the prop sprites (trees, rocks, tall grass) and the water textures.

Run from the repo root:  python3 tools/make_props.py
Writes assets/props.png: 32x48 cells in the order of GridWorld.PROP_SPRITES,
each drawn standing on the cell's bottom edge, centred; and assets/water.png:
a 16x16 water surface tile then a 16x16 waterfall tile, both tiling.
"""
from PIL import Image

W, H = 32, 48
OUTLINE = (30, 40, 34)

PINE = [(40, 72, 50), (56, 94, 62), (82, 124, 78)]
PINE_SNOW = [(200, 212, 224), (232, 240, 248)]
TRUNK = (92, 62, 40)
BOULDER = [(96, 96, 104), (128, 128, 134), (164, 164, 168)]
BUSH = [(56, 90, 50), (76, 114, 62), (104, 140, 80)]
BLADE = [(70, 104, 54), (94, 132, 66), (130, 160, 86)]


def outline(img, box):
    """Darkens transparent pixels next to opaque ones, within box."""
    x0, y0, x1, y1 = box
    src = img.copy().load()
    px = img.load()
    for y in range(y0, y1):
        for x in range(x0, x1):
            if src[x, y][3]:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                if x0 <= x + dx < x1 and y0 <= y + dy < y1 and src[x + dx, y + dy][3]:
                    px[x, y] = OUTLINE + (255,)
                    break


def put(px, ox, x, y, c):
    if 0 <= x < W and 0 <= y < H:
        px[ox + x, y] = c + (255,)


def pine(px, ox, snow=False):
    for y in range(39, 46):
        for x in range(14, 18):
            put(px, ox, x, y, TRUNK)
    # Four tiers, widest at the bottom, each lit from the left.
    for top, bottom, half in ((3, 15, 6), (10, 24, 9), (18, 33, 11), (26, 41, 13)):
        for y in range(top, bottom):
            w = max(1, half * (y - top + 1) // (bottom - top))
            for x in range(16 - w, 16 + w):
                rel = (x - (16 - w)) / max(1, 2 * w)
                c = PINE[2] if rel < 0.3 else (PINE[1] if rel < 0.7 else PINE[0])
                if y == bottom - 1 and (x % 3 == 0):
                    c = PINE[0]
                put(px, ox, x, y, c)
            if snow and y < top + 3:
                for x in range(16 - w, 16 + w):
                    put(px, ox, x, y, PINE_SNOW[1] if x < 16 else PINE_SNOW[0])
        if snow:
            for x in range(16 - half + 1, 16 + half - 1, 2):
                put(px, ox, x, bottom - 2, PINE_SNOW[1])


def boulder(px, ox):
    cx, cy, rx, ry = 16, 39, 10, 7
    for y in range(cy - ry, cy + ry + 1):
        for x in range(cx - rx, cx + rx + 1):
            d = ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2
            if d <= 1:
                light = (x - cx) / rx + (y - cy) / ry
                c = BOULDER[2] if light < -0.6 else (BOULDER[1] if light < 0.4 else BOULDER[0])
                put(px, ox, x, y, c)
    for x in range(10, 16):
        put(px, ox, x + 3, 37 + x % 2, BOULDER[0])


def bush(px, ox):
    for cx, cy, r in ((11, 38, 6), (21, 38, 6), (16, 34, 7)):
        for y in range(cy - r, cy + r + 1):
            for x in range(cx - r, cx + r + 1):
                if (x - cx) ** 2 + (y - cy) ** 2 <= r * r:
                    light = (x - cx) + (y - cy)
                    c = BUSH[2] if light < -4 else (BUSH[1] if light < 3 else BUSH[0])
                    put(px, ox, x, y, c)
    for y in range(44, 46):
        for x in range(9, 24):
            put(px, ox, x, y, BUSH[0])


def tall_grass(px, ox):
    """Pokemon-style tall grass: three short tufts across the cell (16px, centred)."""
    for tuft_x in (9, 14, 19):
        for dx in range(5):
            x = tuft_x + dx
            height = (4, 6, 7, 6, 4)[dx]
            for y in range(46 - height, 46):
                c = BLADE[2] if y < 46 - height + 2 else (BLADE[1] if dx % 2 else BLADE[0])
                put(px, ox, x, y, c)


SPRITES = [pine, lambda p, ox: pine(p, ox, snow=True), boulder, bush, tall_grass]

img = Image.new("RGBA", (W * len(SPRITES), H), (0, 0, 0, 0))
pixels = img.load()
for i, draw in enumerate(SPRITES):
    draw(pixels, i * W)
    outline(img, (i * W, 0, i * W + W, H))
img.save("assets/props.png")
print("wrote assets/props.png")

# --- Water ---------------------------------------------------------------------
WATER = (64, 112, 160)
WATER_DARK = (48, 90, 136)
WATER_LIGHT = (110, 160, 204)
GLINT = (200, 226, 242)
FALL = (96, 150, 200)
FALL_LIGHT = (164, 204, 232)
FALL_DARK = (66, 114, 166)
FOAM = (232, 244, 250)

water = Image.new("RGB", (32, 16), WATER)
wp = water.load()
for x0, y in ((1, 2), (9, 5), (4, 9), (12, 12), (7, 15)):
    for dx in range(5):
        wp[(x0 + dx) % 16, y] = WATER_LIGHT
    wp[(x0 + 1) % 16, (y - 1) % 16] = GLINT
    wp[(x0 + 5) % 16, y] = WATER_DARK
    wp[(x0 + 2) % 16, (y + 1) % 16] = WATER_DARK
FALL_COLUMNS = [FALL, FALL_LIGHT, FALL, FALL_DARK, FALL, FALL_LIGHT, FALL_LIGHT, FALL,
                FALL_DARK, FALL, FALL_LIGHT, FALL, FALL, FALL_DARK, FALL_LIGHT, FALL]
for y in range(16):
    for x in range(16):
        c = FALL_COLUMNS[x]
        # Short breaks in the streaks so the scroll reads as falling water.
        if (y + x * 5) % 16 < 2:
            c = FALL
        if (x, y) in ((2, 3), (9, 11), (13, 6)):
            c = FOAM
        wp[16 + x, y] = c
water.save("assets/water.png")
print("wrote assets/water.png")
