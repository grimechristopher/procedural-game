"""Draws the paper-doll layers for the player sprite.

Styled after Pokemon Black & White's overworld trainers (original art, not
copies): about 28px tall in a 32x32 frame, a head roughly a third of the
height, slim two-pixel arms, separate legs, hair with volume above the head,
three-tone shading lit from the top-left, and an outline in a dark shade of
whatever it borders (added in-game). BW only drew four facings; the
diagonals here extend the same style.

The walk follows Bandygrass's 8-directional walk cycle tutorial: default,
up (body lifts 1px, the moving foot passes at its highest), contact (feet
and arms farthest apart; in front and back views the nearer foot is drawn
lower and wider), passing (back foot lifts), then the same with the other
leg. In diagonals, one side's arm and leg sit a pixel higher.

Run from the repo root:  python3 tools/make_character.py
Writes assets/character/<layer>.png. Every sheet has the same layout: 32x32
frames, 7 columns (default, then up / contact / passing for each leg) by 5
rows of directions
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
COLS, ROWS = 7, 5
S, SE, E, NE, N = range(5)
DEFAULT = 0
UP, CONTACT, PASSING = "up", "contact", "passing"
WHITE = (240, 240, 236)
EYE_WHITE = (250, 250, 250)


def shade(k):
    return (40 + 60 * k, 0, 255)


def stage(frame):
    """(moving leg 0 = image-left / 1 = image-right / None, walk stage) for a column."""
    if frame == DEFAULT:
        return None, None
    return (0 if frame <= 3 else 1), (UP, CONTACT, PASSING)[(frame - 1) % 3]


class Frame:
    """One 32x32 cell. Everything above the legs is lifted by `lift` pixels
    (the walk's bounce); legs and shoes are drawn with the raw_ methods."""

    def __init__(self, img, col, row):
        self.px = img.load()
        self.ox = col * F
        self.oy = row * F
        self.lift = 1 if stage(col)[1] == UP else 0

    def dot(self, x, y, c):
        self.raw_dot(x, y - self.lift if y < LEG_TOP else y, c)

    def raw_dot(self, x, y, c):
        if 0 <= x < F and 0 <= y < F:
            self.px[self.ox + x, self.oy + y] = c + (255,) if len(c) == 3 else c

    def raw_rect(self, x0, y0, x1, y1, k=2):
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                self.raw_dot(x, y, shade(max(0, k - 1) if x == x1 and x1 > x0 else k))

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
# body turns: it narrows, the near side of the torso shows as a darker
# strip, the near arm is in full view and the far arm mostly hides.
#
# Facing south-east, the character's right side faces south-west, so the
# near side and near arm are on the image's left; facing north-east they're
# on the image's right.

HEAD_TOP, HEAD_BOTTOM = 4, 13
EYE_Y = 9
NECK_Y = 14
TORSO_TOP, TORSO_BOTTOM = 15, 21
HAND_Y = 21
LEG_TOP, LEG_BOTTOM = 22, 27
# Head outline per row (others span 11..20).
HEAD_ROWS = {4: (13, 18), 5: (12, 19), 12: (12, 19), 13: (13, 18)}

GEOM = {
    S: dict(torso=(12, 19), side=None, arms=[(10, 11), (20, 21)], legs=[(12, 14), (17, 19)], head=0),
    SE: dict(torso=(12, 19), side=(12, 13), arms=[(10, 11), (20, 20)], legs=[(12, 14), (16, 18)], head=1),
    E: dict(torso=(13, 19), side=None, arms=[(15, 17)], legs=None, head=1),
    NE: dict(torso=(12, 19), side=(18, 19), arms=[(11, 11), (20, 21)], legs=[(13, 15), (17, 19)], head=1),
    N: dict(torso=(12, 19), side=None, arms=[(10, 11), (20, 21)], legs=[(12, 14), (17, 19)], head=0),
}


def head_span(y, shift=0):
    lo, hi = HEAD_ROWS.get(y, (11, 20))
    return lo + shift, hi + shift


def head_shift(direction):
    return GEOM[direction]["head"]


def torso(direction):
    return GEOM[direction]["torso"]


def legs(direction, frame):
    """(x0, x1, bottom_y, far) per leg, drawn back to front. Legs start at
    LEG_TOP - lift so they stay joined to the lifted body."""
    moving, step = stage(frame)
    if direction == E:
        if step is None:
            return [(14, 18, LEG_BOTTOM, False)]
        far_moves = moving == 1  # A: near leg moves; B: far leg
        if step == UP:
            stride, plant = (16, 18, LEG_BOTTOM - 1), (13, 15, LEG_BOTTOM)
        elif step == CONTACT:
            stride, plant = (17, 20, LEG_BOTTOM), (11, 13, LEG_BOTTOM)
        else:
            stride, plant = (15, 17, LEG_BOTTOM), (12, 14, LEG_BOTTOM - 1)
        moving_leg = stride + (far_moves,)
        other = plant + (not far_moves,)
        return sorted([moving_leg, other], key=lambda leg: not leg[3])  # far first

    pair = [list(GEOM[direction]["legs"][0]) + [LEG_BOTTOM], list(GEOM[direction]["legs"][1]) + [LEG_BOTTOM]]
    if step is not None:
        other = 1 - moving
        if step == UP:
            pair[moving][2] -= 1
        elif step == CONTACT:
            # The foot nearer the camera sits lower and wider, the farther one
            # higher and narrower. Facing away, the stepping foot is the far one.
            near, far = (other, moving) if direction in (N, NE) else (moving, other)
            pair[near][2] += 1
            pair[far][2] -= 1
            outward = -1 if near == 0 else 1
            if outward < 0:
                pair[near][0] -= 1
            else:
                pair[near][1] += 1
            if far == 0:
                pair[far][0] += 1
            else:
                pair[far][1] -= 1
        else:
            pair[other][2] -= 1
    # Diagonals: the leading side sits a pixel higher (image-right facing
    # south-east, image-left facing north-east).
    if direction == SE:
        pair[1][2] -= 1
    elif direction == NE:
        pair[0][2] -= 1
    return [(l[0], l[1], l[2], False) for l in pair]


def arms(direction, frame):
    """(x0, x1, top_y, wrist_y, far) per visible arm; the hand is below the wrist.
    Arms swing against the legs, farthest apart at contact."""
    moving, step = stage(frame)
    if direction == E:
        x0 = 15
        if step == CONTACT:
            x0 = 13 if moving == 0 else 17
        return [(x0, x0 + 2, TORSO_TOP, HAND_Y - 1, False)]
    out = []
    for i, (a0, a1) in enumerate(GEOM[direction]["arms"]):
        far = a1 == a0 and direction in (SE, NE)
        wrist = HAND_Y - 1
        if step == CONTACT and not far:
            # The arm opposite the stepping leg swings forward: lower facing
            # us, higher facing away.
            forward = i != moving
            toward_camera = direction in (S, SE)
            wrist += 1 if forward == toward_camera else -1
        if (direction == SE and i == 1) or (direction == NE and i == 0):
            wrist -= 1
        out.append((a0, a1, TORSO_TOP + (1 if far else 0), wrist - (1 if far else 0), far))
    return out


def side_strip(f, d, top, bottom):
    """Darkens the near side of the torso in three-quarter views."""
    strip = GEOM[d]["side"]
    if strip:
        f.rect(strip[0], top, strip[1], bottom, 1, lit=False)


# --- Layers -------------------------------------------------------------------

def body(f, d, fr):
    hs = head_shift(d)
    for y in range(HEAD_TOP, HEAD_BOTTOM + 1):
        lo, hi = head_span(y, hs)
        for x in range(lo, hi + 1):
            k = 2
            if x == hi or y == HEAD_BOTTOM:
                k = 1
            elif x == lo or y == HEAD_TOP + 1:
                k = 3
            f.dot(x, y, shade(k))
    if d == E:
        f.dot(21, EYE_Y + 1, shade(2))  # nose
    elif d == SE:
        f.dot(21, EYE_Y + 2, shade(1))
    f.rect(15 + hs, NECK_Y, 16 + hs, NECK_Y, 1, lit=False)
    t0, t1 = torso(d)
    f.rect(t0, TORSO_TOP, t1, TORSO_BOTTOM)
    side_strip(f, d, TORSO_TOP, TORSO_BOTTOM)
    for a0, a1, top, wrist, far in arms(d, fr):
        f.rect(a0, top, a1, wrist + 1, 1 if far else 2, lit=not far)
    for l0, l1, bottom, far in legs(d, fr):
        f.raw_rect(l0, LEG_TOP - f.lift, l1, bottom, 1 if far else 2)


def eyes(f, d, fr):
    if d in (N, NE):
        return
    if d == E:
        f.dot(19, EYE_Y, shade(0))
        f.dot(19, EYE_Y + 1, shade(0))
        return
    xs = (15, 19) if d == SE else (13, 18)
    for x in xs:
        f.dot(x, EYE_Y, shade(0))
        f.dot(x, EYE_Y + 1, shade(0))


def _hair_cap(f, d, hs, bottom):
    """Hair from above the head down to bottom, with volume on top."""
    for y in range(HEAD_TOP - 2, bottom + 1):
        lo, hi = head_span(max(HEAD_TOP, y), hs)
        if y < HEAD_TOP:
            lo, hi = lo + 1, hi - 1
        else:
            lo, hi = lo - 1, hi + 1  # hair sits a pixel proud of the head
        for x in range(lo, hi + 1):
            f.dot(x, y, shade(3 if y == HEAD_TOP - 2 else (1 if x >= hi - 1 else 2)))


def hair_short(f, d, fr):
    hs = head_shift(d)
    if d in (N, NE):
        _hair_cap(f, d, hs, HEAD_BOTTOM - 1)
        if d == NE:
            # Cheek and ear show on the near side.
            for y in range(EYE_Y - 1, HEAD_BOTTOM):
                lo, hi = head_span(y, hs)
                for x in (hi, hi + 1):
                    f.dot(x, y, (0, 0, 0, 0))
        return
    _hair_cap(f, d, hs, EYE_Y - 2)
    lo, hi = head_span(EYE_Y - 1, hs)
    # Jagged fringe.
    for x in range(lo, hi + 1):
        if (x - lo) % 3 != 2:
            f.dot(x, EYE_Y - 1, shade(2))
    if d == E:
        for y in range(EYE_Y - 1, HEAD_BOTTOM):
            for x in range(10, 16):
                f.dot(x, y, shade(1 if x == 15 else 2))
    elif d == SE:
        lo = head_span(EYE_Y, hs)[0] - 1
        for y in range(EYE_Y - 1, HEAD_BOTTOM):
            for x in range(lo, lo + 3):
                f.dot(x, y, shade(1 if x == lo + 2 else 2))
    else:
        lo, hi = head_span(EYE_Y, hs)
        for y in range(EYE_Y - 1, EYE_Y + 3):
            f.dot(lo - 1, y, shade(2))
            f.dot(lo, y, shade(2))
            f.dot(hi, y, shade(1))
            f.dot(hi + 1, y, shade(1))


def hair_long(f, d, fr):
    hair_short(f, d, fr)
    hs = head_shift(d)
    end = TORSO_TOP + 3
    if d in (N, NE):
        # Tapers down the back, with a ragged hem.
        shift = 1 if d == NE else 0
        for y in range(HEAD_BOTTOM - 1, end + 1):
            inset = max(0, (y - HEAD_BOTTOM) // 2)
            lo, hi = 11 + shift + inset, 20 + shift - inset - (1 if d == NE else 0)
            for x in range(lo, hi + 1):
                if y == end and x % 2:
                    continue
                f.dot(x, y, shade(1 if x == hi else 2))
    elif d == E:
        f.rect(10, EYE_Y - 1, 15, end, 2)
    elif d == SE:
        f.rect(10, EYE_Y - 1, 13, end, 2)
        f.rect(22, EYE_Y, 22, end - 2, 1, lit=False)
    else:
        f.rect(9, EYE_Y - 1, 11, end, 2)
        f.rect(20, EYE_Y - 1, 22, end, 1, lit=False)


def hair_spiky(f, d, fr):
    hair_short(f, d, fr)
    hs = head_shift(d)
    for x in range(12 + hs, 21 + hs, 3):
        f.dot(x, HEAD_TOP - 3, shade(3))
        f.dot(x, HEAD_TOP - 4, shade(2))
        f.dot(x + 1, HEAD_TOP - 3, shade(2))


def hat_cap(f, d, fr):
    hs = head_shift(d)
    top, brim = HEAD_TOP - 3, HEAD_TOP + 2
    for y in range(top, brim):
        lo, hi = head_span(max(HEAD_TOP, y + 2), hs)
        lo, hi = lo - 1, hi + 1
        f.rect(lo, y, hi, y, 3 if y == top else 2, lit=False)
        f.dot(hi, y, shade(1))
    if d == S:
        f.fixed(14, top + 1, 17, top + 2, WHITE)
        f.rect(9, brim, 22, brim, 1, lit=False)
    elif d == SE:
        f.fixed(16, top + 1, 19, top + 2, WHITE)
        f.rect(12, brim, 24, brim, 1, lit=False)
    elif d == E:
        f.rect(17, brim, 24, brim, 1, lit=False)
    elif d == NE:
        f.rect(20, brim, 24, brim, 1, lit=False)
    else:
        f.rect(14, brim, 17, brim, 0, lit=False)


def hat_beanie(f, d, fr):
    hs = head_shift(d)
    for y in range(HEAD_TOP - 3, HEAD_TOP + 3):
        lo, hi = head_span(max(HEAD_TOP, y + 2), hs)
        lo, hi = lo - 1, hi + 1
        f.rect(lo, y, hi, y, 3 if y >= HEAD_TOP + 1 else 2, lit=False)
        f.dot(hi, y, shade(1))
    f.dot(15 + hs, HEAD_TOP - 4, shade(3))
    f.dot(16 + hs, HEAD_TOP - 4, shade(3))


def top_tee(f, d, fr, sleeve_rows=3):
    t0, t1 = torso(d)
    f.rect(t0, TORSO_TOP, t1, TORSO_BOTTOM)
    side_strip(f, d, TORSO_TOP, TORSO_BOTTOM)
    if d in (S, SE):
        mid = (t0 + t1) // 2 + (1 if d == SE else 0)
        f.dot(mid, TORSO_TOP, (0, 0, 0, 0))
        f.dot(mid + 1, TORSO_TOP, (0, 0, 0, 0))
    for a0, a1, top, wrist, far in arms(d, fr):
        f.rect(a0, top, a1, min(wrist, top + sleeve_rows - 1), 1 if far else 2, lit=not far)


def top_long(f, d, fr):
    top_tee(f, d, fr, sleeve_rows=10)


def top_jacket(f, d, fr):
    top_long(f, d, fr)
    if d in (S, SE):
        t0, t1 = torso(d)
        mid = (t0 + t1) // 2 + (1 if d == SE else 0)
        f.fixed(mid, TORSO_TOP, mid + 1, TORSO_BOTTOM, WHITE)
        f.dot(mid - 1, TORSO_TOP, shade(3))
        f.dot(mid + 2, TORSO_TOP, shade(3))


def bottom_pants(f, d, fr, leg_rows=None):
    t0, t1 = torso(d)
    f.rect(t0, TORSO_BOTTOM, t1, TORSO_BOTTOM, 1, lit=False)
    for l0, l1, bottom, far in legs(d, fr):
        end = bottom - 1 if leg_rows is None else min(bottom - 1, LEG_TOP + leg_rows - 1)
        f.raw_rect(l0, LEG_TOP - f.lift, l1, end, 1 if far else 2)


def bottom_shorts(f, d, fr):
    bottom_pants(f, d, fr, leg_rows=2)


def shoes(f, d, fr):
    for l0, l1, bottom, far in legs(d, fr):
        k = 0 if far else 1
        if d in (E, SE):
            f.raw_rect(l0, bottom, l1 + 1, bottom + 2, k)  # toes toward the facing
        elif d == NE:
            f.raw_rect(l0, bottom, l1, bottom + 2, k)
        else:
            f.raw_rect(l0 - (1 if l0 < 16 else 0), bottom, l1 + (1 if l0 >= 16 else 0), bottom + 2, k)


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
