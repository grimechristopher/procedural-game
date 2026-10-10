class_name GridWorld
extends GridMap

## Builds its own MeshLibrary of basic blocks and generates a tile map.
##
## Layer y = -1 is ground; tiles stack on layers 0 and up. Movement uses grid
## coords (x, z) plus the layer of the tile you stand on, since one column can
## hold several surfaces (e.g. ground under a bridge and the bridge deck).
##
## Movement rules (see find_move):
## - Walk between two surfaces when their shared edge is at the same height,
##   so height only changes on ramps and stairs, which can only be entered
##   from their low or high end.
## - Diagonal walks need flat ground at one height, with no corner cutting.
##   Wedges (corner-cut blocks) are the exception: you can pass the open
##   corner of a wedge beside you, or walk over its solid corner on top.
## - Wedges and corner slopes are solid; you can't stand in their cell.
## - A surface needs HEADROOM clear above it to be stood on.

enum Tile {
	GROUND, FULL, HALF, RAMP, HALF_RAMP, STAIRS, BRIDGE,
	WEDGE, HALF_WEDGE,
	CORNER_OUTER, CORNER_INNER, HALF_CORNER_OUTER, HALF_CORNER_INNER,
	PATH, FLOWERS,
	# Same shapes as FULL and WEDGE, with dirt sides for blocks buried under others.
	FULL_DIRT, WEDGE_DIRT,
	# Same shapes as RAMP and HALF_RAMP, grassed over, for the sides of mounds.
	HILL_RAMP, HALF_HILL_RAMP,
}

## Tiles in assets/tileset.png (see tools/make_tileset.py), left to right,
## top to bottom.
enum Tex { GRASS, GRASS_SIDE, DIRT, PATH, FLOWERS, STONE, PLANKS }
const TEX_COLS := 4
const TEX_ROWS := 2

const TILESET := preload("res://assets/tileset.png")

const GROUND_LAYER := -1
const TOP_LAYER := 3
const STAIR_STEPS := 4
const HEADROOM := 1.0
const BRIDGE_THICKNESS := 0.15
const EPS := 0.001
const NO_MOVE := -999

@export var map_size := Vector2i(28, 28)
@export var platform_count := 10
@export var bridge_count := 3
@export var map_seed := 1

var spawn_cell := Vector2i.ZERO


func _ready() -> void:
	cell_size = Vector3.ONE
	cell_center_y = false
	mesh_library = _build_mesh_library()
	generate(map_seed)


# --- Generation -------------------------------------------------------------

func generate(new_seed: int) -> void:
	clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = new_seed
	spawn_cell = map_size / 2

	var reserved := {}
	for x in range(spawn_cell.x - 1, spawn_cell.x + 2):
		for z in range(spawn_cell.y - 1, spawn_cell.y + 2):
			reserved[Vector2i(x, z)] = true

	for x in map_size.x:
		for z in map_size.y:
			set_cell_item(Vector3i(x, GROUND_LAYER, z), Tile.GROUND)
			if x == 0 or z == 0 or x == map_size.x - 1 or z == map_size.y - 1:
				set_cell_item(Vector3i(x, 0, z), Tile.FULL)
				set_cell_item(Vector3i(x, 1, z), Tile.FULL)

	var towers: Array[Rect2i] = []
	var approaches: Array[Vector2i] = []
	var placed := 0
	for attempt in platform_count * 10:
		if placed >= platform_count:
			break
		if _try_place_platform(rng, reserved, towers, approaches):
			placed += 1
	_place_bridges(rng, towers)
	_decorate_ground(rng, approaches)
	_bury_covered_blocks()


## Swaps grass-edged blocks for dirt ones where something sits on top, so
## stacks show one grass edge at the top instead of one per layer.
func _bury_covered_blocks() -> void:
	for pos in get_used_cells():
		var item := get_cell_item(pos)
		if item != Tile.FULL and item != Tile.WEDGE:
			continue
		var above := get_cell_item(pos + Vector3i.UP)
		if above == INVALID_CELL_ITEM or above == Tile.BRIDGE:
			continue
		if item == Tile.FULL:
			set_cell_item(pos, Tile.FULL_DIRT)
		else:
			set_cell_item(pos, Tile.WEDGE_DIRT, get_cell_item_orientation(pos))


