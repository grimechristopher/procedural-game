class_name Buildings

## Low-poly buildings, built from faces textured with the pixel tileset (see
## GridWorld._build_mesh): stone foundations, timber-and-plaster or stone
## walls, gable roofs with overhangs, chimneys, and doors and windows as
## panels on the front.
##
## Each builder returns { name, size, door, faces }. Coordinates are local
## to the building's footprint: x 0..size.x, z 0..size.y, ground at y 0. The
## front faces south (+z), toward the fixed camera. door is the footprint
## column the door is in, along the front row.

const T := GridWorld.Tex
const FRONT := Vector3.BACK


static func house() -> Dictionary:
	var faces := []
	faces += block(Vector3(0, 0, 0), Vector3(4, 0.35, 3), T.FIELDSTONE, T.FIELDSTONE)
	faces += block(Vector3(0.05, 0.35, 0.05), Vector3(3.95, 2.0, 2.95), T.PLASTER)
	faces += gable_roof(0.05, 0.05, 3.95, 2.95, 2.0, 3.3, 0.35, T.THATCH, T.PLASTER)
	faces += block(Vector3(3.0, 2.0, 0.6), Vector3(3.5, 3.9, 1.1), T.FIELDSTONE, T.FIELDSTONE)
	faces += door(1.1, 0.35, 2.95)
	faces.append(panel(2.5, 3.3, 0.9, 1.6, 2.95, T.WINDOW))
	faces.append(panel(0.25, 0.85, 0.9, 1.6, 2.95, T.WINDOW))
	return { name = "House", size = Vector2i(4, 3), door = 1, faces = faces }


static func blacksmith() -> Dictionary:
	var faces := []
	# Stone workshop on the left...
	faces += block(Vector3(0, 0, 0), Vector3(3, 0.25, 3), T.FIELDSTONE, T.FIELDSTONE)
	faces += block(Vector3(0.05, 0.25, 0.05), Vector3(2.95, 1.9, 2.95), T.FIELDSTONE)
	faces += gable_roof(0.05, 0.05, 2.95, 2.95, 1.9, 3.0, 0.3, T.SHINGLE, T.FIELDSTONE)
	faces += door(1.1, 0.25, 2.95)
	faces.append(panel(2.1, 2.75, 0.8, 1.45, 2.95, T.WINDOW))
	# ...and an open forge shed on the right: back wall, corner post, lean-to roof.
	faces += block(Vector3(2.95, 0, 0.05), Vector3(5, 1.9, 0.35), T.FIELDSTONE, T.FIELDSTONE)
	faces += block(Vector3(4.75, 0, 2.7), Vector3(4.95, 1.75, 2.9), T.PLANKS, T.PLANKS)
	faces.append(slope([Vector3(2.95, 2.1, -0.2), Vector3(5.25, 2.1, -0.2),
		Vector3(5.25, 1.6, 3.25), Vector3(2.95, 1.6, 3.25)], T.SHINGLE))
	# Forge with glowing coals and its chimney, and an anvil on a stump.
	faces += block(Vector3(3.3, 0, 0.45), Vector3(4.4, 0.8, 1.45), T.FIELDSTONE, T.EMBERS)
	faces += block(Vector3(3.6, 0.8, 0.5), Vector3(4.1, 3.0, 0.95), T.FIELDSTONE, T.FIELDSTONE)
	faces += block(Vector3(4.1, 0, 1.9), Vector3(4.5, 0.45, 2.3), T.PLANKS, T.PLANKS)
	faces += block(Vector3(3.95, 0.45, 1.97), Vector3(4.7, 0.65, 2.23), T.STONE, T.STONE)
	return { name = "Blacksmith", size = Vector2i(5, 3), door = 1, faces = faces }


static func inn() -> Dictionary:
	var faces := []
	faces += block(Vector3(0, 0, 0), Vector3(6, 0.3, 4), T.FIELDSTONE, T.FIELDSTONE)
	# Stone ground floor under a plastered upper floor that juts out a little.
	faces += block(Vector3(0.05, 0.3, 0.05), Vector3(5.95, 1.7, 3.95), T.FIELDSTONE)
	faces += block(Vector3(-0.05, 1.7, -0.05), Vector3(6.05, 3.3, 4.05), T.PLASTER)
	faces += gable_roof(-0.05, -0.05, 6.05, 4.05, 3.3, 4.9, 0.35, T.SHINGLE, T.PLASTER)
	faces += block(Vector3(0.6, 3.3, 1.0), Vector3(1.1, 5.6, 1.5), T.FIELDSTONE, T.FIELDSTONE)
	faces += door(3.1, 0.3, 3.95)
	faces.append(panel(1.1, 1.9, 0.7, 1.4, 3.95, T.WINDOW))
	faces.append(panel(4.6, 5.4, 0.7, 1.4, 3.95, T.WINDOW))
	for x in [0.5, 2.0, 3.6, 5.0]:
		faces.append(panel(x, x + 0.7, 2.2, 2.9, 4.05, T.WINDOW))
	# Hanging sign on an arm off the east wall.
	faces += block(Vector3(6.05, 2.15, 3.8), Vector3(6.75, 2.25, 3.9), T.PLANKS, T.PLANKS)
	faces += block(Vector3(6.25, 1.5, 3.82), Vector3(6.85, 2.1, 3.88), T.PLANKS, T.PLANKS)
	return { name = "Inn", size = Vector2i(6, 4), door = 3, faces = faces }


