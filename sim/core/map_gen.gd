class_name MapGen
extends RefCounted
## Deterministic terrain generation: fractal value noise built entirely on
## SimRng, so the same seed always produces the same map. Placeholder
## walking-skeleton generator — real worldgen (regions, rivers, ruins, WFC
## detail passes) replaces this later.

const OCTAVES := 4
const BASE_FREQUENCY := 1.0 / 48.0

const THRESHOLD_WATER := 0.34
const THRESHOLD_SAND := 0.40
const THRESHOLD_GRASS := 0.72


static func generate(world_seed: int, width: int, height: int) -> PackedByteArray:
	var tiles := PackedByteArray()
	var _err: int = tiles.resize(width * height)
	var terrain_key := SimRng.key([world_seed, "terrain"])
	for y: int in height:
		var row := y * width
		for x: int in width:
			var e := _fbm(terrain_key, float(x), float(y))
			tiles[row + x] = _tile_for(e)
	return tiles


static func _tile_for(elevation: float) -> int:
	if elevation < THRESHOLD_WATER:
		return SimWorld.TILE_WATER
	if elevation < THRESHOLD_SAND:
		return SimWorld.TILE_SAND
	if elevation < THRESHOLD_GRASS:
		return SimWorld.TILE_GRASS
	return SimWorld.TILE_ROCK


static func _fbm(terrain_key: int, x: float, y: float) -> float:
	var total := 0.0
	var amplitude := 1.0
	var frequency := BASE_FREQUENCY
	var norm := 0.0
	for octave: int in OCTAVES:
		total += amplitude * _value_noise(terrain_key, octave, x * frequency, y * frequency)
		norm += amplitude
		amplitude *= 0.5
		frequency *= 2.0
	return total / norm


static func _value_noise(terrain_key: int, octave: int, x: float, y: float) -> float:
	var x0 := floori(x)
	var y0 := floori(y)
	var tx := x - float(x0)
	var ty := y - float(y0)
	tx = tx * tx * (3.0 - 2.0 * tx)
	ty = ty * ty * (3.0 - 2.0 * ty)
	var v00 := _lattice(terrain_key, octave, x0, y0)
	var v10 := _lattice(terrain_key, octave, x0 + 1, y0)
	var v01 := _lattice(terrain_key, octave, x0, y0 + 1)
	var v11 := _lattice(terrain_key, octave, x0 + 1, y0 + 1)
	return lerpf(lerpf(v00, v10, tx), lerpf(v01, v11, tx), ty)


static func _lattice(terrain_key: int, octave: int, cx: int, cy: int) -> float:
	var k := SimRng.combine(SimRng.combine(SimRng.combine(terrain_key, octave), cx), cy)
	return SimRng.randf(k)
