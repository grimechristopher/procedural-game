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
