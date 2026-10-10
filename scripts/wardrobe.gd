class_name Wardrobe
extends CanvasLayer

## Character customization: pick a style and colour for each appearance
## slot, with a preview that turns through every facing.
## Keyboard driven: up/down choose a row, left/right change it, Enter or
## Esc (or the wardrobe key) closes.

signal changed
signal closed

const PREVIEW_SCALE := 6
const TURN_TIME := 0.5
## Preview facings, turning clockwise from south.
const TURN := [Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(-1, -1),
	Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0), Vector2i(1, 1)]

var appearance: Appearance
var texture: Texture2D

var _rows: Array = []  # [slot key, "style" | "color"]
var _labels: Array[Label] = []
var _swatches: Array[ColorRect] = []
var _selected := 0
var _preview: TextureRect
var _atlas := AtlasTexture.new()
var _turn := 0
var _turn_left := TURN_TIME


func _ready() -> void:
	for s in Appearance.SLOTS:
		if s.styles.size() > 1:
			_rows.append([s.key, "style"])
		if s.colors.size() > 1:
			_rows.append([s.key, "color"])
	_build()
	visible = false


func open(look: Appearance, sheet: Texture2D) -> void:
	appearance = look
	set_texture(sheet)
	_refresh()
	visible = true


func set_texture(sheet: Texture2D) -> void:
	texture = sheet
	_atlas.atlas = sheet
	_show_facing()


func _process(delta: float) -> void:
	if not visible:
		return
	_turn_left -= delta
	if _turn_left <= 0.0:
		_turn_left = TURN_TIME
		_turn = (_turn + 1) % TURN.size()
		_show_facing()


func handle(event: InputEvent) -> void:
	if event.is_action_pressed("ui_up"):
		_selected = posmod(_selected - 1, _rows.size())
	elif event.is_action_pressed("ui_down"):
		_selected = posmod(_selected + 1, _rows.size())
	elif event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right"):
		var row: Array = _rows[_selected]
		appearance.cycle(row[0], row[1], 1 if event.is_action_pressed("ui_right") else -1)
		changed.emit()
	elif event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_cancel") \
			or event.is_action_pressed("wardrobe"):
		visible = false
		closed.emit()
		return
	else:
		return
	_refresh()


func _refresh() -> void:
	for i in _rows.size():
		var key: String = _rows[i][0]
		var field: String = _rows[i][1]
		var slot := Appearance.slot(key)
		var value := appearance.style_name(key) if field == "style" else ""
		var text := "%s %s" % [slot.label, "style" if field == "style" else "colour"]
		_labels[i].text = "%-16s <  %s  >" % [text, value] if field == "style" else "%-16s <        >" % text
		_labels[i].add_theme_color_override("font_color",
			Color(1, 0.85, 0.3) if i == _selected else Color(0.95, 0.92, 0.85))
		_swatches[i].visible = field == "color"
		_swatches[i].color = slot.colors[appearance.choices[key].color]


func _show_facing() -> void:
	var row: Array = Appearance.FACING_ROWS[TURN[_turn]]
	_atlas.region = Rect2(0, row[0] * Appearance.FRAME, Appearance.FRAME, Appearance.FRAME)
	if _preview:
		_preview.flip_h = row[1]


func _build() -> void:
	var panel := PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.16, 0.11, 0.07, 0.95)
	box.border_color = Color(0.75, 0.55, 0.3)
	box.set_border_width_all(3)
	box.set_corner_radius_all(4)
	box.set_content_margin_all(16)
	panel.add_theme_stylebox_override("panel", box)
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.position = Vector2(-330, -230)
	add_child(panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	panel.add_child(col)
	col.add_child(_label("Wardrobe", 26))
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 24)
	col.add_child(body)

	var frame := Panel.new()
	frame.custom_minimum_size = Vector2.ONE * Appearance.FRAME * PREVIEW_SCALE
	var frame_box := StyleBoxFlat.new()
	frame_box.bg_color = Color(0.46, 0.59, 0.29)
	frame_box.set_corner_radius_all(4)
	frame.add_theme_stylebox_override("panel", frame_box)
	body.add_child(frame)
	_preview = TextureRect.new()
	_preview.texture = _atlas
	_preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview.size = frame.custom_minimum_size
	frame.add_child(_preview)

	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 4)
	body.add_child(rows)
	for i in _rows.size():
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 0)
		var label := _label("", 17)
		label.custom_minimum_size.x = 300
		line.add_child(label)
		var swatch := ColorRect.new()
		swatch.custom_minimum_size = Vector2(44, 18)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		line.add_child(swatch)
		rows.add_child(line)
		_labels.append(label)
		_swatches.append(swatch)
	col.add_child(_label("Up/Down: choose    Left/Right: change    Enter: done", 14))


func _label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	return label
