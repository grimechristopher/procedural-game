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
## - Full cliffs that step back one at a time (terraces) are HGSS-style
##   banks: the face slopes down across the whole cell at the cliff's foot
##   (the world makes that cell impassable), wrapping round outer corners.
## - Other faces run straight down every cliff from the band, rock on full
##   cliffs and earth on half cliffs, round the curve of outer corners.
##   (No cast shadows: those belong to a day-night system, later.)
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
## How far a bank's top edge dips below the ground above it (see
## _add_lipped), in blocks.
const LIP := 0.15
## Where a tapered band's outer edge is pulled in to (in tile units, from
## the tile's top-left): past the band, so it narrows to nothing.
const TAPER_END := 10.5 / 16.0
const FACE_OFFSET := 0.01
const WATER_SURFACE := -0.25

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
enum Piece { EDGE, OUTER, INNER, CENTER, JOINT, TEE }


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
	return root


var world: GridWorld
var heights: PackedInt32Array
var terrain: Terrain
var size: Vector2i
var faces := []
## Per cell: Kind, the top of the solid (hidden) stack in blocks, and for
## ramps the layer they're in.
var kind := PackedInt32Array()
var solid := PackedFloat32Array()
var ramp_layer := PackedInt32Array()
## Ramp cell -> { base, rise (blocks), up (Vector2i), tile }.
var ramps := {}
## Cell -> exposed sides -> [bottom, water].
var exposed := {}

func _init(w: GridWorld, h: PackedInt32Array, t: Terrain) -> void:
	world = w
	heights = h
	terrain = t
	size = w.map_size

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
			if _has_bank(c):
				_bank_cell(c)

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
			if k == Kind.RAMP:
				_find_ramp_exposed(c)
				continue
			if k != Kind.BLOCK and k != Kind.GROUND:
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

## Rule: a ramp's sides are cliff edges wherever the ground beside them is
## lower than the ramp's top, unless a matching ramp runs alongside (one
## wide ramp). Its low end is an edge only if the ground in front drops
## below it; its high end never is.
func _find_ramp_exposed(c: Vector2i) -> void:
	var i := c.y * size.x + c.x
	var layer := ramp_layer[i]
	var tile := world.get_cell_item(Vector3i(c.x, layer, c.y))
	var up := world._up_dir(c, layer)
	var base: float = layer + GridWorld._base(tile)
	var rise: float = GridWorld._rise(tile)
	ramps[c] = { base = base, rise = rise, up = up, tile = tile }
	var sides := {}
	for d in GridWorld.ORTHOGONAL:
		var n := c + d
		var hn := _height(n)
		if hn == -99 or d == up:
			continue
		if hn < 0:
			sides[d] = [WATER_SURFACE, true]
			continue
		if d == -up:
			# (Not where the lower half of the same ramp leads into it.)
			# (The ramp below may sit a block lower, on a longer run.)
			var continues := false
			for l in [layer, layer - 1]:
				var below := world.get_cell_item(Vector3i(n.x, l, n.y))
				if below in RAMPS and world._up_dir(n, l) == up \
						and is_equal_approx(l + GridWorld._base(below) + GridWorld._rise(below), base):
					continues = true
			if hn / 2.0 < base and not continues:
				sides[d] = [hn / 2.0, false]
			continue
		if world.get_cell_item(Vector3i(n.x, layer, n.y)) == tile and world._up_dir(n, layer) == up:
			continue
		if hn / 2.0 < base + rise:
			sides[d] = [hn / 2.0, false]
	if not sides.is_empty():
		exposed[c] = sides


## Rule: n counts as level with c for corner pieces if it's as high, or
## it's a ramp leading up onto c.
func _level_with(n: Vector2i, c: Vector2i) -> bool:
	if _height(n) == _height(c):
		return true
	if not ramps.has(n) and kind[n.y * size.x + n.x] == Kind.RAMP:
		_find_ramp_exposed(n)
	return ramps.has(n) and n + ramps[n].up == c \
		and is_equal_approx(ramps[n].base + ramps[n].rise, _height(c) / 2.0)


