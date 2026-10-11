# Terrain rules

The rules the world generator (`scripts/world.gd`) and the terrain mesh
(`scripts/terrain_mesh.gd`) follow. Blocks are cubes; heights come in half
blocks.

## Shape

- **Half cliffs** (half a block) on gentle ground; **full cliffs** (one
  block) on cliffy ground.
- Full cliffs either **step back** one block at a time (terraces) or
  **stack** straight up into walls two or three blocks tall, as the noise
  decides.
- Terraced full cliffs are **HGSS-style banks**: the face slopes down
  across the whole cell at the cliff's foot, which can't be walked on.
  Stacked walls, half cliffs and cliffs into water are **vertical**.
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
  its foot. A ramp can take the place of a bank.
- Every bit of land should be reachable; pockets that can't be joined are
  levelled into the ground beside them (up to 30 cells).

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
   cell counts as level, and a side that's higher rules it out. If a
   diagonal cliff ends at that corner, it's a **joint** instead, carrying
   the diagonal's band through.
4. Otherwise it's plain ground.

Ramps take part like any other cell, their pieces draped over the slope.
Faces hang below every edge: vertical, a bank across the cell in front, or
cut to a ramp's slope.

## Not drawn

- **No cast shadows.** Shadows will come from a day-night lighting system.
  Faces only get fixed brightness by direction and steepness.
