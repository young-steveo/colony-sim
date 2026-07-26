class_name ItemDefs
extends RefCounted
## Item definitions from plain JSON (content/items/items.json) — modders
## author on the same rails we do. Stack size is per-item data (decided
## with the material cycle): small stacks keep labor visible — a big
## lumber operation should LOOK big. `color` is the placeholder-render
## tint until real item sprites land.

const PATH := "res://content/items/items.json"

var ids := PackedStringArray()
var stack_sizes := PackedInt32Array()
var colors := PackedColorArray()


static func load_defs(path: String = PATH) -> ItemDefs:
	var defs := ItemDefs.new()
	var text := FileAccess.get_file_as_string(path)
	assert(text != "", "item defs missing: " + path)
	var data: Dictionary = JSON.parse_string(text)
	var items: Array = data.get("items", [])
	assert(items.size() > 0, "items.json defines no items")
	assert(str(items[0]["id"]) == "wood", "items.json order must match Items.* indices")
	for entry: Dictionary in items:
		var stack_f: float = entry.get("stack", 1.0)
		assert(int(stack_f) >= 1, "items.json: '%s' has stack < 1" % entry["id"])
		var _e1: bool = defs.ids.push_back(entry["id"])
		var _e2: bool = defs.stack_sizes.push_back(int(stack_f))
		var _e3: bool = defs.colors.push_back(Color(str(entry.get("color", "#ffffff"))))
	return defs


func count() -> int:
	return ids.size()


func index_of(id: String) -> int:
	for i: int in ids.size():
		if ids[i] == id:
			return i
	return -1