## How high a cell's ground reaches, in steps: a ramp counts at its top
## (so a ramp climbing up beside a corner doesn't make it drop away).
func _top_steps(c: Vector2i) -> int:
	var h := _height(c)
	if h < 0 or kind[c.y * size.x + c.x] != Kind.RAMP:
		return h
	if not ramps.has(c):
		_find_ramp_exposed(c)
	return roundi((ramps[c].base + ramps[c].rise) * 2.0)


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
		# Rule: if the cliff along one side carries on past the corner (one
		# level lower, along the neighbour on the other side), it's a
		# T-junction: square, not a free-standing rounded corner.
		var nx := c + Vector2i(q.x, 0)
		var nz := c + Vector2i(0, q.y)
		if (_is_exposed(nx, Vector2i(0, q.y)) and _height(nx) >= 0) \
				or (_is_exposed(nz, Vector2i(q.x, 0)) and _height(nz) >= 0):
			return [Piece.TEE, false]
		return [Piece.OUTER, false]
	if side_z:
		return [Piece.EDGE, false]
	if side_x:
		return [Piece.EDGE, true]
	# Rule: an inside corner where both sides are level with c (a ramp up
	# to c counts) and the diagonal drops away.
	var h := _height(c)
	var dh := _top_steps(c + q)
	if dh != -99 and dh < h and kind[c.y * size.x + c.x] != Kind.RAMP \
			and _level_with(c + Vector2i(q.x, 0), c) and _level_with(c + Vector2i(0, q.y), c):
		return [Piece.JOINT if _diagonal_meets(c, q) else Piece.INNER, false]
	return [Piece.CENTER, false]


## Whether a diagonal cliff beside c ends at its corner q, so the quarter
## sits in the crook between two wedges and the band runs on through it.
func _diagonal_meets(c: Vector2i, q: Vector2i) -> bool:
	var corner := Vector2(c.x + 0.5, c.y + 0.5) + Vector2(q) * 0.5
	for n in [c + Vector2i(q.x, 0), c + Vector2i(0, q.y)]:
		if _height(n) < 0 or kind[n.y * size.x + n.x] != Kind.WEDGE:
			continue
		var sn := Vector2(world._corner_dir(n, (heights[n.y * size.x + n.x] - 1) / 2))
		var center := Vector2(n.x + 0.5, n.y + 0.5)
		if corner.is_equal_approx(center + Vector2(sn.x, -sn.y) * 0.5) \
				or corner.is_equal_approx(center + Vector2(-sn.x, sn.y) * 0.5):
			return true
	return false

func _cliffy(c: Vector2i) -> bool:
	return world.is_cliffy_at(c)

# --- Raised blocks and ground-level shores ---------------------------------