# --- Pieces -------------------------------------------------------------------

## A box's sides (and top, if given a tile). Wall tiles line up with the
## world grid and hang from the top edge, so timber beams sit at the eaves.
static func block(lo: Vector3, hi: Vector3, side: int, top := -1) -> Array:
	var faces := [
		face([Vector3(lo.x, lo.y, hi.z), Vector3(hi.x, lo.y, hi.z), Vector3(hi.x, hi.y, hi.z), Vector3(lo.x, hi.y, hi.z)], Vector3.BACK, side, hi.y),
		face([Vector3(lo.x, lo.y, lo.z), Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(lo.x, hi.y, lo.z)], Vector3.FORWARD, side, hi.y),
		face([Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, lo.y, hi.z), Vector3(hi.x, hi.y, hi.z), Vector3(hi.x, hi.y, lo.z)], Vector3.RIGHT, side, hi.y),
		face([Vector3(lo.x, lo.y, lo.z), Vector3(lo.x, lo.y, hi.z), Vector3(lo.x, hi.y, hi.z), Vector3(lo.x, hi.y, lo.z)], Vector3.LEFT, side, hi.y),
	]
	if top >= 0:
		faces.append(face([Vector3(lo.x, hi.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(hi.x, hi.y, hi.z), Vector3(lo.x, hi.y, hi.z)], Vector3.UP, top, hi.y))
	return faces


## A roof whose ridge runs east-west over the middle of the rect, sloping
## down to eaves at eave_y and overhanging the walls, plus the triangular
## gable walls at either end.
static func gable_roof(x0: float, z0: float, x1: float, z1: float, eave_y: float, ridge_y: float,
		overhang: float, roof: int, gable: int) -> Array:
	var zc := (z0 + z1) / 2.0
	var run := (z1 - z0) / 2.0
	var drop := overhang * (ridge_y - eave_y) / run
	var low := eave_y - drop
	return [
		slope([Vector3(x0 - overhang, ridge_y, zc), Vector3(x1 + overhang, ridge_y, zc),
			Vector3(x1 + overhang, low, z1 + overhang), Vector3(x0 - overhang, low, z1 + overhang)], roof),
		slope([Vector3(x0 - overhang, ridge_y, zc), Vector3(x1 + overhang, ridge_y, zc),
			Vector3(x1 + overhang, low, z0 - overhang), Vector3(x0 - overhang, low, z0 - overhang)], roof),
		face([Vector3(x0, eave_y, z0), Vector3(x0, eave_y, z1), Vector3(x0, ridge_y, zc)], Vector3.LEFT, gable, ridge_y),
		face([Vector3(x1, eave_y, z0), Vector3(x1, eave_y, z1), Vector3(x1, ridge_y, zc)], Vector3.RIGHT, gable, ridge_y),
	]


## A sloped quad, given top edge first; tiles run down the slope from it.
static func slope(pts: Array, tex: int) -> Array:
	var n: Vector3 = (pts[1] - pts[0]).cross(pts[2] - pts[0]).normalized()
	if n.y < 0.0:
		n = -n
	return face(pts, n, tex, pts[0].y)


## A two-tile door (bottom and top halves) on a south-facing wall at z.
static func door(x0: float, y0: float, z: float) -> Array:
	return [panel(x0, x0 + 0.8, y0, y0 + 0.8, z, T.DOOR_BOTTOM),
		panel(x0, x0 + 0.8, y0 + 0.8, y0 + 1.6, z, T.DOOR_TOP)]


## One whole tile stretched over a rect on a south-facing wall at z, set a
## hair proud of the wall.
static func panel(x0: float, x1: float, y0: float, y1: float, z: float, tex: int) -> Array:
	z += 0.02
	return [[Vector3(x0, y0, z), Vector3(x1, y0, z), Vector3(x1, y1, z), Vector3(x0, y1, z)], FRONT, tex,
		[Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]]


## A face with tile-space UVs: across in world units along the face, and
## down from v_top (walls: from the top edge; slopes: from the ridge).
static func face(pts: Array, n: Vector3, tex: int, v_top: float) -> Array:
	var across := Vector3.UP.cross(n)
	if across.length() < 0.01:
		across = Vector3.RIGHT
	across = across.normalized()
	var down := across.cross(n).normalized()
	var origin := Vector3(0, v_top, 0)
	if absf(n.y) > 0.1 and absf(n.y) < 0.99:
		# Slopes: measure from the top edge along the slope.
		origin = pts[0]
	var uvs := []
	for p in pts:
		uvs.append(Vector2(p.dot(across), (p - origin).dot(down)))
	return [pts, n, tex, uvs]
