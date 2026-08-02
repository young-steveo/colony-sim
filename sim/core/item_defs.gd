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


## Strict load: dev crashes on any problem, release logs every problem
## and refuses the file (returns null). See ContentJson.
static func load_defs(path: String = PATH) -> ItemDefs:
	var errors: Array[String] = []
	var defs := parse(path, errors)
	return defs if ContentJson.ok(errors) else null


## Validating core: collects problems instead of crashing. Side-effect
## free, so tests can feed it garbage and inspect the error list.
static func parse(path: String, errors: Array[String]) -> ItemDefs:
	var data: Variant = ContentJson.parse_file(path, errors)
	if data == null:
		return null
	var defs := ItemDefs.new()
	var items: Array = (data as Dictionary).get("items", [])
	if items.is_empty():
		errors.push_back("%s: defines no items" % path)
		return defs
	for n: int in items.size():
		if not items[n] is Dictionary:
			errors.push_back("%s: items[%d] is not an object" % [path, n])
			continue
		var entry: Dictionary = items[n]
		var ctx := "%s: item '%s'" % [path, entry.get("id", "#%d" % n)]
		var id := ContentJson.text(entry, "id", "", errors, ctx)
		if id.is_empty():
			errors.push_back("%s: missing id" % ctx)
		var stack := int(ContentJson.num(entry, "stack", 1.0, errors, ctx))
		if stack < 1:
			errors.push_back("%s: stack must be >= 1, got %d" % [ctx, stack])
		var _e1: bool = defs.ids.push_back(id)
		var _e2: bool = defs.stack_sizes.push_back(maxi(stack, 1))
		var _e3: bool = defs.colors.push_back(ContentJson.color(entry, "color", "#ffffff", errors, ctx))
	if defs.ids.size() > 0 and defs.ids[0] != "wood":
		errors.push_back("%s: entry order must match Items.* indices (first must be 'wood')" % path)
	return defs


func count() -> int:
	return ids.size()


func index_of(id: String) -> int:
	for i: int in ids.size():
		if ids[i] == id:
			return i
	return -1
