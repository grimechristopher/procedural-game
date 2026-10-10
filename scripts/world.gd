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
## - Diagonal walks compare heights at the shared corner instead, and the
##   two cells beside the move must be passable at that corner (no corner
##   cutting). Diagonal ramps can only be walked diagonally, up or down.
## - Wedges (corner-cut blocks) are solid, but a diagonal walk can pass the
##   open corner of a wedge beside you, or cross its solid corner on top.
## - Corner slopes are solid.
## - Thin pieces (walls, fences, pillars) share a cell with the floor and
##   block only the cell edges or corners they sit on.
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
	# Stone paving at ground level, for the plaza at spawn.
	PLAZA,
	# Half-height slopes: HALF_* rise from 0 to 0.5, UPPER_HALF_* from 0.5 to 1,
	# so a pair makes a gentle two-cell climb.
	HALF_STAIRS, UPPER_HALF_RAMP, UPPER_HALF_STAIRS,
	# Rise corner to corner; only walkable diagonally.
	DIAG_RAMP, HALF_DIAG_RAMP,
	# Thin pieces along a cell's edge (or, for PILLAR, in its corner).
	WALL, WALL_CORNER, DOORWAY, FENCE, FENCE_CORNER, PILLAR,
	# Farming: ground you can till, its tilled and watered states, and the
	# solid objects you trade with.
	FARMLAND, TILLED, TILLED_WET, SHIPPING_BIN, SHOP_STALL,
	# Water sits a quarter block below the ground. A water bridge is a plank
	# deck at ground level over water; a waterfall is a solid block of water.
	WATER, WATER_BRIDGE, WATERFALL,
	# Props: sprites leaned back to face the fixed camera. All solid except
	# tall grass, which you walk through.
	TREE, SNOW_TREE, BOULDER, BUSH, TALL_GRASS,
}

## Prop tiles, in the order of their sprites in assets/props.png.
const PROP_SPRITES := [Tile.TREE, Tile.SNOW_TREE, Tile.BOULDER, Tile.BUSH, Tile.TALL_GRASS]
const PROP_SPRITE_SIZE := Vector2i(32, 48)
## Props lean back by the camera's pitch so they face it square on.
const PROP_LEAN_DEGREES := 40.0

## Gameplay tags per tile. Systems like farming ask what a cell is tagged
## with (cell_tags / has_tag) rather than checking for particular tiles.
const TAGS := {
	Tile.FARMLAND: [&"tillable"],
	Tile.TILLED: [&"tilled"],
	Tile.TILLED_WET: [&"tilled", &"watered"],
	Tile.SHIPPING_BIN: [&"shipping_bin"],
	Tile.SHOP_STALL: [&"shop"],
	Tile.WATER: [&"water"],
	Tile.WATERFALL: [&"water"],
	Tile.TALL_GRASS: [&"tall_grass"],
}

## Tiles in assets/tileset.png (see tools/make_tileset.py), left to right,
## top to bottom.
enum Tex { GRASS, GRASS_SIDE, DIRT, PATH, FLOWERS, STONE, PLANKS, TILLED, TILLED_WET, SOIL }
const TEX_COLS := 4
const TEX_ROWS := 3

const TILESET := preload("res://assets/tileset.png")
const BLOCK_SHADER := preload("res://assets/block.gdshader")
const WATER_SHADER := preload("res://assets/water.gdshader")
const WATER_TEXTURE := preload("res://assets/water.png")
const PROPS_TEXTURE := preload("res://assets/props.png")

const GROUND_LAYER := -1
const TOP_LAYER := 3
const STAIR_STEPS := 4
const HEADROOM := 1.0
const BRIDGE_THICKNESS := 0.15
const EPS := 0.001
const NO_MOVE := -999

@export var map_size := Vector2i(36, 36)
@export var platform_count := 16
@export var bridge_count := 4
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
	for x in range(spawn_cell.x - 2, spawn_cell.x + 3):
		for z in range(spawn_cell.y - 2, spawn_cell.y + 3):
			reserved[Vector2i(x, z)] = true

	for x in map_size.x:
		for z in map_size.y:
			set_cell_item(Vector3i(x, GROUND_LAYER, z), Tile.GROUND)
			if x == 0 or z == 0 or x == map_size.x - 1 or z == map_size.y - 1:
				set_cell_item(Vector3i(x, 0, z), Tile.FULL)
				set_cell_item(Vector3i(x, 1, z), Tile.FULL)

	var towers: Array[Rect2i] = []
	var approaches: Array[Vector2i] = []
	_place_farm(reserved, approaches)
	_place_river(rng, reserved)
	var placed := 0
	for attempt in platform_count * 10:
		if placed >= platform_count:
			break
		if _try_place_platform(rng, reserved, towers, approaches):
			placed += 1
	for enclosure in [true, false]:
		for attempt in 20:
			if _try_place_enclosure(rng, reserved, approaches, enclosure):
				break
	_place_bridges(rng, towers)
	_decorate_ground(rng, approaches)
	for x in range(spawn_cell.x - 1, spawn_cell.x + 2):
		for z in range(spawn_cell.y - 1, spawn_cell.y + 2):
			set_cell_item(Vector3i(x, GROUND_LAYER, z), Tile.PLAZA)
	_place_scenery(rng, reserved)
	_bury_covered_blocks()


