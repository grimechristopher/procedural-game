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
# Where body parts sit for each direction. Side and three-quarter rows face
# east-ish; the game mirrors them for the west. In three-quarter views the
# body turns: the near side of the torso shows as a darker strip, the near
# arm is in full view and the far arm mostly hides behind the body.
#
# Facing south-east, the character's right side faces south-west, so the
# near side and near arm are on the image's left; facing north-east they're
# on the image's right.

HEAD_ROWS = {6: (13, 18), 7: (11, 20), 17: (12, 19)}  # other rows span 10..21

GEOM = {
    S: dict(torso=(11, 20), side=None, arms=[(9, 10), (21, 22)], legs=[(12, 14), (17, 19)], head=0),
    SE: dict(torso=(12, 20), side=(12, 13), arms=[(10, 11), (21, 21)], legs=[(12, 14), (16, 18)], head=1),
    E: dict(torso=(12, 19), side=None, arms=[(14, 16)], legs=None, head=1),
    NE: dict(torso=(11, 19), side=(18, 19), arms=[(10, 10), (20, 21)], legs=[(12, 14), (16, 18)], head=1),
    N: dict(torso=(11, 20), side=None, arms=[(9, 10), (21, 22)], legs=[(12, 14), (17, 19)], head=0),
}


def head_span(y, shift=0):
    lo, hi = HEAD_ROWS.get(y, (10, 21))
    return lo + shift, hi + shift


def head_shift(direction):
    return GEOM[direction]["head"]


def torso(direction):
    return GEOM[direction]["torso"]


def legs(direction, frame):
    """(x0, x1, bottom_y) per leg, back to front."""
    if direction == E:
        if frame == STAND:
            return [(13, 17, 28)]
        front = (16, 18, 28) if frame == STEP_A else (12, 14, 28)
        back = (12, 14, 27) if frame == STEP_A else (16, 18, 27)
        return [back, front]
    (l0, l1), (r0, r1) = GEOM[direction]["legs"]
    lb, rb = 28, 28
    if frame == STEP_A:
        lb, rb = 29, 27
    elif frame == STEP_B:
        lb, rb = 27, 29
    return [(l0, l1, lb), (r0, r1, rb)]


def arms(direction, frame):
    """(x0, x1, top_y, bottom_y, far) per visible arm."""
    if direction == E:
        swing = {STAND: 0, STEP_A: 1, STEP_B: -1}[frame]
        return [(14 + swing, 16 + swing, 18, 23, False)]
    out = []
    for a0, a1 in GEOM[direction]["arms"]:
        far = a1 == a0 and direction in (SE, NE)
        out.append((a0, a1, 19 if far else 18, 22 if far else 23, far))
    return out


def side_strip(f, d, top, bottom):
    """Darkens the near side of the torso in three-quarter views."""
    strip = GEOM[d]["side"]
    if strip:
        f.rect(strip[0], top, strip[1], bottom, 1, lit=False)


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
    elif d == SE:
        f.dot(22, 13, shade(1))  # nose just past the cheek
    t0, t1 = torso(d)
    f.rect(t0, 18, t1, 23)
    side_strip(f, d, 18, 23)
    for a0, a1, top, bottom, far in arms(d, fr):
        f.rect(a0, top, a1, bottom, 1 if far else 2, lit=not far)
    for l0, l1, bottom in legs(d, fr):
        f.rect(l0, 24, l1, bottom)


def eyes(f, d, fr):
    if d in (N, NE):
        return
    if d == E:
        f.dot(19, 12, shade(0))
        f.dot(19, 13, shade(1))
        f.dot(20, 12, EYE_WHITE)
        return
    if d == SE:
        # Far eye pinched toward the turned-away side, near eye full.
        f.dot(15, 12, shade(0))
        f.dot(15, 13, shade(1))
        f.dot(19, 12, shade(0))
        f.dot(19, 13, shade(1))
        f.dot(20, 12, EYE_WHITE)
        return
    for x in (13, 18):
        f.dot(x, 12, shade(0))
        f.dot(x, 13, shade(1))
        f.dot(x, 11, shade(3))


def hair_short(f, d, fr):
    hs = head_shift(d)
    if d in (N, NE):
        for y in range(5, 17):
            lo, hi = head_span(y, hs)
            if d == NE and y >= 11:
                hi -= 2  # cheek and ear show on the near side
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
    elif d == SE:
        # The back of the head shows on the turned-away side.
        lo = head_span(12, hs)[0]
        for y in range(11, 16):
            for x in range(lo, lo + 3):
                f.dot(x, y, shade(1 if x == lo + 2 else 2))
        for x in range(lo + 4, head_span(11, hs)[1], 3):
            f.dot(x, 11, shade(2))
    else:
        for x in (10 + hs, 21 + hs):
            for y in range(11, 14):
                f.dot(x, y, shade(1))
        for x in range(12 + hs, 20 + hs, 3):
            f.dot(x, 11, shade(2))


def hair_long(f, d, fr):
    hair_short(f, d, fr)
    hs = head_shift(d)
    if d == N:
        f.rect(10, 17, 21, 21, 2)
    elif d == NE:
        f.rect(11, 17, 19, 21, 2)
    elif d == E:
        f.rect(10, 11, 15, 21, 2)
    elif d == SE:
        f.rect(10, 9, 13, 21, 2)
        f.rect(22, 9, 22, 18, 1, lit=False)
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
    if d == S:
        f.fixed(14, 4, 17, 6, WHITE)
        f.rect(9, 8, 22, 9, 1, lit=False)
    elif d == SE:
        f.fixed(16, 4, 19, 6, WHITE)
        f.rect(12, 8, 24, 9, 1, lit=False)  # brim turned toward the facing
    elif d == E:
        f.rect(18, 8, 25, 9, 1, lit=False)
    elif d == NE:
        f.rect(20, 8, 24, 8, 1, lit=False)  # brim peeking past the near side
        f.rect(14, 8, 16, 8, 0, lit=False)
    else:
        f.rect(14, 8, 17, 8, 0, lit=False)


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
    side_strip(f, d, 18, 23)
    if d in (S, SE):
        mid = (t0 + t1) // 2 + (1 if d == SE else 0)
        f.dot(mid, 18, (0, 0, 0, 0))
        f.dot(mid + 1, 18, (0, 0, 0, 0))
    for a0, a1, top, bottom, far in arms(d, fr):
        f.rect(a0, top, a1, min(bottom, sleeve_end), 1 if far else 2, lit=not far)


def top_long(f, d, fr):
    top_tee(f, d, fr, 22)


def top_jacket(f, d, fr):
    top_long(f, d, fr)
    if d in (S, SE):
        t0, t1 = torso(d)
        mid = (t0 + t1) // 2 + (1 if d == SE else 0)
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
        if d in (E, SE):
            f.rect(l0, bottom, l1 + 1, bottom + 1, 1)  # toes toward the facing
        elif d == NE:
            f.rect(l0, bottom, l1, bottom + 1, 1)
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
