class_name Inventory
extends RefCounted

## Hotbar-style inventory: a fixed row of slots, one selected.
## Items are ids like "hoe", "can", "seed:parsnip" or "crop:parsnip".

signal changed

const SIZE := 10

var slots: Array = []
var selected := 0


func _init() -> void:
	slots.resize(SIZE)


func selected_id() -> String:
	var slot = slots[selected]
	return "" if slot == null else slot.id


func select(index: int) -> void:
	selected = posmod(index, SIZE)
	changed.emit()


## Stacks onto a slot holding the same item, else takes the first free slot.
## Returns false if there's no room.
func add(id: String, count := 1) -> bool:
	for slot in slots:
		if slot != null and slot.id == id:
			slot.count += count
			changed.emit()
			return true
	for i in SIZE:
		if slots[i] == null:
			slots[i] = { id = id, count = count }
			changed.emit()
			return true
	return false


func remove(id: String, count := 1) -> bool:
	for i in SIZE:
		var slot = slots[i]
		if slot != null and slot.id == id and slot.count >= count:
			slot.count -= count
			if slot.count == 0:
				slots[i] = null
			changed.emit()
			return true
	return false


func count(id: String) -> int:
	for slot in slots:
		if slot != null and slot.id == id:
			return slot.count
	return 0
