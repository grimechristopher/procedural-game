class_name TerrainShapes
extends RefCounted

## The terrain's shapes, back to basics: plain colours, no textures, so the
## shapes can be got right first.
##
## Every cell is a whole number of blocks high. One rule makes every slope:
##
##   Ground a block below higher ground rises to meet it, starting right at
##   the higher ground's edge and dropping the block over SLOPE_RUN cells
##   (measured straight out from that edge); beyond that it's flat.
##
## So a slope's top is at the edge of the cell above, and its foot stops
## short of the far side of its own cell, leaving a strip of flat ground.
## Measured from a corner, the distance runs round in a curve, so outer
## corners come out rounded. Along a 45-degree edge the higher cells are cut
## along their diagonal and the slope runs straight from the cut. Anything
## taller than a block is a vertical wall. Neighbouring cells measure from the
## same edges, so the pieces always meet. Grass only on flat ground.

## Tiles the generator still keeps in the GridMap for movement, left undrawn
## there because this draws the ground.
const HIDDEN := [
	GridWorld.Tile.FULL, GridWorld.Tile.FULL_DIRT, GridWorld.Tile.ROCK, GridWorld.Tile.HALF,
	GridWorld.Tile.WEDGE, GridWorld.Tile.WEDGE_DIRT, GridWorld.Tile.HALF_WEDGE, GridWorld.Tile.UPPER_HALF_WEDGE,
	GridWorld.Tile.HILL_RAMP, GridWorld.Tile.HALF_HILL_RAMP, GridWorld.Tile.UPPER_HALF_HILL_RAMP,
]

## How far (in cells) a slope runs out from the edge of the ground above it
## while it drops a block. Under 1, so it ends short of the cell's far side
## (and under half a diagonal, so diagonal slopes fit too).
const SLOPE_RUN := 0.7
## Pieces each sloping cell is split into each way.
const STEPS := 7

const GRASS := Color(0.45, 0.66, 0.30)
const SLOPE := Color(0.62, 0.43, 0.26)
const WALL := Color(0.55, 0.52, 0.48)
const WATER := Color(0.25, 0.45, 0.80)
## Where the water's surface sits, and the floor under it, in blocks.
const WATER_LEVEL := -0.25
const RIVER_BED := -1.0

const ORTHO := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
const DIAG := [Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]

var size: Vector2i
var heights: PackedInt32Array  # blocks; -1 is water
## Per cell: the diagonal toward its cut-off corner (ZERO if not cut).
var cuts: Array[Vector2i] = []
var verts := PackedVector3Array()
var colors := PackedColorArray()


## A mesh of the ground for heights in blocks (-1 for water), one per cell.
static func build(heights_blocks: PackedInt32Array, map_size: Vector2i) -> MeshInstance3D:
	var t := TerrainShapes.new()
	t.size = map_size
	t.heights = heights_blocks
	t._run()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = t.verts
	arrays[Mesh.ARRAY_COLOR] = t.colors
	var mesh := ArrayMesh.new()
	if not t.verts.is_empty():
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var node := MeshInstance3D.new()
	node.name = "TerrainShapes"
	node.mesh = mesh
	node.material_override = mat
	return node


func height(c: Vector2i) -> int:
	if c.x < 0 or c.y < 0 or c.x >= size.x or c.y >= size.y:
		return -99
	return heights[c.y * size.x + c.x]


func _run() -> void:
	cuts.resize(size.x * size.y)
	for z in size.y:
		for x in size.x:
			cuts[z * size.x + x] = _cut(Vector2i(x, z))
	for z in size.y:
		for x in size.x:
			var c := Vector2i(x, z)
			if height(c) < 0:
				_water(c)
				continue
			for r in _regions(c):
				_surface(r.poly, r.base)
			_walls(c)


# --- Shapes ------------------------------------------------------------------

