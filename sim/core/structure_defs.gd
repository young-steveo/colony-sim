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


## Strict load: dev crashes on any problem, release logs every problem
## and refuses the file (returns null). See ContentJson.
static func load_defs(path: String = PATH) -> StructureDefs:
	var errors: Array[String] = []
	var defs := parse(path, errors)
	return defs if ContentJson.ok(errors) else null


## Validating core: collects problems instead of crashing. Side-effect
## free, so tests can feed it garbage and inspect the error list.
static func parse(path: String, errors: Array[String]) -> StructureDefs:
	var data: Variant = ContentJson.parse_file(path, errors)
	if data == null:
		return null
	var defs := StructureDefs.new()
	var structures: Array = (data as Dictionary).get("structures", [])
	if structures.size() != _ORDER.size():
		errors.push_back(
			"%s: expected %d structures (%s), got %d" % [
				path, _ORDER.size(), ", ".join(_ORDER), structures.size(),
			]
		)
		return defs
	var _z1: bool = defs.work_seconds.push_back(0.0)
	var _z2: bool = defs.wood_costs.push_back(0)
	for i: int in structures.size():
		if not structures[i] is Dictionary:
			errors.push_back("%s: structures[%d] is not an object" % [path, i])
			continue
		var s: Dictionary = structures[i]
		var ctx := "%s: structure '%s'" % [path, s.get("id", "#%d" % i)]
		if ContentJson.text(s, "id", "", errors, ctx) != _ORDER[i]:
			errors.push_back("%s: entry order must be %s" % [path, ", ".join(_ORDER)])
		var work := ContentJson.num(s, "work", 1.0, errors, ctx)
		if work <= 0.0:
			errors.push_back("%s: work must be > 0, got %s" % [ctx, work])
		var cost: Variant = s.get("cost", {})
		var wood := 0
		if not cost is Dictionary:
			errors.push_back("%s: cost must be an object" % ctx)
		else:
			# The engine pays only wood until a second resource exists;
			# an unknown cost key would otherwise build FREE, silently.
			for key: String in (cost as Dictionary):
				if key != "wood":
					errors.push_back("%s: unknown cost '%s' (only wood is supported in v1)" % [ctx, key])
			wood = int(ContentJson.num(cost, "wood", 0.0, errors, ctx))
			if wood < 0:
				errors.push_back("%s: cost.wood must be >= 0, got %d" % [ctx, wood])
		var _e1: bool = defs.work_seconds.push_back(work)
		var _e2: bool = defs.wood_costs.push_back(maxi(wood, 0))
	var mats: Array = (data as Dictionary).get("wall_materials", [])
	if mats.is_empty():
		errors.push_back("%s: defines no wall materials" % path)
	for n: int in mats.size():
		if not mats[n] is Dictionary:
			errors.push_back("%s: wall_materials[%d] is not an object" % [path, n])
			continue
		var m: Dictionary = mats[n]
		var mctx := "%s: wall material '%s'" % [path, m.get("id", "#%d" % n)]
		var mid := ContentJson.text(m, "id", "", errors, mctx)
		if mid.is_empty():
			errors.push_back("%s: missing id" % mctx)
		var sheet := ContentJson.text(m, "sheet", "", errors, mctx)
		if sheet.is_empty():
			errors.push_back("%s: missing sheet" % mctx)
		elif not FileAccess.file_exists(sheet):
			errors.push_back("%s: sheet not found: %s" % [mctx, sheet])
		var _e3: bool = defs.wall_material_ids.push_back(mid)
		var _e4: bool = defs.wall_material_sheets.push_back(sheet)
	return defs


func wall_material_count() -> int:
	return wall_material_ids.size()