## Scatters flowers, then wears dirt paths from spawn to each way up.
func _decorate_ground(rng: RandomNumberGenerator, targets: Array[Vector2i]) -> void:
	for x in range(1, map_size.x - 1):
		for z in range(1, map_size.y - 1):
			if rng.randf() < 0.08:
				set_cell_item(Vector3i(x, GROUND_LAYER, z), Tile.FLOWERS)

	# Breadth-first over ground-level steps, so paths go around obstacles.
	var came_from := { spawn_cell: spawn_cell }
	var frontier: Array[Vector2i] = [spawn_cell]
	while not frontier.is_empty():
		var c: Vector2i = frontier.pop_front()
		for d in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			if not came_from.has(c + d) and find_move(c, GROUND_LAYER, d) == GROUND_LAYER:
				came_from[c + d] = c
				frontier.append(c + d)
	for target in targets:
		if not came_from.has(target):
			continue
		var c := target
		while c != spawn_cell:
			set_cell_item(Vector3i(c.x, GROUND_LAYER, c.y), Tile.PATH)
			c = came_from[c]
		set_cell_item(Vector3i(c.x, GROUND_LAYER, c.y), Tile.PATH)


## Places a rectangular platform: half height, full height, or a two-high
## tower, each reached by a ramp or staircase (stacked for towers); or a
## mound with ramps on every side and corner slopes between them.
## Platforms 3x3 and up may get their corners cut diagonally with wedges.
## Keeps a one-cell walkway around everything so nothing gets sealed off.
func _try_place_platform(rng: RandomNumberGenerator, reserved: Dictionary, towers: Array[Rect2i],
		approaches: Array[Vector2i]) -> bool:
	var roll := rng.randf()
	var kind: int = 0 if roll < 0.25 else (1 if roll < 0.5 else (2 if roll < 0.75 else 3))
	var mound := kind == 3
	var half := kind == 0 or (mound and rng.randf() < 0.5)
	var size := Vector2i(rng.randi_range(1, 3), rng.randi_range(1, 3)) if mound \
		else Vector2i(rng.randi_range(2, 5), rng.randi_range(2, 5))
	var rect := Rect2i(
		Vector2i(rng.randi_range(5, map_size.x - size.x - 5), rng.randi_range(5, map_size.y - size.y - 5)),
		size)

	# Slope cells run outward from the middle of one side, rising toward the platform.
	# (Mounds have slopes all round; this just picks which side the path comes in.)
	var up_dir: Vector2i = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT][rng.randi() % 4]
	var mid := rect.position + rect.size / 2
	var slope := Vector2i(
		mid.x if up_dir.x == 0 else (rect.position.x - 1 if up_dir.x > 0 else rect.end.x),
		mid.y if up_dir.y == 0 else (rect.position.y - 1 if up_dir.y > 0 else rect.end.y))
	var slope_cells: Array = [slope] if kind < 2 or mound else [slope, slope - up_dir]
	var approach: Vector2i = slope_cells.back() - up_dir
	var claim: Array = [] if mound else slope_cells + [approach]
	var footprint := rect.grow(2 if mound else 1)
	for x in range(footprint.position.x, footprint.end.x):
		for z in range(footprint.position.y, footprint.end.y):
			claim.append(Vector2i(x, z))
	for c in claim:
		if reserved.has(c):
			return false

	var block: Tile = Tile.HALF if half else Tile.FULL
	var layers := 2 if kind == 2 else 1
	for layer in layers:
		for x in range(rect.position.x, rect.end.x):
			for z in range(rect.position.y, rect.end.y):
				set_cell_item(Vector3i(x, layer, z), block)

	if mound:
		_surround_with_slopes(rect, half)
	else:
		var slope_tile: Tile = Tile.HALF_RAMP if half else (Tile.STAIRS if rng.randf() < 0.5 else Tile.RAMP)
		if kind == 2:
			set_cell_item(Vector3i(slope.x, 0, slope.y), Tile.FULL)
			set_slope(slope, 1, slope_tile, up_dir)
			set_slope(slope - up_dir, 0, slope_tile, up_dir)
			towers.append(rect)
		else:
			set_slope(slope, 0, slope_tile, up_dir)
		if size.x >= 3 and size.y >= 3 and rng.randf() < 0.6:
			_cut_corners(rect, layers, Tile.HALF_WEDGE if half else Tile.WEDGE)

	for c in claim:
		reserved[c] = true
	approaches.append(approach)
	return true


