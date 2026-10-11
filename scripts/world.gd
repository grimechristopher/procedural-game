class_name GridWorld
extends GridMap

## Builds its own MeshLibrary of basic blocks and generates the world: open
## terrain shaped by Terrain (hills, terraced mountains, lakes and an ocean
## round the edge), with a settlement at the centre (farm, plaza, town).
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
	# Invisible solid cells under a building's footprint (the building
	# itself is a mesh; see Buildings). The door cell is tagged.
	BUILDING, BUILDING_DOOR,
	# A full block topped with bare rock, for high ground.
	ROCK,
	# A wedge cut through only the top half of a block, its bottom half solid:
	# the corner of a half cliff rising from half height.
	UPPER_HALF_WEDGE,
	# Grassy ramp from half height to the top of the block (the hill
	# counterpart of UPPER_HALF_RAMP).
	UPPER_HALF_HILL_RAMP,
	# Props sunk half a block, for half-height ground.
	TREE_LOW, SNOW_TREE_LOW, BOULDER_LOW, BUSH_LOW, TALL_GRASS_LOW,
	# The foot of an HGSS-style cliff, whose face slopes down across this
	# cell (drawn by TerrainMesh): solid, and otherwise invisible.
	BANK,
}

## Prop tiles, in the order of their sprites in assets/props.png.
const PROP_SPRITES := [Tile.TREE, Tile.SNOW_TREE, Tile.BOULDER, Tile.BUSH, Tile.TALL_GRASS]
## Each prop's sunken version, for standing on a half block.
const PROP_LOW := {
	Tile.TREE: Tile.TREE_LOW, Tile.SNOW_TREE: Tile.SNOW_TREE_LOW, Tile.BOULDER: Tile.BOULDER_LOW,
	Tile.BUSH: Tile.BUSH_LOW, Tile.TALL_GRASS: Tile.TALL_GRASS_LOW,
}
## Solid props a path can be cleared through.
const CLEARABLE := [Tile.TREE, Tile.SNOW_TREE, Tile.BOULDER, Tile.BUSH,
	Tile.TREE_LOW, Tile.SNOW_TREE_LOW, Tile.BOULDER_LOW, Tile.BUSH_LOW]
## Ramps the terrain uses to climb a half or whole step.
const HILL_RAMPS := [Tile.HILL_RAMP, Tile.HALF_HILL_RAMP, Tile.UPPER_HALF_HILL_RAMP]
const PROP_SPRITE_SIZE := Vector2i(32, 48)
## The pitch is HGSS's and Platinum's field camera (see FollowCamera).
const CAMERA_PITCH_DEGREES := 59.05
## Sprites (props, crops, the player) stand upright and are stretched by
## tan(pitch), so on screen their texels are as tall as the ground's and the
## player stands just under two tiles tall.
const SPRITE_STRETCH := tan(deg_to_rad(CAMERA_PITCH_DEGREES))

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
	Tile.TALL_GRASS_LOW: [&"tall_grass"],
	Tile.BUILDING_DOOR: [&"door"],
}

## Tiles in assets/tileset.png (see tools/make_tileset.py), left to right,
## top to bottom.
enum Tex {
	GRASS, GRASS_SIDE, DIRT, PATH, FLOWERS, STONE, PLANKS, TILLED, TILLED_WET, SOIL,
	THATCH, SHINGLE, PLASTER, WINDOW, DOOR_TOP, DOOR_BOTTOM, FIELDSTONE, EMBERS,
	EARTH_SIDE,
	# Cliff-top autotile pieces (see TerrainMesh).
	CLIFF_EDGE, CLIFF_OUTER, CLIFF_INNER, EARTH_EDGE, EARTH_OUTER, EARTH_INNER,
	# Grass creeping over the edges of paths, the plaza and farmland (see TerrainMesh).
	GRASS_EDGE, GRASS_OUTER, GRASS_INNER,
	# Bare rock seen from above, topping high ground.
	ROCK_TOP,
	# Diagonal cliff-top pieces: a wedge's top, and the joint between two
	# wedges (see TerrainMesh).
	CLIFF_DIAG, CLIFF_JOINT, EARTH_DIAG, EARTH_JOINT,
	# The rock of an HGSS-style bank, sloping across a cell (see TerrainMesh).
	BANK_ROCK,
	# Square cliff-top corners where a cliff line carries on past an outside
	# corner at a lower level (see TerrainMesh).
	CLIFF_TEE, EARTH_TEE,
	# The cliff-top pieces on bare-rock high ground: rock inside the band.
	ROCK_EDGE, ROCK_OUTER, ROCK_INNER, ROCK_JOINT, ROCK_TEE, ROCK_DIAG,
	# Contour lines laid over ramps, across the climb (see-through elsewhere).
	SLOPE_LINES,
	# The rock of slopes on high ground: rough chunks, not strata.
	BANK_BOULDERS,
}
const TEX_COLS := 4
const TEX_ROWS := 11

const TILESET := preload("res://assets/tileset.png")
const BLOCK_SHADER := preload("res://assets/block.gdshader")
const WATER_SHADER := preload("res://assets/water.gdshader")
const WATER_TEXTURE := preload("res://assets/water.png")
const PROPS_TEXTURE := preload("res://assets/props.png")

const GROUND_LAYER := -1
const TOP_LAYER := 12
const STAIR_STEPS := 4
const HEADROOM := 1.0
const BRIDGE_THICKNESS := 0.15
const EPS := 0.001
const NO_MOVE := -999

@export var map_size := Vector2i(96, 96)
@export var map_seed := 1

## Terrain levels off to flat ground within this many cells of spawn, for
## the settlement, blending back to the wild over the next SETTLEMENT_BLEND.
const SETTLEMENT_RADIUS := 15.0
const SETTLEMENT_BLEND := 8.0
## Cells over which the land falls away into ocean at the map's edge.
const ISLAND_FALLOFF := 16.0
## The sea round the map: water this far in from the edge (cells), the
## shoreline wandering this far either way, then a strip of ground at sea
## level this wide before the land rises (over ISLAND_FALLOFF).
const COAST_WATER := 5.0
const COAST_WOBBLE := 3.0
const COAST_BEACH := 2.0
## Elevation slopes (blocks per cell) past which ground gets full cliffs:
## stepping back, then stacked two high, then three. Each keeps shelves
## between cliffs about two cells wide or more (half cliffs at a quarter
## block per cell come every two cells).
const STEEP_SLOPE := 0.25
const SHEER_SLOPE := 0.6
const WALL_SLOPE := 0.95
## How far either side of a cell its slope is measured, so patches of
## cliffs come out whole rather than speckled.
const STEEP_REACH := 2
## Terrain.wall_lean above which walls taller than a block slope (as
## staircases of banks) on every side, and above which they slope on their
## east and west sides (which, standing vertical, the camera sees edge on).
## Steps a block high always slope.
const SLOPE_ALL := 0.15
const SLOPE_SIDES := -0.2
## Highest ground, in blocks.
const MAX_HEIGHT := 10
## Ground this many blocks high or higher is bare rock.
@export var rock_level := 5
## Chance a usable cliff step gets a ramp up it, before the connectivity pass.
const RAMP_CHANCE := 0.03
## Cells to either side of a ramp kept clear of other ramps.
const RAMP_GAP := 2
## Unreachable pockets this small (cells) get levelled if no ramp fits
## (and up to twice this, once nothing else will join).
const SMALL_POCKET := 30
const ORTHOGONAL: Array[Vector2i] = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
const DIAGONAL: Array[Vector2i] = [Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]

var spawn_cell := Vector2i.ZERO

## Buildings in the current map: { name, rect, door } (door: the footprint
## cell with the door, interacted with from the cell south of it).
var buildings: Array[Dictionary] = []

var _block_material: ShaderMaterial
var _building_meshes: Node3D
var _edges: Node3D
## Ground heights from the last generate, in half blocks (-1 is water).
var height_map := PackedInt32Array()
## How deep the plateau beside a corridor must be (see _walled).
var _corridor_walls := 2
## Per cell, a bit per ORTHOGONAL side whose full cliff slopes (banks) rather
## than standing vertical.
var _slope_sides := PackedByteArray()
## Cells _slope_walls raised into a slope's staircase (all slope, no ground
## to walk on).
var _raised := PackedByteArray()
## Banks the connector took away this time round (see _restore_banks).
var _peeled: Array[Vector2i] = []
## Leaves terrain blocks undrawn in the GridMap, for TerrainMesh to draw.
## (Off for hand-built test maps, which have no terrain mesh.)
@export var hide_terrain_blocks := true
## Per cell, how far (in steps) the ground may drop to a side neighbour.
var _max_drop := PackedInt32Array()


func _ready() -> void:
	cell_size = Vector3.ONE
	cell_center_y = false
	mesh_library = _build_mesh_library()
	_building_meshes = Node3D.new()
	_building_meshes.name = "Buildings"
	add_child(_building_meshes)
	generate(map_seed)


# --- Generation -------------------------------------------------------------

