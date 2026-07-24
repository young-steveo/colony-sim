class_name SimWorld
extends RefCounted
## World state: the tile grid and the seed everything derives from.
## Positions throughout the sim are in tile-space floats; the renderer owns
## the pixels-per-tile conversion.

const TILE_WATER := 0
const TILE_SAND := 1
const TILE_GRASS := 2
const TILE_ROCK := 3

const STRUCT_NONE := 0
const STRUCT_WALL := 1
const STRUCT_DOOR := 2
const STRUCT_BED := 3

var world_seed: int
var width: int
var height: int
var tiles: PackedByteArray
# Built structures, one per cell (STRUCT_*). Walls block movement; doors
# and beds don't. A second grid layer, deliberately separate from terrain.
var structures: PackedByteArray
var structures_version := 0  # bumps on every set_structure


func _init(seed_value: int, map_width: int, map_height: int) -> void:
	world_seed = seed_value
	width = map_width
	height = map_height
	tiles = MapGen.generate(world_seed, width, height)
	var _e: int = structures.resize(width * height)


func tile_at(x: int, y: int) -> int:
	return tiles[y * width + x]


func structure_at_cell(cell: int) -> int:
	return structures[cell]


func set_structure(cell: int, type: int) -> void:
	structures[cell] = type
	structures_version += 1


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
	var t := tiles[cell]
	return t == TILE_SAND or t == TILE_GRASS