## A cell's top (raised cells) or its shore band (ground level), and the
## faces down its exposed sides.
func _cell(c: Vector2i) -> void:
	var i := c.y * size.x + c.x
	var raised := kind[i] == Kind.BLOCK
	var top := solid[i]
	var base: int = GridWorld.Tex.CLIFF_EDGE if _cliffy(c) else GridWorld.Tex.EARTH_EDGE
	var joint: int = GridWorld.Tex.CLIFF_JOINT if _cliffy(c) else GridWorld.Tex.EARTH_JOINT
	var tee: int = GridWorld.Tex.CLIFF_TEE if _cliffy(c) else GridWorld.Tex.EARTH_TEE
	var top_tex := GridWorld.Tex.GRASS
	if _slope_continues(c):
		# Under a slope that carries on down another one, rock shows
		# between the tips of its ribs, not grass.
		for q in GridWorld.DIAGONAL:
			faces.append(_quarter(c, q, top, GridWorld.Tex.DIRT, false, true))
		_sides(c, raised)
		return
	if raised and _rocky(heights[i]):
		# Bare rock on high ground, with rock (not grass) inside the band.
		base = GridWorld.Tex.ROCK_EDGE
		joint = GridWorld.Tex.ROCK_JOINT
		tee = GridWorld.Tex.ROCK_TEE
		top_tex = GridWorld.Tex.ROCK_TOP
	for q in GridWorld.DIAGONAL:
		var p: Array = _piece(c, q)
		var piece: int = p[0]
		if raised and piece != Piece.CENTER and piece != Piece.JOINT and _only_banks(c, q, piece):
			# Pokemon style: grass right up to a slope's edge (curving down
			# into it), the rock all on the slope.
			_add_lipped(_quarter(c, q, top, top_tex, false, true), c, q)
			continue
		if piece == Piece.OUTER and raised and _rounded(c, q):
			_round_corner(c, q, top, base + Piece.OUTER)
		elif piece == Piece.OUTER and raised:
			_add_lipped(_quarter(c, q, top, base + Piece.OUTER, false, false), c, q)
		elif piece == Piece.CENTER:
			if raised:
				faces.append(_quarter(c, q, top, top_tex, false, true))
		elif piece == Piece.JOINT:
			faces.append(_quarter(c, q, top + (0.0 if raised else LIFT), joint, false, false))
		elif piece == Piece.TEE:
			_add_lipped(_quarter(c, q, top + (0.0 if raised else LIFT), tee, false, false), c, q)
		elif raised:
			_add_lipped(_quarter(c, q, top, base + piece, p[1], false), c, q)
		else:
			faces.append(_quarter(c, q, top + LIFT, base + piece, p[1], false))
	_sides(c, raised)

## The faces down a cell's exposed sides: a bank sloping across the cell
## below, or straight down half a side at a time (the half beside a rounded
## corner is left to the curve).
func _sides(c: Vector2i, raised: bool) -> void:
	if not exposed.has(c):
		return
	var i := c.y * size.x + c.x
	var center := Vector2(c.x + 0.5, c.y + 0.5)
	var tex: int = GridWorld.Tex.DIRT if _cliffy(c) else GridWorld.Tex.EARTH_SIDE
	for d in exposed[c]:
		var bottom: float = exposed[c][d][0]
		var o := Vector2(d)
		var t := Vector2(-d.y, d.x)
		var mid := center + o * 0.5
		if raised and _is_bank(c, d):
			continue  # the bank below draws the slope (_bank_cell)
		for half in [-1, 1]:
			var q := Vector2i(d) + Vector2i(t * half)
			if raised and _rounded(c, q):
				continue
			var a := mid if half == 1 else mid - t * 0.5
			var b := mid + t * 0.5 if half == 1 else mid
			_face(a, b, o, solid[i], bottom, tex)

## Whether ground this high (in steps) is bare rock.
func _rocky(steps: int) -> bool:
	return steps >= world.rock_level * 2


## Whether c's cliff on side d is an HGSS-style bank: a block high, with a
## bank at its foot.
func _is_bank(c: Vector2i, d: Vector2i) -> bool:
	var n := c + d
	var hn := _height(n)
	return hn >= 0 and _height(c) - hn == 2 and world.get_cell_item(Vector3i(n.x, hn / 2, n.y)) == T.BANK


## Whether every drop the quarter of c toward q shows a band for is a
## bank (a slope), so the quarter can be plain ground.
func _only_banks(c: Vector2i, q: Vector2i, piece: int) -> bool:
	var sx := Vector2i(q.x, 0)
	var sz := Vector2i(0, q.y)
	if piece == Piece.INNER:
		return _has_bank(c + q)
	var any := false
	for side in [sx, sz]:
		if _is_exposed(c, side):
			if not _is_bank(c, side):
				return false
			any = true
	return any


