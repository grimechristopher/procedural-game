class_name Farm
extends Node3D

## Stardew Valley-style farming on the GridWorld.
##
## Soil state lives in the GridMap as tagged ground tiles: tillable FARMLAND
## becomes TILLED with the hoe and TILLED_WET with the watering can. Crops
## live here, keyed by cell, and are drawn as billboard sprites.
##
## Each night (sleep):
## - crops on watered soil grow a day; crops on dry soil don't;
## - soil dries out, then rain (some mornings) waters everything again;
## - empty, dry tilled soil sometimes reverts to plain farmland;
## - shipped items are paid for, and energy refills;
## - on a new season, crops that aren't in season die.

signal changed
signal message(text: String)

const MAX_ENERGY := 270
const TOOL_ENERGY := 2
const DAYS_PER_SEASON := 28
const START_GOLD := 500
const REVERT_CHANCE := 0.1
const RAIN_CHANCE := 0.2

@export var world: GridWorld

var inventory := Inventory.new()
var gold := START_GOLD
var energy := MAX_ENERGY
var day := 1
var season: int = Crops.Season.SPRING
var year := 1
var raining := false
## Items in the shipping bin, paid for overnight.
var shipped: Array[String] = []
## Cell -> { crop, days, ready, regrowing, regrow_left, dead }
var plots := {}
var rng := RandomNumberGenerator.new()

var _sprites := {}


func _ready() -> void:
	inventory.changed.connect(func(): changed.emit())
	reset()


## Fresh save: starting tools, seeds and gold, nothing planted.
func reset() -> void:
	for sprite in _sprites.values():
		sprite.queue_free()
	_sprites.clear()
	plots.clear()
	shipped.clear()
	inventory = Inventory.new()
	inventory.changed.connect(func(): changed.emit())
	inventory.add("hoe")
	inventory.add("can")
	inventory.add("seed:parsnip", 15)
	gold = START_GOLD
	energy = MAX_ENERGY
	day = 1
	season = Crops.Season.SPRING
	year = 1
	raining = false
	changed.emit()


# --- Actions ------------------------------------------------------------------

## Uses the selected hotbar item on a cell.
func use_selected(cell: Vector2i) -> void:
	var id := inventory.selected_id()
	if id == "hoe":
		till(cell)
	elif id == "can":
		water(cell)
	elif id.begins_with("seed:"):
		plant(cell, StringName(id.trim_prefix("seed:")))


func till(cell: Vector2i) -> bool:
	if plots.has(cell) and plots[cell].dead:
		# The hoe clears away dead crops.
		_remove_plot(cell)
		return _spend_energy()
	if not world.has_tag(cell, &"tillable"):
		return _fail("Can't till here.")
	if not _spend_energy():
		return false
	world.set_ground(cell, GridWorld.Tile.TILLED)
	changed.emit()
	return true


func water(cell: Vector2i) -> bool:
	if not world.has_tag(cell, &"tilled") or world.has_tag(cell, &"watered"):
		return false
	if not _spend_energy():
		return false
	world.set_ground(cell, GridWorld.Tile.TILLED_WET)
	changed.emit()
	return true


func plant(cell: Vector2i, crop: StringName) -> bool:
	if not world.has_tag(cell, &"tilled") or plots.has(cell):
		return _fail("Plant seeds on empty tilled soil.")
	if not Crops.in_season(crop, season):
		return _fail("%s won't grow in %s." % [Crops.ALL[crop].name, Crops.SEASON_NAMES[season]])
	if not inventory.remove("seed:" + crop):
		return false
	plots[cell] = { crop = crop, days = 0, ready = false, regrowing = false, regrow_left = 0, dead = false }
	_update_sprite(cell)
	changed.emit()
	return true


## Picks a ripe crop into the inventory. Regrowing crops stay planted.
func harvest(cell: Vector2i) -> bool:
	if not plots.has(cell) or not plots[cell].ready:
		return false
	var state: Dictionary = plots[cell]
	if not inventory.add("crop:" + state.crop):
		return _fail("Inventory full.")
	var regrow: int = Crops.ALL[state.crop].regrow
	if regrow > 0:
		state.ready = false
		state.regrowing = true
		state.regrow_left = regrow
		_update_sprite(cell)
	else:
		_remove_plot(cell)
	changed.emit()
	return true


