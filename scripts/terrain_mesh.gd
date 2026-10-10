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
## - Ramps are grassy slopes with the cliff's band running down their
##   sides and the cliff's face cut to their slope below it, so they read as
##   part of the cliff they climb.
## - Ground-level paths, the plaza and farmland get grass creeping round
##   their edges the same way, laid over the GridMap's ground.

## Terrain blocks this mesh draws instead of the GridMap.
const HIDDEN := [
	GridWorld.Tile.FULL, GridWorld.Tile.FULL_DIRT, GridWorld.Tile.ROCK, GridWorld.Tile.HALF,
	GridWorld.Tile.WEDGE, GridWorld.Tile.WEDGE_DIRT, GridWorld.Tile.HALF_WEDGE, GridWorld.Tile.UPPER_HALF_WEDGE,
	GridWorld.Tile.HILL_RAMP, GridWorld.Tile.HALF_HILL_RAMP, GridWorld.Tile.UPPER_HALF_HILL_RAMP,
]

## How far the band reaches in from the edge, in cells (5 px), for the
## straight band along diagonal cliffs.
const BAND := 5.0 / 16.0
## Outer corners are turned in a slight curve of this radius (4 px), in
## this many segments.
const CORNER_RADIUS := 0.25
const ARC_STEPS := 3
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
## Per cell: Kind, the top of the solid (hidden) stack in blocks, and for
## ramps the layer they're in.
var kind := PackedInt32Array()
var solid := PackedFloat32Array()
var ramp_layer := PackedInt32Array()
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
					_ramp(c)
					_sides(c, false)
			if kind[z * size.x + x] == Kind.GROUND:
				_ground_overlay(c)

# --- What's where ---------------------------------------------------------

func _classify() -> void:
	kind.resize(size.x * size.y)
	solid.resize(size.x * size.y)
	ramp_layer.resize(size.x * size.y)
	for z in size.y:
		for x in size.x:
			var i := z * size.x + x
			var h := heights[i]
			if h < 0:
				kind[i] = Kind.NONE
				continue
			var top_layer := (h - 1) / 2
			var top := world.get_cell_item(Vector3i(x, top_layer, z)) if h > 0 else -1
			var above := world.get_cell_item(Vector3i(x, h / 2, z))
			if above in RAMPS and (h == 0 or top in SOLID_TOPS):
				kind[i] = Kind.RAMP
				solid[i] = h / 2.0
				ramp_layer[i] = h / 2
			elif h == 0:
				kind[i] = Kind.GROUND
				solid[i] = 0.0
			elif top in WEDGES:
				kind[i] = Kind.WEDGE
				solid[i] = h / 2.0
			elif top in RAMPS:
				# A ramp up from half height, on a solid lower half.
				kind[i] = Kind.RAMP
				solid[i] = top_layer + 0.5
				ramp_layer[i] = top_layer
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
	var top_tex: int = GridWorld.Tex.ROCK_TOP if world.get_cell_item(Vector3i(c.x, (heights[i] - 1) / 2, c.y)) == T.ROCK \
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

## A rounded outer corner, Pokemon style: the quarter keeps its square
## sides, with the corner itself turned in a slight curve (CORNER_RADIUS),
## and the faces follow it round.
func _round_corner(c: Vector2i, q: Vector2i, top: float, tile: int) -> void:
	var center := Vector2(c.x + 0.5, c.y + 0.5)
	var bottom_x: float = exposed[c][Vector2i(q.x, 0)][0]
	var bottom_z: float = exposed[c][Vector2i(0, q.y)][0]
	var water_x: bool = exposed[c][Vector2i(q.x, 0)][1]
	var water_z: bool = exposed[c][Vector2i(0, q.y)][1]
	var tex: int = GridWorld.Tex.DIRT if _cliffy(c) else GridWorld.Tex.EARTH_SIDE
	var e := 0.5 + FACE_OFFSET
	var r := CORNER_RADIUS
	# The outline in the quarter's own frame (x toward q.x, y toward q.y),
	# from the middle of the x side round to the middle of the y side.
	var outline: Array[Vector2] = [Vector2(e, 0)]
	for k in ARC_STEPS + 1:
		var angle := PI / 2.0 * k / ARC_STEPS
		outline.append(Vector2(e - r, e - r) + Vector2(cos(angle), sin(angle)) * r)
	outline.append(Vector2(0, e))
	# Top: a fan from the cell's centre, the piece's texels laid flat.
	var pts := [_at(center, top)]
	var uvs := [Vector2(0.5, 0.5)]
	for l in outline:
		pts.append(_at(center + Vector2(l.x * q.x, l.y * q.y), top))
		uvs.append(Vector2(0.5, 0.5) + (l / e) * 0.4999)
	faces.append([pts, Vector3.UP, tile, uvs])
	# Faces: straight down each side, then slices round the curve. (Faces
	# already stand FACE_OFFSET out, so they're drawn from the cell's edge.)
	var x_side := center + Vector2(0.5 * q.x, 0)
	var y_side := center + Vector2(0, 0.5 * q.y)
	var x_end := center + Vector2(0.5 * q.x, (e - r) * q.y)
	var y_end := center + Vector2((e - r) * q.x, 0.5 * q.y)
	var ox := Vector2(q.x, 0)
	var oy := Vector2(0, q.y)
	_face(x_side, x_end, ox, top, bottom_x, tex)
	_face(y_end, y_side, oy, top, bottom_z, tex)
	if not water_x and ox.y > -0.3:
		_shadow(x_side, x_end, ox, bottom_x)
	if not water_z and oy.y > -0.3:
		_shadow(y_end, y_side, oy, bottom_z)
	var bottom := minf(bottom_x, bottom_z)
	var along := 0.0
	for k in ARC_STEPS:
		var l0: Vector2 = outline[k + 1]
		var l1: Vector2 = outline[k + 2]
		var d0 := center + Vector2(l0.x * q.x, l0.y * q.y)
		var d1 := center + Vector2(l1.x * q.x, l1.y * q.y)
		var m := (l0 + l1) / 2.0 - Vector2(e - r, e - r)
		var o := Vector2(m.x * q.x, m.y * q.y).normalized()
		var length := d0.distance_to(d1)
		faces.append([[_at(d0, top), _at(d1, top), _at(d1, bottom), _at(d0, bottom)],
			Vector3(o.x, 0, o.y), tex,
			[Vector2(along, 0), Vector2(along + length, 0), Vector2(along + length, top - bottom), Vector2(along, top - bottom)]])
		along += length
		if not (water_x or water_z) and o.y > -0.3:
			var n0 := l0 - Vector2(e - r, e - r)
			var n1 := l1 - Vector2(e - r, e - r)
			_shadow(d0, d1, o, bottom, Vector2(n0.x * q.x, n0.y * q.y).normalized(),
				Vector2(n1.x * q.x, n1.y * q.y).normalized())


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

