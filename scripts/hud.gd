class_name Hud
extends CanvasLayer

## On-screen farming UI, built in code: date and gold, energy bar, hotbar,
## a message line, and the seed shop panel.

const SLOT_SIZE := 56
const TOAST_TIME := 2.5

var shop_open := false

var _date: Label
var _gold: Label
var _energy_fill: ColorRect
var _slots: Array[Panel] = []
var _icons: Array[TextureRect] = []
var _counts: Array[Label] = []
var _item_name: Label
var _toast: Label
var _toast_left := 0.0
var _shop: PanelContainer
var _shop_rows: VBoxContainer


func _ready() -> void:
	_build_status()
	_build_hotbar()
	_build_shop()
	var help := _label("Space: use   E: interact   1-0 / wheel: select   N: sleep   Shift: run", 13)
	help.anchor_top = 1.0
	help.anchor_bottom = 1.0
	help.position = Vector2(12, -26)
	help.modulate = Color(1, 1, 1, 0.75)
	add_child(help)


func _process(delta: float) -> void:
	if _toast_left > 0.0:
		_toast_left -= delta
		_toast.modulate.a = clampf(_toast_left / 0.5, 0.0, 1.0)


func refresh(farm: Farm) -> void:
	_date.text = "%s %d, Year %d%s" % [Crops.SEASON_NAMES[farm.season], farm.day, farm.year,
		"   (rain)" if farm.raining else ""]
	_gold.text = "%d g" % farm.gold
	_energy_fill.size.x = 160.0 * farm.energy / Farm.MAX_ENERGY
	_energy_fill.color = Color(0.35, 0.8, 0.3) if farm.energy > Farm.MAX_ENERGY * 0.25 else Color(0.9, 0.4, 0.2)
	var inv := farm.inventory
	for i in Inventory.SIZE:
		var slot = inv.slots[i]
		_icons[i].texture = null if slot == null else Crops.icon(icon_cell(slot.id))
		_counts[i].text = "" if slot == null or slot.count <= 1 else str(slot.count)
		var style: StyleBoxFlat = _slots[i].get_theme_stylebox("panel")
		style.border_color = Color(1, 0.85, 0.3) if i == inv.selected else Color(0.3, 0.22, 0.14)
	_item_name.text = item_name(inv.selected_id())


func toast(text: String) -> void:
	_toast.text = text
	_toast_left = TOAST_TIME
	_toast.modulate.a = 1.0


func open_shop(farm: Farm) -> void:
	for child in _shop_rows.get_children():
		child.queue_free()
	var stock := farm.shop_stock()
	for i in stock.size():
		var crop: Dictionary = Crops.ALL[stock[i]]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var icon := TextureRect.new()
		icon.texture = Crops.icon(Vector2i(Crops.COL_PACKET, crop.row))
		icon.custom_minimum_size = Vector2(32, 32)
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		row.add_child(icon)
		var label := _label("%d   %s seeds   %d g   (%d days%s)" % [i + 1, crop.name, crop.seed_price,
			Crops.total_days(stock[i]), ", regrows" if crop.regrow > 0 else ""], 18)
		row.add_child(label)
		_shop_rows.add_child(row)
	_shop.visible = true
	shop_open = true


func close_shop() -> void:
	_shop.visible = false
	shop_open = false


static func icon_cell(id: String) -> Vector2i:
	if id == "hoe":
		return Crops.ICON_HOE
	if id == "can":
		return Crops.ICON_CAN
	var crop: Dictionary = Crops.ALL[StringName(id.get_slice(":", 1))]
	return Vector2i(Crops.COL_PACKET if id.begins_with("seed:") else Crops.COL_ITEM, crop.row)


static func item_name(id: String) -> String:
	if id == "":
		return ""
	if id == "hoe":
		return "Hoe"
	if id == "can":
		return "Watering Can"
	var crop_name: String = Crops.ALL[StringName(id.get_slice(":", 1))].name
	return crop_name + " Seeds" if id.begins_with("seed:") else crop_name