## Lays out a field of farmland just south of the spawn plaza, with the
## shipping bin and seed shop on the plaza's east side.
func _place_farm(reserved: Dictionary, approaches: Array[Vector2i]) -> void:
	var field := Rect2i(spawn_cell + Vector2i(-3, 3), Vector2i(7, 5))
	for x in range(field.position.x, field.end.x):
		for z in range(field.position.y, field.end.y):
			set_ground(Vector2i(x, z), Tile.FARMLAND)
	var margin := field.grow(1)
	for x in range(margin.position.x, margin.end.x):
		for z in range(margin.position.y, margin.end.y):
			reserved[Vector2i(x, z)] = true
	set_slope(spawn_cell + Vector2i(2, -1), 0, Tile.SHIPPING_BIN, Vector2i.LEFT)
	set_slope(spawn_cell + Vector2i(2, 1), 0, Tile.SHOP_STALL, Vector2i.LEFT)
	approaches.append(Vector2i(spawn_cell.x, field.position.y - 1))


## Runs a two-wide river down the map, north to south, well clear of the
## farm: in through a waterfall in the north wall, out through the south
## wall, with two plank bridges across it.
func _place_river(rng: RandomNumberGenerator, reserved: Dictionary) -> void:
	var lo := 3 if rng.randf() < 0.5 else map_size.x - 9
	var hi := lo + 4
	var x := rng.randi_range(lo, hi)
	var rows: Array[int] = []
	for z in map_size.y:
		if z > 1 and z < map_size.y - 2 and rng.randf() < 0.35:
			x = clampi(x + (1 if rng.randf() < 0.5 else -1), lo, hi)
		rows.append(x)
		for dx in 2:
			var cell := Vector2i(x + dx, z)
			set_ground(cell, Tile.WATER)
			var top := Tile.WATERFALL if z == 0 else INVALID_CELL_ITEM
			set_cell_item(Vector3i(cell.x, 0, z), top)
			set_cell_item(Vector3i(cell.x, 1, z), top)
			for nx in range(cell.x - 1, cell.x + 2):
				for nz in range(z - 1, z + 2):
					reserved[Vector2i(nx, nz)] = true

	var first := rng.randi_range(4, map_size.y / 2 - 3)
	for z in [first, rng.randi_range(first + 7, map_size.y - 5)]:
		for dx in 2:
			set_slope(Vector2i(rows[z] + dx, z), GROUND_LAYER, Tile.WATER_BRIDGE, Vector2i.RIGHT)


## Scatters forest clumps (mostly near the walls), boulders, bushes and
## patches of tall grass over open grass. Anything solid is only kept if
## every bit of ground that was reachable before still is.
func _place_scenery(rng: RandomNumberGenerator, reserved: Dictionary) -> void:
	var reach := _ground_reachable()
	var groups := []
	for i in 14:
		var near_wall := rng.randf() < 0.6
		var center := Vector2i(rng.randi_range(1, map_size.x - 2), rng.randi_range(1, map_size.y - 2))
		if near_wall:
			var side := rng.randi() % 4
			var depth := rng.randi_range(1, 3)
			center = [Vector2i(depth, center.y), Vector2i(map_size.x - 1 - depth, center.y),
				Vector2i(center.x, depth), Vector2i(center.x, map_size.y - 1 - depth)][side]
		groups.append([center, 2, 0.6, Tile.TREE])
	for i in 8:
		var center := Vector2i(rng.randi_range(2, map_size.x - 3), rng.randi_range(2, map_size.y - 3))
		groups.append([center, 0, 1.0, Tile.BOULDER if rng.randf() < 0.5 else Tile.BUSH])

	for group in groups:
		var placed: Array[Vector2i] = []
		var center: Vector2i = group[0]
		var radius: int = group[1]
		for x in range(center.x - radius, center.x + radius + 1):
			for z in range(center.y - radius, center.y + radius + 1):
				var cell := Vector2i(x, z)
				if _is_open_grass(cell, reserved) and rng.randf() < group[2]:
					set_cell_item(Vector3i(x, 0, z), group[3])
					placed.append(cell)
		if placed.is_empty():
			continue
		var after := _ground_reachable()
		var lost := 0
		for cell in placed:
			if reach.has(cell):
				lost += 1
		if after.size() == reach.size() - lost:
			reach = after
		else:
			for cell in placed:
				set_cell_item(Vector3i(cell.x, 0, cell.y), INVALID_CELL_ITEM)

	for i in 7:
		var center := Vector2i(rng.randi_range(2, map_size.x - 3), rng.randi_range(2, map_size.y - 3))
		for x in range(center.x - 2, center.x + 3):
			for z in range(center.y - 1, center.y + 2):
				if _is_open_grass(Vector2i(x, z), {}) and rng.randf() < 0.75:
					set_cell_item(Vector3i(x, 0, z), Tile.TALL_GRASS)


