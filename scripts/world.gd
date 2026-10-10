class_name GridWorld
extends GridMap

## Builds its own MeshLibrary of basic blocks and generates a tile map.
##
## Layer y = -1 is ground; tiles stack on layers 0 and up. Movement uses grid
## coords (x, z) plus the layer of the tile you stand on, since one column can
## hold several surfaces (e.g. ground under a bridge and the bridge deck).
##
## Movement rules (see find_move):
## - Walk between two surfaces when their shared edge is at the same height.
##   Height changes going up only happen on ramps and stairs, which can only
##   be entered from their low or high end.
## - Hop down off a flat ledge onto flat ground up to max_drop below, in any
##   of the 8 directions. Hops are one-way.
## - Diagonal walks need flat ground at one height, with no corner cutting.
## - A surface needs HEADROOM clear above it to be stood on.

enum Tile { GROUND, FULL, HALF, RAMP, HALF_RAMP, STAIRS, BRIDGE }

const GROUND_LAYER := -1
const TOP_LAYER := 3
const STAIR_STEPS := 4
const HEADROOM := 1.0
const BRIDGE_THICKNESS := 0.15
const EPS := 0.001

@export var map_size := Vector2i(28, 28)
@export var platform_count := 10
@export var bridge_count := 3
@export var max_drop := 1.0
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
	var placed := 0
	for attempt in platform_count * 10:
		if placed >= platform_count:
			break
		if _try_place_platform(rng, reserved, towers):
			placed += 1
	_place_bridges(rng, towers)


## Places a rectangular platform with a ramp or staircase leading up to it:
## half height, full height, or a two-high tower reached by stacked stairs.
## Keeps a one-cell walkway around every platform so nothing gets sealed off.
func _try_place_platform(rng: RandomNumberGenerator, reserved: Dictionary, towers: Array[Rect2i]) -> bool:
	var size := Vector2i(rng.randi_range(2, 5), rng.randi_range(2, 5))
	var rect := Rect2i(
		Vector2i(rng.randi_range(4, map_size.x - size.x - 4), rng.randi_range(4, map_size.y - size.y - 4)),
		size)
	var roll := rng.randf()
	var tier: int = 0 if roll < 0.3 else (1 if roll < 0.65 else 2)

	# Slope cells run outward from the middle of one side, rising toward the platform.
	var up_dir: Vector2i = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT][rng.randi() % 4]
	var mid := rect.position + rect.size / 2
	var slope := Vector2i(
		mid.x if up_dir.x == 0 else (rect.position.x - 1 if up_dir.x > 0 else rect.end.x),
		mid.y if up_dir.y == 0 else (rect.position.y - 1 if up_dir.y > 0 else rect.end.y))
	var slope_cells: Array = [slope] if tier < 2 else [slope, slope - up_dir]
	var approach: Vector2i = slope_cells.back() - up_dir

	var footprint := rect.grow(1)
	var claim: Array = slope_cells + [approach]
	for x in range(footprint.position.x, footprint.end.x):
		for z in range(footprint.position.y, footprint.end.y):
			claim.append(Vector2i(x, z))
	for c in claim:
		if reserved.has(c):
			return false

	var block: Tile = Tile.HALF if tier == 0 else Tile.FULL
	for layer in (2 if tier == 2 else 1):
		for x in range(rect.position.x, rect.end.x):
			for z in range(rect.position.y, rect.end.y):
				set_cell_item(Vector3i(x, layer, z), block)
	var kind: Tile = Tile.HALF_RAMP if tier == 0 else (Tile.STAIRS if rng.randf() < 0.5 else Tile.RAMP)
	if tier == 2:
		set_cell_item(Vector3i(slope.x, 0, slope.y), Tile.FULL)
		set_slope(slope, 1, kind, up_dir)
		set_slope(slope - up_dir, 0, kind, up_dir)
		towers.append(rect)
	else:
		set_slope(slope, 0, kind, up_dir)

	for c in claim:
		reserved[c] = true
	return true


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


# --- Movement queries -------------------------------------------------------