func generate(new_seed: int) -> void:
	clear()
	buildings.clear()
	for mesh in _building_meshes.get_children():
		mesh.queue_free()
	if _edges:
		_edges.queue_free()
	var rng := RandomNumberGenerator.new()
	rng.seed = new_seed
	var terrain := Terrain.new(new_seed)
	spawn_cell = map_size / 2

	var heights := _shape_heights(terrain)
	_slope_walls(terrain, heights)
	_build_terrain(terrain, heights)

	var reserved := {}
	for x in range(spawn_cell.x - 2, spawn_cell.x + 3):
		for z in range(spawn_cell.y - 2, spawn_cell.y + 3):
			reserved[Vector2i(x, z)] = true
	var approaches: Array[Vector2i] = []
	_place_farm(reserved, approaches)
	_place_town(reserved, approaches)
	for walled in [true, false]:
		for attempt in 40:
			if _try_place_enclosure(rng, reserved, approaches, walled):
				break
	_decorate_ground(rng, approaches)
	for x in range(spawn_cell.x - 1, spawn_cell.x + 2):
		for z in range(spawn_cell.y - 1, spawn_cell.y + 2):
			set_cell_item(Vector3i(x, GROUND_LAYER, z), Tile.PLAZA)
	_place_scenery(terrain, heights, reserved)
	_smooth_fins(heights, reserved)
	_connect_everything(heights, reserved)
	_fill_bank_notches(heights, reserved)
	_check_wedges(heights)
	_bury_covered_blocks()
	height_map = heights
	_edges = TerrainMesh.build(self, heights, terrain)
	add_child(_edges)


# --- Terrain ------------------------------------------------------------------

## Heights per cell, in half blocks ("steps"): 0 is ground level, 1 half a
## block up, 2 a block, -1 water. Gentle ground climbs in half cliffs (one
## step); cliffy ground in full cliffs (whole blocks), which stack up to
## Terrain.cliff_tiers blocks straight up where the noise says so, or step
## back one block at a time.
##
## Built from the terrain's elevation, flattened round the settlement, sunk
## into ocean at the edges, given full cliffs wherever it's steep,
## terraced so no cell drops further than its
## cliffs allow, and smoothed of one-cell knobs and pits.
func _shape_heights(terrain: Terrain) -> PackedInt32Array:
	var heights := PackedInt32Array()
	heights.resize(map_size.x * map_size.y)
	_max_drop.resize(map_size.x * map_size.y)
	var elevation := PackedFloat32Array()
	elevation.resize(map_size.x * map_size.y)
	for z in map_size.y:
		for x in map_size.x:
			var e := terrain.elevation(x, z)
			# The sea round the map: a wandering shoreline, a strip of ground
			# at sea level along it, and the land rising gently inland.
			var edge := minf(minf(x, map_size.x - 1 - x), minf(z, map_size.y - 1 - z)) \
				+ terrain.coast_wobble(x, z) * COAST_WOBBLE
			if edge < COAST_WATER:
				e = -1.0
			else:
				e = lerpf(0.25, e, smoothstep(0.0, 1.0, (edge - COAST_WATER - COAST_BEACH) / ISLAND_FALLOFF))
			var d := Vector2(x, z).distance_to(Vector2(spawn_cell))
			elevation[z * map_size.x + x] = lerpf(0.25, e, smoothstep(SETTLEMENT_RADIUS, SETTLEMENT_RADIUS + SETTLEMENT_BLEND, d))
	for z in map_size.y:
		for x in map_size.x:
			var i := z * map_size.x + x
			var tiers := _steep_tiers(elevation, Vector2i(x, z))
			if terrain.is_cliffy(x, z):
				tiers = maxi(tiers, terrain.cliff_tiers(x, z))
			if terrain.near_fault(x, z):
				# An escarpment: one wall, its full height.
				tiers = maxi(tiers, int(Terrain.FAULT_HEIGHT))
			_max_drop[i] = 2 * tiers if tiers > 0 else 1
	for z in map_size.y:
		for x in map_size.x:
			var i := z * map_size.x + x
			var e := elevation[i]
			if e < 0.0:
				heights[i] = -1
			elif _max_drop[i] > 1:
				# Rounded to whole stacks of cliffs, so where they stack the
				# ground rises in tall walls with wide shelves between.
				var tiers := _max_drop[i] / 2
				heights[i] = 2 * mini(floori(e / tiers) * tiers, MAX_HEIGHT)
			elif _beside_cliffs(Vector2i(x, z)):
				# Half cliffs give way beside full ones, rather than leaving
				# half-block shelves squeezed between them.
				heights[i] = 2 * mini(floori(e), MAX_HEIGHT)
			else:
				heights[i] = mini(floori(e * 2.0), MAX_HEIGHT * 2)
	_terrace(heights)
	for i in 3:
		_despeckle(heights)
		_terrace(heights)
	return heights


## Cliffs for steep ground, however gentle its style: half cliffs there
## would come every cell, in rows of one-cell shelves. Full cliffs step
## back (banks) where it's steep, and stack two or three high where it's
## steeper still. 0 where half cliffs will do.
func _steep_tiers(elevation: PackedFloat32Array, cell: Vector2i) -> int:
	var slope := 0.0
	for d: Vector2i in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, -1)]:
		var a := cell + d * STEEP_REACH
		var b := cell - d * STEEP_REACH
		a = a.clamp(Vector2i.ZERO, map_size - Vector2i.ONE)
		b = b.clamp(Vector2i.ZERO, map_size - Vector2i.ONE)
		if a == b:
			continue
		var run := Vector2(a - b).length()
		var rise := absf(elevation[a.y * map_size.x + a.x] - elevation[b.y * map_size.x + b.x]) / run
		slope = maxf(slope, rise)
	if slope > WALL_SLOPE:
		return 3
	return 2 if slope > SHEER_SLOPE else (1 if slope > STEEP_SLOPE else 0)


func _beside_cliffs(cell: Vector2i) -> bool:
	for d in ORTHOGONAL:
		var n := cell + d
		if n.x >= 0 and n.y >= 0 and n.x < map_size.x and n.y < map_size.y and is_cliffy_at(n):
			return true
	return false


## Whether a cell's cliffs are full cliffs (rock), not half cliffs.
func is_cliffy_at(cell: Vector2i) -> bool:
	return _max_drop[cell.y * map_size.x + cell.x] > 1


## Lowers cells until none drops further to a side neighbour than its
## cliffs allow: a step on gentle ground, its stack of whole blocks on
## cliffy ground (which stays in whole blocks).
func _terrace(heights: PackedInt32Array) -> void:
	var changed := true
	while changed:
		changed = false
		for z in map_size.y:
			for x in map_size.x:
				var i := z * map_size.x + x
				var h := heights[i]
				if h < 1:
					continue
				var lowest := h
				for d in ORTHOGONAL:
					var n := _height_at(heights, Vector2i(x, z) + d)
					if n != -99:
						lowest = mini(lowest, maxi(n, 0))
				var top := lowest + _max_drop[i]
				if _max_drop[i] > 1:
					top -= top % 2
				if h > top:
					heights[i] = top
					changed = true


## Knocks down cells standing above three or four of their side neighbours,
## and fills in cells (or puddles) sunk below three or four of them, by a
## step (a whole block on cliffy ground).
func _despeckle(heights: PackedInt32Array) -> void:
	var source := heights.duplicate()
	for z in map_size.y:
		for x in map_size.x:
			var i := z * map_size.x + x
			var h := source[i]
			var step := 2 if _max_drop[i] > 1 else 1
			var above := 0
			var below := 0
			for d in ORTHOGONAL:
				var n := _height_at(source, Vector2i(x, z) + d)
				if n == -99:
					continue
				if n < h:
					above += 1
				elif n > h:
					below += 1
			if above >= 3 and h > 0:
				heights[i] = maxi(h - step, 0)
			elif below >= 3:
				heights[i] = h + step


## Height at a cell, in steps, or -99 outside the map.
func _height_at(heights: PackedInt32Array, cell: Vector2i) -> int:
	if cell.x < 0 or cell.y < 0 or cell.x >= map_size.x or cell.y >= map_size.y:
		return -99
	return heights[cell.y * map_size.x + cell.x]


## Stacks blocks to each cell's height, then cuts plateaus' outside corners
## diagonally and breaks the odd cliff with a ramp. (TerrainMesh draws the
## cliffs: earth faces on gentle ground, rock where the terrain is cliffy.)
func _build_terrain(terrain: Terrain, heights: PackedInt32Array) -> void:
	for z in map_size.y:
		for x in map_size.x:
			var h := heights[z * map_size.x + x]
			if h < 0:
				set_ground(Vector2i(x, z), Tile.WATER)
				continue
			set_ground(Vector2i(x, z), Tile.GROUND)
			_stack_column(Vector2i(x, z), h)
	var settled := SETTLEMENT_RADIUS + 2.0
	for z in map_size.y:
		for x in map_size.x:
			var cell := Vector2i(x, z)
			if heights[z * map_size.x + x] < 0 or Vector2(cell).distance_to(Vector2(spawn_cell)) < settled:
				continue
			_wedge_corner(cell, heights, _slope_sides[z * map_size.x + x])
	for z in map_size.y:
		for x in map_size.x:
			if heights[z * map_size.x + x] >= 0:
				_maybe_ramp(Vector2i(x, z), heights)
	for z in map_size.y:
		for x in map_size.x:
			if _slope_sides[z * map_size.x + x] != 0:
				_place_banks(Vector2i(x, z), heights)