## Grass with nothing on it, away from the walls and anything reserved.
func _is_open_grass(cell: Vector2i, reserved: Dictionary) -> bool:
	if cell.x < 1 or cell.y < 1 or cell.x >= map_size.x - 1 or cell.y >= map_size.y - 1 or reserved.has(cell):
		return false
	var ground := ground_tile(cell)
	if ground != Tile.GROUND and ground != Tile.FLOWERS:
		return false
	for layer in range(0, TOP_LAYER + 1):
		if get_cell_item(Vector3i(cell.x, layer, cell.y)) != INVALID_CELL_ITEM:
			return false
	return true


## Ground cells reachable from spawn by walking at ground level.
func _ground_reachable() -> Dictionary:
	var seen := { spawn_cell: true }
	var frontier: Array[Vector2i] = [spawn_cell]
	while not frontier.is_empty():
		var c: Vector2i = frontier.pop_back()
		for d in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			if not seen.has(c + d) and find_move(c, GROUND_LAYER, d) == GROUND_LAYER:
				seen[c + d] = true
				frontier.append(c + d)
	return seen


## Sets the ground-layer tile of a cell.
func set_ground(cell: Vector2i, tile: Tile) -> void:
	set_cell_item(Vector3i(cell.x, GROUND_LAYER, cell.y), tile)


func ground_tile(cell: Vector2i) -> int:
	return get_cell_item(Vector3i(cell.x, GROUND_LAYER, cell.y))


## Every tag on any tile in the column.
func cell_tags(cell: Vector2i) -> Array:
	var tags := []
	for layer in range(GROUND_LAYER, TOP_LAYER + 1):
		tags.append_array(TAGS.get(get_cell_item(Vector3i(cell.x, layer, cell.y)), []))
	return tags


func has_tag(cell: Vector2i, tag: StringName) -> bool:
	return tag in cell_tags(cell)


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
			if rng.randf() < 0.08 and ground_tile(Vector2i(x, z)) == Tile.GROUND:
				set_ground(Vector2i(x, z), Tile.FLOWERS)

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
			if ground_tile(c) == Tile.GROUND or ground_tile(c) == Tile.FLOWERS:
				set_ground(c, Tile.PATH)
			c = came_from[c]


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
		else Vector2i(rng.randi_range(2, 7), rng.randi_range(2, 7))
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
	var gentle := kind == 1 and rng.randf() < 0.4
	var slope_cells: Array = [slope, slope - up_dir] if kind == 2 or gentle else [slope]
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
		var stairs := rng.randf() < 0.5
		if kind == 2:
			var tile: Tile = Tile.STAIRS if stairs else Tile.RAMP
			set_cell_item(Vector3i(slope.x, 0, slope.y), Tile.FULL)
			set_slope(slope, 1, tile, up_dir)
			set_slope(slope - up_dir, 0, tile, up_dir)
			towers.append(rect)
		elif gentle:
			set_slope(slope, 0, Tile.UPPER_HALF_STAIRS if stairs else Tile.UPPER_HALF_RAMP, up_dir)
			set_slope(slope - up_dir, 0, Tile.HALF_STAIRS if stairs else Tile.HALF_RAMP, up_dir)
		elif half:
			set_slope(slope, 0, Tile.HALF_STAIRS if stairs else Tile.HALF_RAMP, up_dir)
		else:
			set_slope(slope, 0, Tile.STAIRS if stairs else Tile.RAMP, up_dir)
		# Cut no deeper than leaves the middle of every side (where the ramp lands) intact.
		var max_cut := mini((size.x - 1) / 2, (size.y - 1) / 2)
		if max_cut >= 1 and rng.randf() < 0.7:
			var depth := rng.randi_range(maxi(1, max_cut - 1), max_cut)
			_cut_corners(rect, layers, Tile.HALF_WEDGE if half else Tile.WEDGE, depth)
			# Long diagonal edges on one-layer platforms may get a diagonal ramp.
			if depth >= 2 and layers == 1 and rng.randf() < 0.9:
				var corner: Dictionary = _rect_corners(rect)[rng.randi() % 4]
				var i := depth / 2
				var ramp_cell: Vector2i = corner.cell + Vector2i(i * corner.inward.x, (depth - 1 - i) * corner.inward.y)
				set_corner(ramp_cell, 0, Tile.HALF_DIAG_RAMP if half else Tile.DIAG_RAMP, corner.inward)
				approaches.append(ramp_cell - corner.inward)

	for c in claim:
		reserved[c] = true
	approaches.append(approach)
	return true


