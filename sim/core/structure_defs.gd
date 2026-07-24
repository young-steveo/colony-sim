class_name StructureDefs
extends RefCounted
## Structure definitions loaded from plain JSON
## (content/structures/structures.json) so modders author on the same rails
## we do. First pass: wall materials only (id + blob sheet path). Gameplay
## properties (flammability, work cost, build cost) join here as those
## systems land.

const PATH := "res://content/structures/structures.json"

var wall_material_ids := PackedStringArray()
var wall_material_sheets := PackedStringArray()


static func load_defs(path: String = PATH) -> StructureDefs:
	var defs := StructureDefs.new()
	var text := FileAccess.get_file_as_string(path)
	assert(text != "", "structure defs missing: " + path)
	var data: Dictionary = JSON.parse_string(text)
	var mats: Array = data.get("wall_materials", [])
	assert(mats.size() > 0, "structures.json defines no wall materials")
	for m: Dictionary in mats:
		var _e1: bool = defs.wall_material_ids.push_back(m["id"])
		var _e2: bool = defs.wall_material_sheets.push_back(m["sheet"])
	return defs


func wall_material_count() -> int:
	return wall_material_ids.size()