## Picks which full cliffs slope (every step a block high; taller walls
## where SLOPE_ALL says) and builds the taller ones into slopes: a staircase of one-block banks, one cell per block,
## stepping out over the ground in front where there's room for all of it
## (so the slope runs on at 45 degrees), its outside corners wrapping round.
## Where there isn't room the wall stays vertical.
func _slope_walls(terrain: Terrain, heights: PackedInt32Array) -> void:
	_slope_sides.resize(map_size.x * map_size.y)
	_slope_sides.fill(0)
	_raised.resize(map_size.x * map_size.y)
	_raised.fill(0)
	var settled := SETTLEMENT_RADIUS + 2.0
	for z in map_size.y:
		for x in map_size.x:
			var cell := Vector2i(x, z)
			var h := heights[z * map_size.x + x]
			if h < 2 or Vector2(cell).distance_to(Vector2(spawn_cell)) < settled:
				continue
			var lean := terrain.wall_lean(x, z)
			for b in ORTHOGONAL.size():
				var d := ORTHOGONAL[b]
				var hn := _height_at(heights, cell + d)
				if hn < 0:
					continue  # into water (or off the map): vertical
				var drop := h - hn
				# Rule: a step a block high always slopes, HGSS style; taller
				# walls stand vertical unless the wall-style noise leans them.
				if drop == 2 or (drop > 2 and drop % 2 == 0 and is_cliffy_at(cell) \
						and not terrain.near_fault(x, z) \
						and (lean > SLOPE_ALL or (d.x != 0 and lean > SLOPE_SIDES))):
					_slope_sides[z * map_size.x + x] |= 1 << b
	# Grow the staircases a step at a time.
	for step in 8:
		var src := heights.duplicate()
		var src_sides := _slope_sides.duplicate()
		var changed := false
		for z in map_size.y:
			for x in map_size.x:
				var cell := Vector2i(x, z)
				var i := z * map_size.x + x
				var f := src[i]
				if f < 0 or Vector2(cell).distance_to(Vector2(spawn_cell)) < settled:
					continue
				var best := f
				var sides := 0
				for b in ORTHOGONAL.size():
					var d := ORTHOGONAL[b]
					var top := _height_at(src, cell - d) - 2
					if top <= f or (top - f) % 2 != 0 or not src_sides[(cell - d).y * map_size.x + (cell - d).x] & (1 << b):
						continue
					var room := true
					for m in range(1, (top - f) / 2 + 1):
						if _height_at(src, cell + d * m) != f:
							room = false
					if not room:
						continue
					if top > best:
						best = top
						sides = 0
					if top == best:
						sides |= 1 << b
				for q in DIAGONAL:
					# An outside corner between two slopes wraps round.
					var a := Vector2i(q.x, 0)
					var c := Vector2i(0, q.y)
					var top := _height_at(src, cell - q) - 2
					var bits := (1 << ORTHOGONAL.find(a)) | (1 << ORTHOGONAL.find(c))
					if top <= f or (top - f) % 2 != 0 or src_sides[(cell - q).y * map_size.x + (cell - q).x] & bits != bits \
							or _height_at(src, cell - a) < top or _height_at(src, cell - c) < top:
						continue
					if top > best:
						best = top
						sides = 0
					if top == best:
						sides |= bits
				if best > f:
					heights[i] = best
					_raised[i] = 1
					_slope_sides[i] = sides
					_max_drop[i] = maxi(_max_drop[i], 2)
					changed = true
		if not changed:
			break


## Turns a cell's one-block cliffs into HGSS-style banks: the face slopes
## down across the cell at its foot, which can't be walked on. At an outer
## corner between two banks, the diagonal cell takes the corner of the
## slope. (Ramps already in place keep their way up.)
func _place_banks(cell: Vector2i, heights: PackedInt32Array) -> void:
	var h := _height_at(heights, cell)
	var top := get_cell_item(Vector3i(cell.x, (h - 1) / 2, cell.y))
	if h < 2 or top not in [Tile.FULL, Tile.ROCK, Tile.WEDGE, Tile.WEDGE_DIRT]:
		return
	var banked: Array[Vector2i] = []
	var sides := _slope_sides[cell.y * map_size.x + cell.x]
	for b in ORTHOGONAL.size():
		var d := ORTHOGONAL[b]
		if sides & (1 << b) and _bank_foot(cell + d, h - 2, heights):
			set_cell_item(Vector3i(cell.x + d.x, (h - 2) / 2, cell.y + d.y), Tile.BANK)
			banked.append(d)
	if top in [Tile.WEDGE, Tile.WEDGE_DIRT]:
		return  # the slope runs along the diagonal instead of round a corner
	for d in DIAGONAL:
		if Vector2i(d.x, 0) in banked and Vector2i(0, d.y) in banked and _bank_foot(cell + d, h - 2, heights):
			set_cell_item(Vector3i(cell.x + d.x, (h - 2) / 2, cell.y + d.y), Tile.BANK)


## Whether a cell at the foot of a cliff can take a bank: plain ground
## (raised or not) at foot height, with nothing on it.
func _bank_foot(foot: Vector2i, foot_h: int, heights: PackedInt32Array) -> bool:
	if _height_at(heights, foot) != foot_h:
		return false
	var layer := foot_h / 2
	var item := get_cell_item(Vector3i(foot.x, layer, foot.y))
	if item != INVALID_CELL_ITEM and item != Tile.BANK:
		return false
	if foot_h == 0:
		return ground_tile(foot) in [Tile.GROUND, Tile.FLOWERS]
	return get_cell_item(Vector3i(foot.x, layer - 1, foot.y)) in [Tile.FULL, Tile.ROCK]


## Full blocks up to a height in steps, topped with a half block on odd
## steps, and bare rock on high ground.
func _stack_column(cell: Vector2i, h: int) -> void:
	var blocks := h / 2
	for layer in blocks:
		var rock := layer == blocks - 1 and h % 2 == 0 and h >= rock_level * 2
		set_cell_item(Vector3i(cell.x, layer, cell.y), Tile.ROCK if rock else Tile.FULL)
	if h % 2 == 1:
		set_cell_item(Vector3i(cell.x, blocks, cell.y), Tile.HALF)


## Cuts a plateau's outside corner at 45 degrees: a cell whose two
## neighbours on adjacent sides, and the diagonal between them, are lower,
## with level plateau on the other sides and diagonal. Where the cell's
## cliffs slope (`sloped`, its _slope_sides), only between two slopes. (Ground that keeps
## climbing diagonally stays stepped: wedging every step would leave cells
## joined only at their corners.)
func _wedge_corner(cell: Vector2i, heights: PackedInt32Array, sloped := 0) -> void:
	var h := _height_at(heights, cell)
	if h < 1:
		return
	for d in DIAGONAL:
		var a := Vector2i(d.x, 0)
		var b := Vector2i(0, d.y)
		var low := _height_at(heights, cell + a)
		var corner := _height_at(heights, cell + d)
		if low < 0 or low >= h or _height_at(heights, cell + b) != low or corner < 0 or corner > low:
			continue
		if sloped:
			# Sloped cliffs: only a diagonal between two slopes a block high
			# (the slope then runs on along the diagonal, see TerrainMesh),
			# and only on a 45-degree run of them: a shallower edge stays
			# stepped, its corners wrapped round, as HGSS draws it.
			var bits := (1 << ORTHOGONAL.find(a)) | (1 << ORTHOGONAL.find(b))
			if sloped & bits != bits or h - low != 2:
				continue
			var run := false
			for along: Vector2i in [Vector2i(d.x, -d.y), Vector2i(-d.x, d.y)]:
				var n := cell + along
				if _height_at(heights, n) == h and _height_at(heights, n + a) == low \
						and _height_at(heights, n + b) == low:
					run = true
			if not run:
				continue
		# Level plateau behind (or, within a slope's staircase, plateau or
		# more slope rising behind it).
		var behind := [_height_at(heights, cell - a), _height_at(heights, cell - b), _height_at(heights, cell - d)]
		var within := sloped and _raised[cell.y * map_size.x + cell.x] == 1
		# (On a slope, the cell diagonally behind may rise higher still.)
		if sloped and behind[0] == h and behind[1] == h and behind[2] > h:
			behind[2] = h
		if behind.all(func(hb: int) -> bool: return hb == h or (within and hb > h)):
			_wedge_column(cell, low, h, -d)
			return


## Fills banks boxed in on three sides by ground a block above them (a
## one-cell notch, which would be a flat patch of slope nobody can walk
## on) up level with that ground. Safe after joining: a bank isn't walked
## on, and the filled cell joins the ground round it.
func _fill_bank_notches(heights: PackedInt32Array, reserved: Dictionary) -> void:
	for z in range(1, map_size.y - 1):
		for x in range(1, map_size.x - 1):
			var c := Vector2i(x, z)
			var h := _height_at(heights, c)
			if h < 0 or reserved.has(c) or not _has_bank(c, h):
				continue
			var above := 0
			for d in ORTHOGONAL:
				if _height_at(heights, c + d) == h + 2 and not _ramp_near_cell(c + d):
					above += 1
			if above < 3:
				continue
			for layer in range(0, TOP_LAYER + 1):
				set_cell_item(Vector3i(c.x, layer, c.y), INVALID_CELL_ITEM)
			_stack_column(c, h + 2)
			heights[c.y * map_size.x + c.x] = h + 2
			for n in ORTHOGONAL + DIAGONAL:
				if _height_at(heights, c + n) >= 0:
					_unshape(c + n, heights)


