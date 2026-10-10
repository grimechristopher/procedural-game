extends Camera3D

## Fixed-angle follow camera, HGSS style: always faces north (-Z), pitched
## down at a set angle, and never rotates. It's a child of the player, so it
## follows them; only the angle and distance live here.
##
## The defaults are HGSS's field camera (the same as Platinum's, per the pret
## decompilations): 59.05 degrees down, a narrow 16.2 degree vertical field
## of view, and 41.7 tiles away, which shows about 12 tiles top to bottom,
## the DS screen's 192 px. Being far away with a narrow lens is what makes
## it look nearly flat.

## Degrees below horizontal.
@export var pitch := GridWorld.CAMERA_PITCH_DEGREES
## Vertical field of view, in degrees.
@export var view_angle := 16.18
## Distance from the point it looks at, just above the player's feet.
@export var distance := 41.68
@export var look_height := 0.5


func _ready() -> void:
	fov = view_angle
	var angle := deg_to_rad(pitch)
	var target := Vector3(0, look_height, 0)
	transform = Transform3D(Basis(Vector3.RIGHT, -angle),
		target + Vector3(0, sin(angle), cos(angle)) * distance)