## Rule: a bank's slope starts a little in from the cliff's edge, HGSS
## style: the band along the top of the edge leans down into it, by LIP.
## Adds a raised cell's quarter (as _quarter made it), with its outer band
## tilted down along whichever of its sides are banks.
func _add_lipped(quarter: Array, c: Vector2i, q: Vector2i) -> void:
	var lip_x := _is_bank(c, Vector2i(q.x, 0))
	var lip_z := _is_bank(c, Vector2i(0, q.y))
	if not lip_x and not lip_z:
		faces.append(quarter)
		return
	var pts: Array = quarter[0]
	var uvs: Array = quarter[3]
	# Bilinear over the quarter: s out toward the x side, t toward the z side.
	var at := func(st: Vector2) -> Array:
		var a: Vector3 = pts[0].lerp(pts[1], st.x)
		var b: Vector3 = pts[3].lerp(pts[2], st.x)
		var p: Vector3 = a.lerp(b, st.y)
		var ua: Vector2 = uvs[0].lerp(uvs[1], st.x)
		var ub: Vector2 = uvs[3].lerp(uvs[2], st.x)
		if (lip_x and st.x >= 1.0) or (lip_z and st.y >= 1.0):
			p.y -= LIP
		return [p, ua.lerp(ub, st.y)]
	var inner := 1.0 - BAND / 0.5
	var ss := [0.0, inner, 1.0] if lip_x else [0.0, 1.0]
	var ts := [0.0, inner, 1.0] if lip_z else [0.0, 1.0]
	for i in ss.size() - 1:
		for j in ts.size() - 1:
			var corners := [Vector2(ss[i], ts[j]), Vector2(ss[i + 1], ts[j]),
				Vector2(ss[i + 1], ts[j + 1]), Vector2(ss[i], ts[j + 1])]
			var sub_pts := []
			var sub_uvs := []
			for st in corners:
				var v: Array = at.call(st)
				sub_pts.append(v[0])
				sub_uvs.append(v[1])
			faces.append([sub_pts, Vector3.UP, quarter[2], sub_uvs])


## Whether c holds a bank whose slope carries straight on down another
## bank below it (a slope more than a block tall), and is all slope, no
## flat part showing.
func _slope_continues(c: Vector2i) -> bool:
	if not _has_bank(c):
		return false
	var ys: Array = _bank_corners(c)[0]
	var floor_y := _height(c) / 2.0
	var at_floor := 0
	for y in ys:
		if y <= floor_y + 0.001:
			at_floor += 1
	if at_floor > 2:
		return false
	for d in GridWorld.ORTHOGONAL:
		if _height(c + d) == _height(c) - 2 and _has_bank(c + d):
			return true
	return false


## Whether wedge c is cut between two slopes (so its slope runs on along
## the diagonal), rather than standing as a vertical diagonal face.
func _sloped_wedge(c: Vector2i) -> bool:
	var si := world._corner_dir(c, (_height(c) - 1) / 2)
	return _has_bank(c - Vector2i(si.x, 0)) and _has_bank(c - Vector2i(0, si.y))


## Whether a raised cell n's corner at point p is lipped (see _add_lipped):
## one of n's sides meeting there is a bank.
func _lip_at(n: Vector2i, p: Vector2) -> bool:
	var sx := signi(roundi(p.x * 2.0) - (n.x * 2 + 1))
	var sz := signi(roundi(p.y * 2.0) - (n.y * 2 + 1))
	return _is_bank(n, Vector2i(sx, 0)) or _is_bank(n, Vector2i(0, sz))


## Whether c's quarter toward q is an outer corner turned in a curve (both
## its cliffs vertical).
func _rounded(c: Vector2i, q: Vector2i) -> bool:
	return _piece(c, q)[0] == Piece.OUTER and not _is_bank(c, Vector2i(q.x, 0)) \
		and not _is_bank(c, Vector2i(0, q.y))


func _has_bank(c: Vector2i) -> bool:
	var h := _height(c)
	return h >= 0 and world.get_cell_item(Vector3i(c.x, h / 2, c.y)) == T.BANK