## Places a walled ruin with a doorway, or a fenced pen with a gap, on open
## ground. Walls and fences run along the outside edges of the border cells.
func _try_place_enclosure(rng: RandomNumberGenerator, reserved: Dictionary,
		approaches: Array[Vector2i], walled: bool) -> bool:
	var size := Vector2i(rng.randi_range(3, 5), rng.randi_range(3, 5))
	var rect := Rect2i(
		Vector2i(rng.randi_range(3, map_size.x - size.x - 3), rng.randi_range(3, map_size.y - size.y - 3)),
		size)
	var footprint := rect.grow(1)
	for x in range(footprint.position.x, footprint.end.x):
		for z in range(footprint.position.y, footprint.end.y):
			if reserved.has(Vector2i(x, z)):
				return false

	var door_dir: Vector2i = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT][rng.randi() % 4]
	var mid := rect.position + rect.size / 2
	var door := Vector2i(
		mid.x if door_dir.x == 0 else (rect.position.x if door_dir.x < 0 else rect.end.x - 1),
		mid.y if door_dir.y == 0 else (rect.position.y if door_dir.y < 0 else rect.end.y - 1))
	var hi := rect.end - Vector2i.ONE
	for x in range(rect.position.x, rect.end.x):
		for z in range(rect.position.y, rect.end.y):
			var out := Vector2i(
				-1 if x == rect.position.x else (1 if x == hi.x else 0),
				-1 if z == rect.position.y else (1 if z == hi.y else 0))
			if out == Vector2i.ZERO:
				continue
			var cell := Vector2i(x, z)
			if cell == door:
				if walled:
					set_slope(cell, 0, Tile.DOORWAY, door_dir)
			elif out.x != 0 and out.y != 0:
				set_corner(cell, 0, Tile.WALL_CORNER if walled else Tile.FENCE_CORNER, out)
			else:
				set_slope(cell, 0, Tile.WALL if walled else Tile.FENCE, out)
	if walled:
		set_corner(rect.position + Vector2i.ONE, 0, Tile.PILLAR, Vector2i(-1, -1))

	for x in range(footprint.position.x, footprint.end.x):
		for z in range(footprint.position.y, footprint.end.y):
			reserved[Vector2i(x, z)] = true
	approaches.append(door + door_dir)
	return true


## Cuts each corner of a platform off at 45 degrees, depth cells along each
## side: a diagonal line of wedges (solid side inward) with the cells
## outside it cleared back to ground.
func _cut_corners(rect: Rect2i, layers: int, wedge: Tile, depth: int) -> void:
	for corner in _rect_corners(rect):
		for i in depth:
			for j in depth - i:
				var cell: Vector2i = corner.cell + Vector2i(i * corner.inward.x, j * corner.inward.y)
				for layer in layers:
					if i + j == depth - 1:
						set_corner(cell, layer, wedge, corner.inward)
					else:
						set_cell_item(Vector3i(cell.x, layer, cell.y), INVALID_CELL_ITEM)


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
		# Towers apart along x get a bridge running along x (railings on its sides).
		var along := Vector2i.RIGHT if a.end.x <= b.position.x or b.end.x <= a.position.x else Vector2i.DOWN
		for c in span:
			set_slope(c, 1, Tile.BRIDGE, along)
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
		if is_nan(e) or _edge_blocked(cell, dir, e):
			return NO_MOVE
		for t in _surfaces(to):
			var e2 := _edge(t, -dir)
			if is_equal_approx(e2, e) and not _edge_blocked(to, -dir, e2):
				return t.layer
		return NO_MOVE

	var h := _corner_height(s, dir, true)
	if is_nan(h):
		return NO_MOVE
	var side_a := cell + Vector2i(dir.x, 0)
	var side_b := cell + Vector2i(0, dir.y)
	if _corner_blocked(cell, dir, h) \
			or not _corner_passable(side_a, Vector2i(-dir.x, dir.y), h) \
			or not _corner_passable(side_b, Vector2i(dir.x, -dir.y), h):
		return NO_MOVE
	for t in _surfaces(to):
		var h2 := _corner_height(t, -dir, true)
		if is_equal_approx(h2, h) and not _corner_blocked(to, -dir, h2):
			return t.layer
	return NO_MOVE


## Height where a step from (cell, layer) in dir crosses into the next cell:
## the shared edge, or for a diagonal step the shared corner.
func crossing_height(cell: Vector2i, layer: int, dir: Vector2i) -> float:
	var s := _surface(cell, layer)
	if dir.x == 0 or dir.y == 0:
		return _edge(s, dir)
	return _corner_height(s, dir, true)


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


## The tile at (cell, layer) as a surface, or {} if there's no tile there,
## it isn't something you stand on, or something above it leaves less than
## HEADROOM. Thin pieces sit at the cell's edge, so they don't take headroom.
func _surface(cell: Vector2i, layer: int) -> Dictionary:
	if cell.x < 0 or cell.y < 0 or cell.x >= map_size.x or cell.y >= map_size.y:
		return {}
	var pos := Vector3i(cell.x, layer, cell.y)
	var item := get_cell_item(pos)
	if item == INVALID_CELL_ITEM or _is_wedge(item) or _is_corner_slope(item) or _is_thin(item) \
			or item == Tile.SHIPPING_BIN or item == Tile.SHOP_STALL or _is_solid_scenery(item) \
			or item == Tile.TALL_GRASS:
		return {}
	var top := _span(item, layer).y
	for above in range(layer + 1, TOP_LAYER + 1):
		var other := get_cell_item(Vector3i(cell.x, above, cell.y))
		if other == INVALID_CELL_ITEM or _is_thin(other) or other == Tile.TALL_GRASS:
			continue
		if _span(other, above).x < top + HEADROOM - EPS:
			return {}
		break
	var fwd := get_cell_item_basis(pos) * Vector3.FORWARD
	return {
		tile = item, layer = layer,
		up = Vector2i(roundi(fwd.x), roundi(fwd.z)), diag = _corner_dir(cell, layer),
	}