## Squares off diagonal cuts that no longer sit on a corner (the ground
## round them changed after they were cut: a corridor, a levelled pocket).
func _check_wedges(heights: PackedInt32Array) -> void:
	for z in map_size.y:
		for x in map_size.x:
			var cell := Vector2i(x, z)
			var h := heights[z * map_size.x + x]
			if h < 1:
				continue
			var layer := (h - 1) / 2
			if not _is_wedge(get_cell_item(Vector3i(x, layer, z))):
				continue
			var s := _corner_dir(cell, layer)
			var low_a := _height_at(heights, cell - Vector2i(s.x, 0))
			var low_b := _height_at(heights, cell - Vector2i(0, s.y))
			var corner := _height_at(heights, cell - s)
			if low_a < 0 or low_a >= h or low_b != low_a or corner < 0 or corner > low_a:
				_unshape(cell, heights)


## Swaps the blocks of a column between heights low and high (in steps)
## for wedges with their solid corner toward solid: whole wedges, a half
## wedge on a half block, or an upper-half wedge where the cut starts
## halfway up a block.
func _wedge_column(cell: Vector2i, low: int, high: int, solid: Vector2i) -> void:
	for layer in range(low / 2, (high + 1) / 2):
		var cut_from_middle := low > layer * 2
		var half_block := high < layer * 2 + 2
		var tile := Tile.UPPER_HALF_WEDGE if cut_from_middle else (Tile.HALF_WEDGE if half_block else Tile.WEDGE)
		set_corner(cell, layer, tile, solid)


## Now and then breaks a cliff with a grassy ramp at its foot, where
## there's level ground behind to walk up from. (Stairs are for man-made
## places, so the wild never gets them.)
func _maybe_ramp(cell: Vector2i, heights: PackedInt32Array) -> void:
	for d in ORTHOGONAL:
		if Terrain.cell_hash(cell.x, cell.y, d.x * 3 + d.y) < RAMP_CHANCE:
			if _place_ramp(_ramp_pieces(cell, d, heights), d):
				return


## The ramp that would climb from cell up the cliff toward dir, from level
## ground onto level ground a half or whole block higher, as pieces
## [cell, tile, layer]; or [] if none fits. Ramps climb half a block per
## cell: a half cliff in one cell (a half block becomes a ramp up from half
## height), a full cliff over two, cell and the one behind it. Nothing
## climbs a whole block from half height.
func _ramp_pieces(cell: Vector2i, dir: Vector2i, heights: PackedInt32Array, reserved := {}) -> Array:
	var h := _height_at(heights, cell)
	var up := _height_at(heights, cell + dir)
	var rise := up - h
	if h < 0 or _height_at(heights, cell - dir) != h or (rise != 1 and rise != 2):
		return []
	if rise == 2 and h % 2 == 1:
		return []
	var above := cell + dir
	if get_cell_item(Vector3i(above.x, (up - 1) / 2, above.y)) not in [Tile.FULL, Tile.ROCK, Tile.HALF]:
		return []  # the top of the cliff is a wedge or otherwise not walkable
	var layer := h / 2
	if h % 2 == 1:
		if reserved.has(cell) or get_cell_item(Vector3i(cell.x, layer, cell.y)) != Tile.HALF \
				or get_cell_item(Vector3i(cell.x, layer + 1, cell.y)) != INVALID_CELL_ITEM:
			return []
		return [[cell, Tile.UPPER_HALF_HILL_RAMP, layer]]
	if not _ramp_room(cell, layer, h, reserved):
		return []
	if rise == 1:
		return [[cell, Tile.HALF_HILL_RAMP, layer]]
	var out := cell - dir
	if _height_at(heights, out - dir) != h or not _ramp_room(out, layer, h, reserved):
		return []
	return [[cell, Tile.UPPER_HALF_HILL_RAMP, layer], [out, Tile.HALF_HILL_RAMP, layer]]


## Whether a ramp can start on a cell's ground (a bank there gives way).
func _ramp_room(cell: Vector2i, layer: int, h: int, reserved: Dictionary) -> bool:
	if reserved.has(cell) or get_cell_item(Vector3i(cell.x, layer, cell.y)) not in [INVALID_CELL_ITEM, Tile.BANK]:
		return false
	return h > 0 or ground_tile(cell) == Tile.GROUND or ground_tile(cell) == Tile.FLOWERS


## Lays a ramp's pieces, rising toward dir; false if there are none.
func _place_ramp(pieces: Array, dir: Vector2i, surface := []) -> bool:
	for piece in pieces:
		if _ramp_beside(piece[0], dir):
			return false
	for piece in pieces:
		var c: Vector2i = piece[0]
		set_slope(c, piece[2], piece[1], dir)
		if not surface.is_empty():
			surface[c.y * map_size.x + c.x] = _top_surface(c)
	return not pieces.is_empty()


## Forests, boulders, bushes and tall grass on level ground, away from
## cliffs (so ramps stay approachable) and anything reserved. Props on a
## half block are sunk to stand on it.
func _place_scenery(terrain: Terrain, heights: PackedInt32Array, reserved: Dictionary) -> void:
	for z in range(1, map_size.y - 1):
		for x in range(1, map_size.x - 1):
			var cell := Vector2i(x, z)
			var h := heights[z * map_size.x + x]
			var layer := (h + 1) / 2
			if h < 0 or reserved.has(cell) or get_cell_item(Vector3i(x, layer, z)) != INVALID_CELL_ITEM:
				continue
			if h == 0 and ground_tile(cell) != Tile.GROUND and ground_tile(cell) != Tile.FLOWERS:
				continue
			if h % 2 == 1 and get_cell_item(Vector3i(x, h / 2, z)) != Tile.HALF:
				continue
			var level := true
			for d in ORTHOGONAL:
				if _height_at(heights, cell + d) != h \
						or get_cell_item(Vector3i(x + d.x, h / 2, z + d.y)) in HILL_RAMPS:
					level = false
			if not level:
				continue
			var prop := -1
			var roll := Terrain.cell_hash(x, z, 7)
			if roll < terrain.forest(x, z):
				prop = Tile.TREE
			elif roll > 0.985:
				prop = Tile.BOULDER if h >= rock_level * 2 or roll > 0.993 else Tile.BUSH
			elif terrain.is_tall_grass(x, z):
				prop = Tile.TALL_GRASS
			if prop >= 0:
				set_cell_item(Vector3i(x, layer, z), PROP_LOW[prop] if h % 2 == 1 else prop)


## Makes sure everything on land can be walked to from spawn. Each round
## finds the separate pockets of ground that can't be reached and joins
## each to the reachable area once: with a ramp where it's a block higher
## or lower, or by clearing a tree or rock that walls it off. Small pockets
## that can't take a ramp (knobs and pits left by the noise) are levelled
## to the ground beside them instead. Only land cut off by water stays
## unreachable.
func _connect_everything(heights: PackedInt32Array, reserved: Dictionary) -> void:
	var surface := []
	surface.resize(map_size.x * map_size.y)
	for z in map_size.y:
		for x in map_size.x:
			surface[z * map_size.x + x] = _top_surface(Vector2i(x, z))
	_peeled.clear()
	var level_limit := SMALL_POCKET
	for attempt in 40:
		if attempt == 30:
			level_limit = SMALL_POCKET * 2
		var reached := _reach(surface, PackedByteArray(), spawn_cell)
		var pockets := _label_pockets(surface, reached)
		var members := {}
		for i in pockets.size():
			if pockets[i] != 0:
				if not members.has(pockets[i]):
					members[pockets[i]] = []
				members[pockets[i]].append(Vector2i(i % map_size.x, i / map_size.x))
		var joined := 0
		for pocket in members:
			var cells: Array = members[pocket]
			# The gentlest way in from anywhere round the pocket first: a ramp
			# or clearing before cutting a corridor into a cliff.
			# Corridors keep plateau two cells deep either side where they
			# can, one where that's all there is.
			var done := false
			for depth in [2, 1]:
				_corridor_walls = depth
				for cut in [false, true]:
					for cell in cells:
						if _join(cell, reached, surface, heights, reserved, cut):
							done = true
							break
					if done:
						break
				if not done:
					for cell in cells:
						if _carve_join(cell, reached, surface, heights, reserved):
							done = true
							break
				if done:
					break
			if not done:
				# Last, take a bank away, to climb the cliff behind it next time.
				for cell in cells:
					if _join(cell, reached, surface, heights, reserved, true, true):
						done = true
						break
			if not done and cells.size() <= level_limit:
				done = _level_pocket(cells, reached, surface, heights, reserved)
			if done:
				joined += 1
				# Pockets beside it can join it now, rather than each finding
				# its own way in.
				_grow_reach(surface, reached, cells)
		if joined == 0:
			if level_limit > SMALL_POCKET:
				break
			# Stuck (or nearly out of tries, above): level somewhat bigger
			# pockets too, as a last resort.
			level_limit = SMALL_POCKET * 2
	_restore_banks(surface, heights)