## Whether c is on a 45-degree edge of higher ground: the two sides toward a
## corner are lower (and the diagonal no higher), the ground behind is as
## high, and the next cell along the edge is cut the same way. Returns the
## diagonal toward the cut-off corner, or ZERO.
func _cut(c: Vector2i) -> Vector2i:
	var h := height(c)
	if h < 0:
		return Vector2i.ZERO
	for s: Vector2i in DIAG:
		if not _cut_pattern(c, s) and not _v_pattern(c, s):
			continue
		for along: Vector2i in [Vector2i(s.x, -s.y), Vector2i(-s.x, s.y)]:
			if _cut_pattern(c + along, s):
				return s
	return Vector2i.ZERO


## The tip of a V, where two diagonal edges meet pointing into the higher
## ground: one side toward s is lower (with the diagonal), the other is the
## mirror-image cell at the tip (as high), and the ground behind is as high.
func _v_pattern(c: Vector2i, s: Vector2i) -> bool:
	var h := height(c)
	if h < 0:
		return false
	for side in [[Vector2i(s.x, 0), Vector2i(0, s.y)], [Vector2i(0, s.y), Vector2i(s.x, 0)]]:
		var low_side: Vector2i = side[0]
		var twin_side: Vector2i = side[1]
		var low := height(c + low_side)
		if low < 0 or low >= h or height(c + twin_side) != h:
			continue
		var d := height(c + s)
		if d < 0 or d > low:
			continue
		if height(c - low_side) >= h and height(c - twin_side) >= h:
			return true
	return false


func _cut_pattern(c: Vector2i, s: Vector2i) -> bool:
	var h := height(c)
	var low := height(c + Vector2i(s.x, 0))
	if h < 0 or low < 0 or low >= h or height(c + Vector2i(0, s.y)) != low:
		return false
	var d := height(c + s)
	if d < 0 or d > low:
		return false
	return height(c - Vector2i(s.x, 0)) >= h and height(c - Vector2i(0, s.y)) >= h


## The cell's corner points, NW, NE, SE, SW.
static func _square(c: Vector2i) -> Array:
	return [Vector2(c.x, c.y), Vector2(c.x + 1, c.y), Vector2(c.x + 1, c.y + 1), Vector2(c.x, c.y + 1)]


## The parts of cell c with their ground level: the whole cell, or for a
## cut cell its solid triangle and, at the lower ground's level, the cut-off
## triangle.
func _regions(c: Vector2i) -> Array:
	var s := cuts[c.y * size.x + c.x]
	if s == Vector2i.ZERO:
		return [{ poly = _square(c), base = height(c) }]
	var tri := _cut_triangles(c, s)
	# (The lower of the two sides toward the cut: at a V's tip one of them
	# is the other cell at the tip, as high as this one.)
	var low := mini(height(c + Vector2i(s.x, 0)), height(c + Vector2i(0, s.y)))
	return [{ poly = tri[0], base = height(c) }, { poly = tri[1], base = low }]


## [solid triangle, cut-off triangle] of cell c cut toward diagonal s.
static func _cut_triangles(c: Vector2i, s: Vector2i) -> Array:
	var o := Vector2(c)
	var far := o + Vector2((1 + s.x) / 2, (1 + s.y) / 2)
	var near := o + Vector2((1 - s.x) / 2, (1 - s.y) / 2)
	var a := o + Vector2((1 + s.x) / 2, (1 - s.y) / 2)
	var b := o + Vector2((1 - s.x) / 2, (1 + s.y) / 2)
	return [[near, a, b], [far, b, a]]


## The solid ground near c (its 3x3 neighbourhood): each cell's solid part
## and its level, for slopes to measure from.
func _solids_near(c: Vector2i) -> Array:
	var out := []
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var n := c + Vector2i(dx, dz)
			if height(n) < 0:
				continue
			var s := cuts[n.y * size.x + n.x]
			out.append({ poly = _square(n) if s == Vector2i.ZERO else _cut_triangles(n, s)[0], level = height(n) })
	return out


