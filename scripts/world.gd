class_name GridWorld
extends GridMap

## Builds its own MeshLibrary and generates a simple random tile map.
## Layer y = -1 is ground, layer y = 0 holds walls. Grid coords are (x, z).

enum Tile { GROUND, WALL }

@export var map_size := Vector2i(24, 24)
@export_range(0.0, 0.5) var wall_density := 0.15
@export var map_seed := 1

var spawn_cell := Vector2i.ZERO


func _ready() -> void:
	cell_size = Vector3.ONE
	mesh_library = _build_mesh_library()
	generate(map_seed)


func generate(new_seed: int) -> void:
	clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = new_seed
	spawn_cell = map_size / 2
	for x in map_size.x:
		for z in map_size.y:
			set_cell_item(Vector3i(x, -1, z), Tile.GROUND)
			var border := x == 0 or z == 0 or x == map_size.x - 1 or z == map_size.y - 1
			var near_spawn := absi(x - spawn_cell.x) <= 1 and absi(z - spawn_cell.y) <= 1
			if border or (not near_spawn and rng.randf() < wall_density):
				set_cell_item(Vector3i(x, 0, z), Tile.WALL)


func is_walkable(cell: Vector2i) -> bool:
	return get_cell_item(Vector3i(cell.x, -1, cell.y)) == Tile.GROUND \
		and get_cell_item(Vector3i(cell.x, 0, cell.y)) == INVALID_CELL_ITEM


## World-space position of a cell's center, at ground level.
func cell_to_world(cell: Vector2i) -> Vector3:
	return Vector3((cell.x + 0.5) * cell_size.x, 0.0, (cell.y + 0.5) * cell_size.z)


func _build_mesh_library() -> MeshLibrary:
	var lib := MeshLibrary.new()
	_add_box(lib, Tile.GROUND, Color(0.42, 0.68, 0.36))
	_add_box(lib, Tile.WALL, Color(0.45, 0.43, 0.48))
	return lib


func _add_box(lib: MeshLibrary, id: int, color: Color) -> void:
	var mesh := BoxMesh.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mesh.material = mat
	lib.create_item(id)
	lib.set_item_mesh(id, mesh)
