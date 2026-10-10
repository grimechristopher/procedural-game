extends Camera3D

## Fixed-angle follow camera, HGSS / Black & White style: always faces
## north (-Z), pitched down at a set angle, and never rotates. It's a child
## of the player, so it follows them; only the angle and distance live here.

## Degrees below horizontal.
@export var pitch := 40.0
## Distance from the point it looks at, just above the player's feet.
@export var distance := 11.0
@export var look_height := 0.5


func _ready() -> void:
	var angle := deg_to_rad(pitch)
	var target := Vector3(0, look_height, 0)
	transform = Transform3D(Basis(Vector3.RIGHT, -angle),
		target + Vector3(0, sin(angle), cos(angle)) * distance)
