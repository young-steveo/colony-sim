class_name SimWorld
extends RefCounted
## World state: the tile grid and the seed everything derives from.
## Positions throughout the sim are in tile-space floats; the renderer owns
## the pixels-per-tile conversion.

# Engine-side names for terrain indices; the materials themselves (colors,
# walkability, art) live in content/terrain/terrain.json, in this exact
# order (TerrainDefs asserts). Substrates are the ground itself; surfaces
# grow or are laid ON a substrate (tile stack — GDD Environment).
const TILE_WATER := 0
const TILE_DIRT := 1
const TILE_STONE := 2
const SURF_NONE := 0
const SURF_GRASS := 1

const STRUCT_NONE := 0
const STRUCT_WALL := 1
const STRUCT_DOOR := 2
const STRUCT_BED := 3

var world_seed: int
var width: int
var height: int
var terrain_defs: TerrainDefs
var _tile_walkable: PackedByteArray  # LUT by tile byte, from terrain defs
var tiles: PackedByteArray  # substrate per cell
var surfaces: PackedByteArray  # SURF_* per cell; 0 = bare substrate
# Built structures, one per cell (STRUCT_*). Walls block movement; doors
# and beds don't. A second grid layer, deliberately separate from terrain.
var structures: PackedByteArray
var structure_materials: PackedByteArray  # StructureDefs material index
var structures_version := 0  # bumps on every set_structure


func _init(seed_value: int, map_width: int, map_height: int, defs: TerrainDefs = null) -> void:
	world_seed = seed_value
	width = map_width
	height = map_height
	terrain_defs = defs if defs != null else TerrainDefs.load_defs()
	_tile_walkable = terrain_defs.walkable
	var gen := MapGen.generate(world_seed, width, height)
	tiles = gen["substrate"]
	surfaces = gen["surface"]
	var _e: int = structures.resize(width * height)
	var _e2: int = structure_materials.resize(width * height)


func tile_at(x: int, y: int) -> int:
	return tiles[y * width + x]


func surface_at(x: int, y: int) -> int:
	return surfaces[y * width + x]


func structure_at_cell(cell: int) -> int:
	return structures[cell]


func set_structure(cell: int, type: int, material: int = 0) -> void:
	structures[cell] = type
	structure_materials[cell] = material
	structures_version += 1


func structure_material_at(cell: int) -> int:
	return structure_materials[cell]


## Walkability as a flat 0/1 byte grid with the border ring forced to 0 —
## the immutable input flow-field builds consume (safe to hand to a worker
## thread; the sim can keep mutating the live world meanwhile).
func walkability_snapshot() -> PackedByteArray:
	var walk := PackedByteArray()
	var _e: int = walk.resize(width * height)
	for y: int in height:
		var row := y * width
		for x: int in width:
			walk[row + x] = 1 if is_walkable(x, y) else 0
	return walk


func is_walkable(x: int, y: int) -> bool:
	# The outermost ring is impassable by rule: it keeps every system
	# (spawns, sites, flow fields) consistent and lets pathfinding skip
	# bounds checks via border sentinels.
	if x < 1 or y < 1 or x >= width - 1 or y >= height - 1:
		return false
	var cell := y * width + x
	if structures[cell] == STRUCT_WALL:
		return false
	return _tile_walkable[tiles[cell]] == 1
