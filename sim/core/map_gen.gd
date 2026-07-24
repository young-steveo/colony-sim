class_name MapGen
extends RefCounted
## Deterministic terrain generation: fractal value noise built entirely on
## SimRng, so the same seed always produces the same map. Placeholder
## walking-skeleton generator — real worldgen (regions, rivers, ruins, WFC
## detail passes) replaces this later.
##
## Each octave's lattice values are precomputed once (thousands of hashes)
## instead of hashed per tile corner (millions) — ~20x faster, still a pure
## function of the seed.

const OCTAVES := 4
const BASE_FREQUENCY := 1.0 / 48.0

const THRESHOLD_WATER := 0.34
const THRESHOLD_SAND := 0.40
const THRESHOLD_GRASS := 0.72


static func generate(world_seed: int, width: int, height: int) -> PackedByteArray:
	var cell_count := width * height
	var terrain_key := SimRng.key([world_seed, "terrain"])

	var elevation := PackedFloat32Array()
	var _err: int = elevation.resize(cell_count)
	elevation.fill(0.0)
	var norm := 0.0
	var amplitude := 1.0
	var frequency := BASE_FREQUENCY

	for octave: int in OCTAVES:
		var lattice_w := floori((width - 1) * frequency) + 2
		var lattice_h := floori((height - 1) * frequency) + 2
		var lattice := PackedFloat32Array()
		var _err2: int = lattice.resize(lattice_w * lattice_h)
		var octave_key := SimRng.combine(terrain_key, octave)
		for cy: int in lattice_h:
			var row_key := SimRng.combine(octave_key, cy)
			var row := cy * lattice_w
			for cx: int in lattice_w:
				lattice[row + cx] = SimRng.randf(SimRng.combine(row_key, cx))

		for y: int in height:
			var fy := y * frequency
			var y0 := floori(fy)
			var ty := fy - y0
			ty = ty * ty * (3.0 - 2.0 * ty)
			var row0 := y0 * lattice_w
			var row1 := row0 + lattice_w
			var out_row := y * width
			for x: int in width:
				var fx := x * frequency
				var x0 := floori(fx)
				var tx := fx - x0
				tx = tx * tx * (3.0 - 2.0 * tx)
				var top := lerpf(lattice[row0 + x0], lattice[row0 + x0 + 1], tx)
				var bottom := lerpf(lattice[row1 + x0], lattice[row1 + x0 + 1], tx)
				elevation[out_row + x] += amplitude * lerpf(top, bottom, ty)

		norm += amplitude
		amplitude *= 0.5
		frequency *= 2.0

	var tiles := PackedByteArray()
	var _err3: int = tiles.resize(cell_count)
	var inv_norm := 1.0 / norm
	for c: int in cell_count:
		tiles[c] = _tile_for(elevation[c] * inv_norm)
	return tiles


static func _tile_for(elevation: float) -> int:
	if elevation < THRESHOLD_WATER:
		return SimWorld.TILE_WATER
	if elevation < THRESHOLD_SAND:
		return SimWorld.TILE_SAND
	if elevation < THRESHOLD_GRASS:
		return SimWorld.TILE_GRASS
	return SimWorld.TILE_ROCK
