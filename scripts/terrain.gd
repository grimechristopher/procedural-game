class_name Terrain
extends RefCounted

## The shape of the open world: elevation, edge style, forest and tall-grass
## density for any world cell, from the seed alone. Nothing here depends on
## a map's size or on neighbouring results, so the same terrain can be
## generated a piece at a time (chunks) later on.
##
## Elevation is in blocks: below 0 is water. Gentle simplex noise makes
## rolling hills; where a low-frequency mask allows, ridged noise raises
## mountain ranges.

## Elevation of the tallest peaks, in blocks.
const MOUNTAIN_HEIGHT := 9.0

var _hills := FastNoiseLite.new()
var _ridges := FastNoiseLite.new()
var _mountain_mask := FastNoiseLite.new()
var _style := FastNoiseLite.new()
var _forest := FastNoiseLite.new()
var _tall_grass := FastNoiseLite.new()
var _sheer := FastNoiseLite.new()


func _init(seed_value: int) -> void:
	_setup(_hills, seed_value, 0.028, 4)
	_setup(_ridges, seed_value + 1, 0.016, 3)
	_ridges.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_setup(_mountain_mask, seed_value + 2, 0.011, 2)
	_setup(_style, seed_value + 3, 0.035, 2)
	_setup(_forest, seed_value + 4, 0.06, 3)
	_setup(_tall_grass, seed_value + 5, 0.1, 2)
	_setup(_sheer, seed_value + 6, 0.03, 2)


## Continuous elevation in blocks; below 0 is water.
func elevation(x: float, z: float) -> float:
	var hills := _hills.get_noise_2d(x, z) * 3.6 + 1.8
	return hills + mountains(x, z)


## How much of a cell's elevation is mountain, in blocks.
func mountains(x: float, z: float) -> float:
	var mask := clampf(_mountain_mask.get_noise_2d(x, z) * 2.2 - 0.25, 0.0, 1.0)
	var ridge := _ridges.get_noise_2d(x, z) * 0.5 + 0.5
	return mask * ridge * MOUNTAIN_HEIGHT


## Whether one-block steps here are cliffs (with stairs) rather than grassy
## slopes. Mountains are always cliffy.
func is_cliffy(x: float, z: float) -> bool:
	return _style.get_noise_2d(x, z) > 0.12 or mountains(x, z) > 1.5


## How many one-block cliffs may stack straight up here (1 to 3) before
## the ground has to step back. Sheerer in the mountains.
func cliff_tiers(x: float, z: float) -> int:
	var sheer := _sheer.get_noise_2d(x, z) + (0.25 if mountains(x, z) > 1.5 else 0.0)
	return 3 if sheer > 0.25 else (2 if sheer > -0.1 else 1)


## Whether one-block cliffs here are HGSS-style banks, sloping across the
## cell at their foot, rather than vertical: where cliffs step back one at
## a time (terraces). Stacked walls stay vertical.
func has_banks(x: float, z: float) -> bool:
	return is_cliffy(x, z) and cliff_tiers(x, z) == 1


## 0..1 chance of a tree.
func forest(x: float, z: float) -> float:
	return clampf(_forest.get_noise_2d(x, z) * 2.4 - 0.15, 0.0, 0.8)


func is_tall_grass(x: float, z: float) -> bool:
	return _tall_grass.get_noise_2d(x, z) > 0.42


## A stable 0..1 value per cell, for sprinkling things deterministically.
static func cell_hash(x: int, z: int, salt: int) -> float:
	var h := hash(Vector3i(x, z, salt))
	return float(h & 0xffff) / 65535.0


static func _setup(noise: FastNoiseLite, seed_value: int, frequency: float, octaves: int) -> void:
	noise.seed = seed_value
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = frequency
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = octaves