## Puts back the banks _join took away (to climb the cliff behind them)
## where nothing came of it: no ramp took their place and every bit of
## ground reached without them is still reached with them.
func _restore_banks(surface: Array, heights: PackedInt32Array) -> void:
	var before := _reach(surface, PackedByteArray(), spawn_cell)
	var restored: Array[Vector2i] = []
	for r in _peeled:
		var h := _height_at(heights, r)
		var pos := Vector3i(r.x, h / 2, r.y)
		if h < 0 or h % 2 == 1 or get_cell_item(pos) != INVALID_CELL_ITEM or restored.has(r):
			continue
		for d in ORTHOGONAL:
			if _height_at(heights, r + d) == h + 2:
				set_cell_item(pos, Tile.BANK)
				surface[r.y * map_size.x + r.x] = _top_surface(r)
				restored.append(r)
				break
	# Take back those beside ground that got cut off: one per cut-off
	# area each round (reopening one is often enough), until none is.
	for round in 16:
		if restored.is_empty():
			return
		# (Late on, every one beside a cut-off area, so nothing stays cut off.)
		var careful := round < 8
		var after := _reach(surface, PackedByteArray(), spawn_cell)
		var area := {}
		var undo: Array[Vector2i] = []
		for r in restored:
			for d in ORTHOGONAL:
				var n := r + d
				var i := n.y * map_size.x + n.x
				if _height_at(heights, n) < 0 or not before[i] or after[i]:
					continue
				var key := _lost_area(n, before, after, area)
				if not careful or not area.has(-key - 1):
					area[-key - 1] = true
					undo.append(r)
				break
		if undo.is_empty():
			return
		for r in undo:
			var h := _height_at(heights, r)
			set_cell_item(Vector3i(r.x, h / 2, r.y), INVALID_CELL_ITEM)
			surface[r.y * map_size.x + r.x] = _top_surface(r)
			restored.erase(r)


## Labels the area of ground (reached before, not after) holding cell, by
## its lowest cell index, caching labels in `area` (index -> label).
func _lost_area(cell: Vector2i, before: PackedByteArray, after: PackedByteArray, area: Dictionary) -> int:
	var start := cell.y * map_size.x + cell.x
	if area.has(start):
		return area[start]
	var seen: Array[int] = [start]
	var frontier: Array[Vector2i] = [cell]
	var lowest := start
	var visited := {start: true}
	while not frontier.is_empty():
		var c: Vector2i = frontier.pop_back()
		for d in ORTHOGONAL:
			var n := c + d
			if n.x < 0 or n.y < 0 or n.x >= map_size.x or n.y >= map_size.y:
				continue
			var i := n.y * map_size.x + n.x
			if visited.has(i) or not before[i] or after[i]:
				continue
			visited[i] = true
			seen.append(i)
			lowest = mini(lowest, i)
			frontier.append(n)
	for i in seen:
		area[i] = lowest
	return lowest


## The highest surface in a column (terrain has one per column), found
## from the top down rather than by testing every layer.
func _top_surface(cell: Vector2i) -> Dictionary:
	for layer in range(TOP_LAYER, GROUND_LAYER - 1, -1):
		var item := get_cell_item(Vector3i(cell.x, layer, cell.y))
		if item == INVALID_CELL_ITEM or _is_thin(item) or _is_tall_grass(item):
			continue
		return _surface(cell, layer)
	return {}


## Cells reachable from start, walking through matching edges. With a
## non-empty `within`, only cells marked there are entered.
func _reach(surface: Array, within: PackedByteArray, start: Vector2i) -> PackedByteArray:
	var reached := PackedByteArray()
	reached.resize(map_size.x * map_size.y)
	reached[start.y * map_size.x + start.x] = 1
	var frontier: Array[Vector2i] = [start]
	while not frontier.is_empty():
		var c: Vector2i = frontier.pop_back()
		var sc: Dictionary = surface[c.y * map_size.x + c.x]
		for d in ORTHOGONAL:
			var n := c + d
			if n.x < 0 or n.y < 0 or n.x >= map_size.x or n.y >= map_size.y:
				continue
			var i := n.y * map_size.x + n.x
			if reached[i] or (not within.is_empty() and not within[i]):
				continue
			var e := _edge(sc, d)
			if not is_nan(e) and is_equal_approx(_edge(surface[i], -d), e):
				reached[i] = 1
				frontier.append(n)
	return reached


## Spreads `reached` from reached ground beside the given cells into
## whatever it now connects to (after a join changed the ground there).
func _grow_reach(surface: Array, reached: PackedByteArray, around: Array) -> void:
	var frontier: Array[Vector2i] = []
	for c: Vector2i in around:
		for d in ORTHOGONAL:
			var n := c + d
			if n.x >= 0 and n.y >= 0 and n.x < map_size.x and n.y < map_size.y \
					and reached[n.y * map_size.x + n.x]:
				frontier.append(n)
	while not frontier.is_empty():
		var c: Vector2i = frontier.pop_back()
		var sc: Dictionary = surface[c.y * map_size.x + c.x]
		for d in ORTHOGONAL:
			var n := c + d
			if n.x < 0 or n.y < 0 or n.x >= map_size.x or n.y >= map_size.y:
				continue
			var i := n.y * map_size.x + n.x
			if reached[i]:
				continue
			var e := _edge(sc, d)
			if not is_nan(e) and is_equal_approx(_edge(surface[i], -d), e):
				reached[i] = 1
				frontier.append(n)


## Whether you can walk from cell c to its neighbour toward d.
func _links(surface: Array, c: Vector2i, d: Vector2i) -> bool:
	var n := c + d
	if n.x < 0 or n.y < 0 or n.x >= map_size.x or n.y >= map_size.y:
		return false
	var e := _edge(surface[c.y * map_size.x + c.x], d)
	return not is_nan(e) and is_equal_approx(_edge(surface[n.y * map_size.x + n.x], -d), e)


## Numbers the separate pockets of walkable ground that weren't reached
## (0 for reached or unwalkable cells).
func _label_pockets(surface: Array, reached: PackedByteArray) -> PackedInt32Array:
	var labels := PackedInt32Array()
	labels.resize(map_size.x * map_size.y)
	var unreached := PackedByteArray()
	unreached.resize(map_size.x * map_size.y)
	for i in labels.size():
		unreached[i] = 1 if not reached[i] and not surface[i].is_empty() else 0
	var next := 0
	for i in labels.size():
		if not unreached[i] or labels[i] != 0:
			continue
		next += 1
		var pocket := _reach(surface, unreached, Vector2i(i % map_size.x, i / map_size.x))
		for k in pocket.size():
			if pocket[k]:
				labels[k] = next
				unreached[k] = 0
	return labels


## Brings a small pocket level with reachable flat ground beside it (or,
## failing that, with the ground most of its sides meet), restacking each
## cell, and undoes wedges and ramps around it that were shaped for the
## old heights.
func _level_pocket(cells: Array, reached: PackedByteArray, surface: Array, heights: PackedInt32Array,
		reserved: Dictionary) -> bool:
	# The reachable flat ground beside it nearest its own height (however
	# far, so a small knob between tall walls comes down too).
	var target := -99
	var gap := 99
	for c in cells:
		for d in ORTHOGONAL:
			var r: Vector2i = c + d
			var hr := _height_at(heights, r)
			var ri := r.y * map_size.x + r.x
			var g := absi(hr - _height_at(heights, c))
			if hr >= 0 and reached[ri] and _rise(surface[ri].get("tile", -1)) == 0.0 and not surface[ri].is_empty() \
					and g > 0 and g < gap:
				target = hr
				gap = g
	if target == -99:
		# Nothing reachable and flat beside it (it's boxed in by slopes):
		# level it with the most common height around it instead.
		var votes := {}
		for c in cells:
			for d in ORTHOGONAL:
				var hn := _height_at(heights, c + d)
				var hc := _height_at(heights, c)
				if hn >= 0 and hn != hc and absi(hn - hc) <= 2:
					votes[hn] = votes.get(hn, 0) + 1
		for hn in votes:
			if target == -99 or votes[hn] > votes[target]:
				target = hn
	if target == -99:
		return false
	for c in cells:
		var h := _height_at(heights, c)
		if h == target or reserved.has(c):
			continue
		for layer in range(0, TOP_LAYER + 1):
			set_cell_item(Vector3i(c.x, layer, c.y), INVALID_CELL_ITEM)
		_stack_column(c, target)
		heights[c.y * map_size.x + c.x] = target
		for d in ORTHOGONAL + DIAGONAL + [Vector2i.ZERO]:
			var n: Vector2i = c + d
			if _height_at(heights, n) < 0:
				continue
			_unshape(n, heights)
			surface[n.y * map_size.x + n.x] = _top_surface(n)
	return true


## Turns a column's wedges back into blocks, and takes out ramps that no
## longer lead up a cliff, after the heights around it changed.
func _unshape(cell: Vector2i, heights: PackedInt32Array) -> void:
	var h := _height_at(heights, cell)
	for layer in range(0, TOP_LAYER + 1):
		var pos := Vector3i(cell.x, layer, cell.y)
		var item := get_cell_item(pos)
		match item:
			Tile.WEDGE, Tile.WEDGE_DIRT, Tile.UPPER_HALF_WEDGE:
				set_cell_item(pos, Tile.FULL)
			Tile.HALF_WEDGE:
				set_cell_item(pos, Tile.HALF)
			Tile.HILL_RAMP, Tile.HALF_HILL_RAMP, Tile.UPPER_HALF_HILL_RAMP:
				# Still leading up a cliff (a full cliff's lower half leads on
				# to its upper half)?
				var up := cell + _up_dir(cell, layer)
				var rise := 2 if item == Tile.HILL_RAMP or (item == Tile.UPPER_HALF_HILL_RAMP and h % 2 == 0) else 1
				var leads := _height_at(heights, up) == h + rise
				if item == Tile.HALF_HILL_RAMP and get_cell_item(Vector3i(up.x, layer, up.y)) == Tile.UPPER_HALF_HILL_RAMP:
					leads = true
				if not leads:
					set_cell_item(pos, Tile.HALF if item == Tile.UPPER_HALF_HILL_RAMP and h % 2 == 1 else INVALID_CELL_ITEM)
			Tile.BANK:
				# Only at the foot of a cliff a block high.
				var still := false
				for d in ORTHOGONAL + DIAGONAL:
					if _height_at(heights, cell + d) == h + 2:
						still = true
				if not still or layer != h / 2:
					set_cell_item(pos, INVALID_CELL_ITEM)


