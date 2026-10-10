class_name Appearance
extends RefCounted

## What the player looks like: a style and a colour for each paper-doll
## slot, and the sprite sheet built from them.
##
## Layer art comes from tools/make_character.py: every layer shares one
## layout (32x32 frames, 7 columns: default, then up / contact / passing for
## each leg; 5 rows facing S, SE, E, NE, N) and marks recolourable pixels as
## (r, 0, 255) shades. build_texture() recolours each chosen layer, stacks
## them in slot order, and outlines the result, once per change rather than
## every frame.

const FRAME := 32
const COLS := 7
## Walk frames per grid step (default, up, contact, passing).
const STEP_FRAMES := 4
const ROWS := 5
## Outlines take a dark shade of the colour they border, DS style, but never
## lighter than this.
const OUTLINE := Color8(32, 28, 36)
const OUTLINE_DARKEN := 0.62

const CLOTH := [
	Color8(200, 56, 56), Color8(224, 128, 48), Color8(232, 200, 72), Color8(80, 150, 70),
	Color8(48, 150, 150), Color8(64, 110, 200), Color8(48, 60, 110), Color8(130, 80, 170),
	Color8(232, 232, 228), Color8(130, 130, 136), Color8(44, 44, 52), Color8(120, 82, 52),
]

## Draw order, back to front. styles: layer file names, "" for none.
const SLOTS := [
	{ key = "skin", label = "Skin", styles = ["body"], colors = [
		Color8(250, 214, 180), Color8(236, 188, 150), Color8(198, 140, 100),
		Color8(150, 98, 66), Color8(104, 68, 46)] },
	{ key = "eyes", label = "Eyes", styles = ["eyes"], colors = [
		Color8(110, 70, 40), Color8(60, 100, 170), Color8(60, 130, 80), Color8(110, 110, 120)] },
	{ key = "shoes", label = "Shoes", styles = ["shoes"], colors = CLOTH },
	{ key = "bottom", label = "Bottoms", styles = ["bottom_pants", "bottom_shorts"], colors = CLOTH },
	{ key = "top", label = "Top", styles = ["top_tee", "top_long", "top_jacket"], colors = CLOTH },
	{ key = "hair", label = "Hair", styles = ["hair_short", "hair_long", "hair_spiky"], colors = [
		Color8(54, 40, 34), Color8(110, 70, 40), Color8(230, 190, 100), Color8(190, 80, 40),
		Color8(30, 30, 36), Color8(230, 230, 236), Color8(70, 100, 190), Color8(230, 130, 170)] },
	{ key = "hat", label = "Hat", styles = ["", "hat_cap", "hat_beanie"], colors = CLOTH },
]

## Facing -> [sheet row, mirrored].
const FACING_ROWS := {
	Vector2i(0, 1): [0, false], Vector2i(1, 1): [1, false], Vector2i(1, 0): [2, false],
	Vector2i(1, -1): [3, false], Vector2i(0, -1): [4, false],
	Vector2i(-1, 1): [1, true], Vector2i(-1, 0): [2, true], Vector2i(-1, -1): [3, true],
}

static var _layer_cache := {}

## Slot key -> { style, color } as indices into SLOTS.
var choices := {
	skin = { style = 0, color = 1 },
	eyes = { style = 0, color = 0 },
	shoes = { style = 0, color = 11 },
	bottom = { style = 0, color = 11 },
	top = { style = 0, color = 4 },
	hair = { style = 0, color = 1 },
	hat = { style = 0, color = 3 },
}


static func slot(key: String) -> Dictionary:
	for s in SLOTS:
		if s.key == key:
			return s
	return {}


## Moves a slot's style or colour ("style" / "color") by step, wrapping.
func cycle(key: String, field: String, step: int) -> void:
	var options: Array = slot(key)[field + "s"]
	choices[key][field] = posmod(choices[key][field] + step, options.size())


func style_name(key: String) -> String:
	var style: String = slot(key).styles[choices[key].style]
	return "None" if style == "" else style.get_slice("_", 1).capitalize() if "_" in style else style.capitalize()


func build_texture() -> ImageTexture:
	var out := Image.create(FRAME * COLS, FRAME * ROWS, false, Image.FORMAT_RGBA8)
	for s in SLOTS:
		var style: String = s.styles[choices[s.key].style]
		if style == "":
			continue
		_stamp(out, _layer(style), _ramp(s.colors[choices[s.key].color]))
	_outline(out)
	return ImageTexture.create_from_image(out)


static func _layer(name: String) -> Image:
	if not _layer_cache.has(name):
		var img: Image = load("res://assets/character/%s.png" % name).get_image()
		if img.is_compressed():
			img.decompress()
		img.convert(Image.FORMAT_RGBA8)
		_layer_cache[name] = img
	return _layer_cache[name]


## Four shades, darkest first, from a base colour.
static func _ramp(base: Color) -> Array[Color]:
	return [base.darkened(0.55), base.darkened(0.3), base, base.lightened(0.35)]


static func _stamp(out: Image, layer: Image, ramp: Array[Color]) -> void:
	for y in layer.get_height():
		for x in layer.get_width():
			var c := layer.get_pixel(x, y)
			if c.a < 0.5:
				continue
			if c.g8 == 0 and c.b8 == 255:
				c = ramp[clampi(roundi((c.r8 - 40) / 60.0), 0, 3)]
			out.set_pixel(x, y, c)


## Walk column for a point in a step: the default frame, then up, contact
## and passing for whichever leg is stepping.
static func walk_column(step_progress: float, left_foot: bool) -> int:
	var stage := clampi(int(step_progress * STEP_FRAMES), 0, STEP_FRAMES - 1)
	return 0 if stage == 0 else stage + (0 if left_foot else 3)


## Outline around everything, kept inside each frame, coloured a dark shade
## of the pixel it borders.
static func _outline(img: Image) -> void:
	var src := img.duplicate() as Image
	for y in img.get_height():
		for x in img.get_width():
			if src.get_pixel(x, y).a > 0.5:
				continue
			var fx := x % FRAME
			var fy := y % FRAME
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if fx + d.x < 0 or fx + d.x >= FRAME or fy + d.y < 0 or fy + d.y >= FRAME:
					continue
				var inside := src.get_pixel(x + d.x, y + d.y)
				if inside.a > 0.5:
					var edge := inside.darkened(OUTLINE_DARKEN)
					img.set_pixel(x, y, edge if edge.get_luminance() > OUTLINE.get_luminance() else OUTLINE)
					break