## Replaces a platform's corner cells with wedges, solid side inward.
func _cut_corners(rect: Rect2i, layers: int, wedge: Tile) -> void:
	for corner in _rect_corners(rect):
		for layer in layers:
			set_corner(corner.cell, layer, wedge, corner.inward)


## Rings a platform with ramps rising toward it and outer corner slopes.
func _surround_with_slopes(rect: Rect2i, half: bool) -> void:
	var ramp := Tile.HALF_HILL_RAMP if half else Tile.HILL_RAMP
	var ring := rect.grow(1)
	for x in range(rect.position.x, rect.end.x):
		set_slope(Vector2i(x, ring.position.y), 0, ramp, Vector2i.DOWN)
		set_slope(Vector2i(x, ring.end.y - 1), 0, ramp, Vector2i.UP)
	for z in range(rect.position.y, rect.end.y):
		set_slope(Vector2i(ring.position.x, z), 0, ramp, Vector2i.RIGHT)
		set_slope(Vector2i(ring.end.x - 1, z), 0, ramp, Vector2i.LEFT)
	for corner in _rect_corners(ring):
		set_corner(corner.cell, 0, Tile.HALF_CORNER_OUTER if half else Tile.CORNER_OUTER, corner.inward)


## The four corner cells of a rect, each with the diagonal pointing inward.
static func _rect_corners(rect: Rect2i) -> Array:
	var lo := rect.position
	var hi := rect.end - Vector2i.ONE
	return [
		{ cell = lo, inward = Vector2i(1, 1) },
		{ cell = Vector2i(hi.x, lo.y), inward = Vector2i(-1, 1) },
		{ cell = Vector2i(lo.x, hi.y), inward = Vector2i(1, -1) },
		{ cell = hi, inward = Vector2i(-1, -1) },
	]


## Spans bridges between pairs of towers that line up across open ground.
## Decks sit at the top of layer 1, leaving headroom to walk underneath.
func _place_bridges(rng: RandomNumberGenerator, towers: Array[Rect2i]) -> void:
	if towers.size() < 2:
		return
	var linked := {}
	var placed := 0
	for attempt in bridge_count * 20:
		if placed >= bridge_count:
			return
		var a := towers[rng.randi() % towers.size()]
		var b := towers[rng.randi() % towers.size()]
		if a == b or linked.has([a, b]):
			continue
		var span := _bridge_span(rng, a, b)
		if span.is_empty():
			continue
		for c in span:
			set_cell_item(Vector3i(c.x, 1, c.y), Tile.BRIDGE)
		linked[[a, b]] = true
		linked[[b, a]] = true
		placed += 1