## The ground's height at p, in ground whose own level is base: a block
## higher right at the edge of solid ground a block up, falling to base
## SLOPE_RUN out from it.
func ground_at(p: Vector2, base: int, solids: Array) -> float:
	var rise := 0.0
	for a in solids:
		if a.level != base + 1:
			continue
		var d := _distance(p, a.poly)
		if d < SLOPE_RUN:
			rise = maxf(rise, 1.0 - d / SLOPE_RUN)
	return base + rise


## Distance from p to a convex polygon (0 inside).
static func _distance(p: Vector2, poly: Array) -> float:
	var inside := true
	var best := INF
	var n := poly.size()
	var sign := 0.0
	for i in n:
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[(i + 1) % n]
		var cr := (b - a).cross(p - a)
		if absf(cr) > 0.00001:
			if sign == 0.0:
				sign = signf(cr)
			elif signf(cr) != sign:
				inside = false
		var t := clampf((p - a).dot(b - a) / (b - a).length_squared(), 0.0, 1.0)
		best = minf(best, p.distance_to(a + (b - a) * t))
	return 0.0 if inside else best


# --- Drawing -------------------------------------------------------------------

## Ground over a region (a square or triangle) at level base: flat in one
## piece where nothing a block up is near, else split into small pieces
## following the slopes.
func _surface(poly: Array, base: int) -> void:
	var c := Vector2i(floori((poly[0].x + poly[1].x + poly[2].x) / 3.0), floori((poly[0].y + poly[1].y + poly[2].y) / 3.0))
	var solids := _solids_near(c)
	var near_higher := false
	for a in solids:
		if a.level == base + 1 and _poly_distance(poly, a.poly) < SLOPE_RUN:
			near_higher = true
	if not near_higher:
		for i in range(1, poly.size() - 1):
			_ground_tri(_at(poly[0], base), _at(poly[i], base), _at(poly[i + 1], base))
		return
	if poly.size() == 4:
		for j in STEPS:
			for i in STEPS:
				var p00: Vector2 = _lerp4(poly, float(i) / STEPS, float(j) / STEPS)
				var p10: Vector2 = _lerp4(poly, float(i + 1) / STEPS, float(j) / STEPS)
				var p11: Vector2 = _lerp4(poly, float(i + 1) / STEPS, float(j + 1) / STEPS)
				var p01: Vector2 = _lerp4(poly, float(i) / STEPS, float(j + 1) / STEPS)
				var q := [p00, p10, p11, p01].map(func(p): return Vector3(p.x, ground_at(p, base, solids), p.y))
				# Fold along whichever diagonal follows the slope's level
				# lines (its ends nearer the same height), so a diagonal
				# slope's foot doesn't come out jagged.
				if absf(q[0].y - q[2].y) <= absf(q[1].y - q[3].y):
					_ground_tri(q[0], q[1], q[2])
					_ground_tri(q[0], q[2], q[3])
				else:
					_ground_tri(q[0], q[1], q[3])
					_ground_tri(q[1], q[2], q[3])
	else:
		# A triangle split into STEPS rows of small triangles.
		var a: Vector2 = poly[0]
		var b: Vector2 = poly[1]
		var cc: Vector2 = poly[2]
		var pt := func(i: int, j: int) -> Vector3:
			var p: Vector2 = a + (b - a) * (float(i) / STEPS) + (cc - a) * (float(j) / STEPS)
			return Vector3(p.x, ground_at(p, base, solids), p.y)
		for j in STEPS:
			for i in STEPS - j:
				_ground_tri(pt.call(i, j), pt.call(i + 1, j), pt.call(i, j + 1))
				if i + j + 1 < STEPS:
					_ground_tri(pt.call(i + 1, j), pt.call(i + 1, j + 1), pt.call(i, j + 1))


static func _lerp4(poly: Array, u: float, v: float) -> Vector2:
	var top: Vector2 = poly[0].lerp(poly[1], u)
	var bottom: Vector2 = poly[3].lerp(poly[2], u)
	return top.lerp(bottom, v)