## Rule: a bank's slope is set by the heights at its cell's corners. Each
## corner is as high as the tallest block touching it that stands exactly
## a block above the bank's floor (a wedge's cut-off corner doesn't
## count), else the floor. So straight, corner, diagonal and stacked slopes
## all meet without seams. Returns [heights NW, NE, SE, SW], and whether
## the rock is a cliff's (not earth).
func _bank_corners(c: Vector2i) -> Array:
	var hb := _height(c)
	var out := []
	var cliffy := _cliffy(c)
	var beside_cut := false
	for k in CORNERS:
		var p: Vector2 = Vector2(c) + k
		var y := hb / 2.0
		var lipped := false
		for o in [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 0)]:
			var n: Vector2i = Vector2i(p) + o
			if n == c or _height(n) != hb + 2:
				continue
			var kn := kind[n.y * size.x + n.x]
			if kn == Kind.WEDGE:
				var sn := Vector2(world._corner_dir(n, (hb + 1) / 2))
				if p.is_equal_approx(Vector2(n.x + 0.5, n.y + 0.5) - sn * 0.5):
					beside_cut = true
					continue
				lipped = lipped or _sloped_wedge(n)
			elif kn != Kind.BLOCK:
				continue
			y = maxf(y, (hb + 2) / 2.0)
			lipped = lipped or (kn == Kind.BLOCK and _lip_at(n, p))
			cliffy = cliffy or _cliffy(n)
		# (Dipped to meet a lipped edge above it, see _add_lipped.)
		out.append(y - LIP if lipped and y > hb / 2.0 else y)
	return [out, cliffy, beside_cut]

## The cell's corners, NW, NE, SE, SW, as offsets from its north-west corner.
const CORNERS := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]


## A bank's slope from its corner heights, split along the diagonal that
## keeps it lowest (so an outside corner is a facet and an inside one a
## valley), and its ends closed down to lower ground beside it.
func _bank_cell(c: Vector2i) -> void:
	var r: Array = _bank_corners(c)
	var ys: Array = r[0]
	var floor_y := _height(c) / 2.0
	var top: float = ys.max()
	if top <= floor_y:
		return
	var tex: int = _slope_tex(r[1], top)
	var face_tex: int = GridWorld.Tex.DIRT if r[1] else GridWorld.Tex.EARTH_SIDE
	var pts := []
	for k in 4:
		pts.append(Vector3(c.x + CORNERS[k].x, ys[k], c.y + CORNERS[k].y))
	# Split along the diagonal through the corner that differs from the
	# other three: a hip down an outside corner (both halves sloping, as on
	# a pyramid), a valley in an inside one. Beside a diagonal cut, the
	# other way, so the slope ends on the diagonal and the rest is flat.
	var tris: Array = [[0, 1, 2], [0, 2, 3]]
	for k in 4:
		var others: Array = [ys[(k + 1) % 4], ys[(k + 2) % 4], ys[(k + 3) % 4]]
		if is_equal_approx(others[0], others[1]) and is_equal_approx(others[1], others[2]) \
				and not is_equal_approx(ys[k], others[0]):
			var through := k % 2 == 0
			if r[2] and ys[k] > others[0]:
				through = not through
			tris = [[0, 1, 2], [0, 2, 3]] if through else [[0, 1, 3], [1, 2, 3]]
	for t in tris:
		var tri := [pts[t[0]], pts[t[1]], pts[t[2]]]
		if tri[0].y <= floor_y and tri[1].y <= floor_y and tri[2].y <= floor_y:
			continue  # flat at the floor: the cell's own top shows
		_slope_tri(tri, top, tex)
	for e in 4:
		var d: Vector2i = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)][e]
		_bank_side(c, d, pts[e], pts[(e + 1) % 4], face_tex)