## Straight run of empty ground cells between two rects, or [] if none.
func _bridge_span(rng: RandomNumberGenerator, a: Rect2i, b: Rect2i) -> Array:
	for axis in [0, 1]:
		var other: int = 1 - axis
		var lo := maxi(a.position[other], b.position[other])
		var hi := mini(a.end[other], b.end[other])
		if lo >= hi:
			continue
		var first: Rect2i = a if a.position[axis] < b.position[axis] else b
		var second: Rect2i = b if first == a else a
		if first.end[axis] >= second.position[axis]:
			continue
		var line := rng.randi_range(lo, hi - 1)
		var near_end: Vector2i = Vector2i(first.end[axis] - 1, line) if axis == 0 else Vector2i(line, first.end[axis] - 1)
		var far_end: Vector2i = Vector2i(second.position[axis], line) if axis == 0 else Vector2i(line, second.position[axis])
		if get_cell_item(Vector3i(near_end.x, 1, near_end.y)) != Tile.FULL \
				or get_cell_item(Vector3i(far_end.x, 1, far_end.y)) != Tile.FULL:
			return []
		var span := []
		for i in range(first.end[axis], second.position[axis]):
			var c: Vector2i = Vector2i(i, line) if axis == 0 else Vector2i(line, i)
			for layer in range(0, TOP_LAYER + 1):
				if get_cell_item(Vector3i(c.x, layer, c.y)) != INVALID_CELL_ITEM:
					return []
			span.append(c)
		return span
	return []


## Places a sloped tile so that it rises toward up_dir.
func set_slope(cell: Vector2i, layer: int, tile: Tile, up_dir: Vector2i) -> void:
	var basis := Basis(Vector3.UP, atan2(-up_dir.x, -up_dir.y))
	set_cell_item(Vector3i(cell.x, layer, cell.y), tile, get_orthogonal_index_from_basis(basis))


## Places a wedge or corner slope with its solid (or high) corner toward
## diagonal, e.g. (1, 1) for the +x +z corner.
func set_corner(cell: Vector2i, layer: int, tile: Tile, diagonal: Vector2i) -> void:
	# Models put that corner at local (-x, -z): 45 degrees off forward.
	var basis := Basis(Vector3.UP, atan2(-diagonal.x, -diagonal.y) - PI / 4.0)
	set_cell_item(Vector3i(cell.x, layer, cell.y), tile, get_orthogonal_index_from_basis(basis))


# --- Movement queries -------------------------------------------------------

## Layer of the surface a step from (cell, layer) in dir lands on,
## or NO_MOVE if the step is blocked.
func find_move(cell: Vector2i, layer: int, dir: Vector2i) -> int:
	var s := _surface(cell, layer)
	if s.is_empty():
		return NO_MOVE
	var to := cell + dir

	if dir.x == 0 or dir.y == 0:
		var e := _edge(s, dir)
		if not is_nan(e):
			for t in _surfaces(to):
				if is_equal_approx(_edge(t, -dir), e):
					return t.layer
		return NO_MOVE

	if _rise(s.tile) > 0.0:
		return NO_MOVE
	var h := _center(s)
	var dest := _flat_surface_at(to, h)
	if dest.is_empty() \
			or not _corner_passable(cell + Vector2i(dir.x, 0), Vector2i(-dir.x, dir.y), h) \
			or not _corner_passable(cell + Vector2i(0, dir.y), Vector2i(dir.x, -dir.y), h):
		return NO_MOVE
	return dest.layer


func edge_height(cell: Vector2i, layer: int, dir: Vector2i) -> float:
	return _edge(_surface(cell, layer), dir)


func center_height(cell: Vector2i, layer: int) -> float:
	var s := _surface(cell, layer)
	return 0.0 if s.is_empty() else _center(s)


## World-space position of a surface's center.
func cell_to_world(cell: Vector2i, layer: int) -> Vector3:
	return Vector3(cell.x + 0.5, center_height(cell, layer), cell.y + 0.5) * cell_size


## Standable surfaces in a column, bottom to top.
func _surfaces(cell: Vector2i) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for layer in range(GROUND_LAYER, TOP_LAYER + 1):
		var s := _surface(cell, layer)
		if not s.is_empty():
			out.append(s)
	return out


