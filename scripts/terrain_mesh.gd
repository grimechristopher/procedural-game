class_name TerrainMesh
extends RefCounted

## Draws the raised terrain, HGSS style, as one mesh built from the
## heights. The GridMap's terrain blocks still define where you can walk,
## but aren't drawn themselves (see HIDDEN): this mesh is, so that cliffs
## can have rounded corners.
##
## - Tops are drawn a quarter cell at a time, autotiled like a 2D tileset's
##   cliff set: each quarter of a cliff-top cell picks an edge, outer corner
##   or inner corner piece from which of its two sides and the diagonal
##   between them drop away. The pieces carry the cliff's rock (or earth, on
##   gentle ground) onto the top in a band below a grass fringe. Outer
##   corners are rounded into quarter circles.
## - Faces run down every cliff from the band, rock on full cliffs and earth
##   on half cliffs, round the curve of outer corners, with a soft shadow on
##   the ground at their foot (not behind cliffs facing away from the
##   camera, where it'd be hidden anyway).
## - Ground-level paths, the plaza and farmland get grass creeping round
##   their edges the same way, laid over the GridMap's ground.

## Terrain blocks this mesh draws instead of the GridMap.
const HIDDEN := [
	GridWorld.Tile.FULL, GridWorld.Tile.FULL_DIRT, GridWorld.Tile.ROCK, GridWorld.Tile.HALF,
	GridWorld.Tile.WEDGE, GridWorld.Tile.WEDGE_DIRT, GridWorld.Tile.HALF_WEDGE, GridWorld.Tile.UPPER_HALF_WEDGE,
]

## How far the band reaches in from the edge, in cells (5 px), for the
## straight band along diagonal cliffs.
const BAND := 5.0 / 16.0
## Segments in the curve of a rounded corner.
const ARC_STEPS := 4
## Overlays on the GridMap's own ground (at ground level) sit this far
## above it. Faces stand this far out from the cell's edge, clear of the
## sides of the GridMap's ground blocks.
const LIFT := 0.003
const FACE_OFFSET := 0.01
const WATER_SURFACE := -0.25
const SHADOW_WIDTH := 0.45
const SHADOW_ALPHA := 0.35

const T := GridWorld.Tile
const SOLID_TOPS := [T.FULL, T.FULL_DIRT, T.ROCK, T.HALF]
const WEDGES := [T.WEDGE, T.WEDGE_DIRT, T.HALF_WEDGE, T.UPPER_HALF_WEDGE]
const RAMPS := [T.HILL_RAMP, T.HALF_HILL_RAMP, T.UPPER_HALF_HILL_RAMP, T.STAIRS]
## Ground that grass grows round the edges of, in groups that count as the
## same ground (farmland, tilled or not).
const GROUND_GROUPS := [[T.PATH], [T.PLAZA], [T.FARMLAND, T.TILLED, T.TILLED_WET]]
const GRASS := [T.GROUND, T.FLOWERS]

## What tops a cell's column.
enum Kind { NONE, BLOCK, GROUND, WEDGE, RAMP }

## Autotile pieces, in the order of their tiles after the edge piece.
enum Piece { EDGE, OUTER, INNER, CENTER }


## A node holding the terrain's meshes for the world's current heights.
static func build(world: GridWorld, heights: PackedInt32Array, terrain: Terrain) -> Node3D:
	var b := TerrainMesh.new(world, heights, terrain)
	b.run()
	var root := Node3D.new()
	root.name = "TerrainMesh"
	if b.faces.is_empty():
		return root
	var mesh := MeshInstance3D.new()
	mesh.name = "Terrain"
	mesh.mesh = world._build_mesh(b.faces, {}, world.block_material())
	root.add_child(mesh)
	var shadows := MeshInstance3D.new()
	shadows.name = "Shadows"
	shadows.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	b.shadow.set_material(mat)
	shadows.mesh = b.shadow.commit()
	root.add_child(shadows)
	return root