## Whether a diagonal walk at height h can pass the given corner of a cell
## beside it (corner as a sign vector from the cell's center).
func _corner_passable(cell: Vector2i, corner: Vector2i, h: float) -> bool:
	if _corner_blocked(cell, corner, h):
		return false
	for s in _surfaces(cell):
		var ch := _corner_height(s, corner, false)
		if is_equal_approx(ch, h):
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


func _up_dir(cell: Vector2i, layer: int) -> Vector2i:
	var d := get_cell_item_basis(Vector3i(cell.x, layer, cell.y)) * Vector3.FORWARD
	return Vector2i(roundi(d.x), roundi(d.z))


## Surface height at the edge of s facing dir, or NAN if it can't be
## entered or left that way (e.g. the side of a ramp).
func _edge(s: Dictionary, dir: Vector2i) -> float:
	if s.is_empty():
		return NAN
	var rise := _rise(s.tile)
	if rise == 0.0:
		return _span(s.tile, s.layer).y
	if _is_diag_ramp(s.tile):
		return NAN
	var low: float = s.layer + _base(s.tile)
	if dir == s.up:
		return low + rise
	if dir == -s.up:
		return low
	return NAN


## Surface height at a corner of s (a sign vector). With along_only, only
## corners you can step diagonally through count: any corner of flat ground,
## and the low or high corner of a diagonal ramp.
func _corner_height(s: Dictionary, corner: Vector2i, along_only: bool) -> float:
	if s.is_empty():
		return NAN
	var rise := _rise(s.tile)
	if rise == 0.0:
		return _span(s.tile, s.layer).y
	var low: float = s.layer + _base(s.tile)
	if _is_diag_ramp(s.tile):
		if corner == s.diag:
			return low + rise
		if corner == -s.diag:
			return low
		return NAN if along_only else low + rise / 2.0
	if along_only:
		return NAN
	return low + rise if corner.x * s.up.x + corner.y * s.up.y > 0 else low


func _center(s: Dictionary) -> float:
	var rise := _rise(s.tile)
	return s.layer + _base(s.tile) + rise / 2.0 if rise > 0.0 else _span(s.tile, s.layer).y


## Thin pieces in a cell that reach into the body-height space above h.
func _thin_pieces(cell: Vector2i, h: float) -> Array:
	var out := []
	for layer in range(GROUND_LAYER + 1, TOP_LAYER + 1):
		var item := get_cell_item(Vector3i(cell.x, layer, cell.y))
		if not _is_thin(item):
			continue
		var span := _span(item, layer)
		if span.y > h + EPS and span.x < h + HEADROOM - EPS:
			out.append([item, layer])
	return out


func _edge_blocked(cell: Vector2i, dir: Vector2i, h: float) -> bool:
	for piece in _thin_pieces(cell, h):
		var item: int = piece[0]
		match item:
			Tile.WALL, Tile.FENCE:
				if dir == _up_dir(cell, piece[1]):
					return true
			Tile.WALL_CORNER, Tile.FENCE_CORNER:
				var d := _corner_dir(cell, piece[1])
				if dir == Vector2i(d.x, 0) or dir == Vector2i(0, d.y):
					return true
	return false


func _corner_blocked(cell: Vector2i, corner: Vector2i, h: float) -> bool:
	for piece in _thin_pieces(cell, h):
		var item: int = piece[0]
		match item:
			Tile.WALL, Tile.FENCE, Tile.DOORWAY:
				var u := _up_dir(cell, piece[1])
				var across := Vector2i(u.y, -u.x)
				if corner == u + across or corner == u - across:
					return true
			Tile.WALL_CORNER, Tile.FENCE_CORNER:
				var d := _corner_dir(cell, piece[1])
				if corner == d or corner == Vector2i(d.x, -d.y) or corner == Vector2i(-d.x, d.y):
					return true
			Tile.PILLAR:
				if corner == _corner_dir(cell, piece[1]):
					return true
	return false


static func _is_wedge(tile: int) -> bool:
	return tile == Tile.WEDGE or tile == Tile.HALF_WEDGE or tile == Tile.WEDGE_DIRT


static func _is_corner_slope(tile: int) -> bool:
	return tile in [Tile.CORNER_OUTER, Tile.CORNER_INNER, Tile.HALF_CORNER_OUTER, Tile.HALF_CORNER_INNER]


static func _is_diag_ramp(tile: int) -> bool:
	return tile == Tile.DIAG_RAMP or tile == Tile.HALF_DIAG_RAMP


