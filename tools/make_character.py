"""Draws the paper-doll layers for the player sprite.

Run from the repo root:  python3 tools/make_character.py
Writes assets/character/<layer>.png. Every sheet has the same layout: 32x32
frames, 3 columns (stand, step A, step B) by 5 rows of directions
(south, south-east, east, north-east, north); the game mirrors the east-side
rows for the west. See scripts/appearance.gd.

Recolourable pixels are drawn in marker colours (r, 0, 255) where r encodes
a shade 0 (darkest) to 3 (lightest); the game swaps them for a chosen
palette when it builds the sprite. Other pixels keep their colour. Outlines
are added by the game after stacking the layers, not drawn here.
"""
import os

from PIL import Image

F = 32
COLS, ROWS = 3, 5
S, SE, E, NE, N = range(5)
STAND, STEP_A, STEP_B = range(3)
WHITE = (240, 240, 236)
EYE_WHITE = (250, 250, 250)


def shade(k):
    return (40 + 60 * k, 0, 255)


class Frame:
    def __init__(self, img, col, row):
        self.px = img.load()
        self.ox = col * F
        self.oy = row * F

    def dot(self, x, y, c):
        if 0 <= x < F and 0 <= y < F:
            self.px[self.ox + x, self.oy + y] = c + (255,) if len(c) == 3 else c

    def rect(self, x0, y0, x1, y1, k=2, lit=True):
        """Filled rect (inclusive), lit from the top-left in ramp shades."""
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                s = k
                if lit and x == x1 and x1 > x0:
                    s = max(0, k - 1)
                if lit and y == y0 and k < 3 and y1 > y0:
                    s = min(3, k + 1)
                self.dot(x, y, shade(s))

    def fixed(self, x0, y0, x1, y1, c):
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                self.dot(x, y, c)


# --- Skeleton -----------------------------------------------------------------
# Where body parts sit for each direction and frame. Side-facing rows face
# east; diagonals borrow from the front or back view, nudged sideways.

HEAD_ROWS = {6: (13, 18), 7: (11, 20), 17: (12, 19)}  # other rows span 10..21


def head_span(y, shift=0):
    lo, hi = HEAD_ROWS.get(y, (10, 21))
    return lo + shift, hi + shift


def legs(direction, frame):
    """(x0, x1, bottom_y) per leg."""
    if direction in (E, ):
        if frame == STAND:
            return [(13, 17, 28)]
        front = (16, 18, 28) if frame == STEP_A else (12, 14, 28)
        back = (12, 14, 27) if frame == STEP_A else (16, 18, 27)
        return [back, front]
    left, right = (12, 14, 28), (17, 19, 28)
    if frame == STEP_A:
        left, right = (12, 14, 29), (17, 19, 27)
    elif frame == STEP_B:
        left, right = (12, 14, 27), (17, 19, 29)
    if direction in (SE, NE):
        left, right = (left[0] + 1, left[1] + 1, left[2]), (right[0] + 1, right[1] + 1, right[2])
    return [left, right]


def arms(direction, frame):
    """(x0, x1, top_y, bottom_y) per visible arm."""
    if direction == E:
        swing = {STAND: 0, STEP_A: 1, STEP_B: -1}[frame]
        return [(14 + swing, 16 + swing, 18, 23)]
    shift = 1 if direction in (SE, NE) else 0
    return [(9 + shift, 10 + shift, 18, 23), (21 + shift, 22 + shift, 18, 23)]


def torso(direction):
    if direction == E:
        return (12, 19)
    shift = 1 if direction in (SE, NE) else 0
    return (11 + shift, 20 + shift)


def head_shift(direction):
    return 1 if direction in (SE, NE, E) else 0


# --- Layers -------------------------------------------------------------------

def body(f, d, fr):
    hs = head_shift(d)
    for y in range(6, 18):
        lo, hi = head_span(y, hs)
        for x in range(lo, hi + 1):
            k = 2
            if x == hi:
                k = 1
            elif x == lo or y == 7:
                k = 3
            f.dot(x, y, shade(k))
    if d == E:
        f.dot(22, 13, shade(2))  # nose
    t0, t1 = torso(d)
    f.rect(t0, 18, t1, 23)
    for a0, a1, top, bottom in arms(d, fr):
        f.rect(a0, top, a1, bottom)
    for l0, l1, bottom in legs(d, fr):
        f.rect(l0, 24, l1, bottom)


def eyes(f, d, fr):
    if d in (N, NE):
        return
    xs = {S: (13, 18), SE: (14, 19), E: (19,)}[d]
    for x in xs:
        f.dot(x, 12, shade(0))
        f.dot(x, 13, shade(1))
        f.dot(x + (1 if d == E else 0), 12 if d == E else 11, EYE_WHITE if d == E else shade(3))


