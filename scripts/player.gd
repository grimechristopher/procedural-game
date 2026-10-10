class_name Player
extends Node3D

## HGSS-style grid movement, extended to 8 directions.
## - Tap a new direction to turn in place; hold it to start walking.
## - Holding a direction chains steps tile to tile without stopping.
## - Hold run to move at double speed.
## - Height changes only via ramps/stairs; see GridWorld.find_move.

@export var world: GridWorld
@export var walk_step_time := 0.25
@export var run_step_time := 0.125
## Hold longer than this after turning to start walking.
@export var turn_hold_time := 0.1
## Short delay before stepping when already facing the pressed direction,
## so a slightly staggered two-key press still registers as a diagonal.
@export var diagonal_grace_time := 0.05
## Diagonal steps take this much longer, so on-screen speed stays constant.
@export var diagonal_time_scale := 1.41421

@onready var body: Node3D = $Body

var cell := Vector2i.ZERO
## Layer of the tile we're standing on.
var layer := GridWorld.GROUND_LAYER
var facing := Vector2i(0, 1)
## Off while a menu is open: finishes the current step, takes no new input.
var input_enabled := true

var _moving := false
var _from := Vector3.ZERO
var _to := Vector3.ZERO
var _mid_y := 0.0
var _t := 0.0
var _step_time := 0.0
var _hold := 0.0
var _hold_needed := 0.0


func _ready() -> void:
	teleport(world.spawn_cell)


func teleport(target: Vector2i, target_layer := GridWorld.GROUND_LAYER) -> void:
	cell = target
	layer = target_layer
	_moving = false
	_hold = 0.0
	position = world.cell_to_world(cell, layer)


func _process(delta: float) -> void:
	if _moving:
		_t += delta / _step_time
		if _t < 1.0:
			_update_position()
			return
		# Arrived. Chain straight into the next step if input is still held,
		# carrying over leftover time so continuous walking stays smooth.
		var leftover := (_t - 1.0) * _step_time
		position = _to
		_moving = false
		var dir := _read_input() if input_enabled else Vector2i.ZERO
		if dir != Vector2i.ZERO and _try_step(dir):
			_t = leftover / _step_time
			_update_position()
		return

	var dir := _read_input() if input_enabled else Vector2i.ZERO
	if dir == Vector2i.ZERO:
		_hold = 0.0
		return
	if _hold == 0.0:
		_hold_needed = diagonal_grace_time if dir == facing else turn_hold_time
	_face(dir)
	_hold += delta
	if _hold >= _hold_needed:
		_try_step(dir)


func is_moving() -> bool:
	return _moving


## The cell in front of us, which tools and interactions act on.
func target_cell() -> Vector2i:
	return cell + facing


func _try_step(dir: Vector2i) -> bool:
	_face(dir)
	var next_layer := world.find_move(cell, layer, dir)
	if next_layer == GridWorld.NO_MOVE:
		return false
	_hold = 0.0
	_from = world.cell_to_world(cell, layer)
	_mid_y = world.crossing_height(cell, layer, dir)
	cell += dir
	layer = next_layer
	_to = world.cell_to_world(cell, layer)
	_t = 0.0
	_step_time = run_step_time if Input.is_action_pressed("run") else walk_step_time
	if dir.x != 0 and dir.y != 0:
		_step_time *= diagonal_time_scale
	_moving = true
	return true


## Moves in a straight line over the ground, but splits the height change
## at the shared edge so walking onto or off a ramp follows its surface.
func _update_position() -> void:
	position = _from.lerp(_to, _t)
	if _t < 0.5:
		position.y = lerpf(_from.y, _mid_y, _t * 2.0)
	else:
		position.y = lerpf(_mid_y, _to.y, _t * 2.0 - 1.0)


func _face(dir: Vector2i) -> void:
	facing = dir
	# Body model faces -Z by default; grid y maps to world z.
	body.rotation.y = atan2(-dir.x, -dir.y)


func _read_input() -> Vector2i:
	return Vector2i(
		signi(roundi(Input.get_axis("move_left", "move_right"))),
		signi(roundi(Input.get_axis("move_up", "move_down")))
	)