## The texture of a slope topping out at `top` (blocks): earth on gentle
## ground, rock strata on cliffs, and rough boulders on high ground.
func _slope_tex(cliffy: bool, top: float) -> int:
	if not cliffy:
		return GridWorld.Tex.EARTH_SIDE
	return GridWorld.Tex.BANK_BOULDERS if _rocky(roundi(top * 2.0)) else GridWorld.Tex.BANK_ROCK


## A sloped triangle of rock, its strata running along the slope's level
## lines and starting from the slope's top.
func _slope_tri(tri: Array, top: float, tex: int) -> void:
	var n: Vector3 = (tri[1] - tri[0]).cross(tri[2] - tri[0]).normalized()
	if n.y < 0.0:
		n = -n
	var downhill := Vector2(n.x, n.z)
	var along := Vector2(-downhill.y, downhill.x).normalized() if downhill.length() > 0.001 else Vector2.RIGHT
	var uvs := []
	for v: Vector3 in tri:
		uvs.append(Vector2(Vector2(v.x, v.z).dot(along), top - v.y))
	faces.append([tri, n, tex, uvs])


## Closes a bank's side d (top edge a..b) down to the ground beside it
## where that's lower: an end cap where a slope stops.
func _bank_side(c: Vector2i, d: Vector2i, a: Vector3, b: Vector3, tex: int) -> void:
	var n := c + d
	var hn := _height(n)
	if hn == -99:
		return
	var low_a: float
	var low_b: float
	if hn < 0:
		low_a = WATER_SURFACE
		low_b = WATER_SURFACE
	elif _has_bank(n):
		var other: Array = _bank_corners(n)[0]
		var ka := CORNERS.find(Vector2(a.x - n.x, a.z - n.y))
		var kb := CORNERS.find(Vector2(b.x - n.x, b.z - n.y))
		low_a = other[ka]
		low_b = other[kb]
	else:
		low_a = solid[n.y * size.x + n.x] if kind[n.y * size.x + n.x] != Kind.NONE else hn / 2.0
		low_b = low_a
	if a.y < low_a - 0.001 or b.y < low_b - 0.001 or (a.y <= low_a + 0.001 and b.y <= low_b + 0.001):
		return
	var out := Vector3(d.x, 0, d.y) * FACE_OFFSET
	var top := maxf(a.y, b.y)
	var u_a := _along(Vector2(a.x, a.z), Vector2(d))
	var u_b := _along(Vector2(b.x, b.z), Vector2(d))
	var pts := [a + out, b + out]
	var uvs := [Vector2(u_a, top - a.y), Vector2(u_b, top - b.y)]
	if b.y > low_b + 0.001:
		pts.append(Vector3(b.x, low_b, b.z) + out)
		uvs.append(Vector2(u_b, top - low_b))
	if a.y > low_a + 0.001:
		pts.append(Vector3(a.x, low_a, a.z) + out)
		uvs.append(Vector2(u_a, top - low_a))
	faces.append([pts, Vector3(d.x, 0, d.y), tex, uvs])