static func _poly_distance(a: Array, b: Array) -> float:
	var best := INF
	for p in a:
		best = minf(best, _distance(p, b))
	for p in b:
		best = minf(best, _distance(p, a))
	return best


## Vertical walls round cell c, wherever its ground stands above the ground
## next to it (a cell more than a block lower, the river, or across a cut).
func _walls(c: Vector2i) -> void:
	var regions := _regions(c)
	var solids := _solids_near(c)
	# Each region's edges: the other side is the neighbouring cell's region
	# there, or (across a cut) this cell's other region.
	for ri in regions.size():
		var r: Dictionary = regions[ri]
		var poly: Array = r.poly
		for e in poly.size():
			var a: Vector2 = poly[e]
			var b: Vector2 = poly[(e + 1) % poly.size()]
			var mid := (a + b) / 2.0
			var out := Vector2(b - a).orthogonal().normalized()
			# (orthogonal() is a quarter turn; make it point away from the region.)
			var centroid := Vector2.ZERO
			for p in poly:
				centroid += p
			centroid /= poly.size()
			if out.dot(mid - centroid) < 0.0:
				out = -out
			var probe := mid + out * 0.01
			var other_base := -99
			var other_solids := solids
			var n := Vector2i(floori(probe.x), floori(probe.y))
			var hn := height(n)
			if hn == -99:
				continue  # the map's edge
			if hn < 0:
				other_base = -99
			else:
				for o in _regions(n):
					if _distance(probe, o.poly) < 0.001:
						other_base = o.base
				other_solids = _solids_near(n)
			var pts := []
			for k in STEPS + 1:
				var p: Vector2 = a.lerp(b, float(k) / STEPS)
				var top := ground_at(p, r.base, solids)
				var low := RIVER_BED if other_base == -99 else ground_at(p, other_base, other_solids)
				pts.append([p, top, low])
			for k in STEPS:
				var p0: Array = pts[k]
				var p1: Array = pts[k + 1]
				if p0[1] <= p0[2] + 0.001 and p1[1] <= p1[2] + 0.001:
					continue
				var n3 := Vector3(out.x, 0, out.y)
				_add(_at(p0[0], p0[1]), _at(p1[0], p1[1]), _at(p1[0], minf(p1[2], p1[1])), _shade(WALL, n3))
				_add(_at(p0[0], p0[1]), _at(p1[0], minf(p1[2], p1[1])), _at(p0[0], minf(p0[2], p0[1])), _shade(WALL, n3))


func _water(c: Vector2i) -> void:
	var p := _square(c)
	_add(_at(p[0], WATER_LEVEL), _at(p[1], WATER_LEVEL), _at(p[2], WATER_LEVEL), WATER)
	_add(_at(p[0], WATER_LEVEL), _at(p[2], WATER_LEVEL), _at(p[3], WATER_LEVEL), WATER)


static func _at(p: Vector2, y: float) -> Vector3:
	return Vector3(p.x, y, p.y)


## A ground triangle: grass if it's flat, slope colour if not, shaded by
## which way it faces.
func _ground_tri(a: Vector3, b: Vector3, c: Vector3) -> void:
	var flat := absf(a.y - b.y) < 0.001 and absf(b.y - c.y) < 0.001
	var col := GRASS if flat else SLOPE
	var n := (b - a).cross(c - a)
	if n.y < 0.0:
		n = -n
	_add(a, b, c, _shade(col, n))


## Brighter facing up and toward the camera (south), darker facing away.
func _shade(col: Color, n: Vector3) -> Color:
	if n.length() < 0.0001:
		return col
	var light := Vector3(-0.35, 1.0, 0.55).normalized()
	var k := 0.55 + 0.45 * maxf(n.normalized().dot(light), 0.0)
	return Color(col.r * k, col.g * k, col.b * k)


func _add(a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
	verts.append_array([a, b, c])
	colors.append_array([col, col, col])