var world: GridWorld
var heights: PackedInt32Array
var terrain: Terrain
var size: Vector2i
var faces := []
var shadow := SurfaceTool.new()
## Per cell: Kind, and the top of the solid (hidden) stack in blocks.
var kind := PackedInt32Array()
var solid := PackedFloat32Array()
## Cell -> exposed sides -> [bottom, water].
var exposed := {}

func _init(w: GridWorld, h: PackedInt32Array, t: Terrain) -> void:
	world = w
	heights = h
	terrain = t
	size = w.map_size
	shadow.begin(Mesh.PRIMITIVE_TRIANGLES)

func run() -> void:
	_classify()
	_find_exposed()
	for z in size.y:
		for x in size.x:
			var c := Vector2i(x, z)
			match kind[z * size.x + x]:
				Kind.BLOCK, Kind.GROUND:
					_cell(c)
				Kind.WEDGE:
					_wedge(c)
				Kind.RAMP:
					_sides(c, false)
			if kind[z * size.x + x] == Kind.GROUND:
				_ground_overlay(c)

# --- What's where ---------------------------------------------------------

func _classify() -> void:
	kind.resize(size.x * size.y)
	solid.resize(size.x * size.y)
	for z in size.y:
		for x in size.x:
			var i := z * size.x + x
			var h := heights[i]
			if h < 0:
				kind[i] = Kind.NONE
				continue
			if h == 0:
				kind[i] = Kind.GROUND
				solid[i] = 0.0
				continue
			var top_layer := (h - 1) / 2
			var top := world.get_cell_item(Vector3i(x, top_layer, z))
			var above := world.get_cell_item(Vector3i(x, h / 2, z))
			if top in WEDGES:
				kind[i] = Kind.WEDGE
				solid[i] = h / 2.0
			elif top in RAMPS:
				# A ramp up from half height, on the blocks below it.
				kind[i] = Kind.RAMP
				solid[i] = top_layer
			elif top in SOLID_TOPS and above in RAMPS:
				kind[i] = Kind.RAMP
				solid[i] = h / 2.0
			elif top in SOLID_TOPS:
				kind[i] = Kind.BLOCK
				solid[i] = h / 2.0
			else:
				kind[i] = Kind.NONE

## Which sides of each cell drop to lower ground (or water), and how far.
func _find_exposed() -> void:
	for z in size.y:
		for x in size.x:
			var c := Vector2i(x, z)
			var i := z * size.x + x
			var k := kind[i]
			if k != Kind.BLOCK and k != Kind.GROUND and k != Kind.RAMP:
				continue
			var top := solid[i]
			var sides := {}
			for d in GridWorld.ORTHOGONAL:
				var n := c + d
				if n.x < 0 or n.y < 0 or n.x >= size.x or n.y >= size.y:
					continue
				var hn := heights[n.y * size.x + n.x]
				if hn < 0:
					sides[d] = [WATER_SURFACE, true]
					continue
				if k == Kind.GROUND or hn / 2.0 >= top:
					continue
				# A ramp climbing this face hides it (one running alongside doesn't).
				var against := world.get_cell_item(Vector3i(n.x, hn / 2, n.y))
				if against in RAMPS and world._up_dir(n, hn / 2) == -d:
					continue
				sides[d] = [hn / 2.0, false]
			if not sides.is_empty():
				exposed[c] = sides

func _height(c: Vector2i) -> int:
	if c.x < 0 or c.y < 0 or c.x >= size.x or c.y >= size.y:
		return -99
	return heights[c.y * size.x + c.x]

func _is_exposed(c: Vector2i, d: Vector2i) -> bool:
	return exposed.has(c) and exposed[c].has(d)

## Which piece the quarter of c toward corner q shows, and whether it's
## transposed (an edge along the east or west side).
func _piece(c: Vector2i, q: Vector2i) -> Array:
	var side_x := _is_exposed(c, Vector2i(q.x, 0))
	var side_z := _is_exposed(c, Vector2i(0, q.y))
	if side_x and side_z:
		return [Piece.OUTER, false]
	if side_z:
		return [Piece.EDGE, false]
	if side_x:
		return [Piece.EDGE, true]
	var h := _height(c)
	var dh := _height(c + q)
	if dh != -99 and dh < h and _height(c + Vector2i(q.x, 0)) == h and _height(c + Vector2i(0, q.y)) == h:
		return [Piece.INNER, false]
	return [Piece.CENTER, false]