## A rounded outer corner, Pokemon style: the quarter keeps its square
## sides, with the corner itself turned in a slight curve (CORNER_RADIUS),
## and the faces follow it round.
func _round_corner(c: Vector2i, q: Vector2i, top: float, tile: int) -> void:
	var center := Vector2(c.x + 0.5, c.y + 0.5)
	var bottom_x: float = exposed[c][Vector2i(q.x, 0)][0]
	var bottom_z: float = exposed[c][Vector2i(0, q.y)][0]
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
	var top_tex := GridWorld.Tex.ROCK_TOP if _rocky(low) else GridWorld.Tex.GRASS
	# The top: the diagonal piece, drawn with its solid corner top-left
	# (north-west), mirrored to this wedge's.
	var diag: int = GridWorld.Tex.CLIFF_DIAG if _cliffy(c) else GridWorld.Tex.EARTH_DIAG
	if _rocky(h):
		diag = GridWorld.Tex.ROCK_DIAG
	if _sloped_wedge(c):
		diag = top_tex if not _rocky(h) else GridWorld.Tex.ROCK_TOP
	var tri := [solid_corner, p0, p1]
	var tri_uvs := []
	for p in tri:
		if _sloped_wedge(c):
			tri_uvs.append(p)
		else:
			tri_uvs.append(Vector2(0.5 + (p.x - center.x) * -s.x, 0.5 + (p.y - center.y) * -s.y))
	# Out to the face, which stands a hair past the diagonal.
	var reach := -s.normalized() * FACE_OFFSET
	faces.append([[_at(tri[0], top), _at(tri[1] + reach, top), _at(tri[2] + reach, top)], Vector3.UP, diag, tri_uvs])
	if _sloped_wedge(c):
		# Between two slopes: the slope runs on along the diagonal, down to
		# the cut-off corner, starting a little in (its lip, as for banks).
		var tex := _slope_tex(_cliffy(c), top)
		_slope_tri([_at(p0, top - LIP), _at(p1, top - LIP), _at(open_corner, bottom)], top, tex)
		_face(p0, p1, -s.normalized(), top, top - LIP, tex)
		return
	if low > 0:
		faces.append([[_at(open_corner, bottom), _at(p0, bottom), _at(p1, bottom)], Vector3.UP, top_tex,
			_planar([_at(open_corner, bottom), _at(p0, bottom), _at(p1, bottom)])])
	var o := -s.normalized()
	var tex: int = GridWorld.Tex.DIRT if _cliffy(c) else GridWorld.Tex.EARTH_SIDE
	_face(p0, p1, o, top, bottom, tex)

# --- Ramps -------------------------------------------------------------------

## A ramp: the grassy slope, and on each side where the ground beside it is
## lower, the cliff's face cut to the slope and its band running down the
## slope's edge.
func _ramp(c: Vector2i) -> void:
	var r: Dictionary = ramps[c]
	var base: float = r.base
	var rise: float = r.rise
	var up := Vector2(r.up)
	var center := Vector2(c.x + 0.5, c.y + 0.5)
	var across := Vector2(-up.y, up.x)
	var cliffy := _cliffy(c)
	var band: int = GridWorld.Tex.CLIFF_EDGE if cliffy else GridWorld.Tex.EARTH_EDGE
	var joint: int = GridWorld.Tex.CLIFF_JOINT if cliffy else GridWorld.Tex.EARTH_JOINT
	var tee: int = GridWorld.Tex.CLIFF_TEE if cliffy else GridWorld.Tex.EARTH_TEE
	var ground: int = GridWorld.Tex.GRASS
	# On bare-rock high ground, rock (no grass, no contour lines).
	var rocky := _rocky(roundi((base + rise) * 2.0))
	if rocky:
		band = GridWorld.Tex.ROCK_EDGE
		joint = GridWorld.Tex.ROCK_JOINT
		tee = GridWorld.Tex.ROCK_TEE
		ground = GridWorld.Tex.ROCK_TOP
	# The slope, a quarter at a time, autotiled like any cliff top
	# (rule: ramps take part in the autotiling) and draped over the slope.
	var n: Vector3 = Vector3(-up.x * rise, 1.0, -up.y * rise).normalized()
	for q in GridWorld.DIAGONAL:
		var p: Array = _piece(c, q)
		var piece: int = p[0]
		var quarter: Array
		if piece == Piece.CENTER:
			quarter = _quarter(c, q, 0.0, ground, false, true)
		elif piece == Piece.JOINT:
			quarter = _quarter(c, q, 0.0, joint, false, false)
		elif piece == Piece.TEE:
			quarter = _quarter(c, q, 0.0, tee, false, false)
		else:
			quarter = _quarter(c, q, 0.0, band + piece, p[1], false)
		var pts := []
		var taper := piece == Piece.EDGE and Vector2(q).dot(up) < 0.0 and _meets_ground(c, q)
		for j in quarter[0].size():
			var v: Vector3 = quarter[0][j]
			var along: float = clampf((Vector2(v.x, v.z) - center).dot(up) + 0.5, 0.0, 1.0)
			pts.append(Vector3(v.x, base + rise * along, v.z))
			if taper and along < 0.01:
				# Rule: a side's band runs out at the foot, where the face
				# under it does: narrowed to nothing over the last quarter.
				quarter[3][j].y = minf(quarter[3][j].y, TAPER_END)
		quarter[0] = pts
		quarter[1] = n
		faces.append(quarter)
		if piece in [Piece.CENTER, Piece.EDGE, Piece.OUTER] and not rocky:
			_slope_lines(c, q, n)
	# The cliff's face cut to the slope, down each exposed side.
	var face_tex: int = GridWorld.Tex.DIRT if cliffy else GridWorld.Tex.EARTH_SIDE
	for side in [-1, 1]:
		var o: Vector2 = across * side
		if not _is_exposed(c, Vector2i(o)):
			continue
		var floor_h: float = exposed[c][Vector2i(o)][0]
		var a: Vector2 = center - up * 0.5 + o * 0.5
		var b: Vector2 = center + up * 0.5 + o * 0.5
		_slanted_face(a, b, o, base, base + rise, floor_h, face_tex)