## Joins the pocket containing u to reachable ground next to it, if it
## can: a ramp up or down a half or whole block, or clearing a tree or rock
## between u and reachable ground at the same level; with `cut`, also a
## corridor up a taller wall; with `peel`, also taking away a bank that's
## in the way.
func _join(u: Vector2i, reached: PackedByteArray, surface: Array, heights: PackedInt32Array,
		reserved: Dictionary, cut := false, peel := false) -> bool:
	var hu := _height_at(heights, u)
	for d in ORTHOGONAL:
		var r := u + d
		var hr := _height_at(heights, r)
		if hr < 0:
			continue
		var ri := r.y * map_size.x + r.x
		# A bank between u and reached ground (the cliff top beyond it, or
		# the ground below it): swap it for a ramp.
		if hr % 2 == 0 and not reserved.has(r) and get_cell_item(Vector3i(r.x, hr / 2, r.y)) == Tile.BANK:
			var beyond := r + d
			var hb := _height_at(heights, beyond)
			if hb >= 0 and reached[beyond.y * map_size.x + beyond.x]:
				var dir := Vector2i.ZERO
				if hu == hr and hb == hr + 2:
					dir = d
				elif hu == hr + 2 and hb == hr:
					dir = -d
				if dir != Vector2i.ZERO and _place_ramp(_ramp_pieces(r, dir, heights, reserved), dir, surface):
					return true
			if hu == hr and peel:
				# No ramp fits: take the bank away, so u's ground reaches the
				# cliff (which turns vertical there) and can climb it next time.
				set_cell_item(Vector3i(r.x, hr / 2, r.y), INVALID_CELL_ITEM)
				surface[ri] = _top_surface(r)
				_peeled.append(r)
				return true
		if cut and hr % 2 == 0 and get_cell_item(Vector3i(r.x, hr / 2, r.y)) == Tile.BANK \
				and _ramp_through_slope(u, d, reached, surface, heights, reserved):
			return true
		if reached[ri] and hu != hr and absi(hu - hr) <= 2:
			var low := u if hu < hr else r
			var dir := d if hu < hr else -d
			if _place_ramp(_ramp_pieces(low, dir, heights, reserved), dir, surface):
				return true
		elif cut and reached[ri] and absi(hu - hr) > 2:
			var low := u if hu < hr else r
			var dir := d if hu < hr else -d
			if _cut_ramps(low, dir, heights, reserved, surface):
				return true
		elif not reached[ri] and hr == hu and surface[ri].is_empty() and not reserved.has(r):
			# r is blocked (by a tree or rock, or cut into a wedge); clear it if
			# reachable ground at our level lies beyond.
			var prop_at := Vector3i(r.x, (hr + 1) / 2, r.y)
			var wedge_at := Vector3i(r.x, (hr - 1) / 2, r.y)
			var wedged := hr > 0 and _is_wedge(get_cell_item(wedge_at))
			if get_cell_item(prop_at) not in CLEARABLE and not wedged:
				continue
			for d2 in ORTHOGONAL:
				var b := r + d2
				if _height_at(heights, b) == hu and reached[b.y * map_size.x + b.x] and not surface[b.y * map_size.x + b.x].is_empty():
					# Only if it then really links u through r to b.
					var prop := get_cell_item(prop_at)
					var prop_basis := get_cell_item_orientation(prop_at)
					if wedged:
						_unshape(r, heights)
					else:
						set_cell_item(prop_at, INVALID_CELL_ITEM)
					surface[ri] = _top_surface(r)
					if _links(surface, u, d) and _links(surface, r, d2):
						return true
					if not wedged:
						set_cell_item(prop_at, prop, prop_basis)
						surface[ri] = _top_surface(r)
	return false


## Joins u to the ground at the other end of a slope (a staircase of
## banks) starting beside it toward d, by laying a ramp down the slope at
## half a block per cell: through the banks, then on over the ground at the
## slope's foot. One end must be reachable.
func _ramp_through_slope(u: Vector2i, d: Vector2i, reached: PackedByteArray, surface: Array,
		heights: PackedInt32Array, reserved: Dictionary) -> bool:
	var hu := _height_at(heights, u)
	var r := u + d
	var hr := _height_at(heights, r)
	# Walk the staircase to its far end, up or down.
	var step := -2 if hu == hr + 2 else (2 if hu <= hr else 0)
	if step == 0:
		return false
	var banks: Array[Vector2i] = []
	var c := r
	while _height_at(heights, c) >= 0 and _has_bank(c, _height_at(heights, c)) and not reserved.has(c):
		if not banks.is_empty() and _height_at(heights, c) != _height_at(heights, banks[-1]) + step:
			break
		banks.append(c)
		c += d
	if banks.is_empty():
		return false
	var k := banks.size()
	# The ramp runs from the top, down the slope and out over the foot.
	var top: Vector2i = u if step < 0 else c
	var down: Vector2i = d if step < 0 else -d
	var h_top := _height_at(heights, top)
	if step > 0 and h_top != _height_at(heights, banks[-1]) + 2:
		return false
	# Down to the ground past the banks (the slope may end in a step).
	var floor_h := _height_at(heights, top + down * (k + 1))
	if floor_h < 0 or floor_h > h_top - 2 * k:
		return false
	var steps := h_top - floor_h
	var run: Array[Vector2i] = []
	for j in range(1, steps + 1):
		run.append(top + down * j)
	var landing: Vector2i = top + down * (steps + 1)
	for j in range(k, steps):
		var f: Vector2i = run[j]
		if _height_at(heights, f) != floor_h or not _ramp_room(f, floor_h / 2, floor_h, reserved):
			return false
	# Clear of other ways up (no ramps side by side).
	for f: Vector2i in run:
		if _ramp_near(f) or _ramp_beside(f, down):
			return false
	if _height_at(heights, landing) != floor_h or surface[landing.y * map_size.x + landing.x].is_empty():
		return false
	if not reached[top.y * map_size.x + top.x] and not reached[landing.y * map_size.x + landing.x]:
		return false
	for j in steps:
		var f: Vector2i = run[j]
		var s := h_top - (j + 1)
		for layer in range(0, TOP_LAYER + 1):
			set_cell_item(Vector3i(f.x, layer, f.y), INVALID_CELL_ITEM)
		_stack_column(f, s)
		heights[f.y * map_size.x + f.x] = s
		set_slope(f, s / 2, Tile.HALF_HILL_RAMP if s % 2 == 0 else Tile.UPPER_HALF_HILL_RAMP, -down)
	for j in range(-1, steps + 2):
		for side in [Vector2i(down.y, down.x), Vector2i(-down.y, -down.x), Vector2i.ZERO]:
			var n: Vector2i = top + down * j + side
			if _height_at(heights, n) < 0:
				continue
			if side != Vector2i.ZERO:
				_unshape(n, heights)
			surface[n.y * map_size.x + n.x] = _top_surface(n)
	return true


## Climbs a wall of stacked cliffs from low toward dir by cutting a
## corridor into the plateau: ramps climbing half a block per cell, each
## cut cell half a block lower than the next, so the way up runs back into
## the cliff like a path cut into its side.
func _cut_ramps(low: Vector2i, dir: Vector2i, heights: PackedInt32Array, reserved: Dictionary,
		surface: Array) -> bool:
	var h := _height_at(heights, low)
	var top := _height_at(heights, low + dir)
	var steps := top - h
	if h < 0 or h % 2 == 1 or steps % 2 == 1 or steps < 4 or _height_at(heights, low - dir) != h:
		return false
	if not _ramp_room(low, h / 2, h, reserved) or get_cell_item(Vector3i(low.x, h / 2, low.y)) != INVALID_CELL_ITEM:
		return false
	# The corridor and its landing must be plain plateau, clear of other
	# ways up (no corridors side by side or crossing).
	for i in range(1, steps + 1):
		var c := low + dir * i
		if reserved.has(c) or _height_at(heights, c) != top \
				or get_cell_item(Vector3i(c.x, top / 2 - 1, c.y)) not in [Tile.FULL, Tile.ROCK]:
			return false
	for i in range(0, steps + 1):
		if _ramp_near(low + dir * i) or (i > 0 and not _walled(low + dir * i, dir, top, heights)):
			return false
	for i in range(1, steps):
		var c := low + dir * i
		for layer in range(0, TOP_LAYER + 1):
			set_cell_item(Vector3i(c.x, layer, c.y), INVALID_CELL_ITEM)
		_stack_column(c, h + i)
		heights[c.y * map_size.x + c.x] = h + i
	for i in range(0, steps):
		var c := low + dir * i
		var step := h + i
		set_slope(c, step / 2, Tile.HALF_HILL_RAMP if step % 2 == 0 else Tile.UPPER_HALF_HILL_RAMP, dir)
	for i in range(-1, steps + 1):
		for side in [Vector2i(dir.y, dir.x), Vector2i(-dir.y, -dir.x), Vector2i.ZERO]:
			var n: Vector2i = low + dir * i + side
			if _height_at(heights, n) < 0:
				continue
			if side != Vector2i.ZERO:
				_unshape(n, heights)
			surface[n.y * map_size.x + n.x] = _top_surface(n)
	return true


