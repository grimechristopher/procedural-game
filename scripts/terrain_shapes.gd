class_name TerrainShapes
extends RefCounted

## The terrain's shapes, back to basics: plain colours, no textures, so the
## shapes can be got right first.
##
## Every cell is a whole number of blocks high. The ground's surface is set
## by heights at the cells' corners, which neighbouring cells share, so the
## pieces always fit together. One rule makes every shape:
##
##   A cell's corner rises one block if a cell touching that corner is
##   exactly one block higher.
##
## So a one-block step slopes down across the cell at its foot: straight
## along an edge, an outer corner where only the diagonal cell is higher, an
## inner corner where two sides are. Anything taller than a block is a
## vertical wall. Grass only on flat ground.

## Tiles the generator still keeps in the GridMap for movement, left undrawn
## there because this draws the ground.
const HIDDEN := [
	GridWorld.Tile.FULL, GridWorld.Tile.FULL_DIRT, GridWorld.Tile.ROCK, GridWorld.Tile.HALF,
	GridWorld.Tile.WEDGE, GridWorld.Tile.WEDGE_DIRT, GridWorld.Tile.HALF_WEDGE, GridWorld.Tile.UPPER_HALF_WEDGE,
	GridWorld.Tile.HILL_RAMP, GridWorld.Tile.HALF_HILL_RAMP, GridWorld.Tile.UPPER_HALF_HILL_RAMP,
]

const GRASS := Color(0.45, 0.66, 0.30)
const SLOPE := Color(0.62, 0.43, 0.26)
const WALL := Color(0.55, 0.52, 0.48)
const WATER := Color(0.25, 0.45, 0.80)
## Where the water's surface sits, and the floor under it, in blocks.
const WATER_LEVEL := -0.25
const RIVER_BED := -1.0

## The corners of a cell, NW, NE, SE, SW, as offsets from its NW corner.
const CORNERS := [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1)]

var size: Vector2i
var heights: PackedInt32Array  # blocks; -1 is water
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


## The heights at a cell's four corners (NW, NE, SE, SW): its own height,
## or a block higher where a cell touching that corner is a block higher.
func corners(c: Vector2i) -> Array:
	var h := height(c)
	var out := []
	for k in CORNERS:
		var y := h
		for o in [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 0)]:
			if height(c + k + o) == h + 1:
				y = h + 1
		out.append(y)
	return out


func _run() -> void:
	for z in size.y:
		for x in size.x:
			var c := Vector2i(x, z)
			if height(c) < 0:
				_water(c)
			else:
				_top(c)
				_walls(c)


## The ground's surface in cell c: two triangles over its corner heights.
## Where one corner differs from the other three, it's split through that
## corner, so an outer corner is a hip (both halves sloping) and an inner
## corner a valley.
func _top(c: Vector2i) -> void:
	var ys := corners(c)
	var p := []
	for k in 4:
		p.append(Vector3(c.x + CORNERS[k].x, ys[k], c.y + CORNERS[k].y))
	var split_02 := true  # along NW-SE
	for k in 4:
		var others: Array = [ys[(k + 1) % 4], ys[(k + 2) % 4], ys[(k + 3) % 4]]
		if others[0] == others[1] and others[1] == others[2] and ys[k] != others[0]:
			# Through the odd corner (a hip or a valley), unless the cell is
			# on a diagonal edge: then across it, so the slope runs straight
			# along the diagonal.
			split_02 = (k % 2 == 0) != _on_diagonal(c, k, ys[k] > others[0])
	if split_02:
		_tri(p[0], p[1], p[2])
		_tri(p[0], p[2], p[3])
	else:
		_tri(p[0], p[1], p[3])
		_tri(p[1], p[2], p[3])


## Whether cell c, with one corner k unlike the others (raised, or the one
## not raised), is part of a diagonal edge rather than a lone corner: on a
## diagonal the cells either side of it toward k are the other kind of
## corner piece (three corners raised beside a one-raised cell, and the
## other way round); beside a lone corner they're straight slopes.
func _on_diagonal(c: Vector2i, k: int, raised: bool) -> bool:
	var dx := 1 if CORNERS[k].x == 1 else -1
	var dz := 1 if CORNERS[k].y == 1 else -1
	var want := 3 if raised else 1
	for n in [c + Vector2i(dx, 0), c + Vector2i(0, dz)]:
		if height(n) < 0 or _raised_corners(n) != want:
			return false
	return true


func _raised_corners(c: Vector2i) -> int:
	var h := height(c)
	var n := 0
	for y in corners(c):
		if y > h:
			n += 1
	return n


## Vertical walls on c's sides, down to wherever the ground beside it is
## lower (another cell's edge, the river bed, or the map's edge).
func _walls(c: Vector2i) -> void:
	var ys := corners(c)
	# Sides as pairs of corner indices, and the neighbour's matching corners.
	var sides := [[Vector2i(0, -1), 0, 1, 3, 2], [Vector2i(1, 0), 1, 2, 0, 3],
		[Vector2i(0, 1), 2, 3, 1, 0], [Vector2i(-1, 0), 3, 0, 2, 1]]
	for side in sides:
		var d: Vector2i = side[0]
		var n := c + d
		var hn := height(n)
		var low_a: float
		var low_b: float
		if hn == -99:
			low_a = 0.0
			low_b = 0.0
		elif hn < 0:
			low_a = RIVER_BED
			low_b = RIVER_BED
		else:
			var yn := corners(n)
			low_a = yn[side[3]]
			low_b = yn[side[4]]
		var top_a: float = ys[side[1]]
		var top_b: float = ys[side[2]]
		if top_a <= low_a and top_b <= low_b:
			continue
		var a := Vector2(c + CORNERS[side[1]])
		var b := Vector2(c + CORNERS[side[2]])
		var pa := Vector3(a.x, top_a, a.y)
		var pb := Vector3(b.x, top_b, b.y)
		var qa := Vector3(a.x, minf(low_a, top_a), a.y)
		var qb := Vector3(b.x, minf(low_b, top_b), b.y)
		_wall(pa, pb, qb, qa, Vector3(d.x, 0, d.y))


func _water(c: Vector2i) -> void:
	var p := [Vector3(c.x, WATER_LEVEL, c.y), Vector3(c.x + 1, WATER_LEVEL, c.y),
		Vector3(c.x + 1, WATER_LEVEL, c.y + 1), Vector3(c.x, WATER_LEVEL, c.y + 1)]
	_add(p[0], p[1], p[2], WATER)
	_add(p[0], p[2], p[3], WATER)


## A ground triangle: grass if it's flat, slope colour if not, shaded by
## which way it faces.
func _tri(a: Vector3, b: Vector3, c: Vector3) -> void:
	var flat := is_equal_approx(a.y, b.y) and is_equal_approx(b.y, c.y)
	var col := GRASS if flat else SLOPE
	_add(a, b, c, _shade(col, (b - a).cross(c - a)))


func _wall(a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3) -> void:
	_add(a, b, c, _shade(WALL, n))
	_add(a, c, d, _shade(WALL, n))


## Brighter facing up and toward the camera (south), darker facing away.
func _shade(col: Color, n: Vector3) -> Color:
	if n.length() < 0.0001:
		return col
	n = n.normalized()
	if n.y < -0.01:
		n = -n  # ground triangles: whichever way they were wound, face up
	var light := Vector3(-0.35, 1.0, 0.55).normalized()
	var k := 0.55 + 0.45 * maxf(n.dot(light), 0.0)
	return Color(col.r * k, col.g * k, col.b * k)


func _add(a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
	verts.append_array([a, b, c])
	colors.append_array([col, col, col])