## Puts every harvested crop in the shipping bin; they're paid for overnight.
func ship_all() -> int:
	var count := 0
	for slot in inventory.slots.duplicate():
		if slot != null and slot.id.begins_with("crop:"):
			for i in slot.count:
				shipped.append(slot.id)
			count += slot.count
			inventory.remove(slot.id, slot.count)
	if count > 0:
		message.emit("Shipped %d item%s." % [count, "" if count == 1 else "s"])
	else:
		message.emit("Nothing to ship.")
	changed.emit()
	return count


## Seeds the shop sells this season, cheapest first.
func shop_stock() -> Array[StringName]:
	var stock: Array[StringName] = []
	for id in Crops.ALL:
		if Crops.in_season(id, season):
			stock.append(id)
	stock.sort_custom(func(a, b): return Crops.ALL[a].seed_price < Crops.ALL[b].seed_price)
	return stock


func buy_seeds(crop: StringName, count := 1) -> bool:
	var price: int = Crops.ALL[crop].seed_price * count
	if gold < price:
		return _fail("Not enough gold.")
	if not inventory.add("seed:" + crop, count):
		return _fail("Inventory full.")
	gold -= price
	changed.emit()
	return true


## Ends the day and runs the overnight rules.
func sleep() -> void:
	var earned := 0
	for id in shipped:
		earned += Crops.ALL[StringName(id.trim_prefix("crop:"))].sell_price
	gold += earned
	shipped.clear()

	for cell in plots:
		var state: Dictionary = plots[cell]
		if state.dead or not world.has_tag(cell, &"watered"):
			continue
		if state.regrowing:
			state.regrow_left -= 1
			if state.regrow_left <= 0:
				state.regrowing = false
				state.ready = true
		elif not state.ready:
			state.days += 1
			state.ready = state.days >= Crops.total_days(state.crop)

	for pos in world.get_used_cells_by_item(GridWorld.Tile.TILLED_WET):
		world.set_cell_item(pos, GridWorld.Tile.TILLED)
	for pos in world.get_used_cells_by_item(GridWorld.Tile.TILLED):
		var cell := Vector2i(pos.x, pos.z)
		if not plots.has(cell) and rng.randf() < REVERT_CHANCE:
			world.set_cell_item(pos, GridWorld.Tile.FARMLAND)

	day += 1
	if day > DAYS_PER_SEASON:
		day = 1
		season = (season + 1) % 4
		if season == Crops.Season.SPRING:
			year += 1
		for cell in plots:
			if not Crops.in_season(plots[cell].crop, season):
				plots[cell].dead = true
				plots[cell].ready = false

	raining = season != Crops.Season.WINTER and rng.randf() < RAIN_CHANCE
	if raining:
		for pos in world.get_used_cells_by_item(GridWorld.Tile.TILLED):
			world.set_cell_item(pos, GridWorld.Tile.TILLED_WET)

	energy = MAX_ENERGY
	for cell in plots:
		_update_sprite(cell)
	var news := "Day %d of %s." % [day, Crops.SEASON_NAMES[season]]
	if earned > 0:
		news += " Earned %dg." % earned
	if raining:
		news += " It's raining."
	message.emit(news)
	changed.emit()


# --- Helpers ------------------------------------------------------------------

func _spend_energy() -> bool:
	if energy < TOOL_ENERGY:
		return _fail("Too tired. Sleep to recover.")
	energy -= TOOL_ENERGY
	return true


func _fail(text: String) -> bool:
	message.emit(text)
	return false


func _remove_plot(cell: Vector2i) -> void:
	plots.erase(cell)
	if _sprites.has(cell):
		_sprites[cell].queue_free()
		_sprites.erase(cell)
	changed.emit()


func _update_sprite(cell: Vector2i) -> void:
	var sprite: Sprite3D = _sprites.get(cell)
	if sprite == null:
		sprite = Sprite3D.new()
		sprite.texture = Crops.SHEET
		sprite.region_enabled = true
		sprite.pixel_size = 1.0 / Crops.CELL
		sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
		sprite.shaded = false
		add_child(sprite)
		_sprites[cell] = sprite
	sprite.region_rect = Crops.region(Crops.sprite_cell(plots[cell]))
	sprite.position = world.cell_to_world(cell, GridWorld.GROUND_LAYER) + Vector3(0, 0.5, 0)
