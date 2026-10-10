class_name GridWorld
extends GridMap

## Builds its own MeshLibrary of basic blocks and generates a tile map.
##
## Layer y = -1 is ground. Platforms, ramps and walls sit on layer 0 and up.
## Grid coords for movement are (x, z); the top tile of each column defines
## the walkable surface there.
##
## Height changes only happen through sloped tiles (ramps, stairs): you can
## walk between two cells only if their facing edges are at the same height.

enum Tile { GROUND, FULL, HALF, RAMP, HALF_RAMP, STAIRS }

const TOP_LAYER := 3
const STAIR_STEPS := 4

@export var map_size := Vector2i(24, 24)
@export var platform_count := 8
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
			set_cell_item(Vector3i(x, -1, z), Tile.GROUND)
			if x == 0 or z == 0 or x == map_size.x - 1 or z == map_size.y - 1:
				set_cell_item(Vector3i(x, 0, z), Tile.FULL)
				set_cell_item(Vector3i(x, 1, z), Tile.FULL)

	var placed := 0
	for attempt in platform_count * 10:
		if placed >= platform_count:
			break
		if _try_place_platform(rng, reserved):
			placed += 1


## Places a rectangular platform with one ramp or staircase leading up to it.
## Keeps a one-cell walkway around every platform so nothing gets sealed off.
func _try_place_platform(rng: RandomNumberGenerator, reserved: Dictionary) -> bool:
	var size := Vector2i(rng.randi_range(2, 5), rng.randi_range(2, 5))
	var rect := Rect2i(
		Vector2i(rng.randi_range(3, map_size.x - size.x - 3), rng.randi_range(3, map_size.y - size.y - 3)),
		size)

	# Ramp sits just outside the middle of one side, rising toward the platform.
	var up_dir: Vector2i = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT][rng.randi() % 4]
	var mid := rect.position + rect.size / 2
	var ramp_cell := Vector2i(
		mid.x if up_dir.x == 0 else (rect.position.x - 1 if up_dir.x > 0 else rect.end.x),
		mid.y if up_dir.y == 0 else (rect.position.y - 1 if up_dir.y > 0 else rect.end.y))
	var approach := ramp_cell - up_dir

	var footprint := rect.grow(1)
	for x in range(footprint.position.x, footprint.end.x):
		for z in range(footprint.position.y, footprint.end.y):
			if reserved.has(Vector2i(x, z)):
				return false
	if reserved.has(approach):
		return false

	var half := rng.randf() < 0.4
	for x in range(rect.position.x, rect.end.x):
		for z in range(rect.position.y, rect.end.y):
			set_cell_item(Vector3i(x, 0, z), Tile.HALF if half else Tile.FULL)
	var ramp_tile := Tile.HALF_RAMP if half else (Tile.STAIRS if rng.randf() < 0.5 else Tile.RAMP)
	set_slope(ramp_cell, 0, ramp_tile, up_dir)

	for x in range(footprint.position.x, footprint.end.x):
		for z in range(footprint.position.y, footprint.end.y):
			reserved[Vector2i(x, z)] = true
	reserved[approach] = true
	return true


## Places a sloped tile so that it rises toward up_dir.
func set_slope(cell: Vector2i, layer: int, tile: Tile, up_dir: Vector2i) -> void:
	var basis := Basis(Vector3.UP, atan2(-up_dir.x, -up_dir.y))
	set_cell_item(Vector3i(cell.x, layer, cell.y), tile, get_orthogonal_index_from_basis(basis))


# --- Surface queries --------------------------------------------------------

func can_move(from: Vector2i, dir: Vector2i) -> bool:
	if dir.x != 0 and dir.y != 0:
		# Diagonals only across flat ground at one height, with no corner cutting.
		var h := center_height(from)
		for c in [from + dir, from + Vector2i(dir.x, 0), from + Vector2i(0, dir.y)]:
			if not _is_flat(c) or not is_equal_approx(center_height(c), h):
				return false
		return _is_flat(from)
	var a := edge_height(from, dir)
	var b := edge_height(from + dir, -dir)
	return not is_nan(a) and not is_nan(b) and is_equal_approx(a, b)


## Surface height at the edge of a cell facing dir, or NAN if it can't be
## entered or left that way (e.g. the side of a ramp).
func edge_height(cell: Vector2i, dir: Vector2i) -> float:
	var top := _top(cell)
	if top.is_empty():
		return NAN
	var rise := _rise(top.tile)
	if rise == 0.0:
		return top.base + _height(top.tile)
	if dir == top.up:
		return top.base + rise
	if dir == -top.up:
		return top.base
	return NAN


func center_height(cell: Vector2i) -> float:
	var top := _top(cell)
	if top.is_empty():
		return 0.0
	var rise := _rise(top.tile)
	return top.base + (rise / 2.0 if rise > 0.0 else _height(top.tile))


## World-space position of a cell's center, on its surface.
func cell_to_world(cell: Vector2i) -> Vector3:
	return Vector3(cell.x + 0.5, center_height(cell), cell.y + 0.5) * cell_size


func _is_flat(cell: Vector2i) -> bool:
	var top := _top(cell)
	return not top.is_empty() and _rise(top.tile) == 0.0


func _top(cell: Vector2i) -> Dictionary:
	if cell.x < 0 or cell.y < 0 or cell.x >= map_size.x or cell.y >= map_size.y:
		return {}
	for layer in range(TOP_LAYER, -2, -1):
		var pos := Vector3i(cell.x, layer, cell.y)
		var item := get_cell_item(pos)
		if item == INVALID_CELL_ITEM:
			continue
		var fwd := get_cell_item_basis(pos) * Vector3.FORWARD
		return { tile = item, base = float(layer), up = Vector2i(roundi(fwd.x), roundi(fwd.z)) }
	return {}


static func _height(tile: int) -> float:
	return 0.5 if tile == Tile.HALF else 1.0


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