## The tile at (cell, layer) as a surface, or {} if there's no tile there or
## something above it leaves less than HEADROOM.
func _surface(cell: Vector2i, layer: int) -> Dictionary:
	if cell.x < 0 or cell.y < 0 or cell.x >= map_size.x or cell.y >= map_size.y:
		return {}
	var pos := Vector3i(cell.x, layer, cell.y)
	var item := get_cell_item(pos)
	if item == INVALID_CELL_ITEM or _is_wedge(item) or _is_corner_slope(item):
		return {}
	var top := _span(item, layer).y
	for above in range(layer + 1, TOP_LAYER + 1):
		var other := get_cell_item(Vector3i(cell.x, above, cell.y))
		if other != INVALID_CELL_ITEM:
			if _span(other, above).x < top + HEADROOM - EPS:
				return {}
			break
	var fwd := get_cell_item_basis(pos) * Vector3.FORWARD
	return { tile = item, layer = layer, up = Vector2i(roundi(fwd.x), roundi(fwd.z)) }


## Whether a diagonal walk at height h can pass the given corner of cell
## (corner as a sign vector from the cell's center).
func _corner_passable(cell: Vector2i, corner: Vector2i, h: float) -> bool:
	if not _flat_surface_at(cell, h).is_empty():
		return true
	for layer in range(GROUND_LAYER + 1, TOP_LAYER + 1):
		var item := get_cell_item(Vector3i(cell.x, layer, cell.y))
		if not _is_wedge(item):
			continue
		var span := _span(item, layer)
		var solid := _corner_dir(cell, layer)
		# Walking over the wedge's solid corner on top of it.
		if is_equal_approx(span.y, h) and corner == solid:
			return true
		# Walking past its open corner, on the floor it stands on.
		var below := get_cell_item(Vector3i(cell.x, layer - 1, cell.y))
		if corner == -solid and is_equal_approx(span.x, h) and below != INVALID_CELL_ITEM \
				and is_equal_approx(_span(below, layer - 1).y, h):
			return true
	return false


func _corner_dir(cell: Vector2i, layer: int) -> Vector2i:
	var d := get_cell_item_basis(Vector3i(cell.x, layer, cell.y)) * Vector3(-1, 0, -1)
	return Vector2i(roundi(d.x), roundi(d.z))


func _flat_surface_at(cell: Vector2i, h: float) -> Dictionary:
	for s in _surfaces(cell):
		if _rise(s.tile) == 0.0 and is_equal_approx(_center(s), h):
			return s
	return {}


## Surface height at the edge of s facing dir, or NAN if it can't be
## entered or left that way (e.g. the side of a ramp).
func _edge(s: Dictionary, dir: Vector2i) -> float:
	if s.is_empty():
		return NAN
	var rise := _rise(s.tile)
	if rise == 0.0:
		return _span(s.tile, s.layer).y
	if dir == s.up:
		return s.layer + rise
	if dir == -s.up:
		return float(s.layer)
	return NAN


func _center(s: Dictionary) -> float:
	var rise := _rise(s.tile)
	return s.layer + rise / 2.0 if rise > 0.0 else _span(s.tile, s.layer).y


## Vertical extent (bottom, top) a tile occupies in world space.
static func _is_wedge(tile: int) -> bool:
	return tile == Tile.WEDGE or tile == Tile.HALF_WEDGE or tile == Tile.WEDGE_DIRT


static func _is_corner_slope(tile: int) -> bool:
	return tile in [Tile.CORNER_OUTER, Tile.CORNER_INNER, Tile.HALF_CORNER_OUTER, Tile.HALF_CORNER_INNER]


static func _span(tile: int, layer: int) -> Vector2:
	match tile:
		Tile.HALF, Tile.HALF_RAMP, Tile.HALF_HILL_RAMP, Tile.HALF_WEDGE, Tile.HALF_CORNER_OUTER, Tile.HALF_CORNER_INNER:
			return Vector2(layer, layer + 0.5)
		Tile.BRIDGE: return Vector2(layer + 1.0 - BRIDGE_THICKNESS, layer + 1.0)
	return Vector2(layer, layer + 1.0)


static func _rise(tile: int) -> float:
	match tile:
		Tile.RAMP, Tile.HILL_RAMP, Tile.STAIRS: return 1.0
		Tile.HALF_RAMP, Tile.HALF_HILL_RAMP: return 0.5
	return 0.0