## Whether a ramp is in the column at cell or beside it, so a corridor
## there would run alongside or across another way up.
func _ramp_near(cell: Vector2i) -> bool:
	for d in ORTHOGONAL + [Vector2i.ZERO]:
		var n: Vector2i = cell + d
		for layer in range(0, TOP_LAYER + 1):
			var item := get_cell_item(Vector3i(n.x, layer, n.y))
			if item in HILL_RAMPS:
				return true
	return false


## Whether another ramp runs within RAMP_GAP cells to either side of
## cell (across dir, the way it climbs), so ramps don't line up side by
## side like a comb.
func _ramp_beside(cell: Vector2i, dir: Vector2i) -> bool:
	var side := Vector2i(dir.y, dir.x)
	for k in range(-RAMP_GAP, RAMP_GAP + 1):
		if k != 0 and _ramp_near_cell(cell + side * k):
			return true
	return false


## Whether a corridor cell has plateau _corridor_walls cells deep on both
## sides, so cutting it doesn't leave a thin wall standing.
func _walled(cell: Vector2i, dir: Vector2i, top: int, heights: PackedInt32Array) -> bool:
	var side := Vector2i(dir.y, dir.x)
	for k in range(1, _corridor_walls + 1):
		if _height_at(heights, cell + side * k) < top or _height_at(heights, cell - side * k) < top:
			return false
	return true


## Knocks down one-cell fins (ground standing above the ground on two
## opposite sides, left between cuts and levelled pockets) and fills in
## one-cell slots, to the level on either side. Returns how many cells
## changed. Ramps, banks and reserved cells stay.
func _smooth_fins(heights: PackedInt32Array, reserved: Dictionary) -> int:
	var changed := 0
	for z in range(1, map_size.y - 1):
		for x in range(1, map_size.x - 1):
			var c := Vector2i(x, z)
			var h := _height_at(heights, c)
			if h < 0 or reserved.has(c) or _ramp_near(c) or _has_bank(c, h):
				continue
			for d: Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
				var a := _height_at(heights, c + d)
				if a < 0 or a == h or absi(a - h) > 2 or _height_at(heights, c - d) != a \
						or _ramp_near_cell(c + d) or _ramp_near_cell(c - d):
					continue
				for layer in range(0, TOP_LAYER + 1):
					set_cell_item(Vector3i(c.x, layer, c.y), INVALID_CELL_ITEM)
				_stack_column(c, a)
				heights[c.y * map_size.x + c.x] = a
				for n in ORTHOGONAL + DIAGONAL + [Vector2i.ZERO]:
					if _height_at(heights, c + n) >= 0:
						_unshape(c + n, heights)
				changed += 1
				break
	return changed


func _ramp_near_cell(cell: Vector2i) -> bool:
	for layer in range(0, TOP_LAYER + 1):
		if get_cell_item(Vector3i(cell.x, layer, cell.y)) in HILL_RAMPS:
			return true
	return false


func _has_bank(cell: Vector2i, h: int) -> bool:
	return h >= 0 and get_cell_item(Vector3i(cell.x, h / 2, cell.y)) == Tile.BANK


## Joins u's pocket to reachable ground a cliff above or below it where
## there's no room for a ramp at the cliff's foot, by carving the ramp back
## into the higher ground (see _carve_ramps).
func _carve_join(u: Vector2i, reached: PackedByteArray, surface: Array, heights: PackedInt32Array,
		reserved: Dictionary) -> bool:
	var hu := _height_at(heights, u)
	for d in ORTHOGONAL:
		var r := u + d
		var hr := _height_at(heights, r)
		if hr < 0 or not reached[r.y * map_size.x + r.x] or hr == hu:
			continue
		var low := u if hu < hr else r
		var dir := d if hu < hr else -d
		if _carve_ramps(low, dir, heights, reserved, surface):
			return true
	return false


## Cuts a ramp into the higher ground beyond a cliff from low toward dir,
## starting right at the cliff instead of out in front of it: the cells
## behind the cliff's edge are lowered into a run of half-block ramps up to
## the plateau, for cliffs with no level ground at their foot to start from.
func _carve_ramps(low: Vector2i, dir: Vector2i, heights: PackedInt32Array, reserved: Dictionary,
		surface: Array) -> bool:
	var h := _height_at(heights, low)
	var top := _height_at(heights, low + dir)
	var steps := top - h
	if h < 0 or steps < 1 or steps > 6:
		return false
	# Plain plateau to cut into, and somewhere to step off at the top.
	for i in range(1, steps + 2):
		var c := low + dir * i
		if reserved.has(c) or _height_at(heights, c) != top \
				or get_cell_item(Vector3i(c.x, (top - 1) / 2, c.y)) not in [Tile.FULL, Tile.ROCK, Tile.HALF]:
			return false
	var landing := low + dir * (steps + 1)
	if surface[landing.y * map_size.x + landing.x].is_empty():
		return false
	for i in range(1, steps + 1):
		if _ramp_near(low + dir * i) or not _walled(low + dir * i, dir, top, heights):
			return false
	for i in range(1, steps + 1):
		var c := low + dir * i
		var step := h + i - 1
		for layer in range(0, TOP_LAYER + 1):
			set_cell_item(Vector3i(c.x, layer, c.y), INVALID_CELL_ITEM)
		_stack_column(c, step)
		heights[c.y * map_size.x + c.x] = step
		set_slope(c, step / 2, Tile.HALF_HILL_RAMP if step % 2 == 0 else Tile.UPPER_HALF_HILL_RAMP, dir)
	for i in range(0, steps + 2):
		for side in [Vector2i(dir.y, dir.x), Vector2i(-dir.y, -dir.x), Vector2i.ZERO]:
			var n: Vector2i = low + dir * i + side
			if _height_at(heights, n) < 0:
				continue
			if side != Vector2i.ZERO:
				_unshape(n, heights)
			surface[n.y * map_size.x + n.x] = _top_surface(n)
	return true


## Lays out a field of farmland just south of the spawn plaza, with the
## shipping bin and seed shop on the plaza's east side.
func _place_farm(reserved: Dictionary, approaches: Array[Vector2i]) -> void:
	var field := Rect2i(spawn_cell + Vector2i(-3, 3), Vector2i(7, 5))
	for x in range(field.position.x, field.end.x):
		for z in range(field.position.y, field.end.y):
			set_ground(Vector2i(x, z), Tile.FARMLAND)
	# Keep a margin round the field, and the rows south of it clear too: the
	# camera looks north, so anything tall there would hide the crops.
	var margin := field.grow(1).grow_side(SIDE_BOTTOM, 3)
	for x in range(margin.position.x, margin.end.x):
		for z in range(margin.position.y, margin.end.y):
			reserved[Vector2i(x, z)] = true
	set_slope(spawn_cell + Vector2i(2, -1), 0, Tile.SHIPPING_BIN, Vector2i.LEFT)
	set_slope(spawn_cell + Vector2i(2, 1), 0, Tile.SHOP_STALL, Vector2i.LEFT)
	approaches.append(Vector2i(spawn_cell.x, field.position.y - 1))


## Puts the inn north of the spawn plaza, with a house and the blacksmith
## to either side, all facing south toward the plaza (and the camera).
func _place_town(reserved: Dictionary, approaches: Array[Vector2i]) -> void:
	for plan in [[Buildings.inn(), Vector2i(-3, -10)], [Buildings.house(), Vector2i(-8, -6)],
			[Buildings.blacksmith(), Vector2i(4, -6)]]:
		place_building(plan[0], spawn_cell + plan[1], reserved, approaches)


## Blocks a building's footprint, tags its door, adds its mesh, and keeps
## the ground around it clear, with four rows in front: the camera looks
## north, so anything tall there would hide the building and its door.
func place_building(plan: Dictionary, origin: Vector2i, reserved: Dictionary,
		approaches: Array[Vector2i]) -> void:
	var rect := Rect2i(origin, plan.size)
	var door: Vector2i = origin + Vector2i(plan.door, plan.size.y - 1)
	for x in range(rect.position.x, rect.end.x):
		for z in range(rect.position.y, rect.end.y):
			set_cell_item(Vector3i(x, 0, z), Tile.BUILDING_DOOR if Vector2i(x, z) == door else Tile.BUILDING)
	var mesh := MeshInstance3D.new()
	mesh.name = plan.name
	mesh.mesh = _build_mesh(plan.faces, {}, block_material())
	mesh.position = Vector3(origin.x, 0, origin.y)
	_building_meshes.add_child(mesh)
	buildings.append({ name = plan.name, rect = rect, door = door })
	var keep_clear := rect.grow(1).grow_side(SIDE_BOTTOM, 4)
	for x in range(keep_clear.position.x, keep_clear.end.x):
		for z in range(keep_clear.position.y, keep_clear.end.y):
			reserved[Vector2i(x, z)] = true
	approaches.append(door + Vector2i.DOWN)


func building_at(cell: Vector2i) -> Dictionary:
	for b in buildings:
		if b.rect.has_point(cell):
			return b
	return {}


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


## Scatters flowers, then wears dirt paths from spawn to each building,
## the farm and the enclosures within reach of the settlement.
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
			if came_from.has(c + d) or Vector2(c + d).distance_to(Vector2(spawn_cell)) > SETTLEMENT_RADIUS + 4.0:
				continue
			if find_move(c, GROUND_LAYER, d) == GROUND_LAYER:
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


