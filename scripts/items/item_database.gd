extends Node
## Loads every ItemData resource under resources/items/ once at startup
## (autoload "ItemDatabase"). Inventory and AI actions look up item stats
## through here by item_id instead of holding direct resource references,
## so adding a new item never requires touching this script.

const ITEMS_DIR := "res://resources/items/"

var _items: Dictionary = {} ## StringName -> ItemData

func _ready() -> void:
	_load_all()

func get_item(item_id: StringName) -> ItemData:
	return _items.get(item_id)

func has_item(item_id: StringName) -> bool:
	return _items.has(item_id)

func all_item_ids() -> Array:
	return _items.keys()

func item_ids_in_category(category: ItemData.Category) -> Array:
	var result: Array = []
	for id in _items:
		if _items[id].category == category:
			result.append(id)
	return result

func _load_all() -> void:
	var dir := DirAccess.open(ITEMS_DIR)
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".tres"):
			var res: Resource = load(ITEMS_DIR + file_name)
			if res is ItemData and res.item_id != &"":
				_items[res.item_id] = res
		file_name = dir.get_next()
	dir.list_dir_end()
