extends Node3D

@onready var world: GridWorld = $World
@onready var player: Player = $Player
@onready var farm: Farm = $Farm
@onready var hud: Hud = $Hud
@onready var wardrobe: Wardrobe = $Wardrobe

## Open the wardrobe at the start so the player can make their character.
@export var open_wardrobe_on_start := true


func _enter_tree() -> void:
	_setup_input()


func _ready() -> void:
	farm.changed.connect(func(): hud.refresh(farm))
	farm.message.connect(hud.toast)
	hud.refresh(farm)
	wardrobe.changed.connect(func():
		player.refresh_appearance()
		wardrobe.set_texture(player.sprite.texture))
	wardrobe.closed.connect(func(): player.input_enabled = true)
	if open_wardrobe_on_start:
		_open_wardrobe()


func _open_wardrobe() -> void:
	wardrobe.open(player.appearance, player.sprite.texture)
	player.input_enabled = false


func _unhandled_input(event: InputEvent) -> void:
	if wardrobe.visible:
		wardrobe.handle(event)
		get_viewport().set_input_as_handled()
		return
	if hud.shop_open:
		_shop_input(event)
		return
	if event.is_action_pressed("wardrobe"):
		_open_wardrobe()
		return
	if event.is_action_pressed("regenerate"):
		world.generate(randi())
		player.teleport(world.spawn_cell)
		farm.reset()
	elif event.is_action_pressed("use_tool"):
		if _can_act():
			farm.use_selected(player.target_cell())
	elif event.is_action_pressed("interact"):
		if _can_act():
			_interact(player.target_cell())
	elif event.is_action_pressed("sleep"):
		farm.sleep()
	elif event.is_action_pressed("hotbar_next"):
		farm.inventory.select(farm.inventory.selected + 1)
	elif event.is_action_pressed("hotbar_prev"):
		farm.inventory.select(farm.inventory.selected - 1)
	else:
		for i in Inventory.SIZE:
			if event.is_action_pressed("hotbar_%d" % i):
				farm.inventory.select(i)


## Farming happens on the ground, standing still.
func _can_act() -> bool:
	return not player.is_moving() and player.layer == GridWorld.GROUND_LAYER


func _interact(cell: Vector2i) -> void:
	if world.has_tag(cell, &"shop"):
		hud.open_shop(farm)
		player.input_enabled = false
	elif world.has_tag(cell, &"shipping_bin"):
		farm.ship_all()
	else:
		farm.harvest(cell)


func _shop_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("interact"):
		hud.close_shop()
		player.input_enabled = true
		return
	var stock := farm.shop_stock()
	for i in stock.size():
		if event.is_action_pressed("hotbar_%d" % i) and farm.buy_seeds(stock[i]):
			hud.toast("Bought %s seeds." % Crops.ALL[stock[i]].name)


func _setup_input() -> void:
	var bindings := {
		"move_up": [KEY_W, KEY_UP],
		"move_down": [KEY_S, KEY_DOWN],
		"move_left": [KEY_A, KEY_LEFT],
		"move_right": [KEY_D, KEY_RIGHT],
		"run": [KEY_SHIFT, KEY_X],
		"regenerate": [KEY_R],
		"use_tool": [KEY_SPACE, KEY_C],
		"interact": [KEY_E],
		"sleep": [KEY_N],
		"wardrobe": [KEY_P],
	}
	for i in Inventory.SIZE:
		bindings["hotbar_%d" % i] = [KEY_1 + i if i < 9 else KEY_0]
	for action in bindings:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for keycode in bindings[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = keycode
			InputMap.action_add_event(action, ev)
	for pair in [["hotbar_next", MOUSE_BUTTON_WHEEL_DOWN], ["hotbar_prev", MOUSE_BUTTON_WHEEL_UP]]:
		if not InputMap.has_action(pair[0]):
			InputMap.add_action(pair[0])
			var ev := InputEventMouseButton.new()
			ev.button_index = pair[1]
			InputMap.action_add_event(pair[0], ev)