static func _is_solid_scenery(tile: int) -> bool:
	return tile in [Tile.WATER, Tile.WATERFALL, Tile.TREE, Tile.SNOW_TREE, Tile.BOULDER, Tile.BUSH]


static func _is_thin(tile: int) -> bool:
	return tile in [Tile.WALL, Tile.WALL_CORNER, Tile.DOORWAY, Tile.FENCE, Tile.FENCE_CORNER, Tile.PILLAR]


## Vertical extent (bottom, top) a tile occupies in world space.
static func _span(tile: int, layer: int) -> Vector2:
	match tile:
		Tile.HALF, Tile.HALF_RAMP, Tile.HALF_HILL_RAMP, Tile.HALF_STAIRS, Tile.HALF_WEDGE, \
				Tile.HALF_CORNER_OUTER, Tile.HALF_CORNER_INNER, Tile.HALF_DIAG_RAMP, \
				Tile.FENCE, Tile.FENCE_CORNER:
			return Vector2(layer, layer + 0.5)
		Tile.BRIDGE, Tile.WATER_BRIDGE: return Vector2(layer + 1.0 - BRIDGE_THICKNESS, layer + 1.0)
		Tile.WATER: return Vector2(layer, layer + 0.75)
	return Vector2(layer, layer + 1.0)


static func _rise(tile: int) -> float:
	match tile:
		Tile.RAMP, Tile.HILL_RAMP, Tile.STAIRS, Tile.DIAG_RAMP: return 1.0
		Tile.HALF_RAMP, Tile.HALF_HILL_RAMP, Tile.HALF_STAIRS, Tile.HALF_DIAG_RAMP, \
				Tile.UPPER_HALF_RAMP, Tile.UPPER_HALF_STAIRS:
			return 0.5
	return 0.0


## Height a slope starts at within its cell.
static func _base(tile: int) -> float:
	return 0.5 if tile == Tile.UPPER_HALF_RAMP or tile == Tile.UPPER_HALF_STAIRS else 0.0


# --- Meshes -----------------------------------------------------------------
# All meshes have their origin at the bottom center of the cell. Sloped tiles
# are modeled rising toward -Z; GridMap orientation rotates them.

func _build_mesh_library() -> MeshLibrary:
	var mat := ShaderMaterial.new()
	mat.shader = BLOCK_SHADER
	mat.set_shader_parameter("tileset", TILESET)

	# Which tileset tile each kind of face uses.
	var grass_block := { top = Tex.GRASS, side = Tex.GRASS_SIDE, slope = Tex.GRASS }
	var ramp := { top = Tex.PATH, side = Tex.DIRT, slope = Tex.PATH }
	var hill := { top = Tex.GRASS, side = Tex.DIRT, slope = Tex.GRASS }
	var stone := { top = Tex.STONE, side = Tex.STONE, slope = Tex.STONE }
	var wood := { top = Tex.PLANKS, side = Tex.PLANKS, slope = Tex.PLANKS }
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
		[Tile.STAIRS, "Stairs", _stairs_faces(1.0, STAIR_STEPS), stone],
		[Tile.WEDGE, "Wedge", _wedge_faces(1.0), grass_block],
		[Tile.HALF_WEDGE, "HalfWedge", _wedge_faces(0.5), grass_block],
		[Tile.CORNER_OUTER, "CornerOuter", _outer_corner_faces(1.0), hill],
		[Tile.CORNER_INNER, "CornerInner", _inner_corner_faces(1.0), hill],
		[Tile.HALF_CORNER_OUTER, "HalfCornerOuter", _outer_corner_faces(0.5), hill],
		[Tile.HALF_CORNER_INNER, "HalfCornerInner", _inner_corner_faces(0.5), hill],
		[Tile.BRIDGE, "Bridge", _bridge_faces(), wood],
		[Tile.PLAZA, "Plaza", full_box, { top = Tex.STONE, side = Tex.DIRT, slope = Tex.STONE }],
		[Tile.HALF_STAIRS, "HalfStairs", _stairs_faces(0.5, 2), stone],
		[Tile.UPPER_HALF_RAMP, "UpperHalfRamp", _ramp_faces(0.5, 0.5), ramp],
		[Tile.UPPER_HALF_STAIRS, "UpperHalfStairs", _stairs_faces(0.5, 2, 0.5), stone],
		[Tile.DIAG_RAMP, "DiagRamp", _diag_ramp_faces(1.0), ramp],
		[Tile.HALF_DIAG_RAMP, "HalfDiagRamp", _diag_ramp_faces(0.5), ramp],
		[Tile.WALL, "Wall", _wall_faces(1.0), stone],
		[Tile.WALL_CORNER, "WallCorner", _wall_faces(1.0) + _wall_faces(1.0, true), stone],
		[Tile.DOORWAY, "Doorway", _doorway_faces(), stone],
		[Tile.FENCE, "Fence", _fence_faces(), wood],
		[Tile.FENCE_CORNER, "FenceCorner", _fence_faces() + _fence_faces(true), wood],
		[Tile.PILLAR, "Pillar", _box_faces(Vector3(-0.5, 0, -0.5), Vector3(-0.3, 1, -0.3)), stone],
		[Tile.FARMLAND, "Farmland", full_box, { top = Tex.SOIL, side = Tex.DIRT, slope = Tex.SOIL }],
		[Tile.TILLED, "Tilled", full_box, { top = Tex.TILLED, side = Tex.DIRT, slope = Tex.TILLED }],
		[Tile.TILLED_WET, "TilledWet", full_box, { top = Tex.TILLED_WET, side = Tex.DIRT, slope = Tex.TILLED_WET }],
		[Tile.SHIPPING_BIN, "ShippingBin", _box_faces(Vector3(-0.4, 0, -0.32), Vector3(0.4, 0.6, 0.32))
			+ _box_faces(Vector3(-0.45, 0.6, -0.38), Vector3(0.45, 0.7, 0.38)), wood],
		[Tile.SHOP_STALL, "ShopStall", _shop_faces(), stone],
	]
	for item in items:
		lib.create_item(item[0])
		lib.set_item_name(item[0], item[1])
		lib.set_item_mesh(item[0], _build_mesh(item[2], item[3], mat))

	var water_mat := ShaderMaterial.new()
	water_mat.shader = WATER_SHADER
	water_mat.set_shader_parameter("water", WATER_TEXTURE)
	var water_box := _box_faces(Vector3(-0.5, 0, -0.5), Vector3(0.5, 0.75, 0.5))
	for item in [[Tile.WATER, "Water", water_box], [Tile.WATERFALL, "Waterfall", full_box]]:
		lib.create_item(item[0])
		lib.set_item_name(item[0], item[1])
		lib.set_item_mesh(item[0], _build_mesh(item[2], wood, water_mat))
	lib.create_item(Tile.WATER_BRIDGE)
	lib.set_item_name(Tile.WATER_BRIDGE, "WaterBridge")
	lib.set_item_mesh(Tile.WATER_BRIDGE, _build_mesh(_bridge_faces(), wood, mat, _build_mesh(water_box, wood, water_mat)))

	var props_mat := StandardMaterial3D.new()
	props_mat.albedo_texture = PROPS_TEXTURE
	props_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	props_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	props_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	props_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	for i in PROP_SPRITES.size():
		var tile: int = PROP_SPRITES[i]
		lib.create_item(tile)
		lib.set_item_name(tile, Tile.keys()[tile].capitalize())
		lib.set_item_mesh(tile, _prop_mesh(i, props_mat))
	return lib