# --- Meshes -----------------------------------------------------------------
# All meshes have their origin at the bottom center of the cell. Sloped tiles
# are modeled rising toward -Z; GridMap orientation rotates them.

func _build_mesh_library() -> MeshLibrary:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = TILESET
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST

	# Which tileset tile each kind of face uses.
	var grass_block := { top = Tex.GRASS, side = Tex.GRASS_SIDE, slope = Tex.GRASS }
	var ramp := { top = Tex.PATH, side = Tex.DIRT, slope = Tex.PATH }
	var hill := { top = Tex.GRASS, side = Tex.DIRT, slope = Tex.GRASS }
	var full_box := _box_faces(Vector3(-0.5, 0, -0.5), Vector3(0.5, 1, 0.5))

	var lib := MeshLibrary.new()
	var items := [
		[Tile.GROUND, "Ground", full_box, grass_block],
		[Tile.PATH, "Path", full_box, { top = Tex.PATH, side = Tex.DIRT, slope = Tex.PATH }],
		[Tile.FLOWERS, "Flowers", full_box, { top = Tex.FLOWERS, side = Tex.GRASS_SIDE, slope = Tex.GRASS }],
		[Tile.FULL, "Full", full_box, grass_block],
		[Tile.FULL_DIRT, "FullDirt", full_box, { top = Tex.GRASS, side = Tex.DIRT, slope = Tex.GRASS }],
		[Tile.WEDGE_DIRT, "WedgeDirt", _wedge_faces(1.0), { top = Tex.GRASS, side = Tex.DIRT, slope = Tex.GRASS }],
		[Tile.HALF, "Half", _box_faces(Vector3(-0.5, 0, -0.5), Vector3(0.5, 0.5, 0.5)), grass_block],
		[Tile.RAMP, "Ramp", _ramp_faces(1.0), ramp],
		[Tile.HALF_RAMP, "HalfRamp", _ramp_faces(0.5), ramp],
		[Tile.HILL_RAMP, "HillRamp", _ramp_faces(1.0), hill],
		[Tile.HALF_HILL_RAMP, "HalfHillRamp", _ramp_faces(0.5), hill],
		[Tile.STAIRS, "Stairs", _stairs_faces(1.0, STAIR_STEPS), { top = Tex.STONE, side = Tex.STONE, slope = Tex.STONE }],
		[Tile.WEDGE, "Wedge", _wedge_faces(1.0), grass_block],
		[Tile.HALF_WEDGE, "HalfWedge", _wedge_faces(0.5), grass_block],
		[Tile.CORNER_OUTER, "CornerOuter", _outer_corner_faces(1.0), hill],
		[Tile.CORNER_INNER, "CornerInner", _inner_corner_faces(1.0), hill],
		[Tile.HALF_CORNER_OUTER, "HalfCornerOuter", _outer_corner_faces(0.5), hill],
		[Tile.HALF_CORNER_INNER, "HalfCornerInner", _inner_corner_faces(0.5), hill],
		[Tile.BRIDGE, "Bridge", _box_faces(Vector3(-0.5, 1.0 - BRIDGE_THICKNESS, -0.5), Vector3(0.5, 1, 0.5)),
			{ top = Tex.PLANKS, side = Tex.PLANKS, slope = Tex.PLANKS }],
	]
	for item in items:
		lib.create_item(item[0])
		lib.set_item_name(item[0], item[1])
		lib.set_item_mesh(item[0], _build_mesh(item[2], item[3], mat))
	return lib


