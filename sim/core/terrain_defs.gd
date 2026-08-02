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
var blend := PackedInt32Array()  # higher blend scallops OVER lower at seams
# Color shown when this material appears through ANOTHER material's
# transition notches (defaults to the material color). Water overrides
# with a shallows tone: ground at a margin sits in shallow water, and
# deep teal under a mud spit reads as "floating".
var reveal_colors := PackedColorArray()
var surface_ids := PackedStringArray()  # index 0 = SURF_NONE ("bare")
var surface_colors := PackedColorArray()
var surface_sheets := PackedStringArray()


## Strict load: dev crashes on any problem, release logs every problem
## and refuses the file (returns null). See ContentJson.
static func load_defs(path: String = PATH) -> TerrainDefs:
	var errors: Array[String] = []
	var defs := parse(path, errors)
	return defs if ContentJson.ok(errors) else null


## Validating core: collects problems instead of crashing. Side-effect
## free, so tests can feed it garbage and inspect the error list.
static func parse(path: String, errors: Array[String]) -> TerrainDefs:
	var data: Variant = ContentJson.parse_file(path, errors)
	if data == null:
		return null
	var defs := TerrainDefs.new()
	var mats: Array = (data as Dictionary).get("materials", [])
	if mats.is_empty():
		errors.push_back("%s: defines no materials" % path)
		return defs
	var blends_seen := {}
	for n: int in mats.size():
		if not mats[n] is Dictionary:
			errors.push_back("%s: materials[%d] is not an object" % [path, n])
			continue
		var m: Dictionary = mats[n]
		var ctx := "%s: material '%s'" % [path, m.get("id", "#%d" % n)]
		var mid := ContentJson.text(m, "id", "", errors, ctx)
		if mid.is_empty():
			errors.push_back("%s: missing id" % ctx)
		var mcolor := ContentJson.color(m, "color", "#ff00ff", errors, ctx)
		var blend_v := int(ContentJson.num(m, "blend", float(defs.ids.size()), errors, ctx))
		# Seam scallops draw higher-blend OVER lower; equal blends would
		# make that order undefined (and silently seed-dependent).
		if blends_seen.has(blend_v):
			errors.push_back(
				"%s: blend %d already used by '%s' — blends must be unique" % [
					ctx, blend_v, blends_seen[blend_v],
				]
			)
		blends_seen[blend_v] = mid
		var sheet := ContentJson.text(m, "sheet", "", errors, ctx)
		if not sheet.is_empty() and not FileAccess.file_exists(sheet):
			errors.push_back("%s: sheet not found: %s" % [ctx, sheet])
		var _e1: bool = defs.ids.push_back(mid)
		var _e2: bool = defs.colors.push_back(mcolor)
		var _e3: bool = defs.walkable.push_back(1 if bool(m.get("walkable", false)) else 0)
		var _e4: bool = defs.sheets.push_back(sheet)
		var _e4b: bool = defs.blend.push_back(blend_v)
		var _e4c: bool = defs.reveal_colors.push_back(
			ContentJson.color(m, "reveal", str(m.get("color", "#ff00ff")), errors, ctx)
		)
	if defs.ids.size() <= SimWorld.TILE_DIRT_ROCKY:
		errors.push_back(
			"%s: must define all engine substrates (water through dirt_rocky)" % path
		)
	var _s1: bool = defs.surface_ids.push_back("bare")
	var _s2: bool = defs.surface_colors.push_back(Color.MAGENTA)  # never drawn
	var _s3: bool = defs.surface_sheets.push_back("")
	var surfaces: Array = (data as Dictionary).get("surfaces", [])
	for n: int in surfaces.size():
		if not surfaces[n] is Dictionary:
			errors.push_back("%s: surfaces[%d] is not an object" % [path, n])
			continue
		var s: Dictionary = surfaces[n]
		var sctx := "%s: surface '%s'" % [path, s.get("id", "#%d" % n)]
		var _e5: bool = defs.surface_ids.push_back(ContentJson.text(s, "id", "", errors, sctx))
		var _e6: bool = defs.surface_colors.push_back(ContentJson.color(s, "color", "#ff00ff", errors, sctx))
		var _e7: bool = defs.surface_sheets.push_back(ContentJson.text(s, "sheet", "", errors, sctx))
	if defs.surface_ids.size() <= SimWorld.SURF_GRASS:
		errors.push_back("%s: must define the grass surface" % path)
	return defs


func count() -> int:
	return ids.size()
