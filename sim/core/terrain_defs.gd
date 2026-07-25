class_name TerrainDefs
extends RefCounted
## Terrain definitions from plain JSON (content/terrain/terrain.json) —
## modders author on the same rails we do (mirrors StructureDefs). Two
## lists per the tile stack (GDD Environment): `materials` are substrates
## (array order IS the sim's tile byte — SimWorld.TILE_*), `surfaces` grow
## or are laid on a substrate (order is the surface byte, offset by one:
## byte 0 is always "bare"). `sheet` is optional — entries without one
## render as flat placeholder color; with one, the shared 47-blob overlay
## draws on top.

const PATH := "res://content/terrain/terrain.json"

var ids := PackedStringArray()
var colors := PackedColorArray()
var walkable := PackedByteArray()
var sheets := PackedStringArray()  # "" = no art yet
var surface_ids := PackedStringArray()  # index 0 = SURF_NONE ("bare")
var surface_colors := PackedColorArray()
var surface_sheets := PackedStringArray()


static func load_defs(path: String = PATH) -> TerrainDefs:
	var defs := TerrainDefs.new()
	var text := FileAccess.get_file_as_string(path)
	assert(text != "", "terrain defs missing: " + path)
	var data: Dictionary = JSON.parse_string(text)
	var mats: Array = data.get("materials", [])
	assert(mats.size() > 0, "terrain.json defines no materials")
	for m: Dictionary in mats:
		var _e1: bool = defs.ids.push_back(m["id"])
		var _e2: bool = defs.colors.push_back(Color(str(m["color"])))
		var _e3: bool = defs.walkable.push_back(1 if bool(m.get("walkable", false)) else 0)
		var _e4: bool = defs.sheets.push_back(str(m.get("sheet", "")))
	assert(
		defs.ids.size() > SimWorld.TILE_DIRT_ROCKY,
		"terrain.json must define all engine substrates (water through dirt_rocky)"
	)
	var _s1: bool = defs.surface_ids.push_back("bare")
	var _s2: bool = defs.surface_colors.push_back(Color.MAGENTA)  # never drawn
	var _s3: bool = defs.surface_sheets.push_back("")
	for s: Dictionary in data.get("surfaces", []) as Array:
		var _e5: bool = defs.surface_ids.push_back(s["id"])
		var _e6: bool = defs.surface_colors.push_back(Color(str(s["color"])))
		var _e7: bool = defs.surface_sheets.push_back(str(s.get("sheet", "")))
	assert(
		defs.surface_ids.size() > SimWorld.SURF_GRASS,
		"terrain.json must define the grass surface"
	)
	return defs


func count() -> int:
	return ids.size()