func _build_mesh(faces: Array, skin: Dictionary, mat: Material) -> ArrayMesh:
	var top_y := 0.0
	for face in faces:
		for p in face[0]:
			top_y = maxf(top_y, p.y)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for face in faces:
		var pts: Array = face[0]
		var n: Vector3 = face[1]
		var tex: int = skin.top if n.y > 0.99 else (skin.slope if n.y > 0.1 else (Tex.DIRT if n.y < -0.5 else skin.side))
		for i in range(1, pts.size() - 1):
			var a: Vector3 = pts[0]
			var b: Vector3 = pts[i]
			var c: Vector3 = pts[i + 1]
			# Godot treats clockwise as front-facing.
			if (b - a).cross(c - a).dot(n) > 0.0:
				var tmp := b
				b = c
				c = tmp
			for v in [a, b, c]:
				st.set_normal(n)
				st.set_uv(_atlas_uv(tex, _face_uv(v, n, top_y)))
				st.add_vertex(v)
	st.set_material(mat)
	return st.commit()


## Planar UVs in 0..1: tops and slopes project straight down; walls run
## along the wall, measured down from the top of the piece, so grass edges
## sit at the top even on half-height blocks.
static func _face_uv(p: Vector3, n: Vector3, top_y: float) -> Vector2:
	if absf(n.y) > 0.1:
		return Vector2(p.x + 0.5, p.z + 0.5)
	var along := Vector3.UP.cross(n).normalized()
	return Vector2(p.dot(along) + 0.5, top_y - p.y)


static func _atlas_uv(tex: int, uv: Vector2) -> Vector2:
	# Inset half a texel so nearest sampling never bleeds into a neighbor tile.
	var inset := 0.5 / 16.0
	uv = uv.clamp(Vector2(inset, inset), Vector2(1.0 - inset, 1.0 - inset))
	return Vector2((tex % TEX_COLS + uv.x) / TEX_COLS, (tex / TEX_COLS + uv.y) / TEX_ROWS)


## Each face is [points (convex, in order), outward normal].
static func _box_faces(lo: Vector3, hi: Vector3) -> Array:
	return [
		[[Vector3(lo.x, hi.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(hi.x, hi.y, hi.z), Vector3(lo.x, hi.y, hi.z)], Vector3.UP],
		[[Vector3(lo.x, lo.y, lo.z), Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, lo.y, hi.z), Vector3(lo.x, lo.y, hi.z)], Vector3.DOWN],
		[[Vector3(lo.x, lo.y, hi.z), Vector3(hi.x, lo.y, hi.z), Vector3(hi.x, hi.y, hi.z), Vector3(lo.x, hi.y, hi.z)], Vector3.BACK],
		[[Vector3(lo.x, lo.y, lo.z), Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(lo.x, hi.y, lo.z)], Vector3.FORWARD],
		[[Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, lo.y, hi.z), Vector3(hi.x, hi.y, hi.z), Vector3(hi.x, hi.y, lo.z)], Vector3.RIGHT],
		[[Vector3(lo.x, lo.y, lo.z), Vector3(lo.x, lo.y, hi.z), Vector3(lo.x, hi.y, hi.z), Vector3(lo.x, hi.y, lo.z)], Vector3.LEFT],
	]


static func _ramp_faces(rise: float) -> Array:
	var slope_n := Vector3(0, 1, rise).normalized()
	return [
		[[Vector3(-0.5, 0, 0.5), Vector3(0.5, 0, 0.5), Vector3(0.5, rise, -0.5), Vector3(-0.5, rise, -0.5)], slope_n],
		[[Vector3(-0.5, 0, -0.5), Vector3(0.5, 0, -0.5), Vector3(0.5, 0, 0.5), Vector3(-0.5, 0, 0.5)], Vector3.DOWN],
		[[Vector3(-0.5, 0, -0.5), Vector3(0.5, 0, -0.5), Vector3(0.5, rise, -0.5), Vector3(-0.5, rise, -0.5)], Vector3.FORWARD],
		[[Vector3(0.5, 0, 0.5), Vector3(0.5, 0, -0.5), Vector3(0.5, rise, -0.5)], Vector3.RIGHT],
		[[Vector3(-0.5, 0, 0.5), Vector3(-0.5, 0, -0.5), Vector3(-0.5, rise, -0.5)], Vector3.LEFT],
	]