func _cliffy(c: Vector2i) -> bool:
	return terrain.is_cliffy(c.x, c.y)

# --- Raised blocks and ground-level shores ---------------------------------

## A cell's top (raised cells) or its shore band (ground level), and the
## faces down its exposed sides.
func _cell(c: Vector2i) -> void:
	var i := c.y * size.x + c.x
	var raised := kind[i] == Kind.BLOCK
	var top := solid[i]
	var base: int = GridWorld.Tex.CLIFF_EDGE if _cliffy(c) else GridWorld.Tex.EARTH_EDGE
	var top_tex: int = GridWorld.Tex.DIRT if world.get_cell_item(Vector3i(c.x, (heights[i] - 1) / 2, c.y)) == T.ROCK \
		else GridWorld.Tex.GRASS
	for q in GridWorld.DIAGONAL:
		var p: Array = _piece(c, q)
		var piece: int = p[0]
		if piece == Piece.OUTER and raised:
			_round_corner(c, q, top, base + Piece.OUTER)
		elif piece == Piece.CENTER:
			if raised:
				faces.append(_quarter(c, q, top, top_tex, false, true))
		else:
			faces.append(_quarter(c, q, top + (0.0 if raised else LIFT), base + piece, p[1], false))
	_sides(c, raised)

## The straight faces down a cell's exposed sides, half a side at a time:
## the half beside a rounded corner is left to the curve.
func _sides(c: Vector2i, raised: bool) -> void:
	if not exposed.has(c):
		return
	var i := c.y * size.x + c.x
	var center := Vector2(c.x + 0.5, c.y + 0.5)
	var tex: int = GridWorld.Tex.DIRT if _cliffy(c) else GridWorld.Tex.EARTH_SIDE
	for d in exposed[c]:
		var bottom: float = exposed[c][d][0]
		var water: bool = exposed[c][d][1]
		var o := Vector2(d)
		var t := Vector2(-d.y, d.x)
		var mid := center + o * 0.5
		for half in [-1, 1]:
			var q := Vector2i(d) + Vector2i(t * half)
			if raised and _piece(c, q)[0] == Piece.OUTER:
				continue
			var a := mid if half == 1 else mid - t * 0.5
			var b := mid + t * 0.5 if half == 1 else mid
			_face(a, b, o, solid[i], bottom, tex)
			if not water and o.y > -0.3:
				_shadow(a, b, o, bottom)

## A rounded outer corner: the top quarter as a quarter circle round the
## cell's centre, and the face following its curve.
func _round_corner(c: Vector2i, q: Vector2i, top: float, tile: int) -> void:
	var center := Vector2(c.x + 0.5, c.y + 0.5)
	var bottom_x: float = exposed[c][Vector2i(q.x, 0)][0]
	var bottom_z: float = exposed[c][Vector2i(0, q.y)][0]
	var water: bool = exposed[c][Vector2i(q.x, 0)][1] or exposed[c][Vector2i(0, q.y)][1]
	var bottom := minf(bottom_x, bottom_z)
	var tex: int = GridWorld.Tex.DIRT if _cliffy(c) else GridWorld.Tex.EARTH_SIDE
	var along := 0.0
	for k in ARC_STEPS:
		var a0 := PI / 2.0 * k / ARC_STEPS
		var a1 := PI / 2.0 * (k + 1) / ARC_STEPS
		var u0 := Vector2(cos(a0), sin(a0))
		var u1 := Vector2(cos(a1), sin(a1))
		var d0 := Vector2(u0.x * q.x, u0.y * q.y) * (0.5 + FACE_OFFSET)
		var d1 := Vector2(u1.x * q.x, u1.y * q.y) * (0.5 + FACE_OFFSET)
		# Top: a wedge of the quarter circle, the piece's texels laid flat.
		var uv0 := Vector2(0.5, 0.5) + Vector2(u0.x, u0.y) * 0.4999
		var uv1 := Vector2(0.5, 0.5) + Vector2(u1.x, u1.y) * 0.4999
		faces.append([[_at(center, top), _at(center + d0, top), _at(center + d1, top)],
			Vector3.UP, tile, [Vector2(0.5, 0.5), uv0, uv1]])
		# Face: one slice of the curve.
		var o := ((d0 + d1) / 2.0).normalized()
		var length := d0.distance_to(d1)
		faces.append([[_at(center + d0, top), _at(center + d1, top), _at(center + d1, bottom), _at(center + d0, bottom)],
			Vector3(o.x, 0, o.y), tex,
			[Vector2(along, 0), Vector2(along + length, 0), Vector2(along + length, top - bottom), Vector2(along, top - bottom)]])
		along += length
		if not water and o.y > -0.3:
			_shadow(center + d0, center + d1, o, bottom, d0.normalized(), d1.normalized())

