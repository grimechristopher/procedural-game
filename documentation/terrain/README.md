# Terrain shapes (back to basics)

The old tiled terrain (textured autotile pieces, banks, wedges, rounded
corners) is archived in `archive/terrain-v1/`. This is the restart: shapes
first, in plain colours, no textures.

## The one rule

Every cell is a whole number of blocks high.

- Ground a block below higher ground rises to meet it: the slope's top is
  right at the higher ground's edge, and it drops the block over 0.7 of a
  cell measured straight out from that edge, so its foot stops short of the
  far side of its own cell and leaves a strip of flat ground.
- Measured from a corner, that distance runs round in a curve, so outer
  corners are rounded.
- Along a 45-degree edge, the higher cells are cut along their diagonal and
  the slope runs straight out from the cut, as steep as a straight slope. At
  a V, where two such edges meet, the two cells at its tip are cut as mirror
  images.
- Anything taller than a block is a vertical wall.
- Neighbouring cells measure from the same edges, so pieces always meet.

## Colours

Grass green on flat ground only, brown on slopes, grey on vertical walls,
blue water. Faces are shaded by which way they face.

Code: `scripts/terrain_shapes.gd`. Demo: `sidecar/tools/basics.gd`.