# --- Layout -------------------------------------------------------------------

func _build_status() -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _box(Color(0.16, 0.11, 0.07, 0.85), Color(0.45, 0.32, 0.18)))
	panel.position = Vector2(12, 12)
	add_child(panel)
	var col := VBoxContainer.new()
	panel.add_child(col)
	_date = _label("", 20)
	_gold = _label("", 20)
	_gold.add_theme_color_override("font_color", Color(1, 0.86, 0.35))
	col.add_child(_date)
	col.add_child(_gold)
	var bar := ColorRect.new()
	bar.color = Color(0.1, 0.07, 0.05)
	bar.custom_minimum_size = Vector2(160, 12)
	col.add_child(bar)
	_energy_fill = ColorRect.new()
	_energy_fill.size = Vector2(160, 12)
	bar.add_child(_energy_fill)


func _build_hotbar() -> void:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 4)
	bar.anchor_left = 0.5
	bar.anchor_right = 0.5
	bar.anchor_top = 1.0
	bar.anchor_bottom = 1.0
	var width := Inventory.SIZE * (SLOT_SIZE + 4) - 4
	bar.position = Vector2(-width / 2.0, -SLOT_SIZE - 36)
	add_child(bar)
	for i in Inventory.SIZE:
		var slot := Panel.new()
		slot.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
		slot.add_theme_stylebox_override("panel", _box(Color(0.82, 0.68, 0.46, 0.95), Color(0.3, 0.22, 0.14), 3))
		bar.add_child(slot)
		var icon := TextureRect.new()
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.position = Vector2(6, 6)
		icon.size = Vector2(SLOT_SIZE - 12, SLOT_SIZE - 12)
		slot.add_child(icon)
		var key := _label(str((i + 1) % 10), 11)
		key.position = Vector2(5, 2)
		key.add_theme_color_override("font_color", Color(0.3, 0.22, 0.14))
		slot.add_child(key)
		var count := _label("", 14)
		count.position = Vector2(SLOT_SIZE - 26, SLOT_SIZE - 22)
		count.size = Vector2(22, 18)
		count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		count.add_theme_constant_override("outline_size", 4)
		count.add_theme_color_override("font_outline_color", Color.BLACK)
		slot.add_child(count)
		_slots.append(slot)
		_icons.append(icon)
		_counts.append(count)
	_item_name = _centered_label(-SLOT_SIZE - 62, 16)
	_toast = _centered_label(-SLOT_SIZE - 92, 18)


func _build_shop() -> void:
	_shop = PanelContainer.new()
	_shop.add_theme_stylebox_override("panel", _box(Color(0.16, 0.11, 0.07, 0.95), Color(0.75, 0.55, 0.3), 3))
	_shop.anchor_left = 0.5
	_shop.anchor_top = 0.5
	_shop.anchor_right = 0.5
	_shop.anchor_bottom = 0.5
	_shop.position = Vector2(-230, -150)
	_shop.custom_minimum_size = Vector2(460, 0)
	_shop.visible = false
	add_child(_shop)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	_shop.add_child(col)
	col.add_child(_label("Seed Shop", 24))
	_shop_rows = VBoxContainer.new()
	col.add_child(_shop_rows)
	col.add_child(_label("Number keys buy one packet.   Esc / E: close", 14))


func _label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	return label


func _centered_label(y: float, font_size: int) -> Label:
	var label := _label("", font_size)
	label.anchor_left = 0.5
	label.anchor_right = 0.5
	label.anchor_top = 1.0
	label.anchor_bottom = 1.0
	label.position = Vector2(-300, y)
	label.size = Vector2(600, 24)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_constant_override("outline_size", 5)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	add_child(label)
	return label


static func _box(bg: Color, border: Color, width := 2) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(width)
	box.set_corner_radius_all(4)
	box.set_content_margin_all(10)
	return box