## Builds a mesh from faces, or adds them as another surface of into.
func _build_mesh(faces: Array, skin: Dictionary, mat: Material, into: ArrayMesh = null) -> ArrayMesh:
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
	return st.commit(into)


## A prop sprite as a quad standing on the cell's centre, leaned back to
## face the camera, sized so one texel matches the tileset's.
static func _prop_mesh(index: int, mat: Material) -> ArrayMesh:
	var size := Vector2(PROP_SPRITE_SIZE) / 16.0
	var lean := deg_to_rad(PROP_LEAN_DEGREES)
	var up := Vector3(0, cos(lean), -sin(lean)) * size.y
	var u0 := float(index) / PROP_SPRITES.size()
	var u1 := float(index + 1) / PROP_SPRITES.size()
	var bl := Vector3(-size.x / 2, 0, 0)
	var br := Vector3(size.x / 2, 0, 0)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for v in [[bl, Vector2(u0, 1)], [bl + up, Vector2(u0, 0)], [br + up, Vector2(u1, 0)],
			[bl, Vector2(u0, 1)], [br + up, Vector2(u1, 0)], [br, Vector2(u1, 1)]]:
		st.set_normal(Vector3(0, sin(lean), cos(lean)))
		st.set_uv(v[1])
		st.add_vertex(v[0])
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


## Rises toward -Z from base to base + rise.
static func _ramp_faces(rise: float, base := 0.0) -> Array:
	var top := base + rise
	var slope_n := Vector3(0, 1, rise).normalized()
	var faces := [
		[[Vector3(-0.5, base, 0.5), Vector3(0.5, base, 0.5), Vector3(0.5, top, -0.5), Vector3(-0.5, top, -0.5)], slope_n],
		[[Vector3(-0.5, 0, -0.5), Vector3(0.5, 0, -0.5), Vector3(0.5, 0, 0.5), Vector3(-0.5, 0, 0.5)], Vector3.DOWN],
		[[Vector3(-0.5, 0, -0.5), Vector3(0.5, 0, -0.5), Vector3(0.5, top, -0.5), Vector3(-0.5, top, -0.5)], Vector3.FORWARD],
		[[Vector3(0.5, 0, 0.5), Vector3(0.5, 0, -0.5), Vector3(0.5, top, -0.5), Vector3(0.5, base, 0.5)], Vector3.RIGHT],
		[[Vector3(-0.5, 0, 0.5), Vector3(-0.5, 0, -0.5), Vector3(-0.5, top, -0.5), Vector3(-0.5, base, 0.5)], Vector3.LEFT],
	]
	if base > 0.0:
		faces.append([[Vector3(-0.5, 0, 0.5), Vector3(0.5, 0, 0.5), Vector3(0.5, base, 0.5), Vector3(-0.5, base, 0.5)], Vector3.BACK])
	return faces