def hair_short(f, d, fr, length=10):
    hs = head_shift(d)
    if d in (N, NE):
        for y in range(5, 17):
            lo, hi = head_span(y, hs)
            f.rect(lo, y, hi, y, 2 if y > 6 else 3)
        return
    for y in range(5, 11):
        lo, hi = head_span(y, hs)
        for x in range(lo, hi + 1):
            f.dot(x, y, shade(3 if y == 5 else (1 if x == hi else 2)))
    if d == E:
        # Covers the back of the head in profile.
        for y in range(11, 16):
            for x in range(11, 16):
                f.dot(x, y, shade(1 if x == 15 else 2))
    else:
        for x in (10 + hs, 21 + hs):
            for y in range(11, 14):
                f.dot(x, y, shade(1))
        for x in range(12 + hs, 20 + hs, 3):
            f.dot(x, 11, shade(2))


def hair_long(f, d, fr):
    hair_short(f, d, fr)
    hs = head_shift(d)
    if d in (N, NE):
        f.rect(10 + hs, 17, 21 + hs, 21, 2)
    elif d == E:
        f.rect(10, 11, 15, 21, 2)
    else:
        f.rect(9 + hs, 9, 10 + hs, 21, 2)
        f.rect(21 + hs, 9, 22 + hs, 21, 1, lit=False)


def hair_spiky(f, d, fr):
    hair_short(f, d, fr)
    hs = head_shift(d)
    for x in range(11 + hs, 22 + hs, 3):
        f.dot(x, 4, shade(3))
        f.dot(x, 3, shade(2))
        f.dot(x + 1, 4, shade(2))


def hat_cap(f, d, fr):
    hs = head_shift(d)
    f.rect(10 + hs, 3, 21 + hs, 8, 2)
    f.fixed(14 + hs, 4, 17 + hs, 6, WHITE) if d in (S, SE) else None
    if d in (S, SE):
        f.rect(9 + hs, 8, 22 + hs, 9, 1, lit=False)
    elif d == E:
        f.rect(18, 8, 25, 9, 1, lit=False)
    else:
        f.rect(14 + hs, 8, 17 + hs, 8, 0, lit=False)


def hat_beanie(f, d, fr):
    hs = head_shift(d)
    for y in range(2, 9):
        lo, hi = head_span(max(6, y + 2), hs)
        f.rect(lo, y, hi, y, 2 if y < 7 else 3, lit=False)
    f.dot(15 + hs, 1, shade(3))
    f.dot(16 + hs, 1, shade(3))


def top_tee(f, d, fr, sleeve_end=19):
    t0, t1 = torso(d)
    f.rect(t0, 18, t1, 23)
    if d in (S, SE):
        f.dot((t0 + t1) // 2, 18, (0, 0, 0, 0))
        f.dot((t0 + t1) // 2 + 1, 18, (0, 0, 0, 0))
    for a0, a1, top, _ in arms(d, fr):
        f.rect(a0, top, a1, sleeve_end)


def top_long(f, d, fr):
    top_tee(f, d, fr, 22)


def top_jacket(f, d, fr):
    top_long(f, d, fr)
    if d in (S, SE):
        t0, t1 = torso(d)
        mid = (t0 + t1) // 2
        f.fixed(mid, 18, mid + 1, 23, WHITE)
        f.dot(mid - 1, 18, shade(3))
        f.dot(mid + 2, 18, shade(3))


def bottom_pants(f, d, fr, leg_end=None):
    t0, t1 = torso(d)
    f.rect(t0 + 1, 23, t1 - 1, 24, 1, lit=False)
    for l0, l1, bottom in legs(d, fr):
        f.rect(l0, 24, l1, bottom - 1 if leg_end is None else min(bottom - 1, leg_end), 2)


def bottom_shorts(f, d, fr):
    bottom_pants(f, d, fr, leg_end=25)


def shoes(f, d, fr):
    for l0, l1, bottom in legs(d, fr):
        if d == E:
            f.rect(l0, bottom, l1 + 1, bottom + 1, 1)
        else:
            f.rect(l0 - (1 if l0 < 16 else 0), bottom, l1 + (1 if l0 >= 16 else 0), bottom + 1, 1)


LAYERS = {
    "body": body,
    "eyes": eyes,
    "hair_short": hair_short,
    "hair_long": hair_long,
    "hair_spiky": hair_spiky,
    "top_tee": top_tee,
    "top_long": top_long,
    "top_jacket": top_jacket,
    "bottom_pants": bottom_pants,
    "bottom_shorts": bottom_shorts,
    "shoes": shoes,
    "hat_cap": hat_cap,
    "hat_beanie": hat_beanie,
}

os.makedirs("assets/character", exist_ok=True)
for name, draw in LAYERS.items():
    img = Image.new("RGBA", (F * COLS, F * ROWS), (0, 0, 0, 0))
    for row in range(ROWS):
        for col in range(COLS):
            draw(Frame(img, col, row), row, col)
    img.save(f"assets/character/{name}.png")
print("wrote", len(LAYERS), "layers to assets/character/")