## Empty grass at ground level, inside the map.
func _is_open_ground(cell: Vector2i) -> bool:
	if cell.x < 1 or cell.y < 1 or cell.x >= map_size.x - 1 or cell.y >= map_size.y - 1:
		return false
	var ground := ground_tile(cell)
	if ground != Tile.GROUND and ground != Tile.FLOWERS:
		return false
	for layer in range(0, TOP_LAYER + 1):
		if get_cell_item(Vector3i(cell.x, layer, cell.y)) != INVALID_CELL_ITEM:
			return false
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
			if reserved.has(Vector2i(x, z)) or not _is_open_ground(Vector2i(x, z)):
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
			or _is_tall_grass(item):
		return {}
	var top := _span(item, layer).y
	for above in range(layer + 1, TOP_LAYER + 1):
		var other := get_cell_item(Vector3i(cell.x, above, cell.y))
		if other == INVALID_CELL_ITEM or _is_thin(other) or _is_tall_grass(other):
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
## Whether a bank's slope is down at the floor (height h) at its corner
## toward `corner` (no ground a block above touches that corner, as
## TerrainMesh draws it), so a diagonal step can pass that corner, e.g.
## along a diagonal ledge at a slope's foot.
func _bank_foot_corner(cell: Vector2i, corner: Vector2i, h: float) -> bool:
	var hc := _height_at(height_map, cell)
	if hc < 0 or hc % 2 == 1 or get_cell_item(Vector3i(cell.x, hc / 2, cell.y)) != Tile.BANK \
			or not is_equal_approx(hc / 2.0, h):
		return false
	for o: Vector2i in [Vector2i(corner.x, 0), Vector2i(0, corner.y), corner]:
		var n := cell + o
		if _height_at(height_map, n) != hc + 2:
			continue
		# (A diagonal cut's open corner doesn't count.)
		var layer := (hc + 1) / 2
		if _is_wedge(get_cell_item(Vector3i(n.x, layer, n.y))) and corner - o == -_corner_dir(n, layer):
			continue
		return false
	return true


func _corner_passable(cell: Vector2i, corner: Vector2i, h: float) -> bool:
	if _corner_blocked(cell, corner, h):
		return false
	for s in _surfaces(cell):
		var ch := _corner_height(s, corner, false)
		if is_equal_approx(ch, h):
			return true
	if _bank_foot_corner(cell, corner, h):
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
		# Walking past its open corner, on the floor it stands on (its own
		# solid bottom half, for an upper-half wedge).
		if corner != -solid:
			continue
		if item == Tile.UPPER_HALF_WEDGE:
			if is_equal_approx(span.x + 0.5, h):
				return true
			continue
		var below := get_cell_item(Vector3i(cell.x, layer - 1, cell.y))
		if is_equal_approx(span.x, h) and below != INVALID_CELL_ITEM and not _is_wedge(below) \
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
	return tile in [Tile.WEDGE, Tile.HALF_WEDGE, Tile.WEDGE_DIRT, Tile.UPPER_HALF_WEDGE]


static func _is_tall_grass(tile: int) -> bool:
	return tile == Tile.TALL_GRASS or tile == Tile.TALL_GRASS_LOW


static func _is_corner_slope(tile: int) -> bool:
	return tile in [Tile.CORNER_OUTER, Tile.CORNER_INNER, Tile.HALF_CORNER_OUTER, Tile.HALF_CORNER_INNER]


static func _is_diag_ramp(tile: int) -> bool:
	return tile == Tile.DIAG_RAMP or tile == Tile.HALF_DIAG_RAMP


static func _is_solid_scenery(tile: int) -> bool:
	return tile in CLEARABLE or tile in [Tile.WATER, Tile.WATERFALL, Tile.BUILDING, Tile.BUILDING_DOOR, Tile.BANK]


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
				Tile.UPPER_HALF_RAMP, Tile.UPPER_HALF_STAIRS, Tile.UPPER_HALF_HILL_RAMP:
			return 0.5
	return 0.0


## Height a slope starts at within its cell.
static func _base(tile: int) -> float:
	return 0.5 if tile in [Tile.UPPER_HALF_RAMP, Tile.UPPER_HALF_STAIRS, Tile.UPPER_HALF_HILL_RAMP] else 0.0


# --- Meshes -----------------------------------------------------------------
# All meshes have their origin at the bottom center of the cell. Sloped tiles
# are modeled rising toward -Z; GridMap orientation rotates them.

## The unlit, face-shaded tileset material shared by blocks and buildings.
func block_material() -> ShaderMaterial:
	if _block_material == null:
		_block_material = ShaderMaterial.new()
		_block_material.shader = BLOCK_SHADER
		_block_material.set_shader_parameter("tileset", TILESET)
		_block_material.set_shader_parameter("tiles", Vector2(TEX_COLS, TEX_ROWS))
	return _block_material


func _build_mesh_library() -> MeshLibrary:
	var mat := block_material()

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
		[Tile.ROCK, "Rock", full_box, { top = Tex.ROCK_TOP, side = Tex.DIRT, slope = Tex.DIRT }],
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
		[Tile.UPPER_HALF_WEDGE, "UpperHalfWedge",
			_box_faces(Vector3(-0.5, 0, -0.5), Vector3(0.5, 0.5, 0.5)) + _wedge_faces(0.5, 0.5), grass_block],
		[Tile.UPPER_HALF_HILL_RAMP, "UpperHalfHillRamp", _ramp_faces(0.5, 0.5), hill],
	]
	for item in items:
		lib.create_item(item[0])
		lib.set_item_name(item[0], item[1])
		lib.set_item_mesh(item[0], _build_mesh(item[2], item[3], mat))
	if hide_terrain_blocks:
		for tile in TerrainMesh.HIDDEN:
			lib.set_item_mesh(tile, null)

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

	for tile in [Tile.BUILDING, Tile.BUILDING_DOOR, Tile.BANK]:
		lib.create_item(tile)
		lib.set_item_name(tile, Tile.keys()[tile].capitalize())

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
		var low: int = PROP_LOW[tile]
		lib.create_item(low)
		lib.set_item_name(low, Tile.keys()[low].capitalize())
		lib.set_item_mesh(low, _prop_mesh(i, props_mat, 0.5))
	return lib


## Builds a mesh from faces, or adds them as another surface of into.
## A face is [points, outward normal], optionally followed by a tile (else
## the skin picks one by the face's direction) and per-point tile-space UVs
## (else they're projected; see _face_uv).
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
		var tex: int
		if face.size() > 2:
			tex = face[2]
		else:
			tex = skin.top if n.y > 0.99 else (skin.slope if n.y > 0.1 else (Tex.DIRT if n.y < -0.5 else skin.side))
		var uvs: Array = face[3] if face.size() > 3 else []
		for i in range(1, pts.size() - 1):
			var corners := [0, i, i + 1]
			# Godot treats clockwise as front-facing.
			if (pts[i] - pts[0]).cross(pts[i + 1] - pts[0]).dot(n) > 0.0:
				corners = [0, i + 1, i]
			for k in corners:
				var v: Vector3 = pts[k]
				st.set_normal(n)
				st.set_uv(Vector2(tex % TEX_COLS, tex / TEX_COLS))
				st.set_uv2(uvs[k] if not uvs.is_empty() else _face_uv(v, n, top_y))
				st.add_vertex(v)
	st.set_material(mat)
	return st.commit(into)


## A prop sprite as an upright quad standing on the cell's centre, sized so
## one texel matches the tileset's and stretched to face the camera. sink
## lowers it (in blocks) to stand on a half block below its cell.
static func _prop_mesh(index: int, mat: Material, sink := 0.0) -> ArrayMesh:
	var size := Vector2(PROP_SPRITE_SIZE) / 16.0
	var up := Vector3(0, size.y * SPRITE_STRETCH, 0)
	var u0 := float(index) / PROP_SPRITES.size()
	var u1 := float(index + 1) / PROP_SPRITES.size()
	var bl := Vector3(-size.x / 2, -sink, 0)
	var br := Vector3(size.x / 2, -sink, 0)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for v in [[bl, Vector2(u0, 1)], [bl + up, Vector2(u0, 0)], [br + up, Vector2(u1, 0)],
			[bl, Vector2(u0, 1)], [br + up, Vector2(u1, 0)], [br, Vector2(u1, 1)]]:
		st.set_normal(Vector3.BACK)
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


## Full cell cut corner to corner, keeping the (-x, -z) half, from base up
## to base + h.
static func _wedge_faces(h: float, base := 0.0) -> Array:
	var b := base
	var t := base + h
	return [
		[[Vector3(-0.5, b, -0.5), Vector3(0.5, b, -0.5), Vector3(-0.5, b, 0.5)], Vector3.DOWN],
		[[Vector3(-0.5, t, -0.5), Vector3(0.5, t, -0.5), Vector3(-0.5, t, 0.5)], Vector3.UP],
		[[Vector3(-0.5, b, -0.5), Vector3(-0.5, b, 0.5), Vector3(-0.5, t, 0.5), Vector3(-0.5, t, -0.5)], Vector3.LEFT],
		[[Vector3(-0.5, b, -0.5), Vector3(0.5, b, -0.5), Vector3(0.5, t, -0.5), Vector3(-0.5, t, -0.5)], Vector3.FORWARD],
		[[Vector3(0.5, b, -0.5), Vector3(-0.5, b, 0.5), Vector3(-0.5, t, 0.5), Vector3(0.5, t, -0.5)], Vector3(1, 0, 1).normalized()],
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
