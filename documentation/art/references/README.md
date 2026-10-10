# Art references

Reference images for hand-drawn sprite work. **Reference only:** sources and
licences are unknown, so use them for proportions, poses and timing, and
don't trace or copy pixels into game assets.

## walk-cycle-base-4dir-9frame.png

A bare body base, about 28 px tall, in four facings with a 9-frame walk each:

- Row 1: facing north (back view).
- Row 2: facing west (side, walking left).
- Row 3: facing south (front view, eyes visible).
- Row 4: facing east (side, walking right).
- Columns: a standing frame followed by an 8-frame walk cycle (the
  default / up / contact / passing structure, then the same with the other
  leg; see `../README.md`, "Animation rules").

Useful for: body proportions close to our 32×32 player frame, how the hips
and shoulders turn through the cycle in side views, and the head bob.
Shared by the project owner as a template to remember for later sprite
work.

## HGSS / BW overworld screenshots (not in the repo)

The project owner shared HGSS/DPPt overworld screenshots, a Black & White
3D overworld shot and an overhead forest map as style targets. They're
Nintendo's, so they're kept out of the repo; these are the takeaways:

- **Cliffs are warm brown earth ledges**, not grey stone, with a lighter
  lip along the top and rounded ends. Ledge lines follow the land's
  contours, stepping in terraces.
- **Stairs are cut into the cliff face** rather than built against it.
- **Trees have round, dense canopies** and pack into solid forest walls,
  with the edge trees outlining clearings and paths.
- **Paths are autotiled:** dirt and sand patches with soft rounded edges
  against the grass.
- Ponds and lakes are framed by ledges or rocks; wooden plank bridges and
  stepping stones cross them.
- Big tall-grass fields, flower patches, picket fences and lamp posts.
- BW: a distant mountain and cloud skybox behind the 3D world.

## Concept art direction (`documentation/concept/`)

The generated concept art (`harbour-town.png`, `locations-a.png`,
`locations-b.png` and the earlier images) is mood, not spec: it's far
denser and more painterly than 16 px tiles can be, and drawn isometric
rather than from our north-facing camera. Ideas worth taking from it:

- Towns on raised platforms with retaining walls and wide stone stairs.
- Rivers running through gorges with waterfalls down each terrace.
- Arched stone bridges and wooden docks; harbours on the coast.
- Terraced fields and vineyards following the slopes.
- Points of interest: ruins, roadside shrines, bandit camps, mountain
  passes, caves.

It disagrees with the HGSS screenshots on cliffs (grey stone versus brown
earth). The game currently uses brown earth; the cliff colours are four
constants at the top of `tools/make_tileset.py`, so mountains (or other
biomes) could switch to grey stone later.
