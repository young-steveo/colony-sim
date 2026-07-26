class_name StructureDefs
extends RefCounted
## Structure definitions loaded from plain JSON
## (content/structures/structures.json) so modders author on the same rails
## we do. Wall materials (id + blob sheet path), and per-structure gameplay
## data: work seconds and material cost (the data-first audit came due with
## the hauling era). Costs are a dict in the JSON ({"wood": 2}) so future
## resources slot in; the engine reads wood only until a second resource
## exists.

const PATH := "res://content/structures/structures.json"

# structures.json entry order must match the engine's STRUCT_* indices
# (wall=1, door=2, bed=3); index 0 is STRUCT_NONE.
const _ORDER: Array[String] = ["wall", "door", "bed"]

var wall_material_ids := PackedStringArray()
var wall_material_sheets := PackedStringArray()
var work_seconds := PackedFloat32Array()  # by STRUCT_* type; [0] unused
var wood_costs := PackedInt32Array()  # by STRUCT_* type; [0] unused


static func load_defs(path: String = PATH) -> StructureDefs:
	var defs := StructureDefs.new()
	var text := FileAccess.get_file_as_string(path)
	assert(text != "", "structure defs missing: " + path)
	var data: Dictionary = JSON.parse_string(text)
	var structures: Array = data.get("structures", [])
	assert(structures.size() == _ORDER.size(), "structures.json structure list mismatch")
	var _z1: bool = defs.work_seconds.push_back(0.0)
	var _z2: bool = defs.wood_costs.push_back(0)
	for i: int in structures.size():
		var s: Dictionary = structures[i]
		assert(str(s["id"]) == _ORDER[i], "structures.json order must be wall, door, bed")
		var cost: Dictionary = s.get("cost", {})
		var wood_f: float = cost.get("wood", 0.0)
		var _e1: bool = defs.work_seconds.push_back(s.get("work", 1.0))
		var _e2: bool = defs.wood_costs.push_back(int(wood_f))
	var mats: Array = data.get("wall_materials", [])
	assert(mats.size() > 0, "structures.json defines no wall materials")
	for m: Dictionary in mats:
		var _e3: bool = defs.wall_material_ids.push_back(m["id"])
		var _e4: bool = defs.wall_material_sheets.push_back(m["sheet"])
	return defs


func wall_material_count() -> int:
	return wall_material_ids.size()