# --- Wedges ------------------------------------------------------------------

## A diagonal cliff: the solid half's top, the open half's floor (when
## it's raised, so not GridMap ground), the band and the slanted face.
func _wedge(c: Vector2i) -> void:
	var i := c.y * size.x + c.x
	var h := heights[i]
	var top_layer := (h - 1) / 2
	var si := world._corner_dir(c, top_layer)
	var s := Vector2(si)
	var center := Vector2(c.x + 0.5, c.y + 0.5)
	var low := maxi(heights[c.y * size.x + c.x - si.x], 0)
	var top := h / 2.0
	var bottom := low / 2.0
	var p0 := center + Vector2(s.x, -s.y) * 0.5
	var p1 := center + Vector2(-s.x, s.y) * 0.5
	var solid_corner := center + s * 0.5
	var open_corner := center - s * 0.5
	var top_tex := GridWorld.Tex.GRASS
	faces.append([[_at(solid_corner, top), _at(p0, top), _at(p1, top)], Vector3.UP, top_tex,
		_planar([_at(solid_corner, top), _at(p0, top), _at(p1, top)])])
	if low > 0:
		faces.append([[_at(open_corner, bottom), _at(p0, bottom), _at(p1, bottom)], Vector3.UP, top_tex,
			_planar([_at(open_corner, bottom), _at(p0, bottom), _at(p1, bottom)])])
	var o := -s.normalized()
	var base: int = GridWorld.Tex.CLIFF_EDGE if _cliffy(c) else GridWorld.Tex.EARTH_EDGE
	# The straight band along the diagonal edge, just above the top.
	var inner := -o * BAND
	var length := p0.distance_to(p1)
	faces.append([[_at(p0 + inner, top + LIFT), _at(p1 + inner, top + LIFT), _at(p1, top + LIFT), _at(p0, top + LIFT)],
		Vector3.UP, base,
		[Vector2(0, 1.0 - BAND), Vector2(length, 1.0 - BAND), Vector2(length, 0.999), Vector2(0, 0.999)]])
	var tex: int = GridWorld.Tex.DIRT if _cliffy(c) else GridWorld.Tex.EARTH_SIDE
	_face(p0, p1, o, top, bottom, tex)
	if o.y > -0.3:
		_shadow(p0, p1, o, bottom)

# --- Ground-level transitions ------------------------------------------------

## Grass round the edges of a path, the plaza or farmland where it meets
## grass, over the GridMap's ground (see-through elsewhere).
func _ground_overlay(c: Vector2i) -> void:
	var group := _ground_group(world.ground_tile(c))
	if group < 0:
		return
	for q in GridWorld.DIAGONAL:
		var side_x := _is_grass(c + Vector2i(q.x, 0))
		var side_z := _is_grass(c + Vector2i(0, q.y))
		var piece := -1
		var transpose := false
		if side_x and side_z:
			piece = Piece.OUTER
		elif side_z:
			piece = Piece.EDGE
		elif side_x:
			piece = Piece.EDGE
			transpose = true
		elif _is_grass(c + q):
			piece = Piece.INNER
		if piece >= 0:
			faces.append(_quarter(c, q, LIFT, GridWorld.Tex.GRASS_EDGE + piece, transpose, false))

