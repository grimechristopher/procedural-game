# Terrain rules

The rules the world generator (`scripts/world.gd`) and the terrain mesh
(`scripts/terrain_mesh.gd`) follow. Blocks are cubes; heights come in half
blocks.

## Shape

- **Half cliffs** (half a block) on gentle ground; **full cliffs** (one
  block) on cliffy ground, and wherever the ground is steep (climbing more
  than a quarter block per cell, measured over a few cells), so shelves
  between cliffs stay about two cells wide or more instead of coming in
  rows of one-cell strips. Steeper ground stacks its cliffs two or three
  high.
- **Faults**: in some regions the ground steps up two blocks along long
  straight escarpments running diagonally, in bands. Their walls are full
  height and vertical, cut diagonally all along (one long diagonal rock
  face).
- **The sea** round the map: a wandering shoreline, a strip of ground at
  sea level along it, and the land rising gently inland (no rows of
  terraces down to the water).
- Half cliffs give way beside full cliffs: gentle ground next to cliffy
  ground rounds to whole blocks, so no half-block shelves get squeezed
  between full cliffs.
- Full cliffs either **step back** one block at a time (terraces) or
  **stack** straight up into walls two or three blocks tall, as the noise
  decides.
- Full cliffs are either **sloped** (HGSS-style banks) or **vertical**,
  chosen per side. A slope is built of **bank bricks**: a bank sits in the
  cell at a cliff's foot, solid and not walkable, and the rock slopes down
  across it at 45 degrees. Taller walls slope as a staircase of banks, one
  cell per block, stepping out over the ground in front; their outside
  corners wrap round. Where there isn't room in front, the wall stays
  vertical.
- A bank's slope starts a little in from the cliff's edge, as in HGSS:
  the band along the top of the edge leans down into it (a soft lip), and
  the slope's top dips to meet it (diagonal slopes too).
- A bank boxed in on three sides by ground a block above it is filled up
  level with that ground (no flat patches of slope in notches).
- A bank's slope is set by the heights at its cell's corners: each corner
  is as high as the tallest block touching it that stands exactly a block
  above the bank's floor, else the floor. Straight, corner, inside-corner,
  stacked and diagonal slopes all meet without seams, and a slope's end is
  closed down to the ground beside it. A plateau corner between two
  slopes is cut diagonally (a wedge, whose cut-off corner doesn't count),
  so the slope runs on along the diagonal; within a tall slope's staircase
  too, at every level (not on natural terraces, whose shelves are walked).
  Only on a 45-degree run of such corners: a shallower edge stays stepped,
  its corners wrapped round, as HGSS draws it. Cuts the ground round them
  no longer fits (after joining) are squared off again.
- Which sides slope (as in HGSS): every step a block high slopes, where
  there's room for the bank in front. Taller walls stand vertical, unless a
  wall-style noise leans them into staircases of banks (like contour lines
  down a mountain side): on every side in some places, and on east and
  west sides only in more (vertical east/west walls are seen edge on by
  the camera and read as thin lines). Half cliffs and cliffs into water
  are always vertical.
- Plateaus' outside corners are cut **diagonally** (except where banks
  turn the corner themselves), and turned in a **slight curve** where they
  stay square.

## Ways up

- **No stairs in the wild.** Stairs are for man-made places, and never on
  roads where carts go.
- **Ramps climb half a block per cell**: a half cliff in one cell, a full
  cliff over two. Nothing climbs a whole block in one cell.
- Taller walls are climbed by a **corridor** of ramps cut back into the
  plateau, or a ramp **carved** into the cliff top where there's no room at
  its foot. A ramp can take the place of a bank, and a slope of several
  banks is climbed by a ramp laid down through it and on over its foot.
- Every bit of land should be reachable; pockets that can't be joined are
  levelled to the reachable flat ground beside them nearest their height
  (up to 30 cells, or 60 once nothing else will join), so a small knob
  boxed in by tall walls comes down.
- Banks the connector took away to climb a cliff go back afterwards
  wherever nothing came of it (no ramp took their place and nothing
  reached gets cut off), so slopes don't end on stray vertical steps.
- Joins go gentlest first: a ramp or clearing, then a corridor or a ramp
  laid down through a slope (which may end in a step), then carving into
  a cliff top, and only last taking a bank away. A clearing (a tree, a
  rock, or a diagonal cut put back to a square block) only counts if it
  really opens a way through.
- Pockets are joined the gentlest way first (a ramp or clearing before a
  corridor), and each one joined counts as reachable straight away, so the
  pockets beside it join it instead of each cutting its own way in.
- No ramp is laid within two cells to either side of another, so ramps
  don't line up side by side like a comb.
- Corridors never run alongside or across another ramp, and keep plateau
  two cells deep either side (one where that's all there is), so they
  don't leave thin walls standing.
- Before joining, one-cell fins and slots are smoothed to the ground
  either side (away from ramps).

## Edges (autotiling)

Each cell's top is drawn a quarter at a time, picking a piece the way a 2D
tileset's cliff set does:

1. A side of a cell is an **edge** where the ground beside it is lower
   (or water).
   - A ramp climbing that side hides it: no edge.
   - A ramp's own sides are edges wherever the ground beside it is lower
     than the ramp's top, unless a matching ramp runs alongside (one wide
     ramp). Its low end is an edge only where the ground in front drops
     below it, and not where the lower half of the same ramp leads into
     it. Its high end never is.
2. A quarter with **both** its sides on edges is an **outer corner**; with
   **one**, an **edge**. An outer corner is a **T-junction** instead if the
   cliff along one of its sides carries on past the corner, one level
   lower, along the neighbour on the other side (three heights meeting):
   square, the side's band running into the continuing band, not a
   free-standing rounded corner.
3. With **neither**, it's an **inner corner** if the diagonal drops away
   and both sides are level with the cell. A ramp leading up onto the
   cell counts as level, and a side that's higher rules it out. A ramp on
   the diagonal counts at its top, so a wide ramp beside the cell doesn't
   make inner corners along it; nor does a ramp cell get them. If a
   diagonal cliff ends at that corner, it's a **joint** instead, carrying
   the diagonal's band through.
4. Otherwise it's plain ground.

High ground (five blocks up and more) is bare rock: its pieces are the
rock versions, with no grass in them (ramps too, without contour lines),
and slopes topping out there are rough boulders rather than ribs.

Ramps take part like any other cell, their pieces draped over the slope,
with contour lines across the climb so the slope reads as one. Where the
ground beside a ramp is level with its foot, the side's band narrows to
nothing there, as the face under it does.
Faces hang below every edge: vertical, a bank across the cell in front, or
cut to a ramp's slope.

## Not drawn

- **No cast shadows.** Shadows will come from a day-night lighting system.
  Faces only get fixed brightness by direction and steepness.