## Where a step from the surface at (cell, layer) in dir lands.
## Returns { layer, hop } or {} if the step is blocked.
func find_move(cell: Vector2i, layer: int, dir: Vector2i) -> Dictionary:
	var s := _surface(cell, layer)
	if s.is_empty():
		return {}
	var to := cell + dir
	var diagonal := dir.x != 0 and dir.y != 0

	if not diagonal:
		var e := _edge(s, dir)
		if not is_nan(e):
			for t in _surfaces(to):
				if is_equal_approx(_edge(t, -dir), e):
					return { layer = t.layer, hop = false }

	if _rise(s.tile) > 0.0:
		return {}
	var h := _center(s)

	if diagonal:
		var side_a := cell + Vector2i(dir.x, 0)
		var side_b := cell + Vector2i(0, dir.y)
		var dest := _flat_surface_at(to, h)
		if not dest.is_empty() and not _flat_surface_at(side_a, h).is_empty() \
				and not _flat_surface_at(side_b, h).is_empty():
			return { layer = dest.layer, hop = false }
		if not (_open_at(side_a, h) and _open_at(side_b, h)):
			return {}

	var land := _landing(to, h)
	if land.is_empty():
		return {}
	return { layer = land.layer, hop = true }


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
	if item == INVALID_CELL_ITEM:
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


func _flat_surface_at(cell: Vector2i, h: float) -> Dictionary:
	for s in _surfaces(cell):
		if _rise(s.tile) == 0.0 and is_equal_approx(_center(s), h):
			return s
	return {}


## Highest flat surface below h that you'd land on hopping in from height h.
func _landing(cell: Vector2i, h: float) -> Dictionary:
	if not _open_at(cell, h):
		return {}
	var best := {}
	for s in _surfaces(cell):
		if _span(s.tile, s.layer).y < h - EPS:
			best = s
	if best.is_empty() or _rise(best.tile) > 0.0 or h - _center(best) > max_drop + EPS:
		return {}
	return best


## True if nothing in the column occupies the body-height space above h.
func _open_at(cell: Vector2i, h: float) -> bool:
	for layer in range(GROUND_LAYER, TOP_LAYER + 1):
		var item := get_cell_item(Vector3i(cell.x, layer, cell.y))
		if item == INVALID_CELL_ITEM:
			continue
		var span := _span(item, layer)
		if span.y > h + EPS and span.x < h + HEADROOM - EPS:
			return false
	return true


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
static func _span(tile: int, layer: int) -> Vector2:
	match tile:
		Tile.HALF, Tile.HALF_RAMP: return Vector2(layer, layer + 0.5)
		Tile.BRIDGE: return Vector2(layer + 1.0 - BRIDGE_THICKNESS, layer + 1.0)
	return Vector2(layer, layer + 1.0)


static func _rise(tile: int) -> float:
	match tile:
		Tile.RAMP, Tile.STAIRS: return 1.0
		Tile.HALF_RAMP: return 0.5
	return 0.0


# --- Meshes -----------------------------------------------------------------
# All meshes have their origin at the bottom center of the cell. Sloped tiles
# are modeled rising toward -Z; GridMap orientation rotates them.

func _build_mesh_library() -> MeshLibrary:
	var lib := MeshLibrary.new()
	var full_box := _box_faces(Vector3(-0.5, 0, -0.5), Vector3(0.5, 1, 0.5))
	var stone := Color(0.55, 0.53, 0.58)
	var sand := Color(0.80, 0.70, 0.48)
	_add_item(lib, Tile.GROUND, "Ground", full_box, Color(0.42, 0.68, 0.36))
	_add_item(lib, Tile.FULL, "Full", full_box, stone)
	_add_item(lib, Tile.HALF, "Half", _box_faces(Vector3(-0.5, 0, -0.5), Vector3(0.5, 0.5, 0.5)), sand)
	_add_item(lib, Tile.RAMP, "Ramp", _ramp_faces(1.0), stone)
	_add_item(lib, Tile.HALF_RAMP, "HalfRamp", _ramp_faces(0.5), sand)
	_add_item(lib, Tile.STAIRS, "Stairs", _stairs_faces(1.0, STAIR_STEPS), stone)
	_add_item(lib, Tile.BRIDGE, "Bridge", _box_faces(Vector3(-0.5, 1.0 - BRIDGE_THICKNESS, -0.5), Vector3(0.5, 1, 0.5)), Color(0.55, 0.36, 0.22))
	return lib


func _add_item(lib: MeshLibrary, id: int, item_name: String, faces: Array, color: Color) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for face in faces:
		var pts: Array = face[0]
		var n: Vector3 = face[1]
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
				st.add_vertex(v)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	st.set_material(mat)
	lib.create_item(id)
	lib.set_item_name(id, item_name)
	lib.set_item_mesh(id, st.commit())


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


static func _stairs_faces(rise: float, steps: int) -> Array:
	var faces := []
	var depth := 1.0 / steps
	for i in steps:
		var z_front := 0.5 - i * depth
		faces.append_array(_box_faces(
			Vector3(-0.5, 0, z_front - depth),
			Vector3(0.5, rise * (i + 1) / steps, z_front)))
	return faces