func _ground_group(tile: int) -> int:
	for i in GROUND_GROUPS.size():
		if tile in GROUND_GROUPS[i]:
			return i
	return -1

## Whether a cell is grass at ground level (not raised, not other ground).
func _is_grass(c: Vector2i) -> bool:
	return _height(c) == 0 and world.ground_tile(c) in GRASS

# --- Pieces ------------------------------------------------------------------

## One quarter of a cell's top, toward corner q. An autotile piece is
## drawn for the south-east quarter with its edge along the south; other
## quarters mirror it, and an edge along the east or west transposes.
## planar lays a whole-cell tile (plain ground) down instead.
func _quarter(c: Vector2i, q: Vector2i, y: float, tile: int, transpose: bool, planar: bool) -> Array:
	var center := Vector2(c.x + 0.5, c.y + 0.5)
	var pts := []
	var uvs := []
	for k in [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]:
		# Out to the faces, which stand a hair past the cell's edge (and so a
		# lifted overlay doesn't leave a sliver of what's under it showing).
		var reach: Vector2 = Vector2(0.5, 0.5) + k * FACE_OFFSET
		var p: Vector2 = center + Vector2(k.x * q.x, k.y * q.y) * reach
		pts.append(_at(p, y))
		var uv: Vector2 = Vector2(k.y, k.x) if transpose else k
		uvs.append(p if planar else Vector2(0.5, 0.5) + uv * 0.4999)
	return [pts, Vector3.UP, tile, uvs]

## A face from a to b (along the top edge), facing o, from top down to
## bottom, its tile hanging from the top so each block shows one tile.
func _face(a: Vector2, b: Vector2, o: Vector2, top: float, bottom: float, tex: int) -> void:
	if top <= bottom:
		return
	var out := o * FACE_OFFSET
	var u0 := _along(a, o)
	var u1 := u0 + a.distance_to(b)
	faces.append([[_at(a + out, top), _at(b + out, top), _at(b + out, bottom), _at(a + out, bottom)],
		Vector3(o.x, 0, o.y), tex,
		[Vector2(u0, 0), Vector2(u1, 0), Vector2(u1, top - bottom), Vector2(u0, top - bottom)]])

## A strip of shade on the ground at the foot of a face, fading outward
## (along o, or along out_a and out_b at each end, round a curve).
func _shadow(a: Vector2, b: Vector2, o: Vector2, bottom: float, out_a := Vector2.ZERO, out_b := Vector2.ZERO) -> void:
	if out_a == Vector2.ZERO:
		out_a = o
		out_b = o
	var y := bottom + 0.004
	var near0 := Vector3(a.x, y, a.y)
	var near1 := Vector3(b.x, y, b.y)
	var far0 := near0 + Vector3(out_a.x, 0, out_a.y) * SHADOW_WIDTH
	var far1 := near1 + Vector3(out_b.x, 0, out_b.y) * SHADOW_WIDTH
	var dark := Color(0, 0, 0, SHADOW_ALPHA)
	var clear := Color(0, 0, 0, 0)
	for v in [[near0, dark], [near1, dark], [far1, clear],
			[near0, dark], [far1, clear], [far0, clear]]:
		shadow.set_color(v[1])
		shadow.set_normal(Vector3.UP)
		shadow.add_vertex(v[0])


static func _at(p: Vector2, y: float) -> Vector3:
	return Vector3(p.x, y, p.y)


## Where a texture starts along an edge from p, in world units, so
## neighbouring edges' tiles line up.
static func _along(p: Vector2, o: Vector2) -> float:
	if absf(o.y) > 0.9:
		return p.x
	if absf(o.x) > 0.9:
		return p.y
	return 0.0


## Whole-cell tile UVs projected straight down.
static func _planar(pts: Array) -> Array:
	var uvs := []
	for p in pts:
		uvs.append(Vector2(p.x, p.z))
	return uvs
