extends Node3D

@onready var world: GridWorld = $World
@onready var player: Player = $Player


func _enter_tree() -> void:
	_setup_input()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("regenerate"):
		world.generate(randi())
		player.teleport(world.spawn_cell, world.spawn_layer)


func _setup_input() -> void:
	var bindings := {
		"move_up": [KEY_W, KEY_UP],
		"move_down": [KEY_S, KEY_DOWN],
		"move_left": [KEY_A, KEY_LEFT],
		"move_right": [KEY_D, KEY_RIGHT],
		"run": [KEY_SHIFT, KEY_X],
		"regenerate": [KEY_R],
	}
	for action in bindings:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for keycode in bindings[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = keycode
			InputMap.action_add_event(action, ev)