## Rises from the (+x, +z) corner up to the (-x, -z) corner.
static func _diag_ramp_faces(rise: float) -> Array:
	var mid := rise / 2.0
	return [
		_upward_face([Vector3(-0.5, rise, -0.5), Vector3(0.5, mid, -0.5), Vector3(0.5, 0, 0.5), Vector3(-0.5, mid, 0.5)]),
		[[Vector3(-0.5, 0, -0.5), Vector3(0.5, 0, -0.5), Vector3(0.5, 0, 0.5), Vector3(-0.5, 0, 0.5)], Vector3.DOWN],
		[[Vector3(-0.5, 0, -0.5), Vector3(-0.5, 0, 0.5), Vector3(-0.5, mid, 0.5), Vector3(-0.5, rise, -0.5)], Vector3.LEFT],
		[[Vector3(-0.5, 0, -0.5), Vector3(0.5, 0, -0.5), Vector3(0.5, mid, -0.5), Vector3(-0.5, rise, -0.5)], Vector3.FORWARD],
		[[Vector3(0.5, 0, -0.5), Vector3(0.5, mid, -0.5), Vector3(0.5, 0, 0.5)], Vector3.RIGHT],
		[[Vector3(-0.5, 0, 0.5), Vector3(-0.5, mid, 0.5), Vector3(0.5, 0, 0.5)], Vector3.BACK],
	]


## Thin wall along the -Z edge (or the -X edge with on_x).
static func _wall_faces(h: float, on_x := false) -> Array:
	return _edge_box(-0.5, 0.5, 0.0, h, 0.12, on_x)


static func _doorway_faces() -> Array:
	return _edge_box(-0.5, -0.2, 0.0, 1.0, 0.12) + _edge_box(0.2, 0.5, 0.0, 1.0, 0.12) \
		+ _edge_box(-0.2, 0.2, 0.8, 1.0, 0.12)


## Posts and two rails along the -Z edge (or the -X edge with on_x).
static func _fence_faces(on_x := false) -> Array:
	var faces := []
	for x in [-0.5, -0.04, 0.42]:
		faces.append_array(_edge_box(x, x + 0.08, 0.0, 0.5, 0.08, on_x))
	faces.append_array(_edge_box(-0.5, 0.5, 0.18, 0.26, 0.05, on_x))
	faces.append_array(_edge_box(-0.5, 0.5, 0.36, 0.44, 0.05, on_x))
	return faces


## Box hugging the -Z edge: from x0 to x1 along it, y0 to y1 high, depth deep.
static func _edge_box(x0: float, x1: float, y0: float, y1: float, depth: float, on_x := false) -> Array:
	if on_x:
		return _box_faces(Vector3(-0.5, y0, x0), Vector3(-0.5 + depth, y1, x1))
	return _box_faces(Vector3(x0, y0, -0.5), Vector3(x1, y1, -0.5 + depth))


## Stone counter with two posts and a plank awning.
static func _shop_faces() -> Array:
	var faces := _box_faces(Vector3(-0.45, 0, -0.3), Vector3(0.45, 0.6, 0.3))
	for x in [-0.45, 0.37]:
		faces.append_array(_box_faces(Vector3(x, 0.6, 0.22), Vector3(x + 0.08, 0.92, 0.3)))
	faces.append_array(_box_faces(Vector3(-0.5, 0.92, -0.1), Vector3(0.5, 1.0, 0.45)))
	return faces


## Plank deck at the top of the cell with railings along both sides (+-X).
static func _bridge_faces() -> Array:
	var faces := _box_faces(Vector3(-0.5, 1.0 - BRIDGE_THICKNESS, -0.5), Vector3(0.5, 1, 0.5))
	for x in [-0.5, 0.44]:
		faces.append_array(_box_faces(Vector3(x, 1.3, -0.5), Vector3(x + 0.06, 1.38, 0.5)))
		faces.append_array(_box_faces(Vector3(x, 1.0, -0.04), Vector3(x + 0.06, 1.3, 0.04)))
	return faces


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


static func _upward_face(pts: Array) -> Array:
	var n: Vector3 = (pts[1] - pts[0]).cross(pts[2] - pts[0]).normalized()
	return [pts, n if n.y > 0.0 else -n]


static func _upward_tri(a: Vector3, b: Vector3, c: Vector3) -> Array:
	var n := (b - a).cross(c - a).normalized()
	return [[a, b, c], n if n.y > 0.0 else -n]


## Steps climbing toward -Z from base to base + rise.
static func _stairs_faces(rise: float, steps: int, base := 0.0) -> Array:
	var faces := []
	var depth := 1.0 / steps
	for i in steps:
		var z_front := 0.5 - i * depth
		faces.append_array(_box_faces(
			Vector3(-0.5, 0, z_front - depth),
			Vector3(0.5, base + rise * (i + 1) / steps, z_front)))
	return faces