# --- Ramps -------------------------------------------------------------------

## A ramp: the grassy slope, and on each side where the ground beside it is
## lower, the cliff's face cut to the slope and its band running down the
## slope's edge.
func _ramp(c: Vector2i) -> void:
	var i := c.y * size.x + c.x
	var layer := ramp_layer[i]
	var tile := world.get_cell_item(Vector3i(c.x, layer, c.y))
	var base: float = layer + GridWorld._base(tile)
	var rise: float = GridWorld._rise(tile)
	var up := Vector2(world._up_dir(c, layer))
	var center := Vector2(c.x + 0.5, c.y + 0.5)
	var across := Vector2(-up.y, up.x)
	# Corners: low left, low right, high right, high left.
	var corners := [center - up * 0.5 - across * 0.5, center - up * 0.5 + across * 0.5,
		center + up * 0.5 + across * 0.5, center + up * 0.5 - across * 0.5]
	var y := [base, base, base + rise, base + rise]
	var pts := []
	for k in 4:
		pts.append(_at(corners[k], y[k]))
	var n: Vector3 = (pts[1] - pts[0]).cross(pts[3] - pts[0]).normalized()
	faces.append([pts, n if n.y > 0.0 else -n, GridWorld.Tex.GRASS, _planar(pts)])
	var cliffy := _cliffy(c)
	var face_tex: int = GridWorld.Tex.DIRT if cliffy else GridWorld.Tex.EARTH_SIDE
	var band_tex: int = GridWorld.Tex.CLIFF_EDGE if cliffy else GridWorld.Tex.EARTH_EDGE
	for side in [-1, 1]:
		var o: Vector2 = across * side
		var nh := _height(c + Vector2i(o))
		if nh == -99:
			continue
		var floor_h := maxf(nh / 2.0, WATER_SURFACE if nh < 0 else 0.0)
		if floor_h >= base + rise:
			continue
		# The side edge, low end to high end.
		var a: Vector2 = corners[0] if side == -1 else corners[1]
		var b: Vector2 = corners[3] if side == -1 else corners[2]
		_slanted_face(a, b, o, base, base + rise, floor_h, face_tex)
		# The band, on the slope along that edge.
		var inner: Vector2 = -o * BAND
		var lift := Vector3(0, LIFT, 0)
		var u1 := a.distance_to(b)
		faces.append([[_at(a + inner, base) + lift, _at(b + inner, base + rise) + lift,
			_at(b, base + rise) + lift, _at(a, base) + lift], n if n.y > 0.0 else -n, band_tex,
			[Vector2(0, 1.0 - BAND), Vector2(u1, 1.0 - BAND), Vector2(u1, 0.999), Vector2(0, 0.999)]])
		if o.y > -0.3 and nh >= 0:
			_shadow(a, b, o, floor_h)


## A face below an edge that slopes from top_a at a to top_b at b, down to
## floor_h (cut off where the edge dips below the floor).
func _slanted_face(a: Vector2, b: Vector2, o: Vector2, top_a: float, top_b: float, floor_h: float, tex: int) -> void:
	var out := o * FACE_OFFSET
	var t0 := clampf((floor_h - top_a) / (top_b - top_a), 0.0, 1.0) if top_b != top_a else 0.0
	var start := a.lerp(b, t0)
	var start_top := lerpf(top_a, top_b, t0)
	var u0 := 0.0
	var u1 := a.distance_to(b)
	var pts := [_at(start + out, start_top), _at(b + out, top_b), _at(b + out, floor_h)]
	var uvs := [Vector2(u1 * t0, top_b - start_top), Vector2(u1, 0), Vector2(u1, top_b - floor_h)]
	if start_top > floor_h + 0.001:
		pts.append(_at(start + out, floor_h))
		uvs.append(Vector2(u1 * t0, top_b - floor_h))
	faces.append([pts, Vector3(o.x, 0, o.y), tex, uvs])


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
