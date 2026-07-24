class_name SimWorld
extends RefCounted
## World state: the tile grid and the seed everything derives from.
## Positions throughout the sim are in tile-space floats; the renderer owns
## the pixels-per-tile conversion.

const TILE_WATER := 0
const TILE_SAND := 1
const TILE_GRASS := 2
const TILE_ROCK := 3

var world_seed: int
var width: int
var height: int
var tiles: PackedByteArray


func _init(seed_value: int, map_width: int, map_height: int) -> void:
	world_seed = seed_value
	width = map_width
	height = map_height
	tiles = MapGen.generate(world_seed, width, height)


func tile_at(x: int, y: int) -> int:
	return tiles[y * width + x]


func is_walkable(x: int, y: int) -> bool:
	# The outermost ring is impassable by rule: it keeps every system
	# (spawns, sites, flow fields) consistent and lets pathfinding skip
	# bounds checks via border sentinels.
	if x < 1 or y < 1 or x >= width - 1 or y >= height - 1:
		return false
	var t := tiles[y * width + x]
	return t == TILE_SAND or t == TILE_GRASS
