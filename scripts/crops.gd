class_name Crops

## Crop definitions, modeled on Stardew Valley's spring and summer crops.
##
## phases: days spent in each growth phase (all must pass before harvest).
## regrow: days to grow back after a harvest, or 0 if it's harvested once.
## row: row in assets/crops.png (see tools/make_crops.py).

enum Season { SPRING, SUMMER, FALL, WINTER }

const SEASON_NAMES := ["Spring", "Summer", "Fall", "Winter"]

const ALL := {
	&"parsnip": {
		name = "Parsnip", phases = [1, 1, 1, 1], regrow = 0,
		seed_price = 20, sell_price = 35, seasons = [Season.SPRING], row = 0,
	},
	&"potato": {
		name = "Potato", phases = [1, 1, 1, 2, 1], regrow = 0,
		seed_price = 50, sell_price = 80, seasons = [Season.SPRING], row = 1,
	},
	&"cauliflower": {
		name = "Cauliflower", phases = [1, 2, 4, 4, 1], regrow = 0,
		seed_price = 80, sell_price = 175, seasons = [Season.SPRING], row = 2,
	},
	&"green_bean": {
		name = "Green Bean", phases = [1, 1, 1, 3, 4], regrow = 3,
		seed_price = 60, sell_price = 40, seasons = [Season.SPRING], row = 3,
	},
	&"melon": {
		name = "Melon", phases = [1, 2, 3, 3, 3], regrow = 0,
		seed_price = 80, sell_price = 250, seasons = [Season.SUMMER], row = 4,
	},
	&"tomato": {
		name = "Tomato", phases = [2, 2, 2, 2, 3], regrow = 4,
		seed_price = 50, sell_price = 60, seasons = [Season.SUMMER], row = 5,
	},
}

## Sprite sheet layout.
const SHEET := preload("res://assets/crops.png")
const CELL := 16
const COL_SEEDS := 0
const COL_READY := 5
const COL_ITEM := 6
const COL_PACKET := 7
const ICON_ROW := 6
const ICON_HOE := Vector2i(0, ICON_ROW)
const ICON_CAN := Vector2i(1, ICON_ROW)
const ICON_DEAD := Vector2i(2, ICON_ROW)


static func total_days(id: StringName) -> int:
	var days := 0
	for d in ALL[id].phases:
		days += d
	return days


static func in_season(id: StringName, season: int) -> bool:
	return season in ALL[id].seasons


## Sprite sheet cell (column, row) showing a crop's current state.
static func sprite_cell(state: Dictionary) -> Vector2i:
	if state.dead:
		return ICON_DEAD
	var row: int = ALL[state.crop].row
	if state.ready:
		return Vector2i(COL_READY, row)
	if state.regrowing:
		return Vector2i(4, row)
	if state.days == 0:
		return Vector2i(COL_SEEDS, row)
	return Vector2i(1 + mini(3, state.days * 4 / total_days(state.crop)), row)


static func region(sheet_cell: Vector2i) -> Rect2:
	return Rect2(sheet_cell * CELL, Vector2(CELL, CELL))


static func icon(sheet_cell: Vector2i) -> AtlasTexture:
	var tex := AtlasTexture.new()
	tex.atlas = SHEET
	tex.region = region(sheet_cell)
	return tex