## Whether the edge beside the foot quarter q of ramp c comes down to the
## ground there (the ground beside is as high as the ramp's foot).
func _meets_ground(c: Vector2i, q: Vector2i) -> bool:
	var r: Dictionary = ramps[c]
	var side := Vector2i(q.x, 0) if r.up.x == 0 else Vector2i(0, q.y)
	return _is_exposed(c, side) and not exposed[c][side][1] \
		and exposed[c][side][0] >= r.base - 0.001


## Contour lines across a ramp's climb, laid over the quarter of c toward
## q so the slope reads as one; short of any cliff band along its sides.
func _slope_lines(c: Vector2i, q: Vector2i, n: Vector3) -> void:
	var r: Dictionary = ramps[c]
	var up := Vector2(r.up)
	var center := Vector2(c.x + 0.5, c.y + 0.5)
	var reach := Vector2(0.5, 0.5)
	if _is_exposed(c, Vector2i(q.x, 0)):
		reach.x -= BAND
	if _is_exposed(c, Vector2i(0, q.y)):
		reach.y -= BAND
	var pts := []
	var uvs := []
	for k in [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]:
		var p: Vector2 = center + Vector2(k.x * q.x * reach.x, k.y * q.y * reach.y)
		var along: float = clampf((p - center).dot(up) + 0.5, 0.0, 1.0)
		pts.append(Vector3(p.x, r.base + r.rise * along + LIFT, p.y))
		# Tile rows run across the climb.
		uvs.append(Vector2(p.y, p.x) if up.x != 0 else p)
	faces.append([pts, n, GridWorld.Tex.SLOPE_LINES, uvs])


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
	var u1 := _along(b, o)
	faces.append([[_at(a + out, top), _at(b + out, top), _at(b + out, bottom), _at(a + out, bottom)],
		Vector3(o.x, 0, o.y), tex,
		[Vector2(u0, 0), Vector2(u1, 0), Vector2(u1, top - bottom), Vector2(u0, top - bottom)]])


static func _at(p: Vector2, y: float) -> Vector3:
	return Vector3(p.x, y, p.y)


## Where a texture starts along an edge from p, in world units, so
## neighbouring edges' tiles line up (diagonal ones too).
static func _along(p: Vector2, o: Vector2) -> float:
	return p.dot(Vector2(-o.y, o.x))


## Whole-cell tile UVs projected straight down.
static func _planar(pts: Array) -> Array:
	var uvs := []
	for p in pts:
		uvs.append(Vector2(p.x, p.z))
	return uvs
