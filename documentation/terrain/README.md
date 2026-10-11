# Terrain shapes (back to basics)

The old tiled terrain (textured autotile pieces, banks, wedges, rounded
corners) is archived in `archive/terrain-v1/`. This is the restart: shapes
first, in plain colours, no textures.

## The one rule

Every cell is a whole number of blocks high. The ground's surface is set by
heights at the cells' corners, and neighbouring cells share their corners,
so pieces always fit together.

- A cell's corner rises one block if a cell touching that corner is
  exactly one block higher.
- So a one-block step slopes down across the cell at its foot: a straight
  slope along an edge, an outer corner where only the diagonal cell is
  higher, an inner corner where two sides are, and a straight diagonal
  slope along a 45-degree edge.
- A cell with one corner unlike the others is split through that corner (a
  hip on an outer corner, a valley on an inner one), except on a diagonal
  edge, where it's split along the edge so the slope runs straight.
- Anything taller than a block is a vertical wall.

## Colours

Grass green on flat ground only, brown on slopes, grey on vertical walls,
blue water. Faces are shaded by which way they face.

Code: `scripts/terrain_shapes.gd`. Demo: `sidecar/tools/basics.gd`.