## Full cell cut corner to corner, keeping the (-x, -z) half.
static func _wedge_faces(h: float) -> Array:
	return [
		[[Vector3(-0.5, 0, -0.5), Vector3(0.5, 0, -0.5), Vector3(-0.5, 0, 0.5)], Vector3.DOWN],
		[[Vector3(-0.5, h, -0.5), Vector3(0.5, h, -0.5), Vector3(-0.5, h, 0.5)], Vector3.UP],
		[[Vector3(-0.5, 0, -0.5), Vector3(-0.5, 0, 0.5), Vector3(-0.5, h, 0.5), Vector3(-0.5, h, -0.5)], Vector3.LEFT],
		[[Vector3(-0.5, 0, -0.5), Vector3(0.5, 0, -0.5), Vector3(0.5, h, -0.5), Vector3(-0.5, h, -0.5)], Vector3.FORWARD],
		[[Vector3(0.5, 0, -0.5), Vector3(-0.5, 0, 0.5), Vector3(-0.5, h, 0.5), Vector3(0.5, h, -0.5)], Vector3(1, 0, 1).normalized()],
	]


## Where two ramps meet at an outside corner: peaks at the (-x, -z) corner.
static func _outer_corner_faces(rise: float) -> Array:
	var peak := Vector3(-0.5, rise, -0.5)
	return [
		[[Vector3(-0.5, 0, -0.5), Vector3(0.5, 0, -0.5), Vector3(0.5, 0, 0.5), Vector3(-0.5, 0, 0.5)], Vector3.DOWN],
		[[Vector3(-0.5, 0, -0.5), Vector3(-0.5, 0, 0.5), peak], Vector3.LEFT],
		[[Vector3(-0.5, 0, -0.5), Vector3(0.5, 0, -0.5), peak], Vector3.FORWARD],
		_upward_tri(peak, Vector3(0.5, 0, -0.5), Vector3(0.5, 0, 0.5)),
		_upward_tri(peak, Vector3(0.5, 0, 0.5), Vector3(-0.5, 0, 0.5)),
	]


## Where two ramps meet at an inside corner: low only at the (+x, +z) corner.
static func _inner_corner_faces(rise: float) -> Array:
	return [
		[[Vector3(-0.5, 0, -0.5), Vector3(0.5, 0, -0.5), Vector3(0.5, 0, 0.5), Vector3(-0.5, 0, 0.5)], Vector3.DOWN],
		[[Vector3(-0.5, 0, -0.5), Vector3(-0.5, 0, 0.5), Vector3(-0.5, rise, 0.5), Vector3(-0.5, rise, -0.5)], Vector3.LEFT],
		[[Vector3(-0.5, 0, -0.5), Vector3(0.5, 0, -0.5), Vector3(0.5, rise, -0.5), Vector3(-0.5, rise, -0.5)], Vector3.FORWARD],
		[[Vector3(0.5, 0, -0.5), Vector3(0.5, rise, -0.5), Vector3(0.5, 0, 0.5)], Vector3.RIGHT],
		[[Vector3(-0.5, 0, 0.5), Vector3(-0.5, rise, 0.5), Vector3(0.5, 0, 0.5)], Vector3.BACK],
		[[Vector3(-0.5, rise, -0.5), Vector3(-0.5, rise, 0.5), Vector3(0.5, rise, -0.5)], Vector3.UP],
		_upward_tri(Vector3(-0.5, rise, 0.5), Vector3(0.5, rise, -0.5), Vector3(0.5, 0, 0.5)),
	]


static func _upward_tri(a: Vector3, b: Vector3, c: Vector3) -> Array:
	var n := (b - a).cross(c - a).normalized()
	return [[a, b, c], n if n.y > 0.0 else -n]


static func _stairs_faces(rise: float, steps: int) -> Array:
	var faces := []
	var depth := 1.0 / steps
	for i in steps:
		var z_front := 0.5 - i * depth
		faces.append_array(_box_faces(
			Vector3(-0.5, 0, z_front - depth),
			Vector3(0.5, rise * (i + 1) / steps, z_front)))
	return faces
